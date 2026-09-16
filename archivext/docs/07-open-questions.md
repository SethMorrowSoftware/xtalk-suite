# 07 - Open questions

> **Status: this is the to-do list.** Every item was open on 2026-09-15,
> the day the member landed; the first engine contact later that day closed
> the parts struck below. Strike items in place as they close, with the date
> and where the evidence went.

## What the first ENGINE pass must answer (no network needed)

1. **Does the fold compile?** `tests/suite-selftest.livecodescript` carries
   the member harness as `ax1*` and the library verbatim. One bad line takes
   the whole paste (root `CLAUDE.md`, the `dcCleanup()` lesson), and this
   member's 4200 lines have met only the interpreter's subset of the
   language. The things most likely to differ from the interpreter: the
   `byteOffset` skip argument (added to the interpreter for this member, so
   the model is new), `sort lines of` over the rank keys, `the keys of` on a
   nested array, and `replace "#" with quote in tT`.
2. ~~Does the harness run at all?~~ **CLOSED 2026-09-15, standalone**: `axSelfTest`
   ran on the user's OXT engine at 357 passed / 2 failed / 0 skipped (the
   Internet library answered, so the fetch section skipped nothing); both
   reds fixed the same day (`CLAUDE.md` as-built, gotchas 15-16). Still open:
   **does `ax1axSelfTest` report readably in the suite paste**, and does the
   re-run after the fixes read 359/0? Copy the `ArchiveXT` line of the per-member table and
   every red line verbatim into `CLAUDE.md`'s as-built notes; that measured
   floor replaces the placeholder floor 1 at the core's
   `stMergeReturned "ArchiveXT"` call site.
3. ~~Does the demo boot?~~ **CLOSED 2026-09-15**: `examples/archivext-demo.livecodescript`
   booted on the user's engine with its self-check 11/11 (47 controls, the
   preset table, the vector-derived search URL, the etree fixture as six
   tracks), and again on 2026-09-16 after the probe rewrite. The one red it
   ever showed was the copy-paste class the carried block exists for: a new
   button reported `missing` because `kAdUiVersion` had not been bumped, so
   the window was never rebuilt (the constant carries a BUMP-THIS comment
   now).
4. ~~Does the JSON reader agree with the engine about UTF-8?~~ **CLOSED
   2026-09-15**: the escape checks (one-byte escapes, a surrogate pair to four
   UTF-8 bytes, a two-byte code point) and the hex-pinned chapter title all
   ran green on the engine. What the run also found, in the same section: the
   engine folds ARRAY-KEY case, so the reader's by-key index answered `a` for
   `A` - fixed by a byte-exact scan (`CLAUDE.md` gotcha 15, root engine notes
   2.7). A non-BMP code point in a REAL title is still the live pass's.

## What the first LIVE pass must answer

