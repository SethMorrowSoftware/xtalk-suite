# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in the
Box2Dxt member of the xtalk-suite monorepo (`box2dxt/`).

> **Folded into the monorepo 2026-08-14.** Box2Dxt is the family's ANCESTOR -
> the handle tables, the platform-id scheme, the packaged-extension install and
> the exception-firewall discipline the suite members carry were born here -
> and the fold brings it home. Copied verbatim (`git archive`, tracked files
> only) from the standalone repository, which becomes a mirror; development
> happens here now. What the fold changed, each per suite law:
>
> - `tools/check-livecodescript.py` was REPLACED with the suite's unified
>   checker (this copy was the OLDEST surviving pre-unification lineage, 220
>   lines against the union's 840) and is drift-gated + fixture-tested with
>   the other eight copies. First contact found ~1550 violations: ~1520 were
>   the pre-ASCII-rule character set (em dashes, ellipses, middots, and the
>   UI glyph vocabulary - the contraption builder's tool legend is mnemonic
>   ASCII now, and even had two tools sharing one glyph), and the rest were
>   real: **29 `repeat with ... step` loops in the platformer** (OXT ignores
>   the increment - the cxHexDecode lesson; every tile loop would have walked
>   1px at a time, placing 64x the tiles), all rewritten to `repeat while` +
>   explicit `add`; the `.lcb`'s 33 foreign-decl `pI` parameters (spells the
>   reserved token `pi`; positional binds, so the rename is documentation);
>   and one bare lowercase `i` local.
> - `src/code/MANIFEST.sha256` now pins all five committed binaries (suite
>   rule 5's integrity gate; this member never had one).
> - The three stacks over the family's 720p budget were trimmed to fit
>   (demo 660 and the gamekit spike 700 to 640; the contraption builder's
>   kStackH 760 to 640 - all viewport-only, nothing was anchored below).
> - `.github/workflows/native-box2dxt.yml` at the suite root runs the
>   5-target native matrix (paths-scoped; artifacts, never releases or
>   commits - the suite convention). The member's own build.yml stays for
>   standalone work but is inert here. NOT yet done: box2dxt is not in
>   release-binaries.yml's manual assembly matrix. **This is not a clean
>   matrix add** (checked 2026-08-14): box2dxt's known-good Linux build
>   (native-box2dxt.yml) uses `docker run manylinux2014` INSIDE a stock
>   runner, because manylinux2014 is glibc 2.17 and GitHub's node20 actions
>   (checkout/upload-artifact) refuse to start in a 2.17 container - which
>   is exactly why release-binaries.yml's `cmake-members` job uses the
>   `container:` shape with manylinux_2_28. So box2dxt cannot join
>   `cmake-members` as-is: it needs either its own docker-run job ported
>   from native-box2dxt.yml, or a move to manylinux_2_28 that would raise
>   its glibc floor from 2.17 to 2.28 (a real portability regression, the
>   owner's call). `tools/install-release-binaries.py` would also need to
>   learn box2dxt's package layout. Do this as a deliberate release-lane
>   pass, not a drive-by.
> - The examples are registered EXEMPT in the suite UI-kit gate: they are
>   games drawn by this member's own embedded b2k Kit (whose copies have
>   their own sync gate, `tools/sync-embedded-kit.py`), not form UIs.
>   **Phase-2 work, deliberately deferred:** suite-kit chrome for the game
>   stacks (an aesthetic call - the exemptions argue form chrome is not the
>   games' UI language) and harness-scaffold adoption for
>   `examples/box2dxt-selftest`.
>
> **FOLDED INTO THE SUITE HARNESS 2026-08-16, as the eighth folded member.**
> The prerequisite landed 2026-08-14 (`stRunAll` probes the native library in
> a guarded try and SKIPs cleanly when box2dxt is absent - what a folded
> harness needs, since the suite paste runs on machines without box2dxt).
> What the fold did, and what it needed that no earlier member did:
>
> - **A returned-report mode, not scaffold counters.** `function stSelfTest`
>   runs `stRunAll` and returns the report with a summary line the suite
>   core's `stSummaryCounts` can parse (`<n> passed, <n> failed` - exactly two
>   numbers and those two words, nothing else on the line, the `rsSelfTest`
>   shape). Chosen over adopting `tools/harness-scaffold.livecodescript`'s
>   counter names because this harness is not a scaffold adopter at all: it
>   has its own `gRep`/`gPass`/`gFail`, its own report format, its own window,
>   and 43 test handlers of engine-verified history written against them.
>   A returned-report mode is four lines; scaffold adoption is a rewrite of a
>   proven file to suit the fold, which is backwards. The two existing summary
>   lines (`ALL PASS (n assertions)` / `FAILURES: n passes: n`) deliberately do
>   NOT parse as summaries - each carries a disqualifying third word - which is
>   what keeps them from becoming a second match now that the new one exists.
> - **`stOut` writes to its field only when the field is there.** Folded, the
>   suite owns the one window; an unguarded `set the text of field "stReport"`
>   would have thrown on every output line and taken the whole section down.
>   The write moved into `stPaintReport`, guarded with `there is a field` (not
>   a try: a missing field is expected here, and swallowing an error from a
>   field that DOES exist would hide a broken report surface standalone).
> - **The Kit is embedded ONCE.** This example carries a verbatim copy of
>   `src/box2dxt-kit.livecodescript` between sentinels (`tools/sync-embedded-kit.py`
>   owns that region). The generator CUTS that copy (`strip_spans`) and embeds
>   the Kit from `src/` as a suite SCRIPT LAYER, unprefixed, beside coinxt's
>   and onionxt's - so the folded tests call `b2k*` by their real names and the
>   313 Kit handlers are defined exactly once. `check-suite-selftest.py` checks
>   both halves of that (no leftover sentinel; `b2kStepOnce` defined once).
> - **Three names are NOT prefixed**, the only such case in the fold:
>   `b2kFell`, `b2kSensorEnter` and `b2kContact` are message RECEIVERS the Kit
>   dispatches by literal name, so a `b21b2kFell` would never be found and the
>   three checks that prove the Kit's message path (as opposed to its polling
>   accessors) would report 0 events and read like a dispatcher defect. The
>   generator's `keep_names` holds them, asserts they still exist, and the
>   suite checker asserts both directions.
> - **`openCard`/`closeCard`/`buildStUI` are dropped.** This harness hangs its
>   window off the CARD hooks rather than the stack ones, which the fold's
>   existing `openStack`/`closeStack` drop set did not cover; left in, `on
>   openCard` would have rebuilt an 860x640 window over the suite's.
> - **The suite core probes the EXTENSION** (`b2kEnsureNativeLib` then
>   `b2Version()`, guarded) and SKIPs the whole section when it is absent. That
>   probe, not `stRunAll`'s own, is what keeps a machine without box2dxt from
>   folding a green `0 passed, 0 failed` into the suite totals.
> - **The coverage gate is now on this member, and it found the real gap.**
>   `check-suite-coverage.py` measures the Kit (`b2k`, 313 public handlers)
>   and on first contact 211 of them had never been named by any test - many
>   of which RUN on every existing test (`b2kStepOnce` alone drives
>   `b2kHarvestEvents`, `b2kSyncBodies`, `b2kInputTick`, `b2kPlayerTick`,
>   `b2kSpritesTick`, `b2kCamTick` and both dispatchers) with no test ever
>   writing their name down. Harness **v23** adds 13 "Kit API coverage"
>   sections that drive the rest of the surface directly; the member is now at
>   313/313 with ZERO exemptions. Those sections are deliberately SHALLOW next
>   to the behaviour tests above them and say so in their banner: the contract
>   they assert is "this handler exists, takes these arguments, and reports the
>   documented shape". A handler that earns a real lesson should GRADUATE out
>   of them into a section of its own.
> - **The raw `b2*` layer is NOT in that ratchet, and the reason is measured.**
>   `src/box2dxt.lcb` is 376 public handlers over 374 foreign declarations - a
>   1:1 binding - and of those 376 the Kit names 131 while **245 are named by
>   no script anywhere in this member**. Ratcheting them would mean ~375 new
>   assertions against a foreign-bound API written blind in one pass, against
>   this member's own recorded base rate ("5 Kit bugs : 5 harness bugs - expect
>   first-contact arithmetic errors"). The reason is written into
>   `tools/check-suite-coverage.py` beside the row. That layer's cover today is
>   `tests/smoke_test.c` under ASan/UBSan; a script-level ratchet for it is an
>   OPEN item.
> - None of this is runtime-verifiable here: **verified statically; needs an
>   OXT pass**, and the v23 sections are first-contact code, so expect the
>   usual arithmetic slips on the first run.
>
> **THE FIRST TWO ENGINE RUNS CAME BACK (2026-08-16, same day), and the
> prediction held: of the eleven first-run failures, EIGHT were in the
> first-contact v23 sections and the engine was right each time.** Fixed
> across v24/v25 with the engine's numbers as the evidence: the half-extent
> getters return half the CONTROL's real size (a 30x50 request lands as a
> 32x52 control -- the test asserted a number the Kit never promised, and
> now pins the documented relationship); b2kRayHit returns the HIT CONTROL
> or empty, never a boolean (the accessors beside the failing assert were
> proving the hit landed the whole time); b2kImpulse is y-DOWN like every
> other y in the Kit (the test had imported the physics engine's y-up); and
> the player-API section's throw (error 69) was b2kSpritePlay being handed
> an empty control -- which exposed TWO REAL KIT DEFECTS the run gets credit
> for: b2kSpritePlay now no-ops on an empty control per the family's
> stale-handles-never-crash law (b2kPlayerAnims maps states independently
> of art, so a direct b2kPlayerShowState with no art bound reached the
> throw), and ALL EIGHT event-buffer readers are count-guarded, because
> b2kEventsReset zeroes the COUNTS and leaves the entry arrays -- an
> out-of-range index answered the STALE control from the last real event,
> exactly the hazard the EndContact test's own banner named.
> **THE THIRD RUN (2026-08-16, later the same day) confirmed the fixes and
> moved the throw ONE statement, which is the diagnosis:** 353/4 at v25.
> Every v24/v25 correction above reported green with the engine's numbers
> (halfW/halfH "got 16 of 32"/"got 26 of 52", the ray-hit pair, the y-DOWN
> impulse "vy 4000", both cleared-buffer EndContact reads) -- but the
> player-API section STILL threw error 69, now at the paste line for
> `b2kSpriteFlipH`'s deref where run 2's was `b2kSpritePlay`'s. That line
> movement is the whole story: the Play guard worked, the section advanced
> one statement, and died on the NEXT sprite entry point handed the empty
> art -- b2kPlayerShowState's facing latch always fires on its first call
> (sPlayFlipNow starts empty, so `false is not empty`), reaching
> `b2kSpriteFlipH sPlayArt, tFlip` with no art bound. Fixed at v26 by
> finishing the thought instead of iterating one deref per engine run:
> EVERY unguarded sprite entry point now no-ops on an empty ref per the
> family law (FlipH, Stop, SetFrame, FPS, OnFinish, Bind - both args, it
> derefs both - Unbind, MoveTo; Play was v25's; Remove/Anim/Frame/Flipped
> already tolerated it). The player region holds no other sprite calls, so
> this section has no throw left to find.
> **THE FOURTH RUN (2026-08-17) CLEARED THE THROW AND CRACKED THE
> GHOST-LAYER CASE:** 365/4 at v26 -- the player-API section ran to its end
> for the first time, which surfaced one new failure and let the three old
> ones be diagnosed against stable numbers instead of guessed at. What v27
> + the Kit fix did about each:
> - **`b2kPlayerStandUp restores full height` (new, was hidden behind the
>   throw): a test wrong twice over.** The default duckScale is >= 1, so
>   `b2kPlayerDuckSet true` was a complete NO-OP (its guard exits), and the
>   asserted 48 was the REQUEST -- a 48-request control is padded by the
>   capsule fit, the halfW/halfH lesson again. v27 sets duckScale 0.5 and
>   asserts the ROUND-TRIP (duck shrinks what make built; stand-up restores
>   exactly what it found), so the pair now exercises the reshape at all.
> - **The ghost-layer failure is a REAL KIT DEFECT, found from the engine's
>   own number.** y 365 = resting ON the platform = the platform's category
>   never landed. Root cause: Box2D v3.1 filter bits are uint64, a DEFAULT
>   mask reads back as 2^64-1, and the shim's `filter_bits_ok` guard (2^53-1,
>   the double-exact ceiling) makes `b2SetShapeFilter` refuse the whole call
>   SILENTLY when that readback is passed straight back in -- which
>   `b2kSetCategory` did. The shape kept default category 1, which is ALSO
>   the first named layer's bit (b2kDefineLayer starts at 1), so the "ghost"
>   ball collided normally. The clincher: `b2kPlayerDropStart` has carried
>   the exact clamp with the exact reasoning since the drop-through window
>   shipped -- the lesson was learned once and never propagated, the
>   one-copy-fixed shape the checker-drift gate exists for, here inside one
>   file. Fixed in all three public filter wrappers (SetCategory, SetMask's
>   category readback, SetCollisionGroup's both -- that last was a silent
>   no-op for EVERY body with an unlowered mask); b2kNoCollide was never
>   affected (b2FilterJoint, no round-trip).
> - **The post-b2kClear gravity failure VINDICATED the Kit: it is a test
>   under-wait.** 40 steps of free fall from y 200 at this world's pinned
>   gravity (the first behaviour test pins 30 steps -> 200 px/s, i.e.
>   400 px/s^2) is exactly 89 px -- y 289, the engine's number to the pixel,
>   mid-fall at NORMAL gravity with the floor at 500 ~70 steps away. v27
>   steps until grounded (bounded at 150) before asserting the landing.
> - **The crawl stall STAYS OPEN, now instrumented.** x 269 is short of the
>   ceiling's edge at 300, so nothing in the geometry blocks it there, and
>   ~35 px/s net against a 110 px/s crawl target says the controller itself
>   is impeding -- but which of state/grounded/vx is wrong is not decidable
>   from one coordinate. v27's assert reports state, halfH, grounded and vx
>   at the stall, so the next run diagnoses itself.
>
> **THE FIFTH RUN (2026-08-17, 366/3 at v27) CONFIRMED BOTH FIXES AND THE
> INSTRUMENTATION CONVICTED THE DUCK RESHAPE -- the oldest behaviour failure
> was a real Kit defect wearing a passing test's numbers.** The filter clamp
> and the gravity re-wait went green (ghost ball through at y 461; landing at
> y 473, the predicted arithmetic to the pixel). The three remaining reds were
> ONE defect seen from three angles: the crawl assert reported `state duck,
> halfH 13, grounded true, vx -1` -- a body pushing against a wall -- and the
> v27 API round-trip measured the control at 50 -> 52 -> 54 across one
> duck/stand pair. Together: **the physical capsule never shrank.** Two engine
> facts compose into the root cause: the player is a POLYGON graphic (the
> capsule fit sets its style), and OXT does not resize a polygon graphic by a
> height-set -- its rect is DERIVED from its points -- so b2kPlayerDuckSet's
> "resize the control, then b2kReshape" rebuilt the capsule at FULL height
> every time, while sPlayHalfH (bookkeeping, not measurement) insisted the
> pill was short; the crawl then wedged on the ceiling's left face at exactly
> x 269 with vx ~0, and every earlier halfH-based assert in the duck section
> passed because they only ever read the bookkeeping. The +2-per-call growth
> is the second half: the drawer's re-point pads the rect by the pen margin,
> and reshape re-read the padded rect each rebuild. Fixed at v28:
> `b2kReshape` takes optional EXPLICIT pixel dims (box/ball/capsule);
> b2kPlayerAttach captures the capsule's canonical dims BEFORE the first draw
> pads the rect; duck/stand rebuild from those stored dims and never touch the
> control's rect (the drawer's re-point IS a polygon's resize mechanism), and
> the stand-up shift and headroom ray use the stored dims too. Expected next
> paste: **369/0 -- box2dxt fully green** -- if the reshape fix holds;
> holde-em steady at 507/0.
> - The `docs/holde-em/` spec moved UP to the suite's `docs/holde-em/`: it
>   composes torrentxt + sodiumxt + box2dxt, which makes it a CROSS-MEMBER
>   capstone design (Riptide's sibling), not a box2dxt document. (It has
>   since moved again: the 2026-08-15 hold-em fold removed that seed copy,
>   and the spec now lives in the `holde-em/` member.)
>
> The sweep + loop fixes touch nearly every script file, so the whole member
> is **verified statically; needs an OXT re-pass** (its prior engine evidence
> predates the fold). The library namespace stays `org.openxtalk.box2dxt` -
> it predates the family's `org.openxtalk.library.*` convention and is
> shipped; renaming would break every installed user for zero gain.

