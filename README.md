# xTalk Suite

**A family of native extensions that give OpenXTalk (OXT) / the xTalk family
(also LiveCode 9.6.3+) the modern capabilities app authors actually reach for:
cryptography, BitTorrent, reliable-UDP realtime, WebRTC, Tor, and coin
primitives — each behind a small, friendly set of xTalk handlers, each with the
native library bundled inside the extension so there is nothing to install
separately.**

Every member is a thin, well-behaved binding over a proven C/C++ library (or,
for OnionXT, pure LiveCodeScript over a local Tor daemon), built to one shared
set of engineering rules so the seven read as one system. They interoperate: your
identity, your transport, and your storage can come from different members and
compose cleanly — the flagship of that idea is the **Riptide Social** design
(`docs/RIPTIDE-SOCIAL-SPEC.md`), a serverless social app that uses all of them.

## The family

| Extension | Handlers | Wraps | What it gives an xTalk app |
|---|---|---|---|
| **[sodiumxt](sodiumxt/)** | `sx*` | libsodium | Authenticated encryption, signatures, sealed boxes, Argon2id, key derivation, streaming file crypto, hashing, CSPRNG |
| **[torrentxt](torrentxt/)** | `bt*` | libtorrent-rasterbar | The full BitTorrent protocol: DHT, PEX, magnets/metadata, uTP, trackers, webseeds, v1+v2, BEP44 signed mutable items, the rp1 peer-wire transport |
| **[enetxt](enetxt/)** | `en*` | ENet 1.3.18 | Game-grade reliable-UDP: reliable / unreliable-sequenced / unsequenced delivery on independent channels, one-call broadcast |
| **[datachannelxt](datachannelxt/)** | `dc*` | libdatachannel | Browser-interoperable WebRTC data channels with real NAT traversal (ICE) and per-channel reliability |
| **[onionxt](onionxt/)** | `ox*` / `oxh*` | a local Tor daemon (pure script) | Anonymous TCP streams, self-authenticating v3 onion services, HTTP-over-onion hosting |
| **[box2dxt](box2dxt/)** | `b2*` / `b2k*` | Box2D v3.1.0 | The family ANCESTOR, folded home 2026-08-14: full rigid-body physics (bodies, joints, motors, sensors, queries) plus the pure-script **b2k game Kit** - control-backed bodies in pixels/degrees, sprites, input, a player controller and a camera - the game-engine half that pairs with enetxt's game-grade networking |
| **[coinxt](coinxt/)** | `cx*` | trezor-crypto | Bitcoin + Ethereum primitives. **Built:** the hash surface (Keccak-256/SHA3/SHA-2/RIPEMD-160/HMAC/PBKDF2), the secp256k1 curve (ECDSA RFC 6979, recoverable + `ecrecover`, ECDH), the encodings and addresses (hex, Base58Check, Bech32/Bech32m, RLP, P2PKH/P2WPKH/P2TR/ETH + EIP-55), HD wallets (BIP-39 mnemonics, BIP-32/BIP-44 derivation, xprv/xpub), and (phase 5) transactions (Bitcoin legacy + BIP-143 SegWit, Ethereum EIP-155 + EIP-1559) — engine-passed 2026-08-12. Schnorr/BIP-340 deferred with Taproot |

They share a namespace — `org.openxtalk.library.{sodium,torrent,enet,datachannel,...}`
— so the engine resolves each binding automatically once its packaged extension
is installed. (box2dxt predates that convention and ships as
`org.openxtalk.box2dxt`; the name is installed on users' machines, so it
stays.)

## Start here (no experience needed)

