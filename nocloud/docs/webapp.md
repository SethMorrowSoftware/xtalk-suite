# The Web-App Demo (`webapp/`)

`webapp/` is a self-contained **single-page web app** that ships as sample content for
**No Cloud Quick Share**. It is not part of any extension and it is not required to run
Quick Share - it exists purely to *demonstrate* everything the built-in web host can
do, staged as a small believable internet: an art **gallery** with a lightbox, a
streaming **cinema**, a **record shelf** with a playlist player, a **storefront** with
a cart and real digital delivery, a **blog** with shareable deep links, and a live
**backend** call. Point Quick Share at this folder, share it over Tor or a direct web
link, open the address, and you are looking at the demo.

Read this after `../README.md`: it explains what the demo is, how the host serves it,
and the design constraints (relative paths, single-segment routes) that let the same
folder work over both transports.

## What it is

A dependency-free SPA - plain HTML/CSS/JS, **no build step, no framework, no CDN, no
external fonts** - that makes **no network calls other than to the serving folder
itself**. Every media asset is generated rather than sourced (a procedural short film,
synthesized music, hand-written SVG), so the folder is fully self-hosted in spirit as
well as in mechanics: it runs unchanged offline, over Tor, and under a strict CSP.
The tabs (`Home`, `Gallery`, `Theater`, `Music`, `Store`, `Blog`, `Backend`, `About`,
plus a nav-hidden `checkout`) are real client-side routes, each wired to specific host
capabilities.

## What it demonstrates

| Capability | Where in the demo | How the host is exercised |
|---|---|---|
| **Static hosting, correct MIME** | every file | one of each interesting type - `.html .css .js .json .webmanifest .svg .png .jpg .wav .mp3 .mp4 .webm .zip` - served with the right content type |
| **HTTP Range** (stream + seek) | **Theater**, **Music** | the film's chapter buttons and any scrub issue byte-range requests answered `206 Partial Content`; the page narrates the seek so visitors see the mechanism |
| **Multi-format video** | **Theater** | one `<video>` with two `<source>`s - `film.webm` (VP9) then `film.mp4` (H.264, `+faststart`); the browser takes the first it can decode |
| **Forced downloads** | **Store**, Gallery lightbox | any file URL with `?dl` is served `Content-Disposition: attachment` (`qsHttpDisposition`), so "checkout" delivers real files with their real names |
| **SPA routing, refresh-safe** | all tabs | routes are pushed with `history.pushState`; the host falls back to `index.html` for any unknown dot-free route (`qsSiteSpaTarget`) and `app.js` restores the view from `location.pathname` |
| **Query-string deep links** | **Blog** | a post's link is `blog?post=<slug>` - shareable, refresh-safe, and safe for relative assets (see the routing rule below) |
| **Client-side state** | **Store** | the cart lives in `localStorage` (with an in-page fallback), so it survives refreshes without the server keeping any state |
| **Live backend route** | **Backend** tab + startup | `GET /_qs/info` is answered by the stack script (`qsHttpRoute` -> `qsHttpReply`); the tab auto-calls it and pretty-prints the JSON, and startup uses its `mode` field for the transport badge. The tab also fires `OPTIONS /` (the `Allow` header) and surfaces the response headers |
| **User-declared routes** (`.qsroutes.json`) | **Backend** tab, second card | the folder ships its own `.qsroutes.json` with six demo endpoints; the tab live-calls `GET /api/echo?msg=...`, a `{{...}}`-templated route that reflects the query value back escaped - declared in the folder, not in LiveCode. See "The routes the host provides" below and `user-routes.md` |
| **Conditional GET** (weak ETag / `304`) | every file request on a revisit | file responses carry `ETag: W/"size-seed-generation"` (`qsHttpWeakETag`) + `Cache-Control: no-cache`, so the browser revalidates each load and a matching `If-None-Match` is answered `304` with no body *(verified statically + golden-pinned; needs an OXT pass)* |
| **Raster + vector images** | **Gallery** | eight `.svg` pieces + one `.png`, list fetched from `data.json`, keyboard-navigable lightbox with raw/download links |
| **Service worker (secure context)** | **About** tab | `sw.js` registers only when `window.isSecureContext` - proving a Tor `.onion` counts as secure while plain public http does not |
| **PWA manifest** | `site.webmanifest` | installable app metadata, icon, `standalone` display, relative `start_url`/`scope` |
| **Tor vs. web awareness** | header badge + About | `.onion` hostname / `/_qs/info` `mode` drive "Served over Tor" / "Served over the web" / "Static preview" |
| **Light + dark** | `app.css` | `prefers-color-scheme` + CSS custom properties, one stylesheet |

## How the host serves it

Quick Share is an OpenXTalk stack (`../src/nocloudquickshare.livecodescript`) that runs
a small streaming HTTP host. Serving the demo is entirely a runtime action - nothing is
compiled or copied:

1. Open `nocloudquickshare.livecodescript` in OpenXTalk and run it.
2. Drag **this `webapp` folder** onto the drop area (or use the Choose a folder button).
3. Share it:
   - **Over Tor** - the app is served at the onion root, `http://<addr>.onion/`. Tor
     Browser treats a `.onion` as a **secure context**, so the About tab's
     service-worker check registers and lights up.
   - **Over a direct web link** - pick the **Web link** method; the app is served under
     `http://<ip>:<port>/<token>/` and opens in any browser.
4. *(Optional)* enable the LAN-only **web editing** option and set a password. Then either
   append **`/_edit`** to the link for the raw file editor, or click **Admin** in the
   demo's own footer for the friendly **site-admin panel** (see below). The service worker
   deliberately does no caching, and every editor write bumps the host's ETag generation,
   so edits made through the editor show up immediately (the honest caveat for
   out-of-band disk edits is in the Editing notes below).

### The admin panel (the live editor, with a face)

The footer's **Admin** link opens `#admin`, a real content manager built entirely on the
host's LAN-only editor API - no second server, no cloud:

- It **probes reachability** first (an empty `POST /_edit/login`, which the host answers
  `400`/`429` when the editor is live and `404` otherwise). Over Tor, the public web, or a
  static preview it degrades to an honest explainer - the editor simply is not there.
- After a password login (throttled server-side; the session token lives in
  `sessionStorage`), tabs edit **Store**, **Gallery** and **Blog** as forms over
  `store.json` / `data.json` / `blog.json`, plus a **Files** tab to browse, upload and
  delete. Every write is a `PUT /_edit/api/write` of pretty-printed JSON; saves go live at
  once (the page drops its manifest cache so the public views refetch).
- **Media uploads stream in slices:** the first 192 KB goes to `PUT /_edit/api/write`
  (create/truncate) and each further slice to `PUT /_edit/api/append`, so a file larger
  than the host's 256 KB request cap arrives in bounded pieces - the download path's
  fixed-slice discipline, in reverse. A single upload is capped at **1 GiB total**
  (`kEditMaxUploadBytes`); uploads land in `assets/uploads/`, and missing parent folders are
  created by the host (`qsEditEnsureFolders`). Hidden (dot-leading) paths cannot be created
  through the editor, so an upload can never plant an invisible file.
- The whole panel is **fail-closed and same-origin**: it can do nothing the raw editor
  could not, and the editor is LAN-only, password-gated and off by default.

### The routes the host provides for it

- **SPA fallback (`qsSiteSpaTarget`).** Any request that looks like an app route but is
  not an existing file is answered with `index.html`. That is what makes deep links and
  refresh work: refresh on `.../theater` and the host returns the shell, then `app.js`
  reads the path and re-renders the Theater view.
- **Dynamic route (`GET /_qs/info`).** Registered in the stack with
  `qsHttpRoute "GET","/_qs/info",<handler>` and answered with `qsHttpReply`. It returns
  JSON including a `mode` field (`tor` / `clearweb`) that the demo uses to label the
  transport. Add your own with `qsHttpRoute "GET","/api/thing","myHandler"` replying via
  `qsHttpReply` - the Store's checkout page sketches a `POST /api/order` the same way.
- **HTTP Range.** The host serves partial content one bounded slice at a time, so the
  `<video>` and `<audio>` elements stream and seek multi-megabyte (or multi-gigabyte)
  files without the sharer's machine ever holding a whole file in memory.
- **Forced download (`?dl`).** `qsHttpDisposition` serves `inline` by default and
  `attachment` when the query carries `dl` - the Store's entire delivery mechanism.
- **Editor API (LAN-only, auth-gated).** `POST /_edit/login`, `GET /_edit/api/list`,
  `GET /_edit/api/read`, `PUT /_edit/api/write`, `PUT /_edit/api/append` and
  `POST /_edit/api/delete`. Every one gates on `qsEditAuthed` (enabled + LAN-local +
  served-folder + session token) and confines paths with `qsEditSafePath`; over Tor or
  the public web they answer `404`. The Admin panel is a pure client of these.
