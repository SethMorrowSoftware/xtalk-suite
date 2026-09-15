# CLAUDE.md

This file guides Claude Code (claude.ai/code) when working in the ArchiveXT
member of the xtalk-suite monorepo (`archivext/`).

> **Read the docs first.** [docs/00-overview.md](docs/00-overview.md)
> (architecture and the two-layer split), [docs/01-archive-api-model.md](docs/01-archive-api-model.md)
> (what the site actually does, quirk by quirk),
> [docs/03-items-files-and-playlists.md](docs/03-items-files-and-playlists.md)
> (the playlist engine and every place the three source apps disagreed),
> [docs/04-fetch-layer.md](docs/04-fetch-layer.md) (the engine-only half and
> the open TLS question). [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md) is
> the phased HOW. This file is the operational as-built record and the
> hard-won-lesson list, in the same spirit as the sibling `CLAUDE.md` files;
> most lessons below are CARRIED from coinxt (the headless execution gate,
> the portability disciplines), nostrxt (the oracle-plus-KAT shape) and
> riptide (the no-throw library shape) so we do not pay for them twice.

House style: no em-dashes (hyphens, commas, colons, parentheses). ASCII only
in `.livecodescript`, even in comments and strings. Comment the *why*,
densely; match the surrounding style.

## What this is

**ArchiveXT** is an archive.org client layer for OpenXTalk (OXT) / the xTalk
family: the advanced search, metadata, download and image APIs, a Lucene
query grammar with a sanitizer, the preset catalogues of three shipped web
apps (the Grateful Dead Tape Finder, the LibriVox AudioBooks app, Archive
Film Club), and the rules that turn an item's file list into a playlist. It
is one pure-LiveCodeScript file with no native code and no third-party code,
and its network calls go through the engine's own Internet library.

```
app (xTalk)
   |- ax*  src/archivext.livecodescript (axVersion .. axPlaylistTable)   PURE COMPUTE
   |         encoders, identifiers, the query grammar + sanitizer, the four families'
   |         tables, URL builders, the owned JSON reader, the parsers, the playlist engine
   |         no I/O, no engine-only calls, no timers - EXECUTED headlessly on every build
   |- ax*  the same file, axInit .. axFetchItemSync                     FETCH, ENGINE ONLY
             load URL ... with message "axUrlDone"; handles; a watchdog; a body cap;
             onArchive pHandle, pKind, pValue, pTag
```

One file, not two, because nothing here defines an engine message another
library defines (the socket-handler split nostrxt needed does not apply:
`axUrlDone` is a name this library chose). The layer boundary is a comment
line and the harness's section split.

## How ArchiveXT differs from its siblings (read this before you assume)

1. **Unlike coinxt and nostrxt, it owns no cryptography and speaks to no
   protocol with a published vector set.** What it owns is RULES three apps
   wrote for the site's JSON, so the oracle is anchored to those apps' own
   tests, not to a standard. A rule the apps disagreed on is a rule ArchiveXT
   had to pick, and each pick is written down in `docs/03` and in the
   oracle's docstring.
2. **The fixtures are synthetic.** The site is unreachable from the sandbox,
   so `tests/fixtures/*.json` are shaped from the apps' mocks and the
   documented API. Every STATUS block says so. A green build proves the
   script and the oracle agree about those bytes; the live shape is the
   runbook's to confirm.
