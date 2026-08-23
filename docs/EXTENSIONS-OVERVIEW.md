# Extensions overview — what each member enables

One section per suite member: what it is, what it gives an xTalk app, and
where it honestly stands. Compiled 2026-08-15 from each member's own
`README.md` / `CLAUDE.md`, which remain the authority; the root `README.md`
carries the full release matrix. Handler counts are counted from the
sources, not estimated. The three applications (riptide, nocloud,
holde-em) close the page: they are members of the tree and ride the same
gates, but they are apps built *on* the extensions, not extensions.

Suite-wide facts that apply to every section below: each native member
bundles its per-platform library inside the extension (nothing to install
separately); inbound events are **poll-drained** on a timer (no callback
ever runs script); exceptions never cross the FFI; handles are
generation-tagged so a stale one is a no-op, never a crash; and anything
not observed on a real engine is labelled "verified statically; needs an
OXT pass". The generated `tests/suite-selftest.livecodescript` reaches
724 of the 742 coverage-counted public handlers (the 18 unreached are all
onionxt's, each with a written reason: engine socket callbacks and
live-daemon paths). Two script layers ride outside that ratchet and are
reported separately: holde-em's `he*` surface, an advisory row at 121/330
that prints but does not fail the build, and box2dxt's raw `b2*` `.lcb`
binding, which is not coverage-counted at all. Every figure in this
paragraph re-measured 2026-08-19 by `tools/check-suite-coverage.py`.

## sodiumxt — modern cryptography (`sx*`)

Wraps **libsodium** (1.0.20; the Windows builds carry 1.0.22). 72 public
handlers. Binaries committed for **all five platforms** (Linux and Windows
x64/x86 at ABI 9: ABI 8 added the ristretto255 group surface 2026-08-15 and
ABI 9, the same day, its DLEQ/batch follow-ons;
`universal-mac` three ABIs behind, pending the manual `lipo` build).

- **Secret-key authenticated encryption** — XChaCha20-Poly1305, with or
  without associated data: `sxSecretBox`, `sxAeadEncrypt`.
- **Public-key boxes and sealed boxes** (X25519) — encrypt to a
  recipient, anonymously if sealed: `sxBox`, `sxSeal` / `sxSealOpen`.
- **ed25519 signatures** — `sxSignDetached` / `sxSignVerifyDetached`,
  plus `sxSignSeedToExpandedKey`, the Tor-v3-onion key form that lets one
  seed be both a signing identity and an onion address.
- **Password hashing and key derivation** — Argon2id (`sxPwHash`,
  `sxPwHashStrVerify`) and labelled subkeys (`sxKdfDerive`).
- **Streaming AEAD and whole-file crypto** — `sxSecretStreamInitPush` et
  al., `sxEncryptFile` / `sxDecryptFile` (file bytes never enter script).
- **Hashing** — BLAKE2b one-shot / keyed / multipart / file (`sxHash`,
  `sxHashFile`), plus `sxHmacSha256` and `sxSha3_256` (FIPS 202).
- **The ristretto255 group** (ABI 8, holde-em Workstream U) — hash-to-group,
  scalar multiplication, scalar random/invert, point validity for the
  mental-poker deal: `sxRistrettoFromHash`, `sxRistrettoScalarMultPoint`,
  `sxRistrettoScalarRandom`, `sxRistrettoScalarInvert`,
  `sxRistrettoPointValid` — plus the ABI-9 DLEQ/batch follow-ons (the plan's
  recorded Phase 5 surface, shipped 2026-08-15): `sxRistrettoAdd`,
  `sxRistrettoSub`, `sxRistrettoScalarMultBase`,
  `sxRistrettoScalarMultBatch` (52 points, one FFI crossing, atomic on
  failure with the failing index named), `sxRistrettoScalarAdd`,
  `sxRistrettoScalarMul`. Verified statically (cross-checked KATs); needs
  an OXT pass.
