# The HTTP host: architecture, contracts and decisions

The web host inside `src/nocloudquickshare.livecodescript`: a streaming, memory-flat,
transport-neutral HTTP/1.1 server with traversal, dotfile and control-byte guards, a
LAN-only password-gated editor, and framing hardened against smuggling. Handler names are
cited; line numbers are not (they drift).

**Status.** Everything below is verified statically; its pure decisions are pinned in
`tests/fileserver_golden.py` and driven against the shipped script by
`tools/check-script-vectors.py`. It needs an OXT pass; `oxt-pass-checklist.md` is that
pass's script. The endpoint ideas never built wait on the suite's decision D-02 (deferred
2026-08-27 until the first external user report); the suite's docs/WORK-PLAN.md carries
that menu, each idea with its constraint, and the five questions that would order it
close section 4.

## 1. Architecture as built

### 1.1 Two transports, one contract

| | **Clearweb** (`cw:`) | **Tor** (`ox:`) |
|---|---|---|
| Wire | raw TCP listener | OnionXT onion stream |
| Handlers | `qsCw*` (`qsCwAccept` / `qsCwData` / `qsCwServe` / `qsCwServeFile` / `qsCwPump` / ...) | `qsOnion*` + `qsFs*` (`qsFsStream` / `qsFsHandle` / `qsFsServePath` / `qsFsServeFile` / `qsFsPump` / ...) |
| Address model | `http://<ip>:<port>/<token>/...`: a **capability token** is the first path segment | the onion root `http://<addr>.onion/...`: the `.onion` *is* the capability |
| Connection reuse | **keep-alive** for text replies and redirects only (`sCwKeep`, the HTTP/1.1 default; `kCwIdleTimeout` 30 s; at most `kCwMaxKeepAlive` 100 requests); every file response carries `Connection: close` (`qsHttpFileHead`) | **`Connection: close`** on every response, DECIDED 2026-08-27 (D-09) |
| File slice | `kCwChunk` **256 KiB**, paced by socket write completion | `kOnionChunk` **64 KiB**, paced by `kOnionPumpTick` (15 ms) |
| Share shapes | a single **file** or a **folder** | a folder (`sActiveShare["root"]`) |

Both share the framing helpers and the route table, so a handler is **transport-neutral**:
it gets `("cw:" & socket)` or `("ox:" & stream)` as an opaque `pConn` and replies via
`qsHttpReply`. **Tor stays close-per-response (D-09)** because it is simple and auditable
where auditability is the product, the keep-alive win over Tor is unmeasured, and circuit
reuse cuts against unlinkability; reversible if an OXT pass shows Tor pages stalling.

### 1.2 Request framing (`qsHttp*`)

- `qsHttpHeaderEnd` finds the `CRLFCRLF` terminator, probing the native `byteOffset` ONCE
  on a known vector and falling back to an interpreted scan (no O(n^2) stall at 256 KB).
- `qsHttpReqComplete` / `qsHttpReqLength` decide completeness and trim a keep-alive
  request to its exact byte length, so pipelined bytes survive for the next one.
- `qsHttpParseHead` produces `__method` / `__path` / `__query` / `__version` plus
  lowercased headers. The LAST duplicate wins; client headers starting `__` are refused
  (the pseudo-field namespace); a conflicting duplicate `Content-Length` is flagged
  `__dupcl`, the classic smuggling lever. `qsHttpParse` adds `__body`, capped to
  `Content-Length`.
- `Transfer-Encoding: chunked` or `__dupcl` gets a `400` BEFORE any route or disk touch,
  on both transports. A request over `kFsMaxReq` (256 KB) gets a `413`. Only `GET`/`HEAD`
  reach the static pipeline; anything else is `405` unless a route claims it.

### 1.3 Routes

- ONE shared pipeline: `qsHttpTryRoutes` then `qsHttpServeStatic`, called by both
  transport prologues. A registered route answers first, for any method; over clearweb
  the token is stripped so a handler sees the app-relative path.
