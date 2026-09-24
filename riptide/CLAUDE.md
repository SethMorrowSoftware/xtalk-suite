# CLAUDE.md - riptide/

Guidance for Claude Code in this directory. Read the suite's `docs/RIPTIDE-SOCIAL-SPEC.md` FIRST: it
is the design (the rails, the identity architecture, the security model, the phased roadmap), and
this directory implements it phase by phase. The bytes are normative in the suite's
`docs/RIPTIDE-PROTOCOL.md`. The root `CLAUDE.md` still applies; where they conflict, this file wins
inside `riptide/`.

> **Engine BEHAVIOUR** - as opposed to the conventions here - is collected in
> [`docs/OXT-ENGINE-NOTES.md`](https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/OXT-ENGINE-NOTES.md).
> Keep riptide-specific gotchas here; put anything the ENGINE does there.

## 1. What this is

The suite's capstone app, pure LiveCodeScript over the installed extension surfaces. It is
structured like a member so the suite's gates walk it, but it is an APP: nothing here is compiled,
nothing adds native surface, and `rs*` never becomes a library other members may call. Library
0.12.0 (`kRsVersion`), 106 public `rs*` handlers; the suite's `tools/check-suite-coverage.py` prints
the current coverage row (106/106 when last run) and is the authority over any copied number.

| Path | Holds |
|---|---|
| `src/riptide.livecodescript` | the `rs*` library; the byte-exact wire layouts are documented at its top |
| `examples/riptide-social.livecodescript` | the five-card app (Feed, Messages + Call, Devices, Anon, Nostr); carries its libraries between embed sentinels |
| `tests/` | the harness `riptide-selftest.livecodescript` (`rsSelfTest()`, folded into the suite paste) and `riptide_golden_test.py` |
| `tools/` | the oracle `riptide_reference.py`, `emit-kx-anchor.py`, the vector, execution and boot gates, `export-protocol-vectors.py`, the family checker and docs-style copies, `run-gates.sh` |
| `docs/` | `docs/api-reference.md`, `docs/two-machine-runbook.md`, and the GENERATED `docs/protocol-vectors.json` |

## 2. The rules that bind this directory

Code comments cite these numbers; keep them.

1. **The oracle comes first.** `tools/riptide_reference.py` anchors to vectors from OUTSIDE this
   directory (the sodiumxt C KATs, the cross-project BEP44 conformance vector, a real published
   onion). A new derived value gets its oracle derivation and golden pin BEFORE the script
   implementation; a vector captured from the script's own output proves nothing.
2. **One set of bytes, three holders**: the oracle, `tests/riptide_golden_test.py` and the harness
   constants in `tests/riptide-selftest.livecodescript`. `tools/check-selftest-vectors.py` FAILS on
   a constant that is neither re-derived nor listed as an input with a written reason, and on a
   stale input entry. Never hand-edit a golden; regenerate from
   `python3 tools/riptide_reference.py`.
3. **Wire formats bump their magic**: `RIPTKEY1`, `RSH1`, `RSP1`, `RSK1`, `RSI1`, `RSM1`, `RSL1`,
   `RSN1`, `RIPTAPP1`. A framing change mints a new magic and updates build + parse, all three
   holders, its section of the suite's `docs/RIPTIDE-PROTOCOL.md`, and `docs/protocol-vectors.json`
   (`python3 tools/export-protocol-vectors.py`, whose `--check` re-executes every vector in the gate
   set). Never a silent fix.
4. **Caps refuse, never truncate**, on build AND parse; a parse is strict to the byte (exact total
   length, trailing bytes refused).
5. **Every foreign call sits in a try** (`sx*`/`cx*`/`ox*`/`bt*`/`nx*`) and no `rs*` handler may
   throw: return empty (or false) and record the reason for `rsLastError()`.
6. **Probe, never assume** (`rsProbeCapabilities`). SodiumXT is the one hard dependency. A missing
   optional extension disables exactly its feature with an "install org.openxtalk.library.X" message
   and never regresses another (spec section 3.4).
