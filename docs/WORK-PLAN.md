# Work plan: what each member still needs

**The single LIVE list of open work for the suite**, per member and suite-wide.
Last re-audited 2026-09-23: every member was reviewed against its own tree (code,
tests, committed binaries, git history) at `e3d2496`, and the list was refreshed the
same day, after the docs consolidation closed its doc-fix items. The open items that
consolidation's review and repair passes found were added 2026-09-24, each checked
against the tree first. The same day a headless pass (suite PR #144) closed most of
the rows blocked by nothing, deleting each here as it landed, and added the rows its
work turned up (torrentxt #18-#20, box2dxt #10-#11, riptide #8, nocloud #6). The
suite paste's card look (owner decision D-23, 2026-09-24) added suite-wide #13-#14,
suite engine #8 and riptide engine #10. That paste's first engine run, the same day
(Windows, 2620/5/3; runbook section 8), closed box2dxt coding #10 and the Windows
half of box2dxt engine #1, ran the Windows paste half of suite engine #1 and part of
suite engine #8, and added suite-wide #15, suite engine #9 and riptide engine #11.
Its second run that evening (2623/2/3, riptide's two fixes in) closed riptide engine
#2 and #11. The third (2623/2/10, the board review's fixes in) named the engine's
comparison rule and closed suite engine #10; reading that rule in the engine source
added suite-wide #18-#19, suite engine #11, coinxt #8 and riptide #9; the sites
that reading found were fixed the same day (engine note 2.11; holde-em v0.25.4),
and the holde-em fix turned up holde-em #11-#12, closed the same day at v0.25.5,
whose own sweep added holde-em #13-#15. A fourth run, the D-23 paste's first on
Linux (2026-09-25, 2672/0/10, the paste as at `f1346e0` by its version lines;
runbook section 8; 64-bit Kubuntu 24.04 with the committed `x86_64-linux` builds
by the maintainer's account), read riptide's third probe line exactly as the
engine source predicts and closed suite engine #11; it closed box2dxt engine #1
and, on that account of its bitness and builds, sodiumxt engine #3 and torrentxt
engine #1; it ran the Linux paste half of suite engine #1 and more of #8, narrowed
#9 (the paste's loopbacks completed there), and narrowed holde-em engine #1. The
maintainer's answers (2026-09-26) added that the Linux report came from Copy
results and from a SECOND Run all in that launch, TorrentXT installed, which
closed riptide engine #10 and narrowed suite engine #8; that neither machine ran
the preflight; and that both engines are 64-bit, so every Windows run loaded the
`x86_64-win32` DLLs, which narrowed sodiumxt engine #1 to the 32-bit DLL and
`sxVersion()`. A fifth reported run, on that Windows machine the same day
(2653/2/10), read riptide's third probe line exactly as Linux did (engine note
2.10's constant and the two items of 2.11 that line probes are now OBSERVED on
Windows too) and stalled both loopbacks a fourth time (suite engine #9).
A batch of headless work from 2026-09-25 and 09-26, integrated on 2026-09-26,
closed suite-wide #14 (the paste's headless `--full` run, runbook 3.2: no
fold-level fault), #15 (the itemDelimiter premise, reworded to engine note 2.3's
answer), #16 (the paste gives back exactly the ENet holds it took, and
calls `dcCleanup` only while it holds a `dcInit` of its own), #17 (the board's
stamp derived from its build), #18 (the family checker's check 23) and #19 (the
family interpreter refuses a comparison the engine answers differently);
holde-em #13-#15 at v0.25.6 / harness 48, and the rows its review, fix pass and
round 2 found and closed in the same two days (row 16's History rules, a second
dealLevel in one hand, the dealer seat re-sat mid-hand, History's late joiner;
table protocol 2 refuses a mixed-version table by name); riptide #9 at 0.13.0;
coinxt #8; nocloud #6 and torrentxt #18 (case-exact QuickShare routes); and
enetxt #3 (the freshness gate reads every Windows DLL's ABI, through MSVC's
guard frame where the shim has one, hardened by its review). Its workers and
reviewers added suite-wide #20-#23, enetxt #4, datachannelxt #8-#9, torrentxt
#21, coinxt #9-#12, riptide #10-#12 and holde-em #17, each checked against the
tree first. None of that batch has met an engine: every script change in it is
verified statically; needs an OXT pass (the checker, the interpreter and the
freshness gate are headless tools, held by their own fixtures). Its paste
first ran on 2026-09-26, on Linux (2876/0/10; runbook section 8): the batch's
harness pins green and riptide's fourth probe line read (#22), which added #26.
So what the paste carries has now run there: #16's counted ENet and
DataChannel holds and #17's derived stamp in the core, holde-em #13-#15 and the rows after them
through its harness on one machine, and riptide #9's and coinxt #8's library
halves. What it does not carry (the demos, coin-wallet, nocloud and
torrent-quickshare's routes) and Windows keep the label above.

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
| sodiumxt | `sxSelfTest()` 106/106 in the suite paste on Linux, 2026-09-25 (again 2026-09-26), on the `x86_64-linux` file (run 12's) by the maintainer's account (the ABI-10 ChaCha20 section's first recorded Linux run), and on Windows, 2026-09-24 and 09-25, on the `x86_64-win32` MSVC DLL by the maintainer's account (64-bit; the 2026-09-12 build's first engine load) | only optional: the unbound length accessors | the 32-bit MSVC DLL, and `sxVersion()` on Windows; first Mac load; 32-bit Linux; the demo | S1, S5 |
| torrentxt | harness 106/106 in the suite paste on Linux, 2026-09-25 (again 2026-09-26), the 2026-09-12 `x86_64-linux` build's first engine load by the maintainer's account (the 996-byte caps included, which agree), and on Windows, 2026-09-24 and 09-25, on the 2026-09-12 `x86_64-win32` build by the maintainer's account (64-bit; its first engine load, and libtorrent 2.1.1's first recorded Windows run; the 09-25 build INFERRED the same); 101/101 on 2026-08-17, 08-20 and 08-24 | ABI 12 alert codes; Windows libtorrent pin; the shim's btih hex check; torrent-quickshare's dotfile and reserved-path guards | the 32-bit rows (row 47); demo re-opens; Tor toggle and #31-#33; closing-pass C/D; a real swarm | S1-S5, NET |
| enetxt | folded 34/34 and the paste's live loopback COMPLETED, Linux, 2026-09-25 and 09-26, on the 2026-09-12 `x86_64-linux` build by the maintainer's account; folded 34/34 on the 2026-09-12 `x86_64-win32` DLL, Windows, 2026-09-24 and 09-25 (the paste's loopback stalled there all four times, 5.5); async loopback 2026-08-13 | enet-selftest's extra deinitialize (#4) | standalone selftest; leg B and the LAN chat on two machines; internet chat; Mac | S1, S3, 2NET, S5 |
| datachannelxt | folded 39/39 and the paste's live loopback COMPLETED, Linux, 2026-09-25 and 09-26, on the 2026-09-12 `x86_64-linux` build by the maintainer's account; folded 39/39 on the 2026-09-12 `x86_64-win32` DLL, Windows, 2026-09-24 and 09-25 (the paste's loopback stalled there all four times, 5.5); standalone async loopback 2026-08-15 | the process-wide `dcCleanup` (owner, then dispatch); the DHT chat's unchecked nonce; owner calls: the Windows OpenSSL pin and notice, the legacy shim removal | loopback demo (no record at all); leg E; two-network call; browser interop; Mac | S1, S3, 2NET, S5 |
| onionxt | offline self-test 74/0/1 in the suite paste, Linux 2026-09-25 and 09-26 and Windows 2026-09-24 and 09-25 (its floor held each time: 75 against 51); the live-Tor core from the early bring-up | Mode B's lifecycle (after leg F) | Mode B (leg F); the B.12 probes; negative paths; the round trip | S1, S2, S4 |
| coinxt | 299/299 in the suite paste, Linux 2026-09-26 (row #8's three bech32 lines green, engine note 2.12); 296/296 in the suite paste, Linux 2026-09-25 (the 2026-09-12 `x86_64-linux` library by the maintainer's account, at ABI 7) and Windows 2026-09-24 and 09-25 on the 2026-09-12 `x86_64-win32` DLL (64-bit by the maintainer's account; ABI 7's six `cxPubkeyCombine` checks included each time); wallet logs to 2026-09-03 | D-17; per-push Windows/mac CI; Core residue; gap limit; bounds on backend numbers, the library's integer arguments and the mBTC form | row Q's wallet half (silent payments); demo; broadcast; the wallet's post-2026-09-04 surface; Core regtest | S1, S2, NET, S5 |
| nostrxt | core 277/0/2 in the suite paste, Linux 2026-09-25 and 09-26 and Windows 2026-09-24 and 09-25 (its floor held each time: 279 against 278); relay SEND live 2026-08-24 | owner scope only: phase 9 (NIP-17/59, the outbox, `.onion` relays) | relay receive, NIP-42, `ws://`, a bad certificate, forced negatives | S1, NET, a local relay |
| box2dxt | harness v32 385/0 in the suite paste on its 1200-wide card, Linux 2026-09-25 and 09-26 and Windows 2026-09-24 and 09-25 (on the 2026-09-12 DLL there, `playLoudness` exact); every run's delimiter lines settle engine note 2.3's itemDelimiter half | x86-linux glibc regression; platformer polish; three shim defects (dispatch) | the five games; R1; first Mac load; feel pass | S1, S5, PERSON |
| riptide | phases 1-4 on two machines (to 2026-08-15); 512/0/2 at 0.13.0's harness in the suite paste, Linux 2026-09-26 (a second Run all in one launch again, by the maintainer's account; `rsSeqCompare` green; its fourth probe line's first reading, engine note 2.11); 489/0/2 in the suite paste, Linux 2026-09-25 (a second Run all in one launch, by the maintainer's account; its third probe line read the engine source's comparison rule, engine notes 2.10 and 2.11), Windows 2026-09-25 (the same three probe lines) and Windows 2026-09-24 (the day's second and third runs; its first read 487/2/2, both FAILs fixed that day); phase-8 boot 2026-08-29 | bridge reader; RSL1 magic; own-head refresh; per-identity app state; the persona-index cap; two handle orders and the LAN draft compare off the number path | row 35; phases 5, 6, 7 live; phase 8 live; faststart re-run | S1-S4, NET |
| nocloud | no dated pass of this stack in the tree | mtime ETag after D-10; the D-02 menu (deferred) | the 69-item checklist, web-link and Tor halves; sections 7-8 | S1, S2 |
| holde-em | 929/0/5 folded at v0.25.6 / harness 48, Linux, 2026-09-26 (its first engine run, single-machine lines); 751/0/5 folded at v0.25.5 / harness 47, Linux and Windows, 2026-09-25 (the v0.25.4 and v0.25.5 pins' first recorded engine runs; the 5 skips are the live legs); 721/0/5 at v0.25.3 / harness 45, Windows, 2026-09-24 | **Level 2 not wired into play**; animations; the untested handlers; a keyless dealt seat (owner) | harness 48 in the paste on Windows; the standalone `heRunSelftest` and hotseat hands; Phase 1 exit; 2d/2e/2f on real machines; the oracle round | S1-S4, 3M, PERSON |

Suite coverage is what `python3 tools/check-suite-coverage.py` prints: the ratio
of public handlers the suite harness names, the exemptions (all onionxt's: engine
socket callbacks and watchdogs), and two advisory rows with armed floors,
holde-em's `he*` surface and box2dxt's raw `b2*` binding. This summary copies
none of its numbers (root `CLAUDE.md`: hand-copied ratios go stale); run it.

---

## 1. Suite-wide

### 1.1 Facts that shape the work

**The 2026-09-12 binaries have engine records on two rows: `x86_64-win32`,
2026-09-24 and 2026-09-25, and `x86_64-linux`, 2026-09-25 and 2026-09-26.** The
D-23 suite paste loaded all six native members from them and ran every member's
sections, first on Windows (runbook section 8; the maintainer's account that the
latest binaries were installed, and, given 2026-09-26, that the engine is 64-bit),
then on Linux
(2672/0/10; by the maintainer's account 64-bit Kubuntu 24.04 with "the latest
builds", read as the committed `x86_64-linux` files: the 2026-09-12 set, bar
sodiumxt's and box2dxt's run-12 files below), then on the same Windows machine
again by that account (2653/2/10, the loopbacks stalled; that run's binaries
were not stated, and every record below that puts it on the 2026-09-12 set does
so by INFERENCE: no Windows DLL has been committed since, and the refusals
below pass), then on the Linux machine again with the batch's paste
(2876/0/10, 2026-09-26; the same machine and builds by that account). The
reports agree where they can: torrentxt enforced the 996-byte
BEP44 cap, which entered the shim on 2026-09-08 (`aad430a`) and which among
committed builds only `421bab3`'s carry, and coinxt's `cxCheckABI` passed, so
its library answered ABI 7. No engine has loaded the
`x86-win32`, `x86-linux` or mac builds.
`release-binaries.yml` run
`34657390798` from `0f17ab5` was committed as `421bab3` on 2026-09-12. That commit
replaced every Windows DLL (all six members, both bitnesses) and the Linux and mac
libraries of torrentxt, enetxt, datachannelxt and coinxt. It left sodiumxt's Linux and
mac files and box2dxt's Linux files unchanged: those are still the release run 12 files
(`cec1e85`, 2026-08-27). box2dxt's universal-mac dylib shows one commit in git, the
2026-08-14 fold (`6070585`), but it is not a stale build: both release runs built,
verified and installed it, and each installer log says "(unchanged)", a sha256 match
(the shim and its build have not changed since the fold; runs 33025459610 and
34657390798, read 2026-09-24). Git records only changes, so since 2026-09-24 the
release commit's message carries the installer's per-library verdicts. No shipped native code has
changed since `421bab3`: the native edits since are comments (enetxt's guard note of 2026-09-25
among them) and datachannelxt's test-only seams, which the shipped library does not compile.
Before 2026-09-24 the latest dated engine records predated it: the
2026-08-24 paste, the 2026-08-27 two-machine paste and holde-em fold, the 2026-08-29
riptide boot, and the 2026-08-31 to 09-03 coin-wallet logs (the 2026-08-27 paste,
2440/2/3, does not record which platform or binaries it loaded). So the 2026-09-24
and 2026-09-25 runs are the first records for the `x86_64-win32` and
`x86_64-linux` rows, and a 32-bit run will be the first for `x86-win32` or
`x86-linux`. Record which DLL or `.so` row loaded; a regression there is a finding
about those builds.

**Windows ships different upstream versions from Linux and mac.** sodiumxt's MSVC
DLLs carry libsodium 1.0.22 against a pinned 1.0.20 (accepted by D-08, documented).
torrentxt's carry libtorrent 2.1.1 from vcpkg's unpinned port against 2.0.11: **no
decision covers it**. Its first Windows engine run was the 2026-09-24 suite paste
(106/106, on the `x86_64-win32` DLL, 64-bit by the maintainer's account; again
2026-09-25). datachannelxt's
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
machine needs glibc 2.38 or newer to load all six members. The 2026-09-25 Linux
machine, Kubuntu 24.04 by the maintainer's account (a release that ships glibc 2.39;
the run did not print it), loaded all six.

**Platform rows with no engine record** (runbook rows 23, 24, 47): universal-mac for
all six members (CI built and tested every dylib; box2dxt's was rebuilt
byte-identical by both release runs, see above); x86-win32 for sodiumxt, torrentxt
and coinxt (the Windows runs of 2026-09-24 and 09-25 were 64-bit by the
maintainer's account; coinxt's 32-bit DLL has not executed even in CI: its Windows
KAT step is x86_64 only); x86-linux for sodiumxt and torrentxt (the 2026-09-25
Linux run was 64-bit by the maintainer's account).

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
manual dispatch (rule 5); the UI kit's non-adoption by the four member harness
windows (the enetxt, datachannelxt, torrentxt and coinxt selftests), which carry the
harness scaffold and match the kit by value, on D-18's reasoning. The suite paste is
not among them: it adopted the kit and the boot self-check under D-23 (2026-09-24),
keeping the scaffold for its report.

### 1.2 Coding and doc work

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **Choose a suite Linux glibc floor.** Move each Linux release row into a manylinux container (as torrentxt's x86_64 row and box2dxt's per-push lane already do), or publish every measured floor (sodiumxt states none). Add a check to `tools/install-release-binaries.py` that refuses a floor above the stated one | Section 1.1: two members cannot load on current LTS distributions, and box2dxt's x86 floor regressed silently | M | owner, then dispatch |
| 4 | **Supply-chain hygiene.** SHA-pin the 54 `uses:` lines in `.github/workflows` (none is pinned today); add a root SECURITY.md with a disclosure contact (only nocloud has one); add a gate that checks coinxt's vendored trezor-crypto and libsecp256k1 against the commits `coinxt/native/vendor/VENDOR.md` names. No member has had an external security review | Standing gaps found by the 2026-09-08 blockchain research, re-verified 2026-09-23 | M | owner |
| 6 | macOS Gatekeeper/quarantine guidance for the unsigned universal dylibs, written from the first Mac session's record (runbook 2.1 and row 24 ask it to record the first-load behaviour and remedy) | None exists; unsigned distribution was accepted 2026-08-23 | S | engine |
| 8 | Publishing follow-ups: watch each member repository's first generated `gates.yml` / `native.yml` run and record the result; put the `XTALK_PUBLISH_TOKEN` expiry in a calendar (rotation steps: MEMBER-REPO-SPLIT section 2) | This session's GitHub scope cannot see the member repositories' runs; the token is the owner's | S | owner |
| 9 | Draft PR #138 (archivext reviewed against the 9.6.3 dictionary) targets a member that left this tree on 2026-09-21; it was still open and conflicted on 2026-09-23. Move it to the archivext repository or close it | A dead PR against this tree | S | owner |
| 12 | *(optional)* Pay down bare citations: `tools/check-doc-anchors.py` re-resolves anchored citations only and counts the rest as unverified | A line number is a fact about today's file | S-M | none |
| 13 | **Harness scaffold v2: `stPaint` paints by FIRST WORD**, as the suite core's `suLineKind` does (case-sensitive `FAIL`, `PASS`/`ok`, `SKIP`/`skip`, section headers), with a fixture for the note lines a first-word rule could misread. Carry it just before the four member harness windows' next engine re-pass, so one session proves the new block in all four; the suite paste repaints its own view after each run meanwhile (`suPaintResults`), which v2 would retire | The carried `stPaint` tests `begins with`, so a returned member report's indented `  FAIL` stays muted in the paste's All view. A master change re-carries into four published member harnesses, the preflight and the core, and relabels every window it touches | S | engine (rides the harness windows' next re-pass) |
| 20 | **The closing pass over-releases ENet.** `tests/suite-closing-pass.livecodescript`'s `closeStack` calls `enDeinitialize` bare whether or not leg B ever initialized ENet, and `cpBStart`'s "already hosting" refusal runs after `get enInitialize()`, leaving a hold it never returns; its `dcCleanup` is gated on `sDcReady`, a flag and not a count. Count the holds as the suite core does (`suEnInit` / `suEnRelease`) | The class the paste's counted holds closed on 2026-09-25: beside another ENet window, the close ends that window's hosts. Found 2026-09-25 by an interpreter probe (a close with leg B never run took no hold, gave one back, and the other stack's host was lost); not observed on an engine | S | none |
| 21 | **Number-like literals in check 23.** The rule exempts every literal, but by engine note 2.11's parse a hex chunk compared with a number-like literal compares as a number: "14e0" is "0014" (INFERRED from the engine source). Sites in the tree: riptide's zero-target checks against `kRsZeroTarget` (40 zeros, so a target spelled `0e` and then digits reads as 0), and `nostrxt-tests`' `... is "610162"` (and its demo copy: an 8-hex `"00610162"` would read equal). coinxt's wallet sites were settled by hand on 2026-09-26: `"0014"`, `"0020"`, the segwit marker `"0001"`, Electrum's `"100"`, the `"00000000"` fingerprints and `kCwScalarZero` go through `cwSameHex`, and what stays bare (`"5120"`, `"02"`, `"87"`) compares a chunk whose width a length check fixes with a literal no other hex of that width equals (`coinxt/CLAUDE.md`). Extend the rule so a literal or declared constant whose VALUE is number-like counts as hex-shaped beside a hex operand (a must-refuse fixture from each shape), then fix the sites (a letter prefix, or compare the chunk as text) | The literal exemption lets through the genesis-against-"0" shape note 2.11 names; the checker's review measured these sites on 2026-09-25 (holde-em's genesis-head assert took `heHexEq` at integration, `57ce37d`) | S-M | none |
| 22 | **Settle the interpreter's UNSURE forms on an engine.** The line LANDED 2026-09-26: riptide's harness prints a fourth diagnostic probe line (`rstTextProbe`, each item in its own `try`, nothing counted) reading `"0x10" is "16"`, `"inf" is "1e999"`, `"nan" is "nan"` (two texts built apart), an NBSP-edged `"3"` against 3 (`numToCodepoint(160)`), a 385-digit run (375 zeros, then 4294967296) against 4294967296, and `"0x1.8" is "1.5"`, beside the source's prediction `true,?,?,?,false,?` (each `?` the C library's). The last two replace this row's first spelling: the interpreter ANSWERS `"0x.8" is "0.5"` (text before strtod), and a run against itself reads true under every reading, so neither could teach it anything. riptide's check-script-vectors tier 1e holds the line's shape (each item's statements pinned, the line at `rstSectionHead`'s top level) and the interpreter's refusal of each item. READ on Linux on 2026-09-26 (the batch paste; runbook section 8; engine note 2.11 records it item by item): `true,true,false,false,false,true`, items 1 and 5 as the source decides, items 2, 3, 4 and 6 as a C99 `strtod` in a locale where 0xA0 is no space would read them, that reason INFERRED ("inf" is "1e999", two "nan" texts built apart are unequal, the NBSP-edged "3" is not 3, "0x1.8" is "1.5"); riptide's tier 1e holds the reading twice, its record and its ledger row, so a corrupted item fails. Left: the Windows reading of the line, verbatim (runbook S1 item 1; the maintainer will run it later); then teach `coinxt/tools/lcs-interp.py` (and its nostrxt twin) the answers the engines agree on, keep refusing an item whose answer differs by platform, and move tier 1e's refusal rows to the recorded answers. Teachable now: items 1 and 5 (decided by the source, and read so on Linux), and a zero-padded run past 384 characters against an IDENTICAL copy, which `_eq` refuses (`_n` reads it first) though every reading answers true | Since 2026-09-25 the interpreter REFUSES these forms, because engine note 2.11 does not establish them; an engine reading would let it answer (the source already decides items 1 and 5; engine note 2.11). Items 2, 3, 4 and 6 are the C library's, so one platform's reading cannot teach them alone | S | engine (the Windows reading); then none |
| 23 | *(optional)* After the next `release-binaries.yml` dispatch, re-record `tools/test-binary-freshness.py`'s `VECTORS` (bytes, VAs, cookie, section ranges and each DLL's sha256) from the new DLLs, and re-measure the guarded shape if the gate SKIPs a Windows ABI again | The recorded-build anchor is keyed by each DLL's SHA-256 and lapses with a printed NOTE once the DLLs are rebuilt; the mutation battery, the live sweep and the objdump and execution legs keep running on the new bytes. A new MSVC may vary the frame, and the gate then SKIPs by design | S | dispatch |
| 24 | **A dropped delimiter restore is invisible to an end-state check.** A handler that sets the itemDelimiter to comma and then restores what it found passes every check that only asks "is it comma afterwards?" (the coinxt, riptide and nostrxt vector gates, holde-em's execution gate, `check_delimiters`) whether or not the restore is there. Add a hostile-caller sweep to the headless boots (call each delimiter-setting handler with `"|"` set and require `"|"` back, as `check-suite-ui-boot.py` now does for `stCancelPump`), or a checker rule that a handler which sets a delimiter restores it on every exit path | On the engine the delimiter is handler-local (engine note 2.3), so a missing restore now costs only the rest of that handler, but the interpreter models it GLOBAL, so headless gates are exactly where a dropped restore would show and do not look. Found by the itemDelimiter rewording's review, 2026-09-26 (`stCancelPump`'s restore could be deleted with every gate green) | S-M | none |
| 25 | *(optional)* A second Run all in the `--full` profile: press the board's Re-run (`stRerun`) after the first run finishes and hold the second to the same facts, as the maintainer's Linux run of 2026-09-25 did on the engine | `--full` reproduces only the first Run all, and state left over from it is where check 6b's class of fault lives; about double the profile's run time | S | none |
| 26 | **Free text meets the number path.** Where user-typed or wire text (names, labels, tags, JSON keys, routes, device names) meets a bare `is`, `is not`, `=`, `<>` or an ordering, `strtod`'s `nan`, `inf`, `infinity` and hex-float spellings compare as NUMBERS, beside the exponent and leading-zero forms engine note 2.11 already names: on Linux a "nan" is never `is` another "nan" held apart from it, "inf" is "1e999", "0x1.8" is "1.5" and "0x10" is "16" (riptide's fourth probe line, read 2026-09-26; "Infinity" and "INF" INFERRED from the same parse). Sweep every member's shipped script for a bare comparison where BOTH operands can be free text, or free text and a number-like literal or number, and route each through a text compare: a letter on both sides (never `i` or `n`: engine note 2.11's free-text rule), `set the caseSensitive to true` where case matters, or a byte compare (holde-em's `heTSame` and nocloud's `qsSameText` are two such helpers). Pin each fixed site with a vector that feeds it "nan", "Infinity", "0x1.8" and "1e5": the family interpreter REFUSES a bare comparison of the first three (#22), so a site left bare stops its gate instead of passing. Filed already, and not duplicated here: riptide 3.1 coding #12 (the LAN draft's change detection) and datachannelxt 2.4 coding #9 (the DHT chat's offer nonce, where the "n" prefix before a wire `an` spells "nan"), two sites of this class; #21 covers hex beside a number-like literal, and check 23 (a name rule for hex) cannot see free text | Under a bare `is`, a display name "nan" never matches its own copy read back, the tags "inf" and "Infinity" are one tag, and a device named "0x10" is the one named "16" (on Linux; the "Infinity" spelling, and "NaN" in other cases, INFERRED from the same parse): any lookup, dedupe, own-post or change check over such text answers wrong, silently, and a person or a peer chooses the spelling. Items 2, 3, 4 and 6 of the probe line are the C library's, so a site's answer may differ by platform too (Windows unread). Found from the line's first engine reading, 2026-09-26; no sweep has run. One more site, found by reading the same day: coin-wallet's separator guards compare a value with its own stripped copy (`waSafeText(X) is not X` in `waSerializeWallet` and its label loop), so a wallet named "nan", or one holding an address labelled "nan" (a label a BIP-21 URI can carry), would refuse every Save, naming a tab or newline it does not have (INFERRED from the Linux reading; the wallet is not in the paste) | M | none |

### 1.3 Engine work (suite-level)

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | `tests/preflight.livecodescript`, then `tests/suite-selftest.livecodescript`, on Windows and then Linux (glibc 2.38 or newer); quit and relaunch OXT before every torrent-bearing paste (trap 5.1.1). Both pastes have run, each on a 64-bit engine by the maintainer's account: Windows 2026-09-24 (2620/5/3) and 2026-09-25 (2653/2/10), Linux 2026-09-25 (2672/0/10; runbook section 8), and the Linux paste half again on 2026-09-26 with the batch's paste (2876/0/10, the same machine by that account). Owed: the preflight on both platforms (neither machine ran it, by the same account, 2026-09-26 included), and the batch's paste on Windows (the maintainer will run it later) | S1 items 0-1 | the member rows | every member LOADED at its ABI; RECORD each member total (the runbook lists the last ones), do not match it; copy riptide's fourth probe line back verbatim (1.2 #22; Linux read it 2026-09-26, Windows owes it) |
| 2 | Engine-notes probes: the 2^53 line and the `or` probe | S1 | P | notes 2.4 and 2.5 promoted to OBSERVED with the exact text, or 2.5 rewritten |
| 3 | Other engine-notes probes: 5.3 (a second stack in front, and a `send ... in` handler writing an unqualified field: record where the write lands); 2.6 (`the number of chars of X + 1`, and `field "x" & tKind`); optionally 1.1 (a second `script "..."` line mid-file with a declared local read below it); 2.3's lineDelimiter half (a caller's lineDelimiter into a called handler and back, as box2dxt v32 probes the itemDelimiter; never probed on any platform) | S1 | - | each note promoted with a date, or left DOCUMENTED / UNEVIDENCED |
| 4 | The demo re-open fleet, including `start-here.livecodescript`: open one card-hook box2dxt game and one stack-hook demo from the launcher and record whether each builds on first open (its `go invisible stack` / parked-closed create path, engine note 5.5) | S1 items 3, 5 | 37, 38 | per row; this is the largest engine item |
| 5 | Platform rows: 32-bit Windows and Linux, and the first Mac load of all six dylibs (the 64-bit Windows and Linux rows ran 2026-09-24 and 09-25) | S5 | 23, 24, 47 | preflight LOADED and the member sections green on that row, bitness recorded |
| 6 | *(optional)* Cheap measurements nothing schedules: FFI-crossing cost and interpreter op rate; whether `byte N of X` on a 60,000-byte Data is O(1) or O(N); `seek to N in file` (a standing nocloud VERIFY) and `rename file` semantics; whether `open file ... for binary write` truncates an existing longer file (engine note 6.14 gives the four-line probe: the reference and engine source say it does, the tree's comments said it does not); whether OXT exposes SQLite through revDB | S1 | - | numbers recorded in engine notes; 6.14 promoted to OBSERVED with a date, or rewritten as a divergence |
| 7 | Model C Phase 4 exit: a FRESH user on each of macOS, Windows and Linux, following only section 13 of [ONIONXT-INTEGRATION-PLAN.md](ONIONXT-INTEGRATION-PLAN.md), completes a two-machine anonymous transfer | S4 on each OS + PERSON | - | all three done; the phase does not close before |
| 8 | The suite board's first engine run (D-23), in item 1's launch. PARTLY RUN 2026-09-24 (Windows): the build at 1200x640 with every row, the boot self-check green (9/0/0) with its summary note, Run all with the rows accounting for every check, box2dxt at 1200 wide, Copy results unchanged; the board review's fixes that a report can show (the merged skips, the banner, the renamed pump) ran in the day's third run. The same half ran on Linux on 2026-09-25 (2672/0/10, both loopbacks completing, Copy results by the maintainer's account), and there a SECOND Run all in one launch, TorrentXT installed (the maintainer's account): riptide's session sections green, which closed 3.1 engine #10. Windows ran the report half again that day (2653/2/10; whether a launch's first or second Run all, and how the text was copied, not stated). RAN again 2026-09-26 on Linux with the batch's paste, a fresh stack (2876/0/10): the derived stamp's boot line (`suite-board-0961bb91e5ee`, 1.2 #17), the teardown's counted ENet release (3 counted `enInitialize` calls, one `enDeinitialize` each, 1.2 #16), and by the maintainer's account a second Run all in one launch, copied with Copy results. What a text report cannot show is still owed, and so are the halves of those two changes that need another stack: the rebuild over an old-stamp board (the 2026-09-26 stack was fresh) and the counted holds beside a live `enet-selftest` | S1 item 1 | 48 | the pills' look after Run all; Run on sodiumxt, on torrentxt twice and on enetxt; each filter and a row's Show; whether a pressed Run stays hilited and whether the press arms the run; opening, running and closing the paste beside a live `enet-selftest` loopback leaves that loopback's hosts alone; the first open of a window built under the old `suite-board-1` stamp rebuilds it once |
| 9 | Tell the machine from the paste, on Windows. The paste's two loopbacks stalled on the Windows machine in all three 2026-09-24 runs and again on 2026-09-25, four of four in the same phases (they also stalled on 2026-08-27, whose phases and machine were not recorded), while the same loopback code COMPLETED on Linux on 2026-09-25 (runbook section 8 and 5.5), and again on 2026-09-26 with the batch's counted holds (the same machine by the maintainer's account), so the paste's code can finish on an engine and what is left is that machine or that platform's builds. On the Windows machine, run the standalone `enetxt/tests/enet-selftest.livecodescript` and `datachannelxt/examples/datachannel-loopback.livecodescript` | S1 (Windows) | - (runbook 5.5) | both stall: record an environment note (blocked UDP to 127.0.0.1) and leave the paste alone; both complete: the paste's loopbacks fail on Windows where the members' own do not, a defect to root-cause |

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
- Latest records: 106/106 at ABI 10 in the suite paste on Linux, 2026-09-25, the
  7-check ChaCha20 section included: its first RECORDED Linux run (before it, Linux
  was last recorded at ABI 9, 2026-08-18), on the `x86_64-linux` file (release run
  12's, 1.1) by the maintainer's account (64-bit, "the latest builds"), which closed
  engine #3; `put sxVersion()` was not recorded. Again 106/106 on Linux on
  2026-09-26 (the batch paste, the same machine by that account). On Windows, 106/106 in the suite
  paste, 2026-09-24 and again 2026-09-25, on the `x86_64-win32` MSVC DLL (64-bit
  by the maintainer's account, given 2026-09-26), which narrowed engine #1 to the
  32-bit DLL and `sxVersion()`, not recorded there either; earlier, 106/106 on
  2026-08-24 on a mingw DLL since replaced. The 2026-08-27 paste
  (sodiumxt green, platform and package not recorded) may have loaded the run-12
  Linux build first (coding #6).

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 5 | *(optional)* Bind the shim length accessors the `.lcb` does not expose (`sxt_secretbox_keybytes`, `sxt_aead_keybytes`, `sxt_kdf_*` ...); only `sxPwSaltBytes` is public, so callers hard-code 32. No ABI bump | API completeness; adds engine-pass debt | S-M | none |
| 6 | If anyone knows it, record which platform and which sodiumxt package the 2026-08-27 two-machine suite paste (2440/2/3) loaded: if it was a run-12 build, it is the first engine record for a committed sodiumxt binary | The record names no platform | S | owner |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | Preflight and suite paste (or `put sxSelfTest()`) on a **32-bit** Windows engine, the `x86-win32` DLL (the `x86_64-win32` one ran 106/106 on 2026-09-24 and 09-25), and `put sxVersion()` on either DLL | S5 | 23 | LOADED at 10; 106/0 with SHA3, ristretto and ChaCha20; `put sxVersion()` shows libsodium 1.0.22 |
| 2 | The same on a Mac (arm64; Intel too if available) | S5 | 24 | 10 and 106/0 |
| 4 | The same on a 32-bit Linux engine | S5 | 47 | the first x86-linux record |
| 5 | `sodiumxt/examples/sodium-demo.livecodescript` | S1 item 5 | 37 | all 7 tabs build, the About self-test green, the tamper case rejected (no boot self-check: a human judgement) |

### 2.2 torrentxt

- 85 public `bt*` handlers, 78 binds against 78 exports; coverage 85/85. **ABI 11**
  (`torrentxt/src/btx_abi.h` ("#define BTX_ABI_VERSION 11")), matching the `.lcb` and
  the committed binaries.
- The 2026-09-12 binaries carry the bounded rp1 queue, the 996-byte BEP44 cap and
  `alerts_dropped_alert` counting, reported through `btLastError()` until ABI 12:
  `torrentxt/src/torrent_shim.cpp` ("THE BOUNDED INBOUND QUEUE").
- Latest records: harness 106/106 in the suite paste on Linux, 2026-09-25, the
  996-byte caps and both `btAddTorrentFile` forms included, on the 2026-09-12
  `x86_64-linux` build by the maintainer's account (64-bit, "the latest builds"; the
  caps agree, since no committed Linux build before `421bab3` carries them): its
  first engine load, which closed engine #1; its libtorrent version was not printed
  (the tree pins 2.0.11 for Linux); again 106/106 on Linux on 2026-09-26 (the
  batch paste, the same machine by that account). Harness 106/106 in the suite paste on Windows,
  2026-09-24, on the 2026-09-12 `x86_64-win32` build by the maintainer's account
  (64-bit; its first engine load, and libtorrent 2.1.1's and
  `load_torrent_buffer`'s first RECORDED Windows run, the 2026-08-27 paste having
  recorded neither platform nor binaries; the 996-byte caps included), and again
  on 2026-09-25; 101/101 on
  2026-08-17, 08-20 and 08-24, the destructive handlers' refusal legs included. The 2026-08-27 suite paste (2440/2/3,
  platform not recorded) had every folded member green, torrentxt included.
  Two-machine evidence: riptide (2026-08-13, 08-15) and a maintainer report of rp1 chat
  on one LAN (2026-08-27, no PASS lines). The 2026-08-17/20/24 harness runs and the
  riptide runs used binaries built before run 12. The 2026-08-27 session does not
  record which binaries it loaded (run 12 committed torrentxt's at 00:38 UTC that day).
- No dated record shows these running: the `examples/torrent-helpers.livecodescript`
  helpers (Engine #8); `btRemoveTorrent` with deleteFiles=true, which the harness skips
  by design; a real `btMoveStorage` move, proven only on its stale-id refusal leg
  (2026-08-17) (Engine #6).
- `torrent-quickshare`'s route table is case-exact since 2026-09-25 (hex route keys;
  `qsRouteLookupKey` mirrored in `tests/fileserver_golden.py` and driven against the
  demo), and its LAN editor's session token is compared as text since the check-23
  sweep of the same day; verified statically; needs an OXT pass (Engine #2's re-open).

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
| 19 | Refuse a non-hex btih in the shim: libtorrent 2.0.x's `magnet_uri.cpp` ignores `from_hex`'s failure (2.1.1 checks it), so `btx_add_magnet` adds a garbage info-hash on the Linux and mac builds, and a pre-Model-C QuickShare fed a `BTXTOR1:` code cut to 40 characters joins swarm b000...0. Both QuickShares' share-code checks now require hex (`qsIsHex`, 2026-09-24); the shim fix is a native change, so it rides a dispatch. The smoke test pins today's behaviour per libtorrent version | A malformed code joins a real swarm instead of refusing | S + dispatch | dispatch |
| 20 | A truncated LOCKED `BTXTOR1:` code is offered as plaintext: when the address survives and the verifier is cut off, `qsReceiveOnion` shows the "not encrypted, download anyway?" prompt and dials without a key; the encrypted header then refuses it, so nothing is saved, but only after a network dial and a misleading prompt. Distinguishing "unlocked" from "lock cut off" needs a marker the code format does not carry today | A misleading prompt and a needless dial | S | owner (code format) |
| 21 | Port nocloud's dotfile guard (`qsHasDotSegment`, round 5) and reserved-namespace guard (`qsHttpReservedPath`, 2026-08-17) to `torrent-quickshare`, and hold `torrentxt/tests/fileserver_golden.py` to the demo: five of its mirrors (`has_dot_segment`, `http_req_length`, `file_size_probe`, `safe_filename`, `rate_short` / `eta_short`) name handlers the demo does not have (the golden was copied from nocloud's), and only its route section is driven against the script (2026-09-25). By reading, the demo's folder server answers `/.git/config` and `/.env` over Tor and the web link, and its listing shows dot-folders | A guard the golden claims and the demo lacks, against the shared folder's privacy promise; `torrentxt/CLAUDE.md`'s Quick Share lineage paragraph points here | S-M | none |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
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
- Latest records: the suite paste on Linux, 2026-09-25: folded 34/34 and the paste's
  own live loopback COMPLETED (127.0.0.1:27196: connect, the sealed ciphertext
  byte-for-byte, 60000 bytes reassembled into one message, a graceful disconnect),
  on the 2026-09-12 `x86_64-linux` build by the maintainer's account, and the same
  again on 2026-09-26 (the batch paste, its holds counted, suite-wide #16; the
  same machine by that account); the Windows
  pastes of 2026-09-24 and 2026-09-25, folded 34/34 on the 2026-09-12
  `x86_64-win32` DLL with that loopback stalled every time (1.3 #9); standalone
  selftest 2026-08-07; async loopback 2026-08-13; folded 34 on
  2026-08-20; `enet-lan-chat` on one Linux machine 2026-08-18; `enet-internet-chat`
  could not connect on one network 2026-08-27 (no hairpin, as expected).

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 4 | **`enet-selftest` gives back one ENet hold more than it takes**, once per close or Re-run. Its `stRun` initializes twice and its `stFinish` deinitializes twice (the second is labelled "extra deinitialize is a no-op 0", but the shim counts both inits, so it is the call that reaches zero); `stCleanup` then calls `enDeinitialize` once more, bare, on `closeStack` and on Re-run. Beside another ENet window holding the last hold (the suite paste's cross row holds one), that call ends the window's hosts, the defect the paste's counted holds fixed on 2026-09-25. Count holds as the suite core does (`suEnInit` / `suEnRelease`), and make the no-op leg a call at a count this stack knows is zero. The chat demos pair `ecStart`/`ecStop` and `eiStart`/`eiStop`; their only unpaired path is a re-fired `openStack`, which leaks a hold and harms no other window | Found 2026-09-25 while fixing the paste (an interpreter probe read the count 1, 3, 1, 0); not observed on an engine. Runbook row 48 says meanwhile not to close `enet-selftest` or press its Re-run while a paste run holds ENet | S | none |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | `enetxt/tests/enet-selftest.livecodescript` standalone | S1 item 6 | - (runbook 4.3) | no `RUN NOT FINISHED` trailer; the first async run of the member's own harness on the 2026-09-12 binaries (the suite paste loaded them first, 2026-09-24, and its loopback stalled on Windows four times to 2026-09-25: 1.3 #9; the paste's loopback completed on Linux 2026-09-25, on the `x86_64-linux` build by the maintainer's account) and the first standalone async run since the `sEnPolling` rename |
| 2 | Closing-pass leg B (inbound UDP 27300 on the Host) | S3 item 1 | 6 | "peer connected"; text and binary with a NUL echoed byte-exact; a graceful disconnect |
| 3 | `enet-lan-chat` on two machines (UDP 27099) | S3 item 6 | 6 | joins and leaves announced; lines relayed through one `enBroadcast`; RTT on the dashboard |
| 4 | `enet-internet-chat` across two networks | 2NET | 39 | INTERNET LIVE with a non-RFC-1918 remote |
| 5 | Suite paste on a Mac | S5 | 24 | LOADED at 2; the en1 sections green |
| 6 | *(optional)* `enPollLastError`'s throw paths (a dispatched handler that throws; a drain failure), after a small harness addition | S1 | - | the api-reference label on the throw paths flips |

### 2.4 datachannelxt

- libdatachannel v0.24.5, `NO_MEDIA` by decision; **ABI 1**; 31 public handlers;
  coverage 31/31. The 2026-09-12 binaries carry the 2026-09-09 orphan-channel fix.
  Both Linux libraries need glibc 2.38 (1.1).
- Latest records: the suite paste on Linux, 2026-09-25: folded 39/39 and the paste's
  own live loopback COMPLETED (negotiated, both ends open, SCTP at or above its
  16 KiB floor, the large payload whole), on the 2026-09-12 `x86_64-linux` build by
  the maintainer's account (it needs glibc 2.38; Kubuntu 24.04 ships 2.39), and
  the same again on 2026-09-26 (the batch paste, its holds counted, suite-wide
  #16; the same machine by that account); the
  Windows pastes of 2026-09-24 and 2026-09-25, folded 39/39 on the 2026-09-12
  `x86_64-win32` DLL with that loopback stalled every time (1.3 #9); first live
  loopback 2026-08-08; standalone async loopback
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
| 8 | **`dcCleanup` is process-wide and uncounted.** `dcx_init` is an idempotent one-time init (`dcCreatePeer` also calls it implicitly); `dcx_cleanup` frees every peer and channel in the process and joins libdatachannel's threads, however many inits came first; and `dcPoll` drains one queue shared by the whole process. So any stack's `dcCleanup` ends every other DataChannel stack's peers. Callers: the suite paste (since 2026-09-25 only while it holds a `dcInit` of its own), `tests/preflight.livecodescript`'s `pfProbeDc` (a `dcInit` then a `dcCleanup`, generated by `tools/build-preflight.py`), `datachannel-selftest`, the DataChannel demos, `riptide-social`, and closing-pass leg E (gated on the flag `sDcReady`). Refcount init and cleanup in the shim, the implicit init included, or scope cleanup and polling to an owner. A native change: rebuilt binaries (rule 5) | Found reading the shim for the paste's counted holds, 2026-09-25; the paste and preflight halves shown in the headless model, not observed on an engine. Runbook row 48 says meanwhile to keep DataChannel stacks closed for a run that includes DataChannelXT | M | owner, then dispatch |
| 9 | Validate `datachannel-dht-chat`'s offer nonce at the parse boundary. `wxApplyRemote` takes whatever precedes the first LF as the nonce, and `wxApplyOffer` dedups with `("n" & pNonce) is ("n" & sSeenOfferNonce)`: a nonce `an` spells `nan`, and if the engine reads that as a NaN (C's `strtod` does, and a Linux engine's reading of 2026-09-26 says it does there: the fourth probe line's item 3 builds its "nan" the same way, "n" then "an", and read it unequal to another, engine note 2.11; Windows is unread, and the family interpreter refuses the form) it equals nothing, itself included, so the same offer is re-answered and the peer rebuilt on every delivery. Refuse anything but 8 lowercase hex there | The letter prefix of 2026-09-25 is sound only for hex, and this nonce is not checked to be hex; found by the check-23 review by reading. Only a room-key holder can publish, so the reach is low | S | none |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | `datachannel-loopback`: **the only member demo with no engine record** | S1 item 5 | 37 | connected + open on both sides; chat in both panes; the boot self-check green |
| 2 | `datachannel-selftest` standalone on the 2026-09-12 binaries (Windows; Linux with glibc 2.38 or newer), recording which library loaded. The paste's own loopback completed on Linux 2026-09-25 on the `x86_64-linux` build (the maintainer's account) and stalled on Windows 2026-09-24 and 09-25 (1.3 #9); the standalone harness's own async loopback has not run since 2026-08-15 | S1 item 6 | - (runbook 4.2) | green, no trailer |
| 3 | Closing-pass leg E, and `datachannel-dht-chat` on two machines recorded BY NAME (the 2026-08-27 one-LAN report does not say whether the demo or leg E ran; its getting-started section 6 flow has no recorded run either) | S3 items 1, 6 | 6 | OPEN across machines; the record names the stack, both platforms and the selected ICE pair type |
| 4 | Leg E or the DHT chat across two networks | 2NET | 40 | a `srflx` / `prflx` pair (record `relay` honestly if both NATs force TURN) |
| 5 | Browser interop: `datachannelxt/docs/browser-interop.md` (the page and its OXT half landed 2026-09-24; the page was exercised in headless Chromium against the committed `.so` through its C ABI, which proves neither the `.lcb` binding nor an engine) | S1 + a browser | 40 | the channel opens; text arrives as a string, `dcSendData` as an ArrayBuffer |
| 6 | Suite paste on a Mac | S5 | 24 | the dc sections green on the two-slice-lipo dylib |

### 2.5 onionxt

- Pure script; coverage 37/48 (the 11 exemptions are engine socket callbacks and
  watchdogs; the 3 live-daemon ones retired 2026-09-24 to harness calls on their
  refusal paths).
- The **live-Tor core is engine-proven** from the early bring-up (before 2026-08-08),
  `oxh*` hosting included; the offline self-test ran 74/0/1 in the suite paste on
  Windows (2026-09-24 and 09-25) and Linux (2026-09-25 and 09-26), 61/0 on
  2026-08-17 (Windows);
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
- Library: 296/296 in the suite paste, Windows, 2026-09-24, on the 2026-09-12
  `x86_64-win32` DLL (64-bit by the maintainer's account): ABI 7's six
  `cxPubkeyCombine` checks ran green (its first engine run); again 296/296 on
  2026-09-25, on Linux on the 2026-09-12 `x86_64-linux` library by the
  maintainer's account (`cxCheckABI` passed: ABI 7) and on Windows on, by
  inference, the same DLL; 299/299 on Linux on 2026-09-26 (the batch paste, the
  same library by that account), row #8's three new bech32 lines included
  (below); 290/290 at ABI 6, Windows x64, 2026-08-24 (BIP-341).
- Row #8's exact-integer bounds (2026-09-25: `is an integer` in `cxBech32EncodeValues`, digit
  bounds before the arithmetic, `cwAmountAdd` for sums, the boot self-check's `div` / `mod`
  round trip) and its review's three (2026-09-26: `cwExpandExponent`'s exponent, every
  coinxt-demo counter field, coin-selftest's message-checked bech32 refusals). The library's
  half RAN green on Linux on 2026-09-26 (the batch paste): `cxBech32EncodeValues`'
  `is an integer` refused one ulp above 3 and -1e-15 through coin-selftest's
  message-checked lines, and "3e0" encoded exactly as 3 (engine note 2.12). The rest,
  in the wallet, wallet-core and coinxt-demo, which the paste does not carry, is
  verified statically; needs an OXT pass (`coinxt/CLAUDE.md`).
- Hex compares off `is`'s number path (engine note 2.11), 2026-09-26: check 23's 27 wallet
  findings through `cwSameHex` / `cwHexCompare` (one a version number, renamed), then a
  hand sweep's 15 more no name rule sees (PSBT signing's three scriptPubKey checks,
  BIP-322's key check, PSBT combining, the script-type and segwit-marker literals,
  `kCwScalarZero`, the inspect wait, the coinbase test, Electrum's seed prefix, the
  xpub fingerprints), each pinned by a tier-5 vector in `check-wallet-vectors.py` that
  fails with the site undone. Verified statically; needs an OXT pass.
- The wallet (`kWaVersion` 1.2.0, 13 screens) has engine logs from 2026-08-31 to
  2026-09-03: all four transports over clearnet and Tor, RBF, CPFP, a legacy broadcast
  (`7978bdd2...`, 2026-09-02), and in the tenth log the silent-payment send, an
  inscription reveal and a vault payment. Its surface from 2026-09-04 is headless only.

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | Wire `verify-independent-decoder.py --require` (with its pip installs) into the release job, or re-decide D-17 on true facts | D-17's premise is false (1.4); the check last ran 2026-08-13 | S | owner |
| 2 | Per-push CI is Linux only: add Windows lanes (a MinGW build and KATs on a Windows runner, including a 32-bit Python for the x86 DLL) and a mac lane, or record that dispatch-only is permanent | The x86-win32 DLL may never have executed anywhere (CI's Windows KAT step is x86_64 only, and the Windows engine runs of 2026-09-24 and 09-25 loaded the 64-bit DLL, by the maintainer's account) | M | owner |
| 3 | The rest of the Core plan: a `verifymessage` second opinion on the 2011-format signed message (allowlisted in `kWaCoreMethods`, called by nothing); JSON-RPC batching for the Core backends (one POST per request today); a Node-screen card for the regtest sandbox's own mining address (Mine pays the wallet's first address) | Named as left in `coinxt/docs/bitcoin-core-plan.md` | M | none |
| 4 | Restoring past the gap limit: a sync never extends the address window (windows extend on demand since 2026-09-03, a sync does not), so a restored wallet whose whole window is used can miss funds | Funds a restore cannot see | M | owner (it changes what a sync is) |
| 7 | Chain inclusion: the wallet verifies no inclusion proof (no `get_merkle`, `gettxoutproof` or `getblockheader` in any script), so "confirmed" is the backend's word | A trust gap stated by the 2026-09-08 research, still true | M-L | owner (scope) |
| 9 | **Backend numbers and the wallet's own sums, bounded like row #8's.** Integers a backend reports still reach arithmetic with no digit bound: `waMergeUtxos`'s `value` and `vout` pass `waIsDigits` and then `+ 0`; `waCheckedHeight` asks `is an integer`, so "1e20" is a chain tip; a coin's height passes `waIsInt` and then `+ 0`. The wallet's sums of coin values are unbounded too: the `add tRec["value"]` sites in `coin-wallet` (balance, MAX, CPFP, RBF, per address, leaf) and `wallet-core`'s `cwSelectionResult` and `cwBranchAndBound`. Bound each at its parse (digits, then `cwDecCompare` against 2^53) and send the sums through `cwAmountAdd`, with refusal vectors | A backend's number is attacker input like a decoded amount; a 20-digit value rounds on the engine where the interpreter stops. `coinxt/docs/wallet.md` says these are not bounded yet. Found beside row #8, 2026-09-25 | S-M | none |
| 10 | **The library's integer arguments are unbounded.** `cxUIntToBytesLE` (amounts, vout, sequence, version, locktime), `cxHexOfInt` (nonce, gas, chain id, v) and `cxVarInt` encode whatever number they are handed, so digit text past 2^53 is encoded as its rounded neighbour. coinxt-demo bounds its own fields (`cdWholeField`); the library does not. Add a text-shape bound and a 2^53 bound, decided on digits, at the library boundary, with vectors in `check-script-vectors.py`; the suite paste and the demos carry it | Fail closed on every malformed input | S | none |
| 11 | **`cwParseAmount`'s mBTC form truncates.** It computes `cwIntDiv(cwBtcToSat(mBTC text), 1000)`, so a sixth to eighth decimal is dropped silently: "0.00012345" mBTC reads as 12 sat and "0.000001" mBTC as 0 (a headless probe, 2026-09-25); its ceiling is 90071992.54740992 mBTC. Move the decimal point in text instead (for example `cwExpandExponent(tText & "e-3")`) and refuse sub-satoshi precision, as `cwBtcToSat` does | A silent truncation of what a person typed | S | none |
| 12 | Decide what the History screen shows for an UNKNOWN amount: `cwSatToBtc` prints an empty amount as "0.00000000", because the engine orders empty as 0 (`coinxt/CLAUDE.md` records the question the 2026-09-25 census raised) | A blank may say "unknown" more honestly than a zero | S | owner |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | **Row Q's wallet half:** silent-payment receiving in `coin-wallet` on testnet (the "secp256k1 keys" section's six `cxPubkeyCombine` lines ran green 2026-09-24, and on Linux and Windows 2026-09-25) | S1 + NET | Q | Inspect repaints `FOUND:` from the socket callback; Save writes an `sp` line; a second Inspect makes no request |
| 2 | `coinxt/examples/coinxt-demo.livecodescript` | S1 item 5 | 37 | the test mnemonic's published BIP-84 / BIP-44 / ETH addresses; sign/verify; the P2WPKH and EIP-1559 transactions decode |
| 3 | The four-family broadcast: record the legacy P2PKH spend (`7978bdd2...`, 2026-09-02); still owed are native P2WPKH from the wallet, EIP-1559 on Sepolia from the demo (broadcast externally) and EIP-155 from the message box | NET (testnet and Sepolia funds) | 43 | each transaction accepted by the network |
| 4 | The wallet's surface since 2026-09-04, and legs the logs did not reach, shortest first: the boot record; BOLT11 and runestone Inspects (a mainnet backend); the Ordinals screen (prepare, save and reopen, fund on signet or testnet4, reveal); the Vault (lock, pay, then spend after its height with a node accepting it); BIP-322 from a taproot wallet verified in Core or Sparrow; testnet4 with a BIP-329 export and import; Electrum on the mainnet onion (port 110); the Update-from-main swap; the right-click selection fix and three corrected menu items; the stale-answer skip, paint and pump timing and the mixed tip+fees batch; a backend un-marking a coin it still lists, and Esplora's 400 body in the log; CPFP on a foreign transaction; an Electrum-format seed opening real coins; the 2026-09-10 audit fixes (a refused socket, a non-ASCII label saved and reopened, the boot record's four address lines, the new `cw*` shapes); the 2026-09-26 hex-compare rewrites (broadcast marks, the bump guard, CPFP coins, the raw-transaction check, the PSBT, multisig, taproot and BOLT11 key matches: on ordinary txids a broadcast, RBF and CPFP run shows they did not regress) | S2 + NET | 43 | each `coinxt/docs/wallet.md` line's own criterion |
| 5 | A Bitcoin Core 26+ regtest node: the Node-screen sandbox (Start, Mine, Reorg, Stop), the autotest once, `core-rpc` and `core-cli` (+ tor and the node as an onion for `core-tor`). Settle the plan's section 11 risks: HTTP/1.1 keep-alive and megabyte `Content-Length` replies over a LiveCode socket (fallback `Connection: close`), the pruned-node rescan refusal offering the scan tier, and on Windows the cookie under `%APPDATA%\Bitcoin` and console flashes | S1 + a local node (+ tor) | 43 | every "Not run against a node" line in wallet.md flips |
| 6 | Suite paste on a Mac and on a 32-bit Windows engine | S5 | 24, 47 | `cxCheckABI` silent; the coinxt sections green |
| 7 | Open the wallet once on each engine: the boot self-check's "two exponent-form txids are two values, in hex order" line is the first engine reading of `cwSameHex` / `cwHexCompare` at a number-like pair (engine note 2.11) | S1 | 43 | the line PASS |

### 2.7 nostrxt

- Two files: the `nx*` core (81 handlers) and the `nxr*` relay client (23); coverage
  104/104. NIPs 01, 19/21, 44 v2, 42 (build and answer), 13, 05, 11, 65 (build and
  parse).
- **The core is ENGINE-PROVEN 2026-08-24:** 274/0/2 in the suite paste (the 2 skips
  are the relay section, which is not in the paste); 277/0/2 on Windows 2026-09-24
  and 09-25 and on Linux 2026-09-25 and 09-26, the 2026-09-09 fix's pins and the
  278 floor included.
  **The relay SEND half was live-proven 2026-08-24** against wss://nos.lol: connect,
  handshake, publish, ok-true.
- Static only: the receive leg, NIP-42, every `ws://` path, TLS on a bad certificate,
  and the 2026-09-09 guard-nesting change's third site (`nxPowCheck`), which no
  harness runs.

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
- Records: harness v32 385/0 in the suite paste on Windows (2026-09-24 and 09-25,
  `playLoudness` read back exact both times) and Linux (2026-09-25 and 09-26; the
  2026-09-26 run's slab-fall y printed Windows' 836.252747, not 2026-09-25 Linux's
  836.252708, its cause not recorded: `box2dxt/CLAUDE.md`'s ledger); v30 375/0
  Windows (2026-08-20), 374/1 Linux (2026-08-21; the line
  is `playLoudness` readback, engine note 5.4, a printed note since v31, and the
  2026-09-25 Linux run read the same constant 0). v31 (374 expected) has no record
  of its own: the 2026-08-24 paste's zero failures make it green by inference only.
- Five platforms committed; the universal-mac dylib (ABI 4) has never been loaded by an
  engine. It was rebuilt byte-identical by both release runs (1.1). CI's smoke test
  enters all 370 LC_API exports under ASan/UBSan. Risk R1 has Win32 verdicts only
  (2026-06-10).
- Harness v32 (2026-09-24) drives the ten 2026-09-09 delimiter-fixed Kit handlers
  under a caller's tab; it ran 385/0 on Windows on 2026-09-24, on the suite paste's
  1200-wide card, and its two lines answered engine note 2.3 there: a caller's tab
  does not reach a called handler, and a Kit call leaves its caller's delimiter
  alone. That closed coding #10 (restore the ten handlers' delimiter only if a
  callee's comma leaked back: it did not). Linux gave the same two answers on
  2026-09-25 (385/0 on the same card), which closed engine #1, and Windows gave
  them again the same day. Both references name
  every handler (376/376 raw, 313/313 Kit), held by `tools/check-reference-docs.py`.

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 2 | **The x86-linux glibc regression, 2.17 to 2.34:** build that release row in a `manylinux2014_i686` container (as `native-box2dxt.yml` already does), or publish the floor | A silent portability regression | M | dispatch; revisit D-03 |
| 4 | Platformer polish that can be done in the tree: the dev level-picker behind the debug toggle, or styled as intentional; sweep unused handlers and the dead camera-fallback paths; extend `tools/audit-platformer.py` to the vertical L7; check the win-screen summary (time, falls, gems, stars, coin score, hero, a "flawless run" callout); retune `pfMakeCoin`'s coin-tier thresholds if wanted | The code half of the polish plan | M | none |
| 5 | The raw `b2*` script ratchet: 245 handlers named by no script | Blind assertions against a foreign-bound API would mostly be test bugs | L | engine |
| 8 | Point `box2dxt/README.md`'s build badge at the member repository's own `native.yml` once that lane has run | It still points at the suite lane | S | the first member-repository run |
| 11 | Native shim defects found statically 2026-09-24, each a shim change that needs its binaries rebuilt by a dispatch (rule 5): the per-type joint accessors (`src/box2d_lc.c` near 1610-1712) check that the handle is live, not the joint's type, so a wrong-type joint reaches Box2D, and `b2lc_joint_type` answers 0 for both a distance joint and a stale handle; `b2lc_shape_polygon_update` on a non-polygon zeroes the count but keeps the previous radius; the committed Linux `.so` files carry SONAME `libbox2dxt.so` (`BOX2DXT_BARE_SONAME` is OFF), so `b2LoadNativeLib` / `b2LoadNativeLibHere` cannot preload them. All three are documented in `box2dxt/docs/api-reference.md` | Wrong answers a script cannot tell apart | S + dispatch | dispatch |

Parked by D-19 (2026-08-27, "triggers stand"), not scheduled: Wave 8 builder
cross-pollination, `b2kScene*` and enemy-pattern promotion (when a second game needs
them), streamed music, multi-player controller keying, the snake/serpent audit
extension, true multi-layer parallax (waits on transparent overlay art).

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 2 | The five games from `start-here.livecodescript`: `box2dxt-demo`, `-platformer`, `-slingshot`, `-contraption-builder`, `-spike-gamekit` | S1 item 5 (Windows, Linux) | 38 | each builds on FIRST open; the contraption Images panel does not throw; the platformer card fade reveals the level and the L7 camera works; slingshot's own list passes |
| 3 | Risk R1: `box2dxt-spike-gamekit` on Linux and a Mac, recording the S1-S12 verdicts | S1 + S5 | 38 | the verdicts |
| 4 | First Mac load: install the `.lce`, `put b2Version()` returns 4, then the paste section and the spike | S5 | 24 | as named |
| 5 | The platformer polish pass with the owner: facing and scale clean on every sprite in all 7 levels (hitbox vs art, bind offsets, HUD scale, the heart/portrait row); feel locked (move and jump speeds, coyote/buffer/jump-cut, air and wall jumps, dash, springs, swimming, lifts, conveyors); fair hazard timing and an intentional L1-to-L7 ramp; scenery placed by eye; consistent particles; every action audibly cued, nothing doubled; an accurate pause/help overlay; the first 30 s need no unexplained move; transition-card cosmetics and light card text on L6/L7; the parallax seam; each hero skin clean across idle/walk/jump/duck/climb | S1 + PERSON | - | the owner's sign-off |
| 6 | A fresh-machine package run: build with `tools/make-release.py`, install on a clean machine, play end to end | S1 (a clean machine) | - | installs and runs |

---

## 3. The apps

### 3.1 riptide

- Library 0.13.0 (2026-09-25: wire seqs ordered exactly by `rsSeqCompare` and bounded
  on their high half by `rsIsWireInt`, in the library and the demo's LAN checks; the
  hex handle, key and content-address compares check 23 and its review found, moved
  to text at integration, `57ce37d`; verified statically; needs an OXT pass). The
  library's half RAN on Linux on 2026-09-26 (the batch paste, 512/0/2): the harness's
  17 `rsSeqCompare` lines and the 2^53 watermark lines green, and the moved compares
  in `rsIngestHead`, `rsIngestPost`, `rsIngestBlob` and `rsIngestBridge` on every
  ingest line, on ordinary hex (no line feeds them a number-like pair). The demo's
  LAN checks, which the paste does not carry, stay verified statically; needs an OXT
  pass. 107 `rs*` handlers, coverage 107/107 as the gate printed it on 2026-09-26. The
  five-card demo embeds
  nostrxt (core and relay), riptide, onionxt and onion-httpd; `check-demo-boot` boots it
  headlessly over two capability profiles (it prints its own count).
- Records: phases 1-2 two machines 2026-08-13, phases 3-4 2026-08-15; mid-download
  playback measured NEGATIVE 2026-08-27 and fixed that day (`raMediaFrontReady`);
  phases 6-7 compute engine-green to 2026-08-24 (391/0), the whole harness 489/0/2
  in the suite paste on Windows (2026-09-24 and 09-25) and Linux (2026-09-25; by
  the maintainer's account a second Run all in one launch, TorrentXT installed,
  whose green session sections closed engine #10), and 512/0/2 at 0.13.0's harness
  on Linux (2026-09-26, again a second Run all in one launch by that account; its
  fourth probe line's first reading, engine note 2.11); phase 8's v11 boot 9/1 on
  2026-08-29 (the FAIL was the self-check's own defect, since fixed).
- Phase 5 has never run on two machines. The 2026-09-09 prefix-free LAN tags supersede
  the engine-green admission bytes; the harness sections added after 2026-08-24 have
  run in the suite paste since 2026-09-24 (above), while the demo's changes since its
  2026-08-29 boot are static only.

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **A bridge reader in the app:** `rsRequestBridge`, `rsIngestBridge` and `rsNostrBridgeFromEvent` have no app caller. Persist its `pMinSeq` watermark in RIPTAPP1 as `sHeadSeen` is | Phase 8's done-criterion needs the bridge resolved in BOTH directions; the runbook's phase-8 step 6 is blocked until it exists | M | owner (scope) |
| 2 | **Decide RSL1's magic** after the 2026-09-09 tag change: rule 3 says a framing change mints a new magic, and the preimage changed without one, so pre- and post-2026-09-09 devices silently fail admission with each other | Protocol hygiene; it dictates the phase-6 setup | S | owner |
| 4 | Own-head refresh while online: the demo re-puts its BEP44 head only on post, BEP44 items expire, and D-06 rules out follower republish, so the author's own re-put is the only retention | Feeds go dark | S-M | owner (cadence) |
| 6 | Scope calls: the pairwise room (`rsRoomId`, spec 5.2) is library-only, so wire it or record that for good; an anon file transfer over the onion (`rsBtxo*`, spec 8.3) has no app caller (M to build); followers-only sealed media (spec 4.4) is deferred and would need its own spec and record format (L) | Library surface the app does not use | S-L | owner (scope) |
| 8 | One app-state file per machine, not per identity: `raAppSave` seals the current identity's state over the one `RIPTAPP1` file (`riptide/examples/riptide-social.livecodescript`, the app-state path near 17312), and recovering your own head marks the state dirty, so unlocking a SECOND identity with a published head can overwrite the first identity's follows and watermarks. Key the file by identity, or refuse to save over another identity's file. Found statically 2026-09-24; the two-machine runbook's phase 8 step 8 now asks the tester to watch for it | Silent loss of a user's follow list | S-M | owner (file layout) |
| 10 | **Cap the persona index.** `rsAnonSeed(pMaster, 100 + k)` derives subkey 200 + k, which is exactly `rsAnonDmSeed(pMaster, k)`'s seed, so one seed would feed both ed25519 and crypto_kx, against the decision "one seed never feeds two cipher schemes" (executed 2026-09-25: `rsAnonSeed(M, 100)` equals `rsAnonDmSeed(M, 0)`). Neither handler refuses an index above 99, and the protocol's subkey table (`docs/RIPTIDE-PROTOCOL.md` section 2, `100+n` / `200+n`) gives n no bound; a huge index also loses precision in `kRsSubkeyAnonBase + pIndex`. Refuse `pIndex >= 100` in both and state the bound in the table | Latent cross-scheme key reuse in the public library API (the demo uses persona 0 only) | S | none (owner, if the table's bound counts as a spec change) |
| 11 | **Two handle orders compare on the number path** (engine note 2.11): `rsRoomId`'s `tA <= tB` and `rsDmSessionKeys`' `tMine < tTheirs` and `tMine is tTheirs` compare 64-hex handles with bare operators, under plain names check 23 cannot read. When BOTH handles are number-like (all digits, or digits, one `e`, digits) the engine compares them as numbers, so two peers could both pick the kx server role, or order a room's keys differently. Compare with a letter prefix on both sides (lowercase hex in text order is byte order), or byte by byte | Practically unreachable: a random handle is number-like about once in 10^13, and both must be; it is the class note 2.11's rule names | S | none |
| 12 | **The LAN draft's change detection compares number-like text as numbers** (engine note 2.11): `raLanSyncTick` re-sends a draft only when `tText is not sLanDraftLast`, and the typing triggers use `tText is not sLanDraftSeen` and `tText is not sDcTypingSeen`, so a draft edited from `12` to `0012`, `1` to `1.0` or `100000` to `1e5` is never re-sent and the peer keeps the old text (`set the caseSensitive to true` fixes case, not the number path). Compare with a letter prefix on both sides | Cosmetic, a draft divergence until the next edit; shown in the interpreter on 2026-09-25, and the exponent form is OBSERVED in 2.11 (2026-09-25). By the 2026-09-26 Linux reading a draft that reads "nan" never equals its last broadcast either, so it is re-sent every debounce interval and keeps renewing the typing window (INFERRED; suite-wide #26 is the class) | S | none |

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | Re-paste `riptide-social`, then the Nostr card offline | S1 item 3 | 35 | the boot self-check reads 10 passed / 0 failed; an npub shows; Post says "not sent" with no relay; RIPTAPP1 round-trips |
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
- Routes are case-exact since 2026-09-25 (gotcha 22: hex route and root keys,
  `qsSameText`, a declared method must be a token), and the LAN editor's session token
  is compared as text since the check-23 sweep of the same day; verified statically;
  needs an OXT pass (checklist sections 2 and 4).

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

- **v0.25.6, harness 48** (unreleased; table protocol `kHeEnvV` 2), carrying onionxt.
  Built: the Phase 1 hotseat; 2d, 2e, 2f; the Phase 3 oracle; 4a-4e Level 2 compute
  with void-and-audit; Phase 5 DLEQ; 4f's batch mask step. Coverage: the gate's
  advisory holde-em row (floor armed) prints the game handlers no test names; the
  third leaf tranche, section 24, named 14 more on 2026-09-24, and v0.25.6's pins
  named more.
- **v0.25.6 (2026-09-25 and 09-26): its pins engine-run on one machine 2026-09-26
  (below); across machines verified statically; needs an OXT pass:**
  turn-bound acts, sit-out marks and one sender predicate (`heWireSenderOk`, live and
  in History), which closed #13-#15; its fix pass: table protocol 2, so a table
  mixing it with an older holde-em is refused by name at the invite's `p2:` tag, the
  handshake and onion hello, the relay and the ingest (every machine at a table must
  run the same holde-em), History replaying row 16's rules (the board's street order,
  the settle the table applied, a timeout's prescription and bank checks, a timeout
  only for a dealt seat), one dealLevel per hand and one key per seat; that pass's
  review (the relay spends a sequence number only on what the ingest accepts; a cfg
  the host re-signs mid-game); and its round 2 with its review: the open-hand seat
  rule (`heSeatAssignOk`, which closed the dealer seat re-sat mid-hand) and History
  seating a late joiner. The v48 total was recorded on 2026-09-26 (engine #1):
  the harness pins RAN green on Linux (the batch paste, 929/0/5 at v0.25.6 /
  harness 48; every new line PASS, among them table protocol 2's admission and
  naming, turn-bound acts, sit marks, the sender predicate, `dealLevel`, the
  open-hand seat rule and History's late joiner). They are single-machine
  loopback lines: on a live wire between machines v0.25.6 is still verified
  statically; needs an OXT pass (engine #4), and Windows has not run harness 48.
- Folded records to **929/0/5 (2026-09-26, v0.25.6, harness 48, Linux; above)**, and
  **751/0/5 (2026-09-25, v0.25.5, harness 47, Linux, then Windows the same day)**:
  the harness pins of v0.25.4's `heHexEq` and near-integer fixes and of v0.25.5's
  canonical wire indices (`heCanonIdx`), walked counts, hand-bound wires and audit
  guards ran green, their first recorded engine runs; on a live wire
  between machines they are verified statically; needs an OXT pass (engine #4). 721/0/5 on
  2026-09-24 (v0.25.3, harness 45, Windows); 667/0 on 2026-08-27 (v0.25.2, harness 43). Played by a person:
  three hotseat hands (2026-08-17), and a first two-machine 2d contact (2026-08-27)
  where the hand dealt under the lobby overlay (v0.25.3 fixes it, statically).

**Coding.**

| # | Work | Why | Size | Blocked by |
|---|---|---|---|---|
| 1 | **Wire Level 2 into played hands.** The dealLevel gate refuses anything but 0 and 1 (`holde-em/src/holdem.livecodescript` ("unsupported deal level")). Needed: `shuffleStep` / `unmaskStep` on the wire, a `level=2` / `dleq=1` table config, the orchestration, a netsim section | The 4d machine it drives is pure and engine-green, but nothing plays on Level 2; it blocks 4f and the Phase 4 exit | L | none |
| 2 | The Phase 1d / spec 11 animations: deal slides with a ~70 ms stagger; the squash-flip through `b2kSpriteOnFinish`; one-impulse `b2kForce` chip tosses; a `b2kSpriteMoveTo` pot push | Specified and unbuilt | M | engine (a tuning eye) |
| 3 | **More leaf tranches over the untested handlers** (the coverage gate's no-test list). Section 24 (2026-09-24) named 14 consensus leaves (`heNetEngineFold`, `heNetTimeoutRearm`, `heNetTurnClockStart`, the `heBet*` leaves, `heL2ChainOrder`, `heL2VoidMark` and two `heL2*` point refusals). Still owed first: `heHandSettle`, which a harness cannot call as it stands because it sends `heNextHandTick`, which deals a hand (a seam, or a test of its pieces), and the rest of the `heL2*` point helpers | Consensus code no test names | M | none |
| 5 | BEP44 profiles and play-money standings (spec 3/5/8.3): the `btDht*` BEP44 calls have 0 call sites | Build it or strike it from the spec | M | owner |
| 6 | Seven to nine seats (a spec 1 goal; the build is 2-6) | Build it or strike it | M | owner |
| 7 | The optional direct-TCP upgrade lane (pairwise `btMapPort` plus engine sockets, for sub-100 ms actions; 0 call sites) | Build it or strike it | M | owner |
| 8 | Close runbook row 14 at inference strength, as row 26 was: section 11's "seeds XOR" and "full shuffled deck" assertions ran green in every folded run from 2026-08-17 on, and engine note 3.1 answers which stream the pre-fold runs dealt from | A leg the evidence already covers | S | owner |
| 9 | `holde-em/assets/sounds/NOTICE.md`'s cardShuffle row reads as if the sound were wired "in the deal-animation increment"; the source leaves it unwired. A one-word fix in a frozen NOTICE file | Accuracy of a shipped notice | S | owner (explicit OK) |
| 10 | **Table admission list and `cfg` co-signing** (spec 5, 6, 7.3, 9): an admitted-pubkey list (or an explicit open flag) in the host `cfg`, void/forfeit rules in `cfg`, and per-player co-signing of `cfg` before hand 1. Today every table is effectively open (any key whose token verifies is admitted: `heAdmitTokenVerify`) and `cfg` is host-authored only (`heLobbyCfgBody`; `heHostRelay` refuses a `cfg` from any other key). A consensus change: the protocol-kat pins move, `kHeHarnessV` bumps, and so does the table protocol (`kHeEnvV`) | Specified, not built; a player cannot bound who sits at the table or bind the host to the rules | M | none |
| 17 | **A host can deal a seat that no key holds**, one no sit ever filled included: `handStart` checks only the seat list's format. Such a hand can never settle (no key may reveal that seat's position), a stall the host could cause anyway; the open-hand seat rule's refusal of a dealt but keyless seat exists only for this case. Refusing a `handStart` that deals a keyless seat would close it at the source | A further consensus narrowing, left for the owner by the fix pass's round 2 and its review (2026-09-26) | S | owner |

Deferred by the owner on 2026-08-16: spectators. Picking them up needs a wire and UI
decision (a role a joiner can choose, or a sit-request the host answers).

**Engine.**

| # | Run | Where | Row | Green (in brief) |
|---|---|---|---|---|
| 1 | The standalone stack with `heRunSelftest`, then 2-3 hotseat hands. The suite-paste half RAN on Linux and on Windows 2026-09-25 with the v47 total recorded both times (751/0/5 at v0.25.5), after the four wire-arity checks and the nested `heBetApply` guard first ran on 2026-09-24; at v0.25.6 / harness 48 the suite-paste half ran on Linux on 2026-09-26 with its total recorded (929/0/5; runbook section 8). Owed: the standalone half (`heRunSelftest` and the hotseat hands) at harness 48, and the paste on Windows at harness 48 | S1 items 2, 4 | 14 | `heRunSelftest` ends `==== N pass, 0 fail, M skip ====` and `RESULT: green` at v0.25.6 / harness 48 (RECORD N rather than matching any earlier total); the hands complete with no error dialog. (The guard has tested `is an integer`, not `trunc`, since v0.25.4, and its non-numeric and near-integer refusals ran green on 2026-09-25; whether `trunc` of a non-number throws stays unrecorded) |
| 2 | Phase 1 exit: a full 6-seat hotseat session with side pots and all 17 cards on screen, plus the confirming eye on the 720p layout | S1 + PERSON | 42 | as named |
| 3 | 2f bring-up | S2 item 6 | 20 | the Tor pill's states; the invite `p2:<64hex>@<56base32>.onion` (the table-protocol tag since v0.25.6); the derived address equals `oxServiceAddress` |
| 4 | 2d re-run and the Phase 2 exit: a 6-seat table over rp1 across at least 3 machines on real home networks (extra instances fill seats); a mid-hand disconnect that reconnects and resumes; tampered and replayed envelopes provably dropped; receipts matching on every seat. Every machine runs the same holde-em (table protocol 2); optionally one on an older build, refused by name (record the v0.25.6 side's words) | S3 item 4 (3+ seats) | 18 | as named |
| 5 | 2e liveness on wall clocks, plus an attempt at the recorded KNOWN EDGE; report whether the owner-accepted `kHeSeatLiveSecs` of 600 s fits a real table's join-to-boundary gap | S3 item 5 | 28 | per row |
| 6 | 2f exit: a multi-hand onion session, a real host-stream loss, redial and a trimmed resync | S4 item 5 | 20 | per row |
| 7 | Phase 3 exit: two players and a non-playing onion oracle; kill the oracle mid-hand, then void and resume | 3M + tor | 42 | the oracle never holds a seat; the void resumes per spec 9 |
| 8 | 4f and the Phase 4 exit (after coding #1): the batched mask step (4 FFI crossings) does not visibly hitch the table and the pre-ABI-9 fallback's ~312 crossings stay acceptable; then full Level 2 sessions at 6-max across real machines, about 6 s per street over rp1 | S3 | - | user-verified |
| 9 | Phase 5: a hostile review of the deal implementation by a non-author, and a soak; spec 13's value-readiness checklist honestly assessable. Name who does it | PERSON | - | review findings closed |

---

## 4. Recommended order

Advisory, like the recommendations in OPEN-DECISIONS: a route, not a decision.

1. **Headless first.** The 2026-09-24 pass closed the short list that stood here
   (box2dxt v32, nostrxt's floor and pins, onionxt's exemptions and launch checks,
   torrentxt's boundary tests and HEAD port, the enetxt and datachannelxt smoke
   blocks, riptide's LAN keys, the stale-text rows), and the 2026-09-25/26 batch the
   next one (suite-wide #14-#19, holde-em #13-#15, riptide #9, coinxt #8, nocloud #6,
   torrentxt #18, enetxt #3; suite-wide #22's probe line landed 2026-09-26, and
   Linux read it the same day, its Windows reading owed). Left with no blocker,
   the short ones first: the stacks
   that release a hold they never took (enetxt #4, suite-wide #20) and
   datachannel-dht-chat's nonce check (datachannelxt #9); the number-path compares
   check 23 cannot read (riptide #11 and #12, suite-wide #21's literal rule, and
   #26's free-text sweep);
   riptide #10 (the persona-index cap); coinxt #9-#11 (the bounds row #8 left, and
   the mBTC form's truncation) and #3 (the Core residue); torrentxt #21
   (torrent-quickshare's guards); nocloud's optional #4 boot gate; holde-em #3
   (more leaf tranches), #10 (the admission list, a table-protocol bump) and the
   L-sized #1 (Level 2 in played hands); box2dxt #4 (platformer polish); and the
   optional rows. Regenerate the paste, the preflight and the demo embeds once,
   at the end of any batch.
2. **Release-lane decisions, then one dispatch:** the Windows pins and the glibc floor
   decided, torrentxt ABI 12 landed in the same change,
   `release-binaries.yml` dispatched once, so the engine session proves one coherent set. Proving today's
   binaries first and dispatching after is equally honest; mixing the two wastes a pass.
3. **The engine sessions, in the runbook's order:** the paste's headless `--full`
   run first, on a dev machine (runbook 3.2, minutes), then S1 (Windows, then Linux with
   glibc 2.38 or newer; about 3-4 hours), then S2-S5 as resources allow, and the NET,
   2NET and 3M legs on their own. Record totals rather than matching them. S1 item 1
   now includes the half of the suite board's first run (runbook row 48, D-23)
   that a text report cannot show; the 2026-09-24 and 2026-09-25 runs settled
   engine note 2.3's itemDelimiter half for Windows and Linux (box2dxt v32), and S1
   still settles 6.14 (whether `open file ... for binary write` truncates; a
   four-line probe). Every S1 should record the bitness, the distribution and
   the package, as the 2026-09-25 account did, and what it did not: the OXT
   version (the account says only "the latest") and `put sxVersion()`. The
   2026-09-25/26 batch's paste first ran on Linux on 2026-09-26 (2876/0/10; its
   totals are the runbook's last records). The next paste, on Windows (the
   maintainer's next run), records the batch's totals there and riptide's
   fourth probe line verbatim (#22); paste it into a stack an earlier paste
   built under the old `suite-board-1` stamp and watch the board rebuild once
   (the 2026-09-26 stack was fresh, so the rebuild has not run); keep the
   DataChannel stacks closed (datachannelxt #8), and neither close
   `enet-selftest` nor press its Re-run while a paste run holds ENet (enetxt #4;
   runbook row 48).
4. **What only a person can close:** D-04's wording and the owner calls; the box2dxt
   scenery and feel pass; holde-em's Phase 5 review and soak; the Model C Phase 4 exit
   on each OS.