## What this is

**Box2Dxt** is the Box2D **v3.1.0** physics engine packaged for **OpenXTalk (OXT)** and the
wider **xTalk** language family (also compatible with **LiveCode 9.6.3+**). It ships as three
stacked layers plus self-contained example stacks:

```
Box2D v3.1.0 (fetched by CMake)
   └─ C shim         src/box2d_lc.c        →  libbox2dxt.{so,dylib,dll}   (ABI symbols: b2lc_*)
        └─ LCB binding  src/box2dxt.lcb     →  raw  b2*   API  (metres, radians, int handles)
             └─ the Kit  src/box2dxt-kit.livecodescript → friendly b2k* API (pixels, degrees,
                          control-backed bodies, a per-frame render loop)  ← SINGLE SOURCE OF TRUTH
                  └─ examples/*.livecodescript  embed a *synced copy* of the Kit
```

- **C shim** (`src/box2d_lc.c`): exposes Box2D v3 across the LCB foreign-function interface.
  Box2D ids are small by-value structs, so every id is stored in a shim-side handle table and
  crosses the boundary as a **positive 32-bit int handle (0 = null/invalid; generation-tagged,
  so a recycled slot can't resurrect a stale handle — treat handles as opaque)**. Reals cross as
  `double`, booleans as `int`. Every handle is validated with Box2D's `b2*_IsValid` before use,
  so a stale/0 handle is a **harmless no-op** (getters return 0), never a crash. Exported C ABI
  symbols keep the historical **`b2lc_` prefix** for binary stability — **never rename them**.
  The shim compiles into one shared library (`libbox2dxt.{so,dylib,dll}`) that **ships bundled
  INSIDE the extension** under `src/code/<arch>-<platform>/box2dxt.{so,dll,dylib}` (bare token,
  no `lib` prefix; platform-ids `x86_64-linux` / `x86-linux` / `x86_64-win32` / `x86-win32` /
  `universal-mac`, architecture FIRST, Windows `-win32` for both bitnesses). Those libraries are
  **committed** and pinned by `src/code/MANIFEST.sha256` (the suite's native lanes build and
  test them as CI artifacts; Releases exist only on the standalone mirror as history);
  `tools/package-extension.py`
  refreshes that tree from a newer build. Installing the packaged extension makes the engine
  resolve the `c:box2dxt>` bindings via `the revLibraryMapping` automatically — **no loose library,
  no rename, no sudo/`/usr/lib`/`LD_LIBRARY_PATH`** (see `docs/building.md`).
- **LCB binding** (`src/box2dxt.lcb`, `library org.openxtalk.box2dxt`): declares `foreign handler`
  bindings to the shared library and public `b2PascalCase` handlers callable from xTalk. This API
  speaks **metres and radians**; body type codes are `0=static, 1=kinematic, 2=dynamic`.
- **The Kit** (`src/box2dxt-kit.livecodescript`): a pure-xTalk convenience layer (313 `b2k*`
  handlers incl. the game modules: input, sprites, player controller, camera) that speaks
  **screen pixels and degrees**, binds bodies to LiveCode controls, and runs the animation
  loop. This is what the examples and most users actually call.

Docs live in `docs/` (`architecture.md`, `building.md`, `getting-started.md`, `api-reference.md`,
`kit-guide.md`, `kit-reference.md`, `asset-expansion-plan.md`, and `platformer-polish-plan.md` — the
forward-looking plan now that feature dev is frozen; the superseded pre-implementation
`game-engine-spec.md` + `expansion-prep.md` are under `docs/archive/`). The per-platform native
binaries are **committed inside the extension** at `src/code/<arch>-<platform>/`, pinned by
`MANIFEST.sha256` and built/tested by the suite's `native-box2dxt.yml` as artifacts (Releases are
mirror history only); `tools/package-extension.py` refreshes that tree from a newer build.
The install is the packaged extension, not a loose drop-in (a loose `box2dxt.{so,dll,dylib}` beside a
saved stack — copied from `src/code/<arch>-<platform>/` — is only the dev/fallback path, mapped at
runtime by the Kit's `b2kEnsureNativeLib`). The **Game Kit** (input/sprites/player/camera/sound modules) is
implemented and user-verified; content **Waves 0-7 are built** (Wave 8, builder cross-pollination, is
the only remaining roadmap item); `plan.md`'s decision log is the as-built record. Six examples: demo,
contraption builder, **spike-gamekit** (the Phase-0 Game Kit harness), **platformer** (the flagship
game showcase — the Game Kit pushed hard across 7 levels, with bestiary I + variety walkers + bestiary
II frog/barnacle/spider, coin tiers + a hidden star, a forgiving 5-heart health model, character
select, and a polish-pass front-end — a boot title screen + biome-illustrated transition cards that mask
every level load (the §2 headline + bookends, shipped) — the focus of this repo's game work; forward
feature dev is FROZEN, polish underway, see `docs/platformer-polish-plan.md`), **slingshot** (angry-birds-style tower
knockdown over 3 levels — the physics core carrying a whole game with zero events and zero assets), and
the **self-test harness** (below). (The single-screen micro-game was retired in Wave 5; its "whole game
from the physics core" pattern survives only as `kit-guide` section 20 prose.)

## The golden rule: the embedded-Kit sync

The example stacks are **deliberately self-contained** — you paste the whole `.livecodescript`
into a stack script and it runs — so **each example embeds a verbatim copy of the Kit** between
sentinel comments:

```
-- >>> BEGIN EMBEDDED KIT >>>      (e.g. line 36 in the contraption builder)
   ...the entire Kit, generated...
-- <<< END EMBEDDED KIT <<<        (e.g. line 1689 in the contraption builder)
```

Rules:
- **`src/box2dxt-kit.livecodescript` is the only source of truth for the Kit.** Edit it there.
- **Never hand-edit between the sentinels** in an example — the next sync overwrites it.
- After changing the Kit, **re-sync and commit the result**:
  ```sh
  python3 tools/sync-embedded-kit.py            # rewrite embedded copies
  python3 tools/sync-embedded-kit.py --check    # verify (CI gate; non-zero on drift)
  ```
- When auditing/linting an example's *own* code, **exclude the embedded region** (lines between
  the sentinels) so you don't double-count Kit handlers or trip over Kit code you can't edit here.

## Commands

**Native library + tests** (C; this is the only layer with an automated test suite):
```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBOX2DXT_BUILD_TESTS=ON
cmake --build build --config Release
ctest --test-dir build --output-on-failure        # runs tests/smoke_test.c
```
CMake fetches Box2D v3.1.0 automatically (pinned `GIT_TAG v3.1.0`). See `docs/building.md`.

**Sync the embedded Kit** (run after every Kit edit): `python3 tools/sync-embedded-kit.py`

**Static verification for the script layer.** OXT/LiveCode is a GUI runtime — there is **no
headless way to compile or run the `.livecodescript` here**. The user compiles and tests in OXT.
Your job is to catch what's statically catchable *before* they do. One command bundles the gates
(and CI runs the same script):

```sh
python3 tools/check-livecodescript.py
```

It checks the Kit and every example for: **smart/curly quotes** (any one fails OXT compilation),
**handler balance** (every `on`/`command`/`function`/`getprop`/`setprop` has its `end <name>`),
**control-structure balance** (`if`/`repeat`/`switch`/`try` blocks closed inside their handler),
and **embedded-Kit drift** (delegates to `sync-embedded-kit.py --check`). Exit non-zero on any
failure. Run it after **every** `.livecodescript` edit.

**Do not claim runtime behavior you cannot observe** — say "verified statically; needs an OXT
pass" and let the user confirm.

**The self-test harness** (`examples/box2dxt-selftest.livecodescript`) is the runtime safety net:
~372 deterministic assertions across 50 test handlers (currently **v23**) driving the real Kit
(paused world + `b2kStepOnce` hand-stepping + `b2kInputInject` scripted keys). It is in TWO
halves and the file says so where they meet: the first 37 handlers are BEHAVIOUR tests, each
one a lesson learned on real hardware; the 13 added in v23 are **Kit API coverage** - broad,
deliberately shallow, and there because the suite's `check-suite-coverage.py` measured that
211 of the Kit's 313 public handlers had never been named by any test. A handler that earns a
real lesson should graduate out of the second half into a section of its own. The workflow for
every **Kit** change: (1) add/extend an assertion
that captures the new behavior, (2) **bump `kStHarnessV`** (the report header prints it, so a
stale paste identifies itself), (3) the user clicks RUN ALL TESTS and reports. **Example-only
changes do NOT bump the harness** — the rule is conditional on Kit edits (Waves 1 and 3 shipped
with zero Kit changes and zero bump). It has caught five
real Kit bugs that play-testing missed; score so far is 5 Kit bugs : 5 harness bugs — expect
first-contact arithmetic errors in new tests and write them self-diagnosing (print what was
observed, not just FAIL).

## LiveCodeScript / OXT gotchas (learned the hard way)

OXT's compiler is **stricter than LiveCode's**. These are the recurring footguns:

1. **No smart quotes.** Curly `“ ” ‘ ’` (U+201C/201D/2018/2019) anywhere in the script — even inside
   a string literal or comment — fail to compile in OXT. Use straight ASCII `"` and `'` only.
   (Unicode *glyphs* in display strings, e.g. `▲ ↗ ◉ ·`, are fine.)
2. **Avoid property/variable names that shadow LiveCode tokens.** OXT chokes on custom names whose
   stem is an engine keyword/property even when prefixed. Real example that broke OXT compilation:
   `the uCat` / `the uMask` → renamed to **`uHitChans` / `uOnChans`**. Prefer **distinctive,
   multi-word stems** (`uHitChans`, not `uMask`). When in doubt, pick a longer, unambiguous name.
3. **Prefix conventions** (follow them; they also keep the audits clean):
   `u` = custom property on a control (`the uKind of grp`), `g` = script-local global,
   `t` = handler local, `p` = parameter, `k` = constant. Public API: `b2PascalCase` (extension),
   `b2kPascalCase` (Kit), `b2lc_snake_case` (C ABI).
4. **Control-structure shape matters.** Block form `if cond then` ⟶ … ⟶ `end if`; single-line form
   `if cond then doSomething` has **no** `end if`. A trailing `\` continues a logical line. Note:
   naive brace-counters (including the audit above) raise **known false positives** on a `\`-continued
   `if … then \` and on multi-line `else if` — verify by eye, don't "fix" valid code.
5. **`itemDelimiter` / `lineDelimiter` are global mutable state.** Set the delimiter immediately
   before parsing (`set the itemDelimiter to comma`) — never assume its current value. Points are
   `"x,y"` lines; many save records are tab-delimited; the two get interleaved constantly.
6. **Constants must be literals.** `constant k = "120"` is fine; `constant k = a*b` is not. Derive
   computed values at runtime (e.g. canvas edges in `prepArena`/`buildUI`, not as constants).
7. **Command results vs function returns.** A `b2k…` *command* reports via `the result` (or you
   `put` it). A *function* returns a value. `b2kSpawnBox` is a command → `put the result into tCtrl`.
8. **Custom properties are the per-object datastore, and everything is text.** Parts are LiveCode
   graphics carrying `uKind`, `uColor`, `uW/uH`, plus per-kind extras (`uLaserDir`, `uThrustPower`,
   `uFanDir`, …). Booleans round-trip as the strings `"true"`/`"false"`.
9. **Two coordinate systems, y flips.** The Kit is **screen pixels, degrees, y-DOWN**; the
   extension is **metres, radians, y-UP**. Kit wrappers do the conversion (divide by `sScale`,
   negate y — e.g. `b2kForce` passes `-fy`). If you add Kit code that calls the raw `b2*` API,
   mind the flip and the scale.
10. **Dangling else.** A single-line `if cond then stmt` may legally take an
   `else`; a BARE `else` on the next line therefore binds to that single-line
   `if`, its `end if` closes the wrong block, and the outer `if` stays open —
   OXT reports "missing end if" at the handler's end. Chains like
   `if c then s1` / `else s2` (statement on the else line) are fine. The
   static checker's dangling-else gate flags the broken pairing.
11. **Declare `local` only at the top of a handler.** A `local` nested inside
   an `if`/`repeat` block has broken OXT compilation of the entire script.
   Keep all declarations together at the handler's top.
12. **Scrolled-group coordinates are visual.** `the loc`/`rect` of a grouped
   control is reported and set SCROLL-ADJUSTED on OXT, so a per-frame write
   of world coordinates into a scrolled group cancels the pan (objects
   "outrun" the camera at 2x). The Kit's camera probes this at `b2kCamOn`
   and compensates every write (`b2kCamShiftX/Y`); for hand-animated moves
   use `b2kSpriteMoveTo`, never a raw `set the loc`.
13. **Object-type tokens are single words.** `import audioClip from file …`
   compiles; `import audio clip from file …` does NOT (OXT reports "bad
   image type" — the parser rejects `audio` as the import type). Same for
   `videoClip`. The dictionary's prose spells them as two words; the
   tokens aren't.
14. **Sensor/contact MESSAGES go to `b2kContactTarget`, not the frame
   target.** Forgetting it = silent sensors (coins/doors dead, solids
   fine) with zero errors — the micro-game shipped that way. Set BOTH
   targets in every game; the harness asserts the message path now.
15. **The chain ghost rule.** An open chain's first and last segments are
   ghost anchors — N points collide as N−3 segments. Run every chain one
   segment past the surface on each side, or its ends are intangible.
16. **Gameplay verdicts use windows/polls, never instantaneous reads.**
   Post-solve velocities read ~0 on clean impacts; sensor enter/exit
   counting drifts around sleeping/settling bodies; states can be
   outrun by event timing. Presence = poll `b2kOverlap` (sees sleeping
   bodies); stomp-like verdicts = recent-state windows; one-shots =
   sensor events. External player boosts go through `b2kPlayerJump`
   (a raw upward set-velocity on a grounded player gets ground-snapped).
   Corollary (the slingshot): **impact strength = speed-poll the LIGHT
   body** — the light body always inherits the momentum, so the poll
   cannot be outrun; arm such polls only after a build-settle grace.
17. **`b2kSetVelocity` WAKES the body — by design.** Never write a
   velocity per-frame to something meant to REST (the parked-shell bug:
   a per-frame "brake" kept it awake forever, solver + 2 FFI per frame).
   Velocity *asserts* are only for things that must keep moving (the
   player, a sliding shell); transitions write once, rest states write
   nothing. A sleeping body costs the solver zero.
18. **Two velocity-asserting bodies must never share a path.** When both
   write their vx every frame and they collide, the asserts fight the
   solver — visible jitter. Split patrol bands so asserting bodies
   (bats, shells vs patrollers) cannot meet head-on.
19. **A non-looping animation FIRES `b2kSpriteOnFinish` whoever started
   it.** If a game wires the player's sprite finish to its respawn (the
   hit-pose pattern), the Kit's hurt anim must be a **LOOPING twin**
   (`hurtpose`), never the one-shot `hit` — and every `*HurtDone`
   handler gates on its own respawn lock besides.
20. **One-sided chain contacts judge by the CENTROID.** Restoring a
   collision filter while a body straddles the chain line snaps it back
   ON TOP. Restore masks only once the body has cleared the line it
   dropped through, with a hard deadline (4x window) for blocked drops —
   and never park a solid closer than a player-height under a one-way deck.
21. **Filter bits: xTalk bit ops are 32-bit; Box2D's default mask reads
   back as 2^64-1.** Clamp any mask round-trip to 4294967295 before
   bitAnd/bitOr. Bit 2^31 is the Kit's reserved **`oneway`** chain layer:
   `b2kDefineLayer` stops at 2^30 (31 nameable layers) and `b2kSetMask`
   ORs the oneway bit in automatically (a custom mask must not silently
   mean "fall through the terrain").
22. **A `switch` on kinds: deleting a case hands the row to `default`.**
   Keep an EMPTY case with a comment when the default would misbehave
   (a parked shell with no case would get patrol velocity). Paired
   fall-through cases (`case "a"` newline `case "b"`) are legal and used.
23. **Sprites follow position only — they do not rotate.** Bodies whose
   ROTATION matters (tumbling blocks, toppling towers) must be spawned
   GRAPHICS (the poly/image render paths rotate); sprite faces suit
   round things and fixed-rotation bodies only. This is why the
   slingshot is deliberately sprite-free.
24. **Mixed sprite grids never share a level raw.** Foreign-family
   sheets load with `b2kSheetScale` normalisation (e.g. the 70px
   `enemies.png` at 0.9 into the 64px platformer). Family B/C sheet
   frame names carry their **`.png` suffix** (`"bat_fly.png"`); the
   Kenney `-default` sheets do not.
25. **Optional sheets gate their makers on a capability flag** (the
   `gSpooksOK`/`gToysOK` pattern, computed once per build): a missing
   sheet must degrade SILENTLY and the level must stay completable —
   never let a coin or a gate depend on optional art.
26. **Art facing polarity is statically unverifiable.** When adding a
   new sheet's movers, pick a flip convention, note it in the example's
   verify list, and let the OXT round report mirrored sprites.
27. **`the result` is consumed by the NEXT command** — capture it into a
   local immediately after every `b2kSpawn*`/maker call before calling
   anything else (several past bugs were a stale `the result`).
28. **A physics hitbox taller than the VISIBLE sprite makes the head bump
   things it never visually touches.** A capsule sized to the sprite FRAME
   (not the character within it) tops out above the drawn head when the art
   is bottom-aligned with frame headroom (Kenney's 128px characters at a
   down-scale): the invisible "hat" hits the brick/ceiling while the visible
   head stops short with a gap — even though the contact and the head-bump
   poll both fire. Size the hitbox to the VISIBLE art, feet-aligned (derive
   the bind offset from it), and have any head-reach logic read the body's
   real half-height (a build-time global), never a hardcoded constant. The
   platformer's brick-smash gap (round 7) was exactly this: an 88px capsule
   over a ~76px visible character.
29. **A `constant` must be declared BEFORE its first use, lexically.** OXT resolves
   `constant` names by their position in the file, so a handler that references a
   constant declared *later* gets an UNRESOLVED name: it compiles with no error,
   then evaluates to nothing at runtime, silently zeroing the expression. The L4
   lava serpent shipped broken this way — `pfTickLavaSerpent` used `sin(kPI * tP)`
   while `kPI` was declared ~900 lines below, so the term collapsed to 0 every
   frame and the serpent never rose (it stayed in its "submerged, hidden" branch
   forever). Fix: declare the constant above its first use, or inline the literal
   value. Distinct from gotcha 6 (constant *values* must be literals) — this is
   about the *order* of declaration vs use. (Confirmed in OXT.)

## The single-threaded performance playbook

OXT runs everything — physics FFI, script, rendering — on ONE interpreted
thread at ~60fps (≈16ms budget). The three real costs, in order:
**(1) interpreter ops, (2) FFI round-trips, (3) property-set redraws**
(each `set` of a field/control property can mean engine relayout+repaint).
The rules, each earned by a measured regression:

- **One hero snapshot per frame.** Read `b2kPosition`/`b2kPlayerState`
  ONCE in `on b2kFrame` into globals (`gHeroPX/PY/State`); every tick
  shares them. Eight ticks each doing their own read = ~8 needless
  FFI/string round-trips per frame.
- **One clock read per pass.** Hoist `the milliseconds` out of loops.
- **HUD/field text at 4 Hz max, and only on change.** An every-frame ms
  readout forces an every-frame field relayout+redraw — the single
  biggest avoidable cost found in the games.
- **Build once, write on change.** Never `create` controls mid-game
  (creates stall under accelerated rendering — the brick-debris lesson):
  POOL effects at build (debris, rings, dots) and park them off-world;
  reuse by MoveTo/SetDynamic. Pre-warm any sheet frame first shown
  mid-game (`b2kSheetEnsureIcon` at build — the lazy slice costs
  ~250ms/frame-name).
- **Skip redundant property sets.** The Kit's draw keys, `b2kSpriteFlipH`
  same-value guard, icon-now guard, gate-velocity-on-change — mirror the
  pattern for anything you add (loc writes, visibility flips).
- **Every idle tick gates in one compare.** A feature that is absent
  must cost a single `if` per frame (`gPlantN is 0`, `gGhostSpr is
  empty`, `sPlayLadN > 0` …).
- **Resolve at bind/set time, not per use.** Keycode lists resolve at
  bind time; player knobs bake into flat locals at set time; never pay
  name lookups in a per-frame path.
- **Let bodies sleep** (see gotcha 17) — and remember polls
  (`b2kOverlap*`) SEE sleeping bodies, so presence checks never need to
  keep things awake.
- **Defer world rebuilds out of the physics frame.** Rebuilding from
  inside a sensor/contact dispatch is asking for trouble: `send
  "nextLevel" to me in 80 milliseconds` (and guard the handler against
  stale sends with a mode/lock check).
- **Park before disable** (Wave 1 law): move a body off-world FIRST,
  then disable — disabling in place leaves its last broadphase position
  visible to queries for a beat.
- **Raw handles in hot paths.** Kit-internal per-frame code uses the
  cached body handle + raw `b2*` calls (skip the ref lookup and "x,y"
  string packing); reserve the friendly wrappers for event-path and
  build-time code.

## Layout & game-design laws (earned in OXT rounds)

- **THE LAYOUT LAW (Wave 2 closure): every interactive beat gets ~100px
  of clear air — widen the world before squeezing a beat in.** Cramped
  reads as "what IS all this?". When re-spacing, move each beat WHOLE
  (chain + art + cast together) so ghost padding and machine
  relationships survive; preserve deliberate pairings (key-by-thwomp,
  checkpoint-by-slime) at their original offsets.
- **Chains: solid span must equal art span.** Ghost rule (gotcha 15)
  applied mechanically: N points = N-3 solid segments; verify
  `sorted(xs)[1:-1]` against the tile extents (the audit script pattern).
- **Gates must be structural** (floor-to-ceiling; the win provably
  passes through them) · **scenery builds BEFORE actors** (the hero
  walks in front) · **never `b2kCamGoto` before `b2kCamBounds`** (an
  unclamped goto scroll-shifts everything built after it) · **no
  sub-capsule slots between statics** (solver squeeze ejects through
  walls; boundary slabs are THICK, ~256px).
- **The knockback-vs-respawn split (Wave 2):** contact damage =
  `b2kPlayerHurt` knockback + mercy window (`b2kPlayerHurtIs()` gates
  hazard checks); only lethal falls (pits, kill plane) use the respawn
  flow. An explicit `b2kPlayerControl` call cancels a knockback in
  flight, so the two paths hand over cleanly.
- **Self-counting totals:** coins/keys increment their totals as they
  BUILD (`gCoinsTotal` in the makers) so totals can never drift from
  the layout, and fallback levels' smaller totals fall out free.
- **Ladders:** run the zone a little above a platform at the ladder's
  top (walk-off + DOWN grabs it); zones are world state (`b2kClear`
  wipes them).
- **Liquids / SWIM (Wave 4):** a swim pool CANNOT be a sub-ground pit —
  `b2kCamBounds` clamps the camera at the world's bottom edge, so anything
  below the ground line is off-screen. A swimmable pool is a RAISED basin
  between two banks (or the whole ground raised, as the micro-game did):
  hop in, dive for the underwater coins, stroke up + hold-forward to HOP
  out the far bank. Water zones (`b2kPlayerAddWater`) are world state,
  wiped by `b2kClear` like ladders. **Tuning:** `swimGravity` sets only the
  between-stroke SINK; the single-stroke escape height is `swimJump` ALONE
  (the stroke sets velocity directly, then full air-gravity governs the
  apex once you break the surface). To make climbing out HARDER, lower
  `swimJump` — raising `swimGravity` only makes you sink faster between
  strokes.
- **Hazard mercy patterns:** a riser never rises under the hero's feet
  (the piranha); proximity hazards give a sprint-speed telegraph
  (mimic wake ≥110px); unkillable hazards follow "the saw rule" (skip
  or time them — no verdict needed).
- **Versioned chrome:** bump `kUIVersion`-style tags whenever built
  chrome changes so older saved stacks rebuild once; bump the
  newest-cue guard in `*MakeSounds` when adding a tone (sounds survive
  teardown, so the guard must key on the NEWEST name).

## The Contraption Builder (`examples/box2dxt-contraption-builder.livecodescript`)

The flagship example and the file most work happens in (~320 KB). Mental model:

- **It builds its own UI.** On open it programmatically constructs all chrome — top bar, palette,
  inspector, status bar — into the stack, then tags it with `kUIVersion`. **Bump `kUIVersion`
  whenever the built chrome changes** so older saved stacks rebuild once on load.
- **Parts are LiveCode graphics backed by Box2D bodies.** Placing a part creates a graphic, tags
  it (`tagPart` → sets `uKind`/`uColor`, calls `registerKind`), and (for body kinds) spawns a Kit
  body. `gParts` is the CR-list of part controls; joints live in parallel `gJ*` arrays.
- **The per-frame loop is `on b2kFrame`** (the Kit calls it each tick while running). It fans out to
  `renderJoints`, `updateFlashes`, `applyFieldForces`, `updateBombs`, `updateRings`,
  `updateLasers`, `updateThrusters`, `tickHud`. Build-mode redraws go through `renderBuild`.
- **No-body specials vs body parts.** Fans, magnets, the laser, and the goal zone have **no Box2D
  body** — they are pure graphics driven each frame. `kindHasBody(kind)` **must exclude them** (it
  returns false only for `fan`/`magnet`/`laser`/`goal`), or body-only code (`b2kAngle`,
  `reseatDragged`, …) will error on them. `kindIsDynamic` lists the kinds that fans/magnets can push.
- **Save/load** is text: `serializeText` emits `part` / `joint` / `world` records; each part packs
  its extras via `partSpecial` (KV string like `"ldr=45;tpw=700"`) and restores them in
  `applyPartSpecial`. `partLine` saves a part's **anchor** = its `loc`, **except** kinds whose
  meaningful anchor isn't the bbox centre (the laser saves its **emitter** = point 1 of the beam).

### Recipe: adding a new part/special kind

Every kind must be wired through the **whole pipeline** or it half-works. Touch all of these
(grep an existing special like `fan` or `laser` as a template), then verify:

1. **Constants:** add the id to `kShapeTools`/`kSpecialTools`/`kTerrainTools` and its `…Labels`
   constant. **Bump `kUIVersion`** (palette changed).
2. **`placePart`:** add a `case "<id>"` → `place<Id>(pX,pY)`.
3. **`place<Id>()`:** create the graphic, set style/size and `u*` props, `tagPart` it, return the ref.
   Body kinds call `b2kSpawnBox/Ball/Capsule/…`; no-body kinds are just a graphic.
4. **`registerKind`/`unregisterKind`:** add the id to the tracked-kinds list **if it needs a
   per-frame tick** (so `gKindList[id]` is populated).
5. **Per-frame tick:** write `update<Id>s`, add it to `on b2kFrame` (and to `renderBuild` if it must
   refresh in build mode, like the laser beam).
6. **Classification:** `kindHasBody` (exclude no-body specials!) and `kindIsDynamic`.
7. **Inspector:** `partProps` (keys per kind; each tab's keys ≤ `kPropRows` = 10), `propGroup`
   (which tab: shape/physics/collide/special), `propLabel` (human label per key), `adjustPartProp`
   (the +/- stepper per key). For type-in values also `currentPropValue`/`applyPropValue`.
8. **Save/load:** `partSpecial` (pack KV, keys unique within the kind) and `applyPartSpecial`
   (restore). If the anchor isn't the graphic's `loc`, special-case `partLine`.
9. **Cosmetics:** `toolGlyph` (one glyph), `toolHelp` (two lines: short title + long help),
   `niceName`/`friendlyKind`.
10. **Verify:** smart-quote scan = 0, handler balance = 0, `sync --check` clean; confirm no tab
    exceeds 10 rows and no save-key collides. Then the user tests in OXT.

**Invariants the static audits should always hold:** every kind has a `placePart`/glyph/`toolHelp`/
`niceName`; every `partProps` key has both a `propLabel` and an `adjustPartProp` case; no tab > 10
rows; save-keys unique per kind; selection is non-destructive (`selectPart` stores `uSelFg`/`uSelLine`
and `deselectPart` restores them, so highlighting never corrupts a part's real colours).

## Contributing conventions

- **Units/types across the FFI:** reals `double`, booleans `int` (0/1), handles positive `int`
  (0 invalid, opaque). `b2*` = metres/radians, `b2k*` = pixels/degrees.
- **Safety first:** every handler tolerates stale/0 handles (validate with `b2*_IsValid` in C;
  getters return 0, actions no-op). Never let a bad handle reach Box2D.
- **Adding a raw handler:** `b2lc_*` in `src/box2d_lc.c` (validate inputs) → `foreign handler` +
  public `b2*` wrapper in `src/box2dxt.lcb` → bump `LC_ABI_VERSION` if the ABI changed → add a
  `tests/smoke_test.c` assertion. Keep the shim warning-clean (`-Wall -Wextra`, `/W3` on MSVC).
- **Match the surrounding style** — comment density, naming, idiom. This codebase comments the
  *why*, densely; mirror that.

## Git / workflow notes

- The session's working branch is set per-task (e.g. `claude/...`); develop, commit, and push there,
  then open a **draft PR** if none exists. Don't push to `main` without explicit permission.
- A Kit change is only complete when `tools/sync-embedded-kit.py` has been run and the re-synced
  examples are committed **in the same change** — CI's `--check` fails otherwise.