7. **The static gate is law.** `python3 tools/check-livecodescript.py` (the family's unified
   checker) walks this directory; the suite's `tools/check-handler-calls.py` checks every `rs*`
   call's existence and arity. House style: no em/en dashes or curly quotes in any `.md` or
   `.livecodescript` here (`python3 tools/check-docs-style.py`).
   - **7a. The library EXECUTES too.** `python3 tools/check-script-vectors.py` drives the SHIPPED
     `src/riptide.livecodescript` through the family interpreter (`../nostrxt/tools/lcs-interp.py`)
     against the real committed CoinXT; before it, only the static checker read the library, and a
     checker cannot tell whether a handler computes the right bytes. It settles LOGIC, not parser
     behaviour, so it promotes nothing out of "verified statically"; a pure-handler change is not
     done until it passes. Its source rewrites are asserted (trap 13).
   - **7b. DO NOT land UI changes in this app without a way to RUN them.**
     `tools/check-demo-boot.py` boots the shipped stack headlessly under two capability profiles
     (SodiumXT-only, full install), after `tools/test-demo-boot.py`'s seeded-defect fixtures. It
     models the engine; it is not the engine. Born 2026-08-29, when a card passed every gate and
     broke the app at `openStack`.
8. **The honesty convention.** "Verified statically; needs an OXT pass" until a recorded run says
   otherwise; anonymity claims also need a live-Tor pass, the Nostr rail a live-relay pass. Flip
   labels only on a recorded engine result, members first, root README last.

## 3. Decisions (do not re-litigate)

**Identity and records.**
- KDF context: exactly 8 bytes, `"riptide"` + NUL, built by `rsKdfContext()` at runtime (a constant
  cannot hold a NUL). The `sxKdfDerive` subkey id is a DECIMAL STRING; BLAKE2b with the id as LE64
  salt and the context as the personal field, pinned to the sodiumxt C KAT.
- Subkeys: 1 identity ed25519; 2 DM crypto_kx; 3 LAN; 4 Nostr (via the ladder); 5 `RIPTAPP1` seal;
  100+n anon ed25519; 200+n anon DM kx. One seed never feeds two cipher schemes (why 2 is not 1, and
  200+n is not 100+n).
- SHA-3 for the onion: `rsSha3` tries `sxSha3_256` (SodiumXT ABI 7, shipped 2026-08-11 because
  riptide needed it) then `cxSha3_256`; the goldens pin output, not provider, and riptide's own
  onion assembly degrades one provider at a time. `rsVerifyOnionClaim` needs no SHA-3.
- The handle equals `btDhtKeypair`'s publicKey for the same seed (the suite's
  `tests/cross-member-test.py` pins it), so the identity derives via `sxSignKeypairFromSeed` and its
  secret never enters torrentxt.
- Immutable DHT target = SHA-1 of the bencoded value (`sha1Digest` lets the harness prove post-chain
  targets offline). `binaryEncode` n/N/NN is big-endian; u64 splits via `div`/`mod 4294967296`; the
  base32 encoder masks its accumulator each step.
- `kRsMaxRecord` = 996, because BEP44's 1000 applies to the BENCODED value `<len>:<bytes>`. Derived:
  post text capacity 876 (556 with 8 media) and the kind-C ceiling 15,936 bytes (16 chunks), pinned
  headlessly in check-script-vectors because engine-only assertions derived from a constant rot
  silently (six did at 1000 -> 996).
- Kind-C rail (A2, 2026-08-23): chunks split by BYTE, so only the CONCATENATION is UTF-8-validated;
  `rsPublishChunkedPost` signs BEFORE touching the session; `rsAssembleChunkText` re-hashes every
  part. The demo walker BRANCHES ON KIND (a kind-C post once rendered as verified with blank text).

**Phase 2, the live feed.**
- The library never owns a session (one TorrentXT session per process, polled by the app). Every
  live handler takes `pSession` and validates every OTHER input first, so refusals run, and are
  tested, with no torrentxt.
- One seq, one source: `rsPublishHead` reads the BEP44 seq from the head's own bytes; `rsIngestHead`
  refuses a BEP44 seq that disagrees with the embedded one.
- `rsBep44SignBuf` rebuilds the BEP44 buffer in pure script (byte-identical to `btDhtBep44SignBuf`).
  Ingest re-verifies the signature in SodiumXT and recomputes content addresses (trust arithmetic,
  not the transport; it also backstops case-folding `is` on the salt). `rsPublishImmutable` refuses
  a libtorrent target that differs from its own recomputation.
