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
7. **A window may give back only the ENet holds it took** (fixed in `tests/enet-selftest`
   2026-09-26; the suite work plan's enetxt #4). The shim's init count is process-wide, so
   an `enDeinitialize` with no `enInitialize` of this stack's behind it takes ANOTHER
   window's hold, and the one that reaches zero destroys that window's hosts. The harness
   took two holds per run, gave back two in `stFinish` (the second, labelled "extra
   deinitialize is a no-op 0", was in fact the call that reached zero), then gave back a
   third, bare, in `stCleanup` on every close and every Re-run: beside the suite paste's
   cross row or a chat demo, that ended their hosts (an interpreter probe read the count
   1, 3, 1, 0). It now counts its holds in `sStEnHeld` through `stEnInit` / `stEnRelease`,
   the suite paste's `suEnInit` / `suEnRelease` pattern: `stFinish` gives back exactly the
   run's two, `stCleanup` only what a live run still holds (none at rest), a refused init
   counts none. The no-op leg (`stEnNoOpLeg`) calls only where the shim has just refused a
   probe host with "call enInitialize first", i.e. at a process count of zero; beside
   another ENet window it destroys its probe host and SKIPs. The chat demos had the defect
   too, which the enetxt #4 row had missed (it said their only unpaired path was a
   re-fired `openStack`, a leak that harms no other window): `ecStart` / `eiStart` exited
   on a REFUSED `enInitialize`, but `ecStop` / `eiStop` called `enDeinitialize` on every
   close, so a close after a refusal (or with the start never reached, or a second close)
   gave back another window's hold and ended its hosts. Since 2026-09-27 (the fix's review)
   each takes at most ONE hold, flagged by `sHaveEn`: a re-fired `openStack` keeps the one
   it has, and the stop gives back only that one and lowers the flag first. The suite's
   `tools/check-transport-holds.py` drives the harness and both demos beside a modelled
   other window (its fixture plants each old line back and fails); verified statically and
   headlessly; needs an OXT pass. The fold into the suite paste routes `stRun`'s two
   `stEnInit` calls to the paste's own counted `suEnInit` instead.

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
| 2026-09-24 | OXT, Windows (the engine reports Win32), a 2026-09-12 DLL by the maintainer's account (its first engine load), 64-bit by the same account (given 2026-09-26, after this row said "bitness not recorded"), so the `x86_64-win32` one; OXT version and OS build not recorded | the D-23 suite paste (built from `9aa62c8`; this member as at `6401e43`) | 2620 / 5 / 3; enetxt 34/34 folded (lifecycle, stale handles, the helper dispatcher, tuning + abrupt teardown), no skips; the core's loopback bound 127.0.0.1:27196 and took an `enConnect` handle (6/6), then stalled in `connecting` to the 40 s deadline, as datachannelxt's did in `opening`; both loopbacks also stalled on 2026-08-27, whose phases and machine were not recorded (the suite runbook's trap 5.5, suspected environment; UDP loopback not yet tested independently on this machine). The day's second run (8:41 PM) read the same, line for line; `enSend` refused 60001 bytes with -4; `enHostDestroy` x2 and `enDeinitialize` returned 0; board row 41 / 1 / 0 (the 34, its merge line, the loopback's 6; the 1 is the deadline) |
| 2026-09-25 | OXT, Linux (box2dxt's lines print `the platform` as Linux); by the maintainer's account 64-bit Kubuntu 24.04 with the latest committed builds, so the `x86_64-linux` file of `421bab3` (release run 34657390798, 2026-09-12); the latest OXT (no version recorded) and no preflight, by the same account (given 2026-09-26) | the D-23 suite paste as regenerated at `f1346e0` (the tree at `cba3130`, PR #145; this member's folded code as on 2026-09-24, comments aside) | 2672 / 0 / 10; enetxt 34/34 folded, no skips (the same four sections); the core's live loopback COMPLETED on 127.0.0.1:27196: server bound, client created, an `enConnect` handle that the client's connect event names, the server seeing the connect data (7), the SodiumXT-sealed ciphertext delivered byte for byte and opened to the exact plaintext, 60001 bytes refused with -4 and a payload at the 60000-byte budget accepted and reassembled into ONE message, `enDisconnect` 0 and a graceful close (the server drained `enetDisconnect`); `enHostDestroy` x2 and `enDeinitialize` 0; board row 50/0/0. That `.so`'s first engine load, and the paste loopback's first recorded completion since 2026-08-20 (Windows; the 2026-08-24 paste's zero failures imply one more), after its stalls of 2026-08-27 and of all three 2026-09-24 runs (Windows, in `connecting`; the suite runbook's section 8 records the third). So the paste's loopback code completes on an engine, and the Windows stalls belong to that platform or machine (trap 5.5), which the standalone selftest there would tell apart. Gotcha 1's path (`enDisconnect` before connect) is not on this run's path: the loopback disconnects a connected peer, and the abrupt section uses `enDisconnectNow` and `enResetPeer`. By the maintainer's account (given 2026-09-26) the report is the launch's SECOND Run all, the first having run on open, so this `enInitialize returns 0` and the completed loopback came after the core's `stCleanup` (which every Run all runs first) had called `enDeinitialize` in the same process |
| 2026-09-25 (Windows; the Kit report's clock 10:54 PM local) | OXT, Windows (the engine reports Win32), by the maintainer's account the machine of the 2026-09-24 runs and 64-bit, so the `x86_64-win32` DLL, INFERRED to be the 2026-09-12 file (no Windows DLL committed since); no preflight (the same account: none on either machine); the OXT build and whether the report is a launch's first or second Run all not recorded | the same D-23 suite paste as the Linux run (INFERRED from the version lines both reports print: the board stamp `suite-board-1`, holde-em's "stack v0.25.5 harness v47" and riptide's third probe line) | 2653 / 2 / 10 (2665); enetxt 34/34 folded ("34 passed, 0 failed of 34 checks"), no skips; the core's loopback bound 127.0.0.1:27196 and took an `enConnect` handle (6/6), then stalled in `connecting` to the deadline ("UDP to 127.0.0.1 may be blocked"), one of the paste's two FAILs; `enSend` refused 60001 bytes with -4; `enHostDestroy` x2 and `enDeinitialize` returned 0; board row 41 / 1 / 0. That machine's FOURTH stall in `connecting` (2026-09-24 three times, 2026-09-25), the same day the same paste's loopback completed on Linux: the standalone selftest on that machine is still what tells its UDP loopback from the paste (trap 5.5) |
| 2026-09-26 (Linux; the Kit report's clock "Saturday, September 26, 2026 4:23 PM") | OXT, Linux (box2dxt's lines print `the platform` as Linux); by the maintainer's account the machine of the 2026-09-25 Linux run (64-bit Kubuntu 24.04, the latest committed builds, so the `x86_64-linux` file of `421bab3` again; "the latest" OXT, no version recorded, and whether it was the 2026-09-25 build not stated); a fresh stack, no preflight, and the report the launch's second Run all, taken with Copy results (the same account, given 2026-09-26) | PR #147's D-23 suite paste (INFERRED from the version lines the report prints, which exist together only in that batch: the board stamp `suite-board-0961bb91e5ee`, holde-em's "stack v0.25.6 harness v48" and riptide's fourth probe line; its head `2ec9594` carries the paste as last regenerated at `986769f`; this member's folded code as on 2026-09-25, comments aside, and the paste's ENet holds now COUNTED through the core's `suEnInit` / `suEnRelease`, the suite work plan's suite-wide #16) | 2876 / 0 / 10; enetxt 34/34 folded ("34 passed, 0 failed of 34 checks"), no skips; the core's live loopback COMPLETED on 127.0.0.1:27196 again, line for line as on 2026-09-25: server bound, client created, the `enConnect` handle the client's connect event names, the connect data (7), the SodiumXT-sealed ciphertext byte for byte and opened to the exact plaintext, 60001 bytes refused with -4 and 60000 accepted and reassembled into ONE message, `enDisconnect` 0 and a graceful close; board row 50/0/0. The loopback's second recorded completion on Linux, on the same machine by the account. The counted holds ran on an engine (OBSERVED, Linux): `enInitialize returns 0` through the counted init, and at teardown `enHostDestroy` x2 and `enDeinitialize` 0, with the core's line "one enDeinitialize for each of this run's 3 counted enInitialize calls, and no more". Again the launch's second Run all, so this init and the completed loopback followed the first run's release in the same process |
| 2026-09-26 (Linux; the suite's engine preflight, and the Kit report's clock "Saturday, September 26, 2026 5:11 PM") | OXT 9.7.0-dp-1 on Linux (OBSERVED in the preflight's engine block, with systemVersion `Linux 6.8.0-139-generic` and processor `x86_64`; INFERRED for the paste run reported with it); presumably the machine of the 4:23 PM run, so the `x86_64-linux` file of `421bab3` again (not stated for these two reports); for the paste run, its launch's on-open Run all and the only one in that launch, by the maintainer's account (given later that day: "5:11 was the on open run only"), and Copy results not stated | the suite's `tests/preflight.livecodescript`, its first Linux run; and the batch paste a second time (INFERRED from its version lines, the 4:23 PM run's) | Preflight: "enetxt loads; its ABI guard accepted the installed library (expects ABI 2)" PASS, LOADED at 2 by the guard's strict equality inside `enInitialize` (an INFERENCE, as the report says); `enInitialize` returned 0 (the probe prints its code only when it is not) and the probe balanced it with `enDeinitialize`. Its details line, OBSERVED: `enet 1.3.18`, from `enLibraryVersion()` (the shim formats ENet's own `enet_linked_version()`), the first ENet version on record from an engine; `CMakeLists.txt` pins v1.3.18, so the reading agrees with the pin. The paste: 2876 / 0 / 10, line for line the 4:23 PM report bar the Kit's clock line, four box2dxt joint handles and an image id, so enetxt 34/34 folded, the core's live loopback COMPLETED again (a third recorded Linux completion) and the counted teardown line again |
| 2026-09-26 (Windows; the suite's engine preflight, and the Kit report's clocks "Saturday, September 26, 2026 7:24 PM" and "7:28 PM", two paste runs) | OXT 9.6.3 on Win32 (OBSERVED in the preflight's engine block, with systemVersion `NT 10.0` and processor `x86_64`; INFERRED for the paste runs, whether they shared its launch not stated); by the maintainer's account (given after the pass) the machine of 2026-09-24 and 2026-09-25, a fresh stack, and the two paste runs ONE launch's on-open Run all and its second; so the `x86_64-win32` DLL, presumably the 2026-09-12 file (INFERRED: none committed since, and torrentxt's 997-byte refusals pass); Copy results not stated | the suite's `tests/preflight.livecodescript` (its first Windows run at the current ABIs), and the batch paste twice (INFERRED from its version lines: the board stamp `suite-board-0961bb91e5ee`, holde-em's "stack v0.25.6 harness v48" and riptide's fourth probe line; presumably main's at `a812580`; 2857 passed / 2 failed / 10 skipped each time, the 2 the live loopbacks) | Preflight: "enetxt loads; its ABI guard accepted the installed library (expects ABI 2)" PASS, LOADED at 2 by the guard's strict equality inside `enInitialize` (an INFERENCE, as the report says); its details line, OBSERVED: `enet 1.3.18`, the pin, as on Linux. The paste, both runs: enetxt 34/34 folded ("34 passed, 0 failed of 34 checks"), no skips; the core's loopback bound 127.0.0.1:27196 and took an `enConnect` handle (6/6), then stalled in `connecting` to the deadline ("UDP to 127.0.0.1 may be blocked"), one of the paste's two FAILs each time: that machine's fifth and sixth stalls in that phase (the suite runbook's 5.5 and the suite work plan's suite engine #9); `enSend` refused 60001 bytes with -4; board row 41 / 1 / 0. The counted holds ran on Windows (OBSERVED): `enInitialize returns 0` through the counted init and, at teardown, `enHostDestroy` x2 and `enDeinitialize` 0 with the core's line "one enDeinitialize for each of this run's 3 counted enInitialize calls, and no more", in both runs, the second in the same process after the first run's release |
| 2026-09-26 (Windows; the standalone harness, the same evening) | OXT on Windows, the machine of the pass by the maintainer's account (one machine named for the whole post; whether this shared the paste's launch not stated), so presumably the `x86_64-win32` DLL the preflight LOADED at 2 | `tests/enet-selftest.livecodescript` standalone (its report's lines are the file's since 2026-08-20, `4a7cf43`, so which version was pasted cannot be told: presumably main's) | **68 passed, 0 failed, 0 skipped**, no `RUN NOT FINISHED` trailer: lifecycle and diagnostics (4), the stale-handle no-ops (9), the poll dispatcher library (13), tuning and the abrupt teardown with nothing listening on 27099 (8), and the async section "loopback: hosts + connect (async)" COMPLETE (27) on 127.0.0.1 (port 27098 by the file; the report does not print it): both hosts, the peer handle, the -3 and -4 send refusals, the client's connect event naming the `enConnect` handle and the server's carrying data 42 with an address, the hello intact, the server's echo on channel 0 and broadcast on channel 1, the peer connected (5) naming the server port with rtt, loss and send counters, both live `enHostStatus` readings, the tuning setters, binary byte-for-byte including a NUL, `enDisconnect` 0 and the server's disconnect event carrying data 7; then retirement and teardown (7): the client peer retired, zero peers counted, `enHostDestroy` x2 and the double destroy 0, `enDeinitialize returns 0` and "extra deinitialize is a no-op 0". The first standalone record naming its platform (2026-08-07 and 2026-08-13 named none), and, if main's file and the preflight's DLL ran (both presumed, INFERRED), the first since the `sEnPolling` rename and on the 2026-09-12 binaries. So this member's own async ENet loopback COMPLETES on this Windows engine, where the suite paste's stalled in both of the evening's runs: what that tells apart is the suite runbook's 5.5 and work plan suite engine #9's to record. It closed the work plan's enetxt engine #1 |

## Status

The whole `en*` surface is engine-proven (standalone async 2026-08-13, and again on Windows
on 2026-09-26, 68/0/0; the sync half folded through 2026-09-26, on Windows and Linux). The
core's live loopback stalled on 2026-08-27 (its phase not recorded) and in `connecting` in all
three of 2026-09-24's runs, again on 2026-09-25 and twice on 2026-09-26 (Windows, the same
machine each time, by the maintainer's account; blocked UDP to 127.0.0.1 was suspected until
2026-09-26, when this member's standalone `enet-selftest` COMPLETED its own async loopback on
127.0.0.1 on that machine, 68/0/0 (the ledger): the suite runbook's 5.5 and work plan suite
engine #9), and COMPLETED on Linux
x86_64 on 2026-09-25 and again on 2026-09-26 (the same machine, by the maintainer's account): connect, the sealed ciphertext, 60000 bytes reassembled into one
message, a graceful disconnect. So the paste's loopback code works on an engine, and the
Windows stall is, INFERRED, the paste's own pump (its deadline armed ahead of the arm-time render and the window's first layout, what took the time there not yet known; fixed
2026-09-27, verified statically; needs an OXT pass on Windows: the suite runbook's 5.5), not the
machine's UDP. The 2026-09-24 and 2026-09-25 Windows
pastes ran on the 2026-09-12 `x86_64-win32` DLL and the 2026-09-25 Linux paste on the
2026-09-12 `x86_64-linux` file (the maintainer's account: 64-bit OXT on both, the latest
builds; the 2026-09-25 Windows DLL INFERRED the same, the ledger), each file's first engine
load, but their one shim change since 2026-08-27 (gotcha 1's fix) is on a path none of their
checks reached: the fix is driven natively by the smoke test (2026-09-24, ASan/UBSan), not by
an engine. Still un-exercised: the LAN chat demo
between two real machines (runbook row 6, S3 item 6), the closing pass's separate enet leg B
(S3 item 1), `enet-internet-chat` across two networks (verified statically; needs a
two-machine, two-network OXT pass), a standalone re-run carrying the counted holds of gotcha
7 (2026-09-26: verified statically and headlessly; needs an OXT pass; the 2026-09-26 Windows
run was the harness before them), the chat demos' one-hold start and stop (gotcha 7,
2026-09-27: verified statically and headlessly; needs an OXT pass), and any Mac engine load.
Open work: the suite's docs/WORK-PLAN.md.

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
