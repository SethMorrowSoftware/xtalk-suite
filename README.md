# xTalk Suite

**Extensions that give OpenXTalk (OXT) and the xTalk family (also LiveCode 9.6.3+) the
capabilities app authors reach for: cryptography, BitTorrent, reliable-UDP realtime, WebRTC, Tor,
Bitcoin and Ethereum primitives, 2-D physics with a game kit, and Nostr.** Each is a small,
friendly set of xTalk handlers, and each native member bundles its library inside the extension,
so there is nothing else to install. Eight extensions, plus three apps built on them.

Every member is a thin binding over a proven C/C++ library (or, for OnionXT and NostrXT, pure
LiveCodeScript), built to one set of engineering rules so they read as one system and compose:
identity, transport and storage can come from different members. The apps are the proof. All of
it is developed here, and each member is also published into its own repository
([docs/MEMBER-REPO-SPLIT.md](docs/MEMBER-REPO-SPLIT.md)).

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
| [coinxt](coinxt/) | `cx*` | trezor-crypto + bitcoin-core/secp256k1 | Bitcoin and Ethereum primitives: hashes, secp256k1 ECDSA (RFC 6979, recoverable), BIP-340 Schnorr and the BIP-341 Taproot tweak and sighash, encodings and addresses, BIP-39/32/44 HD wallets, WIF, Bitcoin legacy / SegWit / Taproot and Ethereum EIP-155 / EIP-1559 transactions |

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

