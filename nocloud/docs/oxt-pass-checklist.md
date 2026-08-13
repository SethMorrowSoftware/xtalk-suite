# OXT pass checklist (HTTP host)

There is **no headless way to compile or run a `.livecodescript`**, so every change to the
embedded web host is flagged *"verified statically; needs an OXT pass."* This is that pass: the
runtime behaviours that the two gates (`tools/check-livecodescript.py`,
`tests/fileserver_golden.py`) **cannot** observe, to exercise on a real OpenXTalk engine.

Covers the HTTP-host work landed across the recent PRs: custom `.qsroutes.json` routes (bodies,
templating, file-mapped, redirects), the `/_qs/*` observability endpoints, the response-header
set, `OPTIONS`/`Allow`/`405`, the editor-login throttle, and CORS preflight — plus the
load-bearing invariants those ride on (self-building UI, fail-closed extensions, clean shutdown).

**How to use it:** work top-to-bottom, mark each `- [ ]` as pass/fail, and note anything odd
inline. Each item is *action -> expected result*. Anything you can't reach is fine — just say so.
One item is worth capturing precisely because it unblocks the next feature: whether the engine
exposes a **cheap single-file modification date** (see section 4) decides whether conditional GET
/ `ETag` / `304` is worth building.

---

## 0. Build & smoke

- [ ] Paste the script into a one-card mainstack, compile, **close + reopen** -> UI builds, log
      says "ready", no `Chunk: no such object` at `field "qsXfers"`.
- [ ] **Recompile the stack script in place** (the paste-again flow) *without* closing -> UI still
      rebuilds (idempotent `qsBuild`); the poll/refresh loops do not fire against a missing field.

## 1. Custom routes - functional

Test over **both** transports: a web link (paths under `/<token>/…`) and a Tor `.onion` (root).

- [ ] Drop the sample `webapp/.qsroutes.json` into a shared folder.
- [ ] `GET /api/hello` -> JSON body **+ `Access-Control-Allow-Origin: *`**.
- [ ] `GET /api/note` -> body **+ `X-Defined-By: qsroutes.json`**.
- [ ] `GET /api/echo?msg=hi` -> reflects `hi`; **`?msg=<script>alert(1)</script>`** comes back
      **escaped**, not raw.
- [ ] `GET /api/config` -> streams `config.json` as `application/json` (a `Range:` request -> `206`).
- [ ] `GET /go/gallery` -> `302` with `Location: /gallery`.

## 2. Custom routes - security & fail-closed

- [ ] Malformed `.qsroutes.json` (bad JSON) -> **only** custom routes off; static files still
      serve; log notes it was ignored.
- [ ] Build **without the JSON library** -> custom routes silently off, everything else works.
- [ ] A route declaring a path under `/_qs/…` or `/_edit/…` -> **ignored** (cannot shadow the
      reserved namespaces).
- [ ] A `file` route pointing at a dotfile (`.env`, `.qsroutes.json`, `.git/config`) -> **skipped**.
- [ ] A route header value containing CR/LF -> the injected bytes are **stripped** (no extra
      header line appears in the response).
- [ ] A templated body with content-type `image/svg+xml` (or `application/javascript`) reflecting
      `{{query.x}}=<script>` -> **escaped** (no executable markup reaches the browser).
- [ ] **Concurrent shares:** a Tor folder share *and* a web-link share up at once -> each sees
      only **its own** routes (confirm via `/_qs/routes` on each).

## 3. Observability endpoints

- [ ] `GET /_qs/info` -> JSON with `app, version, mode, share, spa, method` (mode correct per
      transport).
- [ ] `GET /_qs/transparency` -> `ip_visible_to_peers:false` / `both_ends_hidden:true` over
      **Tor**; the inverse over a **web link**.
- [ ] `GET /_qs/routes` -> lists active routes as `method`/`path`/`kind` **only** (no file
      targets, no redirect `Location`, no disk path); correct per transport.

## 4. Response headers & HTTP correctness

Inspect the raw headers on any file response (curl `-I`, or the webapp Backend inspector).

- [ ] Present on every response: `Server`, **`Date`** (valid IMF-fixdate, e.g.
      `Sun, 06 Jul 2026 12:00:00 GMT`), `X-Content-Type-Options: nosniff`, `Cache-Control: no-cache`.
- [ ] Present too: **`Referrer-Policy: no-referrer`**, **`X-Frame-Options: DENY`**,
      **`X-Robots-Tag: noindex, nofollow`**, **`Permissions-Policy: browsing-topics=()`**.
