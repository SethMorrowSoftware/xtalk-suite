# 00 - Overview and architecture

> **Status: First engine contact 2026-09-15: `axSelfTest` ran on the user's OXT engine (platform not recorded) at 357 passed / 2 failed / 0 skipped. Both reds were fixed the same day - the JSON reader indexed object children by key in an array and the engine folds array-key case (root `docs/OXT-ENGINE-NOTES.md` 2.7), and one hand-written harness expectation was simply wrong - and the re-run is owed. Still owed: that re-run, the suite-paste fold, the demo's
> window, and a live archive.org pass.** The `ax*` pure layer is EXECUTED on every build through the
> family's headless interpreter against `tools/archive_reference.py`, an
> independent implementation of the same rules anchored to the three source
> apps' own test vectors; the fixtures it runs over are synthetic (the site
> is unreachable from the build sandbox). The fetch layer is written in the
> shapes two other suite stacks use for the engine's Internet library and
> has no engine record of its own. Claim nothing beyond that.

## What ArchiveXT is

An archive.org client layer for OpenXTalk / the xTalk family, in one
LiveCodeScript file, with no native code and no third-party code. It exists
because three shipped web apps (the Grateful Dead Tape Finder, the LibriVox
AudioBooks app, Archive Film Club) had each re-derived a slice of the same
client - a query builder, a URL builder, a JSON reader, a file-list-to-
playlist rule - and none of the three could be pasted into an xTalk stack.
ArchiveXT is the union of what they learned, as a library, and the demo is
the three of them in one window.

## The shape: two layers in one file

```
src/archivext.livecodescript
  |
  |-- ax* PURE COMPUTE (axVersion .. axPlaylistTable)
  |     encoders and text helpers        axUrlEncode, axQueryEncode, axTrim, ...
  |     identifiers, years, durations    axIdentifierIsValid, axYearOf, axDurationSeconds, ...
  |     the query grammar                axQuerySanitize, axQueryBuild, axQueryYears, ...
  |     families, presets, filters       axFamilyInfo, axPresetSpec, axFilterClauses, axSortClause
  |     URL builders                     axSearchUrl, axMetadataUrl, axDownloadUrl, ...
  |     the owned JSON reader            axJsonParse, axJsonGet, axJsonValues, ...
  |     response parsers                 axSearchParse, axItemParse, axDocsTable
  |     files to playlists               axFileIsAudio, axFileStem, axPlaylist, axPlaylistTable
  |
  |-- ax* FETCH (axInit .. axFetchItemSync)      ENGINE ONLY
        load URL ... with message "axUrlDone"; one request = one handle;
        the reply arrives as onArchive pHandle, pKind, pValue, pTag
```

The split is the point, not a tidiness. The pure half does no I/O, calls
nothing engine-only and arms no timer, so the WHOLE of it runs headlessly on
every build - which is the only kind of execution this member has had. The
fetch half is the part that can only be proven on an engine, and it is kept
small: it builds nothing a pure handler could build, it just moves bytes and
correlates replies.

Both halves share one error convention (the riptide / nostrxt-core shape):
**no handler here ever throws.** A function returns empty (or `false` for a
predicate) on refusal and records the reason for `axLastError()`; a command
that yields a handle returns the integer or empty. Every engine call that can
throw sits in a `try`. Read the return, then `axLastError()`, in that order -
a later successful call overwrites the reason.

## The four families

A FAMILY is one of the three apps' worlds plus a generic one, and it decides
the scope every search carries, the fields a search asks for, the default
sort and page size, and the playlist kind an item of that family wants:

| Family | Scope | Playlist kind | From |
|---|---|---|---|
| `etree` | `mediatype:(etree)` | `audio-tracks` (a concert's set list) | the tape finder |
| `librivox` | `collection:(librivoxaudio)` | `audio-chapters` (a book's chapters) | the AudioBooks app |
| `movies` | three mediatypes OR 26 collection identifiers | `video` (episodes with quality variants) | the film club |
| `any` | none - by mediatype | `auto` (decided per item from its mediatype) | new |

`axFamilyInfo` answers all of that as an array; `axPresetSpec` turns a
preset id plus the user's text, years and filter ids into the spec
`axQueryBuild` builds the whole `q` from. That is each app's search-box logic
in two calls.

## How it is verified without an engine

- **The oracle.** `tools/archive_reference.py` is a second implementation of
  every pure rule, in Python, written from the apps' JavaScript and PHP
  (regex for regex) rather than from the script, so a slip in the script and a
  slip in the oracle would have to agree to pass. At import it asserts the
  apps' own published test vectors and refuses to load if any fails.
- **The fixtures.** Nine synthetic archive.org responses under
  `tests/fixtures/`: a LibriVox search and item (the AudioBooks e2e mock
  shape, 36 files), an etree search and item (a 1977 show with VBR / 64k /
  FLAC / Ogg per song, one derivative-only track, sidecars), a movies search
  (including a collection doc) and item (a three-episode series with 512kb
  and ogv variants, sentinel files, a tiny placeholder), a texts item, the
  site's error shape, and a missing item.
- **The KAT.** `tools/archive-kat.py` derives every constant the harness pins
  from the oracle and the fixtures (fixture bytes as hex; parsed expectations
  joined with `|`; anything carrying a quote, a newline or a non-ASCII byte
  pinned as hex and named `...Hex`, an asserted rule). `--check` sweeps it all
  twice and compares.
- **The execution gate.** `tools/check-script-vectors.py` drives the SHIPPED
  script through `tools/lcs-interp.py` in five tiers: the interpreter model
  it leans on, scalar rules and the file-name rules against the oracle, the
  sanitizer and query builders, the preset / filter / sort tables against the
  oracle's second transcription, every fixture through both parsers and every
  playlist kind, and the refusal paths. `tools/test-script-vectors.py` seeds
  seven defects into a copy and requires the gate to fail on each, because a
  gate is believed only once it has been seen to bite.
- **The harness.** `examples/archivext-tests.livecodescript` is the on-engine
  half: 12 sections, all offline, every public handler named (the fetch
  handlers through their refusal paths), folded into the suite paste as
  `ax1*`.

## What ArchiveXT is NOT

- **Not a downloader.** It builds download URLs and can fetch a small body
  through `axFetchUrl`; writing a large file to disk in the background is an
  app concern (and a `load URL` with a progress callback is the engine's
  shape for it).
- **Not a player.** A stream URL is handed to whatever the app has - the
  demo uses a player object and falls back to `launch URL`.
- **Not an uploader**, and not an authenticated client: the S3-like upload
  API and the logged-in endpoints are out of scope (see
  `07-open-questions.md`).
- **Not a cache.** Every reply is unloaded from the URL cache the moment it
  is handled; an app that wants to remember a search keeps the array.
