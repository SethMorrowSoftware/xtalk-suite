-- engine-demo-probe.livecodescript - the checks of tests/engine-demo.lc.
--
-- This is the script of a button that engine-demo.lc puts on the card of
-- the Orb Island stack (examples/box3dxt-orb-island.livecodescript). Every
-- call below therefore resolves the way a player's click does: through
-- the button, its card and the stack, whose script is the game with the
-- Kit embedded in it. Using the stack as a library instead would put its
-- script in the message path twice, and a passed message (openStack
-- passes) would run twice: measured on the server engine, 2026-11-21.
--
-- The world is paused after the build and hand-stepped with b3kStepOnce,
-- so every number is reproducible; keys come from b3kInputInject. The
-- game's own state lives in its script locals, so the checks read what a
-- player sees (the HUD fields, the status line, the banner) and what the
-- Kit reports (things by name, positions, speeds).
--
-- What this is NOT: a pass in the IDE with a real window, keyboard and
-- mouse. The feel, the frame rate on a desktop and the look in the dark
-- appearance need an OXT pass.

global gPrOut, gPrPassed, gPrFailed

command prCheck pName, pOk, pDetail
   if pOk is true then
      add 1 to gPrPassed
      put "PASS " & pName & return after gPrOut
   else
      add 1 to gPrFailed
      put "FAIL " & pName & " - " & pDetail & return after gPrOut
      put "::error title=Orb Island engine test::" & pName & " - " & pDetail & return after gPrOut
   end if
end prCheck

command prInfo pText
   put "INFO " & pText & return after gPrOut
end prInfo

function prNear pA, pB, pTolerance
   if pA is not a number or pB is not a number then return false
   return abs(pA - pB) <= pTolerance
end prNear

function prLine pText
   replace return with " | " in pText
   return pText
end prLine

command prSteps pCount
   repeat pCount times
      b3kStepOnce
   end repeat
end prSteps

-- the size of a panel's soft shadow, 0 for none
function prShadowSize pName
   local tShadow
   put the dropShadow of graphic pName of card 1 of stack "OrbIsland" into tShadow
   if tShadow is not an array then return 0
   return tShadow["size"] + 0
end prShadowSize

function prField pName
   return the text of field pName of card 1 of stack "OrbIsland"
end prField

function prStatus
   return the text of field "uiStatus" of card 1 of stack "OrbIsland"
end prStatus

-- "r,g,b" of one pixel of the view
function prPixel pX, pY
   local tData, tAt
   put the imageData of image "b3kView" of card 1 of stack "OrbIsland" into tData
   put (pY * the width of image "b3kView" of card 1 of stack "OrbIsland" + pX) * 4 into tAt
   return byteToNum(byte tAt + 2 of tData) & comma & byteToNum(byte tAt + 3 of tData) & comma & byteToNum(byte tAt + 4 of tData)
end prPixel

-- the fastest dynamic thing (not the player) within pRadius of a point
function prFastestNear pX, pY, pZ, pRadius
   local tThing, tBest
   put 0 into tBest
   repeat for each line tThing in b3kOverlapSphere(pX, pY, pZ, pRadius)
      if tThing is not b3kPlayer() and b3kType(tThing) is "dynamic" then
         put max(tBest, b3kSpeed(tThing)) into tBest
      end if
   end repeat
   return tBest
end prFastestNear

-- the whole run; pR3 says whether render3dxt is loaded, pB3 box3dxt,
-- pGp gamepadxt and pAu audioxt
command prRunAll pR3, pB3, pGp, pAu
   put empty into gPrOut
   put 0 into gPrPassed
   put 0 into gPrFailed
   -- C drops its crates at random spots: a fixed seed makes every run see
   -- the same island, as the hand-stepping promises (2026-11-21: unseeded,
   -- the picture behind one check differed from run to run)
   set the randomSeed to 20261121
   if pB3 is not true then
      prNoExtension
      exit prRunAll
   end if
   prBuild pR3
   if gPrFailed > 0 then exit prRunAll
   prSound pAu
   prDraw
   prLook pR3
   prWalk
   prOrbs
   prFall
   prPad
   prToys
   prCorners
   prKick
   prBlast
   prDrop
   prSparks
   prSoundsHeard pAu
   prRenderers pR3
   prButtonsAndKeys
   prGamepad pGp
   prPlatformer
   prTiming pR3
   prCheck "no frame of the game threw", b3kFrameError() is empty, prLine(b3kFrameError())
   prClose
end prRunAll

