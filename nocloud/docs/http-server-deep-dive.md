# The HTTP Server — Deep Dive, Improvement Ideas, and Endpoint Brainstorm

> **Status:** design/discussion document grounded in a read of
> `src/nocloudquickshare.livecodescript` (handler names + line numbers cited),
> `tests/fileserver_golden.py`, and `docs/what-it-hides.md`. Anything that changes runtime
> behavior is flagged **needs an OXT pass** (there is no headless way to run a `.livecodescript`).
>
> **Implemented since (Phase 0 + follow-ups, both gates green, pending an OXT pass):**
> `Date` header; MIME top-ups; `OPTIONS`/`Allow` + `429`; editor-login throttle; richer
> `/_qs/info` (+`version`,+`spa`); new `/_qs/transparency`; and **user-defined API routes via
> `.qsroutes.json`** — a declarative, no-LiveCode way for end-users to add endpoints, gated
> by a fail-closed JSON probe (see `user-routes.md`). Those routes now also cover **`file`-mapped
> responses** (stream a folder file under a friendlier URL, Range-aware, folder-confined) and
> **safe `{{...}}` body templating** (reflect `method`/`path`/`query.NAME`/`now`/`date`, each
> escaped for the response type). Also landed: **privacy/safety response headers** on every
> response (`Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`, `X-Robots-Tag: noindex`,
> `Permissions-Policy: browsing-topics=()`) and a read-only **`GET /_qs/routes`** listing the
> active custom routes (method/path/kind only); the `Allow` header on `OPTIONS`/`405` now also
> reflects user-declared route methods; the editor-login `429` carries a `Retry-After`; and a
> `cors: true` route now also answers the `OPTIONS` **CORS preflight** (so preflighted
> cross-origin requests, not just simple GETs, work). And **conditional GET** landed: every file
> response carries a weak `ETag` (`W/"size-seed-gen"` — a per-launch seed + an edit-generation
> counter stand in for the per-file mtime the engine has no cheap way to read), and a matching
> `If-None-Match` on a full request returns `304 Not Modified` with no body. And the two serve
> paths were **unified**: the duplicated route + static tail is now one shared pipeline
> (`qsHttpTryRoutes` + `qsHttpServeStatic`) that both the Tor and clearweb prologues call, so a
> feature is written once.
>
> **2026-08-15 (verified statically + golden-pinned; needs an OXT pass):** the last twin
> residue is gone — the conditional-GET / `Range` / response-head block that `qsFsServeFile`
> and `qsCwServeFile` still each carried verbatim is now ONE shared `qsHttpFileHead` both
> twins call (they keep only the transport-specific write/close/pump lines), with the branch
> pinned **once** in the golden (`http_file_head()` + `http_extra_headers()` /
> `http_disposition()` / `fs_leaf()`) instead of two pasted copies being trusted twice; wire
> bytes are unchanged. Same day, the **token-mount redirect hole** closed: a user-route
> redirect's folder-absolute `Location` is re-based onto the `/<token>/` capability mount
> over a web link (`qsMountLocation`, golden `mount_location()`) — emitted verbatim it
> escaped the mount and the token gate 404'd the redirected request; external and relative
> `Location`s, and the Tor root, are untouched.
>
> **2026-08-16 — Phase 3 LANDED, scoped (verified statically + golden-pinned; needs an OXT
> pass):** `.qsroutes.json` paths may carry **`:param` segments** (see `user-routes.md`,
> "Path parameters"). The scope was set by the contract questions that made the 2026-08-15
> change *skip* a naive matcher, and each is answered structurally rather than patched: (1)
> a pattern's **first segment must be static** — declaration refuses `/:x` (and `/_qs/:x`
> et al. were already refused literally), so no stored pattern can match into the reserved
> `/_qs//_edit` namespaces **by construction**, and `qsRouteMatch` refuses reserved request
> paths outright as a golden-pinned backstop; (2) the **`Allow`/`405` derivation
> pattern-matches** — a request path that a param route claims contributes that route's
> methods (`qsHttpAllow`, golden `http_allow()`); (3) the **CORS preflight promise holds
> identically** — a `cors: true` param route answers `OPTIONS` on its matching paths
> (`qsCorsPreflight`, golden `cors_preflight()`); (4) captures reach **only a templated
> body**, as `{{param.NAME}}` through the same default-deny `qsTemplateEscape` as query
> values (never a `file` target, `redirect` Location, or header — a param is hostile
> input); (5) **"streaming" for a route stays the `file` kind**: an inline body is capped
> at 64 KB, and anything larger points at a folder file and rides the EXISTING bounded
> pump (`qsHttpFileHead` + the per-transport pumps) with per-route headers/type — Phase 3
> deliberately ships no `qsHttpReplyStream`/SSE (§4's long-lived/generated-body endpoints
> stay roadmap). Matching is deterministic (exact beats pattern; fewest params, then
> smallest key) and pattern routes never ride the exact-key fast path (a request for the
> literal pattern text still gets its captures). Golden: `route_key_path` /
> `route_has_params` / `route_param_count` / `user_pattern_valid` / `route_match` /
> `user_route_find` + the extended `http_allow`/`cors_preflight`/`template_value`, 70 new
> checks (358 -> 428). Still open: the **Tor keep-alive question** (§6 Phase 2) — an owner
> decision, deliberately not made by the dedup.
>
> **2026-08-17 — two `HEAD` defects fixed (verified statically + golden-pinned; needs an OXT
> pass):** both were invisible to the gates because neither gate had ever been *asked* about
> `HEAD` on the non-file paths, and §3.4 had carried the question unrun since it was written.
> (1) **A `HEAD` reached no route at all.** `qsHttpTryRoutes` built its lookup key from the
> literal method, so `HEAD /_qs/info` missed both route tables, fell into the static pipeline
> and — the leaf having no `.` — was answered by `qsSiteSpaTarget` with `index.html` at `200
> text/html`, while `qsHttpAllow` advertised `HEAD` on every path unconditionally. Now
> `qsRouteLookupKey` (golden `route_lookup_key()`) returns the `HEAD` key when the table
> declares one and the `GET` key otherwise, asked once per table because the two tables are
> declared independently; the pattern finder gets the same fallback spelled out, since it
> arbitrates by method rather than by key. (2) **`qsFsSendText` sent a body on a `HEAD`** —
> its clearweb twin `qsCwSendText` had the test from the start, so every non-file *Tor* reply
> (listings, `404`s, `/_qs/info`, `/_qs/transparency`, `/_qs/routes`, every user-route body)
> shipped bytes a client discards. Framed correctly, that is **wasted onion bandwidth plus a
> spec violation, not a desync**: a Tor response closes its stream, so there is no following
> response to mis-frame — the keep-alive hazard is the clearweb twin's alone. The method is
> stashed per stream (`sFsMethod`, mirroring `sCwMethod`) and cleared in `qsFsCleanup`.
> Alongside them, the reserved namespaces got the static backstop they never had:
> `qsHttpServeStatic` now refuses `/_qs` and `/_edit` before it consults the share, through
> one `qsHttpReservedPath` predicate that replaced the three literal copies of that rule
> (`qsUserPathValid`, `qsRouteMatch`'s backstop, and this new site — a fourth copy of a
> security test being exactly the drift this repo keeps checkers for). Golden:
> `route_lookup_key` / `reserved_path` / `http_text_response` (which pins BOTH text twins at
> once — they differ in one line, the `Connection` header), 30 new checks (428 -> 458).

