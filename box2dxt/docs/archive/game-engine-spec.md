# Box2Dxt Game Kit — Specification

> **ARCHIVED / HISTORICAL.** This is the pre-implementation *design spec* for the
> Game Kit modules (input · sprites · player · camera · audio). They are all
> implemented and user-verified — the living docs are
> [`../kit-guide.md`](../kit-guide.md) (teaching) and
> [`../kit-reference.md`](../kit-reference.md) (API), with the as-built decisions
> in [`../../plan.md`](../../plan.md). Kept for design-intent history only.

**Player objects, spritesheet animation, and keyboard control for Box2Dxt**

| | |
|---|---|
| Status | **Implemented and user-verified on Win32 (2026-06-11)** — all four modules + audio shipped; as-built deltas live in [plan.md](../../plan.md)'s decision log; runtime behaviour is asserted by `examples/box2dxt-selftest.livecodescript` (harness v22, ~180 checks across 37 test handlers, having grown with the content waves). macOS/Linux passes still open (risk R1). |
| Scope | New `b2k…` modules in the Kit: **Input**, **Sprites**, **Player**, **Camera** |
| Native impact | **None.** No C-shim or LCB changes; ABI stays at 4 |
| Companion | [plan.md](../../plan.md) — the phased implementation plan |

The end goal: make Box2Dxt + xTalk a credible **2D game engine** — you should be
able to build a small platformer (an animated character running and jumping
through a scrolling level) in under a hundred lines of card script, the same way
`b2kQuickStart` makes a physics toy a three-liner today.

