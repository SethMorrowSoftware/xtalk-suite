# CLAUDE.md

This file guides Claude Code (claude.ai/code) in the NostrXT member of the xtalk-suite monorepo
(`nostrxt/`). `README.md` indexes the docs; read [docs/02](docs/02-nip01-events.md) (the
canonical bytes) before touching the core and [docs/05](docs/05-relay-client.md) (the socket
state machine) before touching the relay layer. Most lessons here are carried from OnionXT
(sockets), CoinXT (vectors, canonical bytes) and riptide (the no-throw library shape).

House style: no em/en dashes and no curly quotes in any `.md` (hyphens, commas, colons,
parentheses; `tools/check-docs-style.py` enforces it). ASCII only in `.livecodescript`, even in
comments and strings. Comment the *why*, densely; match the surrounding style.

## What this is

**NostrXT** is the client side of the Nostr protocol for OpenXTalk (OXT) / the xTalk family, in
pure LiveCodeScript: NIP-01 events (build, canonical serialization, id, BIP-340 sign/verify),
NIP-19 bech32 entities and NIP-21 `nostr:` URIs, NIP-44 v2 payloads, NIP-01 filters and wire
messages, an RFC 6455 websocket relay client over engine sockets with NIP-42 auth, NIP-13 PoW,
NIP-05/NIP-11 parsing and NIP-65 kind 10002 relay lists. It adds **no cryptography**: sha256,
BIP-340, x-only keys, ECDH and HMAC-SHA256 are CoinXT (the HARD dependency, ABI >= 6);
randomness, constant-time compare and the NIP-44 cipher are SodiumXT (soft; the cipher needs
ABI 10). NIP-04 is out by decision (AES-256-CBC; no AES in the suite, libsodium ships no CBC,
NIP-44 supersedes it; docs/07).

```
src/       nostrxt.livecodescript (the nx* core), nostr-relay.livecodescript (the nxr* client)
examples/  nostrxt-tests (offline harness, nxSelfTest), nostrxt-demo (paste-and-run, carries all 3)
docs/      the numbered series 00, 02-07, 09 (01 and 08 retired; numbers are stable citations)
tools/     run-gates.sh, the oracle and KAT, the vector / execution / doc gates, carried tooling
```

## The two-file split

