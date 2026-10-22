/* datachannel_web.cpp - the dcx_* C ABI over the BROWSER's WebRTC
 * (wasm32-emscripten, EXPERIMENTAL, 2026-10-21).
 *
 * The desktop shim (datachannel_shim.cpp) drives libdatachannel, which needs
 * sockets, threads and OpenSSL that a web page does not have. A browser has
 * WebRTC itself, so for OXT-Beyond's web IDE this file implements the SAME
 * frozen contract (dcx_abi.h: every symbol, every return code, the event
 * drain's framing and the dcx_record.h registries) over RTCPeerConnection and
 * RTCDataChannel. The .lcb is unchanged: it binds "c:datachannelxt>dcx_*" and
 * the web engine finds these functions in the table CMakeLists.txt generates
 * (datachannelxt_web_exports), as it finds SodiumXT's.
 *
 * THE THREADING CONTRACT, in a browser. WebRTC's callbacks run on the page's
 * event loop, between the engine's turns, never inside a dcx_* call. Each
 * one does exactly what the native callbacks do: append a typed event to a
 * bounded queue (here a JavaScript array) and return. dcx_poll, called from
 * script on a timer, drains it into the caller's buffer. No callback calls
 * into WebAssembly, so none can reach script or interleave with the engine.
 *
 * THE FIREWALL (suite rule 2). A JavaScript exception thrown out of an import
 * would unwind through the engine. Every entry goes through one import,
 * dcx_js(), whose body is a try/catch that turns any throw into the entry's
 * error value and a last-error message, so nothing crosses the FFI.
 *
 * HANDLES (suite rule 4). Peer and channel handles are positive integers from
 * counters that never reuse a value, so a stale handle never names a live
 * object and every call on one is the harmless no-op the contract asks for.
 *
 * What differs from libdatachannel, and why:
 *   - Negotiation is the browser's: the first channel fires
 *     negotiationneeded, which makes the offer; applying a remote offer makes
 *     the answer. Both still surface as E_LOCAL_DESCRIPTION events, and the
 *     browser's local description carries its gathered candidates, as
 *     libdatachannel's does, so the single-blob (non-trickle) signaling works.
 *   - Peer operations that are promises in a browser (applying a description
 *     or a candidate) are chained per peer and run in call order; their
 *     failures land in dcx_last_error, since the call has already returned.
 *   - A remote candidate may carry libdatachannel's "a=" prefix, which a
 *     browser refuses: it is stripped.
 *   - dcx_selected_candidate_pair answers from a snapshot of getStats() taken
 *     when the connection or a channel opens (a browser has no synchronous
 *     getter), in libdatachannel's "candidate:..." spelling.
 *   - dcx_channel_max_message is the SCTP limit the browser negotiated,
 *     capped at DCX_MAX_MESSAGE.
 *   - With no RTCPeerConnection (WebRTC disabled, or node), dcx_init and
 *     dcx_peer_new fail with DCX_ERR_NATIVE and say why.
 */

#include <emscripten.h>

#include "dcx_abi.h"
#include "dcx_record.h"

/* The one import. `op` names the entry (the table below); a..h are its int
 * and pointer arguments. `k` is the registry the JavaScript side encodes
 * events with, passed once so the numbers have ONE source (dcx_record.h).
 *
 * The body is JavaScript, and EM_JS joins it into one line: every statement
 * ends with a semicolon. */