-- ---------------------------------------------------------------------
command prBuild pR3
   local tErr, tName, tI, tBad, tCount
   try
      dispatch "openStack" to stack "OrbIsland"
   catch tErr
      prCheck "openStack builds the window and starts a game", false, prLine(tErr)
      exit prBuild
   end try
   prCheck "openStack builds the window and starts a game", true, empty
   prCheck "the window is 1104 by 640", the width of stack "OrbIsland" is 1104 and the height of stack "OrbIsland" is 640, \
         the width of stack "OrbIsland" && the height of stack "OrbIsland"
   repeat for each item tName in "uiTitle,uiStatus,uiFooter,oiScore,oiTime,oiStats,oiKeys,oiBanner"
      prCheck "field " & tName & " is built", there is a field tName of card 1 of stack "OrbIsland", tName
   end repeat
   repeat for each item tName in "oiRestart,oiPause,oiBlast,oiCrates,oiRender,oiSound,oiLook"
      prCheck "button " & tName & " is built", there is a button tName of card 1 of stack "OrbIsland", tName
   end repeat
   prCheck "the view is the Kit's image, 768 by 456 at 16,58", \
         the rect of image "b3kView" of card 1 of stack "OrbIsland" is "16,58,784,514", \
         the rect of image "b3kView" of card 1 of stack "OrbIsland"
   prCheck "the win banner waits hidden", the visible of field "oiBanner" of card 1 of stack "OrbIsland" is false, \
         the visible of field "oiBanner" of card 1 of stack "OrbIsland"
   prCheck "the chrome carries its version stamp", the uOiUIVersion of stack "OrbIsland" is 3, the uOiUIVersion of stack "OrbIsland"
   -- the view's card has no soft shadow (the engine redrew it under every
   -- frame: 10 ms a frame in the web player); the side panel keeps its own,
   -- which shows this engine reads the property at all
   prCheck "no soft shadow under the view", prShadowSize("oiViewCard") is 0, prShadowSize("oiViewCard")
   prCheck "the side panel keeps its soft shadow", prShadowSize("oiSide") is 10, prShadowSize("oiSide")
   -- smooth edges are dropped only in a web page, where render3dxt draws
   -- on one thread inside the frame
   prCheck "this engine is not a web page", oiOnWeb() is false, the platform
   -- the dark-appearance rule: a control that leaves its colours to the
   -- appearance draws light words in the dark one, white on the light page
   put empty into tBad
   repeat with tI = 1 to the number of fields of card 1 of stack "OrbIsland"
      if the foregroundColor of field tI of card 1 of stack "OrbIsland" is empty then
         put the short name of field tI of card 1 of stack "OrbIsland" & " (text) " after tBad
      end if
      if the opaque of field tI of card 1 of stack "OrbIsland" and \
            the backgroundColor of field tI of card 1 of stack "OrbIsland" is empty then
         put the short name of field tI of card 1 of stack "OrbIsland" & " (fill) " after tBad
      end if
   end repeat
   repeat with tI = 1 to the number of buttons of card 1 of stack "OrbIsland"
      put the short name of button tI of card 1 of stack "OrbIsland" into tName
      if tName is not "Probe" then
         if the foregroundColor of button tI of card 1 of stack "OrbIsland" is empty then
            put tName & " (text) " after tBad
         end if
         if the style of button tI of card 1 of stack "OrbIsland" is not "checkbox" and \
               the backgroundColor of button tI of card 1 of stack "OrbIsland" is empty then
            put tName & " (fill) " after tBad
         end if
      end if
   end repeat
   prCheck "every field and button sets its own colours", tBad is empty, tBad
   prCheck "the page is the kit's ground colour", the backgroundColor of card 1 of stack "OrbIsland" is "240,242,246", \
         the backgroundColor of card 1 of stack "OrbIsland"
   prCheck "a world runs", b3kWorld() is not empty and b3kIsRunning() is true, b3kWorld() && b3kIsRunning()
   if pR3 then
      prCheck "render3dxt draws", b3kRenderer() is "render3dxt", b3kRenderer()
      prCheck "off the web it promises smooth edges", oiRendererWords() is "render3dxt draws: textured, lit and glowing, smooth edges.", oiRendererWords()
   else
      prCheck "box3dxt's own renderer draws", b3kRenderer() is "box3dxt", b3kRenderer()
   end if
   prCheck "the renderer button names it", the label of button "oiRender" of card 1 of stack "OrbIsland" is ("Renderer: " & b3kRenderer() & " (V)"), \
         the label of button "oiRender" of card 1 of stack "OrbIsland"
   prCheck "the HUD counts sixteen orbs to find", prField("oiScore") is "Orbs  0 / 16", prField("oiScore")
   prCheck "the status line invites the hunt", prStatus() begins with "Find the 16 golden orbs.", prStatus()
   prCheck "and it is green", the foregroundColor of field "uiStatus" of card 1 of stack "OrbIsland" is "23,128,63", \
         the foregroundColor of field "uiStatus" of card 1 of stack "OrbIsland"
   repeat for each item tName in "hub,arm,lift,sky lift,wrecking ball,jump pad,first domino,hill,sail 0,sail 90,beacon beam," & \
         "sea north,sea south,sea west,sea east"
      prCheck "the island has its " & tName, b3kThingNamed(tName) is not empty, tName
   end repeat
   repeat for each item tName in "A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P"
      prCheck "the island has its orb " & tName, b3kThingNamed("orb " & tName) is not empty, tName
   end repeat
   put b3kThingCount() into tCount
   prCheck "the island is 175 things with the player", tCount is 175, tCount
   prCheck "C may drop sixty more", oiMaxThings() is 234, oiMaxThings()
   prCheck "the player stands at the start", b3kPlayer() is not empty and \
         prNear(b3kX(b3kPlayer()), 0, 0.01) and prNear(b3kZ(b3kPlayer()), 22, 0.01), b3kPosition(b3kPlayer())
   prCheck "the player walks faster than the Kit's default", b3kPlayerGet("moveSpeed") is 6.5, b3kPlayerGet("moveSpeed")
   prCheck "a drag of the view turns the camera", b3kCamDragged() is false and \
         the hilite of button "oiLook" of card 1 of stack "OrbIsland" is true, \
         the hilite of button "oiLook" of card 1 of stack "OrbIsland"
   b3kPause
