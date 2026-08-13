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
2026-08-13 (see rule 8). The remaining transport phases (3-7) land later,
each behind its own pass.

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
   maintainer's account, dated.

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
