# xTalk Suite

**A family of native extensions that give OpenXTalk (OXT) / the xTalk family
(also LiveCode 9.6.3+) the modern capabilities app authors actually reach for:
cryptography, BitTorrent, reliable-UDP realtime, WebRTC, Tor, coin
primitives, 2-D physics with a game kit, and the Nostr protocol — each behind a
small, friendly set of xTalk handlers, each with any native library bundled
inside the extension so there is nothing to install separately.**

Every member is a thin, well-behaved binding over a proven C/C++ library (or,
for OnionXT and NostrXT, pure LiveCodeScript), built to one shared
set of engineering rules so the eight read as one system. They interoperate: your
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
| **[nostrxt](nostrxt/)** | `nx*` / `nxr*` | the Nostr protocol (pure script; crypto composed from coinxt + sodiumxt) | NIP-01 events with canonical ids and BIP-340 signatures, NIP-19 bech32 entities, the complete NIP-44 v2 payload construction (over SodiumXT ABI 10's `sxChaCha20IetfXor` since 2026-08-23; fails closed on an older installed SodiumXT), filters, and a websocket relay client with verify-before-deliver |
| **[box2dxt](box2dxt/)** | `b2*` / `b2k*` | Box2D v3.1.0 | The family ANCESTOR, folded home 2026-08-14: full rigid-body physics (bodies, joints, motors, sensors, queries) plus the pure-script **b2k game Kit** - control-backed bodies in pixels/degrees, sprites, input, a player controller and a camera - the game-engine half that pairs with enetxt's game-grade networking |
| **[coinxt](coinxt/)** | `cx*` | trezor-crypto + libsecp256k1 | Bitcoin + Ethereum primitives. **Built:** the hash surface (Keccak-256/SHA3/SHA-2/RIPEMD-160/HMAC/PBKDF2), the secp256k1 curve (ECDSA RFC 6979, recoverable + `ecrecover`, ECDH), the encodings and addresses (hex, Base58Check, Bech32/Bech32m, RLP, P2PKH/P2WPKH/P2TR/ETH + EIP-55), HD wallets (BIP-39 mnemonics, BIP-32/BIP-44 derivation, xprv/xpub), and (phase 5) transactions (Bitcoin legacy + BIP-143 SegWit, Ethereum EIP-155 + EIP-1559) — engine-passed 2026-08-12. **BIP-340 Schnorr + the BIP-341 Taproot tweak shipped 2026-08-16** (ABI 6), on a second vendored library - upstream bitcoin-core/secp256k1, pinned and hash-verified, since trezor-crypto has no BIP-340 - driven by all 19 published BIP-340 vectors (10 negative) and all 14 BIP-341 wallet vectors; **ENGINE-VERIFIED 2026-08-16** (the 278-check `cxSelfTest` ran green folded into the suite paste, Schnorr and Taproot sections included). There is still no BIP-341 sighash builder - coinxt signs a sighash it is handed, it cannot compute one |

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
where the download put it — each stack carries the script libraries it needs,
so nothing has to be wired up first, and its **Setup help** button explains
the rest in plain language. Everything here
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
| sodiumxt | yes | **all 5 platforms** (Linux x64/x86, Windows x64/x86 at ABI 10; `universal-mac` still ABI 6, four behind, pending the first mac dispatch of `release-binaries.yml` - its mac lanes landed 2026-08-23 - or a manual `lipo` build) + `MANIFEST.sha256` | The most complete member. The full `sxSelfTest()` — 71 checks — ran green on-engine 2026-08-12, folded into the suite harness, on top of the 2026-08-08 headline-path pass. ABI 8 (2026-08-15) added the ristretto255 group surface for holde-em's mental-poker deal, and ABI 9 (same day) its recorded Phase-5 follow-ons (point add/sub, base-point and one-crossing batch scalar multiplication, scalar add/mul: the DLEQ algebra) — C KATs cross-checked against an independent RFC 9496 reference and green under ASan; **BOTH RAN GREEN ON A REAL ENGINE 2026-08-16** - the full 99-check `sxSelfTest()` folded into the suite paste, ristretto255 and the whole ABI 9 DLEQ/batch surface included (RFC 9496 vectors, the mask/unmask roundtrip, batch agreeing with the single call, the atomic-void index, every negative path), so no `sxRistretto*` handler is static any more. ABI 10 (2026-08-23) added `sxChaCha20IetfXor`, the raw IETF ChaCha20 stream xor NIP-44 needs, on the argued exception in `sodiumxt/docs/security.md` - C KATs cross-checked against an independent RFC 8439 reference and green under ASan/UBSan; that one handler ran green ON-ENGINE 2026-08-24 (Windows x86_64, OXT 9.6.3: the 7-check ChaCha20 section inside sodiumxt's 106/106) - a run that is also the mingw-cross x64 DLL's execution proof at ABI 10. The x86 (32-bit) Windows DLL still needs its own platform proof |
| torrentxt | yes | Linux x64/x86, Windows x64/x86 (**macOS build pending**) | Mature; broad ABI. Session lifecycle and the signed-put path observed on-engine 2026-08-08; the full 96-check member selftest ran green on-engine 2026-08-10 (folded), the v9-v11 surface included. Two-machine rp1/DHT behaviour still open |
| enetxt | yes | Linux x64/x86, Windows x64/x86 (**macOS build pending**) | Phase 1 complete; member selftest passed 2026-08-07, a live loopback plus the 60000-byte fragmentation contract re-confirmed 2026-08-08, and the isolated abrupt-teardown section ran green 2026-08-10 (folded sync half). The standalone async loopback - the live `enHostStatus` pair and the `enPeerStatus` statistics included - ran green 2026-08-13, so nothing in its selftest is static any more; only the two-machine LAN chat stays open |
| datachannelxt | yes | Linux x64/x86, Windows x64/x86 (**macOS build pending**) | Phases 1-2 (data channels). **First engine evidence 2026-08-08**: a live loopback negotiated, opened, and round-tripped byte-for-byte. All 31 public `dc*` handlers have been called on-engine (2026-08-10, folded sync half). The standalone **async loopback** ran green 2026-08-15 - real SDP carrying ICE candidates, correct offer/answer roles, gathering complete on both peers, a selected candidate pair, text and binary (NUL included) byte-for-byte, `dcCreateChannelEx` label/protocol round-trip, and a cap-sized send - so nothing in its selftest is static any more; only browser interop and a two-network call stay open |
| onionxt | no — pure LiveCodeScript | n/a | On-engine proven against a live Tor daemon; the daemon-free address and capability paths re-confirmed 2026-08-08, and the full `oxSelfTest()` (43 checks on the 2026-08-12 engine run; section 10 added 18 more, so it attempts 41-61 depending on what is installed) ran green on-engine 2026-08-12, folded. Mode B (launching tor) still unexercised |
| nostrxt | no — pure LiveCodeScript (crypto composed from coinxt + sodiumxt) | n/a | New 2026-08-23; **the `nx*` core is ENGINE-PROVEN 2026-08-24** (Windows x86_64, OXT 9.6.3; 274 passed / 0 failed / 2 deliberate skips in the suite paste), and the relay layer is SPLIT: connect, handshake, publish and the relay's ok-confirm are live-proven the same day against wss://nos.lol, while the receive leg, NIP-42 auth and every ws:// path keep **“verified statically; needs a live-relay pass”**. What IS machine-verified headlessly: `tools/nostr-kat.py` sweeps the complete published BIP-340 csv, the full official NIP-44 v2 vector set, the BIP-173 strings and the NIP-19 examples through an independent oracle, and `tools/check-selftest-vectors.py` re-derives every harness constant by name. NIP-44 is COMPLETE against a current SodiumXT since 2026-08-23 (`sxChaCha20IetfXor` shipped as ABI 10; the full encrypt/decrypt path sweeps the official vectors headlessly, and still fails closed, by design, on an installed SodiumXT older than ABI 10); wss:// TLS is now HALF measured — that live run was this suite's first `open secure socket` and it worked, but it met an ordinary public host, so whether a bad certificate would be refused is unmeasured in both directions (`docs/OXT-ENGINE-NOTES.md` 6.8) |
| box2dxt | yes | **all 5 platforms** + `MANIFEST.sha256` (added in the fold) | The family ancestor, mature and feature-frozen upstream. The 2026-08-14 fold replaced its pre-unification checker with the suite's (first contact found ~1550 violations: mostly the pre-ASCII character set, plus 29 real `repeat with ... step` engine traps in the platformer, all fixed). **The folded `stSelfTest` was driven through FIVE real-engine runs over 2026-08-16/17 to clear its first-contact reds** (346/11 -> 348/9 -> 353/4 -> 365/4 -> 366/3): the engine corrected blind first-contact coverage tests with its own numbers and surfaced FOUR real Kit defects nothing headless could reach - sprite entry points throwing on an empty control ref (no-op guards across the whole sprite surface), event-buffer readers answering STALE controls after `b2kEventsReset` (count-guarded), the public filter wrappers silently no-opping (Box2D v3.1's uint64 default mask reads back as 2^64-1, above the shim's 2^53 guard, so the round-tripped `b2SetShapeFilter` call was refused whole - the clamp existed in the player's drop-through path all along and is now in all three wrappers), and - run 5's instrumented find - the player's duck reshape never physically shrinking the capsule (OXT does not resize a polygon graphic by a height-set, so the crawl wedged on the ceiling's face at full height while the halfH bookkeeping insisted the pill was short; `b2kReshape` now takes explicit dims and the duck/stand rebuilds pass the canonical capsule dims captured at attach). All three remaining reds traced to that one defect, and the next paste confirmed it: **374/374 at harness v29 on Windows x86_64 (NT 10.0, OXT 9.6.3), 2026-08-17** - fully green, folded into that day's suite pass (`docs/REMAINING-WORK.md`). The same v29 harness ran on **LINUX 2026-08-18 at 373/374**; the single red was the harness's own assertion that `the playLoudness` reads back exactly what was written, which is the HARNESS being wrong about the engine rather than the Kit being broken (`docs/OXT-ENGINE-NOTES.md` 5.4), and it is now two self-diagnosing assertions plus a printed observation. That makes the harness **v30, which carries 375 assertions where v29 had 374, so a v30 total is not comparable to a v29 one - and no v30 total has been observed on either platform yet.** The games and the raw `b2*` layer still owe their own re-pass |
| coinxt | yes (source + `native/build.sh`; ASan self-test + KATs green) | Linux x64/x86, Windows x64/x86 (**macOS build pending**) + `MANIFEST.sha256` | **All five phases engine-proven.** Phase 1 closed 2026-08-08; **phases 2, 3 and 4 closed 2026-08-10** — the member harness ran folded into the suite selftest at 205/206, and the one red line was a real parser fail-open (`cxHdDerivePath` of `"m/"`), fixed, re-modelled in the headless interpreter, and confirmed at **207/207** the same day. The headless gates still cross-verify on every push: RFC 6979 vectors, an independent `ecdsa` library, and `check-script-vectors.py` driving the real `.livecodescript` down BIP-44/BIP-84/Ethereum paths to their published addresses. **Phase 5 (transactions) is ENGINE-PASSED (2026-08-12, Windows x64, 230/230)**: Bitcoin legacy + BIP-143 SegWit and Ethereum EIP-155 + EIP-1559, model-verified against the BIP-143/EIP-155 published examples, driven through the real `.livecodescript` by `check-script-vectors.py` (251 checks) — which caught and fixed a would-be-red engine defect (`cxBtcTxEncode` refused the reference tx over a trailing-empty scriptSig) — and then confirmed on a real engine, the BIP-143 signed tx byte for byte. The independent-decoder bar is met (2026-08-12, extended 2026-08-13 to all four tx families: python-bitcointx accepts fresh legacy + segwit spends under consensus rules, eth-account recovers the exact sender from fresh EIP-155 + EIP-1559 txs); a live testnet broadcast is the one bar left before "broadcastable" **ABI 6 (2026-08-16)** adds BIP-340 Schnorr and the BIP-341 tweak on a second vendored library (upstream bitcoin-core/secp256k1, hash-verified against its pin); the new surface **ran green on a real engine 2026-08-16**, hours after it shipped - all 19 BIP-340 vectors and all 14 BIP-341 wallet vectors through the binding, on the day's first paste. The Windows DLLs still carry static checks only until the next release dispatch |

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
broadly open: **macOS binaries** for the native members (box2dxt, folded home
2026-08-14, is the one already shipping all five platforms), and the
**live-Tor and remaining two-machine work** — riptide's feed propagation
closed 2026-08-13 and its media + both-ways DMs on 2026-08-15, so what is
left is the phase-5 call, the LAN mesh, and the anon persona
(`riptide/docs/two-machine-runbook.md`), which no single-machine offline
paste can reach.

The 2026-08-12 re-run then exercised all seven folded harnesses at their current
sizes — **617 member-harness checks, zero failures** (SodiumXT 71, OnionXT 43,
CoinXT 230, TorrentXT 96, ENetXT 21, DataChannelXT 23, Riptide 133). In
particular, Riptide's phase-2 live feed layer passed its canonical BEP44 buffer,
real-session publish/request, and synthetic ingest-verifier sections. This
closes the single-engine half of runbook item 10; cross-machine DHT propagation
remains part of item 6.

**SUPERSEDED 2026-08-20 - the record is now a WHOLE-RUN one.** A Windows pass
that day finished the suite paste end to end: **1,981 passed, 0 failed, 1
skipped, 1,982 total**, of which **1,868 are folded member checks** (sodiumxt
99, onionxt 61, coinxt 278, torrentxt 101, enetxt 34, datachannelxt 39, box2dxt
375, riptide 338, holde-em 543). Two things make it a different KIND of result
rather than a bigger number. It reached the end: both live loopbacks negotiated
and delivered, the 60000-byte budget was checked on both transports, SCTP
cleared its 16 KiB floor, and teardown released the ENet hosts, the WebRTC peers
and THE libtorrent session. And it settled runbook row 13 - riptide's phase-6
LAN sync records, the phase-7 serving seams, and all three `rsBytesAreUtf8`
checks that were RED on 2026-08-15. The `1 skipped` is not a miscount: riptide's
2 and holde-em's 5 are printed on a second line their own harnesses word as
prose, which `stMergeReturned` deliberately refuses to parse (its comment says
why); onionxt's 1 is inline and merges. The 2026-08-17 record below is kept
verbatim as the dated account of the fold's first compile.

**The 2026-08-17 pass is the largest green run this project has had.** Windows
x86_64, NT 10.0, OXT 9.6.3: **1,836 folded member checks, zero failures, 7
skips** - every skip a live-transport or daemon leg no single machine can run.
Per member: holde-em 538, box2dxt 374, riptide 338, coinxt 278, torrentxt 101,
sodiumxt 99, onionxt 61, datachannelxt 26, enetxt 21. All six packaged
extensions loaded at exactly the ABI their guard expects, and it is the first
run in which every one of the NINE folded harnesses was green at once - roughly
threefold the 617-check run recorded above. `docs/REMAINING-WORK.md` and
`docs/OXT-PASS-RUNBOOK.md` carry that record and what it closed; nothing here
re-derives it.

**The 2026-08-18 pass was the folded harness's first run on LINUX, and it
carries no suite total** - none was recorded, and inventing one from a partial
observation is exactly what the honesty convention forbids. What the run
measured is one number and one lesson: box2dxt's harness came back **373/374,
the run's only failure**, and the red was the HARNESS being wrong rather than
the Kit being broken - exact readback was never `b2kSoundVolume`'s contract, so
the check is now two self-diagnosing probes plus a printed observation
(`docs/OXT-ENGINE-NOTES.md` 5.4). That rewrite makes it harness v30, one
assertion more than the v29 that produced the 374. **v30 has since been observed
on Windows - 375/0 on 2026-08-20**, with the rewritten check reporting
`Win32: 24->24, 73->73` and an exact readback; **Linux, the platform that
failed, has not run v30 yet.** The session's other engine findings - the
`keys of X` parse and the event/handler namespace collision, both OBSERVED, and
the defaultStack trap under a timer, filed OBSERVED and **reclassed DOCUMENTED**
on 2026-08-19 when its throw was traced to the `keys of X` spelling instead -
are written up in the same file, each marked OBSERVED, INFERRED, DOCUMENTED or
UNEVIDENCED so a reader can tell measurement from reasoning.

**The honesty convention, suite-wide.** OXT is a GUI runtime — there is no
headless way to compile or run `.lcb` / `.livecodescript`. Anything not observed
on a real engine is labelled **"verified statically; needs an OXT pass"** (Tor
paths: "+ live-Tor pass"). No member claims a runtime behaviour it has not
measured. `docs/OXT-PASS-RUNBOOK.md` is the runbook for closing that gap: what is
still unproven and where each label lives, the install order, the run order, and
what to record. The convention cuts both ways — a label is removed only for what
a run actually exercised, so each recorded suite-harness pass (2026-08-08,
2026-08-10, 2026-08-12, 2026-08-17, 2026-08-18, 2026-08-20) promoted the
handlers it called and left the ones it did not still labelled, member by
member — and both async-loopback halves have since closed the same way (enet
with the 2026-08-13 standalone pass, datachannel with the 2026-08-15 one),
leaving no member-selftest label standing.

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
two `src/*.livecodescript` libraries into your app (`start using`), or just open
`onionxt/examples/onionxt-demo.livecodescript`, which carries them (see
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
put nxVersion()          -- nostrxt, e.g. "NostrXT 0.1.0" (start using stack "nostrxt" first)
```

Or run all eight suite members plus both app layers - Riptide and holde-em - at once.
`tests/suite-selftest.livecodescript` is a single stack script that builds its
own UI, probes for every member, and reports PASS / FAIL / SKIP in one list — a
member you did not install skips, it never fails.

It is not a sampler. It carries **every member's own deep self-test**, folded in
whole: sodiumxt's `sxSelfTest` (23 groups since the ABI-10 ChaCha20 section
landed 2026-08-23), onionxt's `oxSelfTest` (10 groups, all
offline), coinxt's sections (encodings, addresses, HD, and the phase-5
transaction KATs), torrentxt's full harness, the synchronous halves of enetxt
and datachannelxt, nostrxt's 17-section `nxSelfTest` (canonical serialization,
NIP-19, the complete NIP-44 construction, websocket framing math - folded in
2026-08-23, nothing in it engine-observed yet), box2dxt's `stSelfTest` (51 handlers, 377 `stAssert` call sites of which 375 run, at
harness v30 driving the real b2k Kit hand-stepped one fixed 1/60 tick at a
time; v29's 374 ran green on Windows x86_64 on 2026-08-17, and v30 has since
been observed once - 375/0 on Windows, 2026-08-20; Linux, the platform whose
373/374 prompted the v30 rewrite, has not run v30 yet), riptide's
harness (phases 1-4 + 6 + 7, including the live feed, media, DM, LAN-admission,
and anon-persona layers), and — since 2026-08-16 — holde-em's `heSelfTest` (21
sections over the evaluator, the betting engine and side pots, the whole deal
ladder up to the Level 2 ristretto mental poker and its DLEQ audit, the signed
transcript wire, and three-context netplay, oracle and liveness loopbacks) —
plus the cross-member compositions no per-member harness can have. One paste
settles what used to take nine runs.

holde-em is the one fold that carries a whole APPLICATION rather than a test
file, because its game and its harness are the same 15k-line stack; it rides in
prefixed, entered only through its quiet returned-report entry point, and the
structural gate proves by REACHABILITY that its live paths — a second
libtorrent session, its own 1024x640 table, its report overlay, a b2k world —
stay out of the harness's reach.

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
**830 of 844 public handlers**:

| sodiumxt | onionxt | coinxt | torrentxt | enetxt | datachannelxt | riptide | nostrxt | box2dxt (Kit) |
|---|---|---|---|---|---|---|---|---|
| 73/73 | 31/45 | 90/90 | 85/85 | 23/23 | 31/31 | 83/83 | 101/101 | 313/313 |

The fourteen it does not reach are all onionxt's, and each carries a written
per-handler reason in that tool: **engine socket callbacks and watchdogs** (the
engine supplies a socket id, or a live connection arms the timer, that no
harness can mint) and the legs that need a **live tor daemon**. The gate
fails both on a new public handler that nothing exercises and on a stale excuse
left behind by a rename, so the shortfall can only ever be a decision somebody
wrote down. It counts handlers *reached*, not handlers tested well — depth is
each member's own vector gate.

Two layers are deliberately outside that ratchet, and each says so beside the
tool's member list with the numbers behind the call:

- **box2dxt's raw `b2*` extension binding** — 376 public handlers over 373
  foreign declarations (370 of them binding into the member's own library; the
  "374" quoted here until 2026-08-17 was a `grep -c` that counted one line of
  prose), of which **245 are named by no script anywhere in that member** by
  the gate's counting convention (comments stripped, string literals blanked;
  counting raw tokens instead finds one more name in a comment or literal,
  which is the 244 this line used to give - both numbers are real, the
  convention decides). The b2k Kit above it is the game-facing API and is held
  at 313/313.
  The raw layer's cover is `box2dxt/tests/smoke_test.c`, and since 2026-08-17
  that cover is *measured* rather than asserted: gcov puts it at **194 of the
  370 LC_API exports**, up from 53 the same morning, running in `build-all.sh`
  and under ASan/UBSan in `native-box2dxt.yml`. `check-lcb-signatures.py` holds
  the 370 binds against the 370 definitions on every push.
- **holde-em's `he*` surface** — **measured 2026-08-19.** It is 381 public
  handlers in ONE file that is the game *and* its harness — **330 game + 51
  harness**; the 379 quoted before the gate existed, and the 380 measured on
  2026-08-17, are both superseded by one handler (`heAwardedPot`, added by the
  uncalled-bet fix that same evening). The gate splits the file at its selftest
  boundary and asks its question across the cut, which is the same move as the
  embedded-span cut done with a boundary line instead of a sentinel: **121 of
  330 game handlers are exercised** — 120 named by a body reachable from
  `heSelfTest`, plus one dispatched by name through `heRunSection` that the
  literal-blanking cannot see — and **209 are named by nothing that runs** (20
  live-transport, 9 engine-media, 41 host-window, 139 simply untested). The row
  is ADVISORY — it prints the number without failing the build — but everything
  that would make that number a lie IS enforced, including a denominator floor
  that catches a comment-parse fault which otherwise turned the row green at
  66/260. Seven KAT mirrors plus an independent-reference fuzz still back the
  layer; they are no longer the only thing that does.

Both are open items, not closed ones.

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
  social app on the suite, and `riptide/` is that app: **all seven phases
  built; phases 1-4 DONE on two machines.** Phases 1-2 (identity + the live
  feed) engine-passed 2026-08-12, propagation met 2026-08-13 — the suite's
  first two-machine result. **Phase 3 (media) met 2026-08-15**: a follower
  on a second machine fetched and played an attached video, which
  necessarily walked head publish → head fetch → chain walk → authorSig
  verify → media info-hash → swarm join → playback. **Phase 4 (DMs — signed
  kx prekeys in the feed head, sealed intros over inbox phantom swarms,
  pairwise secretstreams over rp1, crypto_kx anchored against a real
  libsodium) met the same day**: two machines chatted both ways with no
  server. Phases 5-7 are BUILT and statically verified, their live passes
  pending: the dc call (signalled over the encrypted DM rail), the LAN mesh
  (your own devices prove a shared master with a three-leg mutual
  handshake), and the anon persona (an onion-only identity behind
  `rsPersonaAllows`, the pure-policy guard whose full truth table the
  harness asserts). On 2026-08-15 the suite selftest ran on a real engine
  and the whole phase 4-7 **compute** surface came back green (the kx
  session agreement, the DM secretstream round trip, the LAN admit/refuse,
  the anon guard, BTXO framing), so those paths are engine-verified;
  `riptide/docs/two-machine-runbook.md` scripts what the two boxes still
  owe.
  `docs/NEXT-EXTENSIONS-PLAN.md` is the roadmap that produced the members;
  `docs/ONIONXT-INTEGRATION-PLAN.md` is the anonymity-transport
  integration.
- **The open social wire.** nostrxt speaks a PUBLIC protocol rather than a
  suite-internal one: the same coinxt BIP-340 key that signs a Bitcoin
  Taproot spend signs a Nostr event, sodiumxt supplies the randomness and
  (since ABI 10) the NIP-44 cipher, and the relay client rides the same
  engine-socket idioms onionxt proved — so an xTalk app can talk to the
  existing Nostr relay ecosystem, not only to other suite apps. The planned
  composition hedge runs it the other way: a `.onion` relay over onionxt's
  transport needs no TLS at all.
- **The game stack.** box2dxt's b2k Kit is a working game engine (physics,
  sprites, input, camera - the platformer and contraption-builder examples
  are complete games), and enetxt is game-grade networking; together they
  are the suite's multiplayer-game story. The worked PROOF of it is
  [`holde-em/`](holde-em/): serverless online Texas Hold'em - players meet
  over the torrentxt DHT, every action lives in a signed hash-chained
  transcript, and the deal ladder tops out at a mental-poker shuffle.
  Riptide's sibling capstone, folded home from its standalone repository
  2026-08-15 at v0.18.0 and built out headlessly to v0.23.0 the following
  day: the hotseat game, the full Phase 2 online layer (checkpoints,
  show/muck, host election, act timers/time-bank/sit-out/late-join), onion
  tables, the Phase 3 deck oracle, the Level 2 mental-poker layer on
  sodiumxt's ristretto255 surface with its void-and-audit machine and
  DLEQ proofs — all machine-pinned (evaluator exhaustively verified,
  settlement fuzzed, seven KAT mirrors + an independent-reference fuzz in
  the gate set, 114 protocol pins). The live multi-machine passes are the
  open exit gates; nothing plays on Level 2 until the engine-era wiring
  lands.
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
  record registries, the known-answer harnesses, the carried-copy freshness
  gates that replaced the retired generated-standalone check
  (`tools/sync-demo-embeds.py --check` plus its `tools/test-demo-embeds.py
  --mutate` fixtures, so every demo carries a CURRENT copy of the libraries it
  pastes with, and box2dxt's `tools/sync-embedded-kit.py --check` for the same
  shape one level down), the launcher registry
  (`tools/check-launcher-registry.py`, so start-here cannot point at a stack
  that moved), the script-to-script and script-to-`.lcb` call gates
  (`check-handler-calls.py` / `test-handler-calls.py` and
  `check-lcb-call-types.py` / `test-lcb-call-types.py --mutate`),
  `tools/check-timer-stack-pin.py`, the `MANIFEST.sha256` integrity checks, and
  the suite-level carried-block and budget gates (the UI-kit, harness-scaffold
  and demo-self-check drift gates — one look, one scaffold, byte-identical
  everywhere, adoption enforced — plus the 720p
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
  (`workflow_dispatch`). One dispatch builds five of the six members that ship
  committed binaries, for every platform it
  can be built for (20 build jobs: five members x four platforms) - **box2dxt is
  absent from that workflow with no recorded reason, so its committed libraries
  have no dispatch that refreshes them**, asserts each artifact, runs coinxt's
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
  the decision is pressing "Run workflow". Since 2026-08-23 it carries **macOS lanes for all six members** (single-pass universal builds for sodiumxt, coinxt, enetxt, box2dxt; a two-slice-lipo job for torrentxt and datachannelxt, whose OpenSSL-bearing stacks cannot single-pass), building genuinely UNIVERSAL dylibs - both slices cross-compiled in one pass, `lipo -archs` asserted at birth, arm64 tested natively and x86_64 under Rosetta 2, unsigned in the distribution sense (the linker's ad-hoc signature; no notarization anywhere). No mac lane has produced a committed binary yet - the first dispatch is what proves them. The trap that kept macOS out until then: `macos-15` runners are arm64-only, so they
  would emit a thin dylib into `universal-mac` and overwrite sodiumxt's genuine
  two-architecture binary with one that fails on every Intel Mac - which is why
  the installer refuses a thin Mach-O AND a fat container missing a slice, so
  neither a regressed lane nor a hand-built bundle can make that mistake. A
  manual `lipo` build remains equivalent; codesign + notarize exists nowhere
  yet (credentials CI does not hold; unsigned distribution accepted
  2026-08-23).

See `CLAUDE.md` for the suite-level workflow and `docs/README.md` for the
cross-cutting documents.

## License

The suite and every member are **MIT** (see `LICENSE`, which also lists each
member's bundled third-party library and its license — libtorrent (BSD-3) +
Boost, libsodium (ISC), ENet (MIT), libdatachannel (MPL-2.0) + usrsctp (BSD-3),
trezor-crypto + bitcoin-core/libsecp256k1 (both MIT), Box2D v3 (MIT)). OnionXT
and NostrXT ship no third-party code — OnionXT talks to a Tor daemon you run,
and NostrXT is pure script over its sibling extensions.