EM_JS(int, dcx_js, (int op, int a, int b, int c, int d, int e, int f, int g, int h, const int *k), {
  var X = globalThis.__oxtDcxWeb;
  if (!X) {
    X = globalThis.__oxtDcxWeb = {
      peers: new Map(), chans: new Map(), nextPeer: 1, nextChan: 1,
      queue: [], queueBytes: 0, dropped: 0, err: "",
      maxEvents: 65536, maxBytes: 32 * 1024 * 1024, k: null
    };
  }
  if (!X.k) {
    X.k = {};
    var names = ['E_LOCAL_DESCRIPTION', 'E_LOCAL_CANDIDATE', 'E_STATE_CHANGE', 'E_GATHERING_STATE',
      'E_CHANNEL_INCOMING', 'E_CHANNEL_OPEN', 'E_CHANNEL_CLOSED', 'E_MESSAGE', 'E_CHANNEL_ERROR',
      'E_BUFFERED_LOW', 'E_QUEUE_OVERFLOW',
      'F_DC_PEER', 'F_DC_CHANNEL', 'F_DC_SDP', 'F_DC_SDP_TYPE', 'F_DC_CANDIDATE', 'F_DC_MID',
      'F_DC_STATE', 'F_DC_LABEL', 'F_DC_PROTOCOL', 'F_DC_PAYLOAD', 'F_DC_TEXT', 'F_DC_ERROR',
      'F_DC_DROPPED', 'F_DC_LOCAL_CAND', 'F_DC_REMOTE_CAND',
      'FT_INT', 'FT_UTF8', 'FT_RAW', 'MAX_MESSAGE',
      'OK', 'ERR_BAD_HANDLE', 'ERR_INVALID_ARG', 'ERR_TOO_LARGE', 'ERR_NATIVE', 'ERR_EXCEPTION'];
    for (var i = 0; i < names.length; i++) X.k[names[i]] = HEAP32[(k >> 2) + i];
  }
  var K = X.k;
  var enc = new TextEncoder();
  var dec = new TextDecoder();

  function str(p) {
    if (!p) return null;
    var end = p;
    while (HEAPU8[end] !== 0) end++;
    return dec.decode(HEAPU8.slice(p, end));
  }
  function out(s, p, cap) {
    var bytes = enc.encode(s);
    if (bytes.length === 0) return 0;
    if (bytes.length > cap) return -bytes.length;
    HEAPU8.set(bytes, p);
    return bytes.length;
  }
  function fail(code, msg) { X.err = msg; return code; }

  function intField(id, v) { return [id, K.FT_INT, enc.encode(String(v))]; }
  function strField(id, s) { return [id, K.FT_UTF8, enc.encode(s || "")]; }
  function record(fields) {
    var n = 2;
    for (var i = 0; i < fields.length; i++) n += 4 + fields[i][2].length;
    var r = new Uint8Array(n);
    r[0] = fields.length >> 8; r[1] = fields.length & 255;
    var at = 2;
    for (var i = 0; i < fields.length; i++) {
      var v = fields[i][2];
      r[at] = fields[i][0]; r[at + 1] = fields[i][1];
      r[at + 2] = v.length >> 8; r[at + 3] = v.length & 255;
      r.set(v, at + 4);
      at += 4 + v.length;
    }
    return r;
  }
  /* One drain entry, [type:u16][bodyLen:u16][kvrecord], with the native
   * shim's field order (write_event_entry) */
  function emit(type, peer, chan, extra) {
    var fields = [intField(K.F_DC_PEER, peer), intField(K.F_DC_CHANNEL, chan)].concat(extra || []);
    var body = record(fields);
    var entry = new Uint8Array(4 + body.length);
    entry[0] = type >> 8; entry[1] = type & 255;
    entry[2] = body.length >> 8; entry[3] = body.length & 255;
    entry.set(body, 4);
    if (X.queue.length >= X.maxEvents || X.queueBytes + entry.length > X.maxBytes) {
      X.dropped++;
      return;
    }
    X.queue.push({ peer: peer, chan: chan, bytes: entry });
    X.queueBytes += entry.length;
  }

  var PS = { 'new': 0, 'connecting': 1, 'connected': 2, 'disconnected': 3, 'failed': 4, 'closed': 5 };
  var ICE = { 'new': 0, 'checking': 1, 'connected': 2, 'completed': 2, 'disconnected': 3,
    'failed': 4, 'closed': 5 };
  var GS = { 'new': 0, 'gathering': 1, 'complete': 2 };

  function chain(P, label, fn) {
    P.chain = P.chain.then(fn).catch(function (err) {
      X.err = label + ': ' + (err && err.message ? err.message : String(err));
    });
  }
  function announceDescription(P, h) {
    var d = P.pc.localDescription;
    if (X.peers.get(h) !== P || !d) return;
    emit(K.E_LOCAL_DESCRIPTION, h, 0,
      [strField(K.F_DC_SDP, d.sdp), strField(K.F_DC_SDP_TYPE, d.type)]);
  }
  function candidateLine(c) {
    if (!c) return "";
    return 'candidate:' + (c.foundation || '1') + ' 1 ' + String(c.protocol || 'udp').toUpperCase() +
      ' ' + (c.priority || 0) + ' ' + (c.address || c.ip || "") + ' ' + (c.port || 0) +
      ' typ ' + (c.candidateType || 'host');
  }
  function snapshotPair(P) {
    if (!P.pc.getStats) return;
    P.pc.getStats().then(function (stats) {
      var pair = null;
      stats.forEach(function (s) {
        if (s.type === 'transport' && s.selectedCandidatePairId) pair = stats.get(s.selectedCandidatePairId);
      });
      if (!pair) {
        stats.forEach(function (s) {
          if (s.type === 'candidate-pair' && (s.selected || s.nominated) && s.state === 'succeeded') pair = s;
        });
      }
      if (pair) P.pair = [candidateLine(stats.get(pair.localCandidateId)),
        candidateLine(stats.get(pair.remoteCandidateId))];
    }).catch(function () {});
  }
  function peerState(P, h, s) {
    if (s === undefined || s === P.state) return;
    P.state = s;
    emit(K.E_STATE_CHANGE, h, 0, [intField(K.F_DC_STATE, s)]);
    if (s === 2) snapshotPair(P);
  }

  function wireChannel(dc, peerHandle, incoming) {
    var ch = X.nextChan++;
    var C = { dc: dc, peer: peerHandle, open: false, closed: false, low: false };
    X.chans.set(ch, C);
    var P = X.peers.get(peerHandle);
    if (P) P.chans.add(ch);
    dc.binaryType = 'arraybuffer';
    if (incoming) {
      emit(K.E_CHANNEL_INCOMING, peerHandle, ch,
        [strField(K.F_DC_LABEL, dc.label), strField(K.F_DC_PROTOCOL, dc.protocol)]);
    }
    function opened() {
      if (X.chans.get(ch) !== C || C.open) return;
      C.open = true;
      emit(K.E_CHANNEL_OPEN, C.peer, ch);
      var Q = X.peers.get(C.peer);
      if (Q) snapshotPair(Q);
    }
    dc.onopen = opened;
    dc.onclose = function () {
      if (X.chans.get(ch) !== C || C.closed) return;
      C.closed = true;
      emit(K.E_CHANNEL_CLOSED, C.peer, ch);
    };
    dc.onerror = function (ev) {
      if (X.chans.get(ch) !== C) return;
      var m = ev && ev.error && ev.error.message ? ev.error.message : 'data channel error';
      emit(K.E_CHANNEL_ERROR, C.peer, ch, [strField(K.F_DC_ERROR, m)]);
    };
    dc.onmessage = function (ev) {
      if (X.chans.get(ch) !== C) return;
      var text = typeof ev.data === 'string';
      var bytes = text ? enc.encode(ev.data) : new Uint8Array(ev.data);
      if (bytes.length > K.MAX_MESSAGE) {
        emit(K.E_CHANNEL_ERROR, C.peer, ch, [strField(K.F_DC_ERROR,
          'oversized inbound message dropped (' + bytes.length + ' bytes > ' + K.MAX_MESSAGE + ')')]);
        return;
      }
      emit(K.E_MESSAGE, C.peer, ch, [[text ? K.F_DC_TEXT : K.F_DC_PAYLOAD, text ? K.FT_UTF8 : K.FT_RAW, bytes]]);
    };
    dc.onbufferedamountlow = function () {
      if (X.chans.get(ch) !== C || !C.low) return;
      emit(K.E_BUFFERED_LOW, C.peer, ch);
    };
    if (dc.readyState === 'open') opened();
    return ch;
  }
  function unwireChannel(ch) {
    var C = X.chans.get(ch);
    if (!C) return;
    X.chans.delete(ch);
    var P = X.peers.get(C.peer);
    if (P) P.chans.delete(ch);
    C.dc.onopen = C.dc.onclose = C.dc.onerror = C.dc.onmessage = C.dc.onbufferedamountlow = null;
    try { C.dc.close(); } catch (err) {}
  }
  function freePeer(h) {
    var P = X.peers.get(h);
    if (!P) return;
    P.chans.forEach(function (ch) { unwireChannel(ch); });
    X.peers.delete(h);
    var pc = P.pc;
    pc.onnegotiationneeded = pc.onicecandidate = pc.onconnectionstatechange = null;
    pc.oniceconnectionstatechange = pc.onicegatheringstatechange = pc.ondatachannel = null;
    try { pc.close(); } catch (err) {}
  }
  function haveWebRTC() {
    if (typeof RTCPeerConnection === 'undefined') {
      X.err = 'this browser has no WebRTC (RTCPeerConnection is not defined)';
      return false;
    }
    return true;
  }
  function iceServers(lines) {
    var list = [];
    String(lines || "").split(String.fromCharCode(10)).forEach(function (line) {
      line = line.trim();
      if (!line) return;
      var m = /^(turns?):([^@]*)@(.*)$/.exec(line);
      if (m) {
        var colon = m[2].indexOf(':');
        list.push({ urls: m[1] + ':' + m[3],
          username: decodeURIComponent(colon < 0 ? m[2] : m[2].slice(0, colon)),
          credential: decodeURIComponent(colon < 0 ? "" : m[2].slice(colon + 1)) });
      } else {
        list.push({ urls: line });
      }
    });
    return list;
  }
  function chanOf(c) { return X.chans.get(c); }
  function peerOf(p) { return X.peers.get(p); }

  try {
    switch (op) {
    case 1: /* dcx_init */
      return haveWebRTC() ? K.OK : K.ERR_NATIVE;

    case 2: /* dcx_cleanup */
      Array.from(X.peers.keys()).forEach(freePeer);
      Array.from(X.chans.keys()).forEach(unwireChannel);
      X.queue = []; X.queueBytes = 0; X.dropped = 0;
      return K.OK;

    case 3: /* dcx_library_version(out, cap) */
      return out('browser WebRTC (RTCPeerConnection) in place of libdatachannel', a, b);

    case 4: /* dcx_last_error(out, cap) */
      return out(X.err, a, b);

    case 5: /* dcx_clear_error */
      X.err = "";
      return 0;

    case 6: { /* dcx_peer_new(iceServersLines) */
      if (!haveWebRTC()) return 0;
      var pc = new RTCPeerConnection({ iceServers: iceServers(str(a)) });
      var ph = X.nextPeer++;
      var P = { pc: pc, chans: new Set(), chain: Promise.resolve(), state: 0, gathering: 0, pair: null };
      X.peers.set(ph, P);
      pc.onnegotiationneeded = function () {
        chain(P, 'negotiation', function () {
          return pc.setLocalDescription().then(function () { announceDescription(P, ph); });
        });
      };
      pc.onicecandidate = function (ev) {
        if (X.peers.get(ph) !== P || !ev.candidate || !ev.candidate.candidate) return;
        emit(K.E_LOCAL_CANDIDATE, ph, 0, [strField(K.F_DC_CANDIDATE, ev.candidate.candidate),
          strField(K.F_DC_MID, ev.candidate.sdpMid || "")]);
      };
      pc.onconnectionstatechange = function () {
        if (X.peers.get(ph) === P) peerState(P, ph, PS[pc.connectionState]);
      };
      if (!('connectionState' in pc)) {
        pc.oniceconnectionstatechange = function () {
          if (X.peers.get(ph) === P) peerState(P, ph, ICE[pc.iceConnectionState]);
        };
      }
      pc.onicegatheringstatechange = function () {
        var s = GS[pc.iceGatheringState];
        if (X.peers.get(ph) !== P || s === undefined || s === P.gathering) return;
        P.gathering = s;
        emit(K.E_GATHERING_STATE, ph, 0, [intField(K.F_DC_STATE, s)]);
      };
      pc.ondatachannel = function (ev) {
        if (X.peers.get(ph) === P) wireChannel(ev.channel, ph, true);
      };
      return ph;
    }

    case 7: { /* dcx_peer_close(p) */
      var P = peerOf(a);
      if (!P) return fail(K.ERR_BAD_HANDLE, 'stale peer handle');
      P.pc.close();
      P.chans.forEach(function (ch) {
        var C = X.chans.get(ch);
        if (C && !C.closed) { C.closed = true; emit(K.E_CHANNEL_CLOSED, a, ch); }
      });
      peerState(P, a, 5);
      return K.OK;
    }

    case 8: /* dcx_peer_free(p) */
      freePeer(a);
      return 0;

    case 9: { /* dcx_set_local_description(p, type) */
      var P = peerOf(a);
      if (!P) return fail(K.ERR_BAD_HANDLE, 'stale peer handle');
      var type = str(b) || "";
      chain(P, 'dcx_set_local_description', function () {
        var made = type === 'offer' ? P.pc.createOffer() :
          type === 'answer' ? P.pc.createAnswer() : null;
        var set = made ? made.then(function (d) { return P.pc.setLocalDescription(d); }) :
          P.pc.setLocalDescription();
        return set.then(function () { announceDescription(P, a); });
      });
      return K.OK;
    }

    case 10: { /* dcx_set_remote_description(p, sdp, type) */
      var P = peerOf(a);
      if (!P) return fail(K.ERR_BAD_HANDLE, 'stale peer handle');
      var sdp = str(b);
      if (!sdp) return fail(K.ERR_INVALID_ARG, 'empty remote description');
      var type = str(c) || "";
      chain(P, 'dcx_set_remote_description', function () {
        var t = type || (P.pc.signalingState === 'have-local-offer' ? 'answer' : 'offer');
        return P.pc.setRemoteDescription({ type: t, sdp: sdp }).then(function () {
          if (t !== 'offer') return null;
          return P.pc.setLocalDescription().then(function () { announceDescription(P, a); });
        });
      });
      return K.OK;
    }

    case 11: { /* dcx_add_remote_candidate(p, cand, mid) */
      var P = peerOf(a);
      if (!P) return fail(K.ERR_BAD_HANDLE, 'stale peer handle');
      var cand = str(b);
      if (!cand) return fail(K.ERR_INVALID_ARG, 'empty remote candidate');
      if (cand.indexOf('a=') === 0) cand = cand.slice(2);
      var mid = str(c) || "";
      var init = mid ? { candidate: cand, sdpMid: mid } : { candidate: cand, sdpMLineIndex: 0 };
      chain(P, 'dcx_add_remote_candidate', function () { return P.pc.addIceCandidate(init); });
      return K.OK;
    }

    case 12: { /* dcx_local_description(p, out, cap) */
      var P = peerOf(a);
      var desc = P && P.pc.localDescription;
      return desc ? out(desc.sdp, b, c) : 0;
    }

    case 13: { /* dcx_local_description_type(p, out, cap) */
      var P = peerOf(a);
      var desc = P && P.pc.localDescription;
      return desc ? out(desc.type, b, c) : 0;
    }

    case 14: { /* dcx_peer_state(p) */
      var P = peerOf(a);
      return P ? P.state : -1;
    }

    case 15: { /* dcx_gathering_state(p) */
      var P = peerOf(a);
      return P ? P.gathering : -1;
    }

    case 16: { /* dcx_selected_candidate_pair(p, out, cap) */
      var P = peerOf(a);
      if (!P) return 0;
      if (!P.pair) { snapshotPair(P); return 0; }
      var r = record([strField(K.F_DC_LOCAL_CAND, P.pair[0]), strField(K.F_DC_REMOTE_CAND, P.pair[1])]);
      if (r.length > c) return -r.length;
      HEAPU8.set(r, b);
      return r.length;
    }

    case 17: /* dcx_channel_new(p, label) */
    case 18: { /* dcx_channel_new_ex(p, label, protocol, unordered, maxRetransmits, maxLifetimeMs, negotiated, streamId) */
      var P = peerOf(a);
      if (!P) { X.err = 'stale peer handle'; return 0; }
      var label = str(b) || "";
      var opts = {};
      if (op === 18) {
        if (e >= 0 && f >= 0) { X.err = 'set at most one of maxRetransmits / maxLifetimeMs'; return 0; }
        if (h > 65534) { X.err = 'streamId out of range (0..65534)'; return 0; }
        opts.ordered = d === 0;
        if (e >= 0) opts.maxRetransmits = e;
        if (f >= 0) opts.maxPacketLifeTime = f;
        opts.protocol = str(c) || "";
        opts.negotiated = g !== 0;
        if (h >= 0) opts.id = h;
      }
      var dc = P.pc.createDataChannel(label, opts);
      return wireChannel(dc, a, false);
    }

    case 19: { /* dcx_channel_close(c) */
      var C = chanOf(a);
      if (!C) return fail(K.ERR_BAD_HANDLE, 'stale channel handle');
      C.dc.close();
      return K.OK;
    }

    case 20: /* dcx_channel_free(c) */
      unwireChannel(a);
      return 0;

    case 21: { /* dcx_send_data(c, data, len) */
      var C = chanOf(a);
      if (!C) return fail(K.ERR_BAD_HANDLE, 'stale channel handle');
      if (c < 0 || (c > 0 && !b)) return fail(K.ERR_INVALID_ARG, 'bad send buffer');
      if (c > K.MAX_MESSAGE) return fail(K.ERR_TOO_LARGE, 'message exceeds DCX_MAX_MESSAGE (' +
        K.MAX_MESSAGE + ' bytes); chunk it, or move bulk via TorrentXT');
      if (C.dc.readyState !== 'open') return fail(K.ERR_NATIVE, 'dcx_send_data: the channel is not open');
      C.dc.send(HEAPU8.slice(b, b + c));
      return K.OK;
    }

    case 22: { /* dcx_send_text(c, text) */
      var C = chanOf(a);
      if (!C) return fail(K.ERR_BAD_HANDLE, 'stale channel handle');
      var text = str(b);
      if (text === null) return fail(K.ERR_INVALID_ARG, 'null text');
      if (enc.encode(text).length > K.MAX_MESSAGE) return fail(K.ERR_TOO_LARGE,
        'message exceeds DCX_MAX_MESSAGE (' + K.MAX_MESSAGE + ' bytes); chunk it, or move bulk via TorrentXT');
      if (C.dc.readyState !== 'open') return fail(K.ERR_NATIVE, 'dcx_send_text: the channel is not open');
      C.dc.send(text);
      return K.OK;
    }

    case 23: { /* dcx_channel_label(c, out, cap) */
      var C = chanOf(a);
      return C ? out(C.dc.label, b, c) : 0;
    }

    case 24: { /* dcx_channel_protocol(c, out, cap) */
      var C = chanOf(a);
      return C ? out(C.dc.protocol, b, c) : 0;
    }

    case 25: { /* dcx_channel_stream_id(c) */
      var C = chanOf(a);
      return C && typeof C.dc.id === 'number' ? C.dc.id : -1;
    }

    case 26: { /* dcx_channel_is_open(c) */
      var C = chanOf(a);
      return C && C.dc.readyState === 'open' ? 1 : 0;
    }

    case 27: { /* dcx_channel_peer(c) */
      var C = chanOf(a);
      return C ? C.peer : 0;
    }

    case 28: { /* dcx_channel_max_message(c) */
      var C = chanOf(a);
      if (!C) return -1;
      var P = peerOf(C.peer);
      var sctp = P && P.pc.sctp;
      var n = sctp && sctp.maxMessageSize ? sctp.maxMessageSize : K.MAX_MESSAGE;
      return Math.min(n, K.MAX_MESSAGE);
    }

    case 29: { /* dcx_buffered_amount(c) */
      var C = chanOf(a);
      return C ? C.dc.bufferedAmount : -1;
    }

    case 30: { /* dcx_set_buffered_low_threshold(c, amount) */
      var C = chanOf(a);
      if (!C) return fail(K.ERR_BAD_HANDLE, 'stale channel handle');
      if (b < 0) return fail(K.ERR_INVALID_ARG, 'negative threshold');
      C.dc.bufferedAmountLowThreshold = b;
      C.low = true;
      return K.OK;
    }

    case 31: { /* dcx_poll(out, cap) */
      /* As the native drain: FIFO, events naming a freed handle discarded,
       * the first that does not fit ends the pass, the overflow report rides
       * last once the backlog is empty, -needed when nothing fits */
      var at = 2, written = 0;
      while (X.queue.length) {
        var ev = X.queue[0];
        if ((ev.peer && !X.peers.has(ev.peer)) || (ev.chan && !X.chans.has(ev.chan))) {
          X.queue.shift(); X.queueBytes -= ev.bytes.length;
          continue;
        }
        if (at + ev.bytes.length > b) break;
        HEAPU8.set(ev.bytes, a + at);
        at += ev.bytes.length;
        written++;
        X.queue.shift(); X.queueBytes -= ev.bytes.length;
      }
      if (!X.queue.length && X.dropped > 0) {
        var body = record([intField(K.F_DC_PEER, 0), intField(K.F_DC_CHANNEL, 0),
          intField(K.F_DC_DROPPED, X.dropped)]);
        var entry = new Uint8Array(4 + body.length);
        entry[0] = K.E_QUEUE_OVERFLOW >> 8; entry[1] = K.E_QUEUE_OVERFLOW & 255;
        entry[2] = body.length >> 8; entry[3] = body.length & 255;
        entry.set(body, 4);
        if (at + entry.length <= b) {
          HEAPU8.set(entry, a + at);
          at += entry.length;
          written++;
          X.dropped = 0;
        } else if (written === 0) {
          return -(2 + entry.length);
        }
      }
      if (b >= 2) { HEAPU8[a] = written >> 8; HEAPU8[a + 1] = written & 255; }
      if (written === 0 && X.queue.length) return -(2 + X.queue[0].bytes.length);
      return written;
    }
    }
    X.err = 'datachannelxt web: unknown operation ' + op;
    return K.ERR_EXCEPTION;
  } catch (err) {
    X.err = 'browser exception: ' + (err && err.message ? err.message : String(err));
    /* Each entry's error value: 0 for the handle makers and the buffer
     * getters, -1 for the int getters, DCX_ERR_EXCEPTION for the actions */
    if (op === 6 || op === 17 || op === 18 || op === 3 || op === 4 || op === 12 || op === 13 ||
        op === 16 || op === 23 || op === 24 || op === 26 || op === 27 || op === 31) return 0;
    if (op === 14 || op === 15 || op === 25 || op === 28 || op === 29) return -1;
    return K.ERR_EXCEPTION;
  }
});

