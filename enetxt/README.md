# enetxt

**ENet — reliable-UDP real-time networking — for OpenXTalk / the xTalk
family.** Game-grade many-peer messaging from plain xTalk script: reliable,
unreliable-sequenced, and unsequenced delivery on independent channels,
sub-frame latency on a LAN, one broadcast to fan out to every peer.

enetxt binds [ENet](https://github.com/lsalzman/enet) (v1.3.18, MIT — the
reliable-UDP library a generation of games shipped on) behind a flat
`extern "C"` shim with a thin LCB layer on top, the proven shape of its
siblings TorrentXT (libtorrent), dataChannelXT (libdatachannel), and SodiumXT
(libsodium):

```
ENet v1.3.18 (static)                          sockets + the reliability protocol
   |- C++ shim   src/enet_shim.cpp  ->  enetxt.{so,dll,dylib}   (ABI: enx_*, v2)
        |- LCB binding  src/enet.lcb      (org.openxtalk.library.enet; public en*)
             |- examples/enet-helpers.livecodescript   (the pump)
```

It completes the family's real-time story: **enetxt** for many peers at game
cadence where someone is reachable (LAN, port forward, rented box);
**dataChannelXT** for NAT-traversed pairs and browsers; **TorrentXT** for
bulk. The 60 000-byte packet budget here is the seam — when a payload stops
being a message, move it to torrents.

> **Documentation:** [`docs/README.md`](docs/README.md) indexes every page for this member — getting started, all 23 `en*` handlers, the architecture, and the build.

## What it can do

- **Hosts and peers, not sockets.** `enHostCreateServer` /
  `enHostCreateClient` / `enConnect`, with generation-tagged integer handles
  everywhere — a stale handle is always a harmless no-op.
- **Three delivery modes per send** — reliable (acked, ordered), unreliable
  (sequenced, droppable: perfect for state you overwrite every tick),
  unsequenced (fire-and-forget) — on up to 255 independent channels, so
  reliable traffic can never stall the real-time lane.
- **One-call fanout.** `enBroadcast` queues one packet to every connected
  peer — the server-relay primitive.
- **Live stats.** `enPeerStatus` is one FFI round-trip: state, RTT, packet
  loss, byte counters, address. Plus tuning: timeouts, ping interval,
  bandwidth throttles.
- **Pump-driven by design.** ENet has no threads; the helpers' poll loop IS
  the transport ("pump or nothing"), which makes rule 1 of the family — never
  call script from a foreign thread — true by construction.

## Quick taste

```livecodescript
start using stack "enetHelpers"
put enHostCreateServer("", 27099, 32, 2, 0, 0) into sServer
enStartPolling sServer, the long id of this card, 33   -- the heartbeat

on enetConnect pEvent
   enSendText pEvent["peer"], 0, "welcome!", 0          -- 0 = reliable
end enetConnect

on enetReceive pEvent
   enBroadcast sServer, 0, pEvent["payload"], 0         -- relay to everyone
end enetReceive
```

`docs/getting-started.md` walks the rest (the client side, delivery modes,
the protocol-version trick); `examples/enet-lan-chat.livecodescript` is the
complete two-machine LAN demo, and `examples/enet-internet-chat.livecodescript`
is its sibling for two machines on DIFFERENT networks — TorrentXT opens the
router's UDP port (`btMapPort`) and discovers the public IP, and the chat bytes
are pure ENet. That one is verified statically; it needs a two-machine,
two-network OXT pass, which is the leg it exists to close.

## Install

