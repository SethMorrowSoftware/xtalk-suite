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
  upload each built library as an **artifact**; CI does NOT commit binaries,
  because rule 5 makes refreshing a committed binary part of the human-authored
  change that motivated it. `release-binaries.yml` is the manual assembly step
  over the top: one `workflow_dispatch` builds every member for every platform
  (24 jobs), asserts each artifact, and publishes a single bundle, which
  `tools/install-release-binaries.py` verifies and lands locally so the commit
  is still a person's. Two things it cannot make: torrentxt's macOS dylib (it
  must be universal, self-contained, and codesigned/notarized — credentials CI
  does not hold), and any claim that an unexecuted artifact works, which is why
  the coinxt Windows lane's output is driven through the published vectors on a
  Windows runner before it is bundled. The per-member `.github/workflows/` files are kept
  for when a member is worked on in isolation, but **GitHub Actions runs only
  the root workflows in a monorepo**, so they do not fire here.

## Git / workflow

Develop on a per-task branch; commit there; open a **draft PR** if none exists.
Match the surrounding style of whichever member you are in — this codebase
comments the *why*, densely; mirror that. A member's own `CLAUDE.md` may add
stricter, member-specific rules; when it does, it wins for that member.
