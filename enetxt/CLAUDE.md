# CLAUDE.md

Guidance for Claude Code in the ENetXT member of the xtalk-suite monorepo (`enetxt/`). Where
anything disagrees, the code, `docs/api-reference.md` and this file win; `docs/architecture.md`
is the design authority.

## What this is

**enetxt** binds ENet v1.3.18 (MIT, reliable UDP) for OXT: ENet (static, PIC) -> the C++ shim
`src/enet_shim.cpp` (exports `enx_*`, **ABI 2**: `ENX_ABI_VERSION` in `src/enx_abi.h` equals
`kABIVersion` in `src/enet.lcb`) -> ONE library `enetxt.{so,dll,dylib}` (bare token) -> the LCB
binding `src/enet.lcb` (`org.openxtalk.library.enet`, 23 public `en*` over 22 bound `enx_*`)
-> the pump `examples/enet-helpers.livecodescript`. The full binding is built.
Layout: `src/` (shim, headers, `enx_handle_table.h` carried verbatim, `enetxt.map`, `enet.lcb`,
`code/` with `MANIFEST.sha256`); `tests/` (smoke, handle and golden tests, the OXT harness);
`examples/` (helpers, two chats); `tools/` (`run-gates.sh` and its gates,
`package-extension.py`); `docs/`.

## The rules

The shim cites these by number; keep the numbering.

1. **Never call script from a foreign thread - here, PUMP OR NOTHING.** ENet has no threads,
   so nothing connects, sends or receives unless `enet_host_service` runs. `enx_poll` loops
   `enet_host_service(host, &e, 0)` until 0 each tick; its cadence is the latency floor
   (16-33 ms for real-time feel).
2. **The exception firewall.** Every `enx_*` body runs inside `ENX_GUARD_*` (`src/enx_abi.h`):
   one declaration per line inside a guard body (the macro-comma trap), and no preprocessor
   directive inside one (gcc tolerates it, MSVC rejects it with C2121; hoist into a helper).
