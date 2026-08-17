# OXT pass checklist (HTTP host)

There is **no headless way to compile or run a `.livecodescript`**, so every change to the
embedded web host is flagged *"verified statically; needs an OXT pass."* This is that pass: the
runtime behaviours that the two gates (`tools/check-livecodescript.py`,
`tests/fileserver_golden.py`) **cannot** observe, to exercise on a real OpenXTalk engine.

Covers the HTTP-host work landed across the recent PRs: custom `.qsroutes.json` routes (bodies,
templating, file-mapped, redirects, and — since 2026-08-16 — `:param` path patterns), the
`/_qs/*` observability endpoints, the response-header set, `OPTIONS`/`Allow`/`405`, the
editor-login throttle, CORS preflight, and — since 2026-08-17 — the two `HEAD` fixes (a `HEAD`
now reaches the `GET` route instead of falling through to the SPA fallback, and the Tor twin
stopped sending a body with it) plus the reserved-namespace static backstop — all of that on top
of the load-bearing invariants those ride on (self-building UI, fail-closed extensions, clean
shutdown), and the bundled webapp's own browser-only claims (service worker, Range seeking,
`pushState` routing) in section 7.

**How to use it:** work top-to-bottom, mark each `- [ ]` as pass/fail, fill in the **section
tally** at the bottom as each section closes, and note anything odd inline. Each item is
*action -> expected result*. Anything you can't reach is fine — just say so.
One item is worth capturing precisely because it strengthens a shipped feature: whether the engine
exposes a **cheap single-file modification date** (see section 4) — conditional GET / `ETag` /
`304` shipped without it, and a cheap mtime would upgrade its validator.

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
- [ ] `GET /go/gallery` **from inside a `/<token>/` mount** — i.e. `GET /<token>/go/gallery` over a
      web link -> `302` with **`Location: /<token>/gallery`** (the mount re-prefix, 2026-08-15;
      verified statically), and *following* the redirect lands on the gallery, **not** a token-gate
      `404`. Over Tor (root mount) the same route -> `302` with `Location: /gallery` unchanged.
      An external `redirect` target (`http://…`) must go out verbatim on both transports.

## 1a. `:param` routes (Phase 3, 2026-08-16 - verified statically + golden-pinned; THIS is its engine pass)

Uses the sample's `GET /api/greet/:name` route. Test over **both** transports.

- [ ] `GET /api/greet/world` -> `{"hello":"world"}` (the `:name` capture reached the template)
      **+ `Access-Control-Allow-Origin: *`** (the route says `cors: true`).
- [ ] `GET /api/greet/%3Cscript%3E` -> the reflected value comes back **escaped**
      (`&lt;script&gt;`), never raw — a param is hostile input, same discipline as `{{query.*}}`.
- [ ] `GET /api/greet/` (empty segment) and `GET /api/greet/a/b` (two segments) -> **`404`**
      (a param matches exactly one non-empty segment; these fall through to the static pipeline).
- [ ] `GET /api/greet/a%2Fb` -> the `%2F` decodes to a real `/` **before** routing, so this is
      two segments -> **`404`** (a param can never smuggle a slash).
- [ ] **Allow/405 accounting:** `OPTIONS /api/greet/world` -> `200` with `Allow` derived from the
      matching pattern (here `GET, HEAD, OPTIONS`); an unsupported method on that path (e.g.
      `DELETE /api/greet/world`) -> `405` + the same `Allow`. If you add a `POST /api/thing/:id`
      route, `OPTIONS /api/thing/42` must include **`POST`**.
- [ ] **CORS preflight on a param path:** `OPTIONS /api/greet/world` (the route is `cors: true`)
      -> the four `Access-Control-*` headers, exactly as an exact-path cors route answers;
      a preflighted cross-origin `fetch` to the param path succeeds.
