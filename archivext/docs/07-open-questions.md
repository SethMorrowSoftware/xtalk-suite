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
3. **Does the demo boot?** `examples/archivext-demo.livecodescript` prints
   its own boot self-check (47 controls, the preset table, the vector-derived
   search URL, the etree fixture as six tracks). A red line there is the
   record; a FAIL on the control list is the kind of defect the carried block
   has found before (root `CLAUDE.md`, the `scMissing` widening).
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
   numFound 17,098,672 inside a second. Still open from this item: a
   deliberately broken query (`collection:(librivoxaudio) AND`, sent
   unsanitized) coming back as HTTP 200 with a top-level `error` - the
   probe's fourth leg sends exactly that and logs `axLastError`, which
   quotes the site. Record the exact text.
6. ~~The metadata endpoint's shape~~, and a missing item. **CLOSED 2026-09-15
   for the raw body**: a GET of `/metadata/gd1977-05-08.sbd.hicks.4982.sbeok.shnf`
   answered HTTP 200 with the body `{}` - the documented missing-item shape,
   live (that identifier is not the show's real one) - and a GET of
   `/metadata/emma_version_5_1002_librivox` answered 200 with 196,716 bytes,
   `Transfer-Encoding: chunked`, opening `{"alternate_locations":{"servers":`
   (a key the fixtures do not carry; harmless to a by-key reader). Still
   open: that body has not been through `axItemParse` - the probe's second
   leg now calls `axFetchItemSync` and builds the item's playlist, which is
   item 7's LibriVox kind as well; and the `{}` shape has not yet been seen
   by `axFetchItemSync` (the fifth leg, `no_such_item_archivext_probe`).
7. **A real file list through every kind**: a Grateful Dead show through
   `audio-tracks`, a LibriVox book through `audio-chapters`, a Prelinger film
   through `video`, a Gutenberg text through `documents`. The fixtures were
   SHAPED from the apps' mocks; a real list is where the ranking rules meet
   sidecars and derivative names the mocks do not have.
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
10. **Streaming.** Does a player object play an `axDownloadUrl` MP3 through
    the datanode redirect, per platform? The demo's Play button is the test;
    its fallback is `launch URL`.

## What is deliberately not built yet

11. **More families.** `any` searches every mediatype with no presets beyond
    the ten mediatype rows; texts, images, software and audio (non-etree)
    could each carry a curated table the way the three app families do.
12. **Downloads to disk.** A background download with progress (`load URL`
    with a progress message, then a file write) is an app concern today;
    a `axDownloadFile`-shaped helper is a natural next handler once the
    fetch layer has an engine record.
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
