# xTalk Suite

[![Suite gates](https://github.com/SethMorrowSoftware/xtalk-suite/actions/workflows/suite-gates.yml/badge.svg)](https://github.com/SethMorrowSoftware/xtalk-suite/actions/workflows/suite-gates.yml)
[![.lce packages](https://github.com/SethMorrowSoftware/xtalk-suite/actions/workflows/lce-packages.yml/badge.svg)](https://github.com/SethMorrowSoftware/xtalk-suite/actions/workflows/lce-packages.yml)
[![Latest release](https://img.shields.io/github/v/release/SethMorrowSoftware/xtalk-suite?include_prereleases&label=packages)](https://github.com/SethMorrowSoftware/xtalk-suite/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Community: OpenXTalk forums](https://img.shields.io/badge/community-OpenXTalk%20forums-orange)](https://openxtalk.org/forum/)

**[Get the packages](https://github.com/SethMorrowSoftware/xtalk-suite/releases)** ·
**[Built into OXT-Beyond](https://github.com/SethMorrowSoftware/OpenXTalk-Beyond)** ·
[Extensions page](https://sethmorrowsoftware.github.io/OpenXTalk-Beyond/extensions/) ·
[Forum](https://openxtalk.org/forum/) ·
[Contributing](CONTRIBUTING.md) ·
[Security](SECURITY.md)

**Extensions that give OpenXTalk (OXT) and the xTalk family (also LiveCode 9.6.3+) the
capabilities app authors reach for: cryptography, BitTorrent, reliable-UDP realtime, WebRTC, Tor,
Bitcoin and Ethereum primitives, 2-D physics with a game kit, Nostr, and show control (OSC, MIDI
and Art-Net lighting).** Each is a small, friendly set of xTalk handlers, and each native member
bundles its library inside the extension, so there is nothing else to install. Sixteen
extensions, plus three apps built on them.

Every member is a thin binding over a proven C/C++ library (or pure LiveCodeScript for OnionXT
and NostrXT, and pure LiveCode Builder for artnetxt), built to one set of engineering rules so
they read as one system and compose: identity, transport and storage can come from different
members. The apps are the proof. All of it is developed here, and each member is also published
into its own repository ([docs/MEMBER-REPO-SPLIT.md](docs/MEMBER-REPO-SPLIT.md)).

## The extensions

| Member | Handlers | Built on | What it gives an xTalk app |
|---|---|---|---|
| [sodiumxt](sodiumxt/) | `sx*` | libsodium | Authenticated encryption, signatures, sealed boxes, Argon2id, key derivation and exchange, streaming and whole-file crypto, BLAKE2b / SHA3-256 / HMAC, the ristretto255 group, a CSPRNG |
| [torrentxt](torrentxt/) | `bt*` | libtorrent-rasterbar | The full BitTorrent protocol: DHT, PEX, magnets, uTP, trackers, web seeds, v1 + v2, BEP44 signed mutable items, and rp1, a peer-wire transport for opaque bytes |
| [enetxt](enetxt/) | `en*` | ENet 1.3.18 | Game-grade reliable UDP: reliable, unreliable-sequenced and unsequenced delivery on independent channels, one-call broadcast, live peer statistics |
| [datachannelxt](datachannelxt/) | `dc*` | libdatachannel 0.24.5 | Browser-interoperable WebRTC data channels with real NAT traversal (ICE) and per-channel reliability |
| [onionxt](onionxt/) | `ox*` / `oxh*` | a local Tor daemon (pure script) | Anonymous TCP streams, self-authenticating v3 onion services (deterministic from a seed), HTTP-over-onion hosting, offline onion-address tools |
| [nostrxt](nostrxt/) | `nx*` / `nxr*` | pure script over coinxt + sodiumxt | NIP-01 events with an owned canonical serializer and BIP-340 signatures, NIP-19 entities, NIP-44 v2 encryption, filters, and a websocket relay client that verifies before it delivers |
| [box2dxt](box2dxt/) | `b2*` / `b2k*` | Box2D v3.1.0 | Rigid-body physics (bodies, shapes, joints, motors, sensors, queries) plus the pure-script b2k game Kit: bodies in pixels and degrees, sprites, input, a player controller, a camera, sound |
| [box3dxt](box3dxt/) | `b3*` / `b3k*` | Box3D (pre-release, pinned to a commit) | 3D rigid-body physics: bodies, eight shape kinds (sphere to triangle mesh and height field), eight joint kinds with limits, springs and motors, ray casts and overlaps, contact, sensor and move events read by polling; plus the pure-script b3k game Kit: things in metres and degrees, an orbiting camera, input, a player controller, drawn by render3dxt when it is loaded or by box3dxt's own renderer |
| [audioxt](audioxt/) | `au*` | miniaudio 0.11.26 | Sound beside the engine's own `play`: any number of sounds mixed at once with low delay, music streamed from WAV, FLAC and MP3, sample-exact start times, fades and loops, groups, 3D placement, tones and noise, microphone capture to samples or straight to a WAV file, decoding and offline rendering |
| [render3dxt](render3dxt/) | `r3*` | its own C renderer, with stb_image and fast_obj compiled in | A textured 3D picture for an ordinary image control: OBJ models with their materials and pictures, boxes to capsules made to measure, PNG / JPEG / BMP / TGA textures, sun and lamp lights, fog, smooth edges, a camera that projects and casts rays, clicking on things; drawn on the processor across its cores, and made to draw what box3dxt simulates |
| [pdfxt](pdfxt/) | `pdf*` | PDFium chromium/8165 (prebuilt, a second library beside the shim) | Read-only PDF: open a file or bytes (with a password), draw a page as imageData, a BMP or one window of a zoomed page, page text with character boxes, search with highlight rectangles, the outline, links, labels and document information |
| [gamepadxt](gamepadxt/) | `gp*` | SDL 3.4.20 (its gamepad subsystem only) | Game controllers: Xbox, PlayStation, Switch and most other pads under one button layout, sticks with a dead zone, hot-plug, button and axis events read by polling, rumble and lights, mappings, and virtual pads for on-screen controls and tests |
| [xlsxt](xlsxt/) | `xl*` | libxlsxwriter 1.2.4 + zlib 1.4 + Expat 2.10.0 | Excel `.xlsx` workbooks written and read: sheets, text, numbers, formulas, dates, links, cell formats, merged cells, pictures and charts; a whole tab-delimited table in or out in one call; files from Excel, LibreOffice, Numbers and Google Sheets read back |
| [webpxt](webpxt/) | `wp*` | libwebp 1.6.0 | WebP pictures: decode a file to an image's `imageData` and `alphaData` and encode them back, lossy or lossless, with the file's facts, its ICC, EXIF and XMP chunks, and animations read and written frame by frame |
| [barcodext](barcodext/) | `bc*` | zxing-cpp 3.1.1 | barcodes: read every symbol in an image's `imageData` (QR Code, Data Matrix, Aztec, PDF417, EAN/UPC, Code 128 and the other linear kinds) with its text, bytes, kind and position, and create one as pixels, SVG or a module matrix |
| [coinxt](coinxt/) | `cx*` | trezor-crypto + bitcoin-core/secp256k1 | Bitcoin and Ethereum primitives: hashes, secp256k1 ECDSA (RFC 6979, recoverable), BIP-340 Schnorr and the BIP-341 Taproot tweak and sighash, encodings and addresses, BIP-39/32/44 HD wallets, WIF, Bitcoin legacy / SegWit / Taproot and Ethereum EIP-155 / EIP-1559 transactions |
| [curlxt](curlxt/) | `cu*` / `tsNet*` | libcurl 8.22.0 + libssh2 1.11.1 | HTTP(S), FTP(S), SFTP, SCP and SMTP(S) requests as handles, sync or in the background, large transfers straight to and from files; WebSockets (`ws://`, `wss://`); plus the tsNet calls by name, so stacks written for LiveCode's closed tsNet external run unchanged |
| [oscxt](oscxt/) | `osc*` / `scOsc*` | tinyosc (vendored) | Open Sound Control, the network language of TouchOSC, QLab, Resolume and SuperCollider: messages and bundles built from typed arguments and read back into arrays, OSC 1.0 address patterns matched, sent and received over the engine's own UDP sockets |
| [midixt](midixt/) | `midi*` / `scMidi*` | RtMidi 6.0.0 (on the web, the browser's Web MIDI) | Realtime MIDI: every port listed and opened (and virtual ports of your own on macOS and Linux), notes, controllers, program changes, pitch bends and SysEx sent, and everything that arrives drained by polling, decoded and time-stamped |
| [artnetxt](artnetxt/) | `artnet*` / `scArtnet*` | pure LCB (no native library) | Art-Net DMX lighting: up to 512 channel levels per universe sent to nodes and read from other controllers, and nodes found by ArtPoll discovery, over the engine's own UDP sockets |

Design facts that decide how you use them (each member's own docs have the rest):

- **sodiumxt** is the one member whose payload deliberately crosses the FFI: that is its job.
  Nonces are never caller-supplied for anything that seals bytes; the one exception, the raw
  `sxChaCha20IetfXor` (ABI 10), is a building block for NIP-44, argued in
  `sodiumxt/docs/security.md`.
- **torrentxt** keeps piece data on libtorrent's threads, engine to disk; script issues commands
  and polls small records. One session per process.
- **enetxt** is "pump or nothing": ENet is threadless, so everything happens inside `enPoll`.
- **datachannelxt** is the one binding with true cross-thread callbacks; each only locks, copies
  into a bounded queue and unlocks, and a ThreadSanitizer lane polices that. Signalling is the
  app's job (riptide uses its DM rail, the demo uses the DHT).
- **onionxt** adds no cryptography of its own (every hash and signature is a sodiumxt call) and
  talks only to a tor daemon on loopback, which you install. Attaching to a running tor is the
  proven path; launching one from the library is not yet.
- **nostrxt** is a stateless pure-compute core plus a stateful socket layer in a second file, so it
  can be embedded beside onionxt in one script.
- **box2dxt**'s examples are complete games: a seven-level platformer, a contraption builder, a
  slingshot tower-knockdown and a physics demo.
- **box3dxt** simulates, and draws the world into a picture a stack shows in an image (a small
  software renderer in the shim; anything finer is the stack's). Box3D is young (no tagged
  release) and trusts its caller, so the shim holds every argument to stated limits and removes
  a body whose motion stops being a number (`box3dxt/docs/getting-started.md`). Its b3k Kit
  makes games of it as box2dxt's Kit does in 2-D; the example, Orb Island, is one file
  (`box3dxt/docs/kit-guide.md`).
- **audioxt** is a second way to make sound, not a replacement: the `play` command and the
  player object are untouched. It never sends a message; a stack asks which sounds ended
  (`auPollEnded`) on a timer, and calls `auShutDown` when it closes
  (`audioxt/docs/getting-started.md`).
- **render3dxt** draws and nothing else: a scene in, `imageData` out, no window and no
  graphics card. It shares box3dxt's world (y up, metres, quaternions) and reads its texts
  as they stand, so a physics step reaches the picture in one call
  (`r3SceneApplyMoves(scene, b3MovesText())`); neither extension needs the other. Models and
  pictures are files from anywhere, so every index and size in one is checked before use.
- **pdfxt** ships two libraries per platform: its own and a pinned, prebuilt PDFium that it loads
  from beside itself. PDFium's floors are higher than the suite's (macOS 13, Android 6.0); on
  an older system the extension loads and every call is refused with a reason. It reads PDFs
  and never writes one, runs no JavaScript from a file, and reports links without opening them
  (`pdfxt/docs/getting-started.md`).
- **gamepadxt** is "poll or nothing": nothing changes between two `gpPoll` calls, and buttons
  are named by position (`south`), not by the letter printed on them. It reads controllers
  and opens no window (`gamepadxt/docs/getting-started.md`).
- **xlsxt** writes a workbook when it is closed and reads the DATA of one (values, formulas,
  number formats), not its looks. It does not edit a file in place or calculate formulas, and the
  reader treats every file as a stranger's: every size in one is bounded
  (`xlsxt/docs/getting-started.md`).
- **webpxt** and **barcodext** speak the engine's own pixel layout: a script hands over
  `the imageData of image` and gets one back, reordering nothing. Both treat a file or a
  picture as untrusted, hold sizes to stated caps, and never leave the caller's thread
  (`webpxt/docs/getting-started.md`, `barcodext/docs/getting-started.md`).
- **curlxt** is "pump or nothing" like enetxt: libcurl runs inside `cuPoll` / `cuWait`, and the
  helpers keep a timer only while something waits. It never touches libURL: `get url` behaves as
  before. Its tsNet layer was written from tsNet's public dictionary only.
- **oscxt** and **artnetxt** are codecs: they turn values into datagrams and datagrams back
  into values, and the stack sends and receives with the engine's own UDP sockets (each
  member's helpers do it for you). Neither starts a thread or holds a socket of its own.
- **midixt** is "poll or nothing" on input: RtMidi's thread fills a queue, and `midiPoll` (or
  the helpers' timer) drains it on the engine's thread, up to 256 messages in one call; no
  callback ever runs script. ShowControl's stacks keep working: the library ids, handlers and
  helper names of all three are ShowControl's, unchanged.
- **coinxt** signs only a digest the app hands it: the app owns custody. Secrets are wiped before
  free. `coinxt/examples/coin-wallet.livecodescript` is a full wallet over Esplora, Electrum or
  Bitcoin Core, clearnet or Tor.
- enetxt and datachannelxt share a **60000-byte message budget**: when a payload stops being a
  message, it becomes a torrent.

The native members share a namespace, `org.openxtalk.library.{sodium,torrent,enet,datachannel,...}`,
so the engine resolves each binding once its extension is installed. box2dxt predates the
convention and ships as `org.openxtalk.box2dxt`, a name already installed on users' machines.

## The apps

| App | What it is | Uses |
|---|---|---|
| [riptide](riptide/) | **Riptide Social**, a serverless social app: one sealed identity seed, a signed BEP44 feed with torrent-borne media, sealed DMs over rp1, WebRTC calls, LAN device sync, an onion-only persona, and a bridge to Nostr. Design: [docs/RIPTIDE-SOCIAL-SPEC.md](docs/RIPTIDE-SOCIAL-SPEC.md); bytes: [docs/RIPTIDE-PROTOCOL.md](docs/RIPTIDE-PROTOCOL.md) | sodiumxt required; torrentxt, enetxt, datachannelxt and coinxt per feature; onionxt and nostrxt carried inside |
| [nocloud](nocloud/) | **No Cloud Quick Share**, a finished file-sharing app with no server and no account: a share code (BitTorrent over the DHT), a web link any browser opens (a built-in streaming HTTP server), or a private Tor path, with an optional passphrase seal | torrentxt required; sodiumxt for the seal and the Tor path; onionxt carried inside (Tor needs a local daemon) |
| [holde-em](holde-em/) | Serverless **Texas Hold'em**: players meet over the DHT, every action lives in a signed hash-chained transcript, and the deal ladder tops out at a ristretto255 mental-poker shuffle with DLEQ proofs | torrentxt and sodiumxt; optional box2dxt Kit card art and onion tables (onionxt carried inside; Tor needs a local daemon) |

Each app probes its optional members at startup and degrades with a clear message when one is
absent, rather than failing.

## Start here (no experience needed)

1. Install [OXT-Beyond](https://github.com/SethMorrowSoftware/OpenXTalk-Beyond/releases), which
   has every extension built in, or another IDE built on LiveCode Community 9 such as
   [OpenXTalk](https://openxtalk.org) with the packages from [Install](#install).
2. Download this repository (the green **Code** button, then **Download ZIP**) and unzip it
   anywhere, or `git clone` it.
3. In OpenXTalk: `File > New Mainstack`, then `Object > Stack Script`. Paste **all** of
   [`start-here.livecodescript`](start-here.livecodescript), Apply, and **save that stack in the
   unzipped folder's root**, beside this `README.md`. Close its window and open it again.

Do not use `File > Open Stack` on the `.livecodescript` file itself: a script-only file is text,
so opening one builds no window (engine note 5.5 in `docs/OXT-ENGINE-NOTES.md`). Saving the stack
in the repository root is what lets it find everything else by relative path.

Reopening builds a clickable directory of every sample, demo and harness stack. Click one to read
what it is and what it needs; double-click it (or press **Open**) to launch it where it sits. Each
stack carries the script libraries it needs, and a stack missing an extension says so in red
rather than breaking. `tools/check-launcher-registry.py` keeps the directory true to the tree.

## Where it stands

Maturity is uneven by design: members ship as they reach the bar. **The honesty convention:** OXT
is a GUI runtime with no headless way to compile or run `.lcb` or `.livecodescript`, so anything not
observed on a real engine is labelled "verified statically; needs an OXT pass" (Tor paths: "+
live-Tor pass"). A label is removed only for what a run exercised, and a doc that understates a
dated record is wrong too. Each member's `CLAUDE.md` is the authority (its engine evidence ledger
holds every dated record); open work is in [docs/WORK-PLAN.md](docs/WORK-PLAN.md), and
[docs/OXT-PASS-RUNBOOK.md](docs/OXT-PASS-RUNBOOK.md) is how an engine session closes the gap.

| Member | Committed binaries | Latest dated engine record | Still open |
|---|---|---|---|
| sodiumxt | 5 platforms, ABI 10 | full `sxSelfTest()` 106/106 incl. ChaCha20 in the suite paste on Linux, 2026-09-25 (again 2026-09-26), on the `x86_64-linux` file (run 12's) by the maintainer's account (64-bit; ChaCha20's first recorded Linux run), and on Windows, 2026-09-24 to 09-26, on the `x86_64-win32` MSVC DLL by the maintainer's account (64-bit; the 2026-09-12 build's first engine load; libsodium 1.0.22 read by the 2026-09-26 preflight) | the 32-bit MSVC DLL; the 32-bit Linux library; a first Mac load; the demo re-pass |
| torrentxt | 5 platforms, ABI 11 | harness 106/106 in the suite paste on Linux, 2026-09-25 (again 2026-09-26), the 2026-09-12 `x86_64-linux` build's first engine load by the maintainer's account (64-bit; its 996-byte BEP44 refusals agree), and on Windows, 2026-09-24 to 09-26, on the `x86_64-win32` build by the maintainer's account (64-bit; its first engine load, and the first recorded libtorrent 2.1 run on Windows); rp1 chat reported working across two machines on one LAN, 2026-08-27 | the 32-bit Linux and Windows libraries; demo re-opens; the Tor paths; two-machine seed/leech and resume; a real public swarm |
| enetxt | 5 platforms, ABI 2 | folded 34 checks green and the paste's live loopback COMPLETED in the suite paste on Linux, 2026-09-25 and 09-26, on the 2026-09-12 `x86_64-linux` build by the maintainer's account; folded 34 on the 2026-09-12 `x86_64-win32` DLL, Windows, 2026-09-24 to 09-26 (the paste's loopback stalled there all six times, runbook 5.5), where the standalone selftest ran 68/0/0 with its own async loopback complete on 2026-09-26 (presumably on that DLL); standalone async loopback, 2026-08-13 | LAN chat between two machines; internet chat across two networks |
| datachannelxt | 5 platforms, ABI 1 | folded 39 checks green and the paste's live loopback COMPLETED in the suite paste on Linux, 2026-09-25 and 09-26, on the 2026-09-12 `x86_64-linux` build by the maintainer's account; folded 39 on the 2026-09-12 `x86_64-win32` DLL, Windows, 2026-09-24 to 09-26 (the paste's loopback stalled there all six times, runbook 5.5); standalone async loopback, 2026-08-15; a DHT-signalled chat reported working across two machines on one LAN, 2026-08-27 | the standalone selftest's own async loopback on the 2026-09-12 builds (the paste's own completed on Linux); browser interop; a call across two networks; the loopback demo's itemised record (on 2026-09-26 it "seems to work as intended", by the maintainer's account) |
| curlxt | 6 platforms, ABI 2 | its own engine self-test on OXT-Beyond's headless Linux server engine, 2026-11-21, over a locally built library and then over the committed `x86_64-linux` one (release run 44825160471): 138 checks each, none failed, and over release run 44925581646's (the 0.2.1 shim): 141, none failed; every public handler of the binding called, requests through the binding and the helpers, and `ws://` and `wss://` sockets through the binding and the helpers' timer (`curlxt/tests/engine-selftest.lc`, run again by its native lane on every change); its demo, curlxt Live, start to finish on OXT-Beyond 0.2.7-rc.6's desktop engine with no screen, 2026-11-21, over a local library and both release builds: 26 checks each, every scene to its own verdict, a close and a reopen (`curlxt/tests/engine-demo.livecodescript`, run by the same lane); on Windows x86-64, the 2026-11-14 DLL: the three extensions loaded and probed in OXT-Beyond's Windows CI, 2026-11-14, and `tsNetGetSync`, an async `tsNetGet`, a refused expired certificate and five concurrent `cuRequestAsync` calls on the maintainer's PC through the MCP bridge, 2026-11-15; and in OXT-Beyond 0.2.8-dp.1's IDE on that PC, 2026-11-21, curlxt Live over the built-in 0.1.0 (scene 4, 105 of 105 local requests in each of its two fixed builds), then over ABI 2, the binding compiled there over release run 44825160471's DLL and then run 44925581646's: the boot self-check green, every scene to its own verdict and looked at, a close and a reopen, and `wss://` to a public echo service over Schannel through every WebSocket call of the binding and the helpers | the committed ABI 2 libraries on any engine but 64-bit Linux's and Windows'; SFTP, SCP, SMTP, FTP and uploads on an engine; WebSockets on mac and in the Linux and mac IDEs; the demo on a screen on Linux and mac; a row in the suite paste |
| box3dxt | 6 platforms, 4 Android ABIs and a web archive, ABI 3 | its own engine self-test on OXT-Beyond's headless Linux server engine, 2026-11-20, over a locally built library: the module loaded, the ABI check passed and every public handler was called (`box3dxt/tests/engine-selftest.lc`, run again by its native lane on every change); its web archive at ABI 2 in Chromium, 2026-11-21: a web engine built locally from OXT-Beyond's pull request 606 played the b3k Kit's Orb Island (its keys not driven), and the same day the web-2026.11.21 pre-release's Stack Player, in Chromium, played it built into a stack file for the community gallery: the window at its size, W walking to an orb that was counted, C dropping crates, V saying render3dxt was not loaded, a click knocking crates over and a drag turning the camera; in the IDE on the maintainer's Windows PC (OXT-Beyond 0.2.8-dp.1), 2026-11-21, the ABI 2 `x86_64-win32` release library installed as an extension: from script, a drop that came to rest, ray casts, a contact event and a picture read as data, picked and cast through, with no assert; and the ABI 2 `x86_64-android` library answering one call in an app on x86_64 emulators, 2026-11-21 (OXT-Beyond's pull request 606); and the committed ABI 3 `x86_64-linux` library on OXT-Beyond 0.2.8-dp.1's Linux server engine, 2026-11-21: its engine self-test 107 passed (the sky's checks among them), the Kit's test 204 with render3dxt and 193 without, Orb Island's 102 and 99, none failed | the other committed ABI 3 libraries on any engine (the other records are of ABI 2 files or locally built libraries); a window, a frame loop and a game on Windows; macOS, more than one call on Android, and a released web engine; a row in the suite paste |
| audioxt | 6 platforms, 4 Android ABIs and a web archive, ABI 1 | its own engine self-test on OXT-Beyond's headless Linux server engine, 2026-11-20, over a locally built library and through miniaudio's silent device: the module loaded, the ABI check passed, binary data crossed both ways, a tone was rendered and measured, and every public handler was called; the web archive played and recorded in headless Chromium the same day; in the IDE on the maintainer's Windows PC, 2026-11-21, a CI-built 64-bit DLL loaded on WASAPI and the same self-test passed 89, failed 0; the demo driven on the Linux desktop engine the same day (`audioxt/tests/demo-drive.livecodescript`), later over the committed `x86_64-linux` library, and played in the same Windows IDE through a real sound device by its own meters, then fixed to open on the screen and quickly: 0.14 s in OXT-Beyond 0.2.8-dp.1's IDE on Linux (1.8 s before) and 796 ms in the Windows one (59 s before); on 2026-11-22 OXT-Beyond 0.2.8-dp.2.1's web engine, which links the committed web archive, played the demo in headless Chromium by its own report | the other committed release libraries on any engine; macOS and Android; anyone hearing it (nobody has listened); a row in the suite paste |
| render3dxt | 6 platforms, 4 Android ABIs and a web archive, ABI 1 | three engine tests on OXT-Beyond's headless Linux server engine, 2026-11-20, over locally built libraries: the binding alone (`render3dxt/tests/engine-selftest.lc`: the module loaded, pictures drawn from script checked pixel by pixel, every public handler called), with box3dxt beside it (`engine-interop.lc`: a Box3D simulation drawn where Box3D says the bodies are) and its demo stack opened and driven by message (`engine-demo.lc`); all three run again by its native lane on every change. The same day the demo ran in a desktop IDE (OXT-Beyond 0.2.8-dp.2 on Linux, locally built libraries): seen, recorded, dragged, kicked, every button pressed, 57 pictures a second. On Windows (OXT-Beyond 0.2.8-dp.1, dark system appearance) the rebuilt demo was readable, 2026-11-21, and the demo as merged opened there with its boot self-check green (12 passed, 0 failed, 0 skipped) the same day. In a browser, 2026-11-21: a locally built OXT-Beyond web engine with the web archive linked, in Chromium, played OXT-Beyond's Render3D Tour at 59 to 60 pictures a second and the demo at 34 to 36, its boot self-check green (the archive as merged; the one rebuilt with a leak fix has run its own tests under node only). On 2026-11-21 OXT-Beyond 0.2.8-dp.1's Linux server engine loaded the committed x86_64-linux library and passed OXT-Beyond's Android functional test for render3dxt with it (a model, its MTL and a TGA read from disk, drawn, clicked and freed) | the other committed desktop and Android libraries and the rebuilt web archive on any engine (the other runs loaded locally built ones, bar the web archive as first committed); macOS and Android; a released web engine; a pointer on Windows; a row in the suite paste |
| pdfxt | none yet (the first release dispatch lands them: two files per platform), ABI 1 | its own engine self-test on OXT-Beyond's headless Linux server engine, 2026-11-20, over a locally built library and the pinned PDFium: the module loaded, the ABI check passed, pages were drawn into images, text read and searched, and every public handler was called (`pdfxt/tests/engine-selftest.lc`, run again by its native lane on every change); the same self-test in the maintainer's Windows IDE, 2026-11-21, over CI's `x86_64-win32` library: 64 passed, and the 2 first-load checks failed in a session that had used pdfxt first, which they cannot survive (`pdfxt/README.md`); the demo stack driven on the Linux desktop engine without a display, 2026-11-21 | a Windows run in a fresh IDE session; an IDE on Linux and a Mac; macOS and Android engines; a person using the demo; a committed library; a row with a Run in the suite paste |
| gamepadxt | 6 platforms and a web archive, ABI 1 | its own engine self-test on OXT-Beyond's headless Linux server engine, 2026-11-20, over a locally built library and virtual pads: the module loaded, the ABI check passed and every public handler was called (`gamepadxt/tests/engine-selftest.lc`, run again by its native lane on every change); its demo window, Gamepad Lab, driven on OXT-Beyond's Linux desktop engine with no display, 2026-11-21, with that library and without it (`gamepadxt/tests/demo-drive.livecodescript`); the committed web archive in OXT-Beyond's web engine, built by its pull request 612, whose web IDE check ran a virtual pad in Chromium, Firefox and WebKit, 2026-11-21; in the IDE on the maintainer's Windows PC, 2026-11-21 (OXT-Beyond 0.2.8-dp.1, over a DLL the size of the committed one): Gamepad Lab opened and played its first showcase on its software pad; the committed `x86_64-linux` library under OXT-Beyond 0.2.8-dp.1's Linux desktop engine, 2026-11-21: that drive's 162 checks, run locally | a real controller, on any platform; macOS; an IDE on Linux; the committed 32-bit Windows, 32-bit and arm64 Linux and Mac libraries on any engine; a row in the suite paste |
| xlsxt | 6 platforms, 4 Android ABIs and a web archive, ABI 1 | its own engine self-test on OXT-Beyond's headless Linux server engine, 2026-11-20, over a locally built library: the module loaded, the ABI check passed, a workbook with formats, a table, a chart and a picture was written and read back, and every public handler was called (`xlsxt/tests/engine-selftest.lc`, run again by its native lane on every change); in the IDE on the maintainer's Windows PC, 2026-11-21, over the native lane's DLL: that self-test 64/0 and the demo's checks 39/0 (its words were white on white under the dark theme; the demo was rebuilt the same day as a self-playing showcase that names every colour, and that window ran on the same PC readable throughout, its tour and checks 39/0); the committed web archive in OXT-Beyond's web engine, 2026-11-21: a workbook written and read back in Chromium, Firefox and WebKit (its pull request 605, and again in 620, which built xlsxt into 0.2.8-dp.2.1); and two committed release libraries the same day: the `x86_64-android` one in OXT-Beyond's Android check app (that pull request) on Android 13 and 16 x86_64 emulators, `xlLibraryVersion()` and a workbook written in the app's folder and read back cell for cell, and the `x86_64-linux` one running that test on OXT-Beyond 0.2.8-dp.2's Linux standalone engine, headless; and its demo stack in OXT-Beyond 0.2.8-dp.2.1's Stack Player in headless Chromium, 2026-11-22: the tour played to its end and the demo's checks passed 39/0 | the committed Windows, Mac, 32-bit and ARM release libraries on an engine (the Windows runs above loaded the native lane's DLL); macOS; Android on ARM, and with `xlSetTempFolder` set; every handler in a browser; a file of its own opened in Excel, on the record; a row in the suite paste |
| webpxt | 6 platforms, 4 Android ABIs and a web archive, ABI 1 | its own engine self-test on OXT-Beyond's headless Linux server engine, 2026-11-20, over a locally built library: the module loaded, the ABI check passed and every public handler was called (`webpxt/tests/engine-selftest.lc`, run again by its native lane on every change); on 2026-11-21 the same test over the committed `x86_64-linux` library (release run 44846691681): 79 checks, none failed; the same day the IDE on the maintainer's Windows PC (OXT-Beyond 0.2.8-dp.1, 64-bit) loaded the committed `x86_64-win32` library as an installed extension, `wpLibraryVersion()` answered and the community gallery's WebP Studio encoded a picture and decoded it back, and OXT-Beyond's Android check app (its pull request 614) called `wpLibraryVersion()` on an Android 16 x86_64 emulator; on 2026-11-22 every library was rebuilt for the animation-length limit (release run 44965414934, the web archive by hand) and the test, grown to 93 checks, passed over the rebuilt `x86_64-linux` one, none failed (the Windows and Android records are of the 2026-11-21 libraries) | an IDE on Linux or a Mac, or on the rebuilt libraries; macOS and the web; any ARM or 32-bit library; a harness in the suite paste |
| barcodext | 6 platforms, 4 Android ABIs and a web archive, ABI 1 | its own engine self-test on OXT-Beyond's headless Linux server engine, 2026-11-20, over a locally built library: the module loaded, the ABI check passed and every public handler was called (`barcodext/tests/engine-selftest.lc`, run again by its native lane on every change); on 2026-11-21 the same test over the committed `x86_64-linux` library (release run 44846691681): 80 checks, none failed; the same day the IDE on the maintainer's Windows PC (OXT-Beyond 0.2.8-dp.1, 64-bit) loaded the committed `x86_64-win32` library as an installed extension, `bcLibraryVersion()` answered and the community gallery's Barcode Studio made a QR Code and read it back, and OXT-Beyond's Android check app (its pull request 614) called `bcLibraryVersion()` on an Android 16 x86_64 emulator; every picture it read was drawn by its own writer | an IDE on Linux or a Mac; a photograph from a camera; macOS and the web; any ARM or 32-bit library; a harness in the suite paste |
| oscxt | 6 platforms, ABI 2 | its LCB suite under lc-run and its Script suite in OXT-Beyond's headless standalone engine (`-ui`), Linux x86_64, 2026-11-21, over a locally built library: real UDP through the engine's own sockets and an independent OSC peer included (`oscxt/tools/run-lcb-tests.py`, `run-lcs-tests.py`; its native lane runs both on Linux, Windows and macOS on every change); the parser fuzzed under ASan/UBSan the same day; on 2026-11-22 both suites over the committed `x86_64-linux` library (release run 44985328988): the LCB suite's 23 tests (328 checks) and the Script suite's 39 (255 checks), none failed or skipped; the same day the IDE on the maintainer's Windows PC (OXT-Beyond 0.2.8-dp.1, 64-bit) loaded the committed `x86_64-win32` library as an installed extension, `oscVersion()` answered 2 and the shipped self-test passed (29 checks and its UDP loopback), and the IDE on the maintainer's Linux PC (0.2.8-dp.2) loaded the `x86_64-linux` one | an IDE on a Mac; a real OSC application (TouchOSC, QLab, Max); Android; a row in the suite paste |
| midixt | 6 platforms and a web archive, ABI 2 | the same two suites on the same engine, 2026-11-21, over a locally built library and the member's mock MIDI backend; on 2026-11-22 both over the committed `x86_64-linux` library (release run 44985328988) beside the mock: the LCB suite's 25 tests (191 checks) and the Script suite's 38 (322 checks), none failed; with no MIDI service there the real library took its no-service path and said so, and the checks that need a service skipped; the same day, on the maintainer's Linux PC (the IDE of OXT-Beyond 0.2.8-dp.2 with it installed), the shipped self-test passed with every check run, its loopback through an ALSA virtual port among them, and the IDE on the maintainer's Windows PC (0.2.8-dp.1, 64-bit) loaded the committed `x86_64-win32` library, `midiVersion()` answered 2 and the self-test passed (29 checks; 2 skipped, Windows MM having no virtual ports); the web archive's tests (2026-11-22) under node, against a stand-in for the browser's Web MIDI | a message through CoreMIDI, Windows MM or a MIDI keyboard on the record; an IDE on a Mac; a row in the suite paste; the web archive in a web engine and a browser |
| artnetxt | pure LCB (no library to commit) | the same two suites on the same engine, 2026-11-21: lc-compile `-Werror`, real UDP, discovery and DMX against an independent virtual node | a hardware node or lighting desk on the record; any desktop IDE; Windows and macOS on the record outside CI; a row in the suite paste |
| onionxt | pure script | live-Tor core and `oxh*` hosting at bring-up (pre-suite, undated); offline self-test 74/0/1 in the suite paste, Linux 2026-09-25 and 09-26 and Windows 2026-09-24 to 09-26; Esplora and Electrum over Tor from the coin wallet, 2026-09-02 and 09-03 | launching tor from the library (Mode B); four inline probes; an OnionXT-to-OnionXT round trip; live negative paths |
| nostrxt | pure script | core 277/0/2 in the suite paste, Linux 2026-09-25 and 09-26 and Windows 2026-09-24 to 09-26 (the NIP-44 cipher round trip included); relay connect, publish and ok-confirm live against wss://nos.lol, 2026-08-24 | the relay receive leg; NIP-42; `ws://`; bad-certificate TLS (engine note 6.8) |
| box2dxt | 5 platforms, ABI 4 | Kit harness v32: 385/0 in the suite paste on its 1200-wide card, Linux 2026-09-25 and 09-26 (run 12's `x86_64-linux` file, by the maintainer's account) and Windows 2026-09-24 to 09-26 (on the 2026-09-12 DLL there); every run settles the itemDelimiter half of engine note 2.3 (handler-local). `playLoudness` reads back 0 on Linux and exact on Windows (engine note 5.4), a printed note since v31 | the five game stacks since the 2026-08-14 fold; risk R1 on Linux and macOS |
| coinxt | 5 platforms, ABI 7 | library 299/299 at ABI 7 in the suite paste, Linux and Windows 2026-09-26 (the exact whole-number bech32 guard of 2026-09-25 green on both, engine note 2.12); 296/296 in the suite paste, Linux 2026-09-25 and Windows 2026-09-24 and 09-25, on the 2026-09-12 builds by the maintainer's account (`x86_64-linux` and `x86_64-win32`, both engines 64-bit; the 2026-09-25 Windows run's build INFERRED; the six `cxPubkeyCombine` checks included); 290/290 at ABI 6, 2026-08-24; the wallet's engine logs, 2026-09-01 to 09-03: all four public transports, testnet broadcasts, RBF, CPFP, an inscription | silent-payment receive; the wallet surface added since 2026-09-04; the wallet's exact-integer bounds of 2026-09-25/26; a native-P2WPKH and any Ethereum broadcast; the 32-bit Windows DLL |
| riptide | app | phases 1-4 done on two machines, 2026-08-13 and 2026-08-15; harness 512/0/2 at library 0.13.0 in the suite paste, Linux and Windows 2026-09-26 (on each a second Run all in one launch, by the maintainer's account; wire seqs ordered exactly; its fourth probe line read the same on both, engine note 2.11); harness 489/0/2 in the suite paste, Linux 2026-09-25 (a second Run all in one launch, by the maintainer's account, so the fold's stale-session fix ran; its third probe line read the engine's comparison constant, 10 DBL_EPSILON, engine note 2.10), Windows 2026-09-25 (the same probe lines) and Windows 2026-09-24 (the day's second and third runs; its first read 487/2/2: a stale capability count, and a u64 bound the engine let through; both fixed and green that evening) | the demo's 0.13.0 LAN checks (the library's ran in the paste on 2026-09-26; the demo's are verified statically; needs an OXT pass); 0.14.0's persona index cap, byte-order handle compares and draft change detection (2026-09-26), and the UTF-8 round trip and inbox match its review moved off the number path (2026-09-27; verified statically; needs an OXT pass); live passes of phases 5-8; the faststart re-run; the boot re-paste |
| nocloud | app | no dated engine pass in this tree (its pre-fold passes are undated); gates green, including a headless execution gate | the 69-item OXT checklist, web-link and Tor halves (case-exact routes since 2026-09-25 among its items) |
| holde-em | app | the standalone self-test 929/0/5 green and a six-seat hotseat session (the flat table; its transcript re-derived headlessly), Windows, 2026-09-26; folded harness 929/0/5 at v0.25.6 (harness v48), Linux and Windows, 2026-09-26 (turn-bound acts, table protocol 2, History replaying the table's rules, the open-hand seat rule: their pins' first engine runs, each on one machine); 751/0/5 at v0.25.5 (harness v47), Linux and Windows, 2026-09-25 (the 2026-09-25 hex-compare and canonical-index fixes' pins included); 721/0 at v0.25.3 (harness v45), Windows, 2026-09-24 | v0.25.6 across machines (verified statically; needs an OXT pass); the table on the Kit's sprite cards; the multi-machine exits, every machine on the same holde-em; Level 2 is not yet wired into played hands |

**Platform gaps, suite-wide.** Every native member's current binaries come from the 2026-09-12
release dispatch (commit 421bab3). Their `x86_64-win32` builds first met an engine on 2026-09-24, in
the suite paste, on a 64-bit OXT by the maintainer's account, and again on 2026-09-25 on that
machine (its binaries not stated: INFERRED the same set, since nothing newer is committed and
torrentxt's 997-byte refusals pass), and again on 2026-09-26 (the batch paste, twice in one
launch, 2,857 / 2 / 10, and the preflight: all six LOADED on OXT 9.6.3, libsodium 1.0.22 read;
the same machine by the maintainer's account). Their `x86_64-linux` builds (sodiumxt's and box2dxt's are still
run 12's) first met an engine on the record on 2026-09-25, in the same paste, green, on 64-bit
Kubuntu 24.04 with "the latest builds" and "the latest" OXT by the maintainer's account (torrentxt's
997-byte refusals agree; the OXT version and library versions were not recorded), and again on
2026-09-26 on that machine by the same account (the batch paste, 2,876 / 0 / 10). The same day the
engine preflight's first Linux run (presumably that machine; not stated) LOADED all six at their
ABIs on OXT 9.7.0-dp-1 and printed libsodium 1.0.20, enet 1.3.18 and libdatachannel v0.24.5, the
Linux pins. No OXT engine has
loaded any `universal-mac` dylib. No record names a 32-bit engine: sodiumxt, torrentxt and coinxt on
x86-win32 (coinxt's 32-bit DLL may never have executed anywhere: CI's Windows KAT step is x86_64
only, and every Windows engine run since 2026-09-24 loaded the 64-bit DLL, by the same account), and
sodiumxt and torrentxt on x86-linux. The Windows DLLs carry libtorrent 2.1.2 and OpenSSL 3.6.5 from vcpkg
rather than the 2.0.11 and 3.5.9 the other platforms pin; libsodium is 1.0.22 everywhere since
2026-11-07. Linux floors vary: both
datachannelxt builds and the 32-bit builds of torrentxt and gamepadxt need glibc 2.38, box2dxt's
32-bit build 2.34. The
macOS dylibs are universal (arm64 + x86_64) and unsigned.

**Android (started 2026-11-18).** All seven native members build for `arm64-android`,
`armv7-android`, `x86_64-android` and `x86-android` with `tools/build-android.sh`, and each built
library is checked as an Android library (ABI, API 21, Android's own libraries only, 16 KB
alignment). Every member's own tests ran on an Android 5.0 emulator for the two x86 ABIs on
2026-11-18, in the release workflow's first Android run; the ARM libraries are built and checked,
not run. The twenty-eight libraries were committed the same day by a second release run (each
member's `src/code/<abi>-android/`). On 2026-11-19 an OXT engine on Android first loaded them:
OXT-Beyond pinned the twenty-eight and its CI ran an app with all seven extensions on x86_64
emulators (Android 13, and Android 16 with 16 KB pages), where each library loaded and answered
one call. No member's selftest has run on an Android engine, and no `x86-android` or ARM library
has been loaded by one: needs an OXT pass on Android. curlxt's four were rebuilt at ABI 2 on
2026-11-21 and tested on the emulator again; the engine load was of its ABI 1 files.
torrentxt's Android libraries as first committed did not work inside an app on Android 11 or later (found
2026-11-21 in OXT-Beyond's app on an Android 13 emulator: a session starts paused, because
libtorrent built for API 21 uses a socket those Androids refuse an app). The recipe now builds
torrentxt alone for API 24 (Android 7.0), where it does not, and its four libraries were rebuilt
that day (commit d47060f): their tests ran on an Android 7.0 emulator for the two x86 ABIs, and
on 2026-11-22 OXT-Beyond's app, with the `x86_64-android` one, started a session unpaused,
listening on every address, and seeded a file on Android 13 and Android 16 emulators
(`docs/ANDROID.md`, "torrentxt in an app at API 24"). No peer has connected on Android yet.
box3dxt joined on 2026-11-20; its four Android libraries were committed that day by its own release run
(6d132d3), tested on the emulator for the two x86 ABIs, the ARM ones built and checked, not run.
OXT-Beyond pinned them in its pull request 606, whose app on the same two emulators had the
`x86_64-android` one answer one call on 2026-11-21. The same day the four were rebuilt at ABI 3
(release run 44914775780), the x86 ones tested on the emulator again; no engine has loaded those.
audioxt joined the same day; its four Android libraries were committed on 2026-11-21 by release
run 44847619287 (78223d8), the x86 ones tested on the emulator, the ARM ones built and checked, not run.
render3dxt joined the same day; its four Android libraries were committed on 2026-11-21 by release
run 44874931964 (f6c0b1a), the x86 ones tested on the emulator, the ARM ones built and checked, not
run. pdfxt joined the same day and is in the recipe; none of its Android libraries is committed
yet, and each has a prebuilt PDFium beside it, which needs Android 6.0. xlsxt, webpxt and
barcodext joined the same day too; their four Android libraries each were committed on
2026-11-21 by their own release runs (xlsxt's 0be6db1, webpxt's and barcodext's 21f75b8;
webpxt's rebuilt on 2026-11-22 for its animation-length limit, 3d35c4a), tested on the
emulator for the two x86 ABIs, the ARM ones built and checked, not run.
gamepadxt, which joined the same day too, is not built for Android. oscxt and midixt joined on
2026-11-21 with no Android build either (`tools/build-android.sh` names the three desktop-only
and says why); artnetxt has no library.
[docs/ANDROID.md](docs/ANDROID.md) has the method and what differs per member (curlxt reads
Android's system certificate store; onionxt, nostrxt and the three apps are not examined there).

### The suite paste, run by run

`tests/suite-selftest.livecodescript` runs the whole suite from one paste (below). Its dated runs:

| Date | Engine | Result |
|---|---|---|
| 2026-08-08 | not recorded | first end-to-end green, six members installed. One SodiumXT seed derives the SAME ed25519 identity in libsodium and libtorrent; libtorrent's DHT secret key IS SodiumXT's expanded key; TorrentXT accepts a SodiumXT signature over a BEP44 item and REFUSES one minted for another sequence number; one sealed payload crosses both live transports byte-for-byte under the shared 60000-byte budget |
| 2026-08-10 | not recorded | every member's deep self-test folded in: 455 member checks plus the core, 0 failed |
| 2026-08-12 | Windows x64 | 617 folded checks, 0 failed |
| 2026-08-17 | Windows x86_64, OXT 9.6.3 | 1,836 folded checks, 0 failed, 7 skips; all nine folded harnesses green; all six extensions at their expected ABI |
| 2026-08-18 | Linux | the first Linux run, no suite total recorded; box2dxt 373/374, the harness wrong about the engine (engine note 5.4) |
| 2026-08-20 | Windows | 1,981 passed, 0 failed, 1 skipped: the whole run, both live loopbacks, the 60000-byte budget on both transports, teardown |
| 2026-08-24 | Windows x86_64, OXT 9.6.3 | 2,373 passed, 0 failed, 3 skipped: nostrxt's first contact, coinxt's BIP-341, sodiumxt's ABI 10 |
| 2026-08-27 | two machines, one LAN | 2,440 passed, 2 failed, 3 skipped: every folded member green; both failures were the live loopbacks, stalled by loopback UDP being blocked on that machine |
| 2026-09-24 | Windows (the engine reports Win32), three runs; a 64-bit OXT by the maintainer's account | the D-23 board's first engine runs: 2,620 / 5 / 3, then 2,623 / 2 / 3 and 2,623 / 2 / 10 once riptide's two fixes and the board review's were in. Both live loopbacks stalled in all three runs, in the same phases (runbook 5.5); the first run's other three failures were riptide's, fixed that evening, and riptide's probe lines, printed from the second run on, found the engine's comparison tolerance (engine note 2.10) |
| 2026-09-25 | Linux: 64-bit Kubuntu 24.04, the latest committed builds and "the latest" OXT, by the maintainer's account (no OXT version given) | 2,672 passed, 0 failed, 10 skipped, from a SECOND Run all in one launch by the maintainer's account: all ten probed extensions and script layers present and every member row green (nocloud has no in-engine harness), riptide's session sections included (the fold's stale-session fix), both live loopbacks completing (the paste's loopback code finishes on an engine); box2dxt settles engine note 2.3's itemDelimiter half on Linux; riptide's third probe line reads the engine's comparison constant to the digit and shows number-like texts comparing as numbers (engine notes 2.10, 2.11) |
| 2026-09-25 | Windows, the 2026-09-24 machine (64-bit, by the maintainer's account) | 2,653 passed, 2 failed, 10 skipped: every member header as on Linux, riptide's three probe lines character for character, so engine note 2.10's constant and the two items of 2.11 that line probes read the same on Windows; the 2 failures are both live loopbacks, stalled on that machine a fourth time in the same phases (runbook 5.5) |
| 2026-09-26 | Linux, the 2026-09-25 machine (64-bit Kubuntu 24.04, "the latest" OXT and the committed builds, by the maintainer's account; whether the OXT build was 2026-09-25's not stated) | 2,876 passed, 0 failed, 10 skipped, the 2026-09-25/26 batch's first engine run, again from a SECOND Run all in one launch by that account (a fresh stack): every member row green, holde-em v0.25.6 / harness 48 and riptide 0.13.0's exact seq order among them, and coinxt's exact whole-number guard (engine note 2.12); both live loopbacks completed again; riptide's fourth probe line reads "inf", "nan" and a hex float comparing as numbers on Linux (its C library's parse, INFERRED), so free text can compare as a number (engine note 2.11) |
| 2026-09-26 (5:11 PM) | Linux, presumably the same machine (not stated); OXT 9.7.0-dp-1 by the preflight reported with it (INFERRED for this run) | 2,876 passed, 0 failed, 10 skipped again: line for line the earlier run bar the Kit's clock, four generation-tagged joint handles and an image id, so riptide's fourth probe line read the same twice on one machine (a repeat, not a second platform). It was its launch's on-open Run all and the only one, by the maintainer's account, as those handles had INFERRED, where the earlier report was a second (runbook section 8), so a first and a second read alike. The preflight reported with it LOADED all six at their ABIs, its first Linux run |
| 2026-09-26 (7:24 PM and 7:28 PM) | Windows, the 2026-09-24 machine (64-bit), a fresh stack, and both runs in one launch, the on-open Run all and a second, by the maintainer's account; OXT 9.6.3 by that evening's preflight (INFERRED for the runs) | 2,857 passed, 2 failed, 10 skipped, twice: every member header as on Linux that day, holde-em v0.25.6 / harness 48, riptide 0.13.0 and coinxt's exact bech32 guard among them; riptide's fourth probe line identical to Linux's, so on both engines "inf" is "1e999", "0x1.8" is "1.5", two "nan" texts are unequal and a no-break-space-edged "3" is not 3 (each C library's parse, INFERRED: engine note 2.11); the second run's session sections green; the 2 failures are both live loopbacks, stalled on that machine again (runbook 5.5), where enetxt's standalone selftest completed its own the same evening (68/0/0). The preflight LOADED all six at their ABIs and read libsodium 1.0.22 |

## The shared engineering rules

1. **Never call an xTalk handler from a foreign thread.** Inbound events ride a queue that script
   poll-drains on a timer; no callback ever runs script.
2. **The exception firewall.** Every `extern "C"` entry point catches everything and returns an
   error; no exception crosses into the engine.
3. **Payload stays out of script** where a design allows: bulk bytes go engine to disk, and only
   small status records and events cross.
4. **Handles are generation-tagged integers**, validated before use, so a stale handle is a
   harmless no-op, never a crash.
5. **The OXT compiler footguns** (ASCII only, the `k`/`p`/`s`/`t` token-shadow trap, literal
   constants declared before use, `unsafe` around foreign calls, block balance, and more) are
   enforced by `tools/check-livecodescript.py`, one byte-identical, fixture-tested copy in every
   member.

## Install

**The finished packages.** Every extension the suite makes is built as an installable `.lce`
package by `.github/workflows/lce-packages.yml`: each LCB library with its native code for every
committed platform (and, for enetxt and box2dxt, the Visual C++ runtime their Windows DLLs need),
and each script library (the helpers, the b2k and b3k Kits, coinxt's script layer, curlxt's tsNet calls,
OnionXT and its HTTP server, NostrXT and its relay client); `python3 tools/build-lce-packages.py
list` names them. Its `table` gate refuses an extension member with no package, so a new one
cannot be left off; one with no committed library yet waits, and the first build after its
libraries land packages it. Take them from the download page,
<https://sethmorrowsoftware.github.io/xtalk-suite/> (written from the newest published release by
`tools/build-extensions-site.py` and published by `.github/workflows/pages.yml` each time a release
is published; since 2026-11-21 a push to main that changes any package publishes that release by
itself, so the page follows main), from a GitHub release of
this repository, or from the `xtalk-suite-lce` artifact of a run, then in any
IDE built on LiveCode Community 9 (LiveCode Community 9.6.3, OpenXTalk, HyperXTalk, OXT-Beyond)
choose **Tools > Extension Manager > +** and pick the `.lce`. Install a library before its
helpers or script layer (`torrentxt` before `torrentxt-helpers`, `onionxt` before
`onionxt-httpd`). OXT-Beyond has built in every member its `tools/oxt/xtalk-extensions.json`
names (a member that joined lately, from its first release after it is added there); an installed
package replaces the built-in copy. `tools/build-lce-packages.py` says what a package holds; each run
loads and probes every package on OXT-Beyond's engine (Linux x86-64), and the other platforms'
libraries in a package are the committed ones (verified statically; needs an IDE pass on each, bar one: the sodiumxt package installed through OXT-Beyond's Extension Manager on Windows x86-64 and answered `sxVersion()` on 2026-10-21, work plan 1.2 #29).

**From the tree.** Each native member is a standard OXT extension: an LCB module plus the
per-platform library bundled under `src/code/<arch>-<platform>/`, which the engine finds itself
(no `sudo`, no `LD_LIBRARY_PATH`); artnetxt is the same with no library at all. OnionXT and
NostrXT are pure LiveCodeScript: `start using`
their `src/*.livecodescript` libraries, or open a demo that carries them
(`onionxt/examples/onionxt-demo.livecodescript`, `nostrxt/examples/nostrxt-demo.livecodescript`).
Install only what you need. Each member answers a load check in the message box:

```
put sxVersion()          -- sodiumxt, e.g. "SodiumXT 0.1.0 (libsodium 1.0.22)"
put btStartSession()     -- torrentxt: a session handle > 0 (then btStopSession it)
put enLibraryVersion()   -- enetxt
put dcLibraryVersion()   -- datachannelxt
put b2Version()          -- box2dxt: prints 4
put cxKeccak256Len()     -- coinxt: prints 32
put cuLibraryVersion()   -- curlxt
put b3LibraryVersion()   -- box3dxt
put auLibraryVersion()   -- audioxt
put r3LibraryVersion()   -- render3dxt
put pdfLibraryVersion()  -- pdfxt
put gpLibraryVersion()   -- gamepadxt
put xlLibraryVersion()   -- xlsxt
put wpLibraryVersion()   -- webpxt
put bcLibraryVersion()   -- barcodext
put oscVersion()         -- oscxt: prints 2 (its ABI)
put midiVersion()        -- midixt: prints 2 (its ABI)
put the number of bytes in artnetBuildPoll()   -- artnetxt: prints 14
put oxVersion()          -- onionxt (its library in use)
put nxVersion()          -- nostrxt (after start using stack "nostrxt")
```

## The suite self-test

`tests/suite-selftest.livecodescript` is one stack script that builds its own window, probes every
member and reports PASS / FAIL / SKIP (a member you did not install skips, never fails). It folds in
every extension's deep self-test plus riptide's and holde-em's, adds the cross-member compositions,
and is **generated** by `tools/build-suite-selftest.py`, so it cannot drift from the code it tests.
The ENet and DataChannel async loopbacks stay in their own harnesses (two state machines in one
process would race), and holde-em's live game is held out of reach by a gate. Every `suite gates`
run uploads it as a `suite-selftest` artifact, with its coverage report and the runbook.

**Coverage is measured, not asserted.** `tools/check-suite-coverage.py` holds the paste to a
ratchet: a public handler nothing calls fails the build, and so does a stale excuse. The only
exemptions are onionxt's engine socket callbacks and live-tor legs, each with a written reason. It
counts handlers reached, not tested well, and prints its own numbers: run it. box2dxt's raw `b2*`
binding (whose C side `box2dxt/tests/smoke_test.c` enters in full) and holde-em's `he*` surface are
advisory rows with armed floors.

## How they compose

- **Identity once, transport by reachability.** One SodiumXT seed derives a BEP44 DHT key
  (TorrentXT) AND a v3 onion address (OnionXT): the same ed25519 key, so reaching you is verifying
  you.
- **The transport ladder.** enetxt for many peers at game cadence on a LAN; datachannelxt for
  NAT-traversed internet pairs; torrentxt for bulk and many-to-many; onionxt when the path itself
  must stay private. The 60000-byte budget is the seam where a message becomes a torrent.
- **The social app.** riptide builds all eight phases of its spec: 1-4 (identity, the live feed,
  media, DMs) are done on two machines, the compute of 4, 6 and 7 is engine-verified, and the live
  passes of 5-8 (calls, the LAN mesh, the anon persona, the Nostr bridge) are scripted in
  `riptide/docs/two-machine-runbook.md`. The Nostr bridge is reach, never a dependency: an `RSN1`
  record signed by BOTH the ed25519 handle and the secp256k1 npub.
- **The open social wire.** nostrxt speaks a public protocol: the coinxt BIP-340 key that signs a
  Taproot spend signs a Nostr event, and sodiumxt supplies the randomness and the NIP-44 cipher, so
  an xTalk app can talk to the existing relay ecosystem.
- **The game stack.** box2dxt's Kit is a working game engine and enetxt is game-grade networking.
  holde-em is the worked proof over torrentxt and sodiumxt: serverless poker with a signed
  transcript and a mental-poker deal (its live multi-machine passes are open).
- **The shipped product.** nocloud composes the ladder into file sharing: the DHT introduces the
  machines, BitTorrent moves the bytes, and the passphrase seal and the Tor path each degrade
  independently when their member is absent.

## Development

Members build independently (each has its own `CMakeLists.txt` or build script and its own
`tools/run-gates.sh`), and `tools/build-all.sh` walks them; `tools/build-all.sh --gates` runs the
compiler-free gate set. [CLAUDE.md](CLAUDE.md) is the suite's working guide: the rules, the carried
blocks, the gates and the generators. CI runs only from the root:

- **`suite-gates.yml`**: every member's compiler-free gates on every push, plus the native
  cross-member invariants when a change touches them.
- **`native-<member>.yml`**: that member's platform matrix and sanitizer lanes; artifacts only, it
  never commits a binary.
- **`release-binaries.yml`**: a manual dispatch that builds every native member for every platform
  (universal, unsigned macOS dylibs included), checks each library, runs the gates and commits.
  Since 2026-11-18 its `android` job builds all seven for the four Android ABIs through
  `tools/build-android.sh` and runs their tests on an Android 5.0 emulator for the two x86 ABIs
  ([docs/ANDROID.md](docs/ANDROID.md)).
- **`publish-members.yml`**: once the gates pass on `main`, replays each member's changes into its
  own repository, fast-forward only; contributions made there are ported back here.

## Documentation

- Each member's `README.md` is its front door, with its own documentation table.
- [docs/README.md](docs/README.md) indexes the suite documents: the engine runbook and engine
  notes, the work plan, the owner decisions, publishing, the binding playbook, the anonymous
  transport (Model C) and the Riptide spec and protocol.

## Community and support

- **Questions and discussion:** the [OpenXTalk forums](https://openxtalk.org/forum/).
- **Bugs and ideas:** [GitHub issues](https://github.com/SethMorrowSoftware/xtalk-suite/issues),
  with a form for each; [SUPPORT.md](SUPPORT.md) says where each kind of question goes.
- **Security problems:** report them privately, as [SECURITY.md](SECURITY.md) describes. Several
  members guard keys and money, so please do not open a public issue for one.
- **Contributing:** [CONTRIBUTING.md](CONTRIBUTING.md). Everyone taking part follows the
  [Code of Conduct](CODE_OF_CONDUCT.md).

## License

The suite and every member are **MIT** (see `LICENSE`, which also lists each bundled third-party
library and its license: libtorrent (BSD-3) + Boost, libsodium (ISC), ENet (MIT), libdatachannel
(MPL-2.0) + usrsctp (BSD-3), trezor-crypto and bitcoin-core/libsecp256k1 (both MIT), Box2D v3
(MIT)). OnionXT and NostrXT ship no third-party code: OnionXT talks to a Tor daemon you run, and
NostrXT is pure script over its sibling extensions. One gap is known: OpenSSL (Apache-2.0) is
statically linked into torrentxt's Windows, macOS and x86_64-Linux builds and datachannelxt's
Windows and macOS builds, and `LICENSE` does not carry its notice yet (tracked in
[docs/WORK-PLAN.md](docs/WORK-PLAN.md)).