The split is **load-bearing, not aesthetic** (the suite generator's fold cites this section):

- **The nx* core does no I/O and holds no connection state** (the riptide shape): bytes and
  strings in, bytes and strings out, offline-testable. It embeds verbatim in the suite paste
  (`tests/suite-selftest.livecodescript`) and the harness folds there under prefix `nx1`.
- **The nxr* relay layer defines the engine's `socketError` / `socketClosed` / `socketTimeout`.**
  The embedded OnionXT layer defines the same three and the generator refuses a double
  definition, so the relay layer stays OUT of the paste (the onion-httpd precedent). Its offline
  harness sections are probe-guarded and SKIP there: those are the paste's 2 nostrxt skips. It
  ships in the demo embed and in `riptide/examples/riptide-social.livecodescript`. Load the core
  first: the relay layer composes it and owns only sockets, buffers and handles.
- **The embeddable socket split (2026-08-24).** Each engine message is a thin wrapper over a
  named function (`nxrSocketError` / `nxrSocketClosed` / `nxrSocketTimeout`) that answers "was
  that socket mine, and did I handle it?": true when consumed, false for a foreign socket. A
  stack that must define the three itself drops the wrappers (the suite's
  `tools/sync-demo-embeds.py` DROP_HANDLERS, keyed by (app, library) PAIR) and calls the named
  function where it would otherwise `pass`. riptide-social carries OnionXT and this layer that
  way. The "false for a socket that is not ours" contract is pinned offline in
  `examples/nostrxt-tests.livecodescript`, because getting it wrong is a hang, not an error.

## How NostrXT differs from its siblings

1. **Unlike OnionXT, the core is stateless and does no I/O.** Only nxr* owns sockets.
2. **Unlike CoinXT, the interop surface is TEXT.** The canonical NIP-01 serialization is the
   contract; one wrong escape byte changes every event id. So the serializer is OWNED (a stock
   JSON encoder escapes control bytes NIP-01 passes verbatim) and pinned byte for byte.
3. **It carries its own bech32/bech32m, uncapped.** CoinXT's enforces BIP-173's 90-char cap both
   ways and keeps its bit converters private; NIP-19 waives the cap for TLV. NostrXT enforces
   NIP-19's 5000-char SHOULD instead and the KAT asserts the over-90 deviation on purpose.
   Byte shuffling, not cryptography (upstreaming was declined: docs/07).
4. **Two error conventions, never mixed.** Core nx* NEVER throws: functions return empty (or
   false) and record the reason for `nxLastError()`; every cx*/sx* call sits in a try. Relay
   nxr* commands report through `the result`: empty on success, "NostrXT relay: ..." on refusal;
   `nxrConnect` returns the integer handle, so callers test `the result is an integer`.

## Rules

1. **Add no cryptography; compose CoinXT and SodiumXT.** A missing primitive lands upstream first
   (its own ABI bump and tests), then is composed here; a hand-rolled cipher has no tests anyone
   trusts. NIP-44's ChaCha20 went that way (SodiumXT ABI 10 `sxChaCha20IetfXor`, 2026-08-23;
   docs/07 gap #1). On an older installed SodiumXT, `nxNip44Encrypt` / `nxNip44Decrypt` fail
   closed naming it, and the harness proves MAC-before-cipher on any install.
2. **Verify, then trust.** An inbound event is untrusted text until `nxEventVerify` passes (id
   recomputed from the fields AND signature checked). The relay layer verifies by default and
   delivers failures as "invalid", never as events; `nxrSetVerify` is the per-relay, eyes-open
   opt-out. Relay message types compare byte-exact ("EVENT", not "event"), because `is` folds case.
3. **The canonical bytes are law.** `nxEventSerialize` is the id preimage: exactly seven escapes,
   every other byte (control bytes included) verbatim, UTF-8, no whitespace. Any change is
   interop-visible: re-run `tools/nostr-kat.py`, re-paste the harness constants, and the label
   resets to "needs an OXT re-pass". Never "clean up" the serializer.
4. **Fail closed on every wire and parse error** (bad checksum, truncated TLV, MAC mismatch,
   hostile frame length, unparseable relay message); the relay layer tears the connection down.
   No silent fallbacks, no truncation.
5. **Own the lifecycle.** Every `nxrConnect` has an idempotent `nxrDisconnect`; `nxrShutdown`
   closes everything and is safe twice; OXT has no deterministic unload hook, so the app frees
   on `closeStack`. A stale handle or socket id is a clean no-op.
6. **Secret hygiene.** Secret keys cross the API as hex by design, so: never log an nsec or put
   one in an error message; `nxUriEncode` REFUSES to wrap an nsec; `nxKeyGenerate` refuses
   without SodiumXT randomness rather than degrading. Documented limit: OXT script variables are
   not locked memory.

## Gotchas

1. **`is` folds case.** Tag names, relay message types, base64 accept values and bech32
   round-trips compare through `nxStrEqExact` (core) / `nxrStrEq` (relay). A folded compare on
   "EVENT" vs "event" silently accepts a non-conforming relay. (Array keys fold too: suite
   engine note 2.7.)
2. **`itemDelimiter` / `lineDelimiter` are global mutable state** (suite engine note 2.3). Every
   chunk read saves, sets, uses and restores; internal lists flow as 1-based sequential ARRAYS
   counted with the delimiter-free `is among the keys of` walk.
3. **JSON is byte work.** The family checker refuses braces outside string literals, so JSON is
   built from brace characters inside quoted literals and parsed by walking UTF-8 bytes.
   `f(x)["k"]` does not parse: put every function result into a local before subscripting.
4. **Number coercion is a canonical-form hazard.** "1e3" `is an integer`, so `nxEventFromJson`
   requires created_at and kind to be PLAIN DIGIT runs before they reach the serializer.
5. **OnionXT's socket lessons, inherited whole** (suite engine notes 6.1, 6.2): byte
   discipline, `with message` everywhere, short reads are normal, `open socket` is async and
   failure arrives as a `socketError` MESSAGE, watchdog every handshake, store the engine's socket
   id verbatim with a `|name` suffix; act only on OWN ids in the socket messages, `pass` the rest.
6. **The NIP-44 length policy is the vectors', not the newest spec text's.** The published
   vectors pin the u16 prefix and mark 65536+ invalid, so plaintext over 65535 bytes refuses,
   fail closed. The spec's sketched 6-byte extended prefix has no vectors; supporting it is a
   deliberate change with new KAT rows, never a quiet edit.
7. **wss:// connects; that is not "wss verifies"** (suite engine note 6.8). On 2026-08-24
   `open secure socket` connected to wss://nos.lol and carried the handshake, a publish and the
   ok-true: that settles the FORM. It does not settle the SECURITY: no bad certificate has been
   offered, so verification is unproven in both directions, as are SNI, TLS versions and failure
   delivery. Do not let "wss works" become "wss verifies" in any file. The plain ws:// path has
   never run. `open secure socket` appears in no other member's source.
8. **`and` / `or` evaluate BOTH operands** (suite engine note 2.5). `if not nxIsDigits(X) or
   X + 0 < 1` still runs `X + 0`, and arithmetic on non-numeric text is a HARD engine error.
   Three sites were fixed 2026-09-09 as nested `if`s; one (`nxJsonPathNode`) was reachable from
   relay bytes, so a path step like "abc" was an uncaught throw from a never-throw library, and
   its early-out repeats the "/" itemDelimiter restore (gotcha 2). The class first hit
   2026-08-23 ("1e" reaching `+ 0`). Nest the guard.
9. **The defect classes the 2026-08-23 adversarial pass found**, each fixed and pinned as a
   harness regression; do not reintroduce one. The JSON path walk compared object keys with `is`
   (every single-letter tag filter broke through the #e/#E probe loop; "1000" matched "1e3" as a
   NIP-05 name). Duplicate JSON object keys desynced first-wins (`nxJsonGet`) from last-wins
   (`nxEventFromJson`) readers, the show-the-verifier-one-content trick; now refused outright.
   The number parser accepted "07", "1e" and "1-2". The bech32 separator bound carried the
   reference's 0-based `pos + 7` into 1-based code and refused BIP-173's own "A12UEL5L".
   `nxCtEqualHex`'s two paths disagreed on hex case, so a verdict depended on SodiumXT. An
   over-255-byte naddr identifier was silently DROPPED, not refused. The relay layer called the
   core's PRIVATE `nxToLowerAscii` cross-script (every handshake broke in the two-stack
   deployment; the demo embed masked it). `nxrTeardown` dispatched "disconnected" before clearing
   its tables, so an app answering with `nxrDisconnect` re-entered (a second close frame,
   unbounded recursion); teardown now deletes first and dispatches from saved values.