- [ ] `OPTIONS /` -> `200` + `Allow: GET, HEAD, OPTIONS`.
- [ ] `OPTIONS` on a path with a declared `POST` route -> `Allow` **includes `POST`**.
- [ ] An unsupported method (e.g. `DELETE /somefile`) -> `405` + `Allow` header.
- [ ] `HEAD` on a file -> headers only, **no body**.
- [ ] Video/audio scrub -> `206 Partial Content`; a multi-range request -> whole file.
- [ ] A URL with `?dl` -> `Content-Disposition: attachment`.
- [ ] MIME spot-check: `.wasm`, `.mjs`, `.xml`, `.map`, `.webmanifest`, `.woff2` served with the
      right types.
- [ ] **Unblocks the next feature:** does the engine expose a **cheap single-file modification
      date** (without scanning the whole folder via `the detailed files`)? If yes, note how -> it
      makes conditional GET / `ETag` / `304` worth building. If only the folder scan exists, that
      confirms why it stays deferred.

## 5. CORS preflight (newest change)

- [ ] `OPTIONS` to a **`cors: true`** route's path -> `Access-Control-Allow-Origin: *`,
      `Access-Control-Allow-Methods: …`, `Access-Control-Allow-Headers: *`,
      `Access-Control-Max-Age: 600`.
- [ ] `OPTIONS` to a **non-cors** path -> **no** `Access-Control-*` headers (only `Allow`).
- [ ] From a page on a *different* origin, a preflighted `fetch` (`PUT`, or `POST` with a custom
      header) to a `cors` route **succeeds** (the browser does not block it).

## 6. Editor login throttle (LAN editor enabled + cryptoXT present)

- [ ] Editor **off by default**; `/_edit` -> `404` to a Tor/public visitor.
- [ ] Several wrong passwords in a row -> `429` with a **`Retry-After:` header** whose seconds
      match the body message, and the required wait **grows** with each failure.
- [ ] An honest user who waits out the window -> not stuck (a quiet streak is forgiven).
- [ ] Editor writes cannot escape the shared folder (path confinement).

## 6a. Admin panel + upload/append/delete (editor ON, over a LAN web link)

- [ ] Footer **Admin** link over Tor / a static preview -> the honest "no editor here" card
      (the host answers `404` to the probe); over a LAN web link with the editor on -> the login.
- [ ] Sign in -> the dashboard; **Store/Gallery/Blog** tabs edit an item and **Save** -> the
      change is on disk (`store.json` etc. re-pretty-printed) and the matching public page shows it.
- [ ] **Add**, **Delete** (two-step), and **move up/down** all persist and re-order correctly.
- [ ] **Files** tab lists the folder; **upload a >256 KB file** -> it arrives whole via the
      `write` + `append` slice pair, lands in `assets/uploads/`, and the parent folder is created
      if absent; **Delete** removes one file (a folder is refused).
- [ ] A cover/media **Upload…** on a store item fills the path field; Save wires it to the product.
- [ ] Error edges: append to a path that is a **folder** -> `409`; an upload over **1 GiB** ->
      `413 "That upload is too large."`; a **hidden (dot) path** write -> `400`; a mid-session token
      expiry (`401`/`404`) -> the panel forces a **re-login** rather than erroring silently.
- [ ] Saving a product with an **empty/duplicate id** (or a post with an empty/duplicate slug) is
      **refused** in the UI; editing a blog post that has headings/lists/code keeps them intact.

## 7. Webapp demo (open the served `webapp/` folder in a browser)

- [ ] **Backend tab** -> live `/_qs/info`; the header inspector shows all **eight** headers
      (including the four privacy ones); `OPTIONS -> Allow`; the templated `/api/echo?msg=…` call.
- [ ] **About tab** -> "honest privacy model" populated from `/_qs/transparency`.
- [ ] **Admin link** in the footer routes to the admin panel (see §6a).

## 8. Fail-closed extensions & clean shutdown

- [ ] Without **cryptoXT** -> encryption / editor / Tor off with a clear message; Share-code and
      Web-link still work.
- [ ] Without **OnionXT** -> Private/Tor path off; the other two work.
- [ ] Quit via window close **and** via a standalone Cmd-Q -> `qsStop` runs (session stops, Tor
      and web listener torn down, temp `.enc` files deleted).

---

## Results

Bring back a line per failed/surprising item (and the mtime finding from section 4). Format that
travels well:

```
4. Date header: PASS
5. CORS preflight non-cors path: FAIL - Access-Control-Allow-Headers still present
4. cheap single-file mtime: <yes: `the detailed files`-free way is ... / no: folder scan only>
```