- [ ] **Reserved namespaces stay sealed:** add a route `"path": "/:x"` or `"path": "/_qs/:x"` to
      the config -> it is **skipped at load** (not listed by `/_qs/routes`); `GET /_qs/info` and
      `/_edit` behave exactly as before (no pattern can claim them - request-time backstop).
- [ ] **Literal pattern text:** `GET /api/greet/:name` (the `:name` typed literally in the URL)
      -> still served through the matcher, with the capture equal to the literal `:name` text
      (patterns never ride the exact-key fast path).
- [ ] **File-kind param route** (add e.g. `"path": "/dl/:tag", "file": "assets/logo.svg"`):
      `GET /dl/v1` streams the file (a `Range:` request -> `206`; route `headers` present);
      the `:tag` capture is **not** substituted into the file target — every `/dl/<anything>`
      serves the same declared file.
- [ ] `GET /_qs/routes` lists the pattern route with its literal pattern text
      (`/api/greet/:name`).

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
- [ ] **`HEAD` on a ROUTE** (fixed 2026-08-17; verified statically + golden-pinned, THIS is its
      engine pass): `HEAD /_qs/info` and `HEAD /api/hello` -> the **GET's** headers, the GET's
      `Content-Length`, `Content-Type: application/json`, and **no body** — never `text/html`
      and never the SPA's `index.html`. Until the fix the lookup key was built from the literal
      method (`qsRouteLookupKey` now maps HEAD onto the GET route), so a `HEAD` missed both
      route tables, fell through to the static pipeline and came back as `index.html` at `200`
      while `Allow` had advertised `HEAD` on every path. Check over **both** transports.
- [ ] **`HEAD` over Tor specifically** (`qsFsSendText`, fixed the same day): `HEAD /` on a folder
      share -> the listing's headers with its real `Content-Length` and **zero body bytes**
      (compare `curl -s … | wc -c` for the GET against the `HEAD`). The clearweb twin has always
      suppressed the body; the Tor one shipped it for every listing, `404`, `/_qs/*` and
      user-route reply. Nothing desynced (a Tor response closes its stream) — this item is
      about the wasted onion bandwidth and the spec, so *measure the byte count*, don't just
      look for a working page.
- [ ] **A declared `HEAD` route still wins:** add a `"method": "HEAD"` route beside a `GET` one
      on the same path -> `HEAD` runs the HEAD route, `GET` runs the GET route.
- [ ] **`HEAD` on a `:param` route** (e.g. `HEAD /api/greet/world`) -> answered by the matching
      `GET` pattern: headers + `Content-Length`, no body, **not** the SPA fallback.
- [ ] **The reserved namespaces are never served off disk** (`qsHttpReservedPath`, new
      2026-08-17): `GET /_qs/nope` and `HEAD /_qs/nope` -> **`404`**, not `index.html` at `200`;
      `/_edit/api/nope` likewise. Then put a real folder named `_qs` (with a file in it) inside
      the shared folder -> it stays unreachable over HTTP on both transports. (An *unsupported
      method* on a real reserved path, e.g. `DELETE /_qs/info`, is still the route layer's
      `405` + `Allow` — unchanged.)
- [ ] Video/audio scrub -> `206 Partial Content`; a multi-range request -> whole file.
- [ ] A URL with `?dl` -> `Content-Disposition: attachment`.
- [ ] MIME spot-check: `.wasm`, `.mjs`, `.xml`, `.map`, `.webmanifest`, `.woff2` served with the
      right types.
- [ ] **Conditional GET (shared head builder, 2026-08-15):** a file response carries
      `ETag: W/"…"`; repeating the GET with that value in `If-None-Match` -> **`304`, empty
      body**; the same again with a `Range:` header -> the bytes (`200`/`206`), never a `304`.
      Check over **both** transports — since 2026-08-15 one shared helper (`qsHttpFileHead`)
      builds every file head for both, so a defect here would now be a shared one (verified
      statically + golden-pinned; this is its engine pass).