- **Key exchange** — `crypto_kx` client/server session keys
  (`sxKeyExchangeClient` / `sxKeyExchangeServer`).
- **Utilities** — CSPRNG (`sxRandomBytes`), constant-time compare
  (`sxMemEqual`), hex/Base64, padding.
- Design: this is the one member whose **payload deliberately crosses the
  FFI** — that is its job. Nonces are never caller-supplied.
- Status: the most complete member; the 71-check `sxSelfTest()` ran green
  on-engine 2026-08-12.

## torrentxt — the full BitTorrent protocol (`bt*`)

Wraps **libtorrent-rasterbar 2.0.11** (+ Boost), statically linked. 85
public handlers, ABI v11. Binaries: Linux + Windows x64/x86 (macOS needs
a manual universal, codesigned build).

- **Download and seed anything, v1 + v2** — magnets, `.torrent` files,
  bare info-hashes, resume data; create-and-seed your own:
  `btAddMagnet`, `btCreateTorrent`, `btSaveResumeData`.
- **DHT (BEP 5)** — trackerless peer discovery: `btDhtAddBootstrap`,
  `btDhtGetPeers`, announce.
- **BEP44 DHT key-value store** — ed25519-signed mutable items and
  content-addressed immutable items, the suite's serverless rendezvous
  and identity layer: `btDhtPutSigned`, `btDhtPutMutable`.