end prBuild

command prDraw
   local tSky, tGround
   prSteps 1
   prCheck "a frame paints the whole view", \
         the number of bytes of the imageData of image "b3kView" of card 1 of stack "OrbIsland" is 768 * 456 * 4, \
         the number of bytes of the imageData of image "b3kView" of card 1 of stack "OrbIsland"
   put prPixel(384, 4) into tSky
   prCheck "the top of the view is the evening sky", prNear(item 1 of tSky, 238, 6) and prNear(item 2 of tSky, 196, 6) and prNear(item 3 of tSky, 160, 6), tSky
   put prPixel(300, 440) into tGround
   prCheck "the bottom of the view is grass", item 2 of tGround > item 1 of tGround and item 2 of tGround > item 3 of tGround, tGround
end prDraw

command prWalk
   local tZ0, tZ1
   put b3kZ(b3kPlayer()) into tZ0
   b3kInputInject "w"
   prSteps 60
   b3kInputInject empty
   prSteps 30
   put b3kZ(b3kPlayer()) into tZ1
   prCheck "W walks the player north, away from the camera", tZ1 < tZ0 - 3, tZ0 && tZ1
   prCheck "walking into orb A collects it", b3kThingNamed("orb A") is empty and prField("oiScore") is "Orbs  1 / 16", \
         prField("oiScore") && b3kThingNamed("orb A")
   prCheck "the status line counts it", prStatus() is "Orb found: 1 of 16.", prStatus()
   prCheck "walking north faces north", prNear(abs(b3kPlayerFacing()), 180, 20), b3kPlayerFacing()
end prWalk

command prOrbs
   local tLetter, tOrb, tP, tTime
   repeat for each item tLetter in "B,C,D,E,F,G,H,I,J,K,L,M,N,O,P"
      put b3kThingNamed("orb " & tLetter) into tOrb
      put b3kPosition(tOrb) into tP
      b3kPlayerRespawn item 1 of tP, item 2 of tP, item 3 of tP
      prSteps 4
      prCheck "touching orb " & tLetter & " collects it", tOrb is not empty and b3kThingNamed("orb " & tLetter) is empty, \
            tOrb && tP && b3kPosition(b3kPlayer())
   end repeat
   prCheck "the HUD shows all sixteen", prField("oiScore") is "Orbs  16 / 16", prField("oiScore")
   prCheck "the banner shows the time", the visible of field "oiBanner" of card 1 of stack "OrbIsland" is true and \
         prField("oiBanner") begins with "All 16 orbs in", prField("oiBanner")
   prCheck "and the status line too", prStatus() begins with "Every orb found in", prStatus()
   put prField("oiTime") into tTime
   prSteps 60
   prCheck "the clock stops at the last orb", prField("oiTime") is tTime, tTime && prField("oiTime")
end prOrbs

command prFall
   local tCrate
   b3kPlayerRespawn 0, 1, 40
   prSteps 150
   prCheck "a fall into the sea is counted", prField("oiTime") ends with "Falls  1", prField("oiTime")
   prCheck "and puts the player back at the start", prNear(b3kX(b3kPlayer()), 0, 0.5) and prNear(b3kZ(b3kPlayer()), 22, 0.5) and \
         prNear(b3kY(b3kPlayer()), 0.8, 0.3), b3kPosition(b3kPlayer())
   prCheck "and says so", prStatus() begins with "Into the sea!", prStatus()
   put line 1 of b3kOverlapSphere(4.1, 0.425, 18, 0.2) into tCrate
   prCheck "a crate stands in the pyramid", tCrate is not empty and b3kKind(tCrate) is "box", tCrate && b3kKind(tCrate)
   b3kMoveTo tCrate, 0, 3, 40
   prSteps 150
   prCheck "a crate that falls into the sea is gone", b3kIsThing(tCrate) is false, b3kIsThing(tCrate)
end prFall

command prPad
   local tTop, tI
   b3kPlayerRespawn 0, 0.85, -16
   put -99 into tTop
   put 1 into tI
   repeat while tI <= 8
      prSteps 1
      put max(tTop, item 2 of b3kVelocity(b3kPlayer())) into tTop
      add 1 to tI
   end repeat
   prCheck "the jump pad throws the player up", tTop > 8, tTop
   prSteps 30
   prCheck "high into the air", b3kY(b3kPlayer()) > 3.5, b3kY(b3kPlayer())
   prSteps 90