---

## 0. TL;DR

The embedded web host is genuinely well-built for what it is: a **streaming, memory-flat,
transport-neutral** HTTP/1.1 server with a real security posture (traversal + dotfile +
control-byte guards, a LAN-only/password-gated editor, request-framing hardened against
smuggling), all pinned by a Python "golden" that mirrors the pure-logic helpers.

The highest-leverage work is **not** more endpoints first — it's **making routes
first-class** (let a handler set headers, negotiate status, and stream a body) and
**collapsing the clearweb/Tor duplication behind a shared core**. Those two unlock almost
every endpoint idea in §4 cleanly. The most valuable *standards* gaps are **conditional GET
(ETag/`304`)** and a **`Date` header**; the most valuable *endpoints* are a **richer
`/_qs/info` + `/_qs/manifest`** (folder introspection) and an **integrity/hashes** endpoint
that fits the "verify what you downloaded" ethos.

---

## 1. Architecture as-built

### 1.1 Two transports, one contract

The host serves the shared folder over two wire transports that converge on a shared
request/response contract:

| | **Clearweb** (`cw:`) | **Tor** (`ox:`) |
|---|---|---|
| Wire | Raw TCP listener | OnionXT onion stream |
| Handlers | `qsCw*` (`qsCwAccept`/`qsCwData`/`qsCwServe`/`qsCwServeFile`/`qsCwPump`/…) | `qsOnion*` + `qsFs*` (`qsFsStream`/`qsFsHandle`/`qsFsServePath`/`qsFsServeFile`/`qsFsPump`/…) |
| Address model | `http://<ip>:<port>/<token>/…` — a **capability token** is the first path segment | onion **root** `http://<addr>.onion/…` — the `.onion` *is* the capability |
| Connection reuse | **Keep-alive** (`sCwKeep`, HTTP/1.1 default; `kCwIdleTimeout` = 30 s) | **`Connection: close`** on every response (no reuse) |
| File slice | `kCwChunk` = **256 KiB**, paced by socket write-completion | `kOnionChunk` = **64 KiB**, paced by `kOnionPumpTick` (15 ms) timer |
| Share shapes | single **file** share *or* **folder** share | folder share (`sActiveShare["root"]`) |

Both parse with the same framing helpers and dispatch through the same route table, so a
route handler is **transport-neutral**: it gets `("cw:" & socket)` or `("ox:" & stream)`
as an opaque `pConn` and replies via `qsHttpReply` (§1.3).

### 1.2 Request lifecycle & framing (`qsHttp*`, ~3409–3561)

- `qsHttpHeaderEnd` finds the `CRLFCRLF` head terminator. It probes the engine's native
  `byteOffset` **once** against a known vector and uses it as a fast path, falling back to
  an interpreted per-byte scan if the probe misbehaves — a nice guard against an O(n²)
  engine-thread stall on the 256 KB request cap.