- **The rp1 peer-wire transport** — a BEP10 extension moving opaque bytes
  peer-to-peer with no tracker, no server, and no torrent content:
  `btRp1Enable`, `btRp1Send` (riptide's DM rail).
- **Trackers, web seeds, PEX, uTP, NAT port mapping** — `btAddTracker`,
  `btAddWebSeed`, `btMapPort`.
- **Per-torrent control and tuning** — pause/resume, recheck, sequential
  and streaming modes with piece deadlines, file/piece priorities, rate
  and connection caps, queue positions, move-storage.
- **Inspection** — status snapshots, peer lists, file tables, piece
  availability: `btTorrentStatus`, `btPieceAvailability`.
- Design: **payload never crosses the FFI** — piece data moves engine to
  disk on libtorrent's threads; script issues commands and polls small
  typed records (`btPoll`). One session per process.
- Status: the 96-check member selftest ran green on-engine 2026-08-10;
  the transport has carried real two-machine traffic via riptide
  (2026-08-13/15); two-machine runs of its own rp1/DHT demos stay open.

## enetxt — game-grade reliable UDP (`en*`)

Wraps **ENet 1.3.18**, statically linked. 23 public handlers, ABI v2.
Binaries: Linux + Windows x64/x86 (no macOS yet).

- **Hosts and peers, not sockets** — server and client hosts, several per
  process: `enHostCreateServer`, `enHostCreateClient`, `enConnect`.
- **Three delivery modes per send** — reliable/ordered,
  unreliable-sequenced (droppable), and unsequenced — over up to **255
  independent channels**, so bulk reliable traffic cannot stall the
  real-time lane: `enSend`, `enSendText`.
- **One-call fanout** — queue a packet to every connected peer, the
  server-relay primitive: `enBroadcast`.
- **Live statistics in one round-trip** — state, RTT, packet loss,
  byte/packet counters: `enPeerStatus`, `enHostStatus`.
- **Tuning** — retransmission timeouts, ping cadence, live bandwidth
  caps: `enSetPeerTimeout`, `enSetHostBandwidth`.
- **Connection lifecycle** — polite, abrupt, or silent teardown, plus a
  u32 connect-data word (protocol version, room id) the far side reads.
- Design: **"pump or nothing"** — ENet is threadless; everything
  progresses inside `enPoll`, so the family's no-foreign-thread rule is
  true by construction. Packets share the suite's 60000-byte budget.
- Status: everything in its selftest is engine-passed (the async loopback
  with live host/peer statistics closed 2026-08-13); only the two-machine
  LAN chat demo remains unexercised.

## datachannelxt — WebRTC data channels (`dc*`)

Wraps **libdatachannel 0.24.5** (with vendored libjuice for ICE and
usrsctp for SCTP; DTLS via system OpenSSL). 31 public handlers.
Binaries: Linux + Windows x64/x86 (no macOS yet).

- **Peer connections with real NAT traversal** — ICE/STUN/TURN punches
  through two home NATs with no router config: `dcCreatePeer`,
  `dcSelectedCandidatePair`.
- **Browser interoperability** — a channel opened here is a standard
  WebRTC data channel; the far side can be a few lines of JavaScript.
- **Signaling primitives** (the signaling channel itself is the app's
  job — riptide uses DMs, the demo uses the DHT): `dcLocalDescription`,
  `dcSetRemoteDescription`, `dcAddRemoteCandidate`, trickle or one-blob.
- **Per-channel reliability** — reliable+ordered by default; unordered;
  unreliable by max-retransmits or max-lifetime; negotiated channels on
  fixed stream ids: `dcCreateChannel`, `dcCreateChannelEx`.
- **Text and binary messages** — strings and bytes round-trip to browser
  `string` / `ArrayBuffer`: `dcSendText`, `dcSendData`.
- **Backpressure** — send to the high-water mark, resume on the
  buffered-low event: `dcBufferedAmount`, `dcSetBufferedLowThreshold`.
- **Introspection** — channel label/protocol/stream id/max message, peer
  and gathering states, poll-drained events (11 kinds): `dcPoll`.
- Design: the family's one binding with true cross-thread callbacks —
  every callback only locks, copies into a bounded queue, unlocks;
  `dcPoll` drains on the script thread. A ThreadSanitizer CI lane
  polices exactly that.
- Status: the standalone async loopback ran green 2026-08-15 (real SDP,
  correct roles, selected candidate pair, byte-for-byte text and binary),
  so nothing in its selftest is static; open: a real browser peer and a
  call across two networks.

## onionxt — Tor transport, pure script (`ox*` / `oxh*`)

**Pure LiveCodeScript** — no native code, no packaged extension, no
bundled third-party code. Speaks SOCKS5 and the Tor control protocol over
engine sockets to a **local tor daemon** (loopback only). 45 public `ox*`
handlers plus the 11-handler `oxh*` HTTP layer. Installed by copying two
script libraries (`onionxt/src/onionxt.livecodescript` and
`onionxt/src/onion-httpd.livecodescript`) into the message path. The two
FULL demos - `onionxt/examples/onionxt-demo.livecodescript` and
`onionxt/examples/onion-httpd/spike.livecodescript` - instead CARRY those
libraries, embedded between the sentinels `tools/sync-demo-embeds.py`
owns, so each is one paste with no `start using` step; the `socks-dial`
and `onion-roundtrip` snippets are glue and still expect the library in
the message path (2026-08-18: the standalone GENERATOR and both of its
generated twins were deleted, so there is no longer a standalone to
look for).

- **Anonymous TCP streams** — dial any host through Tor; names resolve
  inside Tor, never via local DNS: `oxDial`, `oxWrite`,
  `oxSetStreamCallback`.
- **v3 onion services** — serverless, self-authenticating inbound
  connections: `oxCreateService`, `oxServiceAddress`,
  `oxSetPeerCallback`.
- **Deterministic onions from a seed** — the same seed always yields the
  same `.onion` (composes sodiumxt's expanded-key form):
  `oxCreateServiceFromSeed`.
- **Publish-only mode** — put a virtual port on the Tor network while an
  external local server owns the listener: `oxPublishService`.
- **Control-port bootstrap** — PROTOCOLINFO with SAFECOOKIE (and three
  fallback auth methods), bootstrap progress, readiness probes:
  `oxConnectControl`, `oxIsReady`.
- **Offline address tools** — encode/decode/validate v3 addresses with
  no daemon at all: `oxAddressFromPublicKey`, `oxIsValidAddress`.
- **HTTP-over-onion hosting (`oxh*`)** — serve a site, a browsable
  folder share, or app-defined routes on an onion: `oxhServe`,
  `oxhServeFiles`, `oxhRoute`.
- **Capability probing** — `oxTransportInfo()` flags what this
  environment can do so callers degrade visibly, not silently.
- Design: adds **no cryptography of its own** — every hash and signature
  is a sodiumxt call. Mode A (attach to a running tor) is the tested
  base; Mode B (launch a bundled tor) exists but is unexercised.
- Status: proven against a live daemon (dial, SAFECOOKIE auth, publish,
  and serving a page a real Tor Browser rendered); the 43-check
  `oxSelfTest()` ran green on-engine 2026-08-12. Mode B is the one
  `VERIFY:`-flagged path.

## box2dxt — 2D physics + the b2k game Kit (`b2*` / `b2k*`)

The family **ancestor**, folded home 2026-08-14. Wraps **Box2D v3.1.0**.
376 public `b2*` handlers (metres/radians) plus a **313-handler
pure-script Kit** (`b2k*`, pixels/degrees). Binaries committed for **all
five platforms**. Ships as `org.openxtalk.box2dxt` (predates the
`library.*` naming; installed on users' machines, so it stays).

- **Worlds and stepping** — gravity, sleeping, CCD, threaded worlds:
  `b2NewWorld`, `b2Step`.
- **Rigid bodies** — dynamic/static, forces and impulses, transforms,
  velocities, damping, bullet flag: `b2NewDynamicBody`,
  `b2ApplyImpulse`.
- **Shapes** — box, circle, capsule, segment, incremental convex
  polygons (up to 8 points), chains for one-sided terrain.
- **Joints and motors** — revolute, distance (spring), weld, prismatic,
  wheel (suspension/drive), mouse — each with limits and motors:
  `b2RevoluteEnableMotor`, `b2WheelEnableSpring`.
- **Queries and events** — ray casts, click-picking, sensors as trigger
  zones, per-step contact begin/end snapshots, named collision layers:
  `b2CastRayClosest`, `b2BodyAtPoint`, `b2ContactsUpdate`.
- **The b2k Kit: a working game engine in script** — control-backed
  bodies with a render loop (`b2kQuickStart`, `b2kSpawnBox`), keyboard
  input, sprites and animation, a full **player controller** (run,
  double-jump, wall-jump, dash, duck, climb, swim, drop-through), a
  scrolling camera, and synthesized sound.
- Examples are **complete games**: a seven-level platformer, a
  contraption-builder sandbox, a slingshot tower-knockdown, and a
  six-scene physics demo.
- Status: mature and feature-frozen upstream; the fold's checker sweep
  touched nearly every script (~1550 findings, including 29 real
  `repeat with … step` engine traps), so the whole member is currently
  **verified statically; needs an OXT re-pass**. Pairs with enetxt as
  the suite's multiplayer-game story.

## coinxt — Bitcoin + Ethereum primitives (`cx*`)

Wraps **trezor-crypto** (pinned; plain C, no external deps) plus
**bitcoin-core/secp256k1** (vendored 2026-08-16 for BIP-340). 90 public
handlers, ABI 6. Binaries: Linux + Windows x64/x86 (macOS pending).

- **The hash surface both chains need** — Keccak-256 (Ethereum) vs
  SHA3-256 (NIST), SHA-256/512, RIPEMD-160, `cxHash160` / `cxHash256`,
  HMAC, PBKDF2.
- **secp256k1** — deterministic ECDSA (RFC 6979), recoverable
  signatures and `ecrecover`, ECDH: `cxSign`, `cxVerify`, `cxRecover`.
- **HD wallets** — BIP-39 mnemonics (`cxMnemonicFromEntropy`,
  `cxMnemonicToSeed`), BIP-32/BIP-44 derivation (`cxHdDerivePath`),
  watch-only `cxHdNeuter`, `cxXprv` / `cxXpub`.
- **Encodings** — hex, Base58Check, Bech32/Bech32m, RLP:
  `cxBase58CheckEncode`, `cxBech32EncodeValues`, `cxRlpEncodeBytes`.
- **Addresses** — P2PKH, P2WPKH, P2TR, Ethereum with EIP-55 checksums.
- **Transactions** — Bitcoin legacy + BIP-143 SegWit sighash / encode /
  txid (`cxBtcSighashSegwit`, `cxBtcTxEncode`); Ethereum EIP-155 and
  EIP-1559 (`cxEth1559Sighash`, `cxEth1559Encode`).
- **Schnorr / Taproot** — BIP-340 sign/verify and the BIP-341 output-key
  tweak, shipped 2026-08-16 at ABI 6 against all 19 published BIP-340
  vectors (10 negative) and all 14 BIP-341 wallet vectors.
  `cxBtcAddressP2TR` is deliberately UNCHANGED and still encodes a key it
  is given: making it tweak would turn every existing correct call into a
  permanently unspendable double tweak, so the full path is a separately
  named handler. There is **no BIP-341 sighash builder** — coinxt signs a
  sighash it is handed and cannot compute one.
- **WIF** — `cxWifEncode` / `cxWifDecode`, shipped 2026-08-15.
- Design: signs only a digest the app hands it — never a blind signer;
  the app owns custody. Secrets are wiped before free (`cnx_memzero`,
  ABI 5).
- Status: **all five phases engine-proven** (230/230 on 2026-08-12),
  cross-verified by independent decoders (python-bitcointx accepts fresh
  spends under consensus rules; eth-account recovers the exact sender).
  Everything added since that run — WIF, `cnx_memzero`, Schnorr/Taproot —
  **ran green on 2026-08-17** (Windows x86_64, OXT 9.6.3), taking coinxt to
  278/278 on a real engine. The one bar left before "broadcastable": a live
  testnet broadcast.

## nostrxt — the Nostr protocol, pure script (`nx*` / `nxr*`)

**Pure LiveCodeScript over composed siblings** — no native code and no
bundled third-party code; the crypto is CoinXT (`cxSha256`, BIP-340
`cxSchnorrSign`/`cxSchnorrVerify`, `cxXOnlyPubkey`, `cxEcdh`,
`cxHmacSha256` — the hard dependency for signing and ids) and SodiumXT
(`sxRandomBytes`, `sxMemEqual` — soft). Added 2026-08-23.

- **NIP-01 events**, with an OWNED canonical serializer (exactly the seven
  mandated escapes, other control bytes verbatim — the rule a stock JSON
  encoder breaks, producing wrong event ids), sha256 ids, BIP-340
  signatures, verify-then-trust (`nxEventVerify`), tags, filters, and both
  directions of the relay wire protocol with byte-exact message types.
- **NIP-19 entities** (`npub`/`nsec`/`note` and the TLV
  `nprofile`/`nevent`/`naddr`), on the member's own uncapped bech32 —
  NIP-19 waives BIP-173's 90-character limit, which coinxt's encoder
  enforces, so nostrxt carries its own and its KAT asserts the deviation
  on purpose. `nxUriEncode` refuses to wrap a secret key.
- **NIP-44 v2 payloads**: conversation key (unhashed ECDH x +
  HKDF-extract), message keys (HKDF-expand), the power-of-two padding and
  the MAC-before-cipher order are all built and vector-pinned today;
  encrypt/decrypt fail CLOSED behind the one missing upstream primitive
  (SodiumXT `sxChaCha20IetfXor`, the standing entry in
  `tools/check-handler-calls.py`'s KNOWN_MISSING and
  `nostrxt/docs/07-capabilities-required.md`).
- **A websocket relay client** (`nxr*`, a second file so the suite paste
  never carries a second `socketError` definition): RFC 6455 in pure
  script over engine sockets, verification-on-by-default event delivery,
  NIP-42 auth, ping/pong, fail-closed framing caps. `ws://` mirrors
  onionxt's engine-proven socket idioms; `wss://` is written and labeled —
  nothing in this suite has ever opened a TLS socket.
- Also aboard: NIP-05 and NIP-11 parsing, NIP-13 proof-of-work checks,
  NIP-21 URIs, and builders for the core kinds (metadata, replies with
  NIP-10 markers, reactions, deletions, contacts, relay lists, auth).
- **Design**: a stateless pure-compute core (the riptide shape: no I/O,
  offline-testable, embedded in the suite paste) plus a stateful socket
  layer (the onionxt shape: handles, watchdogs, idempotent teardown).
- **Status**: verified statically; needs an OXT pass + a live-relay pass.
  Nothing has met an engine. What is machine-verified headlessly:
  `tools/nostr-kat.py` sweeps the complete published BIP-340 csv, the full
  official NIP-44 v2 vector set, the BIP-173 strings and the NIP-19
  examples through an independent oracle, and every constant the harness
  pins re-derives by name on every build.

## riptide — Riptide Social, the capstone app (`rs*`)

**An app, not an extension**: the serverless social network of
`docs/RIPTIDE-SOCIAL-SPEC.md`, built phase by phase in pure script over
the installed extensions (sodiumxt required; torrentxt, onionxt, enetxt,
datachannelxt, coinxt optional per feature). Library 0.7.0, 83 public
handlers, all 83 harness-exercised. It exists to prove the suite
composes; `rs*` never becomes a library other members call.

- **Phase 1 — identity**: one master seed, Argon2id-sealed key file, a
  KDF subkey tree; the ed25519 handle doubles as a `.onion` address.
- **Phase 2 — live feed**: signed heads and posts over BEP44
  (`btDhtPutSigned`); everything re-verified before the app believes a
  byte.
- **Phase 3 — media**: attachments as trackerless torrents, seeded in
  place, fetched and co-seeded by followers.
- **Phase 4 — DMs**: signed kx prekeys in the feed head, sealed intros,
  pairwise secretstreams over torrentxt's rp1 wire.
- **Phase 5 — calls**: datachannelxt channels, SDP signalled over the
  encrypted DM rail; STUN only by design.
- **Phase 6 — LAN mesh**: your own devices prove a shared master with a
  three-leg mutual handshake over enetxt.
- **Phase 7 — anon persona**: an onion-only identity behind
  `rsPersonaAllows`, the pure-policy deanonymization guard.
- Status: all seven phases **built**; phases 1–4 **done on two machines**
  (feed propagation 2026-08-13; media playback and both-ways DMs
  2026-08-15). The phase 4–7 compute surface is engine-verified
  (2026-08-15); the live phase 5–7 legs are scripted in
  `riptide/docs/two-machine-runbook.md`.

## nocloud — No Cloud Quick Share, the shipped app (`qs*`)

**A finished end-user app**, folded in 2026-08-13: peer-to-peer file
sharing with no server, no account, and no size limit — one stack script
plus a bundled static web app. torrentxt is required; sodiumxt and
onionxt are optional and probed at startup.

- **Share code** — plain BitTorrent over the DHT: the code *is* the
  content address, so the DHT introduces the machines with no tracker.
  Resumes interrupted transfers; recipient runs the app.
- **Web link** — a plain `http://` link any browser opens: a file, a
  browsable folder, or a whole static site, served by a built-in
  streaming HTTP server with automatic UPnP/NAT-PMP port mapping and
  Range support.
- **Private / Tor** — the bytes ride an onion stream instead; both IPs
  hidden; no torrent created.
- **Optional passphrase seal** — Argon2id + secretstream via sodiumxt:
  the network only sees ciphertext under a neutral name, and a wrong
  passphrase is caught before anything downloads.
- Design: **fail-closed capability probes** — each optional dependency
  is probed once into a guard boolean and never called outside it; a
  missing member disables exactly its feature with an install hint while
  everything else keeps working. Tor's bootstrap state is re-checked at
  the moment of use, never trusted from cache.
- Honest limits, written down: "no cloud" is not "anonymous" and not
  "encrypted" (`nocloud/docs/what-it-hides.md`), and the sending window
  must stay open until the transfer finishes.
- Status: passed the suite's stricter checker clean on first contact;
  like every stack in the 2026-08-14 UI-kit pass, it is labelled
  "UI unified 2026-08-14; needs an OXT re-pass".

## holde-em — serverless Texas Hold'em, the second capstone app (`he*`)

**A whole application in one paste-and-run stack**, folded home
2026-08-15 and into the suite self-test 2026-08-16 as the ninth harness.
No accounts, no server: players meet over the BitTorrent DHT — the table
code *is* the invite — every action lives in a signed hash-chained
transcript, and the deal runs a security ladder topping out at a
**ristretto255 mental-poker shuffle**. torrentxt and sodiumxt are
required; box2dxt (card art via the b2k Kit) and onionxt (anonymous
tables) are optional and probed.

- **The deal ladder** — Level 0 (independent per-player seeds XORed) up
  through the Level 2 mental-poker layer: masked deck, void-and-audit
  attribution that names a cheater from signed records, and Phase 5 DLEQ
  proofs that refuse a wrong unmask step instantly.
- **The transcript is the authority** — settlement, history, and the
  audit verdicts are all re-derived from it, so a tampered settle is
  caught and marked rather than trusted.
- **Liveness** — street checkpoints, show/muck, host election, act
  timers with a per-hand time-bank, sit-out/return, late-join seating,
  and onion auto-redial. v0.24.0 was a correction pass over that layer:
  ten reviewed defects fixed with **no wire change at all**, so the 114
  protocol pins are untouched and v0.23.0 and v0.24.0 clients speak the
  identical protocol.
- Design: its **game and its harness are the same file**, which is why
  its fold is the only one that carries a whole application — and why
  `check-suite-selftest.py` check 7d holds the live game UNREACHABLE
  from the folded harness by reachability rather than by absence.
- Verification: seven KAT mirrors plus `tools/logic-fuzz.py`, an
  INDEPENDENT reference rather than a port, ride `build-all.sh`; the
  1024x640 layout is re-derived from the builders on every push by
  `tools/check-table-layout.py`.
- Status: v0.24.5. Five engine runs (2026-08-16/17) took it to 507/0 on
  the folded harness at stack v0.24.3 / harness v40; the harness has grown
  since (`kHeHarnessV` 40 -> 41, bumped by v0.24.4), so that total is not
  comparable to one taken today and none has been. The pending exit gates
  are all multi-machine: a multi-hand rp1 session on real networks, a
  two-machine onion table over live tor, a three-machine oracle round,
  and a timed liveness session. Phase 4f and Phase 5's hostile review +
  soak remain open.

## How they fit together

- **Identity once, transport by reachability** — one sodiumxt seed is a
  BEP44 key (torrentxt) *and* a v3 onion (onionxt): reaching you is
  verifying you.
- **The transport ladder** — enetxt for many peers at game cadence on a
  LAN; datachannelxt for NAT-traversed internet pairs; torrentxt for
  bulk and many-to-many; onionxt when the path itself must be private.
  The shared 60000-byte message budget is the seam: when a payload stops
  being a message, it becomes a torrent.
- **The game stack** — box2dxt's Kit plus enetxt's networking; the
  worked proof is `holde-em/` (serverless poker over the DHT, folded
  home 2026-08-15: hotseat + online play built, later phases open).
- **The proofs** — riptide composes five members into a social app;
  nocloud ships the ladder as a file-sharing product.