10. **`tools/test-script-vectors.py` mutates the SHIPPED `src/nostrxt.livecodescript` IN PLACE**
    (restored byte-identically, try/finally). Run it serially: a parallel job over one checkout
    once read the mutated file and reported a phantom serializer FAIL.
11. **Suspect the probe first.** The first interpreter model of array-vs-empty comparisons
    (2026-08-23) "found" a dead tag-validation block; riptide's engine-proven `is empty` idiom
    showed the MODEL was wrong (a populated array is NOT empty to `is`); now a named divergence.

## As-built notes: the engine evidence ledger

One row per dated record, newest last. Paste new engine or live-relay results here (the suite
runbook points at this heading); engine behaviour also goes in the suite's engine notes.

| Date | Engine / platform | What ran | Result |
|---|---|---|---|
| 2026-08-23 | none (headless) | v0.1.0 built (core, relay, harness, docs); `tools/nostr-kat.py` swept the complete published sets: the BIP-340 csv with every negative, the official NIP-44 v2 set incl. long-message and invalid rows, BIP-173 valid/invalid, the NIP-19 examples | all gates green; "verified statically" |
| 2026-08-23 | none (review) | pre-engine adversarial pass: 8 independent reviewers traced the algorithms against their specs | 25 defects, each fixed and pinned as a harness regression (gotcha 9) |
| 2026-08-23 | none (SodiumXT C KATs under ASan/UBSan) | `sxChaCha20IetfXor` shipped as SodiumXT ABI 10; its C KATs cross-checked against this member's oracle (RFC 8439 ChaCha20) and the pinned libsodium tarball's expectation file | the seam, both probes and the harness branch flipped with zero code changes here; the suite's `tools/check-handler-calls.py` KNOWN_MISSING entry was deleted, so that gate proves the composition resolves |
| 2026-08-23 | none (lcs-interp.py; the committed coinxt ABI 6 and sodiumxt ABI 10 x86_64-linux binaries) | `tools/check-script-vectors.py` landed: the serializer on escape-torture content, bech32/NIP-19 both ways incl. over-90, the full padding table, the complete NIP-44 path | 81 checks green; `tools/test-script-vectors.py` showed it fails on 4 seeded defects (dropped escape, transposed charset, nudged padding, short-circuited MAC) |
| 2026-08-24 | Windows x86_64, OXT 9.6.3 | the folded harness in the suite paste (`nx1nxSelfTest`; the whole paste ran 2,373 / 0 / 3) | **274 passed, 0 failed, 2 skipped** (both relay sections, absent by design). NIP-44 official vectors decrypted and re-encrypted through the real ABI 10 cipher; every interpreter-modelled engine pin held (the 1e3 fold, the trailing-delimiter eat, case-folding `is`, the base64 leniency traps); event C's non-BMP `textDecode` round trip (euro sign + 4-byte emoji) is faithful; the `nxB64Encode` strip is correct in effect, the raw `base64Encode` emission was not recorded |
| 2026-08-24 | Windows x86_64, OXT 9.6.3 | `examples/nostrxt-demo.livecodescript`, first open, then its live leg to wss://nos.lol | boot self-check 9/9; relay open, identity derived, kind-1 signed, verified, published, ok-true for its id. The suite's first `open secure socket` (engine note 6.8) |
| 2026-09-09 | none (headless) | the `or` no-short-circuit fix (gotcha 8), three sites | `tools/check-script-vectors.py` 81 -> 90 checks; the refusals are not in the member harness yet, so no engine pass has run them |
| 2026-09-24 | none (headless; lcs-interp.py over the committed coinxt and sodiumxt binaries) | the 2026-09-09 fix pinned in `examples/nostrxt-tests.livecodescript` (3 checks, sections 4 and 14, each call in a try so a regression is a FAIL line, not a throw); the whole harness counted in all six CoinXT / SodiumXT combinations to set the suite paste's floor; the demo's row-34 buttons (Unsubscribe, Answer auth, Send raw) | attempted 279 in the 2026-08-24 configuration (its 276 plus the 3 pins; the unpinned harness measured 276, the dated record exactly), 278 without SodiumXT, 280 on a pre-ABI-10 SodiumXT, 253 without CoinXT, the 3 pins passing in all six (the one FAIL per run is the interpreter's fixed clock under "nxUnixNow is after the fixture era"): the suite core's floor is 278 with CoinXT and 253 without, keyed on this member's cached probe. The vector gate's delimiter-survival check was BLIND (still green with the restore deleted, because it asked a second `nxJsonGet`, which re-saves the leaked "/"); it now reads the delimiter against a non-comma sentinel, and `tools/test-script-vectors.py` seeds that defect as its 5th mutation. The three pins, the floor and the three buttons: verified statically; needs an OXT pass (the buttons + a live-relay pass) |
| 2026-09-24 | Windows (the engine reports Win32; OXT version and OS build not recorded), over the 2026-09-12 CoinXT and SodiumXT DLLs (the maintainer's account) | the folded harness in the D-23 suite paste (built from `9aa62c8`; this harness as at `6401e43`; the whole paste ran 2,620 / 5 / 3, none of the 5 nostrxt's) | **277 passed, 0 failed, 2 skipped**: 279 attempted, the previous row's count for this configuration (CoinXT + SodiumXT ABI 10) exactly, over the core's probe-selected floor of 278 (PASS; board row 279 / 0 / 2 with the core's own two checks). Sections 1-16 green, including the three 2026-09-09 pins (a non-numeric array step and a non-numeric port refuse, never a hard error; the step's refusal restores the itemDelimiter), the NIP-44 official vector round trip through the ABI 10 cipher, and "nxUnixNow is after the fixture era" on the engine's clock (the interpreter's one FAIL); the 2 skips are section 17 (the relay layer, not in the paste by design). Closes the previous row's label on the three pins and the 278 floor. Still owed an engine: the other five configurations (the 253 floor among them), section 17, the three buttons, and the fix's third site (`nxPowCheck` on a non-digit target), which no harness or gate runs |

