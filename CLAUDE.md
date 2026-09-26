# CLAUDE.md - xTalk Suite

This guides Claude Code at the suite root, and it is thin on purpose. **Each member owns its own
`CLAUDE.md`, and inside that member it wins: read it first.** This file holds only what is true
across members and the root machinery that keeps them one system. Engine BEHAVIOUR is not here: it
lives in `docs/OXT-ENGINE-NOTES.md`, numbered and cited by number ("engine note 5.5").

## What this repo is

Extensions and apps for OpenXTalk (OXT) and the xTalk family, each a thin binding over a proven
native library (or pure LiveCodeScript), developed together so they release and interoperate as a
suite. Eleven members, all in `tools/member-registry.py` (the one table the split tooling reads;
the other registries name members by hand, `docs/MEMBER-REPO-SPLIT.md` section 8):

- **Native extensions:** sodiumxt (libsodium), torrentxt (libtorrent), enetxt (ENet),
  datachannelxt (libdatachannel), box2dxt (Box2D v3 plus the pure-script b2k game Kit; the family
  ancestor) and coinxt (trezor-crypto + libsecp256k1).
- **Pure-LiveCodeScript extensions:** onionxt (over a local tor daemon) and nostrxt (over coinxt
  and sodiumxt).
- **Apps**, member-shaped so the same gates walk them: riptide (Riptide Social, implementing
  `docs/RIPTIDE-SOCIAL-SPEC.md`), nocloud (No Cloud Quick Share) and holde-em (serverless Hold'em,
  whose game and harness are ONE file).

This monorepo is the development repository and the source of truth. Since 2026-09-22 every member
is PUBLISHED from here into its own repository (see Publishing); the pre-suite repositories
(SodiumXT, OnionXT, dataChannelXT, and TorrentXT, which once vendored enetxt/ and datachannelxt/)
are now those destinations. archivext joined 2026-09-15 and left 2026-09-21 for its own repository
(last state here: commit 99806d2); its engine records stay in engine notes 2.7, 3.4, 5.7-5.10, 6.9.

## Layout

```
README.md                  the front door: the family, start-here, the honest status matrix
LICENSE                    MIT + the attribution of every bundled third-party library
start-here.livecodescript  the runnable front door: paste into a stack script SAVED in the repo root
                           and reopen (never File > Open Stack on it: engine note 5.5); launches every
                           demo and harness in place; held true by tools/check-launcher-registry.py
docs/                      cross-member docs, indexed by docs/README.md
tests/                     suite-selftest.core.livecodescript (hand-written), the GENERATED paste
                           and preflight, suite-closing-pass (the two-machine legs A-F),
                           cross-member-test.py (native invariants over the built shims)
tools/                     suite gates, their fixture tests, generators, carried-block masters,
                           member-registry.py, publish-members.py
.github/workflows/         suite-gates, native-<member>, release-binaries, publish-members
<member>/                  each self-contained: CMakeLists.txt or build.sh, src/, tests/, docs/,
                           tools/run-gates.sh (its gate list), src/code/<arch>-<platform>/ + MANIFEST
```

## The rules that hold across every member (the numbers are cited; keep them)

1. **Never call an xTalk handler from a foreign thread.** Events are poll-drained on a timer; no
   callback runs script.
2. **The exception firewall.** Every `extern "C"` body is
   `try { ... } catch (...) { set_error; return err; }`; nothing crosses the FFI.
3. **Payload avoids the FFI into script** where the design allows; only small status records and
   events cross.
4. **Generation-tagged integer handles**, validated before use: a stale handle is a harmless no-op.
5. **The static gate is law for script.** Every member carries `tools/check-livecodescript.py`:
   ASCII only; the `k`/`p`/`s`/`t` token-shadow trap; literal constants before first use (both
   dialects); declarations at handler top in `.lcb` (measured, NOT enforced for `.livecodescript`,
   where a mid-handler `local` is legal); `unsafe` around foreign calls; block balance including
   `switch`; the zero-arg statement call and throw-in-catch refusals; the per-dialect antipattern
   sets. The copies are byte-identical (`tools/check-checker-drift.py`) and `tools/test-checker.py`
   fixture-tests every rule in every copy. **Done means:** a script change passes that gate; a shim
   change passes the member's smoke test under ASan/UBSan; a native-library change refreshes the
   committed `src/code/<arch>-<platform>/` binary in the same change.
