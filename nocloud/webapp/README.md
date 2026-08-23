# No Cloud Quick Share Web App Demo

A self-contained **single-page app** meant to be hosted straight out of a folder by
**No Cloud Quick Share** (`../src/nocloudquickshare.livecodescript`) - over **Tor** or
a **direct web link**. It plays a whole little internet - an art gallery, a streaming
cinema, a record shelf, a storefront with a working cart, a blog, and a live backend
call - to show, in one place, everything the built-in web host can do. See
`../docs/webapp.md` for the full contributor guide.

## Host it

1. Open `nocloudquickshare.livecodescript` in OpenXTalk and run it.
2. Drag **this `webapp` folder** onto the drop area.
3. Share it:
   - **Over Tor** - the app is served at the onion root (`http://<addr>.onion/`). Tor
     Browser treats a `.onion` as a **secure context**, so the service-worker check on
     the About page lights up.
   - **Over a web link** - pick the **Web link** method; the app lives under
     `http://<ip>:<port>/<token>/`. Open it in any browser.
4. (Optional) tick **Enable web editing**, set a password, and open the link with
   `/_edit` on the end to edit these files from a browser on your LAN.

Because every asset path is **relative**, the exact same folder works at the root (Tor)
or under `/<token>/` (web link) with no build step and no `<base>` tag.

## What it demonstrates

| Feature | Where |
|---|---|
| Static hosting with correct **MIME types** | `.html .css .js .svg .png .jpg .wav .mp3 .mp4 .webm .zip .json .webmanifest` all served correctly |
| **HTTP Range** (streaming + seek) | the **Theater** scrubs/chapter-jumps a real short film; **Music** scrubs three MP3s (and the original `.wav`) |
| Multi-format video | the film is offered as `video/webm` (VP9) *and* `video/mp4` (H.264); the browser picks |
| **Forced downloads** (`?dl`) | the **Store** delivers real files as `Content-Disposition: attachment`; the Gallery lightbox has a download link |
| **SPA routing** with refresh support | every tab is a real route; the server falls back to `index.html` for unknown dot-free routes (`qsSiteSpaTarget`) |
| Shareable **deep links** | `blog?post=<slug>` - the slug rides the query string so relative assets survive a refresh at any mount point |
| **Raster + vector images** | the **Gallery** (8 SVG + 1 PNG) with a keyboard-navigable lightbox, list fetched from `data.json` |
| Client-side state | the Store cart lives in `localStorage` and survives refreshes; checkout is a real receipt of real files |
| **Live backend route** | the **Backend** tab calls `GET /_qs/info` and shows the JSON |
| **User-declared routes** (`.qsroutes.json`) | the **Backend** tab also calls `GET /api/echo` - declared in this folder's own `.qsroutes.json`, not in LiveCode. The file ships six demo routes: canned JSON, a `{{...}}` templated echo, a `:name` path capture, `config.json` served as a `file` route at `/api/config`, and a `/go/gallery` redirect. See `../docs/user-routes.md` |
| **Conditional GET** (weak ETag / `304`) | every file response carries `ETag: W/"size-seed-generation"` + `Cache-Control: no-cache`, so a revisiting browser revalidates instead of re-downloading; a save through `/_edit` bumps the generation. The one stale case is in `sw.js`'s header comment. *(Verified statically + golden-pinned; needs an OXT pass)* |
| **Tor vs. web** awareness | the header badge and the **About** tab (secure-context / service-worker) |

## Files

```
index.html          shell: relative <link>/<script>, header, nav, footer
app.css             one stylesheet, light + dark via prefers-color-scheme
app.js              dependency-free router + views (base-path aware)
data.json           gallery manifest, fetched at runtime
store.json          storefront catalog (products, prices, download files)
blog.json           blog posts (slugs, structured bodies), fetched at runtime
.qsroutes.json      six user-declared demo routes the host reads at share time (the
                    Backend tab's /api/echo among them) - a dotfile, so it is read by
                    the host but never served or listed; see ../docs/user-routes.md
config.json         tiny JSON that the .qsroutes.json "file" route streams from disk
                    at /api/config (Range-aware, folder-confined, like any static file)
site.webmanifest    PWA manifest (installable)
sw.js               minimal service worker (registers only in a secure context; no caching
                    of its own - freshness rides the host's weak-ETag revalidation, see the
                    comment in sw.js for the one stale case)
assets/
  logo.svg          app mark / favicon
  art-01..08.svg    gallery artwork (pure SVG)
  photo.png         a generated raster image (image/png)
  stickers.svg      the sticker-sheet product
  film.webm         "First Light" (46 s, VP9+Opus) - the Theater feature
  film.mp4          the same film in H.264+AAC (faststart) for browsers without VP9
  film-poster.jpg   the poster frame (image/jpeg)
  loop.webm         a 10 s seamless ambient loop (VP9, ~29 KB)
  chime.wav         a short tone (the original Range demo, now the Music interlude)
  music/
    first-light.mp3   ambient title theme (procedurally composed)
    packet-rain.mp3   pluck arpeggios
    harbor.mp3        slow pads + deep bass
  store/
    art-pack.zip      the 8 gallery SVGs, zipped (application/zip)
    prod-*.svg        product thumbnails
```

All media is **generated, not sourced**: the film is procedural (ffmpeg lavfi scenes),
the music is a deterministic little synthesizer, the art is hand-written SVG - so the
folder stays honest to its own pitch: no CDN, no external fonts, no network calls other
than to the folder itself. It runs unchanged offline, over Tor, and under a strict CSP.

## The routing rule (worth knowing before you add pages)

Routes are deliberately **single-segment** (`gallery`, `theater`, `checkout`, ...). A
nested path like `blog/some-post` would move the document's base directory on refresh,
so the shell's *relative* `app.js`/`app.css` would resolve to dotted paths that get a
real 404 instead of the SPA fallback. Deep links into content therefore use the
**query string** (`blog?post=some-post`), which survives refresh at any mount point
with zero asset breakage.
