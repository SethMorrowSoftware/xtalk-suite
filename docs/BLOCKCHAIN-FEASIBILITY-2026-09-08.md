# Blockchain feasibility for the xTalk suite

**SNAPSHOT, compiled 2026-09-08.** Correct on its compile date and decaying from
that day on. Nothing in this document has been built; it is research, and every
capacity figure in it is arithmetic from operation counts rather than a
measurement, because this project has never measured the workload a chain needs
(section 3, item 12).

The question asked: *what would it entail to create a blockchain from the
contents of this suite, OXT, and any other necessary wraps?*

Method: a ten-area survey of the tree, a ten-subsystem gap analysis, six
independently-authored candidate architectures, four judge lenses scoring all
six, and an adversarial verification pass over the six load-bearing claims.
Where the verification pass contradicts the survey, the verification wins and
the finding is marked **[CORRECTED]**. Claims that could not be resolved from
the tree are marked UNVERIFIED and are collected in section 6.

> **WHAT HAS CLOSED SINCE THIS WAS COMPILED (struck 2026-09-09).** A snapshot
> is only honest if it is struck as items close, and this one's own defect list
> was acted on immediately. **Every defect named in section 3 as a thing to fix
> has been fixed and pushed** (PR #132), so read those items as the REASONING
> behind a change rather than as open work:
>
> - **item 6 (no atomic write)** and **item 8 (no database)** stand unchanged.
> - **item 7, riptide's missing read-side watermark** - CLOSED. `rsIngestHead`
>   now requires a reader watermark and fails closed on an omitted one, and the
>   dead `headseq` write has a reader. The u64 bound that came with it exposed
>   two further defects this document did not know about: a partial sweep that
>   INVERTED riptide's BTXO 8 GiB ceiling, and thirteen call sites where the
>   report said ten.
> - **item 9, the unbounded rp1 queue** - CLOSED IN SOURCE, bounded with
>   datachannelxt's tail-drop policy. The committed binaries do not carry it
>   until a release dispatch runs (`REMAINING-WORK` C.0), and two more shim
>   leaks were found beside it (`enx_disconnect`, `cb_data_channel`).
> - **item 13, the BEP44 bencode overshoot** - CLOSED, and WIDER than recorded
>   here: the same off-by-the-bencoding was in riptide's own `kRsMaxRecord`,
>   not only in the shim. 1000 raw -> 996 in both layers.
> - **item 16, `lcs-interp.py`'s arbitrary-precision blind spot** - CLOSED. It
>   refuses past 2^53 now, and it earned its keep within a day by finding an
>   unbounded 8-byte accumulator in coinxt's shipped wallet.
>
> Three defects this document did not find were found afterwards by an
> adversarial sweep over the same tree and are also fixed: a signature-domain
> COLLISION on riptide's LAN rail (one tag was a strict prefix of another, so
> an admission signature was also a valid sync signature), `oxWrite` discarding
> every socket write result, and holde-em's wire signatures covering a PREFIX
> of a line the transcript chain hashed whole. **That this document's own
> survey missed all three is the most useful thing it says about its own
> reliability**, and section 7's "the measurement gap is the dominant risk"
> should be read next to it.

---

## 1. The bottom line

**Feasible, but only in forms that decline most of what a chain is for. And the
most valuable thing to build here is not a chain.**

The one sentence to carry out of this document:

> **This suite can already put arbitrary bytes into Bitcoin and have the network
> accept them, and it cannot verify that anything it reads back is actually in a
> chain.**

Both halves are verified. The producing side ran on a real network: a testnet
spend was built here and accepted, txid
`7978bdd2c097c929cae2ab00084d4454b68b1d054a3f2d53fc7b51b70551e4d5`, 2026-09-02
(`docs/OXT-PASS-RUNBOOK.md` item 16a; `coinxt/docs/wallet.md`), and a taproot
commit-and-reveal followed. The verifying side does not exist, and the wire
layer does not even ask for its inputs: a tree-wide grep across every
`.livecodescript`, `.lcb` and `.md` for `get_merkle`, `gettxoutproof`,
`getblockheader` and `merkleblock` returns **zero hits**. A wallet that has held
real coins takes "confirmed" on a stranger's word.

> **Scope of that sentence, stated precisely.** The wallet does verify *some*
> things it reads: it re-derives a txid from returned raw bytes, and libtorrent
> verifies the ed25519 signature on a BEP44 item before surfacing it. What is
> absent is any check that a transaction is *included in a block that a chain
> committed to*. That is the gap, and closing it is worth doing on its own
> merits whatever else is decided here.

Three further conclusions, in the order they should change a plan:

**(a) A permissionless chain built here is a demonstration, not a security
system.** Not primarily because of the runtime, though the runtime is hostile,
but because the security budget is zero and the attack economics are published.
85% of successful majority attacks between 2018 and 2024 hit chains under three
years old; MIT DCI puts entry cost at $1,500 to $5,000; the Ethereum Classic
attacker rented roughly $204,000 of hashpower to double-spend $5.6M in a
4,236-block reorg. "Nobody attacks a worthless chain" does not hold either: the
December 2019 Vertcoin attack removed 603 blocks to net about $29. Griefing
needs no market.

**(b) The runtime forbids the deployment shape a chain needs.**
`docs/OXT-PASS-RUNBOOK.md` section 1.1 answers "Reachable headless?" with a flat
**No** for every `.lcb` and every `.livecodescript`. Every app in this tree
builds its GUI in `openStack`. A validator here is a window somebody keeps open.
That kills always-on validation, mining continuity, and any witness, calendar or
sequencer role, and it means the most safety-critical code in the system would
be the least testable code in the tree.

**(c) The not-a-chain answers are unusually strong here, and two of them fix
defects that exist in shipped code today.** riptide's DHT feed rail has no
reader-side rollback protection (section 3, item 7). holde-em's settlement
receipt chain is correct and evaporates on quit. nocloud signs nothing of its
own. Three named consumers, three verified gaps, one small shared library closes
all of them.

**Recommendation: build Counterfoil and Rootline as one combined project**
(designs 6 and 4 in section 4): a signed, monotone, hash-linked record layer
with an atomic durable store, whose tree heads are merkle-aggregated and
anchored into Bitcoin, plus a checkpointed header verifier so a receipt this
suite issues can be checked by this suite. The recommended work itself needs no
native code and no ABI bump. Hold design 3's phase 1 (a stateless binding of
Bitcoin Core's script verifier) as a separately-justified option that pays for
itself on coinxt's CI alone.

---

## 2. What the suite already gives you

