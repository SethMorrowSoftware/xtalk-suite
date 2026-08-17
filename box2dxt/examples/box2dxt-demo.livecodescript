-- #####################################################################
-- #  Box2Dxt  -  SELF-CONTAINED DEMO  (Kit + showcase in one file)    #
-- #                                                                   #
-- #  HOW TO RUN                                                       #
-- #   1. Load the box2dxt.lcb extension and put the box2dxt native    #
-- #      library where it can be found. Check: put b2Version()  -- 4  #
-- #   2. Paste THIS WHOLE FILE into a stack`s script                  #
-- #      (Object > Stack Script).                                     #
-- #   3. Open/close the card, or run  startBox2DDemo  in the          #
-- #      Message Box.  Stop with  stopBox2DDemo.                      #
-- #                                                                   #
-- #  This file bundles a verbatim copy of the reusable Kit            #
-- #  (src/box2dxt-kit.livecodescript) so the demo runs from a single  #
-- #  paste. For your own projects, load the Kit on its own instead.   #
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
-- DEMO APP  /  built on the Kit above (b2k...)
--
-- WHAT IT SHOWS
--   / Every shape: boxes, balls, capsules, polygons.
--   / Joints: hinge + motor (windmill, see-saw), distance (cradle), revolute
--     chain (bridge), wheel + suspension (vehicle).
--   / Forces, dragging, contact + end-contact events, live ray casting.
--   / The b2kFrame per-frame hook for app logic and custom drawing.
--
-- NAMING: LiveCode conventions throughout - p* parameters, t* locals,
-- g* script-locals, k* constants - so nothing collides with reserved words.
-- All scene coordinates are in SCREEN PIXELS.
-- =====================================================================

local gScene, gTool, gDrops
local gFrames, gFpsTime, gFps
local gBombs, gFlash
local gCableN, gCableAX, gCableAY, gCableCtrl
local gRingN, gRingX, gRingY, gRingF
local gRayN
local gThrottle, gThrottleTtl, gWheelBack, gWheelFront
local gArenaL, gArenaR, gArenaT, gArenaB
local gObjective, gTargets, gSpawnX, gStartX, gCar
local gScore, gCoins, gCoinTotal, gWheelBC, gWheelFC

constant kScenes     = "playground,pyramid,cradle,bridge,vehicle,lidar"
constant kLabels     = "Playground,Pyramid,Cradle,Bridge,Vehicle,Lidar"
constant kTools      = "box,ball,capsule,poly,bomb"
constant kToolLabels = "Box,Ball,Capsule,Poly,Bomb"
constant kMaxDrops = 70
constant kDemoUIVersion = "1"  -- bump when buildUI's chrome changes; older saved stacks rebuild it once

-- ---------------------------------------------------------------------
on preOpenCard
   startBox2DDemo
end preOpenCard

on closeCard
   stopBox2DDemo
end closeCard

on startBox2DDemo
   -- a proper, centred, non-resizable window
   set the title of this stack to "Box2Dxt - Kit Showcase"
   set the decorations of this stack to "default"
   set the resizable of this stack to false
   set the width of this stack to 980
   set the height of this stack to 640
   set the loc of this stack to the screenLoc
   set the backgroundColor of this card to "22,24,30"
   put "box" into gTool
   if not demoChromeBuilt() then     -- build the chrome once; it persists in the saved stack
      buildUI
      set the uDemoUIVersion of this stack to kDemoUIVersion
   end if
   switchScene "playground"
end startBox2DDemo

on stopBox2DDemo
   b2kTeardown
   clearSceneControls
end stopBox2DDemo

-- =====================================================================
-- Scene lifecycle
-- =====================================================================
on switchScene pScene
   lock screen
   b2kStop
   clearSceneControls
   clearState
   put pScene into gScene
   b2kSetup 0, -10
   b2kFrameTarget the long id of this stack
   b2kContactTarget the long id of this stack
   switch pScene
      case "playground"
         buildPlayground
         break
      case "pyramid"
         buildPyramid
         break
      case "cradle"
         buildCradle
         break
      case "bridge"
         buildBridge
         break
      case "vehicle"
         buildVehicle
         break
      case "lidar"
         buildLidar
         break
   end switch
   raiseUI                       -- keep the chrome above all scene controls
   b2kStart
   highlightScenes
   highlightTools
   setHelp
   updateHud
   unlock screen
end switchScene

-- Keep every UI control above the scene's bodies/rays so the chrome is always
-- visible and clickable, whatever the simulation draws.
on raiseUI
   local tI, tName, tList
   put empty into tList
   repeat with tI = 1 to the number of controls of this card
      put the short name of control tI of this card into tName
      if char 1 to 3 of tName is "ui_" then put tName & cr after tList
   end repeat
   repeat for each line tName in tList
      set the layer of control tName of this card to top
   end repeat