end prPad

command prToys
   local tLift, tLow, tHigh, tY, tArm, tA, tB, tTurn, tBall, tFast, tFar, tP
   put b3kThingNamed("lift") into tLift
   put 99 into tLow
   put -99 into tHigh
   repeat 60 times
      prSteps 10
      put b3kY(tLift) into tY
      put min(tLow, tY) into tLow
      put max(tHigh, tY) into tHigh
   end repeat
   prCheck "the lift rides from the ground to the tower top", tLow < 0.3 and tHigh > 4.85, tLow && tHigh
   put b3kThingNamed("arm") into tArm
   put b3kYaw(tArm) into tA
   prSteps 30
   put b3kYaw(tArm) into tB
   put tB - tA into tTurn
   if tTurn > 180 then subtract 360 from tTurn
   if tTurn < -180 then add 360 to tTurn
   prCheck "the sweeper turns about 45 degrees a second", abs(tTurn) > 15 and abs(tTurn) < 30, tA && tB
   prCheck "and stays at its height", prNear(b3kY(tArm), 0.45, 0.05), b3kY(tArm)
   put b3kThingNamed("wrecking ball") into tBall
   put 0 into tFast
   put 0 into tFar
   repeat 12 times
      prSteps 10
      put max(tFast, b3kSpeed(tBall)) into tFast
      put b3kPosition(tBall) into tP
      put max(tFar, sqrt((item 1 of tP + 12) ^ 2 + (item 2 of tP - 5.2) ^ 2 + (item 3 of tP + 14) ^ 2)) into tFar
   end repeat
   prCheck "the wrecking ball swings", tFast > 2, tFast
   prCheck "and its rope holds it within 4.5 m of the hook", tFar < 4.6, tFar
end prToys

command prKick
   local tCrate, tP, tHV, tHub
   b3kPlayerRespawn 0, 1, 22
   b3kCamOrbit 0, 24, 9.5
   prSteps 45
   put line 1 of b3kOverlapSphere(5, 0.425, 18, 0.2) into tCrate
   prCheck "a crate to kick", tCrate is not empty, tCrate
   put b3kPosition(tCrate) into tP
   put b3kProject(item 1 of tP, item 2 of tP, item 3 of tP) into tHV
   prCheck "the crate is on the view", item 1 of tHV > 16 and item 1 of tHV < 784 and item 2 of tHV > 58 and item 2 of tHV < 514, tHV
   oiKick item 1 of tHV, item 2 of tHV
   prSteps 1
   prCheck "a click on a crate kicks it", b3kSpeed(tCrate) > 3, b3kSpeed(tCrate)
   put b3kThingNamed("hub") into tHub
   put b3kProject(0, 0.9, 0) into tHV
   oiKick item 1 of tHV, item 2 of tHV
   oiKick 400, 62
   prSteps 1
   prCheck "a click on scenery or sky moves nothing", b3kSpeed(tHub) is 0 and b3kFrameError() is empty, b3kSpeed(tHub)
end prKick

command prBlast
   b3kPlayerRespawn 5, 1, 21.5
   b3kInputInject "w"
   prSteps 8
   b3kInputInject empty
   prSteps 30
   prCheck "a crate pyramid stands still before the blast", prFastestNear(5, 1, 18, 2.5) < 0.5, prFastestNear(5, 1, 18, 2.5)
   b3kResume
   oiBlast
   b3kPause
   prSteps 2
   prCheck "X blasts what is in front of the player", prFastestNear(5, 1, 18, 3) > 2, prFastestNear(5, 1, 18, 3)
end prBlast

command prDrop
   local tCount
   put b3kThingCount() into tCount
   b3kResume
   oiDropCrates
   b3kPause
   prCheck "C drops five things", b3kThingCount() is tCount + 5, tCount && b3kThingCount()
   b3kResume
   repeat 20 times
      oiDropCrates
   end repeat
   b3kPause
   prCheck "C stops sixty things past the island", b3kThingCount() >= oiMaxThings() and b3kThingCount() < oiMaxThings() + 5, b3kThingCount()
   prCheck "and says why", prStatus() begins with "That is plenty", prStatus()
   prSteps 60
   prCheck "ninety things fall and settle without a frame error", b3kFrameError() is empty, prLine(b3kFrameError())
end prDrop