6. **The honesty convention.** Anything not observed on a real engine is labelled "verified
   statically; needs an OXT pass" (Tor: "+ live-Tor pass"). A label is removed only for what a run
   exercised. It cuts both ways: understating what a dated record proves is a failure too.

**Where to look:** `docs/OXT-ENGINE-NOTES.md` (what the engine does; stable numbers, each entry
OBSERVED, INFERRED, DOCUMENTED or UNEVIDENCED; read it before an engine session, add to it after);
`docs/OXT-PASS-RUNBOOK.md` (how to run an engine session and what is still owed on one);
`docs/WORK-PLAN.md` (ALL open work: member docs keep a one-line status and honesty labels, not
to-do lists); `docs/OPEN-DECISIONS.md` (owner decisions D-01 onward); `docs/MEMBER-REPO-SPLIT.md`
(publishing, porting back, removing a member); `docs/README.md` (the index of the rest).

## Carried blocks: one master, verbatim copies, a drift gate

Code carried byte-for-byte into many files keeps each demo and harness ONE paste-and-run file. For
every family: **edit the master, then regenerate or re-carry; never patch a copy.**

| Block | Master | Held by |
|---|---|---|
| UI kit v2, the card look | `tools/ui-kit.livecodescript` | `tools/check-ui-kit-drift.py` |
| Demo boot self-check | `tools/demo-selfcheck.livecodescript` | `check-demo-selfcheck-drift.py`, `check-demo-control-lists.py` |
| Harness scaffold | `tools/harness-scaffold.livecodescript` | `tools/check-harness-scaffold-drift.py` |
| Script libraries in demos | `<member>/src/*.livecodescript` | `sync-demo-embeds.py --check` (after `test-demo-embeds.py --mutate`) |
| Checker, docs-style gate, interpreter, templates | every carrier's copy | `tools/check-checker-drift.py` (TEMPLATE_SETS: onionxt, coinxt) |

box2dxt carries the b2k Kit into its harness and games under its own `tools/sync-embedded-kit.py`;
the suite paste is the generated case below. The family interpreter, `coinxt/tools/lcs-interp.py`
(twinned in nostrxt), and riptide's stack runner built on it let execution gates in coinxt, nostrxt,
riptide, nocloud and holde-em RUN the shipped script headlessly (`check-script-vectors.py` and the
boot runners). They settle logic, not parser behaviour, so they upgrade no honesty label.

- **UI kit.** The gate also refuses any window-building stack that neither adopts nor carries a
  written exemption (box2dxt's games and holde-em's table, permanent by D-18). The four member
  harness windows match the kit by value, on D-18's reasoning; the suite paste adopts the kit and
  the boot self-check (D-23). Stacks converted 2026-08-14 say "UI unified 2026-08-14; needs an OXT
  re-pass".
- **Boot self-check.** The block owns counters, PASS/FAIL/SKIP lines, the completeness trailer and
  the delayed-write probe; a demo owns its assertions, one run handler and one line in `openStack`
  or `preOpenStack`, and the gate refuses one that never calls `scBegin`. `scMissing` walks EVERY
  card with a qualified `there is` (engine note 5.6) and asks about images: the types a demo builds
  are not the types the kit builds. Control lists are DERIVED from each source. Fail LOUD, pass
  QUIET: `scFinish` paints the status line only on failure.
- **Harness scaffold** (enetxt, datachannelxt, torrentxt, coinxt selftests and the suite core,
  which keeps it for its report and builds its window with the kit instead of `stBuild`).
  Every render appends `RUN NOT FINISHED` until `stReportDone`, and Copy results carries it: with a
  deadline of about 40 s, "it looks finished" is the normal state of a run that is not.