end raiseUI

on clearState
   put the milliseconds into gFpsTime   -- seed the FPS window so the first reading is sane
   put 0 into gFrames
   put "--" into gFps   -- seed so the first HUD frame reads cleanly, not blank
   put empty into gDrops
   put empty into gBombs
   put empty into gFlash
   put 0 into gCableN
   put empty into gCableAX
   put empty into gCableAY
   put empty into gCableCtrl
   put 0 into gRingN
   put empty into gRingX
   put empty into gRingY
   put empty into gRingF
   put 0 into gRayN
   put 0 into gThrottle
   put 0 into gThrottleTtl
   put empty into gWheelBack
   put empty into gWheelFront
   put empty into gObjective
   put empty into gTargets
   put empty into gSpawnX
   put 0 into gStartX
   put 0 into gScore
   put empty into gCoins
   put 0 into gCoinTotal
   put empty into gWheelBC
   put empty into gWheelFC
end clearState

-- Build the four bounding walls (so bodies stay inside the play area, clear of
-- the toolbar) plus a visible ground strip. Top = below the toolbar.
on prepArena
   local tGroundY, tWide
   put the width of this card into tWide
   put (the height of this card) - 48 into tGroundY
   -- screen-space arena bounds (used to keep gameplay + the lidar inside)
   put 2 into gArenaL
   put tWide - 2 into gArenaR
   put 130 into gArenaT
   put tGroundY into gArenaB
   -- a framed play-field panel behind the bodies (game-board look)
   create graphic "demo_field"
   set the style of graphic "demo_field" to "rectangle"
   set the filled of graphic "demo_field" to true
   set the backgroundColor of graphic "demo_field" to "26,29,37"
   set the foregroundColor of graphic "demo_field" to "46,60,86"
   set the lineSize of graphic "demo_field" to 2
   set the rect of graphic "demo_field" to gArenaL, gArenaT, gArenaR, tGroundY + 20
   -- physics walls (b2kWall takes screen points and converts to world for us)
   b2kWall 2, tGroundY, tWide - 2, tGroundY
   b2kWall 2, 130, tWide - 2, 130
   b2kWall 2, tGroundY, 2, 130
   b2kWall tWide - 2, tGroundY, tWide - 2, 130
   -- visible ground strip
   create graphic "demo_groundbar"
   set the style of graphic "demo_groundbar" to "rectangle"
   set the filled of graphic "demo_groundbar" to true
   set the backgroundColor of graphic "demo_groundbar" to "44,49,60"
   set the lineSize of graphic "demo_groundbar" to 0
   set the rect of graphic "demo_groundbar" to gArenaL, tGroundY, gArenaR, tGroundY + 20
end prepArena

-- =====================================================================
-- Scenes  (all in screen pixels)
-- =====================================================================
on buildPlayground
   prepArena
   local tCx
   put (the width of this card) div 2 into tCx

   -- a sampler of every shape, dropping in
   get newBox(tCx - 250, 200, 58, 58, accentShape(1))
   get newBall(tCx - 120, 180, 56, accentShape(2))
   get newCapsule(tCx + 40, 180, 96, 38, accentShape(3))
   get newPoly(tCx + 210, 180, 36, accentShape(4))

   -- SEE-SAW: a plank hinged to the world at its centre. The fulcrum is purely
   -- decorative - making it a static *body* (as before) jams the plank against
   -- it and the see-saw can't tilt.
   local tPlank, tPivotX, tPivotY
   put tCx - 250 into tPivotX
   put 470 into tPivotY
   create graphic "demo_fulcrum"
   set the style of graphic "demo_fulcrum" to "polygon"
   set the filled of graphic "demo_fulcrum" to true
   set the backgroundColor of graphic "demo_fulcrum" to "92,98,112"
   set the points of graphic "demo_fulcrum" to \
         (tPivotX - 30) & "," & (tPivotY + 70) & cr & (tPivotX + 30) & "," & (tPivotY + 70) \
         & cr & tPivotX & "," & (tPivotY + 6)
   put newBox(tPivotX, tPivotY, 260, 16, "120,180,210") into tPlank
   b2kHinge tPlank, empty, tPivotX, tPivotY
   get newBox(tPivotX - 116, 330, 52, 52, accentShape(5))         -- weight tips it

   -- WINDMILL: a blade hinged to the world, driven by a motor
   local tHubX, tHubY, tBlade, tJoint
   put tCx + 150 into tHubX
   put 300 into tHubY
   put newBox(tHubX, tHubY, 160, 16, "240,212,120") into tBlade
   b2kHinge tBlade, empty, tHubX, tHubY
   put the result into tJoint
   b2kMotor tJoint, 110, 90

   -- PENDULUM: a bob hinged to the world, with a drawn cable
   local tAnchorX, tAnchorY, tBob
   put tCx + 330 into tAnchorX
   put 150 into tAnchorY
   put newBall(tAnchorX + 130, 300, 46, "214,92,92") into tBob
   b2kHinge tBob, empty, tAnchorX, tAnchorY
   addCable tAnchorX, tAnchorY, tBob
   put "Sandbox: drag anything; click empty space to drop the selected shape." into gObjective
