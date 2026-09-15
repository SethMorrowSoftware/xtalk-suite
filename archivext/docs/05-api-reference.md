# 05 - Public API Reference (`ax*`)

> **Status: verified statically; needs an OXT pass + a live archive.org
> pass.** The pure layer (every handler from `axVersion` to
> `axPlaylistTable`) is executed on every build through the family's
> headless interpreter against the independent oracle and the synthetic
> fixtures; the fetch layer (`axInit` onward) is engine-only and has no
> engine record. `tools/check-doc-handlers.py` holds this page and the
> shipped handler set in agreement, both directions: a public handler this
> page does not name, or a name here that no handler defines, fails the
> build.

Naming and shapes: public `axPascalCase`. Commands are shown with
space-separated arguments (`axInit pOwner`); functions with parentheses
(`axVersion()`). Multi-valued fields cross this API as LINES, one value per
line. Every function answers empty (or `false` for a predicate) on refusal
and records the reason for `axLastError()`; no handler throws.

## Version, errors, base URL, capabilities

| Handler | Answers |
|---|---|
| `axVersion()` | `ArchiveXT 0.1.0` |
| `axLastError()` | the reason the most recent failing call recorded (empty after a success) |
| `axBaseUrl()` | the base URL every builder prefixes (default `https://archive.org`) |
| `axSetBaseUrl(pUrl)` | sets it; refuses a non-http(s) URL; trailing slash trimmed; empty restores the default. Returns true on acceptance |
| `axProbeCapabilities()` | an array: `hasUrlLib`, `urlLibVersion`, `version`; probed once and cached. Not a claim about https |

## Encoders and text helpers

| Handler | Answers |
|---|---|
| `axLowerAscii(pText)` | ASCII letters folded to lower case, everything else untouched |
| `axUpperFirst(pText)` | the first character upper-cased (the tag-chip capitalisation) |
| `axTrim(pText)` | leading and trailing whitespace removed |
| `axCollapseSpaces(pText)` | runs of whitespace to one space, trimmed |
| `axUrlEncode(pText)` | `encodeURIComponent`: letters, digits and `-_.!~*'()` kept, everything else `%XX` over UTF-8 bytes |
| `axUrlEncodePath(pPath)` | a `/`-separated path with each segment through `axUrlEncode` |
| `axQueryEncode(pText)` | `URLSearchParams` form encoding: letters, digits and `*-._` kept, space to `+` |
| `axIsHttpUrl(pText)` | true for `http://` or `https://` followed by something |
| `axStrEq(pA, pB)` | byte-exact equality (`is` folds case) |

## Identifiers, years, durations, sizes, natural order, multi-values

| Handler | Answers |
|---|---|
| `axIdentifierIsValid(pText)` | true for 1-100 ASCII letters, digits, `_.-`, starting with a letter or digit |
| `axYearOf(pText)` | the first run of EXACTLY four digits, or empty |
| `axNormalizeYear(pText)` | a trimmed four-digit year in 1000-9999, or empty |
| `axDurationSeconds(pLength)` | seconds from `600.12`, `12:34` or `1:02:03`; empty for anything else |
| `axFormatTime(pSeconds)` | `m:ss` or `h:mm:ss`; empty for a non-number |
| `axFormatBytes(pBytes)` | `B` / `KB` / `MB` / `GB` / `TB`, one decimal above KB; empty for a non-number |
| `axNaturalKey(pText)` | the sort key: digit runs zero-padded to twelve places, letters lower-cased |
| `axNaturalSort(pLines)` | the lines in natural order |
| `axFirst(pValue)` | the first line of a multi-valued field (the value itself when scalar) |
| `axJoin(pValue, pSeparator)` | the lines joined with the separator |
| `axTrackNumber(pText)` | the leading integer of a track field (`4/5` is 4; `n/a` is empty) |

## The query grammar

| Handler | Answers |
|---|---|
| `axQuerySanitize(pText, pAllowFieldSyntax)` | user text made safe for Lucene: plain mode blanks `{}[]^~:/` and the backslash, drops unbound `- + !`, `&&`, `\|\|`, unbalanced quotes and parentheses, and UPPER-CASE operators that cannot bind; field mode keeps the colon, brackets, caret and tilde (`02-search-and-query.md`) |
| `axQueryClause(pField, pValue)` | `field:(value)`, trimmed |
| `axQueryPhrase(pField, pText)` | `field:("text")`, inner quotes stripped |
| `axQueryRange(pField, pFrom, pTo)` | `field:[from TO to]` |
| `axQueryYears(pFrom, pTo)` | a `year:` range that tolerates one end, swapped ends and non-years; empty when neither end is a year |
| `axQueryBuild(pSpec)` | the whole `q` from an array with keys `base`, `text`, `textField`, `fieldSyntax`, `yearFrom`, `yearTo`, `filters` (lines), `plainText`; empty when nothing is left to search for |
| `axPublicDomainClause()` | the film club's `licenseurl:` OR-list, built with `quote` |