enetxt ships as a standard OXT extension: the LCB module plus the
per-platform native library bundled under `src/code/<arch>-<platform>/`
(the five-id layout: `x86_64-linux`, `x86-linux`, `x86_64-win32`, `x86-win32`,
`universal-mac`). **Currently committed: four platforms** — `x86_64-linux`,
`x86-linux`, `x86_64-win32`, and `x86-win32`, pinned in
`src/code/MANIFEST.sha256` (the 2026-08-08 release run landed all four, and
the root workflow `native-enetxt.yml` builds the full matrix on every touch).
Only `universal-mac` is absent: since 2026-08-23 `release-binaries.yml`
carries a universal mac lane for this member (both slices in one
`CMAKE_OSX_ARCHITECTURES` pass, asserted at birth), and its first dispatch is
what lands the dylib; a manual build is equivalent only when it carries BOTH
slices too (`-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"` — the macOS section of
`docs/building.md`), because the suite's `tools/install-release-binaries.py`
refuses a thin Mach-O under the `universal-mac` id. Installing the packaged
extension makes the engine resolve the `c:enetxt>` binding automatically. See
`docs/getting-started.md`.

One rule the app must follow: **call `enDeinitialize` before quitting**
(e.g. on `closeStack`) — there is no automatic unload hook.

## Documentation

| Doc | What is in it |
|---|---|
| `docs/getting-started.md` | install, first server+client, delivery modes |
| `docs/api-reference.md`   | every `en*` handler, event, key, and constant |
| `docs/architecture.md`    | the pump model, the lossless stash drain, handles |
| `docs/building.md`        | building on all five targets (minutes, not hours) |

## Development

`tests/enet_smoke_test.cpp` drives the ENTIRE exported ABI over a live
one-process loopback — connect data, reliable echo, broadcast, byte-exact
payloads, the keyhole partial-drain (lossless at any buffer size), handle
retirement, teardown — and runs under **ASan+UBSan with ENet itself
instrumented**. `record_handle_test` + the Python golden pin the wire format;
`check-record-registry.py` enforces registry/ABI/budget sync; and
`tools/check-livecodescript.py` is the family's unified static gate - one
implementation, carried byte-identical in every member, held there by the
suite's `tools/check-checker-drift.py` and fixture-tested rule by rule by the
suite's `tools/test-checker.py`. It carries the per-dialect antipattern sets
for both `.lcb` and `.livecodescript`, including the `the number of keys of X`
rule that came out of this member's own `examples/enet-lan-chat.livecodescript`
on 2026-08-18.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENETXT_BUILD_TESTS=ON
cmake --build build --parallel && ctest --test-dir build --output-on-failure
```

See `CLAUDE.md` for the engineering rules and `docs/building.md` for the
sanitizer lane. Binding-side runtime behaviour is confirmed in OXT: the
selftest (`tests/enet-selftest.livecodescript`) ran green on 2026-08-07, the
2026-08-08 suite pass re-confirmed the live loopback plus the 60000-byte
fragmentation contract, and the folded synchronous half ran green twice on
2026-08-10 (21 checks), and the full standalone selftest — async loopback,
live host/peer status and the statistics assertions included — ran green on
2026-08-13. Everything green that day is a runtime result; what has landed in
that file SINCE is not. The helper-layer section added 2026-08-20 (it asserts
the `enPollLastError()` / `enPollClearError` surface the pump's guarded drain
gained on 2026-08-18), the harness scaffold's completeness trailer and timer
pins from the same week, and the regenerated helper embed from the 2026-08-23
script-local rename are verified statically; they need an OXT re-pass. The LAN
chat demo is a separate question, and it was open longer than this line used to
admit: it first reached an engine on 2026-08-18 (Linux), on ONE machine, and it
carried two defects that no earlier run could have missed had one ever
happened - `ecDashOnce`'s `the number of keys of sPeers`, which threw once a
second on the host path, and an emptied `sHost` handed to
`enHostDestroy(in pHost as Integer)` on the disconnect path, which killed the
poll chain silently. Both are recorded in
[`../docs/OXT-ENGINE-NOTES.md`](../docs/OXT-ENGINE-NOTES.md) 1.7 and 6.4, and
both are fixed. Host/join chat on one machine was confirmed working by the
maintainer at the end of that session; the two-machine leg is the surface that
still needs an OXT pass.

## License

enetxt is MIT (matching the family). It statically links
[ENet](https://github.com/lsalzman/enet) (MIT).
