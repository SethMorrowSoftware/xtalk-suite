# Extension work plan: coding and engine-pass work, per member (2026-09-23)

**SNAPSHOT, compiled 2026-09-23 at `e3d2496`.** This is a re-audit of every member
of the suite. Each extension and app was reviewed separately against its own
tree: its `CLAUDE.md`, its docs, its tests and tools, its committed binaries, its
git history, and every suite document that mentions it. The results are
organised **per member**. For each one it lists:

- what can still be done **in the tree** (coding, tests, release lanes, doc truth), and
- what still needs **an OXT engine** (which stack to run, on what resources,
  what a green run looks like, and which labels that run flips).

**How it relates to the LIVE documents.** This file is a dated snapshot.
It does not replace any of these:

- [REMAINING-WORK.md](REMAINING-WORK.md), the punch list organised by kind of work;
- [OXT-PASS-RUNBOOK.md](OXT-PASS-RUNBOOK.md), which schedules engine sessions and
  whose S1-S5 codes are reused below;
- [OPEN-DECISIONS.md](OPEN-DECISIONS.md), the owner decision briefs.

Section 1.6 lists the REMAINING-WORK entries this audit found already closed or
changed. When an item below is acted on, record the result at its primary
source, as those documents' ledger rules require. Treat this file as decaying
from its compile date.

**Method and honesty.** Ten reviews ran in parallel, one per member (enetxt and
datachannelxt shared one). Each was told to check claims against the tree
rather than against any single document. The load-bearing suite-wide facts in
section 1 were then **re-measured directly in the compiling session**:

- binary provenance with `strings` and `objdump`;
- which release run built which binary, with `git log` and `git merge-base`;
- the coverage ratchet with `tools/check-suite-coverage.py`;
- CI and publishing state with the Actions API.

So were the individual claims this document states as defects:

- `oxLaunchTor`'s unchecked results;
- holde-em's dealLevel gate;
- box2dxt's glibc floor and harness version;
- D-17's premise.

This document **claims no engine result**. Every "engine-proven" below quotes a
dated record that already exists in the tree, and every run it asks for is
still owed.

**Legend.**
- **Size:** S = hours, M = a day or two, L = a multi-day workstream.
- **Blocked by:** `none`, an owner decision (`D-xx`, or "owner" when no brief
  exists yet), `dispatch` (a `release-binaries.yml` run, which suite rule 5
  reserves for a human), or `engine` (waits on an engine finding).
- **Where:** S1-S5 are the runbook's session types:
  - S1: one machine, no daemon.
  - S2: one machine plus tor.
  - S3: two machines.
  - S4: two machines plus tor.
  - S5: a Mac, or a Windows box.

  Four extra labels mark resources those sessions do not cover:
  - **NET**: internet only; a public relay, testnet coins or a real swarm.
  - **2NET**: two machines on different networks.
  - **3M**: three machines.
  - **PERSON**: a human judgement, such as a review or a feel pass.

---

## At a glance

| Member | Engine-proven core (latest dated record) | Headless work open | Engine work open | Needs |
|---|---|---|---|---|
| sodiumxt | full `sxSelfTest()` 106/106, Windows x64, 2026-08-24 (on a mingw DLL that no longer ships) | Windows provenance docs; stale ChaCha20 labels | Windows re-proof of the MSVC DLLs (both bitnesses); first Mac load; demo re-pass | S1, S5 |
| torrentxt | harness 101/101, Windows, 2026-08-17/20/24 | ABI 12 alert codes; Windows libtorrent pin; boundary tests; quickshare HEAD fixes | first contact with the 2026-09-12 binaries; four restyle re-opens; Tor toggle; #31-#33; closing-pass C/D; real-swarm interop | S1-S5, NET |
| enetxt | async loopback 2026-08-13; folded 2026-08-20 | smoke test for the 09-09 fix; schedule internet chat | two-machine LAN chat + leg B; two-network internet chat | S1, S3, 2NET, S5 |
| datachannelxt | async loopback 2026-08-15; folded 2026-08-20 | browser-peer page; two-network row; stale open instructions | loopback demo (no record at all); leg E; two-network call; browser interop | S1, S3, 2NET, S5 |
| onionxt | live-Tor core (early bring-up); offline self-test 61 checks, 2026-08-17 | `oxLaunchTor` result checks; 3 exemptions retirable offline; Mode B vs docs/07 | Mode B (leg F); B.12 probes; round trip; live negative paths | S1, S2, S4 |
| coinxt | 290/290, Windows, 2026-08-24 (BIP-341) | D-15 apply; D-17 premise; per-push Win/mac CI; Core plan residue | ABI 7 + silent-payment receive (row Q); demo; four-family broadcast; wallet's post-09-04 surface | S1, S2, NET, S5 |
| nostrxt | core 274/0/2, 2026-08-24; relay SEND live-proven 2026-08-24 | placeholder floor; 09-09 refusals into the harness; demo controls for NIP-42 | relay RECEIVE, NIP-42, ws://, bad-certificate TLS | S1, NET, local relay |
| box2dxt | harness v30 375/0 Windows 2026-08-20, 374/1 Linux 2026-08-21 | harness v32 for the 09-09 Kit fix; x86-linux glibc regression; reference docs | v31/v32 totals; the five games on Win/Linux; risk R1; first Mac load; feel pass | S1, S5, PERSON |
| riptide | phases 1-4 two-machine (to 2026-08-15); compute of 6-7 (2026-08-24) | bridge reader; RSL1 magic decision; LAN key case; own-head refresh | row 35 boot; phases 5, 6, 7 live; phase 8 live; faststart re-run | S1-S4, NET |
| nocloud | none dated in this tree (pre-fold passes only) | stale OnionXT wording; D-09 write-through; gate-count drift; Phases 4-5 (D-02) | the 69-item checklist, web-link and Tor halves; mtime probe (D-10) | S1, S2 |
| holde-em | 667/0 folded, 2026-08-27 (v0.25.2) | **Level 2 not wired into play**; animations; 102 untested handlers | v44 total; 6-seat hotseat; 2d/2e multi-machine; 2f onion; 3-machine oracle | S1-S4, 3M, PERSON |

Suite coverage today: **864/878** public handlers exercised by the suite
harness. The 14 exemptions are all onionxt's. holde-em's advisory row reads
158/330, with a floor armed. box2dxt's raw `b2*` binding reads 131/376, also
with a floor. Run `python3 tools/check-suite-coverage.py` rather than trusting
these numbers.

---

## 1. Suite-wide findings

### 1.1 The 2026-09-12 binaries have not been loaded by an engine

Every native member's committed libraries were rebuilt by `release-binaries.yml`
run `34657390798` from `0f17ab5` and committed as `421bab3` on 2026-09-12. No
native source has changed since. The latest engine records per member predate
that build:

- 2026-08-24 for the suite paste.
- 2026-08-27 for holde-em's folded run.
- 2026-08-29 for riptide's boot.
- 2026-09-01 to 09-03 for the coin-wallet logs, on run-12 binaries.

**So the first S1 session is the first engine contact for the current binaries
of all six native members.** A regression there is a finding about those
builds, not about the script. Record per platform which DLL or `.so` was
loaded.

### 1.2 Windows ships different upstream versions than the docs say

Measured from the committed DLLs:

- **sodiumxt:** both DLLs are MSVC builds (linker 14.51) carrying
  **libsodium 1.0.22**. The Linux and mac builds carry the pinned 1.0.20. The
  docs still describe the DLLs as mingw cross-builds of the pinned source, in
  `sodiumxt/docs/building.md` ("mingw cross-builds of the SHA256-pinned source")
  and in
  `sodiumxt/docs/security.md` ("COMMITTED Windows DLLs are built the same way").
  D-08 (2026-08-27) accepted the vcpkg path, so this is a write-through that
  never happened, not a new decision.
- **torrentxt:** both DLLs carry **libtorrent 2.1.1**, from vcpkg's unpinned
  port, since release run 12. Linux and mac carry 2.0.11. The docs promise one
  version, in
  `torrentxt/docs/building.md` ("so all five platforms ship the same engine version").
  **No decision covers this**; the sodiumxt D-08 brief is the template for one.

The 2026-08-24 Windows engine proof of sodiumxt ABI 10 ran on a mingw DLL that
has since been replaced. The first Windows engine run of libtorrent 2.1 is
still owed.

### 1.3 Linux glibc floors are uneven, and most are undocumented

Highest `GLIBC_` symbol version each committed Linux library requires, from
`objdump -T`:

| Member | x86_64-linux | x86-linux | Documented floor |
|---|---|---|---|
| sodiumxt | 2.33 | 2.33 | none stated |
| torrentxt | **2.28** (manylinux, static OpenSSL) | **2.38** + `libssl.so.3` | x86_64 doc still says 2.38 (stale); x86 recorded as deliberate |
| enetxt | 2.14 | 2.28 | none stated |
| datachannelxt | **2.38** | **2.38** | none stated |
| coinxt | 2.25 | 2.25 | 2.25 (matches) |
| box2dxt | 2.17 | **2.34** (was 2.17 before run 12) | `box2dxt/README.md` ("glibc 2.17 floor") - wrong for x86 |

The 2.38 floors come from C23 `__isoc23_strtol` and friends, plus `arc4random`
and `_dl_find_object`. They mean **datachannelxt cannot load on Ubuntu 22.04
(2.35), Debian 12 (2.36) or RHEL 9 (2.34)**, and neither can torrentxt's 32-bit
build. Two things follow:

