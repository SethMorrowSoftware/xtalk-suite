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
   `tools/check-livecodescript.py` (ASCII quotes only; `k`/`p`/`s`/`t`
   prefixes; literal constants before first use; declarations at handler top;
   `unsafe` around foreign calls). A `.lcb`/`.livecodescript` change is not
   "done" until that gate passes; a shim change is not "done" until the
   member's smoke test passes under ASan/UBSan; a native-library change is not
   "done" until the member's committed `src/code/<arch>-<platform>/` binary is
   refreshed in the same change.
6. **The honesty convention** — "verified statically; needs an OXT pass"
   (Tor: "+ live-Tor pass") for anything not observed on a real engine.

## The unified self-test is GENERATED

`tests/suite-selftest.livecodescript` is the one script a maintainer pastes into
an OXT stack to exercise the whole suite, and it is **built, not written**:

```sh
python3 tools/build-suite-selftest.py            # rebuild after touching any harness
python3 tools/build-suite-selftest.py --check    # in the gate set
python3 tools/check-suite-selftest.py            # the checks a compiler would make
```

It is assembled from `tests/suite-selftest.core.livecodescript` (hand-maintained:
the UI, the probe, the runner, and the cross-member sections) plus **every
member's own deep self-test**, folded in with each one's names prefixed. Edit the
member harness, not the generated file.

Three things about it are worth knowing before you touch it:

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
have drifted: **sodiumxt's copy did not know `switch`/`end switch`**, so it read
`end switch` as closing a HANDLER, reported two phantom problems in enetxt's and
datachannelxt's event dispatchers, and would have hidden any real imbalance
inside them. The other five copies already handled it, by two different
implementations. Only sodiumxt's was changed; the drift itself is the standing
cost of copy-per-member and is worth remembering the next time one of these
checkers is edited - a fix applied to one copy is not applied to the suite.

It stayed invisible because of how the two gate layers overlap. Each member's
own checker reads that member's `src/`, `examples/` AND `tests/`, so enetxt's
switch statements were always checked - by enetxt's checker, which handles them.
Separately, the repo-root `tests/` directory is run through EVERY member's
checker in turn. Until now that directory held only the suite harness, which had
no `switch` in it, so sodiumxt's gap was never reached. Folding enetxt's and
datachannelxt's switch-based event dispatchers into that file is what finally put
a `switch` in front of the one checker that could not parse it.

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
  runs). `native-<member>.yml` runs that member's full 5-platform native matrix
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
