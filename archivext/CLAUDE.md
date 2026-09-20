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
- **2026-09-15 - the re-run and the first LIVE contact, same evening.** The
  demo opened on the engine: boot self-check 11/11 GREEN (46 controls, the
  Internet library at 1.2.0), `axSelfTest` **363 passed, 0 failed, 0
  skipped** after the two fixes. Then the first live `load URL` to
  https://archive.org went out - the request reached the site over https
  and the callback delivered the answer through the `error` kind, so the
  load / correlation / callback / unload path is engine-observed - and the
  site answered **400 Bad Request** to the film club's video-scope search.
  The one thing that request did that a plain `load URL` does not was
  replace the Internet library's default headers with a custom User-Agent
  through `libURLSetCustomHTTPHeaders` (no precedent anywhere in this
  tree); that setter is REMOVED (gotcha 17), and the next run is the
  verdict. If a 400 survives it, the query itself is next: the message-box
  probes in `README.md` separate a header cause from an encoding cause in
  four lines.
- **2026-09-15, later - the Live probe.** The header removal changed nothing
  (a timeout instead of a 400), so the demo gained a Live probe button that
  logs three blocking requests with their response headers. Its first run:
  a LibriVox search through the library **200, numFound 101, first
  emma_1903_librivox** - the first live search that ever succeeded, and the
  live proof of the URL bytes and the parser; a metadata GET of a wrong
  identifier answering `{}` (the missing-item shape, live); and the film
  club's full video scope refused as `URL is currently loading` because the
  earlier timed-out search was still loading in libURL. Gotcha 18 records
  the scope change and the two fetch-layer rules that followed.
