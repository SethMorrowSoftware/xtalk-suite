# xTalk Suite

**A family of native extensions that give OpenXTalk (OXT) / the xTalk family
(also LiveCode 9.6.3+) the modern capabilities app authors actually reach for:
cryptography, BitTorrent, reliable-UDP realtime, WebRTC, Tor, and coin
primitives — each behind a small, friendly set of xTalk handlers, each with the
native library bundled inside the extension so there is nothing to install
separately.**

Every member is a thin, well-behaved binding over a proven C/C++ library (or,
for OnionXT, pure LiveCodeScript over a local Tor daemon), built to one shared
set of engineering rules so the six read as one system. They interoperate: your
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
| **[coinxt](coinxt/)** | `cx*` | trezor-crypto | Bitcoin + Ethereum primitives, designed: secp256k1, ECDSA/recoverable/Schnorr, HD wallets (BIP-32/39), address formats (the Keccak/SHA3 hash slice is built and KAT-verified; the rest is spec'd in `coinxt/SPEC.md`, not yet built) |

They share a namespace — `org.openxtalk.library.{sodium,torrent,enet,datachannel,...}`
— so the engine resolves each binding automatically once its packaged extension
is installed.

## Release status (honest, per member)

Maturity is uneven by design — the suite is released as members reach the bar,
not held back to the slowest. Each member's own `README.md` / `CLAUDE.md` is the
authority; this is the summary:

| Extension | Native shim | Committed binaries | Maturity |
|---|---|---|---|
| sodiumxt | yes | **all 5 platforms** (Linux x64/x86, Windows x64/x86, universal-mac) + `MANIFEST.sha256` | The most complete member |
| torrentxt | yes | Linux x64/x86, Windows x64/x86 (**macOS build pending**) | Mature; broad ABI, runtime-proven |
| enetxt | yes | x86_64-linux committed; the root CI builds and tests all 5 platforms and publishes them as artifacts | Phase 1 complete; OXT selftest passed 2026-08-07 |
| datachannelxt | yes | x86_64-linux | Phases 1-2 (data channels); script layer needs an OXT pass |
| onionxt | no — pure LiveCodeScript | n/a | On-engine proven against a live Tor daemon |
| coinxt | yes (source + `native/build.sh`; ASan self-test + KATs green) | x86_64-linux + `MANIFEST.sha256` (`native/build.sh pack` builds the rest) | Designed and statically reasoned; the phase-1 hash surface built, KAT-verified, and bound in `src/coinxt.lcb` (needs an OXT pass) |

**The honesty convention, suite-wide.** OXT is a GUI runtime — there is no
headless way to compile or run `.lcb` / `.livecodescript`. Anything not observed
on a real engine is labelled **"verified statically; needs an OXT pass"** (Tor
paths: "+ live-Tor pass"). No member claims a runtime behaviour it has not
measured. `docs/OXT-PASS-RUNBOOK.md` is the runbook for closing that gap: what is
still unproven and where each label lives, the install order, the run order, and
what to record.

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
5. **The OXT compiler footguns** (ASCII quotes only; `k`/`p`/`s`/`t` prefixes;
   literal constants declared before first use; declarations at the top of a
   handler; `unsafe … end unsafe` around foreign calls) are enforced by
   `tools/check-livecodescript.py`, which every member carries.

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

Or run all six at once: `tests/suite-selftest.livecodescript` is a single stack
script that builds its own UI, probes for every member, runs each one's headline
paths plus the cross-member compositions, and reports PASS / FAIL / SKIP in one
list — a member you did not install skips, it never fails. See
`docs/OXT-PASS-RUNBOOK.md`.

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
  social app on all six; `docs/NEXT-EXTENSIONS-PLAN.md` is the roadmap that
  produced them; `docs/ONIONXT-INTEGRATION-PLAN.md` is the anonymity-transport
  integration.

## Development

Members build independently (each has its own `CMakeLists.txt` /
`tools/`), and `tools/build-all.sh` walks them. CI is two layers, both at the
repository root (GitHub Actions runs only root workflows, so the per-member
`.github/` files are retained for isolated development but are **inert in the
monorepo**):

- **`suite-gates.yml`** — every member's compiler-free gates on every push: the
  LiveCodeScript checker, docs house-style, all golden-vector suites, the
  record registries, the known-answer harnesses, standalone freshness, and the
  `MANIFEST.sha256` integrity checks.
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
