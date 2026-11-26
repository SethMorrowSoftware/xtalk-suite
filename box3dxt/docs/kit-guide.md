# The Box3Dxt Kit: a guide

The Kit (`src/box3dxt-kit.livecodescript`) is a pure-script toolkit for making
3D games in OpenXTalk with the box3dxt extension. It is the 3D sibling of
box2dxt's b2k Kit: you work in **metres and degrees with y pointing up**, and
the Kit runs the world, draws it into one image, moves the camera, reads the
keyboard, walks a player about and tells your script when things touch.

This page teaches it from an empty stack to a game. Every handler has an entry
in [kit-reference.md](kit-reference.md), written from the same doc blocks the
dictionary reads; keep that open beside this. The raw binding underneath is in
[api-reference.md](api-reference.md), and [getting-started.md](getting-started.md)
explains Box3D's units and limits.

**Contents**

1. [What you need](#1-what-you-need)
2. [Your first scene](#2-your-first-scene)
3. [How the Kit thinks](#3-how-the-kit-thinks)
4. [Making things](#4-making-things)
5. [Scenery](#5-scenery)
6. [Looks and materials](#6-looks-and-materials)
7. [Moving things](#7-moving-things)
8. [Reading things](#8-reading-things)
9. [The camera](#9-the-camera)
10. [The mouse: picking and rays](#10-the-mouse-picking-and-rays)
11. [The keyboard](#11-the-keyboard)
12. [The player](#12-the-player)
13. [Messages: frames, touches, sensors, falls](#13-messages-frames-touches-sensors-falls)
14. [Joints](#14-joints)
15. [Two renderers](#15-two-renderers)
16. [Speed](#16-speed)
17. [The raw API underneath](#17-the-raw-api-underneath)
18. [The example game: Orb Island](#18-the-example-game-orb-island)
19. [Things worth knowing](#19-things-worth-knowing)

---

## 1. What you need

- **The box3dxt extension, loaded.** `b3kHasPhysics()` is true when it is.
  Without it nothing can be made, and `b3kLastError()` says so.
- **render3dxt, if you have it.** It is optional. With it the picture is
  textured, lit and smooth-edged; without it box3dxt draws the picture itself
  in solid colours. `b3kHasRender3d()` says which you have. Your game code is
  the same either way (section 15).
- **The Kit itself.** Use it one of two ways:
  1. **Paste it into your stack's script.** Put your own handlers above it or
     below it; they call the Kit by name. This is how the example game is
     made, and it keeps a game as one file you can hand to anyone.
  2. **Keep it in a stack of its own and `start using` it.** Several games can
     then share one copy.

  Either way the Kit's messages reach your card (section 13).

If the box3dxt and render3dxt library files (`.dll`, `.dylib` or `.so`) sit
in the same folder as your saved stack, `b3kEnsureNativeLib` points the engine
at them, so the extension finds its library without an install. `b3kSetup`
calls it for you.

## 2. Your first scene

Put this in a card script (with the Kit in the stack script) and go to the
card:

```
on openCard
   b3kQuickStart
   b3kSpawnBox 0, 4, 0, 1, 1, 1, "orange"
   b3kSpawnBall 0.3, 7, 0.2, 1, "blue"
end openCard

on closeCard
   b3kTeardown
end closeCard
```

`b3kQuickStart` does five things: it makes a world with gravity
(`b3kSetup`), makes an image that fills the card to draw into
(`b3kViewMake`), lays a 30 metre checkered ground (`b3kAddGround`), points
the camera at the middle, and starts the loop (`b3kStart`). The box and the
ball then fall, land and tumble.

When you want the parts separately, the same scene is:

```
on openCard
   b3kSetup
   b3kViewMake 0, 40, 640, 400
   b3kAddGround 30
   b3kCamOrbit 30, 25, 16, 0, 0, 0
   b3kStart
end openCard
```

`b3kTeardown` stops the loop and frees the world, every thing in it and
everything the renderer made for them. Call it before the card goes, so
nothing keeps running behind a card nobody can see.

**If nothing happens,** ask the Kit why:

```
b3kSetup
if b3kLastError() is not empty then answer b3kLastError()
```

## 3. How the Kit thinks

### Metres, degrees, y up

- Lengths are **metres**, times are **seconds** (or milliseconds where a
  handler says so), angles are **degrees** and weights are **kilograms**.
- **y points up.** The ground's top is at y = 0 unless you say otherwise.
  Seen from the +z side (camera yaw 0, section 9), x runs to the right and
  z comes towards you.
- **A position is a centre.** `b3kSpawnBox 0, 4, 0, 1, 1, 1` makes a
  1 metre box whose centre is 4 metres up.
- **Keep moving things between about 0.1 and 10 metres.** Box3D is tuned for
  that range: a 1 cm pebble or a 200 m boulder behaves badly.
- **Colours** are a name (`"orange"`), `"r,g,b"` (`"240,172,64"`) or
  `"#rrggbb"`. Leave a colour empty and the Kit hands out the next colour of
  its palette.

### Things

Everything the Kit makes is a **thing**: one body with one shape, and its
picture. A thing is its body's handle, a positive whole number, so you keep
it in a variable and pass it back:

```
b3kSpawnBall 0, 6, 0, 0.8, "red"
put the result into tBall
b3kPush tBall, 0, 5, 0
```

Commands that make something report it through **the result**: read it on
the very next line, because the next command replaces it. Functions answer
directly.

A thing that is gone (removed, fallen off the world, or from before
`b3kTeardown`) is ignored by every Kit call, so a stale handle is harmless.
`b3kIsThing(tBall)` tells you whether it is still there; `b3kKind(tBall)`
says what it is.

### The loop

`b3kStart` runs a loop that steps the world at a fixed sixtieth of a second,
whatever the frame rate. Each frame it:

1. samples the keys held (when input is on, section 11),
2. steers the player (section 12),
3. runs as many 1/60 s physics steps as the time since the last frame needs,
   at most four (a longer stall is forgiven, not caught up),
4. delivers the touch and sensor messages of those steps,
5. sends `b3kFrame` to your script,
6. draws the picture, if anything moved.

So a frame can run zero, one or several physics steps. Drive game timers from
`b3kFrameMS()`, the real time the last frame covered, never from a count of
frames:

```
on b3kFrame
   add b3kFrameMS() to sClock
end b3kFrame
```

`b3kPause` freezes the world but keeps the loop: no physics step runs and no
`b3kFrame` is sent, but the camera still answers the mouse. `b3kResume`
carries on. `b3kStop` stops the loop altogether; `b3kStart` starts it again.
`b3kStepOnce` runs exactly one frame of one step, paused or not, for a Step
button or a test.

A frame runs inside one `try`, so an error in your `b3kFrame` handler can
never leave the screen locked. The error is kept for you in `b3kFrameError()`
instead of being lost.

## 4. Making things

Things that fall and tumble (all take an optional colour last):

| Call | Makes |
|---|---|
| `b3kSpawnBox x, y, z, w, h, d` | a box, w along x, h along y, d along z |
| `b3kSpawnBall x, y, z, diam` | a ball |
| `b3kSpawnCapsule x, y, z, len, diam` | a pill standing along y |
| `b3kSpawnCylinder x, y, z, h, diam` | a cylinder standing along y |
| `b3kSpawnCone x, y, z, h, diam` | a cone on its base |
| `b3kSpawnHull x, y, z, points` | the tightest solid round some points |
| `b3kSpawnModel x, y, z, source, scale` | a 3D model, from an OBJ file or its text |

Every size has a default (1 metre for most), so `b3kSpawnBox 0, 5, 0` is a
1 metre cube. Things start with a density of 1, so a 1 metre box weighs one
kilogram; `b3kSetDensity` changes that.

**Models** come from Wavefront OBJ, the format every modelling program writes:
pass the full path of a `.obj` file or the OBJ text itself. A moving model
collides as the convex hull of its points (a moving body cannot be hollow).
render3dxt draws the model itself, with its own materials and textures;
box3dxt's renderer draws the hull.

```
b3kSpawnModel 0, 3, 0, specialFolderPath("resources") & "/models/rock.obj", 0.5
put the result into tRock
```

**Names** save you keeping every handle:

```
b3kName tDoor, "door"
-- later, anywhere
b3kRemove b3kThingNamed("door")
```

`b3kThings()` lists every thing, oldest first, and `b3kThingCount()` counts
them. `b3kClear` removes them all but keeps the world, the camera, the view
and the loop: a new level in the same world.

## 5. Scenery

Scenery never falls. It is what your things stand on and bump into.

```
b3kAddGround 40                          -- a 40 m checkered floor at y = 0
b3kAddWalls 1.5                          -- a fence round it, 1.5 m high
b3kAddStaticBox 0, 0.5, -4, 6, 1, 1      -- a low wall
b3kAddRamp 0, 1, 0, 3, 0.3, 6, 20        -- 3 m wide, 6 m long, tipped 20 degrees
b3kAddStaticModel 0, 0, 0, tFolder & "/castle.obj"
```

- There is **one ground**: a second `b3kAddGround` replaces the first.
- A **ramp**'s tilt raises its far (-z) end; an optional yaw after the tilt
  turns the whole ramp round the vertical afterwards.
- A **static model** collides as its own triangles, so an arch can be walked
  through and a bowl holds a ball. A triangle stops what meets its front (its
  corners counter-clockwise as you look at it), which is how modelling
  programs write them.

### Moving platforms

A platform is a box that moves only as it is told, and carries what stands
on it:

```
b3kAddPlatform 0, 1, 0, 3, 0.4, 3
put the result into tLift
b3kGlideTo tLift, 0, 4, 0, 2             -- up to y = 4 in two seconds
```

`b3kGlideTo` gives the platform the speed that brings it there in time and
stops it exactly there; `b3kIsGliding(tLift)` is true until it arrives. A
lift that rises and falls for ever is two lines of your `b3kFrame` handler:

```
if not b3kIsGliding(tLift) and b3kY(tLift) < 2 then b3kGlideTo tLift, 0, 4, 0, 2
if not b3kIsGliding(tLift) and b3kY(tLift) >= 2 then b3kGlideTo tLift, 0, 1, 0, 2
```

### Falling off the world

`b3kKillFloor -6` removes every moving thing whose centre drops below
y = -6, and tells your script first with `b3kFell` (section 13). The player
is reported but never removed: your game decides where it starts again.

## 6. Looks and materials

```
b3kSetColor tCrate, "red"
b3kSetChecker tBall, "white", "red", 8   -- render3dxt only
b3kSetTexture tCrate, specialFolderPath("resources") & "/crate.png"   -- render3dxt only
b3kSetVisible tZone, false               -- hide the picture; it still collides
```

`b3kColor(tCrate)` reads a colour back and `b3kIsVisible(tZone)` whether a
picture shows. What box3dxt's renderer cannot show, it skips: a checker or a
texture keeps the thing's colour there (section 15).

**Glow and lamps** (render3dxt only):

```
b3kSetGlow tOrb, "160,110,0"                 -- shines in the shade too
b3kAddLamp 0, 2.5, 0, "255,200,120", 6       -- a warm lamp, 6 m of light
put the result into tLamp
b3kMoveLamp tLamp, 1, 2.5, 0
b3kRemoveLamp tLamp
b3kSetLight -0.8, -0.5, -0.3, "255,196,140"  -- a low evening sun
```

A glow is added to a thing's own colour whatever the lights do; it lights
the thing, not what is near it. A lamp lights what is within its range, more
the nearer it is. Lighting is worked out at the corners of each shape, so a
lamp shows best on rounded things and small boxes; a big flat box whose
corners are all out of range is not lit by it. A world holds seven lamps
beside the sun; `b3kLamps()` lists them, and they go with `b3kClear` and
`b3kTeardown`. The sun's colour (the fourth argument of `b3kSetLight`) starts
a warm white.

**A model's look** (render3dxt only): `b3kSetLook` draws a 3D model (OBJ
text, or a file's path) in place of a thing's shape. The thing still
collides, falls and is picked as its shape, so a box can look like a carved
platform and a capsule like a character:

```
b3kSetLook b3kPlayer(), tHeroObj, tHeroMtl    -- the OBJ text and its .mtl text
b3kSetLook b3kPlayer(), empty                 -- the capsule again
```

The model's origin sits at the thing's centre and turns with it, so fit the
model to the shape before (Orb Island's `tools/build-game-models.py` does
this). With OBJ text, give the material text too, or the model is white; it
keeps its own colours, and a colour, checker or glow set on the thing shows
again when the look comes off. Things wearing the same model share one copy
of it. box3dxt's renderer keeps drawing the shape.

**A look in parts, and poses.** A character whose arms and legs move is
several models, one a part: `b3kAddLookPart` adds one by name (an empty
model takes it away), and `b3kPoseLookPart` sets where it sits and how it
turns and scales, in the thing's own space, so the parts go wherever the
thing goes. `b3kSetLookPose` poses the whole look on top, which is how a
character squashes as it lands or leans into a run, and how a thing can bob
without moving its body:

```
b3kAddLookPart b3kPlayer(), "arm-left", tArmObj, tArmMtl
b3kPoseLookPart b3kPlayer(), "arm-left", -0.3, 0.9, 0, 40, 0, 0  -- x,y,z, then degrees about x,y,z
b3kSetLookPose b3kPlayer(), 0, -0.1, 0, 0, 0, 0, 1.1, 0.85, 1.1  -- squashed
```

Turns are taken about x, then y, then z, and a pose may end with three
scales. Play an animation by posing the parts each frame from its frames
(Orb Island's `oiAnimPose` reads Kenney's idle, walk and jump that way).

Materials decide how things feel:

| Call | Range | Starts at |
|---|---|---|
| `b3kSetBounce thing, value` | 0 (a thud) to 1 (bounces back as high) | 0.1 (a ball 0.25) |
| `b3kSetFriction thing, value` | 0 (ice) and up | 0.6, ordinary |
| `b3kSetDensity thing, value` | kilograms per cubic metre | 1 |

Body settings change how a thing moves at all:

- `b3kSetType thing, "static"` freezes it where it is; `"kinematic"` moves
  only as told (like a platform); `"dynamic"` falls and collides.
  `b3kType(thing)` reads it.
- `b3kSetGravityScale tBalloon, -0.2` makes one thing float upwards.
- `b3kSetDamping tFeather, 2` slows it as if through air or water.
- `b3kSetBullet tShot, true` makes a fast thing check every step for what it
  might pass through.
- `b3kKeepUpright tSnowman, true` lets it move but never tip over.
- `b3kDisable tDoor` takes it out of the world for now (no collisions, no
  picture); `b3kEnable tDoor` puts it back where it was.
- Things at rest fall asleep to save time and wake when touched;
  `b3kWake tCrate` wakes one yourself.

## 7. Moving things

| Call | What it does |
|---|---|
| `b3kPush thing, dvx, dvy, dvz` | changes its speed at once, whatever it weighs: the kick that suits any size |
| `b3kImpulse thing, ix, iy, iz` | kicks it at its centre; a heavy thing moves less |
| `b3kForce thing, fx, fy, fz` | pushes steadily: call it every frame it should act |
| `b3kTorque thing, tx, ty, tz` | twists steadily, every frame |
| `b3kSetVelocity thing, vx, vy, vz` | sets its speed and direction |
| `b3kSetSpin thing, wx, wy, wz` | sets how fast it turns, in degrees a second |
| `b3kMoveTo thing, x, y, z` | teleports it there, at rest |
| `b3kSetRotation thing, rx, ry, rz` | turns it to three angles |
| `b3kTurnTo thing, yaw` | turns it upright to face a heading (0 faces +z, 90 faces +x) |
| `b3kExplode x, y, z, radius, power` | blows things away from a point |
| `b3kRemove thing` | removes it, with its joints |

```
-- in your b3kFrame handler: a rocket while space is held
if b3kKeyIsDown("space") then b3kForce tRocket, 0, 30, 0
```

Two cautions. Setting a velocity wakes a thing, so never set the velocity of
something meant to rest every frame. And `b3kMoveTo` is a teleport: to move a
platform so that it carries things, glide it (section 5).

## 8. Reading things

| Call | Answers |
|---|---|
| `b3kPosition(thing)` | `"x,y,z"` of its centre; `b3kX`, `b3kY`, `b3kZ` give one each |
| `b3kVelocity(thing)` | `"vx,vy,vz"` in metres a second |
| `b3kSpeed(thing)` | metres a second |
| `b3kRotation(thing)` | `"rx,ry,rz"`, the angles `b3kSetRotation` takes |
| `b3kYaw(thing)` | the heading it faces |
| `b3kMass(thing)` | kilograms (0 for a static thing) |
| `b3kIsAwake(thing)` | whether it is moving, or able to |
| `b3kKind(thing)` | box, ball, capsule, cylinder, cone, hull, model, ground, static, ramp, scenery, platform or sensor |
| `b3kDistance(a, b)` | metres between two centres |
| `b3kNameOf(thing)` | its name, if it has one |

```
if b3kDistance(b3kPlayer(), tExit) < 1.5 then put "home" into sState
```

## 9. The camera

The camera **orbits a point**: it looks at a target from a yaw (degrees round
the vertical), a pitch (degrees above the horizon) and a distance. It starts
at yaw 30, pitch 25, 16 metres from the middle of the world, with a 50 degree
lens.

```
b3kCamOrbit 45, 30, 20, 0, 0, 0          -- yaw, pitch, distance, then the point
b3kCamOrbitBy 2, 0                       -- turn a little (in b3kFrame: a slow spin)
b3kCamZoom 8                             -- 8 metres away
b3kCamZoomBy 0.9                         -- a little nearer
b3kCamSetFov 70                          -- a wider lens
b3kCamLookAt 0, 12, 18, 0, 0, 0          -- or place it by an eye and a target
```

Yaw 0 looks along -z from the +z side. Whichever way you place it, the Kit
keeps it as an orbit, so the next `b3kCamOrbitBy` carries on from there.
`b3kCamYaw()`, `b3kCamPitch()`, `b3kCamDistance()`, `b3kCamEye()` and
`b3kCamTarget()` read it back, and `b3kCamText()` gives it as the seven
numbers both renderers take.

**Following.** `b3kCamFollow tHero` keeps the camera's point on a thing as it
moves, easing after it each frame. The orbit stays yours, so the player can
still turn the view. `b3kCamUnfollow` lets go. `b3kPlayerMake` follows the
player for you.

**Shaking.** `b3kCamShake 0.2, 250` jolts the eye by up to 0.2 metres for a
quarter of a second: a thump, a landing, an explosion.

**Turning with the mouse.** `b3kCamMouseOrbit true` lets a drag on the view
turn the camera (sideways) and tilt it (up and down). A click that did not
move is still yours; section 10 shows how to tell the two apart.

## 10. The mouse: picking and rays

The view is an ordinary image (named `b3kView` when `b3kViewMake` made it),
so it gets `mouseUp` like any control. The Kit turns a point of the card
into the world:

| Call | Answers |
|---|---|
| `b3kThingAt(h, v)` | the thing under that point of the card, or empty |
| `b3kPointAt(h, v)` | `"x,y,z"` where the camera's ray first meets something |
| `b3kGroundPoint(h, v, y)` | where that ray meets a flat level (y = 0 when empty), with or without a body there |
| `b3kProject(x, y, z)` | where a point of the world appears on the card, `"h,v"` |

`b3kThingAt` casts a ray through the world, so it needs no picture and works
with either renderer; the ground counts as a thing, and sensors are not seen.
After it, `b3kHitPoint()`, `b3kHitNormal()` and `b3kHitDistance()` say where
it struck.

When a drag turns the camera, a press that moved is not a click. Ask
`b3kCamDragged()`:

```
on mouseUp
   if the short name of the target is not "b3kView" then pass mouseUp
   if b3kCamDragged() then exit mouseUp      -- that was the camera turning
   get b3kThingAt(the mouseH, the mouseV)
   if it is not empty then b3kPush it, 0, 6, 0
end mouseUp
```

`b3kProject` goes the other way: it puts a label over a thing.

```
set the loc of field "Label" to b3kProject(b3kX(tCrate), b3kY(tCrate) + 1, b3kZ(tCrate))
```

Rays and regions without the mouse:

```
-- is there ground within 2 m under the crate?
put b3kRayHit(b3kX(tCrate), b3kY(tCrate), b3kZ(tCrate), 0, -2, 0) into tBelow
-- everything within 3 m of a point
put b3kOverlapSphere(0, 1, 0, 3) into tNear
```

A ray's last three numbers are its whole travel, how far as well as which
way, not just a direction.

## 11. The keyboard

`b3kInputOn` starts reading the keyboard once a frame. It needs no focus and
no `keyDown` handlers: the loop compares the keys held with the frame before,
so in `b3kFrame` you can ask:

```
if b3kKeyIsDown("shift") then b3kPlayerSet "moveSpeed", 9
if b3kKeyPressed("r") then b3kPlayerRespawn 0, 2, 0
```

`b3kKeyIsDown` is true while a key is held, `b3kKeyPressed` only on the frame
it went down, `b3kKeyReleased` only on the frame it came up. Keys are named
(`left`, `right`, `up`, `down`, `space`, `return`, `escape`, `tab`, `shift`,
`control`, `alt`, `backspace`, `delete`), a single character, or a key code.
`b3kKeysHeld()` lists what is held, which helps when you are not sure of a
name.

**Actions and axes** let a game name what keys mean instead of which keys
they are:

```
b3kBindAction "fire", "x,control"            -- any of these keys fires
if b3kActionPressed("fire") then b3kPush tShot, 0, 0, -20
b3kBindAxis "aim", "a", "d"                  -- -1, 0 or +1
b3kSetSpin tTurret, 0, b3kAxis("aim") * 90, 0
```

`b3kActionIsDown`, `b3kActionPressed` and `b3kActionReleased` ask about an
action the way the key questions ask about a key.

`b3kInputOn` also fills the bindings you have not made: action `jump` (space),
axes `moveX` (left or a, right or d), `moveY` (down or s, up or w) and `turn`
(q, e), which turns the camera. Rebind any of them with `b3kBindAction` or
`b3kBindAxis` to change the keys. `b3kInputOff` stops reading, and
`b3kInputIsOn()` says whether it is on.

**Pretend keys.** `b3kInputInject "up,space"` makes each frame read those keys
instead of the keyboard, until `b3kInputInjectOff`. It is how a test, a replay
or a demo drives a game.

## 12. The player

One call makes a character the keys walk about:

```
b3kQuickStart
b3kPlayerMake 0, 1, 0                        -- a capsule, 1.6 m tall
put the result into tHero
```

Arrows or WASD walk it, **forward is away from the camera**, space jumps, and
Q and E turn the camera. The camera follows it. After the place,
`b3kPlayerMake` takes a kind, `"capsule"` (the default), `"ball"` (it rolls)
or `"box"`, and then a colour.

To make a thing you already have into the player, use `b3kPlayerAttach`:

```
b3kSpawnCylinder 0, 1, 0, 1.2, 0.8, "gold"
put the result into tRobot
b3kPlayerAttach tRobot                       -- walks upright; a ball rolls
```

There is one player at a time; `b3kPlayer()` is its thing.

### Its knobs

`b3kPlayerSet` tunes how it moves, `b3kPlayerGet` reads a knob back, and an
empty value puts the default back:

| Knob | Default | Means |
|---|---|---|
| moveSpeed | 5 | metres a second it walks at |
| accel / airAccel | 40 / 12 | how quickly it reaches that speed, on the ground and in the air |
| jumpSpeed | 5.5 | metres a second upwards when it jumps (about 1.5 m high) |
| jumpCut | 0.5 | how much rising speed it keeps when jump is let go early (1: always full height) |
| airJumps | 0 | extra jumps in the air (1 is a double jump) |
| coyoteMs | 120 | a jump still counts this long after walking off an edge |
| bufferMs | 120 | a jump pressed this long before landing still happens |
| maxSlopeDeg | 50 | steeper than this is a wall, not ground |
| turnSpeed | 720 | degrees a second it turns to face its way |
| maxFall | 40 | the fastest it falls, metres a second |
| carry | 1 | it rides moving platforms (0: it does not) |

```
b3kPlayerSet "moveSpeed", 7
b3kPlayerSet "airJumps", 1                   -- a double jump
```

### Asking and telling

- `b3kPlayerOnGround()` is true when it stands on something.
- `b3kPlayerFacing()` is the way it faces, as a heading.
- `b3kPlayerJump 12` throws it up whether or not it stands on anything: a
  spring, a trampoline, a power-up.
- `b3kPlayerRespawn 0, 2, 0` puts it somewhere, still, standing and ready.
- `b3kPlayerSteer 0, 1` steers it from script (on-screen buttons, a touch
  screen); `b3kPlayerSteer empty, empty` gives the keys back.
- `b3kPlayerControl false` stops the keys steering it for a cut scene;
  `true` gives them back.
- `b3kPlayerRemove` lets it go: the thing stays, the keys stop steering it.

## 13. Messages: frames, touches, sensors, falls

The Kit sends six messages:

| Message | Parameters | When |
|---|---|---|
| `b3kFrame` | none | once a frame, after the physics steps and before the picture |
| `b3kContact` | `pA, pB` | two things started touching |
| `b3kEndContact` | `pA, pB` | they stopped |
| `b3kSensorEnter` | `pSensor, pVisitor` | a thing came into a sensor |
| `b3kSensorExit` | `pSensor, pVisitor` | it left |
| `b3kFell` | `pThing` | a thing dropped below the kill floor |

**Where they go.** Until you choose, they go to the card that is current when
`b3kSetup` makes the world, so a handler in that card's script or in its
stack's script hears them, wherever the Kit itself sits. Choose another
object with `b3kFrameTarget` (for `b3kFrame` and `b3kFell`) and
`b3kContactTarget` (for the touches and sensors).

```
on b3kContact pA, pB
   if pA is b3kPlayer() or pB is b3kPlayer() then add 1 to sBumps
end b3kContact
```

### Sensors

A sensor is a zone that notices what comes and goes and collides with
nothing: a coin, a goal, a trap, a spring pad.

```
b3kAddSensorBox 0, 1, -8, 2, 2, 2            -- or b3kAddSensorBall x, y, z, diam
put the result into tGoal

on b3kSensorEnter pSensor, pVisitor
   if pSensor is tGoal and pVisitor is b3kPlayer() then answer "You made it!"
end b3kSensorEnter
```

render3dxt does not draw a sensor until you show it with
`b3kSetVisible tGoal, true`; box3dxt's renderer draws every shape, so there a
sensor shows as a pale block.

### Polling instead

`b3kEvents()` lists the same events for the current frame, one a line
(`kind,a,b`), for a game that would rather ask than be told:

```
on b3kFrame
   put b3kEvents() into tEvents
   filter tEvents with "sensorenter,*"
   add the number of lines of tEvents to sPickups
end b3kFrame
```

## 14. Joints

A joint ties two things together, or one thing to the world (leave the second
thing empty). Each command reports the joint through the result.

| Call | Makes |
|---|---|
| `b3kHinge a, b, x, y, z, ax, ay, az` | a hinge at a point, turning about an axis: a door, a wheel, a see-saw |
| `b3kBallJoint a, b, x, y, z` | a ball and socket: a shoulder, a chain link, a pendulum |
| `b3kWeld a, b` | glue: the two move as one |
| `b3kRope a, b, length` | a rope from centre to centre: slack when close, taut at its length |
| `b3kSlider a, b, ax, ay, az` | a slide along a line: a lift, a piston, a drawer |

Hinges and sliders can be driven and stopped:

```
b3kSpawnBox 1, 3, 0, 2, 0.2, 1, "brown"
put the result into tDoor
b3kHinge tDoor, empty, 0, 3, 0, 0, 1, 0      -- turns about y at x = 0
put the result into tHinge
b3kHingeLimit tHinge, -90, 90                -- degrees (metres for a slider)
b3kMotor tHinge, 45, 200                     -- 45 degrees a second, at most 200 N m
put b3kHingeAngle(tHinge) into tOpen
```

A motor pushes as hard as it may to keep its speed, so give it no more
strength than the job needs: a weak one stalls under a load, and one far
stronger than its thing pushes past a limit. `b3kMotor tHinge, empty` turns it
off; speed 0 holds it still, as a brake.

`b3kRemoveJoint` takes a joint away. `b3kNoCollide a, b` stops two things
colliding with each other without joining them (the arm of a sweeper through
its hub, a driver in a car); it is a joint too, so `b3kRemoveJoint` takes the
rule away.

## 15. Two renderers

The Kit draws with **render3dxt** when that extension is loaded, and with the
renderer **inside box3dxt** when it is not. `b3kRenderer()` says which is
drawing, and `b3kUseRenderer` chooses: `"auto"` (the default), `"render3dxt"`,
`"box3dxt"`, or `"none"` to run the physics and draw nothing. It can change
while things exist; their pictures are remade.

| | render3dxt | box3dxt's renderer |
|---|---|---|
| colour, light direction (`b3kSetLight`), background | yes | yes |
| ambient light (`b3kSetAmbient`), fog (`b3kSetFog`) | yes | no |
| the sun's colour, glow (`b3kSetGlow`) and lamps (`b3kAddLamp`) | yes | no: white light, the plain colour |
| a model's look (`b3kSetLook`), its parts and poses | yes | no: the shape |
| smooth edges (`b3kSetSmooth`, 1 to 4) | yes | no |
| checkers and textures | yes | the thing's colour |
| a model's own materials | yes | its hull, in one colour |
| hidden things (`b3kSetVisible`) and sensors | hidden until shown | every shape drawn |
| wireframe and outlines (`b3kSetRenderMode`) | no | yes |
| where it draws | on render3dxt's own threads, while your script runs | in the loop |

The two meet at box3dxt's move list: after each physics step the Kit asks
box3dxt which bodies moved (`b3WorldUpdateMoves`) and hands that list to
render3dxt (`r3SceneApplyMoves`), so only what moved is touched.

`b3kDraw` draws the picture now (after changing things while the loop is
stopped or paused), and `b3kSync` puts every picture where its body is and
draws. The loop does both by itself.

## 16. Speed

- **The size of the view matters most.** Halve both sides and a picture costs
  a quarter as much. `b3kViewMake` takes 16 to 2048 pixels a side.
- `b3kSetSmooth 1` makes render3dxt's edges jagged but faster.
- **In a web page render3dxt draws on one thread, and the cost is pixels.**
  Every pixel a shape covers is drawn, even one that a later shape then
  covers, so a big shape hidden under the ground still costs its whole size.
  render3dxt draws in the order things were made: make the ground LAST and a
  pixel of it already hidden by a tree is refused by its depth alone. The
  sky behind everything costs almost nothing, so a view with sky in it is
  cheaper than one full of ground. Orb Island 1.2 measured these
  (2026-11-26).
- `b3kStats()` is one line: pictures drawn in the last second, things, bodies
  awake, the renderer, and whether a frame has caught an error. Put it in a
  field while you build a game.
- Things at rest sleep and cost almost nothing. A game that sets velocities
  every frame keeps them all awake.
- `tests/engine-demo.lc` prints the time of one frame of the example game, with
  each renderer, every time it runs.

## 17. The raw API underneath

The Kit never hides box3dxt. A thing is a body handle, so any raw `b3Body...`
call takes it as it is, `b3kWorld()` is the world for `b3World...` calls, and
`b3kShapeOf(thing)` is the shape for `b3Shape...` calls:

```
b3ShapeSetRollingResistance b3kShapeOf(tBall), 0.05
```

Two differences to keep in mind. The Kit's calls take an empty argument as
"the default", but a raw call that wants a number refuses empty (it is a hard
error in the extension's typed interface). And raw calls are in Box3D's terms
(radians, quaternions); the Kit's are in degrees. The whole raw API is in
[api-reference.md](api-reference.md).

## 18. The example game: Orb Island

`examples/box3dxt-orb-island.livecodescript` is a complete game on the Kit:
walk a floating island 60 metres square, find sixteen golden orbs, and do not
fall into the sea. It is one file: open it from the suite's start-here
launcher, or paste it into a new stack's script and reopen the stack.

Each part of the Kit carries part of the game:

| In the game | From the Kit |
|---|---|
| the world, the loop and the fall into the sea | `b3kSetup`, `b3kStart`, `b3kPause`, `b3kKillFloor` |
| the view and the renderer swap (V) | `b3kViewMake`, `b3kUseRenderer` |
| the evening light, the glowing orbs and crystals, the lanterns | `b3kSetLight` with a colour, `b3kSetFog`, `b3kSetGlow`, `b3kAddLamp` |
| the camera | `b3kCamFollow` (from `b3kPlayerMake`), `b3kCamMouseOrbit`, `b3kCamShake` |
| the island, the ramp, the stairs, the lift and the sky lift | `b3kAddGround`, `b3kAddStaticBox`, `b3kAddRamp`, `b3kAddPlatform` with `b3kGlideTo` |
| the hill | `b3kAddStaticModel` with OBJ text the game writes |
| stands of trees, standing stones, crystals | `b3kSpawnCone`, `b3kSpawnCylinder` and `b3kSpawnBox`, then `b3kSetType "static"` and `b3kSetRotation` |
| the windmill's sails and the beacon's beam | kinematic things turned by `b3kSetSpin` |
| the sweeper and the wrecking ball | a motor-driven `b3kHinge`, a `b3kRope`, `b3kNoCollide` |
| the orbs, the jump pad, the sea, the flags, the plate and the crumbling platforms | sensors, on `b3kSensorEnter` and `b3kSensorExit` |
| the vault's gate and its pressure plate, the turning platform | `b3kAddPlatform` with `b3kGlideTo`, and `b3kSetSpin` |
| crumbling platforms that fall and come back | `b3kAddStaticBox`, then `b3kSetType "dynamic"` and `b3kSetDensity` |
| the flags, platforms, gate, clouds, trees, grass, round isles, lifts and vault walls as Kenney's models | `b3kSetLook` |
| the player's idle, walk and jump, his squash, lean and the orbs' bob | `b3kAddLookPart`, `b3kPoseLookPart`, `b3kSetLookPose` |
| the player's shadow | `b3kRayHit` down from the player |
| the player, and a gamepad's stick | `b3kPlayerMake`, `b3kPlayerJump`, `b3kPlayerSteer`, `b3kPlayerRespawn` on `b3kFell` |
| kicking a crate with the mouse | `b3kThingAt`, unless `b3kCamDragged()` |

Two more of the suite's extensions join in when they are loaded, and the
game runs without them: **gamepadxt** (a controller walks, looks, jumps and
blasts, and rumbles when an orb is found) and **audioxt** (a sea that swells,
a chime a note higher for each orb, jumps, blasts, a splash and a fanfare,
all tones and noise made on the spot).

The models are Kenney's (kenney.nl), from his Platformer, City Builder and
FPS starter kits, CC0 (public domain): `examples/models/` holds them and says
which is which.
A web page has no folder of files beside a stack, so
`tools/build-game-models.py` turns each into OBJ text with flat colours,
fitted to the shape it is drawn on, and writes it into the game between its
`GAME MODELS` markers; its `--check` is a gate.

The game's own code sits above the embedded Kit, which is a verbatim copy of
`src/box3dxt-kit.livecodescript` between two marker lines. Never edit the copy:
change the Kit in `src/` and run `python3 tools/sync-embedded-kit.py`.

`tests/engine-demo.lc` plays the game on OXT-Beyond's headless server engine:
it builds the window, walks to an orb, collects them all, falls into the sea,
rides the pad, the lift and the sky lift, topples the dominoes, kicks, blasts
and drops crates, presses the plate with the heavy crate and with the player,
crumbles a platform, touches a flag and falls back to it, bumps a stand of
trees, falls off the round isle where a square one's corner was, watches the
character idle, walk and jump with its shadow under it and dust where it
lands, swaps the renderer,
and presses every button and key, with
box3dxt alone and with no extension at all; given render3dxt, gamepadxt (a
virtual pad) and audioxt (its silent device) too, it checks the lamps, the
pad's controls and the sounds. What only a person at a real
window can judge (the feel of the controls, the mouse, the look in the light
and dark appearance) is listed under "WHAT TO VERIFY" in the game's header.

## 19. Things worth knowing

- **Read the result at once.** A command that makes something reports it
  through the result, and the very next command replaces it.
- **A stale thing is harmless,** but it is not the same thing any more: keep
  handles of things that can disappear (fallen, removed, collected) in a form
  you can check with `b3kIsThing`.
- **Hidden things still collide.** `b3kSetVisible` is only the picture;
  `b3kDisable` takes a thing out of the world.
- **Separating two things that overlap takes a move.** After `b3kRemoveJoint`
  on a `b3kNoCollide`, two things that already overlap meet again only once
  one of them moves away and back.
- **One player, one ground, one view.** A second `b3kPlayerMake`,
  `b3kAddGround` or `b3kViewMake` replaces the first.
- **The Kit's messages reach the card current at `b3kSetup`.** A game that
  moves to another card calls `b3kSetup` there, or names its target with
  `b3kFrameTarget`.
- **Tidy up.** Call `b3kTeardown` in `closeCard` or `closeStack`. A loop left
  running keeps stepping a world nobody can see.