command prRenderers pR3
   local tGround
   if pR3 then
      -- back to the start first, so the camera frames the island as it did
      -- for the first frame (prDraw): the blast and the crates leave the
      -- player anywhere, and once left falling past the island's edge, with
      -- nothing but sky behind the bottom of the view (2026-11-21)
      b3kPlayerRespawn 0, 1, 22
      prSteps 60
      b3kCamOrbit 0, 24, 9.5
      prSteps 30
      oiNextRenderer
      prCheck "V's handler swaps to box3dxt's renderer", b3kRenderer() is "box3dxt", b3kRenderer()
      prCheck "and the button says so", the label of button "oiRender" of card 1 of stack "OrbIsland" is "Renderer: box3dxt (V)", \
            the label of button "oiRender" of card 1 of stack "OrbIsland"
      prSteps 2
      put prPixel(300, 440) into tGround
      prCheck "box3dxt's renderer draws the island", b3kFrameError() is empty and \
            not (prNear(item 1 of tGround, 238, 6) and prNear(item 2 of tGround, 196, 6) and prNear(item 3 of tGround, 160, 6)), \
            tGround && b3kPosition(b3kPlayer())
      dispatch "keyDown" to stack "OrbIsland" with "v"
      prCheck "the V key swaps back to render3dxt", b3kRenderer() is "render3dxt", b3kRenderer()
   else
      oiNextRenderer
      prCheck "V without render3dxt keeps box3dxt's renderer", b3kRenderer() is "box3dxt", b3kRenderer()
      prCheck "and says render3dxt is not loaded", prStatus() begins with "render3dxt is not loaded", prStatus()
   end if
end prRenderers

command prButtonsAndKeys
   dispatch "mouseUp" to button "oiPause" of card 1 of stack "OrbIsland" with 1
   prCheck "the Pause button resumes a paused game", b3kIsPaused() is false and \
         the label of button "oiPause" of card 1 of stack "OrbIsland" is "Pause (P)", b3kIsPaused()
   dispatch "keyDown" to stack "OrbIsland" with "p"
   prCheck "P pauses it", b3kIsPaused() is true and \
         the label of button "oiPause" of card 1 of stack "OrbIsland" is "Resume (P)", b3kIsPaused()
   dispatch "mouseUp" to button "oiLook" of card 1 of stack "OrbIsland" with 1
   prCheck "the look box unticks", the hilite of button "oiLook" of card 1 of stack "OrbIsland" is false, \
         the hilite of button "oiLook" of card 1 of stack "OrbIsland"
   dispatch "mouseUp" to button "oiLook" of card 1 of stack "OrbIsland" with 1
   prCheck "and ticks again", the hilite of button "oiLook" of card 1 of stack "OrbIsland" is true, \
         the hilite of button "oiLook" of card 1 of stack "OrbIsland"
   dispatch "keyDown" to stack "OrbIsland" with "r"
   prCheck "R starts a new run", prField("oiScore") is "Orbs  0 / 16" and b3kThingCount() is 175 and b3kIsRunning() is true, \
         prField("oiScore") && b3kThingCount() && b3kIsRunning()
   prCheck "with the clock and falls at zero", prField("oiTime") is "Time  0.0 s      Falls  0", prField("oiTime")
   b3kPause
   prSteps 30
   dispatch "mouseUp" to button "oiRestart" of card 1 of stack "OrbIsland" with 1
   prCheck "the Restart button starts a new run", prField("oiScore") is "Orbs  0 / 16" and b3kThingCount() is 175, \
         prField("oiScore") && b3kThingCount()
   b3kPause
   dispatch "keyDown" to stack "OrbIsland" with "a"
   prCheck "a walking key is passed on, not eaten", it is "passed", it
end prButtonsAndKeys

-- ---------------------------------------------------------------------
-- the sound: audioxt's silent test device when audioxt is loaded (a test
-- machine may have no sound card), and a harmless "none" when it is not
command prSound pAu
   if pAu is true then
      oiSoundStart -1
      prCheck "with audioxt the game makes an audio engine", oiSoundOn() is true, oiSoundOn()
      prCheck "and the sound button says it is on", the label of button "oiSound" of card 1 of stack "OrbIsland" is "Sound: on (M)", \
            the label of button "oiSound" of card 1 of stack "OrbIsland"
   else
      prCheck "without audioxt the game is silent", oiSoundOn() is false, oiSoundOn()
      prCheck "and the sound button says so", the label of button "oiSound" of card 1 of stack "OrbIsland" is "Sound: none (M)", \
            the label of button "oiSound" of card 1 of stack "OrbIsland"
   end if
end prSound

-- the late-afternoon look: lamps, glowing orbs that pulse, the sea
command prLook pR3
   local tOrb, tGlow, tSea
   prCheck "the island hangs five lamps", the number of lines of b3kLamps() is 5, b3kLamps()
   if pR3 then
      prCheck "render3dxt lights it with the sun and the five lamps", item 6 of r3LiveCounts() is 6, r3LiveCounts()
   end if
   put b3kThingNamed("orb B") into tOrb
   put b3kGlow(tOrb) into tGlow
   prCheck "an orb glows", tGlow is not empty, tGlow
   prSteps 16
   prCheck "and its glow pulses", b3kGlow(tOrb) is not empty and b3kGlow(tOrb) is not tGlow, tGlow && b3kGlow(tOrb)
   put b3kThingNamed("sea north") into tSea
   prCheck "the sea is a sensor, so a fall passes through it", b3kKind(tSea) is "sensor" and b3kIsVisible(tSea) is true, b3kKind(tSea)
   prCheck "the kill floor is below the sea", b3kY(tSea) > -6, b3kY(tSea)
