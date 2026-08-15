# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository. Read it before touching anything; it carries everything already learned the
hard way across the sibling repos so it never has to be re-learned here.

> **Folded into the monorepo 2026-08-15.** This directory was copied verbatim (via
> `git archive`, tracked files only) from the standalone `hold-em` repository, which
> becomes a mirror; development happens here now, like every other member. The seed
> docs the suite had carried at `docs/holde-em/` (stale at pre-implementation while
> this repo reached v0.18.0) were REMOVED in the fold - this directory is the one
> authority. What the fold changed, each per suite law:
>
> - `tools/check-livecodescript.py` was REPLACED with the suite's unified checker,
>   registered in `tools/check-checker-drift.py` and fixture-tested by
>   `tools/test-checker.py` - never edit it here alone. First contact found TWO real
>   engine traps this repo's own lineage could not see, both in the Level 0 deal
>   path: `heXorSeedsHex` walked its hex pairs with `repeat with ... step 2` (OXT
>   ignores the increment - it would have XORed 63 OVERLAPPING pairs and derived a
>   wrong-but-internally-consistent deck), and `heDeckFromStreamKey` re-threw from
>   inside a `catch` (the throw never reaches the caller on OXT). Both are rewritten;
>   both handlers are re-labelled "verified statically; needs an OXT re-pass", and
>   whether the PREVIOUS on-engine Level 0 runs dealt from the stepped or the
>   1-stepped stream is exactly what that re-pass should establish (the Python KAT
>   mirrors pin the 2-stepped semantics).
> - The hold-em lineage checker survives as `tools/check-holdem-idioms.py`: eight of
>   its checks (H6 chunk-of-array, H7 bitwise, engine-token names, undeclared catch
>   vars, command-with-parens, dynamic property names, message-box prose, undeclared
>   k-constants) have no unified-checker counterpart and every one has shipped-defect
>   provenance here. It runs IN ADDITION via `tools/build-all.sh`; porting those
>   checks INTO the unified checker (and retiring the file) is recorded follow-up.
> - All ten pure-logic gates (the idiom checker, `check-docs.py`, the seven KATs,
>   `logic-fuzz.py`) are wired into the suite's `tools/build-all.sh --gates`, which
>   CI runs on every push; this member's own `.github/workflows/ci.yml` stays for
>   standalone work but is inert here (GitHub runs only root workflows).
> - `src/holdem.livecodescript` is EXEMPT in the suite's `tools/check-ui-kit-drift.py`
>   ("game table on the b2k Kit; suite-kit chrome is phase-2" - the box2dxt games'
>   reasoning). Registering it exposed a latent suite-gate bug the fold fixed: the
>   gate's window-building regex ended in a literal backspace byte, so the
>   width/height spelling had never matched; the rect spelling this stack uses was
>   also unknown to it (and to `tools/check-stack-size.py`, which now parses it).
> - The stack ships at 1024x690 - 50px over the suite's 720p height budget, with the
>   status line and quick-bet row genuinely below y=640. It carries a written SKIP in
>   `tools/check-stack-size.py`; the 720p re-layout is recorded follow-up work, not a
>   number a gate can hold down.
> - The `he*` prefix is registered in `tools/check-handler-calls.py`, which also
>   learned to strip `/* */` block comments (this file's header changelog leaked
>   prose into its candidate set - and 31 phantom "definitions" out of it, suite-wide).
> - Registered in the `start-here.livecodescript` launcher. NOT folded into the
>   generated suite selftest or its coverage gate: this member's harness lives
>   EMBEDDED in the game stack (`heRunSelftest`), not as a separate foldable file -
>   extracting it (or teaching the fold machinery an embedded harness) is recorded
>   follow-up, the box2dxt precedent.
>
> Where this file and the suite root `CLAUDE.md` conflict, this file wins inside
> `holde-em/`; paths in the docs below may still read as if this were its own repo
> root (the suite's standing consolidation-debt caveat).

## What this is

**holde-em** is a serverless online no-limit Texas Hold'em game for **OpenXTalk (OXT)**
and the wider **xTalk** family (also compatible with **LiveCode 9.6.3+**). It is a
pure-script project: **no native code lives in this repo**. It composes four sibling
extensions, each of which wraps its own native library behind a friendly xTalk surface:

```
your table stack (this repo)                 src/holdem.livecodescript
   |- game logic: transcript, deal ladder, betting, evaluator = pure xTalk, here
   |- bt*   TorrentXT   org.openxtalk.library.torrent    rp1 messaging, DHT rendezvous, BEP44
   |- sx*   SodiumXT    org.openxtalk.library.sodium     identity, sealing, hashing, randomness
   |- ox*   OnionXT     (script library + local tor)     onion tables, oracle hosting  [optional]
   |- b2k*  Box2Dxt Kit org.openxtalk.box2dxt            card sprites, chip physics, frame loop
```

The three documents that govern this repo:

- **`holdem-spec.md`** — the design contract (deal protocol ladder, transcript, threat
  model, settlement receipts). Where code differs from the spec, the code wins and the
  spec gets updated.
- **`IMPLEMENTATION-PLAN.md`** — the phased build order with exit criteria per phase.
- **This file** — how to work here without getting bitten by OXT.

**Status: Phase 2 online lobby + online play (2d) written at v0.18.0, on Phase 1
hotseat.** The project was seeded from Box2Dxt's `docs/holde-em/` folder, built out in
its own repository, and folded home into the suite 2026-08-15 (the blockquote above).
README.md's Status section is the current authority; IMPLEMENTATION-PLAN.md carries the
per-phase ledger.

**Because chips may someday carry real value**, the security posture is not optional
polish: read spec sections 2 (threat model), 13 (value-readiness), and 16 (security
checklist) before writing any protocol code, and follow section 16 as law.

## The three layers of the platform (for a fresh Claude)

1. **`.livecodescript` (LiveCodeScript / xTalk)** — everything in this repo. An
   English-like, message-path language: handlers are `on ...`/`command ...`/
   `function ...` closed by `end <name>`; commands report through `the result`,
   functions return values; controls carry **custom properties** (a per-object text
   datastore); timers are `send <msg> to <obj> in <ms> milliseconds`; TCP is available
   through engine sockets (`open socket`, `accept connections`). There is **no headless
   way to compile or run it** — the IDE is a GUI runtime. Development therefore leans on
   static gates (below) plus a human "OXT pass".
2. **LCB (LiveCode Builder)** — the extension language the *siblings* are written in:
   `foreign handler` declarations bind a flat C ABI, packaged as installable extensions;
   the engine resolves each extension's bundled native library via
   `the revLibraryMapping` automatically (no loose libraries, no `LD_LIBRARY_PATH`).
   **This repo writes no LCB** — it only calls the public handlers the installed
   extensions put on the message path.
3. **The C shims / native libraries** — libtorrent-rasterbar, libsodium, Box2D, wrapped
   by their repos behind frozen, versioned C ABIs (`btx_*`, `b2lc_*` symbol prefixes).
   Family conventions you will see reflected in every API: ids cross the FFI as
   **positive int handles** (0 = invalid; stale handles are harmless no-ops, never
   crashes), reals as `double`, booleans as `int`, and **all inbound events arrive
   through poll-drained queues** dispatched on the message path — no callback ever runs
   script from a foreign thread.

## Commands

**Static verification** (the only automated gate that exists for xTalk; run BOTH after
**every** `.livecodescript` edit, and in CI):

```sh
python3 tools/check-livecodescript.py   # the suite's UNIFIED checker (drift-gated copy)
python3 tools/check-holdem-idioms.py    # this member's extra idiom checks
```

Since the 2026-08-15 fold, `check-livecodescript.py` is the suite's unified twelve-check
gate (ASCII, balance incl. switch/try, constants-before-use, token-shadow, zero-arg
statement calls, repeat-step and throw-in-catch refusals, and the per-dialect
antipattern sets) - byte-identical in every member and held so by the suite's
checker-drift gate: never edit the copy here alone. `check-holdem-idioms.py` is the
hold-em lineage checker it replaced, kept because eight of its checks (see its
docstring) exist nowhere in the unified tool and each has caught a real shipped defect
here. Exit non-zero on any failure, either tool.

**Pure-logic pinning** (Phase 1+): the evaluator vectors, betting-engine cases, and
protocol KATs run headless in CI because they are plain algorithms — the one part of
this project that CAN be fully machine-verified. The gates, in the order CI runs them:

```sh
python3 tools/check-livecodescript.py   # dialect gates, every .livecodescript
python3 tools/check-docs.py             # smart-quote scan over *.md
python3 tools/evaluator-kat.py          # spec 8.2 vectors (mirror of heEval7/heRank5)
python3 tools/betting-kat.py            # spec 8.1/8.3 cases (mirror of heBetApply/heSettleOf)
python3 tools/shuffle-kat.py            # playable integer deal (mirror of heShuffleDeck)
python3 tools/protocol-kat.py           # spec 6/7.1 crypto deal (Phase 2 target)
python3 tools/sounds-kat.py             # vendored casino-audio WAVs <-> stack mapping
python3 tools/logic-fuzz.py             # INDEPENDENT-reference fuzz (rules, not the port)
```

The KATs above are *mirrors* — ported line-for-line from the xTalk so a green KAT plus a
green on-engine harness pins the two together. That proves "the port matches the engine",
not "the rules are right": a bug living in both the xTalk and its twin passes unseen.
`tools/logic-fuzz.py` closes that hole — it drives the same mirror functions but checks
them against a SECOND, independently-written evaluator and side-pot settlement (plus
whole-game invariants: chip conservation, no negative stacks, termination). It runs the
evaluator EXHAUSTIVELY (all 2,598,960 five-card hands → exactly 7462 classes) and fuzzes
settlement/games over ~90k configs with fixed seeds (~30 s; `--full` does the exhaustive
order-isomorphism, `--quick` a 5 s smoke). This is the committed backing for any
"verified sound by property tests" claim — do not make that claim without it.

The KAT vectors are also embedded in the stack's own self-test (`heRunSelftest` in the
message box), so a green harness run on-engine plus green KATs in CI pins the xTalk to
the mirrors. Keep it that way: game rules, shuffle, and settlement must live in
handlers that take values and return values, with no UI reads inside.

