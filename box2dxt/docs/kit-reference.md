# Box2Dxt Kit Reference (`b2k…`)

The **Kit** (`src/box2dxt-kit.livecodescript`) is a batteries-included,
pure-xTalk toolkit over the `box2dxt` extension. You work in **pixels, screen
coordinates and degrees**; the Kit hides the world, the fixed-timestep loop,
coordinate conversion, and the per-frame control updates — and it runs with the
demo's performance practices built in.

**Setup:** paste the Kit into your card/stack script (or save it as a library
stack and `start using` it). It requires the `box2dxt` extension loaded
(`put b2Version()` should return `4`).

> **New here?** Read the [**Complete Guide**](kit-guide.md) first — it teaches
> the Kit start-to-finish with runnable examples. This page is the quick-lookup
> reference.

- [60-second start](#60-second-start)
- [World & loop](#world--loop)
- [Configuration](#configuration)
- [Attach & spawn](#attach--spawn)
- [Materials](#materials)
- [Body settings](#body-settings)
- [Act on bodies](#act-on-bodies)
- [Read state](#read-state)
- [Joints](#joints)
- [Input (keyboard)](#input-keyboard)
- [Sprites & animation](#sprites--animation)
- [Player (the platformer controller)](#player-the-platformer-controller)
- [Camera (scrolling levels)](#camera-scrolling-levels)
- [Sound (SFX)](#sound-sfx--with-or-without-asset-files)
- [Drag & events](#drag--events)
- [Sensors (trigger zones)](#sensors-trigger-zones)
- [Collision filtering (named layers)](#collision-filtering-named-layers)
- [Chains & terrain](#chains--terrain)
- [Region & ray queries](#region--ray-queries)
- [Motors & tuning](#motors--tuning)
- [Tips](#tips)

---

## 60-second start

```
on openCard
   b2kQuickStart                       -- world + gravity + card-edge walls + go
   b2kSpawnBall 200, 80, 50            -- create & drop a 50px ball
   b2kSpawnBox 260, 80, 60, 40, "orange"  -- (read `the result` for the ref)
   b2kContactTarget the long id of me  -- (optional) collision messages
end openCard
on mouseDown ; get b2kGrab(the mouseH, the mouseV) ; end mouseDown
on mouseUp   ; b2kRelease ; end mouseUp
on closeCard ; b2kStop ; end closeCard
```

Or **attach controls you designed in the IDE** (graphics rotate; other control
types follow position):

```
b2kSetup                                       -- world + gravity, auto origin
b2kAddStatic the long id of graphic "Floor"
b2kAddBox    the long id of graphic "Crate"
b2kAddBall   the long id of graphic "Ball"
b2kContactTarget the long id of me             -- on b2kContact pA, pB
b2kStart
```

## World & loop

| Handler | Purpose |
|---------|---------|
| `b2kSetup [gx, gy]` | Create the world + gravity, auto-detect the origin. |
| `b2kQuickStart [gy]` | One call: world + gravity + card-edge walls + start the loop. |
| `b2kStart` / `b2kStop` | Begin / end the simulation loop. |
| `b2kPause` / `b2kResume` | Freeze / resume stepping without tearing down. |
| `b2kStepOnce` | Advance exactly one fixed step (even while paused) — drives a Step button. |
| `b2kIsRunning()` | True while the loop is stepping (not stopped or paused). |
| `b2kAddWalls` | Static walls around the current card edges. |
| `b2kAddGround [screenY]` | A static floor across the card (optionally at a given Y). |
| `b2kWall x1, y1, x2, y2` | A static collision segment between two screen points (custom walls, ramps, ledges). **Two-sided** — bodies collide from both sides whichever way you list the points; for one-sided (jump-through) surfaces use `b2kChain`/`b2kSmoothGround`. Invisible — draw your own graphic to match. For level *edges* a character is driven against, prefer a thick invisible static box just outside the play space — it gives the solver a cleaner stop than a thin segment. |
| `b2kKillFloor screenY` | Destroy any **moving** Kit body whose centre falls below this line (empty = off) — crates shoved into pits, enemies knocked off the level: removed instead of falling forever. The player's body is exempt (your game owns its respawn). Each removal first sends **`b2kFell ctrl`** to the frame target so you can clean up companions (bound sprites, table slots); don't delete the control inside that handler. |
| `b2kClear` | Remove all bodies/controls the Kit created, keep the world. |
| `b2kTeardown` | Stop and destroy the world and all Kit state. |
| `b2kVersion()` | Native shim ABI version (`4`) — a load / in-sync check from Kit-only code. |

## Configuration

| Handler | Purpose |
|---------|---------|
| `b2kSetScale px` | Pixels per metre (default 40). |
| `b2kSetOrigin x, y` | Screen point that maps to the world origin. |
| `b2kSetGravity gx, gy` | Change gravity (pixels-down is positive). |
| `b2kSetSubsteps n` | Solver sub-steps per step (≈ 4). |
| `b2kContactTarget obj` | Object that receives `on b2kContact` / `on b2kEndContact` messages. |
| `b2kFrameTarget obj` | Object that receives an `on b2kFrame` message once per simulated frame. |
| `b2kEnableSleeping flag` | Toggle island sleeping (saves CPU when bodies rest). |
| `b2kEnableContinuous flag` | Toggle continuous collision (CCD) for the world. |

## Attach & spawn

Attach physics to existing controls, or spawn new ones. Pass controls by
reference (`the long id of …` is safest). Add `,true`/`,false` to force
dynamic/static where a handler takes an optional `dyn` flag.

**Any control type works** — it falls, collides, and is draggable. How it's
*drawn* to follow its body depends on the type:

| Control | Follows position | Rotates |
|---------|:---:|:---:|
| **Graphic** (box → polygon, or ball) | ✅ | ✅ |
| **Image** (dynamic) | ✅ | ✅ via `the angle` |
| **Button / field / other** | ✅ | ❌ rotation locked so the sim matches the upright render |

| Handler | Purpose |
|---------|---------|
| `b2kAddBox ctrl [,dyn]` | Treat a control as a dynamic (default) box. |
| `b2kAddBall ctrl [,dyn]` | Treat a control as a circle. |
| `b2kAddCapsule ctrl [,dyn]` | Treat a control as a capsule (pill); long side = axis, short side = diameter. |
| `b2kAddPolygon ctrl [,dyn]` | Treat a graphic's points as a convex polygon. |
| `b2kAddStatic ctrl` | Immovable body matching the control. |
| `b2kAddGround [screenY]` | Static floor (see above). |
| `b2kSpawnBox x, y, w, h [,color]` → control | Create a control *and* its box body. |
| `b2kSpawnBall x, y, diam [,color]` → control | Create a control *and* its ball body. |
| `b2kSpawnCapsule x, y, len, thick [,color]` → control | Create a pill-shaped control *and* its capsule body. |
| `b2kReshape ctrl, "box"\|"ball"\|"capsule"\|"poly"` | Rebuild a body's collision shape from the control's current size/points, on the same body (joints survive). Resets material + filter — re-apply them after. |

## Materials

| Handler | Purpose |
|---------|---------|
| `b2kSetBounce ctrl, 0..1` | Restitution. |
| `b2kSetFriction ctrl, 0..1` | Friction. |
| `b2kSetDensity ctrl, d` | Density (affects mass). |

## Body settings

| Handler | Purpose |
|---------|---------|
| `b2kSetBullet ctrl, flag` | Continuous collision for fast bodies. |
| `b2kSetFixedRotation ctrl, flag` | Stop a body from rotating. |
| `b2kSetGravityScale ctrl, s` | Per-body gravity multiplier. |
| `b2kSetDamping ctrl, lin [,ang]` | Linear (and optional angular) damping. |
| `b2kWake ctrl` | Wake a sleeping body. |
| `b2kSleep ctrl` | Send a body to sleep until something wakes it. |
| `b2kSetSleepEnabled ctrl, flag` | Allow / forbid **this body** ever sleeping (vs `b2kEnableSleeping`, which switches the whole world). The player controller forbids it on its body. |
| `b2kSetSleepThreshold ctrl, pxPerSec` | Speed below which a body may fall asleep. |
| `b2kSetStatic ctrl` / `b2kSetDynamic ctrl` / `b2kSetKinematic ctrl` | Change body type at runtime (freeze/unfreeze, moving platforms). |
| `b2kSetType ctrl, "static"\|"kinematic"\|"dynamic"` | Set body type by name. |
| `b2kDisable ctrl` / `b2kEnable ctrl` | Take a body out of / put it back into the simulation. |

## Act on bodies

| Handler | Purpose |
|---------|---------|
| `b2kPush ctrl, dvx, dvy` | Add a one-shot impulse (change in velocity, px/s). |
| `b2kForce ctrl, fx, fy` | Apply a continuous force (call each frame for thrust/wind). |
| `b2kImpulse ctrl, ix, iy` | One-shot impulse, mass-aware (heavier bodies move less). |
| `b2kTorque ctrl, torque` | Continuous turning force (call each frame); +/- sets direction. |
| `b2kAngularImpulse ctrl, imp` | One-shot turning impulse, mass-aware (the angular partner of `b2kImpulse`). |
| `b2kSetVelocity ctrl, vx, vy` | Set linear velocity (px/s). **Wakes the body** — setting a velocity means "move" (raw `b2SetVelocity` does not wake, which once froze a sleeping kinematic gate). |
| `b2kSpin ctrl, degPerSec` | Set angular velocity. |
| `b2kSpinBy ctrl, degPerSec` | Add to the current angular velocity. |
| `b2kMoveTo ctrl, x, y [,deg]` | Teleport a body. |
| `b2kExplode x, y [,radius] [,power]` | Radial impulse from a point. |
| `b2kRemove ctrl` | Destroy a body (and the control if the Kit spawned it). |

## Read state

| Handler | Returns |
|---------|---------|
| `b2kBodyOf(ctrl)` | The underlying `b2…` body handle. |
| `b2kPosition(ctrl)` | Body centre as `x,y` in screen pixels (the position partner of `b2kVelocity`). |
| `b2kWorldCenter(ctrl)` | Centre of mass as `x,y` in screen pixels (the true pivot for spin/torque). |
| `b2kVelocity(ctrl)` | `vx,vy` in px/s. |
| `b2kSpeed(ctrl)` | Scalar speed (px/s). |
| `b2kAngle(ctrl)` | Rotation in degrees. |
| `b2kMass(ctrl)` | Body mass (kg, sim units). |
| `b2kGravityScale(ctrl)` | Per-body gravity multiplier (getter for `b2kSetGravityScale`). |
| `b2kDamping(ctrl)` | Drag as `linear,angular` (getter for `b2kSetDamping`). |
| `b2kBodyType(ctrl)` | Body type as a word: `static` / `kinematic` / `dynamic`. |
| `b2kBodyCount()` | How many bodies the Kit is tracking. |
| `b2kAwakeCount()` | How many dynamic bodies are currently awake (active). |
| `b2kIsAwake(ctrl)` | Whether the body is awake. |
| `b2kSpinRate(ctrl)` | Rotation speed in degrees/sec (getter for `b2kSpin`). |
| `b2kIsBullet(ctrl)` | Whether continuous (CCD) collision is on. |
| `b2kIsEnabled(ctrl)` | Whether the body is in the simulation. |
| `b2kControlAt(x, y)` | The control whose body covers a screen point. |
| `b2kControlContains(ctrl, x, y)` | True if a screen point is inside this control's actual (rotated) collision shape. |
| `b2kRayHit(x1, y1, x2, y2)` | True if a ray hits; then read the result functions below. |
| `b2kRayHitX()` / `b2kRayHitY()` | Hit point in screen pixels. |
| `b2kRayHitNormalX()` / `b2kRayHitNormalY()` | Surface normal at the hit (screen-oriented unit vector). |
| `b2kRayDist()` | Distance in pixels from the ray start to the hit. |

## Joints

All joint constructors return a joint handle; pass it to the motor/limit/spring
helpers or to `b2kRemoveJoint`.

| Handler | Purpose |
|---------|---------|
| `b2kHinge ctrlA, ctrlB, x, y` → joint | Revolute pivot at a screen point (ctrlB empty = pin ctrlA to the world). |
| `b2kWeld ctrlA, ctrlB` → joint | Rigidly glue two controls. |
| `b2kRope ctrlA, ctrlB [,len]` → joint | Maximum-distance link. |
| `b2kSlider ctrlA, ctrlB, axisDeg` → joint | Prismatic: slide ctrlA along an axis (0 = horizontal, 90 = vertical) relative to ctrlB or the world. |
| `b2kWheel chassis, wheel, x, y [,axisDeg]` → joint | Wheel joint: sprung sliding axis + free spin (vehicle wheels). |
| `b2kRemoveJoint joint` | Remove a joint. |

**Motors, limits, springs & readouts:**

| Handler | Purpose |
|---------|---------|
| `b2kMotor joint, degPerSec [,maxTorque]` | Drive a **hinge** joint. |
| `b2kHingeLimit joint, lowerDeg, upperDeg` | Constrain a hinge's angle. |
| `b2kHingeAngle(joint)` → degrees | Current hinge angle. |
| `b2kSliderMotor joint, pxPerSec [,maxForce]` | Drive a **slider**. |
| `b2kSliderLimit joint, lowerPx, upperPx` | Constrain a slider's travel. |
| `b2kSliderPos(joint)` → pixels | Current slider translation. |
| `b2kWheelMotor joint, degPerSec [,maxTorque]` | Drive a **wheel**. |
| `b2kWheelSpring joint, hertz [,damping]` | Tune wheel suspension. |
| `b2kRopeRange joint, minPx, maxPx` | Set a distance joint's min/max length. |
| `b2kRopeLength(joint)` → pixels | Current distance-joint length. |
| `b2kRopeSetLength joint, px` | Set a distance joint's exact rest length. |
| `b2kSpring joint, hertz [,damping]` | Make a rope (distance) joint springy. |
| `b2kWeldSpring joint, hertz [,damping]` | Make a weld springy (0 hertz = rigid). |
| `b2kMotorOff joint` | Turn a hinge motor off (free swing). |
| `b2kHingeLimitOff joint` | Remove a hinge's angle limits. |
| `b2kSliderMotorOff joint` | Turn a slider motor off. |
| `b2kSliderLimitOff joint` | Remove a slider's travel limits. |
| `b2kWheelMotorOff joint` | Turn a wheel motor off. |

## Input (keyboard)

Poll-based held-key input for games: arm it once, then read state from
`on b2kFrame`. The Kit samples `the keysDown` once per frame and diffs against
the previous frame, so held keys are smooth (no OS auto-repeat artifacts), no
focus or message-path setup is needed, and pressed/released edges are exact.
Key names: `left right up down space return escape tab shift control alt
backspace delete`, single characters (`"a"`…`"z"`, digits — letters match both
shifted and unshifted), or raw keycodes.

| Handler | Purpose |
|---------|---------|
| `b2kInputOn` / `b2kInputOff` | Arm / disarm the per-frame keyboard sample. `b2kInputOn` installs starter bindings: axis `moveX` (left,a / right,d), axis `moveY` (up,w / down,s), action `jump` (space). |
| `b2kInputInject keys` / `b2kInputInjectOff` | Replace the keyboard with a **scripted** key set (friendly names or codes; empty = nothing held) until turned off. Deterministic input for the self-test harness, input replays, and cutscene "ghost" players — edges fall out of the normal frame diff exactly as with real keys. |
| `b2kKeyIsDown(key)` | Key currently held. |
| `b2kKeyPressed(key)` / `b2kKeyReleased(key)` | True only on the frame the key went down / came up. |
| `b2kKeysHeld()` | Everything held now, as friendly names (debug HUDs). |
| `b2kBindAction name, keyList` | Name a key set: `b2kBindAction "jump", "space,up,w"`. |
| `b2kActionIsDown(name)` / `b2kActionPressed(name)` / `b2kActionReleased(name)` | Action-level queries — any bound key counts; edges treat the set as one logical key. |
| `b2kBindAxis name, negKeys, posKeys` | Define a -1/0/+1 axis. |
| `b2kAxis(name)` | Read an axis; both directions held = 0. |
| `b2kKeyCodes(key)` / `b2kKeyName(code)` | The name↔keycode maps the module uses (handy for debugging). |
| `b2kFrameMS()` | Real elapsed ms folded into the last frame — drive animations and timers from this, not the step count. |

```
on openCard
   b2kQuickStart
   b2kSpawnCapsule 200, 100, 64, 30, "gold"
   put the result into gHero
   b2kSetFixedRotation gHero, true
   b2kInputOn
   b2kFrameTarget the long id of me
end openCard

on b2kFrame
   b2kSetVelocity gHero, b2kAxis("moveX") * 240, item 2 of b2kVelocity(gHero)
   if b2kActionPressed("jump") then b2kPush gHero, 0, -420
end b2kFrame
```

See `examples/box2dxt-platformer.livecodescript` for the full pattern
(grounded check, jump-cut, one-way ledge).

## Sprites & animation

Spritesheet animation on the **icon-button backend** (chosen by the Phase 0
benchmarks): a sheet registers named or numbered frame *regions* of one
hidden source image; each region is sliced into its own hidden image lazily,
on first use; a **sprite is a transparent button** whose `icon` is the
current frame — all sprites of a sheet share the same frame images. Sheets
persist until `b2kTeardown`; sprites are Kit-created controls, so `b2kClear`
removes them with everything else, and every teardown also **sweeps orphaned
sprite controls** left over from a previous session (script state resets when
a stack reopens; the controls don't — without the sweep they'd linger as
ghost sprites frozen on their last frame).

| Handler | Purpose |
|---------|---------|
| `b2kSheetLoad name, path, fw, fh [,count] [,margin] [,spacing]` → count | Register an image file as a uniform grid of `fw`×`fh` frames, numbered 1..N row-major. `margin` = outer border px, `spacing` = gap between cells (both default 0, edge-to-edge). Frame size **0 = no grid**: name regions yourself with `b2kSheetAddFrame`. |
| `b2kSheetLoadAtlas name, pngPath [,xmlPath]` → count | Register a packed atlas: PNG + `TextureAtlas` XML naming its regions (the Kenney format — see `Spritesheets/` in this repo). Frames are addressed **by name** (`"coin_gold"`). XML path defaults to the PNG path with `.xml`. |
| `b2kSheetFromImage name, imgRef, fw, fh [,count] [,margin] [,spacing]` → count | Register an image already in the stack (e.g. base64-embedded art) as a grid sheet. Same grid arguments as `b2kSheetLoad`. |
| `b2kSheetAddFrame sheet, frame, x, y, w, h` | Name one region yourself — the **no-XML path for packed sheets in any layout**: load the source with frame size 0, then add each frame by name (any size/position; redefining re-bakes). Also works on top of a grid or atlas. |
| `b2kSheetFrames(name)` / `b2kSheetHasFrame(name, frame)` / `b2kSheetFrameNames(name)` | Frame count / existence / every frame key one per line (introspect an atlas you didn't make). |
| `b2kSheetScale name, factor` | Display scale for the sheet's frames (default 1, range 0.05–8) — the engine resamples at slice time, so **any frame size displays at any sprite size**. Set it right after loading, before creating sprites or anims. |
| `b2kSheetFrameSize(name, frame)` → "w,h" | A frame's display size (region × scale) — lay out tiles and platforms from this instead of hard-coding pixels. |
| `b2kSheetPersist flag` / `b2kSheetPersists()` | **Opt-in (default off).** When on, loaded sheets are treated as assets that **survive `b2kTeardown`** (like synthesized sounds) — so a multi-LEVEL game loads its atlases **once**, not on every rebuild (re-decoding/re-parsing/re-slicing is the costliest thing the Kit does). An identical reload becomes a no-op, and because the Kit's source/frame images are named deterministically (`b2ksheet_<name>` / `b2kfr_<sheet>_<n>`), a **saved stack** carries the cache: on reopen the load adopts the in-stack images instead of importing from disk. `b2kSheetsWipe` is still the explicit purge (e.g. after the user picks a different asset folder). |
| `b2kAnimDef sheet, anim, frames, fps [,loop]` | Name an animation: `frames` is a comma list of names and/or indices, numeric ranges (`"1-8"`) expand. `loop` defaults true. |
| `b2kSpriteNew sheet [,frame, x, y]` → control | Create a sprite showing `frame` (default: the sheet's first), sized to the frame. An ordinary Kit control: give it a body (`b2kAddCapsule …`) or bind it to one. |
| `b2kSpriteFromGIF path [,x, y]` → control | An animated-GIF sprite (the engine plays it; play/stop/frame map to `repeatCount`/`currentFrame`). |
| `b2kSpritePlay spr, anim [,restart]` | Start a named animation — a no-op if already playing it, so calling it every frame from a state machine is free. |
| `b2kSpriteStop spr` / `b2kSpriteAnim(spr)` | Freeze on the current frame / what's playing. |
| `b2kSpriteSetFrame spr, frame` / `b2kSpriteFrame(spr)` | Manual frame control (stops any animation). |
| `b2kSpriteFPS spr, fps` | Per-sprite speed override (empty = each animation's own fps). |
| `b2kSpriteFlipH spr, flag` / `b2kSpriteFlipped(spr)` | Face left/right — mirrored frames are flip-cloned lazily, shared like the originals. |
| `b2kSpriteOnFinish spr, message` | When a **non-looping** animation ends, send `message spr, anim` to the frame target (attack/death/effect chains). |
| `b2kSpriteMoveTo spr, x, y` | Move any sprite/control to a **world** position, camera-correct — use this instead of `set the loc` for hand-animated paths (patrols, hovering). |
| `b2kSpriteBind spr, bodyCtrl [,dx, dy]` / `b2kSpriteUnbind spr` | Pin the sprite to another control's position each frame — the standard "art bigger than the collision shape" pattern: an invisible control owns the body, the sprite follows it. |
| `b2kSpriteRemove spr` | Remove the sprite (and its body, if it has one). |

```
b2kSheetLoadAtlas "chars", tFolder & "/spritesheet-characters-default.png"
b2kAnimDef "chars", "walk", "character_beige_walk_a,character_beige_walk_b", 6, true
b2kSpriteNew "chars", "character_beige_idle", 200, 100
put the result into tSpr
b2kSpritePlay tSpr, "walk"
b2kSpriteFlipH tSpr, true       -- face left
```

Performance notes (Phase 0 measurements, modest Win32 hardware): a frame
switch is one icon set; ~25 *moving* animated sprites ≈ 40 fps, a player plus
a handful sits at the loop ceiling. Create sprites at scene load (not
mid-play) and **before** enabling `acceleratedRendering` where possible — bulk
control creation under the compositor caused the spike's one-time stall.

## Player (the platformer controller)

A complete keyboard character controller for **one** player: a vertical
capsule with fixed rotation, sleep disabled, and low friction, steered every
frame from the Input module's axes **`moveX`**/**`moveY`** and action
**`jump`** (rebind those names to remap the controls). Horizontal motion is
velocity-driven — vx accelerates toward `axis × moveSpeed` — and grounding
comes from three short downward rays whose surface normal must point up
within `maxSlopeDeg`, so walkable slope vs wall is one comparison. The jump
feel platformers expect is built in: **coyote time** (jump shortly after
running off a ledge), **jump buffering** (press just before landing),
**jump-cut** (tap = hop, hold = full height), and a terminal fall speed.
With animations mapped, the controller drives
`b2kSpritePlay`/`b2kSpriteFlipH` itself.

**Wave 2 actions**, all built in: **duck** (DOWN while grounded brakes to a
crouch — the hitbox does *not* shrink this wave), **drop-through**
(DOWN+JUMP while standing on a one-way `b2kChain`/`b2kSmoothGround` deck
opens a `dropMs` window in which chains alone stop colliding; on solid
ground the press is simply eaten), **climb** (UP — or DOWN while airborne —
inside a `b2kPlayerAddLadder` zone parks gravity at 0 and runs y at
`climbSpeed`; JUMP exits with a normal jump), and the **hurt-knockback
standard** (`b2kPlayerHurt`, below).

**Wave 4 action: swim.** While the player's centre is inside a
`b2kPlayerAddWater` zone the controller **swims** — gravity scales down to
`swimGravity` (buoyant), the sink caps at `swimMaxFall` (well below the air
terminal), UP/DOWN drive vy at `swimSpeed`, and a JUMP press is a
*repeatable* upward **stroke** (`swimJump`) with no ground gate. State reads
`swim`; leaving the zone (or a hurt) restores the saved gravity scale
exactly once. Mutually exclusive with the climb. Sized for a *raised-bank*
basin — a sub-ground pit falls below the camera (see kit-guide §21).

**Wave 5 actions**, each **opt-in** through a knob (the defaults leave the
controller byte-for-byte as above, and every idle path is one compare per
frame): **double-jump** (`airJumps` — extra mid-air jumps, refilled on
landing), **wall-slide + wall-jump** (`wallSlideMax` caps the fall while you
press into a wall; `wallJumpX`/`wallJumpY` launch up and away with a brief
steer lock — states `wallslide` and a side ray that runs only while airborne),
**dash** (`dashSpeed` on the new `dash` action — a flat horizontal burst for
`dashMs` with gravity parked, cooldown-gated; state `dash`; yields to
climb/swim), **duck capsule reshape** (`duckScale < 1` turns the Wave 2 brake
into a real **crawl** — a feet-anchored `b2kReshape` to a shorter capsule with
a headroom check before standing), and **platform carry** (`platformCarry 1` —
a grounded player inherits the velocity of the moving kinematic body it rides;
a vertical lift's carry is exempt from the ground-snap). The marquee
showcase is the **platformer example**.

| Handler | Purpose |
|---------|---------|
| `b2kPlayerMake x, y, w, h [,sheet]` → control | One call: a capsule body host (`w`×`h` collision box — a visible capsule graphic, or invisible with a bound sprite of `sheet`'s first frame on top), controller armed, input on. Reports the player control. |
| `b2kPlayerAttach ctrl` | Adopt an existing control (or sprite) as the player. A capsule body is added if it has none (then the controller also sets low friction); a body you made yourself keeps your material. Also sets fixed rotation + sleep-off and arms input. |
| `b2kPlayerAnims idle, run, jump [,fall] [,land] [,duck] [,climb] [,hurt] [,swim] [,wall] [,dash]` | Map states to the art's animation names (`fall` defaults to `jump`; `duck` to `idle`; `climb` and `hurt` to `jump`; `swim` and `wall` to `fall`; `dash` to `run` — sheets without those frames still read correctly). `land` is an optional non-looping touch-down flourish, held for its own duration. **Map a LOOPING animation to `hurt`** if your game uses `b2kSpriteOnFinish` on the player's art — a non-looping hurt pose fires that finish message mid-knockback. The art is the player control itself if it is a sprite, else the first sprite `b2kSpriteBind`-pinned to it. |
| `b2kPlayerSet key, value` / `b2kPlayerGet(key)` | Tuning knobs (table below). Settable any time; `b2kClear` keeps them (config, like input bindings), `b2kTeardown`/`b2kPlayerRemove` wipe them. |
| `b2kPlayerOnGround()` | Grounded this frame (post-tick; false on the frame a jump launches). |
| `b2kPlayerState()` | `idle` / `run` / `jump` / `fall` / `duck` / `climb` / `hurt` / `swim` / `wallslide` / `dash`, plus `land` for exactly one frame on touch-down (dust puffs, sounds — read it in `on b2kFrame`). A drop-through renders as `fall`; a knockback's own landing shows no `land` tick. The Wave 5 states (`wallslide`, `dash`) appear only when their knobs are enabled. |
| `b2kPlayerFacing()` | 1 right / -1 left — the last horizontal intent. |
| `b2kPlayerHalfH()` / `b2kPlayerHalfW()` | The capsule's **current** half-extents in px — the half-height drops while in a reshaped duck/crawl. Read these live for head-reach logic (never bake a constant: a hitbox taller than the visible art bumps things the head never touches). |
| `b2kPlayerInLadder()` / `b2kPlayerInWater()` | This frame's ladder / water zone membership (the controller computes them every tick anyway) — for "press UP to climb" prompts, splash effects, a breath meter. |
| `b2kPlayerRespawn x, y` | Teleport to a screen-px point and reset to a clean standing idle: velocity zeroed; the jump/hurt/dash/climb/swim/drop/duck state cleared; the air and air-jump budgets refreshed. The respawn most games hand-roll (move + zero velocity + clear a pile of flags) in one call. Tuning and zones are kept. Empty `x`/`y` reset in place. |
| `b2kPlayerJump [speed]` | Programmatic jump (springs, double-jump powerups): the same launch as a pressed jump but **without** the grounded/coyote gate — the caller decides when it is allowed. |
| `b2kPlayerAddLadder x1, y1, x2, y2` | Register a ladder **zone** (screen-px rect, any corner order; purely polled — no physics object). Zones are world state: `b2kClear` wipes them with everything else. Run the zone a little above a platform at the ladder's top so walking off that edge holding DOWN grabs it. |
| `b2kPlayerAddWater x1, y1, x2, y2` | Register a water/**swim zone** (screen-px rect, any corner order; purely polled). World state, wiped by `b2kClear` like ladders. Top the zone a little above the drawn surface so the dive-in and surface-out break the water where the art is. The pool is a *raised basin* between banks (a sub-ground pit clamps below the camera). |
| `b2kPlayerHurt [fromX]` | The contact-damage knockback standard: an away-pop (`hurtPopX`/`hurtPopY`, ground-snap-exempt; the sign of `fromX` vs the player picks the direction — empty pops back off the facing), the `hurt` state/anim, input suppressed until `hurtMs` *or* the first landing after half of it (whichever is **later**), then an `invulnMs` mercy window in which this command no-ops. Keep your respawn flow for **lethal** hits (pits, kill planes): contact damage knocks back, falling dies. |
| `b2kPlayerHurtIs()` | True through the knockback *and* the mercy window — the one gate your hazard checks need. |
| `b2kPlayerControl flag` | `false` = the controller only observes (state/ground/facing stay fresh) and writes neither velocity nor animations — cutscenes, hit poses, scripted deaths. The `maxFall` clamp stays live. `true` re-asserts the state animation. An **explicit call (either way) cancels a knockback in flight** — your respawn flow takes the body over cleanly, and no mercy window is granted. |
| `b2kPlayer()` / `b2kPlayerSprite()` | The player control / the art control the controller animates. |
| `b2kPlayerRemove` | Tear down the controller (tuning included). The body and sprite remain yours — remove them with `b2kRemove` / `b2kSpriteRemove`. |

**Tuning keys** (`b2kPlayerSet`), with defaults for a 32×48 px player at
scale 40: `moveSpeed` 220 px/s · `accel` 1800 px/s² · `airAccel` 1100 px/s² ·
`jumpSpeed` 460 px/s · `jumpCut` 0.45 (velocity multiplier on early release) ·
`coyoteMs` 90 · `bufferMs` 110 · `maxFall` 900 px/s · `maxSlopeDeg` 50
(steeper than this is a wall, not ground) · `dropMs` 260 (the drop-through
window) · `climbSpeed` 160 px/s (ladder rate; x runs at half `moveSpeed`
while climbing) · `swimSpeed` 150 / `swimJump` 300 px/s (water move speed +
the repeatable stroke) · `swimGravity` 0.35 / `swimMaxFall` 150 (buoyancy:
the between-stroke sink scale and its cap — `swimJump` alone sets the escape
height, so lower IT to make climbing out harder) · `hurtPopX` 220 /
`hurtPopY` 320 px/s (knockback launch) ·
`hurtMs` 700 (control-off span) · `invulnMs` 900 (post-hurt mercy).

**Wave 5 action keys** — all **opt-in** (these defaults leave the controller
exactly as above): `airJumps` 0 (extra mid-air jumps; **1 = double-jump**,
refilled on landing) · `wallJumpX` 0 / `wallJumpY` 0 (wall-jump launch px/s,
away + up; `wallJumpX > 0` arms the **wall system**, `wallJumpY` falls back to
`jumpSpeed`) · `wallSlideMax` 0 (capped fall px/s while pressing into a wall —
the `wallslide` state) · `dashSpeed` 0 (a flat horizontal burst on the **`dash`
action**, default keys SHIFT/X; `0` = off) / `dashMs` 160 / `dashCooldownMs`
500 / `airDash` 1 (**1** = dash works mid-air too; `0` = grounded-only) ·
`duckScale` 1 (ducked capsule height ÷ standing; **< 1 reshapes to a
crawl** so the hero slips under low gaps — feet-anchored, with a headroom check
before standing) · `platformCarry` 0 (**1** = a grounded player inherits the
velocity of a moving kinematic platform it rides; costs two reads per
grounded frame, and changes how a player rides *any* kinematic body).

```
-- a playable character in four lines (after b2kQuickStart + sheet load):
b2kPlayerMake 200, 100, 32, 48, "chars"
put the result into gHero
b2kPlayerAnims "idle", "walk", "jump", "jump"
b2kCamFollow gHero
```

One player at a time: attaching a new player replaces the old controller
state (the old body/sprite stay). The platformer example adopts its own
invisible body host with `b2kPlayerAttach` — its entire movement,
ground-probe and animation code is these four calls.

**Feel guarantees** (all asserted by the self-test): the coyote/buffer
windows run on **sim time** (frame-coherent on slow machines); bodies the
controller creates get **zero restitution** and low friction (landings are
dead, walls don't glue); a touchdown is a `land` only after real airtime
(**landing hysteresis** — solver blips can't double-fire it); and a
**ground-snap** removes the solver's post-landing rebound on flat ground —
slopes are exempt via the surface normal, and *external boosts must use
`b2kPlayerJump`* (a raw upward `b2kSetVelocity` on a grounded player is
treated as solver noise and snapped).

## Camera (scrolling levels)

A clipped **viewport group** the loop scrolls (the mechanism the Phase 0
spike benchmarked). While the camera is on, Kit-created controls — spawns and
sprites — are placed *inside* the viewport, and their locs stay **world
pixels**: contents of a scrolled group keep their coordinates, so physics and
the body sync are untouched and the scroll is pure presentation. Chrome stays
on the card; anything layered *behind* the (transparent) group reads as an
infinite-distance parallax backdrop. Level coordinates should start at 0,0.

| Handler | Purpose |
|---------|---------|
| `b2kCamOn [rect]` | Create the viewport (default: the card rect). Do this *before* building the level, after any static backdrop. |
| `b2kCamOff` | Dissolve the viewport — children return to the card with their world locs. Called automatically by `b2kTeardown`. |
| `b2kCamIsOn()` / `b2kCamGroup()` | State / the group's ref — build your own level controls inside it: `create graphic "x" in b2kCamGroup()`. |
| `b2kCamAdopt ctrl` | Move an existing control (IDE-designed levels, fallback shapes) into the viewport. |
| `b2kCamFollow ctrl [,lerp]` / `b2kCamUnfollow` | Track a control; `lerp` 0.01–1 smooths (default 0.15). |
| `b2kCamDeadzone w, h` | Chase only once the target leaves a centre box (0 = always centre). |
| `b2kCamBounds x1, y1, x2, y2` | Clamp the view to the level. |
| `b2kCamGoto x, y` / `b2kCamPos()` | Cut to a world point / read the view centre. |
| `b2kCamShake ampPx, ms` | A decaying random view offset (impacts, blasts). |
| `b2kCamStatus()` | Empty = healthy; otherwise why the camera degraded (group/scroll failures). Check it after `b2kCamOn` and fall back gracefully. |
| `b2kCamLocSemantics()` | `"visual"` or `"content"` — which grouped-loc coordinate model the startup probe detected. Diagnostic; the Kit compensates automatically. |
| `b2kCamMouseX()` / `b2kCamMouseY()` | The mouse in **world** pixels — use for `b2kGrab`, click-picking, spawning at the pointer. (The Kit's own drag already uses them.) |

```
b2kCamOn
b2kCamBounds 0, 0, 3072, 640
b2kCamDeadzone 140, 600
b2kCamFollow gHero, 0.18
-- in mouseDown:  get b2kGrab(b2kCamMouseX(), b2kCamMouseY())
```

The platformer example is a complete scrolling level on this module.

## Sound (SFX — with or without asset files)

Named sounds over **audioClips** — the one LiveCode sound path with no
external media-layer dependency. The engine plays **one clip at a time** (a
new play cuts the previous); that's the classic LC limit, and short retro
SFX suit it. `b2kToneMake` **synthesizes** a clip in pure script (8-bit mono
WAV, square or sine, a comma list of note frequencies with a per-note
decay), so a self-contained stack ships sound with zero files. Sounds are
assets like sheets: `b2kTeardown` wipes them (names are stable, so
re-making replaces rather than accumulates). Failures degrade to *silence*,
never errors — the first play that throws trips a dead-flag.

| Handler | Purpose |
|---------|---------|
| `b2kSoundLoad name, path` | Import a WAV/AIFF/AU file as a named sound (replaces any same name). |
| `b2kToneMake name, freqs, msPerNote [,vol] [,shape]` | Synthesize a sound: `freqs` like `"1319,1760"` (Hz; 0 = a rest), `vol` 0–100 (default 60), `shape` `"square"` (default, retro) or `"sine"` (soft). ~22 KB per second — keep SFX short. |
| `b2kSound name` | Play (cuts whatever is playing). Stale-safe: unknown names and dead audio no-op. |
| `b2kSoundLoop name` / `b2kSoundStop` | Loop ambience until stopped / stop the current sound. |
| `b2kSoundMute flag` / `b2kSoundMuted()` | Swallow play calls — a user preference that survives `b2kTeardown`. |
| `b2kSoundVolume pct` | The engine-**global** `playLoudness` (0–100) — it affects every stack's audio, so expose it, don't hardcode it. |
| `b2kSoundIsLoaded(name)` / `b2kSoundStatus()` | Loaded check / empty = healthy, else the most recent reason audio degraded. |

```
b2kToneMake "coin", "1319,1760", 36          -- a two-note blip
b2kToneMake "win", "523,659,784,1047", 110   -- a little fanfare
-- in your coin handler:  b2kSound "coin"
```

The platformer's eight cues (jump, land, coin, stomp, hurt, checkpoint,
gate, win) are all synthesized — no asset folder involved.

## Drag & events

| Handler | Purpose |
|---------|---------|
| `b2kGrab(x, y)` → control | Grab the body under a point (mouse joint). Returns the grabbed control, or empty. |
| `b2kRelease` | Release a grabbed body. |
| `on b2kContact pCtrlA, pCtrlB` | Sent to your `b2kContactTarget` when two attached controls **begin** touching. Long ids are empty for walls/ground. |
| `on b2kEndContact pCtrlA, pCtrlB` | Sent when two attached controls **stop** touching. |
| `on b2kFrame` | Sent to your `b2kFrameTarget` once per simulated frame (after bodies sync) — use it for motors, input, and custom drawing. |
| `on b2kFell pCtrl` | Sent to your `b2kFrameTarget` just before the Kit removes a body that crossed the `b2kKillFloor` line. |

> **Frame-exact events:** contact and sensor events are harvested after
> **every** fixed step and buffered for the frame — a frame that ran two
> physics steps loses nothing, and a frame that ran zero repeats nothing. The
> messages and the polling accessors below both read the same frame buffer.

**Polling contacts** — instead of (or alongside) the messages above, read this
frame's touch pairs directly, e.g. from `on b2kFrame`. Indices are 1-based; each
accessor returns a control (empty for a wall, the ground, or any untracked body).

| Handler | Returns |
|---------|---------|
| `b2kContactCount()` | How many pairs **began** touching this frame. |
| `b2kContactA(i)` / `b2kContactB(i)` | The two controls of the *i*-th begin-touch pair. |
| `b2kEndContactCount()` | How many pairs **stopped** touching this frame. |
| `b2kEndContactA(i)` / `b2kEndContactB(i)` | The two controls of the *i*-th end-touch pair. |

## Sensors (trigger zones)

> **One-shots vs. presence:** sensor enter/exit messages are ideal for
> **one-shot** triggers (coins, checkpoints, goals — consumed or guarded on
> first fire). For **presence** state that must stay true while something sits
> there (pressure plates, buttons, zones), poll **`b2kOverlapMoving`** of the
> region each frame instead of counting enters minus exits: a poll is stateless
> (it cannot drift), it still sees **sleeping** bodies — a crate that settles
> and sleeps keeps holding the plate — and the Moving variant filters out the
> floor the pad sits on (the broadphase's fattened boxes would otherwise report
> it forever). The platformer's plate works this way, with a ~0.2 s release
> debounce for feel.

Non-solid fixtures that report overlaps but never block. The Kit enables sensor
events on every body it creates, so sensors detect them automatically.

| Handler | Purpose |
|---------|---------|
| `b2kAddSensor ctrl [,shape]` → body | Attach a static sensor (`shape` = `box`/`ball`/`capsule`). |
| `b2kSetSensor ctrl, flag` | Flip an existing body between solid and sensor (rebuilds the shape, keeping the new sensor state). |
| `on b2kSensorEnter pSensorCtrl, pVisitorCtrl` | Sent to your `b2kContactTarget` when a body enters a sensor. |
| `on b2kSensorExit pSensorCtrl, pVisitorCtrl` | Sent when it leaves. |
| `b2kSensorCount()` / `b2kSensorEnterSensor(i)` / `b2kSensorEnterVisitor(i)` | Poll this frame's enters (1-based). |
| `b2kSensorExitCount()` / `b2kSensorExitSensor(i)` / `b2kSensorExitVisitor(i)` | Poll this frame's leaves (1-based). |

## Collision filtering (named layers)

Up to **31 nameable layers** (bits 2⁰–2³⁰; the top bit 2³¹ is the Kit's
reserved **`oneway`** chain layer — usable by name in any list, never handed
out by `b2kDefineLayer`). Two shapes collide only if **each** one's category
is in the other's mask (and no shared negative group forbids it).

| Handler | Purpose |
|---------|---------|
| `b2kDefineLayer name` → bit | Define/fetch a named layer. |
| `b2kLayerBits(list)` → bits | Turn a comma/space layer-name list into a raw category/mask bitmask. |
| `b2kSetCategory ctrl, layers` | Set which layer(s) a control *is* (comma/space list of names or numbers). |
| `b2kSetMask ctrl, layers` | Set which layer(s) it collides *with*. The reserved `oneway` bit is **included automatically** — a custom-masked body still stands on `b2kChain` terrain (object rules shouldn't silently mean "fall through the ground"). To genuinely pass through chains, use the raw `b2SetShapeFilter`. |
| `b2kSetCollisionGroup ctrl, n` | Negative = never collide with same group; positive = always. |
| `b2kNoCollide ctrlA, ctrlB` → joint | Stop just these two from colliding (a filter joint). |

## Chains & terrain

| Handler | Purpose |
|---------|---------|
| `b2kChain pointList [,loop]` → chain | Smooth static terrain from a list of `x,y` screen points (≥ 4). No inner corners for fast bodies to catch on. Invisible — draw a matching graphic. |
| `b2kSmoothGround pointList` → chain | An open chain (alias for `b2kChain …, false`). |
| `b2kAddChain ctrl, pointList [,loop]` | A smooth chain that **tracks a control** (move/draw the terrain as one graphic). Points are the control's own outline. |

> **One-way chains (Wave 2):** every `b2kChain`/`b2kSmoothGround` chain
> carries the Kit's reserved **`oneway`** collision category (bit 2³¹) with
> an all-bits mask, so nothing collides any differently by default — but the
> player's **drop-through** (DOWN+JUMP while standing on one) can mask out
> chains *alone* for a `dropMs` window. `b2kAddChain` outlines are **solid
> terrain** and are *not* tagged. Don't park a solid platform less than a
> player-height under a one-way deck — a drop that can't clear the deck is
> restored by a hard deadline and may pop back on top.

> **Winding:** a chain's solid side is to the *right* of the point-travel
> direction. For ground you stand on, list the top surface **right-to-left** so
> the solid side faces up. (Bodies falling through *everywhere*? Reverse the
> point order.)

> **The ghost rule (open chains):** Box2D treats an open chain's **first and
> last segments as ghost anchors — they don't collide** (N points ⇒ N−3 solid
> segments). Run the chain **one segment past** the surface you need on each
> side; over solid ground the tails can simply continue flat. Endpoints placed
> *at* a platform's edges leave its ends intangible — bodies fall through the
> outer tiles. (Bodies falling through *near the ends*? This, not winding.)

## Region & ray queries

| Handler | Returns |
|---------|---------|
| `b2kOverlap x1, y1, x2, y2` | Newline list of controls whose body overlaps a screen rect. **Broadphase boxes are fattened** (~0.1 m ≈ a few px), so a region touching the floor reports the floor — use the Moving variant for presence. |
| `b2kOverlapMoving x1, y1, x2, y2` | The same query with **static bodies filtered out** — the presence poll for pressure plates and buttons ("is some *thing* on me?"). Dynamic and kinematic count; sleeping bodies still register. |
| `b2kOverlapCircle x, y, r` | …overlapping a screen circle. |
| `b2kRayHitAll x1, y1, x2, y2` | Every control a ray crosses, nearest-first (vs `b2kRayHit`'s single closest). |

## Motors & tuning

| Handler | Purpose |
|---------|---------|
| `b2kMotorTo mover, ref, dxPx, dyPx, deg [,maxF, maxT]` → joint | Drive `mover` toward a pose offset from `ref` (a moving anchor; empty = world). |
| `b2kExplode x, y [,radius] [,power]` | Native radial blast (shape-aware, affects all dynamic bodies). `b2kExplodeLegacy` keeps the old velocity-based feel. |
| `b2kSetRestitutionThreshold px/s` · `b2kSetContactTuning hz, damp, pushPx` · `b2kSetJointTuning hz, damp` · `b2kSetMaxSpeed px/s` · `b2kEnableWarmStarting flag` | World solver tuning. |
| `b2kProfile()` | `"totalStep,collide,solve"` ms for the last step (a perf HUD). |
| `b2kAwakeBodyCount()` | Awake dynamic bodies (native count). |

## Tips

- Keep moving objects a sensible on-screen size (default scale 40 px/m, so
  roughly **4–400 px**).
- Graphic boxes/polygons and **dynamic images rotate** with their body (images
  via `the angle`). Buttons, fields, and other controls follow position only and
  have their rotation locked, so the simulation stays consistent with the
  upright render.
- The Kit render loop uses Box2D body-move events, so it only considers bodies
  that moved in the latest step, avoids per-body awake/position polling for
  sleeping objects, and skips redraws when the rounded screen pixel/angle did
  not change.
- When you need something the Kit doesn't expose, drop to the
  [core `b2…` API](api-reference.md): `b2kWorld()` returns the world and
  `b2kBodyOf(control)` the body, and `b2kToWorldX/Y(px)` / `b2kToScreenX/Y(m)`
  convert between screen pixels and Box2D metres — so you can mix both layers.
