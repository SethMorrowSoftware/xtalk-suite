# box3dxt Kit reference (`b3k...`)

The 168 handlers of the Kit's API, from the doc blocks in `src/box3dxt-kit.livecodescript`
(OXT-Beyond's dictionary reads the same blocks; `tools/build-kit-reference.py` writes this
file from them, and its `--check` is a gate). New to the Kit? Read
[kit-guide.md](kit-guide.md) first: it goes from an empty stack to a game. The raw binding
under the Kit is in [api-reference.md](api-reference.md).

A pure-script 3D game toolkit over the box3dxt extension (Box3D physics). You work in metres and degrees with y pointing up; the Kit runs the world on a fixed sixtieth-of-a-second step, draws it into one image control, moves the camera, reads the keyboard, steers a player and sends your script messages when things touch.

Start with [`b3kQuickStart`](#b3kquickstart) (or [`b3kSetup`](#b3ksetup), [`b3kViewMake`](#b3kviewmake) and [`b3kStart`](#b3kstart)), make things with [`b3kSpawnBox`](#b3kspawnbox) and its siblings, and handle b3kFrame for per-frame logic and b3kContact or b3kSensorEnter for touches. Commands report through the result, so read it on the next line. When the render3dxt extension is loaded the Kit draws with it (textured, lit, smooth edges); otherwise it draws with the renderer inside box3dxt.

It needs the box3dxt extension loaded: b3kVersion() returns 1.

Not listed, because it is not API: `b3kStep` (the loop's timer message, sent by b3kStart and rescheduled by itself with send in; start the loop with b3kStart, never call it).

## 60-second start

```
on openCard
   b3kQuickStart                     -- world, view, ground, camera, go
   b3kSpawnBox 0, 4, 0, 1, 1, 1, "orange"
   b3kSpawnBall 0.3, 7, 0.2, 1, "blue"
   put the result into tBall          -- a thing is its body's handle
end openCard
on mouseUp
   get b3kThingAt(the mouseH, the mouseV)    -- what is under the mouse
   if it is not empty then b3kPush it, 0, 6, 0
end mouseUp
on closeCard
   b3kTeardown                       -- before the card goes
end closeCard
```

## Cheat sheet

The Kit's own header carries this list; `--check` holds it to the
handlers below and to the messages the Kit sends (`b3kContact`, `b3kEndContact`, `b3kFell`, `b3kFrame`, `b3kSensorEnter`, `b3kSensorExit`).

```
WORLD   b3kSetup [gx,gy,gz] / b3kQuickStart [gy] / b3kStart / b3kStop /
        b3kPause / b3kResume / b3kStepOnce / b3kIsRunning() / b3kIsPaused() /
        b3kClear / b3kTeardown / b3kSetGravity gx,gy,gz / b3kGravity() /
        b3kSetSubsteps n / b3kKillFloor y / b3kWorld() / b3kEnsureNativeLib
TARGETS b3kFrameTarget obj / b3kContactTarget obj
VIEW    b3kViewMake l,t,w,h / b3kViewAttach img / b3kView() /
        b3kUseRenderer "auto"|"render3dxt"|"box3dxt"|"none" / b3kRenderer() /
        b3kSetBackground color / b3kSetLight dx,dy,dz / b3kSetAmbient color /
        b3kSetFog color,near,far / b3kSetSmooth 1..4 / b3kSetRenderMode mode /
        b3kDraw / b3kSync
CAMERA  b3kCamOrbit yaw,pitch,dist[,tx,ty,tz] / b3kCamOrbitBy dYaw,dPitch /
        b3kCamLookAt ex,ey,ez,tx,ty,tz[,fov] / b3kCamZoom dist / b3kCamZoomBy f /
        b3kCamSetFov deg / b3kCamFollow thing[,lerp,height] / b3kCamUnfollow /
        b3kCamShake metres,ms / b3kCamMouseOrbit flag / b3kCamDragged() /
        b3kCamEye() / b3kCamTarget() / b3kCamYaw() / b3kCamPitch() /
        b3kCamDistance() / b3kCamText()
SPAWN   b3kSpawnBox x,y,z,w,h,d[,color] / b3kSpawnBall x,y,z,diam[,color] /
        b3kSpawnCapsule x,y,z,len,diam[,color] / b3kSpawnCylinder x,y,z,h,diam[,color] /
        b3kSpawnCone x,y,z,h,diam[,color] / b3kSpawnHull x,y,z,points[,color] /
        b3kSpawnModel x,y,z,objTextOrPath[,scale,color]          (-> thing)
SCENERY b3kAddGround [size,y,colorA,colorB] / b3kAddWalls [height] /
        b3kAddStaticBox x,y,z,w,h,d[,color] / b3kAddRamp x,y,z,w,h,d,tilt[,yaw,color] /
        b3kAddStaticModel x,y,z,objTextOrPath[,scale,color] /
        b3kAddPlatform x,y,z,w,h,d[,color] / b3kGlideTo thing,x,y,z,seconds /
        b3kIsGliding(thing)
SENSOR  b3kAddSensorBox x,y,z,w,h,d / b3kAddSensorBall x,y,z,diam
LOOK    b3kSetColor thing,color / b3kColor(thing) / b3kSetChecker thing,a,b[,cells] /
        b3kSetTexture thing,path / b3kSetVisible thing,flag / b3kIsVisible(thing)
MATERIAL b3kSetBounce thing,0..1 / b3kSetFriction thing,f / b3kSetDensity thing,d
BODY    b3kSetType thing,"static"|"kinematic"|"dynamic" / b3kType(thing) /
        b3kSetGravityScale thing,s / b3kSetDamping thing,lin[,ang] /
        b3kSetBullet thing,flag / b3kKeepUpright thing,flag / b3kWake thing /
        b3kEnable thing / b3kDisable thing
ACT     b3kPush thing,dvx,dvy,dvz / b3kImpulse thing,ix,iy,iz / b3kForce thing,fx,fy,fz /
        b3kTorque thing,tx,ty,tz / b3kSetVelocity thing,vx,vy,vz /
        b3kSetSpin thing,wx,wy,wz (deg/s) / b3kMoveTo thing,x,y,z /
        b3kSetRotation thing,rx,ry,rz (deg) / b3kTurnTo thing,yaw /
        b3kExplode x,y,z[,radius,power] / b3kRemove thing
GET     b3kPosition(thing) / b3kX(thing) / b3kY(thing) / b3kZ(thing) /
        b3kVelocity(thing) / b3kSpeed(thing) / b3kRotation(thing) / b3kYaw(thing) /
        b3kMass(thing) / b3kIsAwake(thing) / b3kKind(thing) / b3kIsThing(x) /
        b3kThings() / b3kThingCount() / b3kDistance(a,b) / b3kShapeOf(thing) /
        b3kName thing,name / b3kNameOf(thing) / b3kThingNamed(name)
PICK    b3kThingAt(cardX,cardY) / b3kPointAt(cardX,cardY) /
        b3kGroundPoint(cardX,cardY[,y]) / b3kProject(x,y,z) /
        b3kRayHit(ox,oy,oz,dx,dy,dz) + b3kHitPoint() / b3kHitNormal() /
        b3kHitDistance() / b3kOverlapSphere(x,y,z,r)
JOINTS  b3kHinge a,b,x,y,z,ax,ay,az / b3kBallJoint a,b,x,y,z / b3kWeld a,b /
        b3kRope a,b[,maxLen] / b3kSlider a,b,ax,ay,az / b3kMotor j,deg/s[,torque] /
        b3kHingeLimit j,lo,hi / b3kHingeAngle(j) / b3kRemoveJoint j / b3kNoCollide a,b
INPUT   b3kInputOn / b3kInputOff / b3kInputIsOn() / b3kKeyIsDown(k) / b3kKeyPressed(k) /
        b3kKeyReleased(k) / b3kKeysHeld() / b3kBindAction name,keys /
        b3kActionIsDown(name) / b3kActionPressed(name) / b3kActionReleased(name) /
        b3kBindAxis name,neg,pos / b3kAxis(name) / b3kInputInject keys /
        b3kInputInjectOff
PLAYER  b3kPlayerMake x,y,z[,kind,color] / b3kPlayerAttach thing[,mode] /
        b3kPlayerSet key,value / b3kPlayerGet(key) / b3kPlayer() /
        b3kPlayerOnGround() / b3kPlayerFacing() / b3kPlayerJump [speed] /
        b3kPlayerControl flag / b3kPlayerSteer x,y / b3kPlayerRespawn x,y,z /
        b3kPlayerRemove
        (moves on axes "moveX"/"moveY" relative to the camera, jumps on
        action "jump"; axis "turn" (q/e) turns the camera)
EVENTS  on b3kFrame / on b3kContact pA,pB / on b3kEndContact pA,pB /
        on b3kSensorEnter pSensor,pVisitor / on b3kSensorExit pSensor,pVisitor /
        on b3kFell pThing    (poll instead: b3kEvents())
INFO    b3kVersion() / b3kHasPhysics() / b3kHasRender3d() / b3kLastError() /
        b3kFrameError() / b3kFrameMS() / b3kStats()

Tips: a THING is its body's handle (a positive whole number), so raw
b3... calls take it as it is. Messages go to the card that is current at
b3kSetup (its script, then its stack's) unless b3kFrameTarget /
b3kContactTarget say otherwise. Keep moving things between about 0.1 and
10 metres: Box3D is tuned for that range.
```

## Contents

- [Info and capability probes](#info-and-capability-probes)
- [World & loop](#world--loop)
- [The loop: a fixed step, generation-guarded, one screen lock a frame](#the-loop-a-fixed-step-generation-guarded-one-screen-lock-a-frame)
- [The view and the two renderers](#the-view-and-the-two-renderers)
- [The camera](#the-camera)
- [Picking: from the view to the world and back](#picking-from-the-view-to-the-world-and-back)
- [Things: a body, one shape, and its picture](#things-a-body-one-shape-and-its-picture)
- [Scenery: things that do not fall](#scenery-things-that-do-not-fall)
- [Sensors: zones that notice what enters them](#sensors-zones-that-notice-what-enters-them)
- [Look and material](#look-and-material)
- [Body settings](#body-settings)
- [Acting on things](#acting-on-things)
- [Reading things](#reading-things)
- [Joints: hinges, balls, welds, ropes and sliders between two things](#joints-hinges-balls-welds-ropes-and-sliders-between-two-things)
- [Input (keyboard): one sample of the keys held, once a frame](#input-keyboard-one-sample-of-the-keys-held-once-a-frame)
- [The player: one character the keys steer, relative to the camera](#the-player-one-character-the-keys-steer-relative-to-the-camera)

## Info and capability probes

### `b3kVersion`

`b3kVersion()`

The Kit's own version.

Returns: A whole number as text; it goes up when the Kit's calls change.

```
put "Box3Dxt Kit" && b3kVersion() into field "About"
```

See also: [`b3kHasPhysics`](#b3khasphysics), [`b3kHasRender3d`](#b3khasrender3d)

### `b3kHasPhysics`

`b3kHasPhysics()`

Report whether the box3dxt extension is loaded.

Returns: true when box3dxt answers; false otherwise.

The Kit's first question. It asks the library its ABI number inside a try, so a missing extension is an answer, not an error.

```
if not b3kHasPhysics() then answer "Install the box3dxt extension first."
```

See also: [`b3kHasRender3d`](#b3khasrender3d), [`b3kSetup`](#b3ksetup)

### `b3kHasRender3d`

`b3kHasRender3d()`

Report whether the render3dxt extension is loaded.

Returns: true when render3dxt answers; false otherwise.

When it is, the Kit draws with it unless [`b3kUseRenderer`](#b3kuserenderer) says otherwise.

```
if b3kHasRender3d() then b3kSetSmooth 2
```

See also: [`b3kUseRenderer`](#b3kuserenderer), [`b3kRenderer`](#b3krenderer)

### `b3kLastError`

`b3kLastError()`

The reason the last Kit call that failed gave.

Returns: Text, or empty when nothing has failed.

```
b3kSetup
if b3kLastError() is not empty then answer b3kLastError()
```

See also: [`b3kFrameError`](#b3kframeerror)

### `b3kFrameError`

`b3kFrameError()`

The error a frame last caught, if any.

Returns: The engine's error text, or empty.

The loop runs your b3kFrame handler and the Kit's own frame work inside one try, so that an error can never leave the screen locked. The error is kept here instead of being lost: a frame that stopped half way says why.

```
if b3kFrameError() is not empty then put b3kFrameError() into field "Debug"
```

See also: [`b3kFrameTarget`](#b3kframetarget), [`b3kLastError`](#b3klasterror)

### `b3kFrameMS`

`b3kFrameMS()`

The real time the last frame covered.

Returns: Milliseconds, or 0 before the first frame. A hand step counts as one 1/60 s step.

Drive game timers from this, not the frame count: a frame may run zero, one or several fixed physics steps.

```
add b3kFrameMS() to tTimer
```

See also: [`b3kFrameTarget`](#b3kframetarget)

### `b3kStats`

`b3kStats()`

How the Kit is doing, as one line.

Returns: Five items: pictures drawn in the last second, things, bodies awake, the renderer, and true when a frame has caught an error (see [`b3kFrameError`](#b3kframeerror)).

```
put b3kStats() into field "Stats"
```

See also: [`b3kFrameMS`](#b3kframems), [`b3kRenderer`](#b3krenderer)

### `b3kWorld`

`b3kWorld()`

The box3dxt world the Kit runs.

Returns: The world handle, or empty before [`b3kSetup`](#b3ksetup).

For raw b3... calls beside the Kit. A thing is its body's handle, so raw body calls take a thing as it is.

```
put b3WorldContactCount(b3kWorld()) into tTouching
```

See also: [`b3kSetup`](#b3ksetup)

## World & loop

### `b3kEnsureNativeLib`

`b3kEnsureNativeLib`

Point the engine at libraries saved beside the stack.

When box3dxt.dll, .dylib or .so (by platform) sits in the folder of the saved stack, its revLibraryMapping is set to that file, so the extension resolves with no install; render3dxt's library likewise. Otherwise the engine's own search is left alone. An unsaved stack is a quiet no-op. [`b3kSetup`](#b3ksetup) calls it for you.

```
b3kEnsureNativeLib
```

See also: [`b3kSetup`](#b3ksetup)

### `b3kSetup`

`b3kSetup pGx, pGy, pGz`

Make a world with gravity, ready for things.

- `pGx`: Gravity along x in m/s^2. Empty means 0.
- `pGy`: Gravity along y; y points up, so empty means -10 (down).
- `pGz`: Gravity along z. Empty means 0.

Tears down any world the Kit already runs, makes a new one, picks the renderer ([`b3kUseRenderer`](#b3kuserenderer)) and puts the camera at its starting place. If box3dxt is not loaded nothing is made and [`b3kLastError`](#b3klasterror) says so; the result says it too.

```
b3kSetup
b3kAddGround
b3kStart
```

See also: [`b3kQuickStart`](#b3kquickstart), [`b3kStart`](#b3kstart), [`b3kTeardown`](#b3kteardown)

### `b3kQuickStart`

`b3kQuickStart pGy`

One call to a running scene: world, view, ground, camera, go.

- `pGy`: Gravity along y; empty means -10.

[`b3kSetup`](#b3ksetup), then a view filling the card if none is attached ([`b3kViewMake`](#b3kviewmake)), a 30 metre ground ([`b3kAddGround`](#b3kaddground)), the camera looking at the middle, and [`b3kStart`](#b3kstart).

```
b3kQuickStart
b3kSpawnBall 0, 5, 0, 1
```

See also: [`b3kSetup`](#b3ksetup), [`b3kViewMake`](#b3kviewmake), [`b3kAddGround`](#b3kaddground)

### `b3kStart`

`b3kStart`

Start the simulation loop.

Steps the world at a fixed 1/60 s, carries each step to the picture, delivers events and sends b3kFrame once a frame. Calls [`b3kSetup`](#b3ksetup) first when there is no world. Starting again replaces a running loop.

```
b3kSetup
b3kAddGround
b3kStart
```

See also: [`b3kStop`](#b3kstop), [`b3kPause`](#b3kpause), [`b3kStepOnce`](#b3ksteponce)

### `b3kStop`

`b3kStop`

Stop the simulation loop.

The world and its things stay; nothing steps until [`b3kStart`](#b3kstart). [`b3kTeardown`](#b3kteardown) destroys the world as well.

```
b3kStop
```

See also: [`b3kStart`](#b3kstart), [`b3kTeardown`](#b3kteardown)

### `b3kPause`

`b3kPause`

Freeze the simulation without stopping the loop.

While paused no physics step runs and no b3kFrame is sent, but the camera still answers the mouse and the keys, and the picture is redrawn when it moves. [`b3kStepOnce`](#b3ksteponce) still advances one step.

```
b3kPause
```

See also: [`b3kResume`](#b3kresume), [`b3kIsPaused`](#b3kispaused)

### `b3kResume`

`b3kResume`

Resume after [`b3kPause`](#b3kpause).

```
b3kResume
```

See also: [`b3kPause`](#b3kpause)

### `b3kIsRunning`

`b3kIsRunning()`

Report whether the loop is stepping.

Returns: true while started and not paused.

```
if b3kIsRunning() then b3kPause
```

See also: [`b3kIsPaused`](#b3kispaused)

### `b3kIsPaused`

`b3kIsPaused()`

Report whether the loop is paused.

Returns: true or false.

```
if b3kIsPaused() then b3kResume
```

See also: [`b3kIsRunning`](#b3kisrunning)

### `b3kSetGravity`

`b3kSetGravity pGx, pGy, pGz`

Change gravity.

- `pGx`: Along x, m/s^2.
- `pGy`: Along y; -10 is earth-like.
- `pGz`: Along z.

```
b3kSetGravity 0, -3, 0   -- the moon, more or less
```

See also: [`b3kGravity`](#b3kgravity)

### `b3kGravity`

`b3kGravity()`

The world's gravity.

Returns: "x,y,z" in m/s^2, or empty with no world.

```
put item 2 of b3kGravity() into tDown
```

See also: [`b3kSetGravity`](#b3ksetgravity)

### `b3kSetSubsteps`

`b3kSetSubsteps pN`

Set how many solver sub-steps each step takes.

- `pN`: 1 to 8; the Kit starts at 4.

```
b3kSetSubsteps 8   -- tall stacks stand steadier
```

See also: [`b3kSetup`](#b3ksetup)

### `b3kFrameTarget`

`b3kFrameTarget pObject`

Choose the object that receives b3kFrame and b3kFell.

- `pObject`: A reference to an object, such as the long id of this card; empty puts the default back.

Until you name one, the target is the card that is current when [`b3kSetup`](#b3ksetup) makes the world (each b3kSetup chooses again), so a handler in that card's script or in its stack's script, where a pasted Kit sits, hears the messages. A target you name is kept until you name another. b3kFrame is sent once a frame, after the physics steps and before the picture is drawn: read the keys and move things there.

```
b3kFrameTarget the long id of this card
```

See also: [`b3kContactTarget`](#b3kcontacttarget), [`b3kFrameError`](#b3kframeerror)

### `b3kContactTarget`

`b3kContactTarget pObject`

Choose the object that receives the touch and sensor messages.

- `pObject`: A reference to an object; empty sends them to the frame target.

Receives b3kContact and b3kEndContact (two things), b3kSensorEnter and b3kSensorExit (the sensor, then the thing that came or went).

```
b3kContactTarget the long id of this card
```

See also: [`b3kFrameTarget`](#b3kframetarget), [`b3kEvents`](#b3kevents)

### `b3kKillFloor`

`b3kKillFloor pY`

Remove things that fall below a height.

- `pY`: The height in metres; empty turns it off.

A few times a second, every moving thing whose centre is below pY is sent to the frame target as b3kFell, then removed. The player is reported and NOT removed: your game decides where it starts again.

```
b3kKillFloor -10
```

See also: [`b3kRemove`](#b3kremove), [`b3kPlayer`](#b3kplayer)

### `b3kClear`

`b3kClear`

Remove every thing, keep the world.

Things, the ground, the player and every joint go; the world, its gravity, the camera, the view and the loop stay.

```
b3kClear
b3kAddGround
```

See also: [`b3kTeardown`](#b3kteardown), [`b3kRemove`](#b3kremove)

### `b3kTeardown`

`b3kTeardown`

Stop the loop and destroy the world and everything the Kit made.

The world, every thing, the render3dxt scene with its meshes, materials and textures, the player and the camera's follow all go. The view image is kept (it is your control) and so are the key bindings.

```
b3kTeardown    -- in closeCard, before the card goes
```

See also: [`b3kSetup`](#b3ksetup), [`b3kClear`](#b3kclear)

## The loop: a fixed step, generation-guarded, one screen lock a frame

### `b3kStepOnce`

`b3kStepOnce`

Advance exactly one 1/60 s step, even while paused.

Runs one whole frame of one step: keys, player, physics, events, b3kFrame and the picture. For a Step button and for tests. Needs a world; the loop need not be running.

```
b3kPause
b3kStepOnce
```

See also: [`b3kPause`](#b3kpause), [`b3kStart`](#b3kstart)

### `b3kEvents`

`b3kEvents()`

This frame's events, for polling instead of messages.

Returns: One line per event, "kind,a,b": kind is contact, endcontact, sensorenter or sensorexit; a and b are things (0 for a body the Kit did not make, or one already gone).

Read it from b3kFrame: it covers every physics step of the frame.

```
put b3kEvents() into tEvents
filter tEvents with "sensorenter,*"
put the number of lines of tEvents into tPickups
```

See also: [`b3kContactTarget`](#b3kcontacttarget)

## The view and the two renderers

### `b3kViewMake`

`b3kViewMake pLeft, pTop, pWidth, pHeight`

Make an image to draw into and attach it as the view.

- `pLeft`: Its left edge on the card, in pixels.
- `pTop`: Its top edge.
- `pWidth`: Its width, 16 to 2048 pixels.
- `pHeight`: Its height, 16 to 2048 pixels.

Returns: (through the result) the image's long id.

Makes an image named "b3kView" on the current card, or reuses the one there, and hands it to [`b3kViewAttach`](#b3kviewattach). A smaller picture draws faster: halve both sides and it costs a quarter as much.

```
b3kViewMake 0, 40, 640, 400
```

See also: [`b3kViewAttach`](#b3kviewattach), [`b3kView`](#b3kview)

### `b3kViewAttach`

`b3kViewAttach pImage`

Draw into an image you made.

- `pImage`: A reference to an image control (the long id is safest).

The picture takes the image's size, read again whenever the image is resized. The image's own contents are replaced by the picture.

```
b3kViewAttach the long id of image "Game"
```

See also: [`b3kViewMake`](#b3kviewmake), [`b3kView`](#b3kview)

### `b3kView`

`b3kView()`

The image the Kit draws into.

Returns: Its long id, or empty when there is none.

```
put the rect of b3kView() into tRect
```

See also: [`b3kViewMake`](#b3kviewmake), [`b3kViewAttach`](#b3kviewattach)

### `b3kUseRenderer`

`b3kUseRenderer pWhich`

Choose who draws the picture.

- `pWhich`: "auto" (the default), "render3dxt", "box3dxt" or "none".

"auto" takes render3dxt when it is loaded and box3dxt's own renderer otherwise. "none" runs the physics and draws nothing. Naming a renderer that is not loaded falls back as "auto" would, and [`b3kRenderer`](#b3krenderer) says what was chosen. It can change while things exist: their pictures are remade.

```
b3kUseRenderer "box3dxt"   -- solid colours, even with render3dxt loaded
```

See also: [`b3kRenderer`](#b3krenderer), [`b3kHasRender3d`](#b3khasrender3d)

### `b3kRenderer`

`b3kRenderer()`

Who is drawing the picture.

Returns: "render3dxt", "box3dxt" or "none"; empty before [`b3kSetup`](#b3ksetup).

```
if b3kRenderer() is "box3dxt" then b3kSetRenderMode "outline"
```

See also: [`b3kUseRenderer`](#b3kuserenderer)

### `b3kSetBackground`

`b3kSetBackground pColor`

Set the colour behind everything.

- `pColor`: A colour name, "r,g,b" or "#rrggbb".

```
b3kSetBackground "20,24,36"
```

See also: [`b3kSetLight`](#b3ksetlight), [`b3kSetFog`](#b3ksetfog)

### `b3kSetLight`

`b3kSetLight pDx, pDy, pDz`

Set the direction the sunlight travels.

- `pDx`: The x of the direction.
- `pDy`: The y of the direction; negative shines down.
- `pDz`: The z of the direction.

Both renderers light from this direction; a surface facing away keeps a dim shade, so nothing goes black.

```
b3kSetLight -0.4, -1, -0.3
```

See also: [`b3kSetAmbient`](#b3ksetambient)

### `b3kSetAmbient`

`b3kSetAmbient pColor`

Set the light that reaches every surface (render3dxt only).

- `pColor`: A colour name, "r,g,b" or "#rrggbb"; darker is moodier.

```
b3kSetAmbient "60,64,80"
```

See also: [`b3kSetLight`](#b3ksetlight)

### `b3kSetFog`

`b3kSetFog pColor, pNear, pFar`

Fade far things into a colour (render3dxt only).

- `pColor`: The fog's colour; usually the background's.
- `pNear`: Where the fog starts, in metres from the camera.
- `pFar`: Where it is complete. Empty or 0 turns fog off.

```
b3kSetFog "26,30,44", 20, 60
```

See also: [`b3kSetBackground`](#b3ksetbackground)

### `b3kSetSmooth`

`b3kSetSmooth pN`

Choose how smooth edges are (render3dxt only).

- `pN`: 1 (fastest, jagged) to 4 (smoothest); the Kit starts at 2.

```
b3kSetSmooth 1   -- for a slow machine
```

See also: [`b3kRenderer`](#b3krenderer)

### `b3kSetRenderMode`

`b3kSetRenderMode pMode`

Choose how box3dxt's own renderer draws.

- `pMode`: "solid" (the default), "wireframe" or "outline" (solid with edges).

render3dxt always draws solid; this applies to box3dxt's renderer.

```
b3kSetRenderMode "outline"
```

See also: [`b3kUseRenderer`](#b3kuserenderer)

### `b3kDraw`

`b3kDraw`

Draw the picture now.

The loop draws by itself whenever something moved; call this after changing things while the loop is stopped or paused. It draws at once, replacing any picture still being drawn in the background.

```
b3kMoveTo tCrate, 0, 3, 0
b3kDraw
```

See also: [`b3kSync`](#b3ksync)

### `b3kSync`

`b3kSync`

Put every thing's picture where its body is.

The loop does this by itself from the physics step's move list. After moving things by hand in a stopped world, call it (it also draws).

```
b3kPause
b3kMoveTo tCrate, 0, 2, 0
b3kSync
```

See also: [`b3kDraw`](#b3kdraw)

## The camera

### `b3kCamOrbit`

`b3kCamOrbit pYaw, pPitch, pDistance, pTx, pTy, pTz`

Put the camera on an orbit round a point.

- `pYaw`: Degrees round the vertical; 0 looks along -z from the +z side.
- `pPitch`: Degrees above the horizon, -89 to 89.
- `pDistance`: Metres from the point.
- `pTx`: The x of the point it looks at; empty keeps the current one.
- `pTy`: Its y.
- `pTz`: Its z.

```
b3kCamOrbit 45, 30, 20, 0, 0, 0
```

See also: [`b3kCamOrbitBy`](#b3kcamorbitby), [`b3kCamLookAt`](#b3kcamlookat), [`b3kCamFollow`](#b3kcamfollow)

### `b3kCamOrbitBy`

`b3kCamOrbitBy pDYaw, pDPitch`

Turn the camera round its point.

- `pDYaw`: Degrees to add to the yaw.
- `pDPitch`: Degrees to add to the pitch (kept within -89 to 89).

```
b3kCamOrbitBy 2, 0   -- a slow turn, once a frame
```

See also: [`b3kCamOrbit`](#b3kcamorbit), [`b3kCamMouseOrbit`](#b3kcammouseorbit)

### `b3kCamLookAt`

`b3kCamLookAt pEx, pEy, pEz, pTx, pTy, pTz, pFov`

Place the camera by an eye and a target.

- `pEx`: The x of the eye.
- `pEy`: The y of the eye.
- `pEz`: The z of the eye.
- `pTx`: The x of the point it looks at.
- `pTy`: Its y.
- `pTz`: Its z.
- `pFov`: The vertical field of view in degrees; empty keeps the current one (the Kit starts at 50).

The Kit turns it into an orbit round the target, so [`b3kCamOrbitBy`](#b3kcamorbitby) and [`b3kCamZoomBy`](#b3kcamzoomby) carry on from here.

```
b3kCamLookAt 0, 12, 18, 0, 0, 0
```

See also: [`b3kCamOrbit`](#b3kcamorbit), [`b3kCamSetFov`](#b3kcamsetfov)

### `b3kCamZoom`

`b3kCamZoom pDistance`

Set how far the camera stands from its point.

- `pDistance`: Metres, 0.1 or more.

```
b3kCamZoom 8
```

See also: [`b3kCamZoomBy`](#b3kcamzoomby)

### `b3kCamZoomBy`

`b3kCamZoomBy pFactor`

Move the camera nearer or farther by a factor.

- `pFactor`: Below 1 comes nearer, above 1 goes farther.

```
b3kCamZoomBy 0.9
```

See also: [`b3kCamZoom`](#b3kcamzoom)

### `b3kCamSetFov`

`b3kCamSetFov pDegrees`

Set the camera's vertical field of view.

- `pDegrees`: 5 to 150; 50 is a natural lens, small is a telephoto.

```
b3kCamSetFov 70
```

See also: [`b3kCamLookAt`](#b3kcamlookat)

### `b3kCamFollow`

`b3kCamFollow pThing, pLerp, pHeight`

Keep the camera on a thing as it moves.

- `pThing`: The thing to follow.
- `pLerp`: How quickly it catches up each frame, 0.01 to 1; empty means 0.15.
- `pHeight`: Metres above the thing's centre to look at; empty means 0.8.

The orbit (yaw, pitch, distance) stays yours: turn it with [`b3kCamOrbitBy`](#b3kcamorbitby), the mouse ([`b3kCamMouseOrbit`](#b3kcammouseorbit)) or the "turn" axis.

```
b3kPlayerMake 0, 1, 0
b3kCamFollow b3kPlayer()
```

See also: [`b3kCamUnfollow`](#b3kcamunfollow), [`b3kCamOrbit`](#b3kcamorbit)

### `b3kCamUnfollow`

`b3kCamUnfollow`

Stop following.

```
b3kCamUnfollow
```

See also: [`b3kCamFollow`](#b3kcamfollow)

### `b3kCamShake`

`b3kCamShake pAmount, pMilliseconds`

Shake the camera for a moment.

- `pAmount`: How far the eye jumps, in metres; 0.2 is a thump.
- `pMilliseconds`: How long it lasts.

```
b3kCamShake 0.3, 250
```

See also: [`b3kExplode`](#b3kexplode)

### `b3kCamMouseOrbit`

`b3kCamMouseOrbit pFlag`

Let a drag on the view turn the camera.

- `pFlag`: true to turn it on, false to turn it off.

While the mouse button is held after a press on the view, moving the mouse sideways turns the camera round its point and up and down tilts it. A click that did not move is still yours: in mouseUp, ask [`b3kCamDragged`](#b3kcamdragged) whether the press was a drag before treating it as a click.

```
b3kCamMouseOrbit true
```

See also: [`b3kCamDragged`](#b3kcamdragged), [`b3kCamOrbitBy`](#b3kcamorbitby)

### `b3kCamDragged`

`b3kCamDragged()`

Report whether the last press on the view dragged the camera.

Returns: true when the mouse moved more than 4 pixels while held.

```
-- first thing in the view's mouseUp handler:
if b3kCamDragged() then exit mouseUp
```

See also: [`b3kCamMouseOrbit`](#b3kcammouseorbit)

### `b3kCamEye`

`b3kCamEye()`

Where the camera's eye is.

Returns: "x,y,z" in metres.

```
put b3kCamEye() into tEye
```

See also: [`b3kCamTarget`](#b3kcamtarget), [`b3kCamText`](#b3kcamtext)

### `b3kCamTarget`

`b3kCamTarget()`

The point the camera looks at.

Returns: "x,y,z" in metres.

```
put b3kCamTarget() into tAim
```

See also: [`b3kCamEye`](#b3kcameye)

### `b3kCamYaw`

`b3kCamYaw()`

The camera's yaw round its point.

Returns: Degrees.

```
put b3kCamYaw() into tHeading
```

See also: [`b3kCamOrbit`](#b3kcamorbit)

### `b3kCamPitch`

`b3kCamPitch()`

The camera's pitch above the horizon.

Returns: Degrees, -89 to 89.

```
put b3kCamPitch() into tTilt
```

See also: [`b3kCamOrbit`](#b3kcamorbit)

### `b3kCamDistance`

`b3kCamDistance()`

How far the camera stands from its point.

Returns: Metres.

```
put b3kCamDistance() into tZoom
```

See also: [`b3kCamZoom`](#b3kcamzoom)

### `b3kCamText`

`b3kCamText()`

The camera as the seven numbers both renderers take.

Returns: "ex,ey,ez,tx,ty,tz,fov".

```
r3SceneSetCameraText tMyOtherScene, b3kCamText()
```

See also: [`b3kCamEye`](#b3kcameye)

## Picking: from the view to the world and back

### `b3kProject`

`b3kProject(pX, pY, pZ)`

Where a point of the world appears on the card.

- `pX`: The x of the point, in metres.
- `pY`: Its y.
- `pZ`: Its z.

Returns: "h,v" card coordinates (they may lie off the view), or empty when the point is behind the camera or there is no view.

```
set the loc of field "Label" to b3kProject(b3kX(tCrate), b3kY(tCrate) + 1, b3kZ(tCrate))
```

See also: [`b3kThingAt`](#b3kthingat), [`b3kGroundPoint`](#b3kgroundpoint)

### `b3kThingAt`

`b3kThingAt(pH, pV)`

The thing under a point of the card.

- `pH`: The horizontal card coordinate, such as the mouseH.
- `pV`: The vertical card coordinate, such as the mouseV.

Returns: The thing, or empty when the ray from the camera through that point meets nothing within 500 metres.

A ray is cast through the world, so it needs no picture and works with either renderer. Where it struck is [`b3kHitPoint`](#b3khitpoint); the ground counts as a thing. Sensors are not seen.

```
-- in the view's mouseUp handler:
get b3kThingAt(the mouseH, the mouseV)
if it is not empty then b3kPush it, 0, 5, 0
```

See also: [`b3kPointAt`](#b3kpointat), [`b3kRayHit`](#b3krayhit), [`b3kHitPoint`](#b3khitpoint)

### `b3kPointAt`

`b3kPointAt(pH, pV)`

The point of the world under a point of the card.

- `pH`: The horizontal card coordinate.
- `pV`: The vertical card coordinate.

Returns: "x,y,z" where the camera's ray first meets something, or empty.

```
put b3kPointAt(the mouseH, the mouseV) into tWhere
if tWhere is not empty then b3kSpawnBall item 1 of tWhere, 5, item 3 of tWhere, 0.6
```

See also: [`b3kThingAt`](#b3kthingat), [`b3kGroundPoint`](#b3kgroundpoint)

### `b3kGroundPoint`

`b3kGroundPoint(pH, pV, pY)`

Where the camera's ray through a card point meets a flat level.

- `pH`: The horizontal card coordinate.
- `pV`: The vertical card coordinate.
- `pY`: The height of the level in metres; empty means 0.

Returns: "x,y,z", or empty when the ray runs parallel to the level or away from it.

Needs no body there: for aiming, placing things in an editor, or click-to-move over open ground.

```
put b3kGroundPoint(the mouseH, the mouseV) into tAim
```

See also: [`b3kPointAt`](#b3kpointat)

### `b3kRayHit`

`b3kRayHit(pOx, pOy, pOz, pDx, pDy, pDz)`

Cast a ray and report the first thing it meets.

- `pOx`: The x of the start, in metres.
- `pOy`: Its y.
- `pOz`: Its z.
- `pDx`: The x of the travel: how far and which way, not just a direction.
- `pDy`: Its y.
- `pDz`: Its z.

Returns: The thing, or empty. [`b3kHitPoint`](#b3khitpoint), [`b3kHitNormal`](#b3khitnormal) and [`b3kHitDistance`](#b3khitdistance) say more.

A body the Kit did not make is reported as its body handle.

```
-- is there ground within 2 m under the crate?
put b3kRayHit(b3kX(tCrate), b3kY(tCrate), b3kZ(tCrate), 0, -2, 0) into tBelow
```

See also: [`b3kThingAt`](#b3kthingat), [`b3kHitPoint`](#b3khitpoint)

### `b3kHitPoint`

`b3kHitPoint()`

Where the last ray or pick struck.

Returns: "x,y,z", or empty when it struck nothing.

```
get b3kThingAt(the mouseH, the mouseV)
put b3kHitPoint() into tWhere
```

See also: [`b3kRayHit`](#b3krayhit), [`b3kHitNormal`](#b3khitnormal)

### `b3kHitNormal`

`b3kHitNormal()`

Which way the surface faced where the last ray struck.

Returns: "x,y,z" of length 1, or empty.

```
if item 2 of b3kHitNormal() > 0.7 then put "floor" into tSurface
```

See also: [`b3kRayHit`](#b3krayhit)

### `b3kHitDistance`

`b3kHitDistance()`

How far the last ray travelled before it struck.

Returns: Metres, or empty.

```
if b3kHitDistance() < 1 then put "close" into tWarn
```

See also: [`b3kRayHit`](#b3krayhit)

### `b3kOverlapSphere`

`b3kOverlapSphere(pX, pY, pZ, pRadius)`

The things inside a sphere.

- `pX`: The x of the centre.
- `pY`: Its y.
- `pZ`: Its z.
- `pRadius`: The radius in metres.

Returns: One thing a line (each once), or empty.

Sensors and sleeping things are included.

```
put b3kOverlapSphere(0, 1, 0, 3) into tNear
if tNear is not empty then b3kPush line 1 of tNear, 0, 4, 0
```

See also: [`b3kExplode`](#b3kexplode)

## Things: a body, one shape, and its picture

### `b3kSpawnBox`

`b3kSpawnBox pX, pY, pZ, pW, pH, pD, pColor`

Make a box that falls and tumbles.

- `pX`: The x of its centre, in metres.
- `pY`: The y of its centre; y points up.
- `pZ`: The z of its centre.
- `pW`: Its width (along x) in metres; empty means 1.
- `pH`: Its height (along y); empty means 1.
- `pD`: Its depth (along z); empty means 1.
- `pColor`: A colour name, "r,g,b" or "#rrggbb"; empty takes the next colour of the Kit's palette.

Returns: (through the result) the thing, or empty if it was refused (see [`b3kLastError`](#b3klasterror)).

```
b3kSpawnBox 0, 5, 0, 1, 1, 1, "orange"
put the result into tCrate
```

See also: [`b3kSpawnBall`](#b3kspawnball), [`b3kAddStaticBox`](#b3kaddstaticbox), [`b3kRemove`](#b3kremove)

### `b3kSpawnBall`

`b3kSpawnBall pX, pY, pZ, pDiameter, pColor`

Make a ball that falls and rolls.

- `pX`: The x of its centre, in metres.
- `pY`: The y of its centre.
- `pZ`: The z of its centre.
- `pDiameter`: Its diameter in metres; empty means 1.
- `pColor`: A colour; empty takes the next palette colour.

Returns: (through the result) the thing, or empty if it was refused.

```
b3kSpawnBall 0, 6, 0, 0.8, "red"
```

See also: [`b3kSpawnBox`](#b3kspawnbox)

### `b3kSpawnCapsule`

`b3kSpawnCapsule pX, pY, pZ, pLength, pDiameter, pColor`

Make a capsule (a pill) standing along y.

- `pX`: The x of its centre.
- `pY`: The y of its centre.
- `pZ`: The z of its centre.
- `pLength`: Its whole length, end to end; empty means 1.6.
- `pDiameter`: Its diameter; empty means 0.6.
- `pColor`: A colour; empty takes the next palette colour.

Returns: (through the result) the thing, or empty if it was refused.

```
b3kSpawnCapsule 2, 3, 0, 1.8, 0.7
```

See also: [`b3kPlayerMake`](#b3kplayermake)

### `b3kSpawnCylinder`

`b3kSpawnCylinder pX, pY, pZ, pHeight, pDiameter, pColor`

Make a cylinder standing along y.

- `pX`: The x of its centre.
- `pY`: The y of its centre.
- `pZ`: The z of its centre.
- `pHeight`: Its height; empty means 1.
- `pDiameter`: Its diameter; empty means 1.
- `pColor`: A colour; empty takes the next palette colour.

Returns: (through the result) the thing, or empty if it was refused.

Box3D builds it as a 16-sided solid; render3dxt draws it round.

```
b3kSpawnCylinder 0, 4, 0, 0.4, 1.2, "gold"   -- a coin
```

See also: [`b3kSpawnCone`](#b3kspawncone)

### `b3kSpawnCone`

`b3kSpawnCone pX, pY, pZ, pHeight, pDiameter, pColor`

Make a cone standing on its base along y.

- `pX`: The x of its centre.
- `pY`: The y of its centre.
- `pZ`: The z of its centre.
- `pHeight`: Its height; empty means 1.
- `pDiameter`: The diameter of its base; empty means 1.
- `pColor`: A colour; empty takes the next palette colour.

Returns: (through the result) the thing, or empty if it was refused.

```
b3kSpawnCone 0, 2, 0, 1.5, 1, "orange"   -- a traffic cone
```

See also: [`b3kSpawnCylinder`](#b3kspawncylinder)

### `b3kSpawnHull`

`b3kSpawnHull pX, pY, pZ, pPoints, pColor`

Make a solid from the tightest shape round some points.

- `pX`: The x of its place; the points are around it.
- `pY`: Its y.
- `pZ`: Its z.
- `pPoints`: The points, one "x,y,z" a line (or separated by semicolons, or one long comma list), relative to its place. At least 4, not all in one plane.
- `pColor`: A colour; empty takes the next palette colour.

Returns: (through the result) the thing, or empty if it was refused.

Box3D keeps at most 128 corners, so a rounded set of points is simplified. Both renderers draw exactly the solid that collides.

```
-- an eight-sided gem
b3kSpawnHull 0, 4, 0, "0,0.7,0" & cr & "0,-0.7,0" & cr & "0.5,0,0" & cr & "-0.5,0,0" & cr & "0,0,0.5" & cr & "0,0,-0.5"
```

See also: [`b3kSpawnModel`](#b3kspawnmodel)

### `b3kSpawnModel`

`b3kSpawnModel pX, pY, pZ, pSource, pScale, pColor`

Make a moving thing from a 3D model (Wavefront OBJ).

- `pX`: The x of its place.
- `pY`: Its y.
- `pZ`: Its z.
- `pSource`: The model: the full path of a .obj file, or the OBJ text itself.
- `pScale`: A size multiplier; empty means 1.
- `pColor`: A colour; empty keeps the model's own materials in render3dxt (and a light grey in box3dxt's picture).

Returns: (through the result) the thing, or empty if it was refused.

It collides as the convex hull of the model's points (a moving body cannot be hollow). render3dxt draws the model itself, with its materials and textures; box3dxt's renderer draws the hull.

```
b3kSpawnModel 0, 3, 0, specialFolderPath("resources") & "/models/rock.obj", 0.5
```

See also: [`b3kAddStaticModel`](#b3kaddstaticmodel), [`b3kSpawnHull`](#b3kspawnhull)

## Scenery: things that do not fall

### `b3kAddGround`

`b3kAddGround pSize, pY, pColorA, pColorB`

Lay a square checkered ground.

- `pSize`: Its width and depth in metres; empty means 30.
- `pY`: The height of its top surface; empty means 0.
- `pColorA`: The first checker colour; empty is a light grey.
- `pColorB`: The second checker colour; empty is a blue grey.

Returns: (through the result) the ground thing.

A static box one metre thick whose top is at pY, checkered in one metre squares by render3dxt (box3dxt's picture shows it in pColorB). There is one ground: a second call replaces the first. [`b3kAddWalls`](#b3kaddwalls) fences it.

```
b3kAddGround 40
```

See also: [`b3kAddWalls`](#b3kaddwalls), [`b3kKillFloor`](#b3kkillfloor)

### `b3kAddWalls`

`b3kAddWalls pHeight, pColor`

Fence the ground with four walls.

- `pHeight`: How tall they stand above the ground; empty means 1.
- `pColor`: A colour; empty is a slate grey.

Returns: (through the result) the four wall things, one a line.

```
b3kAddGround 20
b3kAddWalls 1.5
```

See also: [`b3kAddGround`](#b3kaddground)

### `b3kAddStaticBox`

`b3kAddStaticBox pX, pY, pZ, pW, pH, pD, pColor`

Make a box that never moves: a wall, a step, a table.

- `pX`: The x of its centre.
- `pY`: The y of its centre.
- `pZ`: The z of its centre.
- `pW`: Its width; empty means 1.
- `pH`: Its height; empty means 1.
- `pD`: Its depth; empty means 1.
- `pColor`: A colour; empty is a slate grey.

Returns: (through the result) the thing.

```
b3kAddStaticBox 0, 0.5, -4, 6, 1, 1   -- a low wall
```

See also: [`b3kAddRamp`](#b3kaddramp), [`b3kAddPlatform`](#b3kaddplatform)

### `b3kAddRamp`

`b3kAddRamp pX, pY, pZ, pW, pH, pD, pTilt, pYaw, pColor`

Make a tilted static box: a ramp or a slide.

- `pX`: The x of its centre.
- `pY`: The y of its centre.
- `pZ`: The z of its centre.
- `pW`: Its width (across the slope).
- `pH`: Its thickness.
- `pD`: Its length (down the slope).
- `pTilt`: Degrees it is tipped about its width; positive raises its far (-z) end.
- `pYaw`: Degrees it is turned round the vertical afterwards; empty means 0.
- `pColor`: A colour; empty is a sand colour.

Returns: (through the result) the thing.

```
b3kAddRamp 0, 1, 0, 3, 0.3, 6, 20
```

See also: [`b3kAddStaticBox`](#b3kaddstaticbox)

### `b3kAddStaticModel`

`b3kAddStaticModel pX, pY, pZ, pSource, pScale, pColor`

Make static scenery from a 3D model (Wavefront OBJ), hollows and all.

- `pX`: The x of its place.
- `pY`: Its y.
- `pZ`: Its z.
- `pSource`: The full path of a .obj file, or the OBJ text itself.
- `pScale`: A size multiplier; empty means 1.
- `pColor`: A colour; empty keeps the model's own materials in render3dxt.

Returns: (through the result) the thing, or empty if it was refused.

It collides as the model's own triangles, so an arch can be walked through and a bowl holds a ball. A triangle stops what meets its FRONT (its corners counter-clockwise as you look at it), which is how modelling programs write them.

```
b3kAddStaticModel 0, 0, 0, tFolder & "/castle.obj"
```

See also: [`b3kSpawnModel`](#b3kspawnmodel)

### `b3kAddPlatform`

`b3kAddPlatform pX, pY, pZ, pW, pH, pD, pColor`

Make a moving platform: a box that moves only as it is told.

- `pX`: The x of its centre.
- `pY`: The y of its centre.
- `pZ`: The z of its centre.
- `pW`: Its width; empty means 3.
- `pH`: Its thickness; empty means 0.4.
- `pD`: Its depth; empty means 3.
- `pColor`: A colour; empty is a teal.

Returns: (through the result) the thing.

A kinematic body: gravity and collisions do not move it, but it carries and pushes what stands on it. Move it with [`b3kGlideTo`](#b3kglideto) or [`b3kSetVelocity`](#b3ksetvelocity).

```
b3kAddPlatform 0, 1, 0, 3, 0.4, 3
put the result into tLift
b3kGlideTo tLift, 0, 4, 0, 2
```

See also: [`b3kGlideTo`](#b3kglideto), [`b3kSetType`](#b3ksettype)

### `b3kGlideTo`

`b3kGlideTo pThing, pX, pY, pZ, pSeconds`

Move a thing to a place over a time, by moving it.

- `pThing`: The thing; a platform ([`b3kAddPlatform`](#b3kaddplatform)) is what this is for.
- `pX`: The x to arrive at.
- `pY`: The y to arrive at.
- `pZ`: The z to arrive at.
- `pSeconds`: How long the trip takes; empty means 1.

The thing is given the speed that brings it there in time, and is stopped exactly there when the time is up, so what it carries rides along. It is meant for kinematic things; a dynamic one is pushed the same way, but gravity and collisions still act on it.

```
-- in your b3kFrame handler: a lift that rises and falls
if not b3kIsGliding(tLift) and b3kY(tLift) < 2 then b3kGlideTo tLift, 0, 4, 0, 2
if not b3kIsGliding(tLift) and b3kY(tLift) >= 2 then b3kGlideTo tLift, 0, 1, 0, 2
```

See also: [`b3kIsGliding`](#b3kisgliding), [`b3kAddPlatform`](#b3kaddplatform)

### `b3kIsGliding`

`b3kIsGliding(pThing)`

Report whether a thing is still on its way to a [`b3kGlideTo`](#b3kglideto) place.

- `pThing`: The thing.

Returns: true or false.

```
if not b3kIsGliding(tLift) then b3kGlideTo tLift, 0, 1, 0, 2
```

See also: [`b3kGlideTo`](#b3kglideto)

## Sensors: zones that notice what enters them

### `b3kAddSensorBox`

`b3kAddSensorBox pX, pY, pZ, pW, pH, pD`

Make a box-shaped zone that reports what enters and leaves it.

- `pX`: The x of its centre.
- `pY`: The y of its centre.
- `pZ`: The z of its centre.
- `pW`: Its width; empty means 1.
- `pH`: Its height; empty means 1.
- `pD`: Its depth; empty means 1.

Returns: (through the result) the sensor thing.

A sensor collides with nothing. render3dxt does not draw it (give it a look with [`b3kSetVisible`](#b3ksetvisible)); box3dxt's renderer draws every shape, so there it shows as a pale block. Messages go to [`b3kContactTarget`](#b3kcontacttarget).

```
b3kAddSensorBox 0, 1, -8, 2, 2, 2
put the result into tGoal
-- then, in your b3kSensorEnter pSensor, pVisitor handler:
if pSensor is tGoal and pVisitor is b3kPlayer() then answer "You made it!"
```

See also: [`b3kAddSensorBall`](#b3kaddsensorball), [`b3kContactTarget`](#b3kcontacttarget)

### `b3kAddSensorBall`

`b3kAddSensorBall pX, pY, pZ, pDiameter`

Make a ball-shaped zone that reports what enters and leaves it.

- `pX`: The x of its centre.
- `pY`: The y of its centre.
- `pZ`: The z of its centre.
- `pDiameter`: Its diameter; empty means 1.

Returns: (through the result) the sensor thing.

```
b3kAddSensorBall 3, 1, 3, 1.2
put the result into tCoinZone
```

See also: [`b3kAddSensorBox`](#b3kaddsensorbox)

## Look and material

### `b3kSetColor`

`b3kSetColor pThing, pColor`

Change a thing's colour.

- `pThing`: The thing.
- `pColor`: A colour name, "r,g,b" or "#rrggbb".

Replaces any checker or picture the thing wore.

```
b3kSetColor tCrate, "red"
```

See also: [`b3kColor`](#b3kcolor), [`b3kSetChecker`](#b3ksetchecker)

### `b3kColor`

`b3kColor(pThing)`

A thing's colour.

- `pThing`: The thing.

Returns: "r,g,b", or empty for no thing.

```
put b3kColor(tCrate) into tWas
```

See also: [`b3kSetColor`](#b3ksetcolor)

### `b3kSetChecker`

`b3kSetChecker pThing, pColorA, pColorB, pCells`

Give a thing a checkerboard look (render3dxt only).

- `pThing`: The thing.
- `pColorA`: The first colour.
- `pColorB`: The second colour.
- `pCells`: How many squares across each face; empty means 4.

box3dxt's renderer shows the first colour.

```
b3kSetChecker tBall, "white", "red", 8
```

See also: [`b3kSetColor`](#b3ksetcolor), [`b3kSetTexture`](#b3ksettexture)

### `b3kSetTexture`

`b3kSetTexture pThing, pPath`

Wrap a picture file round a thing (render3dxt only).

- `pThing`: The thing.
- `pPath`: The full path of a PNG, JPEG, BMP or TGA file.

Each face of a box shows the whole picture. box3dxt's renderer keeps the thing's colour.

```
b3kSetTexture tCrate, specialFolderPath("resources") & "/crate.png"
```

See also: [`b3kSetChecker`](#b3ksetchecker)

### `b3kSetVisible`

`b3kSetVisible pThing, pFlag`

Show or hide a thing's picture.

- `pThing`: The thing.
- `pFlag`: true to show it, false to hide it.

Only the picture: a hidden thing still collides. Hiding is render3dxt's; box3dxt's renderer draws every enabled body.

```
b3kSetVisible tGoalZone, true   -- see where the sensor is
```

See also: [`b3kIsVisible`](#b3kisvisible), [`b3kDisable`](#b3kdisable)

### `b3kIsVisible`

`b3kIsVisible(pThing)`

Report whether a thing's picture is shown.

- `pThing`: The thing.

Returns: true or false.

```
if not b3kIsVisible(tZone) then b3kSetVisible tZone, true
```

See also: [`b3kSetVisible`](#b3ksetvisible)

### `b3kSetBounce`

`b3kSetBounce pThing, pValue`

Set how bouncy a thing is.

- `pThing`: The thing.
- `pValue`: 0 (a thud) to 1 (bounces back as high).

```
b3kSetBounce tBall, 0.8
```

See also: [`b3kSetFriction`](#b3ksetfriction)

### `b3kSetFriction`

`b3kSetFriction pThing, pValue`

Set how grippy a thing is.

- `pThing`: The thing.
- `pValue`: 0 (ice) and up; 0.6 is ordinary.

```
b3kSetFriction tPuck, 0.02
```

See also: [`b3kSetBounce`](#b3ksetbounce)

### `b3kSetDensity`

`b3kSetDensity pThing, pValue`

Set how heavy a thing is for its size.

- `pThing`: The thing.
- `pValue`: Kilograms per cubic metre; the Kit's things start at 1.

```
b3kSetDensity tAnvil, 20
```

See also: [`b3kMass`](#b3kmass)

## Body settings

### `b3kSetType`

`b3kSetType pThing, pType`

Change how a thing moves.

- `pThing`: The thing.
- `pType`: "static" (never moves), "kinematic" (moves only as told) or "dynamic" (falls and collides).

```
b3kSetType tCrate, "static"   -- freeze it where it is
```

See also: [`b3kType`](#b3ktype)

### `b3kType`

`b3kType(pThing)`

How a thing moves.

- `pThing`: The thing.

Returns: "static", "kinematic" or "dynamic"; empty for no thing.

```
if b3kType(tHit) is "dynamic" then b3kPush tHit, 0, 3, 0
```

See also: [`b3kSetType`](#b3ksettype)

### `b3kSetGravityScale`

`b3kSetGravityScale pThing, pScale`

Scale how strongly gravity pulls one thing.

- `pThing`: The thing.
- `pScale`: 1 is normal, 0 floats, negative rises.

```
b3kSetGravityScale tBalloon, -0.2
```

See also: [`b3kSetGravity`](#b3ksetgravity)

### `b3kSetDamping`

`b3kSetDamping pThing, pLinear, pAngular`

Slow a thing down over time, like air or water.

- `pThing`: The thing.
- `pLinear`: How quickly moving slows; 0 is none, 1 is heavy.
- `pAngular`: How quickly spinning slows; empty leaves it alone.

```
b3kSetDamping tFeather, 2
```

See also: [`b3kSetGravityScale`](#b3ksetgravityscale)

### `b3kSetBullet`

`b3kSetBullet pThing, pFlag`

Make a fast thing check every step for what it might pass through.

- `pThing`: The thing.
- `pFlag`: true or false.

```
b3kSetBullet tShot, true
```

See also: [`b3kSetDamping`](#b3ksetdamping)

### `b3kKeepUpright`

`b3kKeepUpright pThing, pFlag`

Stop a thing from tipping over: it may move but not turn.

- `pThing`: The thing.
- `pFlag`: true keeps it upright; false lets it tumble again.

```
b3kKeepUpright tSnowman, true
```

See also: [`b3kPlayerMake`](#b3kplayermake)

### `b3kWake`

`b3kWake pThing`

Wake a sleeping thing.

- `pThing`: The thing.

Things at rest fall asleep to save time, and wake by themselves when touched or pushed.

```
b3kWake tCrate
```

See also: [`b3kIsAwake`](#b3kisawake)

### `b3kDisable`

`b3kDisable pThing`

Take a thing out of the world for now, keeping it.

- `pThing`: The thing.

A disabled thing does not collide, move or show; [`b3kEnable`](#b3kenable) brings it back where it was.

```
b3kDisable tDoor
```

See also: [`b3kEnable`](#b3kenable)

### `b3kEnable`

`b3kEnable pThing`

Bring back a thing [`b3kDisable`](#b3kdisable) took out.

- `pThing`: The thing.

```
b3kEnable tDoor
```

See also: [`b3kDisable`](#b3kdisable)

## Acting on things

### `b3kPush`

`b3kPush pThing, pDvx, pDvy, pDvz`

Change a thing's speed at once, whatever it weighs.

- `pThing`: The thing.
- `pDvx`: Metres a second to add along x.
- `pDvy`: Along y; positive is up.
- `pDvz`: Along z.

The kick that suits any size: the impulse is the thing's mass times the change. A kinematic thing has the change added to its velocity; a static one does not move.

```
b3kPush tBall, 0, 6, 0   -- a hop
```

See also: [`b3kImpulse`](#b3kimpulse), [`b3kSetVelocity`](#b3ksetvelocity)

### `b3kImpulse`

`b3kImpulse pThing, pIx, pIy, pIz`

Kick a thing at its centre.

- `pThing`: The thing.
- `pIx`: The impulse along x, in kilogram metres a second.
- `pIy`: Along y.
- `pIz`: Along z.

A heavy thing moves less than a light one; [`b3kPush`](#b3kpush) ignores weight.

```
b3kImpulse tCrate, 0, 5, 0
```

See also: [`b3kPush`](#b3kpush), [`b3kForce`](#b3kforce)

### `b3kForce`

`b3kForce pThing, pFx, pFy, pFz`

Push a thing steadily: call it every frame it should act.

- `pThing`: The thing.
- `pFx`: The force along x, in newtons.
- `pFy`: Along y.
- `pFz`: Along z.

```
-- in your b3kFrame handler:
if b3kKeyIsDown("space") then b3kForce tRocket, 0, 30, 0
```

See also: [`b3kImpulse`](#b3kimpulse), [`b3kTorque`](#b3ktorque)

### `b3kTorque`

`b3kTorque pThing, pTx, pTy, pTz`

Twist a thing steadily: call it every frame it should act.

- `pThing`: The thing.
- `pTx`: The torque about x, in newton metres.
- `pTy`: About y.
- `pTz`: About z.

```
b3kTorque tTop, 0, 2, 0
```

See also: [`b3kSetSpin`](#b3ksetspin)

### `b3kSetVelocity`

`b3kSetVelocity pThing, pVx, pVy, pVz`

Set a thing's speed and direction.

- `pThing`: The thing.
- `pVx`: Metres a second along x.
- `pVy`: Along y.
- `pVz`: Along z.

It wakes the thing: never set the velocity of something meant to rest every frame.

```
b3kSetVelocity tPuck, 4, 0, -2
```

See also: [`b3kPush`](#b3kpush), [`b3kVelocity`](#b3kvelocity)

### `b3kSetSpin`

`b3kSetSpin pThing, pWx, pWy, pWz`

Set how fast a thing turns.

- `pThing`: The thing.
- `pWx`: Degrees a second about x.
- `pWy`: About y.
- `pWz`: About z.

```
b3kSetSpin tCoin, 0, 180, 0
```

See also: [`b3kTorque`](#b3ktorque)

### `b3kMoveTo`

`b3kMoveTo pThing, pX, pY, pZ`

Put a thing somewhere else at once, at rest.

- `pThing`: The thing.
- `pX`: The x of its new centre.
- `pY`: Its y.
- `pZ`: Its z.

A teleport: its speed and spin are stopped and any [`b3kGlideTo`](#b3kglideto) is dropped. Use [`b3kGlideTo`](#b3kglideto) to move a platform so that it carries things.

```
b3kMoveTo b3kPlayer(), 0, 2, 0   -- back to the start
```

See also: [`b3kGlideTo`](#b3kglideto), [`b3kSetRotation`](#b3ksetrotation)

### `b3kSetRotation`

`b3kSetRotation pThing, pRx, pRy, pRz`

Turn a thing to a rotation given as three angles.

- `pThing`: The thing.
- `pRx`: Degrees about x.
- `pRy`: Degrees about y.
- `pRz`: Degrees about z.

```
b3kSetRotation tCrate, 0, 45, 0
```

See also: [`b3kTurnTo`](#b3kturnto), [`b3kRotation`](#b3krotation)

### `b3kTurnTo`

`b3kTurnTo pThing, pYaw`

Turn a thing to face a heading, upright.

- `pThing`: The thing.
- `pYaw`: Degrees round the vertical; 0 faces +z, 90 faces +x.

```
b3kTurnTo tGuard, b3kPlayerFacing()
```

See also: [`b3kYaw`](#b3kyaw), [`b3kSetRotation`](#b3ksetrotation)

### `b3kExplode`

`b3kExplode pX, pY, pZ, pRadius, pPower`

Blow things away from a point.

- `pX`: The x of the blast.
- `pY`: Its y.
- `pZ`: Its z.
- `pRadius`: How far it reaches at full strength, in metres; empty means 3.
- `pPower`: How hard it pushes; empty means 6.

```
b3kExplode 0, 0.5, 0, 4, 10
b3kCamShake 0.3, 300
```

See also: [`b3kOverlapSphere`](#b3koverlapsphere), [`b3kCamShake`](#b3kcamshake)

### `b3kRemove`

`b3kRemove pThing`

Remove a thing from the world and the picture.

- `pThing`: The thing.

Its joints go with it. A thing that is no longer there is ignored, so removing twice is harmless.

```
-- in your b3kSensorEnter pSensor, pVisitor handler:
if pSensor is tCoinZone then b3kRemove pSensor
```

See also: [`b3kClear`](#b3kclear)

## Reading things

### `b3kPosition`

`b3kPosition(pThing)`

Where a thing is.

- `pThing`: The thing.

Returns: "x,y,z" of its centre in metres; empty for no thing.

```
put b3kPosition(tBall) into tWhere
```

See also: [`b3kX`](#b3kx), [`b3kMoveTo`](#b3kmoveto)

### `b3kX`

`b3kX(pThing)`

A thing's x.

- `pThing`: The thing.

Returns: Metres; 0 for no thing.

```
if b3kX(tBall) > 10 then put "out" into tState
```

See also: [`b3kPosition`](#b3kposition)

### `b3kY`

`b3kY(pThing)`

A thing's height.

- `pThing`: The thing.

Returns: Metres; 0 for no thing.

```
if b3kY(b3kPlayer()) < -5 then b3kMoveTo b3kPlayer(), 0, 2, 0
```

See also: [`b3kPosition`](#b3kposition)

### `b3kZ`

`b3kZ(pThing)`

A thing's z.

- `pThing`: The thing.

Returns: Metres; 0 for no thing.

```
put b3kZ(tBall) into tDepth
```

See also: [`b3kPosition`](#b3kposition)

### `b3kVelocity`

`b3kVelocity(pThing)`

How a thing is moving.

- `pThing`: The thing.

Returns: "vx,vy,vz" in metres a second; empty for no thing.

```
put item 2 of b3kVelocity(tBall) into tFalling
```

See also: [`b3kSpeed`](#b3kspeed), [`b3kSetVelocity`](#b3ksetvelocity)

### `b3kSpeed`

`b3kSpeed(pThing)`

How fast a thing is moving.

- `pThing`: The thing.

Returns: Metres a second; 0 for no thing.

```
if b3kSpeed(tCar) > 20 then b3kSetDamping tCar, 0.5
```

See also: [`b3kVelocity`](#b3kvelocity)

### `b3kRotation`

`b3kRotation(pThing)`

A thing's rotation, as the three angles b3kSetRotation takes.

- `pThing`: The thing.

Returns: "rx,ry,rz" in degrees: turned about x first, then y, then z, as [`b3kSetRotation`](#b3ksetrotation) turns it. Empty for no thing.

ry runs from -90 to 90; rx and rz from -180 to 180. Standing straight up or down (ry at 90 or -90) the x and z turns are the same turn, and it is all given as rz.

```
put b3kRotation(tCrate) into tTurn
b3kSetRotation tOther, item 1 of tTurn, item 2 of tTurn, item 3 of tTurn
```

See also: [`b3kYaw`](#b3kyaw), [`b3kSetRotation`](#b3ksetrotation)

### `b3kYaw`

`b3kYaw(pThing)`

The heading a thing faces.

- `pThing`: The thing.

Returns: Degrees round the vertical, -180 to 180; 0 faces +z, 90 faces +x.

```
put b3kYaw(tCar) into tHeading
```

See also: [`b3kTurnTo`](#b3kturnto)

### `b3kMass`

`b3kMass(pThing)`

How heavy a thing is.

- `pThing`: The thing.

Returns: Kilograms; 0 for a static thing or no thing.

```
put b3kMass(tCrate) into tKg
```

See also: [`b3kSetDensity`](#b3ksetdensity)

### `b3kIsAwake`

`b3kIsAwake(pThing)`

Report whether a thing is awake (moving, or able to).

- `pThing`: The thing.

Returns: true or false.

```
if not b3kIsAwake(tTower) then put "settled" into tState
```

See also: [`b3kWake`](#b3kwake)

### `b3kKind`

`b3kKind(pThing)`

What kind of thing a thing is.

- `pThing`: The thing.

Returns: box, ball, capsule, cylinder, cone, hull, model, ground, static, ramp, scenery, platform or sensor; empty for no thing.

```
if b3kKind(tHit) is "ground" then put b3kHitPoint() into tTarget
```

See also: [`b3kIsThing`](#b3kisthing)

### `b3kIsThing`

`b3kIsThing(pValue)`

Report whether a value is a thing the Kit made and still has.

- `pValue`: Anything.

Returns: true or false.

```
if b3kIsThing(tTarget) then b3kPush tTarget, 0, 3, 0
```

See also: [`b3kKind`](#b3kkind)

### `b3kThings`

`b3kThings()`

Every thing there is.

Returns: One thing a line, oldest first.

```
put line -1 of b3kThings() into tNewest
```

See also: [`b3kThingCount`](#b3kthingcount)

### `b3kThingCount`

`b3kThingCount()`

How many things there are.

Returns: A whole number.

```
put b3kThingCount() && "things" into field "Count"
```

See also: [`b3kThings`](#b3kthings)

### `b3kDistance`

`b3kDistance(pThingA, pThingB)`

How far apart two things' centres are.

- `pThingA`: One thing.
- `pThingB`: The other.

Returns: Metres; empty when either is not a thing.

```
if b3kDistance(b3kPlayer(), tExit) < 1.5 then put "home" into tState
```

See also: [`b3kPosition`](#b3kposition)

### `b3kShapeOf`

`b3kShapeOf(pThing)`

The box3dxt shape of a thing, for raw b3Shape... calls.

- `pThing`: The thing.

Returns: The shape handle; empty for no thing.

```
b3ShapeSetRollingResistance b3kShapeOf(tBall), 0.05
```

See also: [`b3kWorld`](#b3kworld)

### `b3kName`

`b3kName pThing, pName`

Give a thing a name to find it by.

- `pThing`: The thing.
- `pName`: Any text; empty forgets its name.

```
b3kName tDoor, "door"
-- later
b3kRemove b3kThingNamed("door")
```

See also: [`b3kThingNamed`](#b3kthingnamed), [`b3kNameOf`](#b3knameof)

### `b3kNameOf`

`b3kNameOf(pThing)`

A thing's name.

- `pThing`: The thing.

Returns: Its name, or empty.

```
put b3kNameOf(tHit) into field "Picked"
```

See also: [`b3kName`](#b3kname)

### `b3kThingNamed`

`b3kThingNamed(pName)`

The thing with a name.

- `pName`: The name given by [`b3kName`](#b3kname).

Returns: The thing, or empty.

```
b3kPush b3kThingNamed("ball"), 0, 5, 0
```

See also: [`b3kName`](#b3kname)

## Joints: hinges, balls, welds, ropes and sliders between two things

### `b3kHinge`

`b3kHinge pA, pB, pX, pY, pZ, pAx, pAy, pAz`

Join two things with a hinge, or pin one to the world.

- `pA`: The thing that turns.
- `pB`: The other thing, or empty to pin pA to the world.
- `pX`: The x of the hinge point; empty means the centre of pA.
- `pY`: The y of the hinge point; empty means the centre of pA.
- `pZ`: The z of the hinge point; empty means the centre of pA.
- `pAx`: The x of the axis it turns about.
- `pAy`: The y of the axis.
- `pAz`: The z of the axis. An axis left empty or all zeros is 0, 0, 1: the hinge then turns in the x-y plane, the way the starting camera looks.

Returns: (through the result) the joint, or empty when either thing is missing or Box3D refused it ([`b3kLastError`](#b3klasterror) says why).

The two stay together at the point and turn only about the axis: a door, a wheel on an axle, a see-saw, a pendulum. [`b3kMotor`](#b3kmotor) drives it, [`b3kHingeLimit`](#b3khingelimit) stops it, [`b3kHingeAngle`](#b3khingeangle) reads it.

```
b3kSpawnBox 1, 3, 0, 2, 0.2, 1, "brown"
put the result into tDoor
b3kHinge tDoor, empty, 0, 3, 0, 0, 1, 0   -- a door turning about y at x = 0
put the result into tHinge
b3kHingeLimit tHinge, -90, 90
```

See also: [`b3kMotor`](#b3kmotor), [`b3kHingeLimit`](#b3khingelimit), [`b3kHingeAngle`](#b3khingeangle), [`b3kRemoveJoint`](#b3kremovejoint)

### `b3kBallJoint`

`b3kBallJoint pA, pB, pX, pY, pZ`

Join two things with a ball and socket, or hang one from the world.

- `pA`: The thing that swings.
- `pB`: The other thing, or empty to hang pA from the world.
- `pX`: The x of the socket; empty means the centre of pA.
- `pY`: The y of the socket; empty means the centre of pA.
- `pZ`: The z of the socket; empty means the centre of pA.

Returns: (through the result) the joint, or empty when either thing is missing or Box3D refused it.

The two stay together at the point and turn freely about it, every way: a shoulder, a chain link, a pendulum that can swing in a circle.

```
b3kSpawnBall 0, 2, 0, 0.6, "red"
put the result into tBob
b3kBallJoint tBob, empty, 0, 5, 0   -- swings round a point 3 m above it
```

See also: [`b3kHinge`](#b3khinge), [`b3kRope`](#b3krope), [`b3kRemoveJoint`](#b3kremovejoint)

### `b3kWeld`

`b3kWeld pA, pB`

Glue two things together, or one to the world where it is.

- `pA`: A thing.
- `pB`: The thing to glue to it, or empty to fix pA in place.

Returns: (through the result) the joint, or empty when either thing is missing or Box3D refused it.

The two keep the places and turns they had when welded and move as one. [`b3kRemoveJoint`](#b3kremovejoint) breaks the weld.

```
b3kWeld tCart, tCrate
```

See also: [`b3kRemoveJoint`](#b3kremovejoint), [`b3kHinge`](#b3khinge)

### `b3kRope`

`b3kRope pA, pB, pLength`

Tie two things together with a rope from centre to centre.

- `pA`: A thing.
- `pB`: The other thing.
- `pLength`: The rope's length in metres; empty means the distance between them now.

Returns: (through the result) the joint, or empty when either thing is missing or Box3D refused it.

A rope goes slack when the two come closer and stops them going further apart than its length. To hang something from the world, tie it to a static thing ([`b3kAddStaticBox`](#b3kaddstaticbox)).

```
b3kAddStaticBox 0, 6, 0, 0.4, 0.4, 0.4
put the result into tHook
b3kSpawnBall 1, 4, 0, 0.5
put the result into tBob
b3kRope tHook, tBob, 3
```

See also: [`b3kBallJoint`](#b3kballjoint), [`b3kRemoveJoint`](#b3kremovejoint)

### `b3kSlider`

`b3kSlider pA, pB, pAx, pAy, pAz`

Let a thing slide along a line, against another thing or the world.

- `pA`: The thing that slides.
- `pB`: The other thing, or empty to slide pA against the world.
- `pAx`: The x of the direction it slides.
- `pAy`: The y of the direction.
- `pAz`: The z of the direction. All empty or zero means straight up and down (0, 1, 0).

Returns: (through the result) the joint, or empty when either thing is missing or Box3D refused it.

The thing keeps its turn and moves only along the line through where it is now: a lift, a piston, a drawer. [`b3kMotor`](#b3kmotor) drives it (metres a second), [`b3kHingeLimit`](#b3khingelimit) stops it (metres) and [`b3kHingeAngle`](#b3khingeangle) reads how far it has gone.

```
b3kSpawnBox 0, 1, 0, 2, 0.3, 2, "teal"
put the result into tLift
b3kSlider tLift, empty, 0, 1, 0
put the result into tRail
b3kHingeLimit tRail, 0, 4      -- metres, for a slider
b3kMotor tRail, 1, 500         -- one metre a second, upwards
```

See also: [`b3kMotor`](#b3kmotor), [`b3kHingeLimit`](#b3khingelimit), [`b3kHingeAngle`](#b3khingeangle)

### `b3kMotor`

`b3kMotor pJoint, pSpeed, pMax`

Drive a hinge or a slider at a steady speed, or stop driving it.

- `pJoint`: A joint from [`b3kHinge`](#b3khinge) or [`b3kSlider`](#b3kslider).
- `pSpeed`: Degrees a second for a hinge, metres a second for a slider; empty turns the motor off. 0 holds it still, as a brake.
- `pMax`: The most torque (newton metres) or force (newtons) it may use; empty means 100, plenty for the Kit's things (a 1 m box weighs 1 kg).

The motor pushes as hard as it may to keep the speed, so a weak motor stalls under a load and a strong one does not. Give it no more than the job needs, because a limit is a little soft and a motor far stronger than the thing it turns pushes it some way past the limit. Other joints ignore it.

```
b3kMotor tWheel, 360          -- one turn a second
b3kMotor tWheel, empty        -- free again
```

See also: [`b3kHinge`](#b3khinge), [`b3kSlider`](#b3kslider), [`b3kHingeLimit`](#b3khingelimit)

### `b3kHingeLimit`

`b3kHingeLimit pJoint, pLow, pHigh`

Stop a hinge or a slider at two ends, or let it go free.

- `pJoint`: A joint from [`b3kHinge`](#b3khinge) or [`b3kSlider`](#b3kslider).
- `pLow`: The lowest angle in degrees (hinge) or position in metres (slider).
- `pHigh`: The highest. Both empty take the limit off.

Angles and positions count from where the two were when the joint was made. Swapped ends are put in order. Other joints ignore it.

```
b3kHingeLimit tDoor, -90, 90
b3kHingeLimit tLift, 0, 4
```

See also: [`b3kHingeAngle`](#b3khingeangle), [`b3kMotor`](#b3kmotor)

### `b3kHingeAngle`

`b3kHingeAngle(pJoint)`

How far a hinge has turned, or a slider has slid.

- `pJoint`: A joint from [`b3kHinge`](#b3khinge) or [`b3kSlider`](#b3kslider).

Returns: Degrees for a hinge, metres for a slider, counted from where the two were when it was made; 0 for any other joint or no joint.

```
put round(b3kHingeAngle(tDoor)) into field "Door"
```

See also: [`b3kHingeLimit`](#b3khingelimit), [`b3kHinge`](#b3khinge), [`b3kSlider`](#b3kslider)

### `b3kRemoveJoint`

`b3kRemoveJoint pJoint`

Take a joint away.

- `pJoint`: A joint from any of the Kit's joint commands, or from [`b3kNoCollide`](#b3knocollide).

The two things are woken and go their own ways. A joint that is already gone (its thing was removed, say) is ignored.

```
b3kRemoveJoint tWeld
```

See also: [`b3kHinge`](#b3khinge), [`b3kWeld`](#b3kweld)

### `b3kNoCollide`

`b3kNoCollide pA, pB`

Stop two things colliding with each other.

- `pA`: A thing.
- `pB`: Another thing.

Returns: (through the result) a joint that holds the rule; remove it with [`b3kRemoveJoint`](#b3kremovejoint). Empty when either thing is missing.

Everything else still collides with both. Taking the rule away does not push two things apart that already overlap: they meet again once one of them moves away and back.

```
b3kNoCollide tCar, tDriver
```

See also: [`b3kRemoveJoint`](#b3kremovejoint)

## Input (keyboard): one sample of the keys held, once a frame

### `b3kInputOn`

`b3kInputOn`

Start reading the keyboard once a frame.

Each frame the loop reads the keys held down and compares them with the frame before, so the key, action and axis questions answer from b3kFrame. It needs no focus and no key messages.

It also fills empty bindings: action "jump" (space), axis "moveX" (left, a then right, d), axis "moveY" (down, s then up, w) and axis "turn" (q then e), which turns the camera. Bindings you made are kept. [`b3kPlayerAttach`](#b3kplayerattach) turns input on for you.

```
b3kInputOn
if b3kKeyIsDown("space") then put "jumping" into field "State"
```

See also: [`b3kInputOff`](#b3kinputoff), [`b3kKeyIsDown`](#b3kkeyisdown), [`b3kBindAction`](#b3kbindaction), [`b3kAxis`](#b3kaxis)

### `b3kInputOff`

`b3kInputOff`

Stop reading the keyboard.

Every key reads as up afterwards. Bindings are kept.

```
b3kInputOff
```

See also: [`b3kInputOn`](#b3kinputon), [`b3kInputIsOn`](#b3kinputison)

### `b3kInputIsOn`

`b3kInputIsOn()`

Report whether the keyboard is being read.

Returns: true or false.

```
if not b3kInputIsOn() then b3kInputOn
```

See also: [`b3kInputOn`](#b3kinputon)

### `b3kInputInject`

`b3kInputInject pKeys`

Hold keys from script instead of the keyboard.

- `pKeys`: Key names or codes, separated by commas; empty holds none.

Until [`b3kInputInjectOff`](#b3kinputinjectoff), each frame reads this set instead of the keyboard, and pressed and released come from the usual comparison. For tests, replays and characters your script plays.

```
b3kInputInject "up,space"   -- forward and jump
b3kStepOnce
```

See also: [`b3kInputInjectOff`](#b3kinputinjectoff), [`b3kInputOn`](#b3kinputon)

### `b3kInputInjectOff`

`b3kInputInjectOff`

Go back to the real keyboard.

```
b3kInputInjectOff
```

See also: [`b3kInputInject`](#b3kinputinject)

### `b3kKeyIsDown`

`b3kKeyIsDown(pKey)`

Report whether a key is held this frame.

- `pKey`: A key name (left, right, up, down, space, return, escape, tab, shift, control, alt, backspace, delete), one character, or a key code.

Returns: true or false.

Needs [`b3kInputOn`](#b3kinputon); ask it in b3kFrame.

```
if b3kKeyIsDown("shift") then b3kPlayerSet "moveSpeed", 9
```

See also: [`b3kKeyPressed`](#b3kkeypressed), [`b3kKeyReleased`](#b3kkeyreleased), [`b3kInputOn`](#b3kinputon)

### `b3kKeyPressed`

`b3kKeyPressed(pKey)`

Report whether a key went down this frame.

- `pKey`: A key name, one character, or a key code.

Returns: true only on the frame the key went down.

```
if b3kKeyPressed("r") then b3kPlayerRespawn 0, 2, 0
```

See also: [`b3kKeyIsDown`](#b3kkeyisdown), [`b3kKeyReleased`](#b3kkeyreleased)

### `b3kKeyReleased`

`b3kKeyReleased(pKey)`

Report whether a key came up this frame.

- `pKey`: A key name, one character, or a key code.

Returns: true only on the frame the key came up.

```
if b3kKeyReleased("space") then put false into tCharging
```

See also: [`b3kKeyIsDown`](#b3kkeyisdown), [`b3kKeyPressed`](#b3kkeypressed)

### `b3kKeysHeld`

`b3kKeysHeld()`

Every key held this frame, by name.

Returns: The names separated by spaces, or empty.

```
put b3kKeysHeld() into field "Keys"
```

See also: [`b3kKeyIsDown`](#b3kkeyisdown)

### `b3kBindAction`

`b3kBindAction pName, pKeyList`

Name a set of keys as one action.

- `pName`: The action's name, such as "fire".
- `pKeyList`: Key names separated by commas, such as "x,control".

Any of the keys counts, and pressed and released treat the set as one key. The names are turned into key codes once, here.

```
b3kBindAction "fire", "x,control"
if b3kActionPressed("fire") then b3kPush tCannonBall, 0, 0, -20
```

See also: [`b3kActionIsDown`](#b3kactionisdown), [`b3kActionPressed`](#b3kactionpressed), [`b3kBindAxis`](#b3kbindaxis)

### `b3kActionIsDown`

`b3kActionIsDown(pName)`

Report whether any key of an action is held.

- `pName`: The action's name.

Returns: true or false; false for an action never bound.

```
if b3kActionIsDown("fire") then add b3kFrameMS() to tCharge
```

See also: [`b3kBindAction`](#b3kbindaction), [`b3kActionPressed`](#b3kactionpressed)

### `b3kActionPressed`

`b3kActionPressed(pName)`

Report whether an action started this frame.

- `pName`: The action's name.

Returns: true on the frame the first of its keys went down.

```
if b3kActionPressed("jump") then put "up!" into field "Log"
```

See also: [`b3kBindAction`](#b3kbindaction), [`b3kActionReleased`](#b3kactionreleased)

### `b3kActionReleased`

`b3kActionReleased(pName)`

Report whether an action ended this frame.

- `pName`: The action's name.

Returns: true on the frame the last of its keys came up.

```
if b3kActionReleased("fire") then b3kPush tBall, 0, tCharge / 100, -10
```

See also: [`b3kBindAction`](#b3kbindaction), [`b3kActionPressed`](#b3kactionpressed)

### `b3kBindAxis`

`b3kBindAxis pName, pNegKeys, pPosKeys`

Make a -1, 0, +1 axis from two sets of keys.

- `pName`: The axis's name, such as "moveX".
- `pNegKeys`: The keys for -1, separated by commas.
- `pPosKeys`: The keys for +1.

The player walks on "moveX" (sideways) and "moveY" (forward), and the camera turns on "turn". Rebind them to change the keys.

```
b3kBindAxis "moveY", "down,s", "up,w"
```

See also: [`b3kAxis`](#b3kaxis), [`b3kBindAction`](#b3kbindaction)

### `b3kAxis`

`b3kAxis(pName)`

Read an axis.

- `pName`: The axis's name.

Returns: -1, 0 or 1. Both ends held, or neither, is 0.

```
b3kSetSpin tTurret, 0, b3kAxis("aim") * 90, 0
```

See also: [`b3kBindAxis`](#b3kbindaxis)

## The player: one character the keys steer, relative to the camera

### `b3kPlayerMake`

`b3kPlayerMake pX, pY, pZ, pKind, pColor`

Make a player in one call: a thing the keys walk about.

- `pX`: The x where it stands.
- `pY`: The y of its centre.
- `pZ`: The z where it stands.
- `pKind`: "capsule" (1.6 m tall, the default), "ball" (a 0.8 m ball that rolls) or "box" (0.7 by 1.4 by 0.7 m).
- `pColor`: A colour; empty takes the next palette colour.

Returns: (through the result) the player's thing, or empty when there is no world.

It spawns the shape, makes it the player with [`b3kPlayerAttach`](#b3kplayerattach) and points the camera at it with [`b3kCamFollow`](#b3kcamfollow). Arrows or WASD walk, space jumps, Q and E turn the camera; forward is away from the camera.

```
b3kQuickStart
b3kPlayerMake 0, 1, 0
put the result into tHero
```

See also: [`b3kPlayerAttach`](#b3kplayerattach), [`b3kPlayerSet`](#b3kplayerset), [`b3kPlayer`](#b3kplayer)

### `b3kPlayerAttach`

`b3kPlayerAttach pThing, pMode`

Make a thing you already have the player.

- `pThing`: A moving (dynamic) thing.
- `pMode`: "walk" keeps it upright and turns it to face where it goes; "roll" leaves it free to roll. Empty means roll for a ball, walk for the rest.

Returns: (through the result) the thing, or empty when it is not a moving thing.

The thing stops bouncing, never falls asleep and, walking, slides on walls (friction 0.2) and cannot tip over. Input is turned on. There is one player, so attaching another lets the first go, as [`b3kPlayerRemove`](#b3kplayerremove) would.

```
b3kSpawnCylinder 0, 1, 0, 1.2, 0.8, "gold"
put the result into tRobot
b3kPlayerAttach tRobot
```

See also: [`b3kPlayerMake`](#b3kplayermake), [`b3kPlayerRemove`](#b3kplayerremove), [`b3kPlayerSet`](#b3kplayerset)

### `b3kPlayerRemove`

`b3kPlayerRemove`

Let the player go: the thing stays, the keys stop steering it.

The thing gets back its material, its turning and its sleep, and the knobs go back to their defaults. Remove the thing itself with [`b3kRemove`](#b3kremove).

```
b3kPlayerRemove
```

See also: [`b3kPlayerAttach`](#b3kplayerattach), [`b3kRemove`](#b3kremove)

### `b3kPlayerSet`

`b3kPlayerSet pKey, pValue`

Set one of the player's knobs.

- `pKey`: The knob (case does not matter): moveSpeed, accel, airAccel, jumpSpeed, jumpCut, airJumps, coyoteMs, bufferMs, maxSlopeDeg, turnSpeed, maxFall or carry. Any other name is kept for your own use.
- `pValue`: The new value; empty puts the default back.

The defaults: moveSpeed 5 (metres a second), accel 40 and airAccel 12 (m/s^2 toward the wanted speed, on the ground and in the air), jumpSpeed 5.5 (m/s up: about 1.5 m high), jumpCut 0.5 (rising speed kept when jump is let go early; 1 = always full height), airJumps 0, coyoteMs 120 (a jump still counts this long after walking off an edge), bufferMs 120 (a jump pressed this long before landing still happens), maxSlopeDeg 50 (steeper is a wall, not ground), turnSpeed 720 (degrees a second the player turns to face its way), maxFall 40 (m/s) and carry 1 (ride moving platforms; 0 not). A change takes effect from the next frame. [`b3kClear`](#b3kclear) keeps the knobs; [`b3kTeardown`](#b3kteardown) and [`b3kPlayerRemove`](#b3kplayerremove) put the defaults back.

```
b3kPlayerSet "moveSpeed", 7
b3kPlayerSet "airJumps", 1     -- a double jump
```

See also: [`b3kPlayerGet`](#b3kplayerget), [`b3kPlayerMake`](#b3kplayermake)

### `b3kPlayerGet`

`b3kPlayerGet(pKey)`

Read one of the player's knobs.

- `pKey`: The knob's name (case does not matter).

Returns: Its value, or its default when it was never set. A knob of the controller set to something not a number reads as its default.

```
put b3kPlayerGet("jumpSpeed") into tJump
```

See also: [`b3kPlayerSet`](#b3kplayerset)

### `b3kPlayer`

`b3kPlayer()`

The player's thing.

Returns: The thing, or empty when there is no player.

```
-- in your b3kContact pA, pB handler:
if pA is b3kPlayer() or pB is b3kPlayer() then add 1 to tBumps
```

See also: [`b3kPlayerMake`](#b3kplayermake), [`b3kPlayerAttach`](#b3kplayerattach)

### `b3kPlayerOnGround`

`b3kPlayerOnGround()`

Report whether the player stands on something.

Returns: true when ground (anything no steeper than maxSlopeDeg) is under its feet this frame.

```
if not b3kPlayerOnGround() then put "in the air" into field "State"
```

See also: [`b3kPlayerJump`](#b3kplayerjump), [`b3kPlayerSet`](#b3kplayerset)

### `b3kPlayerFacing`

`b3kPlayerFacing()`

Which way the player faces.

Returns: Degrees round the vertical: 0 faces +z, 90 faces +x.

A walking player turns to face the way it goes; a rolling one keeps the way it last went.

```
put b3kPlayerFacing() into tYaw
```

See also: [`b3kYaw`](#b3kyaw), [`b3kPlayerMake`](#b3kplayermake)

### `b3kPlayerJump`

`b3kPlayerJump pSpeed`

Make the player jump, whether or not it stands on anything.

- `pSpeed`: The upward speed in m/s; empty means the jumpSpeed knob.

For springs, trampolines and power-ups: your script decides when it is allowed. Letting go of jump does not cut it short.

```
-- in your b3kSensorEnter pSensor, pVisitor handler: a spring pad
if pSensor is tSpring and pVisitor is b3kPlayer() then b3kPlayerJump 12
```

See also: [`b3kPlayerOnGround`](#b3kplayeronground), [`b3kPlayerSet`](#b3kplayerset)

### `b3kPlayerControl`

`b3kPlayerControl pFlag`

Turn the keys' control of the player on or off.

- `pFlag`: false to stop steering (for a cut scene); true to steer again.

While off, the player keeps its ground check and its fall limit but the Kit writes nothing else to it.

```
b3kPlayerControl false
b3kGlideTo b3kPlayer(), 0, 1, -10, 3
```

See also: [`b3kPlayerSteer`](#b3kplayersteer), [`b3kPlayerMake`](#b3kplayermake)

### `b3kPlayerSteer`

`b3kPlayerSteer pX, pY`

Steer the player from script instead of the keys.

- `pX`: Sideways, -1 (left) to 1 (right), as the camera sees it.
- `pY`: Forward, -1 (toward the camera) to 1 (away). Both empty give the keys back.

For on-screen buttons, touch screens and players your script drives. A jump still comes from the jump action or [`b3kPlayerJump`](#b3kplayerjump).

```
b3kPlayerSteer 0, 1           -- in a "forward" button's mouseDown
b3kPlayerSteer empty, empty   -- and in its mouseUp: the keys again
```

See also: [`b3kPlayerControl`](#b3kplayercontrol), [`b3kAxis`](#b3kaxis)

### `b3kPlayerRespawn`

`b3kPlayerRespawn pX, pY, pZ`

Put the player somewhere, still, standing and ready.

- `pX`: The new x; not a number keeps the current x.
- `pY`: The new y of its centre; not a number keeps the current y.
- `pZ`: The new z; not a number keeps the current z.

It stops, the jump in flight and any buffered jump are forgotten, the air jumps are refilled and steering is on again.

```
-- in your b3kFell pThing handler:
if pThing is b3kPlayer() then b3kPlayerRespawn 0, 2, 0
```

See also: [`b3kMoveTo`](#b3kmoveto), [`b3kKillFloor`](#b3kkillfloor)