1. **Install [OpenXTalk](https://openxtalk.org)** if you have not already.
2. **Download this repository** — the green **Code** button above, then
   **Download ZIP** — and unzip it anywhere (or `git clone` it).
3. In OpenXTalk pick **File > Open Stack** and choose
   [`start-here.livecodescript`](start-here.livecodescript) from the
   unzipped folder.

That opens a clickable directory of every sample, demo and harness stack,
listed by the path it has in this repository. Click one to read what it is
and what it needs; **double-click (or press Open) to launch it** right from
where the download put it — helper stacks are put in use for you, and its
**Setup help** button explains the rest in plain language. Everything here
is a script-only stack that builds its own window when opened, so there is
nothing to install or copy first; a stack missing an extension says so in
red at the top rather than breaking. (`tools/check-launcher-registry.py`
holds the directory true to the tree on every push.)

## Release status (honest, per member)

Maturity is uneven by design — the suite is released as members reach the bar,
not held back to the slowest. Each member's own `README.md` / `CLAUDE.md` is the
authority; this is the summary:

| Extension | Native shim | Committed binaries | Maturity |
|---|---|---|---|
| sodiumxt | yes | **all 5 platforms** (Linux x64/x86, Windows x64/x86 at ABI 7; `universal-mac` still ABI 6, one behind, pending the manual `lipo` build) + `MANIFEST.sha256` | The most complete member. The full `sxSelfTest()` — now 71 checks, every post-pass addition included — ran green on-engine 2026-08-12, folded into the suite harness, on top of the 2026-08-08 headline-path pass |
| torrentxt | yes | Linux x64/x86, Windows x64/x86 (**macOS build pending**) | Mature; broad ABI. Session lifecycle and the signed-put path observed on-engine 2026-08-08; the full 96-check member selftest ran green on-engine 2026-08-10 (folded), the v9-v11 surface included. Two-machine rp1/DHT behaviour still open |
| enetxt | yes | Linux x64/x86, Windows x64/x86 (**macOS build pending**) | Phase 1 complete; member selftest passed 2026-08-07, a live loopback plus the 60000-byte fragmentation contract re-confirmed 2026-08-08, and the isolated abrupt-teardown section ran green 2026-08-10 (folded sync half). The standalone async loopback - the live `enHostStatus` pair and the `enPeerStatus` statistics included - ran green 2026-08-13, so nothing in its selftest is static any more; only the two-machine LAN chat stays open |
| datachannelxt | yes | Linux x64/x86, Windows x64/x86 (**macOS build pending**) | Phases 1-2 (data channels). **First engine evidence 2026-08-08**: a live loopback negotiated, opened, and round-tripped byte-for-byte. All 31 public `dc*` handlers have now been called on-engine (2026-08-10, folded sync half); only the member harness's own async live halves stay static |
| onionxt | no — pure LiveCodeScript | n/a | On-engine proven against a live Tor daemon; the daemon-free address and capability paths re-confirmed 2026-08-08, and the full `oxSelfTest()` (now 43 checks) ran green on-engine 2026-08-12, folded. Mode B (launching tor) still unexercised |
| box2dxt | yes | **all 5 platforms** + `MANIFEST.sha256` (added in the fold) | The family ancestor, mature and feature-frozen upstream. The 2026-08-14 fold replaced its pre-unification checker with the suite's (first contact found ~1550 violations: mostly the pre-ASCII character set, plus 29 real `repeat with ... step` engine traps in the platformer, all fixed) - so the whole member is **verified statically; needs an OXT re-pass**; its prior engine evidence predates the sweep |
| coinxt | yes (source + `native/build.sh`; ASan self-test + KATs green) | Linux x64/x86, Windows x64/x86 (**macOS build pending**) + `MANIFEST.sha256` | **All five phases engine-proven.** Phase 1 closed 2026-08-08; **phases 2, 3 and 4 closed 2026-08-10** — the member harness ran folded into the suite selftest at 205/206, and the one red line was a real parser fail-open (`cxHdDerivePath` of `"m/"`), fixed, re-modelled in the headless interpreter, and confirmed at **207/207** the same day. The headless gates still cross-verify on every push: RFC 6979 vectors, an independent `ecdsa` library, and `check-script-vectors.py` driving the real `.livecodescript` down BIP-44/BIP-84/Ethereum paths to their published addresses. **Phase 5 (transactions) is ENGINE-PASSED (2026-08-12, Windows x64, 230/230)**: Bitcoin legacy + BIP-143 SegWit and Ethereum EIP-155 + EIP-1559, model-verified against the BIP-143/EIP-155 published examples, driven through the real `.livecodescript` by `check-script-vectors.py` (251 checks) — which caught and fixed a would-be-red engine defect (`cxBtcTxEncode` refused the reference tx over a trailing-empty scriptSig) — and then confirmed on a real engine, the BIP-143 signed tx byte for byte. The independent-decoder bar is met (2026-08-12, extended 2026-08-13 to all four tx families: python-bitcointx accepts fresh legacy + segwit spends under consensus rules, eth-account recovers the exact sender from fresh EIP-155 + EIP-1559 txs); a live testnet broadcast is the one bar left before "broadcastable" |

**Where the suite stands after the 2026-08-08 and 2026-08-10 passes.** On
2026-08-08 `tests/suite-selftest.livecodescript` ran green on a real OXT engine
with all six members installed — the suite's first end-to-end runtime evidence.
It proved the compositions that are the actual product: one SodiumXT seed derives
the *same* ed25519 identity in libsodium and libtorrent, libtorrent's DHT secret
key **is** SodiumXT's expanded key, TorrentXT accepts a SodiumXT signature over a
BEP44 item and **refuses** one minted for another sequence number, and a single
SodiumXT-sealed payload crosses **both** live transports byte-for-byte under the
60000-byte budget they share. On 2026-08-10 the harness ran again in its current,
self-contained form — every member's own deep self-test folded in, the coinxt and
onionxt script layers embedded in the paste — and reported **zero failures across
455 member-harness checks plus the whole core**, re-confirming the compositions
and retiring the deeper per-member selftests as an open item. What remains
broadly open: **macOS binaries** for four of the five native members, and the
**live-Tor and two-machine work** (runbook items 4-6), which no single-machine
offline paste can reach.

The 2026-08-12 re-run then exercised all seven folded harnesses at their current
sizes — **617 member-harness checks, zero failures** (SodiumXT 71, OnionXT 43,
CoinXT 230, TorrentXT 96, ENetXT 21, DataChannelXT 23, Riptide 133). In
particular, Riptide's phase-2 live feed layer passed its canonical BEP44 buffer,
real-session publish/request, and synthetic ingest-verifier sections. This
closes the single-engine half of runbook item 10; cross-machine DHT propagation
remains part of item 6.

**The honesty convention, suite-wide.** OXT is a GUI runtime — there is no
headless way to compile or run `.lcb` / `.livecodescript`. Anything not observed
on a real engine is labelled **"verified statically; needs an OXT pass"** (Tor
paths: "+ live-Tor pass"). No member claims a runtime behaviour it has not
measured. `docs/OXT-PASS-RUNBOOK.md` is the runbook for closing that gap: what is
still unproven and where each label lives, the install order, the run order, and
what to record. The convention cuts both ways — a label is removed only for what
a run actually exercised, so each recorded pass (2026-08-08, 2026-08-10) promoted
the handlers it called and left the ones it did not still labelled, member by
member — which is why the datachannel async-loopback half is still labelled
today, inside an otherwise green suite (the enet half closed with the
2026-08-13 standalone pass).

## The shared engineering rules

These hold across every member; a member's `CLAUDE.md` adds only what is
specific to it.

1. **Never call an xTalk handler from a foreign thread.** Inbound events ride a
   queue that script *poll-drains* on a timer; no callback ever runs script.
   (Trivially true for the threadless members — ENet, OnionXT — which are
   "pump or nothing".)
2. **The exception firewall.** Every `extern "C"` entry point wraps
   `try { … } catch (...) { set_error(…); return <error>; }`. No exception ever
   crosses the FFI into the engine.
3. **Payload never crosses the FFI into script** where a design can avoid it —
   bulk bytes stay engine ⇄ disk; only small status records and events cross.
4. **Handles are generation-tagged integers**, validated before use, so a stale
   handle is a harmless no-op, never a crash.
5. **The OXT compiler footguns** (ASCII only; `k`/`p`/`s`/`t` prefixes and the
   token-shadow trap; literal constants declared before first use;
   declarations at the top of an `.lcb` handler; `unsafe … end unsafe` around
   foreign calls; block balance, the zero-arg-statement-call refusal, and
   more) are enforced by `tools/check-livecodescript.py`, which every member
   carries as one byte-identical, fixture-tested copy (the suite gates
   `tools/check-checker-drift.py` and `tools/test-checker.py` keep it that
   way).

## Install

Each native member ships as a standard OXT extension: an LCB module plus the
per-platform native library bundled under `src/code/<arch>-<platform>/`.
Install through the OpenXTalk / LiveCode **Extension Manager** the same way you
install any extension; the engine resolves the native library automatically —
no loose library, no `sudo`, no `LD_LIBRARY_PATH`, no rename. **OnionXT is the
exception**: it is pure LiveCodeScript with no packaged extension — copy its
two `src/*.livecodescript` libraries into your app (`start using`), or build a
paste-and-run standalone with `onionxt/tools/build-standalone.py` (see
`onionxt/docs/10-usage-guide.md`). Install only the
members you need, or the whole suite. Verify from the message box — each member
answers a load-check handler:

```
put sxVersion()          -- sodiumxt,  e.g. "SodiumXT 0.1.0 (libsodium 1.0.20)"
put enLibraryVersion()   -- enetxt
put dcLibraryVersion()   -- datachannelxt
put oxVersion()          -- onionxt
put btStartSession()     -- torrentxt: a session handle > 0 (then btStopSession it)
put cxKeccak256Len()     -- coinxt: prints 32
```

Or run all six suite members plus the Riptide app layer at once.
`tests/suite-selftest.livecodescript` is a single stack script that builds its
own UI, probes for every member, and reports PASS / FAIL / SKIP in one list — a
member you did not install skips, it never fails.

It is not a sampler. It carries **every member's own deep self-test**, folded in
whole: sodiumxt's `sxSelfTest` (21 groups), onionxt's `oxSelfTest` (8, all
offline), coinxt's sections (encodings, addresses, HD, and the phase-5
transaction KATs), torrentxt's full harness, the synchronous halves of enetxt
and datachannelxt, and riptide's harness (phases 1-4, including the live feed,
media, and DM layers against the suite's own session) — plus the cross-member compositions no
per-member harness can have. One paste settles what used to take seven runs.