- **Demo embeds.** The embed goes ABOVE the demo's own code (below its `script "..."` line and
  header prose), providers in dependency order, because declarations resolve by lexical position
  (engine note 1.2); a provider's own `script "..."` line is stripped (1.1). Collisions are REFUSED
  and named, never merged. Registry-driven; `NOT_EMBEDDED` records torrent-quickshare (its live
  `socket*` bodies). **The banner must never say "GENERATED - do not edit"**: the kit and scaffold
  gates skip any file with that phrase in its first 4000 characters.

**Engine socket names (2026-08-24).** `socketError`, `socketClosed` and `socketTimeout` are the
engine's, so one script cannot define them twice. onionxt and nostrxt's relay layer keep the logic
in named functions (`oxSocketError`, `nxrSocketError`, ...) that answer "was this socket mine, and
did I handle it?"; `on socket*` only dispatches. An embedder drops the wrappers via `DROP_HANDLERS`,
keyed by the (app, library) PAIR, never by library (a carrier with no socket handlers of its own
would hang silently), and calls the named function where it would `pass`. Both halves are asserted,
and "false for a socket that is not ours" is pinned offline in both harnesses.

**One name, one library (2026-08-23).** Co-loaded or co-embedded libraries share one namespace.
`tools/check-cross-library-names.py` holds the library corpus disjoint (handlers public and
private, column-0 declarations, the `pass` discipline on engine socket messages, a public-prefix
ratchet), proven by `tools/test-cross-library-names.py` mutating real corpus files in place.

## The gates

**The gate list is the script:** the `== suite:` block of `tools/build-all.sh` plus each member's
`tools/run-gates.sh` (the member owns its list; the walker delegates). `bash tools/build-all.sh
--gates` is the compiler-free set that `suite-gates.yml` runs on every push. Never glob
`tools/*.py` for it: that directory also holds fixture tests, generators, a data module and the
publisher. Write no gate counts in prose; the gates print them. A fixture test runs before its gate.
The gates whose reason is not in their name:

- `check-doc-status-consistency.py` refuses a BLANKET negative (a whole page or member said never
  to have met an engine) unless a dated record that closed it FOLLOWS in the same paragraph.
  Direction is the whole rule; scoped negatives ("the receive leg has not run") are invisible to it.
- `check-lcb-call-types.py`: the script-to-`.lcb` boundary is TYPED and no public `.lcb` handler
  has an optional parameter, so an empty value into `in pX as Integer` is a hard runtime error
  (engine note 6.4). Check 4: event names and handler names share one namespace (6.7).
- `check-timer-stack-pin.py`: an unqualified control in a delayed handler resolves against THE
  DEFAULTSTACK (engine note 5.3). Entries are every delivery class: `send ... in`, engine socket and
  URL callbacks, and library-dispatched callbacks (`oxSetStreamCallback`, `nxrSetCallback`,
  `oxhRoute`, ...); reachability is a same-file closure plus the kit, stopping at a pin. Pin at the
  timer entry point; the kit half lives in the ui-kit master.
- `check-lcb-signatures.py`: every foreign bind against its C definition (arity, return and
  parameter types); box2dxt runs its own, which adds the name bijection.
- `check-binary-freshness.py`: rule 5's automated half (a shim export change without a rebuilt
  committed library fails). `check-handler-calls.py`: every cross-member call resolves.
  `check-shim-scaffold-drift.py`: one handle table in three C++ shims (rule 4).
  `check-stack-size.py`: every window fits 1200 x 640 (720p); holde-em's controls are held by
  `holde-em/tools/check-table-layout.py`. `check-doc-anchors.py`: a suite-doc citation written
  `path` ("anchor") must resolve to one file containing the anchor verbatim.
- `build-preflight.py --check`: `tests/preflight.livecodescript` is GENERATED from the shims' C ABI
  macros, cross-checked against each `.lcb` literal and each guard's throw text (`ABI `); it reads
  the mac ABI from the one `universal-mac` row of `sodiumxt/CLAUDE.md`'s table.