1. Install [OpenXTalk](https://openxtalk.org).
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
| sodiumxt | 5 platforms, ABI 10 | full `sxSelfTest()` 106/106 incl. ChaCha20, Windows x86_64, 2026-08-24 (on a mingw DLL since replaced) | the shipped MSVC Windows DLLs, both bitnesses; a first Mac load; the demo re-pass |
| torrentxt | 5 platforms, ABI 11 | harness 101/101, Windows, 2026-08-17, 08-20 and 08-24; rp1 chat reported working across two machines on one LAN, 2026-08-27 | first contact with the 2026-09-12 binaries (the first libtorrent 2.1 run on Windows); demo re-opens; the Tor paths; two-machine seed/leech and resume; a real public swarm |
| enetxt | 5 platforms, ABI 2 | standalone async loopback, 2026-08-13; folded 34 checks green, Windows, 2026-08-20 | LAN chat between two machines; internet chat across two networks |
| datachannelxt | 5 platforms, ABI 1 | standalone async loopback, 2026-08-15; folded 39 checks green, Windows, 2026-08-20; a DHT-signalled chat reported working across two machines on one LAN, 2026-08-27 | browser interop; a call across two networks; the loopback demo |
| onionxt | pure script | live-Tor core and `oxh*` hosting at bring-up (pre-suite, undated); offline self-test 61/0, Windows x86_64, 2026-08-17; Esplora and Electrum over Tor from the coin wallet, 2026-09-02 and 09-03 | launching tor from the library (Mode B); four inline probes; an OnionXT-to-OnionXT round trip; live negative paths |
| nostrxt | pure script | core 274/0/2, Windows x86_64, 2026-08-24; relay connect, publish and ok-confirm live against wss://nos.lol the same day | the relay receive leg; NIP-42; `ws://`; bad-certificate TLS (engine note 6.8) |
| box2dxt | 5 platforms, ABI 4 | Kit harness v30: 375/0 Windows, 2026-08-20; 374/1 Linux, 2026-08-21 (the red is `playLoudness` readback, engine note 5.4) | the v31 total; the five game stacks since the 2026-08-14 fold; risk R1 on Linux and macOS |
| coinxt | 5 platforms, ABI 7 | library 290/290 at ABI 6 incl. BIP-341, Windows x86_64, 2026-08-24; the wallet's engine logs, 2026-09-01 to 09-03: all four public transports, testnet broadcasts, RBF, CPFP, an inscription | `cxPubkeyCombine` (ABI 7) and silent-payment receive; the wallet surface added since 2026-09-04; a native-P2WPKH and any Ethereum broadcast; the x86-win32 DLL |
| riptide | app | phases 1-4 done on two machines, 2026-08-13 and 2026-08-15; harness 391/391, Windows x86_64, 2026-08-24 | live passes of phases 5-8; the faststart re-run; the boot re-paste |
| nocloud | app | no dated engine pass in this tree (its pre-fold passes are undated); gates green, including a headless execution gate | the 69-item OXT checklist, web-link and Tor halves |
| holde-em | app | folded harness 667/0 at v0.25.2, 2026-08-27 | the v44 total; a six-seat hotseat session; the multi-machine exits; Level 2 is not yet wired into played hands |

**Platform gaps, suite-wide.** Every native member's current binaries come from the 2026-09-12
release dispatch (commit 421bab3), and no engine has loaded those builds yet. No OXT engine has
loaded any `universal-mac` dylib. The 32-bit rows lack engine records: sodiumxt, torrentxt and
coinxt on x86-win32 (coinxt's 32-bit DLL has not executed anywhere, even in CI), sodiumxt and
torrentxt on x86-linux. The Windows DLLs carry libsodium 1.0.22 (accepted, D-08) and libtorrent
2.1.1 rather than the 1.0.20 and 2.0.11 the other platforms pin. Linux floors vary: both
datachannelxt builds and torrentxt's 32-bit build need glibc 2.38, box2dxt's 32-bit build 2.34.
The macOS dylibs are universal (arm64 + x86_64) and unsigned.

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

Each native member is a standard OXT extension: an LCB module plus the per-platform library
bundled under `src/code/<arch>-<platform>/`. Install it with the **Extension Manager** like any
extension; the engine finds the library itself (no `sudo`, no `LD_LIBRARY_PATH`). **OnionXT and
NostrXT are pure LiveCodeScript** with no packaged extension: `start using` their
`src/*.livecodescript` libraries, or open a demo that carries them
(`onionxt/examples/onionxt-demo.livecodescript`, `nostrxt/examples/nostrxt-demo.livecodescript`).
Install only what you need. Each member answers a load check in the message box:

```
put sxVersion()          -- sodiumxt, e.g. "SodiumXT 0.1.0 (libsodium 1.0.20)"
put btStartSession()     -- torrentxt: a session handle > 0 (then btStopSession it)
put enLibraryVersion()   -- enetxt
put dcLibraryVersion()   -- datachannelxt
put b2Version()          -- box2dxt: prints 4
put cxKeccak256Len()     -- coinxt: prints 32
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
- **`publish-members.yml`**: once the gates pass on `main`, replays each member's changes into its
  own repository, fast-forward only; contributions made there are ported back here.

## Documentation

- Each member's `README.md` is its front door, with its own documentation table.
- [docs/README.md](docs/README.md) indexes the suite documents: the engine runbook and engine
  notes, the work plan, the owner decisions, publishing, the binding playbook, the anonymous
  transport (Model C) and the Riptide spec and protocol.

## License

The suite and every member are **MIT** (see `LICENSE`, which also lists each bundled third-party
library and its license: libtorrent (BSD-3) + Boost, libsodium (ISC), ENet (MIT), libdatachannel
(MPL-2.0) + usrsctp (BSD-3), trezor-crypto and bitcoin-core/libsecp256k1 (both MIT), Box2D v3
(MIT)). OnionXT and NostrXT ship no third-party code: OnionXT talks to a Tor daemon you run, and
NostrXT is pure script over its sibling extensions. One gap is known: OpenSSL (Apache-2.0) is
statically linked into torrentxt's Windows, macOS and x86_64-Linux builds and datachannelxt's
Windows and macOS builds, and `LICENSE` does not carry its notice yet (tracked in
[docs/WORK-PLAN.md](docs/WORK-PLAN.md)).