end prLook

-- the corners and the floating isle
command prCorners
   local tSky, tLowZ, tHighZ, tHighY, tSail, tA, tB, tBeam, tFirst, tLast
   -- the sky lift: out over the sea to the isle and back
   put b3kThingNamed("sky lift") into tSky
   put 99 into tLowZ
   put -99 into tHighZ
   put -99 into tHighY
   repeat 100 times
      prSteps 8
      put min(tLowZ, b3kZ(tSky)) into tLowZ
      put max(tHighZ, b3kZ(tSky)) into tHighZ
      put max(tHighY, b3kY(tSky)) into tHighY
   end repeat
   prCheck "the sky lift rides from the island's edge out to the isle", tHighZ > -28 and tLowZ < -35.5 and tHighY > 4.2, tLowZ && tHighZ && tHighY
   -- the windmill's sails and the beacon's beam turn
   put b3kThingNamed("sail 0") into tSail
   put b3kRotation(tSail) into tA
   prSteps 20
   prCheck "the windmill turns", b3kRotation(tSail) is not tA, tA
   put b3kThingNamed("beacon beam") into tBeam
   put b3kYaw(tBeam) into tA
   prSteps 30
   put b3kYaw(tBeam) into tB
   prCheck "the beacon's beam sweeps round", abs(tB - tA) > 10, tA && tB
   -- the player stands on the hill and on the floating isle
   b3kPlayerRespawn -16, 3.4, 13
   prSteps 60
   prCheck "the hill holds the player up", b3kY(b3kPlayer()) > 2.3, b3kPosition(b3kPlayer())
   b3kPlayerRespawn 0, 5.6, -43
   prSteps 60
   prCheck "the floating isle holds the player up", prNear(b3kY(b3kPlayer()), 5.3, 0.3), b3kPosition(b3kPlayer())
   -- the dominoes: a push on the first fells the last
   put b3kThingNamed("first domino") into tFirst
   put line 1 of b3kOverlapSphere(11 + 0.85 * 15, 0.7, 26, 0.05) into tLast
   prCheck "sixteen dominoes stand in a row", tFirst is not empty and tLast is not empty and tLast is not tFirst, tFirst && tLast
   b3kPush tFirst, 2.5, 0, 0
   prSteps 300
   prCheck "a push on the first domino fells the last", b3kY(tLast) < 0.45, b3kPosition(tLast)
   b3kPlayerRespawn 0, 1, 22
   prSteps 30
end prCorners