**The single stack.** `src/holdem.livecodescript` is one paste-and-run stack: the
hotseat game AND its self-test (`heRunSelftest`) and a SodiumXT diagnostic
(`heProbeSodium`) are folded into it. There is no second stack.

**Binary stays out of the playable path (v0.2.0, the hard-won rule).** Repeated OXT
passes threw double/binary conversion errors wherever script touched FFI-bridged
binary (SodiumXT `Data`) through the chunk/arithmetic evaluator — even after copying
the element to a local (H6). The resolution: the **playable deal uses a pure-integer
PRNG** (Park-Miller MINSTD: only `+`, `*`, `mod`, every product `< 2^53` so it is
exact in a double), seeded from `sxRandomUniform` (an *integer* result — no binary
crosses into script) when SodiumXT is present, and from engine time+`random()` as a
labelled practice fallback otherwise. Nothing in a played hand calls `sxHash`,
`sxRandomBytes`, `sxBin2Hex`, `textEncode`, or any `byte`/`byteToNum`/`numToByte`.
The cryptographic Level 0 deal (commit-reveal keyed-stream, spec 7.1) stays specced
and KAT-pinned in `tools/protocol-kat.py` as the Phase 2 / value-path target; wire it
back only behind a confirmed `heProbeSodium` (which tries each `sx*` call in its own
`try` and names any that throws).

