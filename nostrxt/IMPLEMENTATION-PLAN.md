# NostrXT Implementation Plan

The phased build order. Each phase has a goal, concrete deliverables, a "done when" bar, and the
risks that phase exists to retire. The guiding principle is the family's, tightened for a member
whose whole surface is checksummed byte shuffling: **derive every answer from the published vector
sets through an independent oracle before writing the script that must reproduce it, and let no
missing primitive be hand-rolled - a gap in the suite's crypto is an upstream feature landed first,
never a cipher here.** Nothing is "done" on a claim; a pure-compute path is done when the full
published vectors sweep green through the oracle AND the harness pins the same answers, and an
engine path is done only when it has run on a real OXT engine (relay paths: against a real relay).

Read the `docs/` spine first: `docs/00-overview.md` for the architecture and
`docs/01-protocol-model.md` through `docs/05-relay-client.md` for what each layer is. House style
and the static gate (`tools/check-livecodescript.py`) apply to every phase that touches script;
`tools/check-docs-style.py` applies to every phase that touches prose.

## Status as built

Phases 0 through 5 CLOSED - statically - on 2026-08-23, in one build session: ground truth and the
scope decisions (phase 0), the independent oracle and the full-set KAT (phase 1), the pure-compute
core (phase 2), the relay layer (phase 3), the harness and its gates (phase 4), and the docs
(phase 5). "Closed statically" means exactly what the honesty convention says: every gate exits 0,
every pure-compute answer is pinned against the published BIP-340 / NIP-44 / BIP-173 / NIP-19 sets
through `tools/nostr_reference.py`, and **nothing has run on a real OXT engine**. The member-wide
status is "verified statically; needs an OXT pass", relay paths "verified statically; needs an OXT
pass + a live-relay pass", and the open phases below are the order in which that changes.

Two scope decisions from phase 0 are worth restating here because they shape everything after:

- **NIP-04 is out of scope by decision, not deferral.** It needs AES-256-CBC; no AES exists in the
  suite, libsodium provides no CBC so SodiumXT never will, and NIP-44 supersedes it. There is no
  phase where NIP-04 lands.
- **NIP-44's cipher is an upstream request, not a local implementation.** The one primitive the
  suite lacked was raw ChaCha20; phase 8 was the request (`sxChaCha20IetfXor`) and the completion,
  and it CLOSED 2026-08-23 when SodiumXT shipped it as ABI 10. On an installed SodiumXT older
  than that, `nxNip44Encrypt` / `nxNip44Decrypt` still fail closed at the seam with a capability
  error naming it.

## Phase 0 - Ground truth and decisions (no code that ships) - CLOSED 2026-08-23

**Goal:** remove the unknowns and make every scope call before writing protocol code.

- Fetch and pin the primary sources: NIP-01 (events, filters, relay messages), NIP-19 (bech32
  entities), NIP-44 v2 (the payload spec and the official vector file), BIP-340 (the csv), BIP-173
  (bech32 and its vectors), RFC 6455 (the websocket handshake and framing). Record each source URL
  where the derived values live (`tools/nostr-kat.py` names all of them).
- Decide the scope calls, each with written reasons: NIP-04 out (above); the NIP-44 length policy
  (the published vectors pin the u16 length prefix only - 65536+ plaintext is invalid there - so
  NostrXT refuses plaintext over 65535 bytes fail closed, and the newer spec text's sketched 6-byte
  extended prefix waits for vectors to exist); bech32 owned in-member (CoinXT's copy holds
  BIP-173's 90-character cap and keeps its bit converters private; NIP-19 waives the cap for TLV
  entities and NostrXT enforces the 5000-character SHOULD instead); the two-file core/relay split
  (the core does no I/O and can embed in the suite paste; the relay layer defines the engine's
  shared socket handlers and must stay out - the onion-httpd precedent); and the cipher gap routed
  upstream (phase 8).

**Done when:** every vector set has a named source, and every decision above is written down with
its reasons where the code and docs cite it.

**Risk retired:** building a byte-exact protocol on remembered spec text, and re-litigating scope
mid-build.

## Phase 1 - The independent oracle and the full-set KAT - CLOSED 2026-08-23