`[ENGINE]` means observed on a real OXT engine with a date in the tree.
`[STATIC]` means verified statically or headlessly only, per the house
convention. `[HEADLESS]` means executed by a Python driver against the real
committed binaries but never on an engine.

### 2.1 Signatures and hashes: complete, engine-proven, externally accepted

This is the strongest layer in the suite and it is better than most chain
projects ship.

- **secp256k1 ECDSA.** `cxSign`, `cxVerify`, `cxSignRecoverable`, `cxRecover`
  (`coinxt/src/coinxt.lcb`). RFC 6979 deterministic k; low-s enforced
  unconditionally in the shipped binary (`coinxt/native/coinxt.c`), so half of
  BIP-62 / EIP-2 malleability is closed at the C layer. All-zero digest refused.
  `[ENGINE 2026-08-10]`. The recoverable path was independently accepted by
  eth-account, which recovered the exact sender from script-built bytes
  `[2026-08-13]`.
- **BIP-340 Schnorr.** `cxSchnorrSign`, `cxSchnorrVerify`, `cxXOnlyPubkey` over
  vendored bitcoin-core/secp256k1. `[ENGINE 2026-08-17]` against all 19 published
  vectors **including the 10 negatives** (pubkey off curve, `has_even_y(R)`
  false, negated message, negated s, two infinity cases, r equal to the field
  size, s equal to the group order). That negative set is what separates a real
  verifier from a rubber stamp.
- **Digests.** `cxSha256`, `cxSha512`, `cxSha3_256`, `cxKeccak256`,
  `cxRipemd160`, plus `cxHash160` / `cxHash256` composed in script. Keccak-256
  (0x01 padding) and SHA3-256 (0x06) are deliberately separate and the KAT
  asserts they differ. `[ENGINE]`
- **ed25519 and BLAKE2b.** `sxSignDetached` / `sxSignVerifyDetached` /
  `sxSignKeypairFromSeed`, `sxHash` / `sxHashKeyed`, plus **streaming**
  `sxHashInit` / `Update` / `Final` and whole-file `sxHashFile` that reads 16 KiB
  at a time C-side, so a multi-gigabyte file never enters a Data.
  `[ENGINE 2026-08-24, 106/106]`
- **ristretto255 prime-order group.** Hash-to-group, base and general
  scalarmult, point add and sub, scalar add / mul / invert, batch scalarmult,
  point validity. `[ENGINE 2026-08-17 Windows, 2026-08-18 Linux]` against
  RFC 9496 vectors.
- **ChaCha20 raw stream** (`sxChaCha20IetfXor`, ABI 10) `[ENGINE 2026-08-24]`;
  **Argon2id**, an HKDF-shaped KDF, a CSPRNG and constant-time compare
  (`sxPwHash`, `sxKdfDerive`, `sxRandomBytes`, `sxMemEqual`) `[ENGINE]`.

### 2.2 Transaction and record serialization: complete, externally validated

- **A full Bitcoin transaction serializer in pure LiveCodeScript.**
  `cxBtcOutpoint`, `cxBtcOutput`, `cxBtcWitness`, `cxBtcTxEncode`, `cxBtcTxBody`,
  `cxBtcTxid`, `cxVarInt`, `cxDerEncode`. BIP-141 marker and flag emitted only
  when a witness is non-empty. `[ENGINE 2026-08-12]`, byte-exact against the
  BIP-143 worked example, and **accepted by python-bitcointx's `VerifyScript`
  under `SCRIPT_VERIFY_WITNESS`** over per-run fresh fixtures
  (`coinxt/tools/verify-independent-decoder.py`).
- **All three Bitcoin sighash algorithms**, Ethereum RLP and EIP-155 / EIP-1559
  transaction encoding, Base58Check, Bech32 and Bech32m, WIF, xprv/xpub and the
  EIP-55 checksum. BIP-32 HD derivation and BIP-39 mnemonics. `[ENGINE]`
- **nostrxt's owned canonical serializer** (`nostrxt/src/nostrxt.livecodescript`)
  is a second, independent worked example of consensus-grade canonical byte
  discipline in this dialect, with explicit refusals. `[ENGINE 2026-08-24,
  274/274]`

The general point: **consensus-critical byte work is writable and provably
correct in this dialect.** That is not a guess; it is two members' worth of
externally-validated evidence.

### 2.3 Transports: four of them, all real, none of them a gossip network

- **torrentxt.** DHT bootstrap / get_peers / announce, BEP44 signed mutable and
  content-addressed immutable items, and the **rp1** BEP10 peer-wire extension
  carrying opaque bytes at up to 60,000 per message with roughly 1 s flush.
  riptide already chunks content across up to 16 immutable items, each
  re-verified against its own address. `[ENGINE, two-machine 2026-08-13/15]`
- **enetxt.** Reliable/ordered, unreliable-sequenced and unsequenced delivery
  over up to 255 channels, with one-call broadcast fanout and live RTT and loss
  statistics. The 60,000-byte budget and its fragmentation contract are
  observed, not reasoned. `[ENGINE]`
- **datachannelxt.** Browser-interoperable WebRTC data channels with ICE / STUN /
  TURN NAT traversal, reliable and unreliable modes. Needs an out-of-band
  signalling exchange. `[ENGINE]`
- **onionxt.** SOCKS5 dialling and v3 onion services, where the address *is* an
  ed25519 public key: a stable, self-authenticating, NAT-free identity for any
  node, at the cost of a separately-running tor daemon. `[partly ENGINE, live
  Tor legs open]`
- **nostrxt.** NIP-01 events with BIP-340 signatures, NIP-19 encodings, NIP-44 v2
  payloads and a websocket relay client in pure script. `[core ENGINE
  2026-08-24; relay layer needs a live pass]`

None of these is a gossip network. Each moves bytes between peers who already
know about each other. That distinction is what decides several designs below.

### 2.4 An existing Bitcoin client, in pure script, landed one day

Worth its own heading because it reframes the cost question. coinxt's wallet
speaks Esplora, Electrum and Bitcoin Core over JSON-RPC and `shell("bitcoin-cli")`,
including a node screen, a watch wallet, Tor and a UTXO-set scan. It landed
2026-09-04 as roughly 3,000 lines of pure script inside one existing file, with
**no native member, no ABI bump and no binary refresh**. Twelve dated engine
logs now exist for that wallet.

### 2.5 Distributed-systems prior art already in the tree

