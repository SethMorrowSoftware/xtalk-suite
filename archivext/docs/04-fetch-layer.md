# 04 - The fetch layer

> **Status: verified statically; needs an OXT pass + a live archive.org
> pass.** The fetch layer (`axInit` to the end of the file) has no engine
> record. It uses `load URL ... with message`, `URL x` after a `cached`
> status, `unload URL`, `libURLSetCustomHTTPHeaders` and `libURLErrorData`
> in the same shapes two shipped stacks in this suite use (nocloud's
> public-IP probe, coin-wallet's Esplora transport), and neither of those
> has an engine record for them yet either. The harness reaches every fetch
> handler through a refusal path only; no request is ever started offline.

## Why a layer at all

`put URL x` blocks the one interpreter thread, which on a slow or
unreachable host freezes the whole window (the coin-wallet lesson). So
every request here is `load URL ... with message "axUrlDone"`, and the
answer comes back through the message path. What the layer adds over a bare
`load URL`, each paid for by one of the source apps:

| Mechanism | What it does | Why |
|---|---|---|
| CORRELATION | a request is an integer handle; the reply is matched to it by the URL the engine hands back | a reply nobody is waiting for (a cancelled or timed-out request - the engine cannot cancel a load) is unloaded and dropped, never applied to whatever is in flight now |
| A WATCHDOG | `axDeadline` fires per request after `axSetTimeout` seconds (default 30), reports `timeout`, forgets the handle | `load URL` has no deadline of its own |
| A BODY CAP | `axSetMaxBody` (default 16 MB) stops the PARSE of an over-size reply | the whole body is read before this layer sees it, so the cap cannot stop the read; it still keeps a wrong-shaped reply out of a 300 KB JSON parse |
| UNLOAD ALWAYS | every path through `axUrlDone` unloads the URL | the URL cache grows without limit otherwise |
| A USER AGENT | `libURLSetCustomHTTPHeaders` sends `ArchiveXT/<version> (xTalk suite; <repo>)` | be an identifiable client |

## The callback contract

```
axInit the long id of this stack       -- where callbacks are dispatched (empty: the topStack)
axSetCallback "onArchive"              -- the handler name (default onArchive)

put axSearch(tQuery, tOptions) into tHandle       -- onArchive h, "search", tResult, tag
put axFetchItem(tIdentifier, tTag) into tHandle   -- onArchive h, "item",   tItem,   tag
put axFetchUrl(tUrl, tTag) into tHandle           -- onArchive h, "raw",    tBody,   tag
                                                  -- onArchive h, "error",  tReason, tag  (any failure)
```

`axSearch` takes an optional options array: `fields` (comma list), `sort`
(a clause), `rows`, `page`, `tag` (echoed back untouched). Each starter
returns the handle, or empty with the reason when the URL cannot be built
(an empty query, a bad identifier, a non-http URL, a non-numeric page) -
those refusals happen BEFORE anything is loaded, which is what the offline
harness section drives.

Exactly one callback per handle. `tResult` is an `axSearchParse` array,
`tItem` an `axItemParse` array, `tBody` the raw bytes; on `"error"` the
value is the reason (`timeout`, the engine's `libURLErrorData` text, the
site's own rejection, a body over the cap, a parse failure) and
`axLastError()` carries it too.

**Pin the defaultStack first.** The callback is reached from an ENGINE
callback or a timer, so an unqualified control reference inside it resolves
against the defaultStack, not the stack whose script is running (root
`docs/OXT-ENGINE-NOTES.md` 5.3). The suite's `tools/check-timer-stack-pin.py`
knows `axSetCallback` as a registrar and requires the pin in every
registered handler, so a demo that forgets it fails the build.

## Lifecycle

- `axPending()` - how many requests are in flight.
- `axCancel tHandle` - forget one; the engine's load still completes and is
  then dropped as a late reply. A stale or unknown handle is a clean no-op.
- `axCancelAll` - forget everything.
- `axShutdown` - forget everything and drop the owner; safe to call twice.
  Call it from `closeStack`.

## The blocking conveniences

`axGetSync(pUrl)`, `axSearchSync(pQuery, pOptions)` and
`axFetchItemSync(pIdentifier)` are for the message box and for scripts that
have nothing else to do while they wait. Each BLOCKS the interpreter thread
until the site answers or the URL library gives up, so a window that calls
one freezes for that long; the asynchronous handlers above are the shape
for anything with a user in front of it. They apply the same user agent,
the same body cap and the same parsers, and read both `the result` (the
Internet library reports a failure there) and the body (which can be
legitimately empty).

## Capabilities

`axProbeCapabilities()` answers `hasUrlLib` (the Internet library answers
`libURLVersion` in a try), `urlLibVersion` and `version`, probed once and
cached. On a build without the Internet library the fetch handlers still
refuse cleanly; the probe just lets an app say so up front. It is NOT a
claim about https.

## The open TLS question

Everything ArchiveXT fetches is `https://archive.org/...`. Whether this
engine's Internet library does https at all on every platform, and whether
it verifies the server certificate when it does, is unmeasured in this tree:
root `docs/OXT-ENGINE-NOTES.md` 6.8 records the suite's only TLS
observation, and it is `open secure socket` against a good certificate, not
libURL. The consequences are bounded - ArchiveXT sends no credentials and
downloads public data - but a client that silently accepts any certificate
is a client that can be fed a wrong file list, so the first engine pass
should record the answer, in both directions, and `07-open-questions.md`
holds the item. Until then `axSetBaseUrl "http://archive.org"` is the
documented fallback for an engine whose https refuses, at the cost of the
integrity that https would have given.
