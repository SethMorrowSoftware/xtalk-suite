# DataChannelXT

**WebRTC data channels for OpenXTalk / the xTalk family** - browser-interoperable,
NAT-traversing, real-time peer-to-peer messaging from plain xTalk script.

DataChannelXT binds [libdatachannel](https://github.com/paullouisageneau/libdatachannel)
(v0.24.5, C++17, MPL-2.0: WebRTC data channels with libjuice ICE and usrsctp SCTP) behind a
flat `extern "C"` shim with a thin LCB layer on top, the shape of its suite siblings
TorrentXT (libtorrent) and SodiumXT (libsodium):

```
libdatachannel + libjuice + usrsctp (+ system OpenSSL)   owns the network threads
   |- C++ shim     src/datachannel_shim.cpp  ->  datachannelxt.{so,dll,dylib}  (ABI: dcx_*)
        |- LCB binding  src/datachannel.lcb       (library org.openxtalk.library.datachannel; public dc*)
             |- script helpers  examples/datachannel-helpers.livecodescript  (the poll dispatcher)
```

## What it can do

- **Talk to browsers.** A channel opened here is a standard WebRTC data channel; the far
  side can be a few lines of JavaScript in any modern browser.
- **Punch through NATs.** ICE with STUN/TURN (libjuice) finds a direct, DTLS-encrypted path
  between two home connections without either side configuring a router.
- **Real-time modes.** Reliable + ordered by default; `dcCreateChannelEx` adds unordered and
  unreliable (max-retransmits / max-lifetime) channels for game state and live cursors, plus
  negotiated channels on fixed stream ids.
- **Backpressure.** `dcBufferedAmount` and the `dcBufferedLow` event let a sender throttle
  instead of ballooning memory.
- **Text and binary.** `dcSendText` arrives as a string (browser: `string`), `dcSendData` as
  bytes (browser: `ArrayBuffer`), up to 60000 bytes per message; bulk transfer belongs to
  TorrentXT. `dcSendText` refuses a string carrying an embedded NUL with -3 rather than let
  it truncate at the C terminator; anything that can hold a NUL goes via `dcSendData`.

## Quick taste

```livecodescript
start using stack "dataChannelHelpers"      -- the poll dispatcher
dcStartPolling the long id of this card, 33 -- ~30 Hz drain

put dcCreatePeer("stun:stun.l.google.com:19302") into tPeer
put dcCreateChannel(tPeer, "chat") into tChan
-- creating the first channel starts negotiation; now catch the artifacts:

on dcLocalDescriptionReady pEvent
   -- ship pEvent["sdp"] + pEvent["sdpType"] to the far peer over ANY channel
end dcLocalDescriptionReady

on dcLocalCandidate pEvent
   -- ship pEvent["candidate"] + pEvent["mid"] the same way
end dcLocalCandidate

-- ...and feed the far side's artifacts back in:
--   dcSetRemoteDescription tPeer, tSdp, tType
--   dcAddRemoteCandidate tPeer, tCandidate, tMid

on dcChannelOpen pEvent
   put dcSendText(pEvent["channel"], "hello from xTalk!") into tResult  -- 0 or a negative code
end dcChannelOpen

on dcMessage pEvent
   put pEvent["text"] into field "chat"
end dcMessage
```

**Signaling is yours.** WebRTC needs the two peers to exchange a description and candidates
over *some* existing channel: a TorrentXT DHT rendezvous (the serverless flagship), a
copy/paste, a web service. [docs/getting-started.md](docs/getting-started.md) walks it.

## Try it now (no network, no setup)

Paste `examples/datachannel-loopback.livecodescript` into a stack script and reopen the stack
(opening the file itself builds no window - the suite's engine note 5.5). It is one
paste-and-run file with the poll dispatcher carried inside: two real WebRTC peers negotiate
inside one process (offer, answer, ICE, DTLS, SCTP) and you chat between two panes. Its
"signaling" is four lines of script, because both peers live in the same stack.

## Examples and the self-test

The demos carry `datachannel-helpers` between sentinels owned by the suite's
`tools/sync-demo-embeds.py` (nothing to load first); edit the helpers, never the sentinels.

- **`examples/datachannel-helpers.livecodescript`** - the poll dispatcher (`dcStartPolling` /
  `dcStopPolling`) turning the native queue into messages (`dcMessage`, `dcChannelOpen`,
  ...), display sugar and the pump's diagnostic pair (`dcPollLastError` /
  `dcPollClearError`). A real app starts using this copy: `start using stack "dataChannelHelpers"`.
- **`examples/datachannel-loopback.livecodescript`** - two WebRTC peers in one stack, both
  message kinds; its `dcLocalDescriptionReady` / `dcLocalCandidate` handlers are the
  template to replace with real signaling. It has no engine record of its own yet.
- **`examples/datachannel-dht-chat.livecodescript`** - the flagship, two machines and no
  server: host a room, paste its code on the other machine, and the WebRTC handshake travels
  as signed BEP44 items over TorrentXT's DHT; the chat is then a direct DTLS channel (no
  account, no port forward). Shows non-trickle one-blob signaling, the 1000-byte BEP44
  budget (compress + chunk), nonce-paired offer/answer, reconnection and a direct-vs-TURN
  readout. Needs TorrentXT installed too (probed at startup; fails closed).
