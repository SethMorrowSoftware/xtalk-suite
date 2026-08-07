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
| **[coinxt](coinxt/)** | `cx*` | trezor-crypto | Bitcoin + Ethereum primitives: secp256k1, ECDSA/recoverable/Schnorr, HD wallets (BIP-32/39), Keccak, address formats |

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
| enetxt | yes | x86_64-linux (other platforms build in CI) | Phase 1 complete; OXT selftest passed 2026-08-07 |
| datachannelxt | yes | x86_64-linux | Phases 1-2 (data channels) |
| onionxt | no — pure LiveCodeScript | n/a | On-engine proven against a live Tor daemon |
| coinxt | yes (source + `build.sh`; not yet built) | none yet | Designed and statically reasoned |

**The honesty convention, suite-wide.** OXT is a GUI runtime — there is no
headless way to compile or run `.lcb` / `.livecodescript`. Anything not observed
on a real engine is labelled **"verified statically; needs an OXT pass"** (Tor
paths: "+ live-Tor pass"). No member claims a runtime behaviour it has not
measured.

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

Each member ships as a standard OXT extension: an LCB (or script) module plus
the per-platform native library bundled under `src/code/<arch>-<platform>/`.
Install through the OpenXTalk / LiveCode **Extension Manager** the same way you
install any extension; the engine resolves the native library automatically —
no loose library, no `sudo`, no `LD_LIBRARY_PATH`, no rename. Install only the
members you need, or the whole suite. Verify from the message box — each member
answers a load-check handler:

```
put sxVersion()          -- sodiumxt,  e.g. "SodiumXT 0.1.0 (libsodium 1.0.20)"
put enLibraryVersion()   -- enetxt
put dcLibraryVersion()   -- datachannelxt
put oxVersion()          -- onionxt
put btStartSession()     -- torrentxt: a session handle > 0 (then btStopSession it)
```

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
`tools/`), and `tools/build-all.sh` walks them. The suite CI
(`.github/workflows/suite-gates.yml`) runs every member's static gates on each
push; the per-member `.github/` workflows are retained for reference but are
**inert in the monorepo** (GitHub Actions runs only the root workflow). See
`CLAUDE.md` for the suite-level workflow and `docs/README.md` for the
cross-cutting documents.

## License

The suite and every member are **MIT** (see `LICENSE`, which also lists each
member's bundled third-party library and its license — libtorrent (BSD-3) +
Boost, libsodium (ISC), ENet (MIT), libdatachannel (MPL-2.0) + usrsctp (BSD-3),
trezor-crypto (MIT)). OnionXT ships no third-party code; it talks to a Tor
daemon you run.