end buildPlayground

on buildPyramid
   prepArena
   local tRows, tI, tK, tBw, tCx, tGroundY, tX, tY, tBox
   put 7 into tRows
   put 46 into tBw
   put (the width of this card) div 2 into tCx
   put (the height of this card) - 48 into tGroundY
   repeat with tI = 0 to tRows - 1
      repeat with tK = 0 to tRows - 1 - tI
         put tCx + (tK - (tRows - 1 - tI) / 2) * (tBw + 2) into tX
         put tGroundY - tBw / 2 - tI * (tBw + 1) into tY
         put newBox(tX, tY, tBw, tBw, pyramidColor(tI, tRows)) into tBox
         put tBox & cr after gTargets        -- track for the scatter score
         put tX into gSpawnX[tBox]
      end repeat
   end repeat
   put "Objective: pick the Bomb tool (top-right) and blast the stack apart!" into gObjective
end buildPyramid

on buildCradle
   local tN, tI, tR, tAnchorX, tAnchorY, tRestY, tBob, tBx, tLen, tCx, tSpace
   prepArena
   put 5 into tN
   put 48 into tR                       -- ball diameter
   put tR + 1 into tSpace               -- 1px gap: avoids a spawn-overlap blow-up
   put 160 into tAnchorY
   put 400 into tRestY
   put tRestY - tAnchorY into tLen       -- pendulum arm length
   put (the width of this card) div 2 into tCx
   repeat with tI = 1 to tN
      put tCx + (tI - (tN + 1) / 2) * tSpace into tBx
      if tI is 1 then
         -- Create the end ball ALREADY lifted (~50 deg) so the hinge is built
         -- consistent with its position. Teleporting a ball AFTER hinging it
         -- violates the joint and makes the whole cradle explode on step 1.
         put newBall(tBx - tLen * 0.766, tAnchorY + tLen * 0.643, tR, "196,200,214") into tBob
      else
         put newBall(tBx, tRestY, tR, "196,200,214") into tBob
      end if
      b2kSetBounce tBob, 0.9
      b2kSetFriction tBob, 0.05
      b2kHinge tBob, empty, tBx, tAnchorY
      addCable tBx, tAnchorY, tBob
   end repeat
   put "Watch momentum carry through the line - drag a ball aside and release." into gObjective
end buildCradle

on buildBridge
   local tN, tI, tPw, tPy, tStartX, tX, tPlank, tPrevPlank, tCx
   prepArena
   put 12 into tN
   put 62 into tPw
   put 320 into tPy
   put (the width of this card) div 2 into tCx
   put tCx - tN * tPw / 2 into tStartX
   put empty into tPrevPlank
   repeat with tI = 1 to tN
      put tStartX + (tI - 0.5) * tPw into tX
      put newBox(tX, tPy, tPw, 14, "168,146,98") into tPlank
      if tI is 1 then
         b2kHinge tPlank, empty, tX - tPw / 2, tPy
      else
         b2kHinge tPrevPlank, tPlank, tX - tPw / 2, tPy
      end if
      put tPlank into tPrevPlank
   end repeat
   b2kHinge tPrevPlank, empty, tStartX + tN * tPw, tPy
   get newBall(tCx - 60, 150, 54, "92,202,162")
   get newBall(tCx + 60, 140, 66, "214,118,118")
   put "Objective: pile heavy shapes on the plank bridge and watch it sag." into gObjective
end buildBridge

