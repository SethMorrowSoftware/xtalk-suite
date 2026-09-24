# Work plan: what each member still needs

**The single LIVE list of open work for the suite**, per member and suite-wide.
Last re-audited 2026-09-23: every member was reviewed against its own tree (code,
tests, committed binaries, git history) at `e3d2496`, and the list was refreshed the
same day, after the docs consolidation closed its doc-fix items. The open items that
consolidation's review and repair passes found were added 2026-09-24, each checked
against the tree first.

Where the rest lives: each engine leg's full green criterion, and the labels it flips,
is its numbered row in [OXT-PASS-RUNBOOK.md](OXT-PASS-RUNBOOK.md) section 1.2 (this
plan cites the row); owner decisions are in [OPEN-DECISIONS.md](OPEN-DECISIONS.md);
closed results are in each member's `CLAUDE.md` evidence ledger and runbook section 8;
engine behaviour is in [OXT-ENGINE-NOTES.md](OXT-ENGINE-NOTES.md).

**The rule.** When an item closes, delete it here in the same change, and record the
result at its primary source (the member's ledger, the runbook). Re-read the tree,
not the entry: descriptions rot and checks do not, so work that turns a description
into a check ranks above work that re-describes. This document claims no engine
result. Every "engine-proven" below quotes a dated record already in the tree.

## How to read it

- **Size:** S = hours, M = a day or two, L = a multi-day workstream.
- **Blocked by:** `none`; `D-xx` (a decision in OPEN-DECISIONS) or `owner` (a call
  with no brief yet); `dispatch` (a `release-binaries.yml` run, which suite rule 5
  reserves for a person); `engine` (waits on an engine finding).
- **Where** uses the runbook's session types: S1 one machine, no daemon; S2 one
  machine plus tor; S3 two machines; S4 two machines plus tor; S5 a Mac, or a Windows
  box (32-bit engines too). Beyond those: NET internet only (a public relay, testnet
  coins, a real swarm); 2NET two machines on different networks; 3M three machines;
  PERSON a human judgement (a review, a feel pass).
- Each member has a **Coding** table (work in this tree) and an **Engine** table (a
  run). The engine table's Row column is the runbook row; `-` means no row exists yet.
- **Numbers are stable.** A closed row is deleted and its number is never reused, so
  a table can have gaps: rows cite each other ("1.2 #2", "2.2 coding #3").

## At a glance

| Member | Latest dated engine record | Headless work open | Engine work open | Needs |
|---|---|---|---|---|
| sodiumxt | `sxSelfTest()` 106/106, Windows x64, 2026-08-24 (on a mingw DLL that no longer ships) | only optional: the unbound length accessors | Windows re-proof of the MSVC DLLs (both bitnesses); first Mac load; Linux at ABI 10; the demo | S1, S5 |
| torrentxt | harness 101/101, Windows, 2026-08-17, 08-20 and 08-24; suite paste green 2026-08-27 (platform not recorded) | ABI 12 alert codes; Windows libtorrent pin; the shim's btih hex check; a route-key golden mirror | first contact with the 2026-09-12 binaries; demo re-opens; Tor toggle and #31-#33; closing-pass C/D; a real swarm | S1-S5, NET |
| enetxt | folded 34, 2026-08-20; async loopback 2026-08-13 | only optional: the freshness gate's Windows DLL ABI read | standalone selftest; leg B and the LAN chat on two machines; internet chat; Mac | S1, S3, 2NET, S5 |
| datachannelxt | folded 39, 2026-08-20; standalone async loopback 2026-08-15 | owner calls only: the Windows OpenSSL pin and notice; the legacy shim removal | loopback demo (no record at all); leg E; two-network call; browser interop; Mac | S1, S3, 2NET, S5 |
| onionxt | offline self-test 61/0, Windows, 2026-08-17; the live-Tor core from the early bring-up | Mode B's lifecycle (after leg F) | Mode B (leg F); the B.12 probes; negative paths; the round trip | S1, S2, S4 |
| coinxt | 290/290, Windows x64, 2026-08-24; wallet logs to 2026-09-03 | D-17; per-push Windows/mac CI; Core residue; gap limit | row Q (ABI 7, silent payments); demo; broadcast; the wallet's post-2026-09-04 surface; Core regtest | S1, S2, NET, S5 |
| nostrxt | core 274/0/2 and relay SEND live, both 2026-08-24 | owner scope only: phase 9 (NIP-17/59, the outbox, `.onion` relays) | relay receive, NIP-42, `ws://`, a bad certificate, forced negatives | S1, NET, a local relay |
| box2dxt | harness v30 375/0 Windows 2026-08-20, 374/1 Linux 2026-08-21 | x86-linux glibc regression; platformer polish | the v32 total; the five games; R1; first Mac load; feel pass | S1, S5, PERSON |
| riptide | phases 1-4 on two machines (to 2026-08-15); compute of 6-7, 391/0, 2026-08-24; phase-8 boot 2026-08-29 | bridge reader; RSL1 magic; own-head refresh; per-identity app state | row 35; phases 5, 6, 7 live; phase 8 live; faststart re-run | S1-S4, NET |
| nocloud | no dated pass of this stack in the tree | mtime ETag after D-10; the D-02 menu (deferred) | the 69-item checklist, web-link and Tor halves; sections 7-8 | S1, S2 |
| holde-em | 667/0 folded, 2026-08-27 (v0.25.2) | **Level 2 not wired into play**; animations; 88 untested handlers | the v45 total; Phase 1 exit; 2d/2e/2f on real machines; the oracle round | S1-S4, 3M, PERSON |

Suite coverage on 2026-09-24: **867/878** public handlers exercised by the suite
harness; the 11 exemptions are all onionxt's (engine socket callbacks and watchdogs). holde-em's advisory row reads 172/330
and box2dxt's raw `b2*` row 131/376, each with an armed floor. Run
`python3 tools/check-suite-coverage.py` rather than trusting these numbers.

---

## 1. Suite-wide

### 1.1 Facts that shape the work

**The 2026-09-12 binaries have no engine record.** `release-binaries.yml` run
`34657390798` from `0f17ab5` was committed as `421bab3` on 2026-09-12. That commit
replaced every Windows DLL (all six members, both bitnesses) and the Linux and mac
libraries of torrentxt, enetxt, datachannelxt and coinxt. It left sodiumxt's Linux and
mac files and box2dxt's Linux files unchanged: those are still the release run 12 files
(`cec1e85`, 2026-08-27). box2dxt's universal-mac dylib shows one commit in git, the
2026-08-14 fold (`6070585`), but it is not a stale build: both release runs built,
verified and installed it, and each installer log says "(unchanged)", a sha256 match
(the shim and its build have not changed since the fold; runs 33025459610 and
34657390798, read 2026-09-24). Git records only changes, so since 2026-09-24 the
release commit's message carries the installer's per-library verdicts. No native source has changed
since `421bab3`. The latest dated engine records predate it: the 2026-08-24 paste, the
2026-08-27 two-machine paste and holde-em fold, the 2026-08-29 riptide boot, and the
2026-08-31 to 09-03 coin-wallet logs. The 2026-08-27 paste (2440/2/3) does not record
which platform or binaries it loaded. So the first S1 is the first engine contact for
the 2026-09-12 binaries, not necessarily for every file committed today. Record which
DLL or `.so` row loaded; a regression there is a finding about those builds.

**Windows ships different upstream versions from Linux and mac.** sodiumxt's MSVC
DLLs carry libsodium 1.0.22 against a pinned 1.0.20 (accepted by D-08, documented).
torrentxt's carry libtorrent 2.1.1 from vcpkg's unpinned port against 2.0.11: **no
decision covers it**, and its first Windows engine run is owed. datachannelxt's
statically carry OpenSSL 3.6.4 (vcpkg, unpinned) against the mac dylib's pinned 3.5.4;
Linux links the system `libssl.so.3`.

**Linux glibc floors** (the highest `GLIBC_` symbol each committed library needs,
from `objdump -T`, measured 2026-09-23):

| Member | x86_64-linux | x86-linux | Stated in the member's docs |
|---|---|---|---|
| sodiumxt | 2.33 | 2.33 | not stated |
| torrentxt | **2.28** (manylinux, static OpenSSL) | **2.38** + `libssl.so.3` | yes, README |
| enetxt | 2.14 | 2.28 | yes, `enetxt/docs/building.md` |
| datachannelxt | **2.38** | **2.38** | yes, README and building |
| coinxt | 2.25 | 2.25 | yes, `coinxt/CLAUDE.md` |
| box2dxt | 2.17 | **2.34** (2.17 before run 12) | yes, README |

The 2.38 floors come from C23 `__isoc23_strtol` and friends, `arc4random` and
`_dl_find_object`. They mean **datachannelxt cannot load on Ubuntu 22.04 (2.35),
Debian 12 (2.36) or RHEL 9 (2.34)**, nor can torrentxt's 32-bit build. The S1 Linux
machine needs glibc 2.38 or newer to load all six members.

**Platform rows with no engine record** (runbook rows 23, 24, 47): universal-mac for
all six members (CI built and tested every dylib; box2dxt's was rebuilt
byte-identical by both release runs, see above); x86-win32 for sodiumxt, torrentxt and coinxt (whose 32-bit DLL has not
executed even in CI: its Windows KAT step is x86_64 only); x86-linux for sodiumxt and
torrentxt.

**State writes are best-effort, not durable.** No `.c`, `.cpp`, `.h` or
`.livecodescript` file in the tree calls `fsync`, `fdatasync` or `FlushFileBuffers`.
The tree has no atomic replace either: `rename file` appears only in one
download-completion helper, copied three times (nocloud, `torrent-quickshare`,
`torrent-dht-channels`), and no state-writing path uses it. The house safe-write is
delete-then-recreate, motivated by a claim the tree carried as fact, that `open file
... for binary write` does not truncate a longer file; engine note 6.14 (2026-09-24)
files that claim as UNEVIDENCED, because the LiveCode reference and engine source say
write mode DOES truncate. Delete-first is right under both readings, and neither
in-place form is crash-safe: only write-to-temp plus `rename` keeps the old bytes until
the new ones are whole. The research found no recorded run that restarted a process
and read its own state back. The first run scheduled to do that is torrentxt closing-pass leg C,
which resumes across an OXT restart (2.2 Engine #4).

**Publishing is live.** `publish-members.yml` run 3, attempt 2, adopted and published
all eleven member repositories at 16:11 UTC on 2026-09-23 (recorded in
[MEMBER-REPO-SPLIT.md](MEMBER-REPO-SPLIT.md)). CoinXT's own `gates.yml` pays the
multi-hour wallet-gate cost on every publish (that file's section 9).

**Permanent exemptions, recorded rather than open:** onionxt's 11 engine-socket
coverage exemptions (only the engine can mint a socket id); `release-binaries.yml`'s
manual dispatch (rule 5); the harness scaffold's non-adoption of the UI kit (D-18).

### 1.2 Coding and doc work

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **Choose a suite Linux glibc floor.** Move each Linux release row into a manylinux container (as torrentxt's x86_64 row and box2dxt's per-push lane already do), or publish every measured floor (sodiumxt states none). Add a check to `tools/install-release-binaries.py` that refuses a floor above the stated one | Section 1.1: two members cannot load on current LTS distributions, and box2dxt's x86 floor regressed silently | M | owner, then dispatch |
| 2 | **Fold array-key case in the family interpreter.** `coinxt/tools/lcs-interp.py` and its byte-identical `nostrxt/tools/lcs-interp.py` model an array as a case-sensitive dict; the engine folds key case (engine note 2.7, OBSERVED 2026-09-15). Add a case-folded index that keeps the first spelling for `the keys of`, then re-run every execution gate that uses the interpreter (coinxt, nostrxt, riptide, holde-em, nocloud) and READ each new red: a latent engine bug, or a model artefact | Every interpreter-driven gate passes code the engine would run differently; riptide's LAN keys (3.1 #3) are a concrete case | S to change, M to triage | none |
| 4 | **Supply-chain hygiene.** SHA-pin the 54 `uses:` lines in `.github/workflows` (none is pinned today); add a root SECURITY.md with a disclosure contact (only nocloud has one); add a gate that checks coinxt's vendored trezor-crypto and libsecp256k1 against the commits `coinxt/native/vendor/VENDOR.md` names. No member has had an external security review | Standing gaps found by the 2026-09-08 blockchain research, re-verified 2026-09-23 | M | owner |
| 6 | macOS Gatekeeper/quarantine guidance for the unsigned universal dylibs, written from the first Mac session's record (runbook 2.1 and row 24 ask it to record the first-load behaviour and remedy) | None exists; unsigned distribution was accepted 2026-08-23 | S | engine |
| 8 | Publishing follow-ups: watch each member repository's first generated `gates.yml` / `native.yml` run and record the result; put the `XTALK_PUBLISH_TOKEN` expiry in a calendar (rotation steps: MEMBER-REPO-SPLIT section 2) | This session's GitHub scope cannot see the member repositories' runs; the token is the owner's | S | owner |
| 9 | Draft PR #138 (archivext reviewed against the 9.6.3 dictionary) targets a member that left this tree on 2026-09-21; it was still open and conflicted on 2026-09-23. Move it to the archivext repository or close it | A dead PR against this tree | S | owner |
| 12 | *(optional)* Pay down bare citations: `tools/check-doc-anchors.py` re-resolves anchored citations only and counts the rest as unverified | A line number is a fact about today's file | S-M | none |

### 1.3 Engine work (suite-level)

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | `tests/preflight.livecodescript`, then `tests/suite-selftest.livecodescript`, on Windows and then Linux (glibc 2.38 or newer); quit and relaunch OXT before every torrent-bearing paste (trap 5.1.1) | S1 items 0-1 | 31 and the member rows | every member LOADED at its ABI; RECORD each member total (the runbook lists the last ones), do not match it |
| 2 | Engine-notes probes: the 2^53 line and the `or` probe | S1 | P | notes 2.4 and 2.5 promoted to OBSERVED with the exact text, or 2.5 rewritten |
| 3 | Other engine-notes probes: 5.3 (a second stack in front, and a `send ... in` handler writing an unqualified field: record where the write lands); 2.6 (`the number of chars of X + 1`, and `field "x" & tKind`); optionally 1.1 (a second `script "..."` line mid-file with a declared local read below it) | S1 | - | each note promoted with a date, or left DOCUMENTED / UNEVIDENCED |
| 4 | The demo re-open fleet, including `start-here.livecodescript`: open one card-hook box2dxt game and one stack-hook demo from the launcher and record whether each builds on first open (its `go invisible stack` / parked-closed create path, engine note 5.5) | S1 items 3, 5 | 37, 38 | per row; this is the largest engine item |
| 5 | Platform rows: Windows 64- and 32-bit, Linux 32-bit, and the first Mac load of all six dylibs | S5 | 23, 24, 47 | preflight LOADED and the member sections green on that row, bitness recorded |
| 6 | *(optional)* Cheap measurements nothing schedules: FFI-crossing cost and interpreter op rate; whether `byte N of X` on a 60,000-byte Data is O(1) or O(N); `seek to N in file` (a standing nocloud VERIFY) and `rename file` semantics; whether `open file ... for binary write` truncates an existing longer file (engine note 6.14 gives the four-line probe: the reference and engine source say it does, the tree's comments said it does not); whether OXT exposes SQLite through revDB | S1 | - | numbers recorded in engine notes; 6.14 promoted to OBSERVED with a date, or rewritten as a divergence |
| 7 | Model C Phase 4 exit: a FRESH user on each of macOS, Windows and Linux, following only section 13 of [ONIONXT-INTEGRATION-PLAN.md](ONIONXT-INTEGRATION-PLAN.md), completes a two-machine anonymous transfer | S4 on each OS + PERSON | - | all three done; the phase does not close before |

### 1.4 Owner calls this plan waits on

- **Open: D-04**, which `.onion`-derivability wording ships. Recommended: pre-approve
  both the strong and the `svc=` wording, so the S4 #32 run flips a label.
- **Worth re-opening:** D-17 (its premise is false: no workflow invokes
  `coinxt/tools/verify-independent-decoder.py`, last run 2026-08-13) and D-03 ("the
  glibc floor stands as-is" no longer holds for box2dxt's x86-linux build).
- **Raised, not briefed:** the rows marked `owner` here. OPEN-DECISIONS lists them
  with the suite-wide ones: Windows upstream pins, a glibc floor, OpenSSL notices,
  32-bit engines for rows 23 and 47, supply-chain hygiene, the blockchain direction.
- **Deferred, no action:** D-02 (nocloud's endpoint menu), D-13 (onionxt's v2 menu),
  D-19 (box2dxt's roadmap triggers).

---

## 2. The extensions

### 2.1 sodiumxt

- 73 public `sx*` handlers over 124 shim exports; coverage 73/73. **ABI 10** in the
  shim, the `.lcb` and all five binaries.
- Windows DLLs: MSVC + vcpkg libsodium 1.0.22 (D-08); Linux/mac: pinned 1.0.20.
- Latest record: 106/106 at ABI 10, Windows x64, 2026-08-24, including the 7-check
  ChaCha20 section, on a mingw DLL that has since been replaced. Linux was last
  RECORDED at ABI 9 (2026-08-18); the 2026-08-27 paste (sodiumxt green, platform and
  package not recorded) may have loaded the run-12 Linux build (coding #6).

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 5 | *(optional)* Bind the shim length accessors the `.lcb` does not expose (`sxt_secretbox_keybytes`, `sxt_aead_keybytes`, `sxt_kdf_*` ...); only `sxPwSaltBytes` is public, so callers hard-code 32. No ABI bump | API completeness; adds engine-pass debt | S-M | none |
| 6 | If anyone knows it, record which platform and which sodiumxt package the 2026-08-27 two-machine suite paste (2440/2/3) loaded: if it was a run-12 build, it is the first engine record for a committed sodiumxt binary | The record names no platform | S | owner |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | Preflight and suite paste (or `put sxSelfTest()`) on **both** Windows bitnesses | S5 | 23 | LOADED at 10; 106/0 with SHA3, ristretto and ChaCha20; `put sxVersion()` shows libsodium 1.0.22 |
| 2 | The same on a Mac (arm64; Intel too if available) | S5 | 24 | 10 and 106/0 |
| 3 | The same on Linux x86_64 | S1 item 1 | - | 106/0: the first RECORDED ChaCha20 run on Linux |
| 4 | The same on a 32-bit Linux engine | S5 | 47 | the first x86-linux record |
| 5 | `sodiumxt/examples/sodium-demo.livecodescript` | S1 item 5 | 37 | all 7 tabs build, the About self-test green, the tamper case rejected (no boot self-check: a human judgement) |

### 2.2 torrentxt

- 85 public `bt*` handlers, 78 binds against 78 exports; coverage 85/85. **ABI 11**
  (`torrentxt/src/btx_abi.h` ("#define BTX_ABI_VERSION 11")), matching the `.lcb` and
  the committed binaries.
- The 2026-09-12 binaries carry the bounded rp1 queue, the 996-byte BEP44 cap and
  `alerts_dropped_alert` counting, reported through `btLastError()` until ABI 12:
  `torrentxt/src/torrent_shim.cpp` ("THE BOUNDED INBOUND QUEUE").
- Latest record: harness 101/101 on Windows (2026-08-17, 08-20, 08-24), the
  destructive handlers' refusal legs included. The 2026-08-27 suite paste (2440/2/3,
  platform not recorded) had every folded member green, torrentxt included.
  Two-machine evidence: riptide (2026-08-13, 08-15) and a maintainer report of rp1 chat
  on one LAN (2026-08-27, no PASS lines). The 2026-08-17/20/24 harness runs and the
  riptide runs used binaries built before run 12. The 2026-08-27 session does not
  record which binaries it loaded (run 12 committed torrentxt's at 00:38 UTC that day).
- No dated record shows these running: the `examples/torrent-helpers.livecodescript`
  helpers (Engine #8); `btRemoveTorrent` with deleteFiles=true, which the harness skips
  by design; a real `btMoveStorage` move, proven only on its stale-id refusal leg
  (2026-08-17) (Engine #6).

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **ABI 12:** `A_RP1_QUEUE_OVERFLOW` and an alerts-dropped alert code, replacing the interim `btLastError()` reporting. Deliberately not prepared headlessly: this environment rebuilds only the x86_64-linux library, and a bump would leave four binaries answering 11 under a source saying 12 (the freshness gate refuses it, rule 5 forbids it) | Apps see a shed or a dropped alert only by reading the last error | M | dispatch (the same change as the rebuild of all five) |
| 2 | Pin Windows libtorrent to 2.0.11 (a vcpkg baseline or overlay, or FetchContent), or record 2.1.1 as accepted, D-08 style | The Windows build is a different upstream from the tested one | S + dispatch | owner |
| 8 | QuickShare's cross-action guard (design 7.3, guard 3): re-dropping a file already shared anonymously, with the Tor toggle off, seeds it publicly with no "also seed this publicly" confirmation; the `qsAssertNotClearnet` / `chAssertNotClearnet` predicates were never built. Build the confirmation, or record the guard as dropped | A mixing path the design said to refuse | S | owner |
| 11 | The `chAnon` tooltip, the `chHelp` text and the `chSetAnon` dialog in `torrent-dht-channels` say a channel is "reachable from the channel card alone": the strong derivability claim D-04 holds back until register #27's live half passes. Reword to the `svc=`-safe copy, or settle D-04 | Shipped copy ahead of its evidence | S | D-04 |
| 15 | *(optional)* About 55 code comments in 15 files cite "plan section N" of the deleted design brief (it resolves through git history, last changed `bf9b158`) | Pointers into history | S | none |
| 16 | Add the OpenSSL (Apache-2.0) notice: OpenSSL is statically linked into x86_64-linux (3.5.4), both Windows DLLs (3.6.4) and universal-mac (3.5.4), and neither `torrentxt/THIRD-PARTY-LICENSES.md` nor the root LICENSE's torrentxt row carries it | Binary redistribution obligation | S | owner (legal) |
| 17 | Acknowledge the positioning and distribution risk of shipping a BitTorrent client, which the design brief asked to flag before public release (TorrentXT has been public since 2026-09-23); the legitimate framing is resilient distribution of large payloads | Recorded risk, never signed off | S | owner |
| 18 | Mirror `qsRouteLookupKey` (the 2026-09-24 HEAD port: a HEAD finds its GET route) in `torrentxt/tests/fileserver_golden.py`, as nocloud's golden mirrors `route_lookup_key` | The ported routing has no headless pin in this member | S | none |
| 19 | Refuse a non-hex btih in the shim: libtorrent 2.0.x's `magnet_uri.cpp` ignores `from_hex`'s failure (2.1.1 checks it), so `btx_add_magnet` adds a garbage info-hash on the Linux and mac builds, and a pre-Model-C QuickShare fed a `BTXTOR1:` code cut to 40 characters joins swarm b000...0. Both QuickShares' share-code checks now require hex (`qsIsHex`, 2026-09-24); the shim fix is a native change, so it rides a dispatch. The smoke test pins today's behaviour per libtorrent version | A malformed code joins a real swarm instead of refusing | S + dispatch | dispatch |
| 20 | A truncated LOCKED `BTXTOR1:` code is offered as plaintext: when the address survives and the verifier is cut off, `qsReceiveOnion` shows the "not encrypted, download anyway?" prompt and dials without a key; the encrypted header then refuses it, so nothing is saved, but only after a network dial and a misleading prompt. Distinguishing "unlocked" from "lock cut off" needs a marker the code format does not carry today | A misleading prompt and a needless dial | S | owner (code format) |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | Suite paste on Windows **and** Linux | S1 item 1 | 47 (first Windows libtorrent 2.1) | 106/0 (101 before the 2026-09-24 boundary checks); the first contact with the 2026-09-12 binaries and with `load_torrent_buffer` on Windows |
| 2 | Re-opens: `torrent-quickshare`, `torrent-dht-channels`, `torrent-client`, `torrent-rp1-chat` | S1 items 3, 5 | 37 | boot self-check green, the card look; in `torrent-quickshare`, the Tor pill (`qsTorPill`, `430,8,612,32`) and the two transport toggles do not overlap the title or tagline, which closes register #30 (ONIONXT-INTEGRATION-PLAN 12.3; row 37 names it) |
| 3 | Quick Share with the Tor toggle ON; #31 (Anonymous ON / OFF / tor absent) | S2 items 3, 4 | 5, 21 | a share code with no torrent and no DHT call; #31's three behaviours |
| 4 | Closing-pass legs C (seed/leech hash-verified, resume across an OXT restart) and D (rp1 chat); `torrent-dht-channels` and `torrent-rp1-chat` on two machines | S3 items 1, 6 | 6 | each leg's PASS lines |
| 5 | #32, #33 and the Model C gate (plan 12.4); measure throughput in MB/s for register #28 in the same session | S4 | 21, 5 | the feed over the onion with the DHT off; a sha256-identical download; a capture with no swarm/DHT traffic; **settles D-04** |
| 6 | A legal ISO magnet to `torrentFinished` with a hash match; `btMoveStorage` moving a live torrent and `btRemoveTorrent` with deleteFiles=true deleting for real, by hand (the harness skips the delete path by design: its `stNote` in `torrentxt/tests/torrent-selftest.livecodescript` ("deletes real files: manual only")); a packaged fresh install per platform, whose standalone Model C probe reports "needs SodiumXT" distinctly from "no Tor" | NET; S1 per platform | 45 | as named |
| 7 | x86-win32, x86-linux, and the first Mac load | S5 | 47, 24 | 106/0 on each row |
| 8 | The helper stack, `torrentxt/examples/torrent-helpers.livecodescript`: `btStartPolling`, `btStopPolling`, `btTorrentPollOnce`, `btFormatBytes`, `btStateName`. No harness calls them. `enet-internet-chat` carries a verbatim copy and calls `btStartPolling` when it hosts, but its 2026-08-27 record does not say the host path ran. A short check in the member harness, or a demo pass recorded by name, closes it | S1 | - | events drained to the target card, polling stopped cleanly, the two formatters' outputs recorded |

### 2.3 enetxt

- ENet 1.3.18, **ABI 2**, 23 public handlers; coverage 23/23. The 2026-09-12
  binaries carry the 2026-09-09 `enx_disconnect` handle-retire fix (`23a2914`).
- Latest records: standalone selftest 2026-08-07; async loopback 2026-08-13; folded
  34 on 2026-08-20; `enet-lan-chat` on one Linux machine 2026-08-18;
  `enet-internet-chat` could not connect on one network 2026-08-27 (no hairpin, as
  expected).

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 3 | *(optional)* Teach `tools/check-binary-freshness.py` to read the ABI from the Windows DLLs (it SKIPs them today for enetxt, datachannelxt and torrentxt) | Closes a gap in rule 5's automated half | S-M | none |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | `enetxt/tests/enet-selftest.livecodescript` standalone | S1 item 6 | - (runbook 4.3) | no `RUN NOT FINISHED` trailer; the first load of the 2026-09-12 binaries and the first standalone async run since the `sEnPolling` rename |
| 2 | Closing-pass leg B (inbound UDP 27300 on the Host) | S3 item 1 | 6 | "peer connected"; text and binary with a NUL echoed byte-exact; a graceful disconnect |
| 3 | `enet-lan-chat` on two machines (UDP 27099) | S3 item 6 | 6 | joins and leaves announced; lines relayed through one `enBroadcast`; RTT on the dashboard |
| 4 | `enet-internet-chat` across two networks | 2NET | 39 | INTERNET LIVE with a non-RFC-1918 remote |
| 5 | Suite paste on a Mac | S5 | 24 | LOADED at 2; the en1 sections green |
| 6 | *(optional)* `enPollLastError`'s throw paths (a dispatched handler that throws; a drain failure), after a small harness addition | S1 | - | the api-reference label on the throw paths flips |

### 2.4 datachannelxt

- libdatachannel v0.24.5, `NO_MEDIA` by decision; **ABI 1**; 31 public handlers;
  coverage 31/31. The 2026-09-12 binaries carry the 2026-09-09 orphan-channel fix.
  Both Linux libraries need glibc 2.38 (1.1).
- Latest records: first live loopback 2026-08-08; standalone async loopback
  2026-08-15; folded 39 on 2026-08-20; `datachannel-dht-chat` on one machine each on
  Linux and Windows 2026-08-18. On 2026-08-27 the maintainer reported a DHT-signalled
  WebRTC chat working on two machines on one LAN; the stack and the selected-pair
  type were not recorded.

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 5 | *(optional)* Remove the legacy `dcLocalDescription` transition shim (script gotcha 11) once no supported build emits the old event | The cleanup its own comment schedules | S | owner |
| 6 | Pin Windows OpenSSL, or record the acceptance as D-08 did for libsodium | Windows and mac ship different OpenSSL versions | S + dispatch | owner |
| 7 | Correct `datachannelxt/THIRD-PARTY-LICENSES.md`'s "OpenSSL is NOT bundled": the Windows DLLs (3.6.4) and the mac dylib (3.5.4) link it statically; add the Apache-2.0 notice | Binary redistribution obligation | S | owner (legal) |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | `datachannel-loopback`: **the only member demo with no engine record** | S1 item 5 | 37 | connected + open on both sides; chat in both panes; the boot self-check green |
| 2 | `datachannel-selftest` standalone on the 2026-09-12 binaries (Windows; Linux with glibc 2.38 or newer), recording which library loaded | S1 item 6 | - (runbook 4.2) | green, no trailer |
| 3 | Closing-pass leg E, and `datachannel-dht-chat` on two machines recorded BY NAME (the 2026-08-27 one-LAN report does not say whether the demo or leg E ran; its getting-started section 6 flow has no recorded run either) | S3 items 1, 6 | 6 | OPEN across machines; the record names the stack, both platforms and the selected ICE pair type |
| 4 | Leg E or the DHT chat across two networks | 2NET | 40 | a `srflx` / `prflx` pair (record `relay` honestly if both NATs force TURN) |
| 5 | Browser interop: `datachannelxt/docs/browser-interop.md` (the page and its OXT half landed 2026-09-24; the page was exercised in headless Chromium against the committed `.so` through its C ABI, which proves neither the `.lcb` binding nor an engine) | S1 + a browser | 40 | the channel opens; text arrives as a string, `dcSendData` as an ArrayBuffer |
| 6 | Suite paste on a Mac | S5 | 24 | the dc sections green on the two-slice-lipo dylib |

### 2.5 onionxt

- Pure script; coverage 37/48 (the 11 exemptions are engine socket callbacks and
  watchdogs; the 3 live-daemon ones retired 2026-09-24 to harness calls on their
  refusal paths).
- The **live-Tor core is engine-proven** from the early bring-up (before 2026-08-08),
  `oxh*` hosting included; the offline self-test ran 61/0 on 2026-08-17 (Windows);
  coinxt's wallet logs show `oxDial` reaching third-party v3 onions (2026-09-02/03).
- Static only: Mode B; an OnionXT-to-OnionXT dial; the live-accept socket id; the
  2026-08-23/24 socket-message split on a live socket; the 2026-09-09 `oxWrite`
  capture and callback pins; the four B.12 hypotheses.

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 2 | Mode B's lifecycle: no stdout capture, no `close process`, no torrc or DataDirectory cleanup, fixed ports, and `oxStopTor` cannot stop a child whose control connection never authenticated. `onionxt/docs/07-tor-lifecycle.md` now describes the code as it is; decide whether to implement these | A lifecycle the docs once promised | S-M | after leg F (D-07 keeps Mode B optional) |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | `onionxt-demo` with **no tor**, then its About self-test; the `onion-httpd` spike | S1 item 5 | 37 | probes fail closed; `oxSelfTest` green; the spike builds |
| 2 | The demo against a system tor with the B.12 probes, `oxWrite` into a closed stream, and N services live at once (one per anon channel) | S2 item 1 | 44 | a second service on the same local port refused; the raw accepted socket id recorded (engine note 6.2's live half); a stale `close socket` tolerated; the topStack callback owner; the write errors |
| 3 | Closing-pass **leg F** on 9250/9251 beside the system tor (trap 5.3.1) | S2 item 2 | 4 | control authenticated against the LAUNCHED tor; bootstrap 100% (read through the control port); exact bytes echoed; `oxStopTor` twice; the processId recorded and whether the child exits (engine note 6.3). Also the first OnionXT-to-OnionXT dial |
| 4 | Negative paths: a wrong cookie; a bad onion, scoped to an `ExtendedErrors` `0xF*` REP for a well-formed v3 onion that does not exist, with the SocksPort set to `ExtendedErrors` (the mapped REP `0x01` on a retired v2 onion already failed closed on an engine, 2026-09-02, coin-wallet log); a stalled daemon; a double close; a peer vanishing mid-handshake; a descriptor that never publishes; and a cold-start bootstrap that shows progress and never freezes the UI. In the same run, observe `socketTimeout`, including whether it repeats while a read or write is pending, and (after coding #4) which timeout path fired | S2 item 8 | 44 (the last three not yet in it) | each fails closed with a readable reason, none hangs; engine note 6.1 promoted from DOCUMENTED to OBSERVED with a date, or rewritten |
| 5 | The 2026-08-23 `pass` lines and the 2026-08-24 wrapper split on a live socket, including an embedder (nocloud) calling the named functions | S2 | 22, 44 | foreign sockets pass through; nothing hangs |
| 6 | The round trip: two OXT processes or machines, tor and sodiumxt (after coding #5) | S2 item 9 / S4 | 44 | a SodiumXT-sealed message B to A and back, authenticated, both IPs behind Tor |

### 2.6 coinxt

- 95 public handlers (44 in the `.lcb`, 51 in script); coverage 95/95. **ABI 7** in
  the shim, the `.lcb` and all five binaries (2026-09-12).
- Library: 290/290, Windows x64, 2026-08-24 (BIP-341); ABI 7's `cxPubkeyCombine`
  (2026-09-10) has no engine run.
- The wallet (`kWaVersion` 1.2.0, 13 screens) has engine logs from 2026-08-31 to
  2026-09-03: all four transports over clearnet and Tor, RBF, CPFP, a legacy broadcast
  (`7978bdd2...`, 2026-09-02), and in the tenth log the silent-payment send, an
  inscription reveal and a vault payment. Its surface from 2026-09-04 is headless only.

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | Wire `verify-independent-decoder.py --require` (with its pip installs) into the release job, or re-decide D-17 on true facts | D-17's premise is false (1.4); the check last ran 2026-08-13 | S | owner |
| 2 | Per-push CI is Linux only: add Windows lanes (a MinGW build and KATs on a Windows runner, including a 32-bit Python for the x86 DLL) and a mac lane, or record that dispatch-only is permanent | The x86-win32 DLL has never executed anywhere | M | owner |
| 3 | The rest of the Core plan: a `verifymessage` second opinion on the 2011-format signed message (allowlisted in `kWaCoreMethods`, called by nothing); JSON-RPC batching for the Core backends (one POST per request today); a Node-screen card for the regtest sandbox's own mining address (Mine pays the wallet's first address) | Named as left in `coinxt/docs/bitcoin-core-plan.md` | M | none |
| 4 | Restoring past the gap limit: a sync never extends the address window (windows extend on demand since 2026-09-03, a sync does not), so a restored wallet whose whole window is used can miss funds | Funds a restore cannot see | M | owner (it changes what a sync is) |
| 7 | Chain inclusion: the wallet verifies no inclusion proof (no `get_merkle`, `gettxoutproof` or `getblockheader` in any script), so "confirmed" is the backend's word | A trust gap stated by the 2026-09-08 research, still true | M-L | owner (scope) |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | **Row Q:** the "secp256k1 keys" section, then silent-payment receiving in `coin-wallet` on testnet | S1 + NET | Q | the six `cxPubkeyCombine` lines green; Inspect repaints `FOUND:` from the socket callback; Save writes an `sp` line; a second Inspect makes no request |
| 2 | `coinxt/examples/coinxt-demo.livecodescript` | S1 item 5 | 37 | the test mnemonic's published BIP-84 / BIP-44 / ETH addresses; sign/verify; the P2WPKH and EIP-1559 transactions decode |
| 3 | The four-family broadcast: record the legacy P2PKH spend (`7978bdd2...`, 2026-09-02); still owed are native P2WPKH from the wallet, EIP-1559 on Sepolia from the demo (broadcast externally) and EIP-155 from the message box | NET (testnet and Sepolia funds) | 43 | each transaction accepted by the network |
| 4 | The wallet's surface since 2026-09-04, and legs the logs did not reach, shortest first: the boot record; BOLT11 and runestone Inspects (a mainnet backend); the Ordinals screen (prepare, save and reopen, fund on signet or testnet4, reveal); the Vault (lock, pay, then spend after its height with a node accepting it); BIP-322 from a taproot wallet verified in Core or Sparrow; testnet4 with a BIP-329 export and import; Electrum on the mainnet onion (port 110); the Update-from-main swap; the right-click selection fix and three corrected menu items; the stale-answer skip, paint and pump timing and the mixed tip+fees batch; a backend un-marking a coin it still lists, and Esplora's 400 body in the log; CPFP on a foreign transaction; an Electrum-format seed opening real coins; the 2026-09-10 audit fixes (a refused socket, a non-ASCII label saved and reopened, the boot record's four address lines, the new `cw*` shapes) | S2 + NET | 43 | each `coinxt/docs/wallet.md` line's own criterion |
| 5 | A Bitcoin Core 26+ regtest node: the Node-screen sandbox (Start, Mine, Reorg, Stop), the autotest once, `core-rpc` and `core-cli` (+ tor and the node as an onion for `core-tor`). Settle the plan's section 11 risks: HTTP/1.1 keep-alive and megabyte `Content-Length` replies over a LiveCode socket (fallback `Connection: close`), the pruned-node rescan refusal offering the scan tier, and on Windows the cookie under `%APPDATA%\Bitcoin` and console flashes | S1 + a local node (+ tor) | 43 | every "Not run against a node" line in wallet.md flips |
| 6 | Suite paste on a Mac and on a 32-bit Windows engine | S5 | 24, 47 | `cxCheckABI` silent; the coinxt sections green |

### 2.7 nostrxt

- Two files: the `nx*` core (81 handlers) and the `nxr*` relay client (23); coverage
  104/104. NIPs 01, 19/21, 44 v2, 42 (build and answer), 13, 05, 11, 65 (build and
  parse).
- **The core is ENGINE-PROVEN 2026-08-24:** 274/0/2 in the suite paste (the 2 skips
  are the relay section, which is not in the paste). **The relay SEND half was
  live-proven 2026-08-24** against wss://nos.lol: connect, handshake, publish, ok-true.
- Static only: the receive leg, NIP-42, every `ws://` path, TLS on a bad certificate,
  and the 2026-09-09 guard-nesting change.

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 5 | Phase 9 scope: NIP-17 private DMs over NIP-59 gift wrap (the cipher and NIP-44 blockers cleared 2026-08-23/24; pin the published vectors first); NIP-59 as its own layer; NIP-65 outbox routing and a relay pool as a third file over `nxr*`; `.onion` relays over OnionXT (needs a transport seam in `nxrConnect`); NIP-44's extended length (blocked on upstream vectors). Each lands with vectors or is declined with a reason | Scope, not debt | M-L | owner |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | **The receive leg** from `nostrxt-demo`: Connect, Subscribe (kind 1) | NET (CoinXT + SodiumXT installed) | 34 | EVENTs that verify with no `REFUSED`, then EOSE |
| 2 | NIP-42 plus CLOSED and NOTICE (the demo's Answer auth, Unsubscribe and Send raw controls, 2026-09-24), recording the ok/closed reason texts real relays send (docs/05 VERIFY item 9) | a relay that demands auth | 34 | `ok <id>: true` for the kind-22242 event; a `closed` reason starting `auth-required:` |
| 3 | The `ws://` leg against nostr-rs-relay or strfry on loopback | a local relay | 34 | open, publish ok, subscribe returns the event, a ping answered, a clean teardown |
| 4 | **A bad certificate** (self-signed, expired or wrong host); in the same session record whether SNI is sent, which TLS versions negotiate, and how a TLS failure is delivered | NET | 34 | a `socketError` means refused; "the server did not upgrade" means it fails OPEN. Record it in engine note 6.8 whatever it is |
| 5 | Forced negatives: a non-websocket server (fail closed at the 101 check), a handshake timeout (the 20 s watchdog), a mid-session close | NET or a local server | - (add to 34) | each fails closed with a reason |
| 6 | Socket behaviour: whether a large `write to socket` blocks, queues or partially writes; whether the engine-global `socketTimeoutInterval` set by `nxrConnect` disturbs a co-loaded library's sockets (docs/05 VERIFY 5); the close-handshake ordering (VERIFY 8) | NET + OnionXT co-loaded | - (add to 34) | measured and recorded in engine notes |
| 7 | The demo's own test button (`ndTests`), whose relay section SKIPs in the paste | S1 item 5 | 37 | 17 sections, 0 failed, 0 skipped |
| 8 | Message-box probes: row P(b) (the `or` short-circuit the 2026-09-09 fix rests on); raw `base64Encode` emission (does it wrap, how) for the VERIFY at `nxB64Encode` (docs/07 "Other engine unknowns") | S1 | P | as the runbook states |
| 9 | *(optional)* The byte-loop JSON parse on a ~100 KB kind-30023 event, and `nxByteXor` masking on a 1 MB frame (optimise only after an observed stall; docs/07 "Measure before optimizing") | S1 | - | timings recorded |

### 2.8 box2dxt

- Box2D v3.1.0: 376 public `b2*` handlers plus the pure-script Kit's 313 `b2k*`. Kit
  coverage 313/313; the raw binding 131/376, the other 245 held as a floor.
- Records: harness v30 375/0 Windows (2026-08-20), 374/1 Linux (2026-08-21; the line
  is `playLoudness` readback, engine note 5.4). v31 (374 expected) has no record of its
  own: the 2026-08-24 paste's zero failures make it green by inference only.
- Five platforms committed; the universal-mac dylib (ABI 4) has never been loaded by an
  engine. It was rebuilt byte-identical by both release runs (1.1). CI's smoke test
  enters all 370 LC_API exports under ASan/UBSan. Risk R1 has Win32 verdicts only
  (2026-06-10).
- Harness v32 (2026-09-24) drives the ten 2026-09-09 delimiter-fixed Kit handlers
  under a caller's tab; 385 expected in a green run, unobserved. Both references name
  every handler (376/376 raw, 313/313 Kit), held by `tools/check-reference-docs.py`.

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 2 | **The x86-linux glibc regression, 2.17 to 2.34:** build that release row in a `manylinux2014_i686` container (as `native-box2dxt.yml` already does), or publish the floor | A silent portability regression | M | dispatch; revisit D-03 |
| 4 | Platformer polish that can be done in the tree: the dev level-picker behind the debug toggle, or styled as intentional; sweep unused handlers and the dead camera-fallback paths; extend `tools/audit-platformer.py` to the vertical L7; check the win-screen summary (time, falls, gems, stars, coin score, hero, a "flawless run" callout); retune `pfMakeCoin`'s coin-tier thresholds if wanted | The code half of the polish plan | M | none |
| 5 | The raw `b2*` script ratchet: 245 handlers named by no script | Blind assertions against a foreign-bound API would mostly be test bugs | L | engine |
| 8 | Point `box2dxt/README.md`'s build badge at the member repository's own `native.yml` once that lane has run | It still points at the suite lane | S | the first member-repository run |
| 10 | The ten 2026-09-09 Kit handlers set `itemDelimiter` to comma and never restore it (`box2dxt/src/box2dxt-kit.livecodescript`, e.g. `b2kAddBox`). Harmless if the property is handler-local, as the LiveCode dictionary says; a leak into callers if it is global, as engine note 2.3 records. Restore them if harness v32's second observation shows a callee's comma leaking back (note 2.3's counterpoint) | Found statically 2026-09-24 | S | engine (v32's answer) |
| 11 | Native shim defects found statically 2026-09-24, each a shim change that needs its binaries rebuilt by a dispatch (rule 5): the per-type joint accessors (`src/box2d_lc.c` near 1610-1712) check that the handle is live, not the joint's type, so a wrong-type joint reaches Box2D, and `b2lc_joint_type` answers 0 for both a distance joint and a stale handle; `b2lc_shape_polygon_update` on a non-polygon zeroes the count but keeps the previous radius; the committed Linux `.so` files carry SONAME `libbox2dxt.so` (`BOX2DXT_BARE_SONAME` is OFF), so `b2LoadNativeLib` / `b2LoadNativeLibHere` cannot preload them. All three are documented in `box2dxt/docs/api-reference.md` | Wrong answers a script cannot tell apart | S + dispatch | dispatch |

Parked by D-19 (2026-08-27, "triggers stand"), not scheduled: Wave 8 builder
cross-pollination, `b2kScene*` and enemy-pattern promotion (when a second game needs
them), streamed music, multi-player controller keying, the snake/serpent audit
extension, true multi-layer parallax (waits on transparent overlay art).

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | Suite paste on Windows **and** Linux | S1 item 1 | 31 | RECORD the v32 total (385 expected); Linux prints `playLoudness` as a note; the v32 section's two observations (does a caller's tab reach a called handler; does a Kit call's comma leak back) |
| 2 | The five games from `start-here.livecodescript`: `box2dxt-demo`, `-platformer`, `-slingshot`, `-contraption-builder`, `-spike-gamekit` | S1 item 5 (Windows, Linux) | 38 | each builds on FIRST open; the contraption Images panel does not throw; the platformer card fade reveals the level and the L7 camera works; slingshot's own list passes |
| 3 | Risk R1: `box2dxt-spike-gamekit` on Linux and a Mac, recording the S1-S12 verdicts | S1 + S5 | 38 | the verdicts |
| 4 | First Mac load: install the `.lce`, `put b2Version()` returns 4, then the paste section and the spike | S5 | 24 | as named |
| 5 | The platformer polish pass with the owner: facing and scale clean on every sprite in all 7 levels (hitbox vs art, bind offsets, HUD scale, the heart/portrait row); feel locked (move and jump speeds, coyote/buffer/jump-cut, air and wall jumps, dash, springs, swimming, lifts, conveyors); fair hazard timing and an intentional L1-to-L7 ramp; scenery placed by eye; consistent particles; every action audibly cued, nothing doubled; an accurate pause/help overlay; the first 30 s need no unexplained move; transition-card cosmetics and light card text on L6/L7; the parallax seam; each hero skin clean across idle/walk/jump/duck/climb | S1 + PERSON | - | the owner's sign-off |
| 6 | A fresh-machine package run: build with `tools/make-release.py`, install on a clean machine, play end to end | S1 (a clean machine) | - | installs and runs |

---

## 3. The apps

### 3.1 riptide

- Library 0.12.0: 106 `rs*` handlers, coverage 106/106. The five-card demo embeds
  nostrxt (core and relay), riptide, onionxt and onion-httpd; `check-demo-boot` boots it
  headlessly over two capability profiles (it prints its own count).
- Records: phases 1-2 two machines 2026-08-13, phases 3-4 2026-08-15; mid-download
  playback measured NEGATIVE 2026-08-27 and fixed that day (`raMediaFrontReady`);
  phases 6-7 compute engine-green to 2026-08-24 (391/0); phase 8's v11 boot 9/1 on
  2026-08-29 (the FAIL was the self-check's own defect, since fixed).
- Phase 5 has never run on two machines. The 2026-09-09 prefix-free LAN tags supersede
  the engine-green admission bytes; the harness sections added after 2026-08-24 are
  static only.

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **A bridge reader in the app:** `rsRequestBridge`, `rsIngestBridge` and `rsNostrBridgeFromEvent` have no app caller. Persist its `pMinSeq` watermark in RIPTAPP1 as `sHeadSeen` is | Phase 8's done-criterion needs the bridge resolved in BOTH directions; the runbook's phase-8 step 6 is blocked until it exists | M | owner (scope) |
| 2 | **Decide RSL1's magic** after the 2026-09-09 tag change: rule 3 says a framing change mints a new magic, and the preimage changed without one, so pre- and post-2026-09-09 devices silently fail admission with each other | Protocol hygiene; it dictates the phase-6 setup | S | owner |
| 4 | Own-head refresh while online: the demo re-puts its BEP44 head only on post, BEP44 items expire, and D-06 rules out follower republish, so the author's own re-put is the only retention | Feeds go dark | S-M | owner (cadence) |
| 6 | Scope calls: the pairwise room (`rsRoomId`, spec 5.2) is library-only, so wire it or record that for good; an anon file transfer over the onion (`rsBtxo*`, spec 8.3) has no app caller (M to build); followers-only sealed media (spec 4.4) is deferred and would need its own spec and record format (L) | Library surface the app does not use | S-L | owner (scope) |
| 8 | One app-state file per machine, not per identity: `raAppSave` seals the current identity's state over the one `RIPTAPP1` file (`riptide/examples/riptide-social.livecodescript`, the app-state path near 17312), and recovering your own head marks the state dirty, so unlocking a SECOND identity with a published head can overwrite the first identity's follows and watermarks. Key the file by identity, or refuse to save over another identity's file. Found statically 2026-09-24; the two-machine runbook's phase 8 step 8 now asks the tester to watch for it | Silent loss of a user's follow list | S-M | owner (file layout) |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | Re-paste `riptide-social`, then the Nostr card offline | S1 item 3 | 35 | the boot self-check reads 10 passed / 0 failed; an npub shows; Post says "not sent" with no relay; RIPTAPP1 round-trips |
| 2 | Suite paste | S1 item 1 | - | riptide 0 failed with 2 skips; the first engine run of the post-2026-08-24 sections and of LAN admission on the new preimage |
| 3 | Phase 7, the serving half | S2 item 5 | 19 | the onion page in Tor Browser; `/prekey` 264 hex, proven; `/dm` answers `accepted`, and `refused` when mangled |
| 4 | Phase 5, the call and the typing lane, across two networks. In the same slot, two 2026-08-17 changes that have never run: the D15 DM clean close (with a DM conversation open both ways, press Lock on A) and the B3 tick tiers (the pump at about 33 ms while a dc call or enet mesh is live, about 250 ms otherwise, spec 10.1: judge the call and the typing indicator for feel) | S3 item 2 | 16 | `CALL CONNECTED` on both sides with a `typ srflx` `via` line; typing appears and clears; B prints "-- <A's short handle> closed the conversation --", stops showing the channel as open, and renders no stray chat line (the close rides a filler body that is never rendered) |
| 5 | Phase 6, steps 1-11 (a third device or instance; every device on a post-2026-09-09 build). With a call and the mesh up together, watch CPU on the slower machine for the B3 tiers: the painters stay gated to 4 Hz, so a busy CPU with a smooth window points at the transport tier | S3 item 3 | 17, 41 | mutual ADMITTED; drafts converge both ways; presence; the media handoff; the stranger refused; the CPU observation recorded |
| 6 | Phase 7, the finishing half | S4 item 4 | 19 | `accepted` with the PROVEN sender; zero `bt*` calls in a trace |
| 7 | Phase 8 live, steps 0-9 (needs nostrxt's receive leg and coding #1) | NET | 41 | the npub resolves in a web client; `publish -> true`; a verified follow timeline; both bridge halves; the guard refuses `nostr` for anon |
| 8 | The phase-3 faststart re-run | S3 item 7 | 41 | playback starts while visibly below 100% |
| 9 | *(optional, low priority)* Diagnose the first phase-8 card's `Chunk: no target found` at `openStack` (2026-08-29), re-introducing the suspects one at a time: `repeat for each key` over the unset `sAppRelays` / `sNxRelayHandle`, and `nxrInit the long id of me` in `openStack` | S1 | - | the cause named (the re-landed `openStack` is byte-identical to the engine-proven body, so nothing waits on it) |

### 3.2 nocloud

- One stack, `nocloud/src/nocloudquickshare.livecodescript`, serving over a web link
  or Tor; it has carried onionxt embedded since 2026-08-24.
- **No dated engine pass of this stack is recorded in the tree:** the app-layer
  lessons come from undated pre-fold passes, and the header re-opened everything at
  the 2026-08-14 kit adoption. Its three gates are green (`tools/run-gates.sh`). The
  pass checklist has 69 items, none ticked.
- Decisions: D-09 keeps the Tor path close-per-response; D-10 said yes to the mtime
  probe, which has not run; D-02 defers the endpoint menu.

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 3 | After the D-10 probe: build a restart-stable mtime ETag plus `Last-Modified` / `If-Modified-Since` with golden mirrors, or record "design confirmed" in the deep-dive's section 1.5, in D-10 and in `webapp/sw.js`'s header | Closes the one decided-but-unrun question | S-M | engine |
| 4 | *(optional)* A headless boot gate on riptide's `check-demo-boot.py` pattern | Would exercise the TorrentXT-absent guard and the 49-control boot record without an engine; coinxt, riptide and holde-em have one | M | none |
| 5 | The HTTP-host endpoint menu, listed below | Recorded roadmap; the deep-dive carries the questions that order it, not the menu itself | L | D-02 (deferred until the first external user report) |

The deferred menu (D-02; the five questions at the end of
`nocloud/docs/http-server-deep-dive.md` section 4 decide the order):
- Phase 0 and 3 residue: `GET /_qs/health`; aggregate-only `encrypted` / `uptime`
  fields in `/_qs/info`; generated-body streaming (`qsHttpReplyStream`) through the
  bounded pump, the prerequisite for zip, hashes and SSE; `:param` built-in routes.
- Phase 4: `/_qs/manifest` (app-relative, honouring `qsHasDotSegment`), `/_qs/hashes`
  and `/_qs/integrity/:path` (sha256, incremental, cached), `/_qs/search` (names only,
  capped), `sitemap.xml` / `robots.txt`, `feed.json` / `rss.xml`, with golden pins.
- Phase 5 residue: rename and mkdir verbs; a LAN-and-password-only, 404-concealed
  `GET /_edit/api/shares`; SSE live-reload of an open editor.
- Other ideas, each with its constraint: `/_qs/stats` (counts only), `/_qs/qr`,
  `/_qs/zip` (stream zip64 or skip), a RAM-only LAN paste bin, a real `POST /api/order`
  (no PII kept), `security.txt` through a route, a SodiumXT-gated fail-closed
  `POST /_qs/verify-passphrase`; and polish: optional listing suppression, `.gz`
  sidecars via a golden-pinned `qsPickEncoding`, a 431 header limit, an opt-in
  redacted access log, CORS for read-only `/_qs/*` routes only.

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | **The web-link half:** paste and reopen, then checklist sections 0-6a over `/<token>/` from a LAN browser plus `curl -i`; the D-10 mtime probe is in section 4 | S1 item S (60-75 min) | 22 | the boot record reads all 49 controls PASS; each checklist line's expectation; D-10 closes |
| 2 | **The Tor half:** sections 1, 1a and 4 over the `.onion`; also settles the app's Tor VERIFYs (`serviceReady` `pInfo`, `oxStreamState`) and the 2026-08-24 socket-split branches | S2 item 7 | 22 | `both_ends_hidden:true`; HEAD gives 0 body bytes; concurrent shares see only their own routes; `/_edit` 404s |
| 3 | Sections 7-8: the webapp over a web link; fail-closed launches without SodiumXT and without TorrentXT; a standalone's Cmd-Q | S1 + a standalone build | 46 | each line's expectation |
| 4 | The source's VERIFY markers ride 1-3: the window-manager property, the dashed drop outline, `seek to N in file`, `accept connections ... with message`, `write ... to socket ... with message`, the LAN-IP guess per platform, the libURL TLS public-IP probe | S1, S2 | 22 | each marker settled or re-dated |

### 3.3 holde-em

- **v0.25.3, harness 45**, carrying onionxt. Built: the Phase 1 hotseat; 2d, 2e, 2f;
  the Phase 3 oracle; 4a-4e Level 2 compute with void-and-audit; Phase 5 DLEQ; 4f's
  batch mask step. Coverage 172/330 game handlers, **88 with no test** (floor armed;
  the third leaf tranche, section 24, named 14 more on 2026-09-24).
- Folded records to **667/0 (2026-08-27, v0.25.2, harness 43)**. Played by a person:
  three hotseat hands (2026-08-17), and a first two-machine 2d contact (2026-08-27)
  where the hand dealt under the lobby overlay (v0.25.3 fixes it, statically).

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **Wire Level 2 into played hands.** The dealLevel gate refuses anything but 0 and 1 (`holde-em/src/holdem.livecodescript` ("unsupported deal level")). Needed: `shuffleStep` / `unmaskStep` on the wire, a `level=2` / `dleq=1` table config, the orchestration, a netsim section | The 4d machine it drives is pure and engine-green, but nothing plays on Level 2; it blocks 4f and the Phase 4 exit | L | none |
| 2 | The Phase 1d / spec 11 animations: deal slides with a ~70 ms stagger; the squash-flip through `b2kSpriteOnFinish`; one-impulse `b2kForce` chip tosses; a `b2kSpriteMoveTo` pot push | Specified and unbuilt | M | engine (a tuning eye) |
| 3 | **More leaf tranches over the 88 untested handlers.** Section 24 (2026-09-24) named 14 consensus leaves (`heNetEngineFold`, `heNetTimeoutRearm`, `heNetTurnClockStart`, the `heBet*` leaves, `heL2ChainOrder`, `heL2VoidMark` and two `heL2*` point refusals). Still owed first: `heHandSettle`, which a harness cannot call as it stands because it sends `heNextHandTick`, which deals a hand (a seam, or a test of its pieces), and the rest of the `heL2*` point helpers | Consensus code no test names | M | none |
| 5 | BEP44 profiles and play-money standings (spec 3/5/8.3): the `btDht*` BEP44 calls have 0 call sites | Build it or strike it from the spec | M | owner |
| 6 | Seven to nine seats (a spec 1 goal; the build is 2-6) | Build it or strike it | M | owner |
| 7 | The optional direct-TCP upgrade lane (pairwise `btMapPort` plus engine sockets, for sub-100 ms actions; 0 call sites) | Build it or strike it | M | owner |
| 8 | Close runbook row 14 at inference strength, as row 26 was: section 11's "seeds XOR" and "full shuffled deck" assertions ran green in every folded run from 2026-08-17 on, and engine note 3.1 answers which stream the pre-fold runs dealt from | A leg the evidence already covers | S | owner |
| 9 | `holde-em/assets/sounds/NOTICE.md`'s cardShuffle row reads as if the sound were wired "in the deal-animation increment"; the source leaves it unwired. A one-word fix in a frozen NOTICE file | Accuracy of a shipped notice | S | owner (explicit OK) |
| 10 | **Table admission list and `cfg` co-signing** (spec 5, 6, 7.3, 9): an admitted-pubkey list (or an explicit open flag) in the host `cfg`, void/forfeit rules in `cfg`, and per-player co-signing of `cfg` before hand 1. Today every table is effectively open (any key whose token verifies is admitted: `heAdmitTokenVerify`) and `cfg` is host-authored only (`heLobbyCfgBody`; `heHostRelay` refuses a `cfg` from any other key). A consensus change: the protocol-kat pins move and `kHeHarnessV` bumps | Specified, not built; a player cannot bound who sits at the table or bind the host to the rules | M | none |

Deferred by the owner on 2026-08-16: spectators. Picking them up needs a wire and UI
decision (a role a joiner can choose, or a sit-request the host answers).

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | Suite paste, then the standalone stack with `heRunSelftest`, then 2-3 hotseat hands | S1 items 1, 2, 4 | 14 | v0.25.3 / harness 45, 0 failed, 5 skips; RECORD the total rather than matching 667; the first run of the four 2026-09-09 wire-arity checks and of the nested `heBetApply` trunc guard (whether `trunc` of a non-number throws is unrecorded) |
| 2 | Phase 1 exit: a full 6-seat hotseat session with side pots and all 17 cards on screen, plus the confirming eye on the 720p layout | S1 + PERSON | 42 | as named |
| 3 | 2f bring-up | S2 item 6 | 20 | the Tor pill's states; the invite `<64hex>@<56base32>.onion`; the derived address equals `oxServiceAddress` |
| 4 | 2d re-run and the Phase 2 exit: a 6-seat table over rp1 across at least 3 machines on real home networks (extra instances fill seats); a mid-hand disconnect that reconnects and resumes; tampered and replayed envelopes provably dropped; receipts matching on every seat | S3 item 4 (3+ seats) | 18 | as named |
| 5 | 2e liveness on wall clocks, plus an attempt at the recorded KNOWN EDGE; report whether the owner-accepted `kHeSeatLiveSecs` of 600 s fits a real table's join-to-boundary gap | S3 item 5 | 28 | per row |
| 6 | 2f exit: a multi-hand onion session, a real host-stream loss, redial and a trimmed resync | S4 item 5 | 20 | per row |
| 7 | Phase 3 exit: two players and a non-playing onion oracle; kill the oracle mid-hand, then void and resume | 3M + tor | 42 | the oracle never holds a seat; the void resumes per spec 9 |
| 8 | 4f and the Phase 4 exit (after coding #1): the batched mask step (4 FFI crossings) does not visibly hitch the table and the pre-ABI-9 fallback's ~312 crossings stay acceptable; then full Level 2 sessions at 6-max across real machines, about 6 s per street over rp1 | S3 | - | user-verified |
| 9 | Phase 5: a hostile review of the deal implementation by a non-author, and a soak; spec 13's value-readiness checklist honestly assessable. Name who does it | PERSON | - | review findings closed |

---

## 4. Recommended order

Advisory, like the recommendations in OPEN-DECISIONS: a route, not a decision.

1. **Headless first: the small fixes that let the next engine run observe more** (each
   S, blocked by nothing): box2dxt harness v32; nostrxt's 2026-09-09 refusals and its
   measured floor; onionxt's three exemptions retired, `oxLaunchTor`'s result checks
   and the roundtrip fields; torrentxt's boundary tests and the quickshare HEAD port;
   the enetxt and datachannelxt smoke blocks; riptide's LAN `caseSensitive`; nostrxt's
   NIP-42 controls; the stale-text rows. Regenerate the paste, the preflight and the
   demo embeds once, at the end.
2. **Release-lane decisions, then one dispatch:** the Windows pins and the glibc floor
   decided, torrentxt ABI 12 landed in the same change,
   `release-binaries.yml` dispatched once, so the engine session proves one coherent set. Proving today's
   binaries first and dispatching after is equally honest; mixing the two wastes a pass.
3. **The engine sessions, in the runbook's order:** S1 first (Windows, then Linux with
   glibc 2.38 or newer; about 3-4 hours), then S2-S5 as resources allow, and the NET,
   2NET and 3M legs on their own. Record totals rather than matching them.
4. **What only a person can close:** D-04's wording and the owner calls; the box2dxt
   scenery and feel pass; holde-em's Phase 5 review and soak; the Model C Phase 4 exit
   on each OS.
