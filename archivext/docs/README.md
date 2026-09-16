# ArchiveXT documentation

ArchiveXT is archive.org in pure LiveCodeScript: the search, metadata,
download and image APIs, a query grammar with a sanitizer, the preset
catalogues three shipped web apps accumulated, and the rules that turn an
item's file list into a playlist.

These docs are a NUMBERED SERIES, readable in order: 00-01 orient you, 02-04
are the layer specs, 05 is the API, and 06 is the from-zero guide.
**If you just want to use it, jump to [06-usage-guide.md](06-usage-guide.md).**

**Read the STATUS block at the top of each page.** The whole member carries
"verified statically; needs an OXT pass + a live archive.org pass". The pure
layer is executed headlessly against an independent oracle on every build;
the fixtures it runs over are synthetic, and the fetch layer has no engine
record yet.

| Document | What it is |
|---|---|
| [00-overview.md](00-overview.md) | Overview and architecture, plus the member's honesty status in one place. |
| [01-archive-api-model.md](01-archive-api-model.md) | What archive.org actually offers: the four public surfaces, their quirks (HTTP 200 errors, an over-reporting numFound, a missing item as an empty body), identifiers, and the three apps this member was read from. |
| [02-search-and-query.md](02-search-and-query.md) | The Lucene query grammar as functions: the sanitizer (both modes), scopes, presets, year ranges, quick filters, sorts, and the exact bytes of the search URL. |
| [03-items-files-and-playlists.md](03-items-files-and-playlists.md) | From an item's raw file list to something playable: the accept / group / rank / derive / order engine, one kind per family, and every place the three apps disagreed. |
| [04-fetch-layer.md](04-fetch-layer.md) | The asynchronous request layer over the engine's Internet library: handles, the callback contract, the watchdog, the body cap, the late-reply drop, and the open TLS question. |
| [05-api-reference.md](05-api-reference.md) | The public surface, handler by handler. `tools/check-doc-handlers.py` holds this page and the shipped handler set in agreement, both directions. |
| [06-usage-guide.md](06-usage-guide.md) | From zero to a playing stream: task-oriented recipes in the order an app grows. The page most readers want. |
| [07-open-questions.md](07-open-questions.md) | The numbered to-do list: what the first engine pass and the first live pass must answer, and what is deliberately not built yet. |

**Where else to look.** [`../README.md`](../README.md) is the member front door
(what it is, quick start, the honest status). [`../CLAUDE.md`](../CLAUDE.md) is
maintainer memory: the as-built record, the gotchas, and why each decision went
the way it did. [`../IMPLEMENTATION-PLAN.md`](../IMPLEMENTATION-PLAN.md) is the
phased plan with each phase's status. Suite-wide documents that span more than
one member live in [`../../docs/`](../../docs/README.md), indexed there by kind.