- **Coding (M, owner + dispatch):** choose a suite floor. Then either move each
  Linux release row into a manylinux container, as torrentxt's x86_64 row and
  box2dxt's per-push lane already do, or publish each member's measured floor
  in its README and in runbook section 2.1. A check in
  `tools/install-release-binaries.py` that refuses a floor above the stated one
  would stop a silent regression like box2dxt's.
- **Engine:** the Linux machine for S1 needs glibc 2.38 or newer to load all
  six members.

### 1.4 Platform rows with no engine record

- **universal-mac:** none of the six dylibs has been loaded by an OXT engine.
  CI built and tested them; row 24 closed only the builds.
- **x86-win32:** no engine record for sodiumxt, torrentxt or coinxt. coinxt's
  32-bit DLL has not been executed at all, even in CI, whose Windows KAT step
  is x86_64 only. The other members' Windows records do not name a bitness.
- **x86-linux:** no engine record for sodiumxt or torrentxt.

These go to S5, plus one 32-bit OXT engine on Windows and one 32-bit Linux
engine if either exists.

### 1.5 Member publishing went live today

`publish-members.yml` run 3, attempt 2, adopted and published **all eleven**
member repositories at 16:11 UTC on 2026-09-23. SodiumXT took 43 commits and
CoinXT 81, for example. The tree still records only the refusals from that
morning: `docs/MEMBER-REPO-SPLIT.md` ("met eleven refusals"), and root
`CLAUDE.md` ("The first real adoption, 2026-09-23, was refused on all eleven").
Several member reviews repeated that stale state.

Next steps:

- **Record the success** (S).
- **Watch each member repository's first generated `gates.yml` / `native.yml`
  run.** This session's GitHub scope cannot see those repositories.
- Point box2dxt's README badge at its own lane once it has run.
- Put the publish token's expiry in a calendar.
- Note that CoinXT's own `gates.yml` pays the multi-hour wallet-gate cost on
  every publish (MEMBER-REPO-SPLIT section 9).

### 1.6 REMAINING-WORK entries that have closed or changed

| Entry | What the tree says now |
|---|---|
| **C.0** `docs/REMAINING-WORK.md` ("Three members' committed binaries are BEHIND their shims") | **Closed by `421bab3` (2026-09-12).** The build source contains every fix it lists: torrentxt `aad430a` and `1a25641`, and enetxt/datachannelxt `23a2914`. enetxt's disassembly shows the retire path. Only the **ABI 12 alert codes** remain (`BTX_ABI_VERSION` is still 11). The same stale sentence is in `enetxt/CLAUDE.md` and `datachannelxt/CLAUDE.md` ("The committed binaries do NOT carry it yet"), in `torrentxt/CLAUDE.md`, and in BLOCKCHAIN-FEASIBILITY. |
| **C.3** box2dxt release lane | **Closed.** `docs/REMAINING-WORK.md` ("Only **release-binaries.yml** omits it now") is false: the workflow has had box2dxt rows since 2026-08-23, and run 12 committed from them. The same claim is in `box2dxt/CLAUDE.md` and `tools/install-release-binaries.py`. |
| **C.5** torrentxt portable Linux | **Closed for x86_64.** `docs/REMAINING-WORK.md` ("still carries the glibc-2.38 floor") is stale: the committed x86_64 `.so` floors at 2.28 with static OpenSSL. The x86 row is still 2.38 (section 1.3). |
| **C.4** holde-em coverage | The floor is armed ("ARMED AS A FLOOR"), and the figures are stale: the gate prints 158/330 and 102 no-test. |
| **C.7** inert member workflows | The premise has changed. The generated member workflows (since 2026-09-21) have no commit job. |
| **E.3** riptide feed retention | Decided (D-06, no republish). The entry still says "the one unresolved spec-12 decision". |
| **E.8** coinxt SLIP-39 / decoder lane | Both halves were decided 2026-08-27 (D-15, D-17). D-15 was never applied, and D-17's premise is false (section 1.8). |
| **B.3** the Tor evening | Only **three** live-daemon coverage exemptions remain (`oxLaunchTor`, `oxStopTor`, `oxTransportDial`); the entry says seven. The three can also be retired **offline** (onionxt coding item 3). |
| **B.4** riptide passes | "(also blocked on A.6)" is stale, since A.6 is built. The "post-00:46 harness additions" re-run closed 2026-08-20. Phase 8 is missing from the entry. |
| **B.7** torrentxt plan gates | The destructive-handler **refusal** legs are engine-proven (2026-08-17). Only the positive paths remain. |
| **B.9** nocloud checklist | 69 items, not 68 (the TorrentXT-absent item was added 2026-09-10). |
| **B.11 / A.1** holde-em | "Everything statically buildable is BUILT" no longer holds. The Level 2 wiring, the 1d animations, BEP44 standings and 7-9 seats can all be written without an engine (section 3.3). Row 14 can close at inference strength (section 3.3). |
| **B.12** onionxt hypotheses | The line numbers have drifted to 1043, 1170, 1835 and 1866. A fifth inline VERIFY (`oxProcessId`) belongs to Mode B. |
| **B.14** interpreter array-key case | **Still open**, now across **two** byte-identical copies (`coinxt/`, `nostrxt/`) since archivext left. riptide's LAN keys (section 3.1) are a concrete case of the risk it names. |

### 1.7 Runbook drift that will cost engine minutes

Fix these before the next session (S, blocked by nothing):

**Stale expectations**
- S1 item 4 expects holde-em `kHeVersion` 0.24.5; the tree is **0.25.3**
  (harness 44).
- The S5 Windows text still calls row 23 "the ABI-8 mingw DLL re-proof".
- The S5 Mac text still prescribes hand `lipo` builds and torrentxt
  codesigning. Row 24 was closed by CI, and unsigned mac binaries were
  accepted.
- The torrentxt figures are out of date: section 4.4 says 96 checks and
  "nothing is left to flip"; it is 101, and the 2026-09-12 binaries are
  unproven.
- coinxt section 2.4 says ABI 6, four libraries and 16 entry points. Rows
  16a and Q describe superseded binaries and an Electrum-over-Tor gap that
  closed 2026-09-03.

**Legs with no row or session**
- nostrxt row 34 (the relay receive leg);
- `torrent-rp1-chat` and `sodium-demo` re-opens;
- `enet-internet-chat`;
- a datachannelxt two-network call and browser interop;
- riptide's phase-8 live leg, the faststart re-run, and phase-6 steps 7-8;
- holde-em's Phase 1 exit and three-machine oracle;
- coinxt's four-family broadcast and Bitcoin Core regtest section;
- onionxt's B.12 probes, negative paths and round trip;
- torrentxt's B.7 legs;
- nocloud checklist sections 7 and 8.

**Tick sheet**
- Rows 13 and 33 (nostrxt folded) are unticked, though their records exist.
- The sodiumxt DEPTH line cites the 71-check run.
- Lines 23 and 24 still read "ABI-8" and "lipo".

**Budgets and guidance**
- S1 row S budgets 35 minutes for about 58 nocloud checklist items.
- There is no Gatekeeper/quarantine guidance for the unnotarized mac
  binaries.

### 1.8 Owner calls

- **Open:** D-04, which `.onion`-derivability wording ships. The
  recommendation stands: pre-approve both wordings, so the S4 #32 run flips a
  label instead of waiting on copy.
- **Worth re-opening:**
  - **D-17.** Its premise is false. The brief says
    `docs/OPEN-DECISIONS.md` ("The release lane already runs it before any binary"),
    but no workflow invokes
    `coinxt/tools/verify-independent-decoder.py`. Its last recorded run was
    2026-08-13.
  - **D-03.** "The glibc floor stands as-is" no longer describes box2dxt's
    32-bit build (section 1.3).
- **Raised by this audit, with no brief yet:**
  - the Windows upstream pins (1.2);
  - a suite Linux glibc floor (1.3);
  - coinxt per-push Windows/mac CI, or a written "dispatch-only is permanent"
    (C.6);
  - riptide's RSL1 magic after the 2026-09-09 tag change;
  - riptide's own-head refresh cadence and bridge-reader scope;
  - nostrxt's phase 9 scope (gift wrap, outbox, onion relays);
  - holde-em: build or strike BEP44 standings and 7-9 seats, schedule the
    Level 2 wiring, and name who does the Phase 5 hostile review;
  - removal of datachannelxt's legacy `dcLocalDescription` transition shim.
- **Deferred, no action:** D-02 (nocloud Phases 4-5) and D-13 (onionxt v2).

### 1.9 Other suite items

- **B.1, the fleet demo re-pass**, is still the largest engine item. Each
  member section below names its demos; section 4.2 orders them.
- **B.10, the suite-root stacks:** `start-here.livecodescript`, the ui-kit
  master, and `tests/suite-closing-pass.livecodescript`, whose header still
  calls leg A "still-static" although it closed 2026-08-15.
- **Open draft PR #138** ("archivext: review against the 9.6.3 dictionary")
  targets a member that left this tree on 2026-09-21. Move it to the archivext
  repository or close it.

---

## 2. The extensions

### 2.1 sodiumxt

