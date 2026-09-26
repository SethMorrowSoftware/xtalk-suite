# CLAUDE.md

Guidance for Claude Code in the DataChannelXT member of the xtalk-suite monorepo
(`datachannelxt/`). `docs/architecture.md` is the design authority and
`docs/api-reference.md` the public surface; this file holds the working rules, the traps
and the engine record. Engine BEHAVIOUR (as opposed to this member's conventions) lives in
the suite's docs/OXT-ENGINE-NOTES.md, cited below as "engine note N.N".

## What this is

**DataChannelXT** brings WebRTC data channels to OXT: browser-interoperable,
NAT-traversing (ICE/STUN/TURN), reliable and unreliable peer-to-peer messaging from
script. It binds libdatachannel v0.24.5 (C++17, MPL-2.0; vendored libjuice for ICE, usrsctp
for SCTP, plog; DTLS from the system OpenSSL; `NO_MEDIA` and `NO_WEBSOCKET` by decision):

```
libdatachannel + libjuice + usrsctp (+ OpenSSL)   owns the network threads
   |- C++ shim     src/datachannel_shim.cpp  ->  datachannelxt.{so,dll,dylib}  (ABI: dcx_*, DCX_ABI_VERSION 1)
        |- LCB binding  src/datachannel.lcb       (library org.openxtalk.library.datachannel; 31 public dc*)
             |- script helpers  examples/datachannel-helpers.livecodescript  (the poll dispatcher)
```

The library ships bundled under `src/code/<arch>-<platform>/datachannelxt.{so,dll,dylib}`
(bare token, no `lib` prefix; ids `x86_64-linux`, `x86-linux`, `x86_64-win32`,
`x86-win32`, `universal-mac`; all five committed and pinned in `src/code/MANIFEST.sha256`).

Layout: `src/` (shim, `dcx_abi.h`, `dcx_record.h` registries, `dcx_handle_table.h`,
`datachannelxt.map` export filter, the `.lcb`, `code/`); `tests/` (C++ smoke, orphan-channel
and handle tests, record golden, TSan suppressions, the OXT harness
`datachannel-selftest.livecodescript`, and the browser-interop pair `browser-peer.html` +
`datachannel-browser-peer.livecodescript`); `examples/` (helpers, `datachannel-loopback`, the
flagship `datachannel-dht-chat`); `tools/` (`run-gates.sh` and its gates,
`package-extension.py`); `docs/` (the four references and `browser-interop.md`).

## Rules

Code comments cite rules 1-3 by number; keep them.

1. **Never call an LCB handler from a libdatachannel thread.** This is the family's rule 1
   at its worst case: every callback fires on libdatachannel's own workers. A callback body
   only takes `g_mu`, pushes an OWNED copy onto the bounded queue, and releases; `dcPoll`
   (`dcx_poll`) drains on the script thread. The mutex-guarded queue is the most important
   correctness structure here, and the TSan lane exists to police it.
2. **The exception firewall, in BOTH directions.** Every `dcx_*` entry point runs inside
   `DCX_GUARD_*`, and every CALLBACK body has its own `try/catch(...)`, so nothing (a
   `bad_alloc` copying a payload) unwinds into the engine or into libdatachannel's thread.
3. **Payload crosses by design, but bounded.** `DCX_MAX_MESSAGE` is 60000 bytes both ways:
   sends over it are refused with `DCX_ERR_TOO_LARGE` (-4), never truncated or split; the cap
   is advertised in the SCTP negotiation; a misbehaving remote's oversized message is dropped
   WHOLE with an error event. Bulk transfer is TorrentXT's job.
4. **Never call an `rtc*` function while holding `g_mu`.** `rtcDeletePeerConnection` /
   `rtcDelete` block until in-flight callbacks return, and callbacks block on `g_mu`, so entry
   points lock, validate/copy, UNLOCK, then call `rtc*` (an ABBA deadlock was watched under
   gdb). Callbacks may call cheap rtc getters/setters but take `g_mu` only for the enqueue.
5. **Clear every callback before every delete** (`clear_peer_callbacks` /
   `clear_channel_callbacks`). capi.cpp drops the last reference under its global map mutex; a
   still-connecting PeerConnection's destructor then fires the state callback inline, whose
   wrapper re-takes that non-recursive mutex - a self-deadlock inside the dependency,
   reproduced under gdb at `rtcCleanup`. The guard lives in `dcx_peer_free`,
   `dcx_channel_free` and `dcx_cleanup`; keep it on any new teardown path.
6. **A shim change is done when the smoke test is green under ASan/UBSan AND TSan** (gcc
   only; clang's sanitizer runtimes are not installed here). `tests/tsan-suppressions.txt`
   may only name races wholly inside a vendored dependency (today `race:sctp_`); a report
   with a `datachannel_shim.cpp` frame among the racing accesses is ours and must be fixed.
7. **A `.lcb` change is done when** `tools/check-livecodescript.py` and
   `tools/check-record-registry.py` pass AND the suite gate `tools/check-lcb-call-types.py`
   passes (run from the suite root by `tools/build-all.sh --gates`; it types the script ->
   `.lcb` boundary and refuses an event name that collides with a public handler).
8. **An ABI change bumps `DCX_ABI_VERSION` and `kABIVersion` together.** `_checkABI()`
   throws on skew; `check-record-registry.py` proves the header/`.lcb` match, the registries
   and the return-code numbering. Registries are APPEND-ONLY.
9. **A native change refreshes the committed binary (`tools/package-extension.py`) and its
   `src/code/MANIFEST.sha256` line in the same change**; the suite's human-dispatched
   `release-binaries.yml` does both. `native-datachannelxt.yml` uploads artifacts only.
10. **Do not claim runtime behaviour you cannot observe.** Anything not seen on an engine is
    "verified statically; needs an OXT pass". This is policy, not a status label.
11. **Carried code has one master.** Edit `examples/datachannel-helpers.livecodescript` and
    re-run the suite's `tools/sync-demo-embeds.py` (and `tools/build-suite-selftest.py`, since
    the selftest is a suite-paste source); never edit inside the embed sentinels. The UI kit
    and boot self-check blocks are changed in their suite masters, never in a demo.

## Contracts that must hold

- **Event ordering** (pinned by the smoke test): `E_CHANNEL_INCOMING` always precedes that
  channel's `E_CHANNEL_OPEN` - it is enqueued in the SAME locked section that births the
  handle, before the open callback is wired and before the already-open fallback check. The
  drain never reorders or drops an accepted event; an event naming a since-freed handle is
  discarded AT DRAIN TIME. The queue is bounded (65536 events / 32 MiB): overflow sheds the
  NEWEST, counts them, and reports `E_QUEUE_OVERFLOW` once the backlog drains. Invariant:
  delivered + reported-shed == sent.
- **Handles**: positive 32-bit ints (0 invalid), generation-tagged, one table for peers and
  one for channels; a stale handle is a harmless no-op. libdatachannel's own C-API ints are
  NOT generation-tagged, so they are never exposed: the shim maps rtc id <-> our handle and
  events carry OUR ids, re-validated at drain.
- **FFI types**: reals as `double`, booleans as `int` 0/1; the `dcx_` prefix is never renamed
  (the `.lcb` binds name the strings). Byte buffers cross as `Pointer` + `CInt` length (an LCB
  `Data` does NOT auto-bridge to `void*`): out-buffers via `MCMemoryAllocate` + bytes-written
  / `-needed` grow-and-retry, in-buffers via `MCDataGetBytePtr`; `<builtin>` handlers carry
  no leading `_`. No 64-bit foreign int (use decimal `ZStringUTF8` if one is ever needed);
  short strings cross as `ZStringUTF8`.
- **The getter -1 caveat**: `dcx_peer_state`, `dcx_gathering_state`, `dcx_channel_stream_id`,
  `dcx_buffered_amount` and `dcx_channel_max_message` return -1 for "no value / bad handle"
  because 0 is a real value for each.
- **Record schema** byte-identical to TorrentXT's: `[count:u16]` then
  `[fieldId:u8][type:u8][len:u16][bytes]`, big-endian; drain entries
  `[type:u16][bodyLen:u16][kvrecord]`. `record_golden_test.py` and `record_handle_test.cpp`
  pin the same literal bytes.
- **Exports**: only `dcx_*` (plus the C++-mangled `dcx::test::*` smoke-test hooks):
  `src/datachannelxt.map` for GNU ld/lld, an `-exported_symbols_list` derived from it for
  ld64, and a generated `.def` of undecorated names for MSVC. The `dcx::test::seam_*` hooks
  and the state behind them compile only under `DCX_TEST_SEAMS`, into the test-only
  `datachannelxt_seams` library (CMakeLists, test build); the shipped `datachannelxt` never
  has them, so its export table and ABI do not move. A seam makes ONE real condition true at
  the point the production code tests it; add one only for a path no public call can reach.
- **Adding a handler**: `dcx_*` in the shim (validate the handle; `DCX_GUARD_*`; rules 4-5)
  -> `private foreign handler` + public `dc*` wrapper -> check the public name collides with
  no name `_eventName` can return, and a new EVENT name with no public `dc*` handler (script
  gotcha 11) -> the MSVC `.def` list in CMakeLists -> bump the ABI -> a smoke-test assertion
  -> rebuild and `tools/package-extension.py` in the same change.
- **Performance**: one FFI round-trip per poll (`dcPoll` drains everything); poll at 16-33 ms;
  the interval is a latency knob, never a correctness knob; reuse the persistent buffers
  (`sDrainPtr` / `sScratchPtr`); UI text at most ~4 Hz and only on change; backpressure via
  `dcBufferedAmount` + `dcSetBufferedLowThreshold` + `dcBufferedLow`, never blasting.
- **The WebRTC model every demo must convey** (walked in `docs/getting-started.md` section 3):
  signaling is the app's job - ship each `dcLocalDescriptionReady` / `dcLocalCandidate`
  payload over ANY channel, feed the far side's into `dcSetRemoteDescription` /
  `dcAddRemoteCandidate`, wait for `dcChannelOpen`; non-trickle ships
  `dcLocalDescription(peer)` as ONE blob once gathering completes. TURN credentials ride in
  the ICE-server URI and are secrets in ordinary memory.

### The flagship, `examples/datachannel-dht-chat` - decisions that must hold

1. **The room code IS the keypair seed.** `btDhtKeypair` is deterministic on a 64-hex seed,
   so the code is a shared write-capability for one DHT mailbox (salts "wx-o"/"wx-a" split
   the slots). Codes are minted fresh per Host click, so stale DHT leftovers never belong to
   the current room. Documented, not solved: whoever knows a code can read the SDP blobs,
   which contain IPs.
2. **Non-trickle only** - a DHT round-trip is seconds; publish ONE blob per side after
   gathering completes.
3. **The 1000-byte BEP44 budget** sets the wire format: head `"DXC1" & kind & rest`; kind
   "D" = zlib(body) inline, kind "C" = a comma list of 40-hex immutable-chunk targets
   (content-addressed, so integrity is free). Body = `nonce LF type LF sdp`, split on the
   FIRST TWO LFs only (the SDP is full of line breaks).
4. **The nonce pairs answer to offer**; both sides dedup/reject on it, which makes Reconnect
   under the same code safe while stale items linger for hours.
5. **The demo depends on TorrentXT's EXTENSION, never its example files**: the bt poll loop is
   inlined, and both extensions are probed at startup with guarded calls that fail closed.
6. **One standing timer chain per loop**, armed once, rescheduling first, no-oping by phase;
   arming per user action stacks duplicate chains that double every poll and republish.

## Gotchas and traps

### C++

1. **The macro-comma trap**: `std::vector<int> a, b, c;` at the top level of a `DCX_GUARD_*`
   body splits the macro's arguments ("passed 3 arguments"). One declaration per line.
2. **`*/` inside a C comment ends it**: narrating "rtcDelete*/rtcCleanup" or "PS_*/GS_*"
   turned prose into code. Spell it "rtcDelete and rtcCleanup" / "PS_ and GS_".
3. **libdatachannel buffer getters count the NUL** (`copyAndReturn` returns size+1; probe with
   NULL first). Our ABI hides the +1.
4. **`rtcSendMessage(id, data, size)`: size >= 0 is binary, size < 0 is a NUL-terminated
   TEXT message** (what a browser sees as text). `dcx_send_text` passes -1; do not "fix" it.
5. **Messages with no callback set are buffered and FLUSHED when one is set**
   (`Channel::onMessage -> flushPendingMessages`), which makes `register_channel`'s wiring
   window lossless. Verified in the pinned tag's source; re-verify on a version bump.
6. **`juice: UDP socket creation failed, errno=97`** on an IPv6-less container is
   EAFNOSUPPORT; it then works over IPv4. Harmless.
7. **A remote-initiated channel is BORN inside `cb_data_channel`** (libdatachannel already
   holds it with an open SCTP stream), so an early return there abandons a live object. The
   peer-already-freed and handle-table-full exits leaked it until 2026-09-09 (`23a2914`;
   shipped in the 2026-09-12 binaries). A callback may not `rtcDelete*` (rule 5's
   self-deadlock), so both exits hand the id to `orphan_channel` -> `g_orphanChans` ->
   `reap_orphan_channels` on the script thread, as `dcx_channel_new` / `_ex` already delete on
   a `register_channel` failure. `orphan_channel` takes `g_mu` itself, so at the first exit it
   must run after the peer-lookup block has released it. Driven since 2026-09-24 by
   `tests/orphan_channel_test.cpp` (the seam build above): each exit parks exactly one rtc id,
   the next `dcx_poll` deletes it, and the far end sees `E_CHANNEL_CLOSED`. Green under
   ASan/UBSan and TSan; reverting either exit to a bare return fails it, because the far
   channel then never closes.

### Script (LCS / LCB)

Numbered as cited elsewhere in the suite (the suite's `tools/check-lcb-signatures.py` cites 9).

1. **ASCII only** - smart quotes fail OXT compilation (engine note 1.4).
2. **No name whose full spelling lowercases to a reserved token** (`tExt` == `text`; engine
   note 1.5). The checker flags them.
3. **Prefixes**: `t` local, `p` parameter, `s` script-local, `k` constant; public API
   `dcPascalCase`, C ABI `dcx_snake_case`.
4. **Constants are literal and declared before first use** (engine note 1.3).
5. **`unsafe ... end unsafe` brackets every foreign call; all declarations at handler top**
   in `.lcb`.
6. **Commands report via `the result`; functions return a value.**
7. **`itemDelimiter` is global** - set it immediately before use (engine note 2.3).
8. **`dcPoll` is the ONE buffer call returning a COUNT, not bytes** (like `btPoll`): the walker
   reads the leading u16 and each bodyLen, so the buffer tail is never touched.
9. **`ZStringUTF8` measures with `strlen`**, so an embedded NUL truncates a text message AND
   shrinks what the budget check measures, and the shim cannot see it. So `dcSendText` in the
   `.lcb` encodes to UTF-8 and refuses a zero byte with `kErrInvalidArg` (-3) before the
   `unsafe` block, clearing the shim's last-error. Anything that can carry a NUL is binary:
   `dcSendData`. OBSERVED green 2026-08-17 (Windows suite paste; ledger).
10. **LCB idioms do not exist in LCS**: no `{}` array literals; no subscripting a function
    result (`f(x)["k"]`); a bare `is empty` on an ARRAY is vacuously true (count `the keys of`
    instead); string literals have NO escapes (`"\0"` is two characters; use `numToByte`); `is`
    is case-insensitive (`set the caseSensitive to true`), and even then it compares two
    NUMBER-LIKE operands as numbers ("1e5" is "100000"; suite engine note 2.11, from the engine
    source), so a byte-exact compare also prefixes a letter to both sides or goes byte by byte.
    The checker flags the first two (`LCS_ANTIPATTERNS`).
11. **An EVENT name may never equal a public `dc*` handler name** (engine note 6.7). Dispatched
    names share ONE message namespace with public handlers and the LIBRARY handler wins, so the
    app's `on <name>` is never reached. Observed 2026-08-18 on `dcLocalDescription`: the
    dispatch landed in the getter `dcLocalDescription(in pPeer as Integer)` and threw "cannot
    convert value". Rename the EVENT, not the getter (hence `dcLocalDescriptionReady`); suite
    gate `tools/check-lcb-call-types.py` check 4 refuses a new collision. Transition shim:
    `datachannel-helpers` maps the legacy `dcLocalDescription` name onto
    `dcLocalDescriptionReady` as it drains, so apps run against an extension packaged before
    2026-08-18, and comparing sites accept both spellings (the selftest's
    "dcLocalDescription,dcLocalDescriptionReady"). The shim comes out when no supported build
    emits the old name; removal is an owner call.
12. **A zero-argument call in STATEMENT position must be BARE** (engine note 3.3):
    `dcCleanup()` as a statement parses as a command given the non-expression `()`, and since
    a `.livecodescript` compiles as ONE unit it killed the whole suite paste on 2026-08-09.
    `dcFreePeer(sPeerA)` is fine (`(sPeerA)` is an expression); in EXPRESSION position the
    parens are required (`dcCleanup() is 0`); `.lcb` allows `sPrepare()` as a statement, so
    Builder precedent proves nothing. The checker refuses it (fixtures in the suite's
    `tools/test-checker.py`). Lesson: shipped is not run - an unexecuted line is not evidence.
13. **Helper script-locals carry the member stem** (`sDcPolling`, `sDcPollTarget`,
    `sDcPollInterval`, `sDcPollNote`, renamed 2026-08-23): the enet helpers declared the same
    four, and two libraries sharing a column-0 name cannot be co-embedded (engine note 1.6).
    The suite's `tools/check-cross-library-names.py` holds library names disjoint.
14. **An LCB error's line number is read from the source on disk**, not the installed build
    (engine note 6.5, observed on `datachannel.lcb` 2026-08-18): confirm the installed
    extension came from the checkout you are reading before trusting a line number.
15. **Opening a demo file from disk builds no window** (engine note 5.5): paste it into a
    stack script and reopen the stack. The headers of `datachannel-loopback` and
    `datachannel-dht-chat` taught opening the file itself until 2026-09-24; both now teach
    paste-and-reopen, as the docs do.

## Engine evidence ledger

| Date | Engine / platform | What ran | Result |
|---|---|---|---|
| 2026-08-08 | OXT (platform not recorded) | suite selftest, datachannelxt section | green: `dcInit`, stale-handle no-op, peer and channel creation, a live in-process loopback negotiated and opened both ends, incoming channel label, `dcSendData` round-trip byte-for-byte, 60001-byte refusal -4, a payload at the SCTP-negotiated cap, `dcCleanup` |
| 2026-08-09 | OXT (platform not recorded) | first pass of the folded suite paste | compile failure on `dcCleanup()` in statement position took the whole paste (script gotcha 12); fixed at four sites and gated |
| 2026-08-10 | OXT, suite paste (folded) | member harness sync half | 23/23, twice in one day; all 31 public `dc*` handlers called by name |
| 2026-08-12 | OXT, suite paste (platform not recorded) | re-run of the seven folded harnesses | 617 member checks, 0 failures; datachannelxt 23 |
| 2026-08-15 | OXT (platform not recorded) | `tests/datachannel-selftest.livecodescript` standalone, incl. the async loopback | green end to end: genuine SDP carrying candidates; peer A offer, peer B answer; `dcGatheringState` complete (2) on both peers; a selected pair exposing `localCandidate`; stream id assigned; negotiated max message > 0; `dcBufferedAmount` >= 0; `dcSetBufferedLowThreshold` 0 on a live channel; `dcSendText` intact; `dcSendData` byte-for-byte incl. an embedded NUL; `dcCreateChannelEx` label + protocol round-trip; cap-sized send returns 0 |
| 2026-08-17 | OXT 9.6.3, Windows x86_64, NT 10.0 | suite paste (preflight: DataChannelXT LOADED at ABI 1) | paste 1836 folded / 0 failed / 7 skipped; datachannelxt 26 folded: `dcSendText` refuses an embedded NUL with -3, the refusal cleared the shim last-error, the four stale-handle assertions read the exact -2 |
| 2026-08-18 | OXT, Linux then Windows, one machine hosting | `examples/datachannel-dht-chat.livecodescript`, first run | found engine notes 1.6 (duplicate `local sPolling` from the embed: hard compile error), 6.6 (the poll pump died on a bad event without naming it) and 6.7 (the event/getter collision); all fixed and gated; maintainer reported single-machine working after the fixes (environments not captured). The pump guards and `dcPollLastError` landed after this pass |
| 2026-08-20 | OXT, Windows | suite paste, whole run | 1981 / 0 / 1; datachannelxt 39 folded; the core's live dc loopback negotiated and delivered, SCTP cleared its 16 KiB floor, the 60000 budget was checked, teardown released the WebRTC peers |
| 2026-08-24 | OXT 9.6.3, Windows x86_64 | suite paste | 2373 / 0 / 3 deliberate skips (datachannelxt's own count not recorded) |
| 2026-08-27 | CI, no engine | `release-binaries.yml` run 12 (`cec1e85`), two-slice-lipo job | first `universal-mac` dylib committed (both slices built and tested); all five platforms pinned |
| 2026-08-27 | OXT, two-machine session (platform not recorded) | suite paste; a DHT-signalled WebRTC chat | paste 2440 / 2 / 3, every folded member green; the 2 failures were the core's live loopbacks stalling on a machine blocking UDP to 127.0.0.1 (environment). Same evening the maintainer reported "the DHT-signalled WebRTC chat WORKS (real machines, one LAN)"; which stack (the dht-chat demo or closing-pass leg E) and the selected-pair type were not recorded |
| 2026-09-12 | CI, no engine | `release-binaries.yml` run 34657390798 (`421bab3`) | every platform rebuilt from a tree containing `23a2914` (C++ gotcha 7) |
| 2026-09-24 | headless Chromium 141.0.7390.37, Linux x86_64; no engine | `tests/browser-peer.html` against itself, and against the committed `x86_64-linux` library through the `dcx_*` C ABI (a scratch ctypes driver, in both roles) | the page's three checks green; `dcx_send_text` arrived as a string and `dcx_send_data` as an ArrayBuffer, byte-exact; the page's string and ArrayBuffer arrived as TEXT and PAYLOAD events; selected pair host / `prflx` (the browser hid its host address behind an mDNS name). Not the `.lcb`, not an engine: `docs/browser-interop.md` |
| 2026-09-24 | OXT, Windows (the engine reports Win32), a 2026-09-12 DLL by the maintainer's account (its first engine load), 64-bit by the same account (given 2026-09-26, after this row said "bitness not recorded"), so the `x86_64-win32` one; version and OS build not recorded | the D-23 suite paste (built from `9aa62c8`; this harness byte-for-byte as at `6401e43`) | paste 2620 / 5 / 3 (2628); datachannelxt 39 folded, 0 failed, no skips: lifecycle, the stale-handle surface at its exact codes (including the oversize `dcSendText` on a stale handle, still -2, a leg the 2026-08-17 record did not name), the embedded-NUL refusal at -3 and its cleared last-error, and the `datachannel-helpers` section (the pump deliberately left unarmed). The core's live loopback created both peers and A's channel (`dcInit` 0, the version names libdatachannel, `dcPeerState(0)` -1), then stalled in phase `opening` to the 40 s deadline, its one FAIL; both loopbacks also stalled on 2026-08-27, whose phases and machine were not recorded (the suite runbook's trap 5.5; suspected environment, this machine's UDP loopback not yet tested independently). The day's second run (8:41 PM) read the same, line for line, so the live legs (open, the 60000 budget, delivery) did not run; `dcCleanup` 0. Board row 46 / 1 / 0; the paste's other FAILs were riptide's three and the enet loopback |
| 2026-09-25 | OXT, Linux (box2dxt's lines print `the platform` as Linux); by the maintainer's account 64-bit Kubuntu 24.04 with the latest committed builds, so the `x86_64-linux` file of `421bab3` (release run 34657390798, 2026-09-12; glibc floor 2.38, and Kubuntu 24.04 ships 2.39); the latest OXT (no version recorded) and no preflight, by the same account (given 2026-09-26); library version not recorded | the D-23 suite paste as regenerated at `f1346e0` (the tree at `cba3130`, PR #145; this harness's folded code as on 2026-09-24, comments aside) | paste 2672 / 0 / 10 (2682); datachannelxt 39 folded, 0 failed, no skips, the same sections as 2026-09-24. The core's live loopback COMPLETED: `dcInit` 0, the version names libdatachannel, `dcPeerState(0)` -1, both peers and A's channel created; the loopback negotiated and both ends opened, the incoming channel carries its label, peer A reports connected; `dcSendData` refused 60001 bytes with -4 (enetxt's code) and carried the SodiumXT-sealed ciphertext byte for byte, opened to the exact plaintext; SCTP negotiated at least its 16 KiB floor, and a payload at the negotiated cap was accepted and delivered whole; `dcCleanup` 0. Board row 56/0/0. That `.so`'s first engine load (its C ABI was driven headlessly on 2026-09-24, no engine), and the paste loopback's first recorded completion since 2026-08-20 (Windows; the 2026-08-24 paste's zero failures imply one more), after its stalls of 2026-08-27 and of all three 2026-09-24 runs (Windows, in `opening`). So the paste's loopback code completes on an engine, and the Windows stall belongs to that platform or machine (trap 5.5). C++ gotcha 7's two exits (a peer already freed, a full handle table) are not on this loopback's path. By the maintainer's account (given 2026-09-26) the report is the launch's SECOND Run all, the first having run on open, so this `dcInit` 0 and the completed loopback came after the core's `stCleanup` (which every Run all runs first) had called `dcCleanup` in the same process |
| 2026-09-25 (Windows; the Kit report's clock 10:54 PM local) | OXT, Windows (the engine reports Win32), by the maintainer's account the machine of the 2026-09-24 runs and 64-bit, so the `x86_64-win32` DLL, INFERRED to be the 2026-09-12 file (no Windows DLL committed since); no preflight (the same account: none on either machine); the OXT build and whether the report is a launch's first or second Run all not recorded | the same D-23 suite paste as the Linux run (INFERRED from the version lines both reports print: the board stamp `suite-board-1`, holde-em's "stack v0.25.5 harness v47" and riptide's third probe line) | paste 2653 / 2 / 10 (2665); datachannelxt 39 folded ("39 passed, 0 failed of 39 checks"), no skips, the same sections. The core's live loopback created both peers and A's channel (`dcInit` 0, the version names libdatachannel, `dcPeerState(0)` -1), then stalled in phase `opening` to the deadline ("UDP to this machine may be blocked"), one of the paste's two FAILs; `dcCleanup` 0; board row 46 / 1 / 0. That machine's FOURTH stall in `opening` (2026-09-24 three times, 2026-09-25), the same day the same paste's loopback completed on Linux, so on Windows the live legs (open, the 60000 budget, delivery) last ran in August (recorded 2026-08-20; the 2026-08-24 paste's zero failures imply one more); the standalone selftest there is what would tell the machine's UDP from the paste (trap 5.5) |

## Status

The whole `dc*` surface is engine-proven (standalone async loopback 2026-08-15; folded
through 2026-09-25), and the flagship demo ran on one machine on Linux and Windows
(2026-08-18). The suite core's own live loopback (green 2026-08-20) stalled on 2026-08-27,
recorded as a machine blocking UDP to 127.0.0.1 (environment; its phase not recorded), and in
`opening` in all three of 2026-09-24's runs and again on 2026-09-25 (Windows, the same
machine each time; suspected environment, not yet tested independently), and COMPLETED on
Linux x86_64 on 2026-09-25 (negotiated, both ends open, SCTP at least 16 KiB, a cap-sized
payload whole), so the paste's loopback code works on an engine and the Windows stall is
that platform's or that machine's. The 2026-09-24 and 2026-09-25 Windows pastes ran on the
2026-09-12 `x86_64-win32` DLL and the 2026-09-25 Linux paste on the 2026-09-12
`x86_64-linux` file (the maintainer's account: 64-bit OXT on both, the latest committed
builds, Kubuntu 24.04 on Linux), each file's first engine load; neither the `x86-win32` or
`x86-linux` file nor the `universal-mac` dylib has met an engine.
C++ gotcha 7's two exits are driven natively by `tests/orphan_channel_test.cpp` (2026-09-24,
ASan/UBSan and TSan), not by an engine. The pump's failure branches (`dcPollLastError`) are
verified statically; needs an OXT pass.
Still open for this member: browser interop on an engine (the browser page and the OXT half
exist, with the procedure in `docs/browser-interop.md`; the page ran against the committed
library in headless Chromium on 2026-09-24, and the OXT script is verified statically; needs
an OXT pass), a call across two
networks with real NAT traversal (a `srflx`/`prflx` selected pair; loopback never leaves the
host), a two-machine run recorded against the dht-chat demo by name (the 2026-08-27 one-LAN
report does not name its stack), any engine record for
`examples/datachannel-loopback.livecodescript`, and a Mac engine load. Both Linux libraries
need glibc 2.38 or newer (measured 2026-09-23 with `objdump -T`); the x86_64 one loaded on
2026-09-25 on Kubuntu 24.04 by the maintainer's account, a release that ships 2.39 (the run
did not print it). Open work is tracked in the suite's docs/WORK-PLAN.md.

## Build and gates

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DDATACHANNELXT_BUILD_TESTS=ON
cmake --build build --parallel && ctest --test-dir build --output-on-failure
# sanitizer lanes: DATACHANNELXT_SANITIZE is a GLOBAL string (address | thread), injected
# before FetchContent so the whole static stack is instrumented; mutually exclusive builds
cmake -S . -B build-tsan -DDATACHANNELXT_BUILD_TESTS=ON -DDATACHANNELXT_SANITIZE=thread
cmake --build build-tsan --parallel
TSAN_OPTIONS="halt_on_error=1:suppressions=$PWD/tests/tsan-suppressions.txt" \
  ./build-tsan/datachannel_smoke_test
bash tools/run-gates.sh     # this member's gate list (what CI runs)
```

The dependency build is minutes (FetchContent of the pinned tag with its submodules; DTLS
from `libssl-dev` / brew `openssl@3` / vcpkg). The ASan lane, Windows, the universal mac
build and packaging: `docs/building.md`. Comment the why, densely; per-task branch, draft PR.