3. **The fetch layer is the ENGINE's Internet library, not sockets.** `load
   URL ... with message` has no engine record anywhere in this suite yet
   (nocloud and coin-wallet use the same calls and have not run them
   either), and libURL's https behaviour is the open question. The layer is
   kept thin for that reason.
4. **The whole pure layer runs headlessly**, which sets a writing rule: stay
   inside `tools/lcs-interp.py`'s subset. No `switch`, no `delete`, no `div`
   / `mod` / bitwise, no single-line `if`, no `format`, no `word` chunks, no
   regex. What that cost is small (`put char 1 to -2 of x into x` instead of
   `delete the last char of x`) and what it buys is 2920 executed checks per
   build - which, on 2026-09-15, met the engine at 357 of 359 (below).

## As-built record

- **2026-09-15 - the member lands.** Library (99 public + 52 private
  handlers), oracle, nine fixtures, KAT (48 pinned constants), harness (12
  sections, 361 assertions), five-tier execution gate (2920 checks) with a
  seven-defect mutation drive, doc-handlers gate, the three-apps-in-one demo
  (1180x630, kit v2, self-check, embedded library + harness, 46 derived
  controls), and the suite wiring (fold as `ax1`, script layer embedded,
  coverage 99/99 with zero exemptions, launcher row, preflight probe).
  STATUS everywhere: verified statically + executed headlessly; needs an OXT
  pass + a live archive.org pass. The interpreter gained one modelled form
  for this member (`offset` / `byteOffset` with the engine's third, skip,
  argument, answering relative to the skip), carried into all three copies
  and drift-gated.
- **2026-09-15 - first engine contact, the same day.** The user pasted the
  member and ran `axSelfTest` on a real OXT engine: **357 passed, 2 failed,
  0 skipped** (zero skips: the Internet library answered `libURLVersion`).
  The library COMPILED and every section ran, which retired the compile
  question this member's engine-free build could never answer. The two reds,
  both fixed that day: (1) `keys are case-sensitive` - the JSON reader
  indexed an object's children by key in an ARRAY, and the engine folds
  array-key case (`tA["A"]` reads `tA["a"]`; gotcha 15, engine notes 2.7),
  so the reader now scans its key list with `axStrEq` (`axJsonFindKey`);
  (2) `axCleanTitle: nothing left is Untitled` - a hand-written expectation
  that the oracle never covered (gotcha 16); the library was right. The
  re-run after the fixes, the suite-paste fold, the demo's window and the
  live archive.org legs are still owed (docs/07). Before this run the user
  met `Function: error in function handler` with the hint `axVersion` at
  the harness's first library call. Read against the engine source that
  evening (root engine notes 3.4), that trace means "no live handler in the
  message path" - the library was not in use, or its script was dead from a
  lazy parse failure; a fault inside `axVersion` would have read
  differently. The next run, with the library in the path, compiled and
  ran, which is the parse verdict; the conservative rewrites of every
  no-precedent form landed in the same commit window and are kept.

## Gotchas and lessons (each one cost a round)

1. **An xTalk string literal has NO escapes.** The first draft wrote the
   film club's licence clause as a `constant` with `\"` inside it, which is a
   backslash and a quote, not a quote. A constant cannot hold an expression
   either, so any value that carries a double quote is a FUNCTION built with
   `quote` (`axPublicDomainClause`), and the preset TABLES spell a quote as
   `#` and swap it on the way out (`replace "#" with quote in tT`).
2. **The interpreter's subset is the writing rule, and `delete` is outside
   it.** `delete char -1 of x` and `delete line 1 of x` are legal engine
   script that the family interpreter does not model; rewritten as `put char
   1 to -2 of x into x` and `put line 2 to -1 of x into x` (`axChompLine` is
   the shared spelling). Extending the interpreter instead is the right call
   only when the form is one many members write - which is why `byteOffset`
   with a skip WAS added (three copies, byte-identical, `check-checker-
   drift.py`) and `delete` was not.
3. **`tExt` is a token shadow.** The static gate's check 14 refuses a local
   whose name is a keyword with a `t`/`p`/`s`/`k` prefix (`text` here);
   `tExtn`. It found five of them in one sweep, which is the argument for
   running the gate before reading the code.
4. **Track number is per DISC on etree.** Ordering `audio-tracks` by track
   number first interleaved `d1t01, d2t01, d1t02 ...`; tracks now order by
   natural NAME only, which keeps the site's own order. Chapters and
   episodes, whose numbers run through the whole item, still order by track
   first. Documents order by rank digit then name, and documents / images /
   files do not group at all.
5. **A blanked separator is a merged tag.** `axSubjectTags("a|b")` gave
   `A b` because the pipe was blanked rather than split; the JavaScript
   split on `[;|]`. Found by the vector gate, fixed with `replace "|" with
   ";"` before the split.
6. **`is a number` is not the JSON grammar.** `axJsonParse("[01]")` was
   accepted because `01 is a number` is true in xTalk; `axJsonNumberOk`
   now checks RFC 8259 (no leading zero, no bare sign, no empty exponent).
   The vector gate's refusal tier found it.
7. **A harness constant that carries a quote, a newline or a non-ASCII byte
   is pinned as HEX and named `...Hex`.** Three preset expectations shipped
   with embedded quotes before the KAT asserted the rule; now the harness
   compares through `axtHex(...)` and the KAT refuses to emit a bare one.
8. **A tool that writes files can un-escape your escapes.** A `é` and a
   `\n` spelled inside an xTalk string (as text for the JSON reader to
   decode) came out of the file-writing tool as a real e-acute and a real
   newline. The ASCII gate caught the first; the second was a broken
   literal. Write those spellings through a script that emits the bytes
   you mean, and re-run the checker.
9. **A call result cannot be subscripted.** `axFamilyInfo("any")["scope"]`
   and `axPlaylist(...)["count"]` are not xTalk; put the array into a local
   first. Both the harness and the demo had one.
10. **A fixture-only gate cannot see a rule the fixture does not exercise.**
    The mutation drive's stem defect (`axFileStem` keeping `_vbr`) left every
    fixture check green, because the librivox fixture groups by `original`
    and never needs the stem. Direct name-rule vectors against the oracle
    closed it (`check-script-vectors.py`, `check_name_rules`). The general
    form: when a mutation is not caught, the answer is a vector, not a
    weaker mutation.
