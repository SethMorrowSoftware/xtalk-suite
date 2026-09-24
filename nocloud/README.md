# No Cloud Quick Share

**Send any file to anyone. No cloud, no account, no size limit - it goes straight
from your device to theirs.**

No Cloud Quick Share is a tiny peer-to-peer file-sharing app: drag a file onto the
window, get a short code, and send that code to a friend. They paste it in and the
file transfers directly from your machine to theirs. There is no server in the
middle, nothing is uploaded anywhere first, and there is no size cap. It is one
self-contained [OpenXTalk](https://openxtalk.org) / xTalk stack built on the
BitTorrent DHT, with optional Tor anonymity and end-to-end encryption.

> **"No cloud" is not the same as "anonymous", and not the same as "encrypted".**
> Which protections you get depends on how you share. If you are deciding whether to
> trust it, read **[docs/what-it-hides.md](docs/what-it-hides.md)** - the honest page -
> before sending anything sensitive.

## Three ways to share

| Method | What it is | Your IP hidden? | Encrypted? | Recipient needs the app? |
|---|---|---|---|---|
| **Share code** | Plain BitTorrent over the DHT. The code *is* the file's content-address. Resumes if interrupted. | No | Optional (passphrase) | Yes |
| **Web link** | A plain `http://` link that opens in any browser. Serve a file, a folder, or a whole website. | No | No | No - any browser |
| **Private / Tor** | The bytes ride a Tor onion; both IP addresses are hidden and no torrent is created. | **Yes** | Optional (passphrase) | Single file: yes; folder/browser: no |

Any file can be locked with a **passphrase** (optional, needs SodiumXT): the network
only ever sees ciphertext under a neutral name, and a wrong passphrase is caught
before anything downloads.

## Quick start

1. **Install [OpenXTalk](https://openxtalk.org) (OXT).** (It also runs in LiveCode
   9.6.3+, but OXT is the target.)
2. **Install the extensions** via `Tools > Extension Manager`:
   - **TorrentXT** - `org.openxtalk.library.torrent` - **required**.
   - *(optional)* **SodiumXT** - `org.openxtalk.library.sodium` - for the passphrase
     encryption, the LAN web editor and the Private / Tor path.

   **OnionXT needs no install:** it is carried inside the app's script since
   2026-08-24. The Private / Tor path also needs a local **Tor daemon** with its
   control port enabled (system tor, or Tor Browser running). The app detects each
   piece and **fails closed with a clear message** when one is missing; every other
   feature still works.
3. **Run the app** (it builds its own UI - no manual layout):
   1. `File > New Mainstack` (a one-card stack).
   2. `Object > Stack Script`.
   3. Open [`src/nocloudquickshare.livecodescript`](src/nocloudquickshare.livecodescript),
      copy all of it, paste into the stack script, and apply/compile.
   4. **Close the stack window and reopen it.** Reopening builds the UI and starts a
      session.
   5. Use it. **Close the window when done** so it shuts the session down cleanly.

## How it works

The **DHT** (a giant shared address book) introduces the two machines: the share code
is the file's info-hash, so no tracker and no server are needed. **BitTorrent** then
moves the bytes directly between the two computers.

For the **web link** path, the app runs a small streaming HTTP server (with automatic
router port-opening via UPnP/NAT-PMP) so any browser can download - a single file, a
browsable folder, or a whole static website (SPA routing, HTTP Range, a live
`/_qs/info` backend route). For the **Tor** path, the bytes travel over an OnionXT
onion stream so neither side learns the other's address.

The sending window must stay open until the transfer finishes - the file lives only
on your machine, never on a server. That is the privacy feature *and* the one
operational limit (there is no "upload and walk away").

## Requirements

| Component | Library id | Required? | Provides |
|---|---|---|---|
| **TorrentXT** | `org.openxtalk.library.torrent` | **Yes** | the session, DHT, BitTorrent, magnets, UPnP |
| **SodiumXT** | `org.openxtalk.library.sodium` | No | passphrase encryption (Argon2id + secretstream); the LAN editor password; the Private / Tor path needs it too |
| A local **Tor daemon** | - | No | the Private / Tor path (OnionXT itself is carried in the script) |
| Internet library (libURL) | - | No | the public-IP lookup for the web link (try-guarded) |
| JSON library | - | No | custom routes from a shared folder's `.qsroutes.json` |

## The bundled web app

[`webapp/`](webapp/) is a self-contained single-page app you can drop into a served
folder to demonstrate hosting a real website over a web link or a Tor page: an image
**gallery**, a **streaming cinema** (a procedural short film that seeks over HTTP
Range, in WebM *and* MP4), a **music** page, a **storefront** with real `?dl`
forced-download delivery, a **blog** with shareable deep links, a service worker, a
PWA manifest, and the live `/_qs/info` backend route. See [docs/webapp.md](docs/webapp.md).

## Building a standalone

The app is standalone-ready (self-building UI, clean shutdown on quit, per-user save
folder). Tick TorrentXT (required) and SodiumXT (optional) in the standalone builder;
OnionXT is not an extension and needs no ticking, because the script carries it. See
[docs/building-a-standalone.md](docs/building-a-standalone.md).

## Status

The app's runtime behaviour is "verified statically; needs an OXT pass" until the
engine pass in [docs/oxt-pass-checklist.md](docs/oxt-pass-checklist.md) is walked; no
dated engine pass of this stack is recorded yet.

## Documentation

| Document | What it is |
|---|---|
| [docs/what-it-hides.md](docs/what-it-hides.md) | The honest page: what each share path hides, and what it does not. |
| [docs/user-routes.md](docs/user-routes.md) | Custom HTTP endpoints for a shared folder, declared in a `.qsroutes.json` file. |
| [docs/webapp.md](docs/webapp.md) | The `webapp/` demo: what it shows, how the host serves it, how to edit it. |
| [docs/building-a-standalone.md](docs/building-a-standalone.md) | Packaging the app with the standalone builder. |
| [docs/http-server-deep-dive.md](docs/http-server-deep-dive.md) | The embedded HTTP host: architecture, contracts and design decisions. |
| [docs/oxt-pass-checklist.md](docs/oxt-pass-checklist.md) | The engine pass the app owes, and its own record sheet. |
| [CLAUDE.md](CLAUDE.md) | Maintainer and contributor guide: rules, traps, the evidence ledger, the definition of done. |
| [SECURITY.md](SECURITY.md) | How to report a vulnerability, and the security model. |
| [site/README.md](site/README.md) | The product landing page (static files, no build step). |

Suite-wide documents live in the xTalk suite's
[docs/](https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/README.md).

## Development and contributing

`bash tools/run-gates.sh` runs the three gates: the static script checker, the
file-server golden (`tests/fileserver_golden.py`, Python mirrors of the pure helpers)
and the execution gate (`tools/check-script-vectors.py`, which runs the shipped
script's pure helpers headlessly against those mirrors, after its own fixture test).
None of them is the engine, so a change still needs a manual **OXT pass** (paste the
script into a stack, close + reopen, exercise it) before anyone calls it working.

To contribute: read [CLAUDE.md](CLAUDE.md) first (the rules, the recipe for a new
pure-logic helper, the definition of done); open issues and pull requests at the
suite (below); say "verified statically; needs an OXT pass" for anything you did not
watch run; and report vulnerabilities privately per [SECURITY.md](SECURITY.md).

## License

MIT - see [LICENSE](LICENSE). Built on the OpenXTalk extension family (TorrentXT /
SodiumXT / OnionXT), which wrap libtorrent-rasterbar (BSD-3), libsodium (ISC), and
Boost (Boost Software License) under their own permissive terms.

---

*No Cloud Quick Share began life as a demo in the [TorrentXT](https://github.com/SethMorrowSoftware/TorrentXT)
repository and graduated into its own project.*

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

No Cloud Quick Share is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`nocloud/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/nocloud: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `nocloud/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port nocloud --ref pull/<n>/head`, keeping its
author - but a commit made here directly holds up the next publish until
it has been ported, because publishing never overwrites work it did not
write. The suite's `docs/MEMBER-REPO-SPLIT.md` is the whole workflow.

**Suite-level paths cited from here.** This member's `CLAUDE.md` and
`docs/` cite files that live at the suite root, not in this tree:
`docs/OXT-ENGINE-NOTES.md` (engine behaviour, the authoritative list),
`docs/OXT-PASS-RUNBOOK.md`, `tools/build-all.sh`,
`tests/suite-selftest.livecodescript` and the suite-level `docs/`
index. Read them at `https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/<path>`. A path of the
form `../<member>/...` names a sibling member of the suite; each has its
own repository, listed in `tools/member-registry.py` there.

**Sibling members this member's gates need beside it.** `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
reaches into these siblings, found as `../<name>` beside this checkout:

- `../riptide` from https://github.com/SethMorrowSoftware/RipTide - `tools/check-demo-boot.py`, the boot runner `tools/check-script-vectors.py` drives the helpers through.
- `../nostrxt` from https://github.com/SethMorrowSoftware/NostrXT - what riptide's runner loads at import time.
- `../coinxt` from https://github.com/SethMorrowSoftware/CoinXT - what riptide's runner loads at import time.

Clone them beside this checkout under exactly those directory names
(and keep this checkout named `nocloud`), or point `XTALK_SIBLINGS` at a
directory holding them (`XTALK_SIBLING_<NAME>` for one). The generated
`.github/workflows/gates.yml` takes them from the suite itself, at the
commit named by this repository's newest `Suite-Commit:` trailer - the
versions the suite's gates ran with this tree - and sets
`XTALK_REQUIRE_SIBLINGS=1` so a missing sibling fails the job rather
than skipping its tier. Nothing the SHIPPED code needs is beside it: a
demo that uses a sibling's library carries its own copy (below).

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `src/nocloudquickshare.livecodescript`.
- The boot self-check block (`tools/demo-selfcheck.livecodescript`; gate `tools/check-demo-selfcheck-drift.py`) in `src/nocloudquickshare.livecodescript`.
- Sibling libraries embedded by the suite's `tools/sync-demo-embeds.py` (the copy is the shipped file; the master is the sibling's `src/`):
  - `src/nocloudquickshare.livecodescript` carries `onionxt/src/onionxt.livecodescript` from https://github.com/SethMorrowSoftware/OnionXT.
- `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

**What this repository cannot check on its own.** The suite-wide gates -
cross-library name disjointness (`tools/check-cross-library-names.py`),
the carried-copy drift gates above, embed freshness, the cross-member
handler-call and typed-boundary checks (`tools/check-handler-calls.py`,
`tools/check-lcb-call-types.py`), the timer-pin closure, and the suite
paste's coverage ratchet (`tools/check-suite-coverage.py`) - run only in
the suite. `tools/run-gates.sh` here is this member's own list, and the
suite's `tools/build-all.sh` runs that same script, so the two cannot
disagree about what this member's gates are.

<!-- ==== SUITE RELATIONSHIP END ==== -->
