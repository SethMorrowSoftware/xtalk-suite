# Hosting onion services in OpenXTalk (files, sites, apps)

Host Tor onion services from an OXT app, with no web server, no hosting, and no
port forwarding. It serves HTTP over an onion using **OnionXT's own accept loop**
via the `src/onion-httpd.livecodescript` module (`oxh*`). It depends on nothing
but OnionXT and that module: the engine's HTTPD Library is not present on every
OpenXTalk engine (`httpdStart` raised "handler not found" on one), so this runs
wherever OnionXT runs.

```
Tor  --(onion:80)-->  OnionXT accept loop (loopback-guarded, proven)
                          |  onPeer / onStreamData
                      onion-httpd (oxh*)  <- parses the request, routes it, replies
                          |
                      a shared folder  /  your route handlers  /  a static site
```

## Share a folder of files (the file-sharing use case)

One call turns a folder into a private, anonymous file-share:

```
oxhServeFiles "/full/path/to/a/folder"
```

Then, at the onion address, a visitor gets an **auto-generated directory-listing
page** (file names and download links) and can **browse into
subfolders**. You do not write any HTML. Every file is served at its path with the
right MIME type (images preview, PDFs open, everything else downloads), file names
are HTML-escaped so a crafted name cannot inject markup, and `..` traversal is
refused. If a folder happens to contain its own `index.html`, that is served
instead of the listing.

`spike.livecodescript` is exactly this: click **Start**, then **Share Folder**,
pick a folder, and open the printed `http://<address>.onion/` in Tor Browser.

## The rest of the `oxh*` API

| call | does |
|---|---|
| `oxhInit the long id of me` | where your route handlers live |
| `oxhServe pVirtualPort, pLocalPort` | publish an onion and serve HTTP on it (returns the handle) |
| `oxhServeFiles pFolder` | share a folder: files + an auto directory listing |
| `oxhSetRoot pFolder` | static-site mode: serve files, `/` -> `index.html`, no listing (safe default) |
| `oxhRoute pMethod, pPath, pHandler` | a dynamic route; handler is `pHandler pStream, pRequest` |
| `oxhUnroute pMethod, pPath` | remove a route (switch what a path serves at runtime) |
| `oxhReply pStream, pCode, pBodyText, pHeaders` | reply from a route handler |
| `oxhStop pService` | tear the onion down |

A request array carries `__method`, `__path`, `__query`, `__body`, and the
lowercased request headers. The module handles request framing (buffer until the
head and any `Content-Length` body arrive; a request head over 256 KB,
`kOxhMaxRequest`, is refused), a folder-URL redirect so relative links resolve,
the exact-`Content-Length` response, and the clean close.

## Two ways to use this

- **One paste-and-run stack (fastest):** `spike.livecodescript` carries both
  libraries between the sentinels `tools/sync-demo-embeds.py` owns (edit `src/` and
  re-run that tool; never edit inside the sentinels). New mainstack -> Object menu
  -> Stack Script -> paste all of it -> Apply; have tor with the **control port
  enabled** (OnionXT README Troubleshooting); reopen the stack so `preOpenStack`
  builds the UI; then **Start** -> **Share Folder** -> open the printed `.onion`
  in **Tor Browser**.
- **As libraries (what a real app does):** `start using` both
  `src/onionxt.livecodescript` and `src/onion-httpd.livecodescript` and build on
  top. Use the spike as a reference, not as the stack script: pasting it whole
  while the libraries are loaded defines the same handlers twice, which OXT refuses
  at compile time. Copy the parts you want, or delete the embedded region first.

## Status / notes

- **Confirmed on-engine:** hosting a folder as a browsable file share (with the
  auto directory listing), a static site, and dynamic routes all render in Tor
  Browser, both as libraries and as the single paste-and-run stack. The spike's
  UI moved onto the suite kit 2026-08-14, so the stack as a whole is verified
  statically and needs an OXT re-pass.
- **Large files:** a file is read into memory and sent in one response - right for
  documents, images, and modest archives; streaming and HTTP Range (resumable /
  seekable) downloads are a later addition, so multi-GB files are not ideal over
  Tor yet.
- **Receiving files (upload)** is a separate feature: the module parses POST bodies
  (`__body`), but a real upload endpoint needs a multipart route handler that
  writes to disk - straightforward to add when you want two-way transfer.
- OnionXT is callback-driven, but a served file is read whole in one blocking
  step: right for a lightweight self-hosting appliance, not a high-traffic server.
- If the local forward port (8090) reports `cannot listen ...`, change `kLocalPort`
  to a free one (same Windows reserved-port note as the main demo).