- **holde-em** has a signed, hash-chained transcript; idempotent log
  replication; epoch checkpoints that produce equivocation evidence; a
  deterministic state-transition function; and **settlement receipts** that are
  countersigned and hash-chained hand to hand, forming "one countersigned ledger
  no subset of players can rewrite" (`holde-em/holdem-spec.md` 8.3). It also
  carries a written **value-readiness gate** (13): a value layer consumes
  receipts and nothing else, and value attaches only after an adversarial harness
  passes attribution on every scripted attack and after a hostile review by
  someone who did not write it. Neither half has happened for anything in this
  repository.
  > **Honesty scope.** These were exercised as folded harness sections in the
  > single-process suite paste, not against a real equivocating host across two
  > machines. Leader election in particular computes a successor; the **live
  > handover is explicitly not built** (`holde-em/src/holdem.livecodescript`:
  > "What this build does NOT do is the LIVE handover"). Read `[ENGINE]` on this
  > row as "ran in a fold", not "survived an adversary".
- **riptide** has a signed hash chain published over BEP44, a subkey registry, a
  normative wire specification (`docs/RIPTIDE-PROTOCOL.md`) with a
  machine-readable conformance bundle re-executed on every push, and a
  magic-bump versioning law. Two-machine engine-proven for phases 1-4.
- **nocloud** has content-addressed transfer with verification on receipt.

### 2.6 The machinery that would hold a new member honest

Ten unified static gates, a byte-identical checker in every member with a drift
gate, fixture tests that mutation-prove the gates themselves, a coverage ratchet
that fails on a new unexercised handler *and* on a stale exemption, MANIFEST
integrity checks, and a five-platform binary matrix.

> Two rows in that ratchet are **advisory** and print without failing the build:
> holde-em's `he*` surface and box2dxt's raw `b2*` binding. A headline coverage
> ratio is not suite-wide; run `tools/check-suite-coverage.py` for the split.

And `coinxt/tools/lcs-interp.py` is a genuine headless execution path: it drives
shipped LiveCodeScript against the real committed `.so` through ctypes. That is
how six BIP-341 trees are already folded into CI. It has one blind spot, and it
is exactly the blind spot a chain would fall into (section 3, item 16).

---

## 3. What is missing, in order of severity

### Tier 1: structural, not fixable in this runtime

**1. No headless or daemon mode.** `docs/OXT-PASS-RUNBOOK.md` section 1.1 says
**No** for every `.lcb` and `.livecodescript`. No validator, sequencer, witness,
calendar server or always-on co-signer. `docs/OPEN-DECISIONS.md` D-21 also
records an instinct against standing daemons, though **[CORRECTED]** that
decision is scoped to holde-em's Level-1 oracle and is not suite-wide policy;
two candidate designs over-read it.

**2. No bounded execution.** No preemption, no gas metering, no step cap, no
handler timeout, no way to interrupt a running handler. The failure mode is
documented in this codebase: eighteen pasted characters became a 268,435,455
iteration loop over an exhausted string, and "the loop runs for hours ... a
frozen ENGINE with no error anybody can read"
(`coinxt/examples/wallet-core.livecodescript`). Consensus parses adversary-chosen
bytes by definition. Every bound must be hand-written per site, and no gate in
this tree can find the next missing one.

**3. No sybil resistance and no economically meaningful proof-of-work.** No
nonce-grinding loop anywhere; `sodium_increment` and `sodium_compare` are both
unexported, so both the counter bump and the target compare would happen in the
interpreter. Argon2id does not rescue it: verification cost equals generation
cost, so every validating node pays full memory cost per candidate, and
libsodium's wrapper fixes parallelism at p=1.

### Tier 2: real gaps, buildable, in the order to build them

**4. No block merkle tree, and the only merkle code in the tree is the wrong
construction.** Verified: `cxTapBranchHash` **sorts** its two children by byte
value and uses BIP-341 tagged hashes (`coinxt/src/coinxt.livecodescript`). A
Bitcoin block root is unsorted, positional, double-SHA256, with odd-node
duplication and a CVE-2012-2459 duplicate-pair refusal. This cannot be
parameterised into the right function; it is a rewrite. RFC 6962's CT
construction is a third, different one (0x00/0x01 prefixes, power-of-two split,
no duplication). Any design must keep all three distinct.

**5. No merkle proof, no header parser, no PoW check, no SPV.** Zero grep hits
for SPV, merkleblock, gettxoutproof, get_merkle or getblockheader across the
whole tree. The request layer cannot ask for the inputs.

**6. No atomic or durable write.** Zero `fsync` / `fdatasync` /
`FlushFileBuffers` in any `.c`, `.cpp`, `.h` or `.livecodescript` in the tree.
`rename file` appears at exactly three sites, all copies of one
download-completion helper that deletes the destination first, and no
state-writing path uses it. `open file ... for binary write` does **not**
truncate, so the house safe-write idiom is delete-then-recreate, which widens
the crash window. And the runbook's persist-then-restart leg is still open:
**nothing in this project's history has ever restarted a process and read its
own state back.**

**7. No reader-side monotonicity on the DHT rail, and it is a live defect.**
**[CLOSED 2026-09-09 - `rsIngestHead` now requires a reader watermark and fails
closed on an omitted one; the dead `headseq` write has a reader. Kept for the
reasoning.]**
Verified in code: `rsIngestHead` (`riptide/src/riptide.livecodescript`) checks
handle, salt, sequence self-agreement and signature, and nothing else; its own
comment defers replay protection to "the app's replay protection", and the app
never implements one. An older, still-validly-signed head silently rolls a
reader back. riptide even writes a `headseq` field on save that its load switch
has no case for.

**8. No database.** One prose sentence in the whole tree
(`torrentxt/examples/README.md`) asserts the engine has SQLite, and zero call
sites touch it. Persistence is whole-blob `arrayEncode` or
`put ... into url("binfile:")`. No index, no cursor, no range scan, no
transaction.

**9. The rp1 inbound queue is unbounded.**
**[CLOSED IN SOURCE 2026-09-09 - bounded with tail-drop and a shed counter. The
committed binaries do not carry it until a release dispatch runs; see
`REMAINING-WORK` C.0.]** Verified: `push_event` is a bare
`events.push_back` under a mutex (`torrentxt/src/torrent_shim.cpp`), fed from
libtorrent's network threads, while the drain moves at most 65536 bytes per
poll. At the shipped 250 ms cadence that is roughly 262 KB/s of drain against a
sender limited only by bandwidth: **remote unbounded memory growth on a
normally-polling node, with no protocol violation required.** datachannelxt
bounds exactly this with tail-drop and a reported count
(`datachannelxt/src/datachannel_shim.cpp`); torrentxt does not. Separately,
`alerts_dropped_alert` is unmapped, so a lost DHT tip is silence.