**RESOLVED (v0.4.0) — `sxHash` needs an output-length argument.** The v0.2.0 probe
found `sxHash` threw while `sxRandomUniform`/`sxRandomBytes`/`sxBin2Hex` worked; reading
SodiumXT's real `docs/api-reference.md` (cloned into the session) showed why: the
signature is **`sxHash(pData, pOutLen)`** — the earlier code called `sxHash(data)` with
one argument, which throws. Use `sxHash(data, 32)` for BLAKE2b-256. Two other guessed
shapes were also wrong and are now corrected against the real API: **`sxSignKeypairFrom-
Seed pSeed, out rPub, out rSec`** is a *command with out-parameters* (not a function
returning an array), and hole-card delivery uses **`sxSeal(msg, recipPub)` /
`sxSealOpen(sealed, recipPub, recipSec)`**. Everything crosses as `Data`; `textEncode`
strings before hashing/signing, `textDecode(..., "ascii")` the hex helpers back to
text. The crypto seams (`heHash32`, `heHashDomHex`, `heDeriveIdentity`, `heSignDetachedD`,
`heVerifyDetached`, `heSeal`) now wrap these one place each; `heProbeSodium` exercises
the full roundtrip. Lesson: **read the sibling's `docs/api-reference.md`, do not guess
FFI signatures** — the family repos are addable to the session for exactly this.