- The root scripts (`start-here`, `tests/`, `tools/*.livecodescript`) go through one checker copy,
  bar `tools/harness-scaffold.livecodescript` (a template with holes; the exemption asserts the file
  exists). `tests/cross-member-test.py` settles the marquee cross-member claims natively over the
  built sodiumxt and torrentxt shims (full build, and `suite-gates.yml`'s `cross-member` job).

## The generated suite self-test

`tests/suite-selftest.livecodescript` is the one script a maintainer pastes into an OXT stack to
exercise the whole suite. It is **built, never hand-edited**:

```sh
python3 tools/build-suite-selftest.py          # rebuild after touching a harness, the core or a layer
python3 tools/build-suite-selftest.py --check  # in the gates: the committed copy matches the sources
python3 tools/check-suite-selftest.py          # the checks a compiler would make
python3 tools/check-suite-coverage.py          # does it reach the suite? (prints the ratio)
python3 tools/sync-demo-embeds.py              # the OTHER carrier of the script layers
```

It is `tests/suite-selftest.core.livecodescript` (UI, probe, runner, cross-member sections) plus ten
member harnesses with every name PREFIXED (sodiumxt `sx1`, onionxt `ox1`, coinxt `cx1`, torrentxt
`bt1`, enetxt `en1`, datachannelxt `dc1`, box2dxt `b21`, riptide `rs1`, holde-em `he1`, nostrxt
`nx1`), plus five pure-script libraries embedded VERBATIM and unprefixed so the tests call them by
their real names: coinxt, onionxt, the b2k Kit, riptide and the nostrxt core. (The embeds exist
because a harness once ran against a stale in-memory library and reported failures already fixed.)

- **The board (D-23).** The paste wears the demos' look: one row per `tools/member-registry.py`
  member plus a cross-member row (a pill, its counts, a scoped **Run**, **Show**), a results filter
  and the boot self-check. nocloud's row is a caption: the generator's `NO_HARNESS`, and it refuses
  a registry member with neither a harness nor such a reason. A row's Run is a subsequence of Run
  all, never a reordering, and every block tallies into its row. The kit builds the scaffold's four report controls under their own
  names, so the report plumbing is the engine-run code. Held by `check-suite-selftest.py` checks
  6b, 7 (hardened), 10b, 13b, 14, 15, 16a and 17 (fixtures `test-suite-selftest.py` and
  `test-build-suite-selftest.py`), the drift fixtures `test-ui-kit-drift.py` and
  `test-harness-scaffold-drift.py`, and `check-suite-ui-boot.py` (fixture `test-suite-ui-boot.py`),
  which drives the board's logic through the family interpreter in an all-absent profile and
  upgrades no label. Run all has run on an engine (2026-09-24 on Windows: the build, the boot
  self-check, the rows adding up to the totals, Copy results; 2026-09-25 on Linux, the same, and
  by the maintainer's account a SECOND Run all in one launch, riptide's session sections green;
  2026-09-25 on Windows again; runbook section 8); a row's Run, Show and the filters are verified
  statically; needs an OXT pass (runbook row 48).
- **A script-layer edit is done only when every carrier is regenerated** (`build-suite-selftest.py`
  AND `sync-demo-embeds.py`). The carrier sets overlap without either containing the other: the
  b2k Kit is in the paste and no demo; `onionxt/src/onion-httpd.livecodescript` is in demos only.
- **Namespacing is total**, scaffolding and counters included: the "shared" scaffolding differs
  (`stRepeatByte` has three implementations that disagree at `pCount = 0`), and a folded harness
  must behave exactly as standalone. The core merges each member's counters; `stMergeCounted` and
  `stMergeReturned` both validate, so a bad counter is a reported failure.
- **Declared is not in scope.** Every folded declaration is HOISTED above the first handler through
  a second marker in the core: a name resolves by lexical position (engine note 1.2) and an
  undeclared one evaluates to its own spelling (2.1), so a fold that left 106 declarations below
  their first reader died on `add "cx1sPassed" to sPassed`. `split_handlers` collects every
  top-level non-handler line; `assert_no_declaration_dropped` guards only a column-0 declaration
  written inside a handler body. Since D-23 the core's own carried blocks sit below its first
  handler, so the generator hoists their column-0 declarations too and refuses a hand-written late
  or continued one. The paste's copies of the three blocks are therefore not byte copies: the
  drift gates skip it by exact path (`GENERATED_CARRIERS`), and `--check` pins it to the core.
- **The `GENERATED EMBED` sentinels are a contract** with `check-suite-coverage.py`, which CUTS
  those spans before scanning (a library naming its own API is not a test; uncut, it once read a
  fake 309/309) and FAILS on a harness with none. The generator refuses any name defined twice.
- **Not folded, on purpose:** the enetxt and datachannelxt async loopbacks (the core drives its own
  on both transports; two state machines would race). torrentxt's `btStartSession` is rewritten to
  reuse the core's session (one per process), and riptide's `rstAcquireSession` to read the core's
  handle on every call and never start one (a cached handle went stale on every run after the
  first; check 6b). `en1stCleanup`/`dc1stCleanup` call
  `enDeinitialize`/`dcCleanup` and must stay unreachable; `check-suite-selftest.py` enforces it.
- **box2dxt's fold**, each mechanism asserting its inputs exist: `strip_spans` cuts the harness's
  carried Kit (embedded once, from `src/`); `drop_extra` drops `openCard`, `closeCard` and
  `buildStUI`; `keep_names` keeps `b2kFell`, `b2kSensorEnter` and `b2kContact` unprefixed, because
  the Kit dispatches them by literal name.
- **holde-em's fold** carries the whole application, prefixed. `drop_extra` drops nine chrome
  handlers (`preOpenStack` would resize the suite window). An `@PREFIX@` rewrite widens its
  pending-message sweep from `begins with "heNet"` to the member prefix: a fragment of a name is not
  a name, and nothing renames it. Check 7d's reachability closure from `he1heSelfTest` refuses
  `heNetStart` (a second libtorrent session), `heRunSelftest`, `heBuildTable`, `heReportShow` and
  `heKitTryInit`; reachable `heNetStop` only ever sees an empty `gGame["session"]` (only
  `heNetStart` writes it). The closure creates and deletes no control, never resizes or retitles,
  never touches `clipboardData`; check 7e refuses the dropped chrome coming back.
- **One line can take the whole paste:** the fold's first engine pass (2026-08-09) died on
  `dcCleanup()` in statement position (engine note 3.3); every checker copy refuses the form.
- `suite-gates.yml` uploads a `suite-selftest` artifact (paste, coverage report, runbook) without
  regenerating it.

## Coverage

`tools/check-suite-coverage.py` is a ratchet: every public handler of every member must be named in
the scanned view of the paste (comments stripped, embedded spans cut, string literals blanked except
on `do`/`dispatch`/`send`/`stThrows` lines). It fails on a new unexercised handler AND on a stale
excuse. The only exemptions are onionxt's engine socket callbacks and watchdogs, each with a
written reason (its three live-daemon ones retired 2026-09-24 to harness calls on their refusal
paths). It counts "called by name", not "tested well"; depth is each member's
vector gates. Run it for the ratio; never copy the ratio into prose. Two advisory rows sit outside
the ratchet, each with an armed floor (a new gap, a promoted or a stale entry fails):

- **box2dxt's raw `b2*` binding.** By the gate's convention (comments stripped, literals blanked)
  131 of 376 handlers are named by a script and 245 are not; a raw token count gives 132/244. Both
  are real; the convention decides. (An older "374 foreign declarations" was a `grep -c` that also
  counted a line of header prose at `box2dxt.lcb:16`.) The C side is measured by gcov, not grep:
  `box2dxt/tests/smoke_test.c` entered all 370 LC_API exports on 2026-08-23 (about 92% line
  coverage), in build-all's Release walk and the ASan/UBSan job of `native-box2dxt.yml`. A
  declaration is not a call: grep once counted six `extern`-declared, never-called exports.
- **holde-em's `he*` surface.** The one file is split at its selftest boundary, re-found each run.
  Reachability KEEPS literals (`heRunSection "x"` reaches `do pName`); coverage BLANKS them, which
  separates a wired section from a name in a test label. Also enforced: a unique boundary,
  test-shaped names below it, parseable blocks, harness reachability bar three interactive handlers,
  and a denominator floor (an unterminated `/*` once swallowed 2,200 lines into a false green).

The coinxt constant gate taught the rule the ratchet rests on: `check-selftest-vectors.py` printed
"66 harness constants re-derived", counting what it PARSED, not what it checked; it now fails on any
`k*` constant neither re-derived nor listed with a reason. A gate that overstates its coverage is
worse than no gate, because it answers the question nobody asks twice.

## Lessons (tools cite these as "root CLAUDE.md")

- **Shipped is not run**: an unexecuted line is not evidence in either direction, precedent included.
- **Exercise a gate the way the build will**, not the way its docstring describes; a guard tested on
  a hand-built input the pipeline never produces is "component verified, system claimed".
- **Fixture before gate**: a blind gate still prints OK. **Description rots; checks do not.**
- **Hand-copied numbers go stale silently** (ABI numbers, coverage ratios, counts, constants):
  generate them, or run the gate that prints them.
- **A gate is bounded by the question it asks**; the tempting question describes the bug already
  found (the timer-stack-pin gate was widened twice for that). **Look where the forbidden thing
  would actually be**: "is this string in the file" rarely is.
- **Comments versus literals** silently changed a scanner's answer three times: cut comments with a
  string-state-aware scanner, and decide per gate whether a literal is code or a label.
- **A check that cannot use the thing it checks will pass whatever that thing is**: a dry run must
  EXERCISE credentials without spending them. **Understating is dishonest too**: "unproven" over a
  green dated record teaches readers to skip labels.

## Building, CI and release

- `tools/build-all.sh` builds the CMake members (sodiumxt, torrentxt, enetxt, datachannelxt,
  box2dxt) with `<MEMBER>_BUILD_TESTS=ON` and `ctest --no-tests=error`, runs coinxt's
  `native/build.sh asan` self-test and KATs, every member's `tools/run-gates.sh`, the suite gates
  and `tests/cross-member-test.py`. Iterate on a shim under gcc `-fsanitize=address,undefined`
  (clang's ASan runtime is not installed here); include native headers with `-isystem`.
- **Only ROOT workflows run in the monorepo.** `suite-gates.yml`: `build-all.sh --gates` on every
  push, plus the native cross-member job when a change touches it. `native-<member>.yml`: the
  member's matrix and sanitizer lanes, scoped by `paths:`; artifacts only, it NEVER commits a
  binary. Member `.github/workflows/` are GENERATED from these and run only in published repos.
- **`release-binaries.yml`** is a manual dispatch; pressing Run is the human decision rule 5
  requires. It builds all six native members on every platform, installs each library through
  `tools/install-release-binaries.py` (name, object format, architecture and exports checked; a
  thin Mach-O or a fat one missing a slice refused), refreshes manifests, runs the gates and
  commits per `commit_mode` (`branch`, `pr`, `none`). The commit stage waits on the WHOLE matrix:
  one red lane discards every artifact.
- **macOS:** `macos-15` runners are arm64-only, so a plain build emits a thin dylib. sodiumxt,
  coinxt, enetxt and box2dxt build universal in one pass; torrentxt and datachannelxt use a
  two-slice lipo job. arm64 is tested natively, x86_64 under Rosetta. Unsigned, not notarized
  (accepted 2026-08-23).
- **History.** Run 12 (2026-08-27) was the first dispatch to reach its commit stage; runs 5, 10 and
  11 died on a missing Perl module, 70 leaked ENet symbols in enetxt's mac dylib, and a commit
  allowlist `[a-z]+xt` that could not match box2dxt. Every native member's CURRENT binaries come
  from the 2026-09-12 dispatch (run 34657390798 from 0f17ab5, commit 421bab3). Their
  `x86_64-win32` builds first met an engine on 2026-09-24: the D-23 suite paste loaded all six
  and ran every member's sections (runbook section 8), on a 64-bit OXT by the maintainer's
  account (given 2026-09-26), and again on 2026-09-25 on that machine (the builds INFERRED the
  same: nothing newer is committed, and torrentxt's 997-byte refusals pass). Their
  `x86_64-linux` builds (sodiumxt's and box2dxt's still run 12's) first met an engine on the
  record on 2026-09-25: the same paste ran green (2672/0/10) on 64-bit Kubuntu 24.04 with "the
  latest builds" and "the latest" OXT, by the maintainer's account (torrentxt's 997-byte
  refusals agree: no committed Linux build before 421bab3 carries that cap; the OXT version and
  library versions not recorded). No engine has loaded the 32-bit (`x86-win32`, `x86-linux`) or
  mac builds yet. The Windows DLLs carry libsodium 1.0.22 (D-08) and libtorrent 2.1.1, not the
  versions pinned for the other platforms, and the 2026-09-24 runs exercised both by the
  maintainer's account, the 2026-09-25 Windows run by that inference (the report prints no
  library version).

## Member repositories and publishing

- **`tools/member-registry.py` is the one table** (name, repository, native lane, gate siblings
  closed by hand). `tools/sync-member-workflows.py` and `tools/sync-member-readmes.py` derive each
  member's workflows and the generated block of its README from it (both `--check`s are gates).
- **`tools/check-member-standalone.py`** keeps every member ready to stand alone: the kit present
  (README.md, LICENSE, CLAUDE.md, .gitignore, `tools/run-gates.sh`); no markdown link that climbs
  out of the member, and no tool that does except through `sibling()` (`XTALK_SIBLINGS`,
  `XTALK_SIBLING_<NAME>`; `XTALK_REQUIRE_SIBLINGS=1` turns a sibling-absent skip into a failure);
  no gate file its `run-gates.sh` never names; registry and tree in agreement.
- **A departing member takes its ROWS with it**: archivext's exit left thirteen suite gates red, and
  `docs/MEMBER-REPO-SPLIT.md` lists every registry. Only this repository can run the carried-block
  drift gates, embed freshness, cross-library names, cross-member call gates and coverage ratchet.
- **Publishing (D-22, 2026-09-22).** When `suite gates` goes green on `main`, `publish-members.yml`
  runs `tools/publish-members.py`: the first-parent commits that changed `<member>/` are replayed
  onto that member's repository, fast-forward only, each stamped `Suite-Commit: <sha>`, and that
  trailer is the publisher's ENTIRE state. Adoption is an explicit dispatch input; commits the
  suite did not write are refused until ported (`publish-members.py port <member>` stamps
  `Mirror-Commit:`) or accepted; a member whose native lane is red on its last change is held back.
  Generated member CI checks its gate siblings out of the suite at the newest `Suite-Commit:`
  (pulling them from the sibling repositories would have failed five of the eleven).
- **The first real adoption, 2026-09-23, was refused on all eleven**: the token could read
  everything and push nowhere, and the plan run looked healthy because reading a public repository
  needs no token. `--check-push` now tests the credentials with a dry-run push that sends nothing,
  and a refusal names its cause (credentials, workflow files, branch protection, a moved
  repository). The same day, run 3 attempt 2 adopted and published all eleven (16:11 UTC). Re-run
  on an automatic run replays its empty inputs and never adopts; use the Run workflow form.
- The `git subtree split` procedure this replaced could never have run (it shares no history with
  the destination); `tools/test-publish-members.py` tests no-force-push where a race can happen,
  injecting one with a `git` shim on PATH.

## Docs and git

Member docs live in `<member>/docs/` and cite member-root-relative paths (true in the published
repository); member markdown never links out with `../`, so it names a suite doc in plain text or
by absolute URL. Suite docs live in `docs/`, indexed by `docs/README.md`. Dated records keep their
original path spellings.

Develop on a per-task branch, commit there, and open a draft PR if none exists. Match the
surrounding style: this codebase comments the WHY, densely. A member's `CLAUDE.md` may add stricter
rules; inside that member it wins.
