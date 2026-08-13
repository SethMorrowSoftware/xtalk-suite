# CLAUDE.md — xTalk Suite

This file guides Claude Code (claude.ai/code) when working in the **suite**
(the monorepo root). It is intentionally thin: **each member owns its own
`CLAUDE.md`**, and that member file is the authority for its layer. When you
work inside `sodiumxt/`, `torrentxt/`, `enetxt/`, `datachannelxt/`, `onionxt/`,
or `coinxt/`, **read that member's `CLAUDE.md` first** — it carries the hard-won
lessons for that binding. This file records only what is true across all of
them and what the consolidation changed.

## What this repo is

The OpenXTalk library suite: six sibling extensions for OXT / the xTalk family,
each a thin binding over a proven native library (or, for OnionXT, pure
LiveCodeScript over a local Tor daemon), consolidated into one repository so
they release, version, and interoperate as a suite. This monorepo is the
**source of truth**; the former standalone repositories (SodiumXT, OnionXT,
dataChannelXT, and the TorrentXT repo that once vendored enetxt/ and
datachannelxt/ as subfolders) become mirrors. Development happens here.

```
openxtalk-libraries/
  README.md            the suite front door + the honest release matrix
  CLAUDE.md            this file
  LICENSE              MIT + third-party attributions for every bundled lib
  docs/                CROSS-CUTTING documents (span >1 member)
  tools/build-all.sh   walk every buildable member
  .github/workflows/   the CI that runs: suite-gates + a native matrix per
                       member (member .github dirs are inert here)
  sodiumxt/  torrentxt/  enetxt/  datachannelxt/  onionxt/  coinxt/
  riptide/             the capstone APP (not an extension): Riptide Social,
                       implementing docs/RIPTIDE-SOCIAL-SPEC.md phase by
                       phase in pure script; structured like a member so the
                       gate machinery walks it; has its own CLAUDE.md
  nocloud/             a SHIPPED APP (not an extension): No Cloud Quick Share,
                       one stack over torrentxt (+ optional sodiumxt/onionxt),
                       folded in from its standalone repo 2026-08-13 (that
                       repo becomes a mirror, like the other pre-suite repos);
                       member-shaped so the gates walk it; its checker copy
                       was replaced with the unified one in the fold commit;
                       has its own CLAUDE.md
```

Each member stays a **self-contained extension**: its own `CMakeLists.txt` /
`build.sh`, `src/`, `tests/`, `tools/`, `docs/`, and the bundled per-platform
native library under `src/code/<arch>-<platform>/`. Nothing about a member's
internal layout changed in the move — it was copied in verbatim from its
tracked files (via `git archive`, so no build artifacts came along).

## The rules that hold across every member

These are summarized in `README.md`; the operational point for editing is:

1. **Never call an xTalk handler from a foreign thread** — events poll-drain on
   a timer; no callback runs script.
2. **The exception firewall** — every `extern "C"` body is
   `try { … } catch (...) { set_error; return err; }`; nothing crosses the FFI.
3. **Payload avoids the FFI into script** where the design allows; only small
   status records and events cross.
4. **Generation-tagged integer handles**, validated before use — a stale handle
   is a harmless no-op.
5. **The static gate is law for script.** Every member carries
   `tools/check-livecodescript.py` (ASCII only; the `k`/`p`/`s`/`t`
   token-shadow trap; literal constants before first use, both dialects;
   declarations at handler top in `.lcb` - measured, NOT enforced for
   `.livecodescript`, where mid-handler `local` is legal and stands in
   engine-passed code; `unsafe` around foreign calls; block balance including
   `switch`; the zero-arg-statement-call and throw-in-catch refusals; and the
   per-dialect antipattern sets). The copies are UNIFIED and byte-identical:
   `tools/check-checker-drift.py` fails the build if any copy differs, and
   `tools/test-checker.py` fixture-tests every rule in every copy. A
   `.lcb`/`.livecodescript` change is not "done" until that gate passes; a
   shim change is not "done" until the member's smoke test passes under
   ASan/UBSan; a native-library change is not "done" until the member's
   committed `src/code/<arch>-<platform>/` binary is refreshed in the same
   change.