**Where it stands.**
- 73 public `sx*` handlers over 124 shim exports.
- **ABI 10** in the shim, the `.lcb` and all five binaries.
- Coverage 73/73; member gates green.
- Engine record:
  - 68/68 (2026-08-10); 71/0 (2026-08-12, Windows, ABI 7);
  - 99 checks at ABI 9 (2026-08-17, Windows); Linux at ABI 9 (2026-08-18);
  - **106/106 at ABI 10 (2026-08-24, Windows x64)**, including the 7-check
    ChaCha20 section. That run used the mingw DLL, which has since been
    replaced (section 1.2).

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | Correct the Windows provenance: `sodiumxt/docs/building.md`, `sodiumxt/docs/security.md`, README, getting-started, the `CLAUDE.md` platform table, EXTENSIONS-OVERVIEW, runbook 3.2 | A security document names the wrong library version for two shipped binaries | S | none (D-08 decided) |
| 2 | Flip the ChaCha20 labels: `sodiumxt/src/sodium.lcb` ("The ONE surface with no engine run today") and its section banner, `sodiumxt/examples/sodium-tests.livecodescript` lines 27-31 (which contradict line 18 of the same file); then `python3 tools/build-suite-selftest.py` | Understated labels (the 2026-08-24 run covered it); the gate cannot see scoped claims | S | none |
| 3 | `native-sodiumxt.yml` comment still says the mac dylib is "a hand-made lipo build still recorded at ABI 6"; then `tools/sync-member-workflows.py` | The generated member workflow inherits it | S | none |
| 4 | *(optional)* Add the RFC 8439 ChaCha20 vector to the committed-`.so` execution step, which runs only ristretto today | Execution cover for the ABI-10 surface | S | none |
| 5 | *(optional)* Bind the 32 shim length accessors the `.lcb` does not expose (`sxt_secretbox_keybytes`, `sxt_aead_keybytes`, `sxt_kdf_*` ...); only `sxPwSaltBytes` is public, so callers hard-code 32 | API completeness; no ABI bump; adds engine-pass debt | S-M | none |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | `tests/preflight.livecodescript`, then `tests/suite-selftest.livecodescript` (or `put sxSelfTest()`), on **both** Windows bitnesses | S5 (x86 needs a 32-bit OXT) | SodiumXT LOADED at 10; the sodiumxt section 106/0 with SHA3, ristretto and ChaCha20; `put sxVersion()` shows `libsodium 1.0.22` (record it) | inventory row 23; the Windows rows of `sodiumxt/CLAUDE.md`; root README "The x86 (32-bit) Windows DLL still needs its own platform proof" |
| 2 | Same, on a Mac (arm64; Intel too if available) | S5 | 10 and 106/0 | "no OXT engine has loaded the dylib"; tick 24's "then S1 run" |
| 3 | Same, on Linux | S1 | 106/0: the first ChaCha20 run on Linux, which was last seen at ABI 9 | regression evidence only |
| 4 | `sodiumxt/examples/sodium-demo.livecodescript` | S1 | all 7 tabs build in the card look; the About self-test is green; the tamper case is rejected; no error dialog. It carries no boot self-check (a written exemption), so record a human judgement | the demo header's "needs an OXT re-pass"; the `sodium-demo` tick (add it to an S1 row) |

**Doc fixes.**
- Root README line 74 dates the ristretto run 2026-08-16; every other record
  says 2026-08-17.
- `sodiumxt/docs/building.md` says universal-mac is "waiting on the first mac dispatch".
- The `tools/build-preflight.py` docstring says the dylib "is at ABI 6".
- The `sodiumxt/docs/api-reference.md` "See also" lists 5 demo tabs; there are 7.

### 2.2 torrentxt

**Where it stands.**
- 85 public `bt*` handlers and 78 binds against 78 exports; coverage 85/85.
- **ABI 11** everywhere: the header,
  `torrentxt/src/btx_abi.h` ("#define BTX_ABI_VERSION 11"),
  the `.lcb`, and the committed x86_64 `.so`, which returns 11 when
  loaded through ctypes.
