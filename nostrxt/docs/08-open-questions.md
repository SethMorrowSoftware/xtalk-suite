# 08 - Open Questions

The honest to-do list, numbered so answers can cite what they close. Nothing in this
member has run on a real OXT engine; every question below is either an engine
behaviour we have assumed and labeled, a scope decision deliberately not yet made,
or a performance question deliberately not yet optimized. When one is answered, the
answer goes where the family keeps that class of fact: engine behaviour into
`docs/OXT-ENGINE-NOTES.md` at the suite root, member consequences into
`nostrxt/CLAUDE.md`'s as-built notes, and the question is struck here with a date.

## Engine unknowns (the OXT pass owes these)

**1. `base64Encode` wrap behaviour.** The engine's `base64Encode` is documented in
LiveCode lineage to wrap its output with line breaks; every wire format here
(NIP-44 payloads, `Sec-WebSocket-Key`, the accept derivation) is single-line, so
`nxB64Encode` strips both break bytes unconditionally - correct whether the engine
wraps with CRLF, LF, or not at all, since base64's alphabet contains neither byte.
**The STRIP is proven; the EMISSION is still unrecorded.** The 2026-08-24 pass ran
every base64 consumer in the core green (the NIP-44 payload vectors and the RFC 6455
accept derivation, both pinned against the oracle), so whatever `base64Encode` emits
on OXT 9.6.3/Windows, stripping both break bytes yields the right answer - the guess
is now a measured-correct behaviour. What nobody wrote down is the raw emission
itself: whether it wraps, with which bytes, at what line length. That is a one-line
observation for the next session, and it stays `VERIFY (on-engine)` in the source
until someone actually looks.

**2. `textDecode` UTF-8 round-trip fidelity for non-BMP content. ANSWERED
2026-08-24: faithful.** The canonical serializer works on UTF-8 bytes via
`textEncode` / `textDecode`, and event C in the member harness existed to measure
exactly this: its content is built with `textDecode` over pinned bytes (a euro sign
and a four-byte emoji, so both a three-byte and a surrogate-pair codepoint are in
play) and its id is pinned. That line ran GREEN in the suite paste on Windows
x86_64 / OXT 9.6.3, and the check is exact - the id is a sha256 over the serialized
bytes, so any mangling of either codepoint changes it. Scoped honestly: one engine,
one platform, those two codepoints. The fixture bytes stay constants and the harness
file stays pure ASCII, because that is what makes a future FAIL here a real finding
rather than noise.

**3. Secure sockets (wss://). HALF ANSWERED 2026-08-24, and the open half is the
security half.** It has its own entry as gap #2 in `07-capabilities-required.md`.
What the live pass settled: `open secure socket ... with message` exists on OXT
9.6.3, connects to a public relay, and carries a full websocket exchange - root
`docs/OXT-ENGINE-NOTES.md` **6.8**. What it did not: the run met an
ordinary public host, so it is equally consistent with verification working and with none
happening at all, and nobody has offered this engine a bad one. Hostname checking,
SNI, failure delivery and TLS versions are all still unmeasured. `open secure
socket` still appears nowhere else in the suite. The advice this question used to
give has inverted: ws:// is now the form with no live run behind it, so it is not
the safer starting point - and the `.onion` composition path (question 7) is a
design choice about anonymity, not a hedge against an unproven transport.

**4. Socket write backpressure on large frames.** The relay layer writes whole
frames with `write to socket` - fine for REQs and typical events, but a large
publish (the frame cap is megabytes) raises a question nothing in the suite has
measured: does a large `write to socket` block the interpreter thread until the OS
buffer drains, queue internally, or partially write? OnionXT's engine hours never
pushed writes that size. If the engine blocks, big publishes need chunking or a
size ceiling below the protocol cap; do not guess - measure, then record it in the
root engine notes.

## Protocol scope (deliberately not yet decided)

**5. Which NIPs next.** Three candidates, in dependency order:

- **NIP-17 / NIP-59 (private DMs via gift wrap)** is the one users will ask for
  first, and its blocker CLEARED on 2026-08-23: gift wrap is three nested layers
  of NIP-44 encryption, and SodiumXT shipped `sxChaCha20IetfXor` as ABI 10
  (`07-capabilities-required.md` gap #1, closed). The building blocks (kind
  builders, the now-complete NIP-44, `nxrSendRaw` for the wrapped kinds) are all
  here; what gift wrap still deserves before design starts is the NIP-44 OXT
  pass, so the layer under it is engine-proven rather than merely vector-proven.
- **NIP-65 outbox routing** - the relay-list event is already built and parsed
  (`nxRelayListBuild` / `nxRelayListParse`); what is NOT decided is the routing
  STRATEGY: read from the author's write relays, write to the recipient's read
  relays, with what fallback and what cap. That is policy, and it belongs above
  the library or in a considered pool layer (question 6), not improvised inside
  the relay client.
- **NIP-42 is done; NIP-13 is done** (build/answer and difficulty/check
  respectively); anything beyond rides `nxrSendRaw` until it earns handlers.

**6. A relay pool abstraction.** Today one handle is one relay and the app owns
multiplexing. A pool layer (dial several, deduplicate events by id, track per-relay
subscription state, reconnect policy) is the natural next layer - but it is policy
with real design choices (when is an event "seen"? which relay's EOSE ends a
query?), and v0.1 deliberately does not guess. If it comes, it comes as a THIRD
file composing `nxr*`, the same shape as OnionXT's `onion-httpd` over `ox*`, so the
relay client stays a transport.

## Performance (measure before optimizing - the OnionXT native-last law)

**7. Byte-loop JSON parsing cost on an interpreter.** `nxRelayParse` /
`nxEventFromJson` walk every byte of every inbound message in interpreted script.
For chat-sized events that is nothing; for a 100 KB kind-30023 article or a fat
contact list, nobody has measured it on a real engine. The family's law (proven in
OnionXT: default to script; reach for native last, and only after an on-engine pass
shows script is too slow) applies verbatim. If it IS too slow, the remedy ladder
is: parse less (the verbatim-slice design already avoids re-serializing), then a
narrow native helper as an upstream request - never a borrowed engine JSON library,
for the canonical-bytes reason in `06-api-reference.md`.

