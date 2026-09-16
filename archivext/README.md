# ArchiveXT

**archive.org from xTalk: the Internet Archive's search, metadata, download
and image APIs for OpenXTalk (OXT) / the xTalk family, in pure script, plus
everything three shipped archive.org web apps learned to do on top of them.**

ArchiveXT gives an xTalk app the four public surfaces every archive.org
client is built from, and the rules that turn their raw answers into
something a user can play:

1. **Search** - the advanced search API (`advancedsearch.php`) with a Lucene
   query grammar, a sanitizer that keeps user text from becoming a parse
   error (archive.org answers those with HTTP 200 and a stack trace from
   Solr), year ranges, quick filters and a sort menu; and the scrape API
   for deep paging.
2. **Items** - the metadata API (`/metadata/<identifier>`) parsed into an
   xTalk array, with every scalar-or-array field read as lines.
3. **Files to playlists** - an item's raw file list (originals, the site's
   derivatives, thumbnails, sidecars, torrents) turned into a concert's track
   list, an audiobook's chapters, a film's episodes with quality variants, a
   text's readable formats, an image set, or a plain file list.
4. **URLs** - download and streaming paths, thumbnails, the details page and
   the embed player, every one built from a validated identifier.
5. **Catalogues** - the three apps' preset tables as data: the Live Music
   Archive's band collections, LibriVox's audiobook categories, the Moving
   Image Archive's film collections, and a generic family for any mediatype.
6. **An asynchronous fetch layer** over the engine's own Internet library:
   one callback per request, correlation by handle, a watchdog, a body cap,
   a late-reply drop, downloads straight to disk with progress and a stall
   watchdog, and blocking conveniences for the message box.

```
   your xTalk app
      |  build a query, pick a preset      |  search / fetch an item
      v                                    v
   ax* PURE COMPUTE                      ax* FETCH (the tail of the file)
   URL + query builders, preset          load URL ... with message, one
   tables, the owned JSON reader,        request = one handle, the reply
   response parsers, the playlist        arrives as
   engine; no I/O, runs headlessly       onArchive h, kind, value, tag
   on every build                           |
                                            v
                                         archive.org (advancedsearch.php,
                                         /metadata, /download, /services/img)
```

> **Documentation:** [`docs/README.md`](docs/README.md) indexes the numbered
> 00-07 series. If you just want to use ArchiveXT, jump straight to
> [`docs/06-usage-guide.md`](docs/06-usage-guide.md).

## The three apps this folds together

ArchiveXT was built by reading three shipped web apps, each of which had
re-derived a slice of the same client, and taking the union:

| App | What it contributed |
|---|---|
| **Grateful Dead Tape Finder** | the Live Music Archive (`etree`) grammar, a 49-preset band table with per-band year ranges, the SBD / AUD / matrix / top-rated quick filters, `d1t01`-style track titles cleaned of their prefix, natural filename order |
| **AudioBooks (LibriVox)** | the query SANITIZER (the only user-input safety layer any of the three had), a 40-preset category table, chapter grouping by original file, MP3 format ranking, duration parsing, and the exact bytes of the search URL (its tests pin them) |
| **Archive Film Club** | the video scope (three mediatypes OR 26 collection identifiers; kept as `axVideoScope`, while the family searches the cheap mediatype clause since the full form timed out live), the film-collection table, the sort menu, episode identity across encodes (`normalizeBaseName`), MP4-first and largest-size quality selection, quality labels, sentinel-file filters, the public-domain licence clause |

Where two apps disagreed, `docs/03-items-files-and-playlists.md` records
which rule ArchiveXT took and why. The demo stack
(`examples/archivext-demo.livecodescript`) is all three apps in one window,
plus the generic fourth family.

## Quick start

There is nothing to install: ArchiveXT is pure LiveCodeScript and its
network calls go through the engine's Internet library.

**The demo (recommended first contact).** Copy the contents of
`examples/archivext-demo.livecodescript` into the script of a NEW stack, save
it, close it and reopen it. The window builds itself and prints its own boot
self-check. It carries the library and the member self-test verbatim, so no
`start using` step is needed. (Opening the file directly does not build the
window: root `docs/OXT-ENGINE-NOTES.md` 5.5.)

**In your own app.** Open `src/archivext.livecodescript` as a stack and
`start using` it, or paste it into a library stack of your own. Then:

```
-- a blocking search from the message box
put axSearchSync("collection:(GratefulDead) AND year:[1977 TO 1977]", empty) into tResult
put tResult["numFound"] && tResult["docs"][1]["title"]

-- the asynchronous shape for anything with a window
axInit the long id of this stack
axSetCallback "onArchive"
put axSearch(axPresetQuery("librivox", "Author_Search") , empty) into tHandle

on onArchive pHandle, pKind, pValue, pTag
   set the defaultStack to the short name of this stack
   if pKind is "search" then ... else if pKind is "item" then ... else if pKind is "error" then ...
end onArchive
```

`docs/06-usage-guide.md` walks the whole path from a preset to a playing
stream, and `docs/05-api-reference.md` names every handler.

### First engine contact: the exact procedure

The library and the harness are two files, and the harness only works when
the library is in the message path. The demo removes that step, so use it
first:

1. In OXT, make a NEW stack (File > New Stack). Open its stack script.
2. Paste the WHOLE of `examples/archivext-demo.livecodescript` in, apply,
   save the stack somewhere, close it, and reopen it (a pasted script does
   not run `openStack` until the stack is opened again).
3. The window builds itself and the log panel prints the boot self-check.
   Click **Run tests** for the full `axSelfTest` report; **Copy** it.

To run the harness on its own instead: open `src/archivext.livecodescript`
as a stack (File > Open Stack), type `start using stack "archivext"` in
the message box, then paste `examples/archivext-tests.livecodescript` into
a second new stack's script and type `put axSelfTest()`.

If a call fails with `Function: error in function handler` and the hint is
a library handler name, the library is NOT in the message path (it was not
put in use, or its script is dead from a parse failure the engine reports
only lazily - root `docs/OXT-ENGINE-NOTES.md` 3.4). Type `put axVersion()` in the
message box: `ArchiveXT 0.1.0` means the library is loaded and the fault is
elsewhere; an error means it is not, and `put the stacksInUse` shows what
is. Send back the FULL text of the error dialog, every line.

If a search reaches the site and the log says `400 Bad Request`, four
message-box lines separate a header cause from an encoding cause:

```
put URL "https://archive.org/advancedsearch.php?q=collection%3Alibrivoxaudio&fl%5B%5D=identifier&rows=1&output=json"
put the result          -- empty means the plain library path works
put axSearchSync("collection:(librivoxaudio) AND (austen)", empty)["numFound"]
put axLastError()       -- empty means archivext's path works too
```

## Status (honest)

**First engine contact 2026-09-15: `axSelfTest` ran on the user's OXT engine (platform not recorded) at 357 passed / 2 failed / 0 skipped. Both reds were fixed the same day - the JSON reader indexed object children by key in an array and the engine folds array-key case (root `docs/OXT-ENGINE-NOTES.md` 2.7), and one hand-written harness expectation was simply wrong. The re-run read 363 / 0 / 0, the demo's window booted with its self-check 11/11, and the first LIVE pass ran 2026-09-15, later the same day, from the demo's Live probe on the user's OXT engine: a LibriVox search through the library answered HTTP 200 (numFound 101), a real item's metadata came back whole (196,716 bytes, chunked, through the blocking path), and the movies family's cheap scope answered with 17,098,672 hits - every URL byte, the form encoding and both parsers agree with the live site. On 2026-09-16 the five-leg probe and the demo's Search button closed four more legs: a live 412-file list through the item parser and the playlist engine (58 chapters, each with a stream URL), the async `search` kind through the callback (four searches across three families), and both documented error shapes through the shipped code (a Solr error inside an HTTP 200, a missing item's `{}`). Still needed: the suite-paste fold, the async `item` kind, the scrape API, TLS's certificate direction, and streaming.** What is machine-verified on every build, without an engine:

- **The pure layer is EXECUTED**, not just read: `tools/check-script-vectors.py`
  drives the shipped script through the family's headless interpreter
  (`tools/lcs-interp.py`, the coinxt copy) against `tools/archive_reference.py`,
  an independent Python implementation of every rule, written from the three
  apps' own JavaScript and PHP rather than from the script. It re-measured at
  2920 checks on 2026-09-15; run it for today's number.
- **The oracle is anchored** to the three apps' own published test vectors at
  import time, so a broken oracle refuses to load.
- **Every harness constant is derived**, by `tools/archive-kat.py`, and
  `tools/check-selftest-vectors.py` re-derives each one by name on every
  push, so a pasted expectation cannot drift from the fixtures.
