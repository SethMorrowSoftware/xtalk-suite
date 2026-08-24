# CLAUDE.md - riptide/

Guidance for Claude Code when working in this directory. Read
`../docs/RIPTIDE-SOCIAL-SPEC.md` FIRST: it is the full design (the five
rails, the identity architecture, the security model, the phased roadmap),
and this directory implements it phase by phase. This file records only
what is operational and riptide-specific. The root `CLAUDE.md` and the
member files it points to still apply; when they conflict, this file wins
inside `riptide/`.


> **Engine BEHAVIOUR - as opposed to the conventions here - is collected in
> [`docs/OXT-ENGINE-NOTES.md`](../docs/OXT-ENGINE-NOTES.md)**, with the verbatim
> symptom, what each one broke, and the gate (if any) that now holds it. Keep
> member-specific gotchas in this file; put anything the ENGINE does there, so
> there is one authoritative list instead of ten that drift.

## What this is

The suite capstone app, pure LiveCodeScript over the installed extension
surfaces. It is deliberately structured like a member (src/, tests/,
tools/, docs/) so the repository's gate machinery walks it unchanged, but
it is an APP, not an extension: nothing here is compiled, nothing here
adds native surface, and `rs*` never becomes a library other members may
call.

**All seven spec phases are BUILT, and phases 1-4 are DONE on two
machines, done-criteria included** (library 0.11.0; 90 public handlers -
83/83 exercised by the suite paste as last generated, and the seven
2026-08-23 handlers carry their harness sections in
tests/riptide-selftest.livecodescript, entering the 90/90 ratchet the
moment tools/build-suite-selftest.py regenerates the paste):

- **Phases 1-2 (identity + the live feed): DONE.** Engine-passed
  2026-08-12; the two-machine propagation criterion closed 2026-08-13
  (see rule 8).
- **Phase 3 (media): DONE 2026-08-15**, two machines - a follower fetched
  and played an attached video, which necessarily exercised head publish
  -> fetch -> chain walk -> authorSig verify -> media info-hash -> swarm
  join -> playback. The mid-download nuance (playback visibly below 100%)
  stays unmeasured; the runbook scripts it.
- **Phase 4 (DMs): DONE 2026-08-15**, two machines, chat both ways - the
  sealed RSI1 intro, the deterministic-role crypto_kx session, and the
  pairwise secretstream over rp1 all carried real traffic with no server.
- **Phase 5 (live sessions): BUILT, awaiting its pass.** No library
  surface (SDP rides the phase-4 O/A kinds); the demo wiring landed
  2026-08-15 - a Call button on the Messages card, one-blob non-trickle
  signalling (ship the local SDP when dcGatheringState hits complete),
  libdatachannel auto-negotiation on both legs, a visible CONNECTED/via
  line, teardown on hang-up/Lock/close, the mandatory BARE dcCleanup at
  quit. STUN only, no TURN, deliberately - a symmetric-NAT pair fails
  visibly instead of relaying silently. **The spec-6.2 TYPING LANE is
  built too** (2026-08-15, closing remaining-work A.8): a second dc
  channel (unordered, maxRetransmits 0) opened at call setup, absolute
  "1"/"0" state debounced on the poll timer - demo wiring only, no
  library surface (the DTLS session the DM-signalled SDP authenticated
  scopes it; see the sync-payload as-built section below).
- **Phase 6 (LAN mesh): BUILT, awaiting its pass.** The `rsLan*`
  admission layer plus the RSL1 "W" WELCOME (2026-08-15, mutual auth:
  the host signs over the joiner's own response signature, so the joiner
  verifies the host shares the master and gets its positive verdict;
  golden-pinned, rogue-host and cross-handshake-replay refusals in the
  harness). The admission COMPUTE ran engine-green in the suite selftest
  2026-08-15. **The SYNC PAYLOAD landed later the same day** (closing
  remaining-work A.7): three new RSL1 record kinds over the admitted
  mesh - "D" draft sync, "F" feed-seq/read-receipt state, "P"
  presence/typing - signed under the shared LAN key with a distinct
  domain, golden-pinned, refusals harness-proven offline, plus the
  demo's Devices-card wiring (a debounced draft field, per-device
  presence, verified drafts rendered with their origin, strangers
  refused and logged; the receive state was keyed by the enet PEER until
  2026-08-17 - see the C6 record below). **Channel 2 SETTLED 2026-08-16**: bulk media
  handoff is a fourth RSL1 kind, "M", on CHANNEL 0 - a signed POINTER
  (info-hash + file name + size) at the phase-3 torrent path - and
  channel 2 stays reserved, dark (the decision record below). **The SYNC
  PAYLOAD's compute half ran engine-green 2026-08-20** (Windows, in the
  suite paste, riptide 338/0/2): the "D"/"F"/"P"/"M" record bytes against
  their goldens, every stranger/tamper/truncation refusal, and the three
  malformed-UTF-8 checks that came back RED on 2026-08-15 - all now
  "refused, not thrown". So this layer is no longer "verified
  statically". What remains is the live two-machine mesh pass - the full
  draft-appears done-criterion plus the media handoff.