/* The registry, in the order dcx_js() reads it */
static const int k_dcx_registry[] = {
    dcx::E_LOCAL_DESCRIPTION, dcx::E_LOCAL_CANDIDATE, dcx::E_STATE_CHANGE, dcx::E_GATHERING_STATE,
    dcx::E_CHANNEL_INCOMING, dcx::E_CHANNEL_OPEN, dcx::E_CHANNEL_CLOSED, dcx::E_MESSAGE,
    dcx::E_CHANNEL_ERROR, dcx::E_BUFFERED_LOW, dcx::E_QUEUE_OVERFLOW,
    dcx::F_DC_PEER, dcx::F_DC_CHANNEL, dcx::F_DC_SDP, dcx::F_DC_SDP_TYPE, dcx::F_DC_CANDIDATE,
    dcx::F_DC_MID, dcx::F_DC_STATE, dcx::F_DC_LABEL, dcx::F_DC_PROTOCOL, dcx::F_DC_PAYLOAD,
    dcx::F_DC_TEXT, dcx::F_DC_ERROR, dcx::F_DC_DROPPED, dcx::F_DC_LOCAL_CAND,
    dcx::F_DC_REMOTE_CAND,
    dcx::FT_INT, dcx::FT_UTF8, dcx::FT_RAW, DCX_MAX_MESSAGE,
    DCX_OK, DCX_ERR_BAD_HANDLE, DCX_ERR_INVALID_ARG, DCX_ERR_TOO_LARGE, DCX_ERR_NATIVE,
    DCX_ERR_EXCEPTION,
};