on buildVehicle
   local tGroundY, tChassis, tWheelB, tWheelF, tX, tY, tPrevX, tPrevY, tPts, tCarY
   prepArena
   put (the height of this card) - 48 into tGroundY
   -- ROLLING TERRAIN: a chain of static segments + a filled silhouette to match.
   put empty into tPts
   put gArenaL + 6 into tPrevX
   put terrainY(tPrevX) into tPrevY
   put tPrevX & "," & round(tPrevY) & cr after tPts
   put tPrevX + 26 into tX
   repeat until tX > gArenaR - 6
      put terrainY(tX) into tY
      b2kWall tPrevX, tPrevY, tX, tY
      put tX & "," & round(tY) & cr after tPts
      put tX into tPrevX
      put tY into tPrevY
      add 26 to tX
   end repeat
   put (gArenaR - 6) & "," & (tGroundY + 20) & cr & (gArenaL + 6) & "," & (tGroundY + 20) after tPts
   create graphic "demo_terrain"
   set the style of graphic "demo_terrain" to "polygon"
   set the filled of graphic "demo_terrain" to true
   set the backgroundColor of graphic "demo_terrain" to "56,72,50"
   set the foregroundColor of graphic "demo_terrain" to "84,108,74"
   set the lineSize of graphic "demo_terrain" to 2
   set the points of graphic "demo_terrain" to tPts
   -- COINS to grab along the course
   put empty into gCoins
   put 0 into gCoinTotal
   put gArenaL + 150 into tX
   repeat until tX > gArenaR - 130
      put newCoin(tX, terrainY(tX) - 52) & cr after gCoins
      add 1 to gCoinTotal
      add 150 to tX
   end repeat
   -- THE CAR: chassis + two sprung wheels
   put terrainY(190) - 64 into tCarY
   put newBox(190, tCarY, 122, 34, "228,132,60") into tChassis
   put newBall(158, tCarY + 30, 44, "40,40,48") into tWheelB
   put newBall(222, tCarY + 30, 44, "40,40,48") into tWheelF
   b2kWheel tChassis, tWheelB
   put the result into gWheelBack
   b2kWheel tChassis, tWheelF
   put the result into gWheelFront
   b2kWheelSpring gWheelBack, 5, 0.7
   b2kWheelSpring gWheelFront, 5, 0.7
   makeSpoke "demo_spokeB"
   makeSpoke "demo_spokeF"
   put tChassis into gCar
   put tWheelB into gWheelBC
   put tWheelF into gWheelFC
   put 190 into gStartX
   put "Drive with the <- / -> arrow keys - roll over the hills and grab the coins!" into gObjective
end buildVehicle

-- Terrain height (screen Y) at a screen X - gentle rolling hills that always
-- stay above the arena floor.
function terrainY pX
   local tBase, tRel
   put (the height of this card) - 140 into tBase
   put pX - gArenaL into tRel
   return tBase - 40 * sin(tRel / 115) - 18 * sin(tRel / 270 + 1)
end terrainY

function newCoin pX, pY
   local tName, tRef
   put "demo_coin_" & the milliseconds & "_" & random(99999) into tName
   create graphic tName
   put the long id of graphic tName into tRef
   set the style of tRef to "oval"
   set the filled of tRef to true
   set the backgroundColor of tRef to "246,206,90"
   set the foregroundColor of tRef to "176,136,40"
   set the lineSize of tRef to 2
   set the width of tRef to 26
   set the height of tRef to 26
   set the loc of tRef to round(pX) & "," & round(pY)
   return tRef
end newCoin

on makeSpoke pName
   create graphic pName
   set the style of graphic pName to "line"
   set the lineSize of graphic pName to 3
   set the foregroundColor of graphic pName to "205,205,215"
end makeSpoke

on updateSpoke pName, pWheel
   local tcx, tcy, tA
   put empty into tcx
   try
      put item 1 of the loc of pWheel into tcx
      put item 2 of the loc of pWheel into tcy
   catch tErr
   end try
   if tcx is empty then exit updateSpoke
   put b2kAngle(pWheel) * kPI / 180 into tA
   set the points of graphic pName to round(tcx) & "," & round(tcy) & cr \
         & round(tcx + 19 * cos(tA)) & "," & round(tcy + 19 * sin(tA))
end updateSpoke

on buildLidar
   local tI, tBody
   prepArena
   b2kSetGravity 0, 0
   repeat with tI = 1 to 8
      put newBall(rnd(gArenaL + 90, gArenaR - 90), rnd(170, 560), rnd(30, 72), "96,150,210") into tBody
      b2kSetBounce tBody, 1
      b2kSetFriction tBody, 0
      b2kSetVelocity tBody, rnd(-170, 170), rnd(-170, 170)
   end repeat
   repeat with tI = 1 to 3
      put newPoly(rnd(gArenaL + 110, gArenaR - 110), rnd(180, 540), rnd(28, 48), "200,160,120") into tBody
      b2kSetBounce tBody, 1
      b2kSetFriction tBody, 0
      b2kSetVelocity tBody, rnd(-130, 130), rnd(-130, 130)
   end repeat
   put 48 into gRayN
   repeat with tI = 1 to gRayN
      create graphic ("demo_ray_" & tI)
      set the style of graphic ("demo_ray_" & tI) to "line"
      set the lineSize of graphic ("demo_ray_" & tI) to 1
      set the foregroundColor of graphic ("demo_ray_" & tI) to "0,214,130"
      set the blendLevel of graphic ("demo_ray_" & tI) to 28
   end repeat
   create graphic "demo_emitter"
   set the style of graphic "demo_emitter" to "oval"
   set the filled of graphic "demo_emitter" to true
   set the backgroundColor of graphic "demo_emitter" to "0,230,140"
   set the foregroundColor of graphic "demo_emitter" to "190,255,220"
   set the lineSize of graphic "demo_emitter" to 2
   set the width of graphic "demo_emitter" to 16
   set the height of graphic "demo_emitter" to 16
   set the visible of graphic "demo_emitter" to false
   put "Move the mouse inside the arena - rays scan outward and stop at the nearest shape." into gObjective