**Goal:** an implementation-independent source of every answer the script must reproduce.

- `tools/nostr_reference.py`: secp256k1 group math and BIP-340 (sign, verify, tagged hashes,
  lift_x), the NIP-01 canonical serialization and event id, bech32/bech32m with no length cap,
  the full NIP-44 v2 pipeline (ECDH x, HKDF, padding, ChaCha20, HMAC), and the RFC 6455 client
  pieces. Pure standard library; anchored AT IMPORT to transcribed vector subsets so a broken
  transcription refuses to load rather than pinning a wrong answer.
- `tools/nostr-kat.py`: sweeps the FULL published sets (the complete BIP-340 csv including every
  negative, the complete official NIP-44 vector file, the BIP-173 valid and invalid strings, the
  NIP-19 examples) through the oracle, asserts the deliberate over-90 bech32 deviation as a
  deviation, and emits by name every constant the member harness pins (`harness_vectors()`).

**Done when:** `python3 tools/nostr-kat.py --check` exits 0 sweeping the full sets, and every
constant the harness will pin is emitted by name with a source.

**Risk retired:** the self-agreeing-harness failure (the coinxt lesson): a wrong pinned vector is
a test that passes for the wrong value, and only an independent derivation can catch it.

## Phase 2 - The pure-compute core - CLOSED 2026-08-23 (statically)

**Goal:** the whole nx* surface with no I/O and no connection state.

- `src/nostrxt.livecodescript`: hex and base64 discipline, the owned JSON escape/parse pair,
  keys (composed: SodiumXT randomness, CoinXT validation), NIP-01 events (build / canonical
  serialize / id / sign / verify / JSON both ways), tags and the kind builders (metadata,
  reply, reaction, delete, contacts, relay list, NIP-42 auth), bech32 and the NIP-19 entities,
  the NIP-44 schedule / padding / MAC with the cipher seam failing closed, filters and the
  client/relay wire messages, the pure half of RFC 6455, and NIP-13 / NIP-05 / NIP-11.
- The error convention throughout: no nx* handler ever throws; functions return empty or false
  with the reason recorded for `nxLastError()`, and every cx*/sx* call sits in a try.

**Done when:** the static gate passes, the file does no I/O anywhere, and every KAT-derived
answer is reproduced by a harness assertion (phase 4 proves that mechanically).

**Risk retired:** canonical-serialization drift - the class of bug where a well-formed but wrong
preimage produces wrong event ids that verify against themselves - plus the family's delimiter
and byte-discipline traps.

## Phase 3 - The relay layer - CLOSED 2026-08-23 (statically)

**Goal:** the stateful websocket client, composed over the core.

- `src/nostr-relay.livecodescript` (public nxr*): connect / handshake / frame state machine over
  engine sockets, the NIP-01 relay messages both directions, verify-before-deliver (fail closed;
  events arrive as "invalid" with the reason when they cannot be verified), the per-relay
  callback contract (verbatim in the file header), idempotent teardown, and the engine's
  `socketError` / `socketClosed` / `socketTimeout` handlers that act only on their own socket ids
  and pass the rest.
- The split honoured from day one: this file is deliberately NOT embedded in the suite paste
  (those three engine handlers collide with the embedded onionxt layer's; the suite generator
  refuses a duplicate definition, at build time, as it must).

**Done when:** the static gate passes, the callback contract is documented verbatim in the
header, and the offline (fail-closed / clean-miss) paths are covered by harness sections that
SKIP cleanly wherever the layer is not loaded.

**Risk retired:** discovering the socket-handler collision at suite-fold time instead of design
time, and a wire-error path that tears down unsafely.

## Phase 4 - The harness and its gates - CLOSED 2026-08-23 (statically)

**Goal:** a deterministic offline self-test that cannot agree with itself by accident.

- `examples/nostrxt-tests.livecodescript`: entry point `nxSelfTest()`, the suite's summary-line
  contract, SKIP as a counted outcome (CoinXT absent, SodiumXT absent, relay layer not loaded),
  and identical behaviour in all three run modes: standalone, embedded in the demo, folded into
  the suite paste.
- `tools/check-selftest-vectors.py`: every pinned constant re-derived BY NAME through the KAT
  and the oracle, both directions, and every other long literal accounted as an input with a
  written reason.