- `qsHttpReqComplete` / `qsHttpReqLength` implement completeness and keep-alive trimming
  (the served request's exact byte length, so pipelined bytes survive for the next one).
- `qsHttpParseHead` → `__method` / `__path` / `__query` / `__version` + lowercased headers.
  It **refuses client headers starting `__`** (our pseudo-field namespace) and flags
  **conflicting duplicate `Content-Length`** as `__dupcl` — the classic smuggling lever.
- `qsHttpParse` adds `__body` (raw bytes, capped to `Content-Length`).
- **Hardening already in place:** requests with `Transfer-Encoding: chunked` or `__dupcl`
  are refused with `400` **before any route or disk touch** (both transports:
  `qsFsServePath` ~4169, `qsCwServe` ~5050). Oversized requests → `413` (`kFsMaxReq`,
  256 KB). Only `GET`/`HEAD` reach the static pipeline; anything else is `405` unless a
  route claims it.

### 1.3 Dynamic routes (`qsHttpRoute`/`Dispatch`/`Reply`/`Reason`, 3600–3692)

- Registry: `sHttpRoutes["<METHOD> <path>"] -> handler name` (exact string match — and
  built-in routes stay exact-only by design; the `:param` patterns added 2026-08-16 exist
  only for user-declared `.qsroutes.json` routes, see the status ledger).
- **Precedence:** a registered route answers **first, any method**, then the static
  GET/HEAD pipeline runs (`qsFsServePath` ~4176, `qsCwServe` ~5089). Over clearweb the
  token is stripped so the handler sees the **app-relative** path.
- `qsHttpDispatch` wraps the handler in `try` → a throw or missing handler becomes a clean
  `500` (a buggy route never crashes the poll loop or hangs the connection).
- `qsHttpReply pConn, pCode, pType, pBody` is the **only** reply surface for a route: it
  sends status + `Content-Type` + `Content-Length` + the standard extra headers, then
  **closes**. `qsHttpReason` maps a fixed set of status codes.
- **The six built-in routes** (registered in `qsStart` ~1040–1052):
  `GET /_qs/info` (`qsInfoRoute`), `GET /_edit`, `POST /_edit/login`,
  `GET /_edit/api/list`, `GET /_edit/api/read`, `PUT /_edit/api/write`.
- `/_qs/info` returns `{app, mode, share, method}` where `mode ∈ {clearweb, tor, none}`.

### 1.4 Static serving & streaming (`qsFsServeFile`/`qsFsPump`, `qsCwServeFile`/`qsCwPump`)

- Size the file (`qsFileSize`), pick MIME (`qsFsMime`), honor a single `Range`
  (`qsFsParseRange`), write the head, then **pump one bounded slice per tick** — the file
  is **opened/seeked/read/closed inside each tick**, so concurrent downloads of the same
  file never share a cursor and **the file is never read whole into memory**. Watchdogs
  (`kOnionSendTimeout` 90 s; `kCwIdleTimeout` 30 s) reap stalled transfers.
- **Range** supports open-ended (`bytes=N-`), suffix (`bytes=-N`), closed (`bytes=A-B`),
  and returns `416` + `Content-Range: bytes */total` when unsatisfiable. **Multi-range is
  intentionally not supported** — a comma spec serves the whole file.
- **`HEAD` is implemented** on the file path (writes the head, closes, no body:
  `qsFsServeFile` ~4331) — and, **since 2026-08-17**, on the other two halves it had been
  missing from. It was only ever half-done: the TEXT reply over Tor (`qsFsSendText`) had no
  method test at all, so every listing, `404`, `/_qs/*` and user-route body went out with its
  body in answer to a `HEAD` (the clearweb twin `qsCwSendText` had the test from the start);
  and no `HEAD` reached the ROUTE tables at all, because the lookup key was built from the
  literal method — see §3.4, where this was already a watch-item. Both fixed; verified
  statically + golden-pinned (`http_text_response`, `route_lookup_key`), needs an OXT pass.
- **Routing niceties:** directory → `301` to add a trailing slash → `index.html` or a
  generated listing (`qsFsListing`); unknown dot-free path → **SPA fallback** to
  `index.html` (`qsSiteSpaTarget`); real miss → styled `404` (`qsFsNotFound`).

### 1.5 Headers, MIME, disposition

- **Always sent** (`qsHttpExtraHeaders` ~4227): `Server: No Cloud Quick Share`,
  `X-Content-Type-Options: nosniff`, `Cache-Control: no-cache`. Per-file:
  `Content-Type`, `Content-Length`, `Accept-Ranges: bytes`, `Content-Range` (206),
  `Content-Disposition` (`qsHttpDisposition`: `inline`, or `attachment` on `?dl`, with a
  sanitized filename via `qsSafeFilename`).
- **Not sent anywhere:** `Date`, `ETag`, `Last-Modified`, `Content-Encoding` (no
  compression), `Vary`. There is no conditional-GET / `304` path.
- `qsFsMime` covers ~35 extensions (html/css/js/mjs/json/map/xml/txt/md/log/csv, the image
  set incl. webp/avif/svg/ico, av: mp4/m4v/webm/mp3/ogg/wav, pdf/zip/wasm/webmanifest,
  fonts woff/woff2/ttf/otf/eot); unknown → `application/octet-stream`.

### 1.6 Security & confinement

- **Static read path:** `..` → `403`; control bytes (`qsPathHasControl`) → `400`; any path
  segment starting `.` (`qsHasDotSegment`) → **`404` not `403`** ("hidden means does not
  exist" — no `.git`/`.env`/editor-dropping leak). Decodes `%xx` before the disk touch.
- **Editor** (`qsEdit*`, OFF by default): every route gates on `qsEditReachable`
  (`qsEditIsLocal` reads the **TCP peer address**, never a header; Tor is always remote →
  refused) **then** an Argon2id password (`qsEditAuthed`, needs SodiumXT — **fails closed**
  without it). A Tor/public visitor gets `404` and never learns the editor exists. Writes
  are confined by `qsEditSafePath` (lexical: rejects `..`, `:`, control bytes; rebuilds
  from clean segments; **symlink caveat** is documented).
- **Golden coverage:** `tests/fileserver_golden.py` re-implements ~21 pure-logic helpers in
  Python (`parse_range`, `traversal_ok`, `has_dot_segment`, `mime`, `safe_filename`,
  `http_header_end/_content_length/http_req_complete/http_req_length`, `json_escape`,
  `edit_safe_path`, `edit_is_local`, `query_param`, `spa_is_route`, `capability_route`,
  rate/ETA/`html_escape`/`fs_icon`/`file_size_probe`). **Rule:** a new helper with a
  pure-logic core must be mirrored here.

---

## 2. What's already excellent (don't "fix" these)

1. **Memory-flat streaming** with per-slice open/seek/close — correct, concurrency-safe,
   and the right model for a single-threaded engine. A multi-GB file costs ~one slice of
   RAM.
2. **Smuggling-aware framing** — `__dupcl`, chunked refusal, the `__`-namespace guard, the
   256 KB cap, and framing-before-dispatch are more than most hand-rolled servers do.
3. **Fail-closed everywhere** — no SodiumXT ⇒ no editor; no OnionXT ⇒ no Tor; each probed
   once and guarded.
4. **Privacy-first defaults** — dotfiles are `404`, the editor is invisible off-LAN, no
   request/response logging leaves the machine, `Cache-Control: no-cache` suits a
   live-editable folder.
5. **The golden** — pinning pure logic in a second language is exactly how you keep an
   un-headless-testable script honest.

Any change below must **preserve all five**.

---

## 3. Core server improvements (ranked)

Each item: **why**, **effort** (S/M/L), **risk**, and **constraint fit**. "Golden" means a
pure-logic helper must be mirrored in `fileserver_golden.py`.

### 3.1 Tier 1 — high value, low/medium effort

- **A `Date` header on every response.** *(S, low risk)* Currently absent. Trivial, RFC-
  expected, helps caches/proxies and looks correct in `curl -I`. Constraint fit: pure
  string; no golden needed unless you factor a date-formatter helper (then mirror it).
  **Needs OXT pass** to confirm the engine's date formatting.
- **Conditional GET: `ETag` + `Last-Modified` → `304 Not Modified`.** *(M, low–med risk)*
  The single biggest *correctness/perf* win. Today `Cache-Control: no-cache` forces
  revalidation but there's **nothing to revalidate against**, so every reload re-streams
  the whole file. Add a weak validator from `size + mtime` (e.g. `ETag: W/"<size>-<mtime>"`)
  and honor `If-None-Match` / `If-Modified-Since` with an empty-body `304`. Huge for the
  demo's own repeated asset loads and for video re-seeks. Constraint fit: an
  `qsHttpValidator(size,mtime)` + an `qsHttpIsNotModified(headers,validator)` are pure
  logic → **golden them**. Keep `no-cache` (it means "revalidate", not "don't store") so
  live edits still show up.
- **`OPTIONS` + a correct `Allow` header on `405`.** *(S, low risk)* Currently non-GET/HEAD
  without a route is a bare `405`. Add `Allow: GET, HEAD` (plus any methods a route
  registered for that path) and answer `OPTIONS *`/path with `204`. Enables CORS preflight
  (§3.3) and is cheap. Constraint fit: derive `Allow` from `sHttpRoutes` keys for that path.
- **Editor login throttle.** *(S, low risk)* `qsEditLoginRoute` has **no brute-force
  backoff**. Argon2id is slow (good) and the surface is LAN-only (good), but a hostile LAN
  device can still hammer it. Add a small per-peer failure counter with an escalating delay
  / temporary lockout (e.g. after N fails, refuse for T seconds). Constraint fit: a pure
  `qsEditThrottle(state, now)` decision → **golden it**; keep state in a script-local array.
- **MIME table top-ups.** *(S, low risk)* Add the obvious misses: `opus`, `flac`, `m4a`,
  `aac`, `mov`, `mkv`, `heic/heif`, `apng`, `jxl`, `ics`, `vtt` (subtitles), `wasm` is
  present. Constraint fit: extend `qsFsMime` + the golden's `mime()` in lockstep.

### 3.2 Tier 2 — structural, higher leverage

- **Collapse the clearweb/Tor duplication behind a shared core.** *(L, med risk — but the
  biggest maintainability win)* `qsCwServe`≈`qsFsServePath`, `qsCwServeFile`≈`qsFsServeFile`,
  `qsCwPump`≈`qsFsPump`, `qsCwSendText`≈`qsFsSendText`, etc. are parallel implementations,
  and they've **already drifted** (keep-alive exists on `cw` but not `ox`). Extract the
  transport-independent decisions (path→disposition, route-vs-static, range math, head
  construction) into pure helpers that both pumps call, leaving only `oxWrite`/`write to
  socket` transport-specific. Constraint fit: the extracted decision helpers are pure →
  **golden them**; do it incrementally so each step keeps both gates green. **Needs OXT
  pass** for each transport after refactor.
- **Make routes first-class: header control + status + streaming.** *(M–L, med risk)* This
  is the **enabler** for most of §4. Today `qsHttpReply` can only send `status + type +
  one-shot text` and always closes. Add (a) an optional **headers** argument (or a
  `qsHttpReplyEx pConn, pCode, pType, pHeadersArray, pBody`) so a handler can set
  `Cache-Control`, `ETag`, `Location`, CORS, `Content-Disposition`; (b) a **streaming reply**
  (`qsHttpReplyFile pConn, pDisk, pHeaders` reusing the pump; and/or a `qsHttpReplyStream`
  that pumps a generated body in bounded slices) so a route can return a large/dynamic body
  without buffering it whole. Constraint fit: streaming must reuse the existing bounded-pump
  discipline (never buffer whole); header assembly is pure → golden the serializer.
- **Tiny route-pattern matcher (prefix / one param).** *(M, med risk)* Exact-match only
  means every dynamic path needs its own registration; `/_edit/api/read` can't become
  `/api/files/:name`. A minimal matcher — exact first, then a **single** `:param` or a
  trailing `*` prefix — covers the useful cases without a regex engine. Constraint fit:
  matcher is pure → **golden it**; keep it deterministic and cheap (single-thread).
  **Status (2026-08-16): LANDED for user routes**, generalised to multiple `:param`
  segments (static first segment mandatory; no `*` prefix — deliberately) — see the
  status ledger at the top and `user-routes.md`. Built-in `qsHttpRoute` registrations
  stay exact-only: nothing internal needs a pattern, and the smaller surface is the
  safer default.
- **Configurable listing / index behavior + directory `Cache-Control`.** *(S, low risk)*
  Small polish: let the sharer suppress the auto-listing (serve `403`/`404` instead) for
  folders without an `index.html`, since a listing enumerates filenames to anonymous
  visitors. Constraint fit: a one-line policy check; privacy-positive.

### 3.3 Tier 3 — nice-to-have / conditional

- **CORS for `/_qs/*` (and opt-in for user API routes).** *(S)* Read-only public info
  endpoints benefit from `Access-Control-Allow-Origin: *` so other pages/tools can fetch
  them. **Gate carefully:** never CORS-open the editor or anything state-changing. Depends
  on route header control (§3.2).
- **Compression.** *(M–L, med risk — probably skip / do the cheap version)* Real on-the-fly
  gzip fights the "never buffer whole, one slice per tick" model and needs a streaming
  deflate the engine may not expose cheaply. The **pragmatic** version: serve a
  **precompressed sidecar** (`file.css.gz`) when present and the client sends
  `Accept-Encoding: gzip` (static hosts call this "gzip_static"). Constraint fit: a pure
  `qsPickEncoding(acceptEncoding, hasGz)` → golden it; no runtime compressor needed.
- **`431 Request Header Fields Too Large`.** *(S)* Today an oversized head is caught by the
  256 KB total cap and answered `413`. A dedicated header-size limit + `431` is more
  correct but low-impact.
- **Structured, opt-in access log with redaction.** *(S)* `qsAccessLog` already prints
  method+path+peer to the Activity panel. Keep it **off the wire and off disk by default**
  (privacy!); if you ever add file logging, redact the IP over clearweb and never log query
  strings that could carry secrets.

### 3.4 Correctness watch-items (verify, likely fine)

- **`SPA fallback + HEAD`**: ~~confirm a `HEAD` on a SPA route returns the head-only
  path.~~ **RESOLVED 2026-08-17, and the suspicion was better than the question.** A `HEAD`
  did not merely miss the head-only path — it was the SPA fallback's own *cause*: the route
  key was built from the literal method, so `HEAD /_qs/info` matched nothing in either route
  table, fell through to the static pipeline, and `qsSiteSpaTarget` answered the
  extensionless leaf with `index.html` at `200 text/html` — while `qsHttpAllow`
  unconditionally advertised `HEAD` on every path. A reserved-namespace URL was being served
  the SPA. Three fixes, both transports (they share the pipeline): `qsRouteLookupKey` maps a
  `HEAD` onto the `GET` route unless the table declares a `HEAD` one; `qsFsSendText` gained
  the body suppression its clearweb twin always had; and `qsHttpServeStatic` now refuses
  `/_qs` and `/_edit` outright (`qsHttpReservedPath`, one predicate replacing the three
  literal copies of that rule) rather than letting the static pipeline answer a reserved URL
  off disk or off the SPA. Golden-pinned; the engine items are in
  `oxt-pass-checklist.md` §4. **The lesson worth keeping is about this list**: a watch-item
  that is never run is not a control. This one named the exact defect and sat here unrun for
  two rounds of "both gates green" — which is the repo's *shipped is not run* rule arriving
  in a document instead of in code.
- **`Range` on a zero-byte file**: `bytes=0-` against `total=0` — confirm `qsFsParseRange`
  yields `416` (start `>= pTotal`), not a negative length. *(golden already exercises
  bounds; add a `total=0` vector to be safe.)*
- **Percent-encoding of `%2e%2e` / `%2f`**: traversal is checked *after* `urlDecode`, so
  `%2e%2e` decodes to `..` and is caught — good; add an explicit golden vector to pin it.

---

## 4. API endpoint brainstorm (by context)

Legend: **Gate** = who may call it. **Priv** = privacy note. **E/V** = effort/value.
Unless noted, public endpoints must be **safe to expose to an anonymous Tor visitor** — no
IP, no absolute disk path, no sharer identity. Most of the richer ones depend on **route
header control / streaming** (§3.2).

### 4.A Observability & trust — the `/_qs/*` family (public, read-only)

| Endpoint | Purpose | Gate / Priv | E/V |
|---|---|---|---|
| `GET /_qs/info` *(exists — extend)* | Add `version`, `encrypted` (bool), `transport`, `readonly`, `uptime_s`, `spa` (has index.html). **No IP, no path.** | Public. Priv: keep it aggregate; `uptime` is fine, don't expose start wall-clock if paranoid. | S / high |
| `GET /_qs/health` | Liveness probe → `200 {"ok":true}` (or `204`). For uptime monitors / scripts. | Public. Priv: none. | S / med |
| `GET /_qs/stats` | Aggregate counters: requests served, bytes sent, active transfers, distinct-since-start (a count, **never** a list of peers/IPs). | Public **or** LAN-only if you consider counts sensitive. Priv: counts only. | M / med |
| `GET /_qs/transparency` | Machine-readable version of `what-it-hides.md`: `{transport, ip_visible_to_peers, both_ends_hidden, files_encrypted, logging:"none", ephemeral:true}`. Lets a client *prove* the privacy posture. | Public. Priv: this is the honesty endpoint — it states the model, leaks nothing. | S / high |
| `GET /_qs/qr` | Return the share URL as an SVG QR (inline SVG, no external gen). Handy to open on a phone. | Public over the LAN link; over Tor the address is already the page. Priv: only echoes the address the visitor already has. | M / med |

### 4.B Content & site features (public, read-only)

| Endpoint | Purpose | Gate / Priv | E/V |
|---|---|---|---|
| `GET /_qs/manifest` | JSON of the served tree: `[{path,size,mime,mtime}]` (dot-segments excluded, same rules as serving). Powers galleries, file browsers, offline caching, `sitemap`. | Public. Priv: exposes filenames+sizes — same info a directory listing already gives; respect `qsHasDotSegment`; **no absolute paths** (app-relative only). | M / high |
| `GET /_qs/hashes` | Integrity manifest: `{path: {size, sha256}}` for every file. A downloader can verify what they got — squarely on-brand ("no cloud, but you can still trust the bytes"). | Public. Priv: hashes leak nothing new. **Cost:** hashing large trees is CPU on the one thread — compute lazily/incrementally and cache by mtime. | M / high |
| `GET /_qs/search?q=` | Filename (and optionally small-text) search over the manifest → matching paths. | Public **or** LAN-only. Priv: filenames only. Cap result size; never grep large/binary files inline (single thread). | M / med |
| `GET /feed.json` / `/rss.xml` | If the folder looks like a blog (`blog.json` or `*.md` posts), emit a JSON Feed / RSS. Turns "share a folder" into "publish a feed." | Public. Priv: only the content the sharer put there. | M / med |
| `GET /sitemap.xml`, `GET /robots.txt` | Derived from the manifest / a sane default (`Disallow:` nothing, or the sharer's choice). Makes a web-link share behave like a real site. | Public. Priv: `robots.txt` can also *ask* crawlers to stay out — a nice ephemeral-site default. | S / med |
| `GET /_qs/zip?path=` | Stream a **zip of a folder** as `application/zip` (attachment). "Download all." | Public **or** LAN-only. Priv: none new. **Hard part:** must stream (zip64, no whole-buffer) — only do it if streaming replies (§3.2) land; otherwise skip. | L / med |

### 4.C Developer / automation (mostly demo/opt-in)

| Endpoint | Purpose | Gate / Priv | E/V |
|---|---|---|---|
| `POST /api/echo` | Reflect method/headers/body as JSON. The canonical "the host runs my code" demo (the webapp's checkout already *sketches* `POST /api/order`). | Public (demo) / opt-in. Priv: reflects only what the caller sent. | S / med |
| `GET /_qs/routes` | List registered routes (`METHOD path`) — self-documentation for anyone building on the host. | Public **or** LAN-only. Priv: route names only; don't expose handler internals. | S / med |
| `POST /_qs/paste` + `GET /_qs/paste/:id` | An **ephemeral** in-memory key→text store scoped to the sharing session (dies when the window closes — very on-brand). A tiny pastebin/dropbox for text. | LAN-only recommended (writes). Priv: in-RAM only, never disk; size-capped. | M / med |
| `POST /api/order` *(demo)* | Make the webapp's sketched order endpoint real (returns a JSON receipt). Turns the Store tab's "where a real shop goes next" into a live example. | Public (demo). Priv: don't persist PII; it's a demo receipt. | S / low |

### 4.D Collaboration / LAN editor extensions (LAN-only + password, like `/_edit/*`)

All of these **must** reuse `qsEditReachable` + `qsEditAuthed` + `qsEditSafePath` and stay
invisible (`404`) to Tor/public — identical trust model to the existing editor.

| Endpoint | Purpose | Gate / Priv | E/V |
|---|---|---|---|
| `POST /_edit/api/upload` | Upload a file into the shared folder (confined by `qsEditSafePath`). Completes the editor from "edit text" to "manage the share." | LAN + password. Priv: writes confined; enforce a size cap (`kFsMaxReq` bounds the request today — a chunked/large upload needs the streaming-body work). | M / high |
| `POST /_edit/api/delete` / `.../rename` / `.../mkdir` | Basic file management for the LAN editor. | LAN + password. Priv: confined; refuse dot-segments unless explicitly intended. | M / med |
| `GET /_edit/api/events` (SSE) | Live-reload / change feed: emit an event when a served file changes, so an open editor/preview refreshes. | LAN + password. Priv: LAN-only. **Hard part:** SSE = a long-lived response; needs the streaming-reply work and a change signal. | L / med |
| `GET /_edit/api/shares` | Admin view of what's being shared right now (share name, transport, token, whether encrypted) — a control panel in the browser. | LAN + password. Priv: this DOES expose the token/address — hence LAN+password only, never public. | M / med |

### 4.E Privacy / security / transparency (public, honesty-preserving)

| Endpoint | Purpose | Gate / Priv | E/V |
|---|---|---|---|
| `GET /.well-known/security.txt` | Standard security-contact/disclosure file (from a sharer-set value or a sane default). | Public. Priv: note — it lives under a dot-segment, which the static path hides; serve it via a **route**, not the static tree. | S / low |
| `GET /_qs/integrity/:path` | Per-file `{size, sha256, mime}` — the single-file companion to `/_qs/hashes`, cheap to compute on demand. | Public. Priv: none new. | S / med |
| `POST /_qs/verify-passphrase` | For the encrypted path: a challenge that confirms the visitor's passphrase is correct **before** any ciphertext download, using the existing SodiumXT verifier shape (`BTXQS1:`-style authenticator). Mirrors the "verify up front" rule. | Public but **SodiumXT-gated** (fails closed). Priv: reveals only correct/incorrect, never the key. Must reuse the versioned marker discipline. | M / med |
| `GET /_qs/encrypted` | Boolean: is this share end-to-end encrypted? Lets a client show a lock badge honestly. (Could just be a field in `/_qs/info`.) | Public. Priv: a boolean. | S / low |

---

## 5. Cross-cutting theme — the "north star"

Most of §4 wants the same three primitives. Building these once makes the endpoint list
cheap and consistent:

1. **Route header control** — a handler can set arbitrary response headers
   (`Cache-Control`, `ETag`, `Location`, CORS, `Content-Disposition`).
2. **Route streaming** — a handler can return a large/dynamic body (a zip, an SSE feed, a
   hashed manifest) through the existing bounded pump, never buffered whole.
3. **A shared serve core** — so the above (and every future fix) is written **once** and
   both transports inherit it.

Ship those (§3.2) and the public `/_qs/*` observability set (§4.A) + `manifest`/`hashes`
(§4.B), and the host graduates from "serves a folder" to "a tiny, honest, programmable,
verifiable web host in a folder" — without ever contradicting the privacy model.

---

## 6. A possible phased plan

Each phase ends **green on both gates** (`check-livecodescript.py` + `fileserver_golden.py`)
and, for anything touching the wire, an **OXT pass** before it's called "done."

- **Phase 0 — free wins (S):** `Date` header; `Allow` on `405` + `OPTIONS`; MIME top-ups;
  editor-login throttle; extend `/_qs/info` (`version`, `encrypted`, `uptime`, `spa`); add
  `/_qs/health` + `/_qs/transparency`. *Golden:* throttle decision, any new date/encoding
  helper.
- **Phase 1 — conditional GET (M):** `ETag`/`Last-Modified` + `304` on `If-None-Match` /
  `If-Modified-Since`. *Golden:* validator + not-modified decision. Biggest perf/correctness
  gain; low blast radius (adds headers + a 304 branch).
- **Phase 2 — shared serve core (L):** factor the transport-neutral decisions out of the
  `cw`/`ox` twins into pure helpers; bring keep-alive to the Tor path (or consciously
  decide Tor stays close-per-response) so the two can't drift again. *Golden:* the extracted
  decision helpers. Do it in small, individually-green steps.
  **Status (2026-08-15): the dedup half LANDED.** The route + static tails became the shared
  `qsHttpTryRoutes`/`qsHttpServeStatic` pipeline earlier, and the remaining twin block — the
  conditional-GET / `Range` / head assembly duplicated across `qsFsServeFile`/`qsCwServeFile`
  — is now the ONE `qsHttpFileHead` both call, golden-pinned once (`http_file_head()`);
  behavior byte-identical, verified statically, needs an OXT pass. The **keep-alive half
  remains deliberately OPEN**: whether Tor gains keep-alive or is consciously recorded as
  close-per-response (§1.1) is an owner decision this refactor did not make — the shared
  helper emits `Connection: close` on every file head, exactly as both twins always did.
- **Phase 3 — first-class routes (M–L):** header-control + streaming replies + a minimal
  `:param` matcher. Unlocks the rest.
  **Status (2026-08-16): LANDED, deliberately scoped** (verified statically +
  golden-pinned; needs an OXT pass — the checklist's §1a is that pass's script).
  Header-control and streaming had *already* arrived via the user-route work
  (per-route `headers`/`status`/`type`, and `file`-kind routes streaming through the
  shared `qsHttpFileHead` + pump); what this phase added is the `:param` matcher done
  against the contract questions that made the 2026-08-15 change skip it (reserved
  namespaces unreachable by construction, pattern-aware `Allow`/`405` + CORS preflight,
  captures escaped as hostile input, streaming = point at a file). NOT built, still
  open behind §4's endpoint ideas: `qsHttpReplyStream`/SSE (a *generated* long-lived
  body — zip/hashes/events), and patterns for built-in `qsHttpRoute` routes. §4's
  endpoints themselves stay roadmap.
- **Phase 4 — content endpoints (M):** `/_qs/manifest`, `/_qs/hashes` (+ `/_qs/integrity`),
  `/_qs/search`, `sitemap`/`robots`, feed. *Golden:* manifest/serialization purity, hash
  vectors.
- **Phase 5 — editor & collab (M–L, opt-in):** upload/delete/rename/mkdir (needs streaming
  body), `shares` admin, SSE live-reload — all LAN+password, all `404`-concealed.
  **Status: the upload/append/delete half LANDED** — a chunked upload arrives as a
  `write` first slice plus `append` slices (so a file bigger than `kFsMaxReq` gets in),
  bounded in total by `kEditMaxUploadBytes`, with the dotfile and folder-collision
  refusals and a `409` when an existing file cannot be sized; `delete` is deliberately
  file-only and non-recursive. Verified statically, its path helpers golden-pinned
  (`edit_safe_path`/`edit_parent_dirs`/`has_dot_segment`); needs an OXT pass — the
  checklist's §6a is that pass's script. Still OPEN: `rename`/`mkdir` as verbs of their
  own (a write already creates its missing parent folders), the `shares` admin, and SSE
  live-reload.

Sequencing rationale: Phases 0–1 are pure upside with tiny risk; Phase 2 pays down the
duplication debt **before** it's multiplied by new endpoints; Phases 3–5 build on the core.

---

## 7. Guardrails any implementation must honor

- **Two gates + OXT pass.** Mirror every new pure-logic helper in the golden; claim only
  "verified statically; needs an OXT pass" for anything you can't observe on a running
  engine.
- **Fail-closed.** Anything touching SodiumXT (`sx*`) or OnionXT (`ox*`) is probed once and
  guarded; a missing dependency degrades that one feature and nothing else.
- **Single thread, stream everything.** No new endpoint may read a whole file (or buffer a
  whole response) into memory; reuse the bounded pump. Hashing/zip/search must be
  incremental and size-capped. One FFI round-trip per poll.
- **Privacy is the product.** No public endpoint may leak the sharer's IP, absolute paths,
  identity, tokens, or turn logging on by default. Respect `qsHasDotSegment` on every read
  path. LAN-only + password for anything that writes or reveals the address/token. Keep
  `docs/what-it-hides.md` (and the proposed `/_qs/transparency`) truthful.
- **Versioned markers.** Any new wire/at-rest format (e.g. a passphrase-verify challenge)
  gets a versioned magic prefix, is pinned in the golden, and old readers reject unknown
  prefixes cleanly.
- **OXT/xTalk style.** Pure ASCII; distinctive multi-word stems (no reserved-word stem
  shadowing like `tExt`); constants literal + declared before use; declare locals at the
  top; commands report via `the result`, functions return; set `itemDelimiter`/
  `lineDelimiter` immediately before use.

---

## 8. Open questions for you

1. **Priorities:** is the goal *standards polish* (Date/ETag/304, keep-alive parity) or
   *new capability* (manifest/hashes/search, editor uploads, a programmable API)? That
   changes whether Phase 1 or Phases 3–4 come first.
2. **Public vs LAN default for introspection** (`/_qs/manifest`, `/_qs/search`,
   `/_qs/stats`): filenames/sizes are already visible via directory listings, but do you
   want an option to keep a share's *contents list* private while still serving individual
   files by known path?
3. **How far to take routes:** a full "app platform" (streaming, params, header control,
   ephemeral paste/KV) vs. keeping routes a thin demo surface? *(Partially answered
   2026-08-16: params, header control, and file-backed streaming are in for user routes —
   see the ledger. Still yours: generated-body streaming/SSE and anything stateful like
   paste/KV.)*
4. **Integrity/verification appetite:** is a `sha256` manifest + a pre-download
   passphrase-verify endpoint worth the CPU/complexity for your users?
5. **Compression:** worth the `gzip_static` sidecar approach, or leave it (Tor is the
   bottleneck anyway, and text assets here are small)?