**Do not claim runtime behavior you cannot observe.** Anything visual, timed, socket-,
or extension-touching gets the phrase "verified statically; needs an OXT pass" and the
user confirms in the IDE. This discipline is house law across the family.

## Required extensions

| Extension | Library id | Prefix | Needed from | Notes |
|---|---|---|---|---|
| **TorrentXT** | `org.openxtalk.library.torrent` | `bt*` | Phase 2 | ABI v8+. Uses: session settings, `btAddInfohash` phantom swarms, `btDhtAnnounce`/`btDhtGetPeers`, **rp1** (`btRp1Enable/SetToken/Send/Poll`), BEP44 (`btDhtBep44SignBuf` + `btDhtPutSigned`, `btDhtGetMutable`), `btMapPort` for the optional direct-TCP upgrade. Also install its `torrent-helpers` poll dispatcher (`btStartPolling`). |
| **SodiumXT** | `org.openxtalk.library.sodium` | `sx*` | Phase 2 (Phase 1 uses only `sxRandomBytes`/`sxHash` if installed) | Identity, sealing, commitments, randomness. **Phase 4's ristretto255 surface SHIPPED 2026-08-15** (SodiumXT ABI 8, `sxRistretto*` — cross-checked KATs green, handlers still need their OXT pass). |
| **OnionXT** | script libraries `onionxt` (+ `onion-httpd`) | `ox*` | optional (onion tables; Phase 3 oracle hosting) | Not an extension bundle: two `.livecodescript` libraries plus a **locally running tor daemon** (SOCKS 9050, control 9051). Needs SodiumXT ABI >= 6 for deterministic onions. |
| **Box2Dxt** | `org.openxtalk.box2dxt` + the Kit stack | `b2*` / `b2k*` | Phase 1 | Presentation only: spritesheet cards, physics chips, the `on b2kFrame` loop. The Kit is a `.livecodescript` stack (`box2dxt-kit`); whether this repo `start using`s it or embeds a synced copy between sentinels (the Box2Dxt-examples pattern) is a Phase 1 decision recorded in the plan. |

Install all of them through the OXT **Extension Manager**; each bundles its native
libraries per platform — nothing else to install, no `sudo`. Native **sessions bracket
the stack's life**: start in `openStack` (e.g. `btStartSession` → read handle from
`the result`), tear down in `closeStack` (`btStopPolling`, `btStopSession`) — OXT has no
deterministic extension-unload hook, so a session left running leaks its threads.

## API quick-reference (the handlers this game actually calls)

Enough surface that work here rarely needs the sibling repos open. Authoritative docs:
each sibling's `docs/api-reference.md`.