- **2026-09-15, later still - the first LIVE pass, three legs green.** The
  rebuilt demo (boot self-check 11/11 with the probe button among its 47
  controls; `axSelfTest` **363 / 0 / 0** again) ran the probe in its new
  order: (1) the LibriVox search **200, numFound 101, first
  emma_version_5_1002_librivox** (the first result differs from the earlier
  run's because the site's default order is not stable - a fact worth
  knowing before pinning any live identifier in a test); (2) that item's
  metadata **200, 196,716 bytes, `Transfer-Encoding: chunked`**, the body
  opening `{"alternate_locations":{"servers":[...` - a REAL item, whole,
  through the blocking `put URL` path; (3) the movies family's cheap scope
  **200, numFound 17,098,672, first dobba_graphics**, answering in the same
  second the request went out. The `mediatype:(...)` clause is the verdict
  gotcha 18 was waiting for. What that run did NOT do: the item body was
  read raw (`axGetSync`), so `axItemParse` and the playlist engine have not
  met a live file list; the async `axSearch` path has delivered only the
  `error` kind so far (the earlier 400 and timeout), never a `search`; and
  the two documented error shapes (a broken query inside an HTTP 200, a
  missing item's `{}`) were seen only by accident on a wrong identifier.
  The probe now has five legs for exactly those, and the demo's Search
  button in the Films family is the async leg.
- **2026-09-16 - the five-leg probe and the async leg, all green.** Boot
  11/11 again, then the probe: (1) the LibriVox search **200, numFound
  101**; (2) `axFetchItemSync emma_version_5_1002_librivox` PARSED - **412
  files, mediatype audio, server ia800904.us.archive.org, title Emma** -
  and `axPlaylist` over that live file list gave **58 audio-chapters**, the
  first `1 / 01_01 - Volume 1, Chapter 1 / 20:15 / VBR MP3 / 18.54 MB`
  with the stream URL `/download/emma_version_5_1002_librivox/emma_01_austen.mp3`
  - the item parser and the playlist engine have now met a real file list
  (item 7's LibriVox kind); (3) the movies scope **200, numFound
  17,105,370** (up 6,698 overnight - the count is live); (4) the broken
  query `collection:(librivoxaudio) AND`, sent unsanitized, came back
  **HTTP 200 with a Solr error** and `axSearchParse` quoted it: `Archive.org
  rejected the query: a token is at an unexpected position (group close
  token ")" at position 32)` - position 32 in a 30-character query, so the
  site wraps the query in its own parentheses before parsing (docs/01); (5)
  `axFetchItemSync no_such_item_archivext_probe` answered **HTTP 200 with
  `{}`** and the parser refused it as `the item could not be found on
  Archive.org (no metadata block)`. Then the demo's own Search button, the
  ASYNC path: four `axSearch` requests across three families delivered
  their `search` kind through `onArchive` - Films `(test)` **24 of 88,882**,
  etree `(rwat)` **0 of 0** (an empty page renders, not an error), etree
  `(grateful dead)` **10 of 29,267**, LibriVox `(alice)` **24 of 262**. The
  correlation-by-URL, the unload-on-handling and the callback contract are
  engine-observed on the SUCCESS path now, not only on the error path.
  Still owed after this run: the suite-paste fold, the async `item` kind
  (click a result), the scrape API, streaming (the Play button), and TLS's
  certificate direction.
- **2026-09-16 - "the player is still not working": streaming rebuilt,
  downloading added.** The report carried no log line, because a player
  object handed a URL it cannot open throws nothing and plays nothing
  (gotcha 19). Three changes, all UNPROVEN until the next run: Play hands
  the player the DATANODE URL (`axDirectUrl`, new: `https://<server><dir>/
  <name>` from the metadata's own fields, where `/download/` redirects to;
  every playlist entry now carries it as `direct`), asks the player six
  seconds later whether it opened the stream (`the duration` and `the
  currentTime` are 0 when it did not) and logs the platform, the URL, the
  format and the answer; when the answer is no it DOWNLOADS the file and
  plays it from disk. Downloading is a library feature now: `axDownload`
  writes straight to a file through `libURLDownloadToFile`, forwards
  `libURLSetStatusCallback`'s `loading,received,total` as a `progress`
  kind, re-arms its watchdog on every report (a STALL watchdog: a slow
  transfer that is still moving never times out), delivers `file` with the
  path, and `axDownloadSync` is the blocking form; the demo's Download
  button saves to Documents/ArchiveXT/<identifier>/ with progress in the
  status line and reuses a file already there at the promised size. Five
  public handlers joined (`axDirectUrl`, `axDownload`, `axDownloadSync`,
  `axUrlStatus`, `axDownloadDone`), every one named by the harness
  (104/104, zero exemptions); the timer-stack-pin gate learned
  `libURLSetStatusCallback` and `libURLDownloadToFile` as registrars, the
  same delivery class as `load URL ... with message`. Later the same day,
  ahead of the evening pass: the status hook moved OUT of `axInit` - it is
  global to libURL, so the library takes it on the first `axDownload` and
  gives it back in `axShutdown`, and the harness (and therefore the suite
  paste) never takes it at all; the probe grew to TEN legs so one click
  also answers the questions the docs still carry open - three deliberately
  bad certificates from badssl.com for the TLS direction 6.8 / 6.9 have
  waited on (a refusal is the good answer), the scrape API's body shape,
  and a blocking download through the `/download/` redirect; the boot
  self-check gained a line (every entry carries a stream URL and a datanode
  URL); and the runbook's 4.10 carries the pass in click order.

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
17. **Do not replace the Internet library's headers (INFERRED 2026-09-15).**
    `libURLSetCustomHTTPHeaders` replaces libURL's whole default header set
    for every later request, globally, and the first live request that used
    it for a User-Agent drew 400 Bad Request from archive.org. No other
    stack in this suite sets it; the plain `load URL` defaults are the
    proven path. Identify the client some other way if it ever matters
    (the `httpHeaders` property ADDS headers rather than replacing them).
    Marked INFERRED until a run without the setter answers 200 - and every
    request since (three legs green on 2026-09-15) ran without it and did,
    which is consistent with the header cause but does not isolate it: the
    400 came from the broad video-scope query, which later timed out with
    the header gone, so the query may have been the whole story. Stays
    INFERRED; the rule (do not replace the defaults) stands on its own.
18. **The film club's full video scope is too slow for the live site
    (OBSERVED 2026-09-15).** The Live probe settled the search question in
    one click: a LibriVox search through the library answered 200 with
    numFound 101 (the URL bytes, the `+` encoding and the parser are right),
    and the film club's `axVideoScope()` search - three mediatypes OR-ed
    with 26 collection identifiers - had drawn a 400, then no answer inside
    30 s, then libURL's `URL is currently loading` for the orphaned load.
    The `movies` family and every film-collection preset now use the cheap
    `mediatype:(movies OR video OR television)` clause (a collection preset
    leads with `collection:(X) AND`); `axVideoScope()` keeps the app's full
    form for a caller who wants the collection docs and can wait. Two
    fetch-layer rules came out of the same probe: a timed-out request
    `unload`s its URL and a fresh request unloads any orphan of its URL
    first, because libURL refuses a second load of a URL it is still
    loading; and the default timeout is 60 s, not 30. **The verdict came
    the same evening**: the cheap clause answered 200 with 17,098,672 hits
    inside a second, on the same engine that had waited 30 s for the full
    form. Nothing about the full form is WRONG - the film club ships it -
    but the site's cost for an OR over 26 `identifier:` terms inside a
    `mediatype:collection` clause is a query-time cost the app's users pay
    once per session and a library's callers would pay per keystroke.
19. **A player object that cannot open its stream FAILS SILENTLY (INFERRED
    2026-09-16).** "The player is still not working" arrived with a log
    that showed nothing wrong: `set the filename` and `start player`
    throw nothing on a URL the platform's media stack cannot open, and the
    window shows a controller over silence. So a Play that only logs
    "playing <url>" has recorded nothing. The demo now asks the player six
    seconds later - `the duration` (and `the currentTime`) stay 0 when the
    stream never opened - and logs the platform, the URL, the format and
    the answer, then falls back to a download and a LOCAL file, which is
    the one path every platform's player takes. Three suspects are still
    open for the stream itself, and the datanode URL rules out only the
    first: the `/download/` 302 a player may not follow, https inside the
    player at all, and the container (VBR MP3 / MP4 are the safe pair the
    playlist engine already prefers). INFERRED until a log names the wall.
    A pre-pass review the same afternoon added two things the first draft
    lacked: `set the filename of player` DOES give a synchronous verdict in
    `the result` on the platforms that type the media up front ("could not
    create movie reference" is the usual text), so the demo reads it and
    falls back at once instead of guessing after six seconds; and the
    six-second check must know whether it is judging a STREAM or the LOCAL
    file it fell back to, because a player that cannot open the local file
    either (Linux builds have no working player at all; any platform for a
    format its stack lacks) would otherwise download-and-play forever, six
    seconds at a time - the local verdict now ends in `launch document`,
    never in another download. The same review found `put URL x into URL
    "binfile:.."` writing a 0-byte file on a failed GET and reporting
    success (the file write sets `the result` last), which is why
    `axDownloadSync` fetches, judges, then writes.

### 2026-09-20 - the SECOND demo, and the object nothing in this tree had ever used

`examples/archive-gallery.livecodescript` is the same library driven the
other way round: a grid of ten thumbnails in real engine IMAGE objects,
then a film or a concert on a dark stage in the engine's own PLAYER object,
or a photograph in an image object. It was asked for in one sentence - "a
gallery-style app using video player and image object from within the
stack" - and the interesting part is what that turned out to require.

**NO ARCHIVEXT HANDLER CHANGED FOR IT, AND THAT IS THE CLAIM.** The grid is
`axSearch` with `rows` fixed at the tile count; a thumbnail is `axFetchUrl`
against `axThumbnailUrl` arriving through the ordinary `raw` kind; a
picture in the viewer is one playlist entry's datanode URL through the same
call; the file list is `axPlaylist` with the `images` kind the playlist
engine already had. The ONE addition is a fifth family, `mediatype:(image)`,
and it lives in the demo's own `agFamilyFor` rather than in
`axFamilyInfo` - the library's family table is the three source apps' table,
none of them had a picture app, and widening a member's public surface for
one stack is how a member stops describing the thing it was written from.

**SECTION 5 OF `docs/OXT-ENGINE-NOTES.md` HAS NO IMAGE ENTRY, WHICH IS A
FINDING RATHER THAN AN OVERSIGHT.** Nothing in this tree had ever put bytes
into an image object from a script and then asked what happened: box2dxt
loads sprite sheets from FILES, and the coinxt wallet paints a QR it built
itself. So every claim this gallery rests on is DOCUMENTED-class at best,
and the design is arranged around that rather than around a hope:

- **`agSetPicture` is the only place in the stack that touches an image.**
  It sets the content with the location UNLOCKED (the control then snaps to
  the picture's natural size, which is what makes `the width` a
  MEASUREMENT rather than the rect we already chose), asks the control how
  big it became, and treats a width under two pixels as a refusal. That is
  box2dxt's `b2kSheetSourceFromFile` idiom and the wallet's QR idiom
  unchanged, because an image object handed bytes it cannot decode does not
  throw and does not complain - it stays empty, which is gotcha 19's
  silence one object over. Every caller gets EMPTY back and has to decide
  what to show instead.
- **The boot self-check settles the question offline, before anything is
  fetched.** The stack carries a 98-byte four-pixel PNG in hex and puts it
  through `agSetPicture` on open. A FAIL there says this engine will show
  captions over empty frames, in the first second, rather than after ten
  thumbnails have come back looking like a network failure.
- **The live probe's four legs are all about the same question** and none
  of them infers: a search in the image mediatype, the item image service's
  bytes into an image object with the size it answered, the item parsed
  into an `images` playlist, and the full picture's datanode URL into the
  same object. Each leg reports what the CONTROL said.

**THE PLAYER GOT A THIRD SIGNAL, AND IT IS THE ONE NOBODY HERE HAD USED.**
The explorer reads the synchronous verdict `set the filename` leaves in
`the result`, then infers from a duration that never appeared six seconds
later. The gallery keeps both and adds `playStarted`, which a player sends
when it really begins - a POSITIVE signal instead of an inference from
zeros, and nothing in this suite had wired it. It is an addition rather
than a replacement precisely because no engine here has ever been seen
sending it: if none does, the six-second check still decides.

**AND THE FILE-TYPE QUESTION FROM 2026-09-16 GOT AN ANSWER.** "I think we
need to be more specific about file types perhaps" was the report beside
"the player is still not working", and `agStreamPick` is what it turns
into. `axPlaylist` already hands a video entry a `variants` list of
`name|label|size|format` lines; archive.org very often lists an `.ogv`
first, and neither Windows' DirectShow nor macOS' AVFoundation has a stock
Theora decoder - so the playlist's own best entry can be the one encode the
platform cannot open, which is exactly the silent controller over silence.
The picker prefers h.264 / MPEG4 / `.mp4` when the item has one, keeps the
entry's own choice otherwise, and the log says which it took. The rung
below the player is unchanged (download, then play from disk) and the rung
below THAT is `launch document`, the only media path in this tree with a
real engine record behind it (riptide, 2026-08-15, two machines).

**AND THE LADDER KNOWS WHICH RUNG IT IS ON, which is the explorer's own
pre-pass finding applied before this demo met anything.** The six-second
check is armed for the downloaded LOCAL file as well as for the stream, and
`sAgPlayIsFile` is what stops that from being a loop: a stream that never
opened goes to a download, a FILE that never opened goes to the system, and
nothing ever downloads twice. Linux builds have no working player object at
all in this engine line, so without the distinction that platform would have
downloaded and replayed forever, six seconds at a time - which is exactly
what the 2026-09-16 review caught in the explorer before an engine saw it.

**LATE REPLIES ARE A GRID'S HAZARD AND A LIST DOES NOT HAVE IT.** Ten
thumbnails are ten requests in flight at once, so a reader who presses Next
before they land would otherwise see the previous page's pictures under the
new page's captions - a wrong answer that looks like a right one. Every
thumbnail carries the search SERIAL in its tag and a reply whose serial is
not the current one is dropped and logged. The serial is bumped by the
search that STARTS, never by the reply that arrives, so a cancelled search
cannot resurrect itself.

**Two delimiter lessons were applied rather than re-learned.** Box2dxt's
record of `fireEmitter` - an outward call made from inside a loop that has
borrowed the `itemDelimiter` - is why `agCancelThumbs` collects the handles,
restores the delimiter and only then calls `axCancel`, and why
`agStreamPick` parses the variants into a tab record first and scans it
afterwards. A restore at the end of such a loop reads as a fix while
leaving the bug in place.

**THE ADVERSARIAL REVIEW, THE SAME DAY, AND THE SHAPE ITS TWO HIGH FINDINGS
SHARE.** Both were about LEAVING: what the stack does when a reader presses
Back while something is still in flight. The gallery had carefully thought
about the grid's late replies and had not thought about the viewer's at all.

- **Back hid the player and left the six-second check armed.** `stop player`
  leaves the filename loaded, so both of `agPlayCheck`'s guards still
  passed - and a stream that had not opened would then have started a
  multi-hundred-megabyte DOWNLOAD nobody asked for and played a film over
  the gallery when it landed, while a stream that HAD opened would have
  painted "playing" over a stack where nothing was. `agDoStopPlay` already
  established the invariant that leaving playback cancels the check; Back is
  the one path a reader actually takes and it was the one path that broke
  it. The handler's own comment claimed it fell back "only if the reader has
  not moved on", which it had no way to tell - a claim in a comment that
  nothing enforced, which is this member's own recorded failure shape.
- **A picture in flight painted itself over the grid.** `agBigPicture` set
  the big image visible unconditionally, where the tile path asks
  `(sAgPane is "grid")` and this picture's own FAILURE path asks
  `(sAgPane is "viewer")` through `agStagePrompt`. So the failure arm
  respected the pane and the success arm did not.

**And the third finding is the one worth carrying, because the header's own
claim was half true.** "Every picture carries the search SERIAL" was written
about thumbnails and was load-bearing-but-absent for the viewer's picture,
which changes target on every item open and every track selection - neither
of which bumps a SEARCH serial, and neither of which can, because opening an
item must not drop the grid's thumbnails. One counter for two questions is
wrong in whichever direction it is bumped. There are two now
(`sAgViewSerial`), and every transition that changes what the stage is about
goes through `agVoidPicture`, which cancels the fetch AND bumps the serial:
`axCancel` drops a reply still on the wire, the serial drops one already
sitting in the message queue, and neither alone is enough.

**Two smaller ones are the delimiter rule again, and one of them was in the
EXPLORER**, which has been on an engine: `adArmPlayCheck` and `adFileSize`
both read `item` chunks of an engine record without setting the delimiter,
and `adShowProgress` read the layer's `received,total` the same way from
inside a libURL callback. All three are fixed on both demos. The
reachable path is the one holde-em's own sweep names in its comment:
`closeStack` inherits whatever the IDE or another open stack left set, and
under a foreign delimiter the pending-message sweep matches nothing and
cancels nothing, silently.

**The review's own "found nothing" list is worth as much as its findings**
and is recorded so the next reader knows what was looked at: every call
site checked against its definition for arity and command-versus-function,
no undeclared or unused locals, the layout arithmetic bounded inside the
panel on every tile, `agFitRect` proved unable to divide by zero, and the
download-and-play ladder proved terminating on every rung.

**HONESTY, as it stood when this entry was written.** No part of the gallery
stack had run on an engine: not the grid, not one image object, not the
player, not one live thumbnail. That held for a few hours; the entry below
is the run that closed it and the three things it found. The
suite gates
it passes are static plus the member's headless fixtures, and the boot
self-check is what will say - in its own first line, on the reader's own
machine - whether the object this demo is about works there at all.

### 2026-09-20, the evening - the gallery's first engine run, and the three things it was wrong about

The stack met an engine the day it was written (OXT 9.6.3, Windows x86_64).
It booted, searched, opened items, showed the viewer, streamed three MP3s and
ran its four-leg live probe green. It also got three things wrong, and each
one is a different kind of wrong.

**THE BOOT CHECK'S ONE RED LINE WAS THE DECODER, AND THE TELL BEHIND IT WAS
ALSO WRONG.** `an image object takes a picture this stack carries (684x358)`.
684x358 is exactly the stage rect the stack had already set, so the image had
simply kept what it had. Two separate defects:

- The bytes were never a picture. The check fed the carried PNG through the
  harness's `axtHex`, which ends in `textDecode(tOut, "UTF-8")` because every
  other thing it decodes is a JSON fixture and has to come back as TEXT. A
  PNG is not UTF-8, so the decode replaced the invalid sequences and handed
  the image object something else. The gallery owns `agHexBytes` now and asks
  nothing of axtHex; the fix is not to widen axtHex, because all its other
  callers want text.
- **The refusal could not have been detected anyway.** "A width under two
  pixels means the bytes were refused" is box2dxt's idiom, and it works there
  because `b2kSheetSourceFromFile` puts bytes into a control it has just
  CREATED, which has no rect. Here the control carried one, so a refusal read
  back as the rect. `agSetPicture` now clears the content and forces the
  control to one pixel before setting the bytes, and the boot check asserts
  BOTH directions - a picture must be taken, and bytes that are plainly not a
  picture must be refused, which is what will MEASURE the refusal shape on
  the next engine rather than assume it. Root engine notes 5.7.

**THE PLAYER OPENED, RAN, AND WAS SILENT - and its own properties could not
say so.** Three streams: `the result` empty after `set the filename`, a
non-zero duration, `playStarted` on two of the three, and a currentTime that
had advanced 6.03 seconds when the six-second check looked. The reader heard
nothing, and video did not open at all. Root engine notes 5.8 has the record;
what belongs here is what the stack does about it, because every one of these
was a thing the stack never did rather than a thing it did wrong:

- **It never set `the playLoudness`.** Not on the player, not on the engine.
  Note 5.4 already says the property is a request rather than a register, so
  a stack that never sets it is a stack running on whatever the IDE or
  another stack last left. It is set on both now, before every stream, and
  there are Vol + / Vol - buttons because the first thing anyone does with a
  silent player is look for a volume.
- **It could not say what the player had.** `agPlayerReport` logs
  `playLoudness`, `paused`, `playRate`, `status`, `mediaTypes` and `tracks`,
  each read in its own try, at two moments. `the tracks` is the line that
  settles it: it says whether an audio track was found at all.
- **`playStarted` was thrown away on the first play of every session**, which
  is the sharpest of the three because the log looked fine. `on playStarted`
  exits when `sAgPlayUrl` is empty - it has to, or another stack's player
  would be reported as ours - and `agDoPlay` set that variable AFTER
  `start player`. The second and third plays printed the line only because
  the first had left the variable set. State goes up before the player is
  told anything now.
- **And the one experiment nobody has run is now one click.** The platform
  media path on Windows is DirectShow, documented for http and not for https.
  The six-second check retries the same datanode URL once over `http://`
  before falling back to a download. If that opens, the answer to "why will
  video not play" is a scheme.
- Play also prefers a copy **already on disk**, which is both the cheaper
  path and the only way to separate a streaming problem from a playback one
  without guessing - and it means Download and Play now agree about which
  encode they are talking about (`agStreamPick` decides for both; Download
  used to save the playlist's own best entry while Play streamed a different
  one).

**AND THE CAPACITY WAS TWO LIMITS WEARING ONE NUMBER.** A search for 29,281
hits showed ten of them, because `kAgTiles` was also the `rows` the request
asked for. They are different questions - how many results one request brings
back, and how many fit on screen - and they are separate constants now: the
grid is eight by three (a cell of 130x96 shows the item image service's own
180x124 derivative at about 1:1, measured on this run), and a request brings
back `kAgPageSize` results, eight screens' worth, which Prev and Next walk with
no network at all. The page label says "showing 25-48 of 29,281" rather than a
page number, and Next stops at the site's 10,000-hit deep-paging wall instead
of offering a button that comes back empty.

**THE CACHE, asked for in the same breath.** archive.org is a public service
run on donations and a gallery is the client shape most likely to abuse it, so
nothing is asked for twice if it can be helped, on two tiers. Thumbnails and
item metadata live in memory AND on disk under the same Documents/ArchiveXT
folder Download writes to, so reopening the stack tomorrow costs the site
nothing for anything it already answered; search pages live in memory only,
deliberately, because the site's result order is not stable and its counts
move - a search page is a thing to reuse for a minute and not for a week.
Metadata expires after a week with the stamp written INTO the file rather than
read from its modification date, because date formats are the engine's and
this needed no engine pass to be right. A screen of twenty-four thumbnails
also does not fire twenty-four requests: `kAgFetchMax` are in flight and the
next starts when one lands, because the only concurrency this suite has ever
measured is the ten that run happened to fire. The counters are on screen,
because a cache nobody can see is a claim rather than a feature.

**THE HARNESS'S ONE RED LINE WAS A CLOBBERED VARIABLE, and its neighbour had
become a check that could not fail.** `axSelfTest` came back 384/1 on
`a scalar subject is one line`. The scrape-API block added on 2026-09-16 was
inserted between the block that parses the librivox SEARCH fixture into
`tResult` and two assertions that still read it, and its own
`put axScrapeParse(...) into tResult` took the name. So one assertion read
docs out of an array that has no docs, and the line under it - "an absent
field is empty" - passed VACUOUSLY for any input at all. The scrape block has
its own variable now. Worth keeping because of WHERE the gates could not see
it: `check-script-vectors.py` drives the LIBRARY and `check-selftest-vectors.py`
re-derives CONSTANTS, so nothing headless executes the harness's own
assertions, and the engine is the first thing that ever runs them.

### 2026-09-20, later - what ten reviewers found in the day's own work

The engine pass above was reviewed by five pairs of agents, each pair an
investigator and a reviewer told to REFUTE it, and the reviewers earned their
place: two of the five investigations had their headline recommendation
overturned by someone who ran the code instead of reading it. What survived,
and is now in:

- **`agHexBytes` had no even-length guard**, so `agHexBytes("abc")` answered
  one byte instead of refusing - a truncated picture, which is still a
  picture-shaped thing to hand an image object. Confirmed by driving the
  shipped handler through the family interpreter, twice, independently.
  coinxt's `cxHexDecode` carries that guard with a long comment about why;
  this copy was written from the shape and not from the lesson.
- **The tile caption could silently lose its second line.** The kit's
  `uiLabel` sets neither `margins` nor `dontWrap`, and a `lockText` field with
  neither WRAPS - so a title one character over budget becomes two lines and
  pushes the creator onto a third, outside a two-line box. And the budget was
  guessed: 26 characters needs 165 px of a 130 px cell at textSize 9. Measured
  properly (12 px per em, 0.53 em a character worst case, 126 px drawable
  inside 2 px margins) the answer is 20. The 52 it replaced was never measured
  either - it implied 3.8 px a character, which no face in this family is.
- **The row gutter was 4 px** against 12 px between columns, so a descender
  sat on the next tile's border. The investigator's fix was to shrink the
  tile to 92; the reviewer showed that is only free for LANDSCAPE sources -
  the gallery's own `images` family is arbitrary aspect and LibriVox covers
  are square to portrait, which would have lost 8% of their area. Taking the
  10 px out of the CAPTION instead (30 to 28, which still holds two 12 px
  lines inside 2 px margins) costs nothing at all.
- **One fat entry could evict a whole screen from the thumbnail cache.** It is
  refused from memory now, above a screenful's share, and still written to
  disk.
- **`kAgPageSize` went to 192**, which is eight screens a request. The
  investigator wanted 200 to 300; the stack's OWN boot self-check refuses
  those, because neither is a whole number of screens and `agStepScreen`'s
  arithmetic is written for whole ones. A gate written that morning caught a
  recommendation made that afternoon, which is the whole argument for writing
  the assertion beside the constant.

**AND TWO MORE ASSERTIONS IN THE HARNESS THAT COULD NOT FAIL**, both found by
mutation against the shipped code rather than by reading it. `axSearchSync
refuses an empty query` was passing because `tOptions` still carried the bad
`rows` from the line above, so it refused for the wrong reason and could not
fail for the property its label names. And `scrape: the last page has no
cursor` - the stop condition of the whole deep-paging walk - is equally true
of a parser that REFUSED the page: a mutation making `axScrapeParse` refuse an
empty items page left the harness fully green at 350/0. Both fixed. That is
the third and fourth instance of this class in one day, after the clobbered
`tResult` and its vacuous neighbour, and they share one cause: **no gate in
this tree executes the harness's own assertions.** `check-script-vectors.py`
drives the LIBRARY and `check-selftest-vectors.py` re-derives CONSTANTS, so
the engine is the first thing that ever runs them, which makes every one of
them a claim rather than a check until someone pastes the file.

### 2026-09-20, the second engine run - the harness broke the app it had just certified

A long session on the same engine (OXT 9.6.3, Windows x86_64): films and
concerts searched, items opened, three MP3s played, the four-leg probe green
again (180x124 and 1988x1367 into image objects, a second time). Four findings,
and the first is the worst kind - everything was working correctly and the
result was wrong.

**`axSelfTest` LEFT THE LIBRARY CONFIGURED FOR THE HARNESS, and from then on
the app around it was broken.** Every request after the Tests button read:

```
request 30 (item) failed: the reply is larger than 65536 bytes,
which no answer this layer asked for should be
```

65536 is not a number anywhere in the gallery (its cap is 48 MB) or in the
library (16 MB by default). It is the value the harness's own fetch-layer
section sets to prove `axSetMaxBody` accepts a plausible number, one line
before it proves the setter REFUSES 12. The section never put it back - and it
also re-pointed `axInit`'s owner at itself and re-set the timeout. So item
metadata, every full picture and every 192-row search were refused by a test
fixture, with a correct sentence about a reply that was perfectly fine.

**The fix is a library feature rather than a harness patch**, because the
hazard is not the harness's: `axInit` / `axSetCallback` / `axSetTimeout` /
`axSetMaxBody` write script locals of an object that exists ONCE per process,
so any second caller - a harness, a settings panel, a second stack in the same
IDE - silently reconfigures the first. `axSettings()` hands back all five
settings and `axRestoreSettings` takes them, the harness snapshots on the way
in and restores on the way out, and five assertions prove each one came back.
Restoring writes the locals DIRECTLY rather than through the setters, because
a setter declines values outside its range and an undo that silently declines
is the bug it exists to prevent.

**THE WINDOW WAS YESTERDAY'S.** The boot check reported `agCacheInfo`,
`agLouder`, `agQuieter` and tiles 11 to 24 missing - the three controls and
fourteen tiles added that morning. `agBuild` skips its work when the stack
already carries `kAgUiVersion`, and that literal had not been bumped, so a
reader pasting the new script over the stack they already had got the old
window with the new code behind it. THREE halves, which is the interesting
part, because each catches something the others cannot:

- **`kAgUiVersion` is DERIVED from the builder's own text**
  (`tools/check-gallery-ui-version.py`, `--fix` writes it): the first twelve
  hex digits of a SHA-256 over every `command agBuild*` handler. A new
  control changes that text, so the constant changes, so a stack carrying
  the old one rebuilds. **coinxt had already hit this exact failure and
  already built this exact gate** (2026-09-04: a BIP-322 checkbox, Inscribe,
  Lock and four more buttons that never appeared in any existing stack), and
  it took an engine run to notice that the wallet's lesson applied here
  verbatim. Reading the sibling's `tools/` directory is cheaper than a
  second engine pass.
- **`agUiStamp()` carries the geometry**, because the failure has a second
  shape the fingerprint cannot see: the grid went from 10 tiles to 24 by
  changing `kAgTiles`, which the builder READS in a loop - not one character
  of `agBuild`'s text changed. The stamp is the constant plus the grid, the
  tile size and the window size, and the gate asserts that half is still
  there so a tidy-up cannot quietly leave one mechanism doing two jobs.
- **`agScRun` repairs before it reports.** When a control the DERIVED list
  names is missing it calls `agRebuild` once, re-measures, and says in the
  log that the window was redrawn; a second miss is a real defect and still
  fails. That list is the right oracle because
  `tools/check-demo-control-lists.py` maintains it from the source. The
  rebuild repaints from the STATE rather than the defaults (the family
  hilite, the pane, the cache line and any loaded page), because agStart
  paints those AFTER agBuild and a repair that skipped them would leave a
  stack whose script thinks a family is selected and whose window shows
  none - which the boot check would then have failed on, one assertion
  further down.

**TWO FILMS COST 795 MB TO LEARN ONE FACT.** An h.264 MP4 stream was refused
at once with `could not create movie reference`; the stack downloaded 408 MB,
handed the file to the same player, got the same sentence, and passed it to the
system - then did all of it again for a 386 MB MPEG4. Root engine notes 5.9 has
the record (the container is the wall: audio on the same machine in the same
session played). Three changes: a suffix refused from DISK is remembered for
the session and a later stream of that container is not downloaded at all, but
named in a prompt beside the two things that do work (Download, Open page); the
http-scheme retry moved OUT of the six-second check into one
`agStreamFailed`, so the cheap discriminator runs BEFORE the expensive
download rather than after it; and both ways of learning a stream failed (the
synchronous refusal and the six-second silence) now take that one ladder,
which is why the retry had never run - the engine refused these streams
instantly, and the retry lived only on the slow path.

**AND THE FIRST `playStarted` WENT MISSING AGAIN, WHICH REFUTES THE FIX MADE
THAT MORNING.** The morning's reading was ordering - the stack set its "this
player is mine" variable after `start player`, so the message arrived before
anything would recognise it - and that was corrected before this run. The run
lost the first one anyway: silent on play one, reported on plays two and
three, exactly as before. The correction was right about what to do and wrong
about why, and the honest move is to say so in the note rather than leave a
plausible story standing (root engine notes 5.8 now carries both). The one
remaining difference between play one and every later play is that play one
also CREATED the player control, so the player is created at start now
(`agPlayerEnsure`) - and if the next run still loses the message, a
script-side cause is ruled out, which is worth as much as a fix.

**AND A FAILURE QUOTED ANOTHER REQUEST'S HEADERS.** A timed-out search came
back carrying `HTTP/1.1 200 OK` and an `Onion-Location` naming the `/metadata/`
URL a blocking probe leg had just fetched. That is `libURLLastRHHeaders`
keeping the LAST reply (gotcha in engine notes 6.9) landing in the one place a
reader trusts a header block absolutely. The header block is labelled in the
sentence now rather than in a doc. Engine notes 5.10 also pairs the async
timeout with the blocking call beside it and marks the causal half
UNEVIDENCED - one observation is not a rule.

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
python3 archivext/tools/check-gallery-ui-version.py   # --fix writes the stamp
python3 archivext/tools/check-docs-style.py
tools/build-all.sh --gates                          # the whole suite set
```

- **Honesty labels.** Everything in this member read "verified statically;
  needs an OXT pass + a live archive.org pass" until 2026-09-15, when the
  standalone harness, the demo's window and the first three live legs were
  all observed (the as-built record above). What is still owed is SCOPED
  now - the fold, the item parser and playlist engine on a live file list,
  the async `search` kind, the two error shapes, the scrape API, the
  certificate direction of TLS, streaming - and every label says which. Flip them in EVERY carrier (README, the STATUS blocks, the
  runbook row, the suite overview) in one change - the doc-status gate
  exists because nostrxt's pass reached five documents and not the other
  seven.