- `qsHttpDispatch` wraps the handler in `try` (a throw or a missing handler is a clean
  `500`). `qsHttpReply pConn, pCode, pType, pBody` sends status, `Content-Type`,
  `Content-Length` and the extra headers. Over Tor (`qsFsSendText`) it then closes the
  stream; over clearweb (`qsCwSendText`) it keeps the connection when `qsCwWantsKeep`
  allows (at most `kCwMaxKeepAlive` requests) and closes otherwise. `qsHttpReason` maps
  the codes.
- **The ten built-in routes** (registered in `qsStart`): `GET /_qs/info`,
  `GET /_qs/transparency`, `GET /_qs/routes`; `GET /_edit`; `POST /_edit/login`;
  `GET /_edit/api/list`, `GET /_edit/api/read`; `PUT /_edit/api/write`,
  `PUT /_edit/api/append`; `POST /_edit/api/delete`. `/_qs/info` (`qsInfoRoute`) returns
  `{app, version, mode, share, spa, method}`, where `mode` is `clearweb`, `tor` or `none`.
  Built-in routes are exact-match only, by design; only user `.qsroutes.json` routes
  take `:param` patterns.
- **HEAD** (2026-08-17). `qsRouteLookupKey` maps a `HEAD` onto the `GET` route unless the
  table declares a `HEAD` route, asked once per table; the pattern finder has the same
  fallback. Both text twins (`qsFsSendText`, `qsCwSendText`) suppress the body on `HEAD`
  (`sFsMethod` is stashed per stream, cleared in `qsFsCleanup`). A HEAD body over Tor only
  wastes bandwidth (the stream closes); on the clearweb keep-alive path it would desync.
- **Reserved namespaces.** `qsHttpServeStatic` refuses `/_qs` and `/_edit` before it
  touches the share, through the ONE `qsHttpReservedPath` predicate that also serves
  `qsUserPathValid` and `qsRouteMatch`'s backstop (it replaced three literal copies).

### 1.4 Static serving and streaming

- `qsFileSize` sizes the file, `qsFsMime` picks the type (unknown is
  `application/octet-stream`) and `qsFsParseRange` honours one `Range`: `bytes=N-`,
  `bytes=-N` or `bytes=A-B`; unsatisfiable gets `416` + `Content-Range: bytes */total`; a
  multi-range spec serves the whole file, deliberately.
- `qsHttpFileHead` (2026-08-15) is the ONE 304/416/200/206 head plan both twins call
  (golden `http_file_head`); each twin keeps only its write/close/pump lines. The pump
  opens, seeks, reads and closes the file per slice, so concurrent downloads never share a
  cursor. Watchdogs reap stalls (`kOnionSendTimeout` 90 s; `kCwIdleTimeout` 30 s).
- A directory redirects `301` to add its trailing slash, then serves `index.html` or the
  generated `qsFsListing`. An unknown dot-free path falls back to `index.html`
  (`qsSiteSpaTarget`, the SPA fallback). A real miss gets the styled `qsFsNotFound` `404`.

### 1.5 Headers

