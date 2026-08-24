# No Cloud Quick Share

**Send any file to anyone. No cloud, no account, no size limit — it goes straight
from your device to theirs.**

No Cloud Quick Share is a tiny peer-to-peer file-sharing app: drag a file onto the
window, get a short code, and send that code to a friend. They paste it in and the
file transfers directly from your machine to theirs. There is no server in the
middle, nothing is uploaded anywhere first, and there is no size cap. It is one
self-contained [OpenXTalk](https://openxtalk.org) / xTalk stack built on the
BitTorrent DHT, with optional Tor anonymity and end-to-end encryption.

> **"No cloud" is not the same as "anonymous," and not the same as "encrypted."**
> Which protections you get depends on how you share. Please read
> **[docs/what-it-hides.md](docs/what-it-hides.md)** — the honest page — before
> sending anything sensitive.

## Three ways to share

| Method | What it is | Your IP hidden? | Encrypted? | Recipient needs the app? |
|---|---|---|---|---|
| **Share code** | Plain BitTorrent over the DHT. The code *is* the file's content-address. Resumes if interrupted. | No | Optional (passphrase) | Yes |
| **Web link** | A plain `http://` link that opens in any browser. Serve a file, a folder, or a whole website. | No | No | No — any browser |
| **Private / Tor** | The bytes ride a Tor onion; both IP addresses are hidden and no torrent is created. | **Yes** | Optional (passphrase) | Single file: yes; folder/browser: no |

Any file can be locked with a **passphrase** (optional, needs SodiumXT): the network
only ever sees ciphertext under a neutral name, and a wrong passphrase is caught
before anything downloads.

## Quick start

1. **Install [OpenXTalk](https://openxtalk.org) (OXT).** (It also runs in LiveCode
   9.6.3+, but OXT is the target.)
2. **Install the extensions** via `Tools > Extension Manager`:
   - **TorrentXT** — `org.openxtalk.library.torrent` — **required**.
   - *(optional)* **SodiumXT** — `org.openxtalk.library.sodium` — for the passphrase
     encryption and the LAN web editor.
   The app detects each and **fails closed with a clear message** when one is missing;
   every other feature still works.

   *(nothing to install)* **OnionXT** is CARRIED INSIDE this app since
   2026-08-24 - `src/nocloudquickshare.livecodescript` embeds
   `../onionxt/src/onionxt.livecodescript` verbatim between the sentinels
   `tools/sync-demo-embeds.py` owns, so the `start using stack "onionxt"` step this
   list used to carry is GONE and the Tor path is there the moment you paste the
   script. (Only the `ox*` layer is carried: Quick Share never calls the `oxh*` one,
   because it ships its own HTTP server.) What the Private / Tor path still needs
   from you is a local **Tor daemon** with its control port enabled; without one it
   fails closed the same way the two above do. Never edit inside the sentinels -
   change `../onionxt/src/onionxt.livecodescript` and re-run that tool.
3. **Run the app** (it builds its own UI — no manual layout):
   1. `File > New Mainstack` (a one-card stack).
   2. `Object > Stack Script`.
   3. Open [`src/nocloudquickshare.livecodescript`](src/nocloudquickshare.livecodescript),
      copy all of it, paste into the stack script, and apply/compile.
   4. **Close the stack window and reopen it.** Reopening builds the UI and starts a
      session.
   5. Use it. **Close the window when done** so it shuts the session down cleanly.

## How it works

Two proven technologies, no central server:

- **The DHT** (a giant shared address book) remembers *where* things are. The share
  code is the file's info-hash, so the DHT can introduce the two machines with no
  tracker and no server.
- **BitTorrent** moves the actual bytes directly between the two computers.

For the **web link** path, the app runs a small streaming HTTP server (with automatic
router port-opening via UPnP/NAT-PMP) so any browser can download — a single file, a
browsable folder, or a whole static website (SPA routing, HTTP Range, a live
`/_qs/info` backend route). For the **Tor** path, the bytes travel over an OnionXT
onion stream so neither side learns the other's address.

The sending window must stay open until the transfer finishes — the file lives only
on your machine, never on a server. That is the privacy feature *and* the one
operational limit (there is no "upload and walk away").

## Requirements

| Extension | Library id | Required? | Provides |
|---|---|---|---|
| **TorrentXT** | `org.openxtalk.library.torrent` | **Yes** | the session, DHT, BitTorrent, magnets, UPnP |
| **SodiumXT** | `org.openxtalk.library.sodium` | No | passphrase encryption (Argon2id + secretstream); LAN editor password |
| **OnionXT** + local Tor | — | No | the Private / Tor path (needs SodiumXT too) |
| Internet library (libURL) | — | No | public-IP lookup for the web link (try-guarded) |

## The bundled web app

[`webapp/`](webapp/) is a self-contained single-page app you can drop into a served
folder to demonstrate hosting a real website over a web link or a Tor page. It stages
a whole little internet from one folder — an image **gallery**, a **streaming cinema**
(a procedural short film that seeks over HTTP Range, in WebM *and* MP4), a **music**
page with a playlist player, a **storefront** with a cart and real `?dl` forced-download
delivery, a **blog** with shareable deep links, a service worker, a PWA manifest, and
the live `/_qs/info` backend route. See [docs/webapp.md](docs/webapp.md).

## Building a standalone

The app is standalone-ready (self-building UI, clean shutdown on quit, per-user save
folder). Include the TorrentXT extension (required) and SodiumXT (optional) in the
standalone builder. **OnionXT is not an extension** and cannot be ticked there -
see the note above; copy its script library into the app instead. See [docs/building-a-standalone.md](docs/building-a-standalone.md).

## Development

There is **no headless way to compile or run** a `.livecodescript`, so the automated
safety net is two static gates — run both before every change:

```sh
python3 tools/check-livecodescript.py     # lints the stack script
python3 tests/fileserver_golden.py        # pins the pure-logic HTTP/util helpers
```

Then do a manual **OXT pass** (paste the script into a stack, close+reopen, exercise
it). See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the workflow and
**[CLAUDE.md](CLAUDE.md)** for the full engineering playbook and the hard-won
OpenXTalk-runtime lessons. Report issues privately per **[SECURITY.md](SECURITY.md)**.

## License

MIT — see [LICENSE](LICENSE). Built on the OpenXTalk extension family (TorrentXT /
SodiumXT / OnionXT), which wrap libtorrent-rasterbar (BSD-3), libsodium (ISC), and
Boost (Boost Software License) under their own permissive terms.

---

*No Cloud Quick Share began life as a demo in the [TorrentXT](https://github.com/SethMorrowSoftware/TorrentXT)
repository and graduated into its own project.*