**10. No aggregate or threshold signatures, and MuSig2 is not one flag away.**
**[CORRECTED]** The survey called MuSig2 "one enabled module". Verified false:
`coinxt/native/vendor/libsecp256k1/src/modules/` holds exactly two directories
(extrakeys, schnorrsig). MuSig2 is **not vendored**. Enabling it means
re-vendoring, an ABI bump and a release dispatch. No BLS or pairing curve exists
anywhere.

### Tier 3: corrected findings, where the survey was wrong

**11. Bignum: partly refuted. [CORRECTED]** "256-bit arithmetic cannot be
handled correctly in pure script" is false as stated.
`coinxt/examples/wallet-core.livecodescript` implements `cwScalarAdd` /
`cwScalarNegate` (mod n, 32-byte hex, nibble loops) and a u128 decimal-string
library, both executed in CI against an independent oracle. What is genuinely
absent is **big-by-big multiply, big-by-big divide, modular inverse and
modexp**. Crucially, a skeptic independently reproduced the chainwork shortcut
across 176,134 samples with zero mismatches: **exact Bitcoin chainwork
`floor(2^256/(T+1))` IS computable in script** with only a big-by-small divmod,
because a compact target is always `m * 256^k` with `m < 2^24` (exact in a
double). The shortcut is valid for nBits exponent >= 0x13 and provably breaks
below it, so an implementation must refuse below the boundary.

**12. Throughput: partly refuted. [CORRECTED]** "Nothing in this tree measures
throughput" is false. box2dxt's Phase 0 spike is a committed benchmark harness
with warm-up discipline, run four times on Win32 on 2026-06-10: a 16.5 ms timer
cadence giving a ~58-60 fps ceiling, 220-285 ms per script-created sprite, and a
40.2 vs 30.7 fps A/B that chose the shipping backend. What is true, and
decisive: **nothing measures the workload a chain needs.** No FFI-crossing cost,
no hash rate, no signature rate, no parse cost, no memory ceiling. Every
capacity number in this document is arithmetic from operation counts.

**13. BEP44 as a block carrier: partly refuted. [CORRECTED]** "At best it
announces a tip, never carries blocks" is wrong about this code. riptide already
chunks across 16 content-addressed immutable items; blocks would ride rp1
(60,000 bytes per message) or plain torrents (unbounded), with BEP44 naming what
to fetch, which is riptide's shipped and two-machine-proven architecture. Also a
**latent defect worth fixing**: `put_immutable` / `put_mutable` cap the **raw**
bytes then bencode, so the wire value can reach roughly 1005 bytes, over BEP44's
own limit, while only `put_signed` caps the bencoded value.

**14. Native member cost: refuted by roughly an order of magnitude.
[CORRECTED]** The claim was "multi-month before any chain logic". nostrxt landed
**whole in one commit** (`ad9dcee`, 2026-08-23: 45 files, 22,536 insertions) and
went 274/274 on a real engine the next day. Suite-level registration was roughly
250 hand-written lines across 19 files, most of it registry data: prefixing and
declaration hoisting are generated, the checker copy is a `cp`, MANIFEST is
generated, and the gate set is `if [ -f ]`-probed. And the suite's own
integration of a large consensus engine, Bitcoin Core, was **not a native member
at all** (section 2.4). Five committed platforms are not a precondition either;
they landed weeks after every member matured.

**15. Security budget: partly refuted. [CORRECTED]** The empirical core survives
and is strongly evidenced. Two errors. "Provides no meaningful protection" is
false: a majority attacker gets reorgs, double-spends and censorship, and can
**never** forge a signature, spend from an address, mint supply or change
validation rules. The honest statement is that **ordering and finality are
worthless while validity is fully protected.** And the dichotomy "permissioned
trust set or anchored" is not exhaustive: merged mining, borrowed slashable
stake, autonomous reorg-resistance rules, and **no consensus at all over
self-authenticating signed objects** each sit outside it. That last one is what
this suite already does.

### Tier 4: the gate that cannot see the bug class

**16. `coinxt/tools/lcs-interp.py` models integers at Python's arbitrary
precision.** **[CLOSED 2026-09-09 - it refuses past 2^53 now, and found a real
unbounded accumulator in the shipped wallet within a day. Engine notes 2.4.]** Verified: `_n()` returns `int(f)` for any integral value, and
integer literals parse to Python `int`. The engine has IEEE doubles, exact only
to 2^53. The interpreter's own contract says "stricter-than-engine is acceptable
and documented; looser is a bug", and this divergence is looser and is not in its
named list. **Any 256-bit or u64 arithmetic written for any design here could
pass every headless vector and the static gate and be silently wrong on an
engine.** Compounding it, genesis-scale chainwork is 10 digits and fits a double
while real per-block work is 24 digits, so a chainwork implementation validated
at low difficulty passes everything and then misorders forks at scale. **Fix the
interpreter before writing the arithmetic, or none of the testing means
anything.**

---

## 4. The six candidate architectures

**1. CAIRN.** A deliberately tiny Bitcoin-shaped proof-of-work UTXO chain in
LiveCodeScript, gossiped over rp1, tip-announced over BEP44, whose own work is a
short-range tie-breaker only because deep history is anchored into Bitcoin every
1000 blocks. Trust: a K-of-M anchor federation for anything older than the last
checkpoint, plus a mining majority costing about $20 to buy. Effort: 4-5 months
plus 2-3 for a native shim. The most rigorous document in the panel, and it
refutes itself: it states its own PoW budget as economically zero, then admits
its rolling checkpoint creates permanent unreconcilable partition splits "with no
clean fix available at this design point".

**2. Quorum Table.** A permissioned chained-BFT ledger for 4 to 20 known
signers: ed25519 votes over enetxt, onion addresses as validator identity,
commit certificates instead of chainwork, equivocation punished by jailing at an
epoch boundary. Trust: at most f = floor((N-1)/3) Byzantine; accountability
rather than trustlessness. Effort: about 23 person-weeks plus 10-14 engine
sessions. The best scope-elimination argument in the panel (seven of eight hard
gaps evaporate because they are requirements of *permissionless* consensus), the
best test plan, and a deployment shape it describes as "not a service, it is a
standing meeting".

**3. Borrowed Consensus (chainxt).** One native member binding Bitcoin Core's
`libbitcoinkernel` behind a flat `cnc_*` ABI: one kernel, two chains (verify real
Bitcoin, and run your own custom signet on identical rules), with zero lines of
consensus written here. Trust: Bitcoin Core's contributors, plus a large opaque
binary in a supply chain with no provenance. Effort: 3-4 months to the wallet
payoff, 6-8 through a custom signet. The most philosophically correct answer,
and the highest ongoing maintenance load, against an upstream header that calls
itself "unversioned and not stable yet".