end buildLidar

-- =====================================================================
-- Per-frame hook (the Kit sends this once per simulated frame)
-- =====================================================================
on b2kFrame
   switch gScene
      case "vehicle"
         driveFrame
         break
      case "lidar"
         renderLidar
         break
      case "pyramid"
         framePyramid
         break
   end switch
   renderCables
   updateFlashes
   updateBombs
   updateRings
   tickHud
end b2kFrame

-- Count how many tower blocks have been knocked well away from where they
-- started - the demolition "score".
on framePyramid
   local t, tScattered, tX
   put 0 into tScattered
   repeat for each line t in gTargets
      put empty into tX
      try
         put item 1 of the loc of t into tX
      catch tErr
      end try
      if tX is not empty and abs(tX - gSpawnX[t]) > 70 then add 1 to tScattered
   end repeat
   put "Scattered: " & tScattered & " / " & (the number of lines of gTargets) \
         & "   /   pick the Bomb tool and click the stack" into gObjective
end framePyramid

on driveFrame
   if gThrottleTtl > 0 then
      subtract 1 from gThrottleTtl
   else
      put 0 into gThrottle
   end if
   if gWheelBack is not empty then
      b2kWheelMotor gWheelBack, gThrottle, 170
      b2kWheelMotor gWheelFront, gThrottle, 170
   end if
   updateSpoke "demo_spokeB", gWheelBC
   updateSpoke "demo_spokeF", gWheelFC
   -- car position
   local tCx, tCy
   put empty into tCx
   try
      put item 1 of the loc of gCar into tCx
      put item 2 of the loc of gCar into tCy
   catch tErr
   end try
   if tCx is empty then exit driveFrame
   -- collect coins on contact
   local tCoin, tKeep, tCoinX, tCoinY, dx, dy
   put empty into tKeep
   repeat for each line tCoin in gCoins
      put empty into tCoinX
      try
         put item 1 of the loc of tCoin into tCoinX
         put item 2 of the loc of tCoin into tCoinY
      catch tErr
      end try
      if tCoinX is empty then next repeat
      put tCoinX - tCx into dx
      put tCoinY - tCy into dy
      if dx * dx + dy * dy < 3600 then          -- within 60 px
         add 1 to gScore
         spawnRing tCoinX, tCoinY
         try
            delete tCoin
         end try
      else
         put tCoin & cr after tKeep
      end if
   end repeat
   put tKeep into gCoins
   local tDist
   put round((tCx - gStartX) / 40 * 10) / 10 into tDist
   put "Coins: " & gScore & " / " & gCoinTotal & "        Distance: " & max(0, tDist) \
         & " m        <- / -> to drive" into gObjective
end driveFrame

on renderLidar
   local tN, tI, tAng, tEx, tEy, tTx, tTy, tRange, tHx, tHy
   put gRayN into tN
   if tN < 1 then exit renderLidar
   put the mouseH into tEx
   put the mouseV into tEy
   -- Only scan while the cursor is inside the arena, so rays never spill over
   -- the toolbar/HUD (and the UI stays clickable).
   if tEx < gArenaL or tEx > gArenaR or tEy < gArenaT or tEy > gArenaB then
      hideLidar
      exit renderLidar
   end if
   set the visible of graphic "demo_emitter" to true
   set the loc of graphic "demo_emitter" to round(tEx) & "," & round(tEy)
   put 1400 into tRange    -- long enough to always reach a wall, which stops it
   repeat with tI = 1 to tN
      put (tI - 1) * (2 * kPI / tN) into tAng
      put tEx + cos(tAng) * tRange into tTx
      put tEy + sin(tAng) * tRange into tTy
      get b2kRayHit(tEx, tEy, tTx, tTy)
      put b2kRayHitX() into tHx
      put b2kRayHitY() into tHy
      if tHx is empty then       -- a miss: draw the ray out to its far end
         put round(tTx) into tHx
         put round(tTy) into tHy
      end if
      set the points of graphic ("demo_ray_" & tI) to \
            round(tEx) & "," & round(tEy) & cr & tHx & "," & tHy
   end repeat
end renderLidar

on hideLidar
   local tI
   if there is a graphic "demo_emitter" then set the visible of graphic "demo_emitter" to false
   repeat with tI = 1 to gRayN
      if there is a graphic ("demo_ray_" & tI) then set the points of graphic ("demo_ray_" & tI) to empty
   end repeat
end hideLidar