-- the platformer pieces: the plate and the vault's gate, the crumbling
-- and turning platforms out east, and the checkpoint flags
command prPlatformer
   local tCrate, tGate, tPlate, tTurn, tA, tCrumble, tFlag, tSpot
   put b3kThingNamed("heavy crate") into tCrate
   put b3kThingNamed("gate") into tGate
   put b3kThingNamed("plate") into tPlate
   prCheck "the vault has a gate, a plate and a heavy crate", tCrate is not empty and tGate is not empty and tPlate is not empty, \
         tCrate && tGate && tPlate
   prCheck "the gate starts shut", prNear(b3kY(tGate), 1.6, 0.05) and not oiPlateIsDown(), b3kPosition(tGate)
   -- the crate set on the plate holds it down, and the gate sinks
   b3kMoveTo tCrate, 22, 0.9, -17
   prSteps 90
   prCheck "a crate on the plate presses it", oiPlateIsDown(), b3kPosition(tCrate) && b3kPosition(tPlate)
   prCheck "and the gate sinks into the ground", b3kY(tGate) < -1.5, b3kPosition(tGate)
   -- taken off, the gate rises again a little later
   b3kMoveTo tCrate, 19.5, 0.9, -19.5
   prSteps 30
   prCheck "the gate waits a moment once nothing presses", b3kY(tGate) < -1.5, b3kPosition(tGate)
   prSteps 120
   prCheck "then shuts again", prNear(b3kY(tGate), 1.6, 0.05) and not oiPlateIsDown(), b3kPosition(tGate)
   -- the player alone presses it too
   b3kPlayerRespawn 22, 1.2, -17
   prSteps 40
   prCheck "the player on the plate presses it", oiPlateIsDown(), b3kPosition(b3kPlayer())
   b3kPlayerRespawn 0, 1, 22
   prSteps 200
   prCheck "and it rises when the player leaves", not oiPlateIsDown(), b3kPosition(tGate)
   -- the turning platform turns
   put b3kThingNamed("turning platform") into tTurn
   put b3kYaw(tTurn) into tA
   prSteps 30
   prCheck "the turning platform turns", tTurn is not empty and abs(b3kYaw(tTurn) - tA) > 5, tA && b3kYaw(tTurn)
   -- a crumbling platform: stood on, it shakes, falls, and comes back
   put b3kThingNamed("crumble 1") into tCrumble
   prCheck "three crumbling platforms out east", tCrumble is not empty and b3kThingNamed("crumble 3") is not empty, tCrumble
   b3kPlayerRespawn 32, 1.2, 0
   prSteps 20
   prCheck "a crumbling platform holds the player at first", b3kY(b3kPlayer()) > 0.5 and b3kType(tCrumble) is "static", \
         b3kPosition(b3kPlayer()) && b3kType(tCrumble)
   prSteps 60
   prCheck "then lets go and falls", b3kIsThing(tCrumble) is false or b3kType(tCrumble) is "dynamic", b3kType(tCrumble)
   prCheck "and the player falls with it", b3kY(b3kPlayer()) < 0, b3kPosition(b3kPlayer())
   b3kPlayerRespawn 0, 1, 22
   prSteps 330
   put b3kThingNamed("crumble 1") into tSpot
   prCheck "a fallen platform comes back", tSpot is not empty and b3kType(tSpot) is "static" and prNear(b3kY(tSpot), -0.25, 0.01), \
         tSpot && b3kPosition(tSpot)
   -- a flag is a checkpoint: a fall then puts the player back by it
   put b3kThingNamed("flag east islet") into tFlag
   prCheck "three checkpoint flags", tFlag is not empty and b3kThingNamed("flag sky isle") is not empty and b3kThingNamed("flag west rock") is not empty, tFlag
   prCheck "the run starts with the start as its checkpoint", oiCheckpoint() is "0,1,22", oiCheckpoint()
   b3kPlayerRespawn 51.5, 1, -2.2
   prSteps 20
   prCheck "touching a flag makes it the checkpoint", oiCheckpoint() is "51.5,1,-2.2", oiCheckpoint()
   b3kPlayerRespawn 60, 1, 0
   prSteps 120
   prCheck "a fall puts the player back at the checkpoint", prNear(b3kX(b3kPlayer()), 51.5, 0.3) and prNear(b3kZ(b3kPlayer()), -2.2, 0.3), \
         b3kPosition(b3kPlayer())
   prCheck "orb I waits on the east islet", b3kThingNamed("orb I") is not empty and prNear(b3kX(b3kThingNamed("orb I")), 50.5, 0.01), \
         b3kPosition(b3kThingNamed("orb I"))
   b3kPlayerRespawn 0, 1, 22
   prSteps 30
end prPlatformer

-- a found orb bursts into eight sparks that are gone in a second and a half
command prSparks
   local tCount
   put b3kThingCount() into tCount
   oiSparks 0, 2, 10
   prCheck "a burst is eight sparks", b3kThingCount() is tCount + 8, tCount && b3kThingCount()
   prSteps 100
   prCheck "and they are gone a second and a half later", b3kThingCount() is tCount, tCount && b3kThingCount()
end prSparks

-- every sound the game plays is asked for (whether or not audioxt is
-- there to play it), and with audioxt each voice is freed when it ends
command prSoundsHeard pAu
   local tName, tMissing
   b3kPlayerRespawn 0, 1, 22
   prSteps 30
   b3kInputInject "space"
   prSteps 3
   b3kInputInject empty
   prSteps 60
   put empty into tMissing
   repeat for each item tName in "orb,jump,pad,splash,blast,kick,drop,win"
      if tName is not among the lines of oiSoundsPlayed() then put tName & " " after tMissing
   end repeat
   prCheck "each sound is asked for: orb, jump, pad, splash, blast, kick, drop, win", tMissing is empty, tMissing
   if pAu is not true then exit prSoundsHeard
   oiSound "blast"
   prCheck "a sound is a voice waiting to be freed", oiSoundVoices() > 0, oiSoundVoices()
   prSteps 150
   prCheck "and every voice is freed once it is done", oiSoundVoices() is 0, oiSoundVoices()
   dispatch "keyDown" to stack "OrbIsland" with "m"
   prCheck "M turns the sound off", the label of button "oiSound" of card 1 of stack "OrbIsland" is "Sound: off (M)", \
         the label of button "oiSound" of card 1 of stack "OrbIsland"
   dispatch "mouseUp" to button "oiSound" of card 1 of stack "OrbIsland" with 1
   prCheck "and the Sound button on again", the label of button "oiSound" of card 1 of stack "OrbIsland" is "Sound: on (M)", \
         the label of button "oiSound" of card 1 of stack "OrbIsland"
end prSoundsHeard