6. **The honesty convention** — "verified statically; needs an OXT pass"
   (Tor: "+ live-Tor pass") for anything not observed on a real engine.

**Demo UI is ONE carried kit (2026-08-13).** `tools/ui-kit.livecodescript` is
the master for the family demo look — the chrome, the semantic status line,
mono data areas, the honesty footer. Adopting demo stacks embed the block
verbatim between its marker lines (each demo stays a single paste-and-run
file), and `tools/check-ui-kit-drift.py`, in the gate set, holds every copy
byte-identical to the master and refuses unregistered adopters — the
checker-unification model applied to the UI. A look change edits the master
and re-carries; it is never patched inside an adopter.

## The unified self-test is GENERATED

`tests/suite-selftest.livecodescript` is the one script a maintainer pastes into
an OXT stack to exercise the whole suite, and it is **built, not written**:

```sh
python3 tools/build-suite-selftest.py            # rebuild after touching any harness
python3 tools/build-suite-selftest.py --check    # in the gate set
python3 tools/check-suite-selftest.py            # the checks a compiler would make
python3 tools/check-suite-coverage.py            # does it actually reach the suite?
```

It is assembled from `tests/suite-selftest.core.livecodescript` (hand-maintained:
the UI, the probe, the runner, and the cross-member sections) plus **every
member's own deep self-test** (seven since 2026-08-11: the six extensions plus
riptide's phase-1 harness), folded in with each one's names prefixed, plus —
since 2026-08-10 — **the pure-script LIBRARIES themselves**,
`coinxt/src/coinxt.livecodescript`, `onionxt/src/onionxt.livecodescript` and
(since 2026-08-11) `riptide/src/riptide.livecodescript`,
embedded VERBATIM (no prefixing: the tests must call them by their real names).
The embed exists because the old "two `start using` lines" setup step cost a
real engine pass: a fresh harness ran against a stale in-memory coinxt stack
and reported exactly the failures whose fix was already merged. One paste now
carries the code its tests test, and `--check` pins both to one tree — which
also means **a script-layer edit is not done until the harness is rebuilt**,
exactly like a member-harness edit. Edit the member file, not the generated one.

Four things about it are worth knowing before you touch it:

- **The embedded libraries sit between sentinel lines, and the coverage gate
  depends on them.** A library's body names nearly its whole own API
  (`cxMnemonicToSeed` calls `cxMnemonicNormalize`; the socket dispatchers name
  every callback), and none of those mentions is a test. So
  `check-suite-coverage.py` CUTS the `GENERATED EMBED` spans before it scans
  for calls — measured uncut, it reported a fake 309/309 with the 18
  live-daemon/engine-event exemptions silently absorbed — and it FAILS, rather
  than falling back, on a harness with no spans to cut. The sentinel format is
  a contract between the generator and that gate; change both together. The
  generator also refuses to write an assembly where any handler or
  script-level declaration is defined twice, because the embedded layers are
  unprefixed and a script-level duplicate would make two units silently share
  one variable.

- **The namespacing is TOTAL.** All five `.livecodescript` harnesses define
  `stAssert`, `stRun`, `stBuild` and `sTotal`, so every name a member file
  defines is prefixed - including its own scaffolding and its own counters. Not
  because deduplicating would be hard, but because the scaffolding is not
  actually identical (`stRepeatByte` has three implementations that disagree at
  `pCount = 0`) and because a folded harness must behave here exactly as it does
  standalone. The core reads each member's counters afterwards and merges them.
