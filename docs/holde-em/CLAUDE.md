# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository. Read it before touching anything; it carries everything already learned the
hard way across the sibling repos so it never has to be re-learned here.

## What this is

**holde-em** is a serverless online no-limit Texas Hold'em game for **OpenXTalk (OXT)**
and the wider **xTalk** family (also compatible with **LiveCode 9.6.3+**). It is a
pure-script project: **no native code lives in this repo**. It composes four sibling
extensions, each of which wraps its own native library behind a friendly xTalk surface:

```
your table stack (this repo)                 src/holdem.livecodescript (planned)
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

**Status: pre-implementation.** The repo was seeded from Box2Dxt's `docs/holde-em/`
folder; Phase 0 of the plan (bootstrap) is the current work.

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

**Static verification** (the only automated gate that exists for xTalk; run after
**every** `.livecodescript` edit, and in CI):

```sh
python3 tools/check-livecodescript.py
```

It scans every `.livecodescript` under `src/` and `examples/` for: **smart/curly
quotes** (any single one fails OXT compilation), **handler balance**, **control-structure
balance**, and the **dangling-else** pairing. Exit non-zero on any failure. It was
carried from Box2Dxt (where it has caught real breakage repeatedly); the embedded-kit
drift check was dropped as not-yet-applicable — restore it if this repo ever embeds a
library between sentinels.

**Pure-logic pinning** (Phase 1+): the evaluator vectors and protocol KATs run headless
in CI (`tools/` scripts, per the plan) because they are plain algorithms — the one part
of this project that CAN be fully machine-verified. Keep it that way: game rules,
crypto sequencing, and settlement must live in handlers that take values and return
values, with no UI reads inside.

**Do not claim runtime behavior you cannot observe.** Anything visual, timed, socket-,
or extension-touching gets the phrase "verified statically; needs an OXT pass" and the
user confirms in the IDE. This discipline is house law across the family.

## Required extensions

| Extension | Library id | Prefix | Needed from | Notes |
|---|---|---|---|---|
| **TorrentXT** | `org.openxtalk.library.torrent` | `bt*` | Phase 2 | ABI v8+. Uses: session settings, `btAddInfohash` phantom swarms, `btDhtAnnounce`/`btDhtGetPeers`, **rp1** (`btRp1Enable/SetToken/Send/Poll`), BEP44 (`btDhtBep44SignBuf` + `btDhtPutSigned`, `btDhtGetMutable`), `btMapPort` for the optional direct-TCP upgrade. Also install its `torrent-helpers` poll dispatcher (`btStartPolling`). |
| **SodiumXT** | `org.openxtalk.library.sodium` | `sx*` | Phase 2 (Phase 1 uses only `sxRandomBytes`/`sxHash` if installed) | Identity, sealing, commitments, randomness. **Phase 4 requires the planned ristretto255 surface** (`sxRistretto*`) — an upstream SodiumXT work item (expose-only; libsodium already carries the primitives). |
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
Identity/signing: `sxSignKeypairFromSeed` (deterministic, BEP44-compatible),
`sxSignDetached`/`sxSignVerifyDetached`. Private lanes: `sxBoxKeypair`, sealed boxes
`sxSeal`/`sxSealOpen` (anonymous sender), `sxBox`/`sxBoxOpen` (authenticated).
Symmetric: `sxSecretBox`/`sxSecretBoxOpen`, `sxAeadEncrypt`/`sxAeadDecrypt` (nonces are
handled internally — there is deliberately no bring-your-own-nonce entry point).
Hashing/commitments: `sxHash`, `sxHashKeyed`, `sxHmacSha256`. Randomness:
`sxRandomBytes`, `sxRandomUniform`. Utility: `sxMemEqual` (constant-time — the ONLY
legal way to compare secrets/MACs), `sxBin2Hex`/`sxHex2Bin`, `sxBin2Base64`/
`sxBase642Bin`. Passphrases (if a UI lock is ever added): `sxPwHash*` (Argon2id).
Planned (Phase 4 prerequisite): `sxRistrettoFromHash`, `sxRistrettoScalarMultPoint`,
`sxRistrettoScalarRandom`, `sxRistrettoScalarInvert`, `sxRistrettoPointValid`.

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

1. **No smart quotes.** Curly `“ ” ‘ ’` anywhere — even in a comment or string literal —
   fail OXT compilation. Straight ASCII `"` and `'` only. (Unicode glyphs in *display*
   strings are fine.) The static gate enforces this.
2. **Avoid names that shadow engine tokens.** Custom property/variable names whose stem
   is an engine keyword break compilation even when prefixed (real case: `the uCat` /
   `the uMask` → renamed `uHitChans`/`uOnChans`). Prefer distinctive multi-word stems.
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
   function returns a value. Mixing them up fails silently.
8. **Custom properties are text.** Everything round-trips as strings; booleans are the
   strings `"true"`/`"false"`.
10. **Dangling else.** A bare `else` on the line after a single-line `if cond then stmt`
    binds to that inner `if`, closes the wrong block, and surfaces as a baffling
    "missing end if" at handler end. The static gate flags the exact pairing.
11. **Declare `local` only at the top of a handler.** A `local` nested inside an
    `if`/`repeat` block has broken compilation of an entire script.
13. **Object-type tokens are single words.** `import audioClip from file …` compiles;
    `import audio clip …` does not. Dictionary prose spells them as two words; the
    tokens are not.
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

- **After every `.livecodescript` edit:** `python3 tools/check-livecodescript.py`.
- **The self-test harness** (`src/holdem-selftest.livecodescript`, Phase 1+) follows the
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

## Repo layout (planned end-state; see IMPLEMENTATION-PLAN.md for sequencing)

```
README.md                          front door
CLAUDE.md                          you are here
holdem-spec.md                     the design contract
IMPLEMENTATION-PLAN.md             the phased build order
tools/check-livecodescript.py     static gates (carried from the family)
tools/protocol-kat.py              Phase 2+: envelope/chain/deal known-answer vectors
src/holdem.livecodescript          the game: one self-building paste-and-run stack
src/holdem-selftest.livecodescript the harness (evaluator vectors, protocol asserts,
                                   adversarial cheater bots)
.github/workflows/ci.yml           runs the gates + KATs on every push/PR
```