- [1. Where the project stands today](#1-where-the-project-stands-today)
- [2. Research: what the OXT/LiveCode runtime offers](#2-research-what-the-oxtlivecode-runtime-offers)
- [3. Design](#3-design)
- [4. Module: Input](#4-module-input)
- [5. Module: Sprites](#5-module-sprites)
- [6. Module: Player](#6-module-player)
- [7. Module: Camera](#7-module-camera)
- [8. Loop integration and lifecycle](#8-loop-integration-and-lifecycle)
- [9. Asset conventions](#9-asset-conventions)
- [10. Risks and open questions](#10-risks-and-open-questions)
- [11. Out of scope (for now)](#11-out-of-scope-for-now)

---

## 1. Where the project stands today

A thorough review of all three layers, the examples, and the tooling. The short
version: **the physics side of a game engine is already done; every gap is in
the script layer.**

### 1.1 What already exists and is game-ready

| Game-engine need | Already covered by |
|---|---|
| Fixed-timestep loop, 60 Hz, accumulator, frame hook | `b2kStep` (`send … in 16 ms`, 1/60 s steps, clamped), `on b2kFrame` to a target object |
| Character collision shape | `b2kSpawnCapsule` / `b2kAddCapsule` (the canonical platformer body) |
| Upright character | `b2kSetFixedRotation`; non-graphic/non-image controls (incl. **groups**) get fixed rotation and position-only rendering automatically (`b2kAddCapsule` → render mode `"loc"`) |
| Move / jump forces | `b2kSetVelocity`, `b2kPush`, `b2kImpulse`, `b2kForce` |
| Ground / wall sensing | `b2kRayHit` (+ hit point, **surface normal**, distance), `b2kRayHitAll`, `b2kOverlap` |
| Triggers (coins, exits, hazards) | Sensors: `b2kAddSensor`, `on b2kSensorEnter/Exit`, polling accessors |
| Hit strength (landing thumps, damage) | Raw layer `b2ContactHit…` events with impact speed |
| Collision layers (player vs enemy vs decor) | `b2kDefineLayer` / `b2kSetCategory` / `b2kSetMask` (32 named layers) |
| Terrain, slopes | `b2kChain` / `b2kSmoothGround` (one-sided, no ghost bumps); `b2kWall` segments |
| Moving platforms | `b2kSetKinematic` + `b2kMoveTo` / raw `b2SetTargetTransform` |
| Fast-body tunnelling | `b2kSetBullet`, `b2kEnableContinuous` |
| Render performance | `acceleratedRendering` + `layerMode "dynamic"` — already proven in the contraption builder (incl. the popup workaround) |

The raw `b2…` layer wraps the **full Box2D v3.1 live-object surface** (ABI 4),
including multi-shape bodies and the shape-def builder (`b2ShapeDefSensor` on a
*dynamic* body's extra fixture — useful for foot sensors). **Nothing in this
spec requires touching `box2d_lc.c` or `box2dxt.lcb`.**

### 1.2 The gaps

| Gap | Today | Consequence |
|---|---|---|
| **Held-key input** | Examples use `on arrowKey` only — one event per OS auto-repeat | No smooth run, no chords (run + jump), no edge detection |
| **Animation** | None. Kit's `"image"` render mode rotates one static image | No animated characters at all |
| **Spritesheets** | Builder imports single PNG/JPG/GIF as a static image part | No frame-based art pipeline |
| **Player controller** | None | Everyone reinvents ground checks, jump feel, state machines — badly |
| **Camera** | Fixed view, world == card | No levels larger than the window, no scrolling, no parallax |
| **Game scaffolding** | Builder has save/load + goal-zone precedents, nothing reusable | Each game rebuilds scenes/HUD/audio glue |

### 1.3 Constraints inherited from the repo

- The Kit is the **single source of truth**; every Kit change must re-run
  `tools/sync-embedded-kit.py` and commit the re-synced examples together.
- OXT compiles stricter than LiveCode: straight quotes only, no token-shadowing
  names (multi-word `u…` stems), literal constants, balanced handlers —
  `tools/check-livecodescript.py` gates all of it.
- **No headless runtime here**: everything below that claims runtime behaviour
  is marked *(verify in OXT)* and is bundled into the Phase 0 spike stack.

---

## 2. Research: what the OXT/LiveCode runtime offers

OXT forked LiveCode Community 9.6.x, so the LC 9.6 engine surface is the
baseline. Findings, by feature, with confidence levels:

### 2.1 Keyboard

| Primitive | What it gives us | Confidence |
|---|---|---|
| **`the keysDown`** | Comma-list of keycodes of **all keys currently held** — the same codes as `rawKeyDown`. Pollable from any handler, no focus or message-path requirements. | **Confirmed on OXT/Win32** (Phase 0 spike: 3-key chords, arrows+space+letters all reported correctly); macOS/Linux pending |
| `rawKeyDown` / `rawKeyUp` | Per-key edge messages with numeric keycodes. Caveats: OS auto-repeat re-sends `rawKeyDown` while held (confirmed Win32: 21 downs vs 5 ups in the spike — no paired ups), and the messages only reach scripts in the message path (fields and `traversalOn` buttons steal them). | High — repeat noise confirmed, which is exactly why polling wins |
| `keyDown` / `arrowKey` / etc. | Cooked, auto-repeat-paced — what the examples use now. Fine for UI, wrong for movement. | High (already in use) |

**Conclusion — polling wins.** Sampling `the keysDown` once per `b2kFrame` and
**diffing against the previous frame** gives held-state *and* clean
pressed/released edges in one mechanism, with zero auto-repeat artifacts and no
frontscript or focus gymnastics. Event-based `rawKeyDown` tracking (via
`insert script … into front` when the Kit runs as a library) is the documented
**fallback** if the spike finds `keysDown` unreliable on any OXT platform.

Useful keycodes (same values across platforms — X11 keysyms): arrows
`65361/65362/65363/65364` (L/U/R/D), space `32`, return `65293`, shift `65505`,
escape `65307`, letters = ASCII (`a` 97 … `z` 122). **Gotcha:** letter keysyms
are case-shifted — with Shift held, `w` reports `87` not `119`; the key-name
map must match both.

### 2.2 Bitmap animation primitives

Four viable mechanisms, in order of usefulness:

1. **Group-clip + scroll** *(secondary backend — outperformed by item 3 in
   the spike)*. An unadorned group with `lockLoc` true **clips its contents
   to its rect**, and setting `the hScroll` / `the vScroll` of the group pans
   which part of the content shows. Put the sheet image inside a frame-sized
   group; showing cell `(row, col)` is just `set the hScroll to col * frameW`
   / `vScroll to row * frameH`. Zero pixel copying at frame-switch time,
   engine-rendered, full PNG alpha. Spike verdict: works and renders
   correctly, but each sprite carries its own sheet copy (~220–285 ms to
   build) and 25 moving instances ran ~31% slower than icon-flip (S10 vs
   S12). Kept for sheet-direct cases (huge sheets, live sheet edits).
2. **Animated GIF**: an image displays an animated GIF natively;
   `the frameCount`, settable `the currentFrame`, `the repeatCount` (-1 loop,
   0 stop) give free playback *or* manual frame control. Limitations: 256
   colours, 1-bit alpha. Confidence: high. Supported as a **secondary sprite
   backend** (cheapest possible asset path).
3. **Pre-sliced frames + icon flip** *(PRIMARY — promoted by spike S12)*:
   slice the sheet once at load into N hidden images (one per frame), then
   `set the icon of a transparent button` per frame. The classic LC game
   technique, and the spike's winner on the identical 25-sprite scene: warm
   40.2 fps vs 30.7 for group-scroll, build 3.8 s vs 6.6 s, first-frame stall
   halved — and all sprites **share** the frame images instead of carrying
   sheet copies. Also the basis for *rotating* sprites later (image `angle`
   resamples from the original, as `b2kDrawImage` already exploits).
4. **`flip image`** horizontal — for generating left-facing copies of a sheet
   at load time. *(verify in OXT; fallback: reverse each `imageData` row in
   script, one-time)*.

**Mirroring** (facing left/right) is **not** available as a render transform in
LC — there is no negative-scale draw. The Kit will lazily build a flipped copy
of a sheet the first time a sprite faces left, and swap which sheet the
sprite's inner image shows. Column indices mirror (`col' = cols - 1 - col`).

**Rotation**: groups do not rotate, so scroll-backend sprites render upright.
That matches the player design (fixed rotation) exactly. Rotating animated
sprites (a spinning shell) are a later feature via mechanism 3.

### 2.3 Rendering performance

`set the acceleratedRendering of this stack to true` plus
`set the layerMode of <moving control> to "dynamic"` is already this repo's
practice (contraption builder, ROADMAP §1.3), including the known workaround of
toggling acceleration off under modal popups. Sprites add one wrinkle: a
dynamic-layer **group** has its composite cached, and each animation
frame-change invalidates it. At sprite animation rates (8–12 fps per sprite,
frame-sized surfaces) this is small; the spike measures it (target: 25+ animated
sprites + physics at 60 fps on a mid laptop). *(verify in OXT)*

### 2.4 Camera

The same group-scroll trick at playfield scale: put all world controls into one
clipped **viewport group** and set its `hScroll`/`vScroll` each frame. Two
properties make this a perfect fit:

- Controls inside a scrolled group keep **card coordinates** — the Kit's
  body-sync (`set the loc/points/rect of <ctrl>`) needs **zero changes**; the
  scroll is pure presentation on top.
- With acceleratedRendering, scrolling composites cached layers instead of
  re-rasterising the scene.

Mouse mapping must become camera-aware (`world = mouse + scroll − viewport
offset`) — helper functions cover it. HUD lives outside the group; parallax =
additional groups scrolled at a fraction of the camera. *(verify in OXT: scroll
cost on a card-sized group, input mapping)*

### 2.5 Timing and audio

- `b2kFrame` fires once per rendered frame after 0..n fixed steps. Animation is
  presentation, so sprites advance on **wall-clock milliseconds** (`the
  milliseconds`), not step count. A `b2kFrameMS()` helper exposes the frame
  delta the loop already computes.
- Audio (`play` for SFX, player objects for music) is real but platform-quirky;
  deferred to the game-scaffolding phase (see plan, Phase 5) and out of this
  spec's core.

### 2.6 The single-threaded budget

xTalk script runs on one engine thread, and that thread also paints. Is a game
engine *usable* on it? Yes — within a stated envelope — because the design
keeps the per-frame **script** work small, bounded, and constant, and pushes
the heavy work to native code:

| Frame cost (target: 16.7 ms @ 60 fps) | Where it runs | Expected size |
|---|---|---|
| `b2Step` (physics, 50–150 bodies) | Native C (and `b2NewThreadedWorld` can use a Box2D worker pool with no script-side change) | well under 1 ms — measurable via `b2kProfile()` |
| Body→control sync | Script + FFI, already event-driven and redraw-suppressed | ≈ 1–3 ms at 30 moving bodies |
| Input tick | 1 `keysDown` call + short list diff | microseconds |
| Player tick | 10–20 FFI calls incl. 2–3 ray casts | well under 1 ms |
| Sprite tick (25 sprites) | 25 script comparisons; 2 property sets only on frames where an animation actually advances (sprites animate at 8–12 fps, not 60) | ≈ 1 ms |
| Camera tick | lerp math + 2 scroll sets (compositor moves cached layers) | small; **empirical — spike S9** |
| Compositing / property-set redraw | Engine, accelerated layers | the real variable — **spike S9/S10** |

Consequences the design accepts and documents:

- **Pacing, not throughput, is the first failure mode.** `send … in 16 ms` is
  not vsync-locked and the loop schedules the next step *after* the frame's
  work, so a loaded frame drifts the real rate down. **Measured (Phase 0,
  Win32): 16.5 ms average idle cadence, max 17–18 ms** once settling ticks are
  discarded — an idle ceiling of ~58–60 fps that every millisecond of frame
  work erodes (the v1 camera scene held ~55 steady). The fixed-step
  accumulator means none of this can corrupt the simulation — the cost is
  render rate, not physics jitter. Phase 1 therefore **must** include the
  pacing fix: schedule the next step `in max(1, 16 − elapsed)` ms.
- **One budget, shared with user code.** There is no other thread: a blocking
  call anywhere (`answer`, `wait`, synchronous file I/O) stalls the world.
  Game code must defer blocking work to pause states — a documented constraint
  the contraption builder already lives with.
- **The envelope** is dozens of active bodies plus a few dozen animated
  sprites at 60 fps (GameMaker-circa-2005 scale, which matches the project
  goal) — not bullet-hell or 500 entities. The degradation ladder when a scene
  is too heavy: lower per-sprite animation fps → fewer awake bodies (sleeping
  is cheap) → render at 30 fps with the sim still stepping at 60 Hz. The sim
  rate is never lowered.
- All of the empirical cells above are measured by **Phase 0 spike scenes S9
  and S10** on real OXT hardware before any module is built (risk R6).

---

## 3. Design

### 3.1 Shape of the change

All four modules go **into the single existing Kit**
(`src/box2dxt-kit.livecodescript`), as new sections following the Kit's
conventions (`b2k` prefix, commands report via `the result`, script-local
`s…` state, dense *why* comments).

*Considered and rejected:* a separate `box2dxt-gamekit.livecodescript`. It
would keep the physics Kit lean, but: the sprite/player/camera ticks belong
*inside* `b2kStep`'s screen-lock (a second file would need new frame-hook
plumbing and a chained `b2kFrame`); the sync tool and examples assume one
embedded region; and "one Kit, batteries included" is the project's stated
philosophy. The Kit grows ~25 KB — the builder already embeds 78 KB without
trouble.

**Estimated new surface: ~50 public handlers** (10 input, 16 sprites, 13
player, 11 camera) — the tables below are the authoritative list.

### 3.2 Design principles

1. **Pixels and degrees**, like every `b2k…` handler. Speeds in px/s, times in
   ms.
2. **Stale-safe**: every handler tolerates a missing/removed control or unknown
   sheet/anim name as a no-op, mirroring the FFI's handle philosophy.
3. **Pure additive**: no existing handler changes signature or behaviour;
   the contraption builder and demo must run unmodified after the sync.
4. **Multi-instance from day one**: sprite and player state is keyed by control
   reference (like `sBody`/`sRender`), so NPCs/enemies reuse the same machinery
   even though v1 ships a single keyboard-driven player.
5. **OXT-compile-safe**: straight quotes; distinctive multi-word custom-property
   stems (`uSheetName`, `uAnimFrame` — never `uFrame`/`uMask`-style
   token-shadowers); literal constants only.

---

## 4. Module: Input

**Model:** one `keysDown` sample per frame, diffed against the previous sample.
Held = in the current set; *pressed* = in current, not in previous; *released*
= in previous, not in current. No event handlers required, no focus issues, no
auto-repeat noise. `b2kInputOn` arms it; the sample runs inside the loop just
before the `b2kFrame` dispatch, so user code always sees this frame's state.

| Handler | Purpose |
|---|---|
| `b2kInputOn` / `b2kInputOff` | Arm / disarm per-frame sampling (auto-armed by `b2kPlayerMake`). |
| `b2kKeyIsDown(key)` → bool | Key currently held. `key` = friendly name (`"left"`, `"space"`, `"a"`) or raw keycode. |
| `b2kKeyPressed(key)` / `b2kKeyReleased(key)` → bool | Edge: went down / came up **this frame**. |
| `b2kKeysHeld()` → list | All held keys (friendly names where known) — debugging/HUD. |
| `b2kBindAction pName, pKeyList` | Name a key set: `b2kBindAction "jump", "space,up,w"`. |
| `b2kActionIsDown(name)` / `b2kActionPressed(name)` / `b2kActionReleased(name)` → bool | Action-level queries (any bound key). |
| `b2kAxis(name)` → -1/0/1 | Built-in axes `"moveX"`/`"moveY"`, default arrows + WASD; rebind via `b2kBindAxis name, negKeys, posKeys`. |

Implementation notes:

- Key-name map covers arrows, space, return, escape, tab, shift, control,
  letters, digits; letters register **both cases** of their keysym (the Shift
  gotcha, §2.1). Unknown names fall through as numeric codes.
- The previous/current sets are small comma-lists; the diff is a few `among`
  checks — negligible per-frame cost.
- Games should keep focusable chrome off their cards (`traversalOn` false), as
  the builder already does; documented in the kit guide.
- Fallback path (only if the spike fails): `b2kInputOn` additionally inserts
  the Kit as a frontscript with `rawKeyDown`/`rawKeyUp` handlers that maintain
  the same sets and **pass** the messages on; the public API is identical
  either way — callers never know which backend is live.

## 5. Module: Sprites

**Model** *(updated per spike S12)*: a *sheet* is registered once and
**sliced into one hidden image per frame** (engine-side copy; mirrored copies
made lazily the first time a sprite faces left). A *sprite* is a
**transparent button** whose `icon` is the current frame's image — a frame
switch is one property set, and every sprite of a sheet **shares** the same
frame images (no per-sprite pixel copies). Animations are named frame
sequences on the sheet, ticked centrally by the loop on wall-clock time. The
group-clip + scroll mechanism (§2.2-1) remains the documented secondary
backend for sheet-direct cases.

A sprite button is an ordinary Kit control: pass it to `b2kAddCapsule`/
`b2kAddBox` and it gets a body with **fixed rotation and `"loc"` rendering
automatically** (buttons are neither graphics nor images — see §1.1). That
one existing behaviour is what makes sprites compose with physics for free.

| Handler | Purpose |
|---|---|
| `b2kSheetLoad pName, pPath, pFrameW, pFrameH` | Import an image file as a sheet, derive the column/row grid from its size. Reports frame count. |
| `b2kSheetFromImage pName, pImgRef, pFrameW, pFrameH` | Register an image already in the stack (incl. base64-embedded art) as a sheet. |
| `b2kSheetLoadAtlas pName, pPngPath [,pXmlPath]` | Register a packed atlas: PNG + TextureAtlas XML naming its regions (the Kenney format in `Spritesheets/`). Frames are addressed **by name**; regions may be any size/position. *(Added when the project's asset pack arrived.)* |
| `b2kSheetFrames(pName)` → int / `b2kSheetHasFrame(pName, pFrame)` | Frame count / existence (0/false = unknown). |
| `b2kAnimDef pSheet, pAnim, pFrames, pFPS [,pLoop]` | Define a named animation: `pFrames` like `"1-8"` or `"1,2,3,2"`; `pLoop` default true. |
| `b2kSpriteNew pSheet [,pX, pY]` → control | Build the clipped group + inner image; shows frame 1. Reports the control ref. |
| `b2kSpriteFromGIF pPath [,pX, pY]` → control | GIF-backed sprite (engine plays it; `b2kSpritePlay`/`SetFrame` drive `currentFrame`/`repeatCount` instead of scroll). |
| `b2kSpritePlay pCtrl, pAnim [,pRestart]` | Start/resume a named animation (no-op if already playing it, unless `pRestart`). |
| `b2kSpriteStop pCtrl` | Freeze on the current frame. |
| `b2kSpriteAnim(pCtrl)` → name | Currently playing animation (empty = stopped). |
| `b2kSpriteSetFrame pCtrl, pN` / `b2kSpriteFrame(pCtrl)` | Manual frame control (1-based). |
| `b2kSpriteFlipH pCtrl, pFlag` / `b2kSpriteFlipped(pCtrl)` | Face left/right. First left-facing use of a sheet lazily builds the mirrored copy (§2.2). |
| `b2kSpriteFPS pCtrl, pFPS` | Per-sprite speed override (run faster when sprinting). |
| `b2kSpriteOnFinish pCtrl, pMessage` | For non-looping anims: send `pMessage pCtrl, pAnim` to the frame target when it ends (attack/death chaining). |
| `b2kSpriteBind pCtrl, pBodyCtrl [,dx,dy]` / `b2kSpriteUnbind` | Pin the sprite to another control's position each frame — an invisible control owns the body, the art follows it, so collision size is independent of art size. |
| `b2kSpriteRemove pCtrl` | Unregister and delete the sprite (and via `b2kRemove` its body, if any). |

Implementation notes:

- Per-sprite state in script-locals keyed by ref: sheet, anim, frame index,
  ms-accumulator, fps, flip, finish-message. The tick walks one array of live
  sprites; a sprite whose frame did not change this tick touches **no**
  properties (the `sDrawKey` redundancy-suppression pattern, reused).
- Sprites share their sheet's frame images; building a sprite is creating one
  transparent button. (The spike measured per-sprite group+sheet-copy builds
  at ~220–285 ms on modest hardware — buttons avoid that entirely.) Phase 2
  still pools sprites at scene load and creates them **before** enabling
  `acceleratedRendering`, because the spike's one-time first-frame stall
  followed bulk control creation under the compositor.
- Sprites default to `layerMode "dynamic"` and mouse-transparent
  (the group never traps clicks aimed at the playfield).
- `b2kClear`/`b2kTeardown` remove Kit-spawned sprites with everything else;
  sheets persist until `b2kTeardown` (they are assets, not world state).

## 6. Module: Player

**Model:** a vertical **capsule** body (no corner-catching on tile seams),
**fixed rotation**, **sleep disabled** (a player must always respond), low
friction (horizontal motion is velocity-driven, so wall friction can't glue the
character to surfaces), driven by a per-frame controller tick that reads the
Input module and writes `b2kSetVelocity` x / preserves y.

| Handler | Purpose |
|---|---|
| `b2kPlayerMake pX, pY, pW, pH [,pSheet]` → control | One call: sprite (or plain capsule graphic if no sheet), capsule body, controller defaults, input armed. Reports the control. |
| `b2kPlayerAttach pCtrl` | Adopt an existing control/sprite as the player (capsule body added if it has none). |
| `b2kPlayerSet pKey, pValue` / `b2kPlayerGet(pKey)` | Tuning knobs (table below). |
| `b2kPlayerAnims pIdle, pRun, pJump, pFall [,pLand] [,pDuck] [,pClimb] [,pHurt] [,pSwim] [,pWall] [,pDash]` | Map controller states to sheet animations; auto-`FlipH` from facing. (Wave 2-5 slots are optional fallbacks — see kit-reference.) |
| `b2kPlayerOnGround()` → bool | Grounded this frame (post-tick). |
| `b2kPlayerState()` → word | `idle` / `run` / `jump` / `fall` / `duck` / `climb` / `hurt` / `swim` / `wallslide` / `dash` (+ `land` transition tick). |
| `b2kPlayerFacing()` → 1 / -1 | Last horizontal intent. |
| `b2kPlayerJump [pSpeed]` | Programmatic jump (springs, double-jump powerups) — respects the same state machine. |
| `b2kPlayerControl pFlag` | Enable/disable input→motion (cutscenes; physics continues). |
| `b2kPlayerRemove` | Tear down controller state (body/sprite removal via the normal calls). |
| `b2kSetSleepEnabled pCtrl, pFlag` | *(general Kit addition)* wraps raw `b2EnableSleep` — used by the controller, useful generally. |

**Tuning keys** (`b2kPlayerSet`), with defaults chosen for a 32×48 px player at
scale 40: `moveSpeed` 220 px/s · `accel` 1800 px/s² · `airAccel` 1100 px/s² ·
`jumpSpeed` 460 px/s · `jumpCut` 0.45 (velocity multiplier on early release —
variable jump height) · `coyoteMs` 90 (jump grace after leaving a ledge) ·
`bufferMs` 110 (jump pressed just before landing still fires) · `maxFall`
900 px/s · `maxSlopeDeg` 50 (steeper = not ground).

**Ground sensing:** 2–3 short downward `b2kRayHit` casts from points across the
capsule's bottom, length ≈ 4 px below the shape. A hit counts as ground only if
its **screen normal** points sufficiently up (`b2kRayHitNormalY() ≤
−cos(maxSlope)`), which makes slope-walkable vs wall a single comparison. Box2D
rays do not report the convex shape they start inside, so self-hits are
structurally avoided; `b2kRayHitAll`-with-self-skip is the documented fallback
*(verify in OXT spike)*. A foot **sensor fixture** (shape-def sensor on the same
body) is the plan-B mechanism — both are possible today, rays are simpler.

**State machine:** grounded & |vx| < ε → `idle`; grounded & moving → `run`;
airborne & vy upward → `jump`; airborne & falling → `fall`; `fall`→grounded
emits one `land` tick (for dust puffs / landing sounds via `b2kSpriteOnFinish`
or the frame hook). State changes drive `b2kSpritePlay` + `b2kSpriteFlipH`
automatically when `b2kPlayerAnims` is set.

**One-way platforms are in** (no longer deferred): the spike confirmed chain
segments are one-sided exactly the way platformers need — a capsule rises
through from below and lands on top (`b2kChain`/`b2kSmoothGround`, top surface
listed right-to-left; plain `b2kWall` segments are two-sided and cannot do
this). **Explicitly deferred** (designed-for, not in v1) — most have
since landed: **drop-through** and **ladders** in Wave 2, **SWIM zones** in
Wave 4, and **wall-jump/slide**, **dash**, **double-jump**, **duck
capsule-reshape** + **moving-platform velocity carry** in Wave 5 (v1 had
relied on friction for the carry). Still ahead: multiple simultaneous
players (state is per-control already; only the input bindings are global).

## 7. Module: Camera

**Model:** one clipped, lockLoc'd **viewport group**; all world controls live
inside it; the camera tick sets `hScroll`/`vScroll`. Kit rendering is
untouched (§2.4). HUD/chrome stays outside the group.

| Handler | Purpose |
|---|---|
| `b2kCamOn [pRect]` | Create/adopt the viewport group (default: the card rect). New `b2kSpawn…`/`b2kSpriteNew` controls are placed into it while the camera is on. |
| `b2kCamOff` | Ungroup back to the card, reset scroll. |
| `b2kCamAdopt pCtrlList` | Move pre-existing controls (IDE-designed levels) into the viewport. |
| `b2kCamFollow pCtrl [,pLerp]` | Track a control; `pLerp` 0..1 smooths (default 0.15). |
| `b2kCamUnfollow` | Stop tracking (manual camera). |
| `b2kCamDeadzone pW, pH` | Follow only when the target leaves a centre box. |
| `b2kCamBounds pX1, pY1, pX2, pY2` | Clamp the view to level bounds. |
| `b2kCamGoto pX, pY` | Centre the view on a world point (cuts; respects bounds). |
| `b2kCamPos()` → "x,y" | Current view centre (world px). |
| `b2kCamShake pAmpPx, pMs` | Decaying random offset on top of follow (explosions). |
| `b2kCamMouseX()` / `b2kCamMouseY()` | The mouse in **world** pixels (camera-aware) — use these instead of `the mouseH/V` for `b2kGrab`, spawning at the pointer, etc. |

Parallax ships as a documented recipe (a background group scrolled at
`factor × camera`), not API, until a real game needs more.

## 8. Loop integration and lifecycle

Order inside `b2kStep`'s existing per-frame screen lock (new ticks in bold):

```
b2Step × n (fixed 1/60)            -- unchanged
lock screen
   b2kSyncBodies                   -- unchanged: bodies → controls
   **b2kInputTick**                -- sample keysDown, compute edges
   **b2kPlayerTick**               -- read input, rays, velocity, state, anims
   **b2kSpritesTick**              -- advance animations (wall-clock ms)
   **b2kCamTick**                  -- follow/shake → viewport scroll
   b2kDispatchContacts/Sensors     -- unchanged
   dispatch "b2kFrame"             -- unchanged: user logic sees final state
unlock screen
```

Each tick exits immediately when its module is unused (one `if … is empty`),
so a physics-only stack pays nothing. `b2kFrameMS()` (new) exposes the frame's
elapsed ms for user animation/timers. `b2kPause` freezes ticks with the
stepper; `b2kTeardown` releases all module state (sheets included);
`b2kClear` removes sprites/player with the other Kit-spawned controls but
keeps sheets, bindings, and camera config.

## 9. Asset conventions

- **Sheets:** two supported shapes. (1) **Uniform grid** — frames numbered
  left-to-right, top-to-bottom, 1-based; row-per-animation recommended; no
  spacing between cells. (2) **Packed atlas** — PNG + TextureAtlas XML naming
  each region (`<SubTexture name=".." x=".." y=".." width=".." height=".."/>`);
  this is the Kenney format of the repo's `Spritesheets/` pack, and the richer
  option (named frames, mixed sizes, spacing tolerated since regions are
  explicit). PNG with alpha preferred; GIF accepted via the GIF backend.
- **Custom art guidance** (for hand-made sheets): keep every frame of one
  character the same cell size, character centred horizontally with feet on a
  consistent baseline (sprites anchor by centre, so a wandering baseline
  bobs); draw facing **right** (the Kit mirrors lazily); full alpha
  background, no matte.
- **Self-contained examples:** example stacks can't ship loose PNGs, so the
  platformer example embeds a small CC0 placeholder sheet as **base64 in the
  script** (`set the text of img to base64Decode(kPlayerSheetB64)`), registered
  via `b2kSheetFromImage` — plus an "import your own sheet" button reusing the
  builder's `answer file` pattern.
- **User projects:** `b2kSheetLoad` from disk; the builder's image-library
  pattern (import once, reuse) is the eventual asset-manager direction
  (ROADMAP §3.3).

## 10. Risks and open questions

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| R1 | `the keysDown` unreliable on some OXT platform | **Resolved on Win32** (works); other platforms pending | Fallback frontscript backend (§4) behind the same API stays specced |
| R2 | Sprite rendering cost under `acceleratedRendering` | **Resolved — backend decided.** S12 vs S10, identical scene: icon-buttons warm 40.2 fps vs scroll-groups 30.7, build 3.8 s vs 6.6 s, first-frame stall 6.6 s vs 13.5 s → **icon-button backend is Phase 2's primary** (§5). Neither reaches the ~58 fps ceiling at 25 *moving* sprites on modest hardware | Phase 2: pool sprites at load, create before enabling acceleration, document the per-scene budget (a player + ~10 sprites sits near the ceiling); scroll-groups stay as the secondary backend |
| R3 | `flip image` missing/odd in OXT | **Resolved** (works on Win32, byte-verified) | Script-side `imageData` row-mirror fallback no longer needed |
| R4 | Ray-from-inside-shape self-hit behaviour differs | **Resolved** (self-skip confirmed; ray-all also skips; normal and distance exact) | — |
| R5 | One-way platforms: segment/chain one-sidedness vs a jumping capsule | **Resolved** — chains are one-sided exactly as platformers need (S8: rose through from below, landed on top); plain segments are two-sided and out | One-way ledges = `b2kChain`/`b2kSmoothGround`, top surface right-to-left; player drop-through stays deferred (mask-window technique) |
| R10 | Grouped-control coordinates under scroll | **Resolved — the camera's hardest bug.** OXT reports/sets grouped locs SCROLL-ADJUSTED (visual coords), so per-frame world-coordinate writes into the viewport cancelled the pan (the player "outran" the camera at 2x). `b2kCamOn` now probes the engine's model and every in-viewport write compensates via `b2kCamShiftX/Y`; `b2kSpriteMoveTo` covers hand-animated moves | On content-semantics engines all offsets are 0 — correct on both |
| R9 | Calling Kit *commands* with function syntax (`get b2kSpawnBall(...)`) | **Resolved — confirmed broken** (S11: throws at the call line without entering the handler). Statement + `the result` is the only calling convention | Fixed everywhere: Kit internals (`b2kSmoothGround`, `b2kLayerBits` named layers), the builder's servo joint, the 60-second starts and ~25 kit-guide snippets; CHANGELOG records it |
| R6 | Perf: 25+ animated sprites + camera at 60 fps on mid hardware | Medium | Redundancy-suppressed ticks; dynamic layers; spike has a numbered scene; degrade by lowering anim fps, never sim rate |
| R7 | Kit growth (~25 KB) bloats embedded examples | Certain, accepted | By design; sync tool unchanged; ticks early-exit when unused |
| R8 | OXT compile strictness on new code | Certain | Existing static gates run on every edit; naming rules in §3.2 |

**Open questions** (decided during implementation, recorded in plan.md's
decision log): sprite instancing strategy — the script `imageData` copy
measured ~250 ms per sprite on modest hardware, so v3 tests engine
`copy … to group` and Phase 2 likely pools sprites at scene load either way;
whether `b2kPlayerMake` with no sheet draws a capsule graphic or stays
invisible; camera + `b2kAddWalls` interaction (walls should bound the *level*,
not the card, when the camera is on).

## 11. Out of scope (for now)

Deliberately not in this spec, sketched as later phases in [plan.md](../../plan.md):

- **Tilemaps / level editor** — `b2kChain` terrain + IDE-placed controls +
  `b2kCamAdopt` cover small levels; a tile pipeline is its own design.
- **Audio module** — Phase 5; `play` + player-object wrappers with platform
  notes.
- **Scenes/levels format** — the builder's `serializeText` save format is the
  natural seed; needs a design pass once a real game exists.
- **Enemies/AI behaviours** — the sprite+body+sensor primitives compose into
  these; ship as example-level patterns first, API later.
- **Rotating sprites, particles, text styling, gamepads** (no engine gamepad
  support — keyboard only), networking.