- Rollback defence (heads 2026-09-08, bridge 2026-09-10): `rsIngestHead` and `rsIngestBridge` take a
  REQUIRED `pMinSeq`, because a validly-signed OLD record passes every other check. Empty or insane
  is refused, 0 is the affirmative "never seen", equal is accepted, strictly older refused; same-seq
  equivocation is out of scope. Apply semantics, no wire change (protocol 4.1, 8.1). No app in this
  tree ingests a foreign bridge yet. A deferral written in a comment is not a design, it is an open
  defect with a polite name.
- The harness's session starts into a temporary, commits only on success and is never stopped; the
  suite generator aliases the folded copy to the core's session (`@CORESESSION@`), since a second
  `btStartSession` is refused and the live section would SKIP green.

**Phase 3, media.**
- Attachments are SINGLE FILES: a trackerless torrent `btCreateTorrent(path, 0, 0, "")` seeded in
  place (save path = the file's parent); the info-hash is returned, `btFindTorrent` recovers the
  handle. `rsMediaFetch` finds before it adds and sets sequential on both paths (a failed
  `btSetSequentialDownload` fails the call but keeps the torrent).
- `rsMediaStatus` takes the TORRENT handle; its file fields are empty until metadata. File existence
  is NOT playability (a hollow file exists at metadata time, measured 2026-08-27): Play needs
  `raMediaFrontReady`, 5% of the CONTIGUOUS front, on the feed and LAN-handoff paths. A
  non-faststart video cannot start early (the recorded limit).
- The harness clock-salts its payload (a crashed run leaves its torrent seeded) and removes its
  torrent; no golden pins a torrent hash. The demo seeds at POST (`raPost`); a seeding refusal
  ABORTS the post.
- `rsMediaStreamPlan` (B7) is separate from the fetch (`btAddMagnet` has no piece table): from
  `metadataReceived`, the front 8 pieces get deadlines 1 s apart; refusals are non-fatal, including
  without `btSetPieceDeadline`.

**Phase 4, DMs.**
- Intros seal to the PREKEY (a crypto_kx public published as `RSK1`, signed by the identity, named
  by the head's `prekeyTarget`), never to the ed25519 handle; `rsVerifyPrekey` before sealing. A
  recorded delta from spec 5.1.
- kx is anchored by `tools/emit-kx-anchor.py` (a REAL libsodium via ctypes). The lexically smaller
  lowercase-hex handle is the kx CLIENT; "my tx is your rx" is asserted from both ends.
- The recipient handle sits INSIDE the signed intro (third-party replay dies); the sender handle
  derives from the signing seed (a sender/signer mismatch is inexpressible). Frame and message kinds
  compare by BYTE, never `is`. Intro freshness (+-600 s) is the app's policy.
- The demo authenticates a peer by ciphertext the session accepts (the first failed pull drops it),
  runs ONE conversation at a time, and frees streams on every death path with `sxFreeStream` (no
  unload hook).
- D15 (2026-08-17): hang-up and Lock push one FINAL-tag message (`raDmPushClose`, a FILLER body
  never rendered; no other send sets final). The receiver prints "closed the conversation" and drops
  the peer. Verified statically; needs an OXT pass (never run on an engine).

**Phase 5, the call.**
- No library surface: SDP rides the DM kinds "O"/"A", one blob, sent once `dcGatheringState` is
  complete (non-trickle). STUN only, no TURN, by design (a symmetric-NAT pair fails visibly).
  Teardown on hang-up/Lock/close; the mandatory BARE `dcCleanup` at quit.
- Typing lane (spec 6.2, A.8):
  `dcCreateChannelEx(peer, "riptide-typing", "", true, 0, -1, false, -1)` is created BEFORE
  gathering so both channels ride one offer; absolute "1"/"0" state re-sent on a cadence with a
  local expiry; the callee routes channels BY LABEL. A lane refusal is non-fatal.
- B3 (2026-08-17): `raPollDelay` picks the pump tier every tick, never latched: about 33 ms while a
  dc call or enet mesh is live, about 250 ms otherwise (spec 10.1). `raExpire`, `raMediaPaint`,
  `raLanMediaPaint` and `raLanPaintDevices` stay behind a `kPaintMs` gate at 4 Hz. Verified
  statically; needs an OXT pass (never run on an engine).

**Phase 6, the LAN mesh.**
- Admission rides channel-0 MESSAGES (the `enConnect` rider is a u32 protocol tag, checked first).
  All your devices derive ONE LAN ed25519 keypair from subkey 3: it proves "I hold the master", and
  is NOT a per-device identity. The demo holds the master seed while unlocked.
- Domains are PREFIX-FREE 13-byte tags (trap 8): "riptide-lan-a" || nonce || name (admission),
  "riptide-lan-w" || responseSig || hostName (welcome), "riptide-lan-s" over the whole record, kind
  byte inside (sync). Nonces are fresh (`sxRandomBytes`); 0x5a*32 is the golden's only, and a stale
  response is asserted refused.
- NO per-handshake binder (the welcome verifies; it exchanges no key), so the hub relays records
  verbatim. Replay dies by apply semantics: strictly-increasing per-device draft seq, max-applied
  feed/read state, strictly-increasing presence tick. Every record is ABSOLUTE state.
- Presence is sent UNSEQUENCED (enet flag 2), a recorded delta from the spec (its tick makes it
  reorder-proof). Counters seed from `the seconds`. Sends go per-admitted-peer, never `enBroadcast`
  (a pre-drop stranger would get plaintext). Authenticated, NOT encrypted (the Devices footer says
  so). Drafts converge at about 1/s; an over-cap draft adopts state; NO read receipts.
- C6 (2026-08-17): receive state is keyed by DEVICE NAME (`tRec["name"]`, read after the verdict),
  never by enet peer: a joiner gets the whole hub-and-spoke mesh over ONE peer, and peer keying
  silently dropped records, mislabelled drafts and hid devices. `sLanPeerNames` drives disconnect
  drops. Two nodes never run the relay; the runbook's phase-6 step 8 is the third-device test.
  Verified statically; needs an OXT pass (never run on an engine).
- C6's key is the name's lowercase HEX (`raLanDevKey`, 2026-09-24), never the name string: the
  engine folds array-key case (suite engine note 2.7), so "Phone" and "phone", two devices on the
  wire, shared one seq slot and the lower clock-seeded counter was silently dropped. Lowercasing
  on purpose would merge them the same way; hex is one-to-one on the bytes and spelled in one
  case. `sLanPeerLabel` keeps the name for display. check-demo-boot drives both names through
  `raLanSyncReceive` and checks every per-device key set against the fold (the model's dicts do
  not fold, so "both applied" alone passed the old code); test-demo-boot seeds the old keying
  back. Verified statically + headless; needs an OXT pass (runbook phase-6 step 8's case-fold
  bullet).
- Channel 2 (2026-08-16): the media handoff is RSL1 "M", a signed channel-0 POINTER
  (info-hash + name + size) at the torrent rail; channel 2 stays dark (enet's 60000-byte budget).
  Strict lowercase hash, zeros refused. Honest limit: the bytes ride the torrent rail (the swarm
  sees your IP; an offline LAN may not find it). The offer is one slot and outlives the mesh.
- B4 (2026-08-23): "rtt N ms, loss P%" only on DIRECTLY-linked devices (`enPeerStatus`); a relayed
  device's row stays bare.

**Phase 7, the anon persona.**
- `rsPersonaAllows(pIsAnon, pTransport)` is pure policy: anon ONLY `onion`, public anything BUT
  `onion`, unknown refused for both. Nine transports:
  `onion,dht,torrent,rp1,enet,dc,feed,media,nostr`. The harness asserts the full truth table and the
  Anon card's guard panel is a live read; every transport branch routes through it.
- `rsAnonOnion` is offline-derivable and inverts back to the anon handle. BTXO (Model C) is reused
  from quickshare; `rsBtxoStreamStep` (A3, 2026-08-23) is the single-step receiver, caps ported from
  nocloud (name 1024, refused from the first 8 bytes; total 8 GiB; frame 65536).
- Sealed anon DMs (spec 8.3) add one handler, `rsAnonDmSeed` (subkey 200+n); the rest composes
  phase 4. The persona prekey is served over its ONION, never the DHT, and refuses the PUBLIC handle
  as author; the public identity cannot open persona mail.
- 8.2/8.3 serving: the library builds payloads (`rsAnonFeedPage`, `rsAnonPrekeyBody`,
  `rsAnonAcceptDm`); the demo owns the `oxh*` routes, wiring
  `oxSetPeerCallback "oxhPeer"` + `rsAnonCreateService` itself (`oxhServe` would mint a Tor key,
  wrong for a persona). GET `/prekey`: 264 hex chars. POST `/dm`: EXACTLY 632 (48 + 268 bytes, x2),
  refused before decode, one 400 "refused" for every failure. The feed page is a golden-pinned,
  HTML-escaped wire format from its own entries field, never the public feed. Handlers reply from
  locals built at publish time (they run from socket callbacks). Publish is two-step when tor is
  cold. The REPLY rail is deliberately unbuilt.
- A.9 profileMeta: publish (the display name's UTF-8 bytes, refusal non-fatal) and, since
  2026-08-23, the reader (`rsIngestBlob`, 1..64 bytes, a UTF-8 round trip in `raProfileLine`). D14:
  the spec 9.3 attestation was corrected, not built as runtime checks.

**Phase 8, the Nostr rail.**
- REACH, never a dependency: nothing in phase 8 sits on the path of phases 1-7. `hasNostr`,
  `canNostrSign` and `hasNostrRelay` fail separately; the boot self-check SKIPs the rail with an
  install line.
- The protocol is composed from `nx*`/`nxr*`, never re-implemented; riptide owns only the key, the
  bridge and the media convention (kind-1 notes with `r`-tag magnet URIs).
- The key is subkey 4 through a validity LADDER (SHA-256 re-hash, at most 8 rungs, then refuse);
  `rsNostrSeckeyFrom` takes a CANDIDATE so the untakeable branch is provable (all-zeros and the
  group order n are pinned).
- `RSN1` (276 bytes) is signed TWICE over one preimage (ed25519, and BIP-340 over its SHA-256),
  domain "riptide-nostr-b", magic inside the signed span; `rsNostrBridgeFromEvent` requires the
  record's nostrPub to BE the event author (the republish gate). A new rail gets a new SALT
  ("riptide-nostr"), never a new `RSH1` field. Publishing the bridge is always a click; nothing
  dials on open; NIP-42 is never auto-answered; inbound media is a click-only pointer.
- Nostr DMs are a SCOPE CUT: NIP-04 needs AES (absent from the suite); NIP-17 needs an ephemeral-key
  layer and a metadata analysis not yet done. `RIPTAPP1` is sealed under subkey 5 because a follow
  list IS the social graph (1 MiB cap, UTF-8 round-tripped).
- `rsPublishBridge` checks the seed/handle match ABOVE the session check: below it the check runs
  only where torrentxt is installed, and an assertion there passes for the wrong reason.

**The demo (the v11 UI, 2026-08-29).**
- A five-tab bar on every card (`raNavBar`/`raNavMark`; hilite script-managed, autoHilite off,
  re-asserted after every `go`; buttons share names across cards). Two `uiPanel` columns
  ("8,54,598,568" / "602,54,1192,568") created FIRST. `raGateIdentity` is affordance, not
  enforcement. The status line is the identity chip. `returnInField` acts only in one-line fields.
- A `kRaUiVersion` bump runs `raBuildReset` (deletes what `kRaScControls` + `kRaScRetired` name)
  before the builders; the registry constant sits ABOVE the kit block (lexical-position resolution).
- Watermarks persist (2026-09-09): the demo keeps `sHeadSeen` (handle -> highest accepted seq) in
  `RIPTAPP1`, and `raHeadAccepted` MUST call `raAppMark`, because `raAppSave` runs only when
  `sAppDirty`. check-demo-boot pins "a newer head marks dirty, a stale one does not".

## 4. Traps

1. **The demo is the LEAST-verified surface**: the suite selftest never opens it, and only
   check-demo-boot (a model) executes it. With no engine-proven example of a construct in the tree,
   say so in the label.
2. **Card navigation (OXT report 2026-08-15, 48 sites).** `go card "X" of me`,
   `field ... of card ... of me` and `card 1 of me` are WRONG, and the checker passes them: use
   `go to card "X"`, plain `field "X" of card "Y"`, and `set the name of this card to ...` right
   after `create card`. `send "raPoll" to me in N milliseconds` is correct.
3. **The pump runs from every card**, so EVERY control reference is card-qualified and
   existence-guarded (the `raFeedNote`/`raDmLog`/`raAnonLog` pattern); bare card-1 references in
   `raExpire`/`raMediaPaint` once killed the pump off-card (the 2026-08-14 review). Socket-callback
   route handlers too.
4. **`textDecode(x, "UTF-8")` is LOSSY (OBSERVED 2026-08-15).** It returns replacement characters
   and does not throw, so six parsers' try guards were inert. Validate with `rsBytesAreUtf8`:
   decode, re-encode, require identical bytes (an inner try stays for an engine that does throw).
5. **Delimiter leaks.** C10 (2026-08-17): `rsMediaCreate` left `itemDelimiter` "/" on 7 exits;
   restore around the NARROWEST span, not per exit (`rsAnonFeedPage`'s `lineDelimiter` too).
   `raAttach` (2026-08-14) and `rsPersonaAllows` (2026-08-29, benign only because comma is the
   default) leaked it as well. The demo's defensive re-set in `raHandleEvent` STAYS.
6. **A non-literal `constant kX = "a" & return & "b"`** kills compilation of the whole one-unit
   script (suite engine note 1.3; family checker check 22).
7. **`Chunk: no target found` at `openStack` (the first phase-8 card, 2026-08-29) was never
   diagnosed.** Ruled out by inspection: kit-call arity, `there is a card`, chunk-of-object
   expressions, engine note 1.7, `the target`, foreign calls outside a try. Suspects:
   `repeat for each key` over still-UNSET `sAppRelays`/`sNxRelayHandle`, and
   `nxrInit the long id of me` in `openStack` (NostrXT's demo calls it from `preOpenStack`). The
   re-land sidestepped it: `openStack` is byte-identical to the engine-proven fc1eeae body, relay
   defaults paint inside `raBuildNostrCard`, and `nxrInit` is lazy at the first Connect.
8. **Raw-concat signature domains must be PREFIX-FREE, not merely distinct (2026-09-09).**
   "riptide-lan" was a prefix of "riptide-lan-s", so a peer-chosen nonce starting "-s" made an
   admission signature byte-identical to a sync-record signature; check-script-vectors now checks
   every ordered pair for startswith (the Nostr salt/domain relation is harmless: the salt is
   length-delimited bencode). The `RSL1` magic did not bump, so pre- and post-2026-09-09 devices
   silently fail admission with each other.
9. **u64 bound.** `rsReadBEu64` returns empty past 2^53 and ALL THIRTEEN call sites refuse the
   record (f0c31e3 found `rsBtxoParseHeader`'s total and `rsParseBridge`'s seq and timestamp
   missed). The BTXO miss INVERTED the 8 GiB cap, since `empty > 8589934592` is false: a failure
   value changed from a wrong number to empty makes downstream `>` guards never fire, so a partial
   sweep is worse than none. check-script-vectors holds a monotonic table (1 KiB and exactly 8 GiB
   accepted; 8 GiB+1, 2^53, 2^53+1, 2^64-1 refused). The bound is decided on the two u32 HALVES
   (hi < 2^21, or hi = 2^21 and lo = 0; 2026-09-24): the quotient form
   `tHi > (2^53 - tLo) / 2^32` passed that table under IEEE and let 2^53 + 1 through on an engine
   (ledger, 2026-09-24; cause INFERRED: a comparison tolerance or a ~15-digit round trip). Decide a
   wide-integer bound on exact integers that differ by at least 1 at a modest magnitude, never
   against a quotient. Tier 1c replays the table under three comparison models (fixture: the old
   line, which each must accept) and refuses any library comparison against a quotient; the
   harness prints a four-comparison probe that tells the candidate causes apart.
10. **A dead write is invisible to every other gate** (2026-09-08): `raAppSave` emitted `headseq`
    and `raAppLoad` never read it; check-demo-boot round-trips it now. Any value worth persisting is
    worth round-tripping in a test.
11. **The static gate does not follow `\` continuations in `if` headers** (read as an unterminated
    opener). Hoist the condition into a local.
12. **Two Checker classes with DIFFERENT signatures**: check-script-vectors' `ck(label, got, want)`
    versus check-demo-boot's `(label, ok_boolean, detail)`. The wrong shape passes VACUOUSLY
    (2026-09-09).
13. **check-script-vectors rewrites three spellings** outside the interpreter's subset
    (`the number of X in Y`, the one-line `if ... then STMT`, binaryEncode/div/mod); each is named,
    counted and must fire. A wrong ANSWER earns a fix to the shared interpreter, a missing SPELLING
    a rewrite. Its 2026-08-29 first-run findings (negative chunk ranges in the interpreter, the
    oracle's `_verify_ed25519` crash on a tampered R, the `rsPersonaAllows` leak) were mostly the
    tool's own: suspect the probe first.
14. **check-demo-boot.py is also driven by coinxt's, nocloud's and holde-em's gates**: on any path a
    boot walks, use the compiled-regex helpers `_rxi`/`_rx` (2026-09-11). Model fidelity: `the name`
    of a control is type-prefixed (`button "x"`); only `the short name` is bare (2026-08-31).
    `put ... into URL` answers through `the result` (2026-09-24): empty when the write landed, and the
    planted text, with nothing written, for a path in `World.url_write_refuse` (coinxt's save guards
    are held that way). An unplanted missing parent folder is still CREATED, which is looser than the
    engine; a gate that needs that refusal plants it.
15. **The demo carries TWO socket libraries** (onionxt, nostrxt's relay layer). The embed tool drops
    both libraries' `socketError`/`socketClosed`/`socketTimeout` wrappers; the demo's own three call
    `oxSocketError`/`nxrSocketError` (and kin), then `pass`. Keep that `pass`: swallowing a socket
    message another library waits for is a HANG no gate sees.

## 5. Engine evidence ledger

Newest last. "Maintainer's account" is a dated report with no result text or platform captured.

| Date | Engine / platform | What ran | Result |
|---|---|---|---|
| 2026-08-12 | OXT, Windows x64; suite paste | riptide phase 1 (`rs1rsSelfTest`), then phases 1-2 | 89/89, then 133/133, 0 skipped, every probe true including hasSha3: the sealed key file, KDF tree, identity -> handle -> onion, `RSH1`/`RSP1`, the post chain, real-session puts, accepted lookups, the synthetic ingest verifiers |
| 2026-08-13 | two machines (maintainer's account) | phase-2 propagation through the demo | PASS: identities on both sides, feeds both directions through the real DHT, every rendered post ingest-verified; the first real `btPoll` DHT events into the ingest verifiers |
| 2026-08-15 | OXT, platform not recorded; suite paste | phase 4-7 compute: DM secretstream round trip, LAN admit/refuse, guard truth table, BTXO framing, the cross-member seam | green except 3 malformed-UTF-8 checks, which exposed the lossy `textDecode` (trap 4) |
| 2026-08-15 | OXT (maintainer's report) | the demo's multi-card conversion | `... of me` card references rejected, 48 sites (trap 2); fixed the same day |
| 2026-08-15 | two machines (maintainer's account) | phase 3 media; phase 4 DMs | PASS: a follower fetched and PLAYED an attached video "near instantly" (head publish -> fetch -> chain walk -> authorSig verify -> media info-hash -> swarm join -> playback); DMs both ways (sealed `RSI1` intro, deterministic-role crypto_kx, pairwise secretstream over rp1, no server). Reaching the Messages card confirmed the `go to card` fix |
| 2026-08-20 | OXT, Windows; suite paste 1981/0/1 | riptide 0.9.0 compute additions | riptide 338 passed / 0 failed / 2 skipped: sync records D/F/P/M, the 8.2/8.3 serving seams (`rsAnonFeedPage`, `rsAnonPrekeyBody`, `rsAnonAcceptDm` + 5 refusal legs), all three `rsBytesAreUtf8` checks. The 2 skips are the live-tor anon-service legs |
| 2026-08-24 | OXT 9.6.3, Windows x86_64; suite paste 2373/0/3 | riptide including the 2026-08-23 batch | 391/391, including the kind-C chunked-post rail and the BTXO receive path (`rsBtxoStreamStep`) |
| 2026-08-27 | two machines (maintainer's account) | phase-3 mid-download playback | MEASURED NEGATIVE as then wired: Play unlocked on file existence (a hollow file at metadata time), so the player got about 0% real data. Fixed the same day (`raMediaFrontReady`); a faststart re-run is owed |
| 2026-08-29 | OXT (maintainer's account) | the first phase-8 card landing | FAIL: broke `openStack` for the whole app (`Chunk: no target found`, plus a non-literal-constant compile kill); reverted |
| 2026-08-29 | OXT (maintainer's account) | the re-landed five-card stack | reported working: `openStack` completes with the Nostr card in place |
| 2026-08-29 | OXT (maintainer's pasted record) | the v11 UI boot self-check | 9 passed / 1 failed / 0 skipped, all five cards built, every capability true. The FAIL was the carried self-check's own cross-card `there is` defect (suite engine note 5.6; this record is its primary evidence), fixed in the master the same day |
| 2026-09-24 | OXT, Win32; the suite paste (board D-23) | riptide's folded harness, its first engine run since phase 8 | 487 passed, 2 failed, 2 skipped (the skips: the live-tor legs). The DM and live-feed sections passed against the core's session. FAIL 1: the capability check still counted SEVEN probe keys, and phase 8 made it ten (a stale check, not a library defect). FAIL 2: "a seq of 2^53 + 1 is REFUSED" - the engine ACCEPTED it through `rsReadBEu64`'s quotient bound, which pure IEEE, and so every headless gate, refuses (OBSERVED; the cause INFERRED, trap 9). Both fixed the same day: the check asserts the exact ten-key set, the bound is decided on the u32 halves. Verified statically; needs an OXT re-pass |

Caveats that travel with the ledger:
- The 2026-09-09 tag change (trap 8) re-pinned the admission response and welcome goldens, so the
  engine-green admission and welcome BYTES are superseded; the sync-record goldens ("riptide-lan-s")
  are unchanged.
- Harness sections added after 2026-08-24 (Nostr, app state, the watermarks, the u64 bound, the 996
  cap) first met an engine on 2026-09-24 (ledger); of that run's two FAILs, only the u64 bound's
  2^53 + 1 row fell in them, fixed since. What the 2026-09-24 fixes changed (the ten-key check,
  the halves bound and exactness check, the numeric probe line) is static + headless only.
- Headless on 2026-09-23: check-script-vectors 84 checks (1 skip), check-demo-boot 44 checks. Run
  the gates for current counts.

## 6. Status

All eight spec phases are built; phases 1-4 are done on two machines. These are the labels the
suite's `docs/OXT-PASS-RUNBOOK.md` rows flip; open work lives in the suite's `docs/WORK-PLAN.md`.

| Phase | Label |
|---|---|
| 1-2, identity + live feed | DONE: engine 2026-08-12, two machines 2026-08-13 |
| 3, media | DONE 2026-08-15, two machines. Mid-download playback measured negative 2026-08-27 and fixed; the faststart re-run is owed |
| 4, DMs | DONE 2026-08-15, two machines; the D15 clean close (2026-08-17) post-dates that pass and has not run |
| 5, the call + typing lane | built, never run. Verified statically; needs an OXT pass |
| 6, LAN mesh | compute engine-green 2026-08-20, admission and welcome bytes re-pinned since (caveat above). Owed: the live mesh (draft-appears criterion, media handoff, third device) |
| 7, anon persona + 8.2/8.3 serving | compute engine-green 2026-08-15 and 2026-08-20; needs an OXT + live-Tor pass. The harness's 2 anon-service SKIPs are exactly that leg |
| 8, Nostr bridge + `RIPTAPP1` (built 2026-08-29) | library verified statically and executed headlessly (rule 7a); needs an OXT + live-relay pass. The v11 label: verified statically + headless boot + an engine boot record with one since-fixed check defect; needs an OXT re-pass, whose boot record should read 10 passed / 0 failed |

## 7. Gates and suite integration

`bash tools/run-gates.sh` is the ONE gate list (the suite's `build-all.sh` delegates to it): the
static gate, docs style, the `tests/*golden*.py` glob, `check-selftest-vectors.py`,
`check-script-vectors.py`, `test-demo-boot.py` then `check-demo-boot.py` (minutes),
`export-protocol-vectors.py --check`. A missing `../nostrxt` (`lcs-interp.py`, `nostr_reference.py`)
FAILS the gates; a missing `../coinxt` skips tier 2 unless `XTALK_REQUIRE_SIBLINGS=1`.

In the suite, beyond this member's gates:
- **The fold**: the harness folds as member `riptide` (prefix `rs1`, entry `rsSelfTest`, merged via
  `stMergeReturned`), so its report's first line must stay exactly "N passed, M failed", the skip
  count on its own line. The library embeds verbatim as a script layer; the coverage gate fails on
  an unexercised public `rs*`. A script-layer or harness edit is not done until
  `python3 tools/build-suite-selftest.py` has rebuilt the paste.
- **The demo's embeds**: five libraries via the suite's `tools/sync-demo-embeds.py`, in the order
  nostrxt, nostr-relay, riptide, onionxt, onion-httpd (never edit inside the sentinels). A `src/`
  edit is not done until it has been re-run at the suite root; riptide's own tools cannot see that
  drift. The demo is never folded into the paste.