**8. The arithmetic byte-xor in frame masking.** RFC 6455 masking xors EVERY
payload byte, and `nxByteXor` builds each xor from an 8-iteration div/mod loop
because the portable-arithmetic discipline (no `bitXor` - the family has been
bitten by operator portability) applies to the whole file. That is roughly eight
divisions per payload byte, per direction; on a megabyte frame that is millions of
operations in interpreted script. Candidate fixes exist (a 256x256 lookup table is
the classic one; masking only applies client-to-server, so inbound server frames -
unmasked per RFC 6455 - already skip it entirely). Do not take any of them until a
real engine shows a real stall: the harness pins the masked-frame bytes, so any
optimization has a byte-exact regression net waiting.

## Gates (the machinery this member does not have yet)

**9. Headless EXECUTION of the script layer - CLOSED 2026-08-23, exactly as
sketched below.** The interpreter was extended IN ITS HOME (coinxt's
`tools/lcs-interp.py`, whose 300-check gate is the regression proof the
extension is additive) with the constructs this entry measured plus the ones
only execution found (`repeat forever`, the newline named literals,
script-level `local` state - the file-scope error slot no handler could see
until the model learned it), and `nostrxt/tools/check-script-vectors.py` now
EXECUTES the shipped script on every build: 81 checks - the canonical
serializer on escape-torture content, bech32/NIP-19 both directions including
the over-90 deviation, the full padding table, and the COMPLETE NIP-44
encrypt/decrypt path over the real committed coinxt and sodiumxt binaries
through ctypes. `tools/test-script-vectors.py` met the adoption bar the same
day: four seeded defects (a dropped escape, a transposed charset, a nudged
padding, a short-circuited MAC compare) each fail the gate, tree restored
byte-identically. The interpreter copies are drift-gated
(`tools/check-checker-drift.py`, the checker model). The payoff precedent
repeated on first contact, WITH A TWIST the family should keep: the first
model of array comparisons "found" a dead validation block that was actually
the MODEL's bug - refuted against riptide's engine-proven `is empty` refusal
pattern before any healthy code was "fixed". Suspect the probe first; the
corrected model is a named divergence in the interpreter's header. The
original entry stands below as the record of what was asked for.

CoinXT's
`tools/check-script-vectors.py` runs its REAL shipped script headlessly through
`tools/lcs-interp.py` (an interpreter for the LiveCodeScript subset its encoders
use) against published vectors, and it has caught engine-shaped defects no static
gate could - including a chunk-counting rule the model had to learn from a real
engine failure. NostrXT's vector spine today is oracle-only: the KAT proves the
EXPECTED answers are right, not that the script derives them. Extending the
interpreter to this member's dialect would close that gap for the serializer,
bech32 and the NIP-44 schedule - the paths where a silent wrong answer costs the
most. What it would take, measured against what the core actually uses:
`repeat with` loops (including `down to`), `... is among the keys of ...` and the
nested-array writes the tag shape needs, `textEncode` / `textDecode` over UTF-8,
`byte`/`char` chunk expressions with the engine's counting rules, and stubbing the
`cx*`/`sx*` calls the way CoinXT's gate feeds its shim through ctypes. Substantial
but bounded, and the payoff precedent is CoinXT's: its interpreter found a
would-be-red engine line the day it was wired up. (The label this paragraph
closed with - "the first engine pass is what executes it" - retired 2026-08-23;
the gate above executes it on every build. The ENGINE pass is still owed for
parser behaviour, exactly as coinxt's gate says of its own.)

**10. The doc-handler agreement gate.** `06-api-reference.md` promises every public
handler appears exactly once, and `tools/check-doc-handlers.py` is the gate that
holds docs and source to it (the CoinXT `check-doc-handlers` model: a shipped
handler missing from the page, or a documented name no handler defines, each fail
the build). Keeping it honest as the surface grows - especially around the
engine-called handlers, which are documented but not app-facing API - is part of
this member's gate maintenance, not a one-time check.