- **Always sent** (`qsHttpExtraHeaders`): `Server: No Cloud Quick Share` (no version),
  `Date` (IMF-fixdate via `qsHttpDate`), `X-Content-Type-Options: nosniff`,
  `Cache-Control: no-cache`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`,
  `X-Robots-Tag: noindex, nofollow`, `Permissions-Policy: browsing-topics=()`.
- **Per file:** `Content-Type`, `Content-Length`, `Accept-Ranges: bytes`, `Content-Range`
  (on `206`), `Content-Disposition` (`qsHttpDisposition`: `inline`, or `attachment` on
  `?dl`, with the name sanitised by `qsSafeFilename`), and `ETag: W/"size-seed-gen"`
  (`qsHttpWeakETag`).
- **Conditional GET.** The weak ETag's per-launch seed and edit-generation counter stand
  in for the file's mtime (whether the engine can read one cheaply is D-10's probe,
  checklist section 4, not yet run). A matching `If-None-Match` on a full request gets
  `304` with no body (`qsIfNoneMatch`); a `Range` request never does. Non-file answers
  carry no validator. An edit through `/_edit` bumps the generation; an out-of-band disk
  edit that keeps the byte size stays `304`-stale until the app is relaunched.
- **Not sent:** `Last-Modified`, `Content-Encoding` (no compression), `Vary`.

### 1.6 Security and confinement

- **Static read path:** `..` gets `403`; control bytes (`qsPathHasControl`) get `400`; a
  dot-prefixed segment (`qsHasDotSegment`) gets `404`, not `403` (hidden means "does not
  exist": no `.git` / `.env` leak). `%xx` is decoded before the disk check, so `%2e%2e`
  is caught (golden-pinned).
- **The editor** (`qsEdit*`, OFF by default): every route gates on `qsEditReachable`
  (`qsEditIsLocal` reads the TCP peer address, never a header; Tor is always remote),
  then `qsEditAuthed` (an Argon2id password; SodiumXT only, so it fails closed without
  it). A Tor or public visitor gets `404` and never learns the editor exists. Writes are
  confined by `qsEditSafePath` (lexical: no `..`, no `:`, no control bytes, rebuilt from
  clean segments; a symlink the sharer placed inside the folder is followed by the OS).
- **Login throttle** (`qsEditLoginWait`): 4 free tries, then a 1 s wait doubling per
  failure, capped at 30 s, forgiven after 15 minutes of quiet; the `429` carries
  `Retry-After`. The throttle runs before the Argon2id hash, so a flood cannot spin the KDF.

## 2. What NOT to "fix"

1. **Memory-flat streaming** with per-slice open/seek/close (a multi-GB file costs about
   one slice of RAM; concurrency-safe on a single-threaded engine).
2. **Smuggling-aware framing:** `__dupcl`, the chunked refusal, the `__` namespace guard,
   the 256 KB cap, framing before dispatch.
3. **Fail-closed everywhere:** no SodiumXT means no editor and no Tor path; each
   dependency is probed once and guarded.
4. **Privacy-first defaults:** dotfiles `404`, the editor invisible off-LAN, no logging
   leaves the machine, `Cache-Control: no-cache` for a live-editable folder.
5. **The golden mirrors**, now held to the shipped script by the execution gate.

Every change must preserve all five.

## 3. Settled design decisions

- **User routes with `:param` (phase 3, 2026-08-16).** A pattern's first segment must be
  static, so no pattern can reach `/_qs` or `/_edit` by construction, and `qsRouteMatch`
  refuses reserved paths anyway as a backstop. `Allow` / `405` (`qsHttpAllow`) and the
  CORS preflight (`qsCorsPreflight`) are pattern-aware. Captures reach only a templated
  body, through `qsTemplateEscape` (a param is hostile input), never a `file` target, a
  `Location` or a header. "Streaming" for a route means the `file` kind through
  `qsHttpFileHead` and the pumps; inline bodies are capped at 64 KB. There is no `*`
  prefix, deliberately. Exact beats pattern, then fewest params, then the smallest key;
  patterns never ride the exact-key fast path.
- **Redirects under the token mount (2026-08-15).** A user redirect's folder-absolute
  `Location` is re-based onto `/<token>/` over a web link (`qsMountLocation`); external
  and relative targets, and the Tor root, are untouched.
- **The editor's write path (phase 5).** A chunked upload is a first `write` slice plus
  `append` slices, bounded in total by `kEditMaxUploadBytes` (1 GiB). Missing parent
  folders are created (`qsEditParentDirs` / `qsEditEnsureFolders`). Dotfile writes and
  folder collisions are refused; an existing file that cannot be sized gets `409`.
  `delete` is file-only and non-recursive; `rename` and `mkdir` are not verbs of their own.
- **Tor keep-alive** (D-09) and **the validator** (D-10's probe): sections 1.1 and 1.5.

## 4. The phase record

The host was built in phases, and code comments cite them by number.

| Phase | What it was | As built |
|---|---|---|
| 0 | free wins | `Date`; `OPTIONS` / `Allow` / `405`; MIME top-ups; the login throttle; `/_qs/info` `version` + `spa`; `/_qs/transparency`; the privacy headers; `/_qs/routes`; `.qsroutes.json` routes. `/_qs/health` and the `encrypted` / `uptime` fields were not built |
| 1 | conditional GET | the weak ETag + `304`. `Last-Modified` was not built (it waits on D-10) |
| 2 | the shared serve core | the dedup: `qsHttpTryRoutes` / `qsHttpServeStatic`, then `qsHttpFileHead` (2026-08-15). Tor keep-alive decided against (D-09) |
| 3 | first-class routes | per-route headers, status and type; `file`-kind streaming; `:param` patterns (2026-08-16). A generated-body stream (`qsHttpReplyStream`, SSE) and patterns for built-in routes were not built |
| 4 | content endpoints | not built (D-02) |
| 5 | editor and collaboration | upload (`write` + `append`) and `delete`. `rename` / `mkdir` verbs, a shares admin and SSE live-reload were not built |

**Open questions (D-02, deferred 2026-08-27 until the first external user report).**
These are the owner's calls that would order the unbuilt menu:

1. **Priorities:** standards polish or new capability (manifest/hashes/search, a
   programmable API)? Since it was asked, `Date`, the weak ETag + `304` and editor uploads
   were built and Tor keep-alive parity was declined (D-09); the polish left is the
   work plan menu's closing line. This decides whether the phase 3-5 residue is sequenced at all.
2. **Introspection default** (`/_qs/manifest`, `/_qs/search`, `/_qs/stats`): an option to
   keep a share's contents LIST private while still serving files by known path?
3. **How far routes go:** params, header control and file-backed streaming are built
   (2026-08-16); generated-body streaming/SSE and anything stateful (paste, KV) are not.
4. **Integrity appetite:** a sha256 manifest plus a pre-download passphrase-verify
   endpoint, or skip.
5. **Compression:** a `gzip_static`-style sidecar, or leave it (Tor is the bottleneck and
   text assets are small).

The suite's recommendation, not a decision: answer 1 "capability-first" only if a
concrete consumer exists (the bundled webapp or a user request); take 2 as a per-share
toggle if phase 3 work lands anyway; hold routes thin (3); for this app's audience, "skip"
and "leave it" are fine final answers to 4 and 5.

## 5. Guardrails for any change

- **The gates plus an OXT pass.** Mirror, index and drive every new pure-logic helper;
  claim only "verified statically; needs an OXT pass" for what no engine has shown.
- **Fail closed.** Anything touching `sx*` or `ox*` is probed once and guarded; a missing
  dependency degrades that one feature and nothing else.
- **Single thread, stream everything.** No endpoint reads a whole file or buffers a whole
  response; reuse the bounded pump. Hashing, zip and search must be incremental and
  size-capped. One FFI round trip per poll.
- **Privacy is the product.** No public endpoint leaks the sharer's IP, absolute paths,
  identity or tokens, or turns logging on by default. Respect `qsHasDotSegment` on every
  read path. Anything that writes or reveals the address or token is LAN + password only.
  Keep `what-it-hides.md` and `/_qs/transparency` truthful.
- **Versioned markers.** A new wire or at-rest format gets a versioned magic prefix,
  pinned in the golden, and old readers reject an unknown prefix cleanly.
- **xTalk style:** the rules and traps in `../CLAUDE.md` apply.

**A watch-item that is never run is not a control.** "SPA fallback + HEAD" sat on this
page's watch list, naming the exact defect (a `HEAD /_qs/info` answered by the SPA
fallback with `index.html`), through two rounds of green gates until 2026-08-17. Turn a
suspicion into a golden vector or a checklist line the day it is written.