- **Phase 7 (anon persona): BUILT, awaiting OXT + live-Tor.** The
  `rsAnon*` layer, BTXO framing, and `rsPersonaAllows` (the pure-policy
  §9.3 guard, the app's highest-severity invariant) - compute engine-green
  2026-08-15. The sealed anon-DM CRYPTO (spec 8.3) closed the same day
  via `rsAnonDmSeed` (subkey 200+n), and its ONION TRANSPORT is now
  BUILT too (2026-08-15, later the same day): the pure serving seams
  (`rsAnonFeedPage` / `rsAnonPrekeyBody` / `rsAnonAcceptDm`,
  golden-pinned, harness-proven offline) plus the demo's onion-httpd
  wiring (the / page, GET /prekey, POST /dm). **The serving seams' compute
  half ran engine-green 2026-08-20** (Windows, in the suite paste): the
  anon feed page byte-for-byte with its entries HTML-escaped, the GET
  /prekey body decoding to a prekey that verifies under the ANON handle,
  and `rsAnonAcceptDm` accepting the hex-posted sealed intro plus all five
  of its refusal legs. Not "verified statically" any more; the live
  done-criterion remains (a persona reachable and served over Tor with
  zero `bt*` calls in a trace), and the harness's two anon-service SKIPs
  are exactly that leg.

What remains, in one line: the live passes for 5 (the call + typing
lane), 6 (the mesh, through the draft-appears criterion), and 7 (tor,
now including its built 8.2/8.3 serving) - all scripted in
docs/two-machine-runbook.md.

## The rules that bind this directory

1. **The oracle comes first.** `tools/riptide_reference.py` was written
   before the script layer and anchors to vectors from OUTSIDE this
   directory (sodiumxt C KATs, the cross-project BEP44 conformance vector,
   a real published onion). Any new derived value gets its oracle
   derivation and its golden pin BEFORE the script implementation; a
   vector captured from the script's own output proves nothing.
2. **One set of bytes, three holders.** Every golden vector lives in the
   oracle (derivation), `tests/riptide_golden_test.py` (inline literal),
   and the harness constants (`tests/riptide-selftest.livecodescript`).
   `tools/check-selftest-vectors.py` re-derives the harness copy with an
   honest coverage count: it FAILS on a constant that is neither
   re-derived nor listed as an input with a written reason, and on a
   stale input entry. Never hand-edit a golden constant; regenerate from
   `python3 tools/riptide_reference.py`.
3. **Wire formats bump their magic.** `RIPTKEY1`, `RSH1`, `RSP1`: any
   framing change mints a new magic and updates both build and parse plus
   all three vector holders in one change. Never a silent fix.
4. **Caps refuse, never truncate**, on build AND parse, and a parse is
   strict to the byte (exact total length; trailing bytes are refused).
5. **Every foreign call sits in a try.** sx*/cx*/ox* failures throw;
   no rs* handler may ever throw. Functions return empty (or false) on
   failure and record the reason for `rsLastError()`.
6. **Probe, never assume** (`rsProbeCapabilities`). SodiumXT is the one
   hard dependency. A missing optional extension disables exactly its
   feature with a clear "install org.openxtalk.library.X" story and
   never regresses another (the spec's section 3.4 matrix).
7. **The static gate is law**: `python3 tools/check-livecodescript.py`
   (the onionxt/coinxt lineage; it walks this whole directory). The
   repo-wide `tools/check-handler-calls.py` knows the `rs` prefix, so
   every `rs*` call site is checked for existence and arity too. House
   style for prose, declared here because this member carries the gate:
   no em-dashes (hyphens, commas, colons, parentheses) and no curly
   quotes, enforced by `python3 tools/check-docs-style.py` (byte-identical
   with sodiumxt, onionxt and coinxt under `check-checker-drift.py`).
8. **The honesty convention.** "Verified statically; needs an OXT pass"
   until a recorded run says otherwise; anonymity claims additionally
   need a live-Tor pass. Flip labels only on a recorded engine result,
   members first, root README last (the runbook's rule). **Phases 1 and 2 had
   that pass on 2026-08-12**, folded into the suite harness: 133/133, 0
   skipped, every probe true including hasSha3. The sealed key file, KDF tree,
   identity -> handle -> onion, RSH1/RSP1 formats, post chain, phase-2 puts,
   accepted lookups, and synthetic ingest verifiers all ran green on a real
   engine. **The full phase-2 done-criterion closed 2026-08-13**: the
   maintainer ran `examples/riptide-social.livecodescript` on TWO machines -
   identities created on both sides, feeds published and received in BOTH
   directions through the real DHT. The stack renders a post only after
   `rsIngestHead`/`rsIngestPost` verify it, so a received feed is a verified
   chain walk; this was also the first run to drive REAL btPoll DHT events
   into the ingest verifiers (previously synthetic-only). Result text and
   environments were not captured with the report; the record is the
   maintainer's account, dated. The phase-3 media layer followed the same
   arc: built 2026-08-14, then **PASSED on two machines 2026-08-15** (a
   follower fetched and played an attached video); the one nuance still
   unmeasured is playback starting visibly mid-download, which the runbook
   scripts.

## Things learned building phase 1 (do not relearn)

- **The KDF context is 8 bytes exactly** (`crypto_kdf_CONTEXTBYTES`):
  `"riptide"` + one NUL, built by `rsKdfContext()` at runtime because an
  xTalk constant cannot hold a NUL byte. sxKdfDerive's subkey id is a
  DECIMAL STRING, and its semantics are BLAKE2b with the id as LE64 salt
  and the context as the personal field (pinned against the sodiumxt C
  KAT at oracle import).
- **The onion self-computation has two SHA3 providers, sx first.**
  Building phase 1 surfaced the gap (sodiumxt had no SHA-3; riptide
  composed coinxt's `cxSha3_256`), and closing it properly meant shipping
  `sxSha3_256` in SodiumXT ABI 7 (2026-08-11) rather than leaving the
  trust root without its own hash. `rsSha3` tries `sxSha3_256` then
  `cxSha3_256`; both are the same vendored FIPS-202 code, and the golden
  vectors pin the output, not the provider. The verify direction
  (`rsVerifyOnionClaim`, via `oxPublicKeyFromAddress`) needs no SHA-3.
  onionxt's `oxAddressFromPublicKey` now works against SodiumXT ABI 7+,
  but riptide keeps its own assembly (probe-gated, dual-provider) so the
  app degrades one provider at a time instead of all at once.
- **The handle equals btDhtKeypair's publicKey** for the same seed
  (tests/cross-member-test.py pins sodiumxt and libtorrent to one
  derivation), which is why phase 1 derives it via
  `sxSignKeypairFromSeed` only and the identity secret never enters
  torrentxt.
- **The static gate does not follow `\` continuations in `if` headers.**
  An `if` whose condition wraps across a continuation line is read as an
  unterminated opener. Hoist the condition into a local instead.
- **Immutable DHT targets are re-derivable offline**: target = SHA-1 of
  the bencoded value, and the engine has `sha1Digest`, so the harness
  proves the post chain's targets without a session.
- **binaryEncode("n"/"N"/"NN") is the family's big-endian discipline**
  (the BTXO pattern); u64 splits via `div`/`mod 4294967296`. The base32
  encoder masks its accumulator to the pending bits each step (the
  onionxt discipline) so nothing outgrows exact double precision.

## Things decided building phase 2 (do not re-litigate)

- **The library never owns a session.** TorrentXT allows one per process
  and the APP's dispatcher polls it, so every live handler takes
  `pSession` and validates every OTHER input first - which is what lets
  the refusal paths run (and be tested) with no torrentxt installed.
- **One seq, one source of truth.** `rsPublishHead` reads the BEP44 seq
  out of the head's own bytes (`rsParseHead`) rather than taking a second
  argument that could skew, and `rsIngestHead` refuses an event whose
  BEP44 seq disagrees with the embedded one.
- **The canonical BEP44 buffer is rebuilt in pure script**
  (`rsBep44SignBuf`) rather than borrowed from `btDhtBep44SignBuf`, so
  ingest verification works with no torrentxt; the suite harness
  cross-checks the two implementations and `btDhtPutSigned` accepting the
  script-assembled buffer's signature is the deeper proof (libtorrent
  re-verifies before queueing).
- **Ingest trusts arithmetic, not the transport.** libtorrent already
  verifies a mutable item's signature on receipt; `rsIngestHead` verifies
  it AGAIN in SodiumXT, and `rsIngestPost` recomputes the content address
  before believing a byte. Where a string compare could fold case (`is`
  on the salt), the rebuilt-canonical-buffer signature check backstops it
  fail-closed.
- **`rsPublishImmutable` compares libtorrent's returned target against
  its own recomputation** and refuses a mismatch loudly - two SHA-1s over
  one bencoded value disagreeing means someone is not hashing what they
  claim, and shrugging would publish unfindable posts.
- **The harness's session acquisition mirrors torrent-selftest's**: start
  into a temporary, commit only on success, never stop it at the end, and
  `tools/build-suite-selftest.py` carries a riptide rewrite that aliases
  the folded copy to the core's session (the bt1 pattern; a second
  btStartSession would be refused and the live section would SKIP green).

## Things decided building phase 3 (do not re-litigate)

- **Media attachments are SINGLE FILES.** `rsMediaCreate` refuses anything
  that is not a file: a photo or a video has one obvious thing to play,
  a folder does not, and folder shares are a file-sharing app's job
  (quickshare). The torrent is TRACKERLESS (`btCreateTorrent(path, 0, 0,
  "")`) - DHT-only, like everything else riptide does.
- **Seed in place; return the hash, not the handle.** The seed's save path
  is the file's own parent folder, so libtorrent finds the payload where
  it already sits and no copy is made. The function returns the 40-hex
  info-hash because that is what posts carry and what followers fetch;
  `btFindTorrent(pSession, tHash)` recovers the handle whenever the app
  wants one, which is also exactly how `rsMediaFetch` is idempotent.
- **`rsMediaFetch` finds before it adds.** A re-click, a restart's
  re-fetch, or fetching your own seed all land on the `btFindTorrent`
  path and return the live handle instead of a duplicate-add error - and
  the sequential flag is applied on BOTH paths, because the caller asked
  for playback now, not only on first contact. A failed
  `btSetSequentialDownload` fails the call but deliberately leaves the
  torrent added: download progress is never thrown away over a flag, and
  the retry lands on the find path and re-applies.
- **`rsMediaStatus` takes the torrent handle, not the session.** The
  snapshot is per-torrent (`btTorrentStatus` + the first file's on-disk
  path and per-file progress from `btFileList`); demanding a session
  argument it never used would be dishonest API. filePath/fileSize/
  fileProgress stay empty until metadata arrives, so "filePath is empty"
  doubles as the not-openable-yet probe; with a sequential fetch the file
  is openable long before completion, which IS the mid-download play.
- **The harness salts its payload with the clock.** A crashed run leaves
  its torrent in the never-stopped session; fixed payload bytes would make
  the next run's add collide with that leftover. Time-salted bytes give
  every run a fresh info-hash, and the section removes its torrent at the
  end (`btRemoveTorrent`, keep files) so a clean run leaves a clean
  session. No golden vector pins the hash - a torrent's info dict embeds
  the file name and piece hashes, and pinning that is a torrent-format
  oracle this repo does not need.
- **The demo attaches at click, seeds at POST.** The picker only records
  the path; `rsMediaCreate` runs inside `raPost`, where the session is
  guaranteed, and a refusal ABORTS the post - a published post must never
  name a hash nobody can fetch. The strip's one button is two-mooded
  (Fetch until the on-disk file exists for the field's hash, then Play)
  and hands the file to the system player mid-download on purpose.

## Things decided building phase 4 (do not re-litigate)

- **Intros seal to the PREKEY, not the handle.** `sxSeal` takes a
  curve25519 public key; the ed25519 handle is not one, and sodiumxt
  ships no conversion handler. So first contact needs the recipient's
  crypto_kx public - which is exactly what the head's `prekeyTarget`
  publishes, as an RSK1 record SIGNED by the identity key. The seal
  target is therefore provable before anything is sealed to it
  (`rsVerifyPrekey`), and a swapped prekey is a refusal, not a readable
  first message. This is a deliberate delta from the spec section 5.1
  sketch, recorded there too.
- **kx facts are anchored, not remembered.** `tools/emit-kx-anchor.py`
  loads a REAL libsodium via ctypes and prints what crypto_kx returns for
  the oracle's fixed inputs; the oracle's pure-Python X25519/crypto_kx
  self-checks against that output (provenance in both files). A crypto
  constant typed from memory is exactly what rule 1 exists to refuse.
- **Roles are decided by handle order.** The lexically smaller handle
  (lowercase hex = raw byte order, the roomId discipline) is the kx
  CLIENT. Both sides derive the same session with no negotiation, and
  `my tx is your rx` is asserted from BOTH ends in the harness.
- **The recipient handle lives INSIDE the signed intro.** Replaying a
  sealed intro to a third party dies on the recipient check, and a
  sender/signer mismatch cannot be expressed because `rsBuildIntro`
  derives the sender handle from the signing seed rather than taking it
  as an argument.
- **Frame and message kinds compare by BYTE, not by `is`.** `is` folds
  case, and an unsigned transport frame gets no signature backstop, so
  "i" is refused where "I" is meant (the coinxt canonical-form lesson,
  applied at build AND parse).
- **The demo authenticates peers by what only they can do.** A bystander
  in the inbox swarm can see sealed intros (it cannot open them) and can
  even send a fake stream header; what it can NEVER do is produce a
  ciphertext the derived session accepts, so the first failed pull drops
  the peer. The compose box binds to a peer at channel-open and unbinds
  on that failure. ONE conversation at a time, loudly documented - the
  library supports many; the demo optimizes for a two-machine pass.
- **Streams are freed everywhere they can die** (sodiumxt has no unload
  hook): per-peer teardown, lock, and closeStack all run the idempotent
  `sxFreeStream` path.

## Things decided building phase 6 (do not re-litigate)

- **The admission proof is a MESSAGE, not connect data.** enet's
  `enConnect` rider is a u32 (a protocol tag), not a byte buffer, so the
  RSL1 challenge/response ride channel-0 messages. The rider still earns
  its keep: the host refuses a wrong protocol tag before spending a
  challenge on it.
- **One shared keypair, not per-device identity.** All your devices
  derive the SAME ed25519 keypair from the LAN subkey, so the signature
  proves "I hold the master," which is exactly the device-mesh trust
  question. It is deliberately NOT a per-device identity - that would be
  a different feature (and a different spec).
- **The signature binds the nonce AND the name.** `"riptide-lan" ||
  nonce || name`: the nonce (fresh per challenge, from `sxRandomBytes`)
  stops a replayed response, and the name stops a captured signature
  being re-presented under a different device name. The harness proves
  both - a response verifies against its own nonce/name and fails against
  a different one.
- **The nonce anchor is fixed for the golden only.** The oracle pins a
  `0x5a * 32` nonce so the challenge and its signature are reproducible;
  a real host always uses `sxRandomBytes`, and "a fresh nonce refuses a
  stale response" is a harness check, not just a comment.
- **The demo retains the master while unlocked.** The LAN and anon rails
  need subkeys the identity/DM seeds cannot give, so the stack keeps the
  master seed in memory between unlock and Lock/close (the spec's
  one-keyring pattern), cleared on both. The honesty caveat about
  unlocked engine memory already covers it.

## Things decided building the phase-6 sync payload + A.8 typing (2026-08-15; do not re-litigate)

- **Sync records sign under the SHARED LAN KEY with a distinct domain,
  and there is deliberately NO per-handshake session binder.** The
  design question was "what key material does the welcome leave each
  side?", and the honest answer is NONE that is fresh: the welcome is
  mutual signature VERIFICATION, not a key exchange, so the only secret
  both sides hold afterwards is the master-derived LAN ed25519 keypair
  itself. Deriving a per-handshake MAC key from that seed would feed
  one seed to two cipher schemes (the exact reason subkey 2 is separate
  from subkey 1), and binding records to a handshake would break the
  hub-and-spoke RELAY - a record the host forwards verbatim must verify
  identically at every admitted peer. So: ed25519 under the shared key,
  domain "riptide-lan-s" (admission signs "riptide-lan", the welcome
  "riptide-lan-w"), over the WHOLE record body with the kind byte
  inside the signed span. Replay is neutralized where it matters by
  each record's APPLY semantics - drafts by strictly-increasing
  per-device seq, feed/read state by max-apply, presence by
  strictly-increasing tick - plus admission gating at the transport.
- **Every record is ABSOLUTE state, never a delta.** The draft record
  carries the whole current text (empty = cleared), feed state carries
  the latest seq, presence carries the current flag - so any record can
  be dropped, duplicated, or reordered and the next one repairs it.
  That is what makes channel 1's flag-2 send honest, and it is also why
  the demo re-asserts presence every second instead of sending edges.
- **Presence is sent UNSEQUENCED (flag 2), a recorded delta from the
  spec's "unreliable-sequenced".** The record carries its own monotonic
  tick, so it is reorder-proof without enet's sequencing; taking flag
  1's sequencing would only mask ordering bugs the record must survive
  anyway. The spec's section-7 as-built note records the same delta.
- **The counters seed from the clock, not zero.** A leave-and-rejoin
  (or restart) must keep a device's seq/tick moving strictly forward
  past anything a receiver applied for an earlier session; `the
  seconds` gives that for free (the phase-3 clock-salt precedent). The
  receiver additionally drops a device's tracking when the LINK that fed
  it goes away, so even a clock step backwards only costs a stale-looking
  first record. (Written as "drops per-peer tracking with the enet peer",
  which is what the demo did and was the C6 defect; the state is keyed by
  DEVICE now and the link only says which entries to drop.)
- **Sync sends go per-admitted-peer, never enBroadcast.** A broadcast
  would also reach a connected-but-unadmitted stranger in its pre-drop
  window, and drafts are plaintext. The host relays verified records to
  the other admitted peers (bytes intact - the no-binder choice is what
  makes that sound); a two-device pass never exercises the relay, but
  it keeps a three-device mesh from silently not syncing. **That last
  clause was half true and the half it got wrong cost a defect** - the
  host relayed correctly, but until 2026-08-17 the RECEIVER keyed every
  relayed record by the enet peer it arrived over, which on a joiner is
  one peer for the whole mesh. See the C6 record below.
- **Authenticated, NOT encrypted, and the UI says so.** A LAN observer
  reads draft plaintext; the spec's section 7 is admission-only by
  design, and encrypting would need a new traffic subkey (a future spec
  row, not a quiet addition). The Devices-card footer carries the
  caveat.
- **Draft edits debounce on the poll timer and CONVERGE.** The tick
  compares the field against the last state actually broadcast and
  re-sends until they match (at most ~1/s), so intermediate states may
  be skipped but the final state cannot be lost - and a refused build
  (an over-cap draft) adopts the state to avoid logging every tick,
  retrying on the next edit.
- **The demo publishes NO read receipts.** The record carries the
  receipt half (library-complete, harness-covered); the demo's
  one-conversation DM rail keeps no read state to publish, so it sends
  the none spelling and logs any receipt it receives. Inventing read
  semantics for the demo would have been dishonest wiring.
- **A.8 disposition: BUILT, as demo wiring on the dc call.** Spec 6.2's
  typing lane is genuinely separate from the LAN rail's (section 7
  channel 1 covers your OWN devices; 6.2 covers the two call peers),
  and the call plumbing made it modest: a second channel via
  `dcCreateChannelEx(peer, "riptide-typing", "", true, 0, -1, false,
  -1)` created before gathering so both channels ride the one offer,
  absolute "1"/"0" state re-sent on a cadence, a local expiry so a
  dropped "0" cannot stick, and the callee routing incoming channels BY
  LABEL (arrival order is not a protocol). No library surface and no
  record format: the DTLS session the DM-signalled SDP authenticated
  already scopes and authenticates the lane, and a one-byte absolute
  state has nothing to parse. A lane refusal is non-fatal - the call
  continues without it, logged.

## Things decided settling channel 2 - the media handoff (2026-08-16; do not re-litigate)

- **Channel 2 gets NO new wire; the handoff is a channel-0 POINTER.**
  The question was "does bulk media handoff need a chunked channel-2
  lane, or a record that points at the media rail riptide already
  has?", and the tree's own laws answer it. enet's 60000-byte packet
  budget is the suite's message/bulk seam ("when a payload stops being
  a message it becomes a torrent" - enetxt's README), and a draft's
  media - a photo, a video - essentially never fits it. A chunked enet
  lane would reimplement libtorrent's per-piece integrity, resume, and
  backpressure with none of its proof, while the phase-3 machinery
  (rsMediaCreate seeds in place; rsMediaFetch finds-before-adds and
  co-seeds) is the ONE rail of this app already proven end to end on
  two machines - on one LAN, near instantly, which is exactly the
  handoff's shape. So: the RSL1 "M" record (channel 0, reliable) is a
  signed pointer, and channel 2 stays RESERVED, dark, until a genuinely
  sub-budget bulk case mints its own record kind (none exists today -
  drafts already ride channel 0, capped at 4096).
- **The info-hash is deliberately BOTH fields the design asked for.**
  "Content hash" and "torrent linkage" are one value in the phase-3
  design: the 40-hex v1 info-hash is the content address libtorrent
  verifies piece-by-piece against (a receiver cannot be fed different
  bytes than the hash names) AND what a magnet fetch takes. fileName
  and fileSize ride along for the receiving UI only; the torrent's own
  metadata is the authority once fetched.
- **The record follows the sync discipline exactly, nothing new.** Same
  shared LAN key, same "riptide-lan-s" domain, kind byte inside the
  signed span (no cross-kind reads), absolute state (the device's
  LATEST offer), the draft record's strictly-increasing per-device seq
  as the replay guard - and a duplicate apply is harmless anyway,
  because rsMediaFetch is idempotent. The wire hash is strict lowercase
  (a validly SIGNED record with an uppercase hash is refused - the
  coinxt canonical-form lesson, harness-proven), and the all-zeros hash
  is refused at build and parse: a handoff must name real content.
- **The honest limit is the transport's, and it is recorded, not
  hidden.** The pointer record never leaves the LAN; the pointed-at
  bytes ride the ORDINARY torrent rail - swarm peers see your IP, and
  peer discovery is the DHT, so a fully offline LAN may not find its
  swarm even though both devices sit on it. Said in the spec's
  section-7 as-built note, the demo's Devices-card footer, and the
  runbook's phase-6 step 7 (report it as the recorded limit, not a
  defect).
- **The demo's offer is one slot, and it outlives the mesh.** The
  Devices card keeps the LATEST verified offer (the one-conversation
  pattern); per-DEVICE seq tracking drops when the link that carried it
  goes, but the offer and its watched fetch deliberately survive
  Leave/disconnect - the swarm outlives the mesh, and a mid-download must
  not lose its
  Fetch button. The sender reads the true file size from its own seed's
  metadata (rsMediaFetch on its own hash lands on the find path - no
  download, no copy), and the receive path only REMEMBERS a verified
  offer; fetching is the user's click.

## Things decided building phase 7 (do not re-litigate)

- **The guard is a PURE FUNCTION, and it is the crown jewel.**
  `rsPersonaAllows(pIsAnon, pTransport)` is the spec-9.3 invariant made
  code: anon may use only `onion`, public may use anything but `onion`,
  and an unknown transport is refused for BOTH (fail-closed - a typo must
  never read as allowed). It has no I/O, so its FULL truth table is
  asserted in the harness, and the demo's guard panel is a LIVE read of
  it, so what the user sees can never drift from what the library
  enforces. Every transport branch the app adds must route through it.
- **The anon onion is offline-derivable and self-authenticating.**
  `rsAnonOnion(master, n)` = the v3 onion of `anon_seed(master, n)`'s
  ed25519 public, which equals `oxCreateServiceFromSeed(anon_seed)`'s
  address; the golden test pins that the onion inverts back to the anon
  handle. So a follower who has the .onion has verified the key by
  reaching it.
- **BTXO is reused, not reinvented.** The anon file transfer uses the
  Model C `BTXO` framing (magic/ver/flags/nameLen/name/total header,
  u32-length data frames, zero-length terminator) - the same convention
  the quickshare onion transfer speaks - so the framing is a shared
  cross-project contract, golden-pinned here.
- **The sealed anon-DM route: the CRYPTO layer is CLOSED (2026-08-15);
  the transport remains.** The deferral was real - `sxSeal` takes a
  curve25519 key, the persona identity is ed25519 - and the fix was the
  predicted one, and it cost exactly ONE new handler: `rsAnonDmSeed`
  (subkey 200+n, a spec-registry row added with its rationale - one seed
  never feeds two cipher schemes, the same reason subkey 2 is separate
  from subkey 1). Everything else composes from phase 4 unchanged:
  `rsBuildPrekey(kxPub, rsAnonSeed(...))` is the persona's prekey,
  `rsBuildIntro` addressed to the anon handle seals to it via
  `rsDmSealIntro`, and `rsDmOpenIntro(sealed, anonHandle,
  rsAnonDmSeed(...))` opens it. Golden-pinned (the kx public re-derived by
  the vector gate) and harness-proven end to end, including the two
  unlinkability refusals: the persona's prekey refuses the PUBLIC handle
  as author, and the public identity cannot open the persona's mail. The
  persona's prekey is served over its ONION, never the DHT (the 9.3
  guard); that serving is now built - see the 8.2/8.3 entry below.

## Things decided building the 8.2/8.3 onion serving (2026-08-15; do not re-litigate)

- **The library builds payloads; the demo owns the routes.** Three pure
  seams (`rsAnonFeedPage`, `rsAnonPrekeyBody`, `rsAnonAcceptDm`) with no
  I/O, so the harness proves them offline; the demo registers the
  onion-httpd routes (`oxhInit`/`oxhRoute`/`oxhReply`) and composes
  `oxSetPeerCallback "oxhPeer"` with `rsAnonCreateService` - onion-httpd's
  own `oxhServe` calls `oxCreateService` (a TOR-generated key), which is
  the wrong key for a persona whose address IS its identity, so the demo
  wires the peer callback itself and creates the service FROM SEED.
- **HTTP bodies are HEX TEXT, both directions.** The RSK1 record and the
  sealed RSI1 intro are binary; hex survives every HTTP client untouched,
  is copy-pasteable through Tor Browser, and gives the /dm gate an exact
  spelling to refuse against. GET /prekey returns 264 lowercase hex
  chars; POST /dm accepts EXACTLY 632 (48 seal bytes + the 268-byte
  intro, times two) - strict to the char, a trailing newline is a
  refusal, the caps-refuse discipline on an HTTP body.
- **Refuse before decode, and one reply for every refusal.**
  `rsAnonAcceptDm` gates length and per-byte lowercase hex BEFORE
  `sxHex2Bin`, then hands the blob to the EXISTING `rsDmOpenIntro`
  (verify-then-parse); the demo's route answers every refusal - bad hex,
  bad seal, wrong recipient, stale timestamp - with the same 400
  "refused", so the route is not an oracle for a prober. Freshness stays
  the app's policy (the same +-600 s window as the rp1 inbox).
- **The feed page is a WIRE FORMAT, not a template.** Deterministic HTML
  from (title, entries), entries HTML-escaped (the oxhHtmlEscape
  algorithm, mirrored in the oracle) so a crafted entry cannot inject
  markup, golden-pinned byte-for-byte - a look change edits the builder
  and re-pins deliberately. The demo's page content comes from a
  dedicated Anon-card entries field, NEVER from the public feed
  (cross-posting is the spec-8.4 operator mistake that links personas).
- **The route handlers reply from script locals**, built once at publish
  time - never from a field read at request time. They run from ENGINE
  socket callbacks (off raPoll's try, on whatever card is open), so field
  writes go through the guarded raAnonLog and every oxh reply sits in a
  try (the multi-card lesson applied to a new event source).
- **Publish is a two-step state machine when tor is cold.** ADD_ONION
  needs an authenticated control port and `oxConnectControl` is async, so
  the first Publish + serve may only kick off the connect;
  `raAnonStatus` ("control authenticated") re-enters raAnonPublish,
  whose guards make the re-entry idempotent. Fail closed, never a
  blocking wait.
- **The REPLY rail is deliberately unbuilt.** onion-httpd closes each
  stream after its reply (Connection: close), so "the persona replies
  over the same accepted stream" (spec 8.3) would need a persistent
  onion-stream session layer this pass does not add. An accepted intro
  is logged with its PROVEN sender on the Anon card and echoed to the
  Messages card; answering means a public-side DM to that sender. Saying
  so in the UI beats a half-built session.
- **A.9 rode along: the head's profileMeta is now populated.** raPost
  publishes the display name's UTF-8 bytes as an immutable item (spec
  4.1's display-name blob) and names its target in the head -
  content-addressed, so republishing the same name is idempotent, and a
  refusal is NON-fatal (the head carries the none target and the reason
  lands in the feed log). The library needed no change.

## The phase 4-7 adversarial review (2026-08-14)

After building phases 4-7, a five-lens adversarial review (crypto
correctness, wire-parse safety, dialect laws, demo state machines, gate
integrity) ran over the new code. The crypto came back CLEAN and that is
worth recording: the pure-Python X25519/crypto_kx matches libsodium's
construction exactly (checked byte-for-byte against a real libsodium via
emit-kx-anchor.py), the new ed25519 verify accepts/rejects correctly on
every tested path, the role rule makes both peers agree, rsDmSessionKeys
passes the kx keys in libsodium's order on both branches, and the intro's
recipient-binding + the LAN nonce/name binding make replay and
cross-identity reuse structurally impossible. Five real defects surfaced
in the surrounding code, all now fixed with regression coverage:

- **Never-throw violated in three parsers.** rsLanParseChallenge,
  rsLanParseResponse, and rsBtxoParseHeader decoded an attacker-controlled
  UTF-8 name field OUTSIDE a try, so malformed bytes THREW instead of
  returning empty (rule 5) - a LAN peer or BTXO sender could crash the
  admission/parse path. Wrapped each in a try like the phase-1/3/4 parsers
  already do; the harness now feeds each an invalid-UTF-8 name and asserts
  a clean refusal.
- **The multi-card demo turned two feed painters into pump-killers.**
  raExpire and raMediaPaint write card-1 status fields with BARE
  references and run OUTSIDE raPoll's try; before phase 4 there was one
  card so they always resolved, but the new Messages/Devices/Anon cards
  meant a deadline or a media tick firing while off-card threw "no such
  object" out of raPoll and PERMANENTLY stopped the pump (DHT + rp1 +
  enet). Added raFeedNote (card-1-qualified + existence-guarded, the
  raDmLog pattern) and routed every pump-reachable feed write through it,
  including raHandleEvent's walk-status writes (which had stalled the feed
  walk off-card).
- **The guard's "full truth table" omitted two of its own transports.**
  rsPersonaAllows knows eight transports; the harness and the demo panel
  asserted only six, leaving feed and media - the two an anon persona most
  needs kept off - unproven. A future edit letting an anon persona onto
  either would have leaked it to the clearnet DHT/torrent rails while
  rsSelfTest stayed green. Both cells are asserted now, and the live guard
  panel iterates all eight.
- **itemDelimiter left as "/".** raAttach set it for the leaf name and
  never restored it; the pump's raHandleEvent then read comma-joined media
  lists under the wrong delimiter. Restored to comma after use and set
  before the item read.

The lesson is the multi-card one: adding cards silently widened the blast
radius of every bare card-1 reference in the older single-card handlers.
A pump that runs from every card must treat EVERY control reference as
cross-card - qualify and guard, always.

## The first engine pass of phases 4-7 (2026-08-15): textDecode does NOT throw

The suite selftest ran on a real OXT engine, and the phase 4-7 surface came
back GREEN except three checks - a huge result: the DM secretstream round
trip (my tx key's ciphertext decrypts under the peer's rx key, the FINAL
tag survives), the LAN admit/refuse under the shared master, the anon guard
truth table, the BTXO framing, and the whole cross-member seam all passed on
the engine, so the phase 4-7 COMPUTE/CRYPTO paths are engine-verified now,
not merely static. The live two-machine done-criteria (a real DM exchange, a
device joining the mesh, an onion reachable over Tor) still need two boxes.

The three failures were the malformed-UTF-8 refusal checks added in the
review pass, and they exposed a FALSE PREMISE the whole library carried:
six parsers guarded their name/text decode with a `try`, commented "textDecode
throws on malformed UTF-8." **It does not.** On OXT textDecode(...,"UTF-8")
is LOSSY: it decodes invalid bytes to replacement characters and returns a
non-empty string, so every one of those try blocks was INERT and the parsers
would have handed back a mangled name where they meant to refuse. The three
phase-6/7 parsers were the only ones with a test that fed malformed bytes,
so they were the only ones that showed red - the three authenticated parsers
(rsParseHead/rsParsePost/rsDmParseMessage) were silently broken the same way.

The fix is `rsBytesAreUtf8`: validity by ROUND TRIP - decode, re-encode, and
require the bytes to reproduce exactly (only valid UTF-8 does), with an inner
try kept as belt-and-suspenders for any engine that does throw. All six sites
use it now. This is the canonical "shipped is not run" lesson in its purest
form: the "textDecode throws" comment was an attestation no test had ever
exercised, it was wrong, and the first inputs that touched the path found it.
Whenever you must reject malformed UTF-8 in this family, round-trip it - never
trust a decode to throw.

## THE DEMO STACK IS THE LEAST-VERIFIED SURFACE HERE (read before editing it)

`examples/riptide-social.livecodescript` is **not** covered by any harness.
The suite selftest exercises `src/riptide.livecodescript` (the library) and
is what went green on the engine; it never opens the demo, never builds a
card, never dispatches a `mouseUp`. So EVERY line of the demo has only ever
been seen by `check-livecodescript.py`, which validates balance, quoting and
the token traps - NOT whether an object-reference or navigation form is
something the engine accepts.

That gap has now produced its own bug, reported from an engine 2026-08-15:
the phase 4-7 multi-card conversion wrote card navigation and cross-card
references as **`... of me`** - `go card "raMessages" of me`,
`field "raDmLog" of card "raMessages" of me`, `card 1 of me` - 48 sites in
all. **That form is wrong for LiveCodeScript** and the checker passed every
one. The canonical forms are used now: `go to card "raMessages"` /
`go to card 1` for navigation, plain `field "X" of card "Y"` for a control on
another card of the same stack (no qualifier is needed - it is one stack),
and `set the name of this card to "..."` right after `create card` (the new
card is already current). The `send "raPoll" to me in <n> milliseconds` form
is UNCHANGED and correct - that is a message target, engine-proven in
torrent-rp1-chat, and a different construct entirely.

Two things follow, and they are the operational point:

1. **There was no in-repo precedent to copy, and that should have been the
   warning.** Every other demo in this family is a SINGLE card, so the repo
   contained no proven multi-card navigation idiom; `grep` for `go card`
   returns only `go stack` (a different command). Writing a form the tree has
   never executed, in a file no harness runs, is how this landed. When you
   need a construct the suite has no engine-proven example of, say so in the
   honesty label rather than letting a green checker imply it was verified.
2. **PHASE 3 IS DONE: the two-machine media pass happened 2026-08-15.** After
   the `of me` fix the demo ran ON TWO MACHINES and a follower fetched and
   PLAYED an attached video, near instantly. That is the phase-3
   done-criterion met, and it closes the last of the phase 1-3 criteria. It
   also means far more than the media layer was exercised end to end on real
   hardware, because a follower cannot reach a video any other way: machine
   A published a head and a media-bearing post to the DHT, machine B fetched
   that head, walked the chain, VERIFIED the authorSig, surfaced the media
   info-hash from the verified post, joined the author's swarm and played
   what came back. Phases 1-3 of the app - identity, the live feed, and
   media - are now engine-proven across two machines through the real UI,
   not just through the harness.

   Two things this specifically does NOT settle, both worth keeping honest:
   - **"Near instantly" was not distinguished from "mid-download."** The
     criterion's spirit is sequential playback starting before the file is
     complete; a fast small transfer looks the same from outside. Treat the
     mid-download nuance as plausible but unmeasured.
   - ~~The media strip lives on card 1, so this may not have exercised the
     multi-card navigation.~~ **RESOLVED the same day: PHASE 4 IS DONE TOO.**
     Two machines exchanged DMs, chat working BOTH WAYS - the sealed RSI1
     intro, the deterministic-role crypto_kx session, and the pairwise
     secretstream over rp1 all carrying real traffic with no server. Since
     the Messages card had to be reached to do it, that also CONFIRMS the
     `go to card` navigation fix on a real engine. The Devices and Anon
     cards are built by the same `raBuild` pass and use the same navigation
     and reference forms, so the syntax class is settled; what remains
     unexercised there is their own flows, not their spelling.

## The 2026-08-17 pre-engine-pass sweep (do not re-litigate)

Four fixes ahead of the phase 5/6/7 passes. All FOUR are demo or library
edits with no wire-format change, no new golden vector, and no new public
`rs*` handler; all are verified statically and need the OXT pass.

- **C6: the LAN sync state was keyed by the enet PEER, not by the signing
  DEVICE - and the runbook could not have found it.** `raLanSyncReceive`
  keyed all six of its per-device arrays by `pPeer`. On a HOST that is
  accidentally right (one link per device); on a JOINER it is wrong for
  every device but the host, because the mesh is hub-and-spoke and the
  host RELAYS verified records, so a joiner's whole mesh arrives over ONE
  peer id. Three consequences, in rising order of how badly they read on
  an engine: interleaved seq/tick counters from different devices fought
  over one slot and the monotonic guard dropped most of them through a
  path that is a DELIBERATE SILENT EXIT, so nothing was logged; the drafts
  panel labelled every relayed draft with the HOST's name, because it
  looked the label up in `sLanDevices[peer]`; and the devices panel
  iterated `sLanDevices`, so on a joiner OTHER DEVICES NEVER APPEARED AT
  ALL. The library had stated the correct contract since the day it was
  written - `rsLanBuildDraft`'s own comment says "apply only a seq
  strictly above the last one applied FOR THAT DEVICE" - so the demo was
  violating a contract its own library spells out. The fix keys the six
  arrays by `tRec["name"]`, which is INSIDE the signed span and read only
  after the signature verdict; the painters label and iterate by device;
  and a new `sLanPeerNames` (peer -> set of names) is what a disconnect
  drops by, because one link can legitimately carry many devices. Keying
  by name is not a per-device IDENTITY claim - all your devices share one
  LAN keypair, so any admitted device can sign any name - and that is the
  recorded threat model (your own devices), not a hole the keying opens.
  **The process lesson is the one worth keeping: the two-machine runbook
  had exactly ONE non-host device, so the S3 session as scripted could
  not reach the relay at all.** A THIRD-DEVICE step is now step 8 of the
  phase-6 section, and it names the failure it is looking for rather than
  only the success. When a design has a hub-and-spoke shape, a two-node
  test plan is not a small-sample version of it - it is a different
  topology that never runs the code.
- **C10: `rsMediaCreate` leaked `itemDelimiter` as "/" for the rest of
  the session.** A PUBLIC handler set it and none of its seven exits
  restored it; six of those exits are refusals. The demo had already met
  the symptom twice and patched it at the call sites, one patch quoting
  what it looked like from outside - "leaving it as / made item 1 return
  the whole list" - which is exactly how a delimiter leak reports on an
  engine pass: as a mystery about the media list, never as a delimiter.
  Fixed at the source, and fixed by restoring around the NARROWEST span
  (the path split) rather than at each exit, because a restore per exit
  is a line the next refusal path forgets. `rsAnonFeedPage`'s
  `lineDelimiter` got the same save/restore for uniformity, and its
  comment says plainly that it sets the ENGINE DEFAULT, so that one is
  discipline and not a second live bug fixed. The demo's defensive
  re-set in `raHandleEvent` deliberately STAYS - the pump reaches that
  item read from any card after any handler, and one line is cheaper
  than trusting every caller in a file no harness runs - but its comment
  now names the library fix instead of blaming an unnamed earlier
  handler.
- **B3: the pump ran phases 5 and 6 at 7.5x their designed interval.**
  The spec's section 10.1 always named two tiers, ~33 ms while a live
  dc/enet session is active and ~250 ms otherwise; only the slow one
  existed. Phases 5 and 6 are the main events of the next engine session
  and BOTH ARE JUDGED BY FEEL - a call connecting, a typing indicator
  appearing - so a whole slot could have gone to chasing sluggishness
  that was a constant in this file. `raPollDelay` picks the tier on every
  tick (never latched, so hanging up drops straight back to the cheap
  tier). The half that needed care is the UI: a straight fast tier would
  have taken `raExpire`/`raMediaPaint`/`raLanMediaPaint` from 4 Hz to
  30 Hz, which is a NEW performance defect and not a fix, so they sit
  behind a `kPaintMs` gate - and `raLanPaintDevices`, which used to hang
  off the end of `raLanSyncTick`, moved onto that same gate for the same
  reason. Everything else on the fast path was already cadence-gated
  (`raDmTypingTick`, the draft debounce, the presence interval), which is
  why the tier change is small.
- **D15: a DM hang-up was silence, not a close.** `raDmTeardown` freed
  the secretstream handles and pushed nothing, so the far side kept
  showing `-- channel open with ... --` forever. libsodium's FINAL tag is
  the clean-close signal and the spec names `sxIsFinalTag` for exactly
  this, so `raDmPushClose` pushes one last message with final true before
  the free, and the receive path prints `closed the conversation` and
  drops the peer on a final tag. Two things are deliberate: the body is
  FILLER and is never parsed or rendered (the TAG is the message, but
  `rsDmMessageBody` refuses an empty body so something must ride along),
  and the FINAL tag belongs to exactly ONE caller - every ordinary send
  keeps final false, because spending it ends the stream. `sxIsFinalTag`
  was already exercised by the harness, so the gap was only ever in
  `src/` and `examples/`; a reconnect mints fresh streams, so the old
  symptom was silence and never a false auth failure. Do not overstate
  it in the changelog.

## The 2026-08-23 headless batch (A2 / A3 / B4 / B7 / A.9 / D14; do not re-litigate)

Six backlog items closed headlessly (library 0.10.0 -> 0.11.0, seven new
public handlers). WRITTEN as verified-statically; the COMPUTE halves ran green
on-engine **2026-08-24** (Windows x86_64: riptide folded at **391/391** in the
suite paste, the phase-2b kind-C rail and the phase-7b BTXO receive path
included). The live halves (a second machine, a tor daemon, real transports)
keep their stricter labels at each site.

- **A2, the kind-C chunked-post rail - PINNED FIRST, then built.** Kind C
  was the only unpinned riptide wire format; the oracle now derives
  chunk1Target/chunk2Target/postC/postCTarget (real chunk texts whose
  concatenation is the post's full text, plus a media attachment BEHIND
  the chunk list so the kind-C tail parse is pinned), held in all three
  holders per rule 2 - after this there is nothing left to pin in the
  record layer. Then the rail: rsChunkPostText (full 1000-byte chunks by
  BYTE - a boundary may split a UTF-8 sequence, which is why the
  reassembly validates the CONCATENATION, never a chunk alone),
  rsPostTextCapacity (the D-or-C arithmetic as API, so the demo never
  hand-copies 880), rsPublishChunkedPost (compute and sign BEFORE the
  session is touched; a mid-publish failure strands only harmless
  content-addressed orphans), rsIngestBlob (content addressing is what
  extends the authorSig from the named targets to fetched bytes), and
  rsAssembleChunkText (re-hash every part, then one UTF-8 round-trip
  decode of the whole). The demo's walker now BRANCHES ON KIND - before
  this it rendered tPost["text"] unconditionally, so a kind-C post
  displayed as a verified post with BLANK text, the worst failure shape
  because authorSig passes - rendering an honest placeholder, walking the
  parts one immutable await at a time beside the chain walk (one
  reassembly at a time, the one-conversation precedent), and printing the
  full text under the post's own number; raPost auto-chunks over the
  capacity. Expiry and refusal keep the placeholder and say why.
- **A3, the BTXO receive path.** rsBtxoStreamStep is the pure
  length-prefix stream state machine (the builders existed; no reader
  could find a boundary). Single-step by design: accumulate, step, act,
  delete `used` bytes, repeat - which is what lets the harness prove
  reassembly at EVERY byte boundary offline, plus concatenated frames and
  each hostile-input refusal. The caps are PORTED from nocloud's working
  receiver (name 1024 - refused from the first 8 bytes, before the name
  is ever buffered; total 8 GiB; frame 65536), not re-derived. It reuses
  rsBtxoParseHeader for the strict header parse rather than restating it.
- **B4** - the Devices panel appends a live `rtt N ms, loss P%` suffix
  per DIRECTLY-LINKED device from enPeerStatus (stats are a LINK
  property; a relayed device's row stays bare on purpose - printing the
  host's numbers under its name would lie). Probe-guarded and
  try-wrapped; a stale peer's `{}` degrades to nothing.
- **B7** - rsMediaStreamPlan, a SEPARATE handler from rsMediaFetch on
  purpose (the fetch is btAddMagnet: no metadata, no piece table, so a
  deadline at fetch time would name pieces that do not exist). The demo
  arms it from the metadataReceived event on either watched fetch; the
  front 8 pieces get spaced deadlines as a playback PRIMER. Refusals are
  non-fatal everywhere - the fetch stays sequential - including on a
  torrentxt predating btSetPieceDeadline.
- **A.9** - the profileMeta READER (the publish half landed 2026-08-15).
  Fetching a foreign head - the feed walk or Start DM - now also fetches
  its profileMeta target and prints the display name once
  content-verified (rsIngestBlob, then 1..64 bytes and a UTF-8 ROUND
  TRIP, because textDecode is lossy - the demo cannot reach the library's
  private rsBytesAreUtf8, so the idiom is restated at raProfileLine).
  Absent, refused, or late all degrade honestly to the head's own name.
- **D14** - the spec 9.3 attestation corrected AS AN ATTESTATION, not
  built as a runtime fix (the backlog is explicit: no active-persona
  state exists in the demo, and 16 more guard calls would be 16
  compile-time constants that can never refuse). The sentence now states
  what is asserted where: the full truth table in the harness, the live
  guard panel, and the demo's two real persona decisions.
- **D.1 (riptide half)** - the stale labels synced to the recorded
  2026-08-20 Windows run (riptide 338/0/2 in the suite paste): the src
  header and the demo scope block no longer call the 8.2/8.3 serving
  seams "verified statically" - their COMPUTE half is engine-green; what
  remains is the live-Tor leg (and, for the demo, its own route wiring).

## Suite integration status

- `tools/build-all.sh` runs riptide's gates in the member loop (script
  gate, `tests/*golden*.py` glob, vector gate, docs style) and runs
  riptide's script checker over the root `tests/` scripts.
- `tools/check-handler-calls.py` carries the `rs` prefix.
- The suite selftest FOLDS riptide in (since 2026-08-11): the harness as
  the seventh `Member` (prefix `rs1`, entry `rsSelfTest`, run LAST, merged
  via `stMergeReturned` - which is why the report's first line must stay
  exactly "N passed, M failed" with the skip count on its own line), and
  the library as the third embedded script layer. `check-suite-selftest.py`
  and `check-suite-coverage.py` both know riptide, so a new public `rs*`
  handler the harness does not call FAILS the coverage gate - close the
  gap in tests/riptide-selftest.livecodescript and regenerate. A
  script-layer or harness edit here is not done until
  `python3 tools/build-suite-selftest.py` has rebuilt the suite paste.
  `examples/riptide-social.livecodescript` carries three libraries
  verbatim between the sentinels `tools/sync-demo-embeds.py` (at the
  suite root) owns - `src/riptide.livecodescript` plus OnionXT's
  `onionxt` and `onion-httpd` layers, so the demo pastes and runs with
  no `start using` step, and nobody edits inside the sentinels. A
  `src/riptide.livecodescript` edit is therefore not done until
  `python3 tools/sync-demo-embeds.py` has been re-run at the suite root
  either. That copy is NOT cut back out of the suite paste (the riptide
  row has no `strip_spans`); the demo is simply never folded. Riptide's
  own `tools/` does not carry the sync tool, so this drift is invisible
  to the member gates and surfaces only as `--check` failing the suite
  build.
