# No Cloud Quick Share Web App Demo

A self-contained **single-page app** meant to be hosted straight out of a folder by
**No Cloud Quick Share** (`../src/nocloudquickshare.livecodescript`), over **Tor** or a
**direct web link**. It stages a whole little internet (an art gallery, a streaming
cinema, a record shelf, a storefront with a working cart, a blog, and a live backend
call) to show everything the built-in web host can do. All media is **generated, not
sourced**: no CDN, no external fonts, no network calls other than to this folder.

## Host it

1. Run the app: `File > New Mainstack`, `Object > Stack Script`, paste all of
   `../src/nocloudquickshare.livecodescript`, apply, then close and reopen the window.
2. Drag **this `webapp` folder** onto the drop area.
3. Share it **over Tor** (served at the onion root, `http://<addr>.onion/`; Tor Browser
   treats a `.onion` as a secure context, so the service worker registers) or **over a
   web link** (served under `http://<ip>:<port>/<token>/`, in any browser).
4. (Optional) tick **Enable web editing**, set a password, and open the link with
   `/_edit` on the end to edit these files from a browser on your LAN.

Two rules keep the same folder working at both mount points: every asset path is
**relative** (no `<base>` tag), and routes are **single-segment**, with deep links in the
query string (`blog?post=<slug>`).

The full guide - what each tab demonstrates, the host routes it uses, the admin panel,
the file tree and the editing rules - is [`../docs/webapp.md`](../docs/webapp.md). The
folder's `.qsroutes.json` is explained in [`../docs/user-routes.md`](../docs/user-routes.md).