-- Cables (pendulum / cradle): a line from a fixed anchor to a body's centre.
on addCable pAx, pAy, pCtrl
   add 1 to gCableN
   put pAx into gCableAX[gCableN]
   put pAy into gCableAY[gCableN]
   put pCtrl into gCableCtrl[gCableN]
   create graphic ("demo_cable_" & gCableN)
   set the style of graphic ("demo_cable_" & gCableN) to "line"
   set the lineSize of graphic ("demo_cable_" & gCableN) to 2
   set the foregroundColor of graphic ("demo_cable_" & gCableN) to "150,154,168"
end addCable

on renderCables
   local tI
   if gCableN < 1 then exit renderCables
   repeat with tI = 1 to gCableN
      if there is a graphic ("demo_cable_" & tI) then
         try
            set the points of graphic ("demo_cable_" & tI) to \
                  gCableAX[tI] & "," & gCableAY[tI] & cr & the loc of gCableCtrl[tI]
         end try
      end if
   end repeat
end renderCables

-- Contact flashing: light a body's outline white when it starts touching.
on b2kContact pA, pB
   flashCtrl pA
   flashCtrl pB
end b2kContact

on flashCtrl pCtrl
   if pCtrl is empty then exit flashCtrl
   try
      set the foregroundColor of pCtrl to "255,255,255"
      set the lineSize of pCtrl to 2
      put the milliseconds + 150 into gFlash[pCtrl]
   end try
end flashCtrl

on updateFlashes
   local tKey, tNow
   put the milliseconds into tNow
   repeat for each key tKey in gFlash
      if tNow > gFlash[tKey] then
         try
            set the foregroundColor of tKey to "20,20,24"
            set the lineSize of tKey to 1
         end try
         delete variable gFlash[tKey]
      end if
   end repeat
end updateFlashes

-- Bombs: a flashing fuse, then a radial blast + an expanding shock ring.
on spawnBomb pX, pY
   local tBody
   put newBall(pX, pY, 40, "150,40,40") into tBody
   put 60 into gBombs[tBody]
end spawnBomb

on updateBombs
   local tKey, tFuse, tToBlow
   put empty into tToBlow
   repeat for each key tKey in gBombs
      put gBombs[tKey] - 1 into tFuse
      put tFuse into gBombs[tKey]
      if tFuse < 28 then
         try
            if (tFuse mod 6) < 3 then set the backgroundColor of tKey to "245,80,55"
            else set the backgroundColor of tKey to "150,40,40"
         end try
      end if
      if tFuse <= 0 then put tKey & cr after tToBlow
   end repeat
   repeat for each line tKey in tToBlow
      detonate tKey
   end repeat
end updateBombs

on detonate pBomb
   local tLx, tLy
   try
      put item 1 of the loc of pBomb into tLx
      put item 2 of the loc of pBomb into tLy
      b2kExplode tLx, tLy, 210, 720
      spawnRing tLx, tLy
      b2kRemove pBomb
   end try
   delete variable gBombs[pBomb]
end detonate

on spawnRing pX, pY
   add 1 to gRingN
   put pX into gRingX[gRingN]
   put pY into gRingY[gRingN]
   put 0 into gRingF[gRingN]
   create graphic ("demo_ring_" & gRingN)
   set the style of graphic ("demo_ring_" & gRingN) to "oval"
   set the filled of graphic ("demo_ring_" & gRingN) to false
   set the lineSize of graphic ("demo_ring_" & gRingN) to 3
   set the foregroundColor of graphic ("demo_ring_" & gRingN) to "255,170,70"
end spawnRing

on updateRings
   local tI, tFrame, tRad
   if gRingN < 1 then exit updateRings
   repeat with tI = 1 to gRingN
      if gRingF[tI] is not empty then
         put gRingF[tI] + 1 into tFrame
         put tFrame into gRingF[tI]
         if tFrame > 16 then
            if there is a graphic ("demo_ring_" & tI) then delete graphic ("demo_ring_" & tI)
            put empty into gRingF[tI]
         else
            put tFrame * 15 into tRad
            set the rect of graphic ("demo_ring_" & tI) to \
                  round(gRingX[tI] - tRad), round(gRingY[tI] - tRad), \
                  round(gRingX[tI] + tRad), round(gRingY[tI] + tRad)
            set the blendLevel of graphic ("demo_ring_" & tI) to round(tFrame / 16 * 85)
         end if
      end if
   end repeat
end updateRings

on tickHud
   add 1 to gFrames
   local tNow
   put the milliseconds into tNow
   if tNow - gFpsTime >= 500 then
      put round(gFrames * 1000 / (tNow - gFpsTime)) into gFps
      put 0 into gFrames
      put tNow into gFpsTime
      updateHud
   end if
end tickHud