11. **`kAxVec*` is undeclared in the demo until the embed sync runs.** The
    demo's boot self-check reads the harness's pinned constants; before
    `python3 tools/sync-demo-embeds.py` fills the sentinels the checker
    reports them undeclared. Expected, once.
12. **The demo names its player through a variable and creates it on
    demand.** `player` is a control type the kit does not build and the
    control-list gate does not derive, so `kAdPlayerName` keeps it out of
    `kAdScControls`; `launch URL` is the fallback when `create player`
    throws.
13. **The sanitizer is restated over TOKENS, the oracle keeps the regexes.**
    The interpreter has no `matchText`, so the script's sanitizer walks
    words and parentheses by hand while the oracle ports the AudioBooks
    regexes verbatim. Their agreement over 38 vectors in both modes is the
    test; a new sanitizer rule is added on BOTH sides or the gate says so.
14. **The suite wiring is fifteen registries, and the list is worth keeping
    for the next member**: `build-all.sh` (member loop + KAT block),
    `build-suite-selftest.py` (Member + Layer), `check-suite-selftest.py`
    (PREFIXES + ENTRY_POINTS), `check-suite-coverage.py` (MEMBERS +
    REQUIRED_EMBEDS), the core harness (local + probe + run block),
    `sync-demo-embeds.py` (REGISTRY), `check-ui-kit-drift.py` and
    `check-demo-selfcheck-drift.py` (ADOPTERS), `check-demo-control-lists.py
    --write`, `start-here.livecodescript` (slRegistry),
    `check-cross-library-names.py` (SCRIPT_LIBS), `check-handler-calls.py`
    (PREFIXES + CALL_RE), `check-timer-stack-pin.py` (REGISTRAR),
    `check-checker-drift.py` (COPY_SETS) + `test-checker.py` (MEMBERS), and
    `build-preflight.py` (the script-layer probe). Miss one and a gate that
    walks a list it does not know about prints OK.
15. **An array is never an exact-string index (OBSERVED 2026-09-15).** The
    engine folds array-key CASE: `"A" is among the keys of tA` is true when
    the stored key is `a`, and `tA["A"]` reads that element. The reader's
    by-key child index answered the `a` node for `A`, and the first engine
    run's one library red was exactly that line. Keys live in a numbered
    list and are matched with `axStrEq`; root engine notes 2.7 carries the
    rule. The family interpreter models arrays as Python dicts, which do
    NOT fold, so the vector gate could not see it - a model gap recorded in
    `docs/REMAINING-WORK.md` rather than fixed here, because folding keys in
    the interpreter re-runs every member's execution gate at once.
16. **A hand-written harness expectation is outside every gate.** The KAT
    re-derives `kAxVec*` constants; the vector gate drives the LIBRARY
    against the oracle. A literal expectation typed into an `axtCheck` line
    is checked by nothing until an engine runs it - and the first engine run
    found one wrong (`axCleanTitle` of an underscored name is the name, not
    `Untitled`; the film club's prefix test compares against the name as
    written). When a harness line pins a value the oracle can derive, pin
    it through the KAT instead.

## Working rules for this member

- **Edit `src/archivext.livecodescript`, then re-carry.** Two carriers hold a
  verbatim copy: the demo (`python3 tools/sync-demo-embeds.py` from the
  repo root) and the suite paste (`python3 tools/build-suite-selftest.py`).
  Both `--check`s are in the gate set.
- **Edit a rule on both sides.** A change to a pure rule is a change to
  `tools/archive_reference.py` too, or the vector gate fails - which is the
  point. If the change moves a pinned answer, regenerate the harness
  constants (`python3 tools/archive-kat.py` prints them; paste between the
  KAT sentinels) and let `check-selftest-vectors.py --check` confirm.
- **A new public handler needs three things**: a row in
  `docs/05-api-reference.md` (`check-doc-handlers.py`), a call in the member
  harness (`check-suite-coverage.py`), and vectors in
  `check-script-vectors.py` if it is pure.
- **Run the member gates before pushing**, from the repo root:

```sh
python3 archivext/tools/check-livecodescript.py archivext/src archivext/examples
python3 archivext/tools/archive-kat.py --check
python3 archivext/tools/check-selftest-vectors.py --check
python3 archivext/tools/test-script-vectors.py     # slow: seven full gate runs
python3 archivext/tools/check-script-vectors.py --check
python3 archivext/tools/check-doc-handlers.py
python3 archivext/tools/check-docs-style.py
tools/build-all.sh --gates                          # the whole suite set
```

- **Honesty labels.** Everything in this member reads "verified statically;
  needs an OXT pass + a live archive.org pass". The first engine pass flips
  the fold and demo labels; the first live pass flips the API-model and
  fetch labels. Flip them in EVERY carrier (README, the STATUS blocks, the
  runbook row, the suite overview) in one change - the doc-status gate
  exists because nostrxt's pass reached five documents and not the other
  seven.