- **Two things are deliberately NOT folded in**, and both are checked: the ENet
  and DataChannel **async loopbacks** (the core already drives a real loopback on
  both transports, and two state machines in one process race for the event
  handlers), and TorrentXT's own `btStartSession` (one session per process, so
  the fold rewrites it to reuse the core's). `check-suite-selftest.py` fails if
  either regresses, and if `en1stCleanup`/`dc1stCleanup` ever become reachable -
  they call `enDeinitialize`/`dcCleanup`, which would pull the transport out from
  under the core's loopback.
- **A missing declaration is SILENT, which is why there is a checker.** OXT
  cannot compile a `.livecodescript` headlessly, and LiveCodeScript evaluates an
  undeclared name as the literal text of its own name - so a fold that dropped
  `constant kBip39Mnemonic` would not error, it would compare a digest against
  the string `"cx1kBip39Mnemonic"` and report a tidy FAIL that reads like a real
  library defect. That bug was real in the first version of the generator;
  `check-suite-selftest.py` is what found it, and it is mutation-tested.

Folding those harnesses in also surfaced a **latent bug in one copy of the static
gate**. The family keeps a copy of `check-livecodescript.py` per member, and they
had drifted: **sodiumxt's copy did not know `switch`/`end switch`**, so it read
`end switch` as closing a HANDLER, reported two phantom problems in enetxt's and
datachannelxt's event dispatchers, and would have hidden any real imbalance
inside them. The other five copies already handled it, by two different
implementations - measured later, the "drift" was in fact TWO independent
checkers (one lineage in sodiumxt/onionxt/coinxt/riptide, another in
torrentxt/enetxt/datachannelxt), each with real checks the other lacked. **The
copies are UNIFIED now (2026-08-12)**: one implementation carrying the union of
both lineages' checks, byte-identical in all seven members, with
`tools/check-checker-drift.py` failing the build on any divergence and
`tools/test-checker.py` fixture-testing every rule in every copy - so "a fix
applied to one copy is not applied to the suite" is no longer a state the tree
can quietly be in. The self-containment survives: each member still ships its
own copy; the gate just proves the copies are the same tool.

**The first engine pass of the folded harness found what no gate could
(2026-08-09), and it was one line: `dcCleanup()`.** A zero-argument call in
STATEMENT position must be written BARE - a statement starting with an
identifier is parsed as a COMMAND, so the parenthesised spelling hands it the
expression `()`, which is not an expression. A `.livecodescript` compiles as one
unit, so that single line took the whole 4400-line paste with it. What makes it
worth recording rather than just fixing is why it was invisible: the
ONE-argument spelling `dcFreePeer(sPeerA)` is correct (`(sPeerA)` IS an
expression), so the broken line is visually identical to the working one beside
it - `datachannel-loopback` had `dcStopPolling` and `dcCleanup()` on consecutive
lines; in EXPRESSION position (`dcCleanup() is 0`) the parens are REQUIRED, same
characters, opposite verdict; and LiveCode **Builder** allows `sPrepare()` as a
statement, which `sodium.lcb` and `coinxt.lcb` do ~90 times on engine-verified
paths, so "we do this everywhere" was true and irrelevant. All checker copies
refuse it, `.livecodescript` only - and the "each copy tested against the bug,
all three legal forms, and a `.lcb`" attestation this paragraph used to make is
no longer an attestation: those fixtures are COMMITTED in
`tools/test-checker.py` and run against every copy in the gate set, which is
what the shipped-is-not-run lesson below says an attestation must become.

**The second engine error was the generator's, and it is the more instructive
one: DECLARED is not IN SCOPE.** `add pPassed to sPassed` died with
`add: error in source expression`, from `stMergeCounted`. Nothing was wrong with
any member harness. Each one declares its locals above its own handlers, which
is the house pattern in all six - but the FOLD placed coinxt's section about a
thousand lines BELOW the core's `stRunMemberHarnesses`, and that is the handler
that reads `cx1sPassed` to merge the totals. **OXT resolves a script-level name
by lexical position**, a rule this repo already had written down for `constant`
and which turns out to hold for `local` too, so the read saw an undeclared name.
LiveCodeScript does not error on one: it evaluates it to the literal text of its
own name, so the engine tried `add "cx1sPassed" to sPassed`. The generator now
hoists every folded declaration above the first handler, through a second marker
in the core; **106 declarations were below it**, so the counters were merely the
first to do arithmetic on one.