It is **generated** (`tools/build-suite-selftest.py`) from those harnesses rather
than copied from them, because a hand-copied test suite drifts and then reports
green about code that moved. The gate set runs `--check`, so a stale copy fails
the build. The only thing deliberately left out is the ENet and DataChannel
**async loopbacks**: this harness already drives a real loopback on both
transports for its cross-member sections, and two state machines in one process
would race — those stay in `enetxt/tests/` and `datachannelxt/tests/`. See
`docs/OXT-PASS-RUNBOOK.md`.

**How much of the suite it actually reaches is measured, not asserted.**
`tools/check-suite-coverage.py` runs in the gate set and holds it at
**359 of 377 public handlers**:

| sodiumxt | onionxt | coinxt | torrentxt | enetxt | datachannelxt | riptide |
|---|---|---|---|---|---|---|
| 61/61 | 27/45 | 78/78 | 85/85 | 23/23 | 31/31 | 54/54 |

The eighteen it does not reach are all onionxt's, and each carries a written
reason in that tool: eleven are **engine socket callbacks** (the engine supplies
a socket id no harness can mint) and seven need a **live tor daemon**. The gate
fails both on a new public handler that nothing exercises and on a stale excuse
left behind by a rename, so the shortfall can only ever be a decision somebody
wrote down. It counts handlers *reached*, not handlers tested well — depth is
each member's own vector gate.

