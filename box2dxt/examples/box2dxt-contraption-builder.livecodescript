-- #####################################################################
-- #  Box2Dxt  -  CONTRAPTION BUILDER  (Kit + builder GUI in one file) #
-- #                                                                   #
-- #  An interactive sandbox. Drop parts (boxes, balls, capsules,      #
-- #  polygons, imported images and static anchors), wire them up with #
-- #  joints (hinge, weld, rope, slider, wheel), add motors, then      #
-- #  press Run to simulate. It shows how little xTalk it takes to      #
-- #  build a working machine with Box2Dxt.                            #
-- #                                                                   #
-- #  HOW TO RUN                                                       #
-- #   1. Load the box2dxt.lcb extension and put the box2dxt native    #
-- #      library where it can be found. Check: put b2Version()  -- 4  #
-- #   2. Paste THIS WHOLE FILE into a stack's script                  #
-- #      (Object > Stack Script).                                     #
-- #   3. Open/close the card, or run  startCB  in the Message Box.    #
-- #      Stop with  stopCB.                                           #
-- #                                                                   #
-- #  This file bundles a verbatim copy of the reusable Kit            #
-- #  (src/box2dxt-kit.livecodescript) so it runs from a single paste. #
-- #  For your own projects, load the Kit on its own instead.          #
-- #                                                                   #
-- #  Targets OpenXTalk / LiveCode 9.6.3. LiveCode naming throughout:  #
-- #  p* params, t* locals, g* script-locals, k* constants, u* custom  #
-- #  properties, so nothing collides with reserved words.             #
-- #####################################################################

-- =====================================================================
-- EMBEDDED KIT  /  auto-generated copy of src/box2dxt-kit.livecodescript
--
-- This file is self-contained: paste the whole thing into one stack script
-- and it runs.  The Kit below is a GENERATED copy - do not edit it here.
-- Edit the canonical Kit at src/box2dxt-kit.livecodescript, then run:
--     python3 tools/sync-embedded-kit.py
-- (CI checks it stays in sync via:  tools/sync-embedded-kit.py --check)
-- =====================================================================
-- >>> BEGIN EMBEDDED KIT >>>
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

-- =====================================================================
-- World / lifecycle
-- =====================================================================
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
command b2kQuickStart pGravityY
   b2kSetup 0, pGravityY
   b2kAddWalls
   b2kStart
end b2kQuickStart

command b2kStart
   if sWorld is empty then b2kSetup
   put true into sRunning
   put false into sPaused
   put 0 into sAccum
   put the milliseconds into sLast
   put the milliseconds & "_" & random(1000000) into sGen
   send ("b2kStep " & sGen) to me in 16 milliseconds
end b2kStart

command b2kStop
   put false into sRunning
   put the milliseconds & random(9999) into sGen
end b2kStop

command b2kPause
   put true into sPaused
end b2kPause

command b2kResume
   put false into sPaused
   put the milliseconds into sLast
end b2kResume

function b2kIsRunning
   return (sRunning is true) and (sPaused is not true)
end b2kIsRunning

-- Static, invisible walls along the four card edges.
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

command b2kEdge pWx1, pWy1, pWx2, pWy2
   local tBody
   if sWorld is empty then exit b2kEdge   -- no world yet: a wall is a quiet no-op
   put b2NewStaticBody(sWorld, 0, 0) into tBody
   get b2AddSegment(tBody, pWx1, pWy1, pWx2, pWy2, 0.6, 0.1)
end b2kEdge

-- A wide invisible ground line at screen height pScreenY (default: near bottom).
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
command b2kKillFloor pScreenY
   put pScreenY into sKillY
end b2kKillFloor

command b2kWall pX1, pY1, pX2, pY2
   b2kEdge b2kToWorldX(pX1), b2kToWorldY(pY1), b2kToWorldX(pX2), b2kToWorldY(pY2)
end b2kWall

-- Remove every dynamic body (b2kRemove deletes kit-spawned controls; attached
-- controls are just detached). Sprites are Kit-created controls, so they go
-- too; loaded sheets stay (they are assets, not world state).
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
function b2kNumberOr pValue, pDefault
   if pValue is empty then return pDefault
   if pValue is not a number then return pDefault
   return pValue
end b2kNumberOr

function b2kClamp pValue, pLo, pHi
   local tValue
   put b2kNumberOr(pValue, pLo) into tValue
   if tValue < pLo then put pLo into tValue
   if tValue > pHi then put pHi into tValue
   return tValue
end b2kClamp

command b2kSetScale pPixelsPerMetre
   put b2kClamp(pPixelsPerMetre, 1, 10000) into sScale
end b2kSetScale

command b2kSetOrigin pScreenX, pScreenY
   put b2kNumberOr(pScreenX, sOriginX) into sOriginX
   put b2kNumberOr(pScreenY, sOriginY) into sOriginY
end b2kSetOrigin

command b2kSetGravity pGx, pGy
   put b2kNumberOr(pGx, 0) into pGx
   put b2kNumberOr(pGy, -10) into pGy
   if sWorld is not empty then b2SetGravity sWorld, pGx, pGy
end b2kSetGravity

command b2kSetSubsteps pN
   put round(b2kClamp(pN, 1, 64)) into sSub
end b2kSetSubsteps

-- World toggles: island sleeping (saves CPU) and continuous collision (CCD,
-- stops fast bodies tunnelling through thin walls).
command b2kEnableSleeping pFlag
   if sWorld is not empty then b2EnableSleeping sWorld, (pFlag is true)
end b2kEnableSleeping

command b2kEnableContinuous pFlag
   if sWorld is not empty then b2EnableContinuous sWorld, (pFlag is true)
end b2kEnableContinuous

command b2kContactTarget pObject
   put pObject into sContactObj
end b2kContactTarget

-- Object that receives an `on b2kFrame` message once per simulated frame (after
-- bodies are synced). Use it for per-frame logic: motors, custom drawing, input.
command b2kFrameTarget pObject
   put pObject into sFrameObj
end b2kFrameTarget

function b2kWorld
   return sWorld
end b2kWorld

-- Sanity check from kit-only code: returns the native shim's ABI version (4),
-- i.e. that the box2dxt extension and its native library are loaded and in sync.
function b2kVersion
   return b2Version()
end b2kVersion

-- =====================================================================
-- Coordinate conversion (sim Y up; screen Y down)
-- =====================================================================
function b2kToScreenX pWx
   return sOriginX + pWx * sScale
end b2kToScreenX

function b2kToScreenY pWy
   return sOriginY - pWy * sScale
end b2kToScreenY

function b2kToWorldX pSx
   if sScale is empty or sScale = 0 then return 0   -- before b2kSetup: stay safe
   return (pSx - sOriginX) / sScale
end b2kToWorldX

function b2kToWorldY pSy
   if sScale is empty or sScale = 0 then return 0
   return (sOriginY - pSy) / sScale
end b2kToWorldY

-- =====================================================================
-- Attaching existing controls (pDynamic defaults to true)
-- =====================================================================
command b2kAddBox pControl, pDynamic
   local tRef, tType, tFixed, tBody, tHw, tHh, tWx, tWy, tGraphic, tImage
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

command b2kAddBall pControl, pDynamic
   local tRef, tType, tBody, tRad, tWx, tWy
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
command b2kAddCapsule pControl, pDynamic
   local tRef, tType, tFixed, tBody, tWx, tWy, tWm, tHm, tR, tL, tHoriz, tGraphic, tImage
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
command b2kAddPolygon pControl, pDynamic
   local tRef, tType, tBody, tCx, tCy, tWx, tWy, tPoints, p, tLocal, lx, ly, tCount
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

command b2kAddStatic pControl
   b2kAddBox pControl, false
end b2kAddStatic

command b2kRegister pRef, pBody, pIsStatic
   put pBody into sBody[pRef]
   put pRef into sCtrl[pBody]
   put (pIsStatic is true) into sStatic[pRef]
end b2kRegister

-- =====================================================================
-- Spawning new controls (create + attach in one call). Returns control ref.
-- =====================================================================
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
command b2kSetBounce pControl, pRestitution
   local s
   put sShapeH[the long id of pControl] into s
   put b2kClamp(pRestitution, 0, 2) into pRestitution
   if s is not empty then b2SetShapeRestitution s, pRestitution
end b2kSetBounce

command b2kSetFriction pControl, pFriction
   local s
   put sShapeH[the long id of pControl] into s
   put b2kClamp(pFriction, 0, 10) into pFriction
   if s is not empty then b2SetShapeFriction s, pFriction
end b2kSetFriction

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
command b2kReshape pControl, pShape, pW, pH
   local tRef, tBody, tOld, tHw, tHh, tWm, tHm, tR, tL, tHoriz, tCx, tCy, p, lx, ly, tCount, tNewVerts
   local tWx, tWy, tWa
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
command b2kSetBullet pControl, pFlag
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetBullet
   b2SetBullet b, (pFlag is true)
end b2kSetBullet

command b2kSetFixedRotation pControl, pFlag
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetFixedRotation
   b2SetFixedRotation b, (pFlag is true)
end b2kSetFixedRotation

command b2kSetGravityScale pControl, pScale
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetGravityScale
   b2SetGravityScale b, pScale
end b2kSetGravityScale

command b2kSetDamping pControl, pLinear, pAngular
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetDamping
   if pLinear is not empty then b2SetLinearDamping b, pLinear
   if pAngular is not empty then b2SetAngularDamping b, pAngular
end b2kSetDamping

command b2kWake pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kWake
   b2SetAwake b, true
end b2kWake

-- Send a body to sleep (it stops simulating until something wakes it).
command b2kSleep pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSleep
   b2SetAwake b, false
end b2kSleep

-- Allow or forbid THIS body ever falling asleep (vs b2kEnableSleeping,
-- which switches the whole world). The player controller forbids it: a
-- character must respond to input even after standing still for minutes.
command b2kSetSleepEnabled pControl, pFlag
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetSleepEnabled
   b2EnableSleep b, (pFlag is true)
   if pFlag is not true then b2SetAwake b, true
end b2kSetSleepEnabled

-- Below this speed (pixels/sec) a body may fall asleep. Lower = stays awake
-- longer; higher = sleeps sooner (saves CPU).
command b2kSetSleepThreshold pControl, pPxPerSec
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetSleepThreshold
   b2SetSleepThreshold b, pPxPerSec / sScale
end b2kSetSleepThreshold

-- =====================================================================
-- Acting on bodies   (velocities/kicks are in PIXELS/sec, screen-oriented)
-- =====================================================================
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

command b2kPush pControl, pDvxPx, pDvyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kPush
   b2SetVelocity b, b2BodyVX(b) + pDvxPx / sScale, b2BodyVY(b) - pDvyPx / sScale
   b2SetAwake b, true
end b2kPush

command b2kSpin pControl, pDegPerSec
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSpin
   b2SetAngularVelocity b, pDegPerSec * kPI / 180
end b2kSpin

-- Add to the current spin (vs b2kSpin which sets it absolutely).
command b2kSpinBy pControl, pDegPerSec
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSpinBy
   b2SetAngularVelocity b, b2BodyAngularVelocity(b) + pDegPerSec * kPI / 180
   b2SetAwake b, true
end b2kSpinBy

-- Continuous, screen-oriented force (thrusters, wind). Apply each frame for a
-- sustained effect; b2kPush is the one-shot impulse equivalent.
command b2kForce pControl, pFxPx, pFyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kForce
   b2ApplyForce b, pFxPx / sScale, - pFyPx / sScale, true
end b2kForce

-- A one-shot impulse (a sharp kick), screen-oriented. Mass-aware: heavier bodies
-- move less. b2kPush changes velocity directly; this is the impulse equivalent.
command b2kImpulse pControl, pIxPx, pIyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kImpulse
   b2ApplyImpulse b, pIxPx / sScale, - pIyPx / sScale, true
end b2kImpulse

-- A continuous turning force (same units as motor torque). Positive turns one way,
-- negative the other. Apply each frame for a sustained twist; pairs with b2kForce.
command b2kTorque pControl, pTorque
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kTorque
   b2ApplyTorque b, pTorque, true
end b2kTorque

-- A one-shot twist (a sharp angular kick), mass-aware: bodies with more
-- rotational inertia turn less. b2kSpinBy sets the spin directly; this is the
-- impulse equivalent, and the angular partner of b2kImpulse.
command b2kAngularImpulse pControl, pImpulse
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kAngularImpulse
   b2ApplyAngularImpulse b, pImpulse, true
end b2kAngularImpulse

-- Change a body's type at runtime: "static", "kinematic", or "dynamic".
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

command b2kSetStatic pControl
   b2kSetType pControl, "static"
end b2kSetStatic

command b2kSetDynamic pControl
   b2kSetType pControl, "dynamic"
end b2kSetDynamic

command b2kSetKinematic pControl
   b2kSetType pControl, "kinematic"
end b2kSetKinematic

-- Temporarily take a body out of / put it back into the simulation.
command b2kDisable pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kDisable
   b2DisableBody b
end b2kDisable

command b2kEnable pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kEnable
   b2EnableBody b
   put true into sNeedFullSync
end b2kEnable

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
command b2kExplode pScreenX, pScreenY, pRadiusPx, pPowerPx
   if pRadiusPx is empty then put 180 into pRadiusPx
   if pPowerPx is empty then put 900 into pPowerPx
   if sWorld is empty then exit b2kExplode
   b2WorldExplode sWorld, b2kToWorldX(pScreenX), b2kToWorldY(pScreenY), \
         pRadiusPx / sScale, (pRadiusPx / sScale) * 0.5, pPowerPx / sScale
end b2kExplode

-- The original velocity-based blast (pre-v3): kicks only kit-tracked dynamic
-- bodies, ignoring their size. Kept for callers that relied on the old feel.
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
function b2kBodyOf pControl
   return sBody[the long id of pControl]
end b2kBodyOf

-- A body's position in SCREEN pixels as "x,y" (the position partner of
-- b2kVelocity). Controls already follow their body, but this reads the exact,
-- sub-pixel centre - handy for aiming, distance checks, or mixing with b2...
function b2kPosition pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return b2kToScreenX(b2BodyX(b)) & "," & b2kToScreenY(b2BodyY(b))
end b2kPosition

-- A body's centre of mass in SCREEN pixels as "x,y". Differs from b2kPosition
-- for off-centre or compound shapes; it's the true pivot for spin and torque.
function b2kWorldCenter pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return b2kToScreenX(b2BodyWorldCenterX(b)) & "," & b2kToScreenY(b2BodyWorldCenterY(b))
end b2kWorldCenter

function b2kVelocity pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return (b2BodyVX(b) * sScale) & "," & (- b2BodyVY(b) * sScale)
end b2kVelocity

function b2kSpeed pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return sqrt((b2BodyVX(b) * sScale) ^ 2 + (b2BodyVY(b) * sScale) ^ 2)
end b2kSpeed

function b2kAngle pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyAngle(b) * 180 / kPI
end b2kAngle

function b2kIsAwake pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return false
   return b2BodyIsAwake(b)
end b2kIsAwake

-- Current rotation speed in DEGREES/sec (the getter for b2kSpin / b2kSpinBy).
function b2kSpinRate pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyAngularVelocity(b) * 180 / kPI
end b2kSpinRate

function b2kIsBullet pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return false
   return b2BodyIsBullet(b)
end b2kIsBullet

function b2kIsEnabled pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return false
   return b2BodyIsEnabled(b)
end b2kIsEnabled

function b2kMass pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyMass(b)
end b2kMass

-- The body's per-body gravity multiplier (the getter for b2kSetGravityScale).
function b2kGravityScale pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyGravityScale(b)
end b2kGravityScale

-- The body's drag as "linear,angular" (the getter for b2kSetDamping).
function b2kDamping pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return b2BodyLinearDamping(b) & "," & b2BodyAngularDamping(b)
end b2kDamping

-- Body type as a word: "static", "kinematic", or "dynamic" (mirrors b2kSetType).
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
function b2kBodyCount
   return the number of lines of the keys of sBody
end b2kBodyCount

-- How many dynamic bodies are currently awake (i.e. actively simulating).
function b2kAwakeCount
   local tRef, tCount
   put 0 into tCount
   repeat for each key tRef in sBody
      if sStatic[tRef] is not true and b2BodyIsAwake(sBody[tRef]) then add 1 to tCount
   end repeat
   return tCount
end b2kAwakeCount

-- Which attached control sits at a screen point (empty if none).
function b2kControlAt pScreenX, pScreenY
   if sWorld is empty then return empty
   return sCtrl[b2BodyAtPoint(sWorld, b2kToWorldX(pScreenX), b2kToWorldY(pScreenY))]
end b2kControlAt

-- True if SCREEN point (x,y) is inside this control's actual collision shape -
-- rotation- and shape-aware, unlike a bounding-box test. b2kControlAt searches
-- every body; this tests one control you already have (e.g. a precise click hit).
function b2kControlContains pControl, pScreenX, pScreenY
   local tRef
   put the long id of pControl into tRef
   if sShapeH[tRef] is empty then return false
   return b2ShapeTestPoint(sShapeH[tRef], b2kToWorldX(pScreenX), b2kToWorldY(pScreenY))
end b2kControlContains

-- Cast a ray between two screen points; returns the control hit (or empty).
-- Then b2kRayHitX() / b2kRayHitY() give the hit point in screen pixels.
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

function b2kRayHitX
   return sRayX
end b2kRayHitX

function b2kRayHitY
   return sRayY
end b2kRayHitY

-- Surface normal (a unit direction, screen-oriented) at the last ray hit.
function b2kRayHitNormalX
   return sRayNX
end b2kRayHitNormalX

function b2kRayHitNormalY
   return sRayNY
end b2kRayHitNormalY

-- Distance in pixels from the ray's start to the last hit point.
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
function b2kContactCount
   if sEvtCN is empty then return 0
   return sEvtCN
end b2kContactCount

function b2kContactA pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtCN then return empty
   return sCtrl[sEvtCA[pIndex]]
end b2kContactA

function b2kContactB pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtCN then return empty
   return sCtrl[sEvtCB[pIndex]]
end b2kContactB

function b2kEndContactCount
   if sEvtEN is empty then return 0
   return sEvtEN
end b2kEndContactCount

function b2kEndContactA pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtEN then return empty
   return sCtrl[sEvtEA[pIndex]]
end b2kEndContactA

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
command b2kHinge pCtrlA, pCtrlB, pScreenX, pScreenY
   local bA, bB, wx, wy, aA, aB, j
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

command b2kWeld pCtrlA, pCtrlB
   local bA, bB, wx, wy, aA, refA, j
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

command b2kMotor pJoint, pDegPerSec, pMaxTorque
   if pJoint is empty or pJoint <= 0 then exit b2kMotor
   if pMaxTorque is empty then put 1000 into pMaxTorque
   b2RevoluteEnableMotor pJoint, true, pDegPerSec * kPI / 180, pMaxTorque
end b2kMotor

-- Optional revolute (hinge) limits/readout. Angles are in DEGREES.
command b2kHingeLimit pJoint, pLowerDeg, pUpperDeg
   if pJoint is empty or pJoint <= 0 then exit b2kHingeLimit
   b2RevoluteEnableLimit pJoint, true, pLowerDeg * kPI / 180, pUpperDeg * kPI / 180
end b2kHingeLimit

function b2kHingeAngle pJoint
   if pJoint is empty or pJoint <= 0 then return 0
   return b2RevoluteAngle(pJoint) * 180 / kPI
end b2kHingeAngle

-- Rope (distance) extras: read length, set a min/max range, make it springy.
function b2kRopeLength pJoint
   if pJoint is empty or pJoint <= 0 then return 0
   return b2DistanceLength(pJoint) * sScale
end b2kRopeLength

-- Set a rope (distance) joint's exact rest length, in pixels.
command b2kRopeSetLength pJoint, pLengthPx
   if pJoint is empty or pJoint <= 0 then exit b2kRopeSetLength
   b2DistanceSetLength pJoint, pLengthPx / sScale
end b2kRopeSetLength

command b2kRopeRange pJoint, pMinPx, pMaxPx
   if pJoint is empty or pJoint <= 0 then exit b2kRopeRange
   b2DistanceSetLengthRange pJoint, pMinPx / sScale, pMaxPx / sScale
end b2kRopeRange

command b2kSpring pJoint, pHertz, pDamping
   if pJoint is empty or pJoint <= 0 then exit b2kSpring
   if pDamping is empty then put 0.5 into pDamping
   b2DistanceEnableSpring pJoint, true, pHertz, pDamping
end b2kSpring

-- Make a weld springy (0 hertz = rigid again).
command b2kWeldSpring pJoint, pHertz, pDamping
   if pJoint is empty or pJoint <= 0 then exit b2kWeldSpring
   if pDamping is empty then put 0.5 into pDamping
   b2WeldSetStiffness pJoint, pHertz, pDamping, pHertz, pDamping
end b2kWeldSpring

-- Slider (prismatic): constrain pCtrlA to slide along an axis relative to
-- pCtrlB (or the world if empty). pAxisDeg is the on-screen slide direction
-- (0 = horizontal, 90 = vertical; default vertical). Drive it with b2kSliderMotor.
command b2kSlider pCtrlA, pCtrlB, pAxisDeg
   local bMover, bFixed, wax, way, ca, sa, lax, lay, anchX, anchY, aFix, aMov, refA, fixAng, j
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

command b2kSliderMotor pJoint, pPxPerSec, pMaxForce
   if pJoint is empty or pJoint <= 0 then exit b2kSliderMotor
   if pMaxForce is empty then put 1000 into pMaxForce
   b2PrismaticEnableMotor pJoint, true, pPxPerSec / sScale, pMaxForce
end b2kSliderMotor

command b2kSliderLimit pJoint, pLowerPx, pUpperPx
   if pJoint is empty or pJoint <= 0 then exit b2kSliderLimit
   b2PrismaticEnableLimit pJoint, true, pLowerPx / sScale, pUpperPx / sScale
end b2kSliderLimit

function b2kSliderPos pJoint
   if pJoint is empty or pJoint <= 0 then return 0
   return b2PrismaticTranslation(pJoint) * sScale
end b2kSliderPos

-- Wheel: a sprung sliding axis + free spin (vehicle wheels). pChassis carries
-- pWheel; anchor defaults to the wheel's centre, suspension axis to world "up".
-- Drive with b2kWheelMotor, tune ride with b2kWheelSpring.
command b2kWheel pChassis, pWheel, pScreenX, pScreenY, pAxisDeg
   local bA, bB, anchX, anchY, aA, aB, wax, way, ca, sa, lax, lay, angA, j
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

command b2kWheelMotor pJoint, pDegPerSec, pMaxTorque
   if pJoint is empty or pJoint <= 0 then exit b2kWheelMotor
   if pMaxTorque is empty then put 1000 into pMaxTorque
   b2WheelEnableMotor pJoint, true, pDegPerSec * kPI / 180, pMaxTorque
end b2kWheelMotor

command b2kWheelSpring pJoint, pHertz, pDamping
   if pJoint is empty or pJoint <= 0 then exit b2kWheelSpring
   if pHertz is empty then put 4 into pHertz
   if pDamping is empty then put 0.7 into pDamping
   b2WheelEnableSpring pJoint, true, pHertz, pDamping
end b2kWheelSpring

-- OFF switches: the b2k... joint wrappers above only ever turn a feature ON, so
-- these let callers disable a motor or limit again (free swing / unbounded slide).
command b2kMotorOff pJoint
   if pJoint is not empty and pJoint > 0 then b2RevoluteEnableMotor pJoint, false, 0, 0
end b2kMotorOff

command b2kHingeLimitOff pJoint
   if pJoint is not empty and pJoint > 0 then b2RevoluteEnableLimit pJoint, false, 0, 0
end b2kHingeLimitOff

command b2kSliderMotorOff pJoint
   if pJoint is not empty and pJoint > 0 then b2PrismaticEnableMotor pJoint, false, 0, 0
end b2kSliderMotorOff

command b2kSliderLimitOff pJoint
   if pJoint is not empty and pJoint > 0 then b2PrismaticEnableLimit pJoint, false, 0, 0
end b2kSliderLimitOff

command b2kWheelMotorOff pJoint
   if pJoint is not empty and pJoint > 0 then b2WheelEnableMotor pJoint, false, 0, 0
end b2kWheelMotorOff

command b2kRemoveJoint pJoint
   if pJoint is not empty and pJoint > 0 then b2DestroyJoint pJoint
end b2kRemoveJoint

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
command b2kSetSensor pControl, pFlag
   put (pFlag is true) into sSensor[the long id of pControl]
end b2kSetSensor

-- Polling alternative to the on b2kSensorEnter/Exit messages (read in on b2kFrame).
-- Counts/indices are 1-based; each returns a control (empty for untracked bodies).
function b2kSensorCount
   if sEvtSN is empty then return 0
   return sEvtSN
end b2kSensorCount
function b2kSensorEnterSensor pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtSN then return empty
   return sCtrl[sEvtSS[pIndex]]
end b2kSensorEnterSensor
function b2kSensorEnterVisitor pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtSN then return empty
   return sCtrl[sEvtSV[pIndex]]
end b2kSensorEnterVisitor
function b2kSensorExitCount
   if sEvtXN is empty then return 0
   return sEvtXN
end b2kSensorExitCount
function b2kSensorExitSensor pIndex
   -- ENGINE-FOUND 2026-08-16 (on the EndContact pair, fixed as a family):
   -- b2kEventsReset zeroes the COUNTS and leaves the entry arrays, so an
   -- out-of-range index answered the STALE control from the last real
   -- event instead of empty. The count is the contract; hold it here so
   -- every path that zeroes a count is covered at once.
   if pIndex < 1 or pIndex > sEvtXN then return empty
   return sCtrl[sEvtXS[pIndex]]
end b2kSensorExitSensor
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
function b2kOverlapCircle pX, pY, pRadiusPx
   if sWorld is empty then return empty
   return b2kQueryToControls(b2OverlapCircle(sWorld, b2kToWorldX(pX), b2kToWorldY(pY), pRadiusPx / sScale))
end b2kOverlapCircle

-- Every control a ray crosses, nearest-first (vs b2kRayHit's single closest).
function b2kRayHitAll pX1, pY1, pX2, pY2
   if sWorld is empty then return empty
   return b2kQueryToControls(b2RayCastAll(sWorld, b2kToWorldX(pX1), b2kToWorldY(pY1), b2kToWorldX(pX2), b2kToWorldY(pY2)))
end b2kRayHitAll

-- Shared: turn the current query result (count) into a newline list of controls.
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
command b2kSetRestitutionThreshold pPxPerSec
   if sWorld is not empty then b2SetRestitutionThreshold sWorld, pPxPerSec / sScale
end b2kSetRestitutionThreshold

-- Contact softness: stiffness (hertz), damping ratio, max separation-fix speed (px/sec).
command b2kSetContactTuning pHertz, pDamping, pPushPx
   if sWorld is not empty then b2SetContactTuning sWorld, pHertz, pDamping, pPushPx / sScale
end b2kSetContactTuning

command b2kSetJointTuning pHertz, pDamping
   if sWorld is not empty then b2SetJointTuning sWorld, pHertz, pDamping
end b2kSetJointTuning

-- Clamp how fast any body can move (px/sec) - stops runaway speeds.
command b2kSetMaxSpeed pPxPerSec
   if sWorld is not empty then b2SetMaximumLinearSpeed sWorld, pPxPerSec / sScale
end b2kSetMaxSpeed

command b2kEnableWarmStarting pFlag
   if sWorld is not empty then b2EnableWarmStarting sWorld, (pFlag is true)
end b2kEnableWarmStarting

-- A quick perf readout in milliseconds: "totalStep,collide,solve" for the last step.
function b2kProfile
   if sWorld is empty then return empty
   b2WorldProfileUpdate sWorld
   return b2WorldProfileStep() & "," & b2WorldProfileCollide() & "," & b2WorldProfileSolve()
end b2kProfile

-- How many dynamic bodies are awake right now (native count, vs b2kAwakeCount).
function b2kAwakeBodyCount
   if sWorld is empty then return 0
   return b2AwakeBodyCount(sWorld)
end b2kAwakeBodyCount

-- =====================================================================
-- Dragging: call b2kGrab from mouseDown and b2kRelease from mouseUp.
-- =====================================================================
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

command b2kInputOff
   put false into sInputOn
   put comma into sKeysNow
   put comma into sKeysPrev
end b2kInputOff

function b2kInputIsOn
   return (sInputOn is true)
end b2kInputIsOn

-- Internal, called by the loop each frame while armed. The sets are stored
-- comma-wrapped (",65361,32,") so membership is one `contains` test.
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
command b2kInputInject pKeys
   put true into sInjectOn
   put b2kKeyListCodes(pKeys) into sInjectKeys
end b2kInputInject

command b2kInputInjectOff
   put false into sInjectOn
   put empty into sInjectKeys
end b2kInputInjectOff

-- A friendly key name (or raw keycode) -> the keycode candidates it matches,
-- comma-separated. Numbers >= 32 pass through as raw keycodes; single
-- characters resolve to their code (letters to both cases, per the
-- Shift-keysym behaviour the Phase 0 spike confirmed).
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
function b2kKeyInSet pSet, pKey
   local tC
   if pSet is empty or pSet is comma then return false
   repeat for each item tC in b2kKeyCodes(pKey)
      if pSet contains (comma & tC & comma) then return true
   end repeat
   return false
end b2kKeyInSet

function b2kKeyIsDown pKey
   return b2kKeyInSet(sKeysNow, pKey)
end b2kKeyIsDown

-- Edge queries: true only on the single frame the state changed.
function b2kKeyPressed pKey
   return b2kKeyInSet(sKeysNow, pKey) and not b2kKeyInSet(sKeysPrev, pKey)
end b2kKeyPressed

function b2kKeyReleased pKey
   return b2kKeyInSet(sKeysPrev, pKey) and not b2kKeyInSet(sKeysNow, pKey)
end b2kKeyReleased

-- Everything held right now, as friendly names (debug HUDs).
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
command b2kBindAction pName, pKeyList
   put pKeyList into sKeyActions[pName]
   put b2kKeyListCodes(pKeyList) into sKeyActionsC[pName]
end b2kBindAction

-- Internal: a friendly key list -> every matching keycode, comma list.
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
function b2kCodesInSet pSet, pCodes
   local tC
   if pSet is empty or pSet is comma then return false
   repeat for each item tC in pCodes
      if pSet contains (comma & tC & comma) then return true
   end repeat
   return false
end b2kCodesInSet

function b2kActionIsDown pName
   return b2kCodesInSet(sKeysNow, sKeyActionsC[pName])
end b2kActionIsDown

function b2kActionPressed pName
   if not b2kCodesInSet(sKeysNow, sKeyActionsC[pName]) then return false
   return not b2kCodesInSet(sKeysPrev, sKeyActionsC[pName])
end b2kActionPressed

function b2kActionReleased pName
   if not b2kCodesInSet(sKeysPrev, sKeyActionsC[pName]) then return false
   return not b2kCodesInSet(sKeysNow, sKeyActionsC[pName])
end b2kActionReleased

-- Axes: -1 / 0 / +1 from two key sets ("moveX" defaults to left,a / right,d).
-- Both directions held = 0, which is what character movement wants.
command b2kBindAxis pName, pNegKeys, pPosKeys
   put pNegKeys into sAxisNeg[pName]
   put pPosKeys into sAxisPos[pName]
   put b2kKeyListCodes(pNegKeys) into sAxisNegC[pName]
   put b2kKeyListCodes(pPosKeys) into sAxisPosC[pName]
end b2kBindAxis

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
-- (skipping the expensive decode) instead of re-importing from disk. Call
-- b2kSheetsWipe to force a clean reload (e.g. after the user picks a new
-- asset folder). OFF by default, so single-shot examples are unchanged.
command b2kSheetPersist pFlag
   put (pFlag is not false) into sSheetKeep
end b2kSheetPersist

function b2kSheetPersists
   return (sSheetKeep is true)
end b2kSheetPersists

-- Register an image FILE as a uniform grid of pFW x pFH frames, numbered
-- 1..N left-to-right, top-to-bottom. Reports the frame count. Sheets that
-- are not edge-to-edge take pMargin (outer border px) and pSpacing (gap
-- between cells px). Pass pFW/pFH 0 (or empty) to register the image with
-- NO grid and name regions yourself with b2kSheetAddFrame -- the path for
-- packed sheets that have no Kenney-style XML.
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
command b2kSheetLoadAtlas pName, pPngPath, pXmlPath
   local tRef, tXml, tLine, tNm, tX, tY, tW, tH, tSig
   if pXmlPath is empty then
      put pPngPath into pXmlPath
      set the itemDelimiter to "."
      put "xml" into item -1 of pXmlPath
   end if
   put pPngPath & "|" & pXmlPath into tSig
   if sSheetKeep is true and sSheetKeys[pName] is not empty and sSheetPath[pName] is tSig then
      return the number of lines of sSheetKeys[pName]   -- already loaded (same png+xml): reuse it
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
   return the number of lines of sSheetKeys[pName]
end b2kSheetLoadAtlas

function b2kSheetFrames pName
   return the number of lines of sSheetKeys[pName]
end b2kSheetFrames

function b2kSheetHasFrame pName, pFrame
   return (sSheetRegion[pName][pFrame] is not empty)
end b2kSheetHasFrame

-- Every frame key of a sheet, one per line, in definition order --
-- introspect an atlas you didn't make ("what is this frame called?").
function b2kSheetFrameNames pName
   return sSheetKeys[pName]
end b2kSheetFrameNames

-- Display scale for a sheet's frames (default 1). Frames slice lazily, so
-- set this right after loading the sheet, BEFORE creating sprites or anims:
-- already-sliced frames are dropped and re-bake at the new scale, but live
-- sprites keep their button rects. The engine does the resampling, so any
-- frame size displays at any sprite size.
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

function b2kSpriteAnim pCtrl
   try
      return sSprAnim[the long id of pCtrl]
   catch tErr
      return empty   -- a removed control is a stale ref, not an error
   end try
end b2kSpriteAnim

-- Show one frame by name/index (stops any running animation first).
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

function b2kSpriteFrame pCtrl
   try
      return sSprFrameKey[the long id of pCtrl]
   catch tErr
      return empty
   end try
end b2kSpriteFrame

-- Per-sprite speed override (empty = use each animation's own fps).
command b2kSpriteFPS pCtrl, pFPS
   local tRef
   if pCtrl is empty then exit b2kSpriteFPS   -- family law: empty ref = no-op
   put the long id of pCtrl into tRef
   put pFPS into sSprFPSOver[tRef]
   if pFPS is a number and pFPS > 0 then put pFPS into sSprFPS[tRef]
end b2kSpriteFPS

-- Face left (true) or right (false). The mirrored frame image is created
-- the first time it is needed, by flip-cloning the sliced frame.
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

function b2kSpriteFlipped pCtrl
   try
      return (sSprFlip[the long id of pCtrl] is true)
   catch tErr
      return false
   end try
end b2kSpriteFlipped

-- When a NON-looping animation finishes, send pMessage to the frame target
-- with the sprite and the animation name (attack/death/effect chaining).
command b2kSpriteOnFinish pCtrl, pMessage
   if pCtrl is empty then exit b2kSpriteOnFinish   -- family law: empty ref = no-op
   put pMessage into sSprMsg[the long id of pCtrl]
end b2kSpriteOnFinish

-- Pin this sprite to another control's position each frame (offset in px) --
-- the standard pattern for "art bigger than the collision shape": give an
-- invisible control the body, bind the sprite to it.
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

command b2kSpriteUnbind pCtrl
   if pCtrl is empty then exit b2kSpriteUnbind   -- family law: empty ref = no-op
   delete variable sSprBind[the long id of pCtrl]
   put true into sSprLiveDirty
end b2kSpriteUnbind

-- Remove a sprite (and its body, if it has one).
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
command b2kSpriteSweepOrphans pKeepAssets
   local tAgain, i, tName, tHit
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
         if tHit then
            delete control i of this card
            put true into tAgain
            exit repeat
         end if
      end repeat
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
function b2kSheetSliceSig pSheet
   return sSheetPath[pSheet] & "|" & b2kNumberOr(sSheetScale[pSheet], 1)
end b2kSheetSliceSig

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
command b2kPlayerSet pKey, pValue
   put pValue into sPlayTune[toLower(pKey)]
   b2kPlayerTuneCache
end b2kPlayerSet

-- Internal: resolve the knobs into flat locals ONCE per change -- the
-- tick reads these every frame and must not pay name lookups for them.
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

function b2kPlayer
   return sPlayRef
end b2kPlayer

-- The art control the controller animates (empty = none resolved yet).
function b2kPlayerSprite
   return sPlayArt
end b2kPlayerSprite

-- Grounded this frame (post-tick; false on the frame a jump launches).
function b2kPlayerOnGround
   return (sPlayGrounded is true)
end b2kPlayerOnGround

-- idle | run | jump | fall | duck | climb | hurt | swim | wallslide | dash,
-- plus "land" for exactly one frame on touch-down from jump/fall (dust
-- puffs, landing sounds). A drop-through renders as "fall". The Wave 5
-- states (wallslide, dash) only appear when their knobs are enabled.
-- Empty = no player.
function b2kPlayerState
   return sPlayState
end b2kPlayerState

function b2kPlayerFacing
   if sPlayFacing is -1 then return -1
   return 1
end b2kPlayerFacing

-- The capsule's CURRENT half-extents in px (the half-height drops while
-- the player is in a reshaped duck/crawl). Head-reach logic should read
-- these live rather than bake a constant (gotcha 28: a hitbox taller than
-- the visible art bumps things the head never touches).
function b2kPlayerHalfH
   return b2kNumberOr(sPlayHalfH, 0)
end b2kPlayerHalfH

function b2kPlayerHalfW
   return b2kNumberOr(sPlayHalfW, 0)
end b2kPlayerHalfW

-- This frame's ladder / water zone membership (the controller computes
-- these every tick anyway -- read them for "press UP to climb" prompts,
-- splash effects, breath meters, without recomputing the rects yourself).
function b2kPlayerInLadder
   return (sPlayInLad is true)
end b2kPlayerInLadder

function b2kPlayerInWater
   return (sPlayInWat is true)
end b2kPlayerInWater

-- Programmatic jump (springs, double-jump powerups): the same launch as a
-- pressed jump but WITHOUT the grounded/coyote gate -- the caller decides
-- when it is allowed. Uses the jumpSpeed knob unless given a speed.
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
function b2kPlayerHurtIs
   if sPlayHurt is true then return true
   if sPlayInvulnUntil is not empty and sPlayInvulnUntil > 0 and sPlayClock < sPlayInvulnUntil then return true
   return false
end b2kPlayerHurtIs

-- false = the controller only OBSERVES: ground/state/facing stay fresh
-- but it writes neither velocity nor animations (the maxFall clamp stays
-- live -- it is the character's terminal velocity). For cutscenes,
-- hit poses, scripted deaths; physics and the Kit run on.
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
command b2kPlayerRemove
   b2kPlayerForget true
end b2kPlayerRemove

-- Internal: drop controller state. b2kClear passes false (tuning is
-- config and survives, like input bindings); teardown/remove pass true.
-- Ladder zones are WORLD state, so they go either way; a mid-climb or
-- mid-drop body gets its gravity scale and collision mask back first.
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
command b2kPlayerClimbStart pBody
   if sPlayClimb is true then exit b2kPlayerClimbStart
   put b2BodyGravityScale(pBody) into sPlayGravSave
   b2SetGravityScale pBody, 0
   put true into sPlayClimb
   put false into sPlayJumping
end b2kPlayerClimbStart

command b2kPlayerClimbEnd pBody
   if sPlayClimb is not true then exit b2kPlayerClimbEnd
   b2SetGravityScale pBody, b2kNumberOr(sPlayGravSave, 1)
   put empty into sPlayGravSave
   put false into sPlayClimb
end b2kPlayerClimbEnd

-- Internal: enter the swim -- gravity drops to swimGravity (buoyant; the
-- body's own scale is saved and restored, like the climb). Mutually
-- exclusive with the climb: the tick only ever starts one of them.
command b2kPlayerSwimStart pBody
   if sPlaySwim is true then exit b2kPlayerSwimStart
   put b2BodyGravityScale(pBody) into sPlaySwimGravSave
   b2SetGravityScale pBody, b2kNumberOr(sPlaySwimGrav, 0.35)
   put true into sPlaySwim
   put false into sPlayJumping
end b2kPlayerSwimStart

command b2kPlayerSwimEnd pBody
   if sPlaySwim is not true then exit b2kPlayerSwimEnd
   b2SetGravityScale pBody, b2kNumberOr(sPlaySwimGravSave, 1)
   put empty into sPlaySwimGravSave
   put false into sPlaySwim
end b2kPlayerSwimEnd

-- Internal: open the drop-through window -- take the reserved one-way
-- bit out of the player's mask so chains (alone) stop colliding.
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
-- crawling. b2kReshape resets the material, so friction/bounce are re-set.
command b2kPlayerDuckSet pWantDuck
   local tNewH, tShift, tNeed
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
      b2kReshape sPlayRef, "capsule", sPlayCapW, tNewH
      b2kSetFriction sPlayRef, 0.08
      b2kSetBounce sPlayRef, 0
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
command b2kPlayerStandUp
   local tShift
   if sPlayDucked is not true or sPlayRef is empty then exit b2kPlayerStandUp
   -- mirror of the duck: stored capsule dims in, explicit dims to b2kReshape,
   -- no control resize (inert on a polygon graphic; the drawer re-points it)
   put (sPlayCapH - sPlayDuckH) / 2 into tShift
   b2kMoveTo sPlayRef, sPlayPX, sPlayPY - tShift
   b2kReshape sPlayRef, "capsule", sPlayCapW, sPlayCapH
   b2kSetFriction sPlayRef, 0.08
   b2kSetBounce sPlayRef, 0
   put sPlayStandH / 2 into sPlayHalfH
   put false into sPlayDucked
   b2kPlayerTuneCache
end b2kPlayerStandUp

-- Internal: the per-frame controller. Loop order: input -> PLAYER ->
-- sprites -> camera, so it reads this frame's edges and the sprite tick
-- applies the anim it picks. Exits in one compare when unused. The
-- Wave 2 paths (drop window, ladders, hurt) each cost ONE compare per
-- frame while idle -- the tick's steady-state budget is unchanged.
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

function b2kCamIsOn
   return (sCamGroup is not empty)
end b2kCamIsOn

-- The viewport group's reference (empty when the camera is off) -- create
-- your own level controls inside it: create graphic "x" in b2kCamGroup().
function b2kCamGroup
   return sCamGroup
end b2kCamGroup

-- Move an existing control (IDE-designed levels) into the viewport.
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

command b2kCamFollow pCtrl, pLerp
   put the long id of pCtrl into sCamFollow
   if pLerp is a number then put b2kClamp(pLerp, 0.01, 1) into sCamLerp
end b2kCamFollow

command b2kCamUnfollow
   put empty into sCamFollow
end b2kCamUnfollow

-- Follow only once the target leaves a centre box (0 = always centre).
command b2kCamDeadzone pW, pH
   put b2kNumberOr(pW, 0) into sCamDZW
   put b2kNumberOr(pH, 0) into sCamDZH
end b2kCamDeadzone

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

command b2kCamGoto pX, pY
   put b2kNumberOr(pX, sCamX) into sCamX
   put b2kNumberOr(pY, sCamY) into sCamY
   b2kCamApply
end b2kCamGoto

function b2kCamPos
   return round(sCamX) & comma & round(sCamY)
end b2kCamPos

-- A decaying random view offset on top of the follow (impacts, blasts).
command b2kCamShake pAmpPx, pMs
   put b2kClamp(pAmpPx, 0, 200) into sCamShakeAmp
   put the milliseconds + b2kClamp(pMs, 0, 5000) into sCamShakeEnd
end b2kCamShake

-- The mouse in WORLD pixels (camera-aware) -- use these for b2kGrab,
-- spawning at the pointer, click-picking, instead of the mouseH/V.
function b2kCamMouseX
   if sCamGroup is empty then return the mouseH
   set the itemDelimiter to comma
   return the mouseH - (item 1 of the rect of sCamGroup) + the hScroll of sCamGroup
end b2kCamMouseX

function b2kCamMouseY
   if sCamGroup is empty then return the mouseV
   set the itemDelimiter to comma
   return the mouseV - (item 2 of the rect of sCamGroup) + the vScroll of sCamGroup
end b2kCamMouseY

-- Health: empty = camera fine (or simply off); otherwise the reason the
-- camera could not run properly (create-group/scroll failures). Check it
-- after b2kCamOn and degrade your level gracefully.
function b2kCamStatus
   return sCamNote
end b2kCamStatus

-- "visual" when this engine reports/sets grouped locs scroll-adjusted,
-- else "content". Diagnostic; the Kit compensates automatically.
function b2kCamLocSemantics
   if sCamLocVisual is true then return "visual"
   return "content"
end b2kCamLocSemantics

-- Internal: the scroll to subtract when WRITING a position into the
-- viewport on a visual-semantics engine (0 otherwise / outside it).
function b2kCamShiftX pRef
   if sCamLocVisual is not true then return 0
   if sInCam[pRef] is not true then return 0
   return sCamCurH
end b2kCamShiftX

function b2kCamShiftY pRef
   if sCamLocVisual is not true then return 0
   if sInCam[pRef] is not true then return 0
   return sCamCurV
end b2kCamShiftY

-- Move ANY sprite/control to a WORLD position, camera-correct (use this
-- instead of `set the loc` for things you animate by hand, like a patrol
-- path -- outside a camera it is a plain loc set).
command b2kSpriteMoveTo pCtrl, pX, pY
   local tRef
   if pCtrl is empty then exit b2kSpriteMoveTo   -- family law: empty ref = no-op
   put the long id of pCtrl into tRef
   set the loc of tRef to round(pX - b2kCamShiftX(tRef)) & comma & round(pY - b2kCamShiftY(tRef))
end b2kSpriteMoveTo

-- Internal, called by the loop each frame: chase the followed control. The
-- follow eases, but the target is GUARANTEED on screen: if it would leave
-- the view (fast falls, teleports, lerp lag), the camera snaps to it.
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
-- accumulates, and b2kSoundsWipe purges everything (it also sweeps
-- b2ksnd_ clips a dead session left in the stack). Failures degrade to
-- silence, never to errors: the first play that throws trips a
-- dead-flag and b2kSoundStatus() says why. The mute is a user
-- preference. There is no per-frame tick -- audio is purely
-- event-driven.

-- Import a WAV/AIFF/AU file as a named sound (replaces any same name).
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
function b2kWavWrap pData
   local tLen
   put the number of bytes in pData into tLen
   return "RIFF" & b2kLE32(36 + tLen) & "WAVE" & "fmt " & b2kLE32(16) \
         & b2kLE16(1) & b2kLE16(1) & b2kLE32(22050) & b2kLE32(22050) \
         & b2kLE16(1) & b2kLE16(8) & "data" & b2kLE32(tLen) & pData
end b2kWavWrap

-- Internal: little-endian byte packers (hand-rolled: no binaryEncode
-- format-letter portability worries).
function b2kLE16 pN
   return numToByte(pN mod 256) & numToByte(pN div 256 mod 256)
end b2kLE16

function b2kLE32 pN
   return numToByte(pN mod 256) & numToByte(pN div 256 mod 256) & numToByte(pN div 65536 mod 256) & numToByte(pN div 16777216 mod 256)
end b2kLE32

-- Play a named sound (cuts whatever is playing -- the audioClip model).
command b2kSound pName
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tClip
   if sSndMute is true or sSndDead is true then exit b2kSound
   put sSndClip[pName] into tClip
   if tClip is empty then exit b2kSound
   try
      play audioClip tClip
   catch tErr
      put true into sSndDead   -- this engine can't play: silence, no spam
      put "play failed: " & tErr into sSndNote
   end try
end b2kSound

-- Loop a named sound until b2kSoundStop / the next play (ambience).
command b2kSoundLoop pName
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tClip
   if sSndMute is true or sSndDead is true then exit b2kSoundLoop
   put sSndClip[pName] into tClip
   if tClip is empty then exit b2kSoundLoop
   try
      play audioClip tClip looping
   catch tErr
      put true into sSndDead
      put "play failed: " & tErr into sSndNote
   end try
end b2kSoundLoop

command b2kSoundStop
   try
      play stop
   catch tErr
   end try
end b2kSoundStop

-- Mute is a preference: it survives b2kTeardown and stack resets are up
-- to the caller (store it in a custom property if you want it saved).
command b2kSoundMute pFlag
   put (pFlag is true) into sSndMute
   if sSndMute then b2kSoundStop
end b2kSoundMute

function b2kSoundMuted
   return (sSndMute is true)
end b2kSoundMuted

-- The engine-GLOBAL output volume (the playLoudness, 0-100): it affects
-- every stack's audio, so games should expose it, not hardcode it.
command b2kSoundVolume pPct
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   try
      set the playLoudness to round(b2kClamp(pPct, 0, 100))
   catch tErr
      put "volume failed: " & tErr into sSndNote
   end try
end b2kSoundVolume

function b2kSoundIsLoaded pName
   return (sSndClip[pName] is not empty)
end b2kSoundIsLoaded

-- Empty = healthy; otherwise the most recent reason audio degraded
-- (missing file, import failure, play failure). Plays never throw.
function b2kSoundStatus
   return sSndNote
end b2kSoundStatus

-- Internal: delete every Kit-made audioClip ("b2ksnd_" prefix -- catches
-- a dead session's leftovers too) and reset the registry. The dead-flag
-- resets (a fresh world may retry); the mute preference survives.
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
command b2kSync
   lock screen
   try
      b2kSyncAllBodies
   catch tErr
   end try
   unlock screen
end b2kSync

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

command b2kDrawPoly pRef, pWx, pWy, pWa
   local c, s, p, pt, tPts, tFirst, tKey
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
command b2kEventsReset
   put 0 into sEvtCN
   put 0 into sEvtEN
   put 0 into sEvtSN
   put 0 into sEvtXN
end b2kEventsReset

-- Internal: pull THIS step's Box2D events into the frame buffers. Box2D
-- keeps only the latest step's events, so this must run after every
-- b2Step -- the dispatchers and pollers then see the whole frame.
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
-- <<< END EMBEDDED KIT <<<

-- =====================================================================
-- CONTRAPTION BUILDER  /  built on the Kit above (b2k...)
--
-- A free-form construction GUI: place parts, connect them with joints,
-- motorise the joints, then flip Build -> Run to watch it go. Every line
-- below only ever calls the friendly b2k... Kit, in screen pixels.
--
-- WORKFLOW
--   / BUILD mode (the loop is stopped, so nothing falls): click empty
--     canvas with a shape tool to drop a part; drag parts to arrange them;
--     the Delete tool removes a part and its joints.
--   / Pick a joint tool, then click part A and part B to connect them.
--     A Hinge pinned to an Anchor (or empty space = the world) makes the
--     best motor mount. Overlapping parts connect fine.
--   / Motor drives new Hinge / Wheel joints; Bouncy makes new parts springy.
--   / RUN mode: gravity + motors run; drag any body with the mouse.
--   / Save / Load store and restore a whole contraption as text.
--
-- NAMING: p* params, t* locals, g* script-locals, k* constants, u* custom
-- properties. kPI is already defined by the embedded Kit above (do not
-- redeclare it). All coordinates here are SCREEN PIXELS.
-- =====================================================================

local gMode, gTool, gJointTool
local gPendCtrl, gPendX, gPendY
local gMotorOn, gMotorSpeed, gBouncy, gMotorsRunning
local gDragCtrl, gDragMode, gDragMoved
local gDrawPts, gDrawCtrl               -- freehand-terrain points + its preview graphic
local gModalOpen, gModalPaused, gModalAccel   -- popups pause the sim + drop GPU compositing beneath them
local gParts
local gJN
local gJKind, gJHandle, gJCa, gJCb
local gJPx, gJPy, gJMotor, gJVis, gJEnd
local gArenaL, gArenaR, gArenaT, gArenaB
local gStatus
local gNextPid
local gNameCount                       -- per-kind counter for auto-names (Bomb 1, Plate 2, ...)
local gWires                           -- CR-list of signal wires, each "srcCtrl<tab>tgtCtrl" (long ids)
local gWireSrc                         -- the pending wire source while the Link tool waits for a target
local gPlaying                         -- true while in Play mode (Run + win-watching + a clean view)
local gGameWon                         -- latches true the moment every goal zone is reached this run
local gPlayStartMs                     -- the milliseconds Play started, for the solve timer
local gAssets                          -- the image library: CR-list of "path<tab>shape<tab>name"
local gFlash
local gFrames, gFpsTime, gFps, gHudTime   -- gHudTime throttles the live HUD/telemetry refresh
-- new-object + field-force state (balloons rise on their own; fans/magnets are
-- body-less zones that push parts each frame; plates count what rests on them).
-- gKindList[kind] holds a CR-delimited control list per special kind.
local gKindList
local gPlateLoad, gPlateState
local gSensorCount      -- per-sensor count of bodies currently inside (fires on 0->1)
local gRingN, gRingX, gRingY, gRingF
local gDynParts, gDynDirty
-- selection / inspector / onboarding / stress-test bookkeeping
local gSelPart, gHoverId, gOnbStep, gStressCount
local gSelJoint                        -- selected joint index (1..gJN), empty if none
local gFilterPart                      -- part whose collision filter the popup panel is editing
local gInspTab                         -- active inspector tab: shape | physics | collide | special
local gInspectorMode                   -- "simple" (hides expert-only rows) | "advanced"; empty == simple
local gGravityMode                     -- world gravity preset: normal|low|zero|reverse|sideways
local gWorldFeel                       -- world-tuning preset: default|bouncy|floaty|snappy
local gCCD, gSleepOn, gWarmStart, gSubsteps   -- advanced world solver toggles (the "World / Advanced" panel)
local gPreRun                          -- snapshot of the build, taken when Run starts
local gPalOpen                         -- CR-list of palette section titles currently expanded

constant kEditTools    = "drag,delete,duplicate,multiply,link"
constant kEditLabels   = "Drag,Delete,Duplicate,Multiply,Link"
constant kShapeTools   = "box,ball,capsule,poly,image,anchor"
constant kShapeLabels  = "Box,Ball,Capsule,Polygon,Image,Anchor"
constant kSpecialTools = "balloon,bomb,plate,fan,magnet,sensor,laser,thruster,goal"
constant kSpecialLabels = "Balloon,Bomb,Pressure Plate,Fan,Magnet,Sensor,Laser,Thruster,Goal Zone"
constant kTerrainTools = "platform,ramp,hill,draw"
constant kTerrainLabels = "Platform,Ramp,Hill,Draw"
constant kDrawStep = 14       -- min pixels between sampled points while drawing freehand terrain
constant kDrawLineSize = 7    -- drawn ground is thick: reads as solid + easy to click/select
constant kVehicleTools = "car"
constant kVehicleLabels = "Car"
constant kJointTools   = "hinge,weld,servo,rope,slider,wheel,bridge,chain"
constant kJointLabels  = "Hinge,Weld,Servo,Rope,Slider,Wheel,Bridge,Chain"
constant kHingeTorque = 1500, kWheelTorque = 320
constant kBridgeFlex = 30   -- a bridge plank pin flexes +/- this many degrees, so a
                            -- loaded deck sags under weight but can never fold back on itself
constant kServoForce = 3000, kServoTorque = 2500   -- how hard a Servo joint holds its pose

-- Layout, in screen pixels. Derived edges (canvas L/R/T/B) are computed from the
-- card size in prepArena/buildUI, because LiveCode constants cannot be expressions.
constant kStackW = 1180, kStackH = 640
constant kTopBarH = 54, kAccentH = 3
constant kPaletteW = 196, kInspectorW = 248, kStatusH = 26
constant kCanvasInset = 2, kGroundBarH = 22
constant kPalPadX = 12, kPalBtnH = 28, kPalBtnGap = 4
constant kPalSectionGap = 8, kPalHeaderH = 22, kPalScrollW = 16, kPalGutterW = 22
-- Bump kUIVersion whenever the built chrome changes, so older saved stacks rebuild once.
constant kUIVersion = "13"
-- The native shim ABI this build expects; MUST track LC_ABI_VERSION in src/box2d_lc.c.
-- startCB probes b2Version() against this so an outdated/missing library fails fast with
-- a plain-language fix instead of crashing mid-run on an unresolved foreign handler.
constant kReqABI = 4

-- Palette theme: one source of truth for the chrome colours (RGB strings) so the
-- idle / active / hover styling never drifts apart. Used by the setBtn*, highlight*
-- and hover helpers. (String literals are valid constants; expressions are not.)
constant kColPaletteBg = "26,28,35", kColBtnIdle = "44,48,58", kColBtnIdleText = "196,200,212"
constant kColBtnHover = "58,64,78", kColBtnText = "255,255,255"
constant kColAccentGreen = "72,190,130", kColAccentAmber = "232,150,72", kColToggleBlue = "64,132,232"
constant kColDanger = "214,92,92", kColHeaderText = "150,156,172", kColRule = "52,57,70"
-- Former magic numbers: starting motor speed ( deg/s) and world gravity (downward).
constant kDefaultMotorSpeed = 120, kDefaultGravity = -10

-- Materials, motors, feedback timing, and default part sizes (were magic numbers).
constant kBounceOn = 0.7, kFlashMs = 150, kSelectLine = 3
constant kMotorMin = 30, kMotorMax = 600, kFpsWindowMs = 500, kImageMax = 120
constant kBoxMin = 40, kBoxMax = 64, kBallMin = 34, kBallMax = 60
constant kCapLenMin = 80, kCapLenMax = 120, kCapThick = 36
constant kPolyMin = 26, kPolyMax = 44

-- New objects (all built from existing Kit primitives, screen pixels / degrees).
constant kBalloonGravScale = -0.6, kBalloonDamp = 1.2, kBalloonDiam = 46
constant kBombDiam = 40, kBombRadius = 210, kBombPower = 720
constant kBombFuseFrames = 60, kBombImpactSpeed = 700
constant kPlateW = 120, kPlateH = 16
constant kSensorW = 96, kSensorH = 72
constant kFanW = 130, kFanH = 150, kFanForce = 900
constant kMagnetRange = 220, kMagnetForce = 1400, kMagnetMinDist = 16
constant kLaserReach = 1600, kLaserStep = 45   -- laser ray length (px) and the angle step its direction cycles by
constant kGoalW = 120, kGoalH = 120   -- a goal zone's base size (scaled by uGoalScale)
constant kLaserBurnDefault = 36   -- default frames of sustained laser hit before a cutting beam destroys a normal part
constant kToughnessDefault = 36   -- default part toughness, also in sustained laser-hit frames
constant kLaserBurnStep = 12      -- inspector nudge for laser burn time / part toughness
constant kLaserCool = 250  -- ms without a hit after which a part's accrued burn cools back to zero
constant kContainMargin = 90   -- how far past the arena a body may stray before the containment net pulls it back
constant kStressBatch = 50
constant kSizeMin = 16, kSizeMax = 240
-- Terrain (static scenery) can be larger than parts - wide ledges, long ramps.
constant kTerrainMin = 20, kTerrainMax = 600
-- inspector: rows shown per tab, dimension nudge (px), joint click radius (px)
constant kPropRows = 10, kDimStep = 8, kJointHitR = 16
-- the eight collision channels the filter popup exposes (1..8 -> bits 1,2,4..128)
constant kFilterChannels = 8, kAllChannels = "1,2,3,4,5,6,7,8"
-- numeric settings a user may type an exact value for (toggles/colour stay stepper-only)
constant kEntryKeys = "width,height,length,thickness,diameter,size,angle,bounce,density,friction,gravity,lindamp,angdamp,launchspeed,launchdir,spinrate,toughness,blastradius,blastpower,bombfuselen,fanforce,fansize,magforce,magrange,laserburn,goalsize,thrustdir,thrustpower,thrustspin"

-- =====================================================================
-- Lifecycle
-- =====================================================================
-- Build once: startCB generates the chrome on first run and stamps a version on the
-- stack, so save the stack afterwards. On later opens chromeBuilt() is true, so the
-- ~200-control UI is NOT rebuilt - only the native physics world is recreated (it
-- can't be serialised). Run rebuildCB to regenerate the chrome after editing the
-- builder; bumping kUIVersion makes any older saved stack rebuild itself once.
on preOpenCard
   startCB
end preOpenCard

on closeCard
   stopCB
end closeCard

on startCB
   set the title of this stack to "Box2Dxt - Contraption Builder"
   set the decorations of this stack to "default"
   set the resizable of this stack to false
   set the width of this stack to kStackW
   set the height of this stack to kStackH
   set the loc of this stack to the screenLoc
   set the backgroundColor of this card to "22,24,30"
   put "build" into gMode
   put "drag" into gTool
   put empty into gJointTool
   put false into gModalOpen        -- a popup can't survive a close; don't let stale state skip the next enter
   put false into gModalPaused
   put false into gMotorOn
   put true into gMotorsRunning
   put kDefaultMotorSpeed into gMotorSpeed
   put false into gBouncy
   put empty into gParts
   put empty into gFlash
   put 1 into gNextPid
   put 0 into gFrames
   put empty into gFps
   put the milliseconds into gFpsTime
   put empty into gSelPart
   put empty into gSelJoint
   put "shape" into gInspTab
   put "normal" into gGravityMode
   put "default" into gWorldFeel
   setWorldOptionDefaults
   put empty into gHoverId
   put 0 into gStressCount
   put "SHAPES" into gPalOpen        -- single-open accordion: SHAPES is the category open first
   resetSceneState
   resetJointArrays
   resetPend
   if not chromeBuilt() then         -- build the chrome once; it persists in the saved stack
      buildUI
      set the uUIVersion of this stack to kUIVersion
   end if
   -- The physics world needs the native box2dxt library, built from the CURRENT source
   -- (ABI kReqABI). Without it b2kSetup would throw a raw "unable to load foreign library"
   -- LCB error; worse, an OUTDATED library passes a naive load check and then crashes
   -- mid-run on the first unresolved handler. Probe b2Version() and explain the fix in
   -- plain language: an empty result means not loaded, a different number means outdated.
   local tVer
   try
      put b2Version() into tVer
   catch tErr
      put empty into tVer
   end try
   if tVer is not kReqABI then
      local tWhy
      if tVer is empty then
         put "could not be found, so the physics engine cannot start" into tWhy
      else
         put "reports version " & tVer & ", but this build needs version " & kReqABI & \
               ". Rebuild it from the current source" into tWhy
      end if
      if there is a field "ui_status" then put "Box2Dxt native library unavailable - physics is disabled. See the dialog." into field "ui_status"
      answer "Box2Dxt - native library unavailable" & return & return & \
            "The box2dxt extension is loaded, but its native library" && tWhy & "." & return & return & \
            "Put the matching library where OXT's loader looks, named WITHOUT a 'lib' prefix:" & return & \
            "    Linux:    box2dxt.so   (copy to /usr/lib, then run: sudo ldconfig)" & return & \
            "    macOS:    box2dxt.dylib" & return & \
            "    Windows:  box2dxt.dll" & return & return & \
            "Then reopen this stack. Full steps: docs/getting-started.md" with "OK"
      exit startCB
   end if
   b2kSetup 0, kDefaultGravity      -- creates the world; the loop stays stopped
   prepArena
   sweepOrphanParts                 -- a stack saved with parts on the stage reopens to a
                                    -- clean stage (no dead, untracked part graphics)
   b2kFrameTarget the long id of this stack
   b2kContactTarget the long id of this stack
   raiseUI
   highlightAll
   layoutPalette                    -- re-apply accordion state to the persisted palette
   loadImageLibrary                 -- restore the user's imported-image library
   showInspectorForTool
   put "Welcome! Pick a part on the left, drop it on the stage, then press Run. New here? The ? button (top bar) replays the quick tour." into gStatus
   updateHud
   maybeShowOnboarding
end startCB

on stopCB
   b2kTeardown
   put empty into gParts
   put empty into gFlash
   resetSceneState
   resetJointArrays
   clearSceneControls
end stopCB

-- Force a one-time chrome rebuild - after editing the builder, or to repair the UI.
on rebuildCB
   set the uUIVersion of this stack to empty
   startCB
end rebuildCB

-- Draw every part + joint once. Build mode stops the loop (so nothing falls),
-- which also stops the Kit's own redraw - so we sync by hand after each edit.
on renderBuild
   if b2kWorld() is empty then exit renderBuild
   lock screen
   b2kSync
   renderJoints
   updateLasers
   drawWires
   unlock screen
end renderBuild

-- =====================================================================
-- Modal view discipline. While a popup (Recipes / Filter / World / Images)
-- is up, freeze the world beneath it: a running sim keeps every dynamic-layer
-- part repainting under the popup, which fights the compositor (parts and
-- joint markers bleed through patchy chrome) and lets the contraption change
-- while the user is looking away. Pause the loop and composite the classic,
-- cache-free way while the modal is open; restore both exactly as found.
-- =====================================================================
on enterModalView
   if gModalOpen is true then exit enterModalView
   put true into gModalOpen
   put b2kIsRunning() into gModalPaused          -- only resume what we paused
   if gModalPaused then
      b2kPause
      refreshPauseLabel
   end if
   put the acceleratedRendering of this stack into gModalAccel
   set the acceleratedRendering of this stack to false
end enterModalView

on exitModalView
   if gModalOpen is not true then exit exitModalView
   put false into gModalOpen
   set the acceleratedRendering of this stack to gModalAccel
   if gModalPaused is true then
      b2kResume
      refreshPauseLabel
   end if
   put false into gModalPaused
end exitModalView

-- =====================================================================
-- Arena (walls + a framed play field, mirrors the showcase demo)
-- =====================================================================
on prepArena
   set the acceleratedRendering of this stack to true   -- GPU compositing so dynamic-layer bodies move without trails/clipping
   local tWide, tHigh, tCanvasL, tCanvasR, tCanvasT, tCanvasB
   put the width of this card into tWide
   put the height of this card into tHigh
   put kPaletteW into tCanvasL                  -- play field sits between the panels
   put tWide - kInspectorW into tCanvasR
   put kTopBarH + kAccentH into tCanvasT
   put tHigh - kStatusH into tCanvasB
   put tCanvasL + kCanvasInset into gArenaL
   put tCanvasR - kCanvasInset into gArenaR
   put tCanvasT + kCanvasInset into gArenaT
   put tCanvasB - kGroundBarH into gArenaB
   if there is not a graphic "cb_field" then create graphic "cb_field"
   set the style of graphic "cb_field" to "rectangle"
   set the filled of graphic "cb_field" to true
   set the backgroundColor of graphic "cb_field" to "26,29,37"
   set the foregroundColor of graphic "cb_field" to "46,60,86"
   set the lineSize of graphic "cb_field" to 2
   set the rect of graphic "cb_field" to gArenaL, gArenaT, gArenaR, gArenaB + kGroundBarH
   b2kWall gArenaL, gArenaB, gArenaR, gArenaB    -- floor
   b2kWall gArenaL, gArenaT, gArenaR, gArenaT    -- ceiling
   b2kWall gArenaL, gArenaB, gArenaL, gArenaT    -- left wall
   b2kWall gArenaR, gArenaB, gArenaR, gArenaT    -- right wall
   if there is not a graphic "cb_groundbar" then create graphic "cb_groundbar"
   set the style of graphic "cb_groundbar" to "rectangle"
   set the filled of graphic "cb_groundbar" to true
   set the backgroundColor of graphic "cb_groundbar" to "44,49,60"
   set the lineSize of graphic "cb_groundbar" to 0
   set the rect of graphic "cb_groundbar" to gArenaL, gArenaB, gArenaR, gArenaB + kGroundBarH
end prepArena

-- =====================================================================
-- UI
-- =====================================================================
-- The chrome is generated once and saved with the stack; chromeBuilt reports whether
-- the persisted UI is present and current, so startCB can skip the rebuild on reopen.
-- (A version mismatch - e.g. after the builder is updated - rebuilds it once.)
function chromeBuilt
   return (there is a group "ui_palettescroll") and (the uUIVersion of this stack is kUIVersion)
end chromeBuilt

-- Build the whole UI: a top action bar, a grouped tool palette on the left, an
-- inspector/help panel on the right, and a status bar along the bottom.
on buildUI
   clearUI
   makeTopBar
   makePalette
   makeInspector
   makeStatusBar
   buildRecipesMenu
   buildFilterPanel
   buildWorldPanel
   buildPlayOverlay
   buildImagePanel
   applyTooltips
end buildUI

-- Top bar: brand on the left, the global actions right-aligned.
on makeTopBar
   local tWide, tY, tX, tIds, tLbls, tWidths, tGap, tI, tId, tW
   put the width of this card into tWide
   makeBar "ui_header", 0, 0, tWide, kTopBarH, "30,33,42"
   makeBar "ui_accent", 0, kTopBarH, tWide, kTopBarH + kAccentH, kColAccentGreen
   makeLabel "ui_title", 18, 7, 280, 33, "Box2Dxt", 22, "236,238,245", true
   makeLabel "ui_sub", 20, 32, 560, 50, "Contraption Builder - build a machine, then press Run to bring it to life", 11, "150,154,166", false
   put "mode,play,reset,clear,save,load,worldadv,images,recipes,info" into tIds
   put "Run,Play,Reset,Clear,Save,Load,World,Images,Recipes,?" into tLbls
   put "84,58,58,58,58,58,58,66,78,30" into tWidths
   put 6 into tGap
   put 0 into tW
   repeat for each item tId in tWidths
      add tId + tGap to tW
   end repeat
   put tWide - 12 - (tW - tGap) into tX
   put 13 into tY
   repeat with tI = 1 to the number of items of tIds
      makeAction (item tI of tIds), (item tI of tLbls), tX, tY, (item tI of tWidths), 28
      add (item tI of tWidths) + tGap to tX
   end repeat
end makeTopBar

-- Left palette: six colour-coded categories (TOOLS, SHAPES, SPECIAL, TERRAIN,
-- VEHICLES, JOINTS) as a single-open accordion - opening one collapses the others,
-- so the whole toolbox fits the window without a scrollbar. Drag/Delete/Duplicate/
-- Multiply live under TOOLS; SHAPES holds only the parts you actually drop.
on makePalette
   local tWide, tHigh, tY
   put the width of this card into tWide
   put the height of this card into tHigh
   makeBar "ui_palettebg", 0, kTopBarH + kAccentH, kPaletteW, tHigh - kStatusH, kColPaletteBg
   put kTopBarH + kAccentH + 8 into tY
   put makeToolSection("TOOLS", kEditTools, kEditLabels, "tool", tY) into tY
   put makeToolSection("SHAPES", kShapeTools, kShapeLabels, "tool", tY) into tY
   put makeToolSection("SPECIAL", kSpecialTools, kSpecialLabels, "tool", tY) into tY
   put makeToolSection("TERRAIN", kTerrainTools, kTerrainLabels, "tool", tY) into tY
   put makeToolSection("VEHICLES", kVehicleTools, kVehicleLabels, "tool", tY) into tY
   put makeToolSection("JOINTS", kJointTools, kJointLabels, "joint", tY) into tY
   groupPalette
   layoutPalette                          -- apply collapse/expand state, chevrons and scrollbar
end makePalette

-- Wrap the section headers + tool buttons in one scrolling group. The grouping
-- idiom: select the controls, then `group` (the new group is returned in `it`).
on groupPalette
   local tT, tId, tErr
   if there is a group "ui_palettescroll" then exit groupPalette
   -- If grouping ever fails on a platform, degrade to an un-grouped (non-scrolling)
   -- palette rather than aborting the whole UI build.
   try
      select empty
      repeat for each item tT in "TOOLS,SHAPES,SPECIAL,TERRAIN,VEHICLES,JOINTS"
         if there is a button ("ui_hdr_" & tT) then set the selected of button ("ui_hdr_" & tT) to true
         if there is a graphic ("ui_hdrrule_" & tT) then set the selected of graphic ("ui_hdrrule_" & tT) to true
      end repeat
      repeat for each item tId in (kEditTools & comma & kShapeTools & comma & kTerrainTools & comma & kSpecialTools & comma & kVehicleTools)
         if there is a button ("ui_tool_" & tId) then set the selected of button ("ui_tool_" & tId) to true
      end repeat
      repeat for each item tId in kJointTools
         if there is a button ("ui_joint_" & tId) then set the selected of button ("ui_joint_" & tId) to true
      end repeat
      repeat for each item tId in (kEditTools & comma & kShapeTools & comma & kTerrainTools & comma & kSpecialTools & comma & kVehicleTools & comma & kJointTools)
         if there is a field ("ui_g_" & tId) then set the selected of field ("ui_g_" & tId) to true
      end repeat
      group
      set the name of it to "ui_palettescroll"
      select empty
      set the showName of group "ui_palettescroll" to false
      set the showBorder of group "ui_palettescroll" to false
      set the borderWidth of group "ui_palettescroll" to 0
      set the margins of group "ui_palettescroll" to 0
      set the opaque of group "ui_palettescroll" to false
      set the hScrollbar of group "ui_palettescroll" to false
      set the vScrollbar of group "ui_palettescroll" to false   -- single-open always fits; no native bar
      set the unboundedVScroll of group "ui_palettescroll" to false
      set the rect of group "ui_palettescroll" to 0, kTopBarH + kAccentH, kPaletteW, (the height of this card) - kStatusH
      set the vScroll of group "ui_palettescroll" to 0
   catch tErr
      select empty
   end try
end groupPalette

-- Build one labelled palette section: a clickable accordion header (chevron + title)
-- over a hairline rule, then the tool rows. Each row is a left-aligned text button
-- with its glyph in a fixed-width gutter on the left, so every label lines up no
-- matter how wide the glyph is. layoutPalette repositions/shows/hides these after.
function makeToolSection pTitle, pIds, pLabels, pKind, pStartY
   local tY, tI, tId, tLbl, tName, tRight, tGut
   put pStartY into tY
   put kPaletteW - kPalPadX into tRight                      -- shared right edge (symmetric inset, no scrollbar)
   put kPalPadX + kPalGutterW into tGut                      -- labels start after the glyph gutter
   makeButton ("ui_hdr_" & pTitle), (chevronGlyph(pTitle) && pTitle), kPalPadX, tY, tRight - kPalPadX, kPalHeaderH
   set the textAlign of button ("ui_hdr_" & pTitle) to "left"
   set the textStyle of button ("ui_hdr_" & pTitle) to "bold"
   set the textSize of button ("ui_hdr_" & pTitle) to 10
   set the textColor of button ("ui_hdr_" & pTitle) to kColHeaderText
   set the opaque of button ("ui_hdr_" & pTitle) to false   -- reads as a label, still fully clickable
   set the uHdr of button ("ui_hdr_" & pTitle) to pTitle
   makeBar ("ui_hdrrule_" & pTitle), kPalPadX, tY + kPalHeaderH, tRight, tY + kPalHeaderH + 1, kColRule
   add kPalHeaderH + 6 to tY
   repeat with tI = 1 to the number of items of pIds
      put item tI of pIds into tId
      put item tI of pLabels into tLbl
      if pKind is "joint" then
         put "ui_joint_" & tId into tName
         makeButton tName, tLbl, tGut, tY, tRight - tGut, kPalBtnH
         set the uJointId of button tName to tId
      else
         put "ui_tool_" & tId into tName
         makeButton tName, tLbl, tGut, tY, tRight - tGut, kPalBtnH
         set the uToolId of button tName to tId
      end if
      set the textAlign of button tName to "left"          -- menu-style: labels start at the left
      set the margins of button tName to 8
      set the tooltip of button tName to line 1 of toolHelp(tId)   -- set now; survives grouping
      makeLabel ("ui_g_" & tId), kPalPadX, tY, tGut, tY + kPalBtnH, toolGlyph(tId), 13, kColBtnIdleText, false
      set the textAlign of field ("ui_g_" & tId) to "center"
      set the margins of field ("ui_g_" & tId) to 4
      add kPalBtnH + kPalBtnGap to tY
   end repeat
   return tY + kPalSectionGap
end makeToolSection

-- v when a section is expanded, > when collapsed (drives the header label).
function chevronGlyph pTitle
   if pTitle is among the lines of gPalOpen then return "v"
   return ">"
end chevronGlyph

-- Title -> its tool ids / kind. No new data: routes to the existing constant lists.
function sectionIds pTitle
   switch pTitle
      case "TOOLS"
         return kEditTools
      case "SHAPES"
         return kShapeTools
      case "TERRAIN"
         return kTerrainTools
      case "SPECIAL"
         return kSpecialTools
      case "VEHICLES"
         return kVehicleTools
      case "JOINTS"
         return kJointTools
   end switch
   return empty
end sectionIds

function sectionKind pTitle
   if pTitle is "JOINTS" then return "joint"
   return "tool"
end sectionKind

-- Each category owns an accent colour. It fills the header when the section is open,
-- tints the header title when collapsed, and lights up the selected tool inside it -
-- so the palette reads as distinct, colour-coded groups (white text stays legible on
-- every one of these).
function categoryColor pTitle
   switch pTitle
      case "TOOLS"
         return "76,122,210"
      case "SHAPES"
         return kColAccentGreen
      case "SPECIAL"
         return "158,100,205"
      case "TERRAIN"
         return "190,140,72"
      case "VEHICLES"
         return "66,172,182"
      case "JOINTS"
         return kColAccentAmber
   end switch
   return kColAccentGreen
end categoryColor

-- Lay the palette out from gPalOpen. Every header shows (chevron + colour-coded
-- title); the open category reveals its rule + glyph gutters + tool buttons, while
-- collapsed categories hide their rows and park them at the top of the content. With
-- one category open at a time the whole toolbox fits the panel, so there is no native
-- scrollbar to flicker or resize - the viewport rect is re-asserted here each time.
on layoutPalette
   if there is not a group "ui_palettescroll" then exit layoutPalette
   local tY, tTitle, tIds, tPrefix, tId, tBtn, tGlyph, tOpen, tRight, tGut, tPark, tHdr
   lock screen
   -- Re-assert the viewport rect every layout (a stale persisted height was what let
   -- the native bar flicker in) and keep it bar-free: a single open category always
   -- fits, so nothing needs to scroll.
   set the rect of group "ui_palettescroll" to 0, kTopBarH + kAccentH, kPaletteW, (the height of this card) - kStatusH
   set the vScrollbar of group "ui_palettescroll" to false
   set the vScroll of group "ui_palettescroll" to 0   -- lay children out in unscrolled card coords
   put kPaletteW - kPalPadX into tRight
   put kPalPadX + kPalGutterW into tGut
   put kTopBarH + kAccentH + 8 into tY
   put tY into tPark                                  -- collapsed rows park here (top of content)
   repeat for each item tTitle in "TOOLS,SHAPES,SPECIAL,TERRAIN,VEHICLES,JOINTS"
      put sectionIds(tTitle) into tIds
      if sectionKind(tTitle) is "joint" then put "ui_joint_" into tPrefix
      else put "ui_tool_" into tPrefix
      put ("ui_hdr_" & tTitle) into tHdr
      put (tTitle is among the lines of gPalOpen) into tOpen
      -- Header reads as a colour-coded bar: filled in the category colour when open,
      -- just the coloured title when collapsed.
      set the rect of button tHdr to kPalPadX, tY, tRight, tY + kPalHeaderH
      set the label of button tHdr to (chevronGlyph(tTitle) && tTitle)
      if tOpen then
         set the opaque of button tHdr to true
         set the backgroundColor of button tHdr to categoryColor(tTitle)
         set the textColor of button tHdr to kColBtnText
      else
         set the opaque of button tHdr to false
         set the textColor of button tHdr to categoryColor(tTitle)
      end if
      add kPalHeaderH to tY
      if tOpen then
         set the rect of graphic ("ui_hdrrule_" & tTitle) to kPalPadX, tY, tRight, tY + 1
         set the visible of graphic ("ui_hdrrule_" & tTitle) to true
         add 6 to tY
         repeat for each item tId in tIds
            put tPrefix & tId into tBtn
            put "ui_g_" & tId into tGlyph
            if there is a button tBtn then
               set the rect of button tBtn to tGut, tY, tRight, tY + kPalBtnH
               set the visible of button tBtn to true
            end if
            if there is a field tGlyph then
               set the rect of field tGlyph to kPalPadX, tY, tGut, tY + kPalBtnH
               set the visible of field tGlyph to true
            end if
            add kPalBtnH + kPalBtnGap to tY
         end repeat
      else
         set the rect of graphic ("ui_hdrrule_" & tTitle) to kPalPadX, tPark, tRight, tPark + 1
         set the visible of graphic ("ui_hdrrule_" & tTitle) to false
         repeat for each item tId in tIds
            if there is a button (tPrefix & tId) then
               set the rect of button (tPrefix & tId) to tGut, tPark, tRight, tPark + kPalBtnH
               set the visible of button (tPrefix & tId) to false
            end if
            if there is a field ("ui_g_" & tId) then
               set the rect of field ("ui_g_" & tId) to kPalPadX, tPark, tGut, tPark + kPalBtnH
               set the visible of field ("ui_g_" & tId) to false
            end if
         end repeat
      end if
      add kPalSectionGap to tY
   end repeat
   unlock screen
end layoutPalette

-- Single-open accordion: opening a category collapses the others, so the toolbox
-- always fits without a scrollbar. Pure chrome - tool selection and the HUD are left
-- untouched. gPalOpen holds at most one category title (empty = all collapsed).
on togglePaletteSection pTitle
   if pTitle is empty then exit togglePaletteSection
   if pTitle is among the lines of gPalOpen then
      put empty into gPalOpen        -- click the open category to close it
   else
      put pTitle into gPalOpen        -- this category becomes the only open one
   end if
   layoutPalette
end togglePaletteSection

-- Right inspector: a title + plain-language help, a block of property adjusters
-- (hidden until a part is selected), and the persistent build options.
on makeInspector
   local tWide, tHigh, tL, tTop, tI, tRy
   put the width of this card into tWide
   put the height of this card into tHigh
   put tWide - kInspectorW into tL
   put kTopBarH + kAccentH into tTop
   makeBar "ui_inspbg", tL, tTop, tWide, tHigh - kStatusH, kColPaletteBg
   makeLabel "ui_insp_title", tL + 12, tTop + 10, tWide - 86, tTop + 34, "Inspector", 14, "236,238,245", true
   makeAction "rename", "Rename", tWide - 78, tTop + 8, 66, 22
   makeField "ui_insp_body", tL + 12, tTop + 40, tWide - 12, tTop + 118, 11, "190,194,206"
   -- settings tabs: group a part's many settings so each pane stays short
   makeAction "tab_shape", "Shape", tL + 12, tTop + 124, 50, 24
   makeAction "tab_physics", "Physics", tL + 64, tTop + 124, 56, 24
   makeAction "tab_collide", "Collide", tL + 122, tTop + 124, 56, 24
   makeAction "tab_special", "Special", tL + 180, tTop + 124, 56, 24
   -- a clearly-marked, divided settings block so adjustable values stand out
   makeBar "ui_settings_div", tL + 12, tTop + 156, tWide - 12, tTop + 157, "60,66,80"
   makeLabel "ui_settings_hdr", tL + 12, tTop + 162, tWide - 96, tTop + 182, "PART SETTINGS", 11, "120,220,150", true
   makeAction "inspmode", "Simple", tWide - 84, tTop + 160, 72, 22   -- simple/advanced detail toggle
   makeField "ui_settings_hint", tL + 12, tTop + 186, tWide - 12, tTop + 250, 11, "150,154,166"
   put tTop + 186 into tRy
   repeat with tI = 1 to kPropRows
      makeField ("ui_prop_lbl_" & tI), tL + 12, tRy + 3, tWide - 92, tRy + 25, 11, "232,236,246"
      makePropBtn ("prop_dec_" & tI), "-", tWide - 84, tRy, 32, 26
      makePropBtn ("prop_inc_" & tI), "+", tWide - 44, tRy, 32, 26
      add 28 to tRy
   end repeat
   add 6 to tRy
   makeBar "ui_options_div", tL + 12, tRy, tWide - 12, tRy + 1, "60,66,80"
   add 8 to tRy
   makeLabel "ui_hdr_OPTIONS", tL + 12, tRy, tWide - 12, tRy + 20, "BUILD OPTIONS", 11, "120,126,140", true
   add 24 to tRy
   makeAction "motor", "Motor", tL + 12, tRy, 74, 26
   makeAction "bouncy", "Bouncy", tL + 92, tRy, 80, 26
   add 32 to tRy
   makeLabel "ui_lbl_speed", tL + 12, tRy + 2, tWide - 92, tRy + 22, "Motor speed", 11, "168,172,184", false
   makeAction "spddn", "-", tWide - 84, tRy, 32, 26
   makeAction "spdup", "+", tWide - 44, tRy, 32, 26
   add 34 to tRy
   makeAction "gravity", "Gravity: Normal", tL + 12, tRy, kInspectorW - 24, 26
   add 32 to tRy
   makeAction "worldfeel", "Feel: Default", tL + 12, tRy, kInspectorW - 24, 26
   add 32 to tRy
   makeAction "pause", "Pause", tL + 12, tRy, 108, 26
   makeAction "step", "Step", tL + 128, tRy, 80, 26
   clearPropRows
   refreshSpeedLabel
   refreshGravityLabel
   refreshWorldFeelLabel
   refreshInspectorModeLabel
end makeInspector

-- A prominent accent-green +/- button for adjusting a part's settings.
on makePropBtn pId, pLabel, pX, pY, pW, pH
   makeAction pId, pLabel, pX, pY, pW, pH
   setBtnActive ("ui_act_" & pId), kColAccentGreen
   set the textStyle of button ("ui_act_" & pId) to "bold"
end makePropBtn

on refreshSpeedLabel
   if there is a field "ui_lbl_speed" then put "Motor speed: " & gMotorSpeed & " deg/s" into field "ui_lbl_speed"
end refreshSpeedLabel

-- Show (or hide) the hint/preview line of the settings block. The field shares
-- space with the settings rows (both start at the block's top), so when rows
-- are visible the caller passes their count and the field is re-parked just
-- BELOW the last row - never drawn over the rows, which is exactly how the
-- "Simple mode hides..." notice and the special-part previews used to end up
-- overlapping the settings. If the rows leave no room, the text is dropped.
on setSettingsHint pText, pBelowRows
   if there is not a field "ui_settings_hint" then exit setSettingsHint
   local tL, tTop, tY0, tRows, tHintTop, tHintBottom, tLimit
   put (the width of this card) - kInspectorW into tL
   put kTopBarH + kAccentH into tTop
   put tTop + 186 into tY0                        -- first settings row (mirrors makeInspector)
   put numOr(pBelowRows, 0) into tRows
   put tY0 + tRows * 28 into tHintTop
   if tRows > 0 then add 4 to tHintTop
   put tY0 + kPropRows * 28 + 2 into tLimit       -- stay clear of BUILD OPTIONS below
   if tHintTop + 18 > tLimit then put empty into pText   -- a full tab of rows wins
   put min(tHintTop + 64, tLimit) into tHintBottom
   set the rect of field "ui_settings_hint" to tL + 12, tHintTop, (the width of this card) - 12, tHintBottom
   put pText into field "ui_settings_hint"
   set the visible of field "ui_settings_hint" to (pText is not empty)
end setSettingsHint

on makeStatusBar
   local tWide, tHigh
   put the width of this card into tWide
   put the height of this card into tHigh
   makeBar "ui_statusbar", 0, tHigh - kStatusH, tWide, tHigh, "18,20,26"
   makeField "ui_status", 12, tHigh - kStatusH + 3, tWide - 12, tHigh - 4, 11, "200,206,220"
end makeStatusBar

on makeAction pId, pLabel, pX, pY, pW, pH
   makeButton ("ui_act_" & pId), pLabel, pX, pY, pW, pH
   set the uActId of button ("ui_act_" & pId) to pId
   setBtnIdle ("ui_act_" & pId)
end makeAction

-- Delete the chrome. Collect first, then delete, and only touch *top-level*
-- ui_ controls - deleting the palette group cascades to its grouped buttons.
on clearUI
   local tI, tCtrl, tKill
   put empty into tKill
   repeat with tI = 1 to the number of controls of this card
      put the long id of control tI of this card into tCtrl
      if char 1 to 3 of the short name of tCtrl is "ui_" and word 1 of the owner of tCtrl is "card" \
            then put tCtrl & cr after tKill
   end repeat
   repeat for each line tCtrl in tKill
      if there is a tCtrl then delete tCtrl
   end repeat
end clearUI

on clearSceneControls
   local tI, tName
   repeat with tI = the number of controls of this card down to 1
      put the short name of control tI of this card into tName
      if char 1 to 3 of tName is not "ui_" then delete control tI of this card
   end repeat
end clearSceneControls

-- Keep all chrome above the parts and joint markers. Only raise *top-level* ui_
-- controls (the palette group rises as a unit; raising its members individually
-- would pull them out of the group).
on raiseUI
   local tI, tCtrl, tList
   put empty into tList
   repeat with tI = 1 to the number of controls of this card
      put the long id of control tI of this card into tCtrl
      if char 1 to 3 of the short name of tCtrl is "ui_" and word 1 of the owner of tCtrl is "card" \
            then put tCtrl & cr after tList
   end repeat
   repeat for each line tCtrl in tList
      if there is a tCtrl then set the layer of tCtrl to top
   end repeat
end raiseUI

on makeBar pName, pLeft, pTop, pRight, pBottom, pColor
   create graphic pName
   set the style of graphic pName to "rectangle"
   set the filled of graphic pName to true
   set the lineSize of graphic pName to 0
   set the backgroundColor of graphic pName to pColor
   set the rect of graphic pName to pLeft, pTop, pRight, pBottom
end makeBar

on makeLabel pName, pLeft, pTop, pRight, pBottom, pText, pSize, pColor, pBold
   create field pName
   set the rect of field pName to pLeft, pTop, pRight, pBottom
   set the locked of field pName to true
   set the traversalOn of field pName to false
   set the opaque of field pName to false
   set the showBorder of field pName to false
   set the borderWidth of field pName to 0
   set the textSize of field pName to pSize
   set the textColor of field pName to pColor
   if pBold then set the textStyle of field pName to "bold"
   put pText into field pName
end makeLabel

on makeField pName, pLeft, pTop, pRight, pBottom, pSize, pColor
   create field pName
   set the rect of field pName to pLeft, pTop, pRight, pBottom
   set the locked of field pName to true
   set the traversalOn of field pName to false
   set the opaque of field pName to false
   set the showBorder of field pName to false
   set the borderWidth of field pName to 0
   set the textSize of field pName to pSize
   set the textColor of field pName to pColor
   set the margins of field pName to 6
end makeField

on makeButton pName, pLabel, pX, pY, pW, pH
   create button pName
   set the label of button pName to pLabel
   set the autoHilite of button pName to false
   set the opaque of button pName to true
   set the showBorder of button pName to false
   set the threeD of button pName to false
   set the textSize of button pName to 11
   set the rect of button pName to pX, pY, pX + pW, pY + pH
end makeButton

-- Idle / active button styling in one place, so the colours never drift apart and
-- the hover helper can reason about selection state instead of reading pixels.
on setBtnIdle pBtn
   if there is not a button pBtn then exit setBtnIdle
   set the backgroundColor of button pBtn to kColBtnIdle
   set the textColor of button pBtn to kColBtnIdleText
end setBtnIdle

on setBtnActive pBtn, pColor
   if there is not a button pBtn then exit setBtnActive
   set the backgroundColor of button pBtn to pColor
   set the textColor of button pBtn to kColBtnText
end setBtnActive

-- Repaint every palette button. Each category's selected tool lights up in that
-- category's accent colour (Delete stays red); joints use the JOINTS accent.
on highlightAll
   highlightGroup "ui_tool_", kEditTools, gTool, (gJointTool is empty), categoryColor("TOOLS")
   highlightGroup "ui_tool_", kShapeTools, gTool, (gJointTool is empty), categoryColor("SHAPES")
   highlightGroup "ui_tool_", kSpecialTools, gTool, (gJointTool is empty), categoryColor("SPECIAL")
   highlightGroup "ui_tool_", kTerrainTools, gTool, (gJointTool is empty), categoryColor("TERRAIN")
   highlightGroup "ui_tool_", kVehicleTools, gTool, (gJointTool is empty), categoryColor("VEHICLES")
   highlightGroup "ui_joint_", kJointTools, gJointTool, true, categoryColor("JOINTS")
   highlightActions
end highlightAll

-- One palette group's selected/idle styling. The Delete tool flags red when active.
on highlightGroup pPrefix, pItems, pActiveId, pEnabled, pActiveColor
   local tItem, tBtn, tOn
   repeat for each item tItem in pItems
      put pPrefix & tItem into tBtn
      if there is not a button tBtn then next repeat
      put (tItem is pActiveId and pEnabled) into tOn
      if tOn and tItem is "delete" then
         setBtnActive tBtn, kColDanger
      else if tOn then
         setBtnActive tBtn, pActiveColor
      else
         setBtnIdle tBtn
      end if
   end repeat
end highlightGroup

on highlightActions
   local tAccent, tSub
   if there is a button "ui_act_mode" then
      if gMode is "run" then
         set the label of button "ui_act_mode" to "Build"
         setBtnActive "ui_act_mode", kColDanger
      else
         set the label of button "ui_act_mode" to "Run"
         setBtnActive "ui_act_mode", kColAccentGreen
      end if
   end if
   -- the Play button stands out (blue), turning amber 'Stop' while a puzzle runs
   if there is a button "ui_act_play" then
      if gPlaying then
         set the label of button "ui_act_play" to "Stop"
         setBtnActive "ui_act_play", kColAccentAmber
      else
         set the label of button "ui_act_play" to "Play"
         setBtnActive "ui_act_play", kColToggleBlue
      end if
   end if
   -- A clear, full-width cue for which mode you're in: green accent + neutral
   -- subtitle while building; amber accent + a "running" subtitle while simulating.
   if gMode is "run" then
      put "232,150,60" into tAccent
      put "RUNNING - drag parts to play; press Build or Reset to edit" into tSub
   else
      put kColAccentGreen into tAccent
      put "Contraption Builder - build a machine, then press Run to bring it to life" into tSub
   end if
   if there is a graphic "ui_accent" then set the backgroundColor of graphic "ui_accent" to tAccent
   if there is a field "ui_sub" then set the text of field "ui_sub" to tSub
   setToggle "ui_act_motor", gMotorOn
   setToggle "ui_act_bouncy", gBouncy
end highlightActions

on setToggle pBtn, pOn
   if there is not a button pBtn then exit setToggle
   if pOn then
      setBtnActive pBtn, kColToggleBlue
   else
      setBtnIdle pBtn
   end if
end setToggle

-- =====================================================================
-- Input
-- =====================================================================
on mouseDown
   if "ui_" is in the short name of the target then exit mouseDown
   if b2kWorld() is empty then
      startCB
      exit mouseDown
   end if
   local tx, ty, tHit
   put the mouseH into tx
   put the mouseV into ty
   if gMode is "run" then
      if the shiftKey is down then       -- Shift-click kicks the body under the pointer
         kickPartAt tx, ty
         exit mouseDown
      end if
      get b2kGrab(tx, ty)
      if it is not empty then put "run" into gDragMode
      exit mouseDown
   end if
   -- build mode
   if gJointTool is not empty then
      jointClick tx, ty
      exit mouseDown
   end if
   -- Draw tool: press-drag to sketch a ground line (built on release).
   if gTool is "draw" then
      if inArena(tx, ty) then beginDrawTerrain tx, ty
      exit mouseDown
   end if
   -- Drag tool: a click on a joint marker selects that joint for editing.
   if gTool is "drag" then
      local tJHit
      put jointUnderClick(tx, ty) into tJHit
      if tJHit is not empty then
         selectJoint tJHit
         exit mouseDown
      end if
   end if
   put partUnderClick(tx, ty) into tHit
   if gTool is "delete" then
      if tHit is not empty then
         deletePart tHit
         renderBuild
         updateHud
      end if
      exit mouseDown
   end if
   if gTool is "duplicate" then
      if tHit is not empty then duplicatePart tHit
      exit mouseDown
   end if
   if gTool is "multiply" then
      if tHit is not empty then multiplyPart tHit
      exit mouseDown
   end if
   if gTool is "link" then
      handleLinkClick tHit
      exit mouseDown
   end if
   if tHit is not empty then
      put tHit into gDragCtrl
      put "build" into gDragMode
      put false into gDragMoved
      selectPart tHit
   else
      if gTool is not "drag" and inArena(tx, ty) then
         put placePart(tx, ty) into gDragCtrl   -- drop it, then let the user drag it
         if gDragCtrl is not empty then
            put "build" into gDragMode
            put false into gDragMoved
         end if
      else
         deselectPart                           -- clicked empty space; clear selection
      end if
   end if
end mouseDown

on mouseMove pX, pY
   if gDragMode is "draw" then
      extendDrawTerrain pX, pY
      exit mouseMove
   end if
   if gDragMode is "build" and gDragCtrl is not empty then
      local tCx, tCy, tOld, tDx, tDy, tGroup, tP, tHw, tHh
      put max(gArenaL, min(gArenaR, pX)) into tCx
      put max(gArenaT, min(gArenaB, pY)) into tCy
      if the uKind of gDragCtrl is "laser" then       -- drag a laser by its emitter, not the beam midpoint
         set the points of gDragCtrl to round(tCx) & "," & round(tCy) & cr & (line 2 of the points of gDragCtrl)
         drawLaserBeam gDragCtrl
         put true into gDragMoved
         exit mouseMove
      end if
      -- keep the whole rect on the stage, not just its centre, so a wide or
      -- tall part can't be parked half-over the side panels or the ground bar
      put min((the width of gDragCtrl) div 2, (gArenaR - gArenaL) div 2) into tHw
      put min((the height of gDragCtrl) div 2, (gArenaB - gArenaT) div 2) into tHh
      put max(gArenaL + tHw, min(gArenaR - tHw, tCx)) into tCx
      put max(gArenaT + tHh, min(gArenaB - tHh, tCy)) into tCy
      put the loc of gDragCtrl into tOld
      put round(tCx) - item 1 of tOld into tDx       -- how far the grabbed part moved
      put round(tCy) - item 2 of tOld into tDy
      set the loc of gDragCtrl to round(tCx) & "," & round(tCy)
      -- a grouped assembly (e.g. a car) moves as one: shift its other parts too
      put the uGroup of gDragCtrl into tGroup
      if tGroup is not empty then
         repeat for each line tP in gParts
            if tP is empty or tP is gDragCtrl then next repeat
            if the uGroup of tP is tGroup then
               set the loc of tP to (item 1 of the loc of tP + tDx) & "," & (item 2 of the loc of tP + tDy)
            end if
         end repeat
      end if
      put true into gDragMoved
      renderJoints
   end if
end mouseMove

on mouseUp
   if "ui_" is in the short name of the target then
      handleUiClick
      exit mouseUp
   end if
   endDrag
end mouseUp

-- Finish an in-progress drag/draw and clear the drag state. Shared by mouseUp
-- (released over the same control) and mouseRelease (released elsewhere, e.g. over
-- a side panel) so the two paths can never diverge: both must reseat a build-drag's
-- body and finalise a freehand draw, not just release a run-grab.
on endDrag
   if gDragMode is "draw" then
      finishDrawTerrain
   else if gDragMode is "build" and gDragCtrl is not empty and gDragMoved then
      local tGroup, tP
      reseatDragged gDragCtrl
      put the uGroup of gDragCtrl into tGroup
      if tGroup is not empty then
         repeat for each line tP in gParts
            if tP is not empty and tP is not gDragCtrl and the uGroup of tP is tGroup then reseatDragged tP
         end repeat
      end if
      renderBuild
   else if gDragMode is "run" then
      b2kRelease
   end if
   put empty into gDragCtrl
   put empty into gDragMode
end endDrag

-- Re-seat a dragged part's body where its graphic was dropped (angle preserved).
on reseatDragged pCtrl
   if pCtrl is empty or not kindHasBody(the uKind of pCtrl) then exit reseatDragged
   local tLoc
   put the loc of pCtrl into tLoc
   b2kMoveTo pCtrl, item 1 of tLoc, item 2 of tLoc, b2kAngle(pCtrl)
end reseatDragged

-- Pull a part's whole RECT inside the arena (placement clamps only the click
-- point, so a part dropped near an edge could overhang the palette, the
-- inspector or the ground bar). Re-seats the body if the graphic moved. The
-- laser is exempt: its graphic is the beam line, whose bbox is not its footprint.
on clampPartToArena pCtrl
   if pCtrl is empty then exit clampPartToArena
   if the uKind of pCtrl is "laser" then exit clampPartToArena
   local tLoc, tHw, tHh, tCx, tCy
   set the itemDelimiter to comma
   put the loc of pCtrl into tLoc
   put min((the width of pCtrl) div 2, (gArenaR - gArenaL) div 2) into tHw
   put min((the height of pCtrl) div 2, (gArenaB - gArenaT) div 2) into tHh
   put max(gArenaL + tHw, min(gArenaR - tHw, item 1 of tLoc)) into tCx
   put max(gArenaT + tHh, min(gArenaB - tHh, item 2 of tLoc)) into tCy
   if (tCx & "," & tCy) is tLoc then exit clampPartToArena
   set the loc of pCtrl to tCx & "," & tCy
   reseatDragged pCtrl
end clampPartToArena

-- The engine sends mouseRelease (not mouseUp) when the pointer is let go over a
-- different control than the one that got mouseDown - e.g. dragging a part toward
-- the right edge and releasing over the inspector. Route it through the same
-- endDrag so the move/draw is never lost.
on mouseRelease
   endDrag
end mouseRelease

-- =====================================================================
-- Keyboard: Delete removes the selection, Escape cancels/closes, arrows
-- nudge the selected part. These are stack-level messages, so they only
-- arrive when no dialog or editable field has keyboard focus.
-- =====================================================================
on deleteKey
   deleteSelection
end deleteKey

on backspaceKey
   deleteSelection
end backspaceKey

on deleteSelection
   if gMode is not "build" then
      put "Switch back to Build before deleting parts." into gStatus
      updateHud
      exit deleteSelection
   end if
   if gSelJoint is not empty then
      removeJointAt gSelJoint
      renderBuild
      put "Deleted the selected joint." into gStatus
   else if gSelPart is not empty then
      deletePart gSelPart
      renderBuild
   else
      put "Nothing selected - click a part (or a joint marker) first." into gStatus
   end if
   updateHud
end deleteSelection

-- Escape walks outward: close an open overlay first, then cancel a half-made
-- joint/wire, then clear the selection. One press per layer, like any editor.
on escapeKey
   if there is a graphic "ui_onb_scrim" then
      dismissOnboarding
   else if there is a graphic "ui_recipescrim" and the visible of graphic "ui_recipescrim" then
      hideRecipesMenu
   else if there is a graphic "ui_filterscrim" and the visible of graphic "ui_filterscrim" then
      hideFilterPanel
   else if there is a graphic "ui_worldscrim" and the visible of graphic "ui_worldscrim" then
      hideWorldPanel
   else if there is a graphic "ui_imgscrim" and the visible of graphic "ui_imgscrim" then
      hideImagePanel
   else if gWireSrc is not empty then
      put empty into gWireSrc
      put "Wire cancelled." into gStatus
   else if gPendCtrl is not empty then
      resetPend
      put "Joint cancelled." into gStatus
   else
      deselectJoint
      deselectPart
      put "Selection cleared." into gStatus
   end if
   updateHud
end escapeKey

-- Arrow keys nudge the selected part 1 px (Shift: 10 px) in Build mode, with
-- the same group-follow, clamping and body re-seat as a mouse drag.
on arrowKey pKey
   local tDx, tDy, tStep, tGroup, tP, tPt
   if gMode is not "build" or gSelPart is empty then pass arrowKey
   if gSelPart is not among the lines of gParts then pass arrowKey
   put 1 into tStep
   if the shiftKey is down then put 10 into tStep
   put 0 into tDx
   put 0 into tDy
   switch pKey
      case "left"
         put - tStep into tDx
         break
      case "right"
         put tStep into tDx
         break
      case "up"
         put - tStep into tDy
         break
      case "down"
         put tStep into tDy
         break
      default
         pass arrowKey
   end switch
   set the itemDelimiter to comma
   if the uKind of gSelPart is "laser" then        -- nudge the emitter, like a drag does
      put line 1 of the points of gSelPart into tPt
      set the points of gSelPart to ((item 1 of tPt) + tDx) & "," & ((item 2 of tPt) + tDy) \
            & cr & (line 2 of the points of gSelPart)
      drawLaserBeam gSelPart
      exit arrowKey
   end if
   set the loc of gSelPart to ((item 1 of the loc of gSelPart) + tDx) & "," & ((item 2 of the loc of gSelPart) + tDy)
   put the uGroup of gSelPart into tGroup
   if tGroup is not empty then                     -- a grouped assembly moves as one
      repeat for each line tP in gParts
         if tP is empty or tP is gSelPart then next repeat
         if the uGroup of tP is tGroup then
            set the loc of tP to ((item 1 of the loc of tP) + tDx) & "," & ((item 2 of the loc of tP) + tDy)
            reseatDragged tP
         end if
      end repeat
   end if
   clampPartToArena gSelPart
   reseatDragged gSelPart
   renderBuild
end arrowKey

-- Shift-click during Run kicks the dynamic body under the pointer: a sharp,
-- mass-aware upward impulse with a little sideways scatter, plus a tumble. Shows
-- off the one-shot b2kImpulse / b2kAngularImpulse force handlers.
on kickPartAt pX, pY
   local tHit
   put b2kControlAt(pX, pY) into tHit
   if tHit is empty then exit kickPartAt
   if b2kBodyType(tHit) is not "dynamic" then exit kickPartAt
   b2kImpulse tHit, (random(401) - 200), -380       -- up, with random horizontal scatter
   b2kAngularImpulse tHit, (random(481) - 240)       -- a tumble either way
   put "Kicked it! Shift-click any moving part during Run to bat it around." into gStatus
   updateHud
end kickPartAt

on handleUiClick
   local tName, tId
   put the short name of the target into tName
   if tName is "ui_recipescrim" then
      hideRecipesMenu
      exit handleUiClick
   end if
   if tName is "ui_filterscrim" then
      hideFilterPanel
      exit handleUiClick
   end if
   if tName is "ui_worldscrim" then
      hideWorldPanel
      exit handleUiClick
   end if
   if tName is "ui_imgscrim" then
      hideImagePanel
      exit handleUiClick
   end if
   -- Click a settings value to type an exact number (steppers stay on the +/- keys).
   if "ui_prop_lbl_" is in tName then
      editPropValue (the uPropKey of the target)
      exit handleUiClick
   end if
   -- Click a palette section header to collapse / expand it (pure chrome, no selection).
   if "ui_hdr_" is in tName then
      togglePaletteSection (the uHdr of the target)
      exit handleUiClick
   end if
   -- Picking a build tool while the simulation runs drops you back into Build.
   if ("ui_tool_" is in tName or "ui_joint_" is in tName) and gMode is "run" then toggleMode
   if "ui_tool_" is in tName then
      put the uToolId of the target into gTool
      put empty into gJointTool
      resetPend
      deselectPart
      deselectJoint
      put "Tool: " & niceName(gTool) & "." into gStatus
      showInspectorForTool
   else if "ui_joint_" is in tName then
      put the uJointId of the target into gJointTool
      resetPend
      deselectPart
      deselectJoint
      put niceName(gJointTool) & " - click part A, then part B." into gStatus
      showInspectorForTool
   else if "ui_act_" is in tName then
      put the uActId of the target into tId
      handleAction tId
   end if
   highlightAll
   updateHud
end handleUiClick

on handleAction pId
   if char 1 to 5 of pId is "prop_" then
      adjustProp pId
      exit handleAction
   end if
   if char 1 to 4 of pId is "tab_" then
      selectInspTab (char 5 to -1 of pId)
      exit handleAction
   end if
   if char 1 to 5 of pId is "filt_" then
      handleFilterToggle pId
      exit handleAction
   end if
   if char 1 to 5 of pId is "wopt_" then
      handleWorldToggle pId
      exit handleAction
   end if
   if char 1 to 6 of pId is "asset_" then
      placeAssetFromPanel (char 7 to -1 of pId)
      exit handleAction
   end if
   if char 1 to 10 of pId is "imgremove_" then
      removeFromLibrary (char 11 to -1 of pId)
      exit handleAction
   end if
   switch pId
      case "mode"
         if gPlaying then stopPlay      -- leaving Run also leaves Play
         else toggleMode
         break
      case "reset"
         resetMachine
         break
      case "clear"
         clearAll
         break
      case "save"
         saveContraption
         break
      case "load"
         loadContraption
         break
      case "motor"
         put not gMotorOn into gMotorOn
         if gMotorOn then put "Motor ON for new Hinge/Wheel joints (" & gMotorSpeed & " deg/s)." into gStatus
         else put "Motor OFF." into gStatus
         break
      case "bouncy"
         put not gBouncy into gBouncy
         if gBouncy then put "Bouncy material ON for new parts." into gStatus
         else put "Bouncy material OFF." into gStatus
         break
      case "spddn"
         put max(kMotorMin, gMotorSpeed - 30) into gMotorSpeed
         put "Motor speed: " & gMotorSpeed & " deg/s." into gStatus
         refreshSpeedLabel
         break
      case "spdup"
         put min(kMotorMax, gMotorSpeed + 30) into gMotorSpeed
         put "Motor speed: " & gMotorSpeed & " deg/s." into gStatus
         refreshSpeedLabel
         break
      case "gravity"
         cycleGravity
         break
      case "worldfeel"
         cycleWorldFeel
         break
      case "pause"
         togglePause
         break
      case "step"
         stepOnce
         break
      case "recipes"
         toggleRecipesMenu
         break
      case "info"
         startOnboarding
         break
      case "recipeclose"
         hideRecipesMenu
         break
      case "filterclose"
         hideFilterPanel
         break
      case "play"
         if gPlaying then stopPlay
         else startPlay
         break
      case "winagain"
         playAgain
         break
      case "winkeep"
         hideWin
         break
      case "winedit"
         stopPlay
         break
      case "rename"
         renamePart gSelPart
         break
      case "inspmode"
         toggleInspectorMode
         break
      case "worldadv"
         openWorldPanel
         break
      case "images"
         openImagePanel
         break
      case "imgimport"
         importToLibrary
         break
      case "imgclose"
         hideImagePanel
         break
      case "worldclose"
         hideWorldPanel
         break
      case "cart"
         hideRecipesMenu
         buildSampleCart
         break
      case "swing"
         hideRecipesMenu
         buildSampleSwing
         break
      case "balloonlift"
         hideRecipesMenu
         buildRecipeBalloonLift
         break
      case "platebomb"
         hideRecipesMenu
         buildRecipePlateBomb
         break
      case "chainpuzzle"
         hideRecipesMenu
         buildRecipeChainPuzzle
         break
      case "fantower"
         hideRecipesMenu
         buildRecipeFanTower
         break
      case "magnetcatch"
         hideRecipesMenu
         buildRecipeMagnetCatch
         break
      case "catapult"
         hideRecipesMenu
         buildRecipeCatapult
         break
      case "cannon"
         hideRecipesMenu
         buildRecipeCannon
         break
      case "trebuchet"
         hideRecipesMenu
         buildRecipeTrebuchet
         break
      case "crane"
         hideRecipesMenu
         buildRecipeCrane
         break
      case "wreckingball"
         hideRecipesMenu
         buildRecipeWreckingBall
         break
      case "cradle"
         hideRecipesMenu
         buildRecipeCradle
         break
      case "dominoes"
         hideRecipesMenu
         buildRecipeDominoes
         break
      case "terrainrun"
         hideRecipesMenu
         buildRecipeTerrainRun
         break
      case "stress"
         hideRecipesMenu
         stressTest
         break
      case "onbnext"
         onboardingNext
         break
      case "onbskip"
         dismissOnboarding
         break
   end switch
end handleAction

on toggleMode
   if gMode is "build" then
      put serializeText() into gPreRun   -- remember the layout so Reset can restore it
      put "run" into gMode
      put empty into gJointTool
      resetPend
      deselectJoint
      put true into gMotorsRunning
      put empty into gSensorCount   -- every sensor zone starts empty each Run
      resetGoals                    -- and every goal starts unsolved (clears any lit colour from a prior run)
      deleteByPrefix "cb_wire_"     -- wires are a build-time authoring aid; hide them during Run
      armFuses
      armThrusters
      b2kStart                      -- fresh loop: gravity, motors, mouse drag
      applyWorldFeel                -- re-apply the world-tuning preset to the live world
      applyWorldOptions             -- and the advanced solver toggles (CCD, sleeping, substeps...)
      armMotors                     -- re-establish each joint's designed motor state
      armLaunches                   -- fire each part's initial push/spin
      put "Run - gravity & motors live. Drag bodies; Shift-click to kick." into gStatus
   else
      put "build" into gMode
      put empty into gFps
      b2kStop                       -- freeze the loop; parts hold their place
      deleteByPrefix "cb_flame_"    -- thruster exhaust is a Run-only effect
      if gPlaying then              -- any path back to Build also leaves Play cleanly
         put false into gPlaying
         hideWin
         setPlayChrome false
         if there is a button "ui_act_play" then set the label of button "ui_act_play" to "Play"
      end if
      renderBuild
      put "Build mode - arrange parts and connect joints, then press Run." into gStatus
   end if
   highlightAll
   refreshPauseLabel
end toggleMode

-- The part under a click: prefer the actual control clicked, then fall back to
-- the physics point query (reliable even for thin static anchors).
function partUnderClick pX, pY
   local tT
   put the long id of the target into tT
   if tT is among the lines of gParts then return tT
   return b2kControlAt(pX, pY)
end partUnderClick

-- The part under a point, ignoring one part (so overlapping parts connect).
function otherPartAt pX, pY, pExclude
   local tHit
   put b2kControlAt(pX, pY) into tHit
   if tHit is pExclude and pExclude is not empty then
      b2kDisable pExclude               -- hide A, re-query for the part beneath it
      put b2kControlAt(pX, pY) into tHit
      b2kEnable pExclude
   end if
   return tHit
end otherPartAt

-- True when a screen point is inside the play field (keeps parts off the chrome).
function inArena pX, pY
   return pX >= gArenaL and pX <= gArenaR and pY >= gArenaT and pY <= gArenaB
end inArena

-- =====================================================================
-- Placing parts
-- =====================================================================
function placePart pX, pY
   local tCtrl
   put empty into tCtrl
   switch gTool
      case "box"
         put placeBox(pX, pY, rnd(kBoxMin, kBoxMax), rnd(kBoxMin, kBoxMax), randomColor()) into tCtrl
         break
      case "ball"
         put placeBall(pX, pY, rnd(kBallMin, kBallMax), randomColor()) into tCtrl
         break
      case "capsule"
         put placeCapsule(pX, pY, rnd(kCapLenMin, kCapLenMax), kCapThick, randomColor()) into tCtrl
         break
      case "poly"
         put placePoly(pX, pY, rnd(kPolyMin, kPolyMax), randomColor()) into tCtrl
         break
      case "anchor"
         put placeAnchor(pX, pY) into tCtrl
         break
      case "platform"
      case "ramp"
      case "hill"
         put placeTerrain(gTool, pX, pY) into tCtrl
         break
      case "car"
         put placeVehicle(pX, pY) into tCtrl
         break
      case "image"
         put importImage(pX, pY) into tCtrl
         break
      case "balloon"
         put placeBalloon(pX, pY) into tCtrl
         break
      case "bomb"
         put placeBomb(pX, pY) into tCtrl
         break
      case "plate"
         put placePlate(pX, pY) into tCtrl
         break
      case "sensor"
         put placeSensor(pX, pY) into tCtrl
         break
      case "fan"
         put placeFan(pX, pY) into tCtrl
         break
      case "magnet"
         put placeMagnet(pX, pY) into tCtrl
         break
      case "laser"
         put placeLaser(pX, pY) into tCtrl
         break
      case "thruster"
         put placeThruster(pX, pY) into tCtrl
         break
      case "goal"
         put placeGoal(pX, pY) into tCtrl
         break
      default
         return empty
   end switch
   if tCtrl is not empty then
      clampPartToArena tCtrl        -- an edge click must not seed a part overlapping the chrome
      renderBuild                   -- draw the new part right away (no Run needed)
      put "Placed a " & friendlyKind(gTool) & ". Drag to move it; the inspector on the right explains it." into gStatus
      selectPart tCtrl
      updateHud
   end if
   return tCtrl
end placePart

function placeBox pX, pY, pW, pH, pColor
   local tCtrl
   b2kSpawnBox pX, pY, pW, pH, pColor
   put the result into tCtrl
   tagPart tCtrl, "box", pColor, empty
   return tCtrl
end placeBox

function placeBall pX, pY, pDiam, pColor
   local tCtrl
   b2kSpawnBall pX, pY, pDiam, pColor
   put the result into tCtrl
   tagPart tCtrl, "ball", pColor, empty
   return tCtrl
end placeBall

function placeCapsule pX, pY, pLen, pThick, pColor
   local tCtrl
   b2kSpawnCapsule pX, pY, pLen, pThick, pColor
   put the result into tCtrl
   tagPart tCtrl, "capsule", pColor, empty
   return tCtrl
end placeCapsule

function placePoly pX, pY, pR, pColor
   local tName, tRef, tI, tAng, tPoints
   put "cb_poly_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "polygon"
   set the filled of tRef to true
   set the backgroundColor of tRef to pColor
   set the foregroundColor of tRef to "20,20,24"
   set the lineSize of tRef to 1
   put empty into tPoints
   repeat with tI = 0 to 5
      put tI * 60 * kPI / 180 into tAng
      put round(pX + pR * cos(tAng)) & "," & round(pY + pR * sin(tAng)) & cr after tPoints
   end repeat
   set the points of tRef to tPoints
   b2kAddPolygon tRef
   tagPart tRef, "poly", pColor, empty
   return tRef
end placePoly

function placeAnchor pX, pY
   local tName, tRef
   put "cb_anchor_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "rectangle"
   set the filled of tRef to true
   set the backgroundColor of tRef to "120,126,140"
   set the foregroundColor of tRef to "210,214,224"
   set the lineSize of tRef to 2
   set the width of tRef to 26
   set the height of tRef to 26
   set the loc of tRef to round(pX) & "," & round(pY)
   b2kAddStatic tRef
   tagPart tRef, "anchor", "120,126,140", empty
   return tRef
end placeAnchor

-- =====================================================================
-- Terrain: static scenery the dynamic parts rest on, roll down and bump
-- into. Each piece is a convex polygon graphic attached as a *static*
-- polygon body, so the Kit's sync skips it (it never moves) and we draw it
-- once. Rotation is baked into the points (the body angle stays 0), so a
-- ramp can tilt without the per-frame redraw a static body never receives.
-- =====================================================================

-- The static scenery kinds, handled together wherever they differ from parts.
function kindIsTerrain pKind
   return pKind is among the items of "platform,ramp,hill"
end kindIsTerrain

-- Default unrotated size for a fresh terrain piece, as "w,h" in pixels.
function terrainDefault pKind
   switch pKind
      case "ramp"
         return "130,82"
      case "hill"
         return "172,84"
   end switch
   return "150,26"                            -- platform: a wide, shallow ledge
end terrainDefault

-- A terrain piece's earthy default fill colour.
function terrainColor pKind
   switch pKind
      case "ramp"
         return "150,120,84"                  -- packed dirt
      case "hill"
         return "96,132,86"                   -- grassy mound
   end switch
   return "108,116,128"                       -- platform: stone
end terrainColor

-- Screen-space points for a terrain outline: the canonical shape scaled to
-- pW x pH with its bounding box centred on (pCx,pCy), optionally mirrored
-- left<->right (pFlip, for ramps facing the other way), then rotated pAngleDeg
-- about the centre. Convex and <= 8 verts, so b2kAddPolygon accepts it.
function terrainPoints pKind, pCx, pCy, pW, pH, pAngleDeg, pFlip
   local tHw, tHh, tBase, tPt, tx, ty, tC, tS, tA, tRot
   local tBumps, tNh, tIh, tT, tEnv, tBump, tHx, tHy, tYBase
   set the itemDelimiter to comma                -- we parse "x,y" points below
   put pW / 2 into tHw
   put pH / 2 into tHh
   if pFlip is true then put - tHw into tHw      -- mirror about the centre (ramps)
   switch pKind
      case "ramp"
         -- right triangle: flat base, upright high edge, slope rising to one side
         put (pCx - tHw) & "," & (pCy + tHh) & cr & (pCx + tHw) & "," & (pCy + tHh) \
               & cr & (pCx + tHw) & "," & (pCy - tHh) into tBase
         break
      case "hill"
         -- Rolling ground: a flat base with an undulating top. The bump count
         -- grows with width, so a narrow hill is a single dome and a wide one
         -- rolls. placeTerrain turns this outline into a smooth chain, so a fast
         -- body rides over the bumps without catching on any seam.
         put max(1, round(pW / 200)) into tBumps
         put 6 * (tBumps + 1) into tNh                       -- top samples
         put pCy + tHh into tYBase
         -- order base-left, top LEFT->RIGHT, base-right: as a closed chain loop
         -- this puts the solid side below the surface (Box2D: solid = right of
         -- the travel direction), so bodies rest ON the hill rather than fall through.
         put (pCx - tHw) & "," & tYBase into tBase           -- base-left
         repeat with tIh = 1 to tNh - 1                      -- interior top points, left -> right
            put tIh / tNh into tT
            put sin(tT * kPI) into tEnv                       -- 0 at the ends -> meets the base
            put 0.62 + 0.38 * (0.5 - 0.5 * cos(tT * tBumps * 2 * kPI)) into tBump
            put pCx - tHw + tT * pW into tHx
            put tYBase - pH * tEnv * tBump into tHy
            put cr & round(tHx) & "," & round(tHy) after tBase
         end repeat
         put cr & (pCx + tHw) & "," & tYBase after tBase     -- base-right (loop closes to base-left)
         put reversedLines(tBase) into tBase                 -- wind so the chain's solid side faces OUT (bodies rest on top)
         break
      default
         -- platform: an axis-aligned rectangle
         put (pCx - tHw) & "," & (pCy - tHh) & cr & (pCx + tHw) & "," & (pCy - tHh) & cr \
               & (pCx + tHw) & "," & (pCy + tHh) & cr & (pCx - tHw) & "," & (pCy + tHh) into tBase
   end switch
   put ((round(pAngleDeg) mod 360) + 360) mod 360 into tA
   if tA is 0 then return tBase
   put cos(tA * kPI / 180) into tC
   put sin(tA * kPI / 180) into tS
   put empty into tRot
   repeat for each line tPt in tBase
      put (item 1 of tPt) - pCx into tx
      put (item 2 of tPt) - pCy into ty
      put round(pCx + tx * tC - ty * tS) & "," & round(pCy + tx * tS + ty * tC) & cr after tRot
   end repeat
   delete the last char of tRot
   return tRot
end terrainPoints

-- Place a terrain piece: a static polygon body the user can size, rotate and
-- drag like any part. pW/pH default per kind; Load passes the saved size.
function placeTerrain pKind, pX, pY, pW, pH
   local tName, tRef, tWH, tColor
   set the itemDelimiter to comma
   put terrainDefault(pKind) into tWH
   if pW is empty or pW < 1 then put item 1 of tWH into pW
   if pH is empty or pH < 1 then put item 2 of tWH into pH
   put terrainColor(pKind) into tColor
   put "cb_terrain_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "polygon"
   set the filled of tRef to true
   set the backgroundColor of tRef to tColor
   set the foregroundColor of tRef to "20,20,24"
   set the lineSize of tRef to 2                 -- a bolder edge reads as solid ground
   set the points of tRef to terrainPoints(pKind, round(pX), round(pY), pW, pH, 0, false)
   set the loc of tRef to round(pX) & "," & round(pY)
   if pKind is "hill" then b2kAddChain tRef, the points of tRef, true   -- smooth rolling ground
   else b2kAddPolygon tRef, false                                       -- convex: never falls, never syncs
   tagPart tRef, pKind, tColor, empty
   set the uW of tRef to pW
   set the uH of tRef to pH
   set the uAngle of tRef to 0
   set the uFlip of tRef to false
   set the uFriction of tRef to 0.6           -- terrain grips by default
   b2kSetFriction tRef, 0.6
   return tRef
end placeTerrain

-- Rebuild a terrain piece's outline + static collision shape from its current
-- size and angle. Called on every resize/rotate; the body origin stays put.
on regenTerrain pCtrl
   if pCtrl is empty then exit regenTerrain
   local tCx, tCy
   put item 1 of the loc of pCtrl into tCx
   put item 2 of the loc of pCtrl into tCy
   set the points of pCtrl to terrainPoints(the uKind of pCtrl, tCx, tCy, \
         numOr(the uW of pCtrl, 120), numOr(the uH of pCtrl, 26), numOr(the uAngle of pCtrl, 0), \
         (the uFlip of pCtrl is true))
   set the loc of pCtrl to tCx & "," & tCy     -- keep centred on the body origin
   if the uKind of pCtrl is "hill" then
      rebuildHillChain pCtrl                    -- smooth hills use a chain, not a polygon shape
   else
      b2kReshape pCtrl, "poly"
      reapplyMaterial pCtrl
   end if
end regenTerrain

-- Rebuild a hill's smooth static chain from its current outline (the polygon
-- shape path can't represent the rolling, concave profile). Drops the old chain
-- body and re-attaches one to the same graphic, so the part keeps its identity.
on rebuildHillChain pCtrl
   if b2kBodyOf(pCtrl) is not empty then b2kRemove pCtrl   -- destroy old chain body; graphic stays (not kit-spawned)
   b2kAddChain pCtrl, the points of pCtrl, true
end rebuildHillChain

-- =====================================================================
-- Freehand "Draw" terrain: press-drag to sketch a ground line; on release it
-- becomes a closed, self-contained ribbon that follows the stroke. It no longer
-- drops hidden edges to the arena floor, so drawn ground stays where the user
-- put it and can float as a ledge, bridge or obstacle.
-- =====================================================================
on beginDrawTerrain pX, pY
   set the itemDelimiter to comma
   put "draw" into gDragMode
   -- Clamp the first vertex to the arena, exactly like extendDrawTerrain - a draw
   -- that begins off the play area must not seed an out-of-bounds point.
   put max(gArenaL, min(gArenaR, pX)) into pX
   put max(gArenaT, min(gArenaB, pY)) into pY
   put round(pX) & "," & round(pY) into gDrawPts
   put "cb_terrain_" & the milliseconds & "_" & random(99999) into gDrawCtrl
   create graphic gDrawCtrl
   put the long id of graphic gDrawCtrl into gDrawCtrl
   set the layerMode of gDrawCtrl to "dynamic"   -- the live sketch grows every mouseMove
   set the style of gDrawCtrl to "line"
   set the lineSize of gDrawCtrl to kDrawLineSize
   set the foregroundColor of gDrawCtrl to "150,120,84"
   set the points of gDrawCtrl to gDrawPts
   put "Draw the ground - release to set it." into gStatus
end beginDrawTerrain

on extendDrawTerrain pX, pY
   if gDrawCtrl is empty then exit extendDrawTerrain
   set the itemDelimiter to comma
   local tx, ty, tLast
   put max(gArenaL, min(gArenaR, pX)) into tx
   put max(gArenaT, min(gArenaB, pY)) into ty
   put the last line of gDrawPts into tLast
   if tLast is not empty and (abs(tx - item 1 of tLast) + abs(ty - item 2 of tLast)) < kDrawStep then exit extendDrawTerrain
   put cr & round(tx) & "," & round(ty) after gDrawPts
   set the points of gDrawCtrl to gDrawPts
end extendDrawTerrain

on finishDrawTerrain
   if gDrawCtrl is empty then exit finishDrawTerrain
   set the itemDelimiter to comma
   local tPts
   put gDrawPts into tPts
   if the number of lines of tPts < 2 then        -- a click, not a drag: nothing to build
      try
         delete gDrawCtrl
      end try
      put empty into gDrawCtrl
      put empty into gDrawPts
      put "Press and drag to draw a ground line." into gStatus
      exit finishDrawTerrain
   end if
   -- Normalise the contour left->right, then build a CLOSED, filled ribbon. The
   -- drawn surface is still the upper collision edge, but the underside follows
   -- the same stroke a few pixels lower instead of connecting to the arena floor.
   -- The top is laid right->left so the chain's solid side faces up (Box2D: solid
   -- = right of the travel direction), matching the smoke test's ground chain.
   local tShape
   if (item 1 of the last line of tPts) < (item 1 of line 1 of tPts) then put reversedLines(tPts) into tPts
   put drawTerrainRibbon(tPts, kDrawLineSize) into tShape
   set the style of gDrawCtrl to "polygon"
   set the filled of gDrawCtrl to true
   set the backgroundColor of gDrawCtrl to "120,96,60"
   set the foregroundColor of gDrawCtrl to "70,56,36"
   set the lineSize of gDrawCtrl to 2
   set the points of gDrawCtrl to tShape
   tagPart gDrawCtrl, "draw", "120,96,60", empty
   set the uFriction of gDrawCtrl to 0.6
   b2kAddChain gDrawCtrl, tShape, true            -- closed loop = a solid ground mass
   selectPart gDrawCtrl
   put "Ground drawn. Press Run to test it." into gStatus
   put empty into gDrawCtrl
   put empty into gDrawPts
   updateHud
end finishDrawTerrain

-- Build a closed outline around a freehand stroke without anchoring it to the
-- arena floor. The upper edge is the user's stroke; the lower edge is the same
-- stroke offset downward by the drawn line thickness (clamped to the arena).
function drawTerrainRibbon pPts, pThickness
   local tTop, tUnder, tP, tx, ty
   set the itemDelimiter to comma
   if pThickness is empty or pThickness is not a number or pThickness < 1 then put kDrawLineSize into pThickness
   put empty into tUnder
   repeat for each line tP in pPts
      if tP is empty then next repeat
      put item 1 of tP into tx
      put (item 2 of tP) + pThickness into ty
      if ty > gArenaB then put gArenaB into ty
      put round(tx) & "," & round(ty) & cr after tUnder
   end repeat
   if the last char of tUnder is cr then delete the last char of tUnder
   put reversedLines(pPts) into tTop
   return tTop & cr & tUnder
end drawTerrainRibbon

-- A placeholder line graphic for a saved drawn-terrain part; applyPartSpecial
-- fills in its points and chain from the saved point list.
function placeDrawPlaceholder pX, pY
   local tName, tRef
   put "cb_terrain_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "polygon"
   set the filled of tRef to true
   set the backgroundColor of tRef to "120,96,60"
   set the foregroundColor of tRef to "70,56,36"
   set the lineSize of tRef to 2
   set the loc of tRef to round(pX) & "," & round(pY)
   tagPart tRef, "draw", "120,96,60", empty
   return tRef
end placeDrawPlaceholder

-- Reverse the order of a CR-list of points.
function reversedLines pList
   local tL, tOut
   put empty into tOut
   repeat for each line tL in pList
      if tL is not empty then put tL & cr before tOut
   end repeat
   if tOut is not empty then delete the last char of tOut
   return tOut
end reversedLines

-- A drawn terrain's points packed into one save column (CR -> "|", since ";"
-- and TAB are taken by the save format).
function ptsPacked pCtrl
   local tP
   put the points of pCtrl into tP     -- current points, so a dragged terrain saves where it sits
   filter tP without empty             -- drop any trailing blank line
   replace cr with "|" in tP           -- ";" and TAB are taken by the save format
   return tP
end ptsPacked

-- =====================================================================
-- Vehicle: a ready-made car you drop in like any object - a chassis on two
-- sprung, motorised wheels. All three parts share a uGroup tag so dragging one
-- moves the whole car, and the wheel joints/motors save, load and reset normally.
-- =====================================================================
function placeVehicle pX, pY
   local tGid, tChassis, tWB, tWF, tCW, tCH, tWheel, tDx, tDy, tSpeed, tW
   put "veh" & the milliseconds & "_" & random(99999) into tGid
   put 152 into tCW                           -- chassis width
   put 34 into tCH                            -- chassis height
   put 48 into tWheel                         -- wheel diameter
   put round(tCW * 0.31) into tDx             -- wheel offset from centre (x)
   put round(tCH * 0.9) into tDy              -- wheel sits just below the chassis
   put max(160, gMotorSpeed) into tSpeed      -- a lively default drive speed
   -- chassis: a light body keeps the centre of mass low for a stable ride
   put placeBox(pX, pY, tCW, tCH, "212,84,72") into tChassis
   set the uDensity of tChassis to 0.7
   b2kSetDensity tChassis, 0.7
   set the uBounce of tChassis to 0
   b2kSetBounce tChassis, 0
   set the uGroup of tChassis to tGid
   -- two grippy wheels
   put placeBall(pX - tDx, pY + tDy, tWheel, "40,42,50") into tWB
   put placeBall(pX + tDx, pY + tDy, tWheel, "40,42,50") into tWF
   repeat for each line tW in (tWB & cr & tWF)
      set the uFriction of tW to 1
      b2kSetFriction tW, 1
      set the uDensity of tW to 1
      b2kSetDensity tW, 1
      set the uBounce of tW to 0
      b2kSetBounce tW, 0
      set the uGroup of tW to tGid
   end repeat
   -- sprung, motorised wheel joints (connectJoint adds the suspension + motor)
   get connectJoint("wheel", tChassis, tWB, item 1 of the loc of tWB, item 2 of the loc of tWB, tSpeed)
   get connectJoint("wheel", tChassis, tWF, item 1 of the loc of tWF, item 2 of the loc of tWF, tSpeed)
   return tChassis
end placeVehicle

-- Tag a part with the data save/load needs, register it, apply the material.
on tagPart pCtrl, pKind, pColor, pFile
   if pCtrl is empty then exit tagPart
   set the uPartId of pCtrl to gNextPid
   add 1 to gNameCount[pKind]
   set the uPartName of pCtrl to niceName(pKind) && gNameCount[pKind]   -- auto-name; user-renamable in the inspector
   set the uKind of pCtrl to pKind
   set the uColor of pCtrl to pColor
   set the uFile of pCtrl to pFile
   set the uW of pCtrl to the width of pCtrl       -- design size (the graphic rect inflates when rotated)
   set the uH of pCtrl to the height of pCtrl
   add 1 to gNextPid
   put pCtrl & cr after gParts
   put true into gDynDirty               -- the dynamic-part cache must be rebuilt
   registerKind pCtrl, pKind
   if gBouncy and kindIsDynamic(pKind) then
      b2kSetBounce pCtrl, kBounceOn
      set the uBounce of pCtrl to kBounceOn
   else
      set the uBounce of pCtrl to 0
   end if
   if kindHasBody(pKind) then
      set the uFriction of pCtrl to 0.4
      if kindIsDynamic(pKind) then set the uBodyType of pCtrl to "dynamic"
      else set the uBodyType of pCtrl to "static"
   end if
   if kindIsDynamic(pKind) then
      set the uDensity of pCtrl to 1
      set the uGravity of pCtrl to 1
      set the uToughness of pCtrl to kToughnessDefault
      set the uFixedRot of pCtrl to false
      set the layerMode of pCtrl to "dynamic"   -- moving bodies composite on their own GPU layer (no smear/clip artifacts)
      b2kWake pCtrl                       -- so the first sync draws it
   end if
end tagPart

-- Whether a kind moves under gravity (so it gets bounce, waking, field forces).
function kindIsDynamic pKind
   return pKind is among the items of "box,ball,capsule,poly,image,balloon,bomb,thruster"
end kindIsDynamic

-- Fans and magnets are GUI-only influence zones with no physics body.
function kindHasBody pKind
   return pKind is not "fan" and pKind is not "magnet" and pKind is not "laser" and pKind is not "goal"
end kindHasBody

-- Friendly singular name for status messages.
function friendlyKind pKind
   switch pKind
      case "plate"
         return "pressure plate"
      case "balloon"
         return "helium balloon"
      case "poly"
         return "polygon"
      case "image"
         return "picture"
      case "draw"
         return "terrain sketch"
      case "goal"
         return "goal zone"
      default
         return pKind
   end switch
end friendlyKind

-- Add a freshly tagged part to its per-kind list (for fast per-frame iteration).
on registerKind pCtrl, pKind
   if pKind is among the items of "balloon,bomb,plate,fan,magnet,sensor,laser,thruster,goal" then
      put pCtrl & cr after gKindList[pKind]
   end if
   if pKind is "plate" then
      put 0 into gPlateLoad[pCtrl]
      put "up" into gPlateState[pCtrl]
   end if
   if pKind is "sensor" then put 0 into gSensorCount[pCtrl]
end registerKind

-- Drop a deleted part from any per-kind list it belonged to.
on unregisterKind pCtrl
   local tKind, tP, tNew
   repeat for each item tKind in "balloon,bomb,plate,fan,magnet,sensor,laser,thruster,goal"
      if pCtrl is not in gKindList[tKind] then next repeat
      put empty into tNew
      repeat for each line tP in gKindList[tKind]
         if tP is not empty and tP is not pCtrl then put tP & cr after tNew
      end repeat
      put tNew into gKindList[tKind]
   end repeat
   if pCtrl is among the keys of gPlateLoad then delete variable gPlateLoad[pCtrl]
   if pCtrl is among the keys of gPlateState then delete variable gPlateState[pCtrl]
   if pCtrl is among the keys of gSensorCount then delete variable gSensorCount[pCtrl]
end unregisterKind

-- The dynamic (force-responsive) parts, cached and rebuilt only when parts or
-- body types change. This deliberately checks the live Box2D body type, not just
-- the part kind: a user can turn a box/ball/etc. into a static or kinematic
-- body in the inspector, and field forces, goals and containment should then
-- stop treating it as a movable dynamic body.
function dynamicParts
   if not gDynDirty then return gDynParts
   local tP, tList
   put empty into tList
   repeat for each line tP in gParts
      if tP is empty then next repeat
      if kindIsDynamic(the uKind of tP) and b2kBodyType(tP) is "dynamic" then put tP & cr after tList
   end repeat
   put tList into gDynParts
   put false into gDynDirty
   return gDynParts
end dynamicParts

-- Pick an image file and drop it in as a dynamic body (it rotates via `the angle`).
-- Create an image-backed part from a known file + collision shape. Shared by the
-- one-off Image tool and the image library. pShape "auto" picks from the art's
-- aspect: square-ish -> circle, clearly oblong -> capsule (vs the bounding rect).
function spawnImageFrom pPath, pShape, pX, pY
   if there is no file pPath then return empty
   local tName, tRef, tW, tH, tScale, tErr, tAR
   put "cb_img_" & the milliseconds & "_" & random(99999) into tName
   create image tName
   put the long id of image tName into tRef
   try
      set the filename of tRef to pPath
   catch tErr
      delete tRef
      return empty
   end try
   put the formattedWidth of tRef into tW
   put the formattedHeight of tRef into tH
   if tW < 1 or tH < 1 then
      delete tRef
      return empty
   end if
   put kImageMax / max(tW, tH) into tScale
   if tScale > 1 then put 1 into tScale
   set the width of tRef to max(8, round(tW * tScale))
   set the height of tRef to max(8, round(tH * tScale))
   set the loc of tRef to round(pX) & "," & round(pY)
   b2kAddBox tRef
   tagPart tRef, "image", empty, pPath
   if pShape is empty or pShape is "auto" then
      put (the width of tRef) / (the height of tRef) into tAR
      if tAR > 0.75 and tAR < 1.34 then put "ball" into pShape
      else put "capsule" into pShape
   end if
   set the uShape of tRef to pShape
   b2kReshape tRef, pShape
   return tRef
end spawnImageFrom

-- The Image tool: pick a file, drop it, and remember it in the library for reuse.
function importImage pX, pY
   local tFile, tRef
   answer file "Choose an image (PNG or JPG):" with type "Images|png,jpg,jpeg,gif"
   put it into tFile
   if tFile is empty or the result is "cancel" then
      put "Image import cancelled." into gStatus
      updateHud
      return empty
   end if
   if there is no file tFile then
      put "Could not find that image file." into gStatus
      updateHud
      return empty
   end if
   put spawnImageFrom(tFile, "auto", pX, pY) into tRef
   if tRef is empty then
      put "That image could not be loaded (it may be empty or corrupt)." into gStatus
      updateHud
      return empty
   end if
   addToLibrary tFile, (the uShape of tRef)
   put "Image placed and saved to your Images library for reuse. Collides as its shape (change under Collision shape)." into gStatus
   updateHud
   return tRef
end importImage

-- ===================================================================
-- Image library: import once (with a collision shape), reuse forever.
-- The library lives in a stack property, so it persists across sessions;
-- placed instances are ordinary image parts that save with the scene.
-- ===================================================================
on loadImageLibrary
   put the uImageLibrary of this stack into gAssets
end loadImageLibrary

on saveImageLibrary
   set the uImageLibrary of this stack to gAssets
end saveImageLibrary

-- A friendly name from a file path: the file name without folders or extension.
function assetNameFromPath pPath
   local tN
   set the itemDelimiter to "/"        -- LiveCode uses "/" in paths on every platform
   put the last item of pPath into tN
   set the itemDelimiter to "."
   if the number of items of tN > 1 then delete the last item of tN
   return tN
end assetNameFromPath

-- Add a file to the library (deduped by path), with its import-time shape.
on addToLibrary pPath, pShape
   if pPath is empty then exit addToLibrary
   set the itemDelimiter to tab
   local tRec
   repeat for each line tRec in gAssets
      if item 1 of tRec is pPath then exit addToLibrary    -- already in the library
   end repeat
   if pShape is empty then put "auto" into pShape
   put pPath & tab & pShape & tab & assetNameFromPath(pPath) & cr after gAssets
   if the last char of gAssets is return then delete the last char of gAssets
   saveImageLibrary
end addToLibrary

on removeFromLibrary pIndex
   if pIndex < 1 or pIndex > the number of lines of gAssets then exit removeFromLibrary
   delete line pIndex of gAssets
   saveImageLibrary
   refreshImagePanel
end removeFromLibrary

-- Place an instance of a library image - an ordinary image part.
function placeAssetInstance pIndex, pX, pY
   set the itemDelimiter to tab
   local tRec
   put line pIndex of gAssets into tRec
   if tRec is empty then return empty
   return spawnImageFrom(item 1 of tRec, item 2 of tRec, pX, pY)
end placeAssetInstance

-- Import a new image into the library, choosing how it collides now.
on importToLibrary
   answer file "Choose an image to add to your library:" with type "Images|png,jpg,jpeg,gif"
   local tFile, tShape
   put it into tFile
   if tFile is empty or the result is "cancel" then exit importToLibrary
   if there is no file tFile then
      put "Could not find that image file." into gStatus
      updateHud
      exit importToLibrary
   end if
   answer "How should it collide?" with "Auto" or "Ball" or "Box"
   put it into tShape
   if tShape is empty then put "Auto" into tShape
   addToLibrary tFile, toLower(tShape)
   refreshImagePanel
   put "Added " & assetNameFromPath(tFile) & " to your Images library." into gStatus
   updateHud
end importToLibrary

-- =====================================================================
-- Joints (two-click: part A, then part B)
-- =====================================================================
on jointClick pX, pY
   local tHit
   if gPendCtrl is empty then
      put partUnderClick(pX, pY) into tHit
      if tHit is empty then
         put "Click part A first to start the " & gJointTool & " joint." into gStatus
         updateHud
         exit jointClick
      end if
      put tHit into gPendCtrl
      put pX into gPendX
      put pY into gPendY
      flashSelect tHit
      put "Part A set. Now click part B" & jointBHint() into gStatus
      updateHud
      exit jointClick
   end if
   -- second click: the part under the cursor, ignoring A (so overlaps work)
   put otherPartAt(pX, pY, gPendCtrl) into tHit
   if tHit is empty and gJointTool is not "hinge" and gJointTool is not "bridge" and gJointTool is not "chain" then
      put "Part B must be a part for a " & gJointTool & " joint (Hinge, Bridge and Chain can pin to the world)." into gStatus
      resetPend
      updateHud
      exit jointClick
   end if
   makeJoint gJointTool, gPendCtrl, tHit, pX, pY
   resetPend
end jointClick

function jointBHint
   if gJointTool is "hinge" or gJointTool is "bridge" or gJointTool is "chain" then return " (or empty space to anchor to the world)."
   return "."
end jointBHint

on resetPend
   if gPendCtrl is not empty then unflashSelect gPendCtrl
   put empty into gPendCtrl
   put empty into gPendX
   put empty into gPendY
end resetPend

on flashSelect pCtrl
   if pCtrl is empty then exit flashSelect
   try
      set the uPendFg of pCtrl to the foregroundColor of pCtrl   -- save the real outline (anchors and
      set the uPendLine of pCtrl to the lineSize of pCtrl        -- balloons have custom rims) to restore
      set the foregroundColor of pCtrl to "255,255,255"
      set the lineSize of pCtrl to 3
   end try
end flashSelect

on unflashSelect pCtrl
   if pCtrl is empty then exit unflashSelect
   try
      set the foregroundColor of pCtrl to the uPendFg of pCtrl
      set the lineSize of pCtrl to the uPendLine of pCtrl
   end try
end unflashSelect

-- Interactive joint: build it, then add the motor if the Motor toggle is on.
on makeJoint pKind, pA, pB, pX, pY
   if pKind is "bridge" or pKind is "chain" then
      buildSpan pKind, pA, pB, pX, pY
      renderBuild
      updateHud
      exit makeJoint
   end if
   local tMotor
   put 0 into tMotor
   if gMotorOn and (pKind is "hinge" or pKind is "wheel") then put gMotorSpeed into tMotor
   if connectJoint(pKind, pA, pB, pX, pY, tMotor) then
      put "Connected with a " & pKind & " joint. Press Run to test it." into gStatus
      if tMotor > 0 and pKind is "hinge" and pB is not empty \
            and b2kBodyType(pA) is not "static" and b2kBodyType(pB) is not "static" then
         put " Tip: pin one side to an Anchor or the world for a steady spin." after gStatus
      end if
   else
      put "Could not create that joint - try different parts or positions." into gStatus
   end if
   renderJoints
   updateHud
end makeJoint

-- Build a span of hinged segments from the first click point to the second, in
-- the demo's bridge style: a "bridge" is stiff planks, a "chain" is a draping
-- rope of small links. Each segment is a normal part and each link an exact-pivot
-- "pin" joint, so the whole span renders, saves/loads and deletes like anything else.
on buildSpan pKind, pA, pB, pEx, pEy
   local tSx, tSy, tD, tN, tHt, tColor, tDens, tPinKind, tPts, tNpts
   local tI, tJx0, tJy0, tJx1, tJy1, tCx, tCy, tLen, tAng, tSeg, tPrev
   local tAx, tAy, tHalf, tT
   put gPendX into tSx
   put gPendY into tSy
   put sqrt((pEx - tSx) ^ 2 + (pEy - tSy) ^ 2) into tD
   if tD < 50 then
      put "That span is too short - click two points further apart." into gStatus
      exit buildSpan
   end if
   set the itemDelimiter to comma
   -- Build the list of pin points first, then place one equal-length link between
   -- each consecutive pair. A bridge is a straight run of planks; a chain is a
   -- shallow tent (equal links + real slack) that the free pins round into a
   -- natural catenary the moment gravity takes hold on Run.
   if pKind is "bridge" then
      put "deckpin" into tPinKind            -- planks flex a little but never fold back
      put 12 into tHt
      put "168,146,98" into tColor
      put 1 into tDens
      put max(2, min(24, round(tD / 60))) into tN
      put empty into tPts
      repeat with tI = 0 to tN
         put tI / tN into tT
         put round(tSx + tT * (pEx - tSx)) & comma & round(tSy + tT * (pEy - tSy)) & cr after tPts
      end repeat
   else
      put "pin" into tPinKind                 -- links pivot freely so the chain drapes
      put 8 into tHt
      put "150,154,170" into tColor
      put 0.3 into tDens                      -- light links settle into a natural curve
      put (tSx + pEx) / 2 into tAx
      put (tSy + pEy) / 2 + tD * 0.22 into tAy   -- apex sags below the midpoint (the slack)
      put max(3, min(20, round(tD / 34))) into tHalf
      put empty into tPts
      repeat with tI = 0 to tHalf             -- equal links: start -> apex
         put tI / tHalf into tT
         put round(tSx + tT * (tAx - tSx)) & comma & round(tSy + tT * (tAy - tSy)) & cr after tPts
      end repeat
      repeat with tI = 1 to tHalf             -- equal links: apex -> end
         put tI / tHalf into tT
         put round(tAx + tT * (pEx - tAx)) & comma & round(tAy + tT * (pEy - tAy)) & cr after tPts
      end repeat
   end if
   put the number of lines of tPts into tNpts
   put empty into tPrev
   repeat with tI = 1 to tNpts - 1
      put item 1 of line tI of tPts into tJx0
      put item 2 of line tI of tPts into tJy0
      put item 1 of line (tI + 1) of tPts into tJx1
      put item 2 of line (tI + 1) of tPts into tJy1
      put (tJx0 + tJx1) / 2 into tCx
      put (tJy0 + tJy1) / 2 into tCy
      put sqrt((tJx1 - tJx0) ^ 2 + (tJy1 - tJy0) ^ 2) into tLen
      put atan2(tJy1 - tJy0, tJx1 - tJx0) * 180 / kPI into tAng
      put placeBox(round(tCx), round(tCy), max(8, round(tLen)), tHt, tColor) into tSeg
      set the uDensity of tSeg to tDens
      b2kSetDensity tSeg, tDens
      set the uBounce of tSeg to 0           -- spans stay taut even when Bouncy mode is on
      b2kSetBounce tSeg, 0
      b2kMoveTo tSeg, round(tCx), round(tCy), tAng
      if tI is 1 then get connectJoint(tPinKind, pA, tSeg, round(tJx0), round(tJy0), 0)
      else get connectJoint(tPinKind, tPrev, tSeg, round(tJx0), round(tJy0), 0)
      put tSeg into tPrev
   end repeat
   get connectJoint(tPinKind, tPrev, pB, round(pEx), round(pEy), 0)
   put (niceName(pKind) & " built from " & (tNpts - 1) & " segments. Press Run to test it.") into gStatus
end buildSpan

-- The shared joint builder. Picks a sensible pivot per kind, records the joint
-- and its marker, and motorises it when pMotorSpeed > 0. Returns true on success.
function connectJoint pKind, pA, pB, pX, pY, pMotorSpeed
   local tJ, tAxis, tPivX, tPivY, tVis, tEnd, tdx, tdy, tda
   put pX into tPivX
   put pY into tPivY
   put "dot" into tVis
   put empty into tEnd
   put 0 into tJ
   switch pKind
      case "hinge"
         if pB is empty then
            b2kHinge pA, empty, pX, pY            -- pin to the world at the click
            put the result into tJ
            put "rod" into tVis
            put pA into tEnd
         else if b2kBodyType(pA) is "static" and b2kBodyType(pB) is not "static" then
            put item 1 of the loc of pA into tPivX  -- pivot at the static anchor
            put item 2 of the loc of pA into tPivY
            b2kHinge pA, pB, tPivX, tPivY
            put the result into tJ
            put "rod" into tVis
            put pB into tEnd
         else if b2kBodyType(pB) is "static" then
            put item 1 of the loc of pB into tPivX
            put item 2 of the loc of pB into tPivY
            b2kHinge pA, pB, tPivX, tPivY
            put the result into tJ
            put "rod" into tVis
            put pA into tEnd
         else
            put item 1 of the loc of pB into tPivX  -- two dynamic parts: pin at B
            put item 2 of the loc of pB into tPivY
            b2kHinge pA, pB, tPivX, tPivY
            put the result into tJ
            put "dot" into tVis
         end if
         break
      case "weld"
         b2kWeld pA, pB
         put the result into tJ
         put "line" into tVis
         break
      case "servo"
         -- a powered position hold: drives pA to keep its CURRENT pose relative
         -- to pB. It yields under load and springs back, unlike a rigid weld.
         if pB is empty then return false       -- a servo holds between two parts
         put (item 1 of the loc of pA) - (item 1 of the loc of pB) into tdx
         put (item 2 of the loc of pA) - (item 2 of the loc of pB) into tdy
         put round(b2kAngle(pA) - b2kAngle(pB)) into tda
         -- b2kMotorTo is a command: statement call + the result (function
         -- syntax on a command throws in OXT - it never created a joint)
         b2kMotorTo pA, pB, tdx, tdy, tda, kServoForce, kServoTorque
         put the result into tJ
         put "line" into tVis
         break
      case "rope"
         b2kRope pA, pB
         put the result into tJ
         put "line" into tVis
         break
      case "slider"
         put angleAtoB(pA, pB) into tAxis
         b2kSlider pA, pB, tAxis
         put the result into tJ
         put "line" into tVis
         break
      case "wheel"
         put item 1 of the loc of pB into tPivX     -- axle at the wheel's centre
         put item 2 of the loc of pB into tPivY
         b2kWheel pA, pB, tPivX, tPivY
         put the result into tJ
         if tJ > 0 then b2kWheelSpring tJ, 5, 0.7
         put "dot" into tVis
         break
      case "pin"
         b2kHinge pA, pB, pX, pY            -- exact-pivot hinge for spans (no marker)
         put the result into tJ
         put "none" into tVis
         break
      case "deckpin"
         b2kHinge pA, pB, pX, pY            -- bridge-deck pin: hinged but flex-limited (no marker)
         put the result into tJ
         if tJ > 0 then b2kHingeLimit tJ, - kBridgeFlex, kBridgeFlex
         put "none" into tVis
         break
      default
         return false
   end switch
   if tJ is empty or tJ <= 0 then return false
   recordJoint pKind, tJ, pA, pB, tPivX, tPivY, tVis
   put tEnd into gJEnd[gJN]
   if pMotorSpeed > 0 then
      if pKind is "hinge" then
         b2kMotor tJ, pMotorSpeed, kHingeTorque
      else if pKind is "wheel" then
         b2kWheelMotor tJ, pMotorSpeed, kWheelTorque
      end if
      put pMotorSpeed into gJMotor[gJN]
      set the uMotorOn of graphic ("cb_joint_" & gJN) to true
      set the uMotorSpeed of graphic ("cb_joint_" & gJN) to pMotorSpeed
   end if
   return true
end connectJoint

-- Screen-space direction from A to B, in degrees (slider axis).
function angleAtoB pA, pB
   local tAx, tAy, tBx, tBy
   put item 1 of the loc of pA into tAx
   put item 2 of the loc of pA into tAy
   put item 1 of the loc of pB into tBx
   put item 2 of the loc of pB into tBy
   return atan2(tBy - tAy, tBx - tAx) * 180 / kPI
end angleAtoB

on recordJoint pKind, pJoint, pA, pB, pX, pY, pVis
   local tG
   add 1 to gJN
   put pKind into gJKind[gJN]
   put pJoint into gJHandle[gJN]
   put pA into gJCa[gJN]
   put pB into gJCb[gJN]
   put pX into gJPx[gJN]
   put pY into gJPy[gJN]
   put 0 into gJMotor[gJN]
   put pVis into gJVis[gJN]
   put empty into gJEnd[gJN]
   put "cb_joint_" & gJN into tG
   create graphic tG
   set the layerMode of graphic tG to "dynamic"   -- re-pointed every running frame
   if pVis is "none" then
      set the visible of graphic tG to false      -- internal structural pin: no marker
   else if pVis is "dot" then
      set the style of graphic tG to "oval"
      set the filled of graphic tG to true
      set the backgroundColor of graphic tG to "250,210,90"
      set the foregroundColor of graphic tG to "30,30,36"
      set the lineSize of graphic tG to 1
      set the width of graphic tG to 14
      set the height of graphic tG to 14
      set the loc of graphic tG to round(pX) & "," & round(pY)
   else
      set the style of graphic tG to "line"
      if pVis is "rod" then
         set the lineSize of graphic tG to 4
         set the foregroundColor of graphic tG to "250,210,90"
      else
         set the lineSize of graphic tG to 2
         set the foregroundColor of graphic tG to "200,206,220"
      end if
   end if
   -- default editable joint settings, stored on the marker (like parts' u-props)
   set the uJKind of graphic tG to pKind     -- the joint's kind, so per-kind defaults are reachable from the marker alone
   set the uMotorOn of graphic tG to false
   set the uMotorSpeed of graphic tG to gMotorSpeed
   set the uMotorPower of graphic tG to motorPowerDefault(pKind)
   set the uLimitOn of graphic tG to false
   set the uLimitLo of graphic tG to jointLimitLoDefault(pKind)
   set the uLimitHi of graphic tG to jointLimitHiDefault(pKind)
   set the uSpringHz of graphic tG to jointSpringHzDefault(pKind)
   set the uSpringDamp of graphic tG to jointSpringDampDefault(pKind)
   set the uMinLen of graphic tG to 0
   set the uMaxLen of graphic tG to 200
   set the uRangeSet of graphic tG to false
end recordJoint

-- Redraw every joint marker. dot = pivot bead on B; rod = arm from a fixed pivot
-- to the moving part; line = link between the two parts. Empty kind = removed.
on renderJoints
   local tI, tG, tVis, tRunning
   if gJN < 1 then exit renderJoints
   -- While running, the Kit's sync only repositions AWAKE bodies, so a marker
   -- whose tracked body (or bodies) are all asleep is already in the right place
   -- and its redraw - the real per-frame cost on big contraptions - can be
   -- skipped. In build mode parts move under the editor, not the sim, so the
   -- skip is disabled and every marker still follows a dragged part.
   put (gMode is "run") into tRunning
   repeat with tI = 1 to gJN
      put gJVis[tI] into tVis
      if tVis is empty or tVis is "none" then next repeat
      if tRunning then
         if jointAtRest(tI, tVis) then next repeat   -- asleep: marker already correct
      end if
      put "cb_joint_" & tI into tG
      if there is not a graphic tG then next repeat
      try
         if tVis is "dot" then
            set the loc of graphic tG to the loc of gJCb[tI]
         else if tVis is "rod" then
            set the points of graphic tG to \
                  (round(gJPx[tI]) & "," & round(gJPy[tI])) & cr & the loc of gJEnd[tI]
         else
            set the points of graphic tG to the loc of gJCa[tI] & cr & the loc of gJCb[tI]
         end if
      end try
   end repeat
end renderJoints

-- True when a joint marker need not be redrawn this frame: the body (or bodies)
-- it follows are all asleep, so they haven't moved. dot follows B; rod follows
-- its moving end; line follows both A and B.
function jointAtRest pIndex, pVis
   if pVis is "dot" then return not partAwake(gJCb[pIndex])
   if pVis is "rod" then return not partAwake(gJEnd[pIndex])
   return (not partAwake(gJCa[pIndex])) and (not partAwake(gJCb[pIndex]))
end jointAtRest

-- True when a part control has an awake, actively-simulating body. Empty or
-- body-less endpoints (a world pin, a static anchor) count as at rest - they
-- never move - so they don't force a redraw on their own.
function partAwake pCtrl
   if pCtrl is empty then return false
   if b2kBodyOf(pCtrl) is empty then return false
   return b2kIsAwake(pCtrl)
end partAwake

-- =====================================================================
-- Per-frame + contact feedback (only while Running)
-- =====================================================================
on b2kFrame
   renderJoints
   updateFlashes
   applyFieldForces
   updateBombs
   updateRings
   updateLasers
   updateThrusters
   containParts
   checkGoals
   tickHud
end b2kFrame

on b2kContact pA, pB
   flashCtrl pA
   flashCtrl pB
   plateTouch pA, pB, 1
   plateTouch pB, pA, 1
   bombImpactCheck pA
   bombImpactCheck pB
end b2kContact

-- A body left a surface: if it stepped off a pressure plate, lighten its load.
on b2kEndContact pA, pB
   plateTouch pA, pB, -1
   plateTouch pB, pA, -1
end b2kEndContact

-- A dynamic body entered a sensor zone. Fire the plate signal on the first
-- arrival (0->1 occupants) so passing traffic doesn't machine-gun the motors.
on b2kSensorEnter pSensor, pVisitor
   if pSensor is empty or pVisitor is empty then exit b2kSensorEnter
   if (the uKind of pSensor is not "sensor") and (the uSensor of pSensor is not true) then exit b2kSensorEnter
   if b2kBodyType(pVisitor) is not "dynamic" then exit b2kSensorEnter
   add 1 to gSensorCount[pSensor]
   if gSensorCount[pSensor] is 1 then
      try
         set the backgroundColor of pSensor to "120,230,140"   -- lit while occupied
      end try
      put "A sensor zone triggered its signal!" into gStatus
      fireEmitter pSensor
      updateHud
   end if
end b2kSensorEnter

-- A body left a sensor zone; when the last one leaves, the zone goes idle again.
on b2kSensorExit pSensor, pVisitor
   if pSensor is empty then exit b2kSensorExit
   if (the uKind of pSensor is not "sensor") and (the uSensor of pSensor is not true) then exit b2kSensorExit
   subtract 1 from gSensorCount[pSensor]
   if gSensorCount[pSensor] <= 0 then
      put 0 into gSensorCount[pSensor]
      try
         set the backgroundColor of pSensor to numOr(the uColor of pSensor, "232,196,92")
      end try
   end if
end b2kSensorExit

on flashCtrl pCtrl
   if pCtrl is empty then exit flashCtrl
   if the uKind of pCtrl is among the items of "plate,anchor,fan,magnet" then exit flashCtrl
   if pCtrl is gSelPart then exit flashCtrl   -- don't fight the selection outline
   try
      if pCtrl is not among the keys of gFlash then     -- remember the REAL outline once, so a
         set the uFlashFg of pCtrl to the foregroundColor of pCtrl   -- re-flash before expiry can't
         set the uFlashLine of pCtrl to the lineSize of pCtrl        -- bake the white flash colour in
      end if
      set the foregroundColor of pCtrl to "255,255,255"
      set the lineSize of pCtrl to 2
      put the milliseconds + kFlashMs into gFlash[pCtrl]
   end try
end flashCtrl

on updateFlashes
   local tCtrl, tNow, tDead, d
   put the milliseconds into tNow
   put empty into tDead
   repeat for each key tCtrl in gFlash
      if tNow >= gFlash[tCtrl] then
         try
            set the foregroundColor of tCtrl to the uFlashFg of tCtrl   -- restore the part's own
            set the lineSize of tCtrl to the uFlashLine of tCtrl        -- outline, not a generic grey
         end try
         put tCtrl & cr after tDead
      end if
   end repeat
   repeat for each line d in tDead
      delete variable gFlash[d]
   end repeat
end updateFlashes

-- =====================================================================
-- Delete / clear / reset
-- =====================================================================
on deletePart pCtrl
   if pCtrl is empty then exit deletePart
   if gPendCtrl is pCtrl then resetPend
   if gSelPart is pCtrl then deselectPart
   if gWireSrc is pCtrl then put empty into gWireSrc
   removeWiresFor pCtrl
   local tI, tP, tNew
   if gJN >= 1 then
      repeat with tI = 1 to gJN
         if gJCa[tI] is pCtrl or gJCb[tI] is pCtrl then removeJointAt tI
      end repeat
   end if
   put empty into tNew
   repeat for each line tP in gParts
      if tP is not empty and tP is not pCtrl then put tP & cr after tNew
   end repeat
   put tNew into gParts
   unregisterKind pCtrl
   if pCtrl is among the keys of gFlash then delete variable gFlash[pCtrl]   -- don't leave a dead handle for updateFlashes
   put true into gDynDirty
   try
      b2kRemove pCtrl
   end try
   try
      delete pCtrl
   end try
   put "Deleted a part and any joints on it." into gStatus
end deletePart

-- Drop an identical copy of a part - same size, colour, material and special
-- settings - nudged off the original, then select it and switch to Drag so it
-- can be moved straight away. (Joints aren't copied; they connect two parts.)
-- Make one independent copy of a part at (pX,pY): same size, colour, material and
-- special settings. The copy carries no group tag, so copying a vehicle part
-- yields a free part rather than something tied to the original's assembly.
function copyPart pCtrl, pX, pY
   local tNew
   put rebuildPart(the uKind of pCtrl, pX, pY, numOr(the uW of pCtrl, the width of pCtrl), \
         numOr(the uH of pCtrl, the height of pCtrl), \
         (the uColor of pCtrl), (the uFile of pCtrl)) into tNew
   if tNew is empty then return empty
   if the uBounce of pCtrl is not empty then
      set the uBounce of tNew to (the uBounce of pCtrl)
      if (the uBounce of pCtrl) > 0 then b2kSetBounce tNew, (the uBounce of pCtrl)
   end if
   applyPartSpecial tNew, partSpecial(pCtrl)
   set the uGroup of tNew to empty
   clampPartToArena tNew                 -- copies offset toward an edge stay on the stage
   return tNew
end copyPart

on duplicatePart pCtrl
   if pCtrl is empty then exit duplicatePart
   if pCtrl is not among the lines of gParts then exit duplicatePart
   local tLoc, tNx, tNy, tNew
   put the loc of pCtrl into tLoc
   put (item 1 of tLoc) + 26 into tNx
   put (item 2 of tLoc) + 26 into tNy
   if tNx > gArenaR then put (item 1 of tLoc) - 26 into tNx
   if tNy > gArenaB then put (item 2 of tLoc) - 26 into tNy
   put copyPart(pCtrl, tNx, tNy) into tNew
   if tNew is empty then exit duplicatePart
   renderBuild
   put "drag" into gTool
   selectPart tNew
   highlightAll
   put "Duplicated a " & friendlyKind(the uKind of pCtrl) & ". Drag the copy where you want it." into gStatus
   updateHud
end duplicatePart

-- Multiply: drop a whole batch of copies in a tidy grid, asking how many first.
on multiplyPart pCtrl
   if pCtrl is empty then exit multiplyPart
   if pCtrl is not among the lines of gParts then exit multiplyPart
   local tN, tLoc, tOx, tOy, tStep, tCols, tI, tX, tY, tNew, tLast, tMade
   ask "How many copies would you like?" with "5"
   if it is empty or the result is "Cancel" then
      put "Multiply cancelled." into gStatus
      updateHud
      exit multiplyPart
   end if
   if it is not a number then
      put "Please type a whole number (1-50)." into gStatus
      updateHud
      exit multiplyPart
   end if
   put min(50, max(1, round(it))) into tN
   put the loc of pCtrl into tLoc
   put item 1 of tLoc into tOx
   put item 2 of tLoc into tOy
   put max(28, max(numOr(the uW of pCtrl, the width of pCtrl), \
         numOr(the uH of pCtrl, the height of pCtrl)) + 14) into tStep   -- spacing so copies don't pile up
   put max(1, trunc((gArenaR - tOx - tStep) / tStep)) into tCols          -- columns that fit to the right
   put 0 into tMade
   put empty into tLast
   lock screen
   repeat with tI = 1 to tN
      put tOx + ((tI - 1) mod tCols + 1) * tStep into tX
      put tOy + ((tI - 1) div tCols) * tStep into tY
      put max(gArenaL + tStep / 2, min(gArenaR - tStep / 2, tX)) into tX
      put max(gArenaT + tStep / 2, min(gArenaB - tStep / 2, tY)) into tY
      put copyPart(pCtrl, round(tX), round(tY)) into tNew
      if tNew is not empty then
         add 1 to tMade
         put tNew into tLast
      end if
   end repeat
   renderBuild
   unlock screen
   if tLast is not empty then
      put "drag" into gTool
      selectPart tLast
      highlightAll
   end if
   put "Made " & tMade & " copies of the " & friendlyKind(the uKind of pCtrl) & "." into gStatus
   updateHud
end multiplyPart

on removeJointAt pIndex
   if gSelJoint is pIndex then deselectJoint
   try
      b2kRemoveJoint gJHandle[pIndex]
   end try
   if there is a graphic ("cb_joint_" & pIndex) then delete graphic ("cb_joint_" & pIndex)
   put empty into gJKind[pIndex]
   put 0 into gJHandle[pIndex]
   put empty into gJCa[pIndex]
   put empty into gJCb[pIndex]
   put empty into gJVis[pIndex]
   put empty into gJEnd[pIndex]
   put empty into gJPx[pIndex]    -- clear ALL nine parallel arrays so a dead slot holds no ghost data
   put empty into gJPy[pIndex]
   put 0 into gJMotor[pIndex]
end removeJointAt

on clearAll
   if gPlaying then              -- clearing while playing exits Play cleanly (no stuck scrims)
      put false into gPlaying
      hideWin
      setPlayChrome false
      highlightActions
   end if
   resetPend
   deselectPart
   local tP
   lock screen
   clearJoints
   repeat for each line tP in gParts
      if tP is empty then next repeat
      try
         b2kRemove tP
      end try
      try
         delete tP
      end try
   end repeat
   put empty into gParts
   sweepOrphanParts             -- also drop UNTRACKED part graphics (orphans), so a load
                                -- never piles on leftovers and a rebuild leaves no dead shapes
   put empty into gFlash
   resetSceneState
   unlock screen
   put "Cleared. Pick a shape and click the canvas to place parts." into gStatus
   updateHud
end clearAll

-- Delete every PART graphic on the card, INCLUDING any not tracked in gParts
-- (orphans -- e.g. a stack saved with parts on the stage, then reopened: their
-- bodies are gone and gParts no longer lists them, so clearAll's gParts loop
-- can't see them). Parts are exactly the controls tagPart stamps with a uPartId;
-- chrome (ui_*), the arena (cb_*), and the image LIBRARY (data in the
-- uImageLibrary property, not controls) carry none, so they are never touched.
-- Safe to call whenever a truly clean stage is wanted (clearAll, reopen).
on sweepOrphanParts
   local tI
   repeat with tI = the number of controls of this card down to 1
      if the uPartId of control tI of this card is not empty then
         try
            b2kRemove control tI of this card
         end try
         delete control tI of this card
      end if
   end repeat
end sweepOrphanParts

on clearJoints
   local tI
   if gJN >= 1 then
      repeat with tI = 1 to gJN
         try
            b2kRemoveJoint gJHandle[tI]
         end try
         if there is a graphic ("cb_joint_" & tI) then delete graphic ("cb_joint_" & tI)
      end repeat
   end if
   resetJointArrays
end clearJoints

on resetJointArrays
   put empty into gSelJoint
   put 0 into gJN
   put empty into gJKind
   put empty into gJHandle
   put empty into gJCa
   put empty into gJCb
   put empty into gJPx
   put empty into gJPy
   put empty into gJMotor
   put empty into gJVis
   put empty into gJEnd
end resetJointArrays

function liveJointCount
   local tI, tN
   put 0 into tN
   if gJN >= 1 then
      repeat with tI = 1 to gJN
         if gJKind[tI] is not empty then add 1 to tN
      end repeat
   end if
   return tN
end liveJointCount

-- =====================================================================
-- Sample contraptions (built from the same primitives, one click)
-- =====================================================================
on buildSampleCart
   if gMode is "run" then toggleMode
   clearAll
   get placeVehicle((gArenaL + gArenaR) div 2, gArenaT + 110)
   highlightAll
   renderBuild
   put "Sample cart built. Press Run - the motorised wheels drive it." into gStatus
   updateHud
end buildSampleCart

on buildSampleSwing
   if gMode is "run" then toggleMode
   clearAll
   local tCx, tAnchorX, tAnchorY, tLen, tBob
   put (gArenaL + gArenaR) div 2 into tCx
   put tCx into tAnchorX
   put gArenaT + 30 into tAnchorY
   put 220 into tLen
   -- start the bob lifted ~55 deg so gravity swings it (build it where it sits,
   -- then hinge - never teleport a body after jointing it).
   put placeBall(tAnchorX - tLen * 0.819, tAnchorY + tLen * 0.574, 56, "214,92,92") into tBob
   get connectJoint("hinge", tBob, empty, tAnchorX, tAnchorY, 0)
   renderBuild
   put "Sample swing built. Press Run - gravity pulls the bob into a swing." into gStatus
   updateHud
end buildSampleSwing

-- =====================================================================
-- Save / load (whole contraption as tab-delimited text)
-- =====================================================================
-- Serialise the whole scene to CB2 text (used by Save and by Reset's snapshot).
function serializeText
   local tOut, tP, tI, tWsrc, tWtgt
   set the itemDelimiter to comma   -- partLine parses "x,y" locs by item; never assume the caller left it at comma
   put "CB2" & cr into tOut
   put "world" & tab & gGravityMode & tab & gWorldFeel & tab & (gCCD is true) & tab & \
         (gSleepOn is true) & tab & (gWarmStart is true) & tab & numOr(gSubsteps, 4) & cr after tOut
   repeat for each line tP in gParts
      if tP is empty then next repeat
      try
         put partLine(tP) & cr after tOut
      end try
   end repeat
   if gJN >= 1 then
      repeat with tI = 1 to gJN
         if gJKind[tI] is not empty then put jointLine(tI) & cr after tOut
      end repeat
   end if
   set the itemDelimiter to tab
   repeat for each line tP in gWires
      if tP is empty then next repeat
      put item 1 of tP into tWsrc          -- a long id in a variable resolves as an object;
      put item 2 of tP into tWtgt          -- "the uPartId of (item 1 of tP)" trips OXT's object parser
      if tWsrc is among the lines of gParts and tWtgt is among the lines of gParts then
         put "wire" & tab & (the uPartId of tWsrc) & tab & (the uPartId of tWtgt) & cr after tOut
      end if
   end repeat
   return tOut
end serializeText

on saveContraption
   local tOut
   put serializeText() into tOut
   ask file "Save contraption as:" with "contraption.cbx"
   if it is empty or the result is "cancel" then
      put "Save cancelled." into gStatus
      updateHud
      exit saveContraption
   end if
   put tOut into URL ("file:" & it)
   if the result is not empty then
      put "Save failed: " & the result into gStatus
   else
      put "Saved contraption to " & it into gStatus
   end if
   updateHud
end saveContraption

function partLine pCtrl
   local tLoc
   put the loc of pCtrl into tLoc
   if the uKind of pCtrl is "laser" then put (line 1 of the points of pCtrl) into tLoc   -- a laser's anchor is its emitter, not the beam's bbox centre
   return "part" & tab & (the uPartId of pCtrl) & tab & (the uKind of pCtrl) & tab & \
         (item 1 of tLoc) & tab & (item 2 of tLoc) & tab & \
         numOr(the uW of pCtrl, the width of pCtrl) & tab & numOr(the uH of pCtrl, the height of pCtrl) & tab & \
         (the uBounce of pCtrl) & tab & (the uColor of pCtrl) & tab & (the uFile of pCtrl) & tab & \
         partSpecial(pCtrl) & tab & (the uPartName of pCtrl)
end partLine

-- Pack a part's per-kind extras as "key=value;key=value" (empty for plain shapes).
-- Appended as the last column so old 10-column "CB1" saves still load cleanly.
function partSpecial pCtrl
   local tS, tKind
   put the uKind of pCtrl into tKind
   put empty into tS
   if kindIsTerrain(tKind) then               -- static scenery: grip + baked-in angle (+ ramp facing)
      put addKV(tS, "fric=" & (the uFriction of pCtrl)) into tS
      put addKV(tS, "tang=" & numOr(the uAngle of pCtrl, 0)) into tS
      if tKind is "ramp" then put addKV(tS, "flip=" & (the uFlip of pCtrl is true)) into tS
      return tS
   end if
   if kindHasBody(tKind) then
      put addKV(tS, "fric=" & (the uFriction of pCtrl)) into tS
      put addKV(tS, "dens=" & (the uDensity of pCtrl)) into tS
      put addKV(tS, "grav=" & (the uGravity of pCtrl)) into tS
      put addKV(tS, "frot=" & (the uFixedRot of pCtrl is true)) into tS
      put addKV(tS, "btype=" & (the uBodyType of pCtrl)) into tS
      put addKV(tS, "ldmp=" & (the uLinDamp of pCtrl)) into tS
      put addKV(tS, "admp=" & (the uAngDamp of pCtrl)) into tS
      put addKV(tS, "bul=" & (the uBullet of pCtrl is true)) into tS
      put addKV(tS, "ang=" & round(b2kAngle(pCtrl))) into tS
      put addKV(tS, "lspd=" & (the uLaunchSpeed of pCtrl)) into tS
      put addKV(tS, "ldir=" & (the uLaunchDir of pCtrl)) into tS
      put addKV(tS, "spin=" & (the uSpinRate of pCtrl)) into tS
      if the uGroup of pCtrl is not empty then put addKV(tS, "grp=" & (the uGroup of pCtrl)) into tS
      if numOr(the uLayer of pCtrl, 0) > 0 then put addKV(tS, "lyr=" & (the uLayer of pCtrl)) into tS
      if numOr(the uSleep of pCtrl, 0) > 0 then put addKV(tS, "slp=" & (the uSleep of pCtrl)) into tS
      if kindIsDynamic(the uKind of pCtrl) then put addKV(tS, "tuf=" & numOr(the uToughness of pCtrl, kToughnessDefault)) into tS
      if the uKind of pCtrl is "image" and the uShape of pCtrl is not empty then put addKV(tS, "ishp=" & (the uShape of pCtrl)) into tS
      if the uActive of pCtrl is false then put addKV(tS, "act=false") into tS
      if the uSensor of pCtrl is true then put addKV(tS, "sen=true") into tS
      if the uOnChans of pCtrl is not empty then put addKV(tS, "cat=" & (the uOnChans of pCtrl)) into tS
      if the uHitChans of pCtrl is not empty then put addKV(tS, "msk=" & (the uHitChans of pCtrl)) into tS
      if the uKind of pCtrl is "draw" then put addKV(tS, "pts=" & ptsPacked(pCtrl)) into tS
   end if
   switch tKind
      case "fan"
         put addKV(tS, "dir=" & (the uFanDir of pCtrl)) into tS
         put addKV(tS, "force=" & (the uFanForce of pCtrl)) into tS
         put addKV(tS, "fscale=" & (the uFanScale of pCtrl)) into tS
         break
      case "magnet"
         put addKV(tS, "pol=" & (the uMagPolarity of pCtrl)) into tS
         put addKV(tS, "force=" & (the uMagForce of pCtrl)) into tS
         put addKV(tS, "range=" & (the uMagRange of pCtrl)) into tS
         break
      case "bomb"
         put addKV(tS, "bradius=" & (the uBlastRadius of pCtrl)) into tS
         put addKV(tS, "bpower=" & (the uBlastPower of pCtrl)) into tS
         put addKV(tS, "fuse=" & (the uFuseOnRun of pCtrl is true)) into tS
         put addKV(tS, "flen=" & numOr(the uFuseLen of pCtrl, kBombFuseFrames)) into tS
         if the uSoftBlast of pCtrl is true then put addKV(tS, "soft=true") into tS
         if the uDestroys of pCtrl is true then put addKV(tS, "demo=true") into tS
         break
      case "laser"
         put addKV(tS, "ldr=" & numOr(the uLaserDir of pCtrl, 0)) into tS
         put addKV(tS, "lburn=" & numOr(the uLaserBurn of pCtrl, kLaserBurnDefault)) into tS
         if the uLaserCut of pCtrl is true then put addKV(tS, "cut=true") into tS
         break
      case "thruster"
         put addKV(tS, "tdr=" & numOr(the uThrustDir of pCtrl, 270)) into tS
         put addKV(tS, "tpw=" & numOr(the uThrustPower of pCtrl, 0)) into tS
         put addKV(tS, "tsp=" & numOr(the uThrustSpin of pCtrl, 0)) into tS
         if the uThrustAim of pCtrl is "body" then put addKV(tS, "tam=body") into tS
         break
      case "goal"
         put addKV(tS, "gsc=" & numOr(the uGoalScale of pCtrl, 1)) into tS
         break
   end switch
   return tS
end partSpecial

-- Append "key=value" to a packed special string, with a ; separator as needed.
function addKV pS, pKV
   if pS is empty then return pKV
   return pS & ";" & pKV
end addKV

-- Read one value out of a packed "key=value;..." special string (delimiter-safe).
function specialValue pSpecial, pKey
   local tPart, tResult, tKlen
   put empty into tResult
   put the number of chars of pKey into tKlen
   set the itemDelimiter to ";"
   repeat for each item tPart in pSpecial
      if char 1 to tKlen of tPart is pKey and char tKlen + 1 of tPart is "=" then
         put char tKlen + 2 to -1 of tPart into tResult
         exit repeat
      end if
   end repeat
   set the itemDelimiter to comma
   return tResult
end specialValue

function jointLine pIndex
   local tIdA, tIdB
   put 0 into tIdA
   put 0 into tIdB
   try
      if gJCa[pIndex] is not empty then put the uPartId of gJCa[pIndex] into tIdA
   end try
   try
      if gJCb[pIndex] is not empty then put the uPartId of gJCb[pIndex] into tIdB
   end try
   return "joint" & tab & gJKind[pIndex] & tab & tIdA & tab & tIdB & tab & \
         gJPx[pIndex] & tab & gJPy[pIndex] & tab & gJMotor[pIndex] & tab & \
         jointSpecial(pIndex)
end jointLine

on loadContraption
   local tFile, tData
   answer file "Open a contraption:" with type "Contraption|cbx,txt"
   put it into tFile
   if tFile is empty or the result is "cancel" then
      put "Load cancelled." into gStatus
      updateHud
      exit loadContraption
   end if
   put URL ("file:" & tFile) into tData
   if the result is not empty then
      put "Could not read that file: " & the result into gStatus
      updateHud
      exit loadContraption
   end if
   if line 1 of tData is not "CB1" and line 1 of tData is not "CB2" then
      put "That file is not a Contraption Builder save." into gStatus
      updateHud
      exit loadContraption
   end if
   if gMode is "run" then toggleMode
   rebuildFromText tData
   put "Loaded contraption from " & tFile & ". Press Run to simulate." into gStatus
   updateHud
end loadContraption

-- Rebuild the whole scene from CB2/CB1 text, clearing the stage first. Shared by
-- Load (from a file) and Reset (from the pre-run snapshot).
on rebuildFromText pData
   local tLine, tRec, tMap, tNew
   local tId, tKind, tX, tY, tW, tH, tBounce, tColor, tFileRef, tSpecial, tNm
   local tIdA, tIdB, tPx, tPy, tMotor, tA, tB, tJSpecial
   clearAll
   put "normal" into gGravityMode
   put "default" into gWorldFeel
   setWorldOptionDefaults
   put empty into tMap
   lock screen
   repeat for each line tLine in pData
      set the itemDelimiter to tab
      put item 1 of tLine into tRec
      if tRec is "part" then
         put item 2 of tLine into tId
         put item 3 of tLine into tKind
         put item 4 of tLine into tX
         put item 5 of tLine into tY
         put item 6 of tLine into tW
         put item 7 of tLine into tH
         put item 8 of tLine into tBounce
         put item 9 of tLine into tColor
         put item 10 of tLine into tFileRef
         put item 11 of tLine into tSpecial
         put item 12 of tLine into tNm
         set the itemDelimiter to comma
         put rebuildPart(tKind, tX, tY, tW, tH, tColor, tFileRef) into tNew
         if tNew is not empty then
            put tNew into tMap[tId]
            if tBounce is not empty then
               put clampRange(tBounce, 0, 0.9) into tBounce
               set the uBounce of tNew to tBounce
               if tBounce > 0 then b2kSetBounce tNew, tBounce
            end if
            applyPartSpecial tNew, tSpecial
            if tNm is not empty then set the uPartName of tNew to tNm   -- restore a renamed part's name
         end if
      else if tRec is "joint" then
         put item 2 of tLine into tKind
         put item 3 of tLine into tIdA
         put item 4 of tLine into tIdB
         put item 5 of tLine into tPx
         put item 6 of tLine into tPy
         put item 7 of tLine into tMotor
         put item 8 of tLine into tJSpecial
         set the itemDelimiter to comma
         put tMap[tIdA] into tA
         if tIdB is 0 then
            put empty into tB
         else
            put tMap[tIdB] into tB
         end if
         if tA is not empty and (tB is not empty or tKind is "hinge" or tKind is "pin" or tKind is "deckpin") then
            if connectJoint(tKind, tA, tB, tPx, tPy, tMotor) then applyJointSpecial gJN, tJSpecial
         end if
      else if tRec is "wire" then
         put item 2 of tLine into tIdA
         put item 3 of tLine into tIdB
         if (tIdA is among the keys of tMap) and (tIdB is among the keys of tMap) then
            addWire tMap[tIdA], tMap[tIdB]
         end if
      else if tRec is "world" then
         put item 2 of tLine into gGravityMode
         put item 3 of tLine into gWorldFeel
         if gWorldFeel is empty then put "default" into gWorldFeel
         if item 4 of tLine is not empty then put (item 4 of tLine is "true") into gCCD
         if item 5 of tLine is not empty then put (item 5 of tLine is "true") into gSleepOn
         if item 6 of tLine is not empty then put (item 6 of tLine is "true") into gWarmStart
         if item 7 of tLine is not empty then put item 7 of tLine into gSubsteps
         set the itemDelimiter to comma
      else
         set the itemDelimiter to comma
      end if
   end repeat
   set the itemDelimiter to comma
   applyGravityMode
   applyWorldFeel
   refreshGravityLabel
   refreshWorldFeelLabel
   renderBuild
   unlock screen
end rebuildFromText

-- Restore the layout captured when Run last started, and return to Build mode.
on resetMachine
   if gPreRun is empty then
      put "Nothing to reset yet - press Run first; then Reset brings this build back." into gStatus
      updateHud
      exit resetMachine
   end if
   lock screen
   if gMode is "run" then toggleMode
   rebuildFromText gPreRun
   unlock screen
   put "Reset to your pre-run build." into gStatus
   updateHud
end resetMachine

function rebuildPart pKind, pX, pY, pW, pH, pColor, pFile
   if pW is empty or pW < 1 then put kBoxMin into pW
   if pH is empty or pH < 1 then put kBoxMin into pH
   switch pKind
      case "box"
         return placeBox(pX, pY, pW, pH, pColor)
      case "ball"
         return placeBall(pX, pY, pW, pColor)
      case "capsule"
         return placeCapsule(pX, pY, max(pW, pH), min(pW, pH), pColor)
      case "poly"
         return placePoly(pX, pY, round(pW / 2), pColor)
      case "anchor"
         return placeAnchor(pX, pY)
      case "platform"
      case "ramp"
      case "hill"
         return placeTerrain(pKind, pX, pY, pW, pH)
      case "draw"
         return placeDrawPlaceholder(pX, pY)   -- points + chain restored by applyPartSpecial
      case "image"
         return rebuildImage(pX, pY, pW, pH, pFile)
      case "balloon"
         return placeBalloon(pX, pY)
      case "bomb"
         return placeBomb(pX, pY)
      case "plate"
         return placePlate(pX, pY)
      case "sensor"
         return placeSensor(pX, pY)
      case "fan"
         return placeFan(pX, pY)
      case "magnet"
         return placeMagnet(pX, pY)
      case "laser"
         return placeLaser(pX, pY)        -- emitter restored from the saved anchor; beam recast by applyPartSpecial
      case "thruster"
         return placeThruster(pX, pY)
      case "goal"
         return placeGoal(pX, pY)
   end switch
   return empty
end rebuildPart

function rebuildImage pX, pY, pW, pH, pFile
   local tName, tRef
   if pFile is empty then return empty
   put "cb_img_" & the milliseconds & "_" & random(99999) into tName
   create image tName
   put the long id of image tName into tRef
   set the filename of tRef to pFile
   set the width of tRef to pW
   set the height of tRef to pH
   set the loc of tRef to round(pX) & "," & round(pY)
   b2kAddBox tRef
   tagPart tRef, "image", empty, pFile
   return tRef
end rebuildImage

-- =====================================================================
-- HUD + small helpers
-- =====================================================================
on updateHud
   local tInfo, tModeTxt, tMotorTxt
   if gMode is "run" then put "RUN" into tModeTxt
   else put "BUILD" into tModeTxt
   if gMotorOn then put "Motor ON " & gMotorSpeed & " deg/s" into tMotorTxt
   else put "Motor OFF (" & gMotorSpeed & " deg/s)" into tMotorTxt
   put "Mode: " & tModeTxt into tInfo
   if gJointTool is not empty then put tInfo & "    Joint: " & niceName(gJointTool) into tInfo
   else put tInfo & "    Tool: " & niceName(gTool) into tInfo
   put tInfo & "    " & tMotorTxt into tInfo
   put tInfo & "    Parts: " & b2kBodyCount() & "    Joints: " & liveJointCount() into tInfo
   if gBouncy then put tInfo & "    Bouncy" into tInfo
   if gMode is "run" and gFps is not empty then put tInfo & "    " & gFps & " fps" into tInfo
   if gMode is "run" then put tInfo & hudPerf() & hudSelection() into tInfo
   if gStatus is not empty then put tInfo & "     |  " & gStatus into tInfo
   if there is a field "ui_status" then put tInfo into field "ui_status"
end updateHud

-- Live engine telemetry for the status bar (Run only): solver step time + how many
-- bodies are still awake. b2kProfile returns "totalStep,collide,solve" in ms.
function hudPerf
   local tProf
   put b2kProfile() into tProf
   if tProf is empty then return empty
   set the itemDelimiter to comma
   return "    step " & fmtMs(item 1 of tProf) & "ms / awake " & b2kAwakeBodyCount()
end hudPerf

-- Live readout for the selected part or joint, so the inspector numbers can be
-- watched changing during a run (speed/mass/angle, or a joint's own measure).
function hudSelection
   local tK, tH
   if gSelJoint is not empty then
      put gJKind[gSelJoint] into tK
      put gJHandle[gSelJoint] into tH
      if tK is "hinge" then return "    hinge " & round(b2kHingeAngle(tH)) & " deg"
      if tK is "rope" then return "    rope " & round(b2kRopeLength(tH)) & " px"
      if tK is "slider" then return "    slider " & round(b2kSliderPos(tH)) & " px"
      return empty
   end if
   if gSelPart is not empty and the uKind of gSelPart is "laser" then
      if the uLaserDist of gSelPart is empty then return "    beam: no hit"
      return "    beam: " & (the uLaserDist of gSelPart) & " px"
   end if
   if gSelPart is empty or not kindHasBody(the uKind of gSelPart) then return empty
   return "    sel: " & round(b2kSpeed(gSelPart)) & " px/s / " & fmtMass(b2kMass(gSelPart)) & " / " & round(b2kAngle(gSelPart)) & " deg"
end hudSelection

-- Small number formatters for the readouts.
function fmtMs pN
   if pN is empty or pN is not a number then return "0.0"
   return format("%.1f", pN)
end fmtMs

function fmtMass pN
   if pN is empty or pN is not a number then return "0 kg"
   if pN < 10 then return format("%.1f", pN) & " kg"
   return round(pN) & " kg"
end fmtMass

on tickHud
   local tNow
   put the milliseconds into tNow   -- one clock read per pass (perf playbook)
   add 1 to gFrames
   if gFpsTime is empty then put tNow into gFpsTime
   if tNow - gFpsTime >= kFpsWindowMs then
      put round(gFrames * 1000 / (tNow - gFpsTime)) into gFps
      put 0 into gFrames
      put tNow into gFpsTime
   end if
   -- Refresh the HUD ~10x/sec while running so the live telemetry reads smoothly,
   -- without rebuilding the whole status string every single frame.
   if gHudTime is empty or (tNow - gHudTime) >= 100 then
      put tNow into gHudTime
      updateHud
      if gPlaying and not gGameWon and there is a field "ui_playbannerlbl" then
         put "> PLAY - " & playElapsed() & "s    get a movable part into the goal" into field "ui_playbannerlbl"
      end if
   end if
end tickHud

function rnd pLow, pHigh
   return pLow + random(max(1, pHigh - pLow))
end rnd

function randomColor
   return line (random(6)) of shapePalette()
end randomColor

function shapePalette
   return "92,150,222" & cr & "84,206,142" & cr & "232,182,92" & cr \
         & "214,92,92" & cr & "206,124,206" & cr & "120,200,232"
end shapePalette

-- =====================================================================
-- Special objects: helium balloons, bombs, pressure plates, fans, magnets.
-- All are assembled from the same friendly b2k... Kit as the basic shapes.
-- =====================================================================

-- A helium balloon: a light ball with a negative gravity scale, so it rises.
-- Linear damping gives it a gentle terminal speed instead of shooting away.
function placeBalloon pX, pY
   local tCtrl
   b2kSpawnBall pX, pY, kBalloonDiam, "236,120,150"
   put the result into tCtrl
   tagPart tCtrl, "balloon", "236,120,150", empty
   b2kSetDensity tCtrl, 0.3
   set the uDensity of tCtrl to 0.3
   b2kSetGravityScale tCtrl, kBalloonGravScale
   set the uGravity of tCtrl to kBalloonGravScale
   b2kSetDamping tCtrl, kBalloonDamp, 0.4
   return tCtrl
end placeBalloon

-- A bomb: a dynamic ball that detonates on a hard hit, a pressure-plate
-- signal, or (optionally) a fuse lit the moment Run starts.
function placeBomb pX, pY
   local tCtrl
   b2kSpawnBall pX, pY, kBombDiam, "150,40,40"
   put the result into tCtrl
   tagPart tCtrl, "bomb", "150,40,40", empty
   set the uFuseOnRun of tCtrl to true     -- bombs arm on Run by default (fuse length set in the inspector)
   set the uFuse of tCtrl to 0
   set the uFuseLen of tCtrl to kBombFuseFrames    -- countdown frames once armed (60 = ~1s)
   set the uDestroys of tCtrl to false             -- default: push parts; toggle 'Demolish' to vaporise them
   set the uBlastRadius of tCtrl to kBombRadius
   set the uBlastPower of tCtrl to kBombPower
   return tCtrl
end placeBomb

-- A pressure plate: a flat, solid, static bar that notices weight resting on it.
function placePlate pX, pY
   local tName, tRef
   put "cb_plate_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "rectangle"
   set the filled of tRef to true
   set the backgroundColor of tRef to "150,160,180"
   set the foregroundColor of tRef to "210,214,224"
   set the lineSize of tRef to 1
   set the width of tRef to kPlateW
   set the height of tRef to kPlateH
   set the loc of tRef to round(pX) & "," & round(pY)
   b2kAddStatic tRef
   tagPart tRef, "plate", "150,160,180", empty
   return tRef
end placePlate

-- A non-solid trigger zone. Nothing collides with it, but when a dynamic body
-- ENTERS it (on b2kSensorEnter) it fires the same signal as a pressure plate -
-- bombs go off and motors flip. Drawn translucent so it reads as a zone.
function placeSensor pX, pY
   local tName, tRef
   put "cb_sensor_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "rectangle"
   set the filled of tRef to true
   set the backgroundColor of tRef to "232,196,92"     -- amber, idle
   set the foregroundColor of tRef to "120,96,32"
   set the lineSize of tRef to 2
   set the blendLevel of tRef to 55                      -- translucent: clearly a zone, not solid
   set the width of tRef to kSensorW
   set the height of tRef to kSensorH
   set the loc of tRef to round(pX) & "," & round(pY)
   b2kAddSensor tRef                                      -- static, non-solid trigger fixture
   tagPart tRef, "sensor", "232,196,92", empty
   return tRef
end placeSensor

-- A fan/wind zone: a translucent arrow that pushes parts inside it. No body.
function placeFan pX, pY
   local tName, tRef
   put "cb_fan_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "polygon"
   set the filled of tRef to true
   set the backgroundColor of tRef to "90,170,230"
   set the foregroundColor of tRef to "150,210,255"
   set the lineSize of tRef to 1
   set the blendLevel of tRef to 64
   set the uFanDir of tRef to 270             -- 0=right 90=down 180=left 270=up
   set the uFanForce of tRef to kFanForce
   set the uFanScale of tRef to 1
   set the points of tRef to fanArrowPoints(round(pX), round(pY), kFanW div 2, kFanH div 2, 270)
   tagPart tRef, "fan", "90,170,230", empty
   return tRef
end placeFan

-- A magnet: a disc that pulls (or pushes) nearby parts. No body.
function placeMagnet pX, pY
   local tName, tRef
   put "cb_magnet_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "oval"
   set the filled of tRef to true
   set the backgroundColor of tRef to "120,90,210"
   set the foregroundColor of tRef to "210,200,250"
   set the lineSize of tRef to 2
   set the width of tRef to 30
   set the height of tRef to 30
   set the loc of tRef to round(pX) & "," & round(pY)
   set the uMagPolarity of tRef to 1          -- +1 attract, -1 repel
   set the uMagForce of tRef to kMagnetForce
   set the uMagRange of tRef to kMagnetRange
   tagPart tRef, "magnet", "120,90,210", empty
   return tRef
end placeMagnet

-- A goal zone: a no-body target area. In Play, getting a movable part inside it
-- (all goals at once) wins the puzzle. Scaled by uGoalScale, like the fan.
function placeGoal pX, pY
   local tName, tRef
   put "cb_goal_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "rectangle"
   set the filled of tRef to true
   set the backgroundColor of tRef to "92,210,120"
   set the foregroundColor of tRef to "40,150,80"
   set the lineSize of tRef to 3
   set the blendLevel of tRef to 58                       -- translucent: a target zone, not a solid
   set the uGoalScale of tRef to 1
   set the width of tRef to kGoalW
   set the height of tRef to kGoalH
   set the loc of tRef to round(pX) & "," & round(pY)
   tagPart tRef, "goal", "92,210,120", empty
   return tRef
end placeGoal

-- Resize a goal zone around its centre from its scale.
on drawGoalShape pGoal
   local tLoc, tScale
   put the loc of pGoal into tLoc
   put numOr(the uGoalScale of pGoal, 1) into tScale
   set the width of pGoal to round(kGoalW * tScale)
   set the height of pGoal to round(kGoalH * tScale)
   set the loc of pGoal to tLoc
end drawGoalShape

-- Rebuild the fan's arrow polygon around its current centre for its direction.
on drawFanShape pFan
   local tCx, tCy, tScale, tHw, tHh
   put item 1 of the loc of pFan into tCx
   put item 2 of the loc of pFan into tCy
   put the uFanScale of pFan into tScale
   if tScale is empty then put 1 into tScale
   put round(kFanW * tScale / 2) into tHw
   put round(kFanH * tScale / 2) into tHh
   set the points of pFan to fanArrowPoints(tCx, tCy, tHw, tHh, the uFanDir of pFan)
end drawFanShape

-- A filled triangle that points the way the fan blows (within a w x h box).
function fanArrowPoints pCx, pCy, pHw, pHh, pDir
   local tP
   put empty into tP
   switch pDir
      case 0       -- right
         put (pCx + pHw) & "," & pCy & cr after tP
         put (pCx - pHw) & "," & (pCy - pHh) & cr after tP
         put (pCx - pHw) & "," & (pCy + pHh) & cr after tP
         break
      case 90      -- down
         put pCx & "," & (pCy + pHh) & cr after tP
         put (pCx - pHw) & "," & (pCy - pHh) & cr after tP
         put (pCx + pHw) & "," & (pCy - pHh) & cr after tP
         break
      case 180     -- left
         put (pCx - pHw) & "," & pCy & cr after tP
         put (pCx + pHw) & "," & (pCy - pHh) & cr after tP
         put (pCx + pHw) & "," & (pCy + pHh) & cr after tP
         break
      default      -- 270 up
         put pCx & "," & (pCy - pHh) & cr after tP
         put (pCx - pHw) & "," & (pCy + pHh) & cr after tP
         put (pCx + pHw) & "," & (pCy + pHh) & cr after tP
   end switch
   put (line 1 of tP) after tP                -- close the triangle
   return tP
end fanArrowPoints

-- A laser: a no-body emitter that casts a ray each frame and draws the beam to
-- whatever it hits first (a wall counts), marking the distance. Shows off the
-- Kit's ray API (b2kRayHit + b2kRayHitX/Y + b2kRayDist). The graphic is the beam
-- itself - a thick line from the emitter (point 1) to the hit point (point 2).
function placeLaser pX, pY
   local tName, tRef
   put "cb_laser_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "line"
   set the lineSize of tRef to 5
   set the foregroundColor of tRef to "236,80,80"
   set the uLaserDir of tRef to 0            -- 0=right 90=down 180=left 270=up (45 deg steps)
   set the uLaserCut of tRef to false        -- default: a sightline; toggle 'Cut' to burn through parts
   set the uLaserBurn of tRef to kLaserBurnDefault
   set the points of tRef to round(pX) & "," & round(pY) & cr & round(pX + 40) & "," & round(pY)
   tagPart tRef, "laser", "236,80,80", empty
   drawLaserBeam tRef
   return tRef
end placeLaser

-- Recast a laser's ray from its emitter (point 1) along uLaserDir and stretch the
-- beam to the first hit; store the distance for the live readout.
on drawLaserBeam pLaser
   local tHead, tEx, tEy, tRad, tFx, tFy, tHx, tHy, tHitCtrl
   set the itemDelimiter to comma
   put line 1 of the points of pLaser into tHead
   if tHead is empty then exit drawLaserBeam
   put item 1 of tHead into tEx
   put item 2 of tHead into tEy
   put numOr(the uLaserDir of pLaser, 0) * kPI / 180 into tRad
   put tEx + kLaserReach * cos(tRad) into tFx
   put tEy + kLaserReach * sin(tRad) into tFy
   put b2kRayHit(tEx, tEy, tFx, tFy) into tHitCtrl   -- returns the hit control (or empty), NOT a boolean
   if tHitCtrl is not empty then
      put b2kRayHitX() into tHx
      put b2kRayHitY() into tHy
      set the uLaserDist of pLaser to round(b2kRayDist())
   else
      put tFx into tHx
      put tFy into tHy
      set the uLaserDist of pLaser to empty
   end if
   set the points of pLaser to round(tEx) & "," & round(tEy) & cr & round(tHx) & "," & round(tHy)
   -- Cutting beam: a SUSTAINED hit on a movable part burns through and destroys it.
   -- The burn cools back to zero after kLaserCool ms without a hit, so only continuous
   -- exposure accumulates - a part that merely grazes the beam (or a fresh Run) never
   -- inherits stale burn.
   if gMode is "run" and the uLaserCut of pLaser is true and tHitCtrl is not empty \
         and (tHitCtrl is among the lines of gParts) and kindIsDynamic(the uKind of tHitCtrl) then
      local tNow
      put the milliseconds into tNow
      if tNow - numOr(the uBurnAt of tHitCtrl, 0) > kLaserCool then set the uBurn of tHitCtrl to 0
      set the uBurnAt of tHitCtrl to tNow
      set the uBurn of tHitCtrl to numOr(the uBurn of tHitCtrl, 0) + 1
      if the uBurn of tHitCtrl >= laserDestroyFrames(pLaser, tHitCtrl) then destroyPart tHitCtrl
   end if
end drawLaserBeam

-- Required sustained-hit frames for this laser to cut through this target. The
-- laser can be tuned to cut faster/slower, while each dynamic part can be made
-- tougher; the larger value wins so tough parts resist even fast-cut lasers.
function laserDestroyFrames pLaser, pTarget
   local tLaserFrames, tToughFrames
   put round(numOr(the uLaserBurn of pLaser, kLaserBurnDefault)) into tLaserFrames
   put round(numOr(the uToughness of pTarget, kToughnessDefault)) into tToughFrames
   if tLaserFrames < 1 then put 1 into tLaserFrames
   if tToughFrames < 1 then put 1 into tToughFrames
   return max(tLaserFrames, tToughFrames)
end laserDestroyFrames

-- Recast every laser (called each frame while running and on every build redraw).
on updateLasers
   local tL
   repeat for each line tL in gKindList["laser"]
      if tL is not empty then drawLaserBeam tL
   end repeat
end updateLasers

-- A thruster: a dynamic rocket body that drives itself. Each frame it applies a
-- continuous force along its own facing (b2kForce) and, when its ignition fires
-- on the first Run frame, a one-shot velocity pop (b2kPush); an optional spin
-- adds continuous torque (b2kTorque). Lock its rotation for a straight climb, or
-- leave it free to tumble.
function placeThruster pX, pY
   local tRef
   b2kSpawnBox pX, pY, 38, 56, "74,84,104"      -- a tall rocket body
   put the result into tRef
   set the uThrustDir of tRef to 270             -- thrust upward by default (lifts off)
   set the uThrustPower of tRef to 700
   set the uThrustSpin of tRef to 0
   set the uThrustLit of tRef to false
   set the uThrustAim of tRef to "world"     -- thrust a FIXED direction by default (predictable)
   tagPart tRef, "thruster", "74,84,104", empty
   set the uFixedRot of tRef to true         -- and fly straight rather than tumble
   b2kSetFixedRotation tRef, true
   return tRef
end placeThruster

-- Reset every thruster's ignition so a fresh Run pops it off the pad once.
on armThrusters
   local tT
   repeat for each line tT in gKindList["thruster"]
      if tT is empty then next repeat
      set the uThrustLit of tT to false
      set the uThrustArmed of tT to true      -- thrusters start armed each Run; a trigger can switch them off
   end repeat
end armThrusters

-- Drive every thruster each frame: ignition pop, then sustained thrust + spin.
on updateThrusters
   local tT, tRad, tPow
   repeat for each line tT in gKindList["thruster"]
      if tT is empty then next repeat
      if (the uThrustArmed of tT is "false") or (numOr(the uThrustPower of tT, 0) <= 0) then
         hideThrusterFlame tT          -- off: no exhaust
         next repeat
      end if
      put numOr(the uThrustPower of tT, 0) into tPow
      -- world-fixed thrust by default (predictable); "body" aim steers with the rocket's nose
      if the uThrustAim of tT is "body" then
         put (numOr(the uThrustDir of tT, 270) + b2kAngle(tT)) * kPI / 180 into tRad
      else
         put numOr(the uThrustDir of tT, 270) * kPI / 180 into tRad
      end if
      if the uThrustLit of tT is not true then    -- one-shot ignition kick
         b2kPush tT, 140 * cos(tRad), 140 * sin(tRad)
         set the uThrustLit of tT to true
      end if
      b2kForce tT, tPow * cos(tRad), tPow * sin(tRad)
      if numOr(the uThrustSpin of tT, 0) is not 0 then b2kTorque tT, (the uThrustSpin of tT)
      drawThrusterFlame tT, tRad, tPow
   end repeat
end updateThrusters

-- A translucent exhaust flame at the thruster's tail (opposite the thrust),
-- sized by power, so you can see which way it pushes and how hard.
on drawThrusterFlame pT, pRad, pPow
   local tName, tCx, tCy, tLen, tOff, tEx, tEy
   put "cb_flame_" & (the uPartId of pT) into tName
   if there is no graphic tName then
      create graphic tName
      set the layerMode of graphic tName to "dynamic"   -- follows its thruster every frame
      set the style of graphic tName to "oval"
      set the filled of graphic tName to true
      set the lineSize of graphic tName to 0
      set the backgroundColor of graphic tName to "255,150,50"
      set the blendLevel of graphic tName to 28
   end if
   set the itemDelimiter to comma
   put item 1 of the loc of pT into tCx
   put item 2 of the loc of pT into tCy
   put min(40, 14 + pPow / 50) into tLen          -- flame grows with thrust power
   put (the height of pT) / 2 + tLen / 2 into tOff
   put tCx - tOff * cos(pRad) into tEx            -- exhaust is opposite the thrust direction
   put tCy - tOff * sin(pRad) into tEy
   set the width of graphic tName to round(tLen)
   set the height of graphic tName to round(tLen)
   set the loc of graphic tName to round(tEx) & "," & round(tEy)
   set the visible of graphic tName to true
end drawThrusterFlame

on hideThrusterFlame pT
   local tName
   put "cb_flame_" & (the uPartId of pT) into tName
   if there is a graphic tName then set the visible of graphic tName to false
end hideThrusterFlame

-- Safety net: a body flung, blasted or thrust clean out of the arena (past a
-- generous margin) is pulled back to the edge with its speed killed, so nothing
-- is ever lost off-screen. CCD stops most tunnelling; this catches the rest.
on containParts
   local tP, tLoc, tX, tY, tNX, tNY
   set the itemDelimiter to comma
   repeat for each line tP in dynamicParts()
      if tP is empty then next repeat
      put the loc of tP into tLoc
      put item 1 of tLoc into tX
      put item 2 of tLoc into tY
      put tX into tNX
      put tY into tNY
      if tX < gArenaL - kContainMargin then
         put gArenaL + 12 into tNX
      else if tX > gArenaR + kContainMargin then
         put gArenaR - 12 into tNX
      end if
      if tY < gArenaT - kContainMargin then
         put gArenaT + 12 into tNY
      else if tY > gArenaB + kContainMargin then
         put gArenaB - 12 into tNY
      end if
      if tNX is not tX or tNY is not tY then
         b2kMoveTo tP, tNX, tNY, round(b2kAngle(tP))
         b2kSetVelocity tP, 0, 0
      end if
   end repeat
end containParts

-- Restore every saved per-part setting (common body props + per-kind extras).
on applyPartSpecial pCtrl, pSpecial
   if pCtrl is empty then exit applyPartSpecial
   local tKind, tV
   put the uKind of pCtrl into tKind
   if kindIsTerrain(tKind) then               -- restore grip + angle + facing, then redraw
      put specialValue(pSpecial, "fric") into tV
      if tV is not empty then set the uFriction of pCtrl to tV
      put specialValue(pSpecial, "tang") into tV
      if tV is empty then put 0 into tV
      set the uAngle of pCtrl to tV
      set the uFlip of pCtrl to (specialValue(pSpecial, "flip") is "true")
      regenTerrain pCtrl
      exit applyPartSpecial
   end if
   if kindHasBody(tKind) then
      put specialValue(pSpecial, "fric") into tV
      if tV is not empty then
         put clampRange(tV, 0, 2) into tV
         set the uFriction of pCtrl to tV
         b2kSetFriction pCtrl, tV
      end if
      put specialValue(pSpecial, "dens") into tV
      if tV is not empty then
         put clampRange(tV, 0.3, 3) into tV
         set the uDensity of pCtrl to tV
         b2kSetDensity pCtrl, tV
      end if
      put specialValue(pSpecial, "grav") into tV
      if tV is not empty then
         put clampRange(tV, -2, 3) into tV
         set the uGravity of pCtrl to tV
         b2kSetGravityScale pCtrl, tV
      end if
      if specialValue(pSpecial, "frot") is "true" then
         set the uFixedRot of pCtrl to true
         b2kSetFixedRotation pCtrl, true
      end if
      put specialValue(pSpecial, "btype") into tV
      if tV is "static" or tV is "kinematic" then
         set the uBodyType of pCtrl to tV
         b2kSetType pCtrl, tV
         put true into gDynDirty
      end if
      put specialValue(pSpecial, "slp") into tV
      if tV is not empty then
         put clampRange(tV, 0, 200) into tV
         set the uSleep of pCtrl to tV
         b2kSetSleepThreshold pCtrl, tV
      end if
      if specialValue(pSpecial, "act") is "false" then
         set the uActive of pCtrl to false
         b2kDisable pCtrl
      end if
      put specialValue(pSpecial, "ldmp") into tV
      if tV is not empty then
         put clampRange(tV, 0, 5) into tV
         set the uLinDamp of pCtrl to tV
         b2kSetDamping pCtrl, tV, empty
      end if
      put specialValue(pSpecial, "admp") into tV
      if tV is not empty then
         put clampRange(tV, 0, 5) into tV
         set the uAngDamp of pCtrl to tV
         b2kSetDamping pCtrl, empty, tV
      end if
      if specialValue(pSpecial, "bul") is "true" then
         set the uBullet of pCtrl to true
         b2kSetBullet pCtrl, true
      end if
      put specialValue(pSpecial, "lspd") into tV
      if tV is not empty then set the uLaunchSpeed of pCtrl to clampRange(tV, 0, 1500)
      put specialValue(pSpecial, "ldir") into tV
      if tV is not empty then set the uLaunchDir of pCtrl to normDegrees(tV, 0)
      put specialValue(pSpecial, "spin") into tV
      if tV is not empty then set the uSpinRate of pCtrl to clampRange(tV, -720, 720)
      put specialValue(pSpecial, "tuf") into tV
      if tV is not empty then set the uToughness of pCtrl to clampRange(tV, 1, 600)
      put specialValue(pSpecial, "grp") into tV
      if tV is not empty then set the uGroup of pCtrl to tV
      put specialValue(pSpecial, "lyr") into tV
      if tV is not empty then
         set the uLayer of pCtrl to clampRange(tV, 0, 8)
         applyCollisionLayer pCtrl
      end if
      put specialValue(pSpecial, "cat") into tV
      if tV is not empty then set the uOnChans of pCtrl to tV
      put specialValue(pSpecial, "msk") into tV
      if tV is not empty then set the uHitChans of pCtrl to tV
      applyPartFilter pCtrl                  -- no-op unless cat/msk were set above
      put specialValue(pSpecial, "ang") into tV
      if tV is not empty and tV is not 0 then
         b2kMoveTo pCtrl, item 1 of the loc of pCtrl, item 2 of the loc of pCtrl, normDegrees(tV, 0)
      end if
   end if
   switch tKind
      case "fan"
         put specialValue(pSpecial, "dir") into tV
         if tV is not empty then set the uFanDir of pCtrl to normDegrees(tV, 270)
         put specialValue(pSpecial, "force") into tV
         if tV is not empty then set the uFanForce of pCtrl to clampRange(tV, 0, 40000)
         put specialValue(pSpecial, "fscale") into tV
         if tV is not empty then set the uFanScale of pCtrl to clampRange(tV, 0.5, 2.5)
         drawFanShape pCtrl
         break
      case "magnet"
         put specialValue(pSpecial, "pol") into tV
         if tV is not empty and tV is a number and tV < 0 then set the uMagPolarity of pCtrl to -1
         put specialValue(pSpecial, "force") into tV
         if tV is not empty then set the uMagForce of pCtrl to clampRange(tV, 100, 50000)
         put specialValue(pSpecial, "range") into tV
         if tV is not empty then set the uMagRange of pCtrl to clampRange(tV, 60, 1400)
         break
      case "bomb"
         put specialValue(pSpecial, "bradius") into tV
         if tV is not empty then set the uBlastRadius of pCtrl to clampRange(tV, 60, 1200)
         put specialValue(pSpecial, "bpower") into tV
         if tV is not empty then set the uBlastPower of pCtrl to clampRange(tV, 200, 30000)
         if specialValue(pSpecial, "fuse") is "true" then set the uFuseOnRun of pCtrl to true
         put specialValue(pSpecial, "flen") into tV
         if tV is not empty then set the uFuseLen of pCtrl to clampRange(tV, 15, 900)
         if specialValue(pSpecial, "soft") is "true" then set the uSoftBlast of pCtrl to true
         if specialValue(pSpecial, "demo") is "true" then set the uDestroys of pCtrl to true
         break
      case "laser"
         put specialValue(pSpecial, "ldr") into tV
         if tV is not empty then set the uLaserDir of pCtrl to normDegrees(tV, 0)
         put specialValue(pSpecial, "lburn") into tV
         if tV is not empty then set the uLaserBurn of pCtrl to clampRange(tV, 1, 600)
         if specialValue(pSpecial, "cut") is "true" then set the uLaserCut of pCtrl to true
         drawLaserBeam pCtrl
         break
      case "thruster"
         put specialValue(pSpecial, "tdr") into tV
         if tV is not empty then set the uThrustDir of pCtrl to normDegrees(tV, 270)
         put specialValue(pSpecial, "tpw") into tV
         if tV is not empty then set the uThrustPower of pCtrl to clampRange(tV, 0, 40000)
         put specialValue(pSpecial, "tsp") into tV
         if tV is not empty then set the uThrustSpin of pCtrl to clampRange(tV, -40000, 40000)
         if specialValue(pSpecial, "tam") is "body" then set the uThrustAim of pCtrl to "body"
         set the uThrustLit of pCtrl to false
         break
      case "goal"
         put specialValue(pSpecial, "gsc") into tV
         if tV is not empty then set the uGoalScale of pCtrl to clampRange(tV, 0.5, 3)
         drawGoalShape pCtrl
         break
   end switch
   if tKind is "draw" then                       -- restore a freehand-drawn ground mass + its chain
      put specialValue(pSpecial, "pts") into tV
      if tV is not empty then
         replace "|" with cr in tV
         set the points of pCtrl to tV
         b2kAddChain pCtrl, tV, true             -- closed loop, same as when it was drawn
      end if
   end if
   -- Restore a chosen image collision shape and/or the sensor (trigger-zone) flag.
   -- Both end in a reshape, so set the flags first and reshape ONCE: the rebuilt
   -- shape picks up the new outline (image) and the sensor state, then the
   -- material and collision layer (which a reshape resets) are re-applied.
   local tReshape
   put false into tReshape
   if tKind is "image" then
      put specialValue(pSpecial, "ishp") into tV
      if tV is not empty then
         set the uShape of pCtrl to tV
         put true into tReshape
      end if
   end if
   if specialValue(pSpecial, "sen") is "true" then
      set the uSensor of pCtrl to true
      b2kSetSensor pCtrl, true
      put true into tReshape
   end if
   if tReshape then
      b2kReshape pCtrl, partShape(pCtrl)
      reapplyMaterial pCtrl
      reapplyCollision pCtrl
      applySensorLook pCtrl
   end if
end applyPartSpecial

-- =====================================================================
-- Special-object behaviour, run each frame from on b2kFrame.
-- =====================================================================

-- Fans and magnets push the dynamic parts in/near them. The candidate part
-- list is cached (dynamicParts) so this stays cheap as the scene grows. Per-frame
-- fan/magnet properties are snapshotted once, outside the nested part loop, so a
-- large contraption does not repeatedly ask LiveCode for the same rect/loc/custom
-- properties for every dynamic body.
on applyFieldForces
   local tFans, tMags, tParts, tP, tPx, tPy, tF, tM, tFanRects, tFanFx, tFanFy, tR
   local tMagX, tMagY, tMagRange, tMagForce, tMagPol, tLoc, tDir, tForce, tPol
   local tMx, tMy, tdx, tdy, tDist, tRange, tPull, tFx, tFy
   put gKindList["fan"] into tFans
   put gKindList["magnet"] into tMags
   if tFans is empty and tMags is empty then exit applyFieldForces
   put dynamicParts() into tParts
   if tParts is empty then exit applyFieldForces
   set the itemDelimiter to comma                 -- loc and rect are both comma lists

   -- A fan's rect/direction/force cannot change within one frame: convert each
   -- fan into a cached zone rect plus a screen-oriented force vector.
   repeat for each line tF in tFans
      if tF is empty then next repeat
      put the rect of tF into tFanRects[tF]
      put clampRange(numOr(the uFanForce of tF, kFanForce), 0, 40000) into tForce
      put normDegrees(the uFanDir of tF, 270) into tDir
      put 0 into tFanFx[tF]
      put 0 into tFanFy[tF]
      switch tDir
         case 0
            put tForce into tFanFx[tF]
            break
         case 90
            put tForce into tFanFy[tF]
            break
         case 180
            put - tForce into tFanFx[tF]
            break
         default
            put - tForce into tFanFy[tF]
      end switch
   end repeat

   -- Same for magnets: cache centre/range/force/polarity once, and skip invalid
   -- ranges before the nested part loop to avoid per-part guards.
   repeat for each line tM in tMags
      if tM is empty then next repeat
      put clampRange(numOr(the uMagRange of tM, kMagnetRange), 0, 1400) into tRange
      if tRange <= 0 then next repeat
      put the loc of tM into tLoc
      put item 1 of tLoc into tMagX[tM]
      put item 2 of tLoc into tMagY[tM]
      put tRange into tMagRange[tM]
      put clampRange(numOr(the uMagForce of tM, kMagnetForce), 0, 50000) into tMagForce[tM]
      put numOr(the uMagPolarity of tM, 1) into tPol
      if tPol is not a number then put 1 into tPol
      if tPol < 0 then put -1 into tMagPol[tM]
      else put 1 into tMagPol[tM]
   end repeat

   repeat for each line tP in tParts
      if tP is empty then next repeat
      put the loc of tP into tLoc
      put item 1 of tLoc into tPx
      put item 2 of tLoc into tPy
      repeat for each line tF in tFans
         if tF is empty then next repeat
         put tFanRects[tF] into tR
         if tPx >= item 1 of tR and tPx <= item 3 of tR and tPy >= item 2 of tR and tPy <= item 4 of tR then
            b2kForce tP, tFanFx[tF], tFanFy[tF]
         end if
      end repeat
      repeat for each line tM in tMags
         if tM is empty or tMagRange[tM] is empty then next repeat
         put tMagX[tM] into tMx
         put tMagY[tM] into tMy
         put tMagRange[tM] into tRange
         put tMx - tPx into tdx
         put tMy - tPy into tdy
         put sqrt(tdx * tdx + tdy * tdy) into tDist
         if tDist > tRange then next repeat
         if tDist < kMagnetMinDist then put kMagnetMinDist into tDist
         put tMagPol[tM] * tMagForce[tM] * (1 - tDist / tRange) into tPull
         put tPull * tdx / tDist into tFx
         put tPull * tdy / tDist into tFy
         b2kForce tP, tFx, tFy
      end repeat
   end repeat
end applyFieldForces

-- Bombs: light the fuse on Run for any armed for it, then tick all fuses down.
on armFuses
   local tB
   repeat for each line tB in gKindList["bomb"]
      if tB is not empty and the uFuseOnRun of tB is true then set the uFuse of tB to numOr(the uFuseLen of tB, kBombFuseFrames)
   end repeat
end armFuses

on updateBombs
   local tB, tFuse, tBlow
   put empty into tBlow
   repeat for each line tB in gKindList["bomb"]
      if tB is empty then next repeat
      put the uFuse of tB into tFuse
      if tFuse is empty or tFuse <= 0 then next repeat
      subtract 1 from tFuse
      set the uFuse of tB to tFuse
      if tFuse < 28 then
         try
            if (tFuse mod 6) < 3 then set the backgroundColor of tB to "245,80,55"
            else set the backgroundColor of tB to "150,40,40"
         end try
      end if
      if tFuse <= 0 then put tB & cr after tBlow
   end repeat
   repeat for each line tB in tBlow
      detonateBomb tB
   end repeat
end updateBombs

on detonateBomb pBomb
   if pBomb is empty then exit detonateBomb
   if pBomb is not among the lines of gParts then exit detonateBomb   -- already gone
   local tLx, tLy, tRad, tPow
   put item 1 of the loc of pBomb into tLx
   put item 2 of the loc of pBomb into tLy
   put the uBlastRadius of pBomb into tRad
   if tRad is empty then put kBombRadius into tRad
   put the uBlastPower of pBomb into tPow
   if tPow is empty then put kBombPower into tPow
   if the uSoftBlast of pBomb is true then b2kExplodeLegacy tLx, tLy, tRad, tPow   -- old velocity-based feel
   else b2kExplode tLx, tLy, tRad, tPow                                             -- shape-aware native blast
   spawnRing tLx, tLy
   popBalloonsNear tLx, tLy, tRad
   if the uDestroys of pBomb is true then demolishNear tLx, tLy, tRad              -- demolition bomb: vaporise what it reaches
   deletePart pBomb
end detonateBomb

-- Any balloon caught in a blast pops (a little ring, then it is removed).
on popBalloonsNear pX, pY, pRadius
   local tBalloon, tBx, tBy, tdx, tdy, tPop, tR2
   put pRadius * pRadius into tR2
   put empty into tPop
   repeat for each line tBalloon in gKindList["balloon"]
      if tBalloon is empty then next repeat
      put item 1 of the loc of tBalloon into tBx
      put item 2 of the loc of tBalloon into tBy
      put tBx - pX into tdx
      put tBy - pY into tdy
      if tdx * tdx + tdy * tdy <= tR2 then put tBalloon & cr after tPop
   end repeat
   repeat for each line tBalloon in tPop
      spawnRing (item 1 of the loc of tBalloon), (item 2 of the loc of tBalloon)
      deletePart tBalloon
   end repeat
end popBalloonsNear

-- Destroy a part with a little poof of debris (a ring puff), then remove it and
-- everything attached (joints, wires). The destruction primitive shared by the
-- demolition bomb and the cutting laser.
on destroyPart pCtrl
   if pCtrl is empty then exit destroyPart
   if pCtrl is not among the lines of gParts then exit destroyPart
   set the itemDelimiter to comma
   spawnRing (item 1 of the loc of pCtrl), (item 2 of the loc of pCtrl)
   deletePart pCtrl
end destroyPart

-- Demolition blast: remove every dynamic, non-bomb part inside the radius (the
-- bomb's impulse has already shoved everything; this vaporises what it can reach).
on demolishNear pX, pY, pRadius
   local tP, tList
   put empty into tList
   set the itemDelimiter to comma
   repeat for each line tP in b2kOverlapCircle(pX, pY, pRadius)
      if tP is empty or tP is not among the lines of gParts then next repeat
      if the uKind of tP is "bomb" then next repeat          -- don't chain-vaporise other bombs
      if kindIsDynamic(the uKind of tP) then put tP & cr after tList
   end repeat
   repeat for each line tP in tList
      destroyPart tP
   end repeat
end demolishNear

-- An expanding shock ring (purely decorative), ported from the showcase demo.
on spawnRing pX, pY
   add 1 to gRingN
   put pX into gRingX[gRingN]
   put pY into gRingY[gRingN]
   put 0 into gRingF[gRingN]
   create graphic ("cb_ring_" & gRingN)
   set the layerMode of graphic ("cb_ring_" & gRingN) to "dynamic"   -- expands every frame
   set the style of graphic ("cb_ring_" & gRingN) to "oval"
   set the filled of graphic ("cb_ring_" & gRingN) to false
   set the lineSize of graphic ("cb_ring_" & gRingN) to 3
   set the foregroundColor of graphic ("cb_ring_" & gRingN) to "255,170,70"
end spawnRing

on updateRings
   local tI, tName, tFrame, tRad, tLive
   if gRingN < 1 then exit updateRings
   put 0 into tLive
   repeat with tI = 1 to gRingN
      if gRingF[tI] is empty then next repeat
      put "cb_ring_" & tI into tName
      put gRingF[tI] + 1 into tFrame
      put tFrame into gRingF[tI]
      if tFrame > 16 then
         if there is a graphic tName then delete graphic tName
         put empty into gRingF[tI]
         next repeat
      end if
      put tFrame * 13 into tRad
      if there is a graphic tName then
         set the rect of graphic tName to (gRingX[tI] - tRad), (gRingY[tI] - tRad), (gRingX[tI] + tRad), (gRingY[tI] + tRad)
         set the lineSize of graphic tName to max(1, 5 - (tFrame div 4))
      end if
      add 1 to tLive
   end repeat
   if tLive is 0 then put 0 into gRingN   -- every ring has expired: reset so the early-out fires again
end updateRings

-- =====================================================================
-- Pressure plates: count resting bodies; on first press, fire the signal.
-- =====================================================================
on plateTouch pPlate, pOther, pDelta
   if pPlate is empty or pOther is empty then exit plateTouch
   if the uKind of pPlate is not "plate" then exit plateTouch
   if b2kBodyType(pOther) is not "dynamic" then exit plateTouch
   local tLoad
   put gPlateLoad[pPlate] + pDelta into tLoad
   if tLoad < 0 then put 0 into tLoad
   put tLoad into gPlateLoad[pPlate]
   if tLoad >= 1 and gPlateState[pPlate] is "up" then platePressed pPlate
   else if tLoad <= 0 and gPlateState[pPlate] is "down" then plateReleased pPlate
end plateTouch

on platePressed pPlate
   put "down" into gPlateState[pPlate]
   try
      set the backgroundColor of pPlate to "120,230,140"
   end try
   put "A pressure plate fired its signal!" into gStatus
   fireEmitter pPlate
   updateHud
end platePressed

on plateReleased pPlate
   put "up" into gPlateState[pPlate]
   try
      set the backgroundColor of pPlate to "150,160,180"
   end try
end plateReleased

-- The plate's signal: arm every bomb (it detonates next frame, safely outside
-- the contact callback) and flip all motors between running and stopped.
on triggerSignal
   local tB
   repeat for each line tB in gKindList["bomb"]
      if tB is not empty then set the uFuse of tB to 1
   end repeat
   toggleAllMotors
end triggerSignal

-- =====================================================================
-- Signal wiring: the Link tool connects a trigger (pressure plate / sensor)
-- to a target (a bomb). A trigger fires ONLY its wired targets; an unwired
-- trigger keeps the old "fire everything" behaviour so it still does something.
-- =====================================================================
function isEmitter pCtrl
   if pCtrl is empty then return false
   -- triggers start signal wires; a goal zone starts a "this object must reach me" wire
   return (the uKind of pCtrl is "plate") or (the uKind of pCtrl is "sensor") or (the uKind of pCtrl is "goal")
end isEmitter

function isReceiver pCtrl
   if pCtrl is empty then return false
   return kindIsDynamic(the uKind of pCtrl)    -- bombs, thrusters, and any movable part can be a target
end isReceiver

function nameOf pCtrl
   if pCtrl is empty then return "?"
   if the uPartName of pCtrl is not empty then return the uPartName of pCtrl
   return niceName(the uKind of pCtrl)
end nameOf

-- A click with the Link tool: first pick a trigger, then pick its target.
on handleLinkClick pHit
   if pHit is empty then
      put empty into gWireSrc
      put "Link: click a trigger (a pressure plate or a sensor) to start a wire." into gStatus
      renderBuild
      updateHud
      exit handleLinkClick
   end if
   if gWireSrc is empty then
      if not isEmitter(pHit) then
         put "Wires start at a trigger (plate/sensor) or a goal zone. Click one." into gStatus
         updateHud
         exit handleLinkClick
      end if
      put pHit into gWireSrc
      if the uKind of pHit is "goal" then put "Goal " & nameOf(pHit) & " - now click the object that must reach it." into gStatus
      else put "Wiring from " & nameOf(pHit) & " - now click a part to set off." into gStatus
   else
      if pHit is gWireSrc then
         put empty into gWireSrc
         put "Wire cancelled." into gStatus
      else if not isReceiver(pHit) then
         put "Target a movable part." into gStatus
      else
         addWire gWireSrc, pHit
         if the uKind of gWireSrc is "goal" then put "Goal " & nameOf(gWireSrc) & " now needs " & nameOf(pHit) & "." into gStatus
         else put "Wired " & nameOf(gWireSrc) & " to " & nameOf(pHit) & "." into gStatus
         put empty into gWireSrc
      end if
   end if
   renderBuild
   updateHud
end handleLinkClick

-- Record a wire (deduped). Edges are "srcCtrl<tab>tgtCtrl" long ids.
on addWire pSrc, pTgt
   if pSrc is empty or pTgt is empty then exit addWire
   local tEdge
   put pSrc & tab & pTgt into tEdge
   if tEdge is among the lines of gWires then exit addWire
   put tEdge & cr after gWires
   if the last char of gWires is return then delete the last char of gWires
end addWire

-- Drop every wire touching a part (called when the part is deleted).
on removeWiresFor pCtrl
   if gWires is empty then exit removeWiresFor
   local tEdge, tKept
   set the itemDelimiter to tab
   put empty into tKept
   repeat for each line tEdge in gWires
      if item 1 of tEdge is pCtrl or item 2 of tEdge is pCtrl then next repeat
      put tEdge & cr after tKept
   end repeat
   if the last char of tKept is return then delete the last char of tKept
   put tKept into gWires
end removeWiresFor

-- A trigger fired: set off its wired targets, or - if it has none - fall back to
-- the legacy global signal so an unwired plate/sensor still does something.
on fireEmitter pEmitter
   local tEdge, tTgt, tFired
   put false into tFired
   set the itemDelimiter to tab
   repeat for each line tEdge in gWires
      if item 1 of tEdge is pEmitter then
         put item 2 of tEdge into tTgt
         if tTgt is not empty and tTgt is among the lines of gParts then
            fireTarget tTgt
            put true into tFired
         end if
      end if
   end repeat
   if not tFired then triggerSignal
end fireEmitter

-- Set off one wired target by kind: detonate a bomb, toggle a thruster, or give
-- any other movable part a kick.
on fireTarget pTgt
   switch the uKind of pTgt
      case "bomb"
         set the uFuse of pTgt to 1          -- detonate next frame, safely outside the contact callback
         break
      case "thruster"
         set the uThrustArmed of pTgt to (the uThrustArmed of pTgt is "false")   -- toggle on/off
         break
      default
         b2kImpulse pTgt, 0, -360            -- a trigger pops any other part upward
   end switch
end fireTarget

-- Redraw the signal wires as amber connector lines between parts (build mode).
on drawWires
   local tEdge, tSrc, tTgt, tN, tName, tx0, ty0, tx1, ty1
   put 0 into tN
   repeat for each line tEdge in gWires
      set the itemDelimiter to tab
      put item 1 of tEdge into tSrc
      put item 2 of tEdge into tTgt
      if tSrc is empty or tTgt is empty then next repeat
      if tSrc is not among the lines of gParts or tTgt is not among the lines of gParts then next repeat
      set the itemDelimiter to comma
      put item 1 of the loc of tSrc into tx0
      put item 2 of the loc of tSrc into ty0
      put item 1 of the loc of tTgt into tx1
      put item 2 of the loc of tTgt into ty1
      add 1 to tN
      put "cb_wire_" & tN into tName
      -- Reuse the marker if it already exists and only restyle on creation:
      -- renderBuild calls this constantly, and recreating the graphics each
      -- time both churns the compositor and would re-trigger its nudge.
      if there is no graphic tName then
         create graphic tName
         set the layerMode of graphic tName to "dynamic"   -- endpoints move with their parts
         set the style of graphic tName to "line"
         set the lineSize of graphic tName to 2
         set the foregroundColor of graphic tName to "232,200,72"
      end if
      set the points of graphic tName to round(tx0) & "," & round(ty0) & cr & round(tx1) & "," & round(ty1)
   end repeat
   repeat forever                            -- drop leftover markers past the live count
      add 1 to tN
      if there is no graphic ("cb_wire_" & tN) then exit repeat
      delete graphic ("cb_wire_" & tN)
   end repeat
end drawWires

-- =====================================================================
-- Play mode + goals: press Play, get a movable part into every goal zone to
-- solve the puzzle. Build everything we have into actual puzzles.
-- =====================================================================
-- Each frame (Run): mark any goal a movable part is sitting in; win when all are.
on checkGoals
   if gGameWon then exit checkGoals
   if gKindList["goal"] is empty then exit checkGoals
   local tGoal, tTotal, tReached, tP, tGl, tGt, tGr, tGb, tCx, tCy, tpx, tpy, tIn, tReq, tCheckMember
   put 0 into tTotal
   put 0 into tReached
   repeat for each line tGoal in gKindList["goal"]
      if tGoal is empty then next repeat
      add 1 to tTotal
      if the uGoalReached of tGoal is true then
         add 1 to tReached
         next repeat
      end if
      -- the parts that satisfy this goal: its wired payload(s), or any movable part
      put goalTargets(tGoal) into tReq
      put true into tCheckMember
      if tReq is empty then
         put dynamicParts() into tReq
         put false into tCheckMember          -- dynamicParts is already live/valid; skip O(n) membership checks below
      end if
      set the itemDelimiter to comma
      put item 1 of the loc of tGoal into tCx
      put item 2 of the loc of tGoal into tCy
      put tCx - (the width of tGoal) / 2 into tGl
      put tCx + (the width of tGoal) / 2 into tGr
      put tCy - (the height of tGoal) / 2 into tGt
      put tCy + (the height of tGoal) / 2 into tGb
      put false into tIn
      repeat for each line tP in tReq
         if tP is empty then next repeat
         if tCheckMember then
            if tP is not among the lines of gParts then next repeat
            if b2kBodyType(tP) is not "dynamic" then next repeat
         end if
         put item 1 of the loc of tP into tpx
         put item 2 of the loc of tP into tpy
         if tpx >= tGl and tpx <= tGr and tpy >= tGt and tpy <= tGb then
            put true into tIn
            exit repeat
         end if
      end repeat
      if tIn then
         set the uGoalReached of tGoal to true
         set the backgroundColor of tGoal to "150,245,175"   -- lit when satisfied
         add 1 to tReached
      end if
   end repeat
   if tTotal > 0 and tReached >= tTotal then winGame
end checkGoals

-- The payload parts a goal requires (wired from the goal with the Link tool);
-- empty means "any movable part".
function goalTargets pGoal
   local tEdge, tList
   set the itemDelimiter to tab
   put empty into tList
   repeat for each line tEdge in gWires
      if item 1 of tEdge is pGoal then put (item 2 of tEdge) & cr after tList
   end repeat
   return tList
end goalTargets

on winGame
   put true into gGameWon
   if gPlaying then
      if there is a field "ui_winsub" then put "Solved in " & playElapsed() & " seconds." into field "ui_winsub"
      showWin
   else
      put "Goal reached! (Press Play to run it as a puzzle.)" into gStatus
   end if
   updateHud
end winGame

-- Reset every goal zone to unsolved (called when a Run/Play starts).
on resetGoals
   put false into gGameWon
   local tGoal
   repeat for each line tGoal in gKindList["goal"]
      if tGoal is empty then next repeat
      set the uGoalReached of tGoal to false
      set the backgroundColor of tGoal to "92,210,120"
   end repeat
end resetGoals

-- Enter Play mode: run the sim, watch the goals, and clear the editor away.
on startPlay
   if gKindList["goal"] is empty then
      put "Add a Goal Zone first (SPECIAL palette), then press Play." into gStatus
      updateHud
      exit startPlay
   end if
   if gMode is not "run" then toggleMode
   put true into gPlaying
   put the milliseconds into gPlayStartMs
   resetGoals
   setPlayChrome true
   highlightActions                   -- recolour the Play button to amber 'Stop'
   put "PLAY - get a movable part into the goal zone." into gStatus
   updateHud
end startPlay

-- Replay the puzzle from its starting layout.
on playAgain
   hideWin
   resetMachine        -- restore the pre-Play build (also clears the Play chrome)
   startPlay           -- and run it fresh
end playAgain

-- Elapsed Play time in seconds, one decimal.
function playElapsed
   if gPlayStartMs is empty then return "0.0"
   return format("%.1f", (the milliseconds - gPlayStartMs) / 1000)
end playElapsed

-- Leave Play mode: stop the sim, restore the editor.
on stopPlay
   put false into gPlaying
   hideWin
   setPlayChrome false
   if gMode is "run" then toggleMode
   resetGoals                        -- clear the lit/solved colouring
   highlightActions                  -- recolour the Play button back to blue 'Play'
   put "Back to building." into gStatus
   updateHud
end stopPlay

-- Show/clear the Play scrims (over the palette + inspector) and the play banner.
-- The arena stays live so you can fling and nudge parts to solve the puzzle.
on setPlayChrome pOn
   local tWide, tHigh
   put the width of this card into tWide
   put the height of this card into tHigh
   -- always tear down first, so it's idempotent (no duplicate scrims)
   deleteByPrefix "ui_playscrim"
   if there is a graphic "ui_playbanner" then delete graphic "ui_playbanner"
   if there is a field "ui_playbannerlbl" then delete field "ui_playbannerlbl"
   if not pOn then exit setPlayChrome
   makeBar "ui_playscrimL", 0, kTopBarH + kAccentH, kPaletteW, tHigh - kStatusH, "16,18,24"
   set the blendLevel of graphic "ui_playscrimL" to 78
   makeBar "ui_playscrimR", tWide - kInspectorW, kTopBarH + kAccentH, tWide, tHigh - kStatusH, "16,18,24"
   set the blendLevel of graphic "ui_playscrimR" to 78
   makeBar "ui_playbanner", kPaletteW, kTopBarH + kAccentH, tWide - kInspectorW, kTopBarH + kAccentH + 26, "40,120,72"
   makeLabel "ui_playbannerlbl", kPaletteW + 12, kTopBarH + kAccentH + 4, tWide - kInspectorW - 12, kTopBarH + kAccentH + 24, "> PLAY - solve the puzzle", 12, "236,255,240", true
end setPlayChrome

-- The "Solved!" overlay, built once with the chrome and shown on a win.
on buildPlayOverlay
   local tWide, tHigh, tW, tH, tL, tT
   put the width of this card into tWide
   put the height of this card into tHigh
   put 420 into tW
   put 184 into tH
   put (tWide - tW) div 2 into tL
   put (tHigh - tH) div 2 into tT
   makeBar "ui_winscrim", 0, 0, tWide, tHigh, "10,11,15"
   set the blendLevel of graphic "ui_winscrim" to 50
   set the uWinMenu of graphic "ui_winscrim" to true
   makeBar "ui_winbg", tL, tT, tL + tW, tT + tH, "40,120,72"
   set the uWinMenu of graphic "ui_winbg" to true
   makeLabel "ui_wintitle", tL, tT + 28, tL + tW, tT + 68, "*  Solved!", 26, "236,255,240", true
   set the textAlign of field "ui_wintitle" to center
   set the uWinMenu of field "ui_wintitle" to true
   makeLabel "ui_winsub", tL, tT + 74, tL + tW, tT + 98, "You got a part into every goal zone.", 12, "210,240,220", false
   set the textAlign of field "ui_winsub" to center
   set the uWinMenu of field "ui_winsub" to true
   makeAction "winagain", "Play Again", tL + 18, tT + tH - 48, 124, 30
   set the uWinMenu of button "ui_act_winagain" to true
   makeAction "winkeep", "Keep Playing", tL + 148, tT + tH - 48, 124, 30
   set the uWinMenu of button "ui_act_winkeep" to true
   makeAction "winedit", "Edit", tL + 278, tT + tH - 48, 124, 30
   set the uWinMenu of button "ui_act_winedit" to true
   setWinVisible false
end buildPlayOverlay

on showWin
   setWinVisible true
end showWin

on hideWin
   setWinVisible false
end hideWin

on setWinVisible pFlag
   local tI, tCtrl, tList
   put empty into tList
   repeat with tI = 1 to the number of controls of this card
      put the long id of control tI of this card into tCtrl
      if the uWinMenu of tCtrl is true then put tCtrl & cr after tList
   end repeat
   repeat for each line tCtrl in tList
      set the visible of tCtrl to pFlag
      if pFlag then set the layer of tCtrl to top
   end repeat
end setWinVisible

-- ===================================================================
-- Image library popup: import images (with a collision shape) and click one
-- to drop a fresh instance. Static frame built once; the rows are rebuilt to
-- match gAssets each time it opens.
-- ===================================================================
on buildImagePanel
   local tWide, tHigh, tW, tH, tL, tT
   put the width of this card into tWide
   put the height of this card into tHigh
   put 470 into tW
   put 440 into tH
   put (tWide - tW) div 2 into tL
   put (tHigh - tH) div 2 into tT
   makeBar "ui_imgscrim", 0, 0, tWide, tHigh, "10,11,15"
   set the blendLevel of graphic "ui_imgscrim" to 60
   set the uImgMenu of graphic "ui_imgscrim" to true
   makeBar "ui_imgbg", tL, tT, tL + tW, tT + tH, "34,38,48"
   set the uImgMenu of graphic "ui_imgbg" to true
   makeLabel "ui_img_title", tL + 18, tT + 14, tL + tW - 150, tT + 38, "Image Library", 15, "236,238,245", true
   set the uImgMenu of field "ui_img_title" to true
   makeAction "imgimport", "Import New...", tL + tW - 142, tT + 12, 124, 28
   set the uImgMenu of button "ui_act_imgimport" to true
   makeField "ui_img_empty", tL + 18, tT + 52, tL + tW - 18, tT + 96, 11, "168,172,184"
   set the uImgMenu of field "ui_img_empty" to true
   makeAction "imgclose", "Close", tL + tW - 92, tT + tH - 38, 76, 26
   set the uImgMenu of button "ui_act_imgclose" to true
   setImageVisible false
end buildImagePanel

on openImagePanel
   refreshImagePanel
end openImagePanel

on hideImagePanel
   setImageVisible false
end hideImagePanel

-- Rebuild one row per library image (a place button + a remove button), then show.
on refreshImagePanel
   if there is no graphic "ui_imgbg" then exit refreshImagePanel
   deleteByPrefix "ui_act_asset_"
   deleteByPrefix "ui_act_imgremove_"
   local tBg, tL, tW, tT, tN, tI, tRec, tRowY, tName, tShape
   set the itemDelimiter to comma
   put the rect of graphic "ui_imgbg" into tBg
   put item 1 of tBg into tL
   put item 3 of tBg - item 1 of tBg into tW
   put item 2 of tBg into tT
   put the number of lines of gAssets into tN
   if there is a field "ui_img_empty" then
      if tN is 0 then put "Your library is empty. Click 'Import New...' to add an image; it stays here for reuse, and an image collides as its shape." into field "ui_img_empty"
      else if tN > 9 then put "Showing the first 9 of " & tN & " images." into field "ui_img_empty"
      else put empty into field "ui_img_empty"
      set the visible of field "ui_img_empty" to (the text of field "ui_img_empty" is not empty)
   end if
   set the itemDelimiter to tab
   repeat with tI = 1 to min(tN, 9)
      put line tI of gAssets into tRec
      put item 3 of tRec into tName
      put item 2 of tRec into tShape
      put tT + 96 + (tI - 1) * 34 into tRowY
      makeAction ("asset_" & tI), (tName & "   (" & tShape & ")"), tL + 18, tRowY, tW - 84, 28
      set the uImgMenu of button ("ui_act_asset_" & tI) to true
      makeAction ("imgremove_" & tI), "x", tL + tW - 56, tRowY, 38, 28
      set the uImgMenu of button ("ui_act_imgremove_" & tI) to true
   end repeat
   setImageVisible true
end refreshImagePanel

-- Place an instance of a library image at the top of the stage, then select it.
on placeAssetFromPanel pIndex
   hideImagePanel
   local tNew
   put placeAssetInstance(pIndex, (gArenaL + gArenaR) div 2, gArenaT + 90) into tNew
   if tNew is empty then
      put "Could not place that image - its file may have moved." into gStatus
      updateHud
      exit placeAssetFromPanel
   end if
   renderBuild
   put "drag" into gTool
   selectPart tNew
   highlightAll
   put "Placed " & nameOf(tNew) & " - drag it where you want." into gStatus
   updateHud
end placeAssetFromPanel

on setImageVisible pFlag
   local tI, tCtrl, tList
   if pFlag then enterModalView
   else exitModalView
   put empty into tList
   repeat with tI = 1 to the number of controls of this card
      put the long id of control tI of this card into tCtrl
      if the uImgMenu of tCtrl is true then put tCtrl & cr after tList
   end repeat
   repeat for each line tCtrl in tList
      set the visible of tCtrl to pFlag
      if pFlag then set the layer of tCtrl to top
   end repeat
end setImageVisible

on toggleAllMotors
   local tI, tSpeed
   put not gMotorsRunning into gMotorsRunning
   if gJN < 1 then exit toggleAllMotors
   repeat with tI = 1 to gJN
      if gJKind[tI] is empty then next repeat
      if gJMotor[tI] is empty or gJMotor[tI] is 0 then next repeat
      if gMotorsRunning then put gJMotor[tI] into tSpeed
      else put 0 into tSpeed
      if gJKind[tI] is "hinge" then b2kMotor gJHandle[tI], tSpeed, kHingeTorque
      else if gJKind[tI] is "wheel" then b2kWheelMotor gJHandle[tI], tSpeed, kWheelTorque
   end repeat
end toggleAllMotors

-- Push every joint's designed motor state (from its marker) onto the live joint.
-- Joints persist across Build<->Run, and a pressure plate can flip motors off
-- mid-run via toggleAllMotors, so each Run re-applies the design - otherwise a
-- plate that killed a motor would leave it dead after the next Build/Run.
on armMotors
   local tI
   if gJN < 1 then exit armMotors
   repeat with tI = 1 to gJN
      if gJKind[tI] is empty then next repeat   -- removed joint: marker is gone
      applyJointMotor tI
   end repeat
end armMotors

-- A bomb hit hard enough arms a one-frame fuse (so it blows outside the callback).
on bombImpactCheck pCtrl
   if pCtrl is empty then exit bombImpactCheck
   if the uKind of pCtrl is not "bomb" then exit bombImpactCheck
   if the uFuse of pCtrl is not empty and the uFuse of pCtrl > 0 then exit bombImpactCheck
   if b2kSpeed(pCtrl) >= kBombImpactSpeed then set the uFuse of pCtrl to 1
end bombImpactCheck

-- =====================================================================
-- Scene-state reset (called on start, clear and teardown)
-- =====================================================================
on resetSceneState
   put empty into gKindList
   put empty into gPlateLoad
   put empty into gPlateState
   put empty into gSensorCount
   put empty into gDynParts
   put true into gDynDirty
   put 0 into gRingN
   put empty into gRingX
   put empty into gRingY
   put empty into gRingF
   put empty into gNameCount
   put empty into gWires
   put empty into gWireSrc
   deleteByPrefix "cb_ring_"
   deleteByPrefix "cb_wire_"
   deleteByPrefix "cb_flame_"        -- thruster exhaust is a transient run-only effect
end resetSceneState

on deleteByPrefix pPrefix
   local tI, tName
   repeat with tI = the number of controls of this card down to 1
      put the short name of control tI of this card into tName
      if offset(pPrefix, tName) is 1 then delete control tI of this card
   end repeat
end deleteByPrefix

-- =====================================================================
-- Inspector + selection (plain-language help, live property tweaks)
-- =====================================================================
on selectPart pCtrl
   if pCtrl is empty then exit selectPart
   deselectPart
   deselectJoint
   put pCtrl into gSelPart
   try
      set the uSelFg of pCtrl to the foregroundColor of pCtrl
      set the uSelLine of pCtrl to the lineSize of pCtrl
      set the foregroundColor of pCtrl to "255,255,255"
      set the lineSize of pCtrl to kSelectLine
   end try
   showPartInspector pCtrl
end selectPart

on deselectPart
   if gSelPart is empty then exit deselectPart
   try
      set the foregroundColor of gSelPart to the uSelFg of gSelPart
      set the lineSize of gSelPart to the uSelLine of gSelPart
   end try
   put empty into gSelPart
   clearPropRows
end deselectPart

-- Show the active tool's plain-language help when nothing is selected.
on showInspectorForTool
   local tId
   if gJointTool is not empty then put gJointTool into tId
   else put gTool into tId
   setInspector niceName(tId), (line 2 of toolHelp(tId))
   clearPropRows
end showInspectorForTool

-- Preview a hovered tool's help without disturbing the current selection.
on hoverHelp pId
   setInspector niceName(pId), (line 2 of toolHelp(pId))
end hoverHelp

on restoreInspector
   if gSelJoint is not empty then showJointInspector gSelJoint
   else if gSelPart is not empty then showPartInspector gSelPart
   else showInspectorForTool
end restoreInspector

on setInspector pTitle, pBody
   if there is a field "ui_insp_title" then put pTitle into field "ui_insp_title"
   if there is a field "ui_insp_body" then put pBody into field "ui_insp_body"
end setInspector

-- Rename the selected part. Names label wires and (later) puzzle goals.
on renamePart pCtrl
   if pCtrl is empty or pCtrl is not among the lines of gParts then
      put "Select a part first, then press Rename." into gStatus
      updateHud
      exit renamePart
   end if
   ask "Name this part:" with (the uPartName of pCtrl)
   if it is empty or the result is "Cancel" then exit renamePart
   local tNm
   put it into tNm
   replace tab with space in tNm          -- names are tab-delimited in saves
   replace return with space in tNm
   set the uPartName of pCtrl to tNm
   showPartInspector pCtrl                 -- refresh the title
   put "Renamed to " & quote & tNm & quote & "." into gStatus
   updateHud
end renamePart

-- Show a selected part's name, what it does, and the values you can change.
on showPartInspector pCtrl
   if pCtrl is empty then exit showPartInspector
   local tKind, tKey, tRow, tAvail
   put the uKind of pCtrl into tKind
   local tNm, tTitle
   put the uPartName of pCtrl into tNm
   if tNm is empty then put niceName(tKind) into tNm
   put "Selected: " & tNm into tTitle
   -- the title line fits ~18 bold chars; for long names the name matters more
   if the number of chars of tTitle > 18 then put tNm into tTitle
   setInspector tTitle, (line 2 of toolHelp(tKind))
   clearPropRows
   put partTabsForInspector(tKind) into tAvail   -- mode-aware: simple hides expert-only tabs
   if tAvail is empty then
      setSettingsHint "This part has no adjustable settings."
      exit showPartInspector
   end if
   set the itemDelimiter to comma
   if gInspTab is not among the items of tAvail then put item 1 of tAvail into gInspTab
   refreshInspTabs tAvail
   put 0 into tRow
   repeat for each item tKey in partPropsForInspector(tKind)   -- mode-aware row list
      if propGroup(tKey) is not gInspTab then next repeat
      add 1 to tRow
      if tRow > kPropRows then exit repeat
      showPropRow tRow, propLabel(pCtrl, tKey), tKey
   end repeat
   if tRow > 0 then
      if gInspectorMode is "simple" and advancedPropCount(tKind, gInspTab) > 0 then
         setSettingsHint "Simple mode hides some expert settings on this tab - switch to Advanced (top of this block) to show them all.", tRow
      else
         setSettingsHint empty           -- rows are showing; hide the prompt
      end if
   else
      setSettingsHint "Nothing to adjust on this tab."
   end if
   -- A live, plain-language preview for the special kinds (parked below the rows).
   if tKind is "bomb" then setSettingsHint blastPreviewText(pCtrl), tRow
   else if tKind is "laser" then setSettingsHint laserPreviewText(pCtrl), tRow
   else if tKind is "fan" then setSettingsHint fanPreviewText(pCtrl), tRow
   else if tKind is "magnet" then setSettingsHint magnetPreviewText(pCtrl), tRow
   else if tKind is "goal" then setSettingsHint goalPreviewText(pCtrl), tRow
end showPartInspector

-- A live preview of a bomb's reach: how many parts currently sit inside its blast
-- radius, found with the Kit's region query b2kOverlapCircle. Refreshes whenever
-- the bomb is selected or its radius is nudged.
function blastPreviewText pBomb
   local tCx, tCy, tR, tP, tN, tPlural
   set the itemDelimiter to comma
   put item 1 of the loc of pBomb into tCx
   put item 2 of the loc of pBomb into tCy
   put numOr(the uBlastRadius of pBomb, kBombRadius) into tR
   put 0 into tN
   repeat for each line tP in b2kOverlapCircle(tCx, tCy, tR)
      if tP is not empty and tP is not pBomb then add 1 to tN
   end repeat
   if tN is 1 then put "part" into tPlural
   else put "parts" into tPlural
   return "Blast radius " & tR & " px - reaches " & tN && tPlural & " right now."
end blastPreviewText

-- Live, plain-language preview lines for the other special parts, shown in the
-- inspector hint area so a setting's effect is obvious before you press Run.
function laserPreviewText pLaser
   if the uLaserCut of pLaser is true then return "Laser CUT mode: burns through dynamic parts after about " & format("%.1f", numOr(the uLaserBurn of pLaser, kLaserBurnDefault) / 60) & " s of contact (tougher parts take longer)."
   return "Laser is a sightline only. Toggle Cut to make it destroy dynamic parts after sustained exposure."
end laserPreviewText

function fanPreviewText pFan
   return "Fan pushes dynamic parts in its arrow zone. Direction " & dirName(the uFanDir of pFan) & ", strength " & numOr(the uFanForce of pFan, kFanForce) & "."
end fanPreviewText

function magnetPreviewText pMag
   return "Magnet " & magName(the uMagPolarity of pMag) & " parts within " & numOr(the uMagRange of pMag, kMagnetRange) & " px, at strength " & numOr(the uMagForce of pMag, kMagnetForce) & "."
end magnetPreviewText

function goalPreviewText pGoal
   local tReq
   put goalTargets(pGoal) into tReq
   if tReq is empty then return "Goal accepts any dynamic part. Link it to a part to make it a specific puzzle target."
   return "Goal requires " & (the number of lines of tReq) && "linked target(s) to reach this zone."
end goalPreviewText

-- =====================================================================
-- Inspector simple/advanced mode (PR #15 UX): simple hides expert-only rows so
-- newcomers see only everyday controls; advanced shows everything. Empty == simple.
-- =====================================================================
-- The keys treated as "expert" and hidden while the inspector is in simple mode.
function propIsAdvanced pKey
   set the itemDelimiter to comma
   return pKey is among the items of "lindamp,angdamp,bullet,sleep,active,filter,launchspeed,launchdir,spinrate,bodytype,sensor,layer"
end propIsAdvanced

-- A kind's property keys, filtered for the current inspector mode.
function partPropsForInspector pKind
   local tKey, tOut
   if gInspectorMode is "advanced" then return partProps(pKind)
   set the itemDelimiter to comma
   put empty into tOut
   repeat for each item tKey in partProps(pKind)
      if not propIsAdvanced(tKey) then put addItem(tOut, tKey) into tOut
   end repeat
   return tOut
end partPropsForInspector

-- How many expert-only keys a tab holds (drives the "settings hidden" hint).
function advancedPropCount pKind, pGroup
   local tKey, tN
   put 0 into tN
   set the itemDelimiter to comma
   repeat for each item tKey in partProps(pKind)
      if propGroup(tKey) is pGroup and propIsAdvanced(tKey) then add 1 to tN
   end repeat
   return tN
end advancedPropCount

-- The tabs with at least one VISIBLE setting in the current mode, so a tab made
-- empty by simple mode is hidden rather than shown blank.
function partTabsForInspector pKind
   local tKey, tHasShape, tHasPhys, tHasCollide, tHasSpec, tOut
   put false into tHasShape
   put false into tHasPhys
   put false into tHasCollide
   put false into tHasSpec
   set the itemDelimiter to comma
   repeat for each item tKey in partPropsForInspector(pKind)
      switch propGroup(tKey)
         case "shape"
            put true into tHasShape
            break
         case "physics"
            put true into tHasPhys
            break
         case "collide"
            put true into tHasCollide
            break
         case "special"
            put true into tHasSpec
            break
      end switch
   end repeat
   put empty into tOut
   if tHasShape then put "shape" into tOut
   if tHasPhys then put addItem(tOut, "physics") into tOut
   if tHasCollide then put addItem(tOut, "collide") into tOut
   if tHasSpec then put addItem(tOut, "special") into tOut
   return tOut
end partTabsForInspector

on toggleInspectorMode
   if gInspectorMode is "advanced" then put "simple" into gInspectorMode
   else put "advanced" into gInspectorMode
   refreshInspectorModeLabel
   if gSelPart is not empty then showPartInspector gSelPart
   else if gSelJoint is not empty then showJointInspector gSelJoint
   else showInspectorForTool
   if gInspectorMode is "advanced" then put "Inspector: all expert settings are now visible." into gStatus
   else put "Inspector: simple mode hides expert-only settings." into gStatus
   updateHud
end toggleInspectorMode

on refreshInspectorModeLabel
   if gInspectorMode is empty then put "simple" into gInspectorMode
   if there is a button "ui_act_inspmode" then
      if gInspectorMode is "advanced" then set the label of button "ui_act_inspmode" to "Advanced"
      else set the label of button "ui_act_inspmode" to "Simple"
      set the tooltip of button "ui_act_inspmode" to "Inspector detail: " & gInspectorMode & ". Click to toggle; simple hides expert-only settings."
   end if
end refreshInspectorModeLabel

-- =====================================================================
-- Per-property help: tooltips on each settings row + the type-in affordance.
-- =====================================================================
-- True for keys whose label can be clicked to type an exact value.
function propCanType pKey
   set the itemDelimiter to comma
   return pKey is among the items of kEntryKeys
end propCanType

-- Tooltip for a row's +/- button.
function propButtonHelp pKey, pInc
   local tWord
   if pInc then put "Increase" into tWord
   else put "Decrease" into tWord
   set the itemDelimiter to comma
   if pKey is among the items of "color,material,imgshape" then return "Cycle this setting with the +/- buttons."
   if pKey is among the items of "fixedrot,bullet,active,sensor,lasercut,bombfuse,bombsoft,bombdemo,magpol,thrustaim,bodytype,facing" then return "Toggle or cycle this setting with the +/- buttons."
   if propCanType(pKey) then return tWord & " this value. Click the label to type an exact number."
   return tWord & " this setting."
end propButtonHelp

-- Tooltip for a settings row's label: what the property does, in plain language.
function propHelp pKey
   switch pKey
      case "width"
      case "height"
      case "length"
      case "thickness"
      case "diameter"
      case "size"
      case "goalsize"
      case "fansize"
         return "Shape size in pixels. Click the label to type an exact value."
      case "angle"
      case "launchdir"
      case "thrustdir"
      case "fandir"
         return "Direction in degrees. 0 points right, 90 is up; values wrap at 360."
      case "facing"
         return "Which way the part faces. Cycle with the +/- buttons."
      case "color"
         return "Cycle the part colour. Colour is visual only."
      case "imgshape"
         return "Collision shape used for this image: box, ball or capsule."
      case "bounce"
         return "Restitution: higher values bounce more after a collision."
      case "density"
         return "Density sets mass. Heavier parts are harder to push or blast."
      case "friction"
         return "Surface grip. Higher friction resists sliding."
      case "gravity"
         return "Gravity multiplier. 1 is normal, 0 is weightless, negative floats up."
      case "fixedrot"
         return "Locks rotation so the part cannot spin."
      case "bodytype"
         return "Dynamic moves with physics; static stays fixed; kinematic is script-moved."
      case "lindamp"
         return "Linear damping slows movement, like air resistance."
      case "angdamp"
         return "Angular damping slows spinning."
      case "bullet"
         return "Continuous collision for fast parts that could tunnel through thin shapes."
      case "material"
         return "Preset bundle of grip, weight and bounciness."
      case "layer"
         return "Parts on the same non-zero layer pass through each other; layer 0 collides normally."
      case "sensor"
         return "Makes this part a non-solid trigger zone."
      case "filter"
         return "Open the collision-channel filter for advanced rules."
      case "active"
         return "Disabled parts stay visible but are taken out of the simulation."
      case "sleep"
         return "Speed below which a resting body sleeps to save CPU."
      case "launchspeed"
         return "Initial speed applied when Run or Play starts."
      case "spinrate"
         return "Initial spin when Run or Play starts, in degrees per second."
      case "toughness"
         return "Seconds of continuous laser contact this part survives before being cut."
      case "blastradius"
         return "Bomb blast reach in pixels."
      case "blastpower"
         return "Bomb blast impulse strength."
      case "bombfuse"
         return "Arm the fuse automatically when Run starts. Toggle with the +/- buttons."
      case "bombfuselen"
         return "Fuse time in seconds after the bomb is armed."
      case "bombsoft"
         return "Soft blast shoves parts without destroying them."
      case "bombdemo"
         return "Demolition blast can destroy destructible parts."
      case "fanforce"
         return "How hard the fan pushes parts in its zone."
      case "magpol"
         return "Attract or repel. Toggle with the +/- buttons."
      case "magforce"
         return "How strongly the magnet pulls or pushes parts."
      case "magrange"
         return "How far the magnet's pull reaches, in pixels."
      case "laserdir"
         return "Laser aim, in 45-degree steps. Cycle with the +/- buttons."
      case "lasercut"
         return "Toggle between a harmless sightline and a cutting beam."
      case "laserburn"
         return "Seconds of contact a cutting laser needs before it destroys a part."
      case "thrustpower"
         return "How hard the thruster pushes."
      case "thrustspin"
         return "Spin the thruster adds while firing, in degrees per second."
      case "thrustaim"
         return "Aim relative to the world, or to the part's own facing."
      default
         return "Adjust this setting with the +/- buttons."
   end switch
end propHelp

-- The ordered list of adjustable settings shown for each kind of part.
function partProps pKind
   switch pKind
      case "box"
         return "width,height,color,angle,bounce,density,friction,gravity,fixedrot,bodytype,lindamp,angdamp,bullet,material,layer,sensor,filter,active,sleep,launchspeed,launchdir,spinrate,toughness"
      case "image"
         return "width,height,imgshape,angle,bounce,density,friction,gravity,fixedrot,bodytype,lindamp,angdamp,bullet,material,layer,sensor,filter,active,sleep,launchspeed,launchdir,spinrate,toughness"
      case "ball"
         return "diameter,color,bounce,density,friction,gravity,fixedrot,bodytype,lindamp,angdamp,bullet,material,layer,sensor,filter,active,sleep,launchspeed,launchdir,spinrate,toughness"
      case "capsule"
         return "length,thickness,color,angle,bounce,density,friction,gravity,fixedrot,bodytype,lindamp,angdamp,bullet,material,layer,sensor,filter,active,sleep,launchspeed,launchdir,spinrate,toughness"
      case "poly"
         return "size,color,angle,bounce,density,friction,gravity,fixedrot,bodytype,lindamp,angdamp,bullet,material,layer,sensor,filter,active,sleep,launchspeed,launchdir,spinrate,toughness"
      case "balloon"
         return "diameter,color,bounce,density,friction,gravity,toughness"
      case "bomb"
         return "diameter,color,bounce,density,toughness,blastradius,blastpower,bombfuse,bombfuselen,bombsoft,bombdemo"
      case "plate"
         return "width,height,color,angle,friction"
      case "sensor"
         return "width,height,color"
      case "draw"
         return "color"
      case "anchor"
         return "width,height,color,bounce,friction"
      case "ramp"
         return "width,height,angle,facing,friction,color"
      case "platform"
      case "hill"
         return "width,height,angle,friction,color"
      case "fan"
         return "fandir,fanforce,fansize,color"
      case "magnet"
         return "magpol,magforce,magrange,color"
      case "laser"
         return "laserdir,lasercut,laserburn"
      case "goal"
         return "goalsize"
      case "thruster"
         return "width,height,color,angle,bounce,density,friction,gravity,fixedrot,bodytype,material,layer,toughness,thrustdir,thrustpower,thrustspin,thrustaim"
   end switch
   return empty
end partProps

-- The human-readable "Name: value" shown on a property row.
function propLabel pCtrl, pKey
   switch pKey
      case "size"
         return "Size: " & (the width of pCtrl) & " px"
      case "width"
         return "Width: " & numOr(the uW of pCtrl, the width of pCtrl) & " px"
      case "height"
         return "Height: " & numOr(the uH of pCtrl, the height of pCtrl) & " px"
      case "length"
         return "Length: " & numOr(the uW of pCtrl, the width of pCtrl) & " px"
      case "thickness"
         return "Thickness: " & numOr(the uH of pCtrl, the height of pCtrl) & " px"
      case "diameter"
         return "Diameter: " & numOr(the uW of pCtrl, the width of pCtrl) & " px"
      case "angle"
         if kindIsTerrain(the uKind of pCtrl) then return "Angle: " & numOr(the uAngle of pCtrl, 0) & " deg"
         return "Angle: " & round(b2kAngle(pCtrl)) & " deg"
      case "facing"
         if the uFlip of pCtrl is true then return "Facing: high on the left"
         return "Facing: high on the right"
      case "color"
         return "Colour (cycle with +/-)"
      case "bounce"
         return "Bounciness: " & bounceLabel(the uBounce of pCtrl)
      case "density"
         return "Weight: " & weightLabel(pCtrl)
      case "friction"
         return "Grip: " & frictionLabel(the uFriction of pCtrl)
      case "gravity"
         return "Gravity: " & gravityLabel(the uGravity of pCtrl)
      case "fixedrot"
         if the uFixedRot of pCtrl is true then return "Spin: locked"
         return "Spin: free to rotate"
      case "bodytype"
         if the uBodyType of pCtrl is "static" then return "Movement: fixed in place"
         if the uBodyType of pCtrl is "kinematic" then return "Movement: moving platform (kinematic)"
         return "Movement: free-moving"
      case "lindamp"
         return "Air drag (move): " & numOr(the uLinDamp of pCtrl, 0)
      case "angdamp"
         return "Air drag (spin): " & numOr(the uAngDamp of pCtrl, 0)
      case "bullet"
         return "Fast-collision: " & yesNo(the uBullet of pCtrl is true)
      case "material"
         return "Material: " & materialNameOf(pCtrl)
      case "layer"
         if numOr(the uLayer of pCtrl, 0) is 0 then return "Collision layer: 0 (hits everything)"
         return "Collision layer: " & (the uLayer of pCtrl) & " (same-layer parts pass through)"
      case "sleep"
         if numOr(the uSleep of pCtrl, 0) is 0 then return "Sleep: never (stays active)"
         return "Sleeps below: " & (the uSleep of pCtrl) & " px/s"
      case "imgshape"
         return "Collision shape: " & numOr(the uShape of pCtrl, "box")
      case "active"
         if the uActive of pCtrl is false then return "In simulation: no (disabled)"
         return "In simulation: yes"
      case "sensor"
         if the uSensor of pCtrl is true then return "Trigger zone (non-solid): yes"
         return "Trigger zone (non-solid): no"
      case "filter"
         return "Collision filter: " & filterSummary(pCtrl)
      case "launchspeed"
         return "Launch speed: " & numOr(the uLaunchSpeed of pCtrl, 0) & " px/s"
      case "launchdir"
         return "Launch angle: " & numOr(the uLaunchDir of pCtrl, 0) & " deg"
      case "spinrate"
         return "Launch spin: " & numOr(the uSpinRate of pCtrl, 0) & " deg/s"
      case "toughness"
         return "Toughness: " & format("%.1f", numOr(the uToughness of pCtrl, kToughnessDefault) / 60) & " s laser exposure"
      case "blastradius"
         return "Blast size: " & (the uBlastRadius of pCtrl)
      case "blastpower"
         return "Blast power: " & (the uBlastPower of pCtrl)
      case "bombfuse"
         return "Light fuse on Run: " & yesNo(the uFuseOnRun of pCtrl)
      case "bombfuselen"
         return "Fuse length: " & format("%.1f", numOr(the uFuseLen of pCtrl, kBombFuseFrames) / 60) & " s"
      case "bombsoft"
         if the uSoftBlast of pCtrl is true then return "Blast style: soft (legacy, size-blind)"
         return "Blast style: shape-aware (native)"
      case "bombdemo"
         if the uDestroys of pCtrl is true then return "On blast: demolish parts in range"
         return "On blast: push parts (keep them)"
      case "fandir"
         return "Direction: " & dirName(the uFanDir of pCtrl)
      case "fanforce"
         return "Strength: " & (the uFanForce of pCtrl)
      case "fansize"
         return "Zone size: " & sizeLabel(the uFanScale of pCtrl)
      case "magpol"
         return "Mode: " & magName(the uMagPolarity of pCtrl)
      case "magforce"
         return "Strength: " & (the uMagForce of pCtrl)
      case "magrange"
         return "Reach: " & (the uMagRange of pCtrl)
      case "laserdir"
         return "Beam angle: " & numOr(the uLaserDir of pCtrl, 0) & " deg"
      case "lasercut"
         if the uLaserCut of pCtrl is true then return "Mode: cutting (burns through parts)"
         return "Mode: sightline (harmless)"
      case "laserburn"
         return "Cut time: " & format("%.1f", numOr(the uLaserBurn of pCtrl, kLaserBurnDefault) / 60) & " s minimum"
      case "goalsize"
         return "Zone size: " & sizeLabel(numOr(the uGoalScale of pCtrl, 1))
      case "thrustdir"
         return "Thrust angle: " & numOr(the uThrustDir of pCtrl, 270) & " deg"
      case "thrustpower"
         return "Thrust power: " & numOr(the uThrustPower of pCtrl, 0)
      case "thrustspin"
         return "Thrust spin: " & numOr(the uThrustSpin of pCtrl, 0)
      case "thrustaim"
         if the uThrustAim of pCtrl is "body" then return "Aim: steers with the body"
         return "Aim: fixed direction"
   end switch
   return pKey
end propLabel

on clearPropRows
   local tI
   repeat with tI = 1 to kPropRows
      hidePropRow tI
   end repeat
   hideInspTabs
   setSettingsHint "Select a part on the stage to adjust its settings here."
end clearPropRows

on hidePropRow pRow
   if there is a field ("ui_prop_lbl_" & pRow) then set the visible of field ("ui_prop_lbl_" & pRow) to false
   if there is a button ("ui_act_prop_dec_" & pRow) then set the visible of button ("ui_act_prop_dec_" & pRow) to false
   if there is a button ("ui_act_prop_inc_" & pRow) then set the visible of button ("ui_act_prop_inc_" & pRow) to false
end hidePropRow

on showPropRow pRow, pLabel, pKey
   local tShownLabel
   -- Mark type-in rows with a pencil so users know the label is clickable, and
   -- hang plain-language help off every control via its tooltip.
   if propCanType(pKey) then put pLabel & "  ~" into tShownLabel
   else put pLabel into tShownLabel
   if there is a field ("ui_prop_lbl_" & pRow) then
      put tShownLabel into field ("ui_prop_lbl_" & pRow)
      set the tooltip of field ("ui_prop_lbl_" & pRow) to propHelp(pKey)
      set the uPropKey of field ("ui_prop_lbl_" & pRow) to pKey
      set the visible of field ("ui_prop_lbl_" & pRow) to true
   end if
   if there is a button ("ui_act_prop_dec_" & pRow) then
      set the tooltip of button ("ui_act_prop_dec_" & pRow) to propButtonHelp(pKey, false)
      set the uPropKey of button ("ui_act_prop_dec_" & pRow) to pKey
      set the visible of button ("ui_act_prop_dec_" & pRow) to true
   end if
   if there is a button ("ui_act_prop_inc_" & pRow) then
      set the tooltip of button ("ui_act_prop_inc_" & pRow) to propButtonHelp(pKey, true)
      set the uPropKey of button ("ui_act_prop_inc_" & pRow) to pKey
      set the visible of button ("ui_act_prop_inc_" & pRow) to true
   end if
end showPropRow

-- A +/- click on an inspector property row.
on adjustProp pId
   local tDir
   if char 6 to 8 of pId is "inc" then
      put 1 into tDir
   else
      put -1 into tDir
   end if
   if gSelJoint is not empty then
      adjustJointProp gSelJoint, (the uPropKey of the target), tDir
      showJointInspector gSelJoint
      exit adjustProp
   end if
   if gSelPart is empty then exit adjustProp
   adjustPartProp gSelPart, (the uPropKey of the target), tDir
   showPartInspector gSelPart
   if gMode is "build" then renderBuild
end adjustProp

on adjustPartProp pCtrl, pKey, pDir
   local tB, tD, tF, tNewDir, tMf, tMr, tFr, tG, tBr, tPow, tFs, tIdx, tPal, tCnt, tLd, tAd, tLs, tSr
   switch pKey
      case "size"
         if pDir > 0 then resizePart pCtrl, 1.15
         else resizePart pCtrl, 0.87
         break
      case "width"
         if kindIsTerrain(the uKind of pCtrl) then
            setPartDimension pCtrl, "w", numOr(the uW of pCtrl, 120) + pDir * kDimStep
         else
            setPartDimension pCtrl, "w", (the width of pCtrl) + pDir * kDimStep
         end if
         break
      case "height"
         if kindIsTerrain(the uKind of pCtrl) then
            setPartDimension pCtrl, "h", numOr(the uH of pCtrl, 26) + pDir * kDimStep
         else
            setPartDimension pCtrl, "h", (the height of pCtrl) + pDir * kDimStep
         end if
         break
      case "length"
         setPartDimension pCtrl, "w", (the width of pCtrl) + pDir * kDimStep
         break
      case "thickness"
         setPartDimension pCtrl, "h", (the height of pCtrl) + pDir * kDimStep
         break
      case "diameter"
         setPartDimension pCtrl, "d", (the width of pCtrl) + pDir * kDimStep
         break
      case "angle"
         if kindIsTerrain(the uKind of pCtrl) then
            setPartAngle pCtrl, numOr(the uAngle of pCtrl, 0) + pDir * 15
         else
            setPartAngle pCtrl, round(b2kAngle(pCtrl)) + pDir * 15
         end if
         break
      case "facing"
         set the uFlip of pCtrl to not (the uFlip of pCtrl is true)
         regenTerrain pCtrl
         break
      case "color"
         put partSwatches() into tPal
         put the number of lines of tPal into tCnt
         put swatchIndexOf(pCtrl, tPal) + pDir into tIdx
         if tIdx < 1 then put tCnt into tIdx
         if tIdx > tCnt then put 1 into tIdx
         set the backgroundColor of pCtrl to (line tIdx of tPal)
         set the uColor of pCtrl to (line tIdx of tPal)
         break
      case "bounce"
         put (the uBounce of pCtrl) + pDir * 0.15 into tB
         if tB < 0 then put 0 into tB
         if tB > 0.9 then put 0.9 into tB
         set the uBounce of pCtrl to tB
         b2kSetBounce pCtrl, tB
         break
      case "density"
         put the uDensity of pCtrl into tD
         if tD is empty then put 1 into tD
         put tD + pDir * 0.3 into tD
         if tD < 0.3 then put 0.3 into tD
         if tD > 3 then put 3 into tD
         set the uDensity of pCtrl to tD
         b2kSetDensity pCtrl, tD
         break
      case "friction"
         put the uFriction of pCtrl into tFr
         if tFr is empty then put 0.4 into tFr
         put tFr + pDir * 0.2 into tFr
         if tFr < 0 then put 0 into tFr
         if tFr > 2 then put 2 into tFr
         set the uFriction of pCtrl to tFr
         b2kSetFriction pCtrl, tFr
         break
      case "gravity"
         put the uGravity of pCtrl into tG
         if tG is empty then put 1 into tG
         put tG + pDir * 0.25 into tG
         if tG < -2 then put -2 into tG
         if tG > 3 then put 3 into tG
         set the uGravity of pCtrl to tG
         b2kSetGravityScale pCtrl, tG
         break
      case "fixedrot"
         set the uFixedRot of pCtrl to not (the uFixedRot of pCtrl is true)
         b2kSetFixedRotation pCtrl, (the uFixedRot of pCtrl is true)
         break
      case "bodytype"
         switch the uBodyType of pCtrl       -- cycle dynamic -> static -> kinematic
            case "static"
               set the uBodyType of pCtrl to "kinematic"
               break
            case "kinematic"
               set the uBodyType of pCtrl to "dynamic"
               break
            default
               set the uBodyType of pCtrl to "static"
         end switch
         b2kSetType pCtrl, (the uBodyType of pCtrl)
         put true into gDynDirty
         break
      case "lindamp"
         put the uLinDamp of pCtrl into tLd
         if tLd is empty then put 0 into tLd
         put tLd + pDir * 0.25 into tLd
         if tLd < 0 then put 0 into tLd
         if tLd > 5 then put 5 into tLd
         set the uLinDamp of pCtrl to tLd
         b2kSetDamping pCtrl, tLd, empty
         break
      case "angdamp"
         put the uAngDamp of pCtrl into tAd
         if tAd is empty then put 0 into tAd
         put tAd + pDir * 0.25 into tAd
         if tAd < 0 then put 0 into tAd
         if tAd > 5 then put 5 into tAd
         set the uAngDamp of pCtrl to tAd
         b2kSetDamping pCtrl, empty, tAd
         break
      case "bullet"
         set the uBullet of pCtrl to not (the uBullet of pCtrl is true)
         b2kSetBullet pCtrl, (the uBullet of pCtrl is true)
         break
      case "material"
         cycleMaterial pCtrl, pDir
         break
      case "layer"
         set the uLayer of pCtrl to clampRange(numOr(the uLayer of pCtrl, 0) + pDir, 0, 8)
         applyCollisionLayer pCtrl
         break
      case "sleep"
         set the uSleep of pCtrl to clampRange(numOr(the uSleep of pCtrl, 0) + pDir * 10, 0, 200)
         b2kSetSleepThreshold pCtrl, numOr(the uSleep of pCtrl, 0)
         break
      case "imgshape"
         set the itemDelimiter to comma
         put "box,ball,capsule" into tPal
         put itemOffset(numOr(the uShape of pCtrl, "box"), tPal) + pDir into tIdx
         if tIdx < 1 then put the number of items of tPal into tIdx
         if tIdx > the number of items of tPal then put 1 into tIdx
         set the uShape of pCtrl to item tIdx of tPal
         b2kReshape pCtrl, (the uShape of pCtrl)
         reapplyMaterial pCtrl
         reapplyCollision pCtrl             -- reshape resets the filter; restore layer + channels
         break
      case "active"
         if the uActive of pCtrl is false then
            set the uActive of pCtrl to true
            b2kEnable pCtrl
         else
            set the uActive of pCtrl to false
            b2kDisable pCtrl
         end if
         break
      case "sensor"
         set the uSensor of pCtrl to (the uSensor of pCtrl is not true)
         b2kSetSensor pCtrl, (the uSensor of pCtrl is true)
         b2kReshape pCtrl, partShape(pCtrl)
         reapplyMaterial pCtrl
         reapplyCollision pCtrl             -- reshape resets the filter; restore layer + channels
         applySensorLook pCtrl
         break
      case "filter"
         openFilterPanel pCtrl              -- a set of channels needs the popup, not a stepper
         break
      case "launchspeed"
         put numOr(the uLaunchSpeed of pCtrl, 0) + pDir * 50 into tLs
         set the uLaunchSpeed of pCtrl to clampRange(tLs, 0, 1500)
         break
      case "launchdir"
         set the uLaunchDir of pCtrl to ((numOr(the uLaunchDir of pCtrl, 0) + pDir * 15 + 360) mod 360)
         break
      case "spinrate"
         put numOr(the uSpinRate of pCtrl, 0) + pDir * 45 into tSr
         set the uSpinRate of pCtrl to clampRange(tSr, -720, 720)
         break
      case "toughness"
         set the uToughness of pCtrl to clampRange(numOr(the uToughness of pCtrl, kToughnessDefault) + pDir * kLaserBurnStep, 1, 600)
         break
      case "blastradius"
         put the uBlastRadius of pCtrl into tBr
         if tBr is empty then put kBombRadius into tBr
         put tBr + pDir * 60 into tBr
         if tBr < 60 then put 60 into tBr
         if tBr > 1200 then put 1200 into tBr
         set the uBlastRadius of pCtrl to tBr
         break
      case "blastpower"
         put the uBlastPower of pCtrl into tPow
         if tPow is empty then put kBombPower into tPow
         put tPow + pDir * 600 into tPow
         if tPow < 200 then put 200 into tPow
         if tPow > 30000 then put 30000 into tPow
         set the uBlastPower of pCtrl to tPow
         break
      case "fanforce"
         put (the uFanForce of pCtrl) + pDir * 600 into tF
         if tF < 0 then put 0 into tF
         if tF > 40000 then put 40000 into tF
         set the uFanForce of pCtrl to tF
         break
      case "fandir"
         put ((the uFanDir of pCtrl) + pDir * 90 + 360) mod 360 into tNewDir
         set the uFanDir of pCtrl to tNewDir
         drawFanShape pCtrl
         break
      case "fansize"
         put the uFanScale of pCtrl into tFs
         if tFs is empty then put 1 into tFs
         put tFs + pDir * 0.25 into tFs
         if tFs < 0.5 then put 0.5 into tFs
         if tFs > 2.5 then put 2.5 into tFs
         set the uFanScale of pCtrl to tFs
         drawFanShape pCtrl
         break
      case "magpol"
         set the uMagPolarity of pCtrl to (the uMagPolarity of pCtrl) * -1
         break
      case "magforce"
         put (the uMagForce of pCtrl) + pDir * 800 into tMf
         if tMf < 100 then put 100 into tMf
         if tMf > 50000 then put 50000 into tMf
         set the uMagForce of pCtrl to tMf
         break
      case "magrange"
         put (the uMagRange of pCtrl) + pDir * 80 into tMr
         if tMr < 60 then put 60 into tMr
         if tMr > 1400 then put 1400 into tMr
         set the uMagRange of pCtrl to tMr
         break
      case "laserdir"
         set the uLaserDir of pCtrl to ((numOr(the uLaserDir of pCtrl, 0) + pDir * kLaserStep + 360) mod 360)
         drawLaserBeam pCtrl
         break
      case "lasercut"
         set the uLaserCut of pCtrl to not (the uLaserCut of pCtrl is true)
         break
      case "laserburn"
         set the uLaserBurn of pCtrl to clampRange(numOr(the uLaserBurn of pCtrl, kLaserBurnDefault) + pDir * kLaserBurnStep, 1, 600)
         break
      case "goalsize"
         local tGs
         put numOr(the uGoalScale of pCtrl, 1) + pDir * 0.25 into tGs
         if tGs < 0.5 then put 0.5 into tGs
         if tGs > 3 then put 3 into tGs
         set the uGoalScale of pCtrl to tGs
         drawGoalShape pCtrl
         break
      case "thrustdir"
         set the uThrustDir of pCtrl to ((numOr(the uThrustDir of pCtrl, 270) + pDir * kLaserStep + 360) mod 360)
         break
      case "thrustpower"
         set the uThrustPower of pCtrl to clampRange(numOr(the uThrustPower of pCtrl, 0) + pDir * 600, 0, 40000)
         break
      case "thrustspin"
         set the uThrustSpin of pCtrl to clampRange(numOr(the uThrustSpin of pCtrl, 0) + pDir * 800, -40000, 40000)
         break
      case "thrustaim"
         if the uThrustAim of pCtrl is "body" then set the uThrustAim of pCtrl to "world"
         else set the uThrustAim of pCtrl to "body"
         break
      case "bombfuse"
         set the uFuseOnRun of pCtrl to not (the uFuseOnRun of pCtrl is true)
         break
      case "bombfuselen"
         set the uFuseLen of pCtrl to clampRange(numOr(the uFuseLen of pCtrl, kBombFuseFrames) + pDir * 30, 15, 900)
         break
      case "bombsoft"
         set the uSoftBlast of pCtrl to not (the uSoftBlast of pCtrl is true)
         break
      case "bombdemo"
         set the uDestroys of pCtrl to not (the uDestroys of pCtrl is true)
         break
   end switch
end adjustPartProp

-- Scale a part and re-fit its physics shape on the same body (joints survive).
on resizePart pCtrl, pFactor
   local tKind, tCx, tCy, tW, tH
   put the uKind of pCtrl into tKind
   put item 1 of the loc of pCtrl into tCx
   put item 2 of the loc of pCtrl into tCy
   if tKind is "poly" then
      scaleGraphicPoints pCtrl, pFactor, tCx, tCy
   else
      put round((the width of pCtrl) * pFactor) into tW
      put round((the height of pCtrl) * pFactor) into tH
      if tW < kSizeMin then put kSizeMin into tW
      if tH < kSizeMin then put kSizeMin into tH
      if tW > kSizeMax then put kSizeMax into tW
      if tH > kSizeMax then put kSizeMax into tH
      set the width of pCtrl to tW
      set the height of pCtrl to tH
      set the loc of pCtrl to tCx & "," & tCy
   end if
   set the uW of pCtrl to the width of pCtrl
   set the uH of pCtrl to the height of pCtrl
   if tKind is "hill" then
      rebuildHillChain pCtrl
   else if kindHasBody(tKind) then
      b2kReshape pCtrl, partShape(pCtrl)
      reapplyMaterial pCtrl
      reapplyCollision pCtrl             -- reshape resets the filter; keep layer + channels
   end if
end resizePart

-- Scale a polygon graphic's points around its centre, within the size limits.
on scaleGraphicPoints pCtrl, pFactor, pCx, pCy
   if (the width of pCtrl) * pFactor < kSizeMin then exit scaleGraphicPoints
   if (the width of pCtrl) * pFactor > kSizeMax then exit scaleGraphicPoints
   local tPt, tNew
   put empty into tNew
   repeat for each line tPt in the points of pCtrl
      if tPt is empty then next repeat
      put round(pCx + (item 1 of tPt - pCx) * pFactor) & "," & round(pCy + (item 2 of tPt - pCy) * pFactor) & cr after tNew
   end repeat
   set the points of pCtrl to tNew
end scaleGraphicPoints

-- Which collision shape a kind uses, for b2kReshape.
function shapeOfKind pKind
   switch pKind
      case "ball"
      case "balloon"
      case "bomb"
         return "ball"
      case "capsule"
         return "capsule"
      case "poly"
      case "platform"
      case "ramp"
      case "hill"
         return "poly"
   end switch
   return "box"
end shapeOfKind

-- The collision shape b2kReshape should rebuild for a part: an image uses its
-- chosen uShape (box/ball/capsule); every other kind is fixed by its kind.
function partShape pCtrl
   if the uKind of pCtrl is "image" then return numOr(the uShape of pCtrl, "box")
   return shapeOfKind(the uKind of pCtrl)
end partShape

-- After a reshape the new shape has default material; restore the part's values.
on reapplyMaterial pCtrl
   if the uBounce of pCtrl is not empty then b2kSetBounce pCtrl, (the uBounce of pCtrl)
   if the uDensity of pCtrl is not empty then b2kSetDensity pCtrl, (the uDensity of pCtrl)
   if the uFriction of pCtrl is not empty then b2kSetFriction pCtrl, (the uFriction of pCtrl)
end reapplyMaterial

-- Collision layer 0 (the default) hits everything. Layers 1-8 give a part a
-- shared negative collision group, so parts on the SAME layer pass through each
-- other while still colliding with the ground and parts on other layers.
on applyCollisionLayer pCtrl
   local tL
   put numOr(the uLayer of pCtrl, 0) into tL
   if tL is 0 then b2kSetCollisionGroup pCtrl, 0
   else b2kSetCollisionGroup pCtrl, - tL
end applyCollisionLayer

-- A part flagged as a sensor (trigger zone) is non-solid: bodies pass through it
-- and it fires b2kSensorEnter/Exit instead of colliding. Show that with a
-- translucent fill so it reads as a "ghost" zone, not a solid block.
on applySensorLook pCtrl
   if pCtrl is empty then exit applySensorLook
   try
      if the uSensor of pCtrl is true then set the blendLevel of pCtrl to 45
      else set the blendLevel of pCtrl to 0
   end try
end applySensorLook

-- ---------------------------------------------------------------------
-- Collision category / mask filter (the "Collision filter" popup panel)
-- ---------------------------------------------------------------------
-- A part is ON a set of channels (category) and COLLIDES WITH a set of channels
-- (mask). Two parts touch only when each is on a channel the other collides with.
-- This is independent of the simpler "Collision layer" (a group override). The
-- panel works in channel numbers 1..8; the Kit's filter wants the matching bits.

-- Turn a channel-number list ("1,3") into the bit values b2kLayerBits expects
-- (channel N -> 2^(N-1), so "1,3" -> "1,4").
function channelBits pList
   local tN, tOut
   put empty into tOut
   set the itemDelimiter to comma
   repeat for each item tN in pList
      if tN is empty or tN is not a number then next repeat
      put addItem(tOut, round(2 ^ (tN - 1))) into tOut   -- channel N -> bit 2^(N-1), kept integer
   end repeat
   if tOut is empty then return 0
   return tOut
end channelBits

-- A part's stored channel sets, defaulting to the Box2D default (on channel 1,
-- collides with every channel) when the part has never been customised.
function partCategories pCtrl
   return numOr(the uOnChans of pCtrl, "1")
end partCategories

function partMaskChannels pCtrl
   return numOr(the uHitChans of pCtrl, kAllChannels)
end partMaskChannels

function partFilterCustom pCtrl
   return (the uOnChans of pCtrl is not empty) or (the uHitChans of pCtrl is not empty)
end partFilterCustom

-- Push the part's category/mask into the live shape. A reshape resets the filter,
-- so this is re-run after every reshape (next to applyCollisionLayer).
on applyPartFilter pCtrl
   if pCtrl is empty then exit applyPartFilter
   if not partFilterCustom(pCtrl) then exit applyPartFilter   -- leave Box2D defaults alone
   b2kSetCategory pCtrl, channelBits(partCategories(pCtrl))
   b2kSetMask pCtrl, channelBits(partMaskChannels(pCtrl))
end applyPartFilter

-- Re-apply BOTH collision settings (layer group + category/mask) after a reshape,
-- which always rebuilds the shape with a default filter.
on reapplyCollision pCtrl
   applyCollisionLayer pCtrl
   applyPartFilter pCtrl
end reapplyCollision

-- A compact one-line description for the inspector row.
function filterSummary pCtrl
   if not partFilterCustom(pCtrl) then return "default (hits everything)"
   return "on " & channelText(partCategories(pCtrl)) & " / hits " & channelText(partMaskChannels(pCtrl))
end filterSummary

-- "1,2,3,4,5,6,7,8" -> "all"; a short list stays as-is; empty -> "none".
function channelText pList
   local tSorted
   if pList is empty then return "none"
   put sortedChannels(pList) into tSorted
   if tSorted is kAllChannels then return "all"
   return tSorted
end channelText

-- Add or remove a channel number from a comma list, kept sorted; never returns
-- empty (a part must stay on at least one channel, and collide with at least one).
function toggleChannel pList, pIdx
   local tN, tOut, tFound
   put empty into tOut
   put false into tFound
   set the itemDelimiter to comma
   repeat for each item tN in pList
      if tN is pIdx then
         put true into tFound
      else if tN is not empty then
         put addItem(tOut, tN) into tOut
      end if
   end repeat
   if not tFound then put addItem(tOut, pIdx) into tOut
   if tOut is empty then return pIdx          -- refuse to clear the last channel
   return sortedChannels(tOut)
end toggleChannel

-- Sort a channel-number list ascending and drop blanks/dupes.
function sortedChannels pList
   local tN, tSeen, tOut, tI
   set the itemDelimiter to comma
   repeat for each item tN in pList
      if tN is not empty and tN is a number then put true into tSeen[tN]
   end repeat
   put empty into tOut
   repeat with tI = 1 to kFilterChannels
      if tSeen[tI] is true then put addItem(tOut, tI) into tOut
   end repeat
   return tOut
end sortedChannels

-- A generous palette the Colour setting cycles through.
function partSwatches
   return "92,150,222" & cr & "84,206,142" & cr & "232,182,92" & cr & "214,92,92" & cr \
         & "206,124,206" & cr & "120,200,232" & cr & "236,120,150" & cr & "150,160,180" & cr \
         & "120,90,210" & cr & "240,140,60" & cr & "90,200,170" & cr & "232,232,236"
end partSwatches

function swatchIndexOf pCtrl, pPal
   local tLine, tI
   put 0 into tI
   repeat for each line tLine in pPal
      add 1 to tI
      if tLine is (the uColor of pCtrl) then return tI
   end repeat
   return 0
end swatchIndexOf

-- =====================================================================
-- Inspector tabs, exact-value entry, per-axis sizing, and joint settings
-- =====================================================================

-- Which settings tab a property key belongs to.
function propGroup pKey
   if pKey is among the items of "width,height,length,thickness,diameter,size,imgshape,angle,facing,color" then return "shape"
   if pKey is among the items of "bounce,density,friction,gravity,fixedrot,bodytype,lindamp,angdamp,bullet,material" then return "physics"
   if pKey is among the items of "layer,sensor,filter,active,sleep" then return "collide"
   return "special"   -- launchspeed,launchdir,spinrate, laserdir, and the fan/magnet/bomb keys
end propGroup

-- Append an item to a comma list (small sibling of addKV for ; lists).
function addItem pList, pItem
   if pList is empty then return pItem
   return pList & "," & pItem
end addItem

on selectInspTab pTab
   put pTab into gInspTab
   if gSelPart is not empty then showPartInspector gSelPart
end selectInspTab

-- Show only the tabs a part offers, highlighting the active one.
on refreshInspTabs pAvail
   local tT
   set the itemDelimiter to comma
   repeat for each item tT in "shape,physics,collide,special"
      if there is not a button ("ui_act_tab_" & tT) then next repeat
      if tT is among the items of pAvail then
         set the visible of button ("ui_act_tab_" & tT) to true
         if tT is gInspTab then
            setBtnActive ("ui_act_tab_" & tT), kColAccentGreen
         else
            setBtnIdle ("ui_act_tab_" & tT)
         end if
      else
         set the visible of button ("ui_act_tab_" & tT) to false
      end if
   end repeat
end refreshInspTabs

on hideInspTabs
   local tT
   set the itemDelimiter to comma
   repeat for each item tT in "shape,physics,collide,special"
      if there is a button ("ui_act_tab_" & tT) then set the visible of button ("ui_act_tab_" & tT) to false
   end repeat
end hideInspTabs

-- A custom-property value, or a fallback when it has never been set.
function numOr pV, pDefault
   if pV is empty then return pDefault
   return pV
end numOr

function clampRange pV, pLo, pHi
   if pV is empty or pV is not a number then return pLo
   if pV < pLo then return pLo
   if pV > pHi then return pHi
   return pV
end clampRange

function normDegrees pDeg, pDefault
   if pDeg is empty or pDeg is not a number then put pDefault into pDeg
   return ((round(pDeg) mod 360) + 360) mod 360
end normDegrees

-- Convert a user-facing seconds value to the frame counters used by fuses,
-- laser burn and toughness. These systems tick at the fixed 60 Hz sim rate, so
-- storing frames keeps save files deterministic while the inspector shows time.
function secondsToFrames pSeconds, pMinFrames, pMaxFrames
   if pSeconds is empty or pSeconds is not a number then return pMinFrames
   return round(clampRange(pSeconds * 60, pMinFrames, pMaxFrames))
end secondsToFrames

-- Keep a part dimension within the allowed pixel range.
function clampDim pV
   if pV is empty or pV is not a number then return kSizeMin
   put round(pV) into pV
   if pV < kSizeMin then return kSizeMin
   if pV > kSizeMax then return kSizeMax
   return pV
end clampDim

-- Set ONE axis of a part to an exact pixel size, then re-fit its physics shape on
-- the same body so joints survive. pAxis is "w", "h", or "d" (both, for balls).
on setPartDimension pCtrl, pAxis, pValue
   local tKind, tCx, tCy, tW, tH, tAng
   put the uKind of pCtrl into tKind
   -- Terrain rebuilds its outline from uW/uH directly (its angle lives in the
   -- points, not the body), so it sizes cleanly at any rotation.
   if kindIsTerrain(tKind) then
      put clampRange(pValue, kTerrainMin, kTerrainMax) into pValue
      if pAxis is "h" then set the uH of pCtrl to pValue
      else set the uW of pCtrl to pValue
      regenTerrain pCtrl
      exit setPartDimension
   end if
   put item 1 of the loc of pCtrl into tCx
   put item 2 of the loc of pCtrl into tCy
   -- A rotated graphic's rect is its (inflated) bounding box, so resize in an
   -- upright frame, then restore the angle. Axis-aligned parts skip this entirely.
   put 0 into tAng
   if kindHasBody(tKind) then put round(b2kAngle(pCtrl)) into tAng
   if tAng is not 0 then
      b2kMoveTo pCtrl, tCx, tCy, 0
      renderBuild
   end if
   put numOr(the uW of pCtrl, the width of pCtrl) into tW
   put numOr(the uH of pCtrl, the height of pCtrl) into tH
   put clampDim(pValue) into pValue
   if pAxis is "w" then
      put pValue into tW
   else if pAxis is "h" then
      put pValue into tH
   else if pAxis is "d" then
      put pValue into tW
      put pValue into tH
   end if
   set the width of pCtrl to tW
   set the height of pCtrl to tH
   set the loc of pCtrl to tCx & "," & tCy
   set the uW of pCtrl to tW
   set the uH of pCtrl to tH
   if tKind is "hill" then
      rebuildHillChain pCtrl              -- outline carries its own rotation; body stays at 0
   else if kindHasBody(tKind) then
      b2kReshape pCtrl, partShape(pCtrl)
      reapplyMaterial pCtrl
      reapplyCollision pCtrl              -- reshape resets the filter; keep layer + channels
      if tAng is not 0 then b2kMoveTo pCtrl, tCx, tCy, tAng
   end if
end setPartDimension

-- Click a settings value to type an exact number (parts or joints).
on editPropValue pKey
   if pKey is empty then exit editPropValue
   if gSelJoint is not empty then
      editJointValue pKey
      exit editPropValue
   end if
   if gSelPart is empty then exit editPropValue
   if pKey is "filter" then
      openFilterPanel gSelPart
      exit editPropValue
   end if
   set the itemDelimiter to comma
   if pKey is not among the items of kEntryKeys then     -- colours, materials and toggles step with +/-, not type-in
      put "Use the +/- buttons to change this." into gStatus
      updateHud
      exit editPropValue
   end if
   ask ("Set " & propEditName(gSelPart, pKey) & ":") with currentPropValue(gSelPart, pKey)
   if it is empty or the result is "Cancel" then exit editPropValue
   if it is not a number then
      put "Please type a number." into gStatus
      updateHud
      exit editPropValue
   end if
   applyPropValue gSelPart, pKey, it
   showPartInspector gSelPart
   if gMode is "build" then renderBuild
end editPropValue

-- A readable name for the entry dialog, taken from the row label (before the colon).
function propEditName pCtrl, pKey
   local tL
   put propLabel(pCtrl, pKey) into tL
   if ":" is in tL then return char 1 to (offset(":", tL) - 1) of tL
   return pKey
end propEditName

function currentPropValue pCtrl, pKey
   switch pKey
      case "width"
      case "length"
      case "diameter"
      case "size"
         return numOr(the uW of pCtrl, the width of pCtrl)
      case "height"
      case "thickness"
         return numOr(the uH of pCtrl, the height of pCtrl)
      case "angle"
         if kindIsTerrain(the uKind of pCtrl) then return numOr(the uAngle of pCtrl, 0)
         return round(b2kAngle(pCtrl))
      case "bounce"
         return numOr(the uBounce of pCtrl, 0)
      case "density"
         return numOr(the uDensity of pCtrl, 1)
      case "friction"
         return numOr(the uFriction of pCtrl, 0.4)
      case "gravity"
         return numOr(the uGravity of pCtrl, 1)
      case "lindamp"
         return numOr(the uLinDamp of pCtrl, 0)
      case "angdamp"
         return numOr(the uAngDamp of pCtrl, 0)
      case "launchspeed"
         return numOr(the uLaunchSpeed of pCtrl, 0)
      case "launchdir"
         return numOr(the uLaunchDir of pCtrl, 0)
      case "spinrate"
         return numOr(the uSpinRate of pCtrl, 0)
      case "toughness"
         return format("%.2f", numOr(the uToughness of pCtrl, kToughnessDefault) / 60)
      case "blastradius"
         return numOr(the uBlastRadius of pCtrl, kBombRadius)
      case "blastpower"
         return numOr(the uBlastPower of pCtrl, kBombPower)
      case "bombfuselen"
         return format("%.2f", numOr(the uFuseLen of pCtrl, kBombFuseFrames) / 60)
      case "fanforce"
         return numOr(the uFanForce of pCtrl, kFanForce)
      case "fansize"
         return numOr(the uFanScale of pCtrl, 1)
      case "magforce"
         return numOr(the uMagForce of pCtrl, kMagnetForce)
      case "magrange"
         return numOr(the uMagRange of pCtrl, kMagnetRange)
      case "laserburn"
         return format("%.2f", numOr(the uLaserBurn of pCtrl, kLaserBurnDefault) / 60)
      case "goalsize"
         return numOr(the uGoalScale of pCtrl, 1)
      case "thrustdir"
         return numOr(the uThrustDir of pCtrl, 270)
      case "thrustpower"
         return numOr(the uThrustPower of pCtrl, 0)
      case "thrustspin"
         return numOr(the uThrustSpin of pCtrl, 0)
   end switch
   return empty
end currentPropValue

-- Apply an exact typed value to a part (clamped), syncing physics like the steppers.
on applyPropValue pCtrl, pKey, pVal
   switch pKey
      case "width"
      case "length"
         setPartDimension pCtrl, "w", pVal
         break
      case "height"
      case "thickness"
         setPartDimension pCtrl, "h", pVal
         break
      case "diameter"
         setPartDimension pCtrl, "d", pVal
         break
      case "angle"
         setPartAngle pCtrl, pVal
         break
      case "size"
         if (the width of pCtrl) >= 1 then resizePart pCtrl, (clampDim(pVal) / (the width of pCtrl))
         break
      case "bounce"
         put clampRange(pVal, 0, 0.9) into pVal
         set the uBounce of pCtrl to pVal
         b2kSetBounce pCtrl, pVal
         break
      case "density"
         put clampRange(pVal, 0.3, 3) into pVal
         set the uDensity of pCtrl to pVal
         b2kSetDensity pCtrl, pVal
         break
      case "friction"
         put clampRange(pVal, 0, 2) into pVal
         set the uFriction of pCtrl to pVal
         b2kSetFriction pCtrl, pVal
         break
      case "gravity"
         put clampRange(pVal, -2, 3) into pVal
         set the uGravity of pCtrl to pVal
         b2kSetGravityScale pCtrl, pVal
         break
      case "lindamp"
         put clampRange(pVal, 0, 5) into pVal
         set the uLinDamp of pCtrl to pVal
         b2kSetDamping pCtrl, pVal, empty
         break
      case "angdamp"
         put clampRange(pVal, 0, 5) into pVal
         set the uAngDamp of pCtrl to pVal
         b2kSetDamping pCtrl, empty, pVal
         break
      case "launchspeed"
         set the uLaunchSpeed of pCtrl to clampRange(pVal, 0, 1500)
         break
      case "launchdir"
         set the uLaunchDir of pCtrl to normDegrees(pVal, 0)
         break
      case "spinrate"
         set the uSpinRate of pCtrl to clampRange(pVal, -720, 720)
         break
      case "toughness"
         set the uToughness of pCtrl to secondsToFrames(pVal, 1, 600)
         break
      case "blastradius"
         set the uBlastRadius of pCtrl to clampRange(pVal, 60, 1200)
         break
      case "blastpower"
         set the uBlastPower of pCtrl to clampRange(pVal, 200, 30000)
         break
      case "bombfuselen"
         set the uFuseLen of pCtrl to secondsToFrames(pVal, 15, 900)
         break
      case "fanforce"
         set the uFanForce of pCtrl to clampRange(pVal, 0, 40000)
         break
      case "fansize"
         set the uFanScale of pCtrl to clampRange(pVal, 0.5, 2.5)
         drawFanShape pCtrl
         break
      case "magforce"
         set the uMagForce of pCtrl to clampRange(pVal, 100, 50000)
         break
      case "magrange"
         set the uMagRange of pCtrl to clampRange(pVal, 60, 1400)
         break
      case "laserburn"
         set the uLaserBurn of pCtrl to secondsToFrames(pVal, 1, 600)
         break
      case "goalsize"
         set the uGoalScale of pCtrl to clampRange(pVal, 0.5, 3)
         drawGoalShape pCtrl
         break
      case "thrustdir"
         set the uThrustDir of pCtrl to normDegrees(pVal, 270)
         break
      case "thrustpower"
         set the uThrustPower of pCtrl to clampRange(pVal, 0, 40000)
         break
      case "thrustspin"
         set the uThrustSpin of pCtrl to clampRange(pVal, -40000, 40000)
         break
   end switch
end applyPropValue

-- ---- Per-joint inspector --------------------------------------------

-- The on-screen point that selects a joint (its marker bead / link midpoint).
function jointHandleLoc pIndex
   local tVis, tG, tA, tB
   put gJVis[pIndex] into tVis
   put "cb_joint_" & pIndex into tG
   if there is not a graphic tG then return empty
   if tVis is "dot" then return the loc of graphic tG
   if tVis is "rod" then
      put line 1 of the points of graphic tG into tA
      put line 2 of the points of graphic tG into tB
      if tA is empty or tB is empty then return the loc of graphic tG
      return midOf(tA, tB)
   end if
   if gJCa[pIndex] is empty then return empty
   put the loc of gJCa[pIndex] into tA
   if gJCb[pIndex] is empty then put tA into tB
   else put the loc of gJCb[pIndex] into tB
   return midOf(tA, tB)
end jointHandleLoc

function midOf pA, pB
   return round((item 1 of pA + item 1 of pB) / 2) & "," & round((item 2 of pA + item 2 of pB) / 2)
end midOf

-- The live joint whose handle is nearest the click (within kJointHitR), or empty.
function jointUnderClick pX, pY
   local tI, tBest, tBestD, tH, tD
   put empty into tBest
   put empty into tBestD
   if gJN < 1 then return empty
   repeat with tI = 1 to gJN
      if gJKind[tI] is empty then next repeat
      if gJVis[tI] is "none" then next repeat
      put jointHandleLoc(tI) into tH
      if tH is empty then next repeat
      put sqrt((pX - item 1 of tH)^2 + (pY - item 2 of tH)^2) into tD
      if tD <= kJointHitR and (tBest is empty or tD < tBestD) then
         put tI into tBest
         put tD into tBestD
      end if
   end repeat
   return tBest
end jointUnderClick

on selectJoint pIndex
   if pIndex is empty then exit selectJoint
   if gJKind[pIndex] is empty then exit selectJoint
   deselectPart
   deselectJoint
   put pIndex into gSelJoint
   local tG
   put "cb_joint_" & pIndex into tG
   if there is a graphic tG then
      try
         set the uSelLine of graphic tG to the lineSize of graphic tG
         set the uSelFg of graphic tG to the foregroundColor of graphic tG
         set the lineSize of graphic tG to (the lineSize of graphic tG) + 3
         set the foregroundColor of graphic tG to "255,255,255"
      end try
   end if
   showJointInspector pIndex
end selectJoint

on deselectJoint
   if gSelJoint is empty then exit deselectJoint
   local tG
   put "cb_joint_" & gSelJoint into tG
   if there is a graphic tG then
      try
         set the lineSize of graphic tG to the uSelLine of graphic tG
         set the foregroundColor of graphic tG to the uSelFg of graphic tG
      end try
   end if
   put empty into gSelJoint
   clearPropRows
end deselectJoint

-- Show a selected joint's name, what it does, and the values you can change.
on showJointInspector pIndex
   if pIndex is empty then exit showJointInspector
   if gJKind[pIndex] is empty then exit showJointInspector
   local tKind, tKey, tRow, tMk
   put gJKind[pIndex] into tKind
   put the long id of graphic ("cb_joint_" & pIndex) into tMk
   setInspector ("Selected: " & niceName(tKind)), (line 2 of toolHelp(tKind))
   clearPropRows
   hideInspTabs
   put 0 into tRow
   set the itemDelimiter to comma
   repeat for each item tKey in jointProps(tKind)
      add 1 to tRow
      if tRow > kPropRows then exit repeat
      showPropRow tRow, jointPropLabel(tMk, tKind, tKey), tKey
   end repeat
   if tRow > 0 then setSettingsHint empty
   else setSettingsHint "This joint has no adjustable settings."
end showJointInspector

-- The ordered list of adjustable settings shown for each kind of joint.
function jointProps pKind
   switch pKind
      case "hinge"
         return "jmotoron,jmotorspeed,jmotorpower,jlimiton,jlimitlo,jlimithi"
      case "slider"
         return "jmotoron,jmotorspeed,jmotorpower,jlimiton,jlimitlo,jlimithi"
      case "wheel"
         return "jmotoron,jmotorspeed,jmotorpower,jspringhz,jspringdamp"
      case "rope"
         return "jminlen,jmaxlen,jspringhz,jspringdamp"
      case "weld"
         return "jspringhz,jspringdamp"
   end switch
   return empty
end jointProps

-- The human-readable "Name: value" shown on a joint property row.
function jointPropLabel pMk, pKind, pKey
   local tUnit
   if pKind is "slider" then
      put " px/s" into tUnit
   else
      put " deg/s" into tUnit
   end if
   switch pKey
      case "jmotoron"
         return "Motor: " & onOff(the uMotorOn of pMk is true)
      case "jmotorspeed"
         return "Motor speed: " & numOr(the uMotorSpeed of pMk, gMotorSpeed) & tUnit
      case "jmotorpower"
         return "Motor power: " & numOr(the uMotorPower of pMk, motorPowerDefault(pKind))
      case "jlimiton"
         return "Limits: " & onOff(the uLimitOn of pMk is true)
      case "jlimitlo"
         if pKind is "slider" then return "Limit min: " & numOr(the uLimitLo of pMk, -100) & " px"
         return "Limit min: " & numOr(the uLimitLo of pMk, -45) & " deg"
      case "jlimithi"
         if pKind is "slider" then return "Limit max: " & numOr(the uLimitHi of pMk, 100) & " px"
         return "Limit max: " & numOr(the uLimitHi of pMk, 45) & " deg"
      case "jspringhz"
         return "Springiness: " & numOr(the uSpringHz of pMk, 0) & " Hz"
      case "jspringdamp"
         return "Spring damping: " & numOr(the uSpringDamp of pMk, 0.5)
      case "jminlen"
         return "Min length: " & numOr(the uMinLen of pMk, 0) & " px"
      case "jmaxlen"
         return "Max length: " & numOr(the uMaxLen of pMk, 200) & " px"
   end switch
   return pKey
end jointPropLabel

-- "on"/"off" for a boolean-ish global (shared by the joint, filter and world panels).
function onOff pFlag
   if pFlag is true then return "on"
   return "off"
end onOff

on adjustJointProp pIndex, pKey, pDir
   local tMk, tV
   put the long id of graphic ("cb_joint_" & pIndex) into tMk
   switch pKey
      case "jmotoron"
         set the uMotorOn of tMk to not (the uMotorOn of tMk is true)
         applyJointMotor pIndex
         break
      case "jmotorspeed"
         put numOr(the uMotorSpeed of tMk, gMotorSpeed) + pDir * 30 into tV
         set the uMotorSpeed of tMk to clampRange(tV, kMotorMin, kMotorMax)
         applyJointMotor pIndex
         break
      case "jmotorpower"
         put numOr(the uMotorPower of tMk, motorPowerDefault(gJKind[pIndex])) + pDir * 100 into tV
         set the uMotorPower of tMk to clampRange(tV, 50, 6000)
         applyJointMotor pIndex
         break
      case "jlimiton"
         set the uLimitOn of tMk to not (the uLimitOn of tMk is true)
         applyJointLimit pIndex
         break
      case "jlimitlo"
         if gJKind[pIndex] is "slider" then put numOr(the uLimitLo of tMk, -100) + pDir * 20 into tV
         else put numOr(the uLimitLo of tMk, -45) + pDir * 15 into tV
         set the uLimitLo of tMk to tV
         applyJointLimit pIndex
         break
      case "jlimithi"
         if gJKind[pIndex] is "slider" then put numOr(the uLimitHi of tMk, 100) + pDir * 20 into tV
         else put numOr(the uLimitHi of tMk, 45) + pDir * 15 into tV
         set the uLimitHi of tMk to tV
         applyJointLimit pIndex
         break
      case "jspringhz"
         put numOr(the uSpringHz of tMk, 0) + pDir * 1 into tV
         set the uSpringHz of tMk to clampRange(tV, 0, 15)
         applyJointSpring pIndex
         break
      case "jspringdamp"
         put numOr(the uSpringDamp of tMk, 0.5) + pDir * 0.1 into tV
         set the uSpringDamp of tMk to clampRange(tV, 0, 1)
         applyJointSpring pIndex
         break
      case "jminlen"
         put numOr(the uMinLen of tMk, 0) + pDir * 20 into tV
         set the uMinLen of tMk to clampRange(tV, 0, 800)
         set the uRangeSet of tMk to true
         applyJointRange pIndex
         break
      case "jmaxlen"
         put numOr(the uMaxLen of tMk, 200) + pDir * 20 into tV
         set the uMaxLen of tMk to clampRange(tV, 20, 800)
         set the uRangeSet of tMk to true
         applyJointRange pIndex
         break
   end switch
end adjustJointProp

-- Push the marker's stored motor setting to the live joint (kind-specific call).
on applyJointMotor pIndex
   local tKind, tJ, tMk, tOn, tSpd, tPow
   put gJKind[pIndex] into tKind
   put gJHandle[pIndex] into tJ
   put the long id of graphic ("cb_joint_" & pIndex) into tMk
   put (the uMotorOn of tMk is true) into tOn
   put numOr(the uMotorSpeed of tMk, gMotorSpeed) into tSpd
   put numOr(the uMotorPower of tMk, motorPowerDefault(tKind)) into tPow
   switch tKind
      case "hinge"
         if tOn then b2kMotor tJ, tSpd, tPow
         else b2kMotorOff tJ
         break
      case "slider"
         if tOn then b2kSliderMotor tJ, tSpd, tPow
         else b2kSliderMotorOff tJ
         break
      case "wheel"
         if tOn then b2kWheelMotor tJ, tSpd, tPow
         else b2kWheelMotorOff tJ
         break
   end switch
   if tOn then put tSpd into gJMotor[pIndex]
   else put 0 into gJMotor[pIndex]
end applyJointMotor

on applyJointLimit pIndex
   local tKind, tJ, tMk, tOn, tLo, tHi
   put gJKind[pIndex] into tKind
   put gJHandle[pIndex] into tJ
   put the long id of graphic ("cb_joint_" & pIndex) into tMk
   put (the uLimitOn of tMk is true) into tOn
   if tKind is "slider" then
      put numOr(the uLimitLo of tMk, -100) into tLo
      put numOr(the uLimitHi of tMk, 100) into tHi
      if tOn then b2kSliderLimit tJ, tLo, tHi
      else b2kSliderLimitOff tJ
   else if tKind is "hinge" then
      put numOr(the uLimitLo of tMk, -45) into tLo
      put numOr(the uLimitHi of tMk, 45) into tHi
      if tOn then b2kHingeLimit tJ, tLo, tHi
      else b2kHingeLimitOff tJ
   end if
end applyJointLimit

on applyJointSpring pIndex
   local tKind, tJ, tMk, tHz, tDamp
   put gJKind[pIndex] into tKind
   put gJHandle[pIndex] into tJ
   put the long id of graphic ("cb_joint_" & pIndex) into tMk
   put numOr(the uSpringHz of tMk, 0) into tHz
   put numOr(the uSpringDamp of tMk, 0.5) into tDamp
   switch tKind
      case "rope"
         if tHz > 0 then b2kSpring tJ, tHz, tDamp
         else b2DistanceEnableSpring tJ, false, 0, 0   -- 0 Hz = rigid rope again
         break
      case "weld"
         b2kWeldSpring tJ, tHz, tDamp                  -- 0 Hz = rigid weld
         break
      case "wheel"
         b2kWheelSpring tJ, tHz, tDamp
         break
   end switch
end applyJointSpring

on applyJointRange pIndex
   local tJ, tMk
   put gJHandle[pIndex] into tJ
   put the long id of graphic ("cb_joint_" & pIndex) into tMk
   b2kRopeRange tJ, numOr(the uMinLen of tMk, 0), numOr(the uMaxLen of tMk, 200)
end applyJointRange

-- Click a joint value to type an exact number.
on editJointValue pKey
   if gSelJoint is empty then exit editJointValue
   set the itemDelimiter to comma
   if pKey is among the items of "jmotoron,jlimiton" then exit editJointValue   -- toggles only
   local tMk
   put the long id of graphic ("cb_joint_" & gSelJoint) into tMk
   ask ("Set " & jointEditName(pKey) & ":") with jointValueOf(tMk, pKey)
   if it is empty or the result is "Cancel" then exit editJointValue
   if it is not a number then
      put "Please type a number." into gStatus
      updateHud
      exit editJointValue
   end if
   applyJointValue gSelJoint, pKey, it
   showJointInspector gSelJoint
end editJointValue

function jointValueOf pMk, pKey
   switch pKey
      case "jmotorspeed"
         return numOr(the uMotorSpeed of pMk, gMotorSpeed)
      case "jmotorpower"
         return numOr(the uMotorPower of pMk, motorPowerDefault(the uJKind of pMk))
      case "jlimitlo"
         return numOr(the uLimitLo of pMk, 0)
      case "jlimithi"
         return numOr(the uLimitHi of pMk, 0)
      case "jspringhz"
         return numOr(the uSpringHz of pMk, 0)
      case "jspringdamp"
         return numOr(the uSpringDamp of pMk, 0.5)
      case "jminlen"
         return numOr(the uMinLen of pMk, 0)
      case "jmaxlen"
         return numOr(the uMaxLen of pMk, 200)
   end switch
   return empty
end jointValueOf

function jointEditName pKey
   switch pKey
      case "jmotorspeed"
         return "motor speed"
      case "jmotorpower"
         return "motor power"
      case "jlimitlo"
         return "limit minimum"
      case "jlimithi"
         return "limit maximum"
      case "jspringhz"
         return "springiness (Hz)"
      case "jspringdamp"
         return "spring damping (0-1)"
      case "jminlen"
         return "minimum length (px)"
      case "jmaxlen"
         return "maximum length (px)"
   end switch
   return pKey
end jointEditName

on applyJointValue pIndex, pKey, pVal
   local tMk
   put the long id of graphic ("cb_joint_" & pIndex) into tMk
   switch pKey
      case "jmotorspeed"
         set the uMotorSpeed of tMk to clampRange(pVal, kMotorMin, kMotorMax)
         applyJointMotor pIndex
         break
      case "jmotorpower"
         set the uMotorPower of tMk to clampRange(pVal, 50, 6000)
         applyJointMotor pIndex
         break
      case "jlimitlo"
         set the uLimitLo of tMk to pVal
         applyJointLimit pIndex
         break
      case "jlimithi"
         set the uLimitHi of tMk to pVal
         applyJointLimit pIndex
         break
      case "jspringhz"
         set the uSpringHz of tMk to clampRange(pVal, 0, 15)
         applyJointSpring pIndex
         break
      case "jspringdamp"
         set the uSpringDamp of tMk to clampRange(pVal, 0, 1)
         applyJointSpring pIndex
         break
      case "jminlen"
         set the uMinLen of tMk to clampRange(pVal, 0, 800)
         set the uRangeSet of tMk to true
         applyJointRange pIndex
         break
      case "jmaxlen"
         set the uMaxLen of tMk to clampRange(pVal, 20, 800)
         set the uRangeSet of tMk to true
         applyJointRange pIndex
         break
   end switch
end applyJointValue

-- Pack a joint's editable settings as "key=value;..." (per-kind) for Save.
function jointSpecial pIndex
   local tKind, tMk, tS
   put gJKind[pIndex] into tKind
   if tKind is empty then return empty
   put the long id of graphic ("cb_joint_" & pIndex) into tMk
   put empty into tS
   if tKind is "hinge" or tKind is "slider" or tKind is "wheel" then
      put addKV(tS, "mon=" & (the uMotorOn of tMk is true)) into tS
      put addKV(tS, "msp=" & numOr(the uMotorSpeed of tMk, gMotorSpeed)) into tS
      put addKV(tS, "mpw=" & numOr(the uMotorPower of tMk, motorPowerDefault(tKind))) into tS
   end if
   if tKind is "hinge" or tKind is "slider" then
      put addKV(tS, "lon=" & (the uLimitOn of tMk is true)) into tS
      put addKV(tS, "llo=" & numOr(the uLimitLo of tMk, 0)) into tS
      put addKV(tS, "lhi=" & numOr(the uLimitHi of tMk, 0)) into tS
   end if
   if tKind is "rope" or tKind is "weld" or tKind is "wheel" then
      put addKV(tS, "shz=" & numOr(the uSpringHz of tMk, 0)) into tS
      put addKV(tS, "sdm=" & numOr(the uSpringDamp of tMk, 0.5)) into tS
   end if
   if tKind is "rope" and (the uRangeSet of tMk is true) then
      put addKV(tS, "rng=true") into tS
      put addKV(tS, "rmn=" & numOr(the uMinLen of tMk, 0)) into tS
      put addKV(tS, "rmx=" & numOr(the uMaxLen of tMk, 200)) into tS
   end if
   return tS
end jointSpecial

-- Restore a joint's editable settings (from Load); empty string = leave defaults.
on applyJointSpecial pIndex, pSpecial
   if pSpecial is empty then exit applyJointSpecial
   if gJKind[pIndex] is empty then exit applyJointSpecial
   local tMk, tV
   put the long id of graphic ("cb_joint_" & pIndex) into tMk
   put specialValue(pSpecial, "mon") into tV
   if tV is not empty then set the uMotorOn of tMk to (tV is "true")
   put specialValue(pSpecial, "msp") into tV
   if tV is not empty then set the uMotorSpeed of tMk to tV
   put specialValue(pSpecial, "mpw") into tV
   if tV is not empty then set the uMotorPower of tMk to tV
   put specialValue(pSpecial, "lon") into tV
   if tV is not empty then set the uLimitOn of tMk to (tV is "true")
   put specialValue(pSpecial, "llo") into tV
   if tV is not empty then set the uLimitLo of tMk to tV
   put specialValue(pSpecial, "lhi") into tV
   if tV is not empty then set the uLimitHi of tMk to tV
   put specialValue(pSpecial, "shz") into tV
   if tV is not empty then set the uSpringHz of tMk to tV
   put specialValue(pSpecial, "sdm") into tV
   if tV is not empty then set the uSpringDamp of tMk to tV
   applyJointMotor pIndex
   applyJointLimit pIndex
   applyJointSpring pIndex
   if specialValue(pSpecial, "rng") is "true" then
      set the uRangeSet of tMk to true
      put specialValue(pSpecial, "rmn") into tV
      if tV is not empty then set the uMinLen of tMk to tV
      put specialValue(pSpecial, "rmx") into tV
      if tV is not empty then set the uMaxLen of tMk to tV
      applyJointRange pIndex
   end if
end applyJointSpecial

-- Defaults for a joint marker's editable settings, by joint kind.
function jointLimitLoDefault pKind
   if pKind is "slider" then return -100
   return -45
end jointLimitLoDefault

function jointLimitHiDefault pKind
   if pKind is "slider" then return 100
   return 45
end jointLimitHiDefault

function jointSpringHzDefault pKind
   if pKind is "wheel" then return 5
   return 0
end jointSpringHzDefault

function jointSpringDampDefault pKind
   if pKind is "wheel" then return 0.7
   return 0.5
end jointSpringDampDefault

-- ---- Rotation, material presets, launch, gravity, pause -------------

-- Re-seat a part at an exact angle (degrees), keeping its position. Joints survive.
on setPartAngle pCtrl, pDeg
   local tCx, tCy
   -- Terrain bakes its angle into the points (a static body never re-syncs).
   if kindIsTerrain(the uKind of pCtrl) then
      set the uAngle of pCtrl to normDegrees(pDeg, 0)
      regenTerrain pCtrl
      exit setPartAngle
   end if
   if not kindHasBody(the uKind of pCtrl) then exit setPartAngle
   put item 1 of the loc of pCtrl into tCx
   put item 2 of the loc of pCtrl into tCy
   put normDegrees(pDeg, 0) into pDeg
   b2kMoveTo pCtrl, tCx, tCy, pDeg
   renderBuild
end setPartAngle

-- A material is "friction,density,bounce". Presets give parts a quick feel.
function materialPreset pName
   switch pName
      case "Ice"
         return "0.02,0.9,0.05"
      case "Rubber"
         return "0.9,1,0.85"
      case "Metal"
         return "0.3,2.6,0.05"
      case "Wood"
         return "0.5,0.7,0.2"
   end switch
   return "0.4,1,0.2"        -- Default
end materialPreset

-- Name the preset a part currently matches, or "Custom".
function materialNameOf pCtrl
   local tName, tP, tFr, tD, tB
   put numOr(the uFriction of pCtrl, 0.4) into tFr
   put numOr(the uDensity of pCtrl, 1) into tD
   put numOr(the uBounce of pCtrl, 0.2) into tB
   set the itemDelimiter to comma
   repeat for each item tName in "Default,Ice,Rubber,Metal,Wood"
      put materialPreset(tName) into tP
      if tFr is item 1 of tP and tD is item 2 of tP and tB is item 3 of tP then return tName
   end repeat
   return "Custom"
end materialNameOf

-- Step to the next/previous material preset and apply its values.
on cycleMaterial pCtrl, pDir
   local tOrder, tI, tName, tP
   put "Default,Ice,Rubber,Metal,Wood" into tOrder
   set the itemDelimiter to comma
   put itemOffset(materialNameOf(pCtrl), tOrder) + pDir into tI
   if tI < 1 then put the number of items of tOrder into tI
   if tI > the number of items of tOrder then put 1 into tI
   put item tI of tOrder into tName
   put materialPreset(tName) into tP
   set the uFriction of pCtrl to item 1 of tP
   b2kSetFriction pCtrl, item 1 of tP
   set the uDensity of pCtrl to item 2 of tP
   b2kSetDensity pCtrl, item 2 of tP
   set the uBounce of pCtrl to item 3 of tP
   b2kSetBounce pCtrl, item 3 of tP
end cycleMaterial

-- Apply each part's saved launch velocity and spin (called when Run starts).
on armLaunches
   local tP, tSpeed, tDir, tSpin
   repeat for each line tP in gParts
      if tP is empty then next repeat
      if not kindHasBody(the uKind of tP) then next repeat
      put numOr(the uLaunchSpeed of tP, 0) into tSpeed
      put numOr(the uLaunchDir of tP, 0) into tDir
      put numOr(the uSpinRate of tP, 0) into tSpin
      if tSpeed > 0 then b2kSetVelocity tP, tSpeed * cos(tDir * kPI / 180), - tSpeed * sin(tDir * kPI / 180)
      if tSpin is not 0 then b2kSpin tP, tSpin
   end repeat
end armLaunches

-- World gravity presets (metres/sec^2; screen down is negative y).
on applyGravityMode
   switch gGravityMode
      case "low"
         b2kSetGravity 0, -3.5
         break
      case "zero"
         b2kSetGravity 0, 0
         break
      case "reverse"
         b2kSetGravity 0, 10
         break
      case "sideways"
         b2kSetGravity 9, -4
         break
      default
         b2kSetGravity 0, -10
   end switch
end applyGravityMode

on cycleGravity
   local tOrder, tI
   put "normal,low,zero,reverse,sideways" into tOrder
   set the itemDelimiter to comma
   put itemOffset(gGravityMode, tOrder) + 1 into tI
   if tI < 1 or tI > the number of items of tOrder then put 1 into tI
   put item tI of tOrder into gGravityMode
   applyGravityMode
   refreshGravityLabel
   put "Gravity: " & gravityModeName(gGravityMode) & "." into gStatus
   updateHud
end cycleGravity

on refreshGravityLabel
   if there is a button "ui_act_gravity" then set the label of button "ui_act_gravity" to "Gravity: " & gravityModeName(gGravityMode)
end refreshGravityLabel

-- World feel: a few one-click presets that tune how the whole world responds -
-- how readily things bounce (restitution threshold), how soft/stiff contacts are
-- (contact tuning) and a top speed cap. Cosmetic-but-fun; safe before the world
-- exists (the Kit's world setters no-op until b2kSetup has run).
function worldFeelName pMode
   switch pMode
      case "bouncy"
         return "Bouncy"
      case "floaty"
         return "Floaty"
      case "snappy"
         return "Snappy"
   end switch
   return "Default"
end worldFeelName

on applyWorldFeel
   switch gWorldFeel
      case "bouncy"
         b2kSetRestitutionThreshold 20      -- low threshold: collisions bounce readily
         b2kSetContactTuning 30, 10, 120
         b2kSetMaxSpeed 6000
         break
      case "floaty"
         b2kSetRestitutionThreshold 40
         b2kSetContactTuning 12, 12, 80     -- soft, squishy contacts
         b2kSetMaxSpeed 1500                -- gentle, speed-limited
         break
      case "snappy"
         b2kSetRestitutionThreshold 80      -- only fast hits bounce
         b2kSetContactTuning 60, 8, 160     -- stiff, responsive contacts
         b2kSetMaxSpeed 6000
         break
      default                               -- "default": Box2D's standard feel
         b2kSetRestitutionThreshold 40
         b2kSetContactTuning 30, 10, 120
         b2kSetMaxSpeed 6000
   end switch
end applyWorldFeel

-- The advanced solver toggles default to Box2D's recommended setup.
on setWorldOptionDefaults
   put true into gCCD           -- continuous collision ON: fast bodies don't tunnel through walls
   put true into gSleepOn       -- resting bodies sleep (saves CPU)
   put true into gWarmStart     -- reuse last frame's solution (stabler + faster)
   put 4 into gSubsteps         -- solver sub-steps per step
end setWorldOptionDefaults

-- Push the advanced toggles into the live world (re-applied on every Run).
on applyWorldOptions
   b2kEnableContinuous (gCCD is true)
   b2kEnableSleeping (gSleepOn is true)
   b2kEnableWarmStarting (gWarmStart is true)
   b2kSetSubsteps numOr(gSubsteps, 4)
   b2kSetJointTuning 60, 2       -- a sane default joint stiffness (hz, damping)
end applyWorldOptions

on cycleWorldFeel
   local tOrder, tI
   put "default,bouncy,floaty,snappy" into tOrder
   set the itemDelimiter to comma
   put itemOffset(gWorldFeel, tOrder) + 1 into tI
   if tI < 1 or tI > the number of items of tOrder then put 1 into tI
   put item tI of tOrder into gWorldFeel
   applyWorldFeel
   refreshWorldFeelLabel
   put "World feel: " & worldFeelName(gWorldFeel) & "." into gStatus
   updateHud
end cycleWorldFeel

on refreshWorldFeelLabel
   if there is a button "ui_act_worldfeel" then set the label of button "ui_act_worldfeel" to "Feel: " & worldFeelName(gWorldFeel)
end refreshWorldFeelLabel

function gravityModeName pMode
   switch pMode
      case "low"
         return "Low (moon)"
      case "zero"
         return "Zero-G"
      case "reverse"
         return "Reverse"
      case "sideways"
         return "Sideways"
   end switch
   return "Normal"
end gravityModeName

on togglePause
   if gMode is not "run" then
      put "Pause works while the simulation is running - press Run first." into gStatus
      updateHud
      exit togglePause
   end if
   if b2kIsRunning() then
      b2kPause
      put "Paused. Use Step to advance one frame, or Pause again to resume." into gStatus
   else
      b2kResume
      put "Resumed." into gStatus
   end if
   refreshPauseLabel
   updateHud
end togglePause

on stepOnce
   if gMode is not "run" then
      put "Step works while paused during Run - press Run first." into gStatus
      updateHud
      exit stepOnce
   end if
   if b2kIsRunning() then b2kPause        -- stepping implies a paused sim
   b2kStepOnce
   refreshPauseLabel
   put "Stepped one frame." into gStatus
   updateHud
end stepOnce

on refreshPauseLabel
   if there is not a button "ui_act_pause" then exit refreshPauseLabel
   if gMode is "run" and not b2kIsRunning() then set the label of button "ui_act_pause" to "Resume"
   else set the label of button "ui_act_pause" to "Pause"
end refreshPauseLabel

-- Default motor strength by joint kind (torque for hinge/wheel, force for slider).
function motorPowerDefault pKind
   if pKind is "hinge" then return kHingeTorque
   if pKind is "wheel" then return kWheelTorque
   return 1000
end motorPowerDefault

function frictionLabel pV
   if pV is empty then put 0.4 into pV
   if pV <= 0 then return "none (slippery)"
   if pV < 0.3 then return "low"
   if pV < 0.7 then return "medium"
   if pV < 1.2 then return "high"
   return "very high"
end frictionLabel

function gravityLabel pV
   if pV is empty then put 1 into pV
   if pV < -0.3 then return "strong lift"
   if pV < 0.2 then return "gentle lift"
   if pV < 0.7 then return "floaty"
   if pV < 1.3 then return "normal"
   return "heavy"
end gravityLabel

function sizeLabel pV
   if pV is empty then put 1 into pV
   if pV < 0.8 then return "small"
   if pV < 1.3 then return "normal"
   if pV < 1.9 then return "large"
   return "huge"
end sizeLabel

-- Hovering a palette button previews its help; leaving restores the inspector.
on mouseEnter
   local tName
   put the short name of the target into tName
   if "ui_tool_" is in tName then
      hoverTool the long id of the target
      hoverHelp the uToolId of the target
   else if "ui_joint_" is in tName then
      hoverTool the long id of the target
      hoverHelp the uJointId of the target
   end if
end mouseEnter

on mouseLeave
   local tName
   put the short name of the target into tName
   if "ui_tool_" is in tName or "ui_joint_" is in tName then
      highlightAll                              -- restore the correct idle / selected colour
      restoreInspector
   end if
end mouseLeave

-- Lighten a palette button on hover, but only when it is the resting (idle) tool.
-- "Idle" is derived from the current selection, not the pixel colour, so it never
-- mis-reads an accent and never fights the selected / collapsed styling; mouseLeave
-- repaints everything via highlightAll.
on hoverTool pBtn
   if there is not a button pBtn then exit hoverTool
   local tActive
   if the uToolId of pBtn is not empty then
      put (the uToolId of pBtn is gTool and gJointTool is empty) into tActive
   else
      put (the uJointId of pBtn is gJointTool) into tActive
   end if
   if not tActive then set the backgroundColor of pBtn to kColBtnHover
end hoverTool

-- =====================================================================
-- Plain-language labels, tooltips and help text
-- =====================================================================
function niceName pId
   local tNames
   put "drag=Move / Drag" & cr & "box=Box" & cr & "ball=Ball" & cr & "capsule=Capsule" & cr \
         & "poly=Polygon" & cr & "image=Picture" & cr & "anchor=Anchor" & cr & "delete=Delete" & cr \
         & "duplicate=Duplicate" & cr & "multiply=Multiply" & cr & "link=Link" & cr \
         & "balloon=Helium Balloon" & cr & "bomb=Bomb" & cr & "plate=Pressure Plate" & cr \
         & "fan=Fan / Wind" & cr & "magnet=Magnet" & cr & "sensor=Sensor" & cr & "laser=Laser" & cr & "thruster=Thruster" & cr & "goal=Goal Zone" & cr \
         & "platform=Platform" & cr & "ramp=Ramp" & cr & "hill=Hill" & cr & "draw=Draw Terrain" & cr & "car=Car" & cr & "hinge=Hinge Joint" & cr \
         & "weld=Weld Joint" & cr & "servo=Servo Joint" & cr & "rope=Rope Joint" & cr & "slider=Slider Joint" & cr \
         & "wheel=Wheel Joint" & cr & "bridge=Bridge" & cr & "chain=Chain (rope)" into tNames
   local tLine
   set the itemDelimiter to "="
   repeat for each line tLine in tNames
      if item 1 of tLine is pId then
         set the itemDelimiter to comma
         return item 2 of tLine
      end if
   end repeat
   set the itemDelimiter to comma
   return pId
end niceName

-- Small glyphs for the palette. Plain geometric characters that render in the
-- default font everywhere; the text label carries the real meaning.
function toolGlyph pId
   local tGlyphs
   put "drag=::" & cr & "box=[]" & cr & "ball=o" & cr & "capsule=()" & cr & "poly=<>" & cr \
         & "image=#" & cr & "anchor=v" & cr & "delete=x" & cr & "duplicate=[+]" & cr & "multiply=++" & cr & "link=->" & cr & "balloon=O" & cr & "bomb=(*)" & cr \
         & "plate=[-]" & cr & "fan=>" & cr & "magnet=U" & cr & "sensor=(.)" & cr & "laser=/" & cr & "thruster=^" & cr & "goal=|>" & cr \
         & "platform=--" & cr & "ramp=|\" & cr & "hill=/\" & cr & "draw=~" & cr & "car=(o)" & cr & "hinge=-o-" & cr & "weld===" & cr \
         & "servo=(+)" & cr & "rope=~~" & cr & "slider=<->" & cr & "wheel=(O)" & cr & "bridge=n" & cr & "chain=oo" into tGlyphs
   local tLine
   set the itemDelimiter to "="
   repeat for each line tLine in tGlyphs
      if item 1 of tLine is pId then
         set the itemDelimiter to comma
         return item 2 of tLine
      end if
   end repeat
   set the itemDelimiter to comma
   return "*"
end toolGlyph

-- Line 1 = short tooltip; line 2 = the longer inspector explanation.
function toolHelp pId
   switch pId
      case "drag"
         return "Move parts around (places nothing new)." & cr & "Move tool. In Build mode, drag any part to reposition it. In Run mode, grab and fling parts with the mouse."
      case "box"
         return "Drop a solid box that falls and stacks." & cr & "A box is a solid rectangle. It falls, stacks and tumbles - great for crates, walls and dominoes."
      case "ball"
         return "Drop a ball that rolls and bounces." & cr & "A ball rolls and bounces. Handy for wheels, marbles, and things that trigger pressure plates."
      case "capsule"
         return "Drop a rounded bar (a capsule)." & cr & "A capsule is a bar with rounded ends. It rolls on its ends - useful for rollers, limbs and levers."
      case "poly"
         return "Drop a six-sided block." & cr & "A polygon is a chunky many-sided block. It stacks and tumbles like a box with more character."
      case "image"
         return "Use your own picture as an object." & cr & "Pick an image file and it becomes a physical block that tumbles and spins like any other part."
      case "anchor"
         return "Place a fixed point that never moves." & cr & "An anchor is pinned to the world. Attach joints to it to hold things up - perfect as a motor mount or a pivot."
      case "delete"
         return "Remove a part you click on." & cr & "Delete tool. Click any part to remove it, along with any joints attached to it."
      case "duplicate"
         return "Copy a part you click on." & cr & "Duplicate tool. Click any part to drop an identical copy - same size, colour and settings - then drag it where you want."
      case "multiply"
         return "Make many copies of a part at once." & cr & "Multiply tool. Click any part and choose how many copies to make; they drop into a tidy grid, each identical to the original. Great for crates, dominoes and bricks."
      case "link"
         return "Wire a trigger to a bomb." & cr & "Link tool. Click a plate or sensor, then click a bomb - an amber wire ties that trigger to that bomb. An unwired trigger still sets off everything."
      case "balloon"
         return "A helium balloon that floats upward." & cr & "A balloon rises on its own. Tie it to a part with a Rope joint to lift that part. A nearby bomb blast pops it."
      case "bomb"
         return "A bomb that explodes and flings parts." & cr & "Detonates on a hard hit, a pressure-plate signal, or a Run-fuse (toggle it below). The blast flings nearby parts outward."
      case "plate"
         return "A switch that triggers when weighed down." & cr & "A pressure plate. When a part rests on it, it fires a signal: any bombs go off and all motors switch on or off. Build chain reactions with it!"
      case "sensor"
         return "A trigger zone that fires when entered." & cr & "A sensor is a non-solid zone. The moment a part enters, it fires like a pressure plate: bombs go off and motors switch. Great for tripwires and gates."
      case "fan"
         return "A wind zone that blows parts along." & cr & "A fan pushes any part inside its zone in the arrow's direction. Set the direction and strength in the inspector. No body - parts pass through it."
      case "magnet"
         return "A magnet that pulls parts toward it." & cr & "A magnet attracts nearby parts (or repels them). Set attract/repel, strength and reach in the inspector. No body - parts pass through it."
      case "laser"
         return "A ray that draws a beam to whatever it hits." & cr & "A laser casts a ray and draws its beam to the first thing it strikes - walls count. Set the angle in the inspector; select it while running to read the hit distance."
      case "thruster"
         return "A self-propelled rocket that thrusts on Run." & cr & "A thruster drives itself: an ignition kick on Run, then a steady push. Set angle and power in the inspector; Aim makes it steer with the body. A wire can switch it."
      case "goal"
         return "A target zone - reach it to win." & cr & "The finish line for a puzzle. Press Play: get a movable part inside every goal at once to solve it. Resize it in the inspector; parts pass through it."
      case "platform"
         return "Place a solid ledge that never moves." & cr & "A platform is fixed scenery - a solid ledge that stays put. Rest parts on it, build floors and steps, or rotate it into an angled shelf."
      case "ramp"
         return "Place a fixed slope for rolling and sliding." & cr & "A ramp is a fixed wedge. Balls roll down it and parts slide along it. Rotate it for any incline and raise its grip to slow the slide - great for launches and runs."
      case "hill"
         return "Place a smooth rolling mound." & cr & "A hill is a smooth chain mound - parts roll over it without catching. Narrow makes one dome, wide makes rolling hills; size and rotate it to shape the land."
      case "draw"
         return "Draw your own ground line." & cr & "Press and drag to sketch a ground contour - bumps, valleys, ramps. On release it becomes solid terrain. Drag to move it; delete and redraw to reshape."
      case "car"
         return "Drop a ready-made motor car." & cr & "A complete car: a chassis on two sprung, motorised wheels - press Run and it drives. Drag the body to move it all; tune each wheel in the joint inspector."
      case "hinge"
         return "Pin two parts so they rotate." & cr & "A hinge is a pin two parts spin around - like an axle or a pendulum. Pin to an Anchor or empty space, switch Motor on, and it drives itself."
      case "weld"
         return "Glue two parts rigidly together." & cr & "A weld locks two parts as one solid piece - they keep their relative position and angle."
      case "servo"
         return "A powered hold between two parts." & cr & "A servo holds one part at a position and angle relative to another, giving under load and springing back - a soft weld. Click part A, then part B."
      case "rope"
         return "Link two parts with a rope." & cr & "A rope keeps two parts from drifting further apart than its length. They can still swing and fall closer together."
      case "slider"
         return "Let one part slide along a line." & cr & "A slider lets one part slide in a straight line relative to another - like a piston or a drawer."
      case "wheel"
         return "Add a springy, spinning wheel." & cr & "A wheel joint carries a wheel with springy suspension and lets it spin freely - switch Motor on to drive a vehicle."
      case "bridge"
         return "Span a plank bridge between two points." & cr & "Bridge tool. Click a part (or empty space), then a second point: a row of hinged planks spans the gap and sags under weight. Anchor the ends to Anchors or the world."
      case "chain"
         return "Hang a flexible segmented rope." & cr & "Click two points and a rope of small hinged links drapes between them. It bends, coils and swings - great for swings and tethers."
   end switch
   return niceName(pId) & cr & "Select this tool, then click the stage."
end toolHelp

function actionHelp pId
   switch pId
      case "play"
         return "Play the puzzle: run it and try to get a part into every goal zone."
      case "mode"
         return "Switch between Build (arrange) and Run (simulate)."
      case "reset"
         return "Put every part back where it was when you last pressed Run."
      case "clear"
         return "Remove everything and start with an empty stage."
      case "save"
         return "Save this contraption to a file."
      case "load"
         return "Open a contraption you saved earlier."
      case "recipes"
         return "Load a ready-made example, or run a stress test."
      case "info"
         return "Show the quick how-to guide again."
      case "motor"
         return "When on, new Hinge and Wheel joints get a motor that drives them."
      case "bouncy"
         return "When on, new parts are springy and bounce."
      case "spddn"
         return "Slower motor speed for new motorised joints."
      case "spdup"
         return "Faster motor speed for new motorised joints."
      case "recipeclose"
         return "Close this menu."
      case "filterclose"
         return "Close the collision filter."
      case "images"
         return "Your image library - import pictures (with a collision shape) and reuse them."
      case "worldadv"
         return "Advanced world solver settings (CCD, sleeping, sub-steps...)."
      case "worldclose"
         return "Close the world settings."
   end switch
   if char 1 to 5 of pId is "wopt_" then return "Toggle this world solver setting."
   if char 1 to 9 of pId is "prop_inc_" then return "Increase this value."
   if char 1 to 9 of pId is "prop_dec_" then return "Decrease this value."
   if char 1 to 9 of pId is "filt_cat_" then return "Toggle whether this part is on channel " & (char 10 to -1 of pId) & "."
   if char 1 to 10 of pId is "filt_mask_" then return "Toggle whether this part collides with channel " & (char 11 to -1 of pId) & "."
   return niceName(pId)
end actionHelp

-- Put a clear tooltip on every interactive control.
on applyTooltips
   local tI, tName, tCtrl
   repeat with tI = 1 to the number of controls of this card
      put the long id of control tI of this card into tCtrl
      put the short name of tCtrl into tName
      if "ui_tool_" is in tName then set the tooltip of tCtrl to line 1 of toolHelp(the uToolId of tCtrl)
      else if "ui_joint_" is in tName then set the tooltip of tCtrl to line 1 of toolHelp(the uJointId of tCtrl)
      else if "ui_act_" is in tName then set the tooltip of tCtrl to actionHelp(the uActId of tCtrl)
   end repeat
end applyTooltips

function dirName pDeg
   switch pDeg
      case 0
         return "Right"
      case 90
         return "Down"
      case 180
         return "Left"
   end switch
   return "Up"
end dirName

function magName pPol
   if pPol < 0 then return "Repel (push away)"
   return "Attract (pull in)"
end magName

function yesNo pFlag
   if pFlag is true then return "Yes"
   return "No"
end yesNo

function bounceLabel pV
   if pV is empty or pV <= 0 then return "none"
   if pV < 0.3 then return "low"
   if pV < 0.6 then return "medium"
   return "high"
end bounceLabel

function weightLabel pCtrl
   local tD
   put the uDensity of pCtrl into tD
   if tD is empty then put 1 into tD
   if tD <= 0.4 then return "very light"
   if tD <= 0.8 then return "light"
   if tD < 1.5 then return "normal"
   if tD < 2.5 then return "heavy"
   return "very heavy"
end weightLabel

-- =====================================================================
-- Recipes menu (ready-made examples) + stress test
-- =====================================================================
on buildRecipesMenu
   local tWide, tHigh, tL, tT, tW, tH, tBy
   put the width of this card into tWide
   put the height of this card into tHigh
   put 420 into tW
   put 528 into tH
   put (tWide - tW) div 2 into tL
   put (tHigh - tH) div 2 into tT
   makeBar "ui_recipescrim", 0, 0, tWide, tHigh, "10,11,15"
   set the blendLevel of graphic "ui_recipescrim" to 62
   set the uRecipeMenu of graphic "ui_recipescrim" to true
   makeBar "ui_recipebg", tL, tT, tL + tW, tT + tH, "34,38,48"
   set the uRecipeMenu of graphic "ui_recipebg" to true
   makeLabel "ui_recipe_title", tL + 18, tT + 14, tL + tW - 18, tT + 38, "Example Machines", 15, "236,238,245", true
   set the uRecipeMenu of field "ui_recipe_title" to true
   put tT + 46 into tBy
   put recipeCategory("Puzzles (press Play)", "chainpuzzle", \
         "Demolish & Deliver", tL, tW, tBy) into tBy
   put recipeCategory("Launchers", "catapult,cannon,trebuchet,wreckingball", \
         "Catapult,Cannon,Trebuchet,Wrecking Ball", tL, tW, tBy) into tBy
   put recipeCategory("Machines", "crane,cart,fantower,magnetcatch,balloonlift", \
         "Crane,Motor Cart,Fan Tower,Magnet Catch,Balloon Lift", tL, tW, tBy) into tBy
   put recipeCategory("Chain Reactions", "platebomb,dominoes", \
         "Plate -> Bomb,Domino Run", tL, tW, tBy) into tBy
   put recipeCategory("Toys & Tests", "swing,cradle,terrainrun,stress", \
         "Pendulum Swing,Newton's Cradle,Terrain Run,Stress (+" & kStressBatch & ")", tL, tW, tBy) into tBy
   makeAction "recipeclose", "Close", tL + tW - 92, tBy + 2, 76, 26
   set the uRecipeMenu of button "ui_act_recipeclose" to true
   hideRecipesMenu
end buildRecipesMenu

-- Lay out one labelled category of recipe buttons in two columns. Returns the
-- next free Y. pIds / pLabels are comma lists; the headers and buttons all carry
-- uRecipeMenu so the whole gallery shows/hides as one.
function recipeCategory pTitle, pIds, pLabels, pL, pW, pY
   local tHdr, tI, tN, tColW, tBx
   put "ui_reccat_" & the number of controls of this card into tHdr   -- a unique, name-safe id
   makeLabel tHdr, pL + 18, pY, pL + pW - 18, pY + 18, pTitle, 11, "150,196,232", true
   set the uRecipeMenu of field tHdr to true
   add 22 to pY
   set the itemDelimiter to comma
   put the number of items of pIds into tN
   put (pW - 44) div 2 into tColW
   repeat with tI = 1 to tN
      if (tI - 1) mod 2 is 0 then put pL + 18 into tBx
      else put pL + 18 + tColW + 8 into tBx
      makeRecipeBtn (item tI of pIds), (item tI of pLabels), tBx, pY, tColW
      if (tI mod 2 is 0) or (tI is tN) then add 30 to pY
   end repeat
   return pY + 8
end recipeCategory

on makeRecipeBtn pId, pLabel, pX, pY, pW
   makeAction pId, pLabel, pX, pY, pW, 28
   set the uRecipeMenu of button ("ui_act_" & pId) to true
end makeRecipeBtn

on toggleRecipesMenu
   if there is a graphic "ui_recipebg" and the visible of graphic "ui_recipebg" then hideRecipesMenu
   else showRecipesMenu
end toggleRecipesMenu

on showRecipesMenu
   setRecipeVisible true
end showRecipesMenu

on hideRecipesMenu
   setRecipeVisible false
end hideRecipesMenu

-- Show/hide the whole recipes panel. Collect the controls FIRST, then change
-- them: setting the layer mid-loop reorders controls and would skip some.
on setRecipeVisible pFlag
   local tI, tCtrl, tList
   if pFlag then enterModalView
   else exitModalView
   put empty into tList
   repeat with tI = 1 to the number of controls of this card
      put the long id of control tI of this card into tCtrl
      if the uRecipeMenu of tCtrl is true then put tCtrl & cr after tList
   end repeat
   repeat for each line tCtrl in tList
      set the visible of tCtrl to pFlag
      if pFlag then set the layer of tCtrl to top
   end repeat
end setRecipeVisible

-- =====================================================================
-- Collision-filter popup: two rows of eight channel toggles (category /
-- mask). Built once with the chrome (hidden), mirroring the recipes menu.
-- =====================================================================
on buildFilterPanel
   local tWide, tHigh, tW, tH, tL, tT, tI, tBx, tColW, tRowY
   put the width of this card into tWide
   put the height of this card into tHigh
   put 360 into tW
   put 286 into tH
   put (tWide - tW) div 2 into tL
   put (tHigh - tH) div 2 into tT
   makeBar "ui_filterscrim", 0, 0, tWide, tHigh, "10,11,15"
   set the blendLevel of graphic "ui_filterscrim" to 62
   set the uFilterMenu of graphic "ui_filterscrim" to true
   makeBar "ui_filterbg", tL, tT, tL + tW, tT + tH, "34,38,48"
   set the uFilterMenu of graphic "ui_filterbg" to true
   makeLabel "ui_filter_title", tL + 18, tT + 14, tL + tW - 18, tT + 36, "Collision Filter", 15, "236,238,245", true
   set the uFilterMenu of field "ui_filter_title" to true
   makeLabel "ui_filter_sub", tL + 18, tT + 38, tL + tW - 18, tT + 58, "", 11, "150,196,232", false
   set the uFilterMenu of field "ui_filter_sub" to true
   -- "On channels" row
   makeLabel "ui_filter_cathdr", tL + 18, tT + 66, tL + tW - 18, tT + 84, "On channels (what this part is):", 11, "210,214,224", true
   set the uFilterMenu of field "ui_filter_cathdr" to true
   put (tW - 36 - 7 * 6) div kFilterChannels into tColW
   put tT + 88 into tRowY
   repeat with tI = 1 to kFilterChannels
      put tL + 18 + (tI - 1) * (tColW + 6) into tBx
      makeAction ("filt_cat_" & tI), tI, tBx, tRowY, tColW, 26
      set the uFilterMenu of button ("ui_act_filt_cat_" & tI) to true
   end repeat
   -- "Collides with" row
   makeLabel "ui_filter_maskhdr", tL + 18, tT + 124, tL + tW - 18, tT + 142, "Collides with channels:", 11, "210,214,224", true
   set the uFilterMenu of field "ui_filter_maskhdr" to true
   put tT + 146 into tRowY
   repeat with tI = 1 to kFilterChannels
      put tL + 18 + (tI - 1) * (tColW + 6) into tBx
      makeAction ("filt_mask_" & tI), tI, tBx, tRowY, tColW, 26
      set the uFilterMenu of button ("ui_act_filt_mask_" & tI) to true
   end repeat
   makeLabel "ui_filter_help", tL + 18, tT + 182, tL + tW - 18, tT + 244, \
         "Two parts collide only when each is on a channel the other collides with. Tip: keep channel 1 on in the lower row so parts still land on the ground.", \
         11, "150,154,166", false
   set the uFilterMenu of field "ui_filter_help" to true
   makeAction "filterclose", "Close", tL + tW - 92, tT + tH - 34, 76, 26
   set the uFilterMenu of button "ui_act_filterclose" to true
   setFilterVisible false
end buildFilterPanel

-- Open the panel for a part: remember it, paint the toggles, show the panel.
on openFilterPanel pCtrl
   if pCtrl is empty then exit openFilterPanel
   put pCtrl into gFilterPart
   refreshFilterPanel
   setFilterVisible true
end openFilterPanel

on hideFilterPanel
   put empty into gFilterPart
   setFilterVisible false
end hideFilterPanel

-- Light each toggle to match the part's current category / mask channels.
on refreshFilterPanel
   local tI, tCats, tMask
   if gFilterPart is empty then exit refreshFilterPanel
   if there is not gFilterPart then
      hideFilterPanel
      exit refreshFilterPanel
   end if
   if there is a field "ui_filter_sub" then
      put ("Editing: " & niceName(the uKind of gFilterPart)) into field "ui_filter_sub"
   end if
   put "," & sortedChannels(partCategories(gFilterPart)) & "," into tCats
   put "," & sortedChannels(partMaskChannels(gFilterPart)) & "," into tMask
   repeat with tI = 1 to kFilterChannels
      setToggle ("ui_act_filt_cat_" & tI), ("," & tI & "," is in tCats)
      setToggle ("ui_act_filt_mask_" & tI), ("," & tI & "," is in tMask)
   end repeat
end refreshFilterPanel

-- A click on a category/mask channel toggle: flip it, apply, repaint. The action
-- id is "filt_cat_<n>" or "filt_mask_<n>"; split off the row and the channel.
on handleFilterToggle pId
   local tRest, tWhich, tIdx
   if gFilterPart is empty then exit handleFilterToggle
   if there is not gFilterPart then
      hideFilterPanel
      exit handleFilterToggle
   end if
   put char 6 to -1 of pId into tRest           -- "cat_3" or "mask_3"
   set the itemDelimiter to "_"
   put item 1 of tRest into tWhich              -- "cat" | "mask"
   put item 2 of tRest into tIdx                -- the channel number
   set the itemDelimiter to comma
   if tIdx is not a number then exit handleFilterToggle
   if tWhich is "cat" then
      set the uOnChans of gFilterPart to toggleChannel(partCategories(gFilterPart), tIdx)
   else
      set the uHitChans of gFilterPart to toggleChannel(partMaskChannels(gFilterPart), tIdx)
   end if
   applyPartFilter gFilterPart
   refreshFilterPanel
   if gSelPart is gFilterPart then showPartInspector gFilterPart
end handleFilterToggle

on setFilterVisible pFlag
   local tI, tCtrl, tList
   if pFlag then enterModalView
   else exitModalView
   put empty into tList
   repeat with tI = 1 to the number of controls of this card
      put the long id of control tI of this card into tCtrl
      if the uFilterMenu of tCtrl is true then put tCtrl & cr after tList
   end repeat
   repeat for each line tCtrl in tList
      set the visible of tCtrl to pFlag
      if pFlag then set the layer of tCtrl to top
   end repeat
end setFilterVisible

-- =====================================================================
-- World / Advanced popup: the solver toggles the Feel presets don't cover
-- (continuous collision, sleeping, warm-starting, sub-steps). Built once
-- with the chrome, hidden, like the recipes and filter popups.
-- =====================================================================
on buildWorldPanel
   local tWide, tHigh, tW, tH, tL, tT, tRy
   put the width of this card into tWide
   put the height of this card into tHigh
   put 340 into tW
   put 250 into tH
   put (tWide - tW) div 2 into tL
   put (tHigh - tH) div 2 into tT
   makeBar "ui_worldscrim", 0, 0, tWide, tHigh, "10,11,15"
   set the blendLevel of graphic "ui_worldscrim" to 62
   set the uWorldMenu of graphic "ui_worldscrim" to true
   makeBar "ui_worldbg", tL, tT, tL + tW, tT + tH, "34,38,48"
   set the uWorldMenu of graphic "ui_worldbg" to true
   makeLabel "ui_world_title", tL + 18, tT + 14, tL + tW - 18, tT + 36, "World / Advanced", 15, "236,238,245", true
   set the uWorldMenu of field "ui_world_title" to true
   put tT + 48 into tRy
   makeAction "wopt_ccd", "Continuous collision: off", tL + 18, tRy, tW - 36, 28
   set the uWorldMenu of button "ui_act_wopt_ccd" to true
   add 36 to tRy
   makeAction "wopt_sleep", "Sleeping: on", tL + 18, tRy, tW - 36, 28
   set the uWorldMenu of button "ui_act_wopt_sleep" to true
   add 36 to tRy
   makeAction "wopt_warm", "Warm starting: on", tL + 18, tRy, tW - 36, 28
   set the uWorldMenu of button "ui_act_wopt_warm" to true
   add 36 to tRy
   makeAction "wopt_sub", "Solver sub-steps: 4", tL + 18, tRy, tW - 36, 28
   set the uWorldMenu of button "ui_act_wopt_sub" to true
   makeAction "worldclose", "Close", tL + tW - 92, tT + tH - 34, 76, 26
   set the uWorldMenu of button "ui_act_worldclose" to true
   setWorldVisible false
end buildWorldPanel

on openWorldPanel
   refreshWorldPanel
   setWorldVisible true
end openWorldPanel

on hideWorldPanel
   setWorldVisible false
end hideWorldPanel

-- Paint each toggle to its current state (and light the ON ones blue).
on refreshWorldPanel
   if there is a button "ui_act_wopt_ccd" then set the label of button "ui_act_wopt_ccd" to "Continuous collision: " & onOff(gCCD)
   if there is a button "ui_act_wopt_sleep" then set the label of button "ui_act_wopt_sleep" to "Sleeping: " & onOff(gSleepOn)
   if there is a button "ui_act_wopt_warm" then set the label of button "ui_act_wopt_warm" to "Warm starting: " & onOff(gWarmStart)
   if there is a button "ui_act_wopt_sub" then set the label of button "ui_act_wopt_sub" to "Solver sub-steps: " & numOr(gSubsteps, 4)
   setToggle "ui_act_wopt_ccd", (gCCD is true)
   setToggle "ui_act_wopt_sleep", (gSleepOn is true)
   setToggle "ui_act_wopt_warm", (gWarmStart is true)
end refreshWorldPanel

-- A click on a world-option toggle: flip it, push it live, repaint.
on handleWorldToggle pId
   switch pId
      case "wopt_ccd"
         put not (gCCD is true) into gCCD
         break
      case "wopt_sleep"
         put not (gSleepOn is true) into gSleepOn
         break
      case "wopt_warm"
         put not (gWarmStart is true) into gWarmStart
         break
      case "wopt_sub"
         put numOr(gSubsteps, 4) + 1 into gSubsteps
         if gSubsteps > 8 then put 1 into gSubsteps
         break
   end switch
   if gMode is "run" then applyWorldOptions      -- take effect immediately while running
   refreshWorldPanel
end handleWorldToggle

on setWorldVisible pFlag
   local tI, tCtrl, tList
   if pFlag then enterModalView
   else exitModalView
   put empty into tList
   repeat with tI = 1 to the number of controls of this card
      put the long id of control tI of this card into tCtrl
      if the uWorldMenu of tCtrl is true then put tCtrl & cr after tList
   end repeat
   repeat for each line tCtrl in tList
      set the visible of tCtrl to pFlag
      if pFlag then set the layer of tCtrl to top
   end repeat
end setWorldVisible

-- A balloon hauls a box up by a rope.
on buildRecipeBalloonLift
   if gMode is "run" then toggleMode
   clearAll
   local tCx, tBaseY, tBox, tBalloon
   put (gArenaL + gArenaR) div 2 into tCx
   put gArenaB - 36 into tBaseY
   put placeBox(tCx, tBaseY, 42, 42, "120,200,232") into tBox
   b2kSetDensity tBox, 0.1               -- light enough that one balloon's buoyancy (0.6g) actually lifts it
   set the uDensity of tBox to 0.1
   put placeBalloon(tCx, tBaseY - 150) into tBalloon
   get connectJoint("rope", tBalloon, tBox, tCx, tBaseY - 80, 0)
   renderBuild
   put "Balloon Lift - press Run: the balloon rises and hauls the box up by its rope." into gStatus
   updateHud
end buildRecipeBalloonLift

-- A dropped ball lands on a plate, which sets off a bomb under a tower.
on buildRecipePlateBomb
   if gMode is "run" then toggleMode
   clearAll
   local tCx, tPlateX, tTowerX, tI, tBomb, tPlate
   put (gArenaL + gArenaR) div 2 into tCx
   put tCx - 130 into tPlateX
   put tCx + 120 into tTowerX
   put placePlate(tPlateX, gArenaB - 8) into tPlate
   get placeBall(tPlateX, gArenaT + 60, 40, "232,182,92")
   put placeBomb(tTowerX, gArenaB - 28) into tBomb
   set the uFuseOnRun of tBomb to false        -- this bomb fires from the PLATE's wire, not its own fuse
   addWire tPlate, tBomb                        -- the trigger link (this was missing): plate -> bomb
   repeat with tI = 1 to 4
      get placeBox(tTowerX, gArenaB - 66 - tI * 34, 46, 30, "214,92,92")
   end repeat
   renderBuild
   put "Plate -> Bomb - press Run: the ball lands on the plate, the bomb fires, the tower topples." into gStatus
   updateHud
end buildRecipePlateBomb

-- A complete, Play-able puzzle: the ball rolls over a plate that is wired to a
-- demolition bomb; the bomb clears the wall, and the ball carries on into the
-- goal. Shows the whole loop (launch + plate + wire + demolish + goal) in one.
on buildRecipeChainPuzzle
   if gMode is "run" then toggleMode
   clearAll
   local tBall, tPlate, tBomb, tGoal, tI, tWx
   put gArenaL + 440 into tWx
   -- the payload, launched to the right on Play
   put placeBall(gArenaL + 70, gArenaB - 34, 34, "232,182,92") into tBall
   set the uLaunchSpeed of tBall to 820
   set the uLaunchDir of tBall to 0
   set the uDensity of tBall to 1.6
   b2kSetDensity tBall, 1.6
   -- a trigger plate it rolls over first
   put placePlate(gArenaL + 210, gArenaB - 8) into tPlate
   -- a crate wall blocking the way
   repeat with tI = 0 to 3
      get placeBox(tWx, gArenaB - 26 - tI * 30, 40, 28, "200,120,80")
   end repeat
   -- a demolition bomb at the wall, fired only by the plate (not its own fuse)
   put placeBomb(tWx, gArenaB - 26) into tBomb
   set the uFuseOnRun of tBomb to false
   set the uDestroys of tBomb to true
   set the uBlastRadius of tBomb to 190
   set the uBlastPower of tBomb to 900
   addWire tPlate, tBomb
   -- the goal, past the cleared wall
   put placeGoal(gArenaL + 650, gArenaB - 64) into tGoal
   set the uGoalScale of tGoal to 1.3
   drawGoalShape tGoal
   renderBuild
   put "Demolish & Deliver - press Play! The ball trips the plate, the bomb clears the wall, and it rolls into the goal (nudge it if it stalls)." into gStatus
   updateHud
end buildRecipeChainPuzzle

-- An upward fan juggles a few light balls.
on buildRecipeFanTower
   if gMode is "run" then toggleMode
   clearAll
   local tCx, tFan, tI
   put (gArenaL + gArenaR) div 2 into tCx
   put placeFan(tCx, gArenaB - 84) into tFan
   set the uFanForce of tFan to 1800
   repeat with tI = 1 to 3
      get placeBall(tCx, gArenaT + 40 + tI * 46, 36, "84,206,142")
   end repeat
   renderBuild
   put "Fan Tower - press Run: the upward wind catches the balls and juggles them." into gStatus
   updateHud
end buildRecipeFanTower

-- A magnet gathers scattered balls.
on buildRecipeMagnetCatch
   if gMode is "run" then toggleMode
   clearAll
   local tCx, tCy, tMag, tI, tLoX, tHiX, tLoY, tHiY
   put (gArenaL + gArenaR) div 2 into tCx
   put (gArenaT + gArenaB) div 2 into tCy
   put placeMagnet(tCx, tCy) into tMag
   set the uMagRange of tMag to 360
   -- Scatter the balls INSIDE the magnet's reach (clamped to the arena), so every
   -- one is actually caught -- not just whichever happened to land within range.
   put max(gArenaL + 40, tCx - 280) into tLoX
   put min(gArenaR - 40, tCx + 280) into tHiX
   put max(gArenaT + 40, tCy - 170) into tLoY
   put min(gArenaB - 50, tCy + 170) into tHiY
   repeat with tI = 1 to 6
      get placeBall(rnd(tLoX, tHiX), rnd(tLoY, tHiY), 30, "206,124,206")
   end repeat
   renderBuild
   put "Magnet Catch - press Run: the magnet pulls the scattered balls toward it." into gStatus
   updateHud
end buildRecipeMagnetCatch

-- A heavy block drops on one arm of a hinged lever and flings a ball off the other.
on buildRecipeCatapult
   if gMode is "run" then toggleMode
   clearAll
   local tCx, tBaseY, tFulcrum, tArm, tBall, tWeight
   put (gArenaL + gArenaR) div 2 into tCx
   put gArenaB - 70 into tBaseY
   put placeAnchor(tCx, tBaseY - 16) into tFulcrum   -- pivot ON the arm centreline; was 16px below its CG (an unstable inverted pivot that tipped the arm over before the weight landed)
   put placeBox(tCx, tBaseY - 16, 200, 14, "180,150,90") into tArm
   set the uDensity of tArm to 0.6
   b2kSetDensity tArm, 0.6
   get connectJoint("hinge", tArm, tFulcrum, tCx, tBaseY - 16, 0)
   put placeBall(tCx - 84, tBaseY - 39, 30, "232,182,92") into tBall   -- rests on the left arm
   put placeBox(tCx + 78, tBaseY - 110, 54, 54, "214,92,92") into tWeight   -- drops a short, fast way onto the right arm
   set the uDensity of tWeight to 3.4
   b2kSetDensity tWeight, 3.4
   renderBuild
   put "Catapult - press Run: the heavy block drops on the right arm and flings the ball off the left." into gStatus
   updateHud
end buildRecipeCatapult

-- A horizontal cannon: a static carriage + barrel (axis-aligned, so the static
-- render is exact - no rotated-static-body gotcha), a heavy ball that fires up
-- the field on Run via the launch system, and a crate stack to knock down. The
-- ball + barrel share a collision layer, so the ball slips clear of the barrel
-- instead of snagging on it as it launches.
on buildRecipeCannon
   if gMode is "run" then toggleMode
   clearAll
   local tX, tBaseY, tBarrel, tBase, tBall, tI, tStackX
   put gArenaL + 80 into tX
   put gArenaB - 96 into tBaseY
   put placeBox(tX + 18, tBaseY + 34, 66, 30, "92,70,52") into tBase     -- carriage
   set the uBodyType of tBase to "static"
   b2kSetType tBase, "static"
   put placeBox(tX + 30, tBaseY, 96, 34, "70,74,86") into tBarrel        -- barrel
   set the uBodyType of tBarrel to "static"
   b2kSetType tBarrel, "static"
   set the uLayer of tBarrel to 1
   applyCollisionLayer tBarrel
   put placeBall(tX + 88, tBaseY, 26, "40,42,50") into tBall             -- cannonball at the muzzle
   set the uDensity of tBall to 2.6
   b2kSetDensity tBall, 2.6
   set the uLaunchSpeed of tBall to 1000
   set the uLaunchDir of tBall to 8                                       -- a near-flat shot, so it strikes the stack instead of arcing over it
   set the uLayer of tBall to 1
   applyCollisionLayer tBall
   -- Put the stack a fixed distance downrange (inside the flat shot's range), not
   -- at the far wall - otherwise on a wide stage the ball drops short or sails past.
   put min(tX + 688, gArenaR - 110) into tStackX
   repeat with tI = 0 to 4                                                -- crate stack
      get placeBox(tStackX, gArenaB - 22 - tI * 30, 46, 28, "200,120,80")
   end repeat
   renderBuild
   put "Cannon - press Run: the ball fires across the field. Knock the crate stack down!" into gStatus
   updateHud
end buildRecipeCannon

-- A trebuchet: a long arm hinged off-centre, a heavy counterweight welded to the
-- short end and a ball resting on the long end. On Run the weight drops, the arm
-- whips round and flings the ball downfield. (Gravity-driven - no motor.)
on buildRecipeTrebuchet
   if gMode is "run" then toggleMode
   clearAll
   local tCx, tBaseY, tPivot, tArm, tWeight, tBall
   put (gArenaL + gArenaR) div 2 - 70 into tCx
   put gArenaB - 150 into tBaseY
   put placeAnchor(tCx, tBaseY) into tPivot
   put placeBox(tCx + 44, tBaseY, 264, 12, "180,150,90") into tArm
   set the uDensity of tArm to 0.5
   b2kSetDensity tArm, 0.5
   get connectJoint("hinge", tArm, tPivot, tCx, tBaseY, 0)
   put placeBox(tCx - 80, tBaseY + 12, 56, 56, "214,92,92") into tWeight
   set the uDensity of tWeight to 4
   b2kSetDensity tWeight, 4
   get connectJoint("weld", tWeight, tArm)
   put placeBall(tCx + 162, tBaseY - 19, 26, "232,182,92") into tBall   -- rests ON TOP of the long arm so the whip-up flings it (was below the arm)
   set the uDensity of tBall to 0.8
   b2kSetDensity tBall, 0.8
   renderBuild
   put "Trebuchet - press Run: the counterweight drops and the long arm flings the ball downfield." into gStatus
   updateHud
end buildRecipeTrebuchet

-- A crane: a static mast, a motorised jib that swings, and a load hung from the
-- jib end on a rope so it trails and sways as the jib turns.
on buildRecipeCrane
   if gMode is "run" then toggleMode
   clearAll
   local tX, tBaseY, tTop, tMast, tPivot, tJib, tLoad
   put gArenaL + 150 into tX
   put gArenaB - 30 into tBaseY
   put tBaseY - 210 into tTop
   put placeBox(tX, tBaseY - 110, 26, 220, "92,98,112") into tMast
   set the uBodyType of tMast to "static"
   b2kSetType tMast, "static"
   put placeAnchor(tX + 13, tTop) into tPivot                    -- pivot at the mast's right edge
   put placeBox(tX + 118, tTop, 210, 14, "180,150,90") into tJib -- jib cantilevers RIGHT from the pivot, clear of the mast (its left end used to overlap the mast and jam the swing)
   set the uDensity of tJib to 0.4
   b2kSetDensity tJib, 0.4
   get connectJoint("hinge", tJib, tPivot, tX + 13, tTop, 26)    -- 26 deg/s motor swings the jib
   put placeBall(tX + 200, tTop + 92, 34, "232,182,92") into tLoad
   set the uDensity of tLoad to 2
   b2kSetDensity tLoad, 2
   get connectJoint("rope", tJib, tLoad)
   renderBuild
   put "Crane - press Run: the motorised jib swings and the roped load trails and sways behind it." into gStatus
   updateHud
end buildRecipeCrane

-- A wrecking ball: a static gantry, a heavy ball hung on a rope and given a
-- sideways shove on Run so it swings into a brick wall and knocks it down.
on buildRecipeWreckingBall
   if gMode is "run" then toggleMode
   clearAll
   local tX, tTop, tMast, tBeam, tPivot, tBall, tWallX, tI
   put gArenaL + 130 into tX
   put gArenaB - 250 into tTop
   -- A mast with a beam cantilevered to the right; the ball hangs off the beam end and
   -- swings RIGHT into the wall. (The old gantry pinned the ball between two legs, so its
   -- short arc never reached the far wall.)
   put placeBox(tX, (gArenaB + tTop) div 2, 22, gArenaB - tTop, "92,98,112") into tMast
   set the uBodyType of tMast to "static"
   b2kSetType tMast, "static"
   put placeBox(tX + 100, tTop, 200, 16, "92,98,112") into tBeam
   set the uBodyType of tBeam to "static"
   b2kSetType tBeam, "static"
   put placeAnchor(tX + 188, tTop) into tPivot
   put placeBall(tX + 188, tTop + 150, 44, "60,64,74") into tBall   -- heavy ball roped to the beam end
   set the uDensity of tBall to 5
   b2kSetDensity tBall, 5
   get connectJoint("rope", tPivot, tBall)
   set the uLaunchSpeed of tBall to 600
   set the uLaunchDir of tBall to 0                         -- shove right, into the wall
   put tX + 300 into tWallX                                  -- inside the ball's forward swing reach
   repeat with tI = 0 to 5
      get placeBox(tWallX, gArenaB - 22 - tI * 30, 60, 28, "200,120,80")
   end repeat
   renderBuild
   put "Wrecking Ball - press Run: the ball swings off the beam into the brick wall and smashes it down." into gStatus
   updateHud
end buildRecipeWreckingBall

-- Five equal pendulums in a touching row; the raised end ball kicks the chain.
on buildRecipeCradle
   if gMode is "run" then toggleMode
   clearAll
   local tCx, tTopY, tI, tX, tBall, tAnchor, tDiam, tLen
   put (gArenaL + gArenaR) div 2 into tCx
   put gArenaT + 70 into tTopY
   put 38 into tDiam
   put 150 into tLen
   repeat with tI = 1 to 5
      put tCx + (tI - 3) * tDiam into tX
      put placeAnchor(tX, tTopY) into tAnchor
      if tI is 1 then
         put placeBall(tX - 106, tTopY + 106, tDiam, "120,200,232") into tBall   -- raised 45 deg, same rope length
      else
         put placeBall(tX, tTopY + tLen, tDiam, "120,200,232") into tBall
      end if
      set the uBounce of tBall to 0.92         -- near-elastic, so momentum kicks the far ball out
      b2kSetBounce tBall, 0.92
      set the uDensity of tBall to 2
      b2kSetDensity tBall, 2
      get connectJoint("rope", tBall, tAnchor, tX, tTopY, 0)
   end repeat
   renderBuild
   put "Newton's Cradle - press Run: the raised ball swings down and kicks the far ball out." into gStatus
   updateHud
end buildRecipeCradle

-- A launched ball rolls into a line of standing dominoes (shows off Launch + Run).
on buildRecipeDominoes
   if gMode is "run" then toggleMode
   clearAll
   local tBaseY, tX, tI, tStartX, tBall
   put gArenaB - 6 into tBaseY
   put gArenaL + 90 into tStartX
   repeat with tI = 1 to 12
      put tStartX + tI * 34 into tX
      get placeBox(tX, tBaseY - 34, 12, 60, "206,124,206")
   end repeat
   put placeBall(tStartX - 16, tBaseY - 40, 34, "232,182,92") into tBall
   set the uLaunchSpeed of tBall to 320
   set the uLaunchDir of tBall to 0
   renderBuild
   put "Domino Run - press Run: the ball is launched into the line and the dominoes cascade." into gStatus
   updateHud
end buildRecipeDominoes

-- A ball rolls down a ramp, along a raised ledge and into a hill - the terrain set.
on buildRecipeTerrainRun
   if gMode is "run" then toggleMode
   clearAll
   local tDeckTop, tBall
   put gArenaB - 84 into tDeckTop                               -- shared surface for the pieces
   get placeTerrain("platform", (gArenaL + gArenaR) div 2, tDeckTop + 14, 560, 28)
   get placeTerrain("ramp", gArenaR - 206, tDeckTop - 65, 200, 130)   -- on the deck's right end
   get placeTerrain("hill", gArenaL + 252, tDeckTop - 40, 160, 80)    -- a bump partway along
   put placeBall(gArenaR - 142, tDeckTop - 150, 36, "232,182,92") into tBall
   set the uBounce of tBall to 0
   b2kSetBounce tBall, 0
   set the uLaunchSpeed of tBall to 120
   set the uLaunchDir of tBall to 180                           -- a nudge to start it down-slope
   renderBuild
   put "Terrain Run - press Run: the ball rolls down the ramp, along the ledge and into the hill. Resize, rotate or re-grip any terrain piece in the inspector." into gStatus
   updateHud
end buildRecipeTerrainRun

-- Drop a batch of random bodies and run, to find where the frame rate gives out.
on stressTest
   local tI, tX, tY
   repeat with tI = 1 to kStressBatch
      put rnd(gArenaL + 30, gArenaR - 30) into tX
      put rnd(gArenaT + 30, (gArenaT + gArenaB) div 2) into tY
      if tI mod 2 is 0 then get placeBox(tX, tY, rnd(24, 40), rnd(24, 40), randomColor())
      else get placeBall(tX, tY, rnd(22, 36), randomColor())
   end repeat
   add kStressBatch to gStressCount
   if gMode is "build" then toggleMode
   put "Stress test: " & b2kBodyCount() & " bodies. Watch the fps - press again to push further." into gStatus
   updateHud
end stressTest

-- =====================================================================
-- First-run onboarding overlay (also reachable via the ? button)
-- =====================================================================
on maybeShowOnboarding
   if the uSeenOnboarding of this stack is true then exit maybeShowOnboarding
   startOnboarding
end maybeShowOnboarding

on startOnboarding
   put 1 into gOnbStep
   buildOnboardingOverlay
   showOnboardingStep
end startOnboarding

on buildOnboardingOverlay
   removeOnboarding
   local tWide, tHigh, tL, tT, tW, tH
   put the width of this card into tWide
   put the height of this card into tHigh
   makeBar "ui_onb_scrim", 0, 0, tWide, tHigh, "10,11,15"
   set the blendLevel of graphic "ui_onb_scrim" to 45
   put 470 into tW
   put 220 into tH
   put (tWide - tW) div 2 into tL
   put (tHigh - tH) div 2 into tT
   makeBar "ui_onb_card", tL, tT, tL + tW, tT + tH, "34,38,48"
   makeLabel "ui_onb_title", tL + 22, tT + 18, tL + tW - 22, tT + 44, "Welcome", 15, "236,238,245", true
   makeField "ui_onb_text", tL + 22, tT + 50, tL + tW - 22, tT + tH - 50, 12, "200,206,220"
   makeAction "onbskip", "Skip", tL + 22, tT + tH - 38, 70, 26
   makeAction "onbnext", "Next", tL + tW - 92, tT + tH - 38, 70, 26
end buildOnboardingOverlay

on showOnboardingStep
   local tTitle, tText
   switch gOnbStep
      case 1
         put "Step 1 of 5 - Pick a part" into tTitle
         put "On the left is your toolbox. Click a category header (SHAPES, SPECIAL, JOINTS...) to open it - only one opens at a time. Try a shape under SHAPES (Box or Ball), or something fun under SPECIAL - a Balloon, a Bomb, a Thruster, a Laser." into tText
         break
      case 2
         put "Step 2 of 5 - Drop it and arrange" into tTitle
         put "Click the dark stage in the middle to drop your part, then drag parts to arrange them. The panel on the right explains and tunes whatever you select (and Rename names it)." into tText
         break
      case 3
         put "Step 3 of 5 - Connect with joints" into tTitle
         put "Pick a joint under JOINTS (a Hinge is a pin things spin around), then click part A and part B to link them. Turn Motor on first to make hinges and wheels drive themselves." into tText
         break
      case 4
         put "Step 4 of 5 - Wire up triggers" into tTitle
         put "Use the Link tool (under TOOLS): click a Pressure Plate or Sensor, then click a Bomb to wire them - an amber wire means that trigger sets off that bomb. Set a bomb to 'Demolish' or a laser to 'Cut' to destroy parts." into tText
         break
      default
         put "Step 5 of 5 - Set a goal and Play" into tTitle
         put "Drop a Goal Zone (under SPECIAL), then press Play (top bar): get a movable part into the goal to solve it. Run just tests physics; Play is the puzzle. Open Recipes > Puzzles for a ready-made one." into tText
   end switch
   if there is a field "ui_onb_title" then put tTitle into field "ui_onb_title"
   if there is a field "ui_onb_text" then put tText into field "ui_onb_text"
   if gOnbStep >= 5 then set the label of button "ui_act_onbnext" to "Start building"
   else set the label of button "ui_act_onbnext" to "Next"
   raiseOnboarding
end showOnboardingStep

on onboardingNext
   add 1 to gOnbStep
   if gOnbStep > 5 then dismissOnboarding
   else showOnboardingStep
end onboardingNext

on dismissOnboarding
   removeOnboarding
   set the uSeenOnboarding of this stack to true
   put "Have fun! Pick a part on the left and click the stage to begin." into gStatus
   updateHud
end dismissOnboarding

on removeOnboarding
   deleteByPrefix "ui_onb_"
   if there is a button "ui_act_onbnext" then delete button "ui_act_onbnext"
   if there is a button "ui_act_onbskip" then delete button "ui_act_onbskip"
end removeOnboarding

on raiseOnboarding
   local tName
   repeat for each item tName in "ui_onb_scrim,ui_onb_card,ui_onb_title,ui_onb_text,ui_act_onbskip,ui_act_onbnext"
      if there is a control tName then set the layer of control tName to top
   end repeat
end raiseOnboarding