Two things about the gates here are worth carrying. `check-suite-selftest.py`
already proved every folded name was DECLARED - that check passed throughout,
because declared and in-scope are different questions and only the first is
visible to a grep. And `stMergeCounted` did the `add` on trust while
`stMergeReturned`, ten lines above it, had validated its counts since the day it
was written, on the reasoning that a parse can fail but a script local cannot.
The asymmetry is the bug: an uncaught engine error takes the WHOLE run, so six
harnesses' worth of results were lost to one line that could not name the member
it came from. Both paths validate now, and a bad counter is a reported failure
that prints what it got.

**The meta-lesson is the expensive one: shipped is not run.** The suite harness
carried a comment asserting both spellings were fine, reasoning that
datachannelxt shipped the parenthesised form so the engine must accept it. But
datachannelxt's own harness had never been run on an engine, so the attestation
was circular - and the comment even said "this harness has run neither", which
should have been the tell. An unexecuted line is not evidence, in either
direction. The honesty convention already covers this; it just has to be applied
to the code we are citing as precedent, not only to the code we are writing.

**"Current" and "structurally sound" are not "complete", and only the first two had
a gate.** `--check` proves the pasteable file is what the sources produce;
`check-suite-selftest.py` proves the merge holds together. Neither one looks at
whether the harness *reaches* anything, so a member could ship a public handler,
never test it, and both stay green about a file that does not touch the new code.
That gap is invisible from the inside: the harness is ~4400 lines and runs ~580
checks, and nobody re-asks "is this thorough?" after a number that size. When it was
first measured, **31 public handlers had never been called** - including coinxt's
`cxHdDeriveChild` (the single CKD step the whole HD layer loops over) and both ABI-4
tweak exports, which are what make an xpub watch-only wallet agree with its xprv.
Thirteen were closed by adding checks to the member harnesses; the other eighteen are
all onionxt's and now carry a written per-handler reason in
`tools/check-suite-coverage.py` - eleven **engine socket callbacks** (the engine
supplies a socket id no harness can mint) and seven that need a **live tor daemon**.
The gate fails on a new unexercised handler AND on a stale excuse, so a renamed
handler cannot leave a permanent exemption behind it. It is a floor, not a ceiling:
"called by name" is not "tested well", and depth stays the member vector gates' job.

The same shape of hole was in **coinxt's own constant gate**, found while fixing this
one: `check-selftest-vectors.py` re-derived an explicit list and then printed
"66 harness constants re-derived" - a count of the constants it had PARSED, not the
ones it had CHECKED. Two constants added in this very change sailed through it. A gate
that overstates its coverage is worse than no gate, because it answers the question
nobody asks twice. It now fails on any `k*` constant that is neither re-derived nor
listed as an input with a reason, and reports the honest split.

It stayed invisible because of how the two gate layers overlapped. Each member's
own checker reads that member's tree, so enetxt's switch statements were always
checked - by enetxt's checker, which handled them. Separately, the repo-root
`tests/` directory used to run through EVERY member's checker in turn; it held
only the suite harness, which had no `switch` in it, so sodiumxt's gap was never
reached until the fold put enetxt's and datachannelxt's switch-based dispatchers
in front of the one checker that could not parse them. (Since the unification,
that seven-way cross-run is one run: the copies are byte-identical, the drift
gate proves it, and `build-all.sh` runs the root scripts through a single copy.)

## Docs: member vs. suite

- **Member docs** live in `<member>/docs/` and describe that one extension
  (its api-reference, architecture, building, getting-started).