**4. Rootline.** Signed append-only logs whose tree heads are notarized into
Bitcoin through coinxt's already-engine-proven transaction path, distributed
over nostrxt / torrentxt / onionxt, with a checkpointed header verifier so a
receipt is checkable. Certificate-transparency semantics plus OpenTimestamps
anchoring, no new native code. Trust: the log operator for availability and
non-equivocation only; Bitcoin for the timestamp. Effort: 12-16 weeks, one
person. Its stated security delta is the most precise in the panel: "a chain
says the second spend does not exist; Rootline says both spends exist, both are
signed by the same key, and here is the proof that key defrauded someone."

**5. Croupier.** Bonded permissioned proof-of-stake, promoting holde-em's DLEQ
work from dealing cards to electing block proposers as a ristretto255 VRF, with
BIP-340 block signatures, rp1 gossip, Bitcoin anchoring as a long-range backstop
and implemented slashing. Trust: two thirds of bonded stake, plus a bespoke VRF
nothing outside this repository can verify. Effort: 12-16 weeks for two, plus
two ABI bumps. It carries the sharpest structural insight in the panel (PoS fork
choice needs no 256-bit arithmetic, so the operation this tree cannot perform is
the one it does not require) and pays for it with unreviewable cryptography, a
documented-impossible long-range defence (forward-secure key erasure cannot work
where variables are not locked memory), and the largest legal surface of the six.

**6. Counterfoil.** A roughly 900-byte signed, monotone, hash-linked record
format plus a reader-enforced watermark and an atomic local store: one shared
substrate that closes riptide's rollback hole, gives nocloud delivery receipts it
does not have, and turns holde-em's in-memory receipt chain into a durable
threshold-signed ledger. Trust: your own device, plus the other party for
availability only. Effort: 8-12 weeks. Its own one-liner says "It is not a
blockchain and should never be called one."

### Comparative scoring

| Design | Engine feasibility | Adversarial security | Fit with project | Value and reality | Total |
|---|---|---|---|---|---|
| **6 Counterfoil** | 8 | 7 | **8.5** | **9** | **32.5** |
| **3 Borrowed Consensus** | **9** | **8** | 7.5 | 7 | **31.5** |
| **4 Rootline** | 7 | 6 | 8 | 8 | **29.0** |
| 2 Quorum Table | 6 | 7 | 7 | 4 | 24.0 |
| 1 CAIRN | 5 | 5 | 4 | 3 | 17.0 |
| 5 Croupier | 4 | 4 | 5.5 | 2 | 15.5 |

The lenses disagree informatively. Engine feasibility and adversarial security
both put chainxt first, for the same reason: it is the only design whose hot
path never enters the interpreter and whose consensus bytes are parsed by
hardened C rather than by unpreemptable script. Fit and value both put
Counterfoil first, for the same reason: it costs one member of pure script and
fixes three verified defects that exist right now.

### A seventh shape, which no design took and which the tree already uses

**Be a client of an external consensus daemon over a socket.** This suite does
that shape three times already: onionxt over a local tor daemon, the wallet over
Electrum / Esplora / bitcoin-cli, nostrxt over relays. Section 2.4 is the
existence proof at consensus scale: Bitcoin Core integrated in one day, pure
script, no binary. If the goal is "an xTalk app that participates in a
blockchain", this is the cheapest correct answer available and it is already
half-built. It deserves to be costed properly before any of designs 1, 2 or 5 is
started.

### Recommendation

**Pursue designs 6 and 4 as one combined project.** They are complementary
rather than competing, and every judge grafted one into the other unprompted.
Counterfoil supplies the substrate (record format, reader-enforced watermark
with named verdicts, atomic store, portable fork proof); Rootline supplies what
makes it worth having to somebody outside the tree (RFC 6962 consistency proofs,
merkle aggregation so N records share one on-chain transaction, a serialized
proof format that outlives the app, and the checkpointed header verifier).
Neither is a blockchain, and both should say so on the label.

**Hold design 3's phase 1 as a separately-justified option.** Binding only
`libbitcoinkernel`'s *stateless* surface (script verification, block check,
script flags) is coinxt's exact calculator shape: no handles, no threads, no
datadir, no poll queue. Independently of any chain, it converts
`coinxt/tools/verify-independent-decoder.py` from a pip-dependent acceptance run
into an in-tree CI gate. That is a standalone win for an existing member even if
the rest is never built. Gate it on a build-feasibility spike, because the
32-bit lanes are exactly where a LevelDB-backed chainstate dies.

**Do not build designs 1 or 5.** CAIRN spends four months to produce a chain
whose own security it proves is worthless, with a finality rule it admits
permanently splits. Croupier attaches the best component idea in the panel to a
token, for nobody, secured by cryptography nothing outside this repository can
verify, against coinxt's own written rule that the family adds no cryptography
of its own and that the rule "counts double for money".

---

## 5. A phased roadmap for the recommendation

Every phase ships something runnable and falsifies a named risk.

### Phase 0: measure, and make the gates able to see (2 weeks, 1 engine session)

Ships the first throughput measurement in this project's history, written into
`docs/OXT-ENGINE-NOTES.md` as OBSERVED; a corrected interpreter; three defect
fixes.

- A roughly 60-line probe stack pasted into OXT on Windows and Linux: N x
  `cxSha256` at 32 / 64 / 1024 / 65536 bytes; N x an empty interpreted loop for
  the baseline; N x `sxSignVerifyDetached`; N x hex encode and decode over 32
  bytes; `byte N to M of` on a 60,000-byte Data at rising offsets; a
  `rename file` test across a full disk, an existing destination and a read-only
  volume; and a write-then-restart-then-read round trip.
- Clamp `lcs-interp.py`'s arithmetic to double precision in all three
  drift-gated copies, add the divergence to its named list, and triage whatever
  shipped script the clamp newly flags.