- **`tests/datachannel-selftest.livecodescript`** - verifies an installed extension end to
  end: the synchronous surface, a live loopback, message round-trips, teardown.
- **`tests/browser-peer.html` + `tests/datachannel-browser-peer.livecodescript`** - the
  browser-interop pair: a static page (plain JavaScript `RTCPeerConnection`) and a
  message-box-driven OXT script, signaling by copy/paste. They check that `dcSendText`
  arrives in a browser as a string and `dcSendData` as an ArrayBuffer, and the reverse.
  Procedure: [docs/browser-interop.md](docs/browser-interop.md).

Every demo builds its own UI idempotently, treats the poll interval as a latency knob, and
calls `dcCleanup` on `closeStack`, written bare (a zero-argument call in statement position
does not compile with parentheses).

## Status

The binding is engine-proven: first live loopback 2026-08-08; every one of the 31 public
`dc*` handlers called by name 2026-08-10; the standalone self-test green end to end,
async loopback included, 2026-08-15; the embedded-NUL refusal and exact stale-handle codes
green 2026-08-17 (Windows); folded in the suite paste through 2026-09-25, when the paste's
own live loopback also completed on Linux (negotiated, both ends open, SCTP at least 16 KiB,
a cap-sized payload whole). The flagship ran on
one machine on Linux and Windows on 2026-08-18, which surfaced engine notes 1.6, 6.6 and 6.7
(why the event is `dcLocalDescriptionReady`), and a DHT-signalled WebRTC chat was reported
working between two machines on one LAN on 2026-08-27 (which stack ran was not recorded).
Still open: the loopback demo (no engine record), a two-machine run recorded against the
dht-chat demo by name, a call across two networks with real NAT traversal, and browser
interop on an engine (the page and the OXT half exist; the page has run only headlessly,
2026-09-24, against the committed library through its C ABI).
`CLAUDE.md` carries the dated ledger.

## Install

A standard OXT extension: the LCB module plus the native library under
`src/code/<platform-id>/`. All five ids are committed and pinned in `src/code/MANIFEST.sha256`
(`x86_64-linux`, `x86-linux`, `x86_64-win32`, `x86-win32`, and `universal-mac` with both
slices, first landed 2026-08-27 by the suite's `release-binaries.yml` two-slice-lipo job; all
five rebuilt 2026-09-12). Both Linux libraries need glibc 2.38 or newer (measured
2026-09-23): Ubuntu 22.04, Debian 12 and RHEL 9 cannot load them; the x86_64 one loaded on
Kubuntu 24.04 (glibc 2.39) on 2026-09-25. Install through the
Extension Manager and the engine resolves `c:datachannelxt>`: no loose library, no `sudo`.

One rule the app must follow: **call `dcCleanup` before quitting** (e.g. on `closeStack`),
written bare in statement position. There is no automatic unload hook; skipping it leaks the
native worker threads at quit.

## Documentation

| Document | What it is |
|---|---|
| [docs/getting-started.md](docs/getting-started.md) | Install to a two-machine connection: the three habits, the signaling shapes (including why the event is `dcLocalDescriptionReady`), STUN/TURN, the demos. Read first. |
| [docs/api-reference.md](docs/api-reference.md) | All 31 public `dc*` handlers, events, error codes, constants and the app rules. |
| [docs/architecture.md](docs/architecture.md) | How libdatachannel's worker threads and OXT's single thread share a process safely: the bounded queue, the lock discipline, handles, the codec. |
| [docs/building.md](docs/building.md) | Building on all five targets, the ASan and TSan lanes, packaging and CI. |
| [docs/browser-interop.md](docs/browser-interop.md) | The browser leg: the page, the OXT half, the copy/paste blob format, the procedure and what has run. |
| [CLAUDE.md](CLAUDE.md) | Maintainer memory: rules, gotchas, the engine evidence ledger. |
| [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) | License texts for libdatachannel, libjuice, usrsctp and plog. |