- **The gate is proved to bite**: `tools/test-script-vectors.py` edits seven
  defects one at a time into the shipped script and requires the vector gate
  to fail on each (a transposed hex alphabet, a sanitizer that keeps a colon,
  a misspelled collection, a chapter stem that keeps `_vbr`, an inverted
  MP4-first rank, a one-digit natural pad, a dropped etree ordering).

What that does NOT cover, and what the runbook asks for:

- The **fixtures are synthetic**. archive.org is unreachable from the build
  sandbox, so `tests/fixtures/*.json` are shaped from the apps' own mocked
  responses and the documented API. A green build says the script agrees
  with the oracle about those bytes, not that the live site still answers in
  that shape. The first live pass (2026-09-15) said the search shape does -
  `numFound` / `docs` arrived as the fixtures assume - and the second
  (2026-09-16) put a real 412-file list through the parser and the playlist
  engine and got the book's 58 chapters in order.
- The **fetch layer** (`axInit` onward) uses `load URL ... with message`,
  `unload URL` and `libURLErrorData` in the
  shapes two other stacks in this suite use, and since 2026-09-15 it is the
  first of the three WITH an engine record: the async path delivered the
  `error` kind (a 400, then the watchdog's `timeout`), and the blocking path
  carried three green requests over https, one of them a 196 KB chunked
  body (root `docs/OXT-ENGINE-NOTES.md` 6.9). Whether this engine's Internet
  library VERIFIES certificates is still the suite's open TLS question (6.8
  is a socket observation, 6.9 a libURL one, and neither offered the engine
  a bad certificate). `docs/04-fetch-layer.md` and `docs/07-open-questions.md`
  carry the detail.
- The **member self-test** (`examples/archivext-tests.livecodescript`,
  `axSelfTest()`, 12 sections) ran standalone on 2026-09-15 with zero skips
  (the engine's Internet library answered), and again at 363 / 0 / 0 after
  the fixes. It is folded into the suite paste as `ax1*` and has not yet
  been run THERE; the demo's window HAS opened on an engine (boot self-check
  11/11, the Live probe's three legs green).

## Layout

```
archivext/
  README.md                       this file
  CLAUDE.md                       maintainer memory: the as-built record and the gotchas
  IMPLEMENTATION-PLAN.md          the phased HOW, with what is built and what is open
  LICENSE                         MIT (no third-party code is bundled)
  src/archivext.livecodescript    THE LIBRARY: ax* pure layer + ax* fetch layer, one file
  examples/archivext-tests.livecodescript   the member self-test (axSelfTest), KAT constants pinned
  examples/archivext-demo.livecodescript    the three apps in one stack (carries library + harness)
  tests/fixtures/*.json           nine synthetic archive.org responses, hex-pinned by the KAT
  tools/archive_reference.py      the independent oracle (Python, anchored to the apps' vectors)
  tools/archive-kat.py            derives the harness constants; --check sweeps everything
  tools/check-selftest-vectors.py re-derives every pinned constant by name
  tools/check-script-vectors.py   EXECUTES the shipped script against the oracle + fixtures
  tools/test-script-vectors.py    proves that gate fails on seven seeded defects
  tools/lcs-interp.py             the family interpreter (byte-identical to coinxt's; drift-gated)
  tools/check-doc-handlers.py     docs <-> shipped handler set, both directions
  tools/check-livecodescript.py   the unified static gate (byte-identical suite-wide)
  tools/check-docs-style.py       the house-style prose gate
  docs/                           the numbered 00-07 series, indexed by docs/README.md
```

## How it is held true

Every gate above runs in `tools/build-all.sh --gates` from the repository
root, which is what CI runs on every push. Suite-wide, ArchiveXT is also
walked by the cross-library name gate (every `ax*` name unique across the
suite), the handler-calls gate, the timer-stack-pin gate (its callback
delivery is registered there), the UI-kit and self-check drift gates for the
demo, the launcher registry, and the suite coverage ratchet (every public
`ax*` handler is named by the folded harness; the fetch handlers through
their refusal paths). The demo's embedded copies of the library and the
harness are pinned to their sources by `tools/sync-demo-embeds.py --check`.

## License

MIT, see [`LICENSE`](LICENSE). ArchiveXT bundles no third-party code. The
Internet Archive's APIs are theirs; be a polite client (the scrape API exists so a walk over a whole
collection does not hammer the search endpoint).