## Families, presets, quick filters, sorts

| Handler | Answers |
|---|---|
| `axFamilyList()` | `id\|title` lines: `etree`, `librivox`, `movies`, `any` |
| `axFamilyInfo(pFamily)` | an array: `id`, `title`, `kind` (the playlist kind), `scope`, `rows`, `fields`, `sort`; empty for an unknown family |
| `axFamilyScope(pFamily)` | the scope clause alone |
| `axVideoCollections()` | the film club's 26 collection identifiers, one per line |
| `axVideoScope()` | `(mediatype:(movies OR video OR television) OR (mediatype:collection AND identifier:(...)))` |
| `axPresetTable(pFamily)` | every preset as `id\|title\|group\|query\|mode\|yearFrom\|yearTo` lines, `#` already swapped for `quote` |
| `axPresetList(pFamily)` | `id\|title` lines, table order |
| `axPresetInfo(pFamily, pId)` | one row as an array with those seven keys; empty for an unknown id |
| `axPresetQuery(pFamily, pId)` | a fixed preset's full query; empty for a mode preset (it needs text) |
| `axPresetSpec(pFamily, pId, pText, pYearFrom, pYearTo, pFilters)` | the `axQueryBuild` spec for this preset, text, years and filter ids (a comma list): each app's search-box logic in one call |
| `axFilterList(pFamily)` | the quick filters as `id\|label\|clause` lines |
| `axFilterClause(pFamily, pId)` | one clause; empty for an unknown id |
| `axFilterClauses(pFamily, pIds)` | the clauses of a comma list of ids, one per line, unknown ids dropped |
| `axSortList()` | the sort menu as `id\|label\|clause` lines (`relevance` has an empty clause) |
| `axSortClause(pId)` | the clause for a menu id; a clause-shaped id (`year asc`) passes through; else `downloads desc` |

## URL builders

Every builder validates its identifier with `axIdentifierIsValid` and
prefixes `axBaseUrl()`.