- The 2026-09-12 binaries carry the bounded rp1 queue, the 996-byte BEP44 cap
  and `alerts_dropped_alert` counting (`torrentxt/src/torrent_shim.cpp`, "THE
  BOUNDED INBOUND QUEUE"). Their strings are present in all five binaries.
- Engine record: harness 101/101 on Windows (2026-08-17, 2026-08-20,
  2026-08-24), including the destructive handlers' refusal legs on 2026-08-17.
  Two-machine rp1/DHT evidence exists only through riptide (2026-08-13 and
  2026-08-15). Every one of these ran binaries built before run 12.

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **ABI 12**: `A_RP1_QUEUE_OVERFLOW` and an alerts-dropped alert code, replacing the interim last-error reporting | Apps can see a shed or dropped alert only by reading `btLastError()` | M | dispatch (must land in the same change as the rebuild of all five, or the freshness gate goes red) |
| 2 | Pin Windows libtorrent (vcpkg baseline/overlay, or FetchContent) to 2.0.11, or record 2.1.1 as accepted, D-08 style | Section 1.2; the Windows build is a different upstream from the tested one | S + dispatch | owner |
| 3 | Boundary tests: 996 accepted and 997 refused in the smoke test (today it refuses only 1001); the rp1 shed; the alerts-dropped report; a size-boundary assertion in `torrentxt/tests/torrent-selftest.livecodescript` | The three 2026-09 fixes have no test that would catch their regression | S | none |
| 4 | Document the interim reporting in the `btRp1Poll`/`btPoll` sections of `torrentxt/docs/api-reference.md`, and have `torrentxt/examples/torrent-helpers.livecodescript` read it | Otherwise the fix is invisible to app authors | S | none |
| 5 | Port nocloud's 2026-08-17 HEAD fixes into `torrentxt/examples/torrent-quickshare.livecodescript`. Its route key is still built from the literal method ("put toUpper(tMethod) & space & tPath into tRouteKey"), so `HEAD /_qs/info` misses, and a HEAD over Tor sends a body | Known defects in a shipped example | S | none |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | Suite paste, on Windows **and** Linux | S1 | torrentxt 101/0; the first contact with the 2026-09-12 binaries, and the first engine run of libtorrent 2.1 (Windows) | the `load_torrent_buffer` "engine-proven NOWHERE yet" line in `torrentxt/CLAUDE.md`; runbook 4.4 |
| 2 | Restyle re-opens, one fresh launch each (trap 5.1.1): `torrent-quickshare`, `torrent-dht-channels`, `torrent-client`, **and `torrent-rp1-chat`** (it has a boot self-check but no S1 row) | S1 | the boot self-check passes; the v2 card look | each header's "UI unified 2026-08-14; needs an OXT re-pass"; the DEMOS ticks |
| 3 | Quick Share with the Tor toggle ON; #31 in `torrent-dht-channels` (Anonymous ON / OFF / tor absent) | S2 | a share code with no torrent created and no DHT call; #31's three behaviours | inventory row 5; runbook 4.7; the 12.3 register #31 |
| 4 | `tests/suite-closing-pass.livecodescript` legs C (seed/leech with a hash-verified payload, plus resume across an OXT restart) and D (rp1 chat); `torrent-rp1-chat` two-way | S3 | each leg's PASS lines | row 6 (torrent legs); the plan's Phase-2 resume and Phase-3 leech gates |
| 5 | #32 / #33 and the Model C gate (plan 12.4) | S4 | the feed over the onion with the DHT off; a sha256-identical download; a capture with zero swarm/DHT traffic | the 12.3 register; row 21; **settles D-04** |
| 6 | B.7's unscheduled legs: a legal ISO magnet through to `torrentFinished` with a hash match; `btMoveStorage` actually moving and `btRemoveTorrent` actually deleting; a packaged fresh install per platform | NET / S1 per platform | as named | `torrentxt/docs/archive/TorrentXT-IMPLEMENTATION-PLAN.md` gates |
| 7 | First universal-mac load | S5 | 101/0 | the mac residual of row 24 |

**Doc fixes.**
- C.0 and C.5 (section 1.6).
- README lines 69, 73 and 267 and `torrentxt/src/code/universal-mac/README.md` still say
  the mac binary is absent or the x86_64 floor is 2.38.
- `README.md` and `torrentxt/docs/building.md` cite a member `build.yml` that was deleted
  2026-09-21.
- `CLAUDE.md` calls the 2.1 branch "COMPILE-PROVEN ... has never executed",
  but CI runs ctest on it and the DLLs ship it.
- Three demo headers cite "demo passes recorded in torrentxt/CLAUDE.md", which
  records none.

### 2.3 enetxt

**Where it stands.**
- ENet 1.3.18, **ABI 2**, 23 public handlers; coverage 23/23; gates green.
- Engine record:
  - standalone selftest 2026-08-07;
  - async loopback, including `enHostStatus`/`enPeerStatus`, 2026-08-13;
  - folded sync half 21/21 (2026-08-10, 2026-08-17); 34 checks on 2026-08-20
    (21 plus, by count, the 13 helper-section assertions);
  - `enet-lan-chat` on **one** Linux machine on 2026-08-18. Two defects were
    found and fixed; the maintainer reported the re-run working.
- The 2026-09-12 binaries carry the 2026-09-09 `enx_disconnect` handle-retire
  fix; the disassembly of the x86_64 `.so` shows the retire path.

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | A smoke-test block for the 2026-09-09 fix: connect to a dead port, call `enx_disconnect`, expect `enx_peer_status == 0` and `enx_reset_peer == STALE` | The fix is compile-verified only; no test drives it | S | none |
| 2 | Give `enet-internet-chat` a runbook row, a tick line and a B item | Its two-network leg is scheduled nowhere | S | none |
| 3 | *(optional)* Teach `tools/check-binary-freshness.py` to read the ABI from the Windows DLLs (it SKIPs them today for enetxt, datachannelxt and torrentxt) | Closes a gap in rule 5's automated half | S-M | none |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | `enetxt/tests/enet-selftest.livecodescript`, standalone | S1 | ends with no `RUN NOT FINISHED` trailer; the first load of the 2026-09-12 binaries, and the first standalone async run since the `sEnPolling` rename | README "they need an OXT re-pass" (helper layer) |
| 2 | Closing-pass leg B (inbound **UDP 27300** on the Host) | S3 | "peer connected", text and binary (with NUL) echoed byte-exact, graceful disconnect | row 6 (enet leg); B.2; `enetxt/CLAUDE.md` ("Still un-exercised") |
| 3 | `enetxt/examples/enet-lan-chat.livecodescript` on two machines (UDP 27099) | S3 | joins/leaves announced, lines relayed through one `enBroadcast`, RTT on the dashboard | the header's "has not run BETWEEN TWO REAL MACHINES"; the tick sheet's "Two machines still OWED" |
| 4 | `enetxt/examples/enet-internet-chat.livecodescript` (Host needs enetxt + torrentxt, and UPnP UDP 27199 or a forward) | 2NET | pill INTERNET LIVE with a non-RFC-1918 remote; RTT/loss from `enPeerStatus`; a same-LAN run reads LAN ONLY | `enetxt/CLAUDE.md`'s 2026-08-24 as-built note; README; getting-started |
| 5 | Suite paste on a Mac | S5 | enetxt LOADED at 2; en1 sections green | the row-24 mac residual |

**Doc fixes.**
- C.0 and C.7 (section 1.6).
- README, `enetxt/docs/building.md` and `CLAUDE.md` still say universal-mac is absent
  or manually built.
- The harness header and runbook 4.3 understate the 2026-08-20 run.
- The `enet-lan-chat` header omits its 2026-08-18 run and calls leg B "item 6".

### 2.4 datachannelxt

**Where it stands.**
- libdatachannel v0.24.5, `NO_MEDIA` by decision; **ABI 1**; 31 public
  handlers; coverage 31/31; gates green.
- Engine record:
  - first live loopback 2026-08-08;
  - folded 23/23 (2026-08-10), 26 (2026-08-17, the NUL, last-error and order
    legs), 39 (2026-08-20);
  - **standalone async loopback green 2026-08-15**;
  - `datachannel-dht-chat` on one machine each on Linux and Windows,
    2026-08-18, which found engine notes 1.6, 6.6 and 6.7.
- The 2026-09-12 binaries descend from the 2026-09-09 orphan-channel fix, per
  commit ancestry.
- Both Linux libraries need **glibc 2.38** (section 1.3).

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **A browser-peer harness**: a static page plus copy/paste signalling, and a runbook procedure | B.6's browser leg cannot be run without it; no browser peer exists in the tree | M | none |
| 2 | A runbook row whose green is a `srflx`/`prflx` selected pair across two networks | Leg E proves one LAN only ("host/host means one LAN") | S | none |
| 3 | Fix the open instructions contradicted by engine note 5.5 (OBSERVED): `datachannel-dht-chat` (lines 56-57) and `datachannelxt/examples/datachannel-loopback.livecodescript` ("builds its UI on first open") | The 2026-08-27 header sweep missed these two, and the next passes open both | S | none |
| 4 | Teaching docs: README line 67 and getting-started line 122 put a two-argument paren call (`dcSendText(pEvent["channel"], ...)`) in statement position, which no engine-run caller does. Switch them to the `put`/`get` form, and add the bare-`dcCleanup` warning enetxt's reference carries | A first reader copies these lines | S | none |
| 5 | *(optional)* Remove the legacy `dcLocalDescription` transition shim (gotcha 11) | The cleanup its own comment schedules | S | owner |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | `datachannelxt/examples/datachannel-loopback.livecodescript`. **This is the only member demo with no engine record at all** | S1 | Connect gives connected + open on both sides; chat works in both panes; the boot self-check is green | the header; the footer; README; examples/README; getting-started; the DEMOS tick |
| 2 | Closing-pass leg E (torrentxt installed, fresh launch) | S3 | "channel OPEN across machines; selected pair:"; text both directions | row 6 (dc leg); B.2 |
| 3 | `datachannel-dht-chat` on two machines | S3 | Host, room code, Join, OPEN in 10-30 s; the direct/TURN readout | the header's "Two machines still OWED" |
| 4 | Leg E or the DHT chat across two networks | 2NET | a `srflx`/`prflx` pair; record `relay` honestly if both NATs force TURN | `datachannelxt/CLAUDE.md` ("Still open for this member"); B.6; the root README row |
| 5 | Browser interop (after coding item 1) | S1 + a browser | channel opens; text arrives as a string; `dcSendData` arrives as an ArrayBuffer | B.6's browser half |
| 6 | Suite paste on a Mac | S5 | dc sections green on the two-slice-lipo dylib | the row-24 mac residual |

**Doc fixes.**
- C.0 (section 1.6).
- The 2026-08-17 legs are still labelled "NOT observed" or "verified
  statically" in the harness header, the `.lcb`, `CLAUDE.md`, README and
  getting-started.
- README says universal-mac "is not committed yet".
- `CLAUDE.md` says CI "binaries land on main", which contradicts rule 5.
- B.6's citation has drifted.

### 2.5 onionxt

**Where it stands.**
- Pure script.
- The **live-Tor core is engine-proven** from the early bring-up recorded in
  `onionxt/CLAUDE.md`: SOCKS dial, SAFECOOKIE, ADD_ONION with Detach, inbound
  accept, streams both ways, events. So is `oxh*` hosting in Tor Browser.
- The offline self-test ran on an engine at 40/0 (2026-08-10), 43/0
  (2026-08-12) and **61 checks (2026-08-17, Windows)**.
- coinxt's wallet logs of 2026-09-02/03 show `oxDial` reaching third-party v3
  onions: Esplora on port 80 and Electrum. A real SOCKS handshake timeout
  failed closed. onionxt's own docs do not record any of this.
- Coverage 34/48. The **14 exemptions are 11 engine socket events plus 3 live
  daemon**: `oxLaunchTor`, `oxStopTor`, `oxTransportDial`.
- Not yet on an engine:
  - Mode B;
  - an OnionXT-to-OnionXT onion dial;
  - the live-accept half of the socket-id parser;
  - the 2026-08-23 foreign-socket `pass` split;
  - the 2026-09-09 `oxWrite` failure capture;
  - the four B.12 hypotheses.

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **`oxLaunchTor` never checks whether the launch worked.** It ignores `the result` of the torrc write and of `open process (quote & pTorPath ...) for read` and returns empty, against its own contract. Also, the pipe is opened for read and never read: with tor's default notice logging to stdout, a long-running child could fill the pipe and block (inferred, not observed). Add `Log notice file` to the generated torrc, or drain it | Leg F's first PASS line ("torrc written, process started") currently claims more than the code checks | S | none |
| 2 | Reconcile Mode B with `onionxt/docs/07-tor-lifecycle.md`. The code has no stdout capture, no `close process`, no torrc cleanup and fixed ports, and `oxStopTor` cannot stop a child whose control connection never authenticated. Implement these, or narrow docs/07 and runbook 4.7, whose "record whether stdout carried Bootstrapped 100%" cannot be done through OnionXT | The docs describe a lifecycle the code does not have | S-M | best decided after leg F (D-07 keeps Mode B optional) |
| 3 | **Retire the 3 live-daemon exemptions offline.** Each has a fail-closed path the harness can call by name: `oxLaunchTor ""` refuses before touching disk; `oxStopTor` unauthenticated is the idempotent disconnect; `oxTransportDial ""` is refused before `open socket`. Never pass a non-empty non-onion host, since that would really dial. Delete the rows in `tools/check-suite-coverage.py` ("oxTransportDial") and rebuild the paste | Coverage 37/48; the exemptions stop standing in for an evening | S | none |
| 4 | Make the two "SOCKS handshake timed out" paths distinguishable (the watchdog and `oxSocketTimeout`) | The 2026-09-02 log cannot say which one fired | S | none |
| 5 | Record the 2026-08-17 61-check run and the coin-wallet dials in `onionxt/CLAUDE.md`. The observed timeout contradicts "no stalled-handshake case was forced" | Evidence the member does not know it has | S | none |
| 6 | Runbook rows for: the four B.12 probes; writing into a closed stream; the Phase-4 two-instance round trip (and fix `onionxt/examples/onion-roundtrip`, which reads fields "myAddress"/"state" it never builds); the live negative paths | None of these is scheduled | S | none |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | `onionxt/examples/onionxt-demo.livecodescript` with **no tor**, then its About self-test; the `onionxt/examples/onion-httpd/spike.livecodescript` stack | S1 | the card look; the boot record; probes **fail closed**; `oxSelfTest` green | the demo header's re-pass label; the harness's "has NOT run" skip note |
| 2 | The same demo against a system tor (9050/9051, cookie auth), with the B.12 probes folded in: a second service on the same local port refused; the raw accepted socket id recorded (also settles engine note 6.2's live half); stale `close socket` tolerated; the topStack callback owner; `oxWrite` into a closed stream returning an error | S2 | auth; bootstrap seeded (trap 5.8); a publish that Tor Browser reaches | B.12; the "onionxt demo vs live tor" and "onion-httpd spike" ticks |
| 3 | `tests/suite-closing-pass.livecodescript` **leg F on 9250/9251 beside the running system tor** (trap 5.3.1) | S2 | launch; control authenticated against the **launched** tor; Bootstrapped 100%; serviceReady; exact bytes echoed; `oxStopTor` twice. Record the processId and whether the child exits | inventory row 4 (Mode B); `CLAUDE.md` Still-VERIFY item 8; README; docs/05, 07, 10; engine note 6.3; B.3. **Also the first OnionXT-to-OnionXT dial on record** |
| 4 | `onionxt/examples/onion-roundtrip/roundtrip-example.livecodescript`: two OXT processes (or two machines) plus tor plus sodiumxt | S2 / S4 | a sealed round trip | the `onionxt/IMPLEMENTATION-PLAN.md` Phase 4 line |
| 5 | Live negative paths: a wrong cookie gives authfailed; a bad onion gives a mapped REP; a stalled daemon times out cleanly | S2 | each fails closed with a readable reason | docs/09 q12; the Phase 6 done-bar |

**Doc fixes.**
- "Seven" exemptions in REMAINING-WORK and the runbook; the true count is 3.
  A live pass will not retire them anyway, only harness calls will.
- `onionxt/CLAUDE.md` ("Verified statically and pinned by seven") says seven
  socket-id fixtures still need an OXT pass; there are eight, and they ran
  2026-08-17.
- The "only Mode B is unexercised" headline, in the source header, README,
  docs/05, docs/10 and examples/README, understates what is open.
- docs/09 q7 does not record D-07.
- `docs/anon-transport-onboarding.md` and `docs/anon-transport-threat-model.md`
  still call decisions 14.1 and 14.4 open (closed by D-07 and D-05).
- The suite core's onionxt floor comment says ten sections; there are 11.

### 2.6 coinxt

**Where it stands.**
- 95 public handlers: 44 in the `.lcb`, 51 in script. Coverage 95/95.
- **ABI 7** in the shim, the `.lcb` and all five binaries (2026-09-12).
- Engine record, all on Windows x64:
  - phase 1 (2026-08-08);
  - phases 2-4 (2026-08-10, 207/207);
  - phase 5 (2026-08-12, 230/230);
  - WIF and ABI 5/6 (2026-08-17, 278);
  - BIP-341 (2026-08-24, 290/290).
- **ABI 7's `cxPubkeyCombine` (2026-09-10) has no engine run yet.**
- The wallet (`kWaVersion` 1.2.0, **13 screens**) has engine logs from
  2026-09-01 to 09-03, on testnet. They cover all four transports (Esplora and
  Electrum, over clearnet and Tor), RBF, CPFP, a legacy broadcast
  (`7978bdd2...`) and an inscription.
- Everything the wallet gained from 2026-09-04 is headless only:
  - the Ordinals and Vault screens;
  - the Bitcoin Core backends;
  - BIP-322, Runes, BOLT11;
  - testnet4 with BIP-329 labels;
  - the 2026-09-10 audit fixes;
  - silent-payment receiving.

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | Apply D-15: strike "SLIP-39 later" in `coinxt/README.md` ("SLIP-39 later"), `coinxt/SPEC.md` and `coinxt/docs/api-reference.md`; strike REMAINING-WORK E.8 | Decided 2026-08-27, never written through | S | none |
| 2 | Either wire `verify-independent-decoder.py --require` (with its pip installs) into the release job, or re-decide D-17 on true facts | D-17's premise is false (section 1.8); the check last ran 2026-08-13 | S | owner |
| 3 | `coinxt/SPEC.md` ("43 exports as built") has no `cnx_pubkey_combine`; the surface is 44 | Spec behind the code | S | none |
| 4 | Per-push CI is Linux only (C.6): add Windows lanes (a MinGW build plus KATs on a Windows runner, including a 32-bit Python for the x86 DLL) and a mac lane, or record that dispatch-only is permanent | The x86-win32 DLL has never executed anywhere | M | owner |
| 5 | Runbook rows for the four-family broadcast and for a Bitcoin Core regtest session (`coinxt/docs/bitcoin-core-plan.md` section 9 promises one) | B.8 and the Core backends are unscheduled | S | none |
| 6 | The rest of the Core plan: `verifymessage` and JSON-RPC batching | Named as what is left in the plan's own header | M | none |
| 7 | Restoring past the gap limit: a sync never extends the address window (named as open in `CLAUDE.md`, 2026-09-02) | A restored wallet can miss funds | M | owner (it changes what a sync is) |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | **Row Q**: the "secp256k1 keys" section (suite paste or `coinxt/tests/coin-selftest.livecodescript`), then `coinxt/examples/coin-wallet.livecodescript` on testnet. Pay the wallet's own `tsp1` address from Send, then paste that transaction alone on Tools and press Inspect. Run **row P** (the 2^53 probe) in the same session | S1 + NET (a backend, a little testnet coin) | the six `cxPubkeyCombine` lines green; Inspect logs "Asked <host> for the N transaction(s)" and repaints `FOUND:` from the socket callback; Save writes an `sp` line; a second Inspect makes no request | `coinxt/CLAUDE.md`'s 2026-09-10/11 entries; wallet.md's silent-payment section; the ABI7 tick; engine note 2.4 to OBSERVED |
| 2 | `coinxt/examples/coinxt-demo.livecodescript` | S1 | the card look; the test mnemonic's published BIP-84/BIP-44/ETH addresses; sign/verify; the P2WPKH and EIP-1559 txs decode | the demo header; the phase-6 line in `coinxt/IMPLEMENTATION-PLAN.md`; the tick |
| 3 | **B.8, the four-family broadcast.** Legacy P2PKH is done in substance (`7978bdd2...`, 2026-09-02) and only needs recording. Still to do: native P2WPKH from the wallet; EIP-1559 from the demo on Sepolia (the demo has no transport, so broadcast externally); EIP-155 from the message box (`cxEthLegacySighash`/`cxEthLegacyEncode`; no UI) | NET (testnet and Sepolia funds) | each tx accepted by the network | "one bar left before broadcastable" in README, SPEC, the plan, api-reference and getting-started |
| 4 | The wallet's post-09-04 surface: BOLT11 and a runestone Inspect (mainnet backend); BIP-322 from a taproot wallet checked in Core or Sparrow; a vault release after its height; the Ordinals/Vault screens; testnet4 + BIP-329 labels; the 2026-09-10 legs; Electrum on the mainnet onion (port 110) | S2 + NET | each section's own criterion | each wallet.md "Not run on an engine" line |
| 5 | A Bitcoin Core 26+ regtest node on the same machine: the Node-screen sandbox, `core-rpc`, `core-cli`; `core-tor` also needs the node published as an onion | S1 (+ tor) + a local node | as the plan's section 9 | wallet.md "Not run against a node" |
| 6 | Suite paste on a Mac, and on a 32-bit Windows engine | S5 | `cxCheckABI` silent; coinxt sections green | row 24's coinxt slot; the x86-win32 gap |

**Doc fixes.**
- wallet.md still ends its silent-payment, inscription and timelock sections
  "Not run on an engine", although the tenth log covered them (and `CLAUDE.md`
  says they were flipped).
- "Ten screens" in wallet.md, README and runbook row 16a; there are 13.
- wallet.md says coinxt had "two on-engine passes"; there were five.
- `docs/README.md` calls the Core plan "PLAN ONLY"; phases 1-4 landed
  2026-09-04.
- README and the root `native-coinxt.yml` cite the removed member `ci.yml`.
- The root README matrix says "The Windows DLLs still carry static checks
  only"; only x86-win32 still does.
- Engine note 6.9 and wallet.md disagree about whether Esplora over clearnet
  has an engine record. One of them is wrong.

### 2.7 nostrxt

**Where it stands.**
- Two files: the `nx*` core (81 handlers) and the `nxr*` relay client (23).
  Coverage 104/104.
- NIPs covered: 01, 19/21, 44 v2, 42 (build and answer), 13, 05, 11, and 65
  (build and parse).
- **The core is ENGINE-PROVEN 2026-08-24**: 274/0/2 in the suite paste; the 2
  skips are the relay section, deliberately absent from the paste. NIP-44 ran
  through the real ABI-10 cipher, and the non-BMP `textDecode` check passed.
- **The relay SEND half was live-proven 2026-08-24** against wss://nos.lol:
  connect, handshake, publish and ok-true. It was the suite's first
  `open secure socket`.
- Still owed:
  - the receive leg (REQ/EVENT/EOSE/CLOSED/NOTICE);
  - NIP-42;
  - every ws:// path;
  - TLS behaviour on a bad certificate;
  - the 2026-09-09 guard-nesting change, which is headless only.

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | Replace the placeholder floor 1 at the core's NostrXT merge site: `tests/suite-selftest.core.livecodescript` ("a first engine pass will give this member its measured floor"). Audit the CoinXT-absent and SodiumXT-absent skip branches first; the member attempted 276 items | The floor is how the paste notices a member silently doing less | S | none |
| 2 | Pin the 2026-09-09 refusals (`wss://h:abc/`, `a/abc`, delimiter survival) in `nostrxt/examples/nostrxt-tests.livecodescript`, then regenerate the carriers (suite paste, demo, riptide) | Today only the headless gate checks them, so the next engine pass cannot | S | none |
| 3 | Make row 34 drivable from the demo: a button that answers a NIP-42 challenge (the demo only logs "answer with nxAuthBuild + nxEventSign + nxrAuth"), and Unsubscribe / raw-send controls | Otherwise the auth round trip and a provoked CLOSED are message-box work | S | none |
| 4 | Fix the dangling onion-relay cross-reference (docs/08's "question 7" is JSON parse cost, and README, 00-overview and docs/07 cite it) | A reader dead-ends | S | none |
| 5 | Phase 9 optional NIPs: NIP-17/59 gift wrap (M-L; pin the published vectors first); NIP-65 outbox and a relay pool (M); `.onion` relays over onionxt, which need a transport seam in `nxrConnect` (M-L); NIP-44 extended length is blocked on upstream vectors | Scope, not debt | - | owner |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | **The receive leg**: `nostrxt/examples/nostrxt-demo.livecodescript`, Connect, then Subscribe (kind 1) | NET (public wss relay; CoinXT + SodiumXT installed) | `event (nd-notes)` lines verifying with no `REFUSED`, then end-of-stored-events | the receive half in `nostrxt/src/nostr-relay.livecodescript`'s STATUS; docs/05; README; `CLAUDE.md` gotcha 7; the root README relay row |
| 2 | NIP-42 plus CLOSED/NOTICE (after coding item 3) | a relay that demands auth (a local daemon configured for it) | an `auth` challenge; `ok <id>: true` for the kind-22242 event; a `closed` reason starting `auth-required:` | docs/05 VERIFY item 9 |
| 3 | The ws:// leg | a local relay daemon (nostr-rs-relay or strfry) on loopback | open, publish ok, subscribe returns the event | "every ws:// path" in each STATUS block |
| 4 | **A bad certificate**: point the demo at a self-signed, expired or wrong-host TLS endpoint | NET | a `socketError` means the engine refuses bad certificates; reaching "the server did not upgrade" means it **fails open**. Record either result | engine note 6.8 (the only observation that can move it); docs/07 gap #2 |
| 5 | The demo's own test button (`ndTests`): the "relay layer, offline paths" section, including the split contract that `nxrSocketError` disowns a foreign socket. It SKIPs in the paste and has never run anywhere | S1 | 17 sections, 0 failed, 0 skipped | the relay harness label |
| 6 | Message-box probes: row P(b) (the `or` short-circuit, engine note 2.5, which the 2026-09-09 fix rests on); raw `base64Encode` emission (docs/08 q1) | S1 | as the runbook states | engine notes 2.5; the VERIFY at the base64 site |

**Doc fixes.**
- "wss:// written but engine-unproven" in `nostrxt/CLAUDE.md`, README's diagram,
  docs/06 and docs/09. Each contradicts its own file's STATUS block.
- NIP-44 "needs an OXT pass" at two sites in `nostrxt/src/nostrxt.livecodescript`,
  carried verbatim into the demo, the paste and riptide.
- NIP-17 "blocked on phase 8" (phase 8 closed 2026-08-23).
- The demo header calls the certificate "VALID", which note 6.8 calls circular.
- Runbook 4.9's heading still says "the member with NO engine evidence yet".
- Row 34 sits in no session, and its tick line has no slots for receive,
  NIP-42 or bad-cert.

### 2.8 box2dxt

**Where it stands.**
- Box2D v3.1.0: 376 public `b2*` handlers plus the pure-script Kit's 313 `b2k*`.
- Kit coverage 313/313. The raw binding is 131/376 named by some script; the
  other 245 are the armed baseline.
- Engine record:
  - harness v29: 374/374 on Windows (2026-08-17), 373/1 on Linux
    (2026-08-18);
  - harness v30: **375/0 on Windows (2026-08-20)**, 374/1 on Linux
    (2026-08-21). The one Linux line is `playLoudness` readback (engine note
    5.4), a harness assumption rather than a Kit defect.
  - The harness is at v31 now (374 expected), with no v31 record of its own.
    The 2026-08-24 whole paste had zero failures, which makes v31 green at
    inference strength only.
- Binaries: all five platforms. The release lane has existed since 2026-08-23.
  The universal-mac dylib (ABI 4) has never been loaded by an engine.
- CI: the smoke test enters all 370 LC_API exports under ASan/UBSan.

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **Harness assertion + bump to v32** for the 2026-09-09 Kit delimiter fix (`51ac525` changed ten Kit handlers and left `kStHarnessV` at 31). Add a tab-delimited call through `b2kAddBox`/`b2kHinge`, bump per `box2dxt/examples/box2dxt-selftest.livecodescript` ("bump on EVERY harness change"), and rebuild the paste | The member's own rule; the fix has no engine-facing test | S | none |
| 2 | **x86-linux glibc regression, 2.17 to 2.34.** Build that release row in a `manylinux2014_i686` container, as `native-box2dxt.yml` already does, or state the floor. `box2dxt/README.md` ("glibc 2.17 floor") is wrong for it | Section 1.3; a silent portability regression | M | dispatch; revisit D-03 |
| 3 | Complete the reference docs: api-reference names about 217 of 376 handlers; kit-reference 242 of 313 (missing `b2kPlayerDuckSet`, `b2kPlayerTick`, `b2kSyncAll`, `b2kEnsureNativeLib`) | The README's own "Incomplete" note | M | none |
| 4 | Polish-plan work that can be done in the tree: tuck the dev level-picker behind the debug key (section 6); sweep the dead camera-fallback code (section 7); extend `box2dxt/tools/audit-platformer.py` to level 7, which it skips today | A.16's code half | M | none (scenery is the owner's eye: `box2dxt/docs/platformer-polish-plan.md` ("composition needs a human eye")) |
| 5 | The raw `b2*` script ratchet (245 handlers named by no script) | Blind assertions against a foreign-bound API would mostly be test bugs | L | engine |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | Suite paste on Windows **and** Linux | S1 | box2dxt 374/0 at v31, or v32 after coding item 1. Record the total rather than matching it; Linux prints the `playLoudness` observation as a note | inventory row 31; the selftest STATUS; root README harness lines; B.5's harness clause |
| 2 | The five games from `start-here.livecodescript`: `box2dxt-demo`, `-platformer`, `-slingshot`, `-contraption-builder`, `-spike-gamekit` | S1 (Win + Linux) | each builds on **first** open (the 2026-08-27 launcher fix, itself unverified: note 5.5); the contraption Images panel does not throw (the delimiter fix); the platformer card fade reveals the level and the L7 vertical camera works; slingshot's own seven-item list passes | each example's STATUS; the tick sheet; B.1/B.5 |
| 3 | **Risk R1**: `box2dxt-spike-gamekit` on Linux and macOS, recording S1-S12 verdicts | S1 Linux + S5 Mac | the verdicts | `box2dxt/plan.md` ("macOS/Linux verdicts are still open"); the spec's R1 row |
| 4 | First Mac load: install the `.lce`, `put b2Version()` returns 4, then the paste section and the spike | S5 | as named | "no Mac has ever loaded it" |
| 5 | Polish plan section 9: the feel, facing, scale and audio pass on the platformer, with the owner | S1 + PERSON | all 7 levels; sprites face right; tunables locked; every action cued | the section 9 boxes |
| 6 | Fresh-machine package run (`box2dxt/tools/make-release.py`, then install on a clean machine) | S1 (clean box) | installs and runs | section 9 "Packages clean" |

**Doc fixes.**
- C.3 (section 1.6).
- The v30/v31 records disagree across the selftest header, the tick sheet,
  root README, B.5 and polish-plan section 9. One sweep should state: v30
  375/0 Windows 2026-08-20, 374/1 Linux 2026-08-21; v31 unrecorded.
- The selftest's "crawl stall STILL OPEN" comment; the stall was fixed at v28.
- "Phase-2" wording that outlived D-18, in `tools/check-ui-kit-drift.py` and
  `CLAUDE.md`.
- The launcher describes the selftest as exercising "the b2* binding surface";
  it drives the Kit.
- `box2dxt/dist/INSTALL.md` predates the title screen.

---

## 3. The apps

### 3.1 riptide

**Where it stands.**
- Library 0.12.0: 106 `rs*` handlers, coverage 106/106.
- The five-card demo embeds nostrxt (core + relay), riptide, onionxt and
  onion-httpd. Gates green, including `check-demo-boot` (44 checks, two
  capability profiles).
- Phases 1-2: engine 2026-08-12, two machines 2026-08-13. Phases 3-4: two
  machines 2026-08-15.
- The phase-3 mid-download question was **measured negative 2026-08-27** and
  fixed the same day (`raMediaFrontReady`). The re-run is owed.
- **Phase 5 has never run.** The compute halves of phases 6-7 are engine-green:
  2026-08-15, 2026-08-20 (338/0/2) and 2026-08-24 (391/0).
- On 2026-09-09 the LAN domain tags became prefix-free (`riptide-lan-a` / `-w`
  / `-s`), a security fix for a signature-domain collision. The engine-green
  admission bytes are therefore superseded.
- Phase 8's card boot was reported working 2026-08-29. The v11 boot read 9/1,
  and the one FAIL was the self-check's own defect, since fixed.
- The harness sections added after 2026-08-24 are static only: the Nostr and
  app-state sections, the watermarks, the u64 bound and the 996-byte cap.

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **A bridge reader in the app.** `rsRequestBridge`, `rsIngestBridge` and `rsNostrBridgeFromEvent` have no app caller (`riptide/CLAUDE.md` ("ingests a foreign bridge yet")). Persist its `pMinSeq` watermark in RIPTAPP1 as `sHeadSeen` is | Phase 8's done-criterion needs the bridge resolved in **both** directions; step 6 of the runbook cannot be done from the UI | M | owner (scope) |
| 2 | **Decide RSL1's magic** after the 2026-09-09 tag change. Rule 3 says wire formats bump their magic; the commit changed the signature preimage without a bump and without a compatibility note, so a pre-09-09 device and a post-09-09 device silently fail admission | Protocol hygiene; also dictates the phase-6 two-machine setup | S | owner |
| 3 | LAN keys may collide by case: `raLanSyncReceive` keys `sLanPeerSeq`/`Tick`/`Draft` by `tRec["name"]` without `caseSensitive`, and the engine folds array-key case (note 2.7, OBSERVED). "Phone" and "phone" would share a seq slot. The painters do set `caseSensitive`. Inferred, not observed | The C6 silent-drop shape | S | none |
| 4 | Own-head refresh while online: the demo re-puts its BEP44 head only on post, BEP44 items expire, and D-06 rules out follower republish, so author refresh is the only retention | Feeds go dark | S-M | owner (cadence) |
| 5 | Scripts for the post-2026-08-23 features in `riptide/docs/two-machine-runbook.md`: the kind-C long post, the profileMeta reader, the `rtt/loss` suffix, watermark persistence across restart. Plus suite-runbook rows for the phase-8 live leg, the faststart re-run and phase-6 steps 7-8 | They are built and unscheduled | S | none |
| 6 | Spec deltas: spec 4.1's profileMeta "avatar info-hash and bio" versus the display-name bytes that are built (and normative in `RIPTIDE-PROTOCOL.md` section 4); 4.4's followers-only sealed media is unbuilt and not marked deferred | Spec and protocol disagree | S | none |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | **Row 35**: paste `riptide/examples/riptide-social.livecodescript`, fresh launch; then, with CoinXT, the Nostr card offline | S1 | boot self-check **10 passed / 0 failed**; an npub appears; Post reports "not sent" with no relay; RIPTAPP1 save/load round-trips | row 35; the v11 label in `CLAUDE.md`; the examples/README phase-8 label |
| 2 | Suite paste | S1 | riptide 0 failed, 2 skips (the live anon-service legs); the first engine run of the phase-8 and app-state sections, and admission re-established on the new preimage | the post-08-24 section labels |
| 3 | Phase 7 serving half (two-machine runbook, steps 1-5) | S2 | the onion page in Tor Browser; `/prekey` returns 264 hex and `rsVerifyPrekey` accepts it; `/dm` answers `accepted`, and `refused` when mangled | row 19's serving half |
| 4 | Phase 5, the call and the typing lane | S3 across two networks | `CALL CONNECTED` on both sides; a `typ srflx` `via` line; typing appears and clears; the "closed the conversation" line | row 16 |
| 5 | Phase 6, steps 1-11 (with a third device or a second instance). Every device must run the post-2026-09-09 build | S3 (+ third device) | mutual ADMITTED; drafts converge both ways; `[typing]`/`[quiet]`; feed seq adopted; the media handoff; B lists A and C; the stranger refused | row 17 |
| 6 | Phase 7 finishing half | S4 | `accepted` with the PROVEN sender; zero `bt*` calls in a trace | row 19 |
| 7 | Phase 8 live, steps 0-9 | NET (public relay; a second machine optional) | the npub resolves in a web client; relays `OPEN`; `publish -> true`; a verified follow timeline (**depends on nostrxt's receive leg**); both bridge halves (needs coding item 1); the guard refuses `nostr` for anon | spec 10.3 item 8; README; `CLAUDE.md` |
| 8 | Phase-3 faststart re-run | S3 | playback starts while visibly below 100% | the mid-download question, in four places |

**Doc fixes.**
- E.3 and B.4 (section 1.6).
- The source header, api-reference and README call the 2026-08-23 handlers
  unrun; their compute ran 2026-08-24.
- The mid-download question is still called unmeasured in four places.
- `CLAUDE.md` says the demo "carries three libraries"; it carries five.
- `docs/README.md` says 90 handlers; there are 106.
- The boot runner is counted as 38 or 40 checks in the docs; it prints 44.
- Two-machine runbook phase 8 step 1 names a retired button.

### 3.2 nocloud

**Where it stands.**
- One stack, `nocloud/src/nocloudquickshare.livecodescript`, serving over a
  web link or Tor. It has carried onionxt embedded since 2026-08-24.
- **No dated engine pass of this stack is recorded in the tree.** The
  App-layer lessons come from undated pre-fold passes, and the header
  re-opened everything at the 2026-08-14 kit adoption.
- Gates are green: `check-script-vectors` ran 435 checks and caught 4 of 4
  seeded defects.
- The pass checklist has **69 items, none ticked**.

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | Fix OnionXT wording that the embed made wrong: `qsCapabilityLine` still prints "OnionXT not in the message path" (`nocloud/src/nocloudquickshare.livecodescript`), `qsLog` says "install OnionXT + SodiumXT", and there are two stale VERIFY comments. Checklist section 8's "Without OnionXT" can no longer be produced; replace it with "no Tor daemon" | Users get install advice for something they already have | S | none |
| 2 | Write the decisions through: D-09 (close-per-response) into the http-server deep-dive (lines 64, 454-457 and table 1.1); D-02's deferral into section 8; section 3.4's two watch-items are already pinned | Ledger rule | S | none |
| 3 | Gate-count drift: README, CONTRIBUTING and the checklist say "two gates"; there have been three since 2026-09-11 | A contributor runs two | S | none |
| 4 | After the mtime probe (D-10): build a restart-stable mtime ETag plus `Last-Modified` with golden mirrors, or record "design confirmed" in the deep-dive, D-10 and `webapp/sw.js` | Closes the one decided-but-unrun question | S-M | engine |
| 5 | Unbuilt phases: `/_qs/health` and the `/_qs/info` `encrypted`/`uptime` fields (Phase 0 residue); `Last-Modified` (Phase 1); `qsHttpReplyStream`/SSE (Phase 3 residue); all of Phase 4; Phase 5's rename/mkdir, shares admin and live-reload | Recorded roadmap | L | D-02 (deferred; revisit on the first external report) |
| 6 | *(optional)* A headless boot gate on riptide's `riptide/tools/check-demo-boot.py` pattern | Would exercise the TorrentXT-absent guard and `qsScRun` without an engine; coinxt, riptide and holde-em have one | M | none |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | **Web-link half**: paste the stack and reopen, then checklist sections 0-6a over `/<token>/` from a LAN browser plus `curl -i`, with a second-origin page for section 5. **The D-10 mtime probe is in section 4** | S1 (torrentxt + sodiumxt installed) | the boot record reads "all 49 controls" PASS; each checklist line's own expectation. Budget 60-75 min, not 35: section 2's "without JSON" needs a relaunch | row 22's web half; the header re-pass label; the deep-dive's web labels; **D-10 closes** |
| 2 | **Tor half**: sections 1, 1a and 4 over the `.onion`. `/_qs/transparency` gives `both_ends_hidden:true`; HEAD gives 0 body bytes; concurrent shares see only their own routes; `/_edit` 404s; section 6a's "no editor here" card; the service worker registers over `.onion` | S2 (+ Tor Browser, `curl --socks5-hostname`) | as listed; also settles the app's own Tor VERIFYs (serviceReady `pInfo`, `oxStreamState`) | row 22's Tor half; the OnionXT block label; B.3's "nocloud's Tor path" |
| 3 | Unscheduled sections. Section 7's webapp web-link half: Theater/Music `206`, `?dl` `.wav`, `pushState` reload/paste/Back, the `file://` fallback. Section 8's fail-closed launches, without SodiumXT and without TorrentXT, each needing an uninstall and a fresh launch. A clean shutdown via standalone Cmd-Q, which needs a standalone build | S1 (+ a standalone build) | each line's expectation | CLAUDE.md gotcha 8; the checklist's own tallies |

**Doc fixes.**
- B.9's count; E.5's citation and its "waits on Phase 3" (built 2026-08-16);
  A.14 contradicts D-09.
- D-11's cite has moved (`kAnonSizeWarn` is now near line 2407).
- Runbook S2 says nocloud "still wants the optional `start using`"; it embeds
  onionxt.
- `docs/README.md` points at an "honest status" the README does not have.

### 3.3 holde-em

**Where it stands.**
- **v0.25.3, harness 44**, an 18,436-line stack carrying onionxt.
- Built: Phase 1 hotseat; 2d online Level 0; 2e liveness; 2f onion tables;
  Phase 3 oracle; 4a-4e Level 2 compute with void-and-audit and the cheater
  bots; Phase 5 DLEQ; 4f's batch mask step.
- Engine record, folded into the suite paste on Windows: 507/0 (2026-08-16),
  538/0 (2026-08-17), 543/0/5 (2026-08-20), 584/0 (2026-08-24) and **667/0
  (2026-08-27, v0.25.2, harness 43)**.
- Played by a person: three heads-up hotseat hands (2026-08-17), and a first
  two-machine 2d contact (2026-08-27). In that contact, joins worked and the
  hand dealt, but underneath the lobby overlay, which v0.25.3 fixes
  (statically).
- Coverage 158/330 game handlers: 20 live-transport, 9 engine-media, 41
  host-window and **102 with no test**. The floor is armed.

**Coding work.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **Wire Level 2 into played hands.** The dealLevel gate still refuses anything but 0 and 1 (`holde-em/src/holdem.livecodescript` ("unsupported deal level")). Needed: `shuffleStep`/`unmaskStep` on the wire, a `level=2`/`dleq=1` table config, the orchestration and a netsim section | The 4d machine it drives is pure and engine-green, but README says "nothing plays on Level 2 yet". It blocks the Phase 4 exit and 4f | L | none |
| 2 | The Phase 1d / spec 11 animations: none exist (`b2kForce` has 0 call sites; the one `b2kSpriteMoveTo` is pool placement) | B.11 calls them polish; they are unbuilt | M | engine (tuning eye) |
| 3 | **A third leaf tranche over the 102 untested handlers**, consensus-critical first: `heNetEngineFold`, `heNetTimeoutRearm`, `heNetTurnClockStart` (the v0.24.0 fixes), `heHandSettle`, `heBetPay`, the `heL2*` point helpers | Consensus code that no test names | M | none |
| 4 | BEP44 profiles and standings (spec 5, plan 2a): the `btDht*` calls have 0 call sites, yet README and `CLAUDE.md` advertise them | Build it or strike it | M | owner |
| 5 | Seven to nine seats (a spec 1 goal; the build is 2-6) | Build it or strike it | M | owner |

**Engine work.**

| # | Run | Where | Green looks like | Flips |
|---|---|---|---|---|
| 1 | Suite paste, then `holde-em/src/holdem.livecodescript` standalone with `heRunSelftest`, and 2-3 hotseat hands | S1 | holde-em at v0.25.3/v44, 0 failed, 5 skips. **Record the total rather than matching 667.** Then `RESULT: green`; hands complete | the 2026-09-09 ten-field checks' "runs on the next engine pass"; runbook S1 items 2 and 4 (**change 4's expected version to 0.25.3**) |
| 2 | Phase 1 exit: a full 6-seat hotseat session with side pots and all 17 cards on screen, plus the confirming eye on the 720p layout | S1 | as named | the `holde-em/IMPLEMENTATION-PLAN.md` Phase 1 exit; B.11 |
| 3 | Row 20 bring-up | S2 | Tor pill states; the invite `<64hex>@<56base32>.onion`; derived address == `oxServiceAddress` | row 20's single-machine half |
| 4 | Row 18: a 2d re-run on v0.25.3 (multi-hand, receipts matching on every seat, the overlay dismissed at handStart). Row 28: the timed liveness session (wall-clock timeouts, the bank arming once per hand, two misses sitting a seat out, a late join, a parked table resuming), plus an attempt at the recorded KNOWN EDGE | S3 (3+ seats via extra instances) | as named | the 2d and 2e "needs the multi-machine OXT pass" lines |
| 5 | Row 20 exit: a multi-hand onion session, plus a real host-stream loss followed by redial and a trimmed resync | S4 | as named | the 2f entries |
| 6 | Phase 3 exit: two players plus a non-playing onion oracle, with the oracle killed mid-hand, then void and resume | **3M + tor**; no session type exists for it | as named | the Phase 3 exit |
| 7 | 4f and the Phase 4 exit | after coding item 1 | - | - |
| 8 | The Phase 5 hostile review and soak | PERSON | - | the Phase 5 exit |

**Row 14** (the deal-path re-pass) **can close at inference strength**, the way
row 26 did:

- Section 11's "seeds XOR" and "full shuffled deck" assertions have run green
  in every folded run since 2026-08-17.
- Engine note 3.1 (OBSERVED: `step` is not honoured) answers the pre-fold
  stream question.

**Doc fixes.**
- Several places still say the member's ristretto/DLEQ calls "have never run
  on an engine": README lines 91 and 216, `CLAUDE.md`, the spec (477 and
  section 14), the plan, and a source banner. Rows 15 and 27 closed that on
  2026-08-17.
- Version drift: `CLAUDE.md` says v0.24.5, README and the plan say v0.25.0,
  and REMAINING-WORK says v0.23.0. The source changelog stops at v0.25.1.
- The 2026-08-27 session (667/0, first 2d contact) is recorded only in the
  runbook.
- README still says `start using stack "onionxt"`, and advertises unbuilt
  BEP44 standings and chip physics.
- Several docs cite the removed `ci.yml`.
- D-21 and D-18 have not been written through into the spec and
  `CLAUDE.md`.

---

## 4. Recommended order

This is advisory, like the recommendations in OPEN-DECISIONS: a route, not a
decision.

### 4.1 Before the next engine session (headless, this tree)

1. **One truth-sync change** covering:
   - section 1.5 (record the publishing success);
   - section 1.6 (strike or annotate the REMAINING-WORK entries);
   - section 1.7 (the runbook drift, especially S1 item 4's version and the
     unscheduled rows);
   - each member's "Doc fixes".

   This is what keeps the next session from spending minutes on stale
   expectations. Size M in total, but mechanical.
2. **The small code fixes that make the next engine run observe more.** Each
   is S, blocked by nothing, and gated where a gate exists:
   - box2dxt harness v32;
   - nostrxt's 2026-09-09 refusals into the harness, and the placeholder
     floor;
   - onionxt's three exemptions retired offline, and `oxLaunchTor`'s result
     checks;
   - torrentxt's boundary tests and the quickshare HEAD ports;
   - enetxt's disconnect smoke block;
   - riptide's LAN `caseSensitive`;
   - nostrxt's NIP-42 demo controls;
   - the datachannelxt open-instruction fixes.

   Regenerate the suite paste and the demo embeds once, at the end.
3. **Release-lane decisions, then one dispatch.**
   - Decide the Windows upstream pins (1.2) and the Linux glibc floor (1.3).
   - Land torrentxt ABI 12 in the same change.
   - Dispatch `release-binaries.yml` once.

   That dispatch gives the engine session one coherent set of binaries rather
   than proving 2026-09-12's and then replacing them. If the owner prefers to
   prove what ships today first, run 4.2 and then dispatch. Either order is
   honest; mixing them wastes a pass.

### 4.2 The engine sessions

**S1, on Windows, then on Linux (glibc 2.38 or newer).** Quit and relaunch OXT
before each torrent-bearing paste (trap 5.1.1). The session has grown well past
the runbook's hour; roughly 3-4 hours with everything below, as an estimate.

1. `tests/preflight.livecodescript`. Record every member's LOADED line and ABI.
2. `tests/suite-selftest.livecodescript`. **Record** each member's total
   against these expectations:
   - sodiumxt 106 and torrentxt 101;
   - nostrxt 274/0/2;
   - riptide 0 failed with 2 skips;
   - box2dxt v31/v32;
   - holde-em v44.
3. Row P probes, and row Q (coinxt ABI 7). Row Q's wallet half needs NET.
4. Row 35: the riptide-social boot and the Nostr card offline.
5. holde-em standalone, with hotseat hands and, if time allows, the 6-seat
   Phase 1 exit.
6. The demo re-opens, one fresh launch each:
   - `torrent-quickshare`, `torrent-dht-channels`, `torrent-client`,
     `torrent-rp1-chat`;
   - `onionxt-demo` (no tor) and the onion-httpd spike;
   - `datachannel-loopback`;
   - `coinxt-demo`, `sodium-demo`;
   - `nostrxt-demo`'s offline test button;
   - the five box2dxt games.
7. The standalone `enet-selftest` and `datachannel-selftest`.
8. nocloud's web-link half, with the mtime probe.

**The later sessions:**
- **S2** (one machine plus tor):
  - onionxt demo live with the B.12 probes;
  - **leg F (Mode B)**;
  - the Quick Share Tor toggle and #31;
  - riptide phase 7 serving;
  - holde-em row 20 bring-up;
  - nocloud's Tor half;
  - onionxt's negative paths and round trip.
- **S3** (two machines):
  - closing-pass legs B-E;
  - the enet LAN chat and the DHT chat;
  - riptide phases 5 and 6, and the faststart re-run;
  - holde-em rows 18 and 28.
- **S4** (two machines plus tor):
  - #32 and #33 (which settles D-04);
  - the Model C gate;
  - riptide phase 7 finishing;
  - holde-em row 20 exit.
- **S5:**
  - Windows 32-bit and 64-bit re-proofs (sodiumxt row 23, coinxt x86);
  - the Mac first loads for all six native members;
  - box2dxt R1 on macOS.
- **NET and 2NET:**
  - the nostrxt receive leg, NIP-42, ws:// and the bad-certificate test;
  - riptide phase 8 live;
  - the coinxt four-family broadcast and the wallet's post-09-04 surface;
  - torrentxt real-swarm interop;
  - `enet-internet-chat` and the datachannelxt two-network call;
  - browser interop, after its harness exists.
- **3M:** the holde-em Phase 3 oracle round.

### 4.3 What only a person can close

- D-04's wording, and the owner calls listed in section 1.8.
- The box2dxt scenery and feel pass.
- holde-em's Phase 5 hostile review and soak.
- The Phase 4 exit of `docs/anon-transport-onboarding.md`: a fresh user
  completing it on each OS.