Suite-wide documents: https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/README.md

## Development

`tests/datachannel_smoke_test.cpp` drives an in-process loopback (two peers, SDP/candidate
shuttle, echo) through the exported ABI, and CI runs it three ways: Release, **ASan+UBSan
across the whole dependency stack**, and **ThreadSanitizer** across the same (this is the
family's one binding with true cross-thread callbacks; TSan is the gate that proves the
queue). `tests/orphan_channel_test.cpp` rides the same lanes. It drives the two orphan exits
of the remote-channel callback against `datachannelxt_seams`, a test-only build of the same
shim that is never shipped. `bash tools/run-gates.sh` runs the static gates without a native build: the unified
`check-livecodescript.py`, the record golden, `check-record-registry.py` and the manifest.
Build commands and the sanitizer lanes: [docs/building.md](docs/building.md).

## License

DataChannelXT is MIT (see `LICENSE`). It statically links
[libdatachannel](https://github.com/paullouisageneau/libdatachannel) and
[libjuice](https://github.com/paullouisageneau/libjuice) (both MPL-2.0) and
[usrsctp](https://github.com/sctplab/usrsctp) (BSD-3). DTLS comes from OpenSSL (Apache-2.0):
the host's library on Linux, statically linked into the Windows DLLs and the universal mac
dylib. MPL-2.0 is file-level copyleft and compatible with this use: modifications to
those libraries themselves must be published, and none are made (they build from pinned
upstream tags).

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

DataChannelXT is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`datachannelxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/dataChannelXT: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `datachannelxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port datachannelxt --ref pull/<n>/head`, keeping its
author - but a commit made here directly holds up the next publish until
it has been ported, because publishing never overwrites work it did not
write. The suite's `docs/MEMBER-REPO-SPLIT.md` is the whole workflow.

**Suite-level paths cited from here.** This member's `CLAUDE.md` and
`docs/` cite files that live at the suite root, not in this tree:
`docs/OXT-ENGINE-NOTES.md` (engine behaviour, the authoritative list),
`docs/OXT-PASS-RUNBOOK.md`, `tools/build-all.sh`,
`tests/suite-selftest.livecodescript` and the suite-level `docs/`
index. Read them at `https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/<path>`. A path of the
form `../<member>/...` names a sibling member of the suite; each has its
own repository, listed in `tools/member-registry.py` there.

**Sibling members this member's gates need beside it.** None: `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
needs nothing but this checkout and Python 3.

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `examples/datachannel-dht-chat.livecodescript`, `examples/datachannel-loopback.livecodescript`.
- The boot self-check block (`tools/demo-selfcheck.livecodescript`; gate `tools/check-demo-selfcheck-drift.py`) in `examples/datachannel-dht-chat.livecodescript`, `examples/datachannel-loopback.livecodescript`.
- The self-test harness scaffold (`tools/harness-scaffold.livecodescript`; gate `tools/check-harness-scaffold-drift.py`) in `tests/datachannel-selftest.livecodescript`.
- This member's own library, embedded into its own stacks by the same tool so each is one file to paste: `examples/datachannel-dht-chat.livecodescript` carries `examples/datachannel-helpers.livecodescript`; `examples/datachannel-loopback.livecodescript` carries `examples/datachannel-helpers.livecodescript`; `tests/datachannel-selftest.livecodescript` carries `examples/datachannel-helpers.livecodescript`.
- `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

**What this repository cannot check on its own.** The suite-wide gates -
cross-library name disjointness (`tools/check-cross-library-names.py`),
the carried-copy drift gates above, embed freshness, the cross-member
handler-call and typed-boundary checks (`tools/check-handler-calls.py`,
`tools/check-lcb-call-types.py`), the timer-pin closure, and the suite
paste's coverage ratchet (`tools/check-suite-coverage.py`) - run only in
the suite. `tools/run-gates.sh` here is this member's own list, and the
suite's `tools/build-all.sh` runs that same script, so the two cannot
disagree about what this member's gates are.

<!-- ==== SUITE RELATIONSHIP END ==== -->