- **Suite docs** live in the top-level `docs/` and span more than one member:
  the roadmap (`NEXT-EXTENSIONS-PLAN.md`), the Tor-transport integration
  (`ONIONXT-INTEGRATION-PLAN.md`), and the five-extension capstone design
  (`RIPTIDE-SOCIAL-SPEC.md`). See `docs/README.md`.

> **Cross-reference caveat (consolidation debt).** Members and suite docs were
> moved verbatim, so some internal path references still read as if each project
> were its own repo root (e.g. a doc citing `examples/foo` now lives under
> `<member>/examples/foo`, and a cross-member reference like "TorrentXT's
> `docs/…`" now means `torrentxt/docs/…`). This is known, harmless to the code,
> and a good first cleanup pass — do not treat such a path as a bug in the code
> it points at.

## Building & CI

- `tools/build-all.sh` configures, builds, and tests each member that has a
  `CMakeLists.txt` (sodiumxt, torrentxt, enetxt, datachannelxt — with each
  member's `<MEMBER>_BUILD_TESTS` enabled and `ctest --no-tests=error`, so "no
  tests registered" can never pass silently), runs coinxt's
  `native/build.sh asan` self-test and KAT harness, and runs every member's
  static gates (script checker, docs style, golden vectors, record registries,
  KATs, standalone freshness, and the MANIFEST.sha256 integrity checks).
  OnionXT is pure script — nothing to compile.
- Build under **gcc** with `-fsanitize=address,undefined` while iterating on any
  shim (clang's ASan runtime is not installed in this environment). Treat every
  native-library header as a **system header** (`-isystem`) so its warnings do
  not pollute the suite's `-Wall -Wextra`.
- CI lives at the repository root, in two layers. `suite-gates.yml` runs every
  member's compiler-free gates on every push (the set `build-all.sh --gates`
  runs), and then uploads a **`suite-selftest` artifact** - the pasteable harness,
  the coverage report, and the runbook - so the person doing an engine pass can
  download the file instead of cloning. It does NOT generate the harness there:
  `--check` already failed the build if the committed copy were stale, so the tree
  copy is the built copy, and generating it in CI would let the artifact and the
  repository drift with only the artifact current. `native-<member>.yml` runs that member's full 5-platform native matrix
  and its sanitizer lanes, scoped by `paths:` so only the touched member
  builds, on pull requests, pushes to `main`, and on demand. The native lanes
  upload each built library as an **artifact** and never commit one: they fire on
  every push, so a commit step there would land binaries nobody asked for on
  somebody else's change. `release-binaries.yml` is the manual assembly step over
  the top: one `workflow_dispatch` builds every member for every platform it can (20
  jobs: five members x four platforms), asserts each artifact, then installs each library into its member's
  `src/code/<platform-id>/`, refreshes the manifests, runs the whole gate set,
  and commits (`commit_mode`: `branch` / `pr` / `none`). That still satisfies
  rule 5, whose point is that a committed binary traces to a human decision - the
  decision is the person pressing "Run workflow". The verification is the same
  code either way, because the job runs `tools/install-release-binaries.py`
  rather than reimplementing it. It builds NO macOS lanes: `macos-15` runners are
  arm64-only, so they would emit a thin dylib into `universal-mac` and regress
  sodiumxt's genuine two-architecture binary into one that fails on every Intel
  Mac. macOS stays a manual `lipo` build (plus codesigning/notarization for
  torrentxt, which needs credentials CI does not hold), and the installer
  refuses a thin Mach-O. Nor does it claim an unexecuted artifact works, which
  is why the coinxt Windows lane's output is driven through the published
  vectors on a Windows runner before it is bundled. The per-member `.github/workflows/` files are kept
  for when a member is worked on in isolation, but **GitHub Actions runs only
  the root workflows in a monorepo**, so they do not fire here.

## Git / workflow

Develop on a per-task branch; commit there; open a **draft PR** if none exists.
Match the surrounding style of whichever member you are in — this codebase
comments the *why*, densely; mirror that. A member's own `CLAUDE.md` may add
stricter, member-specific rules; when it does, it wins for that member.