- [ ] **Would improve the validator:** does the engine expose a **cheap single-file modification
      date** (without scanning the whole folder via `the detailed files`)? Conditional GET shipped
      *without* it (the `W/"size-seed-gen"` ETag stands in for mtime); a cheap mtime would let the
      ETag survive restarts. If only the folder scan exists, that confirms the current design.

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
- [ ] **The service worker registers ONLY in a secure context** (`webapp/sw.js:1-14` states the
      claim; the registration is gated on `window.isSecureContext` at `webapp/app.js:837-838`):
      over a Tor **`.onion`** the About tab's service-worker row reads *registered + active
      (secure context)* and its chip goes live; over a plain **`http://` web link** it reads
      *unavailable here - needs a secure context* and `navigator.serviceWorker.register` is
      never reached. Only a browser can settle this one, which is why it is here.
- [ ] **The Theater's Range claim is true** (the page asserts it at `webapp/app.js:345-352`;
      the seek buttons and the `seeked` report are `:386-397`): click a chapter -> the status
      line says *Seeked to …*, and the host's Activity log / dev-tools Network shows a
      **`206 Partial Content`** for `assets/film.webm` (or `.mp4`), **not** a fresh whole-file
      `200`. Scrub backwards too — a second `206` at a lower offset.
- [ ] **The Music deck streams the same way** (`webapp/app.js:400-451`): a track does **not**
      fetch until played (`preload="none"`), scrubbing issues `Range:` -> `206`, and each row's
      **get** link (`?dl=1`) arrives as a download with `Content-Disposition: attachment` —
      including the `.wav` interlude, which exercises a different MIME row.
- [ ] **SPA URLs are real URLs** (`history.pushState` in `go()`, `webapp/app.js:1422-1426`):
      moving between tabs changes the address bar with **no page load**; then **reload** on a
      deep tab and **paste that URL into a fresh window** -> the same view, because the host's
      SPA fallback answers the extensionless path with `index.html`; Back/Forward walk the
      history correctly. Over a web link the `/<token>/` prefix must survive every hop. Opening
      the folder over `file://` (no host at all) must take the documented full-navigation
      fallback rather than erroring.

## 8. Fail-closed extensions & clean shutdown

- [ ] Without **cryptoXT** -> encryption / editor / Tor off with a clear message; Share-code and
      Web-link still work.
- [ ] Without **OnionXT** -> Private/Tor path off; the other two work.
- [ ] Quit via window close **and** via a standalone Cmd-Q -> `qsStop` runs (session stops, Tor
      and web listener torn down, temp `.enc` files deleted).

---

## Section tally

Fill this in **as you go**, one verdict per section. It exists because this file is the record
sheet for two runbook sittings that split it (in the suite runbook at the monorepo root,
`docs/OXT-PASS-RUNBOOK.md`: session S1's stretch row **S** takes the web-link half, session
S2's item **7** the Tor half), and a half-finished pass that reports only its failures
cannot be told apart from one that never reached those items at all. `PASS` = every item in the
section passed; `FAIL` = at least one did not (the failure itself goes in Results below);
`PARTIAL` = some items were not reached — say which; `SKIP` = the whole section was out of reach
(no Tor daemon, no second machine, cryptoXT absent).

```
0.  Build & smoke                    ____      4.  Response headers & HTTP    ____
1.  Custom routes - functional       ____      5.  CORS preflight             ____
1a. :param routes                    ____      6.  Editor login throttle      ____
2.  Custom routes - security         ____      6a. Admin panel + upload       ____
3.  Observability endpoints          ____      7.  Webapp demo                ____
                                               8.  Fail-closed + shutdown     ____
transport: web link ____ / Tor ____            date ________  engine ____________
```

## Results

Bring back a line per failed/surprising item (and the mtime finding from section 4). Format that
travels well:

```
4. Date header: PASS
5. CORS preflight non-cors path: FAIL - Access-Control-Allow-Headers still present
4. cheap single-file mtime: <yes: `the detailed files`-free way is ... / no: folder scan only>
```
