# ArchiveXT implementation plan

**Status: phases 0-5 BUILT 2026-09-15, verified statically + executed
headlessly; needs an OXT pass + a live archive.org pass (phase 6). Phases
7+ are open.** Each phase records what it built and where the evidence is.
`docs/07-open-questions.md` is the item-level list; this page is the shape.

## The goal, restated

One library that lets an xTalk app do what three shipped archive.org web
apps do - the Grateful Dead Tape Finder, the LibriVox AudioBooks app,
Archive Film Club - and one demo stack that IS the three of them, plus a
generic family for any other mediatype. Pure script, no extension, built
to the suite's rules from the first line: the static gate, the honesty
convention, the carried blocks, an execution gate that runs the shipped
script headlessly, and a KAT that derives every harness constant.

## Phase 0 - research (done 2026-09-15)

Read the suite's rules and gates (root `CLAUDE.md`, the coinxt / nostrxt /
riptide members as the models for a pure-script member with an oracle), then
the three apps' code and tests. Findings that shaped the design:

- The three apps share ONE client shape (query builder, URL builder, JSON
  read, file-list rule) and disagree in the details; `docs/03` records the
  choices.
- Only the AudioBooks app had a sanitizer; a Lucene parse error is an
  HTTP-200 body with a top-level `error`, so an unguarded app shows a
  stack trace. That became a family-wide rule.
- archive.org is unreachable from the build sandbox (the egress proxy
  refuses the CONNECT), so the fixtures had to be synthetic, shaped from the
  apps' own mocks. Recorded in every STATUS block.

## Phase 1 - the pure layer (done)

`src/archivext.livecodescript`, `axVersion` to `axPlaylistTable`: encoders,
identifiers, years, durations, sizes, natural order, the query grammar and
sanitizer, the four families' tables, the URL builders, an owned JSON reader
(document handles, exact key lookup, RFC 8259 numbers, fields as lines), the
two response parsers, and the playlist engine (accept / group / rank /
derive / order, one kind per family). Written inside the family
interpreter's subset so that ALL of it executes headlessly: no `switch`, no
`delete`, no `div` / `mod`, no single-line `if`, no regex (the sanitizer is
restated over tokens; the oracle keeps the apps' regexes, and agreement is
the test).

## Phase 2 - the oracle, the fixtures, the KAT, the harness (done)

- `tools/archive_reference.py`: every rule a second time, in Python, from
  the apps' JavaScript and PHP; anchored at import to their published
  vectors.
- `tests/fixtures/*.json`: nine synthetic responses covering every kind and
  both error shapes.
- `tools/archive-kat.py`: derives the harness constants (hex for anything
  that carries a quote, a newline or a non-ASCII byte, an asserted rule);
  `--check` sweeps twice.
- `examples/archivext-tests.livecodescript`: `axSelfTest()`, 12 offline
  sections, every public handler named; `tools/check-selftest-vectors.py`
  re-derives every pinned constant by name.
- `tools/check-script-vectors.py`: five tiers driving the SHIPPED script
  through `tools/lcs-interp.py` (2920 checks on 2026-09-15);
  `tools/test-script-vectors.py` seeds seven defects and requires the gate
  to catch each. The seventh (a chapter stem that keeps `_vbr`) was NOT
  caught by the first version, because a fixture groups by `original` and
  never exercises the stem; direct name-rule vectors closed it the same day.
  A fixture-only gate cannot see a rule the fixture does not exercise.

## Phase 3 - the fetch layer (done, engine-unproven)

`axInit` to `axFetchItemSync`: `load URL ... with message "axUrlDone"`, one
handle per request, correlation by URL, a per-request watchdog
(`axDeadline`), a body cap, unload on every path, a user agent, the four-kind
callback contract, and three blocking conveniences. Reached by the harness
through refusal paths only. Registered with the suite's timer-stack-pin gate
(`axSetCallback` is a registrar), so a callback that touches controls
without pinning the defaultStack fails the build.

## Phase 4 - the demo (done, engine-unproven)

`examples/archivext-demo.livecodescript`: three panels (explore: family,
presets, filters, years, query; results: table, paging, random, sort; item:
title, metadata, playlist, open page / copy URL / play / stop), the UI kit
v2 and the boot self-check carried verbatim, the library and the harness
embedded between sentinels, a player object created on demand with `launch
URL` as the fallback, 1180x630 inside the family's 720p budget, registered in
the launcher.

## Phase 5 - suite wiring (done)

Every registry that walks a member or a demo: `build-all.sh`'s member loop
and KAT block, `build-suite-selftest.py` (Member `ax1` + the script layer),
`check-suite-selftest.py`, `check-suite-coverage.py` (99/99 public handlers,
zero exemptions), the core harness's probe and run block,
`sync-demo-embeds.py`, the UI-kit / self-check / control-list gates, the
launcher registry, `check-cross-library-names.py`, `check-handler-calls.py`,
`check-timer-stack-pin.py`, `check-checker-drift.py` (the interpreter copy
joined the byte-identical set), `test-checker.py`, `build-preflight.py` (an
`ArchiveXT script layer` probe), and the suite docs.

## Phase 6 - the first engine pass and the first live pass (OPEN)

The runbook row and `docs/07-open-questions.md` items 1-10: the fold
compiles and reports; the demo boots; the search, metadata and download
endpoints answer in the fixture shapes; a real file list through every
kind; the scrape API; TLS in both directions; a player streaming a download
URL. Each result flips the STATUS blocks in place, dated.

## Phase 7+ - open

More families with curated tables (texts, images, software), a download-
to-disk helper with progress, a small result cache, a thirty-line minimal
demo. None starts before phase 6 has an engine record: building more on an
unproven fetch layer is how a member accumulates debt it cannot see.