-- the gamepad: a virtual pad of gamepadxt's, when it is loaded
command prGamepad pGp
   local tPad, tZ, tY, tYaw
   if pGp is not true then
      prCheck "without gamepadxt there is no pad", oiPadOn() is false and oiPadWords() is "not loaded", oiPadWords()
      exit prGamepad
   end if
   prCheck "with gamepadxt the game starts it", oiPadOn() is true, oiPadOn()
   if oiPadOn() is not true then exit prGamepad
   b3kPause
   b3kPlayerRespawn 0, 1, 22
   b3kCamOrbit 0, 22, 10
   prSteps 30
   put gpVirtualAttach("Orb test pad") into tPad
   prSteps 2
   prCheck "a pad that arrives is taken up", oiPadWords() is "Orb test pad", oiPadWords()
   put b3kZ(b3kPlayer()) into tZ
   get gpVirtualSetAxis(tPad, "lefty", -1)
   prSteps 40
   prCheck "the left stick pushed up walks the player north", b3kZ(b3kPlayer()) < tZ - 2, tZ && b3kZ(b3kPlayer())
   get gpVirtualSetAxis(tPad, "lefty", 0)
   prSteps 40
   prCheck "and let go, the player stops", b3kSpeed(b3kPlayer()) < 0.5, b3kSpeed(b3kPlayer())
   put b3kY(b3kPlayer()) into tY
   get gpVirtualSetButton(tPad, "south", true)
   prSteps 1
   get gpVirtualSetButton(tPad, "south", false)
   prSteps 6
   prCheck "A (south) jumps", b3kY(b3kPlayer()) > tY + 0.2, tY && b3kY(b3kPlayer())
   prSteps 60
   put b3kCamYaw() into tYaw
   get gpVirtualSetAxis(tPad, "rightx", 1)
   prSteps 10
   get gpVirtualSetAxis(tPad, "rightx", 0)
   prSteps 1
   prCheck "the right stick turns the camera", abs(b3kCamYaw() - tYaw) > 20, tYaw && b3kCamYaw()
   b3kResume
   get gpVirtualSetButton(tPad, "west", true)
   prSteps 1
   get gpVirtualSetButton(tPad, "west", false)
   prSteps 1
   prCheck "X (west) blasts", "blast" is among the lines of oiSoundsPlayed(), oiSoundsPlayed()
   get gpVirtualSetButton(tPad, "start", true)
   prSteps 1
   get gpVirtualSetButton(tPad, "start", false)
   prSteps 1
   prCheck "Start pauses", b3kIsPaused() is true, b3kIsPaused()
   get gpVirtualSetButton(tPad, "start", true)
   prSteps 1
   get gpVirtualSetButton(tPad, "start", false)
   prSteps 1
   prCheck "and Start again plays on", b3kIsPaused() is false, b3kIsPaused()
   b3kPause
   gpVirtualDetach tPad
   prSteps 2
   prCheck "a pad that leaves is let go", oiPadWords() is "none connected", oiPadWords()
end prGamepad

command prTiming pR3
   local tStart, tMs
   put the milliseconds into tStart
   prSteps 60
   put (the milliseconds - tStart) / 60 into tMs
   prInfo "one frame of the island (physics, the Kit, the picture at 768 x 456), " & b3kRenderer() & ": " & round(tMs, 1) & " ms"
   if pR3 then
      b3kUseRenderer "box3dxt"
      put the milliseconds into tStart
      prSteps 60
      put (the milliseconds - tStart) / 60 into tMs
      prInfo "the same frame, box3dxt's renderer: " & round(tMs, 1) & " ms"
      b3kUseRenderer "render3dxt"
   end if
end prTiming

command prClose
   dispatch "closeStack" to stack "OrbIsland"
   prCheck "closing the stack tears the world down", b3kWorld() is empty, b3kWorld()
end prClose

-- without box3dxt: the window still builds and says why nothing runs, and
-- no button or key throws
command prNoExtension
   local tErr, tWhere
   try
      dispatch "openStack" to stack "OrbIsland"
   catch tErr
      prCheck "without box3dxt, openStack still builds the window", false, prLine(tErr)
      exit prNoExtension
   end try
   prCheck "without box3dxt, openStack still builds the window", there is a field "oiScore" of card 1 of stack "OrbIsland", empty
   prCheck "the status line says why nothing runs", prStatus() begins with "Nothing can run: the box3dxt extension is not loaded", prStatus()
   prCheck "in red", the foregroundColor of field "uiStatus" of card 1 of stack "OrbIsland" is "176,58,46", \
         the foregroundColor of field "uiStatus" of card 1 of stack "OrbIsland"
   put "start" into tWhere
   try
      put "Blast" into tWhere
      oiBlast
      put "Drop crates" into tWhere
      oiDropCrates
      put "Pause" into tWhere
      oiTogglePause
      put "Renderer" into tWhere
      oiNextRenderer
      put "a click on the view" into tWhere
      oiKick 300, 200
      put "R" into tWhere
      dispatch "keyDown" to stack "OrbIsland" with "r"
      put "M" into tWhere
      dispatch "keyDown" to stack "OrbIsland" with "m"
      put "the Pause button" into tWhere
      dispatch "mouseUp" to button "oiPause" of card 1 of stack "OrbIsland" with 1
      put "closeStack" into tWhere
      dispatch "closeStack" to stack "OrbIsland"
      put empty into tWhere
   catch tErr
   end try
   prCheck "every button and key is harmless without box3dxt", tWhere is empty, tWhere && prLine(tErr)
end prNoExtension