5. ~~The search endpoint's shape today.~~ **CLOSED 2026-09-15, live**: the
   demo's Live probe ran `axSearchSync("collection:(librivoxaudio) AND
   (austen)")` against the site and got 200, numFound 101, first
   `emma_1903_librivox` - the URL bytes, the `+` encoding and the parser all
   agree with the live site. What failed was the film club's full video
   scope: a 400 once, then no answer inside 30 s, then libURL's `URL is
   currently loading` for the orphaned load; the movies family now searches
   the cheap mediatype clause (gotcha 18), and the next probe WAS its
   verdict: `mediatype:(movies OR video OR television)` answered 200 with
   numFound 17,098,672 inside a second (17,105,370 the next day - the count
   is live). **The broken-query half CLOSED 2026-09-16**: the probe's fourth
   leg sent `collection:(librivoxaudio) AND` unsanitized and the site
   answered HTTP 200 with a top-level error, which `axSearchParse` refused
   and quoted verbatim: `Archive.org rejected the query: a token is at an
   unexpected position (group close token ")" at position 32)`. Position 32
   in a 30-character query: the site wraps the query in its own parentheses
   before Solr sees it, which is why a trailing operator reads as a stray
   group close (recorded in `01-archive-api-model.md`). The async path
   closed the same day: the demo's Search button delivered the `search`
   kind through `onArchive` four times across three families, including an
   empty page (`0 of 0`) that rendered as a result, not an error.
6. ~~The metadata endpoint's shape~~, and a missing item. **CLOSED 2026-09-15
   for the raw body**: a GET of `/metadata/gd1977-05-08.sbd.hicks.4982.sbeok.shnf`
   answered HTTP 200 with the body `{}` - the documented missing-item shape,
   live (that identifier is not the show's real one) - and a GET of
   `/metadata/emma_version_5_1002_librivox` answered 200 with 196,716 bytes,
   `Transfer-Encoding: chunked`, opening `{"alternate_locations":{"servers":`
   (a key the fixtures do not carry; harmless to a by-key reader).
   **CLOSED 2026-09-16 through the parser too**: `axFetchItemSync` of the
   same item answered 412 files, mediatype audio, server
   ia800904.us.archive.org, title Emma; and `axFetchItemSync
   no_such_item_archivext_probe` met the `{}` body and refused it with `the
   item could not be found on Archive.org (no metadata block)`. Both
   documented shapes are now observed through the shipped code, not read
   raw.
7. **A real file list through every kind**: ~~a LibriVox book through
   `audio-chapters`~~ **CLOSED 2026-09-16** - `axPlaylist` over the live
   412-file list of `emma_version_5_1002_librivox` gave 58 chapters, the
   first `1 / 01_01 - Volume 1, Chapter 1 / 20:15 / VBR MP3 / 18.54 MB`
   with the stream URL `/download/emma_version_5_1002_librivox/emma_01_austen.mp3`;
   the accept / group / rank / derive / order rules held against sidecars
   and derivative names the mocks never had. Still open: a Grateful Dead
   show through `audio-tracks`, a Prelinger film through `video`, a
   Gutenberg text through `documents` - the demo's item panel (click a
   result) is the leg, and it is also the async `item` kind's first run.
8. **The scrape API** (`axScrapeUrl`): no source app used it, and its body
   shape (`items`, `count`, `cursor`) is from the documentation only. The
   deep-paging walk it exists for is untested end to end.
9. **TLS.** ~~Does `load URL "https://archive.org/..."` work on this engine?~~
   **Answered 2026-09-15, the working direction**: `load URL` and `put URL`
   both reached archive.org over https and carried real bodies back (three
   HTTP 200s, one of them 196 KB chunked; root `docs/OXT-ENGINE-NOTES.md`
   6.9). Still open, and the only thing that can move that entry: does the
   same call against a host with a BAD certificate fail? Record it beside
   6.8 whatever the answer is (see `04-fetch-layer.md`).
10. **Streaming.** Does a player object play an archive.org MP3, per
    platform? The first report (2026-09-16) was "the player is still not
    working" with nothing in the log: a player handed a URL it cannot open
    throws nothing and plays nothing. Two things changed the same day, both
    UNPROVEN until the next run. Play now hands the player the DATANODE URL
    (`axDirectUrl`, the `server` / `dir` the metadata names) rather than
    the `/download/` URL whose 302 a player may not follow, and asks the
    player six seconds later whether it opened the stream (`the duration`
    is 0 when it did not); when it did not, the demo downloads the file
    (item 12) and plays it from disk. The log now records the platform,
    the URL, the format and the duration the player reported - the next
    log will say WHICH of the three (the redirect, https in the player,
    the format) was the wall.

## What is deliberately not built yet

11. **More families.** `any` searches every mediatype with no presets beyond
    the ten mediatype rows; texts, images, software and audio (non-etree)
    could each carry a curated table the way the three app families do.
12. ~~Downloads to disk.~~ **BUILT 2026-09-16** (unproven until its first
    run): `axDownload(pUrl, pPath, pTag)` writes straight to disk through
    `libURLDownloadToFile`, forwards the Internet library's status
    callback as the `progress` kind, re-arms its watchdog on every report
    (a stall watchdog, not a total-time one), and delivers `file` with the
    path; `axDownloadSync` is the blocking form. The demo's Download button
    saves to Documents/ArchiveXT/<identifier>/ and reuses a file already
    there at the promised size; Play falls back to download-and-play. What
    the first run must answer: does `libURLDownloadToFile` follow the
    `/download/` redirect (libURL follows redirects for `load URL`, and
    this is the same library), does the status callback report
    `loading,received,total` on this engine, and does a player open the
    local file.
13. **A result cache.** Every reply is unloaded on handling; an app that
    pages back and forth re-fetches. A small keyed cache with a TTL is
    cheap once the correlation layer is proven.
14. **The full-text and beta search endpoints**, favourites, reviews,
    authentication and upload: out of scope until someone needs them.
15. **The family interpreter folds no array-key case.** The engine does
    (2026-09-15), so `tools/lcs-interp.py` passes code the engine folds; a
    model fix touches every member's execution gate at once and is recorded
    in root `docs/REMAINING-WORK.md` as suite work, not this member's.
16. **A second carrier for the library.** Today the only demo is the
    three-in-one explorer; a minimal "one search box, one list" stack of
    thirty lines would be the better first read for a newcomer, and the
    usage guide's first recipe is written to become it.

## Standing hazards worth re-reading before the pass

- `axSearchParse` trusts `numFound` only as a display number; the end of
  paging is a short page. The demo's Next button disables on a short page,
  not on the count.
- The site's default result order is NOT stable: the same LibriVox query
  answered `emma_1903_librivox` first at 21:12 and
  `emma_version_5_1002_librivox` first at 22:44 on 2026-09-15, with the
  same numFound. Never pin a live identifier from an unsorted search in a
  test; sort, or pin the identifier itself.
- The preset tables are bookmarks: a collection identifier the film club or
  the tape finder chose in 2024 may have been renamed. An empty result from
  a fixed preset is more likely a stale bookmark than a library defect.
- The demo's `adPlayer` is created on demand and named through a variable
  because a `player` is a control type the kit does not build; if the
  control-list gate ever learns to read `create player`, the derived list
  will change and the assertion count line with it.