**You do not have to clone it.** Every `suite gates` run uploads a
`suite-selftest` artifact with the pasteable script, that coverage report, and
the runbook.

## How they compose

The members are deliberately non-overlapping, so real apps mix them:

- **Identity once, transport by reachability.** One SodiumXT seed derives a
  BEP44 DHT key (TorrentXT) *and* a v3 onion address (OnionXT) — the same
  ed25519 key, so "reaching you is verifying you."
- **The transport ladder.** enetxt for many peers at game cadence on a LAN;
  datachannelxt for NAT-traversed internet pairs; torrentxt for bulk and
  many-to-many; onionxt when the network path itself must stay private. The
  60000-byte packet budget is the seam: when a payload stops being a message,
  it becomes a torrent.
- **The worked example.** `docs/RIPTIDE-SOCIAL-SPEC.md` designs a serverless
  social app on all six, and `riptide/` is that app being built — phase 1
  (the identity foundation and the feed wire formats, offline-verifiable,
  golden-pinned, and engine-passed 2026-08-12) and phase 2 (the live feed
  layer: signed BEP44 heads, content-addressed posts, verified ingest —
  engine-passed 2026-08-12 at 133/133, and its **two-machine propagation
  done-criterion met 2026-08-13**: `riptide/examples/riptide-social.livecodescript`
  exchanged verified feeds in both directions over the real DHT, the suite's
  first two-machine result) are COMPLETE in the tree; phases 3 (media —
  attachments seed in place as trackerless torrents, posts carry only
  info-hashes, followers fetch sequentially and co-seed) and 4 (DMs —
  signed kx prekeys in the feed head, sealed intros over inbox phantom
  swarms, pairwise secretstreams over rp1, crypto_kx anchored against a
  real libsodium) are BUILT (2026-08-14, statically verified; their
  done-criteria — a follower plays a video mid-download, and two machines
  exchange encrypted DMs with no server — await two-machine passes);
  `docs/NEXT-EXTENSIONS-PLAN.md` is the roadmap that produced the members;
  `docs/ONIONXT-INTEGRATION-PLAN.md` is the anonymity-transport
  integration.