static int js(int op, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0,
              int g = 0, int h = 0) {
    return dcx_js(op, a, b, c, d, e, f, g, h, k_dcx_registry);
}

static int ptr(const void *p) {
    return static_cast<int>(reinterpret_cast<uintptr_t>(p));
}

/* ====================================================================== *
 *  The frozen ABI (dcx_abi.h), each entry one call of dcx_js()
 * ====================================================================== */

extern "C" DCX_API int DCX_CALL dcx_abi_version(void) {
    return DCX_ABI_VERSION;
}

extern "C" DCX_API int DCX_CALL dcx_init(void) { return js(1); }
extern "C" DCX_API int DCX_CALL dcx_cleanup(void) { return js(2); }

extern "C" DCX_API int DCX_CALL dcx_library_version(char *out, int cap) {
    return js(3, ptr(out), cap);
}
extern "C" DCX_API int DCX_CALL dcx_last_error(char *out, int cap) {
    return js(4, ptr(out), cap);
}
extern "C" DCX_API void DCX_CALL dcx_clear_error(void) { js(5); }

extern "C" DCX_API int DCX_CALL dcx_peer_new(const char *iceServersLines) {
    return js(6, ptr(iceServersLines));
}
extern "C" DCX_API int DCX_CALL dcx_peer_close(int p) { return js(7, p); }
extern "C" DCX_API void DCX_CALL dcx_peer_free(int p) { js(8, p); }
extern "C" DCX_API int DCX_CALL dcx_set_local_description(int p, const char *type) {
    return js(9, p, ptr(type));
}
extern "C" DCX_API int DCX_CALL dcx_set_remote_description(int p, const char *sdp,
                                                           const char *type) {
    return js(10, p, ptr(sdp), ptr(type));
}
extern "C" DCX_API int DCX_CALL dcx_add_remote_candidate(int p, const char *cand,
                                                         const char *mid) {
    return js(11, p, ptr(cand), ptr(mid));
}
extern "C" DCX_API int DCX_CALL dcx_local_description(int p, char *out, int cap) {
    return js(12, p, ptr(out), cap);
}
extern "C" DCX_API int DCX_CALL dcx_local_description_type(int p, char *out, int cap) {
    return js(13, p, ptr(out), cap);
}
extern "C" DCX_API int DCX_CALL dcx_peer_state(int p) { return js(14, p); }
extern "C" DCX_API int DCX_CALL dcx_gathering_state(int p) { return js(15, p); }
extern "C" DCX_API int DCX_CALL dcx_selected_candidate_pair(int p, void *out, int cap) {
    return js(16, p, ptr(out), cap);
}

