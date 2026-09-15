# 02 - Search and the query grammar

> **Status: verified statically; needs a live archive.org pass.** Every
> function on this page is pure and is executed on every build against the
> oracle: the sanitizer over 38 vectors in both modes, the builders over the
> AudioBooks app's own test cases, the preset / filter / sort tables against
> a second transcription. What no build can check is whether archive.org's
> Solr still parses what the grammar produces; the three apps' users did,
> daily, and the first live pass re-confirms it here.

## The grammar

archive.org's advanced search speaks Lucene, and every one of the three apps
built its `q` by string concatenation: a scope, an optional preset clause,
the user's text, a year range and the quick-filter clauses, joined with
` AND `. ArchiveXT is that grammar as functions:

| Function | Produces |
|---|---|
| `axQueryClause("collection", " Phish ")` | `collection:(Phish)` |
| `axQueryPhrase("creator", "Jane Austen")` | `creator:("Jane Austen")` (inner quotes stripped) |
| `axQueryRange("year", 1965, 1995)` | `year:[1965 TO 1995]` |
| `axQueryYears("1965", "1995")` | the same, but tolerant: one end, swapped ends, non-years |
| `axPublicDomainClause()` | the film club's three-spelling `licenseurl:` OR-list |
| `axQueryBuild(tSpec)` | the whole `q` from one array (below) |

`axQueryBuild` takes an array:

| Key | Meaning |
|---|---|
| `base` | the scope or preset query this search starts from |
| `text` | the user's text, SANITIZED here |
| `textField` | empty: appended as ` AND (text)`; a field name: appended as ` AND field:(text)` (the author / title / collection search modes) |
| `fieldSyntax` | true lets the text carry field syntax (the Custom modes) |
| `yearFrom`, `yearTo` | the year range, through `axQueryYears` |
| `filters` | ready clauses, one per line, each appended with AND |
| `plainText` | true: the film club rule instead of the sanitizer - strip `: " ( )` and wrap in parentheses |

It answers empty, with the reason, when nothing at all is left to search for.

## The sanitizer

The one user-input safety layer any of the three apps had, restated over
tokens (`axQuerySanitize`). It exists because a Lucene parse error comes back
as HTTP 200 with a Solr stack trace, so a stray `(` or a trailing `AND` from
a user is a visible failure. In PLAIN mode (`pAllowFieldSyntax` false):

- the characters `{ } [ ] ^ ~ : / and the backslash` are blanked (a colon
  would start a field search; a tilde a fuzzy one);
- a `-`, `+` or `!` that is not inside a word is dropped (leading `-austen`
  would negate);
- `&&` and `||` become spaces;
- an unbalanced double quote is dropped, and so is an unbalanced parenthesis
  run;
- the Lucene operators `AND`, `OR`, `NOT` (UPPER-CASE only: "Pride and
  Prejudice" is a phrase, "Pride AND Prejudice" a query) are dropped where
  they cannot bind - leading, trailing, doubled, or against a parenthesis;
- whitespace collapses; an empty result stays empty.

In FIELD mode (`pAllowFieldSyntax` true) the colon, the range brackets, the
boost caret and the fuzzy tilde survive, so `creator:austen AND title:emma`
or `year:[1800 TO 1850]` pass through, while the balance rules still apply
(`year:[1800 TO` loses its bracket).

The 38 vectors the gate drives through both modes are the AudioBooks app's
own test cases plus the edge cases the port found; `tools/check-script-
vectors.py` lists them in `SANITIZE_VECTORS`.

## Scopes, families and presets

A FAMILY's scope is the clause every search in it carries
(`axFamilyScope`): `mediatype:(etree)`, `collection:(librivoxaudio)`, the
film club's video scope, or nothing for `any`. The video scope is the film
club's `videoQuery` half: three mediatypes OR-ed with 26 collection
identifiers as a `mediatype:collection AND identifier:(...)` sub-clause
(`axVideoScope`; the 26 are `axVideoCollections`), which is why a search in
the movies family can return a COLLECTION doc among the films - the demo
shows its `num_items` for that case.

A PRESET is a row of the family's table (`axPresetTable`, one `|`-separated
row per line; `axPresetList` for the id and title lines; `axPresetInfo` for
one row as an array):

| Column | Meaning |
|---|---|
| `id`, `title`, `group` | the menu entry and the heading it sits under |
| `query` | the full Lucene query for a fixed preset, scope included |
| `mode` | empty for a fixed preset; `collection`, `creator` or `title` for the search modes that put the user's text into THAT field over the family scope; `custom` for the modes that let the text carry field syntax |
| `yearFrom`, `yearTo` | a default year range some presets carry (the tape finder's Grateful Dead 1965-1995) |

Inside the table source a `#` stands for a double quote (an xTalk literal
cannot hold one) and is swapped for `quote` on the way out, which is why a
preset such as Bob Weir's (`creator:("Bob Weir") -creator:("Bob Weir and
Ratdog")`) is pinned in the harness as hex.

`axPresetSpec(pFamily, pId, pText, pYearFrom, pYearTo, pFilters)` is the whole
of each app's search-box logic in one call: a fixed preset's query becomes
the base and the text is appended; a mode preset uses the scope as the base
and routes the text into its field; the movies family uses the plain
strip-and-wrap text rule; a preset's default year range applies only when
the caller gave no year at all (the tape finder fills its year boxes from
it, so a user who cleared them searched every year). `axPresetQuery` is the
shortcut for a fixed preset with no text.

The counts, for orientation (the KAT pins them; the gate is the authority):
etree 49, librivox 40, movies 26, any 10. A preset is a query somebody
chose, and the collections it names can go stale the way any bookmark does.

## Quick filters and sorts

`axFilterList(pFamily)` answers `id|label|clause` lines: the tape finder's
four (`soundboard`, `aud`, `matrix`, `five-star`), the AudioBooks three
(`solo`, `complete`, `english`), the film club's `publicdomain`.
`axFilterClauses(pFamily, "soundboard,five-star")` turns a comma list of ids
into the `filters` lines a spec wants, dropping unknown ids silently (the
AudioBooks rule).

`axSortList()` is the film club's sort menu plus the plain date sort its
server used, as `id|label|clause` lines; `axSortClause(pId)` answers the
clause, passes a clause-shaped id (`year asc`) through, and falls back to
`downloads desc`. `relevance` is an empty clause, which `axSearchUrl` turns
into no sort parameter at all.

## Paging

`axSearchUrl(pQuery, pFields, pSort, pRows, pPage)` pages 1-based, `rows` per
page (default 24). Remember the over-reporting count from
`01-archive-api-model.md`: the end of the results is a page shorter than
`rows`, not `start + count >= numFound`. For a walk over a whole collection
use `axScrapeUrl` with the cursor the previous page returned - the search
API stops paging past its first 10,000 hits; the scrape API is untested
against the site (no source app used it) and is the first thing the live
pass should try after the search itself.