on updateHud
   if there is not a field "ui_hud" then exit updateHud
   local tLine
   put sceneTitle(gScene) & "        FPS " & gFps & "        Bodies " \
         & b2kBodyCount() & " (" & b2kAwakeCount() & " awake)" into tLine
   if gObjective is not empty then put "        " & gObjective after tLine
   put tLine into field "ui_hud"
end updateHud

-- =====================================================================
-- Input
-- =====================================================================
on mouseDown
   if "ui_" is in the short name of the target then exit mouseDown
   -- If the script was just (re)compiled, the demo isn't running yet; start it
   -- on the first click rather than acting on an un-built world.
   if b2kWorld() is empty then
      startBox2DDemo
      exit mouseDown
   end if
   if gScene is "lidar" then exit mouseDown
   get b2kGrab(the mouseH, the mouseV)
   if it is empty then sceneClick the mouseH, the mouseV
end mouseDown

on mouseUp
   local tName
   put the short name of the target into tName
   if "ui_scene_" is in tName then
      switchScene the uSceneId of the target
      exit mouseUp
   end if
   if "ui_tool_" is in tName then
      put the uToolId of the target into gTool
      highlightTools
      updateHud
      exit mouseUp
   end if
   b2kRelease
end mouseUp

on mouseRelease
   b2kRelease
end mouseRelease

on arrowKey pKey
   if gScene is "vehicle" then
      if pKey is "right" then
         put -560 into gThrottle
         put 20 into gThrottleTtl
      else if pKey is "left" then
         put 560 into gThrottle
         put 20 into gThrottleTtl
      end if
      exit arrowKey
   end if
   pass arrowKey
end arrowKey

on sceneClick pX, pY
   local tCtrl
   switch gTool
      case "ball"
         put newBall(pX, pY, rnd(28, 64), randomColor()) into tCtrl
         break
      case "capsule"
         put newCapsule(pX, pY, rnd(70, 120), 34, randomColor()) into tCtrl
         break
      case "poly"
         put newPoly(pX, pY, rnd(22, 42), randomColor()) into tCtrl
         break
      case "bomb"
         spawnBomb pX, pY
         exit sceneClick
      default
         put newBox(pX, pY, rnd(34, 60), rnd(34, 60), randomColor()) into tCtrl
   end switch
   registerDrop tCtrl
end sceneClick

-- Keep the count of click-dropped bodies bounded so spamming stays smooth.
on registerDrop pCtrl
   local tOldest
   put pCtrl & cr after gDrops
   if the number of lines of gDrops > kMaxDrops then
      put line 1 of gDrops into tOldest
      delete line 1 of gDrops
      try
         b2kRemove tOldest          -- removes the body (and spawned controls)
         delete tOldest             -- and the graphic, for directly-made polys
      end try
   end if
end registerDrop

-- =====================================================================
-- Body factories  (call as functions; return the control)
-- =====================================================================
function newBox pX, pY, pW, pH, pColor
   b2kSpawnBox pX, pY, pW, pH, pColor
   return the result
end newBox

function newBall pX, pY, pDiam, pColor
   b2kSpawnBall pX, pY, pDiam, pColor
   return the result
end newBall

function newCapsule pX, pY, pLen, pThick, pColor
   b2kSpawnCapsule pX, pY, pLen, pThick, pColor
   return the result
end newCapsule

function newPoly pX, pY, pR, pColor
   local tName, tRef, tI, tAng, tPoints
   put "demo_poly_" & the milliseconds & "_" & random(99999) into tName
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
   return tRef
end newPoly