- **User-declared routes (`.qsroutes.json`).** The folder carries one, so sharing it also
  demonstrates the declarative route layer: canned JSON (`/api/hello`, `/api/note`), the
  `{{...}}`-templated echo the Backend tab calls (`/api/echo` - reflected values escaped
  default-deny), a `:name` path capture (`/api/greet/:name`), `config.json` streamed
  under `/api/config` (a `file` route: Range-aware, ETag'd and folder-confined exactly
  like a static file), and a `/go/gallery` redirect (re-based onto the `/<token>/` mount
  over a web link). No code runs, `/_qs` and `/_edit` stay reserved, and the dotfile
  itself is never served or listed. The full model, its guards and its limits are
  `user-routes.md`; the golden pins the guard logic. *(Verified statically +
  golden-pinned; needs an OXT pass - `oxt-pass-checklist.md` is that pass's script.)*
- **Conditional GET (weak ETag -> `304`).** Every file response - static assets and
  `.qsroutes.json` `file` routes alike - carries `ETag: W/"size-seed-generation"`
  (`qsHttpWeakETag`) plus `Cache-Control: no-cache`, and a full-file request with a
  matching `If-None-Match` is answered `304 Not Modified` with no body (a `Range:`
  request always gets bytes, never a `304`). Non-file answers (`/_qs/*`, user-route
  bodies, listings) are sent with no validator, so they are regenerated every request.
  This is what makes browser caching safe for the demo; the freshness caveat is in the
  Editing notes below. *(Verified statically + golden-pinned; needs an OXT pass.)*

## The two design constraints

**1. Relative paths.** Every asset URL and every generated link is **relative**, never
rooted at `/`. The router in `app.js` derives its base by scanning
`location.pathname` for the right-most segment that names a known route. That single
rule is why the *same untouched folder* works both at the root (`/`, over Tor) and
under `/<token>/` (over a web link) with **no `<base>` tag and no rebuild**. The
manifest follows suit: `start_url` and `scope` are `./`.

**2. Single-segment routes.** A consequence of rule 1: a nested route path like
`blog/my-post` would change the document's base directory when loaded directly, so the
shell's relative `app.js`/`app.css` would resolve to `blog/app.js` - a dotted path
that gets a real 404 instead of the SPA fallback, leaving an unstyled dead page. So
every route is one segment (`store`, `checkout`, ...) and deep links into content ride
the **query string** (`blog?post=my-post`), which is invisible to path resolution and
therefore refresh-safe at any mount point. If you add pages, keep paths relative
(`assets/foo.svg`, not `/assets/foo.svg`) and routes flat, or you will break the
web-link (token-prefixed) case.

## Files

```
index.html          shell: relative <link>/<script>, header, nav, footer, manifest link
app.css             one stylesheet, light + dark via prefers-color-scheme
app.js              dependency-free router + views (base-path aware; transport detection)
data.json           gallery manifest, fetched at runtime
store.json          storefront catalog: products, blurbs, prices, download files
blog.json           blog posts: slugs, dates, teasers, structured bodies (p/h/code/ul)
.qsroutes.json      six user-declared demo routes, read by the host at share time - a
                    dotfile, never served or listed (see user-routes.md)
config.json         tiny JSON streamed by the .qsroutes.json "file" route at /api/config
site.webmanifest    PWA manifest (installable; relative start_url/scope)
sw.js               minimal service worker - registers only in a secure context; NO caching
assets/
  logo.svg          app mark / favicon
  art-01..08.svg    gallery artwork (pure SVG)
  photo.png         a raster image (image/png)
  stickers.svg      the sticker-sheet product (SVG with text)
  film.webm         "First Light", 46 s, VP9+Opus - the Theater feature presentation
  film.mp4          the same film, H.264+AAC with +faststart (moov atom up front)
  film-poster.jpg   poster frame (image/jpeg)
  loop.webm         10 s seamless ambient loop (VP9, ~29 KB)
  chime.wav         a short tone (audio/wav; the Music page's interlude)
  music/*.mp3       three procedurally composed tracks (audio/mpeg)
  store/
    art-pack.zip    the 8 gallery SVGs zipped (application/zip; a real product download)
    prod-*.svg      product thumbnails
```

## Editing notes for contributors

- **Keep every path relative and every route single-segment** (see above) - the two
  most important rules.
- **`sw.js` must stay cache-free.** It has no `fetch` handler on purpose, so the worker
  itself can never mask a live edit - but since the host grew conditional GET, that is
  only half the freshness story. The server tags every file response with a weak ETag
  (`W/"size-seed-generation"`, `qsHttpWeakETag` in the stack) plus `Cache-Control:
  no-cache`, so the *browser's* cache revalidates on every load: an edit through
  `/_edit` bumps the generation and always shows up immediately, while an out-of-band
  disk edit that keeps the byte size unchanged leaves the ETag intact and revalidates
  `304`-stale until the app is relaunched (a fresh per-launch seed). Do not add caching
  without a very good reason.
- **The demo must degrade gracefully in a plain static preview** (opened as files, or
  from a non-Quick Share server): the Backend tab and transport badge already fail
  closed with a clear message when `/_qs/info` is unreachable, and the JSON-driven tabs
  show a "could not load" line rather than a blank page. Preserve that.
- **Stay self-contained** - no CDN, no external fonts, no third-party network calls - so
  the demo keeps working offline, over Tor, and under a strict CSP.
- **Escape everything data-driven.** Every string that arrives from a JSON manifest goes
  through `esc()` before it touches `innerHTML`; keep that discipline for new fields.
- User-facing copy says **"No Cloud Quick Share."** Match that wording if you add UI text.
- The media is regenerable: the film/loop/poster come from ffmpeg `lavfi` scenes and the
  tracks from a deterministic numpy synthesizer. If you replace them, keep files small
  (this folder rides in a git repo) and keep the provenance honest - generated or
  properly licensed, nothing scraped.