extern "C" DCX_API int DCX_CALL dcx_channel_new(int p, const char *label) {
    return js(17, p, ptr(label));
}
extern "C" DCX_API int DCX_CALL dcx_channel_new_ex(int p, const char *label,
                                                   const char *protocol, int unordered,
                                                   int maxRetransmits, int maxLifetimeMs,
                                                   int negotiated, int streamId) {
    return js(18, p, ptr(label), ptr(protocol), unordered, maxRetransmits, maxLifetimeMs,
              negotiated, streamId);
}
extern "C" DCX_API int DCX_CALL dcx_channel_close(int c) { return js(19, c); }
extern "C" DCX_API void DCX_CALL dcx_channel_free(int c) { js(20, c); }
extern "C" DCX_API int DCX_CALL dcx_send_data(int c, const void *data, int len) {
    return js(21, c, ptr(data), len);
}
extern "C" DCX_API int DCX_CALL dcx_send_text(int c, const char *text) {
    return js(22, c, ptr(text));
}
extern "C" DCX_API int DCX_CALL dcx_channel_label(int c, char *out, int cap) {
    return js(23, c, ptr(out), cap);
}
extern "C" DCX_API int DCX_CALL dcx_channel_protocol(int c, char *out, int cap) {
    return js(24, c, ptr(out), cap);
}
extern "C" DCX_API int DCX_CALL dcx_channel_stream_id(int c) { return js(25, c); }
extern "C" DCX_API int DCX_CALL dcx_channel_is_open(int c) { return js(26, c); }
extern "C" DCX_API int DCX_CALL dcx_channel_peer(int c) { return js(27, c); }
extern "C" DCX_API int DCX_CALL dcx_channel_max_message(int c) { return js(28, c); }
extern "C" DCX_API int DCX_CALL dcx_buffered_amount(int c) { return js(29, c); }
extern "C" DCX_API int DCX_CALL dcx_set_buffered_low_threshold(int c, int amount) {
    return js(30, c, amount);
}

extern "C" DCX_API int DCX_CALL dcx_poll(void *out, int cap) {
    return js(31, ptr(out), cap);
}