- The NIP-44 seam sections prove today what can be proved today: the MAC verifies BEFORE the
  cipher runs (a tampered payload refuses at the MAC), and the cipher seam fails closed naming
  the missing upstream primitive - with the vector round-trip branch already written for the day
  it ships.

**Done when:** all member gates exit 0 and the vector gate reports every pinned constant
re-derived (its output is the authoritative count).

**Risk retired:** transcription slips in either direction, and a harness whose green depends on
which of the three run modes it is in.

## Phase 5 - Docs - CLOSED 2026-08-23

**Goal:** the member reads like its siblings: dense on the why, honest on the status.

- `README.md`, this plan, `LICENSE`, and the `docs/` spine `00-overview.md` through
  `09-usage-guide.md`, every claim carrying its status label and every structural number
  attributed to the gate that measures it.

**Done when:** `tools/check-docs-style.py` exits 0 and no document claims more than the gates
verify.

**Risk retired:** docs that overstate an unexecuted line (the family's shipped-is-not-run
lesson, applied to prose).

## Phase 6 - The first OXT engine pass - OPEN

**Goal:** run the member on a real engine and flip the core's honesty label.

- On an engine with CoinXT (ABI >= 6) and SodiumXT installed: `start using` both stacks, probe
  `nxVersion()` and `nxProbeCapabilities()`, then run `nxSelfTest()` and read the whole report.
- Work through the `VERIFY (on-engine)` labels the source carries (the base64 wrap behaviour in
  `nxB64Encode` is the first), promoting or correcting each one where it stands.
- Record every engine behaviour learned - symptom verbatim, what it broke - in the suite's
  engine-behaviour ledger at the repository root, per the family convention.

**Done when:** `nxSelfTest()` completes on a real engine with zero failures (or every failure is
recorded and fixed), and the core's label moves from "verified statically; needs an OXT pass" to
an engine-passed statement naming the date, platform and check count.

**Risk retired:** the class no headless gate can see - the engine parse and scope rules that have
each cost this family a real engine pass (the statement-call parse, DECLARED-is-not-IN-SCOPE, the
undeclared name evaluating to its own spelling).

## Phase 7 - The live-relay pass - OPEN

**Goal:** the relay client shakes hands with a real relay.

- ws:// first: the plain-socket path mirrors the idioms OnionXT proved on-engine, so it is the
  cheapest leg. Connect, receive "open", subscribe, receive verified events and "eose", publish
  a signed event and receive its "ok", answer a ping, tear down cleanly, and force the negative
  paths (a non-websocket server, a handshake timeout, a mid-session close).
- wss:// second, and it is THE open transport question: nothing in this suite has ever opened a
  secure socket, so certificate verification, TLS version support and failure delivery are all
  unmeasured. Whatever the engine does, record it in `docs/08-open-questions.md` and the ledger -
  a negative result (the engine cannot do TLS usefully) is a result, and it would make the
  OnionXT composition path (below) the primary secure transport rather than a nicety.

**Done when:** the full verb set is observed against at least one public relay over ws://, the
wss:// question is answered either way with the observation recorded, and the relay label flips
accordingly.

**Risk retired:** RFC 6455 on a real wire (fragmentation, interleaved control frames, server
close behaviour), and the TLS unknown that currently gates real-world relay coverage.

## Phase 8 - The upstream cipher and NIP-44 completion - CLOSED 2026-08-23 (engine sweep still owed)

**Goal:** encrypted payloads work end to end, with the cipher living where family law puts it.

- Propose `sxChaCha20IetfXor` upstream in SodiumXT: RFC 8439 ChaCha20, 12-byte nonce, counter 0,
  an unauthenticated stream xor. This is a documented tension, not a routine request: sodiumxt's
  own rules refuse raw stream ciphers and caller-supplied nonces precisely because misuse is
  silent, so the proposal must carry the written loud reason - NIP-44 is an externally-specified
  format whose MAC and nonce derivation live in the caller by design, the primitive would ship
  labeled for protocol implementations rather than general use, and the alternative is a cipher
  hand-rolled outside SodiumXT's tests, which is strictly worse. SodiumXT decides on its own
  ground; the request lands there first with its own ABI bump and KATs (the split-the-change
  law).
