# Hosting onion services in OpenXTalk (files, sites, apps)

Host Tor onion services from an OXT app, with no web server, no hosting, and no
port forwarding. It serves HTTP over an onion using **OnionXT's own accept loop**
via the `src/onion-httpd.livecodescript` module (`oxh*`) - it depends on nothing
but OnionXT and that module (no engine-shipped HTTPD Library), so it runs wherever
OnionXT runs.

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
head and any `Content-Length` body arrive), a folder-URL redirect so relative
links resolve, the exact-`Content-Length` response, and the clean close.

## Two ways to use this

- **As libraries (best for a real project):** `start using` both
  `src/onionxt.livecodescript` and `src/onion-httpd.livecodescript`, and build your
  app on top (`spike.livecodescript` is one such app). The library sources are the
  single source of truth.
- **As one paste-and-run stack (best for quick testing):** `spike.livecodescript`
  ITSELF carries both libraries, embedded between the sentinels that
  `tools/sync-demo-embeds.py` owns - paste it into one mainstack's stack script and
  it self-builds its UI, with no `start using` wiring. Edit the sources under
  `src/` and re-run that tool; never edit inside the sentinels. (Before
  2026-08-17 this was a separate generated `standalone.livecodescript`; the suite
  tool embeds in place instead, so there is one file to open, not two.)

## How to run

**Paste-and-run (fastest):**
1. New mainstack -> Object menu -> Stack Script -> paste all of
   `spike.livecodescript` -> Apply.
2. tor with the **control port enabled** (OnionXT README Troubleshooting).
3. Reopen the stack (so `preOpenStack` builds the UI), then **Start** ->
   **Share Folder** -> open the printed `.onion` in **Tor Browser**.

**Libraries (what a real app does):**
1. Put **both** `src/onionxt.livecodescript` and `src/onion-httpd.livecodescript`
   in the message path (`start using` them).
2. Use `spike.livecodescript` as a reference, not as the stack script - pasting it
   whole while the libraries are also loaded defines the same handlers twice, which
   OXT refuses at compile time. Copy the parts you want, or delete the embedded
   region between the sentinels first.
3. tor with the control port enabled; **Start**, **Share Folder**, open the `.onion`.

## Status / notes

- **Confirmed on-engine:** hosting a folder as a browsable file share (with the
  auto directory listing), a static site, and dynamic routes all render in Tor
  Browser, both as libraries and as the single paste-and-run stack.
- **Large files:** a file is read into memory and sent in one response - right for
  documents, images, and modest archives; streaming and HTTP Range (resumable /
  seekable) downloads are a later addition, so multi-GB files are not ideal over
  Tor yet.
- **Receiving files (upload)** is a separate feature: the module parses POST bodies
  (`__body`), but a real upload endpoint needs a multipart route handler that
  writes to disk - straightforward to add when you want two-way transfer.
- Single-threaded and blocking, like OnionXT itself: right for a lightweight
  self-hosting appliance, not a high-traffic server.
- If the local forward port (8090) reports `cannot listen ...`, change `kLocalPort`
  to a free one (same Windows reserved-port note as the main demo).