**TorrentXT** — commands report via `the result`; events drain via `btPoll(sSession)` /
`btRp1Poll(sSession)` each poll tick (the helpers' 250 ms cadence is fine).
`btStartSession`/`btStopSession`/`btLastError()`; `btSetBool sSession, "enable_dht"|
"enable_upnp"|"enable_natpmp", true`; rendezvous: `btAddInfohash(sSession, tHex40,
tPath)` + `btDhtAnnounce`/`btDhtGetPeers`; **rp1**: `btRp1Enable` (before adding swarms),
`btRp1SetToken sSession, tSignedBlob` (lands in peers' `rp1Handshake` event as `token`),
`btRp1Send sSession, tPeer, tBytes` (opaque, <= 60000 bytes, flushed on libtorrent's
<= 1 s per-peer tick — **turn-rate, not frame-rate**), `btRp1Poll` (events: `rp1Handshake`
/ `rp1Message` with `peer`, `payload`); BEP44: `btDhtBep44SignBuf(salt, seq, value)` →
sign externally with `sxSignDetached` → `btDhtPutSigned` (the secret key never crosses
into TorrentXT), `btDhtGetMutable`, `btDhtPutImmutable`/`btDhtGetImmutable`; ports:
`btMapPort` (confirmed by a `portMapped` event) for the optional direct-TCP lane.

**SodiumXT** — everything is `Data`; `textEncode` xTalk strings before hashing/sealing;
failures **throw** (wrap in `try`), except `sxSignVerifyDetached` which returns false.
**Exact signatures matter (see the resolved-`sxHash` note above):** identity/signing is
`sxSignKeypairFromSeed pSeed, out rPub, out rSec` (a **command with out-params**, not a
function), then `sxSignDetached(msg, sec)` → `Data` and `sxSignVerifyDetached(sig, msg,
pub)` → `Boolean` (never throws). Private lanes: `sxBoxKeypair`/`sxBoxKeypairFromSeed
pSeed, out rPub, out rSec` (commands), sealed boxes `sxSeal(msg, recipPub)` /
`sxSealOpen(sealed, recipPub, recipSec)` (anonymous sender), `sxBox`/`sxBoxOpen`
(authenticated). Symmetric: `sxSecretBox`/`sxSecretBoxOpen`, `sxAeadEncrypt`/
`sxAeadDecrypt` (nonces handled internally). Hashing/commitments: **`sxHash(pData,
pOutLen)`** (the output length is mandatory — use `32` for BLAKE2b-256), `sxHashKeyed(pData,
pKey, pOutLen)`, `sxHmacSha256`. Hex helpers `sxBin2Hex`/`sxHex2Bin` take and return
`Data` (ASCII) — `textDecode(..., "ascii")` for a display string. Randomness:
`sxRandomBytes`, `sxRandomUniform`. Utility: `sxMemEqual` (constant-time — the ONLY
legal way to compare secrets/MACs), `sxBin2Hex`/`sxHex2Bin`, `sxBin2Base64`/
`sxBase642Bin`. Passphrases (if a UI lock is ever added): `sxPwHash*` (Argon2id).
Shipped for Phase 4 (SodiumXT ABI 8, 2026-08-15): `sxRistrettoFromHash(h64)`,
`sxRistrettoScalarMultPoint(k, p)`, `sxRistrettoScalarRandom()`,
`sxRistrettoScalarInvert(k)` (all -> 32-byte `Data`, throw on failure - the
catch path is the detection path), `sxRistrettoPointValid(p)` -> Boolean (a
predicate, never throws on malformed input); the 64-byte from-hash input is
`sxHash(tData, 64)`. Verified statically; needs an OXT pass.

**OnionXT** — assumes a reachable tor daemon; it is a transport + naming layer and adds
no cryptography of its own (composes SodiumXT). Dial-out: `oxDial` through SOCKS5 →
stream id, `oxWrite`, `oxCloseStream`, callbacks via `oxSetStreamCallback`. Hosting:
`oxConnectControl` (+ `oxSetControlPort`/`oxSetSocksPort`), `oxCreateService` /
`oxCreateServiceFromSeed` (deterministic address from a seed), `oxPublishService`,
`oxRemoveService`. Addresses: `oxAddressFromPublicKey`/`oxPublicKeyFromAddress`/
`oxIsValidAddress` (a v3 onion address IS an ed25519 public key — self-authenticating
rendezvous). Readiness: `oxIsReady`, `oxBootstrapProgress`.

**Box2Dxt Kit** — pixels/degrees, y-down; the Kit drives a fixed 1/60 s loop and calls
`on b2kFrame` in your script each tick. Sheets: `b2kSheetLoadAtlas`, `b2kSheetScale`,
`b2kSheetFrameNames`, and **`b2kSheetEnsureIcon` at build for every frame that can
appear** (a lazy first slice costs ~250 ms). Sprites: `b2kSpriteNew`, `b2kSpritePlay`
(one-shots fire `b2kSpriteOnFinish` — see carried gotcha 19), `b2kSpriteSetFrame`,
`b2kSpriteFPS`, `b2kSpriteFlipH`, `b2kSpriteMoveTo` (never a raw `set the loc`),
`b2kSpriteBind`/`b2kSpriteRemove`. Bodies (chips): `b2kSpawnBox`/`b2kSpawnBall` are
*commands* → `put the result into tCtrl` immediately (gotcha 27); one `b2kForce` toss,
then let them sleep (gotcha 17). Sensors/contacts (if ever used) go to
`b2kContactTarget` (gotcha 14). Deterministic stepping exists (`b2kStepOnce`,
`b2kInputInject`) but this game does not depend on physics determinism — physics is
cosmetic here by design (spec section 11).

## LiveCodeScript / OXT gotchas (carried from Box2Dxt, original numbering kept)

`holdem-spec.md` cites these by number, so the Box2Dxt numbering is preserved; gaps are
lessons that only apply to platformer-style games and were left behind. OXT's compiler
is **stricter than LiveCode's**; every one of these broke a real build or shipped a real
bug in the family.

1. **No smart quotes.** Curly quotes (U+201C U+201D U+2018 U+2019) anywhere — even in a comment or string literal —
   fail OXT compilation. Straight ASCII `"` and `'` only. (Unicode glyphs in *display*
   strings are fine.) The static gate enforces this.
2. **Avoid names that shadow engine tokens.** Custom property/variable names whose stem
   is an engine keyword break compilation even when prefixed (real case: `the uCat` /
   `the uMask` → renamed `uHitChans`/`uOnChans`). A whole name that case-insensitively
   *equals* a token is even worse — it silently evaluates AS the token: `tAb` is read as
   the `tab` constant (found v0.4.2, in `heByteXor` → renamed `tWorkA`). Prefer
   distinctive multi-word stems. The static gate now flags any local/param whose name
   equals an engine token (check 7).
3. **Prefix conventions:** `u` = custom property, `g` = script-local global, `t` =
   handler local, `p` = parameter, `k` = constant. Public API prefixes in the family:
   `b2k*`, `bt*`, `sx*`, `ox*`; this repo's public surface will be `he*` (holde-em) —
   pick distinctive names within it.
4. **Control-structure shape matters.** Block form `if cond then` … `end if`; the
   single-line form `if cond then doSomething` has **no** `end if`. A trailing `\`
   continues a logical line. Naive brace-counters false-positive on `\`-continued `if`
   and multi-line `else if` — verify by eye before "fixing" valid code.
5. **`itemDelimiter`/`lineDelimiter` are global mutable state.** Set immediately before
   every parse; never assume the current value. Envelope fields and record packing will
   interleave tab- and comma-delimited text constantly.
6. **Constants must be literal.** `constant k = "120"` compiles; `constant k = a*b`
   does not — derive computed values at runtime.
7. **Command results vs function returns.** A command reports via `the result`; a
   function returns a value. Mixing them up fails silently — and calling a **command**
   with function-call syntax `heFoo()` does not fail silently: it **throws** at the call
   site ("error in function handler"), the body never runs (found v0.10.x — the harness
   called `heProbeSodium()` this way and the probe blew up before executing). Only a
   `function` may be invoked with `()`; a command is a statement, or route it through a
   value via `the result`. The static gate flags a locally-declared command used with
   `()` (check 10) — a parenthesised first argument `heFoo (x), y` is legal and is not
   flagged.
8. **Custom properties are text.** Everything round-trips as strings; booleans are the
   strings `"true"`/`"false"`.
10. **Dangling else.** A bare `else` on the line after a single-line `if cond then stmt`
    binds to that inner `if`, closes the wrong block, and surfaces as a baffling
    "missing end if" at handler end. The static gate flags the exact pairing.
11. **Declare `local` only at the top of a handler.** A `local` nested inside an
    `if`/`repeat` block has broken compilation of an entire script.
13. **Object-type tokens are single words.** `import audioClip from file …` compiles;
    `import audio clip …` does not. Dictionary prose spells them as two words; the
    tokens are not. Same family (found v0.17.1): the message box CONTAINER is the
    single token `msg` — `put x into msg`; the prose form `put x into the message
    box` throws at runtime. The static gate flags `the message box` in code
    (check 12).
14. **Sensor/contact messages go to `b2kContactTarget`, not the frame target.**
    Forgetting it = silent sensors with zero errors. Set both targets if the table ever
    uses Kit sensors.
17. **`b2kSetVelocity` wakes the body — by design.** Never write a velocity per-frame to
    something meant to rest. Chips get ONE toss impulse, then sleep; a sleeping body
    costs the solver zero.
19. **A non-looping animation fires `b2kSpriteOnFinish` whoever started it.** Card-flip
    chaining relies on this; every `*Done` handler must gate on its own context lock so
    a stale finish cannot double-fire a flip sequence.
23. **Sprites follow position only — they do not rotate.** Card flips are therefore
    squash-frame animations, never rotations; anything that must visibly tumble (chips)
    is a *graphic*-backed body, not a sprite.
24. **Mixed sprite families never share a table raw.** Foreign sheets load with
    `b2kSheetScale` normalisation; some families' frame names carry their `.png` suffix
    and some do not — check per sheet.
27. **`the result` is consumed by the NEXT command.** Capture it into a local
    immediately after every spawn/maker call before calling anything else. Several past
    bugs in the family were a stale `the result`.
29. **A `constant` must be declared before its first use, lexically.** OXT resolves
    constant names by file position; a use above the declaration compiles clean and
    silently evaluates to nothing at runtime. Declare constants at the top of the file
    (this bug shipped a broken feature in the family once already; it is invisible to
    every static check).

House additions for THIS repo (earned in the siblings, restated as law here):

- **H1. Bracket native sessions around the stack's life** (`openStack`/`closeStack`);
  never leave a TorrentXT session running after close.
- **H2. One poll drain per tick.** `btPoll` + `btRp1Poll` on the helpers' timer (~250 ms)
  — never in `on b2kFrame`, never per-frame.
- **H3. Everything is `Data` at the SodiumXT boundary.** `textEncode(..., "utf-8")` on
  the way in, `textDecode` on the way out; hex only for display/transcript-text fields.
- **H4. Crypto failures throw** — every `sxSecretBoxOpen`/`sxSealOpen`/`sxSignOpen` sits
  in a `try`/`catch`, and the catch path treats the message as hostile (drop and log),
  never as a retry.
- **H5. Pure logic stays pure.** Evaluator, betting engine, transcript fold, settlement:
  values in, values out, no UI reads, no `the result` reliance inside — this is what
  keeps them machine-testable (and it is why the KATs can run in CI at all).
- **H6. Never take a chunk of an array element directly.** `byte i of tA[j]`,
  `char 5 to -1 of tA["from"]`, `item n of tA["stacks"]` — all of them throw a
  double/binary conversion error at runtime (found on this repo's first OXT pass, in
  the seed-XOR path; the compiler accepts the syntax happily). Copy the element into a
  plain local, then chunk the local. Same rule for `replace ... in tA["k"]` — copy out,
  modify, or avoid. The static gate flags the chunk pattern (check 5).
  **Corollary (v0.1.1): keep FFI-bridged binary away from the script chunk evaluator
  entirely.** The double/binary error persisted past the copy-to-local fix, so binary
  from `sx*` handlers is now hex-encoded at the edge (`sxBin2Hex` — itself proven by
  the sodium probe) and everything script-side chunks plain hex text; raw Data exists
  only in expressions passed straight into `sx*` calls. Seeds, the shuffle stream, and
  every transcript field follow this rule.
- **H7. No bitwise operators.** `bitXor`/`bitAnd`/`bitOr`/`bitNot` throw the same
  double/binary conversion error at runtime on this OXT engine (found v0.4.1, in the
  seed-XOR path — `bitXor(acc, baseConvert(...))`). They are valid LiveCode syntax, so
  no structural check sees them. Do every bit operation with **pure integer arithmetic**
  (`div`, `mod`, `add`, `*`) — the repo carries `heByteXor` (an 8-iteration div/mod XOR)
  for exactly this. The static gate flags any bitwise operator (check 6).
- **H8. Declare the catch variable as a local.** `try … catch tErr` where `tErr` is not in
  the handler's `local` list throws a SECOND error on strict OXT the moment the catch
  fires and its body references the variable — which masks the real failure and surfaces
  as an opaque "error in function handler". It is invisible on a read (the catch only
  misbehaves when it actually fires) and only bites once the `try` body starts throwing:
  `heProbeSodium`/`heProbeTorrent`/`heDeckFromStreamKey`/`heNetStart` all shipped this and
  blew up only once SodiumXT/TorrentXT was installed (found v0.10.x — the probe threw
  instead of reporting). Every `catch <var>` must have a matching `local … <var>` (the
  family pattern; `heTableNew` does it right). The static gate flags any undeclared catch
  variable (check 9).
- **H9. No parenthesised dynamic property names.** `the (expr) of obj` /
  `set the (expr) of obj to ...` — building a property NAME at runtime — is not
  portable xTalk: property names are compile-time tokens, and the computed-name form
  is engine-shaky on OXT. It shipped once (v0.14.0 stored avatar paths in per-seat
  props named `"uHeAvatarPath" & N`) and was caught in the pre-OXT-pass re-audit
  (v0.15.0 fold of PR #33). The portable shape is ONE property holding a line-/item-
  indexed list (`uHeAvatarPaths`, line N = seat N — paths cannot contain a newline,
  so the index is safe); copy the property into a local before chunking it (H6
  corollary). The static gate flags any `the (` in code (check 11).

## The single-threaded performance playbook (condensed for a card game)

OXT runs everything — script, FFI, rendering — on ONE interpreted thread at ~60 fps
(~16 ms budget). Costs in order: interpreter ops, FFI round-trips, property-set redraws.

- **Pool at build, never create mid-hand.** All card sprites, chip bodies, and UI
  chrome exist before hand 1; reuse by `b2kSpriteMoveTo`/frame swap. Creates stall
  under accelerated rendering.
- **Pre-warm every sheet frame** that can appear (`b2kSheetEnsureIcon` at build).
- **HUD text at 4 Hz max, and only on change** (pot, stacks, timers). An every-frame
  field write forces an every-frame relayout+repaint — the single biggest avoidable
  cost found in the family's games.
- **Idle costs one compare.** Between animations the table's `b2kFrame` work must gate
  behind single `if`s.
- **No per-frame crypto, no per-frame FFI.** All signing/sealing happens at message
  boundaries (human-rate); the deal-time burst (52 scalar mults at Phase 4) is fine
  *because* it is deal-time.
- **Defer world changes out of event dispatch**: `send "..." to me in 80 milliseconds`
  and guard the handler against stale sends with a mode/lock check.

## Security house rules

Spec section 16 is the checklist and it is law. The load-bearing ones: `sxMemEqual` for
every secret comparison; `sxRandomBytes` for everything unguessable (the engine
`random()` never touches dealing or keys); domain-separated, versioned hash inputs
(`"HOLDEM-<PURPOSE>-v<N>|"`); verify-then-parse on every inbound envelope, drop-and-log
on any failure; fresh per-hand deal randomness and per-table session keys; long-term
keys only ever sign. When in doubt, the spec's threat model (section 2) decides.

## Workflow

- **After every `.livecodescript` edit:** `python3 tools/check-livecodescript.py` AND
  `python3 tools/check-holdem-idioms.py`.
- **The self-test harness** (`heRunSelftest`, embedded in the one stack) follows the
  Box2Dxt pattern: deterministic assertions, a version constant (`kHeHarnessV`) printed
  in the report header and **bumped on every engine-behavior change** so a stale paste
  identifies itself, and self-diagnosing asserts that print what was observed, not just
  FAIL. Expect first-contact arithmetic errors in new tests; write them to debug
  themselves.
- **The OXT round-trip:** you change script → gates pass → the user pastes/compiles in
  OXT, runs the harness and/or plays, reports back. Anything not user-confirmed stays
  labelled "verified statically".
- **Git:** work on the session's task branch, push, open a draft PR. Keep commits
  scoped; docs-only changes say so.
- **Style:** this codebase comments the *why*, densely, in the family's voice — mirror
  it. Straight quotes everywhere, including docs.

## Repo layout (as-built; see IMPLEMENTATION-PLAN.md for sequencing)

```
README.md                          front door
CLAUDE.md                          you are here
LICENSE                            MIT (the family default, decided Phase 0)
holdem-spec.md                     the design contract
IMPLEMENTATION-PLAN.md             the phased build order
tools/check-livecodescript.py      the suite's UNIFIED static checker (drift-gated)
tools/check-holdem-idioms.py       this member's extra idiom checks (the old lineage)
tools/check-docs.py                docs smart-quote scan
tools/evaluator-kat.py             spec 8.2 evaluator vectors (CI mirror of heEval7)
tools/betting-kat.py               spec 8.1/8.3 betting + settlement cases (CI mirror)
tools/shuffle-kat.py               playable integer deal (CI mirror of heShuffleDeck)
tools/protocol-kat.py              spec 6/7.1 crypto envelope/chain/deal wires
tools/fold-kat.py                  transcript fold + settlement/deal audits (CI mirror)
tools/atlas-kat.py                 Kenney card atlas <-> frame-name mapping
tools/sounds-kat.py                vendored casino WAVs <-> stack mapping
tools/logic-fuzz.py                INDEPENDENT-reference fuzz (rules, not the port)
assets/cards/, assets/sounds/      vendored Kenney CC0 art + audio (see NOTICE.md)
src/holdem.livecodescript          the whole thing: game + self-test + sodium probe,
                                   one self-building paste-and-run stack
.github/workflows/ci.yml           the standalone mirror's CI; INERT in the suite
                                   (tools/build-all.sh --gates runs the same set here)
```