- When it ships: NostrXT's seam needs no code change (`nxNip44HasCipher()` is a live probe, and
  the harness's cipher branch is already written) - the work here is running the official
  encrypt/decrypt vector sweep through the now-complete path on an engine, and turning the
  capability docs from "requested" to "shipped, ABI N".

**How it closed (2026-08-23):** exactly as written above. SodiumXT shipped
`sxChaCha20IetfXor` as ABI 10, with the loud reason argued in `sodiumxt/docs/security.md`
(the four points docs/07 demanded), C KATs cross-checked against this member's own oracle
plus the pinned libsodium tarball's expectation file, ASan/UBSan green, and all four non-mac
platform binaries refreshed in the same change. NostrXT's seam, probes and harness branch
flipped with zero code changes; the capability docs turned from "requested" to "shipped,
ABI 10". The one deliverable this phase still owes is the ENGINE sweep of the now-complete
path (runbook rows; the honesty label stays "verified statically; needs an OXT pass"), which
rides the member's first OXT pass rather than standing as its own phase.

**Done when:** SodiumXT ships the primitive; `nxNip44Encrypt` / `nxNip44Decrypt` round-trip the
official vectors on an engine (the harness's seam section goes green on its cipher branch); and
`docs/07-capabilities-required.md` records the shipped ABI.

**Risk retired:** the standing incompleteness of DMs - resolved the only way family law allows,
and never by a cipher written here.

## Phase 9 - Optional NIP additions - OPEN, each its own decision

**Goal:** grow coverage deliberately, never by drift.

- **NIP-17 private DMs** (gift-wrapped, via NIP-59 seals and gift wraps): the modern DM scheme.
  Blocked on phase 8 twice over - the rumor/seal/wrap layers each encrypt with NIP-44 - and
  worth doing only with its published vectors pinned first.
- **NIP-59 gift wrap** as its own composable layer (NIP-17 needs it; other NIPs reuse it).
- **Onion-relay composition:** a `.onion` relay reached over OnionXT's transport seam instead of
  a direct engine socket - the metadata-privacy story, and independently a hedge against the
  wss:// question. A composition of two existing members, designed at the transport seam, not a
  fork of the relay layer.

**Done when:** each addition lands as its own phase with vectors where vectors exist, or is
explicitly declined here with reasons - either outcome is a close.

**Risk retired:** scope creep; the NIP space is unbounded and this member's scope is not.

## Phase 10 - Possible: a headless execution gate for the compute core - OPEN

**Goal:** close the shipped-is-not-run gap for the pure nx* paths without an engine.

- Model on coinxt's `coinxt/tools/check-script-vectors.py` over `coinxt/tools/lcs-interp.py`:
  drive the pure-compute handlers (serialization, ids, bech32, the NIP-44 schedule and padding,
  frame encode/decode) through a headless interpreter against the same oracle-derived vectors,
  so the script is EXECUTED on every build, not just statically checked. Coinxt's gate caught a
  real assembly defect no static check could; that is the argument for paying the port cost.
- The bar for adopting it is the family's: the interpreter must be honest about what it does not
  model, and the gate must be exercised the way the build will run it (a seeded mutation must
  fail it) before it counts as cover.

**Done when:** the gate runs in the member's gate set, a deliberately seeded wrong byte in a
compute path fails the build, and its docstring states exactly which handlers it executes and
which it cannot.

**Risk retired:** an engine pass spent on the class of bug a headless run could have caught for
free.

## Cross-cutting: what "done" always means

- The static gate and the docs-style gate pass; the KAT sweeps green; the vector gate re-derives
  every pinned constant by name.
- Crypto is CoinXT and SodiumXT, never hand-rolled; a missing primitive is an upstream feature
  landed first. Every wire error fails closed and tears down; every teardown is idempotent; the
  app frees what it opens.
- The honesty rules hold: "verified statically; needs an OXT pass" (relay paths: "+ a live-relay
  pass") until a real engine, and for the relay a real relay, says otherwise - and no open item
  (wss://, NIP-17, the NIP-44 engine sweep; the cipher gap itself closed 2026-08-23) is
  presented as solved.