- ~~Fix the three verified defects independently of everything else: riptide's
  missing high-water mark, the unbounded rp1 deque (copy datachannelxt's
  tail-drop-and-count policy verbatim and map `alerts_dropped_alert`), and the
  BEP44 bencode overshoot.~~ **DONE 2026-09-09** (PR #132), and doing them
  independently of everything else was the right call for a reason this plan
  did not anticipate: each one uncovered a defect next to it that no survey had
  named. The clamp above is what made the wallet's unbounded accumulator
  visible; the watermark's u64 bound exposed an INVERTED ceiling in riptide's
  BTXO reader; the BEP44 fix turned out to be needed in two layers, not one.
  ~~`alerts_dropped_alert` is still unmapped and still worth doing.~~ **DONE
  2026-09-10, source only**: it is counted in the drain and reported through
  the last-error channel, the same interim the rp1 shed count rides; a proper
  alert code still waits for ABI 12 and the release dispatch (`REMAINING-WORK`
  C.0).

Falsifies: "we know what this runtime costs" (nobody does), "chunk indexing is
O(1)" (unknown, and if it is O(N) then every byte loop in the suite is quadratic
and the storage design changes), "`rename file` is atomic here", and "our
headless gate can see a precision bug" (it cannot).

> **The one piece of native work in the plan, and it is separately justified.**
> Bounding the rp1 queue changes a record or alert code, which
> `torrentxt/src/btx_abi.h` says bumps `BTX_ABI_VERSION` (11 to 12) and therefore
> needs a five-platform binary refresh. That cost belongs to the DoS fix, not to
> the recommendation: the recommended record, store, anchoring and verifier work
> is pure script throughout. Fix the DoS whether or not this plan proceeds.

### Phase 1: the merkle and header layer, fully headless (2-3 weeks)

Ships the three merkle constructions kept deliberately distinct (Bitcoin block:
unsorted, double-SHA256, odd-node duplication, CVE-2012-2459 refusal; RFC 6962:
0x00/0x01 prefixes, power-of-two split, inclusion **and consistency** proofs;
OpenTimestamps: explicit prepend / append / hash op lists), plus 80-byte header
parsing, compact-nBits expansion, the PoW target comparison, header linkage and
retarget validation. Plus the coinxt promotions: make `cxCompareBytes` public
(verified `private function`, so the tree's only exact 256-bit comparison is
unreachable from every app; its contract is equal-width operands only), add
`cxVarIntDecode` enforcing shortest form, and add `cxUIntFromBytesLE` / `BE` with
the 2^53 throw riptide already uses and coinxt's encoders lack.

Falsifies: "consensus-critical byte work can be written and proven correct in
this dialect without an engine". Pinned against real published Bitcoin block
headers and branches and against published RFC 6962 vectors, driven through
`lcs-interp.py` against the real committed `coinxt.so`.

> **Read phase 1's "headless" label against item 16.** It ships compact-nBits
> expansion and a PoW target comparison, which is precisely the arithmetic the
> unclamped interpreter cannot judge. Phase 0's clamp is a hard prerequisite,
> not a parallel task.

> **New member, or new handlers on coinxt?** This is a real fork in the road and
> should be decided before phase 1 starts, not discovered. A new member costs
> roughly 20 registrations across 19 files plus a harness fold into a
> 43,003-line paste that raises the cost of every future engine pass forever.
> Putting these handlers on coinxt costs none of that, and the private helpers
> they need (`cxCompareBytes`, byte slicing, integer encoders) are already
> inside coinxt. The argument for a separate member is that merkle and header
> logic is not cryptography and coinxt's charter says it is a calculator. The
> argument against is the maintenance tax named in section 7. Record the call in
> `docs/OPEN-DECISIONS.md` as a dated D-NN entry.

### Phase 2: the record and the store (3 weeks, 1 engine session)

Ships the signed record format (build / parse / verify / hash / sign-span), the
reader-enforced watermark with six named verdicts (`ok` / `dup` / `stale` /
`fork` / `gap` / `bad`), the portable fork proof, the cosign and threshold quorum
check, and the atomic sealed store.

The store should use append-only tagged frames plus a small atomic head pointer,
with forward recovery scanning to the first bad tag, exploiting the engine's
documented **non-truncating** `open file ... for binary write` plus seek as the
append primitive, so torn-write garbage is overwritten rather than needing a
truncate the engine does not have. Include a torn-write harness: corrupt the log
at every byte offset of the last frame and assert recovery lands on the right
height every time.

Falsifies: "a crash-recoverable store is possible here", and its engine-session
half closes the resume-across-a-restart leg this tree has never closed.

> **Do not let this phase claim durability.** With no `fsync` anywhere and
> `seek to N in file` never once executed (it carries four standing
> `-- VERIFY (on-engine)` markers), the honest claim is **crash-recoverable,
> best-effort durable**. Whether to export `fsync` and an atomic replace from an
> existing shim, which is a few lines of POSIX and Win32 C, is the one place
> where a small amount of native code would change an honesty label. It is a
> D-NN-shaped decision and should be taken before this phase, not after.

Also unresolved and needed before coding: the store's on-disk location and
sharing model (one file per app, or one shared ledger, given that
`start-here.livecodescript` ships a SESSION card because several suite stacks are
routinely open at once, and that LiveCode keys a file handle by path and no-ops a
second open); where the signing key comes from and who owns it when three apps
share the substrate; and the record format's versioning policy, for which the
tree's only written convention is the magic-is-the-version hard-fork-only law in
`docs/RIPTIDE-PROTOCOL.md`.

### Phase 3: anchoring, creating side, on a real chain (1-2 weeks, 1 engine session)

Ships merkle aggregation of N record hashes into one 32-byte root, a serialized
OpenTimestamps-shaped proof format, and the root handed to the wallet's existing
`data: <hex>` pay-to line, which already flows through selection, review,
signing, PSBT and fee bump. Output: a real testnet anchor of a real batch.

Falsifies: "this suite can notarize into Bitcoin today". Low risk, because the
transaction half is already engine-proven on testnet.

> **Discipline, non-negotiable:** never ship a creating side whose receipts the
> product cannot check. Receipts carry a machine-readable `unattested` marker
> until phase 4 lands.

> **Layer ownership must be decided here.** The existing OP_RETURN helper lives
> in the *example* layer (`coinxt/examples/wallet-core.livecodescript`), not in
> the shipped `cx*` library. A member depending on an example file inverts the
> suite's dependency direction. Either promote the helper into `cx*` or have the
> anchoring layer emit the script itself.

### Phase 4: the verification wire (2-3 weeks, 1 engine session)

Ships three Esplora endpoints (`/api/tx/<txid>/merkle-proof`,
`/api/block/<hash>/header`, `/api/block-height/<n>`), two Electrum methods
(`blockchain.transaction.get_merkle`, `blockchain.block.header`), two Core verbs
(`getblockheader`, `gettxoutproof`), a checkpointed header store, and the
verifier that walks a receipt from leaf hash to root to anchor bytes to txid to
merkle branch to header to proof-of-work to checkpoint.

