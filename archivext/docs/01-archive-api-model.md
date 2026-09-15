# 01 - The archive.org API model

> **Status: verified statically; the first live archive.org pass ran
> 2026-09-15 and re-observed the two main shapes.** Everything on this page
> about the site's behaviour comes from its public documentation and from
> what the three source apps handle in their code and their tests - the
> over-reporting count, the HTTP-200 error, the empty-body missing item.
> None of it had been re-observed against the live site from this tree
> (the build sandbox cannot reach it) until the demo's Live probe ran on the
> user's engine: the search shape (`response` / `numFound` / `docs`) arrived
> as written, twice; a real `/metadata/` body arrived whole (196,716 bytes,
> chunked, opening with an `alternate_locations` block the table below does
> not list - the parser reads by key, so order and extra keys cost nothing);
> and a GET of a non-existent identifier answered HTTP 200 with the body
> `{}`, the documented missing-item shape. Still to re-observe: the HTTP-200
> Solr error for a broken query, the over-reporting count at the end of a
> paged walk, the scrape API's shape, and the datanode redirect on a
> download URL. The Live probe's legs 4 and 5 are the first two.

## The four surfaces

Every archive.org web client is built from the same four public endpoints,
and ArchiveXT builds every one of them from a validated identifier and a
configurable base (`axBaseUrl`, default `https://archive.org`, changeable
with `axSetBaseUrl` for a mirror or a test server):

| Surface | URL | Builder | Answers |
|---|---|---|---|
| Advanced search | `/advancedsearch.php?q=...&fl[]=...&sort[]=...&rows=N&page=P&output=json` | `axSearchUrl` | `{"response":{"numFound":N,"start":S,"docs":[...]}}` |
| Scrape (deep paging) | `/services/search/v1/scrape?q=...&fields=...&count=N&cursor=...` | `axScrapeUrl` | `{"items":[...],"count":N,"cursor":"..."}` |
| Item metadata | `/metadata/<identifier>` | `axMetadataUrl` | `{"metadata":{...},"files":[...],"item_size":N,"server":...,"dir":...}` |
| File download / stream | `/download/<identifier>/<file name>` | `axDownloadUrl` | the bytes (a redirect to a datanode first) |
| Item image | `/services/img/<identifier>` | `axThumbnailUrl` | a JPEG |
| Details page | `/details/<identifier>` | `axDetailsUrl` | the site's HTML page (for `launch URL`) |
| Embed player | `/embed/<identifier>` | `axEmbedUrl` | the site's player (for a browser object) |

The search URL's bytes are pinned to the AudioBooks app's exactly (its tests
assert them): `fl[]` is form-encoded to `fl%5B%5D`, repeated once per field,
`sort[]` appears only when a sort is given, the query goes through
form encoding (space to `+`, `*-._` spared), and `output=json` closes it.
The download and metadata paths encode each segment the way
`encodeURIComponent` does (`-_.!~*'()` spared, space to `%20`), so a file
named `a b#1.mp3` becomes `a%20b%231.mp3`.

## Identifiers

An item identifier is the site's primary key. ArchiveXT accepts what the
site accepts (`axIdentifierIsValid`): 1 to 100 characters of ASCII letters,
digits, `_`, `.` and `-`, starting with a letter or digit. Anything else -
an empty value, a path traversal, a space, a tag - is refused BEFORE a URL is
built, and the refusal names the reason. A validated identifier never needs
encoding, which is why the item URLs are byte-simple.

## The quirks the apps handle, and ArchiveXT handles

1. **A malformed query is HTTP 200.** advancedsearch.php answers a Lucene
   parse error with a 200 and a top-level `"error"` string carrying Solr's
   message. `axSearchParse` checks for that key before anything else and
   refuses with `Archive.org rejected the query: ...`. This is why the
   sanitizer exists (`02-search-and-query.md`): an unguarded app shows the
   user a stack trace.
2. **numFound over-reports.** The site's count is an estimate that the paging
   will not deliver in full; a page shorter than `rows` is the end. Apps that
   trusted the count showed empty pages. `axSearchParse` hands back
   `numFound`, `start` and `count` and lets the app apply the rule.
3. **A missing item is `{}`.** The metadata API answers an unknown identifier
   with HTTP 200 and an empty object. The absence of the `metadata` block is
   the only signal, and `axItemParse` turns it into a "could not be found"
   refusal.
4. **Fields are scalar OR array.** `creator` is a string on one item and an
   array on the next; `subject` is a string, an array, or a `;`-separated
   string. ArchiveXT reads every field as LINES (one value per line, the
   AudioBooks `asList` rule), so a scalar and a one-element array read the
   same, and `axFirst` / `axJoin` are the two spellings an app needs.
5. **Search and metadata disagree about the same field.** A doc's `year` may
   be missing where its `date` is present, and a metadata block's `date` may
   be `1977-05-08T00:00:00Z`, `05/08/1977` or `c. 1900`. `axYearOf` takes the
   first run of EXACTLY four digits (the PHP app's `/(\d{4})/` would take the
   first four of a longer run - a deliberate correction, recorded in the
   oracle).
6. **Durations come in three spellings.** `length` is `600.12`, `12:34` or
   `1:02:03`; `axDurationSeconds` reads all three and refuses anything else.
7. **The file list mixes everything.** Originals, the site's own derivatives
   of each original (`_vbr.mp3`, `_64kb.mp3`, `_512kb.mp4`), thumbnails,
   spectrograms, `_meta.xml` / `_files.xml` sidecars, torrents and `.ia`
   placeholders share one array. `03-items-files-and-playlists.md` is the
   rule that finds the playable ones.

## The three source apps

| App | Stack | What it is |
|---|---|---|
| Grateful Dead Tape Finder | PHP proxy + vanilla JS | band presets over the Live Music Archive, SBD / AUD / matrix filters, year ranges, a show's track list with a player |
| AudioBooks | Node/Express + vanilla JS | LibriVox categories, author / title search, a book's chapters grouped from the file list, a queue |
| Archive Film Club | React | the Moving Image Archive's collections, a series' episodes with quality variants, a sort menu, public-domain filtering |

ArchiveXT was written from their code and their tests, not from the site.
Where they disagree, `03-items-files-and-playlists.md` records the choice;
where one of them had something the others lacked (the AudioBooks
sanitizer, the film club's scope OR-list, the tape finder's year ranges),
the library carries it for every family.

## What is deliberately not modelled

- **Authentication and upload** (the S3-like API, logged-in metadata
  writes): out of scope; nothing here sends credentials.
- **The full-text search API** and the `/services/search/beta` endpoints:
  not used by any of the three apps; `axScrapeUrl` is the one endpoint added
  beyond them, for deep paging, and it is untested against the site.
- **Datanode redirects.** A download URL answers a redirect to a datanode;
  the engine's URL library follows it. ArchiveXT never builds a datanode URL
  itself (`server` and `dir` from the metadata block are handed back,
  unused).