## Status

The nx* core, NIP-44 included, is **engine-proven 2026-08-24** and again **2026-09-24** (Windows,
the engine reports Win32: 277 / 0 / 2, the 2026-09-09 fix's pins and the suite paste's 278 floor
among what ran); the relay connect / handshake / publish / ok path is **live-proven 2026-08-24**
(all in the ledger). The receive leg (REQ, EVENT, EOSE, CLOSED, NOTICE), NIP-42, every ws:// path
and the offline relay harness sections (they SKIP in the paste; the demo's test button that runs
them has no recorded engine run) keep "verified statically; needs an OXT pass + a live-relay
pass"; the demo's Answer auth, Unsubscribe and Send raw buttons (added 2026-09-24) make the
NIP-42 and CLOSED legs button work, and have not run either. Bad-certificate TLS behaviour is
unmeasured (gotcha 7). No engine has run the paste's CoinXT-less floor (253, interpreter-measured)
or the fix's latent third site, `nxPowCheck` on a non-digit target, which no harness or gate runs
at all. Open work: the suite's docs/WORK-PLAN.md.

## Build and gates

```sh
bash tools/run-gates.sh     # the member's one gate list: what CI and the suite's build-all.sh run
```

- `tools/check-livecodescript.py`: the unified family checker (byte-identical, drift-gated at
  the suite root). OXT has no headless compile, so a script change is not done until it passes.