3. **Payload crosses by design, but ENet is not for files** (bulk is TorrentXT's).
   `enet_packet_create` COPIES in (never NO_ALLOCATE); after a successful `enet_peer_send` the
   host owns the packet, but a REFUSED send leaves it ours - destroy it; on receive copy the
   bytes out THEN `enet_packet_destroy`, before the drain returns. Never hand script a pointer
   into ENet memory.
4. **A shim change is done when `enet_smoke_test` is green under ASan/UBSan** (gcc; clang's
   runtimes are not installed here). A native-library change refreshes the committed binary
   (`tools/package-extension.py`) AND its `MANIFEST.sha256` line in one change; the suite's
   hand-dispatched `release-binaries.yml` does both; `native-enetxt.yml` never commits.
5. **Registries are APPEND-ONLY; an ABI change bumps `ENX_ABI_VERSION` and `kABIVersion`
   together** (`tools/check-record-registry.py` proves the `.lcb` mirror).
6. **Script is done when `tools/check-livecodescript.py` passes**, and stays "verified
   statically; needs an OXT pass" until an engine runs it. Kit fixes go in the suite master
   `tools/ui-kit.livecodescript`, never a demo; edit `enet-helpers` and re-run the suite's
   `tools/sync-demo-embeds.py`, never inside the sentinels.

## As built

- ENet via FetchContent, headers SYSTEM; `CMAKE_POSITION_INDEPENDENT_CODE ON` must sit BEFORE
  FetchContent (non-PIC static ENet cannot link into the shared lib; ld only says "bad
  value"). `ENETXT_SANITIZE` is the GLOBAL sanitizer knob, injected before FetchContent so
  ENet is instrumented; "address" is the lane that matters; NO TSan lane (threadless).
- `enet_initialize`/`deinitialize` are process-global: the shim refcounts them and the FINAL
  `enDeinitialize` destroys every surviving host. Many hosts per process are fine
  (torrentxt's one-session rule does not apply).
- **Lossless partial drain**: an event that no longer fits the caller buffer goes into the
  host's ONE-SLOT STASH and the pump STOPS; the rest stay inside ENet and the stash goes
  first next poll. Lossless and ordered at ANY buffer size (the smoke test's keyhole
  scenario), with no bounded queue, because WE decide when events materialize.
- **Handles**: born in `enx_connect` (outgoing) or at the drain that writes an incoming peer's
  E_CONNECT (the event carries the newborn handle); the int rides `ENetPeer.data` as a
  backlink; retired when E_DISCONNECT drains, or at once on `disconnect_now`/`reset`.
- 60000-byte budget both ways: sends over it return -4; oversized inbound drops WHOLE with an
  E_ERROR event.
- Registries (`src/enx_record.h`): 15 field ids, 4 event codes, 10 peer states
  (static_asserted against ENetPeerState, whose real spelling is
  `ENET_PEER_STATE_ACKNOWLEDGING_DISCONNECT`), 3 send flags as OUR enum 0 reliable /
  1 unreliable / 2 unsequenced (ENet's raw bits would make the safe default a magic number).
- Only `enx_*` is exported (22 bound + the `enx_selftest_throw` firewall hook): `src/enetxt.map`
  for GNU ld/lld, and a derived `-exported_symbols_list` for ld64, which has no
  `--version-script` (2026-08-26; release run 10 measured 70 leaked ENet names). Committed
  copies are `strip --strip-unneeded`.
- The helper pump guards BOTH the `enPoll` drain and each dispatch and records the first
  failure in `enPollLastError()` (cleared only by bare `enPollClearError`).

## Gotchas and traps

1. **`enx_disconnect` leaked the handle from every pre-connect state** (fixed 2026-09-09,
   `23a2914`). Per enet 1.3.18 `peer.c`, `enet_peer_disconnect` does NOTHING from
   DISCONNECTING / DISCONNECTED / ACKNOWLEDGING_DISCONNECT / ZOMBIE, moves to DISCONNECTING
   only from CONNECTED or DISCONNECT_LATER, and from every other state (CONNECTING included,
   where `enx_connect` leaves a peer) does `enet_host_flush` + `enet_peer_reset`, queuing no
   event and leaving the peer DISCONNECTED. So the fix tests the POST-call state: DISCONNECTED
   owes nothing, retire now; anything else owes an event and the drain retires it.
   `retire_peer` is idempotent, so racing the drain is harmless. Driven since 2026-09-24 by
   `enet_smoke_test`'s CONNECTING block: a dead port, no poll, the precondition that the
   peer really is CONNECTING, then the retire at the call, `ENX_ERR_STALE`, no event, and
   cancel-and-retry on a one-peer host where a leaked handle would have aliased the retry's
   live peer. Green under ASan/UBSan; reverting the fix fails four of its checks.
2. **An EMPTY handle into `enHostDestroy` (`in pHost as Integer`) THROWS** and silently kills
   the poll chain (suite engine note 6.4). Guard every handle-clearing path; the suite's
   `tools/check-lcb-call-types.py` checks the boundary.
3. **`the number of keys of X` does not parse**: write `the number of lines of the keys of X`
   (engine note 1.7).
4. **The kit defaultStack pin (engine note 5.3) did not fix that dashboard throw**: an
   argument is evaluated in the CALLER and never reaches the pinned handler (why 5.3 is
   classed DOCUMENTED, not OBSERVED).
5. **Helper script-locals carry the member stem** (`sEnPolling`, `sEnPollTarget`,
   `sEnPollInterval`, `sEnPollNote`, renamed 2026-08-23): datachannel's helpers declared the
   same four, and two libraries sharing a column-0 name cannot be co-embedded (engine note
   1.6); the suite's `tools/check-cross-library-names.py` holds them disjoint.
6. **`enet-internet-chat`**: ENet has no NAT traversal, so the HOST runs a TorrentXT session
   only for `btMapPort(session, port, port, FALSE)` (FALSE is load-bearing: a TCP mapping
   tests green while every UDP packet drops) and public-IP discovery via `externalIp` (rides
   DHT traffic, hence the bootstrap nodes). Invite is ip:port; a joiner needs only enetxt;
   both poll dispatchers are co-embedded. The pill reads INTERNET LIVE only for a remote
   outside RFC 1918 / loopback / link-local (truth table in the boot self-check). On ONE
   network it cannot connect: most routers refuse to hairpin the public-IP invite
   (engine-reported 2026-08-27; the watchdog's cause 5).

## Engine evidence ledger

| Date | Engine / platform | What ran | Result |
|---|---|---|---|
| 2026-08-07 | OXT (platform not recorded) | `tests/enet-selftest.livecodescript` | green, all tests; retired the `MCStringEncode` first-runtime-use flag (the `enSendText` legs exercise it) |
| 2026-08-08 | OXT, suite paste | cross-member leg and the budget | a SodiumXT-sealed ciphertext crossed a live ENet loopback byte-for-byte; `enSend` refused 60001 bytes with -4, accepted 60000, and ENet reassembled all 60000 into ONE message |
| 2026-08-10 | OXT, suite paste (folded) | sync half incl. the isolated teardown section | 21/21, twice; `enDisconnectNow`, `enResetPeer`, `enSetPeerTimeout`, `enSetHostBandwidth` returned 0 on a live client host |
| 2026-08-13 | OXT (platform not recorded) | `enet-selftest` standalone, async loopback | green end to end: live `enHostStatus` pair (connected, then zero peers), `enPeerStatus` rtt / packetLoss / counters, echo / broadcast / binary, graceful close |
| 2026-08-17 | OXT 9.6.3, Windows x86_64, NT 10.0 | suite paste (preflight: enetxt LOADED at ABI 2) | enetxt 21/21 folded; paste 1,836 folded / 0 failed / 7 skipped |
| 2026-08-18 | OXT, Linux, ONE machine | `examples/enet-lan-chat.livecodescript`, first run | gotchas 2 and 3 found and fixed; maintainer reported single-machine host/join chat working after the fixes (environment not captured) |
| 2026-08-20 | OXT, Windows | suite paste, whole run | 1981 / 0 / 1; enetxt 34 folded (21 plus, by count, the 13 helper-section assertions); the core's ENet loopback delivered, 60000 budget checked, hosts released |
| 2026-08-24 | OXT 9.6.3, Windows x86_64, NT 10.0 | suite paste | 2,373 / 0 / 3 deliberate skips (enetxt's own count not recorded) |
| 2026-08-27 | CI, no engine | `release-binaries.yml` run 12 (`cec1e85`) | first `universal-mac` dylib committed (both slices); all five platforms pinned |
| 2026-08-27 | OXT, two-machine session (platform not recorded) | suite paste; `enet-internet-chat` on one network | 2440 / 2 / 3, every folded member green (the renamed helper locals ran folded); the 2 failures were the core's loopbacks on a machine blocking UDP to 127.0.0.1 (environment: the suite runbook's trap 5.5); internet chat correctly could not connect (gotcha 6) |
| 2026-09-12 | CI, no engine | `release-binaries.yml` run 34657390798 (`421bab3`) | every platform rebuilt from a tree containing `23a2914`; the x86_64 `.so` disassembly shows the gotcha-1 retire path |
| 2026-09-24 | OXT, Windows (the engine reports Win32), a 2026-09-12 DLL by the maintainer's account (its first engine load); OXT version, OS build and bitness not recorded | the D-23 suite paste (built from `9aa62c8`; this member as at `6401e43`) | 2620 / 5 / 3; enetxt 34/34 folded (lifecycle, stale handles, the helper dispatcher, tuning + abrupt teardown), no skips; the core's loopback bound 127.0.0.1:27196 and took an `enConnect` handle (6/6), then stalled in `connecting` to the 40 s deadline, as datachannelxt's did in `opening`; both loopbacks also stalled on 2026-08-27, whose phases and machine were not recorded (the suite runbook's trap 5.5, suspected environment; UDP loopback not yet tested independently on this machine). The day's second run (8:41 PM) read the same, line for line; `enSend` refused 60001 bytes with -4; `enHostDestroy` x2 and `enDeinitialize` returned 0; board row 41 / 1 / 0 (the 34, its merge line, the loopback's 6; the 1 is the deadline) |

## Status

The whole `en*` surface is engine-proven (standalone async 2026-08-13; the sync half folded
through 2026-09-24, on Windows). The core's live loopback stalled on 2026-08-27 (its phase
not recorded) and in `connecting` in both of 2026-09-24's runs (suspected blocked UDP to
127.0.0.1, the suite runbook's trap 5.5; the 2026-09-24 machine is not yet tested
independently). That paste ran on a 2026-09-12 Windows DLL (the maintainer's account; its
bitness not recorded), those binaries' first engine load, but their one shim change since
2026-08-27 (gotcha 1's fix) is on a path none of its checks reached: the fix is driven
natively by the smoke test (2026-09-24, ASan/UBSan), not by an engine. Still un-exercised:
the LAN chat demo between two real machines (runbook row 6, S3 item 6), the closing pass's
separate enet leg B (S3 item 1), `enet-internet-chat` across two networks
(verified statically; needs a two-machine, two-network OXT pass), a standalone async re-run
on the current binaries, and any Mac engine load. Open work: the suite's docs/WORK-PLAN.md.

## Build and gates

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENETXT_BUILD_TESTS=ON
cmake --build build --parallel && ctest --test-dir build --output-on-failure
cmake -S . -B build-asan -DENETXT_BUILD_TESTS=ON -DENETXT_SANITIZE=address
cmake --build build-asan --parallel && ./build-asan/enet_smoke_test
bash tools/run-gates.sh     # this member's gate list (what CI runs)
```

Windows, the universal mac build and packaging: `docs/building.md`. Engine behaviour goes in
the suite's docs/OXT-ENGINE-NOTES.md. Comment the why, densely; per-task branch, draft PR.