-- =====================================================================
-- UI
-- =====================================================================
-- The chrome (top bar, scene/tool buttons, HUD, help bar) is generated once and
-- saved with the stack; this reports whether that persisted UI is present and
-- current, so startBox2DDemo skips the rebuild on reopen. A kDemoUIVersion bump
-- (after the demo's chrome changes) rebuilds it once on the next open.
function demoChromeBuilt
   return (there is a button "ui_scene_playground") and (the uDemoUIVersion of this stack is kDemoUIVersion)
end demoChromeBuilt

on buildUI
   clearUI
   local tWide, tI, tScene, tTool, tX
   put the width of this card into tWide

   makeBar "ui_header", 0, 0, tWide, 54, "30,33,42"
   makeBar "ui_accent", 0, 54, tWide, 57, "64,132,232"
   makeLabel "ui_title", 18, 11, 320, 44, "Box2Dxt", 22, "236,238,245", true
   makeLabel "ui_sub", 20, 33, 460, 53, "Box2D v3 physics / the OpenXTalk Kit, in action", 11, "150,154,166", false

   put 16 into tX
   repeat with tI = 1 to the number of items of kScenes
      put item tI of kScenes into tScene
      makeButton ("ui_scene_" & tScene), (item tI of kLabels), tX, 66, 96, 28
      set the uSceneId of button ("ui_scene_" & tScene) to tScene
      add 100 to tX
   end repeat

   put tWide - (5 * 62) - 8 into tX
   repeat with tI = 1 to the number of items of kTools
      put item tI of kTools into tTool
      makeButton ("ui_tool_" & tTool), (item tI of kToolLabels), tX, 66, 58, 28
      set the uToolId of button ("ui_tool_" & tTool) to tTool
      add 62 to tX
   end repeat

   makeBar "ui_hudbar", 0, 100, tWide, 126, "18,20,26"
   makeField "ui_hud", 12, 103, tWide - 12, 124, 12, "224,226,234"
   makeBar "ui_helpbar", 0, (the height of this card) - 28, tWide, the height of this card, "18,20,26"
   makeField "ui_help", 12, (the height of this card) - 26, tWide - 12, (the height of this card) - 5, 11, "168,172,184"
end buildUI

on clearUI
   local tI, tName
   repeat with tI = the number of controls of this card down to 1
      put the short name of control tI of this card into tName
      if char 1 to 3 of tName is "ui_" then delete control tI of this card
   end repeat
end clearUI

on clearSceneControls
   local tI, tName
   repeat with tI = the number of controls of this card down to 1
      put the short name of control tI of this card into tName
      if char 1 to 3 of tName is not "ui_" then delete control tI of this card
   end repeat
end clearSceneControls

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

on highlightScenes
   local tScene
   repeat for each item tScene in kScenes
      if there is a button ("ui_scene_" & tScene) then
         if tScene is gScene then
            set the backgroundColor of button ("ui_scene_" & tScene) to "64,132,232"
            set the textColor of button ("ui_scene_" & tScene) to "255,255,255"
         else
            set the backgroundColor of button ("ui_scene_" & tScene) to "44,48,58"
            set the textColor of button ("ui_scene_" & tScene) to "196,200,212"
         end if
      end if
   end repeat
end highlightScenes

on highlightTools
   local tTool
   repeat for each item tTool in kTools
      if there is a button ("ui_tool_" & tTool) then
         if tTool is gTool then
            set the backgroundColor of button ("ui_tool_" & tTool) to "72,190,130"
            set the textColor of button ("ui_tool_" & tTool) to "255,255,255"
         else
            set the backgroundColor of button ("ui_tool_" & tTool) to "44,48,58"
            set the textColor of button ("ui_tool_" & tTool) to "196,200,212"
         end if
      end if
   end repeat
end highlightTools

on setHelp
   if there is a field "ui_help" then put sceneHelp(gScene) into field "ui_help"
end setHelp

-- =====================================================================
-- Helpers
-- =====================================================================
function shapePalette
   return "92,150,222" & cr & "84,206,142" & cr & "232,182,92" & cr \
         & "214,92,92" & cr & "206,124,206" & cr & "120,200,232"
end shapePalette

function accentShape pIndex
   return line (((pIndex - 1) mod 6) + 1) of shapePalette()
end accentShape

function randomColor
   return line (random(6)) of shapePalette()
end randomColor

function pyramidColor pRow, pRows
   local tT, tRed, tGreen, tBlue
   put pRow / (pRows - 1) into tT
   put round(80 + tT * 150) into tRed
   put round(120 + tT * 60) into tGreen
   put round(220 - tT * 120) into tBlue
   return tRed & "," & tGreen & "," & tBlue
end pyramidColor

function rnd pLow, pHigh
   return pLow + random(max(1, pHigh - pLow))
end rnd

function sceneTitle pScene
   switch pScene
      case "playground"
         return "PLAYGROUND - shapes, a see-saw, a motorised windmill & a pendulum"
      case "pyramid"
         return "PYRAMID - stacking (pick the Bomb tool and click the stack!)"
      case "cradle"
         return "NEWTON'S CRADLE - distance/hinge joints + restitution"
      case "bridge"
         return "BRIDGE - a chain of revolute joints you can load up"
      case "vehicle"
         return "VEHICLE - wheel joints, a motor & spring suspension"
      case "lidar"
         return "LIDAR - live ray casting that follows your mouse"
   end switch
   return pScene
end sceneTitle

function sceneHelp pScene
   local tTail
   put "   Drag any body with the mouse. Click empty space to add the selected shape (top-right). Click a tab to reset that scene." into tTail
   switch pScene
      case "vehicle"
         return "Drive with the LEFT / RIGHT arrow keys to climb the bumps. Drag the car to mess with it." & tTail
      case "lidar"
         return "Move the mouse - rays fan out from the cursor and each stops at the nearest shape (b2kRayHit)."
      case "pyramid"
         return "Choose the Bomb tool and click beside the stack to scatter it with a blast." & tTail
      case "cradle"
         return "Momentum carries through the line of balls. Drag one aside and let go." & tTail
   end switch
   return "Bodies flash white the instant they touch (contact events)." & tTail
end sceneHelp