| Handler | Answers |
|---|---|
| `axSearchUrl(pQuery, pFields, pSort, pRows, pPage)` | advancedsearch.php with `q`, one `fl[]` per comma-listed field, `sort[]` when given, `rows` (default 24), 1-based `page` (default 1), `output=json`; refuses an empty query, non-numeric rows or page, a page below 1 |
| `axScrapeUrl(pQuery, pFields, pCount, pCursor)` | services/search/v1/scrape with `q`, `fields`, `count` (default 100) and the previous page's `cursor` |
| `axMetadataUrl(pIdentifier)` | `/metadata/<identifier>` |
| `axDownloadUrl(pIdentifier, pFileName)` | `/download/<identifier>/<encoded file name>` (the item's directory listing when the name is empty) |
| `axThumbnailUrl(pIdentifier)` | `/services/img/<identifier>` |
| `axDetailsUrl(pIdentifier)` | `/details/<identifier>` |
| `axEmbedUrl(pIdentifier)` | `/embed/<identifier>` |

## The JSON reader

Owned, because the engine's `JSONToArray` is not in every build and a
reader that runs headlessly has to be script. Documents are HANDLES
(integers from 1) over a script-level table; object keys are looked up
exactly (case-sensitive); a duplicate key keeps its first value; numbers
are stored as their text; a path is `/`-separated with 1-based indices into
arrays (`response/docs/3/title`).

| Handler | Answers |
|---|---|
| `axJsonParse(pJson)` | a document handle, or empty with the reason (truncated document, unterminated string, unknown escape, lone surrogate, trailing bytes, mixed-case literal, a number outside the RFC 8259 grammar, depth over 64) |
| `axJsonFree pHandle` | drops one document; unknown handle is a no-op |
| `axJsonFreeAll` | drops every document |
| `axJsonHandleIsLive(pHandle)` | true while the handle names a parsed document |
| `axJsonType(pHandle, pPath)` | `object`, `array`, `string`, `number`, `boolean`, `null`, or `missing` |
| `axJsonGet(pHandle, pPath)` | the scalar at the path (strings decoded, numbers as text, booleans `true` / `false`, null and a miss both empty); a container answers its VERBATIM source slice |
| `axJsonCount(pHandle, pPath)` | the child count of a container (0 otherwise) |
| `axJsonKeys(pHandle, pPath)` | an object's keys, one per line, source order |
| `axJsonValues(pHandle, pPath)` | the value as LINES: a scalar is one line, an array of scalars one line each (the field rule every parser applies) |
| `axUtf8Bytes(pCode)` | the UTF-8 bytes of a code point (the string decoder's escape path) |

## Response parsers

| Handler | Answers |
|---|---|
| `axSearchParse(pJson)` | an array: `numFound`, `start`, `count`, `docs[i][field]` as lines; refuses the site's HTTP-200 `error` shape with its message, and a body with no `response.docs` |
| `axItemParse(pJson)` | an array: `identifier`, `metadata[field]` as lines, `files[i][field]` as lines, `filesCount`, `itemSize`, `server`, `dir`; a `{}` body refuses as "could not be found" |
| `axDocsTable(pResult, pFields)` | a search result as tab-separated lines for a table field, first value of each comma-listed field |

## Files to playlists

| Handler | Answers |
|---|---|
| `axFileExtension(pName)` | the lower-cased extension without the dot |
| `axFileIsAudio(pFile)` | true for a playable audio file (a file array from `axItemParse`, or a name) |
| `axFileIsVideo(pFile)` | true for a playable video file that is not a sentinel |
| `axFileIsDocument(pFile)` | true for pdf, epub, djvu, txt and the other readable formats |
| `axFileIsImage(pFile)` | true for an image file that is not a thumbnail sidecar |
| `axFileIsContent(pFile)` | true for anything that is not a metadata sidecar, torrent or placeholder |
| `axFileStem(pName)` | the AudioBooks chapter stem: lower-cased, extension and `_64kb` / `_vbr` / `_orig` / `_original` dropped |
| `axVideoStem(pName)` | the film club's `normalizeBaseName`: extension, resolution and encode suffixes stripped until stable |
| `axPrettyName(pName)` | the stem with underscores as spaces, as a fallback title |
| `axTrackTitleClean(pTitle)` | a `d1t01` / `t05` prefix removed, separators to spaces, whitespace collapsed |
| `axCleanTitle(pName, pItemTitle)` | the film club's `getCleanTitle`; `Untitled` when nothing is left |
| `axQualityLabel(pName)` | `1080p` / `720p` / `480p` / `360p` / `H.264` / `SD` / `Archive` / `Auto` |
| `axSubjectTags(pSubject, pMax)` | the first N tag chips from a subject field (lines, `;` or `\|` separated), noise words and long tags dropped |
| `axPlaylistKindFor(pFamily, pMediatype)` | `audio-tracks`, `audio-chapters`, `video`, `documents`, `images` or `files` |
| `axPlaylist(pItem, pKind)` | the playable list: `count`, `kind`, `entries[i]` with `name`, `title`, `track`, `length`, `format`, `size`, `url`, `stem`, `index`, and for video `quality` + `variants` (`name\|label\|size\|format` lines, best first); `auto` picks the kind from the item; empty with a reason when the item has no file of that kind |
| `axPlaylistTable(pPlaylist)` | tab-separated lines: number, title, duration, format, human size, quality for video |

## The fetch layer (engine only)

| Handler | Does |
|---|---|
| `axInit pOwner` | the object callbacks dispatch to (a long id); empty means the topStack at delivery. Fills the defaults; may be called again to move the callbacks |
| `axSetCallback pHandlerName` | the handler dispatched for every outcome (default `onArchive`; empty restores it) |
| `axSetTimeout pSeconds` | seconds before an outstanding request is reported as `timeout` (default 30; under 1 or a non-number keeps the current setting) |
| `axSetMaxBody pBytes` | the largest reply parsed (default 16 MB; under 1024 keeps the current setting) |
| `axPending()` | how many requests are in flight |
| `axSearch(pQuery, pOptions)` | starts a search; options `fields`, `sort`, `rows`, `page`, `tag`; returns the handle, or empty when the URL cannot be built. Delivers `"search"` |
| `axFetchItem(pIdentifier, pTag)` | starts a metadata fetch. Delivers `"item"` |
| `axFetchUrl(pUrl, pTag)` | starts a raw fetch of any http(s) URL. Delivers `"raw"` |
| `axCancel pHandle` | forgets a request (the engine's load still completes and is dropped as a late reply); unknown handle is a no-op |
| `axCancelAll` | forgets every request |
| `axShutdown` | forgets everything and drops the owner; safe twice |
| `axUrlDone pUrl, pStatus` | the engine's URL callback (`cached` on success); public because the engine delivers it by name, never called by an app |
| `axDeadline pHandle` | the per-request watchdog the layer arms with `send ... in`; public for the same reason; unknown handle is a no-op |
| `axGetSync(pUrl)` | BLOCKING: the body of an http(s) URL, or empty with the reason |
| `axSearchSync(pQuery, pOptions)` | BLOCKING: `axSearch` and `axSearchParse` in one call |
| `axFetchItemSync(pIdentifier)` | BLOCKING: `axFetchItem` and `axItemParse` in one call |

The callback contract: `onArchive pHandle, pKind, pValue, pTag` with `pKind`
one of `search`, `item`, `raw`, `error`; exactly one call per handle. Pin
the defaultStack first inside it (`04-fetch-layer.md`).