- **The game stack.** box2dxt's b2k Kit is a working game engine (physics,
  sprites, input, camera - the platformer and contraption-builder examples
  are complete games), and enetxt is game-grade networking; together they
  are the suite's multiplayer-game story. The worked design for it is
  [`docs/holde-em/`](docs/holde-em/): serverless online Texas Hold'em where
  players meet over the torrentxt DHT, every action lives in a signed
  hash-chained transcript, and the deal runs a mental-poker shuffle -
  Riptide's sibling capstone, moved up from box2dxt's docs in the fold
  because it composes three members.
- **The shipped example.** [`nocloud/`](nocloud/) is **No Cloud Quick Share**,
  a finished end-user app that composes the suite the way the ladder above
  describes: peer-to-peer file sharing as one stack script over torrentxt
  (the DHT is the introduction, BitTorrent moves the bytes), with sodiumxt
  supplying the optional passphrase seal and onionxt the optional
  Private/Tor path — each degrading independently with a clear message when
  absent. Folded in from its standalone repository 2026-08-13 (that repo
  becomes a mirror, like every pre-suite home); it is member-shaped, so the
  same gate set walks it.

## Development

Members build independently (each has its own `CMakeLists.txt` /
`tools/`), and `tools/build-all.sh` walks them. CI is two layers, both at the
repository root (GitHub Actions runs only root workflows, so the per-member
`.github/` files are retained for isolated development but are **inert in the
monorepo**):

- **`suite-gates.yml`** — every member's compiler-free gates on every push: the
  LiveCodeScript checker, docs house-style, all golden-vector suites, the
  record registries, the known-answer harnesses, standalone freshness, the
  `MANIFEST.sha256` integrity checks, and the suite-level carried-block and
  budget gates (the UI-kit and harness-scaffold drift gates — one look, one
  scaffold, byte-identical everywhere, adoption enforced — plus the 720p
  stack-size budget: every sample window fits 1200 x 640).
- **`native-<member>.yml`** — the per-member native matrix, plus that member's
  sanitizer lanes, scoped by `paths:` so only the member you touched builds. The
  four CMake members cover all five platforms, each with its own dependency
  setup; coinxt builds from a shell script rather than CMake, so its lane covers
  Linux only and the file says exactly what macOS and Windows would still need.
  Each lane uploads its built library as an artifact; **these automatic
  workflows never commit binaries** — they fire on every push, so a commit step
  here would land binaries nobody asked for on somebody else's change.
  `coinxt/tools/check-binary-freshness.py` (in the always-on gates) turns
  forgetting to refresh one into a build failure rather than a load failure on a
  user's machine.

- **`release-binaries.yml`** — the assembly step, run by hand
  (`workflow_dispatch`). One dispatch builds every member for every platform it
  can be built for (20 build jobs: five members x four platforms), asserts each artifact, runs coinxt's
  published vectors against the real cross-built DLL on a Windows runner,
  publishes one bundle, and then **installs each library into its own member's
  `src/code/<platform-id>/`, refreshes the manifests, and commits**. It calls
  `tools/install-release-binaries.py` to do it, so the same checks apply whether
  CI lands the binaries or you do: each library's name, object format, and
  architecture are verified against the directory it claims — plus coinxt's
  export surface — before anything is written, and the whole gate set runs over
  the result before anything is pushed. `commit_mode` picks `branch` (the
  default), `pr`, or `none` (bundle only, land it yourself). Rule 5 still holds,
  because its point is that a committed binary traces to a human decision: here
  the decision is pressing "Run workflow". It builds **no macOS lanes**: `macos-15` runners are arm64-only, so they
  would emit a thin dylib into `universal-mac` and overwrite sodiumxt's genuine
  two-architecture binary with one that fails on every Intel Mac. macOS stays a
  deliberate manual `lipo` build (and, for torrentxt, a codesigned and notarized
  one), and the installer refuses a thin Mach-O so a hand-built bundle cannot
  make that mistake either.

See `CLAUDE.md` for the suite-level workflow and `docs/README.md` for the
cross-cutting documents.

## License

The suite and every member are **MIT** (see `LICENSE`, which also lists each
member's bundled third-party library and its license — libtorrent (BSD-3) +
Boost, libsodium (ISC), ENet (MIT), libdatachannel (MPL-2.0) + usrsctp (BSD-3),
trezor-crypto (MIT)). OnionXT ships no third-party code; it talks to a Tor
daemon you run.
