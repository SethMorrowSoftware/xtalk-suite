# Building a standalone app

No Cloud Quick Share is a single stack script, and it is **standalone-ready**: the UI
self-builds on every launch (nothing needs to persist in the stackfile), every handler
declares its variables (strict / `explicitVariables`-clean), and quitting is caught by
`shutdownRequest`, so a packaged `.exe` / `.app` / Linux binary shuts its session down
cleanly even on Cmd-Q or a Dock quit.

## Before you package

Confirm it runs from source first (the Quick start in `../README.md`): create a one-card
mainstack, paste `../src/nocloudquickshare.livecodescript` into its **stack script**,
compile, then close and reopen the window. If it builds its UI and logs "ready", you are
ready to package.

## In the standalone builder

1. **Include the required extension:** `org.openxtalk.library.torrent` (**TorrentXT**).
   Without it there is no session and nothing can be shared or downloaded.
2. **Include SodiumXT if you want its features:** `org.openxtalk.library.sodium` - the
   passphrase encryption, the LAN web-editor password, and the Private / Tor path. It
   fails closed with a clear message when absent, so it is safe to ship with or without.
3. **OnionXT is not in the builder, and needs no ticking.** It is pure LiveCodeScript with
   no packaged extension and no `org.openxtalk.*` id; since 2026-08-24 the stack script
   carries it, so the Tor path ships with the script. At runtime the Tor path still needs
   SodiumXT and a **local Tor daemon** on the user's machine (system tor on
   `127.0.0.1:9051`, or Tor Browser on `9151`).
4. **Include the Internet library (libURL).** It is used only for the public-IP lookup on
   the web-link path and is harmless if left out (the lookup is `try`-guarded).
5. **Include the JSON Library** if end-users should be able to add their own API endpoints
   with a `.qsroutes.json` in the shared folder (see `user-routes.md`). Without it the
   custom-routes feature is simply off and everything else works. (`JSONToArray` works in
   the IDE without this, but a standalone needs the library ticked in Inclusions.)
6. **Nothing else.** No other inclusions, externals, fonts, or bundled resources are
   needed. The web-app demo in `../webapp/` is *content the user serves*, not something
   the standalone must bundle.

## Runtime facts to know

- **Downloads land in `Documents/No Cloud Quick Share`** on every platform (created on
  first use).
- **The release version** is the constant `kQsAppVersion` (currently `1.0.0`). It appears
  in the window title, the startup log line and the `version` field of `/_qs/info`; the
  HTTP `Server:` header carries no version. Bump it when you cut a release so bug reports
  identify their build.
- **The UI version** is a separate constant, `kQsUiVersion`. A saved stack rebuilds its
  UI when it differs; a fresh standalone always builds clean, so it matters only when you
  change the generated layout.
- **The web-link path opens a router port** via UPnP / NAT-PMP (through TorrentXT) and
  looks up the public IP; where the router will not cooperate, the local-network link
  still works and the app explains the state.

## Per-platform notes

- The app has no native code of its own; the standalone builder bundles the prebuilt
  extensions above for the target platforms you select.
- The Tor daemon is a runtime dependency on the end user's machine, not something you
  bundle.
- Test each packaged target with at least the **Share code** and **Web link** paths and,
  if you shipped SodiumXT, a passphrase share and a Tor share with a daemon running.
