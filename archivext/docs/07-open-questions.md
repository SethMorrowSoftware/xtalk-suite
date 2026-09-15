# 07 - Open questions

> **Status: this is the to-do list.** Every item is open as of 2026-09-15,
> the day the member landed. Strike items in place as they close, with the
> date and where the evidence went.

## What the first ENGINE pass must answer (no network needed)

1. **Does the fold compile?** `tests/suite-selftest.livecodescript` carries
   the member harness as `ax1*` and the library verbatim. One bad line takes
   the whole paste (root `CLAUDE.md`, the `dcCleanup()` lesson), and this
   member's 4200 lines have met only the interpreter's subset of the
   language. The things most likely to differ from the interpreter: the
   `byteOffset` skip argument (added to the interpreter for this member, so
   the model is new), `sort lines of` over the rank keys, `the keys of` on a
   nested array, and `replace "#" with quote in tT`.
2. **Does `ax1axSelfTest` report readably**, and what does the fetch section
   SKIP on this engine? Copy the `ArchiveXT` line of the per-member table and
   every red line verbatim into `CLAUDE.md`'s as-built notes; that measured
   floor replaces the placeholder floor 1 at the core's
   `stMergeReturned "ArchiveXT"` call site.
3. **Does the demo boot?** `examples/archivext-demo.livecodescript` prints
   its own boot self-check (46 controls, the preset table, the vector-derived
   search URL, the etree fixture as six tracks). A red line there is the
   record; a FAIL on the control list is the kind of defect the carried block
   has found before (root `CLAUDE.md`, the `scMissing` widening).
4. **Does the JSON reader agree with the engine about UTF-8?** `axUtf8Bytes`
   builds the bytes of a code point by hand and the reader decodes them with
   `textDecode`; the librivox fixture's chapter 3 title carries a `&`, HTML
   tags and quotes, and the KAT pins it as hex. A non-BMP surrogate pair in a
   real title is the case the fixtures do not carry.

## What the first LIVE pass must answer

5. **The search endpoint's shape today.** `axSearchSync` from the message
   box against a LibriVox query: does `numFound` / `start` / `docs` still
   arrive as the fixtures assume, and does a deliberately broken query
   (`austen AND`, unsanitized) still come back as HTTP 200 with a top-level
   `error`? Record the exact body.
6. **The metadata endpoint's shape**, and a missing item: `axFetchItemSync
   "no_such_item_xyz"` should answer empty with the "could not be found"
   reason from a `{}` body.
7. **A real file list through every kind**: a Grateful Dead show through
   `audio-tracks`, a LibriVox book through `audio-chapters`, a Prelinger film
   through `video`, a Gutenberg text through `documents`. The fixtures were
   SHAPED from the apps' mocks; a real list is where the ranking rules meet
   sidecars and derivative names the mocks do not have.
8. **The scrape API** (`axScrapeUrl`): no source app used it, and its body
   shape (`items`, `count`, `cursor`) is from the documentation only. The
   deep-paging walk it exists for is untested end to end.
9. **TLS.** Does `load URL "https://archive.org/..."` work on this engine and
   platform, and does the same call against a host with a bad certificate
   FAIL? Both directions, recorded in root `docs/OXT-ENGINE-NOTES.md` 6.8
   whatever the answer is (see `04-fetch-layer.md`).
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
15. **A second carrier for the library.** Today the only demo is the
    three-in-one explorer; a minimal "one search box, one list" stack of
    thirty lines would be the better first read for a newcomer, and the
    usage guide's first recipe is written to become it.

## Standing hazards worth re-reading before the pass

- `axSearchParse` trusts `numFound` only as a display number; the end of
  paging is a short page. The demo's Next button disables on a short page,
  not on the count.
- The preset tables are bookmarks: a collection identifier the film club or
  the tape finder chose in 2024 may have been renamed. An empty result from
  a fixed preset is more likely a stale bookmark than a library defect.
- The demo's `adPlayer` is created on demand and named through a variable
  because a `player` is a control type the kit does not build; if the
  control-list gate ever learns to read `create player`, the derived list
  will change and the assertion count line with it.
