-- =====================================================================
-- box2dxt-kit.livecodescript   /   "Box2Dxt Kit"  (b2k...)
--
-- A friendly, pure-xTalk toolkit over the box2dxt extension. You work in
-- PIXELS, SCREEN coordinates and DEGREES; the kit converts to Box2D's
-- metres / radians / y-up for you, runs the world, and moves your controls.
-- Runs in OpenXTalk (OXT); compatible with LiveCode 9.6.3+.
-- Requires the box2dxt extension loaded (put b2Version() should return 4).
--
-- =====================  60-SECOND START  =============================
--   on openCard
--      b2kQuickStart            -- world + gravity + walls around the card + go
--      b2kSpawnBall 200,80, 50               -- create + drop a ball
--      b2kSpawnBox 260,80, 60,40, "orange"   -- (read `the result` for the ref)
--      b2kContactTarget the long id of me    -- (optional) collision messages
--   end openCard
--   on mouseDown ; get b2kGrab(the mouseH,the mouseV) ; end mouseDown
--   on mouseUp   ; b2kRelease ; end mouseUp
--   on closeCard ; b2kStop ; end closeCard
--
-- =====================  CHEAT SHEET  ================================
-- WORLD   b2kSetup [gx,gy] / b2kQuickStart [gy] / b2kStart / b2kStop /
--         b2kTeardown / b2kAddWalls / b2kWall x1,y1,x2,y2 / b2kClear /
--         b2kPause / b2kResume / b2kIsRunning() / b2kKillFloor y
--         (movers below y are removed; "b2kFell ctrl" precedes each)
-- CONFIG  b2kSetScale px / b2kSetOrigin x,y / b2kSetGravity gx,gy /
--         b2kSetSubsteps n / b2kContactTarget obj / b2kFrameTarget obj /
--         b2kEnableSleeping flag / b2kEnableContinuous flag
-- ATTACH  b2kAddBox ctrl[,dyn] / b2kAddBall ctrl[,dyn] / b2kAddCapsule ctrl[,dyn]
--         b2kAddPolygon ctrl[,dyn] / b2kAddStatic ctrl / b2kAddGround [screenY]
-- SPAWN   b2kSpawnBox x,y,w,h[,color] / b2kSpawnBall x,y,diam[,color] /
--         b2kSpawnCapsule x,y,len,thick[,color]                       (-> control)
-- MATERIAL b2kSetBounce ctrl,0..1 / b2kSetFriction ctrl,0..1 / b2kSetDensity ctrl,d
-- BODY    b2kSetBullet ctrl,flag / b2kSetFixedRotation ctrl,flag /
--         b2kSetGravityScale ctrl,s / b2kSetDamping ctrl,lin[,ang] / b2kWake ctrl /
--         b2kSetType ctrl,name / b2kSetStatic/Dynamic/Kinematic ctrl /
--         b2kEnable/Disable ctrl / b2kSetSleepEnabled ctrl,flag
-- ACT     b2kPush ctrl,dvx,dvy / b2kImpulse ctrl,ix,iy / b2kForce ctrl,fx,fy /
--         b2kSetVelocity ctrl,vx,vy / b2kSpin ctrl,deg/s / b2kSpinBy ctrl,deg/s /
--         b2kTorque ctrl,t / b2kAngularImpulse ctrl,imp / b2kMoveTo ctrl,x,y[,deg] /
--         b2kExplode x,y[,radius][,power] / b2kRemove ctrl
-- GET     b2kBodyOf(ctrl) / b2kPosition(ctrl) / b2kWorldCenter(ctrl) / b2kVelocity(ctrl) /
--         b2kSpeed(ctrl) / b2kAngle(ctrl) / b2kMass(ctrl) / b2kBodyType(ctrl) /
--         b2kGravityScale(ctrl) / b2kDamping(ctrl) / b2kIsAwake(ctrl) / b2kControlAt(x,y) /
--         b2kControlContains(ctrl,x,y) / b2kBodyCount() / b2kAwakeCount() /
--         b2kToWorldX/Y(px) / b2kToScreenX/Y(m) /
--         b2kRayHit(x1,y1,x2,y2) + b2kRayHitX/Y() / b2kRayHitNormalX/Y() / b2kRayDist()
-- JOINTS  b2kHinge ctrlA,ctrlB,x,y / b2kWeld ctrlA,ctrlB / b2kRope ctrlA,ctrlB[,len]
--         b2kSlider ctrlA,ctrlB,axisDeg / b2kWheel chassis,wheel,x,y[,axisDeg]
--         b2kMotor j,degPerSec[,maxTorque] / b2kSliderMotor j,pxPerSec[,maxForce] /
--         b2kWheelMotor j,degPerSec[,maxTorque] / b2kRemoveJoint j
-- JOINT+  b2kHingeLimit j,loDeg,hiDeg / b2kHingeAngle(j) / b2kSliderLimit j,loPx,hiPx /
--         b2kSliderPos(j) / b2kRopeRange j,minPx,maxPx / b2kRopeLength(j) /
--         b2kSpring j,hz[,damp] / b2kWeldSpring j,hz[,damp] / b2kWheelSpring j,hz[,damp]
-- DRAG    b2kGrab(x,y) -> control / b2kRelease
-- INPUT   b2kInputOn/Off / b2kKeyIsDown(k) / b2kKeyPressed/Released(k) /
--         b2kInputInject keys / b2kInputInjectOff (scripted keys: tests/replays) /
--         b2kKeysHeld() / b2kBindAction name,keys / b2kActionIsDown/Pressed/
--         Released(name) / b2kBindAxis name,negKeys,posKeys / b2kAxis(name) /
--         b2kFrameMS()   (poll-based: arm b2kInputOn, read from on b2kFrame)
-- SPRITE  b2kSheetLoad name,path,fw,fh[,n,margin,gap] / b2kSheetLoadAtlas name,png[,xml] /
--         b2kSheetFromImage name,img,fw,fh[,n,margin,gap] / b2kSheetFrames(name) /
--         b2kSheetAddFrame sheet,frame,x,y,w,h (no-XML packed sheets; fw/fh 0 = no grid) /
--         b2kSheetFrameNames(name) / b2kSheetHasFrame(name,frame) /
--         b2kSheetScale name,factor / b2kSheetFrameSize(name,frame) /
--         b2kAnimDef sheet,anim,frames,fps[,loop] / b2kSpriteNew sheet[,frame,x,y] /
--         b2kSpriteFromGIF path[,x,y] / b2kSpritePlay spr,anim[,restart] /
--         b2kSpriteStop spr / b2kSpriteSetFrame spr,f / b2kSpriteFlipH spr,flag /
--         b2kSpriteFPS spr,fps / b2kSpriteOnFinish spr,msg /
--         b2kSpriteBind spr,bodyCtrl[,dx,dy] / b2kSpriteRemove spr
-- PLAYER  b2kPlayerMake x,y,w,h[,sheet] / b2kPlayerAttach ctrl /
--         b2kPlayerAnims idle,run,jump,fall[,land,duck,climb,hurt,swim] /
--         b2kPlayerSet key,value / b2kPlayerGet(key) / b2kPlayerOnGround() /
--         b2kPlayerState() (idle|run|jump|fall|land|duck|climb|hurt|swim) /
--         b2kPlayerFacing() / b2kPlayerJump [speed] / b2kPlayerControl flag /
--         b2kPlayerAddLadder x1,y1,x2,y2 / b2kPlayerAddWater x1,y1,x2,y2 /
--         b2kPlayerHurt [fromX] /
--         b2kPlayerHurtIs() (true through knockback + mercy window) /
--         b2kPlayer() / b2kPlayerSprite() / b2kPlayerRemove
--         (drives axes "moveX"/"moveY" + action "jump"; rebind to remap.
--         DOWN ducks / DOWN+JUMP on a one-way chain drops through /
--         UP/DOWN in a ladder zone climbs / JUMP exits a climb /
--         in a water zone UP/DOWN swim, JUMP strokes (repeatable))
-- CAMERA  b2kCamOn [rect] / b2kCamOff / b2kCamFollow ctrl[,lerp] / b2kCamUnfollow /
--         b2kCamDeadzone w,h / b2kCamBounds x1,y1,x2,y2 / b2kCamGoto x,y /
--         b2kCamPos() / b2kCamShake amp,ms / b2kCamMouseX/Y() / b2kCamGroup() /
--         b2kCamAdopt ctrl   (world px == control locs; spawns auto-join the view)
-- AUDIO   b2kSoundLoad name,path / b2kToneMake name,freqs,msPerNote[,vol,shape] /
--         b2kSound name / b2kSoundLoop name / b2kSoundStop / b2kSoundMute flag /
--         b2kSoundMuted() / b2kSoundVolume pct / b2kSoundIsLoaded(name) /
--         b2kSoundStatus()  (audioClips: one at a time; b2kToneMake = no asset files)
-- EVENTS  on b2kContact pCtrlA,pCtrlB / on b2kEndContact pCtrlA,pCtrlB
--         (long ids; empty for walls/ground) / on b2kFrame  (once per frame)
--         poll instead: b2kContactCount()+b2kContactA/B(i) / b2kEndContactCount()+...
-- SENSOR  b2kAddSensor ctrl[,shape] / on b2kSensorEnter pSensor,pVisitor /
--         on b2kSensorExit pSensor,pVisitor / b2kSensorCount()+EnterSensor/Visitor(i)
-- FILTER  b2kDefineLayer name / b2kSetCategory ctrl,layers / b2kSetMask ctrl,layers /
--         b2kSetCollisionGroup ctrl,n / b2kNoCollide ctrlA,ctrlB
-- TERRAIN b2kChain pointList[,loop] / b2kSmoothGround pointList  (>=4 screen
--         points; chains carry the reserved "oneway" layer, bit 2^31)
-- QUERY+  b2kOverlap x1,y1,x2,y2 / b2kOverlapMoving x1,y1,x2,y2 (presence:
--         statics filtered out) / b2kOverlapCircle x,y,r / b2kRayHitAll x1,y1,x2,y2
-- MOTOR   b2kMotorTo mover,ref,dxPx,dyPx,deg[,maxF,maxT] / b2kExplode (native blast)
-- TUNE    b2kSetRestitutionThreshold px/s / b2kSetContactTuning hz,damp,pushPx /
--         b2kSetJointTuning hz,damp / b2kSetMaxSpeed px/s / b2kEnableWarmStarting f /
--         b2kProfile() / b2kAwakeBodyCount()
--
-- Tips: pass controls by reference (the long id of ... is safest). Keep moving
-- objects a sensible on-screen size (default scale 40 px/m, so ~4-400 px).
-- Graphic boxes/polygons and dynamic images rotate; buttons/fields/etc follow
-- position upright (their rotation is locked so the sim matches the render).
-- =====================================================================

local sWorld, sRunning, sPaused, sGen
local sScale, sOriginX, sOriginY
local sAccum, sLast, sSub
local sBody          -- ctrlRef     -> body handle
local sCtrl          -- body handle -> ctrlRef
local sShapeH        -- ctrlRef     -> shape handle (for material edits)
local sRender        -- ctrlRef     -> "poly" | "ball" | "image" | "loc"
local sVerts         -- ctrlRef     -> local polygon verts (metres) for "poly"
local sRad           -- ctrlRef     -> radius (metres) for "ball"
local sImgAngle      -- ctrlRef     -> last applied angle (deg) for "image"
local sStatic        -- ctrlRef     -> true for bodies that never move
local sSpawned       -- ctrlRef     -> true if the kit created the control
local sSensor        -- ctrlRef     -> true for sensor (non-solid trigger) bodies
local sLayers        -- collision-layer name -> bit value
local sNextBit       -- next free collision-layer bit
local sDragJoint, sDragAnchor, sDragging
local sContactObj    -- object that receives b2kContact messages
local sFrameObj      -- object that receives an on b2kFrame message each frame
local sRayX, sRayY   -- last b2kRayHit point (screen pixels)
local sRayNX, sRayNY -- last b2kRayHit surface normal (screen-oriented)
local sRayDist       -- last b2kRayHit distance from the ray start (pixels)
local sRayBodyH      -- last b2kRayHit BODY HANDLE (already fetched for the
                     -- control lookup; stashed so the player's ground probe
                     -- can classify the hit with zero extra FFI calls)
local sOneWayBody    -- body handle -> true for one-way chain bodies (b2kChain)
local sNeedFullSync  -- true when a script-side transform/type edit bypassed move events
local sEvtCN, sEvtCA, sEvtCB -- begin-contacts buffered THIS FRAME (body handles)
local sEvtEN, sEvtEA, sEvtEB -- end-contacts buffered this frame
local sEvtSN, sEvtSS, sEvtSV -- sensor enters this frame (sensor, visitor)
local sEvtXN, sEvtXS, sEvtXV -- sensor exits this frame
local sKillY         -- kill floor: screen y below which dynamic bodies are removed
local sDrawKey       -- ctrlRef -> last rendered pixel/angle key; avoids redundant redraws
local sInputOn       -- true while the per-frame keyboard sample is armed
local sInjectOn      -- true = the sample comes from sInjectKeys, not the keyboard
local sInjectKeys    -- injected keycode list (tests, replays, cutscene ghosts)
local sKeysNow       -- comma-wrapped keycode set held this frame (",65361,32,")
local sKeysPrev      -- last frame's set; pressed/released edges are the diff
local sKeyActions    -- action name -> bound key list ("jump" -> "space,up,w")
local sAxisNeg       -- axis name -> negative-direction key list
local sAxisPos       -- axis name -> positive-direction key list
local sKeyActionsC   -- action name -> RESOLVED keycode list (bind-time cache)
local sAxisNegC      -- axis name -> resolved negative keycodes
local sAxisPosC      -- axis name -> resolved positive keycodes
local sFrameMS       -- real elapsed ms folded into the last frame (b2kFrameMS)
local sSheetSrc      -- sheet -> long id of its hidden source image
local sSheetOwned    -- sheet -> true when the Kit created the source image
local sSheetRegion   -- sheet -> frame key -> "x,y,w,h" region (source px)
local sSheetKeys     -- sheet -> CR list of frame keys, definition order
local sSheetIcon     -- sheet -> frame key -> sliced frame image id (lazy)
local sSheetFlip     -- sheet -> frame key -> mirrored image id (lazy)
local sSheetData     -- sheet -> cached source imageData (freed on teardown)
local sSheetAlpha    -- sheet -> cached source alphaData
local sSheetScale    -- sheet -> display scale factor (default 1; engine-resampled at slice time)
local sSheetPath     -- sheet -> its source path/ref (the idempotent-reload + reuse key)
local sSheetKeep     -- true = sheets survive b2kTeardown (b2kSheetPersist); assets, like sounds
local sAnimList      -- "sheet|anim" -> CR list of frame keys
local sAnimFPS       -- "sheet|anim" -> frames per second
local sAnimLoop      -- "sheet|anim" -> true/false
local sSprRefs       -- CR list of every live sprite control
local sSprLive       -- ...the subset the tick must service (bound/playing)
local sSprLiveDirty  -- true -> rebuild sSprLive from sSprRefs next tick
local sSprSheet, sSprKind, sSprAnim, sSprStep, sSprNextMS
local sSprFPS, sSprFPSOver, sSprFlip, sSprMsg, sSprFrameKey, sSprIconNow
local sSprBind, sSprBindDX, sSprBindDY, sSprLastLoc
local sCamGroup      -- viewport group long id while the camera is on
local sCamFollow     -- control the camera tracks (empty = manual)
local sCamLerp       -- follow smoothing 0..1 (1 = snap)
local sCamDZW, sCamDZH -- deadzone box in px (0 = always centre)
local sCamB1X, sCamB1Y, sCamB2X, sCamB2Y -- world bounds (sCamB1X empty = none)
local sCamX, sCamY   -- current view centre (world px)
local sCamShakeAmp, sCamShakeEnd
local sCamLastH, sCamLastV -- last written scroll (skip redundant sets)
local sCamNote       -- empty = healthy; else why the camera is degraded
local sCamLocVisual  -- true when this engine reports grouped locs SCROLL-ADJUSTED
local sCamCurH, sCamCurV -- the scroll actually applied this frame (cached)
local sInCam         -- ctrlRef -> true when the Kit placed it inside the viewport
local sPlayRef       -- the player's control (empty = no player controller)
local sPlayArt       -- the sprite whose anims the controller drives
local sPlayTune      -- tuning key -> value (b2kPlayerSet; defaults fill gaps)
local sPlayAnims     -- state -> animation name (idle/run/jump/fall/land/duck/climb/hurt)
local sPlayState     -- idle | run | jump | fall | land | duck | climb | hurt
                     -- (land lasts one tick; a drop-through renders as fall)
local sPlayFacing    -- 1 right / -1 left (last horizontal intent)
local sPlayGrounded  -- this frame's ray-probe verdict
local sPlayGroundMS  -- when last grounded (the coyote window)
local sPlayPressMS   -- when jump was last pressed (the buffer window)
local sPlayJumping   -- a controller jump is still ascending (cut-eligible)
local sPlayControl   -- false = observe only: no velocity or anim writes
local sPlayOwnBody   -- true when the controller created the body
local sPlayHalfW, sPlayHalfH -- capsule half-extents in px (probe geometry)
local sPlayAnimNow   -- last animation written (redundancy suppression)
local sPlayFlipNow   -- last flip written
local sPlayHoldMS    -- suppress anim switches until then (land flourish)
-- hot-path caches (b2kPlayerTuneCache): the tick runs every frame, so
-- the knobs resolve at SET time, not per use
local sPlayMoveSpd, sPlayAccelG, sPlayAccelA, sPlayJumpSpd, sPlayJumpCut
local sPlayCoyote, sPlayBuffer, sPlayMaxFall, sPlayCosSlope
local sPlayDropMS, sPlayClimbSpd                       -- Wave 2 caches...
local sPlayHurtPopX, sPlayHurtPopY, sPlayHurtMS, sPlayInvulnMS
local sPlayProbeOffs -- the 3 probe x-offsets, precomputed at attach
local sPlayReach     -- probe ray length (halfH + 4), precomputed
local sPlayAir       -- consecutive airborne ticks (landing hysteresis)
local sPlayNormX     -- surface normal X at the grounded probe hit (slope test)
local sPlayPX, sPlayPY -- the probe's screen-px body centre, stashed for the
                     -- ladder zone test and b2kPlayerHurt (no second FFI read)
local sPlayOnOneWay  -- this frame's ground is a one-way chain (drop eligible)
local sPlayDropUntil -- sim-clock end of the drop-through window (0 = inactive)
local sPlayDropHard  -- hard restore deadline (4x dropMs): a drop that lands on
                     -- a parked solid under the chain must not stay intangible
local sPlayDropLineY -- surface y the drop started through; the mask is only
                     -- restored once the capsule's TOP clears it (a straddling
                     -- restore would snap the player back on top: chain contacts
                     -- are one-sided, judged by the centroid)
local sPlayDropSeen  -- the probe skipped a one-way hit this frame (still inside)
local sPlayDropMask  -- the player's mask to restore when the window closes
local sPlayClimb     -- true while in the climb state (gravity scale parked at 0)
local sPlayGravSave  -- the body's gravity scale to restore on climb exit
local sPlayLadN      -- registered ladder zones (flat numeric arrays: the
local sPlayLadL, sPlayLadT, sPlayLadR, sPlayLadB -- ...in-zone test is pure compares)
-- Wave 4: water zones + the swim state (a buoyant parallel to the climb)
local sPlaySwim      -- true while submerged in a water zone (gravity scaled down)
local sPlaySwimGravSave -- the body's gravity scale to restore on swim exit
local sPlaySwimSpd, sPlaySwimJump, sPlaySwimGrav, sPlaySwimMaxFall -- swim tune caches
local sPlayWatN      -- registered water zones (flat numeric arrays, like ladders)
local sPlayWatL, sPlayWatT, sPlayWatR, sPlayWatB
local sPlayHurt      -- true while knockback owns the controller
local sPlayHurtEnd   -- sim-clock when hurtMs has elapsed
local sPlayHurtHalf  -- sim-clock when half of hurtMs has elapsed (landings
                     -- only count from here; restore = LATER of the two)
local sPlayHurtLand  -- sim-clock of the first landing after the half mark (0 = none)
local sPlayInvulnUntil -- sim-clock end of the post-hurt mercy window
local sPlayClock     -- the player's SIM-TIME clock: summed frame ms.
                     -- Wall-clock would shrink the coyote/buffer windows
                     -- on slow machines (90ms = fewer frames); sim time
                     -- keeps them frame-coherent everywhere and makes
                     -- hand-stepped tests deterministic.
-- Wave 5 actions: double-jump, wall-slide/jump, dash, duck capsule reshape,
-- moving-platform carry. Each is OPT-IN through a knob whose default leaves
-- the pre-Wave-5 controller byte-for-byte unchanged, and each idle path
-- costs ONE compare per frame (the wall side-probe casts only while the
-- system is on AND airborne; carry reads a velocity only while grounded).
local sPlayAirJumps     -- extra mid-air jumps allowed (airJumps knob; 0 = none)
local sPlayAirJumpsLeft -- air jumps remaining (reset to sPlayAirJumps on ground)
local sPlayWallOn       -- the wall system is armed (wallJumpX or wallSlideMax > 0)
local sPlayWallJumpX, sPlayWallJumpY, sPlayWallSlideMax -- wall tune caches
local sPlayWall         -- airborne wall touch: -1 wall on left, 1 on right, 0 none
local sPlayWallSliding  -- true while actively wall-sliding (drives state + anim)
local sPlayWallLockUntil -- sim-clock through which a wall-jump owns vx (no air steer)
local sPlayDashSpd, sPlayDashMS, sPlayDashCool -- dash tune caches
local sPlayAirDash      -- true = dash allowed in mid-air (airDash knob; false = grounded only)
local sPlayDash         -- true while a dash is in flight (gravity parked at 0)
local sPlayDashEnd      -- sim-clock the dash ends
local sPlayDashReady    -- sim-clock the next dash may start (the cooldown gate)
local sPlayDashDir      -- dash direction (the facing captured at dash start)
local sPlayDashGravSave -- the body's gravity scale to restore when the dash ends
local sPlayDuckScale    -- ducked capsule height as a fraction of standing (1 = no reshape)
local sPlayDucked       -- true while the capsule is shrunk for a crawl
local sPlayStandH       -- the full standing capsule height in px (for the duck reshape)
local sPlayCapW, sPlayCapH -- the capsule's CANONICAL pixel dims, captured at attach
                        -- BEFORE the first draw pads the rect: the duck/stand
                        -- rebuilds pass these to b2kReshape explicitly, because a
                        -- polygon graphic's rect is DERIVED from its points -- OXT
                        -- ignores a height-set on one, and re-reading the drawn
                        -- rect compounds the pen margin (+2 every rebuild)
local sPlayDuckH        -- the ducked capsule height in px (for the stand-up shift)
local sPlayCarry        -- true = inherit a moving platform's velocity (platformCarry knob)
local sPlayGroundBody   -- the body handle under the grounding ray (carry reads its velocity)
local sPlayInLad, sPlayInWat -- this frame's ladder/water zone membership (exposed by getters)
local sSndClip       -- sound name -> audioClip short name ("b2ksnd_...")
local sSndMute       -- true = swallow play calls (a user preference; survives teardown)
local sSndDead       -- true after a play failure: degrade to silence, never errors
local sSndNote       -- empty = healthy; else why audio is degraded

constant kPI = 3.14159265358979

/**
Title: Box2Dxt Kit
Author: Box2Dxt contributors
Description:
A pure-script game toolkit over the box2dxt extension (Box2D v3.1 physics).
You work in screen pixels, screen coordinates (y down) and degrees; the Kit
converts to Box2D's metres, radians and y-up, runs a fixed-step frame loop,
and moves your controls to follow their bodies.

Start with <b2kQuickStart> (or <b2kSetup> and <b2kStart>), give controls
bodies with <b2kAddBox> or create them with <b2kSpawnBox>, and set a
<b2kFrameTarget> for per-frame logic and a <b2kContactTarget> for collision
messages. Commands report through the result, so read it on the next line.
Besides physics it has keyboard input, sprite sheets and animation, a
platformer player controller, a scrolling camera and synthesized sound.

It needs the box2dxt extension loaded: b2kVersion() should return 4.

Tags: Physics, Games
*/

-- =====================================================================
-- World / lifecycle
-- =====================================================================
/**
Summary: Create the physics world and reset the Kit to a clean state.

pGravityX: Horizontal gravity in Box2D units (metres per second squared, y up). Empty means 0.

pGravityY: Vertical gravity in Box2D units, y up, so a negative value pulls down. Empty means -10.

Example:
b2kSetup
b2kAddStatic the long id of graphic "Floor"
b2kAddBox the long id of graphic "Crate"
b2kStart

Description:
Use <b2kSetup> to start a world without starting the loop. It first
tears down any previous world (<b2kTeardown>), then sets the scale to 40
pixels per metre, the origin to the card's bottom centre (40 px up from the
bottom edge) and 4 solver sub-steps.

The gravity values go to Box2D unchanged, in metres per second squared with
y pointing up. It also maps a native library saved beside the stack
(<b2kEnsureNativeLib>).

References: b2kQuickStart (handler), b2kStart (handler), b2kTeardown (handler)
*/
command b2kSetup pGravityX, pGravityY
   b2kEnsureNativeLib
   b2kTeardown
   if pGravityX is empty then put 0 into pGravityX
   if pGravityY is empty then put -10 into pGravityY
   put b2NewWorld(pGravityX, pGravityY, true, true) into sWorld
   put b2NewStaticBody(sWorld, 0, 0) into sDragAnchor
   put 40 into sScale
   put (the width of this card) div 2 into sOriginX
   put (the height of this card) - 40 into sOriginY
   put 4 into sSub
   b2kResetTables
   put empty into sLayers
   put 1 into sNextBit
   put 0 into sDragJoint
   put false into sDragging
   put false into sRunning
   put false into sPaused
   put false into sNeedFullSync
   put empty into sKillY
   b2kEventsReset
end b2kSetup

-- Point the engine at the native library so the c:box2dxt> foreign bindings
-- resolve on EVERY platform and IDE -- including OXT Lite, whose stripped IDE
-- does not auto-scan an extension's code/ folder. the revLibraryMapping is the
-- exact name->path table the engine consults when loading a foreign-handler
-- library (engine resolver MCEngineLoadLibrary); seeding it ourselves means no
-- /usr/lib, no LD_LIBRARY_PATH, no sudo, no code/ packaging, on Linux/macOS/
-- Windows alike. The library ships next to the stack under its bare name
-- (box2dxt.{so,dll,dylib}); if it is there we map it, otherwise we leave the
-- engine's own search untouched (so the historical "beside the engine" path on
-- Win/macOS still works). Raw b2* callers that do not use the Kit can set the
-- same mapping themselves before their first b2 call.
/**
Summary: Point the engine at a box2dxt library saved beside the stack.

Example:
b2kEnsureNativeLib
put b2kVersion() into tABI

Description:
When a file named box2dxt.dll, box2dxt.dylib or box2dxt.so (by
platform) sits in the folder of the saved stack, <b2kEnsureNativeLib> sets the
revLibraryMapping for "box2dxt" to it, so the extension's foreign handlers
resolve with no install. Otherwise it leaves the engine's own search alone.
An unsaved stack is a quiet no-op.

<b2kSetup> calls it for you. Scripts that use the raw b2 layer without the
Kit can call it before their first b2 call.

References: b2kSetup (handler), b2kVersion (handler)
*/
command b2kEnsureNativeLib
   local tStackFile, tDir, tName, tPath, tOldDelim
   put the effective filename of this stack into tStackFile
   if tStackFile is empty then exit b2kEnsureNativeLib
   switch the platform
      case "Win32"
         put "box2dxt.dll" into tName
         break
      case "MacOS"
         put "box2dxt.dylib" into tName
         break
      default
         put "box2dxt.so" into tName   -- Linux and friends
         break
   end switch
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to slash
   put item 1 to -2 of tStackFile into tDir
   set the itemDelimiter to tOldDelim
   put tDir & slash & tName into tPath
   if there is a file tPath then
      set the revLibraryMapping["box2dxt"] to tPath
   end if
end b2kEnsureNativeLib

/**
Summary: Empty the Kit's control and body tables.

Example:
b2kResetTables

Description:
Internal: <b2kSetup> and <b2kTeardown> call it. It forgets every
control-to-body pairing, shape, render kind and camera membership, but it
destroys no body and deletes no control, so calling it on a live world leaves
bodies the Kit no longer tracks.

References: b2kSetup (handler), b2kTeardown (handler)
*/
command b2kResetTables
   put empty into sBody
   put empty into sCtrl
   put empty into sShapeH
   put empty into sRender
   put empty into sVerts
   put empty into sRad
   put empty into sImgAngle
   put empty into sDrawKey
   put empty into sStatic
   put false into sNeedFullSync
   put empty into sSpawned
   put empty into sSensor
   put empty into sInCam
   put empty into sOneWayBody
end b2kResetTables

/**
Summary: Stop the loop and destroy the world and all Kit state.

Example:
b2kTeardown

Description:
Use <b2kTeardown> when a scene is finished. It stops the loop,
destroys the Box2D world, forgets the player controller (tuning included),
removes sprites, dissolves the camera viewport and empties the Kit's tables.

Sheets are wiped too unless <b2kSheetPersist> is on, in which case only the
sprite instances go and the sheet cache survives. Sounds always survive; use
<b2kSoundsWipe> to remove them.

References: b2kSetup (handler), b2kClear (handler), b2kStop (handler)
*/
command b2kTeardown
   put false into sRunning
   put the milliseconds & random(9999) into sGen
   if sWorld is not empty then b2DestroyWorld sWorld
   put empty into sWorld
   b2kPlayerForget true   -- full: a teardown wipes the tuning too
   if sSheetKeep is true then
      -- sheets are ASSETS that SURVIVE teardown (b2kSheetPersist), exactly
      -- like sounds: clear only the sprite INSTANCES + dead viewports and
      -- keep the sheet cache, so a level rebuild reuses it instead of
      -- re-decoding/re-parsing/re-slicing (the costliest thing the Kit does).
      b2kSpritesClear
      b2kSpriteSweepOrphans true
      put empty into sSheetData    -- the imageData cache re-derives lazily;
      put empty into sSheetAlpha   -- free it like the full wipe would
   else
      b2kSheetsWipe   -- sprites first: their stored long ids include the group
   end if
   -- sounds deliberately SURVIVE teardown: clips are tiny (KBs) and
   -- deterministic, and re-synthesis cost a fifth of a second on every
   -- reset. b2kSoundsWipe purges them when you really want them gone.
   b2kCamOff       -- ...then dissolve the viewport (survivors go to the card)
   b2kResetTables
   put 0 into sDragJoint
   put false into sDragging
end b2kTeardown

-- One-liner: world with gravity, walls around the card, loop running.
/**
Summary: Make a world with gravity, walls around the card, and start the loop.

pGravityY: Vertical gravity in Box2D units, y up (negative pulls down). Empty means -10.

Example:
b2kQuickStart
b2kSpawnBall 200, 80, 50
put the result into tBall

Description:
The one-call start: <b2kSetup> with no horizontal gravity,
<b2kAddWalls> around the card edges, then <b2kStart>.

References: b2kSetup (handler), b2kAddWalls (handler), b2kStart (handler)
*/
command b2kQuickStart pGravityY
   b2kSetup 0, pGravityY
   b2kAddWalls
   b2kStart
end b2kQuickStart

/**
Summary: Start the simulation loop.

Example:
b2kSetup
b2kAddWalls
b2kStart

Description:
Use <b2kStart> to begin stepping the world at a fixed 1/60 s step,
syncing controls and delivering events once per frame. If no world exists yet
it calls <b2kSetup> first. Starting again replaces any running loop rather
than adding a second one.

References: b2kStop (handler), b2kPause (handler), b2kStepOnce (handler)
*/
command b2kStart
   if sWorld is empty then b2kSetup
   put true into sRunning
   put false into sPaused
   put 0 into sAccum
   put the milliseconds into sLast
   put the milliseconds & "_" & random(1000000) into sGen
   send ("b2kStep " & sGen) to me in 16 milliseconds
end b2kStart

/**
Summary: Stop the simulation loop.

Example:
b2kStop

Description:
The world and its bodies stay; nothing steps until <b2kStart>.
Use <b2kTeardown> to destroy the world as well.

References: b2kStart (handler), b2kPause (handler), b2kTeardown (handler)
*/
command b2kStop
   put false into sRunning
   put the milliseconds & random(9999) into sGen
end b2kStop

/**
Summary: Freeze stepping without stopping the loop.

Example:
b2kPause

Description:
While paused, the loop keeps running but no physics step, sync or
frame message happens. <b2kStepOnce> still advances one step.

References: b2kResume (handler), b2kStepOnce (handler), b2kIsRunning (handler)
*/
command b2kPause
   put true into sPaused
end b2kPause

/**
Summary: Resume stepping after a pause.

Example:
b2kResume

Description:
The elapsed-time clock restarts from now, so the pause is not
replayed as one long catch-up step.

References: b2kPause (handler)
*/
command b2kResume
   put false into sPaused
   put the milliseconds into sLast
end b2kResume

/**
Summary: Report whether the loop is running and not paused.

Returns: true while the loop is stepping; false when stopped or paused.

Example:
if b2kIsRunning() then b2kPause

References: b2kStart (handler), b2kPause (handler)
*/
function b2kIsRunning
   return (sRunning is true) and (sPaused is not true)
end b2kIsRunning

-- Static, invisible walls along the four card edges.
/**
Summary: Add static, invisible walls along the four card edges.

Example:
b2kSetup
b2kAddWalls

Description:
The walls are untracked world bodies, so <b2kClear> leaves them in
place. They are placed for the current scale and origin, so set those first.

References: b2kWall (handler), b2kAddGround (handler), b2kQuickStart (handler)
*/
command b2kAddWalls
   local tL, tR, tT, tB
   put b2kToWorldX(0) into tL
   put b2kToWorldX(the width of this card) into tR
   put b2kToWorldY(0) into tT
   put b2kToWorldY(the height of this card) into tB
   b2kEdge tL, tB, tR, tB
   b2kEdge tL, tT, tR, tT
   b2kEdge tL, tB, tL, tT
   b2kEdge tR, tB, tR, tT
end b2kAddWalls

/**
Summary: Add a static segment between two points given in world metres.

pWx1: X of the first point, in metres.

pWy1: Y of the first point, in metres (y up).

pWx2: X of the second point, in metres.

pWy2: Y of the second point, in metres (y up).

Example:
b2kEdge b2kToWorldX(0), b2kToWorldY(400), b2kToWorldX(300), b2kToWorldY(400)

Description:
Internal: <b2kWall> and <b2kAddWalls> build their segments with it.
With no world it is a quiet no-op. Most scripts want <b2kWall>, which takes
screen pixels.

References: b2kWall (handler)
*/
command b2kEdge pWx1, pWy1, pWx2, pWy2
   local tBody
   if sWorld is empty then exit b2kEdge   -- no world yet: a wall is a quiet no-op
   put b2NewStaticBody(sWorld, 0, 0) into tBody
   get b2AddSegment(tBody, pWx1, pWy1, pWx2, pWy2, 0.6, 0.1)
end b2kEdge

-- A wide invisible ground line at screen height pScreenY (default: near bottom).
/**
Summary: Add a wide, invisible static floor across the card.

pScreenY: The floor's screen y in pixels. Empty means 40 px above the card's bottom edge.

Example:
b2kAddGround 420

Description:
The floor is a long static segment (1000 m wide), not tracked as a
body, so <b2kClear> keeps it. With no world it does nothing.

References: b2kAddWalls (handler), b2kWall (handler)
*/
command b2kAddGround pScreenY
   local tBody, tWy
   if sWorld is empty then exit b2kAddGround
   if pScreenY is empty then put (the height of this card) - 40 into pScreenY
   put b2kToWorldY(pScreenY) into tWy
   put b2NewStaticBody(sWorld, 0, tWy) into tBody
   get b2AddSegment(tBody, -500, 0, 500, 0, 0.7, 0.1)
end b2kAddGround

-- A static collision segment between two SCREEN points - custom walls, ramps,
-- ledges and floors. Like the card-edge walls it is invisible (draw your own
-- graphic to match) and lives for the world's lifetime; it isn't tracked as a
-- body, so b2kClear leaves it in place.
-- Destroy any moving Kit body whose centre falls below this SCREEN y
-- (empty = off). Crates shoved into pits, enemies knocked off the level:
-- gone instead of falling forever. The PLAYER's body is exempt (the game
-- owns its respawn). Each removal first sends "b2kFell <ctrl>" to the
-- frame target so the game can clean up companions (bound sprites, table
-- slots) -- do not delete the control inside that handler; the Kit is
-- mid-removal (Kit-spawned controls are deleted for you).
/**
Summary: Remove moving Kit bodies whose centre falls below a screen line.

pScreenY: The screen y in pixels below which moving bodies are removed. Empty turns the kill floor off.

Example:
b2kKillFloor 900

Description:
Crates pushed into pits and enemies knocked off a level are removed
instead of falling forever. The player controller's body is exempt; your game
owns its respawn.

Before each removal the Kit sends the message b2kFell, with the control as
its parameter, to the frame target (<b2kFrameTarget>). Use it to clean up
companions such as bound sprites, but do not delete the control in
that handler, because the Kit is removing it.

References: b2kFrameTarget (handler), b2kRemove (handler)
*/
command b2kKillFloor pScreenY
   put pScreenY into sKillY
end b2kKillFloor

/**
Summary: Add an invisible static segment between two screen points.

pX1: Screen x of the first point, in pixels.

pY1: Screen y of the first point, in pixels.

pX2: Screen x of the second point, in pixels.

pY2: Screen y of the second point, in pixels.

Example:
b2kWall 100, 400, 300, 340

Description:
Use <b2kWall> for custom walls, ramps and ledges. The segment is
two-sided: bodies collide from either side. It is invisible, so draw a
graphic to match, and it is not tracked as a body, so <b2kClear> leaves it.
For one-sided surfaces use <b2kChain>.

References: b2kChain (handler), b2kAddWalls (handler), b2kEdge (handler)
*/
command b2kWall pX1, pY1, pX2, pY2
   b2kEdge b2kToWorldX(pX1), b2kToWorldY(pY1), b2kToWorldX(pX2), b2kToWorldY(pY2)
end b2kWall

-- Remove every dynamic body (b2kRemove deletes kit-spawned controls; attached
-- controls are just detached). Sprites are Kit-created controls, so they go
-- too; loaded sheets stay (they are assets, not world state).
/**
Summary: Remove every moving body and every sprite, keeping the world.

Example:
b2kClear
b2kSpawnBox 200, 80, 60, 40
put the result into tBox

Description:
Use <b2kClear> to reset a scene without rebuilding the world. Every
non-static Kit body is removed with <b2kRemove> (controls the Kit spawned are
deleted, attached controls are only detached), sprites are removed, and the
player controller's state and ladder and water zones are dropped. Player
tuning, input bindings, loaded sheets, sounds, static bodies, walls and chains
stay.

References: b2kRemove (handler), b2kTeardown (handler)
*/
command b2kClear
   local tRef, tList, d
   b2kSpritesClear
   b2kPlayerForget false   -- the player is world state; its tuning is config
   put empty into tList
   repeat for each key tRef in sBody
      if sStatic[tRef] is not true then put tRef & cr after tList
   end repeat
   repeat for each line d in tList
      if d is not empty then b2kRemove d
   end repeat
end b2kClear

-- =====================================================================
-- Configuration
-- =====================================================================
/**
Summary: Return a value when it is a number, else a default.

pValue: The value to test.

pDefault: What to return when the value is empty or not a number.

Returns: The value, or the default.

Example:
put b2kNumberOr(field "Speed", 200) into tSpeed

Description:
A small helper the Kit uses to make optional arguments safe.

References: b2kClamp (handler)
*/
function b2kNumberOr pValue, pDefault
   if pValue is empty then return pDefault
   if pValue is not a number then return pDefault
   return pValue
end b2kNumberOr

/**
Summary: Clamp a value into a range.

pValue: The value to clamp. Empty or not a number counts as the low bound.

pLo: The lower bound.

pHi: The upper bound.

Returns: The value limited to the range from the low to the high bound.

Example:
put b2kClamp(tVolume, 0, 100) into tVolume

References: b2kNumberOr (handler)
*/
function b2kClamp pValue, pLo, pHi
   local tValue
   put b2kNumberOr(pValue, pLo) into tValue
   if tValue < pLo then put pLo into tValue
   if tValue > pHi then put pHi into tValue
   return tValue
end b2kClamp

/**
Summary: Set how many screen pixels make one Box2D metre.

pPixelsPerMetre: Pixels per metre, clamped to 1-10000. The default after setup is 40.

Example:
b2kSetup
b2kSetScale 50

Description:
Set the scale right after <b2kSetup>, before adding bodies: bodies
already in the world keep the size they were built with. Moving objects
behave best at roughly 0.1 to 10 metres, so 4 to 400 px at the default scale.

References: b2kSetOrigin (handler), b2kToWorldX (handler), b2kToScreenX (handler)
*/
command b2kSetScale pPixelsPerMetre
   put b2kClamp(pPixelsPerMetre, 1, 10000) into sScale
end b2kSetScale

/**
Summary: Set the screen point that maps to the world origin.

pScreenX: Screen x in pixels. Empty or not a number keeps the current value.

pScreenY: Screen y in pixels. Empty or not a number keeps the current value.

Example:
b2kSetOrigin 0, 0

Description:
<b2kSetup> puts the origin at the card's bottom centre. Change it
before adding bodies, because conversions made earlier are not redone.

References: b2kSetScale (handler), b2kToWorldX (handler)
*/
command b2kSetOrigin pScreenX, pScreenY
   put b2kNumberOr(pScreenX, sOriginX) into sOriginX
   put b2kNumberOr(pScreenY, sOriginY) into sOriginY
end b2kSetOrigin

/**
Summary: Change the world's gravity.

pGx: Horizontal gravity in Box2D units (metres per second squared). Not a number means 0.

pGy: Vertical gravity in Box2D units, y up, so negative pulls down. Not a number means -10.

Example:
b2kSetGravity 0, -20

Description:
The values go to Box2D unchanged, in metres per second squared with
y pointing up, the same convention as <b2kSetup>. With no world it does
nothing.

References: b2kSetup (handler), b2kSetGravityScale (handler)
*/
command b2kSetGravity pGx, pGy
   put b2kNumberOr(pGx, 0) into pGx
   put b2kNumberOr(pGy, -10) into pGy
   if sWorld is not empty then b2SetGravity sWorld, pGx, pGy
end b2kSetGravity

/**
Summary: Set the solver sub-steps per physics step.

pN: Sub-steps per step, rounded and clamped to 1-64. The default is 4.

Example:
b2kSetSubsteps 8

Description:
More sub-steps make stacks and joints stiffer and cost more CPU.
*/
command b2kSetSubsteps pN
   put round(b2kClamp(pN, 1, 64)) into sSub
end b2kSetSubsteps

-- World toggles: island sleeping (saves CPU) and continuous collision (CCD,
-- stops fast bodies tunnelling through thin walls).
/**
Summary: Turn island sleeping on or off for the whole world.

pFlag: true to let resting bodies sleep, false to keep them all awake.

Example:
b2kEnableSleeping false

Description:
Sleeping saves CPU when bodies rest, and it is on by default. Use
<b2kSetSleepEnabled> to change it for one body.

References: b2kSetSleepEnabled (handler), b2kSleep (handler)
*/
command b2kEnableSleeping pFlag
   if sWorld is not empty then b2EnableSleeping sWorld, (pFlag is true)
end b2kEnableSleeping

/**
Summary: Turn continuous collision (CCD) on or off for the world.

pFlag: true to stop fast bodies tunnelling through static walls, false to turn it off.

Example:
b2kEnableContinuous true

Description:
Use <b2kSetBullet> for continuous collision between moving bodies.

References: b2kSetBullet (handler)
*/
command b2kEnableContinuous pFlag
   if sWorld is not empty then b2EnableContinuous sWorld, (pFlag is true)
end b2kEnableContinuous

/**
Summary: Set the object that receives contact and sensor messages.

pObject: A reference to the object, such as the long id of the card. Empty turns the messages off.

Example:
b2kContactTarget the long id of me

Description:
After each frame the Kit sends this object b2kContact and
b2kEndContact (two controls that began or stopped touching), and
b2kSensorEnter and b2kSensorExit (a sensor control and a visitor control).
A control parameter is empty for a wall, the ground or any body the Kit does
not track. Without a target no message is sent; the polling functions such
as <b2kContactCount> work either way.

References: b2kFrameTarget (handler), b2kContactCount (handler), b2kAddSensor (handler)
*/
command b2kContactTarget pObject
   put pObject into sContactObj
end b2kContactTarget

-- Object that receives an `on b2kFrame` message once per simulated frame (after
-- bodies are synced). Use it for per-frame logic: motors, custom drawing, input.
/**
Summary: Set the object that receives a b2kFrame message every frame.

pObject: A reference to the object, such as the long id of the card. Empty turns the message off.

Example:
b2kFrameTarget the long id of me

Description:
The Kit sends b2kFrame once per simulated frame, after bodies,
input, the player, sprites and the camera have updated. Put per-frame game
logic there. The same object receives b2kFell (<b2kKillFloor>) and sprite
finish messages (<b2kSpriteOnFinish>).

An error inside b2kFrame is caught silently so the screen never stays
locked; the rest of that frame's work is skipped.

References: b2kContactTarget (handler), b2kFrameMS (handler), b2kKillFloor (handler)
*/
command b2kFrameTarget pObject
   put pObject into sFrameObj
end b2kFrameTarget

/**
Summary: The raw Box2D world handle.

Returns: The world handle, or empty before setup.

Example:
put b2kWorld() into tWorld

Description:
Use it to mix Kit code with calls to the raw b2 layer.

References: b2kBodyOf (handler)
*/
function b2kWorld
   return sWorld
end b2kWorld

-- Sanity check from kit-only code: returns the native shim's ABI version (4),
-- i.e. that the box2dxt extension and its native library are loaded and in sync.
/**
Summary: The native library's ABI version.

Returns: The ABI version number of the loaded box2dxt library (4 for this Kit).

Example:
if b2kVersion() is not 4 then answer "box2dxt is missing or out of date"

Description:
A load and in-sync check from Kit-only code. It calls the extension,
so it throws if the box2dxt extension is not loaded.

References: b2kEnsureNativeLib (handler)
*/
function b2kVersion
   return b2Version()
end b2kVersion

-- =====================================================================
-- Coordinate conversion (sim Y up; screen Y down)
-- =====================================================================
/**
Summary: Convert a world x in metres to a screen x in pixels.

pWx: The world x, in metres.

Returns: The screen x, in pixels.

Example:
put b2kToScreenX(2.5) into tX

References: b2kToScreenY (handler), b2kToWorldX (handler)
*/
function b2kToScreenX pWx
   return sOriginX + pWx * sScale
end b2kToScreenX

/**
Summary: Convert a world y in metres (y up) to a screen y in pixels (y down).

pWy: The world y, in metres.

Returns: The screen y, in pixels.

Example:
put b2kToScreenY(0) into tGroundY

References: b2kToScreenX (handler), b2kToWorldY (handler)
*/
function b2kToScreenY pWy
   return sOriginY - pWy * sScale
end b2kToScreenY

/**
Summary: Convert a screen x in pixels to a world x in metres.

pSx: The screen x, in pixels.

Returns: The world x in metres, or 0 before <b2kSetup>.

Example:
put b2kToWorldX(the mouseH) into tWx

References: b2kToWorldY (handler), b2kToScreenX (handler)
*/
function b2kToWorldX pSx
   if sScale is empty or sScale = 0 then return 0   -- before b2kSetup: stay safe
   return (pSx - sOriginX) / sScale
end b2kToWorldX

/**
Summary: Convert a screen y in pixels (y down) to a world y in metres (y up).

pSy: The screen y, in pixels.

Returns: The world y in metres, or 0 before <b2kSetup>.

Example:
put b2kToWorldY(the mouseV) into tWy

References: b2kToWorldX (handler), b2kToScreenY (handler)
*/
function b2kToWorldY pSy
   if sScale is empty or sScale = 0 then return 0
   return (sOriginY - pSy) / sScale
end b2kToWorldY

-- =====================================================================
-- Attaching existing controls (pDynamic defaults to true)
-- =====================================================================
/**
Summary: Give a control a box-shaped body matching its rect.

pControl: The control, by reference (the long id of the control is safest).

pDynamic: true (the default) for a dynamic body, false for a static one.

Returns: The body handle through the result, or 0 when there is no world or the control has no size.

Example:
b2kAddBox the long id of graphic "Crate"
put the result into tBody

Description:
A graphic becomes a polygon outline that rotates with its body; a
dynamic image rotates through its angle; other controls (buttons, fields)
follow position only and have their rotation locked so the simulation matches
the upright drawing. The control is drawn at once, even with the loop
stopped.

The shape starts with density 1, friction 0.4 and bounce 0.2.

References: b2kAddBall (handler), b2kAddStatic (handler), b2kSpawnBox (handler), b2kRemove (handler)
*/
command b2kAddBox pControl, pDynamic
   local tRef, tType, tFixed, tBody, tHw, tHh, tWx, tWy, tGraphic, tImage
   set the itemDelimiter to comma   -- locs and anchors are "x,y" (gotcha 5)
   if sWorld is empty then return 0   -- attach needs a world (b2kSetup first)
   put the long id of pControl into tRef
   put (pDynamic is not false) into pDynamic
   if pDynamic then put 2 into tType
   else put 0 into tType
   put ((the width of pControl) / 2) / sScale into tHw
   put ((the height of pControl) / 2) / sScale into tHh
   if tHw <= 0 or tHh <= 0 then return 0
   put b2kToWorldX(item 1 of the loc of pControl) into tWx
   put b2kToWorldY(item 2 of the loc of pControl) into tWy
   put (word 1 of tRef is "graphic") into tGraphic
   put (word 1 of tRef is "image") into tImage
   -- Graphics rotate as polygons; dynamic images rotate via `the angle`. Other
   -- control types (button, field, ...) can't be shown rotated, so we lock
   -- their rotation to keep the simulation consistent with the upright render.
   if tGraphic or (tImage and pDynamic) then put false into tFixed
   else put true into tFixed
   put b2NewBody(sWorld, tType, tWx, tWy, 0, false, tFixed) into tBody
   b2ShapeDefEnableSensorEvents true   -- so sensors can detect this shape
   put b2AddBox(tBody, tHw, tHh, 1.0, 0.4, 0.2) into sShapeH[tRef]
   b2kRegister tRef, tBody, (not pDynamic)
   if tGraphic and pDynamic then
      set the style of pControl to "polygon"
      put "poly" into sRender[tRef]
      put ("-" & tHw) & "," & ("-" & tHh) & cr & tHw & "," & ("-" & tHh) & cr \
            & tHw & "," & tHh & cr & ("-" & tHw) & "," & tHh into sVerts[tRef]
   else if tImage and pDynamic then
      put "image" into sRender[tRef]
   else
      put "loc" into sRender[tRef]
   end if
   -- Draw the new body NOW. The style switch above left a "poly" graphic with
   -- no points (invisible), and the move-event sync can't help: a world that
   -- isn't stepping emits no move events, so a part spawned while the loop is
   -- stopped would stay invisible until the first Run. Attach = visible.
   b2kDrawBody tRef, tWx, tWy, 0
   return tBody
end b2kAddBox

/**
Summary: Give a control a circular body.

pControl: The control, by reference (the long id of the control is safest).

pDynamic: true (the default) for a dynamic body, false for a static one.

Returns: The body handle through the result, or 0 when there is no world or the control has no width.

Example:
b2kAddBall the long id of graphic "Ball"

Description:
The radius is half the control's width. A graphic is redrawn as a
circle, an image rotates through its angle, and other controls follow
position. The shape starts with density 1, friction 0.4 and bounce 0.4.

References: b2kAddBox (handler), b2kSpawnBall (handler)
*/
command b2kAddBall pControl, pDynamic
   local tRef, tType, tBody, tRad, tWx, tWy
   set the itemDelimiter to comma   -- locs and anchors are "x,y" (gotcha 5)
   if sWorld is empty then return 0
   put the long id of pControl into tRef
   put (pDynamic is not false) into pDynamic
   if pDynamic then put 2 into tType
   else put 0 into tType
   put ((the width of pControl) / 2) / sScale into tRad
   if tRad <= 0 then return 0
   put b2kToWorldX(item 1 of the loc of pControl) into tWx
   put b2kToWorldY(item 2 of the loc of pControl) into tWy
   put b2NewBody(sWorld, tType, tWx, tWy, 0, false, false) into tBody
   b2ShapeDefEnableSensorEvents true   -- so sensors can detect this shape
   put b2AddCircle(tBody, 0, 0, tRad, 1.0, 0.4, 0.4) into sShapeH[tRef]
   b2kRegister tRef, tBody, (not pDynamic)
   if word 1 of tRef is "graphic" then put "ball" into sRender[tRef]
   else if word 1 of tRef is "image" then put "image" into sRender[tRef]
   else put "loc" into sRender[tRef]
   put tRad into sRad[tRef]
   b2kDrawBody tRef, tWx, tWy, 0   -- visible at attach, even with the loop stopped
   return tBody
end b2kAddBall

-- Capsule ("pill"): the long side of the control's rect is the capsule axis,
-- the short side its diameter. Graphics render as a rounded outline (and rotate);
-- images rotate via `the angle`; other controls follow position upright.
/**
Summary: Give a control a capsule (pill) body.

pControl: The control, by reference (the long id of the control is safest).

pDynamic: true (the default) for a dynamic body, false for a static one.

Returns: The body handle through the result, or 0 when there is no world or the control has no size.

Example:
b2kAddCapsule the long id of graphic "Hero"
b2kSetFixedRotation the long id of graphic "Hero", true

Description:
The longer side of the control's rect is the capsule's axis and the
shorter side its diameter. A dynamic graphic is redrawn as a rounded outline
that rotates; a dynamic image rotates through its angle; other controls follow
position upright.

References: b2kAddBox (handler), b2kSpawnCapsule (handler), b2kReshape (handler)
*/
command b2kAddCapsule pControl, pDynamic
   local tRef, tType, tFixed, tBody, tWx, tWy, tWm, tHm, tR, tL, tHoriz, tGraphic, tImage
   set the itemDelimiter to comma   -- locs and anchors are "x,y" (gotcha 5)
   if sWorld is empty then return 0
   put the long id of pControl into tRef
   put (pDynamic is not false) into pDynamic
   if pDynamic then put 2 into tType
   else put 0 into tType
   put (the width of pControl) / sScale into tWm
   put (the height of pControl) / sScale into tHm
   if tWm <= 0 or tHm <= 0 then return 0
   put (tWm >= tHm) into tHoriz
   if tHoriz then
      put tHm / 2 into tR
      put max(0, tWm / 2 - tR) into tL
   else
      put tWm / 2 into tR
      put max(0, tHm / 2 - tR) into tL
   end if
   put b2kToWorldX(item 1 of the loc of pControl) into tWx
   put b2kToWorldY(item 2 of the loc of pControl) into tWy
   put (word 1 of tRef is "graphic") into tGraphic
   put (word 1 of tRef is "image") into tImage
   if tGraphic or (tImage and pDynamic) then put false into tFixed
   else put true into tFixed
   put b2NewBody(sWorld, tType, tWx, tWy, 0, false, tFixed) into tBody
   b2ShapeDefEnableSensorEvents true   -- so sensors can detect this shape
   if tHoriz then
      put b2AddCapsule(tBody, - tL, 0, tL, 0, tR, 1.0, 0.4, 0.2) into sShapeH[tRef]
   else
      put b2AddCapsule(tBody, 0, - tL, 0, tL, tR, 1.0, 0.4, 0.2) into sShapeH[tRef]
   end if
   b2kRegister tRef, tBody, (not pDynamic)
   if tGraphic and pDynamic then
      set the style of pControl to "polygon"
      put "poly" into sRender[tRef]
      put b2kCapsuleVerts(tL, tR, tHoriz) into sVerts[tRef]
   else if tImage and pDynamic then
      put "image" into sRender[tRef]
   else
      put "loc" into sRender[tRef]
   end if
   -- Same as b2kAddBox: the freshly point-less "poly" graphic must be drawn
   -- here, because a stopped world never emits the move event that would.
   b2kDrawBody tRef, tWx, tWy, 0
   return tBody
end b2kAddCapsule

-- Build a body from a polygon graphic's own points (<= 8 vertices, convex).
/**
Summary: Give a polygon graphic a body built from its own points.

pControl: The polygon graphic, by reference. Its points must form a convex outline.

pDynamic: true (the default) for a dynamic body, false for a static one.

Returns: The body handle through the result, or 0 when there is no world or fewer than 3 points.

Example:
b2kAddPolygon the long id of graphic "Wedge"

Description:
Only the first 8 points are used, relative to the control's centre.
The graphic is redrawn from those points as the body moves and rotates.

References: b2kAddBox (handler), b2kReshape (handler)
*/
command b2kAddPolygon pControl, pDynamic
   local tRef, tType, tBody, tCx, tCy, tWx, tWy, tPoints, p, tLocal, lx, ly, tCount
   set the itemDelimiter to comma   -- locs and anchors are "x,y" (gotcha 5)
   if sWorld is empty then return 0
   put the long id of pControl into tRef
   put (pDynamic is not false) into pDynamic
   if pDynamic then put 2 into tType
   else put 0 into tType
   put item 1 of the loc of pControl into tCx
   put item 2 of the loc of pControl into tCy
   put b2kToWorldX(tCx) into tWx
   put b2kToWorldY(tCy) into tWy
   put b2NewBody(sWorld, tType, tWx, tWy, 0, false, false) into tBody
   b2PolyBegin
   put empty into tLocal
   put 0 into tCount
   repeat for each line p in the points of pControl
      if p is empty then next repeat
      if tCount >= 8 then next repeat
      put (item 1 of p - tCx) / sScale into lx
      put - ((item 2 of p - tCy) / sScale) into ly
      b2PolyAddPoint lx, ly
      put lx & "," & ly & cr after tLocal
      add 1 to tCount
   end repeat
   if tCount < 3 then
      b2DestroyBody tBody
      return 0
   end if
   b2ShapeDefEnableSensorEvents true   -- so sensors can detect this shape
   put b2AddPolygon(tBody, 1.0, 0.4, 0.2) into sShapeH[tRef]
   b2kRegister tRef, tBody, (not pDynamic)
   put "poly" into sRender[tRef]
   put tLocal into sVerts[tRef]
   b2kDrawBody tRef, tWx, tWy, 0   -- visible at attach, even with the loop stopped
   return tBody
end b2kAddPolygon

/**
Summary: Give a control an immovable box body.

pControl: The control, by reference (the long id of the control is safest).

Example:
b2kAddStatic the long id of graphic "Floor"

Description:
The same as <b2kAddBox> with pDynamic false.

References: b2kAddBox (handler), b2kSetStatic (handler)
*/
command b2kAddStatic pControl
   b2kAddBox pControl, false
end b2kAddStatic

/**
Summary: Record a control and body pair in the Kit's tables.

pRef: The control's long id.

pBody: The raw body handle.

pIsStatic: true when the body never moves, so the sync skips it.

Example:
b2kRegister the long id of graphic "Rock", tBody, true

Description:
Internal: the attach handlers call it. Registering a body you made
with the raw b2 layer lets Kit getters and events find its control, but the
Kit does not draw it until a render kind is set by an attach handler.

References: b2kAddBox (handler), b2kBodyOf (handler)
*/
command b2kRegister pRef, pBody, pIsStatic
   put pBody into sBody[pRef]
   put pRef into sCtrl[pBody]
   put (pIsStatic is true) into sStatic[pRef]
end b2kRegister

-- =====================================================================
-- Spawning new controls (create + attach in one call). Returns control ref.
-- =====================================================================
/**
Summary: Create a filled rectangle graphic with a dynamic box body.

pScreenX: Centre x in pixels. Not a number means the world origin's x.

pScreenY: Centre y in pixels. Not a number means the world origin's y.

pW: Width in pixels. Empty means 40.

pH: Height in pixels. Empty means the width.

pColor: Optional fill colour, such as "orange" or "255,128,0". An unknown name is ignored.

Returns: The new control's long id through the result, or empty when there is no world.

Example:
b2kSpawnBox 260, 80, 60, 40, "orange"
put the result into tBox

Description:
The Kit owns the control: <b2kRemove> and <b2kClear> delete it.
While the camera is on it is created inside the viewport. Read the result on
the very next line, because the next command replaces it.

References: b2kSpawnBall (handler), b2kSpawnCapsule (handler), b2kAddBox (handler), b2kRemove (handler)
*/
command b2kSpawnBox pScreenX, pScreenY, pW, pH, pColor
   local tName, tRef
   if sWorld is empty then return empty   -- spawn needs a world (b2kSetup first)
   if pW is empty then put 40 into pW
   put b2kClamp(pW, 1, 10000) into pW
   if pH is empty then put pW into pH
   put b2kClamp(pH, 1, 10000) into pH
   put b2kNumberOr(pScreenX, sOriginX) into pScreenX
   put b2kNumberOr(pScreenY, sOriginY) into pScreenY
   put "b2kspawn_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create graphic (tName)
   else
      create graphic (tName) in group "b2kcam_view"
   end if
   put the long id of graphic (tName) into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   set the style of tRef to "rectangle"
   set the filled of tRef to true
   set the foregroundColor of tRef to "20,20,24"
   if pColor is not empty then
      try
         set the backgroundColor of tRef to pColor
      catch tErr
         -- an unknown colour name (CSS names like "teal" are not LC/X11
         -- names) must not abort the spawn and orphan the control
      end try
   end if
   set the width of tRef to pW
   set the height of tRef to pH
   set the loc of tRef to round(pScreenX - b2kCamShiftX(tRef)) & "," & round(pScreenY - b2kCamShiftY(tRef))
   b2kAddBox tRef
   put true into sSpawned[tRef]
   return tRef
end b2kSpawnBox

/**
Summary: Create a filled circle graphic with a dynamic ball body.

pScreenX: Centre x in pixels. Not a number means the world origin's x.

pScreenY: Centre y in pixels. Not a number means the world origin's y.

pDiameter: Diameter in pixels. Empty means 40.

pColor: Optional fill colour. An unknown name is ignored.

Returns: The new control's long id through the result, or empty when there is no world.

Example:
b2kSpawnBall 200, 80, 50, "red"
put the result into tBall

Description:
The Kit owns the control: <b2kRemove> and <b2kClear> delete it.

References: b2kSpawnBox (handler), b2kAddBall (handler)
*/
command b2kSpawnBall pScreenX, pScreenY, pDiameter, pColor
   local tName, tRef
   if sWorld is empty then return empty
   if pDiameter is empty then put 40 into pDiameter
   put b2kClamp(pDiameter, 1, 10000) into pDiameter
   put b2kNumberOr(pScreenX, sOriginX) into pScreenX
   put b2kNumberOr(pScreenY, sOriginY) into pScreenY
   put "b2kspawn_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create graphic (tName)
   else
      create graphic (tName) in group "b2kcam_view"
   end if
   put the long id of graphic (tName) into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   set the style of tRef to "oval"
   set the filled of tRef to true
   set the foregroundColor of tRef to "20,20,24"
   if pColor is not empty then
      try
         set the backgroundColor of tRef to pColor
      catch tErr
         -- an unknown colour name (CSS names like "teal" are not LC/X11
         -- names) must not abort the spawn and orphan the control
      end try
   end if
   set the width of tRef to pDiameter
   set the height of tRef to pDiameter
   set the loc of tRef to round(pScreenX - b2kCamShiftX(tRef)) & "," & round(pScreenY - b2kCamShiftY(tRef))
   b2kAddBall tRef
   put true into sSpawned[tRef]
   return tRef
end b2kSpawnBall

-- Create a pill-shaped graphic and attach a capsule body. pLength is along the
-- pill's long axis, pThickness across it; horizontal if pLength >= pThickness.
/**
Summary: Create a pill-shaped graphic with a dynamic capsule body.

pScreenX: Centre x in pixels. Not a number means the world origin's x.

pScreenY: Centre y in pixels. Not a number means the world origin's y.

pLength: Length along the pill's axis in pixels. Empty means 80.

pThickness: Thickness across the pill in pixels. Empty means 40.

pColor: Optional fill colour. An unknown name is ignored.

Returns: The new control's long id through the result, or empty when there is no world.

Example:
b2kSpawnCapsule 200, 100, 64, 30, "gold"
put the result into tHero

Description:
The pill is horizontal when the length is at least the thickness,
vertical otherwise. The Kit owns the control.

References: b2kSpawnBox (handler), b2kAddCapsule (handler)
*/
command b2kSpawnCapsule pScreenX, pScreenY, pLength, pThickness, pColor
   local tName, tRef
   if sWorld is empty then return empty
   if pLength is empty then put 80 into pLength
   if pThickness is empty then put 40 into pThickness
   put b2kClamp(pLength, 1, 10000) into pLength
   put b2kClamp(pThickness, 1, 10000) into pThickness
   put b2kNumberOr(pScreenX, sOriginX) into pScreenX
   put b2kNumberOr(pScreenY, sOriginY) into pScreenY
   put "b2kspawn_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create graphic (tName)
   else
      create graphic (tName) in group "b2kcam_view"
   end if
   put the long id of graphic (tName) into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   set the style of tRef to "polygon"
   set the filled of tRef to true
   set the foregroundColor of tRef to "20,20,24"
   if pColor is not empty then
      try
         set the backgroundColor of tRef to pColor
      catch tErr
         -- an unknown colour name (CSS names like "teal" are not LC/X11
         -- names) must not abort the spawn and orphan the control
      end try
   end if
   if pLength >= pThickness then
      set the width of tRef to pLength
      set the height of tRef to pThickness
   else
      set the width of tRef to pThickness
      set the height of tRef to pLength
   end if
   set the loc of tRef to round(pScreenX - b2kCamShiftX(tRef)) & "," & round(pScreenY - b2kCamShiftY(tRef))
   b2kAddCapsule tRef
   put true into sSpawned[tRef]
   return tRef
end b2kSpawnCapsule

-- =====================================================================
-- Materials & body properties
-- =====================================================================
/**
Summary: Set how bouncy a control's shape is (restitution).

pControl: The control, by reference (the long id of the control is safest).

pRestitution: 0 for no bounce up to 1 for a full bounce; clamped to 0-2.

Example:
b2kSetBounce tBall, 0.8

Description:
A control with no Kit shape is ignored.

References: b2kSetFriction (handler), b2kSetDensity (handler), b2kSetRestitutionThreshold (handler)
*/
command b2kSetBounce pControl, pRestitution
   local s
   put sShapeH[the long id of pControl] into s
   put b2kClamp(pRestitution, 0, 2) into pRestitution
   if s is not empty then b2SetShapeRestitution s, pRestitution
end b2kSetBounce

/**
Summary: Set a control's shape friction.

pControl: The control, by reference (the long id of the control is safest).

pFriction: Friction, usually 0 (ice) to 1 (rubber); clamped to 0-10.

Example:
b2kSetFriction tCrate, 0.1

Description:
A control with no Kit shape is ignored.

References: b2kSetBounce (handler), b2kSetDensity (handler)
*/
command b2kSetFriction pControl, pFriction
   local s
   put sShapeH[the long id of pControl] into s
   put b2kClamp(pFriction, 0, 10) into pFriction
   if s is not empty then b2SetShapeFriction s, pFriction
end b2kSetFriction

/**
Summary: Set a control's shape density, which sets its mass.

pControl: The control, by reference (the long id of the control is safest).

pDensity: Density in kilograms per square metre; clamped to 0-10000. The default is 1.

Example:
b2kSetDensity tCrate, 5

Description:
A control with no Kit shape is ignored.

References: b2kMass (handler), b2kSetBounce (handler)
*/
command b2kSetDensity pControl, pDensity
   local s
   put sShapeH[the long id of pControl] into s
   put b2kClamp(pDensity, 0, 10000) into pDensity
   if s is not empty then b2SetShapeDensity s, pDensity
end b2kSetDensity

-- Re-fit a body's collision shape to the control's CURRENT size, in place on the
-- SAME body so any joints stay valid. pShape is "box" | "ball" | "capsule" | "poly".
-- Resize the control's graphic first, then re-apply materials afterwards.
-- ENGINE-FOUND 2026-08-17 (run 5's duck instrumentation): pW/pH, when given,
-- are EXPLICIT pixel dims that replace the control-rect read for box/ball/
-- capsule. Two engine facts force the option: OXT will not resize a polygon
-- graphic by a height-set (its rect is derived from its points, so the
-- player's duck "resize the control first" never landed and the capsule
-- rebuilt at FULL height -- the crawl wedged on the ceiling's face with the
-- bookkeeping insisting it was short), and the drawer's re-point pads the
-- rect by the pen margin, so re-reading the rect compounds +2 per rebuild
-- (50 -> 52 -> 54 across one duck/stand pair, the engine's own numbers).
/**
Summary: Rebuild a body's collision shape from the control's current size.

pControl: The control, by reference (the long id of the control is safest).

pShape: "box" (the default), "ball", "capsule" or "poly".

pW: Optional width in pixels to use instead of the control's width (box, ball and capsule).

pH: Optional height in pixels to use instead of the control's height (box and capsule).

Example:
set the width of tPlank to 200
b2kReshape tPlank, "box"
b2kSetFriction tPlank, 0.6

Description:
The new shape goes on the same body, so joints stay valid, and the
control is redrawn at once. The new shape has the default material and
collision filter, so re-apply bounce, friction, density and layers after it.
A sensor stays a sensor. If the new size is zero, or a poly outline has
fewer than 3 points, the old shape is kept.

Pass pW and pH for a polygon graphic: the engine will not resize one by
setting its height.

References: b2kAddBox (handler), b2kSetSensor (handler), b2kSetCategory (handler)
*/
command b2kReshape pControl, pShape, pW, pH
   local tRef, tBody, tOld, tHw, tHh, tWm, tHm, tR, tL, tHoriz, tCx, tCy, p, lx, ly, tCount, tNewVerts
   local tWx, tWy, tWa
   set the itemDelimiter to comma   -- locs and anchors are "x,y" (gotcha 5)
   put the long id of pControl into tRef
   if sBody[tRef] is empty then exit b2kReshape
   put sBody[tRef] into tBody
   -- Build the new shape first and drop the old one only afterwards, so the body
   -- is never momentarily shapeless and a rejected shape leaves the original
   -- intact (any joints on the body stay valid throughout).
   put sShapeH[tRef] into tOld
   put empty into sShapeH[tRef]
   b2ShapeDefEnableSensorEvents true   -- keep the reshaped body detectable by sensors
   if sSensor[tRef] is true then b2ShapeDefSensor true   -- a sensor stays a sensor after reshaping
   switch pShape
      case "ball"
         if pW is a number and pW > 0 then
            put (pW / 2) / sScale into tR
         else
            put ((the width of pControl) / 2) / sScale into tR
         end if
         if tR <= 0 then
            put tOld into sShapeH[tRef]
            b2ShapeDefReset   -- drop the pending one-shot flags set above
            exit b2kReshape
         end if
         put b2AddCircle(tBody, 0, 0, tR, 1.0, 0.4, 0.4) into sShapeH[tRef]
         put tR into sRad[tRef]
         break
      case "capsule"
         if pW is a number and pW > 0 then
            put pW / sScale into tWm
         else
            put (the width of pControl) / sScale into tWm
         end if
         if pH is a number and pH > 0 then
            put pH / sScale into tHm
         else
            put (the height of pControl) / sScale into tHm
         end if
         if tWm <= 0 or tHm <= 0 then
            put tOld into sShapeH[tRef]
            b2ShapeDefReset   -- drop the pending one-shot flags set above
            exit b2kReshape
         end if
         put (tWm >= tHm) into tHoriz
         if tHoriz then
            put tHm / 2 into tR
            put max(0, tWm / 2 - tR) into tL
            put b2AddCapsule(tBody, - tL, 0, tL, 0, tR, 1.0, 0.4, 0.2) into sShapeH[tRef]
         else
            put tWm / 2 into tR
            put max(0, tHm / 2 - tR) into tL
            put b2AddCapsule(tBody, 0, - tL, 0, tL, tR, 1.0, 0.4, 0.2) into sShapeH[tRef]
         end if
         put b2kCapsuleVerts(tL, tR, tHoriz) into sVerts[tRef]
         break
      case "poly"
         put item 1 of the loc of pControl into tCx
         put item 2 of the loc of pControl into tCy
         b2PolyBegin
         put empty into tNewVerts
         put 0 into tCount
         repeat for each line p in the points of pControl
            if p is empty then next repeat
            if tCount >= 8 then next repeat
            put (item 1 of p - tCx) / sScale into lx
            put - ((item 2 of p - tCy) / sScale) into ly
            b2PolyAddPoint lx, ly
            put lx & "," & ly & cr after tNewVerts
            add 1 to tCount
         end repeat
         if tCount < 3 then           -- degenerate outline: keep the existing shape
            put tOld into sShapeH[tRef]
            b2ShapeDefReset   -- drop the pending one-shot flags set above
            exit b2kReshape
         end if
         put b2AddPolygon(tBody, 1.0, 0.4, 0.2) into sShapeH[tRef]
         put tNewVerts into sVerts[tRef]
         break
      default
         if pW is a number and pW > 0 then
            put (pW / 2) / sScale into tHw
         else
            put ((the width of pControl) / 2) / sScale into tHw
         end if
         if pH is a number and pH > 0 then
            put (pH / 2) / sScale into tHh
         else
            put ((the height of pControl) / 2) / sScale into tHh
         end if
         if tHw <= 0 or tHh <= 0 then
            put tOld into sShapeH[tRef]
            b2ShapeDefReset   -- drop the pending one-shot flags set above
            exit b2kReshape
         end if
         put b2AddBox(tBody, tHw, tHh, 1.0, 0.4, 0.2) into sShapeH[tRef]
         if sRender[tRef] is "poly" then
            put ("-" & tHw) & "," & ("-" & tHh) & cr & tHw & "," & ("-" & tHh) & cr \
                  & tHw & "," & tHh & cr & ("-" & tHw) & "," & tHh into sVerts[tRef]
         end if
   end switch
   if tOld is not empty then b2DestroyShape tOld   -- now safe to release the old shape
   -- The size/outline changed but the body need not have moved, so the move-event
   -- sync would skip it (an at-rest body produces no move event). Bust the
   -- pose-keyed draw cache and redraw at the body's current pose right now so the
   -- new shape is visible immediately, awake or asleep.
   delete variable sDrawKey[tRef]
   put b2BodyX(tBody) into tWx
   put b2BodyY(tBody) into tWy
   if sRender[tRef] is "poly" or sRender[tRef] is "image" then put b2BodyAngle(tBody) into tWa
   else put 0 into tWa
   lock screen
   b2kDrawBody tRef, tWx, tWy, tWa
   unlock screen
end b2kReshape

-- Every body-targeting wrapper resolves the control's body first and quietly
-- no-ops when there is none (unregistered, removed, or pre-setup): the kit's
-- contract is that a missing body is never a script error.
/**
Summary: Turn continuous collision on or off for one fast body.

pControl: The control, by reference (the long id of the control is safest).

pFlag: true to treat the body as a bullet, false for normal stepping.

Example:
b2kSetBullet tShot, true

Description:
A bullet does not tunnel through other moving bodies. A control with no Kit body is ignored.

References: b2kIsBullet (handler), b2kEnableContinuous (handler)
*/
command b2kSetBullet pControl, pFlag
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetBullet
   b2SetBullet b, (pFlag is true)
end b2kSetBullet

/**
Summary: Stop or allow a body's rotation.

pControl: The control, by reference (the long id of the control is safest).

pFlag: true to stop the body rotating, false to let it rotate.

Example:
b2kSetFixedRotation tHero, true

Description:
Characters usually want fixed rotation. A control with no Kit body is ignored.

References: b2kSpin (handler), b2kAngle (handler)
*/
command b2kSetFixedRotation pControl, pFlag
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetFixedRotation
   b2SetFixedRotation b, (pFlag is true)
end b2kSetFixedRotation

/**
Summary: Set a per-body gravity multiplier.

pControl: The control, by reference (the long id of the control is safest).

pScale: 1 is normal gravity, 0 none, a negative value floats the body up.

Example:
b2kSetGravityScale tBalloon, -0.4

Description:
A control with no Kit body is ignored.

References: b2kGravityScale (handler), b2kSetGravity (handler)
*/
command b2kSetGravityScale pControl, pScale
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetGravityScale
   b2SetGravityScale b, pScale
end b2kSetGravityScale

/**
Summary: Set a body's linear and angular damping (drag).

pControl: The control, by reference (the long id of the control is safest).

pLinear: Linear damping, 0 for none. Empty leaves it unchanged.

pAngular: Angular damping, 0 for none. Empty leaves it unchanged.

Example:
b2kSetDamping tFeather, 2, 1

Description:
A control with no Kit body is ignored.

References: b2kDamping (handler)
*/
command b2kSetDamping pControl, pLinear, pAngular
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetDamping
   if pLinear is not empty then b2SetLinearDamping b, pLinear
   if pAngular is not empty then b2SetAngularDamping b, pAngular
end b2kSetDamping

/**
Summary: Wake a sleeping body.

pControl: The control, by reference (the long id of the control is safest).

Example:
b2kWake tCrate

Description:
A control with no Kit body is ignored.

References: b2kSleep (handler), b2kIsAwake (handler)
*/
command b2kWake pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kWake
   b2SetAwake b, true
end b2kWake

-- Send a body to sleep (it stops simulating until something wakes it).
/**
Summary: Put a body to sleep until something wakes it.

pControl: The control, by reference (the long id of the control is safest).

Example:
b2kSleep tCrate

Description:
A sleeping body stops simulating until a contact, a joint or a call such as <b2kWake> wakes it. A control with no Kit body is ignored.

References: b2kWake (handler), b2kIsAwake (handler)
*/
command b2kSleep pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSleep
   b2SetAwake b, false
end b2kSleep

-- Allow or forbid THIS body ever falling asleep (vs b2kEnableSleeping,
-- which switches the whole world). The player controller forbids it: a
-- character must respond to input even after standing still for minutes.
/**
Summary: Allow or forbid one body ever falling asleep.

pControl: The control, by reference (the long id of the control is safest).

pFlag: true to allow sleep; anything else forbids it and wakes the body.

Example:
b2kSetSleepEnabled tHero, false

Description:
<b2kEnableSleeping> switches the whole world; this switches one
body. The player controller forbids sleep on its body so it always responds
to input. A control with no Kit body is ignored.

References: b2kEnableSleeping (handler), b2kSetSleepThreshold (handler)
*/
command b2kSetSleepEnabled pControl, pFlag
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetSleepEnabled
   b2EnableSleep b, (pFlag is true)
   if pFlag is not true then b2SetAwake b, true
end b2kSetSleepEnabled

-- Below this speed (pixels/sec) a body may fall asleep. Lower = stays awake
-- longer; higher = sleeps sooner (saves CPU).
/**
Summary: Set the speed below which a body may fall asleep.

pControl: The control, by reference (the long id of the control is safest).

pPxPerSec: The speed in pixels per second. Lower keeps the body awake longer.

Example:
b2kSetSleepThreshold tCrate, 4

Description:
A control with no Kit body is ignored.

References: b2kSetSleepEnabled (handler)
*/
command b2kSetSleepThreshold pControl, pPxPerSec
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetSleepThreshold
   b2SetSleepThreshold b, pPxPerSec / sScale
end b2kSetSleepThreshold

-- =====================================================================
-- Acting on bodies   (velocities/kicks are in PIXELS/sec, screen-oriented)
-- =====================================================================
/**
Summary: Set a body's velocity in pixels per second, and wake it.

pControl: The control, by reference (the long id of the control is safest).

pVxPx: Horizontal velocity in px/s (positive is right).

pVyPx: Vertical velocity in px/s (positive is down).

Example:
b2kSetVelocity tHero, b2kAxis("moveX") * 240, item 2 of b2kVelocity(tHero)

Description:
Setting a velocity always wakes the body. Do not write a velocity
every frame to a body that is meant to come to rest: it never sleeps. For a
player under the controller use <b2kPlayerJump> for upward boosts. A control with no Kit body is ignored.

References: b2kVelocity (handler), b2kPush (handler), b2kImpulse (handler)
*/
command b2kSetVelocity pControl, pVxPx, pVyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetVelocity
   b2SetVelocity b, pVxPx / sScale, - pVyPx / sScale
   -- setting a velocity means "move": wake the body. Raw SetVelocity
   -- does NOT wake (why b2kPush always called SetAwake) - a SLEEPING
   -- kinematic (a parked gate) given one cached write stayed frozen,
   -- which read as "the pressure plate is flaky".
   b2SetAwake b, true
end b2kSetVelocity

/**
Summary: Add to a body's velocity in pixels per second.

pControl: The control, by reference (the long id of the control is safest).

pDvxPx: Change in horizontal velocity, px/s.

pDvyPx: Change in vertical velocity, px/s (negative is up).

Example:
b2kPush tHero, 0, -420

Description:
A one-shot kick that ignores mass: every body gains the same speed.
It wakes the body. Use <b2kImpulse> for a mass-aware kick. A control with no Kit body is ignored.

References: b2kImpulse (handler), b2kSetVelocity (handler)
*/
command b2kPush pControl, pDvxPx, pDvyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kPush
   b2SetVelocity b, b2BodyVX(b) + pDvxPx / sScale, b2BodyVY(b) - pDvyPx / sScale
   b2SetAwake b, true
end b2kPush

/**
Summary: Set a body's angular velocity in degrees per second.

pControl: The control, by reference (the long id of the control is safest).

pDegPerSec: The spin rate in degrees per second.

Example:
b2kSpin tWheel, 360

Description:
It replaces the current spin. A control with no Kit body is ignored.

References: b2kSpinBy (handler), b2kSpinRate (handler)
*/
command b2kSpin pControl, pDegPerSec
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSpin
   b2SetAngularVelocity b, pDegPerSec * kPI / 180
end b2kSpin

-- Add to the current spin (vs b2kSpin which sets it absolutely).
/**
Summary: Add to a body's angular velocity, in degrees per second.

pControl: The control, by reference (the long id of the control is safest).

pDegPerSec: The change in spin rate, degrees per second.

Example:
b2kSpinBy tWheel, 90

Description:
It wakes the body. A control with no Kit body is ignored.

References: b2kSpin (handler), b2kAngularImpulse (handler)
*/
command b2kSpinBy pControl, pDegPerSec
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSpinBy
   b2SetAngularVelocity b, b2BodyAngularVelocity(b) + pDegPerSec * kPI / 180
   b2SetAwake b, true
end b2kSpinBy

-- Continuous, screen-oriented force (thrusters, wind). Apply each frame for a
-- sustained effect; b2kPush is the one-shot impulse equivalent.
/**
Summary: Apply a continuous force to a body's centre.

pControl: The control, by reference (the long id of the control is safest).

pFxPx: Horizontal force, scaled by the Kit's pixels per metre (positive is right).

pFyPx: Vertical force, scaled the same way (positive is down).

Example:
b2kForce tRocket, 0, -300

Description:
A force acts for one step, so call it every frame (from b2kFrame)
for thrust or wind. It wakes the body. A control with no Kit body is ignored.

References: b2kImpulse (handler), b2kTorque (handler)
*/
command b2kForce pControl, pFxPx, pFyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kForce
   b2ApplyForce b, pFxPx / sScale, - pFyPx / sScale, true
end b2kForce

-- A one-shot impulse (a sharp kick), screen-oriented. Mass-aware: heavier bodies
-- move less. b2kPush changes velocity directly; this is the impulse equivalent.
/**
Summary: Apply a one-shot, mass-aware impulse to a body's centre.

pControl: The control, by reference (the long id of the control is safest).

pIxPx: Horizontal impulse, scaled by the Kit's pixels per metre (positive is right).

pIyPx: Vertical impulse, scaled the same way (positive is down).

Example:
b2kImpulse tCrate, 0, -50

Description:
Heavier bodies move less. It wakes the body. A control with no Kit body is ignored.

References: b2kPush (handler), b2kForce (handler)
*/
command b2kImpulse pControl, pIxPx, pIyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kImpulse
   b2ApplyImpulse b, pIxPx / sScale, - pIyPx / sScale, true
end b2kImpulse

-- A continuous turning force (same units as motor torque). Positive turns one way,
-- negative the other. Apply each frame for a sustained twist; pairs with b2kForce.
/**
Summary: Apply a continuous turning force to a body.

pControl: The control, by reference (the long id of the control is safest).

pTorque: The torque, in Box2D units; the sign sets the direction.

Example:
b2kTorque tWheel, 20

Description:
Like <b2kForce>, call it every frame for a sustained twist. A control with no Kit body is ignored.

References: b2kAngularImpulse (handler), b2kForce (handler)
*/
command b2kTorque pControl, pTorque
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kTorque
   b2ApplyTorque b, pTorque, true
end b2kTorque

-- A one-shot twist (a sharp angular kick), mass-aware: bodies with more
-- rotational inertia turn less. b2kSpinBy sets the spin directly; this is the
-- impulse equivalent, and the angular partner of b2kImpulse.
/**
Summary: Apply a one-shot, mass-aware turning impulse.

pControl: The control, by reference (the long id of the control is safest).

pImpulse: The angular impulse, in Box2D units; the sign sets the direction.

Example:
b2kAngularImpulse tWheel, 2

Description:
Bodies with more rotational inertia turn less. A control with no Kit body is ignored.

References: b2kTorque (handler), b2kSpinBy (handler)
*/
command b2kAngularImpulse pControl, pImpulse
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kAngularImpulse
   b2ApplyAngularImpulse b, pImpulse, true
end b2kAngularImpulse

-- Change a body's type at runtime: "static", "kinematic", or "dynamic".
/**
Summary: Change a body's type by name.

pControl: The control, by reference (the long id of the control is safest).

pType: "static", "kinematic" or "dynamic"; any other value means dynamic.

Example:
b2kSetType tPlatform, "kinematic"

Description:
A kinematic body moves only by the velocity you give it and is not
pushed by others, which suits moving platforms. A non-static body is woken.
A control with no Kit body is ignored.

References: b2kSetStatic (handler), b2kSetDynamic (handler), b2kSetKinematic (handler), b2kBodyType (handler)
*/
command b2kSetType pControl, pType
   local tRef, tCode
   put the long id of pControl into tRef
   if sBody[tRef] is empty then exit b2kSetType
   switch pType
      case "static"
         put 0 into tCode
         break
      case "kinematic"
         put 1 into tCode
         break
      default
         put 2 into tCode
   end switch
   b2SetBodyType sBody[tRef], tCode
   put (tCode is 0) into sStatic[tRef]   -- only true statics are skipped by sync
   if tCode is not 0 then b2SetAwake sBody[tRef], true
   put true into sNeedFullSync
end b2kSetType

/**
Summary: Make a body static (immovable).

pControl: The control, by reference (the long id of the control is safest).

Example:
b2kSetStatic tCrate

Description:
The same as <b2kSetType> with "static".

References: b2kSetType (handler), b2kSetDynamic (handler)
*/
command b2kSetStatic pControl
   b2kSetType pControl, "static"
end b2kSetStatic

/**
Summary: Make a body dynamic (moved by forces and collisions).

pControl: The control, by reference (the long id of the control is safest).

Example:
b2kSetDynamic tCrate

Description:
The same as <b2kSetType> with "dynamic".

References: b2kSetType (handler), b2kSetStatic (handler)
*/
command b2kSetDynamic pControl
   b2kSetType pControl, "dynamic"
end b2kSetDynamic

/**
Summary: Make a body kinematic (moved only by its velocity).

pControl: The control, by reference (the long id of the control is safest).

Example:
b2kSetKinematic tLift
b2kSetVelocity tLift, 0, -60

Description:
The same as <b2kSetType> with "kinematic".

References: b2kSetType (handler), b2kSetVelocity (handler)
*/
command b2kSetKinematic pControl
   b2kSetType pControl, "kinematic"
end b2kSetKinematic

-- Temporarily take a body out of / put it back into the simulation.
/**
Summary: Take a body out of the simulation.

pControl: The control, by reference (the long id of the control is safest).

Example:
b2kMoveTo tDoor, -500, -500
b2kDisable tDoor

Description:
A disabled body has no gravity and no collisions and its control
stays where it is. Move it out of the way first if it should vanish. A control with no Kit body is ignored.

References: b2kEnable (handler), b2kIsEnabled (handler)
*/
command b2kDisable pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kDisable
   b2DisableBody b
end b2kDisable

/**
Summary: Put a disabled body back into the simulation.

pControl: The control, by reference (the long id of the control is safest).

Example:
b2kEnable tDoor

Description:
A control with no Kit body is ignored.

References: b2kDisable (handler), b2kIsEnabled (handler)
*/
command b2kEnable pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kEnable
   b2EnableBody b
   put true into sNeedFullSync
end b2kEnable

/**
Summary: Teleport a body to a screen point and angle.

pControl: The control, by reference (the long id of the control is safest).

pScreenX: The new centre x, in pixels.

pScreenY: The new centre y, in pixels.

pAngleDeg: The new angle in degrees. Empty means 0.

Example:
b2kMoveTo tCrate, 300, 100

Description:
The control is redrawn at once. Velocity is kept; follow it with
<b2kSetVelocity> to stop the body. A control with no Kit body is ignored.

References: b2kPosition (handler), b2kSetVelocity (handler), b2kSpriteMoveTo (handler)
*/
command b2kMoveTo pControl, pScreenX, pScreenY, pAngleDeg
   local tRef, tWx, tWy, tWa
   if pAngleDeg is empty then put 0 into pAngleDeg
   put the long id of pControl into tRef
   if sBody[tRef] is empty then exit b2kMoveTo
   put b2kToWorldX(pScreenX) into tWx
   put b2kToWorldY(pScreenY) into tWy
   put pAngleDeg * kPI / 180 into tWa
   b2SetTransform sBody[tRef], tWx, tWy, tWa
   b2kDrawBody tRef, tWx, tWy, tWa
end b2kMoveTo

/**
Summary: Destroy a control's body and forget it.

pControl: The control, by reference (the long id of the control is safest).

Example:
b2kRemove tCoin

Description:
If the Kit created the control (b2kSpawn commands, sprites) the
control is deleted too; a control you attached is left on the card. The
body's joints are destroyed with it.

References: b2kClear (handler), b2kSpriteRemove (handler)
*/
command b2kRemove pControl
   local tRef, tBody, tWasSpawned
   put the long id of pControl into tRef
   put sBody[tRef] into tBody
   if tBody is not empty and tBody > 0 then
      b2DestroyBody tBody
      delete variable sCtrl[tBody]
   end if
   put (sSpawned[tRef] is true) into tWasSpawned
   delete variable sBody[tRef]
   delete variable sShapeH[tRef]
   delete variable sRender[tRef]
   delete variable sVerts[tRef]
   delete variable sRad[tRef]
   delete variable sImgAngle[tRef]
   delete variable sStatic[tRef]
   delete variable sSpawned[tRef]
   delete variable sSensor[tRef]
   delete variable sInCam[tRef]
   -- If the kit created this control (b2kSpawn...), delete it too, so removing
   -- a body never leaves a dead graphic behind. Attached controls are left alone.
   if tWasSpawned then
      try
         delete tRef
      end try
   end if
end b2kRemove

-- A radial "blast" that kicks nearby dynamic bodies outward. Uses Box2D's native
-- b2World_Explode: it's shape-perimeter aware (so a wide plank catches more blast
-- than a small ball) and affects EVERY dynamic body in range, not just kit ones.
-- pPowerPx is the impulse per unit length of facing surface; pRadiusPx the reach.
/**
Summary: Push dynamic bodies away from a point with a radial blast.

pScreenX: The blast centre x, in pixels.

pScreenY: The blast centre y, in pixels.

pRadiusPx: The reach in pixels. Empty means 180.

pPowerPx: The impulse per unit of facing surface, scaled by the Kit's pixels per metre. Empty means 900.

Example:
b2kExplode the mouseH, the mouseV, 200, 1200

Description:
It uses Box2D's own explosion, which is shape-aware (a wide plank
catches more than a small ball) and affects every dynamic body in range, not
only Kit bodies. With no world it does nothing.

References: b2kExplodeLegacy (handler), b2kImpulse (handler)
*/
command b2kExplode pScreenX, pScreenY, pRadiusPx, pPowerPx
   if pRadiusPx is empty then put 180 into pRadiusPx
   if pPowerPx is empty then put 900 into pPowerPx
   if sWorld is empty then exit b2kExplode
   b2WorldExplode sWorld, b2kToWorldX(pScreenX), b2kToWorldY(pScreenY), \
         pRadiusPx / sScale, (pRadiusPx / sScale) * 0.5, pPowerPx / sScale
end b2kExplode

-- The original velocity-based blast (pre-v3): kicks only kit-tracked dynamic
-- bodies, ignoring their size. Kept for callers that relied on the old feel.
/**
Summary: The older velocity-based blast, for Kit bodies only.

pScreenX: The blast centre x, in pixels.

pScreenY: The blast centre y, in pixels.

pRadiusPx: The reach in pixels. Empty means 180.

pPowerPx: The speed added at the centre, falling to 0 at the edge. Empty means 900.

Example:
b2kExplodeLegacy 300, 200

Description:
It adds velocity directly to every non-static Kit body in range,
ignoring size and mass. Kept for scripts that relied on that feel; new code
should use <b2kExplode>.

References: b2kExplode (handler)
*/
command b2kExplodeLegacy pScreenX, pScreenY, pRadiusPx, pPowerPx
   local cx, cy, tRadM, tRef, b, dx, dy, d, f
   if pRadiusPx is empty then put 180 into pRadiusPx
   if pPowerPx is empty then put 900 into pPowerPx
   put b2kToWorldX(pScreenX) into cx
   put b2kToWorldY(pScreenY) into cy
   put pRadiusPx / sScale into tRadM
   repeat for each key tRef in sBody
      if sStatic[tRef] is true then next repeat
      put sBody[tRef] into b
      put b2BodyX(b) - cx into dx
      put b2BodyY(b) - cy into dy
      put sqrt(dx * dx + dy * dy) into d
      if d > 0.02 and d < tRadM then
         put (1 - d / tRadM) * (pPowerPx / sScale) into f
         b2SetVelocity b, b2BodyVX(b) + dx / d * f, b2BodyVY(b) + dy / d * f
         b2SetAwake b, true
      end if
   end repeat
end b2kExplodeLegacy

-- =====================================================================
-- Getters
-- =====================================================================
/**
Summary: The raw Box2D body handle behind a control.

pControl: The control, by reference (the long id of the control is safest).

Returns: The body handle, or empty when the control has no Kit body.

Example:
put b2kBodyOf(tCrate) into tBody

Description:
Use it to mix Kit code with calls to the raw b2 layer.

References: b2kWorld (handler), b2kRegister (handler)
*/
function b2kBodyOf pControl
   return sBody[the long id of pControl]
end b2kBodyOf

-- A body's position in SCREEN pixels as "x,y" (the position partner of
-- b2kVelocity). Controls already follow their body, but this reads the exact,
-- sub-pixel centre - handy for aiming, distance checks, or mixing with b2...
/**
Summary: A body's centre in screen pixels.

pControl: The control, by reference (the long id of the control is safest).

Returns: "x,y" in screen pixels (sub-pixel), or "0,0" when the control has no body.

Example:
put item 1 of b2kPosition(tHero) into tHeroX

References: b2kWorldCenter (handler), b2kVelocity (handler), b2kMoveTo (handler)
*/
function b2kPosition pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return b2kToScreenX(b2BodyX(b)) & "," & b2kToScreenY(b2BodyY(b))
end b2kPosition

-- A body's centre of mass in SCREEN pixels as "x,y". Differs from b2kPosition
-- for off-centre or compound shapes; it's the true pivot for spin and torque.
/**
Summary: A body's centre of mass in screen pixels.

pControl: The control, by reference (the long id of the control is safest).

Returns: "x,y" in screen pixels, or "0,0" when the control has no body.

Example:
put b2kWorldCenter(tLever) into tPivot

Description:
It differs from <b2kPosition> for off-centre shapes; it is the true pivot for spin and torque.

References: b2kPosition (handler)
*/
function b2kWorldCenter pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return b2kToScreenX(b2BodyWorldCenterX(b)) & "," & b2kToScreenY(b2BodyWorldCenterY(b))
end b2kWorldCenter

/**
Summary: A body's velocity in pixels per second.

pControl: The control, by reference (the long id of the control is safest).

Returns: "vx,vy" in px/s with y down, or "0,0" when the control has no body.

Example:
put item 2 of b2kVelocity(tHero) into tFallSpeed

References: b2kSetVelocity (handler), b2kSpeed (handler)
*/
function b2kVelocity pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return (b2BodyVX(b) * sScale) & "," & (- b2BodyVY(b) * sScale)
end b2kVelocity

/**
Summary: A body's speed in pixels per second.

pControl: The control, by reference (the long id of the control is safest).

Returns: The speed, or 0 when the control has no body.

Example:
if b2kSpeed(tBall) > 600 then b2kSound "whoosh"

References: b2kVelocity (handler)
*/
function b2kSpeed pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return sqrt((b2BodyVX(b) * sScale) ^ 2 + (b2BodyVY(b) * sScale) ^ 2)
end b2kSpeed

/**
Summary: A body's rotation in degrees.

pControl: The control, by reference (the long id of the control is safest).

Returns: The angle in degrees (counter-clockwise positive, not wrapped), or 0 when the control has no body.

Example:
put round(b2kAngle(tPlank)) into field "Angle"

References: b2kSpinRate (handler), b2kMoveTo (handler)
*/
function b2kAngle pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyAngle(b) * 180 / kPI
end b2kAngle

/**
Summary: Report whether a body is awake.

pControl: The control, by reference (the long id of the control is safest).

Returns: true or false; false when the control has no body.

Example:
if not b2kIsAwake(tCrate) then b2kWake tCrate

References: b2kWake (handler), b2kSleep (handler)
*/
function b2kIsAwake pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return false
   return b2BodyIsAwake(b)
end b2kIsAwake

-- Current rotation speed in DEGREES/sec (the getter for b2kSpin / b2kSpinBy).
/**
Summary: A body's rotation speed in degrees per second.

pControl: The control, by reference (the long id of the control is safest).

Returns: The angular velocity, or 0 when the control has no body.

Example:
put b2kSpinRate(tWheel) into tRate

References: b2kSpin (handler), b2kSpinBy (handler)
*/
function b2kSpinRate pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyAngularVelocity(b) * 180 / kPI
end b2kSpinRate

/**
Summary: Report whether a body uses continuous (bullet) collision.

pControl: The control, by reference (the long id of the control is safest).

Returns: true or false; false when the control has no body.

Example:
put b2kIsBullet(tShot) into tCCD

References: b2kSetBullet (handler)
*/
function b2kIsBullet pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return false
   return b2BodyIsBullet(b)
end b2kIsBullet

/**
Summary: Report whether a body is in the simulation.

pControl: The control, by reference (the long id of the control is safest).

Returns: true or false; false when the control has no body.

Example:
if not b2kIsEnabled(tDoor) then b2kEnable tDoor

References: b2kEnable (handler), b2kDisable (handler)
*/
function b2kIsEnabled pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return false
   return b2BodyIsEnabled(b)
end b2kIsEnabled

/**
Summary: A body's mass.

pControl: The control, by reference (the long id of the control is safest).

Returns: The mass in Box2D units (kilograms), or 0 when the control has no body.

Example:
put b2kMass(tCrate) into tMass

References: b2kSetDensity (handler)
*/
function b2kMass pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyMass(b)
end b2kMass

-- The body's per-body gravity multiplier (the getter for b2kSetGravityScale).
/**
Summary: A body's gravity multiplier.

pControl: The control, by reference (the long id of the control is safest).

Returns: The gravity scale, or 0 when the control has no body.

Example:
put b2kGravityScale(tBalloon) into tScale

References: b2kSetGravityScale (handler)
*/
function b2kGravityScale pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyGravityScale(b)
end b2kGravityScale

-- The body's drag as "linear,angular" (the getter for b2kSetDamping).
/**
Summary: A body's linear and angular damping.

pControl: The control, by reference (the long id of the control is safest).

Returns: "linear,angular", or "0,0" when the control has no body.

Example:
put item 1 of b2kDamping(tFeather) into tDrag

References: b2kSetDamping (handler)
*/
function b2kDamping pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return b2BodyLinearDamping(b) & "," & b2BodyAngularDamping(b)
end b2kDamping

-- Body type as a word: "static", "kinematic", or "dynamic" (mirrors b2kSetType).
/**
Summary: A body's type as a word.

pControl: The control, by reference (the long id of the control is safest).

Returns: "static", "kinematic" or "dynamic"; "static" when the control has no body.

Example:
if b2kBodyType(tCrate) is "dynamic" then b2kPush tCrate, 0, -200

References: b2kSetType (handler)
*/
function b2kBodyType pControl
   local b, tCode
   put sBody[the long id of pControl] into b
   if b is empty then return "static"
   put b2BodyType(b) into tCode
   if tCode is 1 then return "kinematic"
   if tCode is 2 then return "dynamic"
   return "static"
end b2kBodyType

-- How many bodies the kit is currently tracking.
/**
Summary: How many bodies the Kit is tracking.

Returns: The number of controls with a Kit body.

Example:
put b2kBodyCount() into field "Bodies"

References: b2kAwakeCount (handler), b2kAwakeBodyCount (handler)
*/
function b2kBodyCount
   return the number of lines of the keys of sBody
end b2kBodyCount

-- How many dynamic bodies are currently awake (i.e. actively simulating).
/**
Summary: How many non-static Kit bodies are awake.

Returns: The count, walked over the Kit's own bodies.

Example:
put b2kAwakeCount() into field "Awake"

Description:
<b2kAwakeBodyCount> asks Box2D instead and counts bodies the Kit does not track too.

References: b2kBodyCount (handler), b2kAwakeBodyCount (handler)
*/
function b2kAwakeCount
   local tRef, tCount
   put 0 into tCount
   repeat for each key tRef in sBody
      if sStatic[tRef] is not true and b2BodyIsAwake(sBody[tRef]) then add 1 to tCount
   end repeat
   return tCount
end b2kAwakeCount

-- Which attached control sits at a screen point (empty if none).
/**
Summary: The Kit control whose body covers a screen point.

pScreenX: The point's x, in pixels.

pScreenY: The point's y, in pixels.

Returns: The control's long id, or empty when no Kit body is there.

Example:
put b2kControlAt(the mouseH, the mouseV) into tPicked

Description:
With the camera on, pass world pixels from <b2kCamMouseX> and <b2kCamMouseY>.

References: b2kControlContains (handler), b2kGrab (handler)
*/
function b2kControlAt pScreenX, pScreenY
   if sWorld is empty then return empty
   return sCtrl[b2BodyAtPoint(sWorld, b2kToWorldX(pScreenX), b2kToWorldY(pScreenY))]
end b2kControlAt

-- True if SCREEN point (x,y) is inside this control's actual collision shape -
-- rotation- and shape-aware, unlike a bounding-box test. b2kControlAt searches
-- every body; this tests one control you already have (e.g. a precise click hit).
/**
Summary: Report whether a screen point is inside one control's collision shape.

pControl: The control, by reference (the long id of the control is safest).

pScreenX: The point's x, in pixels.

pScreenY: The point's y, in pixels.

Returns: true when the point is inside the shape (rotation and shape aware); false otherwise or when the control has no shape.

Example:
if b2kControlContains(tGear, the mouseH, the mouseV) then b2kSpin tGear, 180

References: b2kControlAt (handler)
*/
function b2kControlContains pControl, pScreenX, pScreenY
   local tRef
   put the long id of pControl into tRef
   if sShapeH[tRef] is empty then return false
   return b2ShapeTestPoint(sShapeH[tRef], b2kToWorldX(pScreenX), b2kToWorldY(pScreenY))
end b2kControlContains

-- Cast a ray between two screen points; returns the control hit (or empty).
-- Then b2kRayHitX() / b2kRayHitY() give the hit point in screen pixels.
/**
Summary: Cast a ray between two screen points and find the closest hit.

pX1: Start x, in pixels.

pY1: Start y, in pixels.

pX2: End x, in pixels.

pY2: End y, in pixels.

Returns: The Kit control hit, or empty when nothing is hit or the body is not a Kit body.

Example:
get b2kRayHit(100, 300, 600, 300)
put b2kRayHitX() into tHitX

Description:
After a hit, <b2kRayHitX>, <b2kRayHitY>, <b2kRayHitNormalX>,
<b2kRayHitNormalY> and <b2kRayDist> describe it; after a miss they are empty.
Walls and chains count as hits even though they return empty, so test
<b2kRayHitX> to tell a wall from a miss. A ray that starts inside a shape
does not report that shape.

References: b2kRayHitX (handler), b2kRayDist (handler), b2kRayHitAll (handler)
*/
function b2kRayHit pX1, pY1, pX2, pY2
   local dx, dy
   if sWorld is not empty and \
         b2CastRayClosest(sWorld, b2kToWorldX(pX1), b2kToWorldY(pY1), b2kToWorldX(pX2), b2kToWorldY(pY2)) then
      put round(b2kToScreenX(b2RayX())) into sRayX
      put round(b2kToScreenY(b2RayY())) into sRayY
      put b2RayNormalX() into sRayNX        -- surface normal, screen-oriented
      put - b2RayNormalY() into sRayNY
      put pX2 - pX1 into dx
      put pY2 - pY1 into dy
      put b2RayFraction() * sqrt(dx * dx + dy * dy) into sRayDist
      -- the handle is fetched for the control lookup anyway; stashing it
      -- lets the player's probe classify the ground (one-way chain or
      -- solid) without a single extra FFI call
      put b2RayBody() into sRayBodyH
      return sCtrl[sRayBodyH]
   end if
   put empty into sRayX
   put empty into sRayY
   put empty into sRayNX
   put empty into sRayNY
   put empty into sRayDist
   put empty into sRayBodyH
   return empty
end b2kRayHit

/**
Summary: The x of the last ray hit, in screen pixels.

Returns: The rounded x, or empty when the last ray missed.

Example:
if b2kRayHitX() is not empty then put b2kRayHitX() into tX

References: b2kRayHit (handler), b2kRayHitY (handler)
*/
function b2kRayHitX
   return sRayX
end b2kRayHitX

/**
Summary: The y of the last ray hit, in screen pixels.

Returns: The rounded y, or empty when the last ray missed.

Example:
put b2kRayHitY() into tGroundY

References: b2kRayHit (handler), b2kRayHitX (handler)
*/
function b2kRayHitY
   return sRayY
end b2kRayHitY

-- Surface normal (a unit direction, screen-oriented) at the last ray hit.
/**
Summary: The x part of the surface normal at the last ray hit.

Returns: A unit-vector component, screen oriented, or empty when the last ray missed.

Example:
put b2kRayHitNormalX() into tNX

References: b2kRayHit (handler), b2kRayHitNormalY (handler)
*/
function b2kRayHitNormalX
   return sRayNX
end b2kRayHitNormalX

/**
Summary: The y part of the surface normal at the last ray hit.

Returns: A unit-vector component, screen oriented (negative points up), or empty when the last ray missed.

Example:
if b2kRayHitNormalY() < -0.7 then put true into tIsFloor

References: b2kRayHit (handler), b2kRayHitNormalX (handler)
*/
function b2kRayHitNormalY
   return sRayNY
end b2kRayHitNormalY

-- Distance in pixels from the ray's start to the last hit point.
/**
Summary: The distance from the last ray's start to its hit, in pixels.

Returns: The distance, or empty when the last ray missed.

Example:
put b2kRayDist() into tGap

References: b2kRayHit (handler)
*/
function b2kRayDist
   return sRayDist
end b2kRayDist

-- ---- contacts, polling style ----------------------------------------
-- The kit also SENDS `on b2kContact` / `on b2kEndContact` to your
-- b2kContactTarget. These functions instead let you POLL the same snapshot
-- (e.g. from `on b2kFrame`) without registering a target. The snapshot
-- covers EVERY fixed step the frame ran (nothing lost on a 2-step frame,
-- nothing repeated on a 0-step one); indices are 1-based. Each accessor
-- returns the touching control's long id (empty for a wall, the ground,
-- or any body the kit isn't tracking).
/**
Summary: How many pairs of bodies began touching this frame.

Returns: The count, 0 when none.

Example:
if b2kContactCount() > 0 then put b2kContactA(1) && b2kContactB(1) into tPair

Description:
Poll it from b2kFrame instead of, or alongside, the b2kContact message. Events are collected after every fixed step of the frame, so none
is lost on a two-step frame or repeated on a zero-step one.

References: b2kContactA (handler), b2kContactB (handler), b2kEndContactCount (handler), b2kContactTarget (handler)
*/
function b2kContactCount
   if sEvtCN is empty then return 0
   return sEvtCN
end b2kContactCount

/**
Summary: The first control of a pair that began touching this frame.

pIndex: The 1-based index of the event within this frame.

Returns: The control's long id, or empty for a wall, the ground, an untracked body or an index out of range.

Example:
put b2kContactA(1) into tFirst

References: b2kContactCount (handler), b2kContactB (handler)
*/
function b2kContactA pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtCN then return empty
   return sCtrl[sEvtCA[pIndex]]
end b2kContactA

/**
Summary: The second control of a pair that began touching this frame.

pIndex: The 1-based index of the event within this frame.

Returns: The control's long id, or empty for a wall, the ground, an untracked body or an index out of range.

Example:
put b2kContactB(1) into tSecond

References: b2kContactCount (handler), b2kContactA (handler)
*/
function b2kContactB pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtCN then return empty
   return sCtrl[sEvtCB[pIndex]]
end b2kContactB

/**
Summary: How many pairs of bodies stopped touching this frame.

Returns: The count, 0 when none.

Example:
put b2kEndContactCount() into tPartings

Description:
Events are collected after every fixed step of the frame, so none
is lost on a two-step frame or repeated on a zero-step one.

References: b2kEndContactA (handler), b2kEndContactB (handler), b2kContactCount (handler)
*/
function b2kEndContactCount
   if sEvtEN is empty then return 0
   return sEvtEN
end b2kEndContactCount

/**
Summary: The first control of a pair that stopped touching this frame.

pIndex: The 1-based index of the event within this frame.

Returns: The control's long id, or empty for a wall, the ground, an untracked body or an index out of range.

Example:
put b2kEndContactA(1) into tFirst

References: b2kEndContactCount (handler), b2kEndContactB (handler)
*/
function b2kEndContactA pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtEN then return empty
   return sCtrl[sEvtEA[pIndex]]
end b2kEndContactA

/**
Summary: The second control of a pair that stopped touching this frame.

pIndex: The 1-based index of the event within this frame.

Returns: The control's long id, or empty for a wall, the ground, an untracked body or an index out of range.

Example:
put b2kEndContactB(1) into tSecond

References: b2kEndContactCount (handler), b2kEndContactA (handler)
*/
function b2kEndContactB pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtEN then return empty
   return sCtrl[sEvtEB[pIndex]]
end b2kEndContactB

-- =====================================================================
-- Joints (return a joint handle; pass it to b2kMotor / b2kRemoveJoint)
-- =====================================================================
-- Revolute pivot at screen point (x,y). If ctrlB is empty, pins ctrlA to the
-- world at that point (great for pendulums and swinging doors).
/**
Summary: Pin two controls together, or one to the world, at a screen point.

pCtrlA: The control, by reference (the long id of the control is safest).

pCtrlB: The second control, or empty to pin the first to the world.

pScreenX: The pivot x, in pixels.

pScreenY: The pivot y, in pixels.

Returns: The joint handle through the result, or 0 when a control has no body or there is no world.

Example:
b2kHinge tDoor, empty, 300, 120
put the result into tHinge
b2kHingeLimit tHinge, -90, 0

Description:
A revolute joint: the bodies keep the pivot point in common and
rotate freely about it. Good for pendulums, doors and wheels on a fixed axle.

References: b2kMotor (handler), b2kHingeLimit (handler), b2kHingeAngle (handler), b2kRemoveJoint (handler)
*/
command b2kHinge pCtrlA, pCtrlB, pScreenX, pScreenY
   local bA, bB, wx, wy, aA, aB, j
   set the itemDelimiter to comma   -- locs and anchors are "x,y" (gotcha 5)
   put sBody[the long id of pCtrlA] into bA
   if bA is empty or sWorld is empty then return 0
   if pCtrlB is not empty and sBody[the long id of pCtrlB] is empty then return 0
   put b2kToWorldX(pScreenX) into wx
   put b2kToWorldY(pScreenY) into wy
   put b2kLocalAnchor(bA, wx, wy) into aA
   if pCtrlB is empty then
      put sDragAnchor into bB
      put wx & "," & wy into aB
   else
      put sBody[the long id of pCtrlB] into bB
      put b2kLocalAnchor(bB, wx, wy) into aB
   end if
   put b2RevoluteJoint(sWorld, bA, bB, item 1 of aA, item 2 of aA, item 1 of aB, item 2 of aB, false) into j
   return j
end b2kHinge

/**
Summary: Glue two controls rigidly together.

pCtrlA: The control, by reference (the long id of the control is safest).

pCtrlB: The second control, by reference.

Returns: The joint handle through the result, or 0 when a control has no body or there is no world.

Example:
b2kWeld tCart, tCrate
put the result into tGlue

Description:
The bodies keep their current relative position and angle. <b2kWeldSpring> makes the weld springy.

References: b2kWeldSpring (handler), b2kRemoveJoint (handler)
*/
command b2kWeld pCtrlA, pCtrlB
   local bA, bB, wx, wy, aA, refA, j
   set the itemDelimiter to comma   -- locs and anchors are "x,y" (gotcha 5)
   put sBody[the long id of pCtrlA] into bA
   put sBody[the long id of pCtrlB] into bB
   if bA is empty or bB is empty or sWorld is empty then return 0
   put b2BodyX(bB) into wx
   put b2BodyY(bB) into wy
   put b2kLocalAnchor(bA, wx, wy) into aA
   put b2BodyAngle(bB) - b2BodyAngle(bA) into refA
   put b2WeldJoint(sWorld, bA, bB, item 1 of aA, item 2 of aA, 0, 0, refA, false) into j
   return j
end b2kWeld

-- Distance link. pLengthPx defaults to the current distance between centres.
/**
Summary: Link two controls by a distance joint between their centres.

pCtrlA: The control, by reference (the long id of the control is safest).

pCtrlB: The second control, by reference.

pLengthPx: The rest length in pixels. Empty means the current distance between the centres.

Returns: The joint handle through the result, or 0 when a control has no body or there is no world.

Example:
b2kRope tAnchor, tBob
put the result into tRope
b2kSpring tRope, 4, 0.3

Description:
As built, the joint holds the bodies at the rest length. Use
<b2kRopeRange> for a slack rope with a minimum and maximum, and <b2kSpring>
to make it springy.

References: b2kRopeRange (handler), b2kRopeLength (handler), b2kSpring (handler), b2kRemoveJoint (handler)
*/
command b2kRope pCtrlA, pCtrlB, pLengthPx
   local bA, bB, tLen, dx, dy, j
   put sBody[the long id of pCtrlA] into bA
   put sBody[the long id of pCtrlB] into bB
   if bA is empty or bB is empty or sWorld is empty then return 0
   if pLengthPx is empty then
      put b2BodyX(bB) - b2BodyX(bA) into dx
      put b2BodyY(bB) - b2BodyY(bA) into dy
      put sqrt(dx * dx + dy * dy) into tLen
   else
      put pLengthPx / sScale into tLen
   end if
   put b2DistanceJoint(sWorld, bA, bB, 0, 0, 0, 0, tLen, false) into j
   return j
end b2kRope

/**
Summary: Drive a hinge joint at a set speed.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

pDegPerSec: The target speed in degrees per second.

pMaxTorque: The most torque the motor may use. Empty means 1000.

Example:
b2kMotor tHinge, 180

References: b2kMotorOff (handler), b2kHinge (handler)
*/
command b2kMotor pJoint, pDegPerSec, pMaxTorque
   if pJoint is empty or pJoint <= 0 then exit b2kMotor
   if pMaxTorque is empty then put 1000 into pMaxTorque
   b2RevoluteEnableMotor pJoint, true, pDegPerSec * kPI / 180, pMaxTorque
end b2kMotor

-- Optional revolute (hinge) limits/readout. Angles are in DEGREES.
/**
Summary: Limit a hinge joint's angle.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

pLowerDeg: The lowest angle in degrees.

pUpperDeg: The highest angle in degrees.

Example:
b2kHingeLimit tHinge, -45, 45

Description:
Angles are measured from the pose the bodies had when the hinge was made.

References: b2kHingeLimitOff (handler), b2kHingeAngle (handler)
*/
command b2kHingeLimit pJoint, pLowerDeg, pUpperDeg
   if pJoint is empty or pJoint <= 0 then exit b2kHingeLimit
   b2RevoluteEnableLimit pJoint, true, pLowerDeg * kPI / 180, pUpperDeg * kPI / 180
end b2kHingeLimit

/**
Summary: A hinge joint's current angle.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

Returns: The angle in degrees, or 0 for an empty or 0 handle.

Example:
put round(b2kHingeAngle(tHinge)) into field "Angle"

References: b2kHingeLimit (handler), b2kHinge (handler)
*/
function b2kHingeAngle pJoint
   if pJoint is empty or pJoint <= 0 then return 0
   return b2RevoluteAngle(pJoint) * 180 / kPI
end b2kHingeAngle

-- Rope (distance) extras: read length, set a min/max range, make it springy.
/**
Summary: A distance joint's current length.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

Returns: The length in pixels, or 0 for an empty or 0 handle.

Example:
put b2kRopeLength(tRope) into tLen

References: b2kRopeSetLength (handler), b2kRope (handler)
*/
function b2kRopeLength pJoint
   if pJoint is empty or pJoint <= 0 then return 0
   return b2DistanceLength(pJoint) * sScale
end b2kRopeLength

-- Set a rope (distance) joint's exact rest length, in pixels.
/**
Summary: Set a distance joint's rest length.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

pLengthPx: The rest length in pixels.

Example:
b2kRopeSetLength tRope, 120

References: b2kRopeLength (handler), b2kRopeRange (handler)
*/
command b2kRopeSetLength pJoint, pLengthPx
   if pJoint is empty or pJoint <= 0 then exit b2kRopeSetLength
   b2DistanceSetLength pJoint, pLengthPx / sScale
end b2kRopeSetLength

/**
Summary: Set a distance joint's minimum and maximum length.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

pMinPx: The shortest length in pixels.

pMaxPx: The longest length in pixels.

Example:
b2kRopeRange tRope, 0, 200

References: b2kRope (handler), b2kRopeSetLength (handler)
*/
command b2kRopeRange pJoint, pMinPx, pMaxPx
   if pJoint is empty or pJoint <= 0 then exit b2kRopeRange
   b2DistanceSetLengthRange pJoint, pMinPx / sScale, pMaxPx / sScale
end b2kRopeRange

/**
Summary: Make a distance joint springy.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

pHertz: The spring stiffness in hertz.

pDamping: The damping ratio. Empty means 0.5.

Example:
b2kSpring tRope, 3, 0.2

References: b2kRope (handler), b2kWeldSpring (handler), b2kWheelSpring (handler)
*/
command b2kSpring pJoint, pHertz, pDamping
   if pJoint is empty or pJoint <= 0 then exit b2kSpring
   if pDamping is empty then put 0.5 into pDamping
   b2DistanceEnableSpring pJoint, true, pHertz, pDamping
end b2kSpring

-- Make a weld springy (0 hertz = rigid again).
/**
Summary: Make a weld joint springy.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

pHertz: The stiffness in hertz for both the linear and angular parts; 0 makes the weld rigid again.

pDamping: The damping ratio. Empty means 0.5.

Example:
b2kWeldSpring tGlue, 5

References: b2kWeld (handler), b2kSpring (handler)
*/
command b2kWeldSpring pJoint, pHertz, pDamping
   if pJoint is empty or pJoint <= 0 then exit b2kWeldSpring
   if pDamping is empty then put 0.5 into pDamping
   b2WeldSetStiffness pJoint, pHertz, pDamping, pHertz, pDamping
end b2kWeldSpring

-- Slider (prismatic): constrain pCtrlA to slide along an axis relative to
-- pCtrlB (or the world if empty). pAxisDeg is the on-screen slide direction
-- (0 = horizontal, 90 = vertical; default vertical). Drive it with b2kSliderMotor.
/**
Summary: Let one control slide along an axis relative to another, or to the world.

pCtrlA: The control that slides, by reference.

pCtrlB: The control it slides against, or empty for the world.

pAxisDeg: The on-screen slide direction in degrees: 0 is horizontal, 90 vertical. Empty means 90.

Returns: The joint handle through the result, or 0 when a control has no body or there is no world.

Example:
b2kSlider tLift, empty, 90
put the result into tTrack
b2kSliderLimit tTrack, -200, 0

Description:
A prismatic joint. Drive it with <b2kSliderMotor> and bound it with <b2kSliderLimit>.

References: b2kSliderMotor (handler), b2kSliderLimit (handler), b2kSliderPos (handler), b2kRemoveJoint (handler)
*/
command b2kSlider pCtrlA, pCtrlB, pAxisDeg
   local bMover, bFixed, wax, way, ca, sa, lax, lay, anchX, anchY, aFix, aMov, refA, fixAng, j
   set the itemDelimiter to comma   -- locs and anchors are "x,y" (gotcha 5)
   put sBody[the long id of pCtrlA] into bMover
   if pCtrlB is empty then put sDragAnchor into bFixed
   else put sBody[the long id of pCtrlB] into bFixed
   if bMover is empty or bFixed is empty or sWorld is empty then return 0
   if pAxisDeg is empty then put 90 into pAxisDeg
   put cos(pAxisDeg * kPI / 180) into wax
   put - sin(pAxisDeg * kPI / 180) into way
   put b2BodyAngle(bFixed) into fixAng
   put cos(- fixAng) into ca
   put sin(- fixAng) into sa
   put wax * ca - way * sa into lax
   put wax * sa + way * ca into lay
   put b2BodyX(bMover) into anchX
   put b2BodyY(bMover) into anchY
   put b2kLocalAnchor(bFixed, anchX, anchY) into aFix
   put b2kLocalAnchor(bMover, anchX, anchY) into aMov
   put b2BodyAngle(bMover) - fixAng into refA
   put b2PrismaticJoint(sWorld, bFixed, bMover, item 1 of aFix, item 2 of aFix, \
         item 1 of aMov, item 2 of aMov, lax, lay, refA, false) into j
   return j
end b2kSlider

/**
Summary: Drive a slider joint at a set speed.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

pPxPerSec: The target speed in pixels per second along the axis.

pMaxForce: The most force the motor may use. Empty means 1000.

Example:
b2kSliderMotor tTrack, 80

References: b2kSliderMotorOff (handler), b2kSlider (handler)
*/
command b2kSliderMotor pJoint, pPxPerSec, pMaxForce
   if pJoint is empty or pJoint <= 0 then exit b2kSliderMotor
   if pMaxForce is empty then put 1000 into pMaxForce
   b2PrismaticEnableMotor pJoint, true, pPxPerSec / sScale, pMaxForce
end b2kSliderMotor

/**
Summary: Limit a slider joint's travel.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

pLowerPx: The lowest translation in pixels.

pUpperPx: The highest translation in pixels.

Example:
b2kSliderLimit tTrack, -200, 0

Description:
Translation is measured along the joint's axis from where the joint was made.

References: b2kSliderLimitOff (handler), b2kSliderPos (handler)
*/
command b2kSliderLimit pJoint, pLowerPx, pUpperPx
   if pJoint is empty or pJoint <= 0 then exit b2kSliderLimit
   b2PrismaticEnableLimit pJoint, true, pLowerPx / sScale, pUpperPx / sScale
end b2kSliderLimit

/**
Summary: A slider joint's current translation.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

Returns: The translation in pixels along the axis, or 0 for an empty or 0 handle.

Example:
if b2kSliderPos(tTrack) <= -200 then b2kSliderMotor tTrack, 80

References: b2kSliderLimit (handler), b2kSlider (handler)
*/
function b2kSliderPos pJoint
   if pJoint is empty or pJoint <= 0 then return 0
   return b2PrismaticTranslation(pJoint) * sScale
end b2kSliderPos

-- Wheel: a sprung sliding axis + free spin (vehicle wheels). pChassis carries
-- pWheel; anchor defaults to the wheel's centre, suspension axis to world "up".
-- Drive with b2kWheelMotor, tune ride with b2kWheelSpring.
/**
Summary: Attach a wheel to a chassis with a sprung axis and free spin.

pChassis: The chassis control, by reference.

pWheel: The wheel control, by reference.

pScreenX: The anchor x in pixels. Empty means the wheel's centre.

pScreenY: The anchor y in pixels, used when an anchor x is given.

pAxisDeg: The suspension axis in screen degrees. Empty means straight up.

Returns: The joint handle through the result, or 0 when a control has no body or there is no world.

Example:
b2kWheel tCar, tFrontWheel
put the result into tAxle
b2kWheelMotor tAxle, -720

References: b2kWheelMotor (handler), b2kWheelSpring (handler), b2kRemoveJoint (handler)
*/
command b2kWheel pChassis, pWheel, pScreenX, pScreenY, pAxisDeg
   local bA, bB, anchX, anchY, aA, aB, wax, way, ca, sa, lax, lay, angA, j
   set the itemDelimiter to comma   -- locs and anchors are "x,y" (gotcha 5)
   put sBody[the long id of pChassis] into bA
   put sBody[the long id of pWheel] into bB
   if bA is empty or bB is empty or sWorld is empty then return 0
   if pScreenX is empty then
      put b2BodyX(bB) into anchX
      put b2BodyY(bB) into anchY
   else
      put b2kToWorldX(pScreenX) into anchX
      put b2kToWorldY(pScreenY) into anchY
   end if
   if pAxisDeg is empty then
      put 0 into wax
      put 1 into way
   else
      put cos(pAxisDeg * kPI / 180) into wax
      put - sin(pAxisDeg * kPI / 180) into way
   end if
   put b2BodyAngle(bA) into angA
   put cos(- angA) into ca
   put sin(- angA) into sa
   put wax * ca - way * sa into lax
   put wax * sa + way * ca into lay
   put b2kLocalAnchor(bA, anchX, anchY) into aA
   put b2kLocalAnchor(bB, anchX, anchY) into aB
   put b2WheelJoint(sWorld, bA, bB, item 1 of aA, item 2 of aA, \
         item 1 of aB, item 2 of aB, lax, lay, false) into j
   return j
end b2kWheel

/**
Summary: Drive a wheel joint at a set spin speed.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

pDegPerSec: The target spin in degrees per second.

pMaxTorque: The most torque the motor may use. Empty means 1000.

Example:
b2kWheelMotor tAxle, -720

References: b2kWheelMotorOff (handler), b2kWheel (handler)
*/
command b2kWheelMotor pJoint, pDegPerSec, pMaxTorque
   if pJoint is empty or pJoint <= 0 then exit b2kWheelMotor
   if pMaxTorque is empty then put 1000 into pMaxTorque
   b2WheelEnableMotor pJoint, true, pDegPerSec * kPI / 180, pMaxTorque
end b2kWheelMotor

/**
Summary: Tune a wheel joint's suspension.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

pHertz: The spring stiffness in hertz. Empty means 4.

pDamping: The damping ratio. Empty means 0.7.

Example:
b2kWheelSpring tAxle, 6, 0.5

References: b2kWheel (handler)
*/
command b2kWheelSpring pJoint, pHertz, pDamping
   if pJoint is empty or pJoint <= 0 then exit b2kWheelSpring
   if pHertz is empty then put 4 into pHertz
   if pDamping is empty then put 0.7 into pDamping
   b2WheelEnableSpring pJoint, true, pHertz, pDamping
end b2kWheelSpring

-- OFF switches: the b2k... joint wrappers above only ever turn a feature ON, so
-- these let callers disable a motor or limit again (free swing / unbounded slide).
/**
Summary: Turn a hinge joint's motor off.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

Example:
b2kMotorOff tHinge

Description:
The hinge swings freely again.

References: b2kMotor (handler)
*/
command b2kMotorOff pJoint
   if pJoint is not empty and pJoint > 0 then b2RevoluteEnableMotor pJoint, false, 0, 0
end b2kMotorOff

/**
Summary: Remove a hinge joint's angle limits.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

Example:
b2kHingeLimitOff tHinge

References: b2kHingeLimit (handler)
*/
command b2kHingeLimitOff pJoint
   if pJoint is not empty and pJoint > 0 then b2RevoluteEnableLimit pJoint, false, 0, 0
end b2kHingeLimitOff

/**
Summary: Turn a slider joint's motor off.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

Example:
b2kSliderMotorOff tTrack

References: b2kSliderMotor (handler)
*/
command b2kSliderMotorOff pJoint
   if pJoint is not empty and pJoint > 0 then b2PrismaticEnableMotor pJoint, false, 0, 0
end b2kSliderMotorOff

/**
Summary: Remove a slider joint's travel limits.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

Example:
b2kSliderLimitOff tTrack

References: b2kSliderLimit (handler)
*/
command b2kSliderLimitOff pJoint
   if pJoint is not empty and pJoint > 0 then b2PrismaticEnableLimit pJoint, false, 0, 0
end b2kSliderLimitOff

/**
Summary: Turn a wheel joint's motor off.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

Example:
b2kWheelMotorOff tAxle

References: b2kWheelMotor (handler)
*/
command b2kWheelMotorOff pJoint
   if pJoint is not empty and pJoint > 0 then b2WheelEnableMotor pJoint, false, 0, 0
end b2kWheelMotorOff

/**
Summary: Destroy a joint.

pJoint: The joint handle a Kit joint constructor reported. Empty or 0 makes this a no-op.

Example:
b2kRemoveJoint tRope

Description:
Works for every joint the Kit makes, including <b2kMotorTo> and <b2kNoCollide> joints. A stale handle is harmless.

References: b2kHinge (handler), b2kRope (handler), b2kNoCollide (handler)
*/
command b2kRemoveJoint pJoint
   if pJoint is not empty and pJoint > 0 then b2DestroyJoint pJoint
end b2kRemoveJoint

/**
Summary: Convert a world point to a raw body's local frame.

pBody: A raw body handle (see b2kBodyOf).

pWx: The world x, in metres.

pWy: The world y, in metres.

Returns: "lx,ly" in metres in the body's local frame.

Example:
put b2kLocalAnchor(b2kBodyOf(tDoor), b2kToWorldX(300), b2kToWorldY(120)) into tAnchor

Description:
A helper the joint constructors use to place anchors.

References: b2kBodyOf (handler), b2kHinge (handler)
*/
function b2kLocalAnchor pBody, pWx, pWy
   local bcx, bcy, ba, dx, dy, c, s
   put b2BodyX(pBody) into bcx
   put b2BodyY(pBody) into bcy
   put b2BodyAngle(pBody) into ba
   put pWx - bcx into dx
   put pWy - bcy into dy
   put cos(- ba) into c
   put sin(- ba) into s
   return (dx * c - dy * s) & "," & (dx * s + dy * c)
end b2kLocalAnchor

-- =====================================================================
-- Sensors (non-solid trigger zones)
-- =====================================================================
-- Attach a SENSOR fixture to a control: it reports overlaps but never blocks.
-- Static by default (a fixed trigger zone); pShape is "box" (default), "ball" or
-- "capsule". While the loop runs, overlaps are delivered to your b2kContactTarget
-- as `on b2kSensorEnter pSensorCtrl, pVisitorCtrl` / `on b2kSensorExit ...`. The
-- kit enables sensor events on every body it creates, so sensors detect them.
/**
Summary: Give a control a static sensor body: it reports overlaps but never blocks.

pControl: The control, by reference (the long id of the control is safest).

pShape: "box" (the default), "ball" or "capsule".

Returns: The body handle through the result, or 0 when there is no world or the control has no size.

Example:
b2kAddSensor the long id of graphic "Goal"
b2kContactTarget the long id of me

Description:
Each frame, bodies that entered or left the sensor are reported to
the contact target (<b2kContactTarget>) as b2kSensorEnter and b2kSensorExit,
with the sensor control and the visitor control. The frame target does not
get them. The Kit enables sensor events on every body it creates, so its
bodies are detected.

Sensor messages suit one-shot triggers such as coins and goals. For presence
(pressure plates) poll <b2kOverlapMoving> each frame instead.

References: b2kSensorCount (handler), b2kSetSensor (handler), b2kOverlapMoving (handler)
*/
command b2kAddSensor pControl, pShape
   local tRef
   if sWorld is empty then return 0
   put the long id of pControl into tRef
   b2ShapeDefSensor true
   b2ShapeDefEnableSensorEvents true
   switch pShape
      case "ball"
         b2kAddBall pControl, false
         break
      case "capsule"
         b2kAddCapsule pControl, false
         break
      default
         b2kAddBox pControl, false
   end switch
   if sBody[tRef] is empty then
      -- the attach bailed (zero-sized control): clear the pending one-shot
      -- sensor flags so they cannot leak onto the next shape someone creates
      b2ShapeDefReset
      return 0
   end if
   put true into sSensor[tRef]
   return sBody[tRef]
end b2kAddSensor

-- Flip a control's collision between solid and SENSOR (a non-solid trigger that
-- reports overlaps but never blocks). The flag lives on the shape, so rebuild the
-- shape afterwards with b2kReshape - it re-applies the sensor state from here.
/**
Summary: Mark a control's shape as a sensor or as solid, for its next rebuild.

pControl: The control, by reference (the long id of the control is safest).

pFlag: true for a sensor, anything else for solid.

Example:
b2kSetSensor tZone, true
b2kReshape tZone, "box"

Description:
The sensor flag lives on the shape, so this only records the
choice. Rebuild the shape with <b2kReshape> to apply it.

References: b2kReshape (handler), b2kAddSensor (handler)
*/
command b2kSetSensor pControl, pFlag
   put (pFlag is true) into sSensor[the long id of pControl]
end b2kSetSensor

-- Polling alternative to the on b2kSensorEnter/Exit messages (read in on b2kFrame).
-- Counts/indices are 1-based; each returns a control (empty for untracked bodies).
/**
Summary: How many sensor entries happened this frame.

Returns: The count, 0 when none.

Example:
if b2kSensorCount() > 0 then put b2kSensorEnterVisitor(1) into tWho

Description:
The polling alternative to the b2kSensorEnter message; read it from
b2kFrame. Events are collected after every fixed step of the frame.

References: b2kSensorEnterSensor (handler), b2kSensorEnterVisitor (handler), b2kSensorExitCount (handler)
*/
function b2kSensorCount
   if sEvtSN is empty then return 0
   return sEvtSN
end b2kSensorCount
/**
Summary: The sensor control of an entry this frame.

pIndex: The 1-based index of the entry within this frame.

Returns: The sensor's long id, or empty for an untracked body or an index out of range.

Example:
put b2kSensorEnterSensor(1) into tZone

References: b2kSensorCount (handler), b2kSensorEnterVisitor (handler)
*/
function b2kSensorEnterSensor pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtSN then return empty
   return sCtrl[sEvtSS[pIndex]]
end b2kSensorEnterSensor
/**
Summary: The visiting control of an entry this frame.

pIndex: The 1-based index of the entry within this frame.

Returns: The visitor's long id, or empty for an untracked body or an index out of range.

Example:
put b2kSensorEnterVisitor(1) into tWho

References: b2kSensorCount (handler), b2kSensorEnterSensor (handler)
*/
function b2kSensorEnterVisitor pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtSN then return empty
   return sCtrl[sEvtSV[pIndex]]
end b2kSensorEnterVisitor
/**
Summary: How many sensor exits happened this frame.

Returns: The count, 0 when none.

Example:
put b2kSensorExitCount() into tLeft

References: b2kSensorExitSensor (handler), b2kSensorExitVisitor (handler), b2kSensorCount (handler)
*/
function b2kSensorExitCount
   if sEvtXN is empty then return 0
   return sEvtXN
end b2kSensorExitCount
/**
Summary: The sensor control of an exit this frame.

pIndex: The 1-based index of the exit within this frame.

Returns: The sensor's long id, or empty for an untracked body or an index out of range.

Example:
put b2kSensorExitSensor(1) into tZone

References: b2kSensorExitCount (handler), b2kSensorExitVisitor (handler)
*/
function b2kSensorExitSensor pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtXN then return empty
   return sCtrl[sEvtXS[pIndex]]
end b2kSensorExitSensor
/**
Summary: The visiting control of an exit this frame.

pIndex: The 1-based index of the exit within this frame.

Returns: The visitor's long id, or empty for an untracked body or an index out of range.

Example:
put b2kSensorExitVisitor(1) into tWho

References: b2kSensorExitCount (handler), b2kSensorExitSensor (handler)
*/
function b2kSensorExitVisitor pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtXN then return empty
   return sCtrl[sEvtXV[pIndex]]
end b2kSensorExitVisitor

-- =====================================================================
-- Collision filtering (named layers; up to 32)
-- =====================================================================
-- Define (or fetch) a named collision layer, returning its bit value. Then
-- b2kSetCategory / b2kSetMask take a comma- or space-separated list of layer
-- names (or raw numbers). Two shapes collide only if EACH one's category appears
-- in the other's mask (and no shared negative group forbids it).
/**
Summary: Define or look up a named collision layer.

pName: The layer's name.

Returns: The layer's bit value through the result, or 0 when all 31 nameable layers are taken.

Example:
b2kDefineLayer "enemies"
put the result into tBit

Description:
Layers are handed out from bit 1 up to bit 2^30. The top bit, 2^31,
is the Kit's reserved "oneway" layer for chains; it can be named in a list
but is never handed out. You rarely need to call this yourself: the layer
lists of <b2kSetCategory> and <b2kSetMask> define names as they meet them.

References: b2kLayerBits (handler), b2kSetCategory (handler), b2kSetMask (handler)
*/
command b2kDefineLayer pName
   if sLayers[pName] is not empty then return sLayers[pName]
   if sNextBit is empty or sNextBit < 1 then put 1 into sNextBit
   -- xTalk's bitOr is 32-bit, so a wrapped layer would get a category of 0
   -- (= collides with nothing). Refuse instead of corrupting filters. The
   -- TOP bit (2^31) is the Kit's reserved "oneway" chain layer, so user
   -- layers stop at 2^30: 31 nameable layers.
   if sNextBit > 1073741824 then return 0
   put sNextBit into sLayers[pName]
   put sNextBit * 2 into sNextBit
   return sLayers[pName]
end b2kDefineLayer

/**
Summary: Turn a list of layer names into a bitmask.

pLayerList: A comma or space separated list of layer names or raw numbers.

Returns: The combined bit value.

Example:
put b2kLayerBits("player,enemies") into tMask

Description:
Unknown names are defined on the way (<b2kDefineLayer>); "oneway" is bit 2^31.

References: b2kDefineLayer (handler)
*/
function b2kLayerBits pLayerList
   local tBits, tL
   put 0 into tBits
   replace comma with space in pLayerList
   repeat for each word tL in pLayerList
      if tL is empty then next repeat
      if tL is "oneway" then
         -- the reserved chain layer (bit 2^31): nameable in masks so a
         -- body can opt in/out of one-way terrain explicitly
         put tBits bitOr 2147483648 into tBits
         next repeat
      end if
      if tL is a number then
         put tBits bitOr (tL) into tBits
      else
         -- b2kDefineLayer is a COMMAND: OXT cannot call commands with
         -- function syntax, so invoke it as a statement and read the result
         b2kDefineLayer tL
         put tBits bitOr (the result) into tBits
      end if
   end repeat
   return tBits
end b2kLayerBits

/**
Summary: Set which collision layers a control belongs to.

pControl: The control, by reference (the long id of the control is safest).

pLayerList: A comma or space separated list of layer names or raw numbers.

Example:
b2kSetCategory tSlime, "enemies"

Description:
Two shapes collide only when each one's category is in the other's
mask. The shape keeps its mask and group. A control with no Kit shape is
ignored.

References: b2kSetMask (handler), b2kSetCollisionGroup (handler), b2kDefineLayer (handler)
*/
command b2kSetCategory pControl, pLayerList
   local s, tM
   put sShapeH[the long id of pControl] into s
   if s is empty then exit b2kSetCategory
   -- ENGINE-FOUND 2026-08-17 (the ghost-layer harness failure, stable
   -- across four runs): Box2D v3.1 filter bits are uint64, so a DEFAULT
   -- mask reads back as 2^64-1 -- above the shim's 2^53-1 double guard,
   -- which made b2SetShapeFilter refuse the whole call SILENTLY, so the
   -- category never landed and the shape kept the default bit (which is
   -- also the FIRST named layer's bit: b2kDefineLayer starts at 1).
   -- b2kPlayerDropStart had this exact clamp, with this exact reasoning,
   -- since the drop-through window shipped -- it was never propagated to
   -- the public filter wrappers. Clamp every readback that feeds back in:
   -- every category this Kit can mint lives below 2^32, so "all 32 kit
   -- bits" is behaviour-identical.
   put b2ShapeFilterMask(s) into tM
   if tM > 4294967295 then put 4294967295 into tM
   b2SetShapeFilter s, b2kLayerBits(pLayerList), tM, b2ShapeFilterGroup(s)
end b2kSetCategory

/**
Summary: Set which collision layers a control collides with.

pControl: The control, by reference (the long id of the control is safest).

pLayerList: A comma or space separated list of layer names or raw numbers.

Example:
b2kSetMask tGhost, "walls"

Description:
The reserved "oneway" bit is always added, so a body with a custom
mask still stands on <b2kChain> terrain. The shape keeps its category and
group. A control with no Kit shape is ignored.

References: b2kSetCategory (handler), b2kNoCollide (handler)
*/
command b2kSetMask pControl, pLayerList
   local s, tC
   put sShapeH[the long id of pControl] into s
   if s is empty then exit b2kSetMask
   -- a named-layer mask means OBJECT rules, not "fall through the
   -- terrain": the reserved chain bit rides along automatically, so
   -- custom-masked bodies still stand on b2kChain ground. To really
   -- pass through chains use raw b2SetShapeFilter (the player's
   -- drop-through window does exactly that, internally).
   -- The category readback is clamped like b2kSetCategory's mask (the
   -- 2^53 shim-guard trap): a default category is 1, but a raw-call
   -- category above 2^32 must not silently void THIS wrapper's write.
   put b2ShapeFilterCategory(s) into tC
   if tC > 4294967295 then put 4294967295 into tC
   b2SetShapeFilter s, tC, b2kLayerBits(pLayerList) bitOr 2147483648, b2ShapeFilterGroup(s)
end b2kSetMask

-- Group index: bodies sharing a NEGATIVE group never collide; a POSITIVE group
-- always collide. Overrides category/mask. 0 (default) = use category/mask.
/**
Summary: Set a control's collision group index.

pControl: The control, by reference (the long id of the control is safest).

pGroup: A negative group never collides with its own group; a positive one always does; 0 uses category and mask.

Example:
b2kSetCollisionGroup tRagdollArm, -1

Description:
The group overrides category and mask. A control with no Kit shape is ignored.

References: b2kSetCategory (handler), b2kNoCollide (handler)
*/
command b2kSetCollisionGroup pControl, pGroup
   local s, tC, tM
   put sShapeH[the long id of pControl] into s
   if s is empty then exit b2kSetCollisionGroup
   -- both readbacks feed back in, so both get the 2^53 shim-guard clamp
   -- (see b2kSetCategory): a default mask made this whole command a
   -- silent no-op for every body whose mask was never lowered.
   put b2ShapeFilterCategory(s) into tC
   if tC > 4294967295 then put 4294967295 into tC
   put b2ShapeFilterMask(s) into tM
   if tM > 4294967295 then put 4294967295 into tM
   b2SetShapeFilter s, tC, tM, pGroup
end b2kSetCollisionGroup

-- =====================================================================
-- Chains (smooth terrain) and world queries
-- =====================================================================
-- A smooth static chain (ground/terrain) from a list of SCREEN points ("x,y" per
-- line). Unlike joined box/segment edges it has no inner corners for fast bodies
-- to catch on. Needs >= 4 points; pLoop true closes it. Invisible (draw a matching
-- graphic). Returns a chain handle (b2DestroyChain to remove).
-- THE GHOST RULE (open chains): Box2D uses the FIRST and LAST segments as
-- ghost anchors only -- N points collide as N-3 segments. Run the chain one
-- segment PAST the surface you need on each side (over solid ground the
-- ghost tails can simply continue flat). A chain whose endpoints sit AT the
-- platform edges has non-solid ends -- bodies fall straight through them.
/**
Summary: Build smooth static terrain from a list of screen points.

pPoints: Screen points, one "x,y" per line. At least 4 points.

pLoop: true to close the chain into a loop; anything else leaves it open.

Returns: The chain handle through the result, or 0 when there is no world.

Example:
b2kChain "900,400" & cr & "600,400" & cr & "300,400" & cr & "0,400"
put the result into tGround

Description:
A chain has no inner corners for fast bodies to catch on. It is
invisible (draw a graphic to match) and one-sided: the solid side is to the
right of the direction the points run, so list a floor's top surface right to
left. On an open chain the first and last segments are ghost anchors that do
not collide, so run the chain one segment past the surface you need at
each end.

Every Kit chain carries the reserved "oneway" layer, which lets the player
drop through it. It is not a tracked body, so <b2kClear> leaves it.

References: b2kSmoothGround (handler), b2kAddChain (handler), b2kWall (handler)
*/
command b2kChain pPoints, pLoop
   local tBody, p, tChain
   if sWorld is empty then return 0
   set the itemDelimiter to comma   -- points are "x,y" (gotcha 5)
   put b2NewStaticBody(sWorld, 0, 0) into tBody
   b2ChainBegin
   repeat for each line p in pPoints
      if p is empty then next repeat
      b2ChainAddPoint b2kToWorldX(item 1 of p), b2kToWorldY(item 2 of p)
   end repeat
   -- every Kit chain carries the reserved ONE-WAY category (bit 2^31,
   -- the "oneway" layer) with an all-bits mask: nothing collides any
   -- differently, but the player's drop-through window can now stop
   -- colliding with chains ALONE by masking out that single bit.
   b2ShapeDefFilter 2147483648, 4294967295, 0
   put b2CreateChain(tBody, (pLoop is true), 0.6, 0.1) into tChain
   if tChain > 0 then put true into sOneWayBody[tBody]
   return tChain
end b2kChain

/**
Summary: Build an open chain of smooth static terrain.

pPoints: Screen points, one "x,y" per line. At least 4 points.

Returns: The chain handle through the result, or 0 when there is no world.

Example:
b2kSmoothGround tPoints
put the result into tGround

Description:
The same as <b2kChain> with pLoop false; its ghost rule and winding apply.

References: b2kChain (handler)
*/
command b2kSmoothGround pPoints
   -- statement call + the result: OXT cannot call commands function-style.
   -- Mind b2kChain's GHOST RULE: the outer two points anchor, not collide.
   b2kChain pPoints, false
   return the result
end b2kSmoothGround

-- Attach a smooth static chain to a CONTROL, from a list of SCREEN points
-- ("x,y" per line) - the control's own outline. Unlike b2kChain (which makes an
-- untracked world body), this registers the body against the control like
-- b2kAddBox/Ball/Polygon, so it selects (b2kControlAt), drags (b2kMoveTo) and
-- removes (b2kRemove) as a normal static part. The points are taken relative to
-- the control's centre, so moving the control moves the terrain with it. pLoop
-- true closes the outline into a solid blob; false leaves a one-sided ground
-- line. Great for smooth, rolling, concave terrain a fast body won't catch on.
/**
Summary: Give a control a static chain body from its outline points.

pControl: The control, by reference (the long id of the control is safest).

pPoints: Screen points, one "x,y" per line.

pLoop: true to close the outline into a solid blob; anything else leaves an open line.

Returns: The body handle through the result, or 0 when there is no world.

Example:
b2kAddChain the long id of graphic "Hill", the points of graphic "Hill", false

Description:
Unlike <b2kChain> the body is registered against the control, so
<b2kControlAt>, <b2kMoveTo> and <b2kRemove> treat it like any static part.
The points are taken relative to the control's centre. These chains are solid
terrain and do not carry the "oneway" layer.

References: b2kChain (handler), b2kRemove (handler)
*/
command b2kAddChain pControl, pPoints, pLoop
   local tRef, tCx, tCy, tBody, p, lx, ly
   if sWorld is empty then return 0
   set the itemDelimiter to comma   -- locs and points are "x,y" (gotcha 5)
   put the long id of pControl into tRef
   put item 1 of the loc of pControl into tCx
   put item 2 of the loc of pControl into tCy
   put b2NewStaticBody(sWorld, b2kToWorldX(tCx), b2kToWorldY(tCy)) into tBody
   b2ChainBegin
   repeat for each line p in pPoints
      if p is empty then next repeat
      put (item 1 of p - tCx) / sScale into lx          -- local to the control's centre
      put - ((item 2 of p - tCy) / sScale) into ly
      b2ChainAddPoint lx, ly
   end repeat
   get b2CreateChain(tBody, (pLoop is true), 0.6, 0.1)
   b2kRegister tRef, tBody, true                        -- static, kit-tracked
   put "loc" into sRender[tRef]                          -- static: registered but never synced
   return tBody
end b2kAddChain

-- Controls whose body overlaps a screen RECT (newline-separated long ids).
-- NOTE: this asks the BROADPHASE, whose boxes are fattened (~0.1m = a few
-- px) -- a region touching the floor reports the floor. For presence
-- checks (plates, buttons) use b2kOverlapMoving.
/**
Summary: The Kit controls whose bodies overlap a screen rectangle.

pX1: One corner's x, in pixels.

pY1: One corner's y, in pixels.

pX2: The other corner's x, in pixels.

pY2: The other corner's y, in pixels.

Returns: The controls' long ids, one per line, or empty.

Example:
put b2kOverlap(100, 100, 200, 200) into tInside

Description:
It asks Box2D's broadphase, whose boxes are slightly enlarged
(about 0.1 m, a few pixels), so a rectangle touching the floor reports the
floor. Use <b2kOverlapMoving> for presence checks.

References: b2kOverlapMoving (handler), b2kOverlapCircle (handler)
*/
function b2kOverlap pX1, pY1, pX2, pY2
   if sWorld is empty then return empty
   return b2kQueryToControls(b2OverlapAABB(sWorld, b2kToWorldX(pX1), b2kToWorldY(pY1), b2kToWorldX(pX2), b2kToWorldY(pY2)))
end b2kOverlap

-- Controls of MOVING (non-static) bodies overlapping a screen RECT --
-- THE presence poll for pressure plates and buttons. A pad region must
-- sit on its floor, and the broadphase's fattened boxes make the floor
-- itself overlap it forever; filtering statics asks what a plate means:
-- "is some THING on me?" (Dynamic and kinematic bodies count; sleeping
-- ones still register.)
/**
Summary: The non-static Kit controls overlapping a screen rectangle.

pX1: One corner's x, in pixels.

pY1: One corner's y, in pixels.

pX2: The other corner's x, in pixels.

pY2: The other corner's y, in pixels.

Returns: The controls' long ids, one per line, or empty.

Example:
put (b2kOverlapMoving(400, 380, 460, 400) is not empty) into tPlateDown

Description:
The presence poll for pressure plates and buttons: static bodies
are filtered out, dynamic and kinematic bodies count, and sleeping bodies
still register.

References: b2kOverlap (handler), b2kAddSensor (handler)
*/
function b2kOverlapMoving pX1, pY1, pX2, pY2
   local tLine, tOut
   put empty into tOut
   repeat for each line tLine in b2kOverlap(pX1, pY1, pX2, pY2)
      if tLine is empty then next repeat
      if sStatic[tLine] is true then next repeat
      put tLine & cr after tOut
   end repeat
   return tOut
end b2kOverlapMoving

-- Controls whose body overlaps a screen circle.
/**
Summary: The Kit controls whose bodies overlap a screen circle.

pX: The centre x, in pixels.

pY: The centre y, in pixels.

pRadiusPx: The radius, in pixels.

Returns: The controls' long ids, one per line, or empty.

Example:
put b2kOverlapCircle(the mouseH, the mouseV, 40) into tNear

References: b2kOverlap (handler)
*/
function b2kOverlapCircle pX, pY, pRadiusPx
   if sWorld is empty then return empty
   return b2kQueryToControls(b2OverlapCircle(sWorld, b2kToWorldX(pX), b2kToWorldY(pY), pRadiusPx / sScale))
end b2kOverlapCircle

-- Every control a ray crosses, nearest-first (vs b2kRayHit's single closest).
/**
Summary: Every Kit control a ray between two screen points crosses.

pX1: Start x, in pixels.

pY1: Start y, in pixels.

pX2: End x, in pixels.

pY2: End y, in pixels.

Returns: The controls' long ids, one per line, nearest first, or empty.

Example:
put b2kRayHitAll(0, 200, 600, 200) into tLine

References: b2kRayHit (handler)
*/
function b2kRayHitAll pX1, pY1, pX2, pY2
   if sWorld is empty then return empty
   return b2kQueryToControls(b2RayCastAll(sWorld, b2kToWorldX(pX1), b2kToWorldY(pY1), b2kToWorldX(pX2), b2kToWorldY(pY2)))
end b2kRayHitAll

-- Shared: turn the current query result (count) into a newline list of controls.
/**
Summary: Turn the last raw query's rows into Kit controls.

pCount: The row count the raw query returned.

Returns: The controls' long ids, one per line; rows with no Kit control are skipped.

Example:
put b2kQueryToControls(tCount) into tControls

Description:
A helper behind <b2kOverlap>, <b2kOverlapCircle> and <b2kRayHitAll>.

References: b2kOverlap (handler)
*/
function b2kQueryToControls pCount
   local i, c, tList
   put empty into tList
   repeat with i = 1 to pCount
      put sCtrl[b2QueryBody(i)] into c
      if c is not empty then put c & cr after tList
   end repeat
   return tList
end b2kQueryToControls

-- =====================================================================
-- Motor & filter joints
-- =====================================================================
-- Drive pMover toward a target pose relative to pRef (a moving anchor; empty =
-- the world). Offsets are in screen pixels / degrees from pRef's centre. Great for
-- followers, lifts and character motion. Returns a joint handle (b2kRemoveJoint).
/**
Summary: Drive a control toward a pose offset from another control or the world.

pMover: The control to drive, by reference.

pRef: The control the offset is measured from, or empty for the world.

pOffsetXPx: The target x offset, in pixels.

pOffsetYPx: The target y offset, in pixels (positive is down).

pAngleDeg: The target angle offset in degrees. Empty means 0.

pMaxForce: The most force the joint may use. Empty means 1000.

pMaxTorque: The most torque the joint may use. Empty means 1000.

Returns: The joint handle through the result, or 0 when a control has no body or there is no world.

Example:
b2kMotorTo tPet, tHero, -40, 0, 0
put the result into tLeash

Description:
A motor joint, good for followers and lifts. Remove it with <b2kRemoveJoint>.

References: b2kRemoveJoint (handler), b2kSlider (handler)
*/
command b2kMotorTo pMover, pRef, pOffsetXPx, pOffsetYPx, pAngleDeg, pMaxForce, pMaxTorque
   local bMover, bRef
   put sBody[the long id of pMover] into bMover
   if pRef is empty then put sDragAnchor into bRef
   else put sBody[the long id of pRef] into bRef
   if bMover is empty or bRef is empty or sWorld is empty then return 0
   if pAngleDeg is empty then put 0 into pAngleDeg
   if pMaxForce is empty then put 1000 into pMaxForce
   if pMaxTorque is empty then put 1000 into pMaxTorque
   return b2MotorJoint(sWorld, bRef, bMover, pOffsetXPx / sScale, - pOffsetYPx / sScale, \
         pAngleDeg * kPI / 180, pMaxForce, pMaxTorque, 0.3, false)
end b2kMotorTo

-- Stop two specific controls from colliding with each other (without changing how
-- either collides with anything else). Returns a joint handle (b2kRemoveJoint).
/**
Summary: Stop two controls colliding with each other.

pCtrlA: The control, by reference (the long id of the control is safest).

pCtrlB: The second control, by reference.

Returns: The joint handle through the result, or 0 when a control has no body or there is no world.

Example:
b2kNoCollide tHero, tPet
put the result into tPass

Description:
A filter joint: only this pair stops colliding; each still
collides with everything else. Remove it with <b2kRemoveJoint>.

References: b2kRemoveJoint (handler), b2kSetCollisionGroup (handler)
*/
command b2kNoCollide pCtrlA, pCtrlB
   local bA, bB
   put sBody[the long id of pCtrlA] into bA
   put sBody[the long id of pCtrlB] into bB
   if bA is empty or bB is empty or sWorld is empty then return 0
   return b2FilterJoint(sWorld, bA, bB)
end b2kNoCollide

-- =====================================================================
-- World tuning (advanced) + perf readout
-- =====================================================================
-- Below this approach speed (px/sec) collisions stop bouncing, even if bouncy.
/**
Summary: Set the speed below which collisions stop bouncing.

pPxPerSec: The approach speed, in pixels per second.

Example:
b2kSetRestitutionThreshold 30

Description:
A higher value removes small jittery bounces. With no world it does nothing.

References: b2kSetBounce (handler)
*/
command b2kSetRestitutionThreshold pPxPerSec
   if sWorld is not empty then b2SetRestitutionThreshold sWorld, pPxPerSec / sScale
end b2kSetRestitutionThreshold

-- Contact softness: stiffness (hertz), damping ratio, max separation-fix speed (px/sec).
/**
Summary: Tune contact softness for the world.

pHertz: Contact stiffness, in hertz.

pDamping: The contact damping ratio.

pPushPx: The fastest speed, in pixels per second, at which overlapping shapes are pushed apart.

Example:
b2kSetContactTuning 30, 10, 5

Description:
With no world it does nothing.

References: b2kSetJointTuning (handler)
*/
command b2kSetContactTuning pHertz, pDamping, pPushPx
   if sWorld is not empty then b2SetContactTuning sWorld, pHertz, pDamping, pPushPx / sScale
end b2kSetContactTuning

/**
Summary: Tune joint softness for the world.

pHertz: Joint stiffness, in hertz.

pDamping: The joint damping ratio.

Example:
b2kSetJointTuning 60, 2

Description:
With no world it does nothing.

References: b2kSetContactTuning (handler)
*/
command b2kSetJointTuning pHertz, pDamping
   if sWorld is not empty then b2SetJointTuning sWorld, pHertz, pDamping
end b2kSetJointTuning

-- Clamp how fast any body can move (px/sec) - stops runaway speeds.
/**
Summary: Limit how fast any body can move.

pPxPerSec: The top speed, in pixels per second.

Example:
b2kSetMaxSpeed 1800

Description:
With no world it does nothing.
*/
command b2kSetMaxSpeed pPxPerSec
   if sWorld is not empty then b2SetMaximumLinearSpeed sWorld, pPxPerSec / sScale
end b2kSetMaxSpeed

/**
Summary: Turn the solver's warm starting on or off.

pFlag: true to reuse the last step's solution (the default), false to turn it off.

Example:
b2kEnableWarmStarting true

Description:
Warm starting makes stacks faster and more stable. With no world it does nothing.
*/
command b2kEnableWarmStarting pFlag
   if sWorld is not empty then b2EnableWarmStarting sWorld, (pFlag is true)
end b2kEnableWarmStarting

-- A quick perf readout in milliseconds: "totalStep,collide,solve" for the last step.
/**
Summary: Timings for the last physics step.

Returns: "totalStep,collide,solve" in milliseconds, or empty with no world.

Example:
put b2kProfile() into field "Perf"

References: b2kAwakeBodyCount (handler)
*/
function b2kProfile
   if sWorld is empty then return empty
   b2WorldProfileUpdate sWorld
   return b2WorldProfileStep() & "," & b2WorldProfileCollide() & "," & b2WorldProfileSolve()
end b2kProfile

-- How many dynamic bodies are awake right now (native count, vs b2kAwakeCount).
/**
Summary: How many bodies Box2D has awake.

Returns: The native count, or 0 with no world.

Example:
put b2kAwakeBodyCount() into field "Awake"

Description:
It counts every awake body in the world, including bodies the Kit does not track.

References: b2kAwakeCount (handler), b2kProfile (handler)
*/
function b2kAwakeBodyCount
   if sWorld is empty then return 0
   return b2AwakeBodyCount(sWorld)
end b2kAwakeBodyCount

-- =====================================================================
-- Dragging: call b2kGrab from mouseDown and b2kRelease from mouseUp.
-- =====================================================================
/**
Summary: Start dragging the dynamic body under a screen point.

pScreenX: The point's x, in pixels.

pScreenY: The point's y, in pixels.

Returns: The grabbed control, or empty when no dynamic body is there.

Example:
get b2kGrab(b2kCamMouseX(), b2kCamMouseY())

Description:
Call it from mouseDown and <b2kRelease> from mouseUp. While a body
is held, the loop pulls it toward the mouse each frame with a mouse joint.
With the camera on, pass <b2kCamMouseX> and <b2kCamMouseY>.

References: b2kRelease (handler), b2kControlAt (handler)
*/
function b2kGrab pScreenX, pScreenY
   local tWx, tWy, tBody
   if sWorld is empty then return empty   -- grab before setup: nothing to hit
   put b2kToWorldX(pScreenX) into tWx
   put b2kToWorldY(pScreenY) into tWy
   put b2BodyAtPoint(sWorld, tWx, tWy) into tBody
   if tBody > 0 and b2BodyType(tBody) is 2 then
      b2SetAwake tBody, true
      put b2MouseJoint(sWorld, sDragAnchor, tBody, tWx, tWy, 6, 0.7, 4000) into sDragJoint
      put true into sDragging
      return sCtrl[tBody]
   end if
   return empty
end b2kGrab

/**
Summary: Let go of a dragged body.

Example:
b2kRelease

Description:
Safe to call when nothing is held.

References: b2kGrab (handler)
*/
command b2kRelease
   if sDragJoint is not empty and sDragJoint > 0 then b2DestroyJoint sDragJoint
   put 0 into sDragJoint
   put false into sDragging
end b2kRelease

-- =====================================================================
-- Input (keyboard): poll-and-diff held keys, once per frame
-- =====================================================================
-- Model: one `the keysDown` sample per frame (taken inside the loop, just
-- before b2kFrame dispatches), diffed against the previous frame's sample.
-- Held = in the current set; pressed/released = the diff. This sidesteps
-- every event-path problem at once: OS auto-repeat (Win32 re-sends
-- rawKeyDown with no paired ups), focus stealing by fields/buttons, and
-- frontscript plumbing. Letter keys bind BOTH keysym cases ("w" = 119 and
-- 87) because the reported code shifts with the Shift key.
/**
Summary: Turn on the per-frame keyboard sample.

Example:
b2kInputOn
b2kFrameTarget the long id of me

Description:
Each frame the loop reads the keys held down and compares them with
the previous frame, so the key, action and axis queries work from b2kFrame.
No focus or key messages are needed.

It also fills empty bindings: action "jump" (space), action "dash" (shift, x),
axis "moveX" (left, a / right, d) and axis "moveY" (up, w / down, s). Your own
bindings are kept.

References: b2kInputOff (handler), b2kKeyIsDown (handler), b2kBindAction (handler), b2kAxis (handler)
*/
command b2kInputOn
   put true into sInputOn
   put comma into sKeysNow
   put comma into sKeysPrev
   -- starter bindings; rebind freely (these only fill empty slots)
   if sKeyActions["jump"] is empty then b2kBindAction "jump", "space"
   if sKeyActions["dash"] is empty then b2kBindAction "dash", "shift,x"
   if sAxisNeg["moveX"] is empty then b2kBindAxis "moveX", "left,a", "right,d"
   if sAxisNeg["moveY"] is empty then b2kBindAxis "moveY", "up,w", "down,s"
end b2kInputOn

/**
Summary: Turn off the per-frame keyboard sample.

Example:
b2kInputOff

Description:
Every key reads as up afterwards. Bindings are kept.

References: b2kInputOn (handler), b2kInputIsOn (handler)
*/
command b2kInputOff
   put false into sInputOn
   put comma into sKeysNow
   put comma into sKeysPrev
end b2kInputOff

/**
Summary: Report whether the keyboard sample is on.

Returns: true or false.

Example:
if not b2kInputIsOn() then b2kInputOn

References: b2kInputOn (handler)
*/
function b2kInputIsOn
   return (sInputOn is true)
end b2kInputIsOn

-- Internal, called by the loop each frame while armed. The sets are stored
-- comma-wrapped (",65361,32,") so membership is one `contains` test.
/**
Summary: Take this frame's keyboard sample.

Example:
b2kInputTick

Description:
Internal: the loop and <b2kStepOnce> call it once per frame. The
current key set becomes the previous one and a new set is read from the
keyboard, or from the injected keys. A no-op while input is off.

References: b2kInputOn (handler), b2kInputInject (handler)
*/
command b2kInputTick
   if sInputOn is not true then exit b2kInputTick
   put sKeysNow into sKeysPrev
   if sInjectOn is true then
      put comma & sInjectKeys & comma into sKeysNow
   else
      put comma & the keysDown & comma into sKeysNow
   end if
end b2kInputTick

-- Replace the keyboard with a SCRIPTED key set (friendly names or codes;
-- empty = nothing held) until b2kInputInjectOff. Deterministic input for
-- the self-test harness, input replays, and cutscene "ghost" players --
-- edges fall out of the normal frame diff exactly as with real keys.
/**
Summary: Replace the keyboard with a scripted set of held keys.

pKeys: A comma list of key names or codes to hold; empty holds nothing.

Example:
b2kInputInject "right,space"

Description:
Until <b2kInputInjectOff>, each frame's sample reads this set
instead of the keyboard, and pressed and released edges come from the normal
frame comparison. For tests, input replays and scripted characters.

References: b2kInputInjectOff (handler), b2kInputTick (handler)
*/
command b2kInputInject pKeys
   put true into sInjectOn
   put b2kKeyListCodes(pKeys) into sInjectKeys
end b2kInputInject

/**
Summary: Return to reading the real keyboard.

Example:
b2kInputInjectOff

References: b2kInputInject (handler)
*/
command b2kInputInjectOff
   put false into sInjectOn
   put empty into sInjectKeys
end b2kInputInjectOff

-- A friendly key name (or raw keycode) -> the keycode candidates it matches,
-- comma-separated. Numbers >= 32 pass through as raw keycodes; single
-- characters resolve to their code (letters to both cases, per the
-- Shift-keysym behaviour the Phase 0 spike confirmed).
/**
Summary: The keycodes a key name matches.

pKey: A key name (left, right, up, down, space, return, escape, tab, shift, control, alt, backspace, delete), a single character, or a raw keycode.

Returns: A comma list of keycodes. A letter gives both cases; a number of 32 or more is returned as is; an unknown name gives 0.

Example:
put b2kKeyCodes("w") into tCodes

References: b2kKeyName (handler), b2kKeyListCodes (handler)
*/
function b2kKeyCodes pKey
   local tLower, tUpper
   if pKey is a number and pKey >= 32 then return pKey
   switch pKey
      case "left"
         return 65361
      case "up"
         return 65362
      case "right"
         return 65363
      case "down"
         return 65364
      case "space"
         return 32
      case "return"
      case "enter"
         return "65293,65421"
      case "escape"
      case "esc"
         return 65307
      case "tab"
         return 65289
      case "shift"
         return "65505,65506"
      case "control"
      case "ctrl"
         return "65507,65508"
      case "alt"
      case "option"
         return "65513,65514"
      case "backspace"
         return 65288
      case "delete"
         return 65535
   end switch
   if the number of chars of pKey is 1 then
      put charToNum(toLower(pKey)) into tLower
      put charToNum(toUpper(pKey)) into tUpper
      if tLower >= 97 and tLower <= 122 then return tLower & comma & tUpper
      return charToNum(pKey)
   end if
   return 0
end b2kKeyCodes

-- The reverse map, for readouts: a keycode -> its friendly name (or itself).
/**
Summary: The friendly name of a keycode.

pCode: A keycode.

Returns: The key's name, a lower-case letter or digit, or the code itself when it has no name.

Example:
put b2kKeyName(65361) into tName

References: b2kKeyCodes (handler), b2kKeysHeld (handler)
*/
function b2kKeyName pCode
   switch pCode
      case 65361
         return "left"
      case 65362
         return "up"
      case 65363
         return "right"
      case 65364
         return "down"
      case 32
         return "space"
      case 65293
      case 65421
         return "return"
      case 65307
         return "escape"
      case 65289
         return "tab"
      case 65505
      case 65506
         return "shift"
      case 65507
      case 65508
         return "control"
      case 65513
      case 65514
         return "alt"
      case 65288
         return "backspace"
      case 65535
         return "delete"
   end switch
   if pCode >= 97 and pCode <= 122 then return numToChar(pCode)
   if pCode >= 65 and pCode <= 90 then return numToChar(pCode + 32)
   if pCode >= 48 and pCode <= 57 then return numToChar(pCode)
   return pCode
end b2kKeyName

-- True when any of pKey's candidate codes is in the given set.
/**
Summary: Report whether a key is in a comma-wrapped keycode set.

pSet: A set of keycodes wrapped in commas, such as ",65361,32,".

pKey: A key name (left, right, up, down, space, return, escape, tab, shift, control, alt, backspace, delete), a single character, or a raw keycode.

Returns: true when any of the key's codes is in the set; false for an empty set.

Example:
put b2kKeyInSet(",32,", "space") into tHeld

Description:
A helper behind <b2kKeyIsDown>, <b2kKeyPressed> and <b2kKeyReleased>.

References: b2kCodesInSet (handler), b2kKeyIsDown (handler)
*/
function b2kKeyInSet pSet, pKey
   local tC
   if pSet is empty or pSet is comma then return false
   repeat for each item tC in b2kKeyCodes(pKey)
      if pSet contains (comma & tC & comma) then return true
   end repeat
   return false
end b2kKeyInSet

/**
Summary: Report whether a key is held this frame.

pKey: A key name (left, right, up, down, space, return, escape, tab, shift, control, alt, backspace, delete), a single character, or a raw keycode.

Returns: true or false.

Example:
if b2kKeyIsDown("left") then b2kPush tShip, -10, 0

Description:
Needs <b2kInputOn>; read it from b2kFrame.

References: b2kKeyPressed (handler), b2kKeyReleased (handler), b2kInputOn (handler)
*/
function b2kKeyIsDown pKey
   return b2kKeyInSet(sKeysNow, pKey)
end b2kKeyIsDown

-- Edge queries: true only on the single frame the state changed.
/**
Summary: Report whether a key went down this frame.

pKey: A key name (left, right, up, down, space, return, escape, tab, shift, control, alt, backspace, delete), a single character, or a raw keycode.

Returns: true only on the frame the key went down.

Example:
if b2kKeyPressed("space") then b2kPush tHero, 0, -420

References: b2kKeyIsDown (handler), b2kKeyReleased (handler)
*/
function b2kKeyPressed pKey
   return b2kKeyInSet(sKeysNow, pKey) and not b2kKeyInSet(sKeysPrev, pKey)
end b2kKeyPressed

/**
Summary: Report whether a key came up this frame.

pKey: A key name (left, right, up, down, space, return, escape, tab, shift, control, alt, backspace, delete), a single character, or a raw keycode.

Returns: true only on the frame the key came up.

Example:
if b2kKeyReleased("space") then put false into tCharging

References: b2kKeyIsDown (handler), b2kKeyPressed (handler)
*/
function b2kKeyReleased pKey
   return b2kKeyInSet(sKeysPrev, pKey) and not b2kKeyInSet(sKeysNow, pKey)
end b2kKeyReleased

-- Everything held right now, as friendly names (debug HUDs).
/**
Summary: Every key held this frame, by name.

Returns: The names separated by spaces, or empty.

Example:
put b2kKeysHeld() into field "Keys"

Description:
Handy for a debug display.

References: b2kKeyName (handler), b2kKeyIsDown (handler)
*/
function b2kKeysHeld
   local tOut, tC
   put empty into tOut
   repeat for each item tC in char 2 to -2 of sKeysNow
      put b2kKeyName(tC) & space after tOut
   end repeat
   return word 1 to -1 of tOut
end b2kKeysHeld

-- Actions: a named set of keys ("jump" = "space,up,w"). Any bound key
-- counts; the action's edges treat the whole set as one logical key.
-- The name->keycode resolution happens ONCE, at bind time (the cached
-- code list is what the per-frame queries scan) -- these run inside the
-- player tick and game code every frame, so they must stay cheap.
/**
Summary: Name a set of keys as one action.

pName: The action's name, such as "jump".

pKeyList: A comma list of key names, such as "space,up,w".

Example:
b2kBindAction "fire", "x,control"

Description:
Any bound key counts, and pressed and released treat the set as one key. Keycodes are resolved once, here.

References: b2kActionIsDown (handler), b2kActionPressed (handler), b2kBindAxis (handler)
*/
command b2kBindAction pName, pKeyList
   put pKeyList into sKeyActions[pName]
   put b2kKeyListCodes(pKeyList) into sKeyActionsC[pName]
end b2kBindAction

-- Internal: a friendly key list -> every matching keycode, comma list.
/**
Summary: Every keycode a comma list of key names matches.

pKeyList: A comma list of key names or codes.

Returns: A comma list of keycodes.

Example:
put b2kKeyListCodes("left,a") into tCodes

Description:
A helper the bind commands use.

References: b2kKeyCodes (handler), b2kBindAction (handler)
*/
function b2kKeyListCodes pKeyList
   local tK, tOut
   put empty into tOut
   set the itemDelimiter to comma
   repeat for each item tK in pKeyList
      if tOut is empty then
         put b2kKeyCodes(word 1 of tK) into tOut
      else
         put comma & b2kKeyCodes(word 1 of tK) after tOut
      end if
   end repeat
   return tOut
end b2kKeyListCodes

-- Internal: is any of these (pre-resolved) keycodes in the given set?
/**
Summary: Report whether any of a list of keycodes is in a comma-wrapped set.

pSet: A set of keycodes wrapped in commas.

pCodes: A comma list of keycodes.

Returns: true when any code is in the set; false for an empty set.

Example:
put b2kCodesInSet(",32,", "32,65362") into tAny

Description:
A helper behind the action and axis queries.

References: b2kKeyInSet (handler), b2kActionIsDown (handler)
*/
function b2kCodesInSet pSet, pCodes
   local tC
   if pSet is empty or pSet is comma then return false
   repeat for each item tC in pCodes
      if pSet contains (comma & tC & comma) then return true
   end repeat
   return false
end b2kCodesInSet

/**
Summary: Report whether any key of an action is held.

pName: The action's name.

Returns: true or false; false for an action that was never bound.

Example:
if b2kActionIsDown("fire") then put true into tCharging

References: b2kBindAction (handler), b2kActionPressed (handler)
*/
function b2kActionIsDown pName
   return b2kCodesInSet(sKeysNow, sKeyActionsC[pName])
end b2kActionIsDown

/**
Summary: Report whether an action started this frame.

pName: The action's name.

Returns: true on the frame the first of its keys went down.

Example:
if b2kActionPressed("jump") then b2kPush tHero, 0, -420

References: b2kBindAction (handler), b2kActionReleased (handler)
*/
function b2kActionPressed pName
   if not b2kCodesInSet(sKeysNow, sKeyActionsC[pName]) then return false
   return not b2kCodesInSet(sKeysPrev, sKeyActionsC[pName])
end b2kActionPressed

/**
Summary: Report whether an action ended this frame.

pName: The action's name.

Returns: true on the frame the last of its keys came up.

Example:
if b2kActionReleased("fire") then put false into tCharging

References: b2kBindAction (handler), b2kActionPressed (handler)
*/
function b2kActionReleased pName
   if not b2kCodesInSet(sKeysPrev, sKeyActionsC[pName]) then return false
   return not b2kCodesInSet(sKeysNow, sKeyActionsC[pName])
end b2kActionReleased

-- Axes: -1 / 0 / +1 from two key sets ("moveX" defaults to left,a / right,d).
-- Both directions held = 0, which is what character movement wants.
/**
Summary: Define a -1, 0, +1 axis from two key sets.

pName: The axis's name, such as "moveX".

pNegKeys: A comma list of keys for the -1 direction.

pPosKeys: A comma list of keys for the +1 direction.

Example:
b2kBindAxis "steer", "left,a", "right,d"

References: b2kAxis (handler), b2kBindAction (handler)
*/
command b2kBindAxis pName, pNegKeys, pPosKeys
   put pNegKeys into sAxisNeg[pName]
   put pPosKeys into sAxisPos[pName]
   put b2kKeyListCodes(pNegKeys) into sAxisNegC[pName]
   put b2kKeyListCodes(pPosKeys) into sAxisPosC[pName]
end b2kBindAxis

/**
Summary: Read an axis.

pName: The axis's name.

Returns: -1, 0 or 1. Both directions held, or neither, gives 0.

Example:
b2kSetVelocity tHero, b2kAxis("moveX") * 240, item 2 of b2kVelocity(tHero)

References: b2kBindAxis (handler)
*/
function b2kAxis pName
   local tNeg, tPos
   put b2kCodesInSet(sKeysNow, sAxisNegC[pName]) into tNeg
   put b2kCodesInSet(sKeysNow, sAxisPosC[pName]) into tPos
   if tPos and not tNeg then return 1
   if tNeg and not tPos then return -1
   return 0
end b2kAxis

-- Real elapsed ms folded into the last frame -- drive animations and user
-- timers from this, not the step count (a frame may run 0..n fixed steps).
/**
Summary: The real time the last frame covered.

Returns: Milliseconds, or 0 before the first frame. A hand step counts as one 1/60 s step.

Example:
add b2kFrameMS() to tTimer

Description:
Drive animations and game timers from this, not the frame count: a
frame may run zero, one or several fixed physics steps.

References: b2kFrameTarget (handler)
*/
function b2kFrameMS
   if sFrameMS is empty then return 0
   return sFrameMS
end b2kFrameMS

-- =====================================================================
-- Sprites: sheets, atlases, named animations (icon-button backend)
-- =====================================================================
-- Model (decided by the Phase 0 spike, S12): a sheet registers named or
-- numbered frame REGIONS of one hidden source image; each region is sliced
-- into its own hidden image LAZILY, on first use. A sprite is a transparent
-- BUTTON whose icon is the current frame's image -- a frame switch is one
-- property set, and every sprite of a sheet shares the same frame images.
-- Mirrored (left-facing) frames are flip-clones, also made lazily.
-- Sheets persist until b2kTeardown (unless b2kSheetPersist is on; see below);
-- sprites are Kit-created controls, so b2kClear removes them like everything
-- else the Kit spawned.

-- Loaded sheets are ASSETS, not world state. By default b2kTeardown wipes
-- them (a full reset), but a multi-LEVEL game reloads the same atlases every
-- rebuild -- the costliest thing the Kit does (decode each PNG, parse each
-- XML, re-slice every frame). Turn this ON and sheets SURVIVE b2kTeardown,
-- exactly like synthesized sounds do, so they load ONCE per session: a level
-- rebuild reuses them (an identical b2kSheetLoad/LoadAtlas is then a no-op),
-- and re-warmed frames are already sliced. The Kit's source images are named
-- deterministically (b2ksheet_<name>) and tagged with their file path, so a
-- SAVED stack carries them: on reopen the load reuses the in-stack image
-- (skipping the expensive decode) instead of re-importing from disk. An
-- ATLAS also carries its parsed regions (stamped on that image), so its
-- reload needs NO file at all -- not the PNG, not the XML (b2kSheetLoadAtlas);
-- a grid sheet never needed more than the image. Slices are named
-- deterministically too, so whatever was sliced before the save is reused.
-- Call b2kSheetsWipe to force a clean reload (e.g. after the user picks a new
-- asset folder). OFF by default, so single-shot examples are unchanged.
/**
Summary: Keep loaded sheets alive across teardowns.

pFlag: true (or empty) to keep sheets, false to wipe them with each teardown (the starting state).

Example:
b2kSheetPersist true

Description:
With persistence on, sheets survive <b2kTeardown> like sounds do, so
a multi-level game loads its atlases once and an identical reload is a no-op.
The Kit's source and frame images have stable names and are marked with
where they came from, so a saved stack carries them: on reopen a load adopts
the images already in the stack, and an atlas needs neither its PNG nor its
XML. <b2kSheetsWipe> still clears everything.

References: b2kSheetPersists (handler), b2kSheetLoadAtlas (handler), b2kSheetsWipe (handler)
*/
command b2kSheetPersist pFlag
   put (pFlag is not false) into sSheetKeep
end b2kSheetPersist

/**
Summary: Report whether sheets survive teardown.

Returns: true or false.

Example:
put b2kSheetPersists() into tKeep

References: b2kSheetPersist (handler)
*/
function b2kSheetPersists
   return (sSheetKeep is true)
end b2kSheetPersists

-- Register an image FILE as a uniform grid of pFW x pFH frames, numbered
-- 1..N left-to-right, top-to-bottom. Reports the frame count. Sheets that
-- are not edge-to-edge take pMargin (outer border px) and pSpacing (gap
-- between cells px). Pass pFW/pFH 0 (or empty) to register the image with
-- NO grid and name regions yourself with b2kSheetAddFrame -- the path for
-- packed sheets that have no Kenney-style XML.
/**
Summary: Register an image file as a sheet of numbered grid frames.

pName: The sheet's name.

pPath: The image file's path.

pFW: Frame width in pixels; 0 or empty registers no grid.

pFH: Frame height in pixels; 0 or empty registers no grid.

pCount: Optional number of frames to register; empty means every whole cell.

pMargin: Optional outer border in pixels. Empty means 0.

pSpacing: Optional gap between cells in pixels. Empty means 0.

Returns: The sheet's frame count through the result, or 0 when the file cannot be loaded.

Example:
b2kSheetLoad "coins", tFolder & "/coins.png", 32, 32
put the result into tFrames

Description:
Frames are numbered 1 to N left to right, top to bottom. With no
grid, name regions yourself with <b2kSheetAddFrame>. The image is loaded into
a hidden image the Kit owns.

References: b2kSheetLoadAtlas (handler), b2kSheetFromImage (handler), b2kAnimDef (handler), b2kSpriteNew (handler)
*/
command b2kSheetLoad pName, pPath, pFW, pFH, pCount, pMargin, pSpacing
   local tRef, tSig
   put pPath & "|" & pFW & "|" & pFH & "|" & pCount & "|" & pMargin & "|" & pSpacing into tSig
   if sSheetKeep is true and sSheetKeys[pName] is not empty and sSheetPath[pName] is tSig then
      return the number of lines of sSheetKeys[pName]   -- already loaded (same file+grid): reuse it
   end if
   put b2kSheetSourceFromFile(pName, pPath) into tRef
   if tRef is empty then return 0
   b2kSheetGridRegions pName, pFW, pFH, pCount, pMargin, pSpacing
   put tSig into sSheetPath[pName]
   return the number of lines of sSheetKeys[pName]
end b2kSheetLoad

-- Register an image already in the stack (e.g. base64-embedded art) as a
-- grid sheet. The image is used in place and never deleted by the Kit.
-- Same grid arguments as b2kSheetLoad (margin/spacing; 0x0 = no grid).
/**
Summary: Register an image already in the stack as a grid sheet.

pName: The sheet's name.

pImgRef: The image, by reference.

pFW: Frame width in pixels; 0 or empty registers no grid.

pFH: Frame height in pixels; 0 or empty registers no grid.

pCount: Optional number of frames to register; empty means every whole cell.

pMargin: Optional outer border in pixels. Empty means 0.

pSpacing: Optional gap between cells in pixels. Empty means 0.

Returns: The sheet's frame count through the result.

Example:
b2kSheetFromImage "hero", the long id of image "HeroArt", 48, 48
put the result into tFrames

Description:
The image is used in place and the Kit never deletes it.

References: b2kSheetLoad (handler), b2kSheetAddFrame (handler)
*/
command b2kSheetFromImage pName, pImgRef, pFW, pFH, pCount, pMargin, pSpacing
   local tRef, tSig
   put the long id of pImgRef into tRef
   put tRef & "|" & pFW & "|" & pFH & "|" & pCount & "|" & pMargin & "|" & pSpacing into tSig
   if sSheetKeep is true and sSheetKeys[pName] is not empty and sSheetPath[pName] is tSig then
      return the number of lines of sSheetKeys[pName]   -- already loaded (same image+grid): reuse it
   end if
   b2kSheetForget pName
   put tRef into sSheetSrc[pName]
   put false into sSheetOwned[pName]
   b2kSheetGridRegions pName, pFW, pFH, pCount, pMargin, pSpacing
   put tSig into sSheetPath[pName]
   return the number of lines of sSheetKeys[pName]
end b2kSheetFromImage

-- Name one region of a loaded sheet yourself: the no-XML path for packed
-- sheets in any layout. Load the source first (b2kSheetLoad/FromImage with
-- frame size 0 for no grid), then add each frame by name; regions may be
-- any size and position and can also be added on top of a grid or atlas.
-- Redefining a name re-bakes its slice on next use.
/**
Summary: Name one rectangular region of a loaded sheet as a frame.

pSheet: The sheet's name.

pFrame: The frame's name.

pX: The region's left, in source pixels.

pY: The region's top, in source pixels.

pW: The region's width in pixels, at least 1.

pH: The region's height in pixels, at least 1.

Example:
b2kSheetAddFrame "items", "key", 0, 64, 32, 32

Description:
The path for packed sheets that have no XML: load the source with a
frame size of 0, then add each frame. It also works on top of a grid or an
atlas. Redefining a name drops its old slices. Bad arguments, or a sheet
that is not loaded, are ignored.

References: b2kSheetLoad (handler), b2kSheetFrameNames (handler)
*/
command b2kSheetAddFrame pSheet, pFrame, pX, pY, pW, pH
   local tId
   if sSheetSrc[pSheet] is empty then exit b2kSheetAddFrame
   if pFrame is empty then exit b2kSheetAddFrame
   if pX is not a number or pY is not a number then exit b2kSheetAddFrame
   if pW is not a number or pH is not a number then exit b2kSheetAddFrame
   if pW < 1 or pH < 1 then exit b2kSheetAddFrame
   if sSheetRegion[pSheet][pFrame] is empty then
      if sSheetKeys[pSheet] is empty then
         put pFrame into sSheetKeys[pSheet]
      else
         put cr & pFrame after sSheetKeys[pSheet]
      end if
   else
      -- redefined: drop any stale slices so the new region re-bakes lazily
      put sSheetIcon[pSheet][pFrame] into tId
      if tId is not empty then
         try
            delete image id tId
         catch tErr
         end try
      end if
      delete variable sSheetIcon[pSheet][pFrame]
      put sSheetFlip[pSheet][pFrame] into tId
      if tId is not empty then
         try
            delete image id tId
         catch tErr
         end try
      end if
      delete variable sSheetFlip[pSheet][pFrame]
   end if
   put round(pX) & comma & round(pY) & comma & round(pW) & comma & round(pH) into sSheetRegion[pSheet][pFrame]
end b2kSheetAddFrame

-- Register a packed atlas: a PNG plus the TextureAtlas XML that names its
-- regions (<SubTexture name=".." x=".." y=".." width=".." height=".."/> --
-- the Kenney pack format, like Spritesheets/ in this repo). Frames are
-- addressed BY NAME. pXmlPath defaults to the png path with ".xml".
-- Persisting (b2kSheetPersist), the first load also STAMPS the parsed regions
-- onto the Kit's source image, so a SAVED stack carries the whole atlas --
-- the pixels AND the names -- and a later load ADOPTS it with no file access
-- at all (b2kSheetAdoptAtlas): the art folder may be gone, renamed, or on
-- another machine, because the two paths are then only the cache key.
/**
Summary: Register a packed atlas: a PNG and its TextureAtlas XML.

pName: The sheet's name.

pPngPath: The PNG file's path.

pXmlPath: The XML file's path. Empty means the PNG path with an xml extension.

Returns: The sheet's frame count through the result, or 0 when a file cannot be read.

Example:
b2kSheetLoadAtlas "chars", tFolder & "/spritesheet-characters-default.png"
put the result into tFrames

Description:
The XML names each region in SubTexture tags (the Kenney format),
and frames are addressed by those names. With <b2kSheetPersist> on, the first
load stamps the regions on the Kit's source image and a later load, even in a
reopened saved stack, adopts them with no file access.

References: b2kSheetPersist (handler), b2kSheetAdoptAtlas (handler), b2kSheetFrameNames (handler), b2kAnimDef (handler)
*/
command b2kSheetLoadAtlas pName, pPngPath, pXmlPath
   local tRef, tXml, tLine, tNm, tX, tY, tW, tH, tSig, tN
   if pXmlPath is empty then
      put pPngPath into pXmlPath
      set the itemDelimiter to "."
      put "xml" into item -1 of pXmlPath
   end if
   put pPngPath & "|" & pXmlPath into tSig
   if sSheetKeep is true and sSheetKeys[pName] is not empty and sSheetPath[pName] is tSig then
      return the number of lines of sSheetKeys[pName]   -- already loaded (same png+xml): reuse it
   end if
   -- ADOPT before touching the disk: the XML used to be read FIRST, so a saved
   -- stack whose art folder had moved registered nothing at all, even though
   -- every pixel it needed was already inside it
   if sSheetKeep is true then
      b2kSheetAdoptAtlas pName, pPngPath, pXmlPath
      put the result into tN
      if tN > 0 then return tN
   end if
   put URL ("file:" & pXmlPath) into tXml
   if tXml is empty then put URL ("binfile:" & pXmlPath) into tXml
   if tXml is empty then return 0
   put b2kSheetSourceFromFile(pName, pPngPath) into tRef
   if tRef is empty then return 0
   set the itemDelimiter to comma
   repeat for each line tLine in tXml
      if tLine contains "<SubTexture" then
         put b2kXmlAttr(tLine, "name") into tNm
         put b2kXmlAttr(tLine, "x") into tX
         put b2kXmlAttr(tLine, "y") into tY
         put b2kXmlAttr(tLine, "width") into tW
         put b2kXmlAttr(tLine, "height") into tH
         if tNm is empty or tX is not a number or tY is not a number then next repeat
         if tW is not a number or tH is not a number then next repeat
         put tX & comma & tY & comma & tW & comma & tH into sSheetRegion[pName][tNm]
         put tNm & cr after sSheetKeys[pName]
      end if
   end repeat
   if the last char of sSheetKeys[pName] is cr then delete the last char of sSheetKeys[pName]
   put tSig into sSheetPath[pName]
   -- the stamp a later session adopts: which XML the regions came from, and
   -- the regions themselves (persisting only: otherwise the source image is
   -- wiped at teardown, so there is nothing to carry)
   if sSheetKeep is true then
      set the uB2kAtlasXml of tRef to pXmlPath
      set the uB2kAtlasRows of tRef to b2kSheetAtlasRows(pName)
   end if
   return the number of lines of sSheetKeys[pName]
end b2kSheetLoadAtlas

-- Every frame's region of a sheet, one line each, "x,y,w,h,name" in source
-- pixels and definition order (the NAME LAST, so a name holding a comma
-- survives a round trip). Introspection for any sheet; for an atlas it is
-- also the stamp a persisting load leaves on its source image.
/**
Summary: Every frame region of a sheet, one per line.

pName: The sheet's name.

Returns: Lines of "x,y,w,h,name" in source pixels, in definition order; empty for an unknown sheet.

Example:
put b2kSheetAtlasRows("chars") into field "Regions"

Description:
The name comes last so a name with a comma survives. For a persisting atlas this is also the stamp a saved stack adopts.

References: b2kSheetAdoptAtlas (handler), b2kSheetFrameNames (handler)
*/
function b2kSheetAtlasRows pName
   local tKey, tOut
   put empty into tOut
   repeat for each line tKey in sSheetKeys[pName]
      put sSheetRegion[pName][tKey] & comma & tKey & cr after tOut
   end repeat
   if the last char of tOut is cr then delete the last char of tOut
   return tOut
end b2kSheetAtlasRows

-- Internal: register an atlas from the stamp its first load left on the
-- Kit's source image b2ksheet_<name> (b2kSheetLoadAtlas, persisting): the
-- rows of b2kSheetAtlasRows and the XML path they were parsed from. Adopted
-- only when the image still answers to the same png path AND the same xml
-- path -- the provenance rule b2kSheetSliceSig applies to slices -- so a sheet
-- name reused for different art reads its files instead. The rows rebuild the
-- key list EXACTLY (order and any duplicate included), because a saved slice
-- is found by its key's position (b2kSheetKeyIndex): one row skipped would
-- shift every later frame onto its neighbour's pixels, so a malformed stamp
-- adopts nothing. Reports the frame count; 0 = nothing to adopt.
/**
Summary: Register an atlas from the stamp a saved stack carries.

pName: The sheet's name.

pPngPath: The PNG path the atlas was first loaded from.

pXmlPath: The XML path the atlas was first loaded from.

Returns: The frame count through the result, or 0 when there is nothing to adopt.

Example:
b2kSheetAdoptAtlas "chars", tPng, tXml
put the result into tFrames

Description:
Internal: <b2kSheetLoadAtlas> calls it when sheets persist. It
adopts only when the image b2ksheet_ plus the sheet name exists and was
stamped from the same PNG and XML paths, and a malformed stamp adopts
nothing. It reads no file.

References: b2kSheetLoadAtlas (handler), b2kSheetAtlasRows (handler)
*/
command b2kSheetAdoptAtlas pName, pPngPath, pXmlPath
   local tImg, tRows, tLine, tKeys, tRegion, tCount, i
   put "b2ksheet_" & pName into tImg
   if there is no image tImg then return 0
   if the uB2kSrcPath of image tImg is not pPngPath then return 0
   if the uB2kAtlasXml of image tImg is not pXmlPath then return 0
   if the width of image tImg < 2 then return 0
   put the uB2kAtlasRows of image tImg into tRows
   if tRows is empty then return 0
   put empty into tKeys
   put 0 into tCount
   set the itemDelimiter to comma
   repeat for each line tLine in tRows
      if item 1 of tLine is not a number or item 2 of tLine is not a number then return 0
      if item 3 of tLine is not a number or item 4 of tLine is not a number then return 0
      add 1 to tCount
      put item 1 to 4 of tLine into tRegion[tCount]
      -- the name is everything after the fourth comma, taken as CHARS, so a
      -- comma inside it (or trailing it) comes back exactly as it was written
      put char ((the number of chars of tRegion[tCount]) + 2) to -1 of tLine into tKeys[tCount]
      if tKeys[tCount] is empty then return 0
   end repeat
   -- a different registration of this name earlier in the session goes
   -- first; detach its source ref so the forget cannot delete the very image
   -- being adopted
   put empty into sSheetSrc[pName]
   b2kSheetForget pName
   set the lockLoc of image tImg to true
   put the long id of image tImg into sSheetSrc[pName]
   put true into sSheetOwned[pName]
   put empty into sSheetKeys[pName]
   repeat with i = 1 to tCount
      put tRegion[i] into sSheetRegion[pName][tKeys[i]]
      put tKeys[i] & cr after sSheetKeys[pName]
   end repeat
   if the last char of sSheetKeys[pName] is cr then delete the last char of sSheetKeys[pName]
   put pPngPath & "|" & pXmlPath into sSheetPath[pName]
   return the number of lines of sSheetKeys[pName]
end b2kSheetAdoptAtlas

/**
Summary: How many frames a sheet has.

pName: The sheet's name.

Returns: The frame count, 0 for an unknown sheet.

Example:
put b2kSheetFrames("coins") into tN

References: b2kSheetHasFrame (handler), b2kSheetFrameNames (handler)
*/
function b2kSheetFrames pName
   return the number of lines of sSheetKeys[pName]
end b2kSheetFrames

/**
Summary: Report whether a sheet has a frame.

pName: The sheet's name.

pFrame: The frame's name or number.

Returns: true or false.

Example:
if b2kSheetHasFrame("chars", "character_beige_jump") then put true into tCanJump

References: b2kSheetFrames (handler)
*/
function b2kSheetHasFrame pName, pFrame
   return (sSheetRegion[pName][pFrame] is not empty)
end b2kSheetHasFrame

-- Every frame key of a sheet, one per line, in definition order --
-- introspect an atlas you didn't make ("what is this frame called?").
/**
Summary: Every frame key of a sheet.

pName: The sheet's name.

Returns: The frame names or numbers, one per line, in definition order.

Example:
put b2kSheetFrameNames("chars") into field "Frames"

References: b2kSheetFrames (handler), b2kSheetAtlasRows (handler)
*/
function b2kSheetFrameNames pName
   return sSheetKeys[pName]
end b2kSheetFrameNames

-- Display scale for a sheet's frames (default 1). Frames slice lazily, so
-- set this right after loading the sheet, BEFORE creating sprites or anims:
-- already-sliced frames are dropped and re-bake at the new scale, but live
-- sprites keep their button rects. The engine does the resampling, so any
-- frame size displays at any sprite size.
/**
Summary: Set the display scale of a sheet's frames.

pName: The sheet's name.

pScale: The scale factor, clamped to 0.05-8. The default is 1.

Example:
b2kSheetLoad "tiles", tPath, 70, 70
b2kSheetScale "tiles", 0.9

Description:
Set it right after loading, before making sprites: frames already
sliced are dropped and re-sliced at the new scale, but existing sprite
buttons keep their size.

References: b2kSheetFrameSize (handler), b2kSheetLoad (handler)
*/
command b2kSheetScale pName, pScale
   local tKey, tId
   put b2kClamp(pScale, 0.05, 8) into pScale
   if b2kNumberOr(sSheetScale[pName], 1) is pScale then exit b2kSheetScale
   put pScale into sSheetScale[pName]
   repeat for each key tKey in sSheetIcon[pName]
      put sSheetIcon[pName][tKey] into tId
      if tId is not empty then
         try
            delete image id tId
         catch tErr
         end try
      end if
   end repeat
   repeat for each key tKey in sSheetFlip[pName]
      put sSheetFlip[pName][tKey] into tId
      if tId is not empty then
         try
            delete image id tId
         catch tErr
         end try
      end if
   end repeat
   delete variable sSheetIcon[pName]
   delete variable sSheetFlip[pName]
end b2kSheetScale

-- A frame's DISPLAY size as "w,h" (its region size times the sheet scale) --
-- lay out tiles and platforms from this instead of hard-coding pixels.
/**
Summary: A frame's display size.

pName: The sheet's name.

pFrame: The frame's name or number.

Returns: "w,h" in pixels (the region times the sheet scale), or empty for an unknown frame.

Example:
put item 1 of b2kSheetFrameSize("tiles", "grass") into tTileW

References: b2kSheetScale (handler)
*/
function b2kSheetFrameSize pName, pFrame
   local tRegion, tScale
   put sSheetRegion[pName][pFrame] into tRegion
   if tRegion is empty then return empty
   set the itemDelimiter to comma
   put b2kNumberOr(sSheetScale[pName], 1) into tScale
   return max(1, round((item 3 of tRegion) * tScale)) & comma & max(1, round((item 4 of tRegion) * tScale))
end b2kSheetFrameSize

-- Define a named animation: pFrames is a comma list of frame names and/or
-- 1-based indices, with numeric ranges ("1-8") expanded. pLoop defaults true.
/**
Summary: Define a named animation over a sheet's frames.

pSheet: The sheet's name.

pAnim: The animation's name.

pFrames: A comma list of frame names and numbers; a numeric range such as 1-8 expands.

pFPS: Frames per second, clamped to 0.1-120.

pLoop: false for a one-shot animation; anything else loops.

Example:
b2kAnimDef "chars", "walk", "character_beige_walk_a,character_beige_walk_b", 6, true

References: b2kSpritePlay (handler), b2kSpriteOnFinish (handler)
*/
command b2kAnimDef pSheet, pAnim, pFrames, pFPS, pLoop
   local tKey, tList, tItem, tA, tB, i
   put pSheet & "|" & pAnim into tKey
   put empty into tList
   set the itemDelimiter to comma
   repeat for each item tItem in pFrames
      put word 1 to -1 of tItem into tItem
      if tItem contains "-" and tItem is not a number then
         set the itemDelimiter to "-"
         put item 1 of tItem into tA
         put item 2 of tItem into tB
         set the itemDelimiter to comma
         if tA is a number and tB is a number then
            repeat with i = tA to tB
               put i & cr after tList
            end repeat
            next repeat
         end if
      end if
      put tItem & cr after tList
   end repeat
   if the last char of tList is cr then delete the last char of tList
   put tList into sAnimList[tKey]
   put b2kClamp(pFPS, 0.1, 120) into sAnimFPS[tKey]
   put (pLoop is not false) into sAnimLoop[tKey]
end b2kAnimDef

-- Create a sprite: a transparent button showing pFrame (default: the sheet's
-- first frame), centred on pX,pY and sized to the frame. Reports the control.
-- It is an ordinary Kit control: pass it to b2kAddCapsule/b2kAddBox for a
-- body (buttons render position-only with rotation locked), or bind it to
-- another control's body with b2kSpriteBind.
/**
Summary: Create a sprite: a transparent button showing a sheet frame.

pSheet: The sheet's name.

pFrame: The frame to show. Empty means the sheet's first frame.

pX: The centre x in pixels. Empty means the card's centre.

pY: The centre y in pixels. Empty means the card's centre.

Returns: The sprite's long id through the result, or empty for an unknown sheet or frame.

Example:
b2kSpriteNew "chars", "character_beige_idle", 200, 100
put the result into tSpr
b2kSpritePlay tSpr, "walk"

Description:
The button is sized to the frame. It is an ordinary Kit control:
give it a body with <b2kAddCapsule> or <b2kAddBox> (sprites follow position
and do not rotate), or pin it to another control with <b2kSpriteBind>.
<b2kClear> removes it.

References: b2kSpritePlay (handler), b2kSpriteBind (handler), b2kSpriteRemove (handler)
*/
command b2kSpriteNew pSheet, pFrame, pX, pY
   local tName, tRef, tKey, tRegion, tW, tH
   if sSheetKeys[pSheet] is empty then return empty
   put pFrame into tKey
   if tKey is empty then put line 1 of sSheetKeys[pSheet] into tKey
   put b2kSheetFrameSize(pSheet, tKey) into tRegion   -- "w,h" at display scale
   if tRegion is empty then return empty
   set the itemDelimiter to comma
   put item 1 of tRegion into tW
   put item 2 of tRegion into tH
   put b2kNumberOr(pX, (the width of this card) div 2) into pX
   put b2kNumberOr(pY, (the height of this card) div 2) into pY
   put "b2kspr_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create button tName
   else
      create button tName in group "b2kcam_view"
   end if
   put the long id of button tName into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   set the style of tRef to "transparent"
   set the showName of tRef to false
   set the traversalOn of tRef to false
   set the autoHilite of tRef to false
   subtract b2kCamShiftX(tRef) from pX   -- creation while scrolled: place in
   subtract b2kCamShiftY(tRef) from pY   -- world coords on visual engines too
   set the rect of tRef to round(pX - tW / 2), round(pY - tH / 2), round(pX + tW / 2), round(pY + tH / 2)
   if sCamGroup is empty then
      -- dynamic layers composite in STACK coordinates: inside a scrolled
      -- viewport they ignore the group scroll and draw unscrolled, so a
      -- camera sprite must stay a plain group child
      try
         set the layerMode of tRef to "dynamic"
      catch tErr
      end try
   end if
   put pSheet into sSprSheet[tRef]
   put "sheet" into sSprKind[tRef]
   put false into sSprFlip[tRef]
   put true into sSpawned[tRef]
   put tRef & cr after sSprRefs
   b2kSpriteShowFrame tRef, tKey
   return tRef
end b2kSpriteNew

-- A sprite backed by an animated GIF file: the engine plays it; the Kit's
-- play/stop/frame calls drive repeatCount/currentFrame instead of icons.
/**
Summary: Create a sprite from an animated GIF file.

pPath: The GIF file's path.

pX: The centre x in pixels. Empty means the card's centre.

pY: The centre y in pixels. Empty means the card's centre.

Returns: The image's long id through the result, or empty when the file cannot be loaded.

Example:
b2kSpriteFromGIF tFolder & "/flame.gif", 300, 200
put the result into tFlame

Description:
The engine plays the GIF. <b2kSpritePlay> and <b2kSpriteStop> set
its repeatCount and <b2kSpriteSetFrame> its currentFrame.

References: b2kSpriteNew (handler), b2kSpriteRemove (handler)
*/
command b2kSpriteFromGIF pPath, pX, pY
   local tName, tRef, tData
   put URL ("binfile:" & pPath) into tData   -- content-load, like the sheets
   if tData is empty then return empty
   put "b2kspr_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create image tName
   else
      create image tName in group "b2kcam_view"
   end if
   put the long id of image tName into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   try
      set the text of tRef to tData
   catch tErr
   end try
   set the lockLoc of tRef to true
   if the width of tRef < 1 then
      try
         delete tRef
      catch tErr
      end try
      return empty
   end if
   put b2kNumberOr(pX, (the width of this card) div 2) into pX
   put b2kNumberOr(pY, (the height of this card) div 2) into pY
   set the loc of tRef to round(pX - b2kCamShiftX(tRef)) & comma & round(pY - b2kCamShiftY(tRef))
   if sCamGroup is empty then
      try
         set the layerMode of tRef to "dynamic"   -- see b2kSpriteNew note
      catch tErr
      end try
   end if
   try
      set the repeatCount of tRef to -1
   catch tErr
   end try
   put "gif" into sSprKind[tRef]
   put true into sSpawned[tRef]
   put tRef & cr after sSprRefs
   return tRef
end b2kSpriteFromGIF

-- Start a named animation; a no-op if it is already playing (so calling it
-- every frame from a state machine is free) unless pRestart forces frame 1.
/**
Summary: Play a named animation on a sprite.

pCtrl: The sprite control, by reference. Empty makes this a no-op.

pAnim: The animation's name, defined with b2kAnimDef for the sprite's sheet.

pRestart: true to restart from the first frame when it is already playing.

Example:
b2kSpritePlay tSpr, "walk"

Description:
Playing the animation that is already playing does nothing, so a
state machine can call it every frame. An unknown animation is ignored.

References: b2kAnimDef (handler), b2kSpriteStop (handler), b2kSpriteAnim (handler), b2kSpriteFPS (handler)
*/
command b2kSpritePlay pCtrl, pAnim, pRestart
   local tRef, tKey
   -- ENGINE-FOUND 2026-08-16: an empty control is a harmless no-op, per the
   -- family law (stale handles never crash). `the long id of <empty>` THROWS,
   -- and the player path can legally reach here with no art: b2kPlayerAnims
   -- maps state names independently of art, and b2kPlayerShowState is a
   -- public entry point whose tick-side caller guards sPlayArt but whose
   -- direct callers cannot be expected to. The throw took a whole harness
   -- section down as error 69 with no useful name.
   if pCtrl is empty then exit b2kSpritePlay
   put the long id of pCtrl into tRef
   if sSprKind[tRef] is "gif" then
      try
         set the repeatCount of tRef to -1
      catch tErr
      end try
      exit b2kSpritePlay
   end if
   if sSprSheet[tRef] is empty then exit b2kSpritePlay
   put sSprSheet[tRef] & "|" & pAnim into tKey
   if sAnimList[tKey] is empty then exit b2kSpritePlay
   if sSprAnim[tRef] is pAnim and pRestart is not true then exit b2kSpritePlay
   put pAnim into sSprAnim[tRef]
   put true into sSprLiveDirty   -- it now needs per-frame service
   put 1 into sSprStep[tRef]
   if sSprFPSOver[tRef] is not empty then
      put sSprFPSOver[tRef] into sSprFPS[tRef]
   else
      put sAnimFPS[tKey] into sSprFPS[tRef]
   end if
   if sSprFPS[tRef] is empty or sSprFPS[tRef] <= 0 then put 8 into sSprFPS[tRef]
   put the milliseconds + (1000 / sSprFPS[tRef]) into sSprNextMS[tRef]
   b2kSpriteShowFrame tRef, line 1 of sAnimList[tKey]
end b2kSpritePlay

/**
Summary: Stop a sprite's animation on its current frame.

pCtrl: The sprite control, by reference. Empty makes this a no-op.

Example:
b2kSpriteStop tSpr

References: b2kSpritePlay (handler), b2kSpriteSetFrame (handler)
*/
command b2kSpriteStop pCtrl
   local tRef
   if pCtrl is empty then exit b2kSpriteStop   -- family law: empty ref = no-op
   put the long id of pCtrl into tRef
   if sSprKind[tRef] is "gif" then
      try
         set the repeatCount of tRef to 0
      catch tErr
      end try
      exit b2kSpriteStop
   end if
   put empty into sSprAnim[tRef]
   put true into sSprLiveDirty
end b2kSpriteStop

/**
Summary: The animation a sprite is playing.

pCtrl: The sprite control, by reference.

Returns: The animation's name, or empty when stopped or the control is gone.

Example:
if b2kSpriteAnim(tSpr) is empty then b2kSpritePlay tSpr, "idle"

References: b2kSpritePlay (handler)
*/
function b2kSpriteAnim pCtrl
   try
      return sSprAnim[the long id of pCtrl]
   catch tErr
      return empty   -- a removed control is a stale ref, not an error
   end try
end b2kSpriteAnim

-- Show one frame by name/index (stops any running animation first).
/**
Summary: Show one frame on a sprite, stopping any animation.

pCtrl: The sprite control, by reference. Empty makes this a no-op.

pFrame: The frame's name or number.

Example:
b2kSpriteSetFrame tSpr, "character_beige_hit"

References: b2kSpriteFrame (handler), b2kSpriteStop (handler)
*/
command b2kSpriteSetFrame pCtrl, pFrame
   local tRef
   if pCtrl is empty then exit b2kSpriteSetFrame   -- family law: empty ref = no-op
   put the long id of pCtrl into tRef
   if sSprKind[tRef] is "gif" then
      try
         set the repeatCount of tRef to 0
         set the currentFrame of tRef to pFrame
      catch tErr
      end try
      exit b2kSpriteSetFrame
   end if
   put empty into sSprAnim[tRef]
   put true into sSprLiveDirty
   b2kSpriteShowFrame tRef, pFrame
end b2kSpriteSetFrame

/**
Summary: The frame a sprite is showing.

pCtrl: The sprite control, by reference.

Returns: The frame's name or number, or empty.

Example:
put b2kSpriteFrame(tSpr) into tShown

References: b2kSpriteSetFrame (handler)
*/
function b2kSpriteFrame pCtrl
   try
      return sSprFrameKey[the long id of pCtrl]
   catch tErr
      return empty
   end try
end b2kSpriteFrame

-- Per-sprite speed override (empty = use each animation's own fps).
/**
Summary: Override a sprite's animation speed.

pCtrl: The sprite control, by reference. Empty makes this a no-op.

pFPS: Frames per second; empty goes back to each animation's own speed.

Example:
b2kSpriteFPS tSpr, 12

References: b2kSpritePlay (handler), b2kAnimDef (handler)
*/
command b2kSpriteFPS pCtrl, pFPS
   local tRef
   if pCtrl is empty then exit b2kSpriteFPS   -- family law: empty ref = no-op
   put the long id of pCtrl into tRef
   put pFPS into sSprFPSOver[tRef]
   if pFPS is a number and pFPS > 0 then put pFPS into sSprFPS[tRef]
end b2kSpriteFPS

-- Face left (true) or right (false). The mirrored frame image is created
-- the first time it is needed, by flip-cloning the sliced frame.
/**
Summary: Make a sprite face left or right.

pCtrl: The sprite control, by reference. Empty makes this a no-op.

pFlag: true to mirror the frames (face left), false for the art as drawn.

Example:
b2kSpriteFlipH tSpr, true

Description:
Mirrored frames are made the first time they are needed and shared by every sprite of the sheet.

References: b2kSpriteFlipped (handler), b2kSheetEnsureFlip (handler)
*/
command b2kSpriteFlipH pCtrl, pFlag
   local tRef
   -- ENGINE-FOUND 2026-08-16 (the b2kSpritePlay guard's sibling, one engine
   -- run later): b2kPlayerShowState's facing latch always fires on its first
   -- call (sPlayFlipNow starts empty, so `false is not empty` is true), so a
   -- direct call with no art reached this deref and error 69 took the whole
   -- harness section. Same law, same guard: an empty ref is a no-op.
   if pCtrl is empty then exit b2kSpriteFlipH
   put the long id of pCtrl into tRef
   if sSprSheet[tRef] is empty then exit b2kSpriteFlipH
   put (pFlag is true) into pFlag
   if sSprFlip[tRef] is pFlag then exit b2kSpriteFlipH
   put pFlag into sSprFlip[tRef]
   if sSprFrameKey[tRef] is not empty then b2kSpriteShowFrame tRef, sSprFrameKey[tRef]
end b2kSpriteFlipH

/**
Summary: Report whether a sprite is mirrored.

pCtrl: The sprite control, by reference.

Returns: true or false.

Example:
put b2kSpriteFlipped(tSpr) into tFacingLeft

References: b2kSpriteFlipH (handler)
*/
function b2kSpriteFlipped pCtrl
   try
      return (sSprFlip[the long id of pCtrl] is true)
   catch tErr
      return false
   end try
end b2kSpriteFlipped

-- When a NON-looping animation finishes, send pMessage to the frame target
-- with the sprite and the animation name (attack/death/effect chaining).
/**
Summary: Name a message to send when a one-shot animation ends.

pCtrl: The sprite control, by reference. Empty makes this a no-op.

pMessage: The message name; empty turns it off.

Example:
b2kSpriteOnFinish tSpr, "heroAttackDone"

Description:
When a non-looping animation on this sprite ends, the Kit sends the
message to the frame target (<b2kFrameTarget>) with two parameters, the
sprite and the animation name. It fires for every non-looping animation,
whoever started it.

References: b2kAnimDef (handler), b2kFrameTarget (handler)
*/
command b2kSpriteOnFinish pCtrl, pMessage
   if pCtrl is empty then exit b2kSpriteOnFinish   -- family law: empty ref = no-op
   put pMessage into sSprMsg[the long id of pCtrl]
end b2kSpriteOnFinish

-- Pin this sprite to another control's position each frame (offset in px) --
-- the standard pattern for "art bigger than the collision shape": give an
-- invisible control the body, bind the sprite to it.
/**
Summary: Pin a sprite to another control's position every frame.

pCtrl: The sprite control, by reference. Empty makes this a no-op.

pBodyCtrl: The control to follow, by reference. Empty makes this a no-op.

pDX: Optional x offset in pixels. Empty means 0.

pDY: Optional y offset in pixels. Empty means 0.

Example:
b2kSpriteBind tArt, tHitbox, 0, -6

Description:
The usual pattern for art bigger than its collision shape: an
invisible control owns the body and the sprite follows it.

References: b2kSpriteUnbind (handler), b2kSpriteNew (handler)
*/
command b2kSpriteBind pCtrl, pBodyCtrl, pDX, pDY
   local tRef
   -- family law: an empty ref on either side is a no-op (both are dereffed)
   if pCtrl is empty or pBodyCtrl is empty then exit b2kSpriteBind
   put the long id of pCtrl into tRef
   put the long id of pBodyCtrl into sSprBind[tRef]
   put b2kNumberOr(pDX, 0) into sSprBindDX[tRef]
   put b2kNumberOr(pDY, 0) into sSprBindDY[tRef]
   put true into sSprLiveDirty   -- it now needs per-frame service
end b2kSpriteBind

/**
Summary: Stop a sprite following another control.

pCtrl: The sprite control, by reference. Empty makes this a no-op.

Example:
b2kSpriteUnbind tArt

References: b2kSpriteBind (handler)
*/
command b2kSpriteUnbind pCtrl
   if pCtrl is empty then exit b2kSpriteUnbind   -- family law: empty ref = no-op
   delete variable sSprBind[the long id of pCtrl]
   put true into sSprLiveDirty
end b2kSpriteUnbind

-- Remove a sprite (and its body, if it has one).
/**
Summary: Remove a sprite, and its body if it has one.

pCtrl: The sprite control, by reference.

Example:
b2kSpriteRemove tSpr

Description:
A control that is already gone is still cleared from the Kit's records.

References: b2kSpriteNew (handler), b2kRemove (handler)
*/
command b2kSpriteRemove pCtrl
   local tRef
   try
      put the long id of pCtrl into tRef
   catch tErr
      put pCtrl into tRef   -- stale path (group gone): still clear the registry
   end try
   if sBody[tRef] is not empty then
      try
         b2kRemove tRef       -- destroys the body and deletes the control
      catch tErr
      end try
   else
      try
         delete tRef
      catch tErr
      end try
   end if
   b2kSpriteForget tRef
end b2kSpriteRemove

-- Internal: drop a sprite's registry entries (the control is already gone).
/**
Summary: Drop a sprite's records once its control is gone.

pRef: The sprite's long id.

Example:
b2kSpriteForget tSpr

Description:
Internal: <b2kSpriteRemove> and the sprite tick call it. It deletes no control.

References: b2kSpriteRemove (handler)
*/
command b2kSpriteForget pRef
   local tLn
   delete variable sSprSheet[pRef]
   delete variable sSprKind[pRef]
   delete variable sSprAnim[pRef]
   delete variable sSprStep[pRef]
   delete variable sSprNextMS[pRef]
   delete variable sSprFPS[pRef]
   delete variable sSprFPSOver[pRef]
   delete variable sSprFlip[pRef]
   delete variable sSprMsg[pRef]
   delete variable sSprBind[pRef]
   delete variable sSprBindDX[pRef]
   delete variable sSprBindDY[pRef]
   delete variable sSprFrameKey[pRef]
   delete variable sSprIconNow[pRef]
   delete variable sSprLastLoc[pRef]
   delete variable sInCam[pRef]
   set the wholeMatches to true
   put lineOffset(pRef, sSprRefs) into tLn
   if tLn > 0 then delete line tLn of sSprRefs
   put true into sSprLiveDirty
end b2kSpriteForget

-- Internal: remove every live sprite (b2kClear / b2kTeardown path).
/**
Summary: Remove every sprite.

Example:
b2kSpritesClear

Description:
Internal: <b2kClear> and <b2kTeardown> call it. Sheets stay loaded.

References: b2kSpriteRemove (handler), b2kClear (handler)
*/
command b2kSpritesClear
   local tRef, tList
   put sSprRefs into tList
   repeat for each line tRef in tList
      if tRef is not empty then b2kSpriteRemove tRef
   end repeat
   put empty into sSprRefs
   put empty into sSprLive
   put false into sSprLiveDirty
end b2kSpritesClear

-- Internal: forget one sheet -- its regions, anims, sliced/mirrored frame
-- images, and (if the Kit loaded it) the hidden source image.
/**
Summary: Forget one sheet.

pName: The sheet's name.

Example:
b2kSheetForget "coins"

Description:
It deletes the sheet's sliced and mirrored frame images, the source
image if the Kit loaded it, and the sheet's animations. Sprites that show it
stay on the card.

References: b2kSheetsWipe (handler)
*/
command b2kSheetForget pName
   local tKey, tId
   if sSheetSrc[pName] is empty and sSheetKeys[pName] is empty then exit b2kSheetForget
   repeat for each key tKey in sSheetIcon[pName]
      put sSheetIcon[pName][tKey] into tId
      if tId is not empty then
         try
            delete image id tId
         catch tErr
         end try
      end if
   end repeat
   repeat for each key tKey in sSheetFlip[pName]
      put sSheetFlip[pName][tKey] into tId
      if tId is not empty and tId is not sSheetIcon[pName][tKey] then
         try
            delete image id tId
         catch tErr
         end try
      end if
   end repeat
   if sSheetOwned[pName] is not false and sSheetSrc[pName] is not empty then
      try
         delete sSheetSrc[pName]
      catch tErr
      end try
   end if
   delete variable sSheetSrc[pName]
   delete variable sSheetOwned[pName]
   delete variable sSheetRegion[pName]
   delete variable sSheetKeys[pName]
   delete variable sSheetIcon[pName]
   delete variable sSheetFlip[pName]
   delete variable sSheetData[pName]
   delete variable sSheetAlpha[pName]
   delete variable sSheetScale[pName]
   delete variable sSheetPath[pName]
   repeat for each key tKey in sAnimList
      if char 1 to (the number of chars of pName) + 1 of tKey is pName & "|" then
         delete variable sAnimList[tKey]
         delete variable sAnimFPS[tKey]
         delete variable sAnimLoop[tKey]
      end if
   end repeat
end b2kSheetForget

-- Internal: every sheet + every sprite (b2kTeardown path).
/**
Summary: Forget every sheet and remove every sprite.

Example:
b2kSheetsWipe

Description:
It also deletes Kit-made sprite and sheet images a previous session
left on the card. <b2kTeardown> calls it unless sheets persist; call it
yourself to force a clean reload.

References: b2kSheetForget (handler), b2kSheetPersist (handler), b2kSpriteSweepOrphans (handler)
*/
command b2kSheetsWipe
   local tName
   b2kSpritesClear
   repeat for each key tName in sSheetSrc
      b2kSheetForget tName
   end repeat
   put empty into sSheetSrc
   put empty into sSheetRegion
   put empty into sSheetKeys
   put empty into sSheetIcon
   put empty into sSheetFlip
   put empty into sSheetData
   put empty into sSheetAlpha
   put empty into sSheetScale
   put empty into sSheetPath
   put empty into sAnimList
   put empty into sAnimFPS
   put empty into sAnimLoop
   b2kSpriteSweepOrphans
end b2kSheetsWipe

-- Internal: delete Kit-generated sprite/sheet controls left over from a
-- PREVIOUS session. Script-locals reset when a stack reopens (or a new
-- script is pasted in), but the controls persist -- registry cleanup can't
-- see them, so a reopened stack would show ghost sprites frozen on their
-- last frame. Swept by name prefix on every teardown.
/**
Summary: Delete Kit controls a previous session left on the card.

pKeepAssets: true to keep sheet images (sources and frames) and delete only sprites and dead viewports.

Example:
b2kSpriteSweepOrphans false

Description:
A reopened stack resets script variables but keeps its controls,
so old sprites would linger frozen. It deletes controls on this card
named with the Kit's prefixes: dead camera viewports (ungrouped first),
sprites, and unless kept, sheet images. Teardowns call it.

References: b2kSheetsWipe (handler), b2kTeardown (handler)
*/
command b2kSpriteSweepOrphans pKeepAssets
   local tAgain, i, tName, tHit
   -- 1) dissolve dead viewports first. Ungrouping RENUMBERS the card's
   --    controls, so the scan restarts after each one (there are few).
   put true into tAgain
   repeat while tAgain
      put false into tAgain
      repeat with i = 1 to the number of controls of this card
         put the short name of control i of this card into tName
         if char 1 to 7 of tName is "b2kcam_" then
            -- a dead session's viewport: free the children, then the shell
            try
               ungroup control i of this card
            catch tErr
               delete control i of this card
            end try
            put true into tAgain
            exit repeat
         end if
      end repeat
   end repeat
   -- 2) everything else in ONE backward pass: deleting control i never
   --    renumbers the controls below it, so nothing restarts. (Restarting
   --    from control 1 after every delete was quadratic, and a persisted
   --    sheet cache keeps hundreds of frame images on the card for every
   --    rescan to walk past.) The guard covers a delete that took more than
   --    one control with it.
   repeat with i = the number of controls of this card down to 1
      if i > the number of controls of this card then next repeat
      put the short name of control i of this card into tName
      put false into tHit
      if char 1 to 7 of tName is "b2kspr_" then put true into tHit
      -- sheet ASSET images (sources + sliced frames + flips) are KEPT
      -- when persisting (b2kSheetPersist); only sprite instances + dead
      -- viewports go, so the sheet cache survives the teardown
      if pKeepAssets is not true then
         if char 1 to 6 of tName is "b2kfr_" then put true into tHit
         if char 1 to 6 of tName is "b2kfl_" then put true into tHit
         if char 1 to 9 of tName is "b2ksheet_" then put true into tHit
      end if
      if tHit then delete control i of this card
   end repeat
end b2kSpriteSweepOrphans

-- ---- sprite internals ------------------------------------------------

-- Internal: load an image file into a hidden, Kit-owned source image.
-- The bytes are loaded as CONTENT (binfile -> set the text), not as a
-- filename reference: referenced images size and load lazily for hidden
-- controls, which broke the slicer's stride; content images adopt their
-- pixel size immediately -- the exact path b2kSheetFromImage users (and
-- the platformer's embedded placeholder) already exercise successfully.
-- lockLoc only AFTER the content, so the control has auto-sized first.
/**
Summary: Load an image file into the hidden source image of a sheet.

pName: The sheet's name.

pPath: The image file's path.

Returns: The source image's long id, or empty on failure.

Example:
put b2kSheetSourceFromFile("coins", tPath) into tImg

Description:
Internal: the sheet loaders call it. The file is loaded as image
content. When sheets persist and an image already loaded from the same path
is in the stack, it is reused without reading the file.

References: b2kSheetLoad (handler), b2kSheetLoadAtlas (handler)
*/
function b2kSheetSourceFromFile pName, pPath
   local tImg, tData
   put "b2ksheet_" & pName into tImg
   -- REUSE: a source image already decoded for this exact file -- earlier
   -- this session, or carried inside a SAVED stack (b2kSheetPersist) -- is
   -- the cache. Adopt it in place and skip the costly binfile decode.
   if sSheetKeep is true and there is an image tImg \
         and the uB2kSrcPath of image tImg is pPath and the width of image tImg >= 2 then
      set the lockLoc of image tImg to true
      put the long id of image tImg into sSheetSrc[pName]
      put true into sSheetOwned[pName]
      return sSheetSrc[pName]
   end if
   b2kSheetForget pName
   if there is no file pPath then return empty
   put URL ("binfile:" & pPath) into tData
   if tData is empty then return empty
   if there is an image tImg then delete image tImg
   create image tImg
   set the visible of it to false
   try
      set the text of image tImg to tData
   catch tErr
      delete image tImg
      return empty
   end try
   if the width of image tImg < 2 then
      delete image tImg
      return empty
   end if
   set the lockLoc of image tImg to true
   set the uB2kSrcPath of image tImg to pPath   -- the cache key for next time
   put the long id of image tImg into sSheetSrc[pName]
   put true into sSheetOwned[pName]
   return sSheetSrc[pName]
end b2kSheetSourceFromFile

-- Internal: register grid regions over the current source image. Margin =
-- outer border (left AND top, assumed symmetric), spacing = gap between
-- cells; both default 0 (edge-to-edge, the common case). A frame size of
-- 0/empty registers NO grid -- the caller names regions with
-- b2kSheetAddFrame instead.
/**
Summary: Register numbered grid frames over a sheet's source image.

pName: The sheet's name.

pFW: Frame width in pixels; 0 or empty registers no grid.

pFH: Frame height in pixels; 0 or empty registers no grid.

pCount: Optional number of frames to register; empty means every whole cell.

pMargin: Optional outer border in pixels. Empty means 0.

pSpacing: Optional gap between cells in pixels. Empty means 0.

Example:
b2kSheetGridRegions "coins", 32, 32, empty, 0, 0

Description:
Internal: the grid loaders call it. A frame size below 1 registers nothing.

References: b2kSheetLoad (handler), b2kSheetFromImage (handler)
*/
command b2kSheetGridRegions pName, pFW, pFH, pCount, pMargin, pSpacing
   local tCols, tRows, tMax, i, tC, tR
   if sSheetSrc[pName] is empty then exit b2kSheetGridRegions
   if b2kNumberOr(pFW, 0) < 1 or b2kNumberOr(pFH, 0) < 1 then exit b2kSheetGridRegions
   put b2kClamp(pFW, 1, 4096) into pFW
   put b2kClamp(pFH, 1, 4096) into pFH
   put round(b2kClamp(pMargin, 0, 2048)) into pMargin
   put round(b2kClamp(pSpacing, 0, 2048)) into pSpacing
   put ((the width of sSheetSrc[pName]) - 2 * pMargin + pSpacing) div (pFW + pSpacing) into tCols
   put ((the height of sSheetSrc[pName]) - 2 * pMargin + pSpacing) div (pFH + pSpacing) into tRows
   if tCols < 1 or tRows < 1 then exit b2kSheetGridRegions
   put tCols * tRows into tMax
   if pCount is a number and pCount > 0 and pCount < tMax then put pCount into tMax
   repeat with i = 1 to tMax
      put (i - 1) mod tCols into tC
      put (i - 1) div tCols into tR
      put (pMargin + tC * (pFW + pSpacing)) & comma & (pMargin + tR * (pFH + pSpacing)) & comma & pFW & comma & pFH into sSheetRegion[pName][i]
      put i & cr after sSheetKeys[pName]
   end repeat
   if the last char of sSheetKeys[pName] is cr then delete the last char of sSheetKeys[pName]
end b2kSheetGridRegions

-- Internal: one attribute value out of an XML tag line (attr="value").
/**
Summary: Read one attribute value from an XML tag line.

pLine: A line holding one XML tag.

pAttr: The attribute's name.

Returns: The attribute's value, or empty when it is absent.

Example:
put b2kXmlAttr(tLine, "width") into tW

Description:
The atlas loader's small parser.

References: b2kSheetLoadAtlas (handler)
*/
function b2kXmlAttr pLine, pAttr
   local tFrom, tLen
   put offset(pAttr & "=" & quote, pLine) into tFrom
   if tFrom is 0 then return empty
   add the number of chars of pAttr + 2 to tFrom
   put offset(quote, pLine, tFrom - 1) into tLen
   if tLen is 0 then return empty
   return char tFrom to tFrom + tLen - 2 of pLine
end b2kXmlAttr

-- Internal: make sure a frame's sliced image exists (lazy, cached). The
-- source pixels are fetched once per sheet and kept until teardown.
-- Internal: the 1-based position of a frame key in its sheet's key list --
-- a STABLE id (load order is deterministic) used to name sliced frames so a
-- SAVED stack can find and reuse them (b2kSheetPersist), never duplicating.
/**
Summary: A frame's position in its sheet.

pSheet: The sheet's name.

pKey: The frame's name or number.

Returns: The 1-based position in definition order, or 0 when absent.

Example:
put b2kSheetKeyIndex("chars", "character_beige_idle") into tPos

Description:
It names saved slices so a reopened stack can find and reuse them.

References: b2kSheetSliceSig (handler)
*/
function b2kSheetKeyIndex pSheet, pKey
   local i, tK
   put 0 into i
   repeat for each line tK in sSheetKeys[pSheet]
      add 1 to i
      if tK is pKey then return i
   end repeat
   return 0
end b2kSheetKeyIndex

-- Internal: a slice's provenance stamp. A saved frame image is only safe to
-- reuse if it was baked from the CURRENT source (sSheetPath already encodes
-- the file/image + grid/xml args) at the CURRENT scale. Stamped onto each
-- slice as uB2kSig and re-checked on reuse, so a reopened stack that reuses a
-- sheet NAME for different art, or changes a sheet's scale, re-slices instead
-- of adopting stale pixels (the name alone is not a safe identity).
/**
Summary: A sheet's provenance stamp.

pSheet: The sheet's name.

Returns: A string naming the sheet's source, its load arguments and its scale.

Example:
put b2kSheetSliceSig("chars") into tSig

Description:
A saved slice is reused only when its stamp matches, so new art or a new scale is re-sliced.

References: b2kSheetKeyIndex (handler), b2kSheetEnsureIcon (handler)
*/
function b2kSheetSliceSig pSheet
   return sSheetPath[pSheet] & "|" & b2kNumberOr(sSheetScale[pSheet], 1)
end b2kSheetSliceSig

/**
Summary: Slice a frame's image now instead of on first display.

pSheet: The sheet's name.

pKey: The frame's name or number.

Example:
b2kSheetEnsureIcon "chars", "character_beige_hit"

Description:
Frames are sliced lazily, and a slice made mid-game costs a visible
hitch. Pre-warm frames that first appear during play. The result is cached,
so a second call is free.

References: b2kSheetEnsureFlip (handler), b2kSheetScale (handler)
*/
command b2kSheetEnsureIcon pSheet, pKey
   local tRegion, tX, tY, tW, tH, tSW, tRowPx, tFD, tFA, y, tName, tScale, tW2, tH2
   if sSheetIcon[pSheet][pKey] is not empty then exit b2kSheetEnsureIcon
   put sSheetRegion[pSheet][pKey] into tRegion
   if tRegion is empty then exit b2kSheetEnsureIcon
   -- Frame image name. Persisting: a DETERMINISTIC name (b2kfr_<sheet>_<n>)
   -- lets a slice carried in a SAVED stack be found and reused -- but only if
   -- its uB2kSig still matches (baked from the current source at the current
   -- scale), so a reused sheet name or a changed scale re-slices rather than
   -- show stale pixels. Off the persist path: a fresh unique name (no key
   -- scan; the slice is wiped on teardown anyway), exactly as before.
   if sSheetKeep is true then
      put "b2kfr_" & pSheet & "_" & b2kSheetKeyIndex(pSheet, pKey) into tName
      if there is an image tName and the uB2kSig of image tName is b2kSheetSliceSig(pSheet) then
         put the id of image tName into sSheetIcon[pSheet][pKey]
         exit b2kSheetEnsureIcon
      end if
   else
      put "b2kfr_" & the milliseconds & "_" & random(1000000) into tName
   end if
   if sSheetData[pSheet] is empty then
      put the imageData of sSheetSrc[pSheet] into sSheetData[pSheet]
      put the alphaData of sSheetSrc[pSheet] into sSheetAlpha[pSheet]
   end if
   set the itemDelimiter to comma
   put item 1 of tRegion into tX
   put item 2 of tRegion into tY
   put item 3 of tRegion into tW
   put item 4 of tRegion into tH
   put the width of sSheetSrc[pSheet] into tSW
   -- refuse to slice from inconsistent pixels: a stride mismatch must yield
   -- an empty (invisible) frame, never garbage on screen
   if the number of bytes in sSheetData[pSheet] is not tSW * (the height of sSheetSrc[pSheet]) * 4 then exit b2kSheetEnsureIcon
   if tX + tW > tSW then exit b2kSheetEnsureIcon
   put empty into tFD
   put empty into tFA
   repeat with y = 0 to tH - 1
      put (tY + y) * tSW + tX into tRowPx
      put byte (tRowPx * 4 + 1) to (tRowPx * 4 + tW * 4) of sSheetData[pSheet] after tFD
      put byte (tRowPx + 1) to (tRowPx + tW) of sSheetAlpha[pSheet] after tFA
   end repeat
   if the number of bytes in tFD is not tW * tH * 4 then exit b2kSheetEnsureIcon
   if the number of bytes in tFA is not tW * tH then
      put empty into tFA   -- no usable alpha: ship the frame fully opaque
   end if
   if there is an image tName then delete image tName   -- never duplicate a deterministic slice
   create image tName
   set the visible of it to false
   set the lockLoc of it to true
   set the width of it to tW
   set the height of it to tH
   set the imageData of image tName to tFD
   if tFA is not empty then set the alphaData of image tName to tFA
   -- sheet scale: resize the control (the engine resamples the render),
   -- then bake that render back in as the frame's real pixels
   put b2kNumberOr(sSheetScale[pSheet], 1) into tScale
   if tScale is not 1 then
      put max(1, round(tW * tScale)) into tW2
      put max(1, round(tH * tScale)) into tH2
      set the width of image tName to tW2
      set the height of image tName to tH2
      put the imageData of image tName into tFD
      put the alphaData of image tName into tFA
      set the imageData of image tName to tFD
      if tFA is not empty then set the alphaData of image tName to tFA
   end if
   if sSheetKeep is true then set the uB2kSig of image tName to b2kSheetSliceSig(pSheet)
   put the id of image tName into sSheetIcon[pSheet][pKey]
end b2kSheetEnsureIcon

-- Internal: the mirrored copy of a frame (falls back to the unmirrored
-- frame if this engine's flip throws, so facing left never errors).
/**
Summary: Make a frame's mirrored image now instead of on first display.

pSheet: The sheet's name.

pKey: The frame's name or number.

Example:
b2kSheetEnsureFlip "chars", "character_beige_walk_a"

Description:
It slices the frame first if needed. If this engine's flip fails, the unmirrored frame is used.

References: b2kSheetEnsureIcon (handler), b2kSpriteFlipH (handler)
*/
command b2kSheetEnsureFlip pSheet, pKey
   local tName
   if sSheetFlip[pSheet][pKey] is not empty then exit b2kSheetEnsureFlip
   if sSheetKeep is true then
      put "b2kfl_" & pSheet & "_" & b2kSheetKeyIndex(pSheet, pKey) into tName
      if there is an image tName and the uB2kSig of image tName is b2kSheetSliceSig(pSheet) then
         put the id of image tName into sSheetFlip[pSheet][pKey]   -- reuse a saved flip
         exit b2kSheetEnsureFlip
      end if
   else
      put "b2kfl_" & the milliseconds & "_" & random(1000000) into tName
   end if
   b2kSheetEnsureIcon pSheet, pKey
   if sSheetIcon[pSheet][pKey] is empty then exit b2kSheetEnsureFlip
   try
      if there is an image tName then delete image tName
      clone image id sSheetIcon[pSheet][pKey]
      set the name of it to tName
      set the visible of it to false
      flip image tName horizontal
      if sSheetKeep is true then set the uB2kSig of image tName to b2kSheetSliceSig(pSheet)
      put the id of image tName into sSheetFlip[pSheet][pKey]
   catch tErr
      put sSheetIcon[pSheet][pKey] into sSheetFlip[pSheet][pKey]
   end try
end b2kSheetEnsureFlip

-- Internal: point a sprite's icon at a frame, honouring its facing. Skips
-- the property set when the icon is already right (the sDrawKey idea).
/**
Summary: Point a sprite's icon at a frame.

pRef: The sprite's long id.

pKey: The frame's name or number.

Example:
b2kSpriteShowFrame tSpr, 3

Description:
Internal: it honours the sprite's facing and skips the icon set when
the frame is already shown. It does not stop an animation; use
<b2kSpriteSetFrame> for that.

References: b2kSpriteSetFrame (handler)
*/
command b2kSpriteShowFrame pRef, pKey
   local tSheet, tIcon
   put sSprSheet[pRef] into tSheet
   if tSheet is empty then exit b2kSpriteShowFrame
   if sSprFlip[pRef] is true then
      b2kSheetEnsureFlip tSheet, pKey
      put sSheetFlip[tSheet][pKey] into tIcon
   else
      b2kSheetEnsureIcon tSheet, pKey
      put sSheetIcon[tSheet][pKey] into tIcon
   end if
   if tIcon is empty then exit b2kSpriteShowFrame
   put pKey into sSprFrameKey[pRef]
   if sSprIconNow[pRef] is tIcon then exit b2kSpriteShowFrame
   set the icon of pRef to tIcon
   put tIcon into sSprIconNow[pRef]
end b2kSpriteShowFrame

-- Internal: per-frame service -- bound sprites follow their body's control,
-- playing animations advance on wall-clock time. Vanished controls are
-- forgotten, like the body sync does.
/**
Summary: Run one frame of sprite service.

Example:
b2kSpritesTick

Description:
Internal: the loop calls it each frame. Bound sprites follow their
control and playing animations advance on wall-clock time; sprites whose
control vanished are forgotten. Only bound or playing sprites are visited.

References: b2kSpriteBind (handler), b2kSpritePlay (handler)
*/
command b2kSpritesTick
   local tNow, tRef, tDead, tSheet, tAnim, tAKey, tList, tStep, tN, tLoc, tBX, tBY
   if sSprRefs is empty then exit b2kSpritesTick
   -- the tick walks only the LIVE subset (bound and/or playing); the
   -- list rebuilds lazily when membership changed. Tile-heavy scenes
   -- are ~90% inert sprites, and per-frame cost must not scale with
   -- them (a platformer level: ~100 tiles skipped, ~25 live serviced).
   if sSprLiveDirty is true then
      put empty into sSprLive
      repeat for each line tRef in sSprRefs
         if tRef is empty then next repeat
         if sSprBind[tRef] is not empty or sSprAnim[tRef] is not empty then
            put tRef & cr after sSprLive
         end if
      end repeat
      put false into sSprLiveDirty
   end if
   if sSprLive is empty then exit b2kSpritesTick
   put the milliseconds into tNow
   put empty into tDead
   set the itemDelimiter to comma
   repeat for each line tRef in sSprLive
      if tRef is empty then next repeat
      -- still-inert guard: membership changed mid-frame retires next tick
      if sSprBind[tRef] is empty and sSprAnim[tRef] is empty then next repeat
      try
         if sSprBind[tRef] is not empty then
            put the loc of sSprBind[tRef] into tLoc
            put (item 1 of tLoc) + b2kCamShiftX(sSprBind[tRef]) + sSprBindDX[tRef] into tBX
            put (item 2 of tLoc) + b2kCamShiftY(sSprBind[tRef]) + sSprBindDY[tRef] into tBY
            put tBX & comma & tBY into tLoc
            if sSprLastLoc[tRef] is not tLoc then
               set the loc of tRef to (tBX - b2kCamShiftX(tRef)) & comma & (tBY - b2kCamShiftY(tRef))
               put tLoc into sSprLastLoc[tRef]
            end if
         end if
         if sSprKind[tRef] is "sheet" and sSprAnim[tRef] is not empty then
            if tNow >= sSprNextMS[tRef] then
               put sSprSheet[tRef] into tSheet
               put sSprAnim[tRef] into tAnim
               put tSheet & "|" & tAnim into tAKey
               put sAnimList[tAKey] into tList
               put the number of lines of tList into tN
               put sSprStep[tRef] + 1 into tStep
               if tStep > tN then
                  if sAnimLoop[tAKey] is false then
                     put empty into sSprAnim[tRef]
                     put true into sSprLiveDirty   -- (if also unbound) retire it
                     if sSprMsg[tRef] is not empty and sFrameObj is not empty then
                        dispatch sSprMsg[tRef] to sFrameObj with tRef, tAnim
                     end if
                     next repeat
                  end if
                  put 1 into tStep
               end if
               put tStep into sSprStep[tRef]
               add (1000 / sSprFPS[tRef]) to sSprNextMS[tRef]
               if sSprNextMS[tRef] < tNow then put tNow + (1000 / sSprFPS[tRef]) into sSprNextMS[tRef]
               b2kSpriteShowFrame tRef, (line tStep of tList)
            end if
         end if
      catch tErr
         put tRef & cr after tDead   -- control vanished; clean up below
      end try
   end repeat
   repeat for each line tRef in tDead
      if tRef is not empty then b2kSpriteForget tRef
   end repeat
end b2kSpritesTick

-- =====================================================================
-- Player: a platformer character controller (input -> motion + anims)
-- =====================================================================
-- ONE keyboard-driven player (spec section 6): a vertical capsule with
-- fixed rotation, sleep disabled and low friction, steered by a per-frame
-- tick that reads the Input module's axes "moveX"/"moveY" and action
-- "jump" (rebind those names to remap the controls). Horizontal motion is
-- velocity-driven -- vx is accelerated toward axis * moveSpeed, so
-- stopping needs no friction and walls can't glue the character.
-- Grounding is decided by short downward rays whose surface normal must
-- point sufficiently up, which makes walkable-slope vs wall one cosine
-- compare. The feel features platformers expect are built in: coyote
-- time, jump buffering, release jump-cut (tap = hop, hold = full jump),
-- a terminal fall speed, and a one-tick "land" state for dust and sound.
-- Wave 2 actions: DOWN ducks (brake to a stop; the hitbox keeps its
-- size this wave); DOWN+JUMP on a ONE-WAY CHAIN drops through it (a
-- dropMs window without chain collision); UP (or DOWN in the air) in a
-- b2kPlayerAddLadder zone climbs (gravity 0, velocity-driven, JUMP
-- exits); b2kPlayerHurt is the contact-damage knockback standard.
-- With b2kPlayerAnims set, the controller drives b2kSpritePlay/FlipH on
-- the player's art -- the player control itself when it IS a sprite, or
-- the first sprite b2kSpriteBind-pinned to it (the invisible-body
-- pattern). Tuning lives in b2kPlayerSet/Get; b2kClear keeps it (it is
-- config, like input bindings); b2kTeardown and b2kPlayerRemove wipe it.

-- One call: an invisible capsule host (or a visible capsule graphic when
-- no sheet is given), the body, the controller, input armed. With pSheet,
-- a sprite showing the sheet's first frame is created and bound on top --
-- so the collision size (pW x pH) is independent of the art size.
-- Reports the player control (give that to b2kCamFollow, sensors, etc).
/**
Summary: Create a platformer player in one call.

pX: The centre x in pixels. Not a number means the world origin's x.

pY: The centre y in pixels. Not a number means the world origin's y.

pW: The collision width in pixels. Empty means 32.

pH: The collision height in pixels. Empty means 48.

pSheet: Optional sheet name: a sprite of its first frame is created and pinned on top.

Returns: The player control's long id through the result, or empty when there is no world.

Example:
b2kPlayerMake 200, 100, 32, 48, "chars"
put the result into gHero
b2kPlayerAnims "idle", "walk", "jump"
b2kCamFollow gHero

Description:
It creates a rectangle graphic as the body host (hidden when a
sprite of the sheet is made), attaches it with <b2kPlayerAttach>, and turns
input on. The collision size is independent of the art size. Give the
returned control to <b2kCamFollow> and your hazard checks.

References: b2kPlayerAttach (handler), b2kPlayerAnims (handler), b2kPlayerSet (handler), b2kPlayer (handler)
*/
command b2kPlayerMake pX, pY, pW, pH, pSheet
   local tName, tRef, tArt
   if sWorld is empty then return empty
   if pW is empty then put 32 into pW
   if pH is empty then put 48 into pH
   put b2kClamp(pW, 4, 10000) into pW
   put b2kClamp(pH, 4, 10000) into pH
   put b2kNumberOr(pX, sOriginX) into pX
   put b2kNumberOr(pY, sOriginY) into pY
   put "b2kspawn_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create graphic (tName)
   else
      create graphic (tName) in group "b2kcam_view"
   end if
   put the long id of graphic (tName) into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   set the style of tRef to "rectangle"
   set the filled of tRef to true
   set the foregroundColor of tRef to "20,20,24"
   set the backgroundColor of tRef to "70,130,220"
   set the width of tRef to pW
   set the height of tRef to pH
   set the loc of tRef to round(pX - b2kCamShiftX(tRef)) & "," & round(pY - b2kCamShiftY(tRef))
   put true into sSpawned[tRef]
   if pSheet is not empty and sSheetKeys[pSheet] is not empty then
      set the visible of tRef to false       -- the graphic is only the body host
      b2kSpriteNew pSheet, empty, pX, pY
      put the result into tArt
      if tArt is not empty then
         b2kSpriteBind tArt, tRef
      else
         set the visible of tRef to true     -- sprite failed: stay visible
      end if
   end if
   b2kPlayerAttach tRef   -- adds the capsule (tall rect -> vertical pill)
   return tRef
end b2kPlayerMake

-- Adopt an existing control (or sprite) as the player. A capsule body is
-- added if it has none -- then the controller also sets its material (low
-- friction); a body you made yourself is left exactly as you tuned it.
/**
Summary: Make an existing control the player.

pCtrl: The control, by reference (the long id of the control is safest).

Example:
b2kPlayerAttach the long id of graphic "Hitbox"

Description:
A control without a body gets a capsule body with low friction
(0.08) and no bounce; a body you made yourself keeps its material. The body
gets fixed rotation and is never allowed to sleep, and input is turned on.

There is one player at a time: attaching another replaces the controller's
state, and the old body and sprite stay. With no world it does nothing.

References: b2kPlayerMake (handler), b2kPlayerRemove (handler), b2kPlayerAnims (handler)
*/
command b2kPlayerAttach pCtrl
   local tRef
   if sWorld is empty then exit b2kPlayerAttach
   put the long id of pCtrl into tRef
   put false into sPlayOwnBody
   -- capture the capsule's canonical dims BEFORE b2kAddCapsule's first draw
   -- re-points the graphic and pads its rect by the pen margin: these are what
   -- the duck/stand rebuilds hand b2kReshape, so the physical capsule always
   -- re-derives from one stable pair instead of the drawn rect (which OXT
   -- will not resize by a height-set and which grows +2 per redraw)
   put (the width of tRef) into sPlayCapW
   put (the height of tRef) into sPlayCapH
   if sBody[tRef] is empty then
      b2kAddCapsule tRef
      if sBody[tRef] is empty then exit b2kPlayerAttach   -- zero-sized control
      put true into sPlayOwnBody
      b2kSetFriction tRef, 0.08   -- low: walls must not glue the capsule
      b2kSetBounce tRef, 0        -- characters land DEAD: the default 0.2
                                  -- restitution rebounded every landing
                                  -- (~13px hop = double land ticks/sounds)
   end if
   put tRef into sPlayRef
   b2kSetFixedRotation tRef, true
   b2kSetSleepEnabled tRef, false   -- a player must always respond
   put (the width of tRef) / 2 into sPlayHalfW
   put (the height of tRef) / 2 into sPlayHalfH
   put (the height of tRef) into sPlayStandH   -- full height, for the duck reshape
   put "idle" into sPlayState
   put 1 into sPlayFacing
   put false into sPlayGrounded
   put 0 into sPlayGroundMS
   put 0 into sPlayPressMS
   put false into sPlayJumping
   put true into sPlayControl
   put 0 into sPlayHoldMS
   put 0 into sPlayClock
   put 0 into sPlayAir
   put empty into sPlayAnimNow
   put empty into sPlayFlipNow
   -- Wave 2 state starts clean (ladder ZONES survive an attach: they are
   -- world geometry, registered before or after the player exists)
   put 0 into sPlayPX
   put 0 into sPlayPY
   put false into sPlayOnOneWay
   put 0 into sPlayDropUntil
   put 0 into sPlayDropHard
   put empty into sPlayDropMask
   put false into sPlayClimb
   put empty into sPlayGravSave
   put false into sPlaySwim
   put empty into sPlaySwimGravSave
   put false into sPlayHurt
   put 0 into sPlayHurtEnd
   put 0 into sPlayHurtHalf
   put 0 into sPlayHurtLand
   put 0 into sPlayInvulnUntil
   -- Wave 5 state starts clean (the knobs decide whether each is reachable)
   put 0 into sPlayAirJumpsLeft
   put 0 into sPlayWall
   put false into sPlayWallSliding
   put 0 into sPlayWallLockUntil
   put false into sPlayDash
   put 0 into sPlayDashEnd
   put 0 into sPlayDashReady
   put 0 into sPlayDashDir
   put empty into sPlayDashGravSave
   put false into sPlayDucked
   put empty into sPlayGroundBody
   put false into sPlayInLad
   put false into sPlayInWat
   if sPlayLadN is empty then put 0 into sPlayLadN
   b2kPlayerTuneCache   -- bake the knobs + probe geometry for the tick
   b2kPlayerResolveArt
   b2kInputOn   -- arms the sampler; starter bindings fill empty slots only
end b2kPlayerAttach

-- Internal: which control's animations the controller drives -- the
-- player itself when it is a sprite, else the first sprite bound to it.
/**
Summary: Find the control whose animations the controller drives.

Example:
b2kPlayerResolveArt
put b2kPlayerSprite() into tArt

Description:
Internal: the player itself if it is a sprite, else the first
sprite pinned to it with <b2kSpriteBind>. Call it after binding new art to an
existing player.

References: b2kPlayerSprite (handler), b2kSpriteBind (handler)
*/
command b2kPlayerResolveArt
   local tRef
   put empty into sPlayArt
   if sPlayRef is empty then exit b2kPlayerResolveArt
   if sSprSheet[sPlayRef] is not empty then
      put sPlayRef into sPlayArt
      exit b2kPlayerResolveArt
   end if
   repeat for each line tRef in sSprRefs
      if sSprBind[tRef] is sPlayRef then
         put tRef into sPlayArt
         exit b2kPlayerResolveArt
      end if
   end repeat
end b2kPlayerResolveArt

-- Tuning knobs (pixels, px/s, ms, degrees). Keys: moveSpeed, accel,
-- airAccel, jumpSpeed, jumpCut, coyoteMs, bufferMs, maxFall, maxSlopeDeg,
-- dropMs (drop-through window), climbSpeed (ladder px/s), swimSpeed/
-- swimJump (water px/s + stroke), swimGravity/swimMaxFall (buoyancy),
-- hurtPopX/hurtPopY (knockback launch px/s), hurtMs (control-off span),
-- invulnMs (post-hurt mercy). Wave 5, all OPT-IN (default = off): airJumps
-- (extra mid-air jumps; 1 = double-jump), wallJumpX/wallJumpY (wall-jump
-- launch px/s) + wallSlideMax (capped slide fall px/s), dashSpeed/dashMs/
-- dashCooldownMs (the dash; bind the "dash" action), duckScale (ducked
-- capsule height as a fraction of standing, <1 to crawl), platformCarry
-- (1 = ride moving platforms). Settable any time, before or after the
-- player exists; unknown keys are stored verbatim for your own use.
/**
Summary: Set a player tuning knob.

pKey: The knob's name (case does not matter).

pValue: The new value; empty goes back to the default.

Example:
b2kPlayerSet "jumpSpeed", 520
b2kPlayerSet "airJumps", 1

Description:
Knobs: moveSpeed, accel, airAccel, jumpSpeed, jumpCut, coyoteMs,
bufferMs, maxFall, maxSlopeDeg, dropMs, climbSpeed, swimSpeed, swimJump,
swimGravity, swimMaxFall, hurtPopX, hurtPopY, hurtMs, invulnMs, and the
opt-in airJumps, wallJumpX, wallJumpY, wallSlideMax, dashSpeed, dashMs,
dashCooldownMs, airDash, duckScale and platformCarry (<b2kPlayerDefault>
gives each default). Unknown keys are stored for your own use.

Set them before or after the player exists; a change applies from the next
frame. <b2kClear> keeps them; <b2kTeardown> and <b2kPlayerRemove> reset
them.

References: b2kPlayerGet (handler), b2kPlayerDefault (handler), b2kPlayerTuneCache (handler)
*/
command b2kPlayerSet pKey, pValue
   put pValue into sPlayTune[toLower(pKey)]
   b2kPlayerTuneCache
end b2kPlayerSet

-- Internal: resolve the knobs into flat locals ONCE per change -- the
-- tick reads these every frame and must not pay name lookups for them.
/**
Summary: Copy the tuning knobs into the controller's fast variables.

Example:
b2kPlayerTuneCache

Description:
Internal: <b2kPlayerSet> calls it, so a knob takes effect on the next frame.

References: b2kPlayerSet (handler)
*/
command b2kPlayerTuneCache
   put b2kPlayerGet("moveSpeed") into sPlayMoveSpd
   put b2kPlayerGet("accel") into sPlayAccelG
   put b2kPlayerGet("airAccel") into sPlayAccelA
   put b2kPlayerGet("jumpSpeed") into sPlayJumpSpd
   put b2kPlayerGet("jumpCut") into sPlayJumpCut
   put b2kPlayerGet("coyoteMs") into sPlayCoyote
   put b2kPlayerGet("bufferMs") into sPlayBuffer
   put b2kPlayerGet("maxFall") into sPlayMaxFall
   put b2kPlayerGet("dropMs") into sPlayDropMS
   put b2kPlayerGet("climbSpeed") into sPlayClimbSpd
   put b2kPlayerGet("swimSpeed") into sPlaySwimSpd
   put b2kPlayerGet("swimJump") into sPlaySwimJump
   put b2kPlayerGet("swimGravity") into sPlaySwimGrav
   put b2kPlayerGet("swimMaxFall") into sPlaySwimMaxFall
   put b2kPlayerGet("hurtPopX") into sPlayHurtPopX
   put b2kPlayerGet("hurtPopY") into sPlayHurtPopY
   put b2kPlayerGet("hurtMs") into sPlayHurtMS
   put b2kPlayerGet("invulnMs") into sPlayInvulnMS
   -- Wave 5 knob caches + the one-compare gates the tick reads
   put b2kPlayerGet("airJumps") into sPlayAirJumps
   put b2kPlayerGet("wallJumpX") into sPlayWallJumpX
   put b2kPlayerGet("wallJumpY") into sPlayWallJumpY
   put b2kPlayerGet("wallSlideMax") into sPlayWallSlideMax
   put (sPlayWallJumpX > 0 or sPlayWallSlideMax > 0) into sPlayWallOn
   put b2kPlayerGet("dashSpeed") into sPlayDashSpd
   put b2kPlayerGet("dashMs") into sPlayDashMS
   put b2kPlayerGet("dashCooldownMs") into sPlayDashCool
   put (b2kPlayerGet("airDash") is not 0) into sPlayAirDash
   put b2kPlayerGet("duckScale") into sPlayDuckScale
   put (b2kPlayerGet("platformCarry") is not 0) into sPlayCarry
   put cos(b2kPlayerGet("maxSlopeDeg") * kPI / 180) into sPlayCosSlope
   if sPlayHalfW is not empty and sPlayHalfW > 0 then
      put sPlayHalfH + 4 into sPlayReach
      put (0 - max(2, sPlayHalfW * 0.6)) & comma & 0 & comma & max(2, sPlayHalfW * 0.6) into sPlayProbeOffs
   end if
end b2kPlayerTuneCache

/**
Summary: Read a player tuning knob.

pKey: The knob's name (case does not matter).

Returns: The knob's value, or its default when unset. A known knob set to a non-number reads as its default.

Example:
put b2kPlayerGet("jumpSpeed") into tJump

References: b2kPlayerSet (handler), b2kPlayerDefault (handler)
*/
function b2kPlayerGet pKey
   local tDef
   put toLower(pKey) into pKey
   put b2kPlayerDefault(pKey) into tDef
   if sPlayTune[pKey] is empty then return tDef
   -- known keys are numeric: a garbage value must not break the tick
   if tDef is not empty then return b2kNumberOr(sPlayTune[pKey], tDef)
   return sPlayTune[pKey]
end b2kPlayerGet

-- Internal: the defaults (spec section 6 -- a 32x48 px player, scale 40).
/**
Summary: The shipped default of a player tuning knob.

pKey: The knob's name in lower case, such as "jumpspeed".

Returns: The default value, or empty for a knob the controller does not know.

Example:
put b2kPlayerDefault("jumpspeed") into tStock

Description:
The defaults suit a 32 by 48 px player at scale 40: moveSpeed 220,
jumpSpeed 460, maxFall 900, and so on. The opt-in actions default to off.
<b2kPlayerGet> lower-cases its key for you; this does not.

References: b2kPlayerGet (handler), b2kPlayerSet (handler)
*/
function b2kPlayerDefault pKey
   switch pKey
      case "movespeed"
         return 220
      case "accel"
         return 1800
      case "airaccel"
         return 1100
      case "jumpspeed"
         return 460
      case "jumpcut"
         return 0.45
      case "coyotems"
         return 90
      case "bufferms"
         return 110
      case "maxfall"
         return 900
      case "maxslopedeg"
         return 50
      case "dropms"
         return 260
      case "climbspeed"
         return 160
      case "swimspeed"
         return 150
      case "swimjump"
         return 300
      case "swimgravity"
         return 0.35
      case "swimmaxfall"
         return 150
      case "hurtpopx"
         return 220
      case "hurtpopy"
         return 320
      case "hurtms"
         return 700
      case "invulnms"
         return 900
      -- Wave 5 (all OPT-IN: these defaults disable the feature, so an
      -- untouched controller behaves exactly as it did before Wave 5)
      case "airjumps"
         return 0          -- extra mid-air jumps (1 = double-jump)
      case "walljumpx"
         return 0          -- away-from-wall launch px/s (0 = wall system off)
      case "walljumpy"
         return 0          -- up launch off a wall (0 = fall back to jumpSpeed)
      case "wallslidemax"
         return 0          -- capped fall px/s while hugging a wall (0 = no slide)
      case "dashspeed"
         return 0          -- dash px/s (0 = dash off)
      case "dashms"
         return 160        -- dash duration
      case "dashcooldownms"
         return 500        -- minimum gap between dashes
      case "airdash"
         return 1          -- 1 = dash works mid-air too; 0 = dash only when grounded
      case "duckscale"
         return 1          -- ducked capsule height / standing height (1 = no reshape)
      case "platformcarry"
         return 0          -- 1 = inherit a moving platform's velocity (opt-in: it
                           -- costs 2 reads/grounded-frame and changes how a player
                           -- rides any kinematic body), 0 = off
   end switch
   return empty
end b2kPlayerDefault

-- Map the controller's states to the art's animations (empty leaves that
-- state alone; pFall defaults to pJump). pLand is an optional non-looping
-- touch-down flourish: the controller holds it for its own duration, then
-- idle/run resume. NOTE: a finishing land animation dispatches the art's
-- b2kSpriteOnFinish message like any non-looping animation would.
-- Wave 2 slots (all optional, so old five-argument calls keep working):
-- pDuck falls back to the idle pose, pClimb and pHurt to the jump pose;
-- the Wave 4 pSwim falls back to the fall pose -- sheets without those
-- frames still read correctly. Wave 5 slots: pWall (wall-slide) falls back
-- to the fall pose, pDash falls back to the run pose.
/**
Summary: Map the controller's states to the art's animation names.

pIdle: Animation for standing still.

pRun: Animation for running.

pJump: Animation for rising.

pFall: Optional animation for falling. Empty uses the jump animation.

pLand: Optional one-shot touch-down animation, held for its own length.

pDuck: Optional crouch animation. Empty uses idle.

pClimb: Optional ladder animation. Empty uses jump.

pHurt: Optional knockback animation. Empty uses jump.

pSwim: Optional swim animation. Empty uses the fall animation.

pWall: Optional wall-slide animation. Empty uses the fall animation.

pDash: Optional dash animation. Empty uses run.

Example:
b2kPlayerAnims "idle", "walk", "jump", "fall", "land"

Description:
The controller then plays these on the player's art and flips it to
face the way it moves. If your game uses <b2kSpriteOnFinish> on the player's
art, map a looping animation to hurt: a one-shot hurt pose fires the finish
message mid-knockback.

References: b2kPlayerState (handler), b2kAnimDef (handler), b2kPlayerSprite (handler)
*/
command b2kPlayerAnims pIdle, pRun, pJump, pFall, pLand, pDuck, pClimb, pHurt, pSwim, pWall, pDash
   put pIdle into sPlayAnims["idle"]
   put pRun into sPlayAnims["run"]
   put pJump into sPlayAnims["jump"]
   if pFall is empty then
      put pJump into sPlayAnims["fall"]
   else
      put pFall into sPlayAnims["fall"]
   end if
   put pLand into sPlayAnims["land"]
   if pDuck is empty then
      put pIdle into sPlayAnims["duck"]
   else
      put pDuck into sPlayAnims["duck"]
   end if
   if pClimb is empty then
      put pJump into sPlayAnims["climb"]
   else
      put pClimb into sPlayAnims["climb"]
   end if
   if pHurt is empty then
      put pJump into sPlayAnims["hurt"]
   else
      put pHurt into sPlayAnims["hurt"]
   end if
   if pSwim is empty then
      put sPlayAnims["fall"] into sPlayAnims["swim"]
   else
      put pSwim into sPlayAnims["swim"]
   end if
   if pWall is empty then
      put sPlayAnims["fall"] into sPlayAnims["wallslide"]
   else
      put pWall into sPlayAnims["wallslide"]
   end if
   if pDash is empty then
      put sPlayAnims["run"] into sPlayAnims["dash"]
   else
      put pDash into sPlayAnims["dash"]
   end if
   put empty into sPlayAnimNow   -- re-assert on the next tick
   if sPlayArt is empty then b2kPlayerResolveArt
end b2kPlayerAnims

/**
Summary: The player control.

Returns: The player's long id, or empty when there is no player.

Example:
put b2kPlayer() into tHero

References: b2kPlayerSprite (handler), b2kPlayerMake (handler)
*/
function b2kPlayer
   return sPlayRef
end b2kPlayer

-- The art control the controller animates (empty = none resolved yet).
/**
Summary: The control the controller animates.

Returns: The art control, or empty when none is found.

Example:
put b2kPlayerSprite() into tArt

References: b2kPlayer (handler), b2kPlayerResolveArt (handler)
*/
function b2kPlayerSprite
   return sPlayArt
end b2kPlayerSprite

-- Grounded this frame (post-tick; false on the frame a jump launches).
/**
Summary: Report whether the player is grounded this frame.

Returns: true or false; false on the frame a jump launches.

Example:
if b2kPlayerOnGround() then put 0 into tAirTime

References: b2kPlayerState (handler)
*/
function b2kPlayerOnGround
   return (sPlayGrounded is true)
end b2kPlayerOnGround

-- idle | run | jump | fall | duck | climb | hurt | swim | wallslide | dash,
-- plus "land" for exactly one frame on touch-down from jump/fall (dust
-- puffs, landing sounds). A drop-through renders as "fall". The Wave 5
-- states (wallslide, dash) only appear when their knobs are enabled.
-- Empty = no player.
/**
Summary: The player's current state.

Returns: idle, run, jump, fall, duck, climb, hurt, swim, wallslide or dash, or land for one frame on touch-down; empty when there is no player.

Example:
if b2kPlayerState() is "land" then b2kSound "land"

Description:
Read it from b2kFrame. A drop-through reads as fall. The wallslide
and dash states appear only when their knobs are on.

References: b2kPlayerOnGround (handler), b2kPlayerAnims (handler)
*/
function b2kPlayerState
   return sPlayState
end b2kPlayerState

/**
Summary: Which way the player faces.

Returns: 1 for right, -1 for left (the last horizontal input).

Example:
b2kSpawnBall item 1 of b2kPosition(b2kPlayer()) + 30 * b2kPlayerFacing(), 100, 12

References: b2kPlayerState (handler)
*/
function b2kPlayerFacing
   if sPlayFacing is -1 then return -1
   return 1
end b2kPlayerFacing

-- The capsule's CURRENT half-extents in px (the half-height drops while
-- the player is in a reshaped duck/crawl). Head-reach logic should read
-- these live rather than bake a constant (gotcha 28: a hitbox taller than
-- the visible art bumps things the head never touches).
/**
Summary: The player capsule's current half-height.

Returns: Pixels, or 0 when there is no player.

Example:
put item 2 of b2kPosition(b2kPlayer()) - b2kPlayerHalfH() into tHeadY

Description:
It shrinks during a reshaped crawl, so read it live rather than using a constant.

References: b2kPlayerHalfW (handler)
*/
function b2kPlayerHalfH
   return b2kNumberOr(sPlayHalfH, 0)
end b2kPlayerHalfH

/**
Summary: The player capsule's half-width.

Returns: Pixels, or 0 when there is no player.

Example:
put b2kPlayerHalfW() into tHalfW

References: b2kPlayerHalfH (handler)
*/
function b2kPlayerHalfW
   return b2kNumberOr(sPlayHalfW, 0)
end b2kPlayerHalfW

-- This frame's ladder / water zone membership (the controller computes
-- these every tick anyway -- read them for "press UP to climb" prompts,
-- splash effects, breath meters, without recomputing the rects yourself).
/**
Summary: Report whether the player is inside a ladder zone this frame.

Returns: true or false.

Example:
if b2kPlayerInLadder() then show field "ClimbHint"

References: b2kPlayerAddLadder (handler), b2kPlayerInWater (handler)
*/
function b2kPlayerInLadder
   return (sPlayInLad is true)
end b2kPlayerInLadder

/**
Summary: Report whether the player is inside a water zone this frame.

Returns: true or false.

Example:
if b2kPlayerInWater() then subtract b2kFrameMS() from tBreath

References: b2kPlayerAddWater (handler), b2kPlayerInLadder (handler)
*/
function b2kPlayerInWater
   return (sPlayInWat is true)
end b2kPlayerInWater

-- Programmatic jump (springs, double-jump powerups): the same launch as a
-- pressed jump but WITHOUT the grounded/coyote gate -- the caller decides
-- when it is allowed. Uses the jumpSpeed knob unless given a speed.
/**
Summary: Make the player jump, with no ground check.

pSpeed: The launch speed in px/s. Empty means the jumpSpeed knob.

Example:
b2kPlayerJump 700

Description:
The same launch as a pressed jump, for springs and power-ups; the
caller decides when it is allowed. Use it for every upward boost: a raw
upward velocity on a grounded player is treated as a rebound and snapped
away.

References: b2kPlayerSet (handler), b2kPlayerOnGround (handler)
*/
command b2kPlayerJump pSpeed
   local tVel
   if sPlayRef is empty or sBody[sPlayRef] is empty then exit b2kPlayerJump
   if pSpeed is empty then put b2kPlayerGet("jumpSpeed") into pSpeed
   set the itemDelimiter to comma
   put b2kVelocity(sPlayRef) into tVel
   b2kSetVelocity sPlayRef, item 1 of tVel, 0 - pSpeed
   put true into sPlayJumping
   put 0 into sPlayGroundMS   -- consume coyote: no free second jump
   put 0 into sPlayPressMS    -- ...and any buffered press
end b2kPlayerJump

-- Register a ladder ZONE (screen-px rect, any corner order). While the
-- player's centre is inside one, UP enters the climb state (DOWN too,
-- when airborne -- walk off a platform and grab); gravity parks at 0,
-- y runs at climbSpeed off the moveY axis (0 = hang), x at half speed.
-- JUMP exits with a normal jump; leaving the zone (or climbing down
-- onto ground) restores gravity. Zones are pure polled geometry -- no
-- physics objects -- and are WORLD state: b2kClear wipes them.
-- TIP: run the zone a little above a platform at the ladder's top, so
-- walking off that edge while holding DOWN grabs the ladder.
/**
Summary: Register a ladder zone.

pX1: One corner's x, in pixels.

pY1: One corner's y, in pixels.

pX2: The other corner's x, in pixels.

pY2: The other corner's y, in pixels.

Example:
b2kPlayerAddLadder 600, 180, 640, 420

Description:
While the player's centre is inside, UP starts a climb (DOWN too
when airborne): gravity stops, y moves at climbSpeed and x at half speed,
and JUMP leaves with a normal jump. Zones are plain rectangles with no
physics; <b2kClear> removes them. Start the zone a little above the
platform at the ladder's top. Corners that are not numbers are ignored.

References: b2kPlayerInLadder (handler), b2kPlayerAddWater (handler)
*/
command b2kPlayerAddLadder pX1, pY1, pX2, pY2
   if pX1 is not a number or pY1 is not a number \
         or pX2 is not a number or pY2 is not a number then exit b2kPlayerAddLadder
   if sPlayLadN is empty then put 0 into sPlayLadN
   add 1 to sPlayLadN
   put min(pX1, pX2) into sPlayLadL[sPlayLadN]
   put max(pX1, pX2) into sPlayLadR[sPlayLadN]
   put min(pY1, pY2) into sPlayLadT[sPlayLadN]
   put max(pY1, pY2) into sPlayLadB[sPlayLadN]
end b2kPlayerAddLadder

-- Register a water ZONE (screen-px rect, any corner order). While the
-- player's centre is inside one, the controller SWIMS: gravity drops to
-- swimGravity (buoyant), the sink caps at swimMaxFall, UP/DOWN swim at
-- swimSpeed, and JUMP is a repeatable upward STROKE (swimJump) -- no
-- ground needed. Leaving the zone restores gravity. Pure polled geometry,
-- WORLD state (b2kClear wipes them), exactly like the ladder zones.
-- TIP: top the zone a little ABOVE the water's surface tiles, so the dive
-- in and the surface-out break the water where the surface art sits.
/**
Summary: Register a water (swim) zone.

pX1: One corner's x, in pixels.

pY1: One corner's y, in pixels.

pX2: The other corner's x, in pixels.

pY2: The other corner's y, in pixels.

Example:
b2kPlayerAddWater 900, 300, 1200, 460

Description:
While the player's centre is inside, it swims: gravity drops to
swimGravity, sinking is capped at swimMaxFall, UP and DOWN move at swimSpeed,
and each JUMP press is an upward stroke. Zones have no physics; <b2kClear>
removes them. Top the zone a little above the drawn water surface.

References: b2kPlayerInWater (handler), b2kPlayerAddLadder (handler)
*/
command b2kPlayerAddWater pX1, pY1, pX2, pY2
   if pX1 is not a number or pY1 is not a number \
         or pX2 is not a number or pY2 is not a number then exit b2kPlayerAddWater
   if sPlayWatN is empty then put 0 into sPlayWatN
   add 1 to sPlayWatN
   put min(pX1, pX2) into sPlayWatL[sPlayWatN]
   put max(pX1, pX2) into sPlayWatR[sPlayWatN]
   put min(pY1, pY2) into sPlayWatT[sPlayWatN]
   put max(pY1, pY2) into sPlayWatB[sPlayWatN]
end b2kPlayerAddWater

-- The knockback standard (spec section 9.4): control off, an away-pop
-- (the sign of pFromX vs the player picks the direction; no/empty
-- pFromX pops away from the facing), the hurt anim, control restored
-- after hurtMs OR the first landing after half of it -- whichever is
-- LATER -- then an invulnMs mercy window during which this command
-- no-ops and b2kPlayerHurtIs() stays true (skip your hazard checks).
-- Games keep their respawn flow for LETHAL hits (pits, kill planes):
-- contact damage knocks back, falling dies -- the Wave 2 split.
/**
Summary: Knock the player back from a hit.

pFromX: The x the hit came from; the player pops away from it. Empty pops backward from the facing.

Example:
if not b2kPlayerHurtIs() then b2kPlayerHurt item 1 of b2kPosition(tSlime)

Description:
The contact-damage standard: an away pop (hurtPopX, hurtPopY), the
hurt state, input ignored until hurtMs has passed or the first landing after
half of it, whichever is later, then an invulnMs mercy window in which
this command does nothing. Ignored while control is off. Keep your respawn flow
for lethal falls.

References: b2kPlayerHurtIs (handler), b2kPlayerControl (handler), b2kPlayerRespawn (handler)
*/
command b2kPlayerHurt pFromX
   local tDir
   if sPlayRef is empty or sBody[sPlayRef] is empty then exit b2kPlayerHurt
   if b2kPlayerHurtIs() then exit b2kPlayerHurt          -- mercy window
   if sPlayControl is not true then exit b2kPlayerHurt   -- a cutscene owns the body
   if sPlayClimb is true then b2kPlayerClimbEnd sBody[sPlayRef]
   if sPlaySwim is true then b2kPlayerSwimEnd sBody[sPlayRef]
   if sPlayDash is true then b2kPlayerDashEnd sBody[sPlayRef]
   if pFromX is a number then
      if pFromX > sPlayPX then
         put -1 into tDir
      else
         put 1 into tDir
      end if
   else
      put 0 - sPlayFacing into tDir   -- pop back off whatever was ahead
   end if
   -- the pop rides the jump flag, like b2kPlayerJump: a raw upward
   -- set-velocity on a grounded player reads as solver rebound and gets
   -- ground-snapped to zero (gotcha 16)
   b2kSetVelocity sPlayRef, tDir * sPlayHurtPopX, 0 - sPlayHurtPopY
   put true into sPlayJumping
   put true into sPlayHurt
   put 0 into sPlayHurtLand
   put sPlayClock + sPlayHurtMS into sPlayHurtEnd
   put sPlayClock + sPlayHurtMS / 2 into sPlayHurtHalf
   put false into sPlayGrounded
   put 0 into sPlayGroundMS   -- no coyote freebie off a knockback
   put 0 into sPlayPressMS
   put "hurt" into sPlayState
   put empty into sPlayAnimNow   -- assert the hurt anim this tick
end b2kPlayerHurt

-- True through the knockback AND the mercy window that follows it: the
-- one gate a game's hazard checks need (poll it before calling
-- b2kPlayerHurt -- though a hurt inside the window already no-ops).
/**
Summary: Report whether the player is in knockback or its mercy window.

Returns: true or false.

Example:
if b2kPlayerHurtIs() then put true into tSkipHazards

References: b2kPlayerHurt (handler)
*/
function b2kPlayerHurtIs
   if sPlayHurt is true then return true
   if sPlayInvulnUntil is not empty and sPlayInvulnUntil > 0 and sPlayClock < sPlayInvulnUntil then return true
   return false
end b2kPlayerHurtIs

-- false = the controller only OBSERVES: ground/state/facing stay fresh
-- but it writes neither velocity nor animations (the maxFall clamp stays
-- live -- it is the character's terminal velocity). For cutscenes,
-- hit poses, scripted deaths; physics and the Kit run on.
/**
Summary: Give the controller control of the player, or make it only observe.

pFlag: false to observe only; anything else gives control back.

Example:
b2kPlayerControl false

Description:
While observing, ground, state and facing stay fresh but the
controller writes no velocity and no animation (the maxFall limit still
applies); use it for cutscenes and scripted poses. Either call cancels a
knockback in progress with no mercy window. Giving control back re-applies
the state's animation.

References: b2kPlayerHurt (handler), b2kPlayerRespawn (handler)
*/
command b2kPlayerControl pFlag
   put (pFlag is not false) into sPlayControl
   -- an EXPLICIT control call overrides a knockback in flight: the game
   -- is taking the body (cutscene, respawn). No mercy window is granted
   -- -- the game owns what happens next.
   if sPlayHurt is true then
      put false into sPlayHurt
      put 0 into sPlayHurtLand
   end if
   -- a dash parks gravity at 0 and is ended only by its own tick, which
   -- stops running when control goes off -- so end it here or the parked
   -- gravity (and the held vy) leak into the cutscene.
   if sPlayControl is not true and sPlayDash is true \
         and sPlayRef is not empty and sBody[sPlayRef] is not empty then
      b2kPlayerDashEnd sBody[sPlayRef]
   end if
   -- returning control must re-assert the state anim over any manual pose
   if sPlayControl then put empty into sPlayAnimNow
end b2kPlayerControl

-- Teleport the player to a screen-px point and reset it to a clean
-- standing idle: velocity zeroed; the jump/hurt/dash/climb/swim/drop/duck
-- state cleared; the air and air-jump budgets refreshed. This is the
-- respawn most games hand-roll (b2kMoveTo + b2kSetVelocity + clearing a
-- pile of flags) in one call. Tuning and zones are kept (world/config
-- state). Empty pX/pY reuse the current centre (an in-place reset).
/**
Summary: Teleport the player and reset it to a clean standing idle.

pX: The new centre x in pixels. Not a number keeps the current x.

pY: The new centre y in pixels. Not a number keeps the current y.

Example:
b2kPlayerRespawn 120, 300

Description:
Velocity is zeroed; jump, hurt, dash, climb, swim, drop and duck
states are cleared; the air-jump budget is refilled and control is on.
Tuning and zones are kept.

References: b2kPlayerHurt (handler), b2kMoveTo (handler)
*/
command b2kPlayerRespawn pX, pY
   local tB
   if sPlayRef is empty or sBody[sPlayRef] is empty then exit b2kPlayerRespawn
   put sBody[sPlayRef] into tB
   if sPlayClimb is true then b2kPlayerClimbEnd tB
   if sPlaySwim is true then b2kPlayerSwimEnd tB
   if sPlayDash is true then b2kPlayerDashEnd tB
   if sPlayDropUntil is not empty and sPlayDropUntil > 0 then b2kPlayerDropRestore
   if sPlayDucked is true then b2kPlayerStandUp
   put b2kNumberOr(pX, sPlayPX) into pX
   put b2kNumberOr(pY, sPlayPY) into pY
   b2kMoveTo sPlayRef, pX, pY
   b2kSetVelocity sPlayRef, 0, 0
   put true into sPlayControl
   put false into sPlayJumping
   put false into sPlayHurt
   put 0 into sPlayHurtLand
   put 0 into sPlayInvulnUntil
   put false into sPlayGrounded
   put 0 into sPlayAir
   put 0 into sPlayWallLockUntil
   put false into sPlayWallSliding
   put sPlayAirJumps into sPlayAirJumpsLeft
   put "idle" into sPlayState
   put empty into sPlayAnimNow   -- re-assert the idle pose next tick
end b2kPlayerRespawn

-- Tear down the controller, tuning included. The body and sprite remain
-- yours: remove them with b2kRemove / b2kSpriteRemove as usual.
/**
Summary: Remove the player controller.

Example:
b2kPlayerRemove
b2kRemove tHero

Description:
The controller's state and tuning go. The body and sprite stay;
remove them with <b2kRemove> and <b2kSpriteRemove>.

References: b2kPlayerAttach (handler), b2kPlayerForget (handler)
*/
command b2kPlayerRemove
   b2kPlayerForget true
end b2kPlayerRemove

-- Internal: drop controller state. b2kClear passes false (tuning is
-- config and survives, like input bindings); teardown/remove pass true.
-- Ladder zones are WORLD state, so they go either way; a mid-climb or
-- mid-drop body gets its gravity scale and collision mask back first.
/**
Summary: Drop the controller's state.

pFull: true to drop the tuning knobs too.

Example:
b2kPlayerForget false

Description:
Internal: <b2kClear> passes false and <b2kTeardown> and
<b2kPlayerRemove> pass true. A climb, swim, dash or drop in progress is ended
first so the body gets its gravity and mask back. Ladder and water zones go
either way.

References: b2kPlayerRemove (handler), b2kClear (handler)
*/
command b2kPlayerForget pFull
   if sPlayClimb is true and sPlayRef is not empty and sBody[sPlayRef] is not empty then
      b2kPlayerClimbEnd sBody[sPlayRef]
   end if
   if sPlaySwim is true and sPlayRef is not empty and sBody[sPlayRef] is not empty then
      b2kPlayerSwimEnd sBody[sPlayRef]
   end if
   if sPlayDash is true and sPlayRef is not empty and sBody[sPlayRef] is not empty then
      b2kPlayerDashEnd sBody[sPlayRef]
   end if
   if sPlayDropUntil is not empty and sPlayDropUntil > 0 then b2kPlayerDropRestore
   put empty into sPlayRef
   put empty into sPlayArt
   put empty into sPlayAnims
   put empty into sPlayState
   put false into sPlayGrounded
   put false into sPlayJumping
   put true into sPlayControl
   put 1 into sPlayFacing
   put 0 into sPlayGroundMS
   put 0 into sPlayPressMS
   put 0 into sPlayHoldMS
   put 0 into sPlayClock
   put 0 into sPlayAir
   put empty into sPlayAnimNow
   put empty into sPlayFlipNow
   put false into sPlayOnOneWay
   put 0 into sPlayDropUntil
   put 0 into sPlayDropHard
   put empty into sPlayDropMask
   put false into sPlayClimb
   put empty into sPlayGravSave
   put false into sPlaySwim
   put empty into sPlaySwimGravSave
   put false into sPlayHurt
   put 0 into sPlayHurtEnd
   put 0 into sPlayHurtHalf
   put 0 into sPlayHurtLand
   put 0 into sPlayInvulnUntil
   -- Wave 5 state (the body keeps any reshaped duck size -- it is yours
   -- now; b2kClear removes it, teardown removes everything)
   put 0 into sPlayAirJumpsLeft
   put 0 into sPlayWall
   put false into sPlayWallSliding
   put 0 into sPlayWallLockUntil
   put false into sPlayDash
   put 0 into sPlayDashEnd
   put 0 into sPlayDashReady
   put 0 into sPlayDashDir
   put empty into sPlayDashGravSave
   put false into sPlayDucked
   put empty into sPlayGroundBody
   put false into sPlayInLad
   put false into sPlayInWat
   put 0 into sPlayLadN
   put empty into sPlayLadL
   put empty into sPlayLadT
   put empty into sPlayLadR
   put empty into sPlayLadB
   put 0 into sPlayWatN
   put empty into sPlayWatL
   put empty into sPlayWatT
   put empty into sPlayWatR
   put empty into sPlayWatB
   if pFull is true then put empty into sPlayTune
end b2kPlayerForget

-- Internal: 3 short rays cast down from the capsule's bottom; ground is
-- any hit whose surface normal points up within maxSlopeDeg. The rays
-- start inside our own capsule, which Box2D structurally never reports
-- (Phase 0, S7) -- self-hits are impossible. Sets the grounded flag and
-- refreshes the coyote clock. While OUR jump is still ascending the
-- probe is skipped outright: it would otherwise re-ground on the launch
-- frame and report phantom landings while rising THROUGH a one-way
-- chain (the bridge route). Plain upward motion is NOT skipped -- running
-- up a slope moves the capsule upward while genuinely grounded.
/**
Summary: Run the controller's ground probe.

pBody: The player's raw body handle, b2kBodyOf(b2kPlayer()).

pVY: The body's vertical velocity in px/s, screen oriented (negative is rising).

Example:
b2kPlayerProbe b2kBodyOf(b2kPlayer()), 0

Description:
Internal: three short rays down from the capsule decide whether the
player is grounded (a surface whose normal points up within maxSlopeDeg).
Skipped while the controller's own jump is still rising.

References: b2kPlayerOnGround (handler), b2kPlayerTick (handler)
*/
command b2kPlayerProbe pBody, pVY
   local tX, tY, tOff
   put false into sPlayGrounded
   put false into sPlayOnOneWay
   put false into sPlayDropSeen
   put empty into sPlayGroundBody
   set the itemDelimiter to comma
   -- raw reads with the caller's body handle: the probe runs every
   -- frame, so it skips the ref->body lookup and the "x,y" string pack.
   -- The centre is stashed even when the rays are skipped -- the tick's
   -- ladder zone test and b2kPlayerHurt read it.
   put b2kToScreenX(b2BodyX(pBody)) into tX
   put b2kToScreenY(b2BodyY(pBody)) into tY
   put tX into sPlayPX
   put tY into sPlayPY
   if sPlayJumping is true and pVY < 0 then exit b2kPlayerProbe
   repeat for each item tOff in sPlayProbeOffs
      get b2kRayHit(tX + tOff, tY, tX + tOff, tY + sPlayReach)
      if sRayNY is not empty and sRayNY <= 0 - sPlayCosSlope then
         if sOneWayBody[sRayBodyH] is true then
            -- mid-drop, a one-way chain is NOT ground (or the controller
            -- would re-ground on the very platform it is leaving -- the
            -- phantom-ground lesson in reverse); remember the sighting:
            -- the window's restore logic waits for the capsule to clear
            if sPlayDropUntil > 0 then
               put true into sPlayDropSeen
               next repeat
            end if
            put true into sPlayOnOneWay   -- standing on a chain: drop eligible
         end if
         put true into sPlayGrounded
         put sRayBodyH into sPlayGroundBody  -- the platform under us (carry)
         put sRayNX into sPlayNormX          -- flat vs slope, for ground-snap
         put sPlayClock into sPlayGroundMS   -- the sim clock, not wall time
         exit b2kPlayerProbe
      end if
   end repeat
end b2kPlayerProbe

-- Internal: enter the climb -- gravity parks at 0 (the body's own scale
-- is saved and restored, so a game-tuned floatiness survives a ladder).
/**
Summary: Start the climb's gravity hold.

pBody: The player's raw body handle, b2kBodyOf(b2kPlayer()).

Example:
b2kPlayerClimbStart b2kBodyOf(b2kPlayer())

Description:
Internal: saves the body's gravity scale and sets it to 0. A repeated start is a no-op.

References: b2kPlayerClimbEnd (handler)
*/
command b2kPlayerClimbStart pBody
   if sPlayClimb is true then exit b2kPlayerClimbStart
   put b2BodyGravityScale(pBody) into sPlayGravSave
   b2SetGravityScale pBody, 0
   put true into sPlayClimb
   put false into sPlayJumping
end b2kPlayerClimbStart

/**
Summary: End the climb's gravity hold.

pBody: The player's raw body handle, b2kBodyOf(b2kPlayer()).

Example:
b2kPlayerClimbEnd b2kBodyOf(b2kPlayer())

Description:
Internal: restores the saved gravity scale. Without a start it is a no-op.

References: b2kPlayerClimbStart (handler)
*/
command b2kPlayerClimbEnd pBody
   if sPlayClimb is not true then exit b2kPlayerClimbEnd
   b2SetGravityScale pBody, b2kNumberOr(sPlayGravSave, 1)
   put empty into sPlayGravSave
   put false into sPlayClimb
end b2kPlayerClimbEnd

-- Internal: enter the swim -- gravity drops to swimGravity (buoyant; the
-- body's own scale is saved and restored, like the climb). Mutually
-- exclusive with the climb: the tick only ever starts one of them.
/**
Summary: Start the swim's buoyancy.

pBody: The player's raw body handle, b2kBodyOf(b2kPlayer()).

Example:
b2kPlayerSwimStart b2kBodyOf(b2kPlayer())

Description:
Internal: saves the body's gravity scale and sets it to swimGravity. A repeated start is a no-op.

References: b2kPlayerSwimEnd (handler)
*/
command b2kPlayerSwimStart pBody
   if sPlaySwim is true then exit b2kPlayerSwimStart
   put b2BodyGravityScale(pBody) into sPlaySwimGravSave
   b2SetGravityScale pBody, b2kNumberOr(sPlaySwimGrav, 0.35)
   put true into sPlaySwim
   put false into sPlayJumping
end b2kPlayerSwimStart

/**
Summary: End the swim's buoyancy.

pBody: The player's raw body handle, b2kBodyOf(b2kPlayer()).

Example:
b2kPlayerSwimEnd b2kBodyOf(b2kPlayer())

Description:
Internal: restores the saved gravity scale. Without a start it is a no-op.

References: b2kPlayerSwimStart (handler)
*/
command b2kPlayerSwimEnd pBody
   if sPlaySwim is not true then exit b2kPlayerSwimEnd
   b2SetGravityScale pBody, b2kNumberOr(sPlaySwimGravSave, 1)
   put empty into sPlaySwimGravSave
   put false into sPlaySwim
end b2kPlayerSwimEnd

-- Internal: open the drop-through window -- take the reserved one-way
-- bit out of the player's mask so chains (alone) stop colliding.
/**
Summary: Open the drop-through window.

Example:
b2kPlayerDropStart

Description:
Internal: takes the reserved one-way bit (2^31) out of the player's
collision mask, so one-way chains alone stop colliding, for dropMs.

References: b2kPlayerDropRestore (handler), b2kChain (handler)
*/
command b2kPlayerDropStart
   local tS, tM
   put sShapeH[sPlayRef] into tS
   if tS is empty then exit b2kPlayerDropStart
   put b2ShapeFilterMask(tS) into tM
   -- Box2D's default mask reads back as 2^64-1, which neither xTalk's
   -- 32-bit bit ops nor the shim's 2^53 guard can round-trip: clamp to
   -- "all 32 kit bits" -- identical behaviour, every category this Kit
   -- can mint lives below 2^32
   if tM > 4294967295 then put 4294967295 into tM
   put tM into sPlayDropMask
   b2SetShapeFilter tS, b2ShapeFilterCategory(tS), tM bitAnd (bitNot 2147483648), b2ShapeFilterGroup(tS)
   put sPlayClock + sPlayDropMS into sPlayDropUntil
   put sPlayClock + sPlayDropMS * 4 into sPlayDropHard
   put sRayY into sPlayDropLineY   -- the grounding ray's hit = the surface line
end b2kPlayerDropStart

/**
Summary: Close the drop-through window.

Example:
b2kPlayerDropRestore

Description:
Internal: puts back the mask <b2kPlayerDropStart> saved.

References: b2kPlayerDropStart (handler)
*/
command b2kPlayerDropRestore
   local tS
   put 0 into sPlayDropUntil
   put 0 into sPlayDropHard
   put sShapeH[sPlayRef] into tS
   if tS is empty or sPlayDropMask is empty then exit b2kPlayerDropRestore
   b2SetShapeFilter tS, b2ShapeFilterCategory(tS), sPlayDropMask, b2ShapeFilterGroup(tS)
   put empty into sPlayDropMask
end b2kPlayerDropRestore

-- Internal (Wave 5): enter the dash -- gravity parks at 0 (saved/restored
-- like the climb) so the burst is a flat horizontal zip; the tick holds vx
-- at dashSpeed for dashMs, then b2kPlayerDashEnd restores gravity. The
-- cooldown (dashReady) gates the next start.
/**
Summary: Start a dash.

pBody: The player's raw body handle, b2kBodyOf(b2kPlayer()).

Example:
b2kPlayerDashStart b2kBodyOf(b2kPlayer())

Description:
Internal: saves the gravity scale and sets it to 0, and starts the
dash timer and cooldown in the facing direction. A repeated start is a no-op.

References: b2kPlayerDashEnd (handler)
*/
command b2kPlayerDashStart pBody
   if sPlayDash is true then exit b2kPlayerDashStart
   put b2BodyGravityScale(pBody) into sPlayDashGravSave
   b2SetGravityScale pBody, 0
   put true into sPlayDash
   put sPlayFacing into sPlayDashDir
   put sPlayClock + sPlayDashMS into sPlayDashEnd
   put sPlayClock + sPlayDashMS + sPlayDashCool into sPlayDashReady
   put false into sPlayJumping
end b2kPlayerDashStart

/**
Summary: End a dash.

pBody: The player's raw body handle, b2kBodyOf(b2kPlayer()).

Example:
b2kPlayerDashEnd b2kBodyOf(b2kPlayer())

Description:
Internal: restores the saved gravity scale. Without a start it is a no-op.

References: b2kPlayerDashStart (handler)
*/
command b2kPlayerDashEnd pBody
   if sPlayDash is not true then exit b2kPlayerDashEnd
   b2SetGravityScale pBody, b2kNumberOr(sPlayDashGravSave, 1)
   put empty into sPlayDashGravSave
   put false into sPlayDash
end b2kPlayerDashEnd

-- Internal (Wave 5): a single horizontal ray toward the input/facing side.
-- A near-vertical hit within a capsule-width is a wall -> sPlayWall = the
-- side (-1 left, 1 right; 0 = none). Runs only while the wall system is on
-- AND the player is airborne, so the steady-state budget is untouched.
/**
Summary: Look for a wall beside the player.

pBody: The player's raw body handle, b2kBodyOf(b2kPlayer()).

pAxis: The side to look: -1 left, 1 right, 0 the facing.

Example:
b2kPlayerWallProbe b2kBodyOf(b2kPlayer()), 1

Description:
Internal: one sideways ray for the wall-slide and wall-jump system. Its result has no public reader.

References: b2kPlayerTick (handler)
*/
command b2kPlayerWallProbe pBody, pAxis
   local tDir
   put 0 into sPlayWall
   if pAxis is 0 then
      put sPlayFacing into tDir
   else
      put pAxis into tDir
   end if
   set the itemDelimiter to comma
   get b2kRayHit(sPlayPX, sPlayPY, sPlayPX + tDir * (sPlayHalfW + 4), sPlayPY)
   if sRayNX is not empty and abs(sRayNX) > 0.7 and abs(sRayNY) < 0.6 then
      put tDir into sPlayWall
   end if
end b2kPlayerWallProbe

-- Internal (Wave 5): enter/leave the reshaped crawl (only when duckScale
-- < 1). Entering shrinks the capsule FEET-ANCHORED (drop the centre by
-- half the height lost so the feet stay planted); standing waits for
-- headroom (a ray up from the crouched top), so a low ceiling keeps you
-- crawling. b2kReshape resets the shape's material AND its collision
-- FILTER (documented contract, kit-guide section 5), so both are captured
-- and re-applied around each rebuild.
--
-- FILTER FIX 2026-08-17: only half of that contract was honoured here.
-- Friction and bounce have been re-set since the crawl shipped; the filter
-- never was, so every duck (and every stand-up) silently returned the
-- player to the default category 1 / collide-with-everything and threw
-- away whatever b2kSetCategory/b2kSetMask/b2kSetCollisionGroup the game
-- had set. Unlike a hand-written b2kReshape call the game gets no chance
-- to re-apply it either -- the duck fires from INSIDE b2kPlayerTick, so
-- there is no hook between the reshape and the next step. The readback is
-- clamped exactly as b2kPlayerDropStart clamps its mask: Box2D's default
-- bits read back as 2^64-1, above the shim's 2^53 double guard, and
-- b2SetShapeFilter would then refuse the whole call SILENTLY (the
-- ghost-layer defect, run 5). A category of 0 means the readback found no
-- shape at all, so the restore is skipped rather than stamping a
-- collides-with-nothing filter onto the new one.
/**
Summary: Shrink the player to a crawl, or stand up when there is room.

pWantDuck: true to crawl; anything else stands up if a ray finds headroom.

Example:
b2kPlayerDuckSet true

Description:
Only active when duckScale is below 1 (the default is 1, a no-op).
The capsule is rebuilt shorter with the feet planted, keeping its collision
filter, with friction 0.08 and no bounce.

References: b2kPlayerStandUp (handler), b2kPlayerHalfH (handler)
*/
command b2kPlayerDuckSet pWantDuck
   local tNewH, tShift, tNeed, tS, tCat, tMask, tGrp
   if sPlayRef is empty then exit b2kPlayerDuckSet
   if pWantDuck is true then
      if sPlayDucked is true or sPlayDuckScale >= 1 then exit b2kPlayerDuckSet
      -- rebuild from the CANONICAL capsule dims, never the drawn rect, and
      -- never a height-set on the control: OXT ignores a height-set on a
      -- polygon graphic (its rect follows its points), so the old "resize
      -- the control, then reshape" rebuilt the capsule at FULL height every
      -- time -- the crawl wedged on the ceiling's face while sPlayHalfH
      -- insisted the pill was short (run 5's instrumented failure). The
      -- drawer re-points the graphic from the new shape, which IS the
      -- polygon's resize mechanism.
      put max(8, round(sPlayCapH * sPlayDuckScale)) into tNewH
      put (sPlayCapH - tNewH) / 2 into tShift
      b2kMoveTo sPlayRef, sPlayPX, sPlayPY + tShift
      -- capture the filter BEFORE the rebuild: b2kReshape destroys the old
      -- shape, and sShapeH[sPlayRef] names a different shape afterwards.
      -- The empty guard is b2kPlayerDropStart's: the raw b2Shape* handlers
      -- take an Integer, so handing one an empty ref is a coercion THROW
      -- from inside the player tick, not a quiet 0.
      put 0 into tCat
      put sShapeH[sPlayRef] into tS
      if tS is not empty then
         put b2ShapeFilterCategory(tS) into tCat
         put b2ShapeFilterMask(tS) into tMask
         put b2ShapeFilterGroup(tS) into tGrp
         if tCat > 4294967295 then put 4294967295 into tCat
         if tMask > 4294967295 then put 4294967295 into tMask
      end if
      b2kReshape sPlayRef, "capsule", sPlayCapW, tNewH
      b2kSetFriction sPlayRef, 0.08
      b2kSetBounce sPlayRef, 0
      put sShapeH[sPlayRef] into tS   -- the reshape minted a NEW shape
      if tCat > 0 and tS is not empty then b2SetShapeFilter tS, tCat, tMask, tGrp
      put tNewH into sPlayDuckH
      put tNewH / 2 into sPlayHalfH
      put true into sPlayDucked
      b2kPlayerTuneCache   -- the probe reach follows the new (shorter) capsule
   else
      if sPlayDucked is not true then exit b2kPlayerDuckSet
      -- headroom from the stored capsule dims (the drawn rect is pen-padded)
      put sPlayCapH - sPlayDuckH into tNeed
      set the itemDelimiter to comma
      get b2kRayHit(sPlayPX, sPlayPY - sPlayHalfH, sPlayPX, sPlayPY - sPlayHalfH - tNeed - 2)
      if sRayNY is not empty then exit b2kPlayerDuckSet   -- a ceiling: stay crawling
      b2kPlayerStandUp
   end if
end b2kPlayerDuckSet

-- Internal (Wave 5): restore the capsule to standing height, feet planted.
-- Used by the duck exit (with headroom) and by b2kPlayerRespawn (forced).
/**
Summary: Restore the player's standing capsule.

Example:
b2kPlayerStandUp

Description:
Internal: stands the player up with no headroom check whenever it is ducked. <b2kPlayerRespawn> uses it.

References: b2kPlayerDuckSet (handler)
*/
command b2kPlayerStandUp
   local tShift, tS, tCat, tMask, tGrp
   if sPlayDucked is not true or sPlayRef is empty then exit b2kPlayerStandUp
   -- mirror of the duck: stored capsule dims in, explicit dims to b2kReshape,
   -- no control resize (inert on a polygon graphic; the drawer re-points it),
   -- and the same material + filter capture/restore around the rebuild (see
   -- b2kPlayerDuckSet's header). This one is reached by b2kPlayerRespawn too,
   -- which is the other path with no hook for the game to re-apply a filter.
   put (sPlayCapH - sPlayDuckH) / 2 into tShift
   b2kMoveTo sPlayRef, sPlayPX, sPlayPY - tShift
   put 0 into tCat
   put sShapeH[sPlayRef] into tS
   if tS is not empty then
      put b2ShapeFilterCategory(tS) into tCat
      put b2ShapeFilterMask(tS) into tMask
      put b2ShapeFilterGroup(tS) into tGrp
      if tCat > 4294967295 then put 4294967295 into tCat
      if tMask > 4294967295 then put 4294967295 into tMask
   end if
   b2kReshape sPlayRef, "capsule", sPlayCapW, sPlayCapH
   b2kSetFriction sPlayRef, 0.08
   b2kSetBounce sPlayRef, 0
   put sShapeH[sPlayRef] into tS   -- the reshape minted a NEW shape
   if tCat > 0 and tS is not empty then b2SetShapeFilter tS, tCat, tMask, tGrp
   put sPlayStandH / 2 into sPlayHalfH
   put false into sPlayDucked
   b2kPlayerTuneCache
end b2kPlayerStandUp

-- Internal: the per-frame controller. Loop order: input -> PLAYER ->
-- sprites -> camera, so it reads this frame's edges and the sprite tick
-- applies the anim it picks. Exits in one compare when unused. The
-- Wave 2 paths (drop window, ladders, hurt) each cost ONE compare per
-- frame while idle -- the tick's steady-state budget is unchanged.
/**
Summary: Run one frame of the player controller.

Example:
b2kPlayerTick

Description:
Internal: the loop and <b2kStepOnce> call it after the input
sample. It probes the ground, applies input, jumping, ladders, water, hurt
and the opt-in actions, and picks the animation. It exits at once when there
is no player.

References: b2kPlayerAttach (handler), b2kStepOnce (handler)
*/
command b2kPlayerTick
   local tNow, tDT, tB, tVX, tVY, tAxis, tAxisY, tTarget, tAcc, tStep
   local tPrevState, tWrite, tInZone, tDuck, tClimbJump, i, tInWater
   local tOnLift, tPVX, tPVY   -- Wave 5: platform-carry scratch
   if sPlayRef is empty then exit b2kPlayerTick
   put sBody[sPlayRef] into tB
   if tB is empty then exit b2kPlayerTick
   -- the controller's clock is SIM time: the coyote/buffer windows must
   -- mean the same number of frames on every machine (and stand still
   -- while paused/hand-stepped) -- wall-clock would not
   put sPlayClock + b2kClamp(sFrameMS, 0, 100) into sPlayClock
   put sPlayClock into tNow
   -- present velocity, screen-oriented px/s (positive vy = falling).
   -- Raw reads with the cached handle: this runs every frame, so skip
   -- the wrapper's ref lookup and "vx,vy" string round-trip (same math
   -- as b2kVelocity -- mind the y flip, gotcha 9).
   set the itemDelimiter to comma
   put b2BodyVX(tB) * sScale into tVX
   put 0 - (b2BodyVY(tB) * sScale) into tVY
   b2kPlayerProbe tB, tVY
   -- a touch of ground refills the air-jump budget (Wave 5; idle when
   -- airJumps is 0, the default)
   if sPlayGrounded is true then put sPlayAirJumps into sPlayAirJumpsLeft
   -- the drop window's bookkeeping runs UNGATED (a hurt or control-off
   -- mid-drop must never strand the mask without its one-way bit). The
   -- mask returns when the clock has run AND the capsule has cleared the
   -- line it dropped through -- a straddling restore would snap it back
   -- on top (chain contacts are one-sided, judged by the centroid) --
   -- with a hard 4x deadline for drops that land on something below.
   if sPlayDropUntil > 0 and tNow >= sPlayDropUntil then
      if (sPlayDropSeen is not true and sPlayPY - sPlayHalfH > sPlayDropLineY + 2) \
            or tNow >= sPlayDropHard then
         b2kPlayerDropRestore
      end if
   end if
   -- the hurt window runs its own clock: control comes back at hurtMs
   -- OR the first landing after half of it, whichever is LATER, and the
   -- mercy window starts then
   if sPlayHurt is true then
      if sPlayHurtLand is 0 and sPlayGrounded is true and tNow >= sPlayHurtHalf then
         put tNow into sPlayHurtLand
      end if
      if tNow >= sPlayHurtEnd and sPlayHurtLand > 0 then
         put false into sPlayHurt
         put tNow + sPlayInvulnMS into sPlayInvulnUntil
         put empty into sPlayAnimNow   -- re-assert the state anim
      end if
   end if
   put false into tWrite
   put false into tDuck
   put false into tOnLift
   if sPlayControl is true and sPlayHurt is not true then
      put sFrameMS / 1000 into tDT
      if tDT <= 0 then put 1 / 60 into tDT
      if tDT > 0.05 then put 0.05 into tDT
      put b2kAxis("moveX") into tAxis
      put b2kAxis("moveY") into tAxisY
      if tAxis is not 0 then
         if tAxis < 0 then
            put -1 into sPlayFacing
         else
            put 1 into sPlayFacing
         end if
      end if
      -- ladder + water presence: pure numeric compares on the probe's
      -- stashed centre; zero zones of a kind = one compare and out
      put false into tInZone
      if sPlayLadN > 0 then
         repeat with i = 1 to sPlayLadN
            if sPlayPX >= sPlayLadL[i] and sPlayPX <= sPlayLadR[i] \
                  and sPlayPY >= sPlayLadT[i] and sPlayPY <= sPlayLadB[i] then
               put true into tInZone
               exit repeat
            end if
         end repeat
      end if
      put false into tInWater
      if sPlayWatN > 0 then
         repeat with i = 1 to sPlayWatN
            if sPlayPX >= sPlayWatL[i] and sPlayPX <= sPlayWatR[i] \
                  and sPlayPY >= sPlayWatT[i] and sPlayPY <= sPlayWatB[i] then
               put true into tInWater
               exit repeat
            end if
         end repeat
      end if
      put tInZone into sPlayInLad   -- exposed by b2kPlayerInLadder/InWater
      put tInWater into sPlayInWat
      -- DASH (Wave 5): a flat horizontal burst that overrides normal
      -- movement for dashMs, then hands back. Idle in one compare when
      -- dashSpeed is 0; yields to climb/swim (it ends on entering either).
      if sPlayDash is true then
         if tNow >= sPlayDashEnd or tInWater is true or tInZone is true then
            b2kPlayerDashEnd tB
         else
            put sPlayDashDir into sPlayFacing   -- face the dash, not late input
            put sPlayDashDir * sPlayDashSpd into tVX
            put 0 into tVY
            put true into tWrite
         end if
      end if
      if sPlayDash is not true and sPlayDashSpd > 0 and tNow >= sPlayDashReady \
            and (sPlayAirDash is true or sPlayGrounded is true) \
            and sPlayClimb is not true and sPlaySwim is not true \
            and tInZone is not true and tInWater is not true \
            and b2kActionPressed("dash") then
         b2kPlayerDashStart tB
         put sPlayDashDir * sPlayDashSpd into tVX
         put 0 into tVY
         put true into tWrite
      end if
      -- everything below (climb/swim entry + the three movement modes) is
      -- suspended while a dash owns the body
      if sPlayDash is not true then
      if sPlayClimb is not true and sPlaySwim is not true and tInZone is true then
         -- enter: UP any time in-zone; DOWN only while AIRBORNE (a
         -- grounded DOWN is a duck -- or a drop-through on a chain)
         if tAxisY is -1 or (tAxisY is 1 and sPlayGrounded is not true) then
            b2kPlayerClimbStart tB
         end if
      end if
      if sPlaySwim is not true and sPlayClimb is not true and tInWater is true then
         b2kPlayerSwimStart tB   -- submerged: buoyant gravity, stroke to rise
      end if
      if sPlayClimb is true then
         if b2kActionPressed("jump") then
            -- JUMP exits with a normal jump. The same press edge is
            -- still "pressed" when the walk branch runs below this
            -- tick: tClimbJump keeps it from re-arming the buffer
            -- (one press must never pay for two jumps)
            b2kPlayerClimbEnd tB
            put 0 - sPlayJumpSpd into tVY
            put true into sPlayJumping
            put false into sPlayGrounded
            put 0 into sPlayGroundMS
            put 0 into sPlayPressMS
            put true into tClimbJump
            put true into tWrite
         else
            if tInZone is not true or (sPlayGrounded is true and tAxisY is 1) then
               -- slid out of the zone, or climbed down onto ground:
               -- gravity returns and (same tick) normal control resumes
               b2kPlayerClimbEnd tB
            else
               -- the climb drive: y runs at climbSpeed off the moveY
               -- axis (0 = hang), x at half speed, gravity parked at 0
               put tAxisY * sPlayClimbSpd into tVY
               put tAxis * sPlayMoveSpd / 2 into tTarget
               put sPlayAccelG * tDT into tStep
               if tVX < tTarget then
                  put min(tTarget, tVX + tStep) into tVX
               else
                  put max(tTarget, tVX - tStep) into tVX
               end if
               put true into tWrite
            end if
         end if
      end if
      if sPlaySwim is true then
         if tInWater is not true then
            b2kPlayerSwimEnd tB   -- surfaced / left the pool: gravity returns
         else
            -- horizontal: ease vx toward axis * swimSpeed (sluggish -- the
            -- air-accel rate gives the underwater drag)
            put tAxis * sPlaySwimSpd into tTarget
            put sPlayAccelA * tDT into tStep
            if tVX < tTarget then
               put min(tTarget, tVX + tStep) into tVX
            else
               put max(tTarget, tVX - tStep) into tVX
            end if
            -- vertical: a JUMP press is a repeatable upward STROKE (no
            -- ground gate -- the spec's water jump); else UP/DOWN swim at
            -- swimSpeed; else the reduced gravity sinks you, capped low
            if b2kActionPressed("jump") then
               put 0 - sPlaySwimJump into tVY
            else
               if tAxisY is not 0 then
                  put tAxisY * sPlaySwimSpd into tVY
               end if
            end if
            put true into tWrite
         end if
      end if
      if sPlayClimb is not true and sPlaySwim is not true then
         -- horizontal: accelerate vx toward axis * moveSpeed (air = airAccel)
         put tAxis * sPlayMoveSpd into tTarget
         -- DUCK: down on the ground. With duckScale < 1 the capsule
         -- reshapes to a CRAWL (slow movement, shorter hitbox -- so you
         -- can slip under a low gap); otherwise the Wave 2 duck brakes to
         -- a stop with the hitbox unchanged.
         if tAxisY is 1 and sPlayGrounded is true then
            put true into tDuck
            if sPlayDuckScale < 1 then
               b2kPlayerDuckSet true
               put tAxis * sPlayMoveSpd * 0.5 into tTarget   -- crawl, not brake
            else
               put 0 into tTarget
            end if
         end if
         if tDuck is not true and sPlayDucked is true then b2kPlayerDuckSet false
         -- PLATFORM CARRY (Wave 5): inherit the ground body's velocity so a
         -- moving platform carries you (static ground reads 0 -> no effect).
         -- A vertical lift's carry exempts the ground-snap below.
         if sPlayCarry is true and sPlayGrounded is true and sPlayGroundBody is not empty then
            put b2BodyVX(sPlayGroundBody) * sScale into tPVX
            put 0 - (b2BodyVY(sPlayGroundBody) * sScale) into tPVY
            add tPVX to tTarget
            if tPVY is not 0 and sPlayJumping is not true then
               put tPVY into tVY
               put true into tOnLift
            end if
         end if
         if sPlayGrounded then
            put sPlayAccelG into tAcc
         else
            put sPlayAccelA into tAcc
         end if
         -- a wall-jump owns vx briefly (sPlayWallLockUntil): skip the air
         -- steer so the away-launch carries clear before control resumes
         if tNow >= sPlayWallLockUntil then
            put tAcc * tDT into tStep
            if tVX < tTarget then
               put min(tTarget, tVX + tStep) into tVX
            else
               put max(tTarget, tVX - tStep) into tVX
            end if
         end if
         put true into tWrite
         if tClimbJump is not true and b2kActionPressed("jump") then put tNow into sPlayPressMS
         -- WALL slide (Wave 5; airborne only, one ray when the system is
         -- armed): hugging a wall while falling caps the fall at wallSlideMax
         put false into sPlayWallSliding
         if sPlayWallOn is true and sPlayGrounded is not true then
            b2kPlayerWallProbe tB, tAxis
            if sPlayWall is not 0 and tAxis is sPlayWall and tVY > 0 and sPlayWallSlideMax > 0 then
               if tVY > sPlayWallSlideMax then put sPlayWallSlideMax into tVY
               put true into sPlayWallSliding
            end if
         end if
         if tDuck is true then
            -- a press while crouched: on a ONE-WAY CHAIN it drops
            -- through (dropMs of no chain collision); on solid ground
            -- nothing -- and nothing later either, so the buffer is
            -- eaten (a crouch-press must not launch on release)
            if sPlayPressMS > 0 and tNow - sPlayPressMS <= sPlayBuffer then
               if sPlayOnOneWay is true and sPlayDropUntil is 0 then
                  b2kPlayerDropStart
                  put false into sPlayGrounded   -- falling from this frame on
                  put 0 into sPlayGroundMS       -- no coyote out of a drop
               end if
               put 0 into sPlayPressMS
            end if
         else
            -- a buffered press, in priority: WALL-JUMP > ground/coyote
            -- jump > air-jump (the double-jump). The wall and air branches
            -- idle (their knobs are 0) unless the game enables them.
            if sPlayPressMS > 0 and tNow - sPlayPressMS <= sPlayBuffer then
               if sPlayWallOn is true and sPlayWall is not 0 \
                     and sPlayGrounded is not true and sPlayWallJumpX > 0 then
                  -- WALL-JUMP: up + away from the wall, with a brief steer
                  -- lock so the launch carries before air control resumes
                  put sPlayWallJumpY into tStep
                  if tStep <= 0 then put sPlayJumpSpd into tStep
                  put 0 - tStep into tVY
                  put (0 - sPlayWall) * sPlayWallJumpX into tVX
                  put 0 - sPlayWall into sPlayFacing
                  put true into sPlayJumping
                  put tNow + 180 into sPlayWallLockUntil
                  put 0 into sPlayPressMS
               else
                  if sPlayGrounded or (sPlayGroundMS > 0 and tNow - sPlayGroundMS <= sPlayCoyote) then
                     put 0 - sPlayJumpSpd into tVY
                     put true into sPlayJumping
                     put false into sPlayGrounded   -- airborne from this frame on
                     put 0 into sPlayGroundMS       -- consume coyote
                     put 0 into sPlayPressMS        -- consume the buffer
                  else
                     if sPlayAirJumps > 0 and sPlayAirJumpsLeft > 0 then
                        -- DOUBLE / AIR JUMP: airborne, no ground or coyote
                        put 0 - sPlayJumpSpd into tVY
                        put true into sPlayJumping
                        subtract 1 from sPlayAirJumpsLeft
                        put 0 into sPlayPressMS
                     end if
                  end if
               end if
            end if
         end if
         -- jump-cut: releasing while still rising from OUR jump shortens it
         if sPlayJumping and tVY < 0 and b2kActionReleased("jump") then
            put tVY * sPlayJumpCut into tVY
            put false into sPlayJumping
         end if
      end if
      end if
   end if
   if sPlayJumping and tVY >= 0 then put false into sPlayJumping   -- apex
   -- terminal velocity: the low swimMaxFall is the buoyant sink cap while
   -- submerged; the normal maxFall (the character's terminal velocity) else
   if sPlaySwim is true then
      if tVY > sPlaySwimMaxFall then
         put sPlaySwimMaxFall into tVY
         put true into tWrite
      end if
   else
      if tVY > sPlayMaxFall then
         put sPlayMaxFall into tVY
         put true into tWrite
      end if
   end if
   -- GROUND-SNAP: grounded on FLAT ground, drifting upward, and we did
   -- not jump = the contact solver's push-out rebound after a hard
   -- landing (a ~7px hop: phantom airtime, double land ticks - measured
   -- by the self-test at vy 61 up). Kill it at the source. Slopes are
   -- exempt (|normalX| >= 0.1): running uphill is real upward motion.
   -- Climbs are exempt too: rising up a ladder from its grounded base
   -- is exactly the motion this guard exists to kill. External boosts
   -- must use b2kPlayerJump, which sets the jump flag (b2kPlayerHurt's
   -- pop rides the same flag).
   if sPlayGrounded and sPlayJumping is not true and sPlayClimb is not true \
         and sPlaySwim is not true and tOnLift is not true and tVY < 0 and abs(sPlayNormX) < 0.1 then
      put 0 into tVY
      put true into tWrite
   end if
   if tWrite then b2SetVelocity tB, tVX / sScale, 0 - (tVY / sScale)
   -- the state machine (land = exactly one tick on touch-down), with
   -- LANDING HYSTERESIS: the contact solver's push-out (and chain seams)
   -- can blip the 4px probe off for a tick around an impact -- without
   -- hysteresis that read as a second micro-fall and a second land tick
   -- (double land sounds; the self-test caught it). A touchdown counts
   -- as "land" only after a real airborne stretch (3+ ticks), and a
   -- single ungrounded blip does not even show as airborne -- unless it
   -- is OUR jump, which must read as "jump" on its launch frame.
   -- Hurt and climb OWN the state outright; a knockback's landing shows
   -- no "land" tick (the hit pose holds through the touchdown).
   put sPlayState into tPrevState
   if sPlayHurt is true then
      put "hurt" into sPlayState
      if sPlayGrounded is true then
         put 0 into sPlayAir
      else
         add 1 to sPlayAir
      end if
   else
      if sPlayClimb is true then
         put "climb" into sPlayState
         put 0 into sPlayAir
      else
         if sPlayGrounded is true then
            if (tPrevState is "jump" or tPrevState is "fall") and sPlayAir >= 3 then
               put "land" into sPlayState
            else
               if tDuck is true then
                  put "duck" into sPlayState
               else
                  if abs(tVX) < 8 then
                     put "idle" into sPlayState
                  else
                     put "run" into sPlayState
                  end if
               end if
            end if
            put 0 into sPlayAir
         else
            add 1 to sPlayAir
            if sPlayWallSliding is true then
               put "wallslide" into sPlayState   -- Wave 5: clinging a wall
            else
               if sPlayJumping is true or sPlayAir >= 2 then
                  if tVY < 0 then
                     put "jump" into sPlayState
                  else
                     put "fall" into sPlayState
                  end if
               end if
            end if
         end if
      end if
   end if
   -- swim OWNS the state while submerged: the machine above ran the
   -- grounded/airborne branch (sPlayClimb is false underwater), so override
   -- to "swim" and keep the air counter clear -- surfacing must never read
   -- as a long fall plus a phantom land tick.
   if sPlaySwim is true and sPlayHurt is not true then
      put "swim" into sPlayState
      put 0 into sPlayAir
   end if
   -- a dash OWNS the state outright (it yields to swim/climb, so it can
   -- never be underwater -- this safely overrides last)
   if sPlayDash is true then
      put "dash" into sPlayState
      put 0 into sPlayAir
   end if
   -- animations: only while controlling (manual poses own the art when
   -- control is off), and never let a vanished art control abort the
   -- frame -- the loop's ticks share one try block
   if sPlayControl is not true then exit b2kPlayerTick
   if sPlayAnims["idle"] is empty and sPlayAnims["run"] is empty then exit b2kPlayerTick
   try
      if sPlayArt is empty then b2kPlayerResolveArt
      if sPlayArt is not empty then b2kPlayerShowState tNow, tVX
   catch tErr
      put empty into sPlayArt   -- art gone; re-resolve next tick
   end try
end b2kPlayerTick

-- Internal: drive the art's animation and facing from the current state.
/**
Summary: Play the animation and facing for the player's state.

pNow: The controller's clock, in milliseconds.

pVX: The player's horizontal velocity, in px/s.

Example:
b2kPlayerShowState 0, 0

Description:
Internal: the tick calls it while the controller has control and art.

References: b2kPlayerAnims (handler), b2kPlayerTick (handler)
*/
command b2kPlayerShowState pNow, pVX
   local tWant, tAnim, tAKey, tFPS, tFlip
   put sPlayState into tWant
   if pNow < sPlayHoldMS and tWant is not "jump" and tWant is not "fall" \
         and tWant is not "hurt" and tWant is not "climb" and tWant is not "swim" \
         and tWant is not "wallslide" and tWant is not "dash" then
      put empty into tAnim   -- mid land-flourish: leave it playing
   else
      if tWant is "land" and sPlayAnims["land"] is empty then
         -- no flourish mapped: land straight into idle or run, by speed
         if abs(pVX) < 8 then
            put "idle" into tWant
         else
            put "run" into tWant
         end if
      end if
      put sPlayAnims[tWant] into tAnim
   end if
   if tAnim is not empty and tAnim is not sPlayAnimNow then
      b2kSpritePlay sPlayArt, tAnim, (tWant is "land")
      put tAnim into sPlayAnimNow
      if tWant is "land" then
         -- hold the flourish for its own length (frames / fps)
         put sSprSheet[sPlayArt] & "|" & tAnim into tAKey
         put sAnimFPS[tAKey] into tFPS
         if tFPS is empty or tFPS <= 0 then put 8 into tFPS
         put pNow + (the number of lines of sAnimList[tAKey]) * 1000 / tFPS into sPlayHoldMS
      else
         put 0 into sPlayHoldMS
      end if
   end if
   put (sPlayFacing < 0) into tFlip
   if tFlip is not sPlayFlipNow then
      b2kSpriteFlipH sPlayArt, tFlip
      put tFlip into sPlayFlipNow
   end if
end b2kPlayerShowState

-- =====================================================================
-- Camera: a clipped viewport group the loop scrolls (proven in spike S9)
-- =====================================================================
-- While the camera is on, Kit-created controls (spawns and sprites) are
-- placed INSIDE the viewport group; their locs stay WORLD pixels, because
-- contents of a scrolled group keep their coordinates -- the body sync and
-- all physics math are untouched, the scroll is pure presentation. Chrome
-- stays on the card; anything behind the (transparent) group reads as an
-- infinite-distance parallax backdrop. Map mouse points with
-- b2kCamMouseX/Y. Level coordinates should start at 0,0: an invisible
-- anchor pins the group's content origin there, so scroll == view corner.
/**
Summary: Turn on the scrolling camera.

pRect: The viewport rect on the card. Empty means the card's rect.

Example:
b2kCamOn
b2kCamBounds 0, 0, 3072, 640
b2kCamFollow gHero, 0.18

Description:
It creates a clipped viewport group the loop scrolls. While it is on,
controls the Kit creates go inside it and keep world-pixel locations. Turn
it on before building the level, after any static backdrop. Check
<b2kCamStatus> afterwards: a failure is reported there, not thrown.

References: b2kCamOff (handler), b2kCamFollow (handler), b2kCamBounds (handler), b2kCamStatus (handler)
*/
command b2kCamOn pRect
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tG
   if sCamGroup is not empty then exit b2kCamOn
   put empty into sCamNote
   if pRect is empty then put the rect of this card into pRect
   try
      create group "b2kcam_view"
   catch tErr
      put "create group failed: " & tErr into sCamNote
      exit b2kCamOn
   end try
   put the long id of group "b2kcam_view" into tG
   try
      set the margins of tG to 0
      set the showBorder of tG to false
      set the hScrollbar of tG to false
      set the vScrollbar of tG to false
      create graphic "b2kcam_anchor" in group "b2kcam_view"
      set the rect of it to 0, 0, 1, 1
      set the visible of it to false
      set the lockLoc of tG to true
      set the rect of tG to pRect
   catch tErr
      put "viewport setup failed: " & tErr into sCamNote
      try
         delete group "b2kcam_view"
      catch tErr
      end try
      exit b2kCamOn
   end try
   try
      set the unboundedHScroll of tG to true
      set the unboundedVScroll of tG to true
   catch tErr
   end try
   -- NOTE: deliberately NOT layerMode "scrolling". The compositor caches
   -- that mode's content as one surface; past common GPU surface limits
   -- (~2048px) the cached world freezes while dynamic-layer sprites keep
   -- moving -- the player "runs off" a stopped picture. Plain rendering
   -- pans correctly at any level size.
   put tG into sCamGroup
   set the itemDelimiter to comma
   put ((item 1 of pRect) + (item 3 of pRect)) / 2 into sCamX
   put ((item 2 of pRect) + (item 4 of pRect)) / 2 into sCamY
   put 0.15 into sCamLerp
   put 0 into sCamDZW
   put 0 into sCamDZH
   put empty into sCamFollow
   put empty into sCamB1X
   put 0 into sCamShakeAmp
   put empty into sCamLastH
   put empty into sCamLastV
   -- self-test: prove the scroll property actually pans this group. The
   -- anchor is stretched first so content exceeds the view (engines clamp
   -- scroll to content bounds), then restored; failure is reported via
   -- b2kCamStatus instead of letting the player walk out of a frozen view.
   try
      set the rect of graphic "b2kcam_anchor" to 0, 0, 4000, 2000
      set the hScroll of sCamGroup to 7
      if the hScroll of sCamGroup is not 7 then
         put "group scroll is ineffective on this engine" into sCamNote
      end if
      set the hScroll of sCamGroup to 0
      set the rect of graphic "b2kcam_anchor" to 0, 0, 1, 1
   catch tErr
      put "setting the group scroll failed: " & tErr into sCamNote
   end try
   -- probe the engine's coordinate semantics for grouped controls: place a
   -- probe at x=100, scroll by 50, and read the loc back. Engines that
   -- report 50 give SCROLL-ADJUSTED (visual) locs -- every per-frame
   -- position write into the group must then subtract the live scroll, or
   -- the write cancels the pan and the control "outruns" the world.
   put false into sCamLocVisual
   try
      set the rect of graphic "b2kcam_anchor" to 0, 0, 4000, 2000
      create graphic "b2kcam_probe" in group "b2kcam_view"
      set the rect of it to 96, 96, 104, 104
      set the visible of it to false
      set the hScroll of sCamGroup to 50
      put ((item 1 of the loc of graphic "b2kcam_probe") is 50) into sCamLocVisual
      set the hScroll of sCamGroup to 0
      delete graphic "b2kcam_probe"
      set the rect of graphic "b2kcam_anchor" to 0, 0, 1, 1
   catch tErr
      put false into sCamLocVisual
   end try
   put 0 into sCamCurH
   put 0 into sCamCurV
   put empty into sInCam
   b2kCamApply
end b2kCamOn

-- Dissolve the viewport: children return to the card with their world locs.
/**
Summary: Turn off the camera.

Example:
b2kCamOff

Description:
The viewport is dissolved and its controls return to the card with their world locations. <b2kTeardown> calls it.

References: b2kCamOn (handler)
*/
command b2kCamOff
   if sCamGroup is empty then exit b2kCamOff
   try
      ungroup group "b2kcam_view"
   catch tErr
   end try
   if there is a graphic "b2kcam_anchor" then delete graphic "b2kcam_anchor"
   put empty into sCamGroup
   put false into sCamLocVisual
   put 0 into sCamCurH
   put 0 into sCamCurV
   put empty into sInCam
end b2kCamOff

/**
Summary: Report whether the camera is on.

Returns: true or false.

Example:
if not b2kCamIsOn() then b2kCamOn

References: b2kCamOn (handler)
*/
function b2kCamIsOn
   return (sCamGroup is not empty)
end b2kCamIsOn

-- The viewport group's reference (empty when the camera is off) -- create
-- your own level controls inside it: create graphic "x" in b2kCamGroup().
/**
Summary: The camera's viewport group.

Returns: The group's long id, or empty when the camera is off.

Example:
create graphic "Sign" in b2kCamGroup()

Description:
Create your own level controls inside it so they scroll.

References: b2kCamAdopt (handler), b2kCamOn (handler)
*/
function b2kCamGroup
   return sCamGroup
end b2kCamGroup

-- Move an existing control (IDE-designed levels) into the viewport.
/**
Summary: Move an existing control into the camera's viewport.

pCtrl: The control, by reference (the long id of the control is safest).

Example:
b2kCamAdopt the long id of graphic "Platform1"

Description:
For levels laid out in the IDE. With the camera off it does nothing.

References: b2kCamGroup (handler)
*/
command b2kCamAdopt pCtrl
   if sCamGroup is empty then exit b2kCamAdopt
   try
      relayer pCtrl to front of group "b2kcam_view"
   catch tErr
      -- no script relayer on this engine: the control stays on the card.
      -- Physics is unaffected; only its drawing will not scroll.
   end try
   -- mark AFTER the move: a long id embeds the group path, so the key
   -- must be the post-relayer id or the camera's write-compensation
   -- (b2kCamShiftX/Y) never recognises adopted controls
   try
      put true into sInCam[the long id of pCtrl]
   catch tErr
   end try
end b2kCamAdopt

/**
Summary: Make the camera follow a control.

pCtrl: The control, by reference (the long id of the control is safest).

pLerp: Optional smoothing, 0.01 to 1 (1 snaps). The default is 0.15.

Example:
b2kCamFollow gHero, 0.18

Description:
The camera eases toward the control, and snaps when the control would leave the view.

References: b2kCamUnfollow (handler), b2kCamDeadzone (handler)
*/
command b2kCamFollow pCtrl, pLerp
   put the long id of pCtrl into sCamFollow
   if pLerp is a number then put b2kClamp(pLerp, 0.01, 1) into sCamLerp
end b2kCamFollow

/**
Summary: Stop the camera following.

Example:
b2kCamUnfollow

References: b2kCamFollow (handler), b2kCamGoto (handler)
*/
command b2kCamUnfollow
   put empty into sCamFollow
end b2kCamUnfollow

-- Follow only once the target leaves a centre box (0 = always centre).
/**
Summary: Set a centre box the target may move in before the camera chases.

pW: The box's width in pixels; 0 always centres.

pH: The box's height in pixels; 0 always centres.

Example:
b2kCamDeadzone 140, 600

References: b2kCamFollow (handler)
*/
command b2kCamDeadzone pW, pH
   put b2kNumberOr(pW, 0) into sCamDZW
   put b2kNumberOr(pH, 0) into sCamDZH
end b2kCamDeadzone

/**
Summary: Keep the view inside the level's rectangle.

pX1: The level's left, in world pixels.

pY1: The level's top, in world pixels.

pX2: The level's right, in world pixels.

pY2: The level's bottom, in world pixels.

Example:
b2kCamBounds 0, 0, 3072, 640

Description:
Set the bounds before <b2kCamGoto>.

References: b2kCamOn (handler), b2kCamGoto (handler)
*/
command b2kCamBounds pX1, pY1, pX2, pY2
   put pX1 into sCamB1X
   put pY1 into sCamB1Y
   put pX2 into sCamB2X
   put pY2 into sCamB2Y
   -- stretch the invisible anchor across the whole level: the group's
   -- scrollable content then always spans the bounds, so the engine can
   -- never clamp the scroll short (works with or without unbounded scroll)
   if sCamGroup is not empty then
      try
         set the rect of graphic "b2kcam_anchor" to pX1, pY1, pX2, pY2
      catch tErr
      end try
   end if
end b2kCamBounds

/**
Summary: Cut the view to a world point.

pX: The new view centre x, in world pixels.

pY: The new view centre y, in world pixels.

Example:
b2kCamGoto 0, 320

Description:
The point is clamped to the bounds and applied at once.

References: b2kCamPos (handler), b2kCamBounds (handler)
*/
command b2kCamGoto pX, pY
   put b2kNumberOr(pX, sCamX) into sCamX
   put b2kNumberOr(pY, sCamY) into sCamY
   b2kCamApply
end b2kCamGoto

/**
Summary: The view's centre.

Returns: "x,y" in world pixels.

Example:
put b2kCamPos() into tView

References: b2kCamGoto (handler)
*/
function b2kCamPos
   return round(sCamX) & comma & round(sCamY)
end b2kCamPos

-- A decaying random view offset on top of the follow (impacts, blasts).
/**
Summary: Shake the view for a moment.

pAmpPx: The shake size in pixels, 0-200.

pMs: How long it lasts, in milliseconds, 0-5000.

Example:
b2kCamShake 8, 300

References: b2kCamOn (handler)
*/
command b2kCamShake pAmpPx, pMs
   put b2kClamp(pAmpPx, 0, 200) into sCamShakeAmp
   put the milliseconds + b2kClamp(pMs, 0, 5000) into sCamShakeEnd
end b2kCamShake

-- The mouse in WORLD pixels (camera-aware) -- use these for b2kGrab,
-- spawning at the pointer, click-picking, instead of the mouseH/V.
/**
Summary: The mouse's x in world pixels.

Returns: The mouse x adjusted for the camera scroll; the plain mouseH when the camera is off.

Example:
get b2kGrab(b2kCamMouseX(), b2kCamMouseY())

References: b2kCamMouseY (handler), b2kGrab (handler)
*/
function b2kCamMouseX
   if sCamGroup is empty then return the mouseH
   set the itemDelimiter to comma
   return the mouseH - (item 1 of the rect of sCamGroup) + the hScroll of sCamGroup
end b2kCamMouseX

/**
Summary: The mouse's y in world pixels.

Returns: The mouse y adjusted for the camera scroll; the plain mouseV when the camera is off.

Example:
put b2kCamMouseY() into tWorldY

References: b2kCamMouseX (handler)
*/
function b2kCamMouseY
   if sCamGroup is empty then return the mouseV
   set the itemDelimiter to comma
   return the mouseV - (item 2 of the rect of sCamGroup) + the vScroll of sCamGroup
end b2kCamMouseY

-- Health: empty = camera fine (or simply off); otherwise the reason the
-- camera could not run properly (create-group/scroll failures). Check it
-- after b2kCamOn and degrade your level gracefully.
/**
Summary: Why the camera is not working, if it is not.

Returns: Empty when healthy (or off), otherwise the reason.

Example:
if b2kCamStatus() is not empty then answer b2kCamStatus()

References: b2kCamOn (handler)
*/
function b2kCamStatus
   return sCamNote
end b2kCamStatus

-- "visual" when this engine reports/sets grouped locs scroll-adjusted,
-- else "content". Diagnostic; the Kit compensates automatically.
/**
Summary: Which grouped-location model this engine uses.

Returns: "visual" when grouped controls report scroll-adjusted locations, else "content".

Example:
put b2kCamLocSemantics() into tModel

Description:
A diagnostic from the probe <b2kCamOn> runs; the Kit compensates either way.

References: b2kCamShiftX (handler)
*/
function b2kCamLocSemantics
   if sCamLocVisual is true then return "visual"
   return "content"
end b2kCamLocSemantics

-- Internal: the scroll to subtract when WRITING a position into the
-- viewport on a visual-semantics engine (0 otherwise / outside it).
/**
Summary: The horizontal scroll to subtract when placing a control in the viewport.

pRef: The control's long id.

Returns: The scroll in pixels on a visual-model engine for a control inside the viewport, else 0.

Example:
set the loc of tRef to tX - b2kCamShiftX(tRef), tY - b2kCamShiftY(tRef)

Description:
<b2kSpriteMoveTo> and the renderer apply it for you.

References: b2kCamShiftY (handler), b2kCamLocSemantics (handler), b2kSpriteMoveTo (handler)
*/
function b2kCamShiftX pRef
   if sCamLocVisual is not true then return 0
   if sInCam[pRef] is not true then return 0
   return sCamCurH
end b2kCamShiftX

/**
Summary: The vertical scroll to subtract when placing a control in the viewport.

pRef: The control's long id.

Returns: The scroll in pixels on a visual-model engine for a control inside the viewport, else 0.

Example:
put b2kCamShiftY(tRef) into tShift

References: b2kCamShiftX (handler)
*/
function b2kCamShiftY pRef
   if sCamLocVisual is not true then return 0
   if sInCam[pRef] is not true then return 0
   return sCamCurV
end b2kCamShiftY

-- Move ANY sprite/control to a WORLD position, camera-correct (use this
-- instead of `set the loc` for things you animate by hand, like a patrol
-- path -- outside a camera it is a plain loc set).
/**
Summary: Move a control to a world position, camera-correct.

pCtrl: The control, by reference. Empty makes this a no-op.

pX: The world x, in pixels.

pY: The world y, in pixels.

Example:
b2kSpriteMoveTo tBat, tBatX, 200

Description:
Use it instead of setting the loc for things you animate by hand,
such as patrols. Outside a camera it is a plain loc set. It does not move a
body; use <b2kMoveTo> for that.

References: b2kMoveTo (handler), b2kCamShiftX (handler)
*/
command b2kSpriteMoveTo pCtrl, pX, pY
   local tRef
   if pCtrl is empty then exit b2kSpriteMoveTo   -- family law: empty ref = no-op
   put the long id of pCtrl into tRef
   set the loc of tRef to round(pX - b2kCamShiftX(tRef)) & comma & round(pY - b2kCamShiftY(tRef))
end b2kSpriteMoveTo

-- Internal, called by the loop each frame: chase the followed control. The
-- follow eases, but the target is GUARANTEED on screen: if it would leave
-- the view (fast falls, teleports, lerp lag), the camera snaps to it.
/**
Summary: Run one frame of the camera.

Example:
b2kCamTick

Description:
Internal: the loop calls it each frame. It chases the followed
control, then applies the view with <b2kCamApply>, and forces the scroll if
the target ever ends up outside the view.

References: b2kCamApply (handler), b2kCamFollow (handler)
*/
command b2kCamTick
   local tLoc, tTX, tTY, tHalfW, tHalfH
   if sCamGroup is empty then exit b2kCamTick
   if sCamFollow is not empty then
      try
         set the itemDelimiter to comma
         put the loc of sCamFollow into tLoc
         put (item 1 of tLoc) + b2kCamShiftX(sCamFollow) into tTX
         put (item 2 of tLoc) + b2kCamShiftY(sCamFollow) into tTY
         if abs(tTX - sCamX) > sCamDZW / 2 then
            put sCamX + sCamLerp * (tTX - sCamX) into sCamX
         end if
         if abs(tTY - sCamY) > sCamDZH / 2 then
            put sCamY + sCamLerp * (tTY - sCamY) into sCamY
         end if
         -- the never-offscreen guarantee (32 px inside the view edges)
         put ((item 3 of the rect of sCamGroup) - (item 1 of the rect of sCamGroup)) / 2 into tHalfW
         put ((item 4 of the rect of sCamGroup) - (item 2 of the rect of sCamGroup)) / 2 into tHalfH
         if abs(tTX - sCamX) > tHalfW - 32 then put tTX into sCamX
         if abs(tTY - sCamY) > tHalfH - 32 then put tTY into sCamY
      catch tErr
         put empty into sCamFollow   -- target vanished
      end try
   end if
   b2kCamApply
   -- reality check: prove the target is inside the view using the ACTUAL
   -- scroll properties (not internal state). If anything desynced them --
   -- an engine quirk, a missed write -- force the scroll directly.
   if sCamFollow is not empty then
      try
         set the itemDelimiter to comma
         put the loc of sCamFollow into tLoc
         put (item 1 of tLoc) + b2kCamShiftX(sCamFollow) - (the hScroll of sCamGroup) into tTX
         put ((item 3 of the rect of sCamGroup) - (item 1 of the rect of sCamGroup)) into tHalfW
         if tTX < 48 or tTX > tHalfW - 48 then
            set the hScroll of sCamGroup to round((item 1 of tLoc) - tHalfW / 2)
            put the hScroll of sCamGroup into sCamLastH
            put item 1 of tLoc into sCamX
         end if
      catch tErr
      end try
   end if
end b2kCamTick

-- Internal: clamp to bounds, add shake, write the scroll (skip when same).
/**
Summary: Write the camera's scroll.

Example:
b2kCamApply

Description:
Internal: clamps the view to the bounds, adds any shake and sets the group's scroll when it changed.

References: b2kCamTick (handler), b2kCamBounds (handler)
*/
command b2kCamApply
   local tVW, tVH, tHalfW, tHalfH, tX, tY, tH, tV, tNow
   if sCamGroup is empty then exit b2kCamApply
   set the itemDelimiter to comma
   put (item 3 of the rect of sCamGroup) - (item 1 of the rect of sCamGroup) into tVW
   put (item 4 of the rect of sCamGroup) - (item 2 of the rect of sCamGroup) into tVH
   put tVW / 2 into tHalfW
   put tVH / 2 into tHalfH
   put sCamX into tX
   put sCamY into tY
   if sCamB1X is not empty then
      if tX > sCamB2X - tHalfW then put sCamB2X - tHalfW into tX
      if tX < sCamB1X + tHalfW then put sCamB1X + tHalfW into tX
      if tY > sCamB2Y - tHalfH then put sCamB2Y - tHalfH into tY
      if tY < sCamB1Y + tHalfH then put sCamB1Y + tHalfH into tY
   end if
   -- write the clamped centre back: the follow math must ease against the
   -- view that is actually shown, or the camera lags invisibly at the
   -- bounds and the player outruns a scroll that has not started yet
   put tX into sCamX
   put tY into sCamY
   if sCamShakeAmp > 0 then
      put the milliseconds into tNow
      if tNow >= sCamShakeEnd then
         put 0 into sCamShakeAmp
      else
         put tX + (random(sCamShakeAmp * 2 + 1) - sCamShakeAmp - 1) into tX
         put tY + (random(sCamShakeAmp * 2 + 1) - sCamShakeAmp - 1) into tY
      end if
   end if
   put round(tX - tHalfW) into tH   -- content origin pinned at 0,0
   put round(tY - tHalfH) into tV
   if tH is not sCamLastH then
      set the hScroll of sCamGroup to tH
      put tH into sCamLastH
   end if
   if tV is not sCamLastV then
      set the vScroll of sCamGroup to tV
      put tV into sCamLastV
   end if
   put tH into sCamCurH
   put tV into sCamCurV
end b2kCamApply

-- =====================================================================
-- Audio: named sounds over audioClips + a script-side tone synthesizer
-- =====================================================================
-- Model: a sound is an AUDIOCLIP imported into the stack -- the one LC
-- sound path with no external media-layer dependency -- and plays by
-- name (`play audioClip`). The engine plays ONE clip at a time; a new
-- play cuts the previous. That is the classic LC limit, and it suits
-- short retro SFX (document it, don't fight it). b2kToneMake SYNTHESIZES
-- a clip in pure script (8-bit mono WAV at 22050 Hz, square or sine, a
-- comma list of note frequencies, per-note decay so notes never click),
-- so a self-contained example ships sound with ZERO asset files. Sounds
-- are assets that SURVIVE b2kTeardown -- clips are tiny and resets must
-- stay snappy; names are stable, so re-making replaces rather than
-- accumulates, a SAVED stack's clips are adopted by name when it reopens
-- (b2kSoundClip), and b2kSoundsWipe purges everything (it also sweeps
-- b2ksnd_ clips a dead session left in the stack). Failures degrade to
-- silence, never to errors: the first play that throws trips a
-- dead-flag and b2kSoundStatus() says why. The mute is a user
-- preference. There is no per-frame tick -- audio is purely
-- event-driven.

-- Import a WAV/AIFF/AU file as a named sound (replaces any same name).
/**
Summary: Import a sound file under a name.

pName: The sound's name.

pPath: A WAV, AIFF or AU file's path.

Example:
b2kSoundLoad "boom", tFolder & "/boom.wav"

Description:
The file becomes an audioClip in the stack, replacing a sound of the
same name. A missing file or failed import is reported by <b2kSoundStatus>,
not thrown.

References: b2kSound (handler), b2kToneMake (handler), b2kSoundStatus (handler)
*/
command b2kSoundLoad pName, pPath
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tClip, tCount
   if pName is empty then exit b2kSoundLoad
   if there is no file pPath then
      put "no such file: " & pPath into sSndNote
      exit b2kSoundLoad
   end if
   put "b2ksnd_" & pName into tClip
   try
      if there is an audioClip tClip then delete audioClip tClip
      put the number of audioClips of this stack into tCount
      import audioClip from file pPath
      if the number of audioClips of this stack > tCount then
         set the name of audioClip (tCount + 1) of this stack to tClip
         put tClip into sSndClip[pName]
      end if
   catch tErr
      put "import failed: " & tErr into sSndNote
   end try
end b2kSoundLoad

-- Synthesize a named sound: pFreqs is a comma list of note frequencies
-- in Hz (0 = a rest), each pMsPerNote long; pVolPct 0-100 (default 60);
-- pShape "square" (default -- retro/plucky) or "sine" (soft). About
-- 22 KB per second of audio, built once -- keep SFX short.
--   b2kToneMake "coin", "1319,1760", 36          -- a two-note blip
--   b2kToneMake "win", "523,659,784,1047", 110   -- a little fanfare
/**
Summary: Synthesize a sound from note frequencies, with no asset file.

pName: The sound's name.

pFreqs: A comma list of frequencies in hertz; 0 is a rest.

pMsPerNote: Each note's length in milliseconds, 5-2000.

pVolPct: Volume 0-100. Empty means 60.

pShape: "sine" for a soft tone; anything else is a square wave.

Example:
b2kToneMake "coin", "1319,1760", 36
b2kSound "coin"

Description:
It builds an 8-bit mono WAV at 22050 Hz in script, with a decay on
each note, and imports it as an audioClip, replacing a sound of the same
name. About 22 KB per second: keep effects short.

References: b2kSound (handler), b2kToneBytes (handler), b2kSoundLoad (handler)
*/
command b2kToneMake pName, pFreqs, pMsPerNote, pVolPct, pShape
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tClip, tData, tPath, tCount, tF
   if pName is empty then exit b2kToneMake
   put "b2ksnd_" & pName into tClip
   put b2kClamp(pMsPerNote, 5, 2000) into pMsPerNote
   put b2kClamp(b2kNumberOr(pVolPct, 60), 0, 100) into pVolPct
   put empty into tData
   set the itemDelimiter to comma
   repeat for each item tF in pFreqs
      put b2kToneBytes(b2kNumberOr(word 1 of tF, 440), pMsPerNote, pVolPct, pShape) after tData
   end repeat
   if tData is empty then exit b2kToneMake
   put specialFolderPath("temporary") & "/b2ktone_" & the milliseconds & "_" & random(99999) & ".wav" into tPath
   put b2kWavWrap(tData) into URL ("binfile:" & tPath)
   try
      if there is an audioClip tClip then delete audioClip tClip
      put the number of audioClips of this stack into tCount
      import audioClip from file tPath
      if the number of audioClips of this stack > tCount then
         set the name of audioClip (tCount + 1) of this stack to tClip
         put tClip into sSndClip[pName]
      end if
   catch tErr
      put "import failed: " & tErr into sSndNote
   end try
   try
      delete file tPath
   catch tErr
   end try
end b2kToneMake

-- Internal: pMs of one note as 8-bit unsigned mono PCM at 22050 Hz,
-- with a linear decay across the note (clickless and plucky).
/**
Summary: Synthesize one note as raw samples.

pFreq: The frequency in hertz; 0 or below is a rest.

pMs: The length in milliseconds.

pVolPct: Volume 0-100.

pShape: "sine", or anything else for square.

Returns: 8-bit unsigned mono samples at 22050 Hz with a linear decay, or empty for a zero length.

Example:
put b2kToneBytes(880, 50, 60, "sine") into tSamples

References: b2kWavWrap (handler), b2kToneMake (handler)
*/
function b2kToneBytes pFreq, pMs, pVolPct, pShape
   local tRate, tN, tOut, i, tPhase, tStep, tAmp, tEnv, tS
   put 22050 into tRate
   put round(tRate * pMs / 1000) into tN
   if tN < 1 then return empty
   put pVolPct * 1.27 into tAmp   -- 0-100 -> 0-127 sample amplitude
   put pFreq / tRate into tStep
   put 0 into tPhase
   put empty into tOut
   repeat with i = 0 to tN - 1
      put tAmp * (1 - i / tN) into tEnv
      if pFreq <= 0 then
         put 0 into tS   -- a rest
      else
         if pShape is "sine" then
            put tEnv * sin(tPhase * 2 * kPI) into tS
         else
            if tPhase mod 1 < 0.5 then
               put tEnv into tS
            else
               put 0 - tEnv into tS
            end if
         end if
      end if
      put numToByte(round(128 + tS)) after tOut
      add tStep to tPhase
   end repeat
   return tOut
end b2kToneBytes

-- Internal: wrap raw 8-bit mono 22050 Hz samples in a WAV container.
/**
Summary: Wrap raw samples in a WAV file header.

pData: 8-bit mono samples at 22050 Hz.

Returns: The bytes of a WAV file.

Example:
put b2kWavWrap(tSamples) into URL ("binfile:" & tPath)

References: b2kToneBytes (handler), b2kLE32 (handler)
*/
function b2kWavWrap pData
   local tLen
   put the number of bytes in pData into tLen
   return "RIFF" & b2kLE32(36 + tLen) & "WAVE" & "fmt " & b2kLE32(16) \
         & b2kLE16(1) & b2kLE16(1) & b2kLE32(22050) & b2kLE32(22050) \
         & b2kLE16(1) & b2kLE16(8) & "data" & b2kLE32(tLen) & pData
end b2kWavWrap

-- Internal: little-endian byte packers (hand-rolled: no binaryEncode
-- format-letter portability worries).
/**
Summary: Pack a number as two little-endian bytes.

pN: A whole number from 0 to 65535.

Returns: Two bytes.

Example:
put b2kLE16(1) into tBytes

References: b2kLE32 (handler), b2kWavWrap (handler)
*/
function b2kLE16 pN
   return numToByte(pN mod 256) & numToByte(pN div 256 mod 256)
end b2kLE16

/**
Summary: Pack a number as four little-endian bytes.

pN: A whole number from 0 to 4294967295.

Returns: Four bytes.

Example:
put b2kLE32(22050) into tBytes

References: b2kLE16 (handler), b2kWavWrap (handler)
*/
function b2kLE32 pN
   return numToByte(pN mod 256) & numToByte(pN div 256 mod 256) & numToByte(pN div 65536 mod 256) & numToByte(pN div 16777216 mod 256)
end b2kLE32

-- Play a named sound (cuts whatever is playing -- the audioClip model).
/**
Summary: Play a named sound.

pName: The sound's name.

Example:
b2kSound "coin"

Description:
The engine plays one clip at a time, so this cuts whatever is
playing. Unknown names, mute and dead audio are silent no-ops; a failed play
turns audio off for the session and <b2kSoundStatus> says why.

References: b2kSoundLoop (handler), b2kSoundMute (handler), b2kToneMake (handler)
*/
command b2kSound pName
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tClip
   if sSndMute is true or sSndDead is true then exit b2kSound
   put b2kSoundClip(pName) into tClip
   if tClip is empty then exit b2kSound
   try
      play audioClip tClip
   catch tErr
      put true into sSndDead   -- this engine can't play: silence, no spam
      put "play failed: " & tErr into sSndNote
   end try
end b2kSound

-- Loop a named sound until b2kSoundStop / the next play (ambience).
/**
Summary: Loop a named sound until stopped.

pName: The sound's name.

Example:
b2kSoundLoop "wind"

Description:
It plays until <b2kSoundStop> or the next sound.

References: b2kSoundStop (handler), b2kSound (handler)
*/
command b2kSoundLoop pName
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tClip
   if sSndMute is true or sSndDead is true then exit b2kSoundLoop
   put b2kSoundClip(pName) into tClip
   if tClip is empty then exit b2kSoundLoop
   try
      play audioClip tClip looping
   catch tErr
      put true into sSndDead
      put "play failed: " & tErr into sSndNote
   end try
end b2kSoundLoop

/**
Summary: Stop the current sound.

Example:
b2kSoundStop

References: b2kSoundLoop (handler)
*/
command b2kSoundStop
   try
      play stop
   catch tErr
   end try
end b2kSoundStop

-- Mute is a preference: it survives b2kTeardown and stack resets are up
-- to the caller (store it in a custom property if you want it saved).
/**
Summary: Mute or unmute the Kit's sounds.

pFlag: true to mute; anything else unmutes.

Example:
b2kSoundMute true

Description:
Muting also stops the current sound. The setting survives <b2kTeardown> but not a reopened stack; save it yourself if needed.

References: b2kSoundMuted (handler)
*/
command b2kSoundMute pFlag
   put (pFlag is true) into sSndMute
   if sSndMute then b2kSoundStop
end b2kSoundMute

/**
Summary: Report whether sounds are muted.

Returns: true or false.

Example:
put b2kSoundMuted() into tMuted

References: b2kSoundMute (handler)
*/
function b2kSoundMuted
   return (sSndMute is true)
end b2kSoundMuted

-- The engine-GLOBAL output volume (the playLoudness, 0-100): it affects
-- every stack's audio, so games should expose it, not hardcode it.
/**
Summary: Set the engine's global playback volume.

pPct: Volume 0-100.

Example:
b2kSoundVolume 70

Description:
It sets the playLoudness, which affects every stack's audio, so let the user choose it.

References: b2kSoundMute (handler)
*/
command b2kSoundVolume pPct
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   try
      set the playLoudness to round(b2kClamp(pPct, 0, 100))
   catch tErr
      put "volume failed: " & tErr into sSndNote
   end try
end b2kSoundVolume

/**
Summary: Report whether a named sound exists.

pName: The sound's name.

Returns: true or false; true too for a clip a saved stack carried in.

Example:
if not b2kSoundIsLoaded("coin") then b2kToneMake "coin", "1319,1760", 36

References: b2kSoundClip (handler)
*/
function b2kSoundIsLoaded pName
   return (b2kSoundClip(pName) is not empty)
end b2kSoundIsLoaded

-- Internal: the audioClip that plays pName, or empty. The registry is a
-- script local, so it is EMPTY when a saved stack reopens; the clips were
-- saved WITH the stack under their stable names (b2ksnd_<name>), so a clip
-- already in the stack is ADOPTED into the registry instead of being made
-- again. A game's "already built?" guard (b2kSoundIsLoaded) then holds
-- across a reopen, where it used to re-synthesize every cue on every launch.
/**
Summary: The audioClip that plays a named sound.

pName: The sound's name.

Returns: The clip's name, or empty.

Example:
put b2kSoundClip("coin") into tClip

Description:
A clip already in the stack under the Kit's name for the sound (as
in a reopened saved stack) is adopted instead of being made again.

References: b2kSoundIsLoaded (handler), b2kSound (handler)
*/
function b2kSoundClip pName
   local tClip
   if pName is empty then return empty
   if sSndClip[pName] is not empty then return sSndClip[pName]
   put "b2ksnd_" & pName into tClip
   if there is an audioClip tClip then
      put tClip into sSndClip[pName]
      return tClip
   end if
   return empty
end b2kSoundClip

-- Empty = healthy; otherwise the most recent reason audio degraded
-- (missing file, import failure, play failure). Plays never throw.
/**
Summary: Why audio is degraded, if it is.

Returns: Empty when healthy, otherwise the latest reason (missing file, failed import or play).

Example:
if b2kSoundStatus() is not empty then put b2kSoundStatus() into field "Log"

References: b2kSound (handler)
*/
function b2kSoundStatus
   return sSndNote
end b2kSoundStatus

-- Internal: delete every Kit-made audioClip ("b2ksnd_" prefix -- catches
-- a dead session's leftovers too) and reset the registry. The dead-flag
-- resets (a fresh world may retry); the mute preference survives.
/**
Summary: Stop playback and delete every Kit sound.

Example:
b2kSoundsWipe

Description:
It deletes every Kit-made audioClip, including ones a previous
session left in the stack, and resets audio after a failure. The mute
setting survives.

References: b2kSoundLoad (handler), b2kTeardown (handler)
*/
command b2kSoundsWipe
   local i, tName
   try
      play stop
   catch tErr
   end try
   repeat with i = the number of audioClips of this stack down to 1
      put the short name of audioClip i of this stack into tName
      if char 1 to 7 of tName is "b2ksnd_" then
         try
            delete audioClip i of this stack
         catch tErr
         end try
      end if
   end repeat
   put empty into sSndClip
   put false into sSndDead
   put empty into sSndNote
end b2kSoundsWipe

-- =====================================================================
-- The loop  (fixed timestep, generation-guarded; one screen lock per frame)
-- =====================================================================
-- The whole frame -- body sync, contact/sensor dispatch and the app's own
-- b2kFrame drawing -- runs inside a single lock screen / unlock screen so it
-- composites in ONE redraw (no tearing between bodies and the joints/HUD a user
-- draws on top). The try/catch guarantees the unlock even if a user handler
-- throws, so a faulty event handler can never leave the screen frozen.
on b2kStep pGen
   local tNow, tElapsed, tFixed, tNext
   if not sRunning then exit b2kStep
   if pGen is not sGen then exit b2kStep
   if sPaused is not true then
      put the milliseconds into tNow
      put (tNow - sLast) / 1000 into tElapsed
      put tNow into sLast
      add tElapsed to sAccum
      if sAccum > 0.20 then put 0.20 into sAccum
      put tElapsed * 1000 into sFrameMS
      put 1 / 60 into tFixed
      -- events are HARVESTED per fixed step into frame buffers: Box2D
      -- only exposes the LAST step's events, so a 2-step frame would
      -- lose the first step's pickups/stomps, and a 0-step frame would
      -- re-read (duplicate!) the previous step's. The buffers make the
      -- frame's event view exact either way.
      b2kEventsReset
      repeat while sAccum >= tFixed
         b2Step sWorld, tFixed, sSub
         b2kHarvestEvents
         subtract tFixed from sAccum
      end repeat
      if sDragging then
         -- camera-aware: b2kCamMouseX/Y fall back to the raw mouse when off
         b2MouseSetTarget sDragJoint, b2kToWorldX(b2kCamMouseX()), b2kToWorldY(b2kCamMouseY())
      end if
      lock screen
      try
         b2kSyncBodies         -- lock-free; this frame's single lock is held here
         b2kInputTick          -- keyboard sample, so b2kFrame sees this frame's edges
         b2kPlayerTick         -- reads the fresh edges, steers, picks the anim
         b2kSpritesTick        -- bound sprites follow bodies; animations advance
         b2kCamTick            -- viewport chases its target over the fresh locs
         b2kDispatchContacts
         b2kDispatchSensors
         if sFrameObj is not empty then dispatch "b2kFrame" to sFrameObj
      catch tErr               -- a user handler error must never freeze the screen
      end try
      unlock screen
   end if
   -- Pace the next step against what this frame consumed instead of a flat
   -- 16 ms scheduled AFTER the work: the flat delay made the real rate
   -- "timer cadence (~16.5 ms) plus frame cost", measured at ~50 fps under
   -- load in the Phase 0 spike. Clamp to 1..16 so a heavy frame reschedules
   -- immediately and an idle one never busy-loops.
   -- Reschedule with pGen (OUR generation), never the live sGen: if a user
   -- handler inside this frame tore the world down and restarted it (a
   -- level change from a sensor event), sGen is already the NEW loop's --
   -- rescheduling with it would clone the loop and double-step forever.
   -- With pGen, this stale instance's next tick fails the guard and dies.
   if sPaused is true then
      send ("b2kStep " & pGen) to me in 16 milliseconds
   else
      put 16 - (the milliseconds - tNow) into tNext
      if tNext < 1 then put 1 into tNext
      if tNext > 16 then put 16 into tNext
      send ("b2kStep " & pGen) to me in tNext milliseconds
   end if
end b2kStep

-- Advance exactly one fixed step, even while paused (drives a Step button).
/**
Summary: Advance the world exactly one fixed step.

Example:
b2kPause
b2kStepOnce

Description:
It works while paused, for a Step button or tests, and runs one
full frame: sync, input, player, sprites, camera, events and b2kFrame. It
does nothing unless the loop has been started.

References: b2kPause (handler), b2kStart (handler)
*/
command b2kStepOnce
   if not sRunning then exit b2kStepOnce
   b2kEventsReset
   b2Step sWorld, (1 / 60), sSub
   b2kHarvestEvents
   put 1000 / 60 into sFrameMS   -- a hand-stepped frame is one fixed step long
   if sDragging then
      b2MouseSetTarget sDragJoint, b2kToWorldX(b2kCamMouseX()), b2kToWorldY(b2kCamMouseY())
   end if
   lock screen
   try
      b2kSyncBodies
      b2kInputTick
      b2kPlayerTick
      b2kSpritesTick
      b2kCamTick
      b2kDispatchContacts
      b2kDispatchSensors
      if sFrameObj is not empty then dispatch "b2kFrame" to sFrameObj
   catch tErr
   end try
   unlock screen
end b2kStepOnce

-- Public, standalone-safe sync: locks the screen and always unlocks, even if a
-- draw throws. This is the "the loop is stopped, redraw by hand" entry point
-- (editors and build modes call it after spawning or moving things), so it must
-- FULL-SCAN: the move-event fast path only reports bodies a b2Step moved, and a
-- stopped world steps never - relying on it here would draw nothing at all.
-- The running loop instead holds one lock across the whole frame and calls the
-- lock-free, move-event-driven b2kSyncBodies directly.
/**
Summary: Redraw every awake, moving Kit body's control now.

Example:
b2kMoveTo tCrate, 300, 100
b2kSync

Description:
For a stopped or paused world, such as an editor, where no step
produces the move events the loop draws from. It holds one screen lock and
always releases it.

References: b2kSyncAll (handler), b2kSyncAllBodies (handler)
*/
command b2kSync
   lock screen
   try
      b2kSyncAllBodies
   catch tErr
   end try
   unlock screen
end b2kSync

/**
Summary: Redraw every awake, moving Kit body's control now.

Example:
b2kSyncAll

Description:
The same as <b2kSync>.

References: b2kSync (handler)
*/
command b2kSyncAll
   lock screen
   try
      b2kSyncAllBodies
   catch tErr
   end try
   unlock screen
end b2kSyncAll

-- Lock-free body sync (the caller owns the screen lock). Fast path: Box2D already
-- gives us the bodies that moved during the last step, so we use that event list
-- instead of scanning every tracked control and calling body-is-awake/x/y/angle
-- across the FFI for each one.
/**
Summary: Draw the bodies that moved in the last step.

Example:
b2kSyncBodies

Description:
Internal: the loop calls it under its screen lock. It reads
Box2D's move events, applies the kill floor, and forgets controls that
vanished.

References: b2kSyncAllBodies (handler), b2kKillFloor (handler)
*/
command b2kSyncBodies
   if sNeedFullSync is true then
      b2kSyncAllBodies
      put false into sNeedFullSync
      exit b2kSyncBodies
   end if

   local tN, i, tBody, tRef, tWx, tWy, tWa, tDead, tFell
   put empty into tDead
   put empty into tFell
   put b2BodiesUpdate(sWorld) into tN
   if tN <= 0 then exit b2kSyncBodies

   repeat with i = 1 to tN
      put b2BodyMoveBody(i) into tBody
      if tBody <= 0 then next repeat
      put sCtrl[tBody] into tRef
      if tRef is empty then next repeat
      if sStatic[tRef] is true then next repeat
      try
         put b2BodyMoveX(i) into tWx
         put b2BodyMoveY(i) into tWy
         -- the kill floor: a mover that fell below the line is queued for
         -- removal instead of drawn (the player is the game's to respawn).
         -- Zero extra scanning: falling bodies are, by definition, moving.
         if sKillY is not empty and tRef is not sPlayRef and b2kToScreenY(tWy) > sKillY then
            put tRef & cr after tFell
            next repeat
         end if
         if sRender[tRef] is "poly" or sRender[tRef] is "image" then
            put b2BodyMoveAngle(i) into tWa
         else
            put 0 into tWa
         end if
         b2kDrawBody tRef, tWx, tWy, tWa
      catch tErr
         put tRef & cr after tDead   -- control vanished; clean up below
      end try
   end repeat
   b2kPruneDeadRefs tDead
   repeat for each line tRef in tFell
      if tRef is empty then next repeat
      if sFrameObj is not empty then dispatch "b2kFell" to sFrameObj with tRef
      b2kRemove tRef
   end repeat
end b2kSyncBodies

-- Lock-free full scan (the caller owns the screen lock). Comprehensive fallback
-- for script-side edits that do not come from a Box2D step event (for example
-- changing a body type while paused).
/**
Summary: Draw every awake, non-static Kit body.

Example:
b2kSyncAllBodies

Description:
Internal: the caller holds the screen lock. <b2kSync> wraps it in one.

References: b2kSync (handler), b2kSyncBodies (handler)
*/
command b2kSyncAllBodies
   local tRef, tBody, tWx, tWy, tWa, tDead
   put empty into tDead
   repeat for each key tRef in sBody
      if sStatic[tRef] is true then next repeat
      put sBody[tRef] into tBody
      if b2BodyIsAwake(tBody) is false then next repeat   -- asleep = at rest, skip redraw
      try
         put b2BodyX(tBody) into tWx
         put b2BodyY(tBody) into tWy
         if sRender[tRef] is "poly" or sRender[tRef] is "image" then
            put b2BodyAngle(tBody) into tWa
         else
            put 0 into tWa
         end if
         b2kDrawBody tRef, tWx, tWy, tWa
      catch tErr
         put tRef & cr after tDead   -- control vanished; clean up below
      end try
   end repeat
   b2kPruneDeadRefs tDead
end b2kSyncAllBodies

/**
Summary: Forget controls that no longer exist.

pDead: Control references, one per line.

Example:
b2kPruneDeadRefs tGone

Description:
Internal: destroys each one's body and drops every record of it, as <b2kRemove> would.

References: b2kRemove (handler)
*/
command b2kPruneDeadRefs pDead
   local d, tBody
   repeat for each line d in pDead
      if d is not empty then
         put sBody[d] into tBody
         if tBody is not empty then
            b2DestroyBody tBody
            delete variable sCtrl[tBody]
         end if
         -- drop every parallel entry, exactly like b2kRemove, so a vanished
         -- control leaves no stale state behind
         delete variable sBody[d]
         delete variable sShapeH[d]
         delete variable sRender[d]
         delete variable sVerts[d]
         delete variable sRad[d]
         delete variable sImgAngle[d]
         delete variable sStatic[d]
         delete variable sSpawned[d]
         delete variable sSensor[d]
         delete variable sDrawKey[d]
         delete variable sInCam[d]
      end if
   end repeat
end b2kPruneDeadRefs

/**
Summary: Place a control at a body pose.

pRef: The control's long id.

pWx: The body's x, in metres.

pWy: The body's y, in metres.

pWa: The body's angle, in radians.

Example:
b2kDrawBody tRef, 2, 3, 0

Description:
Internal: picks the renderer for the control's kind and skips the write when nothing visible changed.

References: b2kDrawPoly (handler), b2kDrawBall (handler), b2kDrawImage (handler)
*/
command b2kDrawBody pRef, pWx, pWy, pWa
   local tSx, tSy, tKey
   switch sRender[pRef]
      case "poly"
         b2kDrawPoly pRef, pWx, pWy, pWa
         break
      case "ball"
         b2kDrawBall pRef, pWx, pWy
         break
      case "image"
         b2kDrawImage pRef, pWx, pWy, pWa
         break
      default
         put round(b2kToScreenX(pWx)) into tSx
         put round(b2kToScreenY(pWy)) into tSy
         put tSx & "," & tSy into tKey
         if sDrawKey[pRef] is tKey then exit b2kDrawBody
         set the loc of pRef to (tSx - b2kCamShiftX(pRef)) & "," & (tSy - b2kCamShiftY(pRef))
         put tKey into sDrawKey[pRef]
   end switch
end b2kDrawBody

/**
Summary: Redraw a polygon graphic at a body pose.

pRef: The control's long id.

pWx: The body's x, in metres.

pWy: The body's y, in metres.

pWa: The body's angle, in radians.

Example:
b2kDrawPoly tRef, 2, 3, 0.5

Description:
Internal: re-points the graphic from its stored outline.

References: b2kDrawBody (handler), b2kCorner (handler)
*/
command b2kDrawPoly pRef, pWx, pWy, pWa
   local c, s, p, pt, tPts, tFirst, tKey
   set the itemDelimiter to comma   -- locs and anchors are "x,y" (gotcha 5)
   put round(b2kToScreenX(pWx)) & "," & round(b2kToScreenY(pWy)) & "," & round(pWa * 1800 / kPI) into tKey
   if sDrawKey[pRef] is tKey then exit b2kDrawPoly
   put cos(pWa) into c
   put sin(pWa) into s
   put empty into tPts
   put empty into tFirst
   local tOffX, tOffY
   put b2kCamShiftX(pRef) into tOffX
   put b2kCamShiftY(pRef) into tOffY
   repeat for each line p in sVerts[pRef]
      put b2kCorner(pWx, pWy, item 1 of p, item 2 of p, c, s) into pt
      if tOffX is not 0 or tOffY is not 0 then
         put ((item 1 of pt) - tOffX) & "," & ((item 2 of pt) - tOffY) into pt
      end if
      if tFirst is empty then put pt into tFirst
      put pt & cr after tPts
   end repeat
   put tFirst after tPts
   set the points of pRef to tPts
   put tKey into sDrawKey[pRef]
end b2kDrawPoly

/**
Summary: Redraw a ball graphic at a body position.

pRef: The control's long id.

pWx: The body's x, in metres.

pWy: The body's y, in metres.

Example:
b2kDrawBall tRef, 2, 3

Description:
Internal: sets the graphic's rect from the stored radius.

References: b2kDrawBody (handler)
*/
command b2kDrawBall pRef, pWx, pWy
   local tRp, tSx, tSy, tKey
   put sRad[pRef] * sScale into tRp
   put round(b2kToScreenX(pWx)) into tSx
   put round(b2kToScreenY(pWy)) into tSy
   put tSx & "," & tSy & "," & round(tRp) into tKey
   if sDrawKey[pRef] is tKey then exit b2kDrawBall
   subtract b2kCamShiftX(pRef) from tSx
   subtract b2kCamShiftY(pRef) from tSy
   set the rect of pRef to round(tSx - tRp), round(tSy - tRp), round(tSx + tRp), round(tSy + tRp)
   put tKey into sDrawKey[pRef]
end b2kDrawBall

-- Position + rotate an image control to follow its body. The body angle is in
-- radians, CCW-positive in the sim's y-up frame; with this kit's y-flip that is
-- also a CCW screen rotation, which matches `the angle` (CCW-positive). We keep
-- the image at its design size and skip redundant re-rotations (each set of the
-- angle resamples the image, but always from the original, so there's no drift).
/**
Summary: Move and rotate an image to a body pose.

pRef: The control's long id.

pWx: The body's x, in metres.

pWy: The body's y, in metres.

pWa: The body's angle, in radians.

Example:
b2kDrawImage tRef, 2, 3, 0.5

Description:
Internal: sets the image's angle in whole degrees and its location; the image keeps its design size.

References: b2kDrawBody (handler)
*/
command b2kDrawImage pRef, pWx, pWy, pWa
   local tDeg, tSx, tSy, tKey
   put ((round(pWa * 180 / kPI) mod 360) + 360) mod 360 into tDeg
   put round(b2kToScreenX(pWx)) into tSx
   put round(b2kToScreenY(pWy)) into tSy
   put tSx & "," & tSy & "," & tDeg into tKey
   if sDrawKey[pRef] is tKey then exit b2kDrawImage
   if sImgAngle[pRef] is not tDeg then
      set the angle of pRef to tDeg
      put tDeg into sImgAngle[pRef]
   end if
   set the loc of pRef to (tSx - b2kCamShiftX(pRef)) & "," & (tSy - b2kCamShiftY(pRef))
   put tKey into sDrawKey[pRef]
end b2kDrawImage

/**
Summary: One outline corner in screen pixels.

pWx: The body's x, in metres.

pWy: The body's y, in metres.

pLx: The corner's local x, in metres.

pLy: The corner's local y, in metres.

c: The cosine of the body's angle.

s: The sine of the body's angle.

Returns: "x,y" in rounded screen pixels.

Example:
put b2kCorner(2, 3, 0.5, 0.5, 1, 0) into tPoint

References: b2kDrawPoly (handler)
*/
function b2kCorner pWx, pWy, pLx, pLy, c, s
   local rx, ry
   put pLx * c - pLy * s into rx
   put pLx * s + pLy * c into ry
   return round(b2kToScreenX(pWx + rx)) & "," & round(b2kToScreenY(pWy + ry))
end b2kCorner

-- Local-space outline (metres) approximating a capsule of half-length pL and
-- radius pR: two half-circle caps joined by straight edges. Built along local X
-- and transposed to local Y when the capsule is vertical. Used only to draw the
-- graphic; the collision shape is a true Box2D capsule.
/**
Summary: The local outline the Kit draws a capsule with.

pL: The capsule's half-length, in metres.

pR: The radius, in metres.

pHoriz: true for a horizontal capsule, false for vertical.

Returns: 18 local points in metres, one "x,y" per line.

Example:
put b2kCapsuleVerts(0.5, 0.3, false) into tOutline

Description:
Drawing only: the collision shape is a true capsule.

References: b2kAddCapsule (handler)
*/
function b2kCapsuleVerts pL, pR, pHoriz
   local tV, i, a, lx, ly
   local n
   put 8 into n
   put empty into tV
   repeat with i = 0 to n               -- right cap: -90 -> +90 degrees
      put (-90 + 180 * i / n) * kPI / 180 into a
      put pL + pR * cos(a) into lx
      put pR * sin(a) into ly
      if pHoriz then put lx & "," & ly & cr after tV
      else put ly & "," & lx & cr after tV
   end repeat
   repeat with i = 0 to n               -- left cap: +90 -> +270 degrees
      put (90 + 180 * i / n) * kPI / 180 into a
      put - pL + pR * cos(a) into lx
      put pR * sin(a) into ly
      if pHoriz then put lx & "," & ly & cr after tV
      else put ly & "," & lx & cr after tV
   end repeat
   return tV
end b2kCapsuleVerts

-- Internal: zero the frame's event buffers (the loop calls this before
-- it steps; the buffers then accumulate one harvest per fixed step).
/**
Summary: Zero this frame's event counts.

Example:
b2kEventsReset

Description:
Internal: the loop calls it before stepping. The event readers check the counts, so old entries are never returned.

References: b2kHarvestEvents (handler)
*/
command b2kEventsReset
   put 0 into sEvtCN
   put 0 into sEvtEN
   put 0 into sEvtSN
   put 0 into sEvtXN
end b2kEventsReset

-- Internal: pull THIS step's Box2D events into the frame buffers. Box2D
-- keeps only the latest step's events, so this must run after every
-- b2Step -- the dispatchers and pollers then see the whole frame.
/**
Summary: Collect the last step's contact and sensor events.

Example:
b2kHarvestEvents

Description:
Internal: runs after every fixed step, because Box2D keeps only the latest step's events.

References: b2kEventsReset (handler), b2kContactCount (handler)
*/
command b2kHarvestEvents
   local tN, i
   put b2ContactsUpdate(sWorld) into tN
   repeat with i = 1 to tN
      add 1 to sEvtCN
      put b2ContactBeginBodyA(i) into sEvtCA[sEvtCN]
      put b2ContactBeginBodyB(i) into sEvtCB[sEvtCN]
   end repeat
   repeat with i = 1 to b2ContactEndCount()
      add 1 to sEvtEN
      put b2ContactEndBodyA(i) into sEvtEA[sEvtEN]
      put b2ContactEndBodyB(i) into sEvtEB[sEvtEN]
   end repeat
   put b2SensorsUpdate(sWorld) into tN
   repeat with i = 1 to tN
      add 1 to sEvtSN
      put b2ShapeBody(b2SensorBeginSensorShape(i)) into sEvtSS[sEvtSN]
      put b2ShapeBody(b2SensorBeginVisitorShape(i)) into sEvtSV[sEvtSN]
   end repeat
   repeat with i = 1 to b2SensorEndCount()
      add 1 to sEvtXN
      put b2ShapeBody(b2SensorEndSensorShape(i)) into sEvtXS[sEvtXN]
      put b2ShapeBody(b2SensorEndVisitorShape(i)) into sEvtXV[sEvtXN]
   end repeat
end b2kHarvestEvents

/**
Summary: Send this frame's contact messages.

Example:
b2kDispatchContacts

Description:
Internal: sends b2kContact and b2kEndContact to the contact target, in step order. No target, no messages.

References: b2kContactTarget (handler), b2kDispatchSensors (handler)
*/
command b2kDispatchContacts
   local i, tA, tB
   if sContactObj is empty then exit b2kDispatchContacts
   repeat with i = 1 to sEvtCN
      put sCtrl[sEvtCA[i]] into tA
      put sCtrl[sEvtCB[i]] into tB
      dispatch "b2kContact" to sContactObj with tA, tB
   end repeat
   repeat with i = 1 to sEvtEN
      put sCtrl[sEvtEA[i]] into tA
      put sCtrl[sEvtEB[i]] into tB
      dispatch "b2kEndContact" to sContactObj with tA, tB
   end repeat
end b2kDispatchContacts

-- Deliver the frame's buffered sensor begin/end overlaps (if a target is
-- set) as on b2kSensorEnter / on b2kSensorExit, in step order.
/**
Summary: Send this frame's sensor messages.

Example:
b2kDispatchSensors

Description:
Internal: sends b2kSensorEnter and b2kSensorExit to the contact target, in step order. No target, no messages.

References: b2kContactTarget (handler), b2kDispatchContacts (handler)
*/
command b2kDispatchSensors
   local i, tS, tV
   if sContactObj is empty then exit b2kDispatchSensors
   repeat with i = 1 to sEvtSN
      put sCtrl[sEvtSS[i]] into tS
      put sCtrl[sEvtSV[i]] into tV
      dispatch "b2kSensorEnter" to sContactObj with tS, tV
   end repeat
   repeat with i = 1 to sEvtXN
      put sCtrl[sEvtXS[i]] into tS
      put sCtrl[sEvtXV[i]] into tV
      dispatch "b2kSensorExit" to sContactObj with tS, tV
   end repeat
end b2kDispatchSensors