- `tools/nostr-kat.py --check` sweeps the full published sets through `tools/nostr_reference.py`,
  the independent oracle (own secp256k1, BIP-340, bech32, HKDF, ChaCha20, NIP-44, serializer)
  that anchors to published vectors at import and REFUSES TO LOAD broken. Without `--check` it
  prints the constants the harness pins: never hand-edit a harness vector; edit the KAT fixture,
  re-run, paste the block. The RFC 6455 values are DERIVED (anchored to python-websockets; the RFC
  hosts were unreachable from the build environment) and match the RFC's published example.
- `tools/check-selftest-vectors.py --check`: every harness constant re-derives BY NAME, both ways.
- `tools/check-script-vectors.py --check` EXECUTES the shipped core through `tools/lcs-interp.py`
  (coinxt's copy, drift-gated). Tier 2 feeds cx*/sx* from the committed sibling x86_64-linux
  binaries via ctypes (`../coinxt`, `../sodiumxt`, or `XTALK_SIBLINGS` / `XTALK_SIBLING_<NAME>`;
  absent SKIPS loudly, `XTALK_REQUIRE_SIBLINGS=1` fails); stand-ins are a deterministic
  `sxRandomBytes` and hashlib for `sha1Digest`. It settles LOGIC, not parser behaviour, so it
  upgrades no label. `tools/test-script-vectors.py` is its mutation drive (slow; gotcha 10).
- `tools/check-docs-style.py`, and `tools/check-doc-handlers.py --check` (docs and source agree on
  the public surface both ways; `docs/06-api-reference.md` names every public handler).

**Done means:** the gates are green, every carrier is regenerated at the suite root
(`python3 tools/build-suite-selftest.py`, `python3 tools/sync-demo-embeds.py`: the suite paste
carries the core, nostrxt-demo core + relay + harness, riptide-social core + relay), and the
change has had, or is flagged as needing, an engine pass. A serializer, bech32 or NIP-44 change
lands new KAT rows in the SAME change. A change needing a new CoinXT or SodiumXT primitive
splits, upstream first (`sxSha3_256` for onionxt and `sxChaCha20IetfXor` here were composed with
zero code changes). Work on a per-task branch with a draft PR (the suite root's CLAUDE.md).
