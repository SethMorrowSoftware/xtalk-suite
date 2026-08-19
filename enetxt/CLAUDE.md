# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in
the ENetXT member of the xtalk-suite monorepo (`enetxt/`).

> **Phase 1 complete (the full binding).** The plan is the suite's
> `docs/NEXT-EXTENSIONS-PLAN.md` Part III ("ENet — real-time, step 1");
> milestones 0–3 are built: the full `enx_` ABI (v2), the LCB layer
> (`org.openxtalk.library.enet`, public `en*`), helpers, the LAN chat demo,
> the OXT selftest, all static gates, CI, and the four committed
> Linux/Windows binaries (macOS stays a manual build).
> The OXT runtime pass happened 2026-08-07: `tests/enet-selftest.livecodescript`
> runs green in OXT — all tests pass. That retires the `MCStringEncode`
> first-runtime-use flag from the pre-pass audit (the selftest's `enSendText`
> legs exercise that bind). A second engine pass on 2026-08-08 (the suite
> selftest, green) added the cross-member evidence: enetxt carried a
> SodiumXT-sealed ciphertext over a live loopback and delivered it
> byte-for-byte, `enSend` **refused** 60001 bytes with `-4` rather than
> truncating, accepted a payload at exactly the 60000-byte budget, and ENet
> reassembled all 60000 bytes into ONE message — the fragmentation contract,
> observed rather than reasoned. A third pass on 2026-08-10 (the suite selftest
> with this member's synchronous half folded in, 21 checks green, twice in one
> day) retired the isolated teardown section added after the 2026-08-07 pass:
> `enDisconnectNow`, `enResetPeer`, `enSetPeerTimeout` and `enSetHostBandwidth`
> all returned 0 against a live client host on a real engine. A fourth pass
> on 2026-08-13 closed the async loopback itself: the member selftest ran
> STANDALONE, green end to end — the live `enHostStatus` pair (while
> connected, and counting zero peers after the disconnect) and the
> `enPeerStatus` statistics half (rtt, packetLoss, the packet/byte
> counters), added that same day, are all runtime results now.
> A fifth pass on 2026-08-18 finally put the LAN chat DEMO on an engine, on
> ONE machine (Linux; the suite's
> [`docs/OXT-ENGINE-NOTES.md`](../docs/OXT-ENGINE-NOTES.md) 6.4 is the dated
> entry, and the session's later Windows report there is datachannelxt's, not
> this member's). It reported two defects in this demo, and fixing the first
> did not end the hunt, which is why both are recorded here rather than only
> the one that finished it. (1) `enHostDestroy sHost` on the disconnect path,
> declared `in pHost as Integer`, handed EMPTY by the second
> `enetDisconnect` - ENet delivers one per peer and a failed connect makes one
> of its own - which is a throw, not a no-op: it killed the poll chain and
> left the demo silently dead (6.4). The same file already guarded `sHost` in
> ten other places, and this was the one path that did not. (2) `the number of
> keys of sPeers` does not parse at all - `keys` is not a chunk, so the engine
> reads `keys of sPeers` as an OBJECT expression (1.7, filed that day as
> 1.5b). Two
> occurrences in this file, the join log in `enetConnect` and the dashboard in
> `ecDashOnce`, both rewritten to `the number of lines of the keys of sPeers`,
> the spelling that already had engine evidence behind it. The once-a-second
> "Chunk: error in object expression" was credited to the UI kit's `uiStatus`
> first, and the defaultStack pin that went into the kit master for it is a
> real hardening resting on documented resolution semantics - but an argument
> is evaluated in the CALLER and never reaches the handler it is passed to, so
> (2) is what had been throwing all along, and 5.3 is classed DOCUMENTED
> rather than OBSERVED for exactly that reason. The pin lives in the suite's
> `tools/ui-kit.livecodescript` and was re-carried byte-identical, never
> patched into this demo. The poll pump gained a guarded DRAIN as well as a
> guarded dispatch in the same session, plus `enPollLastError()` /
> `enPollClearError`, which the demo surfaces in its own log. At the end of
> that session the maintainer reported single-machine host/join chat working.
> Still un-exercised: the LAN chat demo between two real MACHINES - the demo
> is a single-machine engine pass 2026-08-18, and the two-machine leg needs an
> OXT pass.

## The rules that carry over unchanged

1. **Never call script from a foreign thread** — trivially satisfied here:
   ENet has NO internal threads. The flip side is the binding's defining
   property: **pump or nothing.** Nothing connects, sends, or receives unless
   `enet_host_service` is called; the `enPoll` drain (each tick: loop
   `enet_host_service(host, &e, 0)` until 0) is the transport's heartbeat and
   its cadence is the latency floor (16–33 ms for real-time feel).
2. **The exception firewall** — every `enx_*` entry point body runs inside
   `ENX_GUARD_*` (see `src/enx_abi.h`). Two sibling lessons are baked into the
   macros' comment and MUST be kept: one declaration per line inside a guard
   body (the macro-comma trap), and no preprocessor directive inside a guard
   body (gcc tolerates it, MSVC rejects it — C2121; hoist into a helper).
3. **Payload crosses here by design** (packets ARE messages: game state,
   control) but ENet is not for files — bulk belongs to TorrentXT. Packet
   ownership: `enet_packet_create` copies in; after `enet_peer_send` the host
   owns the packet; on RECEIVE copy the bytes out THEN `enet_packet_destroy`
   — never hand script a pointer into ENet-owned memory (the smoke test models
   this copy-then-destroy shape).

## As-built facts (Phase 1)

- Dependency pinned: ENet v1.3.18 (MIT) via FetchContent; headers are SYSTEM
  headers; `CMAKE_POSITION_INDEPENDENT_CODE ON` sits BEFORE FetchContent (a
  non-PIC static archive cannot link into the shared lib; ld only says "bad
  value"). One shared library, bare token `enetxt`.
- `ENETXT_SANITIZE` is the family's GLOBAL sanitizer knob (injected before
  FetchContent so ENet is instrumented too). "address" is the lane that
  matters; ENet is threadless so there is NO TSan lane, on purpose.
- `enet_initialize`/`enet_deinitialize` are process-global; the shim
  refcounts them, and the FINAL deinitialize destroys every surviving host
  (many HOSTS per process are fine — the torrentxt single-session rule does
  NOT apply here).
- **THE LOSSLESS PARTIAL DRAIN** (this binding's one novel structure):
  enx_poll encodes serviced events into the caller buffer; one that no longer
  fits goes into the host's ONE-SLOT STASH and the pump STOPS — unserviced
  events stay inside ENet, the stash goes first next poll. Lossless and
  ordered at ANY buffer size (pinned by the smoke test's keyhole scenario);
  no bounded queue or overflow accounting needed because WE decide when
  events materialize.
- **Handle lifecycle**: born in enx_connect (outgoing) or at the drain that
  writes an incoming peer's E_CONNECT (the announcing event carries the
  newborn handle); the int handle rides ENetPeer.data as a backlink; retired
  when E_DISCONNECT drains (polite) or immediately on disconnect_now/reset
  (ENet defines those as locally event-less).
- **Packet ownership** (ENet's contract, kept everywhere): create COPIES
  bytes in (never NO_ALLOCATE); after a successful send the host owns the
  packet (but a REFUSED enet_peer_send leaves it ours — destroy it); on
  receive, copy out THEN destroy before the drain returns.
- The 60000-byte budget is enforced both ways: sends refuse with -4;
  oversized inbound drops WHOLE with an E_ERROR event.
- Registries (enx_record.h): 15 field ids, 4 event codes, 10 peer states
  (static_asserted to mirror ENetPeerState — NOTE the real enum spells it
  ENET_PEER_STATE_ACKNOWLEDGING_DISCONNECT), 3 send flags (OUR enum: 0
  reliable / 1 unreliable / 2 unsequenced — ENet's raw bits would make the
  safe default a magic number). APPEND-ONLY; adding one bumps the ABI.

## Building

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENETXT_BUILD_TESTS=ON
cmake --build build --parallel && ctest --test-dir build --output-on-failure
cmake -S . -B build-asan -DENETXT_BUILD_TESTS=ON -DENETXT_SANITIZE=address
cmake --build build-asan --parallel && ./build-asan/enet_smoke_test
```

gcc for the sanitizer lane (clang's runtimes are not installed in this
environment). A shim change is "done" only with the smoke test green under
ASan/UBSan.