Scope, stated honestly: **checkpointed header verification, not full SPV.** Each
header's own work, linkage and retarget are checked; there is no chainwork fork
choice. The tip is corroborated by two *independent* backends, one of them a
`.onion` where the circuit is the authentication, because
`docs/OXT-ENGINE-NOTES.md` 6.8 leaves TLS certificate verification unmeasured in
both directions and instructs treating anything unsafe under no verification as
unsafe. That limit goes in the honesty label, not a footnote.

Falsifies: "a receipt this suite issues can be checked by this suite". This is
the largest honesty upgrade available to the repository.

### Phase 5: the three app adoptions (4-6 weeks)

Ships riptide's follow list as a signed record with its ingest wrapped by the
watermark; nocloud delivery receipts (receiver signs, sender verifies against the
hash it computed when it created the torrent, so the receipt cannot be forged and
cannot be claimed for a file the receiver never held); holde-em's settlement
chain persisted, its unanimity gate replaced by a threshold, and its identity
seed moved out of a plaintext stack custom property into the sealed store with
fail-closed generation.

Falsifies: "this is a shared substrate and not a riptide feature with a member
directory around it". If two of three apps decline, the honest outcome is roughly
200 lines of watermark code in riptide and no member, and the plan should be
allowed to end there. Record that outcome as a dated decision rather than
letting it be inferred.

> **Budget the re-verification.** riptide's ingest rail is two-machine
> engine-proven and pinned by 98 golden and refusal vectors re-executed on every
> push, under a normative wire specification with a magic-bump versioning law.
> Adding a reader-enforced watermark changes ingest semantics, so it is a
> `docs/RIPTIDE-PROTOCOL.md` amendment plus new refusal vectors plus arguably a
> re-pass, not 200 lines of app code.

### Phase 6 (optional, separately justified): chainxt phase 1 (5-7 weeks including prerequisite)

**Prerequisite, not optional.** SHA-pin every GitHub Action across all eight
workflows (verified: **zero** are pinned, and two invoke a third-party action by
mutable tag in build jobs whose artifacts a `contents: write` job later commits),
replace mutable upstream `GIT_TAG` pins with commit SHAs or hashed tarballs
following sodiumxt's own precedent, add build provenance attestation, add a root
`SECURITY.md` with a disclosure contact (verified: only `nocloud/SECURITY.md`
exists), and add a gate verifying coinxt's vendored trezor-crypto and
libsecp256k1 against the commits `VENDOR.md` names (those SHAs appear in no
`.py`, `.sh` or `.yml`). About a week, and it protects the six existing members
whether or not chainxt is ever built.

Then vendor `libbitcoinkernel` pinned by commit SHA, get it to build static on
all five platform ids, link a three-export stateless shim, and expose
`cnVerifyScript` / `cnCheckBlock` / `cnScriptFlags`. **Kill criterion:** if it
will not build for i686 in the first two weeks, stop; the fallback is phase 4's
checkpointed verifier on three platforms, and the design should be structured so
that answer is cheap. Phases 1 and 2 of any new member owe what
`docs/NEXT-EXTENSIONS-PLAN.md` Part V.4 already specifies; cite it rather than
inventing a new bar.

### Total effort

Phases 0 through 5 sum to **14-19 weeks for one competent person**, or roughly
10-13 elapsed weeks for two working in parallel, plus 4-6 engine sessions of
which one should be two-machine. Phase 6 adds 5-7 weeks and is a separate
decision. Expect roughly one real defect per two-machine engine evening; that is
this project's informal experience rather than a measured rate.

---

## 6. Open questions and cheap experiments

### Only the maintainer can answer these

1. **What is the actual goal?** "A blockchain" and "the properties people want
   from a blockchain" have different answers here, and the second is much better
   served. If the requirement is genuinely a chain with transferable value among
   strangers, the honest recommendation is to build it elsewhere and use this
   suite as its wallet and client. **The recommendation in section 4 stands only
   under the second reading**; under the first, section 4's seventh shape (be a
   client) is the answer, not designs 6 and 4.
2. **Does anyone want to run a node?** `docs/OPEN-DECISIONS.md` D-06 decided that
   a follower does not republish other people's records, and `nostrxt/README.md`
   says "It is not a relay server. Storing and serving other people's events is a
   different program." The word "blockchain" appears in zero suite-level planning
   documents. A chain needs someone to overturn that posture deliberately.
3. **Is transferable value in scope?** The recommendation carries none by
   construction: attestations, receipts, revocations and head pointers raise no
   money-transmission, securities or sanctions question. A token raises all three
   at once, into a tree with zero legal analysis outside holde-em's gambling
   paragraph.
4. **Is a GUI-window-per-participant deployment acceptable?** Every consensus
   design in the panel dies on this, and no engineering fixes it.
5. **Is the maintenance load acceptable?** A sixth binary-shipping member
   tracking an upstream that calls itself unstable, on five platforms including
   two 32-bit lanes, in a repository already carrying over 100 MB of committed
   binaries, is a permanent tax on a very small team.
6. **New member or new handlers on coinxt** (phase 1), and **does the tree accept
   a native `fsync` and atomic-replace export** (phase 2)? Both are D-NN-shaped.
7. **What is the decision rule if phase 0 measures the FFI crossing at 50
   microseconds?** At 1 microsecond a 4,000-leaf merkle root is 72 ms; at 50 it
   is 3.6 seconds and the fold must move into C, which reintroduces every cost
   this plan avoids. Set the threshold and the fallback before measuring.
8. **Who is the auditor, and what result counts as the transparency half
   working?** Split-view detection rests on gossip, and this suite structurally
   cannot host a gossiper. Set a success criterion, or the experiment cannot
   fail.

### Cheap experiments that resolve the biggest unknowns

| Experiment | Cost | Resolves |
|---|---|---|
| The phase 0 probe stack | 1 day to write, 1 engine session | FFI-crossing cost, interpreter op rate, whether `byte N of X` is O(1) or O(N). Every capacity claim in this document depends on these and none is measured. |
| Does OXT expose SQLite via revDB? | 5 minutes at an engine | Either hands the suite a free embedded database, changing the storage answer for every design, or confirms a native KV member would be needed. One prose sentence asserts it; zero code touches it. |
| `seek to N in file` and `rename file` on both platforms | Same session | The store's two load-bearing primitives. `seek` carries four standing `-- VERIFY (on-engine)` markers and has never executed. |
| Offer the engine a bad TLS certificate | 30 minutes | `docs/OXT-ENGINE-NOTES.md` 6.8 records that the one successful `open secure socket` met a good host, so success is equally consistent with full verification and with none. Decides whether any https backend is usable. |
| Clamp `lcs-interp.py` to double precision and re-run the gates | 1 day plus triage | Whether the tree's only headless execution path can see a 2^53 defect. It currently cannot. |
| Re-derive the chainwork shortcut against Bitcoin Core's `GetBlockProof` | 1 day | Whether exact chainwork is reachable in script. Verified once across 176,134 samples; should not be depended on until re-derived here, and must refuse nBits exponents below 0x13. |

