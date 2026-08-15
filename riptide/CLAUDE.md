# CLAUDE.md - riptide/

Guidance for Claude Code when working in this directory. Read
`../docs/RIPTIDE-SOCIAL-SPEC.md` FIRST: it is the full design (the five
rails, the identity architecture, the security model, the phased roadmap),
and this directory implements it phase by phase. This file records only
what is operational and riptide-specific. The root `CLAUDE.md` and the
member files it points to still apply; when they conflict, this file wins
inside `riptide/`.

## What this is

The suite capstone app, pure LiveCodeScript over the installed extension
surfaces. It is deliberately structured like a member (src/, tests/,
tools/, docs/) so the repository's gate machinery walks it unchanged, but
it is an APP, not an extension: nothing here is compiled, nothing here
adds native surface, and `rs*` never becomes a library other members may
call.

**Phases 1 and 2 of the spec's seven are COMPLETE**, done-criteria included:
phase 1 (identity + the pure-compute feed layer) and the phase-2 LIVE feed
layer (BEP44 head/post publish, async lookups, ingest verifiers) are
engine-passed, and phase 2's two-machine propagation criterion closed
2026-08-13 (see rule 8). **Phases 3 (media) and 4 (DMs) are BUILT but not
passed** (2026-08-14): phase 3 is `rsMediaCreate`/`rsMediaFetch`/
`rsMediaStatus` plus the demo's media strip; phase 4 is the `rsDm*` layer
(kx prekeys, RSK1/RSI1/RSM1 records, deterministic-role sessions, inbox
join + framed send) plus the demo's Messages card - all golden-pinned
where deterministic, refusal-covered in the harness, verified statically;
their done-criteria (a follower plays a video mid-download; two machines
exchange authenticated encrypted DMs) each need a two-machine pass.
**Phase 6 (LAN mesh) is BUILT but not passed** (2026-08-14): the `rsLan*`
admission layer (shared-master ed25519 keypair, RSL1 challenge/response)
plus the demo's Devices card, golden-pinned and offline-harness-covered;
its done-criterion (a device that shares the master joins, a stranger is
refused) needs a two-machine pass. **Phase 5 (live sessions) needs no
library surface** - SDP rides the phase-4 DM message kinds O/A over the
existing secretstream, so it is a demo-wiring milestone still to build.
**Phase 7 (anon persona) is BUILT but not passed** (2026-08-14): the
`rsAnon*` layer (onion-only persona derivation, probe-gated service
wrapper, BTXO framing) and `rsPersonaAllows` - the pure-policy §9.3 guard,
the app's highest-severity invariant - plus the demo's Anon card, all
golden-pinned/harness-covered where deterministic; its done-criterion (a
persona reachable over Tor with zero `bt*` calls in a trace) needs an OXT +
live-Tor pass. With that, all seven spec phases are built in the tree;
only phase 5's dc demo wiring and phase 7's sealed anon-DM route remain,
both noted below.

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
   every `rs*` call site is checked for existence and arity too.
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
   maintainer's account, dated. **The phase-3 media layer (2026-08-14) has
   had NO engine pass yet**: its label is "verified statically; needs an
   OXT pass", and its done-criterion additionally needs the two-machine
   mid-download play.

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
- **The sealed anon-DM route is DEFERRED, honestly.** Spec 8.3 wants
  `sxSeal(message, anonPub)`, but `sxSeal` takes a curve25519 key and the
  persona identity is ed25519 (no conversion handler exists). The correct
  fix is the same published-prekey pattern the DM rail uses (phase 4),
  which is a later pass - not something to fake now. The library ships
  the derivation, the guard, the service wrapper, and BTXO; the sealed
  inbound DM is the one piece left.

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
