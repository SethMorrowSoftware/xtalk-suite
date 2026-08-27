# DataChannelXT

**WebRTC data channels for OpenXTalk / the xTalk family** — browser-interoperable,
NAT-traversing, real-time peer-to-peer messaging from plain xTalk script.

DataChannelXT binds [libdatachannel](https://github.com/paullouisageneau/libdatachannel)
(C++17, MPL-2.0 — WebRTC data channels with libjuice ICE and usrsctp SCTP) behind a
flat `extern "C"` shim with a thin LCB layer on top, the same proven shape as its
suite siblings TorrentXT (libtorrent) and SodiumXT (libsodium), and the pre-suite
projects Box2Dxt and ShowControl where the shape was proven:

```
libdatachannel + libjuice + usrsctp (+ system OpenSSL)   owns the network threads
   |- C++ shim     src/datachannel_shim.cpp  ->  datachannelxt.{so,dll,dylib}  (ABI: dcx_*)
        |- LCB binding  src/datachannel.lcb       (library org.openxtalk.library.datachannel; public dc*)
             |- script helpers  examples/datachannel-helpers.livecodescript  (the poll dispatcher)
```

An OXT app gets what no xTalk environment has had: a **direct, encrypted, real-time
channel to another machine — or to a web browser** — that punches through NATs
(ICE/STUN/TURN), with reliable *and* unreliable delivery modes, ordered and
unordered, from a dozen lines of script.

## What it can do

- **Talk to browsers.** A data channel opened here is a standard WebRTC data
  channel; the far side can be five lines of JavaScript on any modern browser.
- **Punch through NATs.** ICE with STUN/TURN (libjuice) finds a path between two
  home connections without either side configuring a router.
- **Real-time modes.** Reliable+ordered by default; `dcCreateChannelEx` unlocks
  unordered and unreliable (max-retransmits / max-lifetime) channels for game
  state and live cursors, plus negotiated channels on fixed stream ids.
- **Backpressure.** `dcBufferedAmount` + the `dcBufferedLow` event let a sender
  throttle instead of ballooning memory.
- **Text and binary.** `dcSendText` arrives as a string (browser: `string`),
  `dcSendData` as bytes (browser: `ArrayBuffer`), up to 60 000 bytes per message
  (the documented budget — route bulk transfer to TorrentXT, which exists for it).
  Text is text: `dcSendText` refuses a string carrying an embedded NUL with -3
  rather than let it truncate at the C string's terminator (see the api-reference).
  Anything that can hold a NUL is binary — send it with `dcSendData`.

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
   dcSendText(pEvent["channel"], "hello from xTalk!")
end dcChannelOpen

on dcMessage pEvent
   put pEvent["text"] into field "chat"
end dcMessage
```

**Signaling is yours** — WebRTC needs the two peers to exchange a description and
candidates over *some* existing channel, and that channel is your choice: a
TorrentXT DHT rendezvous (the serverless flagship pairing), a copy/paste, a web
service. `examples/datachannel-loopback.livecodescript` is a complete demo
where "signaling" is four lines of script, because both peers live in the
same stack; `docs/getting-started.md` walks the real thing.

## Try it now (no network, no setup)

Paste `examples/datachannel-loopback.livecodescript` into a stack script and
reopen the stack (opening the file itself builds no window - `docs/OXT-ENGINE-NOTES.md`
5.5 in the suite root) - one paste-and-run file, the poll dispatcher carried inside it, nothing to load
alongside: two real WebRTC peers negotiate inside one process — offer, answer,
ICE, DTLS, SCTP — and you chat between two panes. If that works, the whole
pipeline works; real signaling is the only thing left to add.

> **Honesty note (the suite convention):** the native pipeline (shim +
> libdatachannel) is proven by the C++ smoke test under ASan/UBSan and TSan.
> The script layer now has its **first recorded engine evidence**: on
> **2026-08-08** the suite's `tests/suite-selftest.livecodescript` ran green on a real OXT
> engine, and its datachannelxt section drove `dcInit`, a stale-handle no-op,
> peer and channel creation, a **live in-process loopback that negotiated and
> opened both ends**, the incoming channel's label, `dcSendData` round-tripping
> a payload byte-for-byte, the 60000-byte refusal (`-4`), a payload at the
> SCTP-negotiated cap, and `dcCleanup`. So the binding loads and the
> negotiate → open → transfer → teardown spine is observed, not designed.
>
> On **2026-08-10** the member harness's synchronous half ran green on a real
> engine too (23 checks, twice in one day), folded into the suite selftest,
> which now calls **every one of the 31 public `dc*` handlers** by name —
> `dcCreateChannelEx`, `dcSetBufferedLowThreshold`, `dcLocalDescriptionType`,
> `dcChannelProtocol`, `dcSetLocalDescription` and friends included. On
> **2026-08-15** the standalone async loopback closed too:
> `tests/datachannel-selftest.livecodescript` ran green end to end — a real
> SDP carrying ICE candidates, correct offer/answer roles, gathering
> complete on both peers with a selected candidate pair, text and binary
> (embedded NUL included) byte-for-byte, the `dcCreateChannelEx`
> label/protocol round-trip, and a cap-sized send. **That run closed the async
> loopback; it vouches for the file it ran, not for the file as it stands.**
> The assertions added since - the exact-code stale-handle checks, the
> embedded-NUL refusal and its last-error clearing, and the
> skip-on-failed-setup teardown branch - are **verified statically; needs an
> OXT pass** on a build carrying `kErrInvalidArg`. Still open: browser interop
> (a real Chrome/Firefox peer) and a call across two networks with real
> NAT traversal.

## Then try the flagship (two machines, no server)

`examples/datachannel-dht-chat.livecodescript` supplies that real signaling
with the family's own answer: **TorrentXT's DHT.** Host a room on one machine,
paste the room code on the other, and the WebRTC handshake travels as signed
BEP44 items over the BitTorrent DHT — then the chat itself is a direct,
DTLS-encrypted data channel between the two machines. No account, no server,
no port forward, nothing to operate. It needs the TorrentXT extension
installed alongside this one (probed at startup; fails closed with a clear
message when missing); `docs/getting-started.md` section 6 has the tour.

## Install

DataChannelXT ships as a standard OXT extension: the LCB module plus the
per-platform native library bundled under `src/code/<arch>-<platform>/`
(the five-id layout: `x86_64-linux`, `x86-linux`, `x86_64-win32`, `x86-win32`,
`universal-mac`). Four are committed and pinned in `src/code/MANIFEST.sha256`;
`universal-mac` is not committed yet — since 2026-08-23 the suite's
`release-binaries.yml` carries a two-slice-lipo mac lane for this member
(per-arch pinned static OpenSSL, both slices tested, `lipo -create`), and its
first dispatch is what lands the dylib; a manual build per `docs/building.md`
remains equivalent.
Installing the packaged extension makes the engine resolve the
`c:datachannelxt>` binding automatically — no loose library, no `sudo`, no
`LD_LIBRARY_PATH`. See `docs/getting-started.md`.

One rule the app must follow: **call `dcCleanup()` before quitting** (e.g. on
`closeStack`). There is no automatic unload hook; skipping it leaks the native
worker threads at quit.

## Documentation

| Doc | What is in it |
|---|---|
| `docs/getting-started.md` | install, first connection, the signaling walk-through |
| `docs/api-reference.md`   | every `dc*` handler, event, key, and constant |
| `docs/architecture.md`    | the shim design: the mutex queue, handles, the record codec |
| `docs/building.md`        | building the native library on all five targets |

## Development

The native layer has a real test story — `tests/datachannel_smoke_test.cpp`
drives an in-process loopback (two peers, SDP/candidate shuttle, echo) through
the exported ABI, and CI runs it three ways: plain Release, **ASan+UBSan across
the whole dependency stack**, and **ThreadSanitizer** across the same (this is
the family's one binding with true cross-thread callbacks; TSan is the gate
that proves the queue). Static gates (`tools/check-livecodescript.py`, the
record golden, the registry cross-check) run without any native build.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DDATACHANNELXT_BUILD_TESTS=ON
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

See `CLAUDE.md` for the engineering rules (the three safety rules, the lock
discipline, the FFI conventions) and `docs/building.md` for the sanitizer lanes.

## License

DataChannelXT is MIT (see `LICENSE`). It statically links
[libdatachannel](https://github.com/paullouisageneau/libdatachannel),
[libjuice](https://github.com/paullouisageneau/libjuice) (both MPL-2.0), and
[usrsctp](https://github.com/sctplab/usrsctp) (BSD-3); DTLS via the system
OpenSSL (Apache-2.0). MPL-2.0 is file-level copyleft and compatible with this
use — modifications to those libraries themselves must be published, and none
are made (they build from pinned upstream tags).