### UNVERIFIED, and flagged as such

- Whether `bitcoinkernel.h` exposes a custom `signetchallenge`. Design 3's "run
  your own chain" half rests on it and could not be checked from this tree.
- Whether `libbitcoinkernel` builds for i686 at all.
- The real BEP44 item lifetime. The only figure anywhere is a code comment
  estimating about 2 hours.
- Whether libtorrent actually rejects a 1005-byte bencoded value. libtorrent is
  FetchContent-pinned rather than vendored, so the arithmetic is verified here
  and the network consequence is not.
- Sustainable DHT put and get rates, rp1 behaviour above two peers, and per-peer
  resource cost at scale. The largest peer count ever executed anywhere in this
  tree is **one live connection**.
- python-opentimestamps' license, if the `.ots` format is reimplemented.

---

## 7. Risks

### Technical

**The measurement gap is the dominant risk and it is cheap to close.** Every
throughput, capacity and schedule number here is arithmetic from operation
counts. The tree's only timings are four Win32 rendering spikes from 2026-06-10.
Phase 0 exists because the FFI-crossing cost could change a design rather than
merely slow it.

**A hostile input can freeze the process silently, and no gate can find the next
missing bound.** The verifier parses attacker-supplied bytes. Every length field
must be bounded by the remaining input before it is used, hand-written per site,
each with a refusal vector. One miss is a hung app with no error message.

**Two engine hazards have already corrupted correctness in this tree and would
do so again.** `the caseSensitive` defaults FALSE, so `is` and `offset()` fold
case; `coinxt/CLAUDE.md` records an adversarial read-through finding 414 green
wallet checks "running under a comparison rule the engine does not have". `the
itemDelimiter` is global mutable state whose corruption is engine-observed
repeatedly in shipped code. Any hex-comparing verifier must compare bytes,
byte-exact, through a length-checked comparator.

**Persistence is best-effort unless a native primitive is added.** No `fsync`
exists in this engine. Temp-then-rename is the strongest primitive available and
cannot guarantee durability across power loss. The answer is replication and
content-addressed rebuild, or the small C export named in phase 2.

**Key custody is a first-class risk and the tree says so.** An OXT script
variable is not locked memory: a seed held in script can be paged to disk and is
not reliably zeroed. This plan introduces a new signing key and moves holde-em's
identity seed into a sealed store. Sealing at rest does not change what happens
while the key is in a variable.

**Split-view detection may never fire.** If the auditor population is
realistically zero, the transparency value dies and only the anchoring value
survives: unforgeable timestamps and no back-dating, which hold with zero
auditors.

**The supply chain is unauditable and this recommendation does not fix it.**
Over 100 MB of opaque native code loads into every engine process.
`tools/check-binary-freshness.py` answers "does this match THIS source tree",
never "where did these bytes come from". Zero SHA-pinned actions, mutable
upstream tags, no reproducible builds, no attestation, no signing. A pure-script
recommendation adds no binaries, which is a modest argument in its favour, and
the hardening in phase 6's prerequisite should happen anyway.

### Non-technical

**Legal and regulatory exposure of transferable value is unanalysed and large.**
The tree's only regulatory prose is holde-em's gambling paragraph. coinxt, which
handles real Bitcoin, carries none. Issuing a transferable token plausibly
implicates money transmission, securities characterisation, sanctions and
AML/CFT, and tax reporting, in most jurisdictions, with named natural persons
attached to a public repository. **This recommendation carries zero transferable
value precisely to avoid this.** If value is later attached, holde-em's own
written gate should govern it: value attaches only after the adversarial harness
passes attribution on every scripted attack, and after a hostile review by
someone who did not write it. Neither half has happened for anything in this
repository.

**Abuse exposure is permanent and unmoderatable by design.** BEP44 puts are
globally replicated with no takedown path; onion services have no operator to
serve; anything anchored is permanent. The suite's own brainstorm already flags
that open inboxes need rate limiting or proof of work "or they become spam and
malware drops". No such mitigation exists in any member.

**No external security review has ever been performed on any member of this
suite**, there is no root `SECURITY.md`, and there is no disclosure contact. A
finder has nowhere to report. That should be fixed regardless of this project.

**Maintenance load on a small team is the risk that actually kills projects like
this.** The suite paste is already 43,003 lines and every folded harness raises
the cost of every future engine pass forever. Four named release dispatches were
needed before one landed end to end (runs 5, 10 and 11 failed at three different
stages before run 12 on 2026-08-27), and the bundle stage gates on the whole
30-job matrix, so 29 green artifacts were once discarded over one missing Perl
module. Every design that adds a native member inherits that permanently.

**Scope creep from "not a blockchain" to "a blockchain" is the most likely way
this goes wrong.** Counterfoil's own one-liner exists for a reason. The moment
the substrate is called a chain, every expectation in section 3's tier 1 arrives
with it, and none of them can be met here.

---

## Appendix: files to open first

- `coinxt/src/coinxt.livecodescript`: the serializer, sighashes, HD, encodings.
  The proof that consensus-critical byte work is writable and correct here.
- `coinxt/src/coinxt.lcb`: the native boundary and its ABI gate.
- `holde-em/src/holdem.livecodescript` and `holde-em/holdem-spec.md` sections 8.3
  and 13: the transcript, the receipts, and the value-readiness gate. The closest
  thing to consensus in this tree.
- `riptide/src/riptide.livecodescript`: the signed hash chain over BEP44, and the
  missing watermark in `rsIngestHead`.
- `nostrxt/src/nostrxt.livecodescript`: the owned canonical serializer and its
  refusals.
- `torrentxt/src/torrent_shim.cpp`: BEP44 and rp1, including the four cap sites
  and the unbounded event deque in `push_event`.
- `coinxt/tools/lcs-interp.py`: the only headless execution path, and its
  precision blind spot in `_n()`.
- `docs/OXT-ENGINE-NOTES.md`: what the engine actually does.
- `docs/OXT-PASS-RUNBOOK.md` section 1.1: the layer table, and the flat **No**.
