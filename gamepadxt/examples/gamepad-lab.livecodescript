script "GamepadLab"
-- gamepad-lab.livecodescript - Gamepad Lab: everything gamepadxt does, in
-- one window that builds itself. One paste-and-run file.
--
-- WHAT THIS IS. gamepadxt reads game controllers through SDL 3's gamepad
-- layer. This window shows all of it: the controllers plugged in and what
-- they are, every button, stick and trigger as it moves, the events each
-- poll gathers, the dead zone, rumble, the light, player numbers and the
-- mapping SDL reads a pad by. It opens playing: a touch pad (a controller
-- made in software by gpVirtualAttach) plays five showcases in turn, one
-- thing each. Plug a controller in, or press a button on one, and it takes
-- over. The mouse and the keys drive the touch pad too.
--
-- WHAT TO LOOK AT AS A TEMPLATE. glFrame is the loop a game uses, from a
-- timer sixty times a second:
--
--    get gpPoll()                             -- what the pads did
--    put gpEvents() into tEvents              -- presses and plugs, a line each
--    put gpPadStick(sPad, "left") into sLeft  -- where the stick is now
--    put gpPadButtons(sPad) into tHeld        -- what is held now
--
-- The library never calls a handler of this stack: the stack asks and the
-- library answers, so nothing ever runs on another thread. glPlay is the
-- small game under the drawing, and it is a dozen lines.
--
-- HOW TO USE. Paste this into a new stack's script, then close and reopen
-- the stack: the window builds itself. Opening this file directly does not
-- build it (docs/OXT-ENGINE-NOTES.md 5.5). With no gamepadxt the window
-- still opens, says so in words, and plays the showcases as a recording.
--
-- HONESTY (the suite convention): this script has run on OXT-Beyond's Linux
-- desktop engine with no display, over virtual pads, with the library and
-- without it (tests/demo-drive.livecodescript, 2026-11-21: the window built,
-- the showcases played, a second pad took over, every control was driven by
-- message); in the IDE on Windows (2026-11-21: it opened and played its
-- first showcase on the software pad); and in OXT-Beyond 0.2.8-dp.2.1's web
-- Stack Player in headless Chromium (2026-11-22: the showcases played, and a
-- pad the test put into the browser's Gamepad API took over). No real
-- controller has driven it and no Mac has run it: verified statically;
-- needs an OXT pass.
--
-- THE LOOK is this stack's own, a dark stage like the suite's 3D demos:
-- every field and button says its own colours, so a dark system theme
-- leaves nothing white on white.
--
-- By Seth Morrow. MIT, as the rest of gamepadxt.

-- Bumped whenever the window changes, so a saved stack rebuilds it.
constant kGlUiVersion = "gamepad-lab-3"
constant kGlWidth = 1180
constant kGlHeight = 640
constant kFrameMs = 16
-- Where the drawing of a controller goes: its builder's numbers are drawn
-- about 268,62 and moved here.
constant kPadLeft = 100
constant kPadTop = 100
constant kButtons = "south,east,west,north,back,guide,start,leftstick,rightstick,leftshoulder,rightshoulder,dpup,dpdown,dpleft,dpright,misc1,rightpaddle1,leftpaddle1,rightpaddle2,leftpaddle2,touchpad,misc2,misc3,misc4,misc5,misc6"
constant kAxes = "leftx,lefty,rightx,righty,lefttrigger,righttrigger"
-- The first showcase presses them in this order
constant kWave = "south,east,west,north,leftshoulder,rightshoulder,dpup,dpright,dpdown,dpleft,back,guide,start,leftstick,rightstick,touchpad,leftpaddle1,leftpaddle2,rightpaddle1,rightpaddle2,misc1,misc2,misc3,misc4,misc5,misc6"
constant kSceneTitles = "Every button|Sticks and the dead zone|Rumble, light and players|Remap a button|A small game"
constant kSceneLabels = "1. Every button|2. Sticks, dead zone|3. Rumble and light|4. Remap a button|5. A small game"
constant kSceneMs = "10400,12000,10000,10800,12600"
-- The colours: a dark stage, light words, one warm accent
constant kBg = "20,23,30"
constant kPanel = "28,32,41"
constant kPanelLine = "46,52,64"
constant kStage = "15,17,22"
constant kText = "222,226,234"
constant kDim = "150,160,178"
constant kAccent = "255,150,60"
constant kLive = "96,200,110"
constant kIdle = "62,69,82"
constant kKnob = "104,113,130"
constant kBody = "44,49,58"
constant kInk = "210,214,222"
constant kWell = "30,34,41"
constant kWellLine = "70,78,92"
constant kHeld = "255,176,58"
constant kButtonFill = "40,46,60"
constant kButtonLine = "92,104,124"
constant kButtonText = "230,233,238"
constant kOnText = "24,26,32"
-- The small words on the drawing's buttons
constant kLabelInk = "180,188,202"
constant kLeds = "255,64,64|255,150,40|80,220,100|60,210,230|70,120,255|190,90,255|0,0,0"
constant kBallColours = "255,176,58|96,200,110|80,150,240|230,90,80|240,200,70|190,90,255"
constant kLogLines = 200
-- Arrow keys, then Z X A S Q W and Return in both cases, and Enter
constant kDriveKeys = "65361,65362,65363,65364,122,120,97,115,113,119,90,88,65,83,81,87,65293,65421"
-- The small game's course, as fractions of the arena; a point outside it
-- is a wall to run into
constant kCourse = "0.14,0.3|0.86,0.3|1.3,0.55|0.84,0.78|0.16,0.76|-0.3,0.45|0.5,0.5"
-- How far the arena's caption reaches down into it: the ball rolls below
-- it, so a ball pushed into the top left never sits on the caption's words
constant kArenaCaption = 20

local sRunning       -- true while the frame loop runs
local sLib           -- true when gamepadxt is in this engine
local sStarted       -- true between a gpStart() that worked and gpStop
local sGhost         -- true when a recording plays instead (no library)
local sOpenedAt      -- the milliseconds when the window opened
local sFrame         -- the pending glFrame message, empty for none
local sPad           -- the pad on show, 0 for none
local sPadName
local sPadVirtual    -- whether it is a virtual pad
local sPadList       -- the handles in the order the list shows them
local sTouch         -- the touch pad this stack made, 0 for none
local sHeld          -- the buttons drawn held
local sAxes          -- the axes drawn
local sLeft, sRight  -- the sticks with the dead zone taken out, this frame
local sReadout
local sDrag          -- what the mouse drives on the touch pad: empty,
                     -- left, right, lefttrigger, righttrigger or a button
local sDragFrom, sDragStart, sDragMoved
local sKeys          -- the drive keys held, by key code
local sVSet          -- what the touch pad was last told, by button or axis
local sLog, sLogDirty, sLogShownAt, sT0, sFrames
local sBallX, sBallY, sBallShown, sJump, sWasHit, sBallColour, sFlash
local sRumbleUntil, sRumbleAsked, sRumbleShown, sShake, sLed
local sGreetUntil, sGlow
local sFirstMapping  -- each pad's mapping as first shown, by its GUID
local sChipText, sChipColour, sChipBar
-- The showcases
local sScene         -- the showcase playing, 0 for none
local sSceneAt       -- the milliseconds it began
local sTour          -- true while the five play one after another
local sDone          -- the one-off steps this showcase has taken
local sSaved         -- what a showcase changes, to put back after
local sWay, sWayAt   -- the small game's next point, and since when
-- The recording, when there is no library
local sGhostButtons, sGhostAxes, sGhostDZ, sGhostSwap, sGhostPlayer, sGhostLED
local sGhostMotors, sGhostMotorsUntil, sGhostTrig, sGhostTrigUntil
-- The library's dead zone and axis step are the whole process's: what this
-- window found, put back when it closes
local sFoundZone, sFoundStep
-- A box's own scroll bar while it is dragged: the box, where the drag
-- began and the box's scroll then
local sMarkDrag, sMarkY, sMarkScroll

----------------------------------------------------------------
-- Opening and closing

on preOpenStack
   glBuild
end preOpenStack

on openStack
   glOpen
end openStack

on closeStack
   glClose
end closeStack

command glOpen
   local tOk, tError
   set the defaultStack to the short name of me
   glBuild
   if sRunning is true then glClose
   put 0 into sPad
   put empty into sPadName
   put false into sPadVirtual
   put 0 into sTouch
   put empty into sPadList
   put empty into sDrag
   put empty into sKeys
   put empty into sVSet
   put 0 into sFrames
   put 0 into sShake
   put 0 into sRumbleUntil
   put "0,0,0,0" into sRumbleAsked
   put empty into sRumbleShown
   put empty into sLed
   put 0 into sGreetUntil
   put empty into sGlow
   put empty into sChipText
   put empty into sChipColour
   put empty into sChipBar
   put 0 into sScene
   put false into sTour
   put 1 into sBallColour
   put 0 into sLogShownAt
   put the milliseconds into sOpenedAt
   if sT0 is empty then
      put the milliseconds into sT0
      put empty into sLog
   end if
   glCentreBall
   glLightShown empty
   put false into sLib
   put false into sStarted
   put false into tOk
   try
      put gpStart() into tOk
      put true into sLib
   catch tError
      put false into sLib
   end try
   -- running from here: the list and the info read it
   put true into sRunning
   if sLib and tOk is true then
      put false into sGhost
      put true into sStarted
      put gpDeadZone() into sFoundZone
      put gpAxisEvents() into sFoundStep
      set the label of button "startStop" to "Stop"
      glStatusLibrary
      set the thumbPosition of scrollbar "deadZone" of me to round(gpDeadZone() * 100)
      set the hilite of button "axisEvents" of me to gpAxisEvents() > 0
      glShowDeadZone
      glLog "started: SDL reads the controllers, gpPoll() every" && kFrameMs && "ms"
      glAttachTouch
      glSelect sTouch
   else
      -- Nothing to read controllers with: the rest of the window still
      -- works, on a recording of the touch pad
      if sLib then
         glLog "gpStart() refused:" && gpLastError()
         glStatus "Controllers cannot be read here:" && gpLastError()
      else
         glStatus "gamepadxt is not installed: a recording plays"
      end if
      put true into sGhost
      glGhostReset
      set the label of button "startStop" to "Stop"
      set the thumbPosition of scrollbar "deadZone" of me to 15
      glShowDeadZone
      glLog "no gamepadxt here: the touch pad below is a recording"
      glSelect 0
   end if
   glStrengths
   put true into sTour
   glPlayScene 1
   glShowLog
   glSchedule
end glOpen

command glClose
   if sFrame is not empty then
      cancel sFrame
      put empty into sFrame
   end if
   put false into sRunning
   glStopScene
   put false into sTour
   if sStarted is true then
      put false into sStarted
      -- the touch pad is this window's: a start another stack holds would
      -- keep it open after gpStop
      if sTouch is not 0 then gpVirtualDetach sTouch
      if sFoundZone is a number then gpSetDeadZone sFoundZone
      if sFoundStep is a number then gpSetAxisEvents sFoundStep
      gpStop
   end if
   put 0 into sTouch
   put 0 into sPad
   put false into sPadVirtual
   put empty into sDrag
   put empty into sKeys
end glClose

command glStartStop
   if sRunning is true then
      glClose
      -- starts are counted: another stack's start keeps the pads open
      if sLib and gpIsStarted() then
         glLog "stopped here; another stack still reads controllers"
      else if sLib then
         glLog "stopped: gpStop closed every pad"
      else
         glLog "stopped"
      end if
      set the label of button "startStop" to "Start"
      glListPads
      glShowInfo
      glDrawNothing
      glShowSceneButtons
      glChipUpdate the milliseconds
      glAbout "Stopped. Start reads the controllers again and plays the showcases."
      glStatus "Stopped"
      glShowLog
   else
      glOpen
   end if
end glStartStop

----------------------------------------------------------------
-- The frame: a showcase's step, the poll, what happened, what is held

command glSchedule
   if sRunning is true and sFrame is empty then
      send "glFrame" to me in kFrameMs milliseconds
      put the result into sFrame
   end if
end glSchedule

on glFrame
   local tEvents, tError, tNow
   put empty into sFrame
   if sRunning is not true then exit glFrame
   -- a timer runs with whatever stack is the default; this one's controls
   -- are meant
   set the defaultStack to the short name of me
   lock screen
   try
      put the milliseconds into tNow
      if sScene > 0 then glSceneStep tNow - sSceneAt
      if sStarted is true then
         get gpPoll()
         if gpEventCount() > 0 then
            put gpEvents() into tEvents
            glEvents tEvents
         end if
      end if
      glRead
      glDraw
      glPlay
      glChipUpdate tNow
      if sLogDirty is true and tNow - sLogShownAt > 100 then glShowLog
      add 1 to sFrames
      if sFrames mod 30 is 1 then glFooter
   catch tError
      glLog "error in the frame:" && line 1 of tError
      glShowLog
   end try
   unlock screen
   glSchedule
end glFrame

-- What gpEvents() gave, one event a line, oldest first
command glEvents pEvents
   local tLine, tRelist, tPad
   put false into tRelist
   repeat for each line tLine in pEvents
      glLog tLine
      put item 2 of tLine into tPad
      switch item 1 of tLine
         case "connected"
            put true into tRelist
            if tPad is not sTouch then
               -- a pad there when the window opened waits for a press; one
               -- plugged in later takes over at once
               if the milliseconds - sOpenedAt < 1500 then
                  glLog "found:" && gpPadName(tPad) & ": press a button on it to take over"
                  glStatus "Found" && gpPadName(tPad) & ": press a button on it to take over"
               else
                  glTakeOver tPad
               end if
            end if
            break
         case "disconnected"
            put true into tRelist
            if tPad is sTouch then put 0 into sTouch
            if tPad is sPad then glSelect glNextPad()
            break
         case "button"
            if tPad is sPad then
               if item 4 of tLine is "down" then
                  glPressed item 3 of tLine
               end if
            else if tPad is not sTouch and item 4 of tLine is "down" then
               glTakeOver tPad
            end if
            break
      end switch
   end repeat
   if tRelist then glListPads
end glEvents

-- A controller arrived, or one not on show was pressed: it is shown, and
-- greeted with a short buzz and a green light where it has them
command glTakeOver pPad
   if not gpPadIsConnected(pPad) then exit glTakeOver
   glStopScene
   put false into sTour
   glShowSceneButtons
   glSelect pPad
   if gpPadHasRumble(pPad) then
      if gpPadRumble(pPad, 0.3, 0.6, 220) then
         put the milliseconds + 220 into sRumbleUntil
         put "0.3,0.6,0,0" into sRumbleAsked
      end if
   end if
   if gpPadHasLED(pPad) then
      if gpPadSetLED(pPad, 80, 220, 100) then put "80,220,100" into sLed
   end if
   glLightShown empty
   put the milliseconds + 1200 into sGreetUntil
   glStatusLibrary
   glLog "hello," && sPadName
   glAboutIdle
end glTakeOver

-- The pad to show when the one on show goes: another controller, or the
-- touch pad
function glNextPad
   local tPad
   if sStarted is not true then return 0
   repeat for each item tPad in gpPads()
      if tPad is not sPad and tPad is not sTouch then return tPad
   end repeat
   if sTouch is not 0 and gpPadIsConnected(sTouch) then return sTouch
   return 0
end glNextPad

----------------------------------------------------------------
-- The controllers

command glAttachTouch
   if sStarted is not true or sTouch is not 0 then exit glAttachTouch
   put gpVirtualAttach("Touch pad") into sTouch
   put empty into sVSet
   if sTouch is 0 then glLog "no touch pad:" && gpLastError()
   glTouchLabel
end glAttachTouch

command glListPads
   local tText, tPad, tLine, tAt
   put empty into sPadList
   put empty into tText
   put 0 into tAt
   if sStarted is true then
      repeat for each item tPad in gpPads()
         put gpPadName(tPad) into tLine
         if gpPadIsVirtual(tPad) then
            put " (made in software)" after tLine
         else if gpPadType(tPad) is not empty then
            put " (" & gpPadType(tPad) & ")" after tLine
         end if
         put tLine & return after tText
         put tPad & comma after sPadList
         if tPad is sPad then put the number of lines of tText into tAt
      end repeat
   else if sGhost is true and sRunning is true then
      put "Touch pad (a recording)" & return into tText
      put 1 into tAt
   end if
   if tText is not empty then delete the last char of tText
   if sPadList is not empty then delete the last char of sPadList
   set the text of field "padList" to tText
   set the hilitedLine of field "padList" to tAt
   glTouchLabel
   -- the footer's count changes with the list, not half a second later
   glFooter
end glListPads

command glPickFromList
   local tLine
   put the hilitedLine of field "padList" into tLine
   if tLine is an integer and tLine > 0 and tLine <= the number of items of sPadList then
      if item tLine of sPadList is not sTouch then
         glStopScene
         put false into sTour
         glShowSceneButtons
      end if
      glSelect item tLine of sPadList
      glAboutIdle
   end if
end glPickFromList

-- Shows pad pPad (0 for none) in the drawing and the panels
command glSelect pPad
   if pPad is not an integer then put 0 into pPad
   if sStarted is not true then put 0 into pPad
   if pPad is not 0 and not gpPadIsConnected(pPad) then put 0 into pPad
   put pPad into sPad
   put sPad is not 0 and gpPadIsVirtual(sPad) into sPadVirtual
   if sPad is 0 then
      put empty into sPadName
   else
      put gpPadName(sPad) into sPadName
   end if
   put "-" into sHeld
   put "-" into sAxes
   put empty into sRumbleShown
   put 0 into sRumbleUntil
   put empty into sLed
   put empty into sGlow
   glListPads
   glShowInfo
   glShowLabels
   glShowMapping
   glShowAbilities
   glShowParts
   if sPad is 0 and sGhost is not true then glDrawNothing
   glLightShown empty
end glSelect

command glShowInfo
   local tInfo, tPlayer
   put -1 into tPlayer
   if sGhost is true and sRunning is true then
      put "Name: Touch pad, a recording" & return & \
            "gamepadxt is not in this OXT-Beyond, so no controller can be read here. The showcases play from this stack's own script instead: the drawing, the game and the rumble you see are the recording." into tInfo
      put sGhostPlayer into tPlayer
   else if sPad is 0 then
      put "No controller on show." into tInfo
   else
      put gpPadPlayer(sPad) into tPlayer
      put "Name: " & sPadName & return into tInfo
      put "Kind: " & gpPadType(sPad) & return after tInfo
      put "USB vendor, product: " & glHex(gpPadVendor(sPad)) & ", " & glHex(gpPadProduct(sPad)) & return after tInfo
      put "Player: " & glPlayerName(tPlayer) & return after tInfo
      put "Battery: " & glBattery(sPad) & return after tInfo
      put "Made in software: " & glYesNo(sPadVirtual) & return after tInfo
      put "Buttons: " & glCountParts(gpButtonNames(), "button") & ", axes: " & glCountParts(gpAxisNames(), "axis") & return after tInfo
      put "Handle: " & sPad & return after tInfo
      put "GUID: " & gpPadGUID(sPad) after tInfo
   end if
   set the text of field "padInfo" to tInfo
   glShowPlayerLights tPlayer
end glShowInfo

-- The four lights in the drawing show the player number, as many pads do
command glShowPlayerLights pPlayer
   local tI
   repeat with tI = 1 to 4
      if pPlayer is an integer and pPlayer + 1 is tI then
         set the backgroundColor of graphic ("plr_" & tI) to kLive
      else
         set the backgroundColor of graphic ("plr_" & tI) to kWell
      end if
   end repeat
end glShowPlayerLights

-- The letter or symbol printed on each face button of this pad
command glShowLabels
   local tName, tLabel
   repeat for each item tName in "south,east,west,north"
      put empty into tLabel
      if sGhost is true then
         put item itemOffset(tName, "south,east,west,north") of "A,B,X,Y" into tLabel
      else if sPad is not 0 then
         put glLabelText(gpPadButtonLabel(sPad, tName)) into tLabel
      end if
      set the label of graphic ("btn_" & tName) to tLabel
      -- with no label a graphic would show its name instead
      set the showName of graphic ("btn_" & tName) to tLabel is not empty
   end repeat
end glShowLabels

command glShowMapping
   local tGUID
   if sGhost is true then
      set the text of field "mapping" to "SDL's mappings are in gamepadxt, which this OXT-Beyond does not have."
   else if sPad is 0 then
      set the text of field "mapping" to empty
   else
      put gpPadGUID(sPad) into tGUID
      if tGUID is not empty and sFirstMapping[tGUID] is empty then
         put gpPadMapping(sPad) into sFirstMapping[tGUID]
      end if
      set the text of field "mapping" to glMappingShown(gpPadMapping(sPad))
   end if
   set the vScroll of field "mapping" of me to 0
   glScrollMark "mapping"
end glShowMapping

-- A mapping has no space in it but in the pad's name, and the engine
-- breaks a line only at a space: shown as it comes, it runs off the box's
-- right edge. The box shows a space after each comma, and what is read back
-- from it has them taken out again (a comma never ends a pad's name).
function glMappingShown pLine
   replace comma with comma & space in pLine
   return pLine
end glMappingShown

function glMappingRead pLine
   put word 1 to -1 of pLine into pLine
   repeat while pLine contains (comma & space)
      replace comma & space with comma in pLine
   end repeat
   repeat while pLine contains (space & comma)
      replace space & comma with comma in pLine
   end repeat
   return pLine
end glMappingRead

-- A button, stick or trigger the pad does not have is drawn faint
command glShowParts
   local tName, tNames
   put kButtons into tNames
   if sPad is not 0 then put gpButtonNames() into tNames
   repeat for each item tName in tNames
      if there is a graphic ("btn_" & tName) then
         glFaint "btn_" & tName, sPad is not 0 and not gpPadHasButton(sPad, tName)
      end if
   end repeat
   repeat for each item tName in "left,right"
      glFaint "well_" & tName, sPad is not 0 and not gpPadHasAxis(sPad, tName & "x")
      glFaint "trigwell_" & tName, sPad is not 0 and not gpPadHasAxis(sPad, tName & "trigger")
   end repeat
end glShowParts

command glFaint pGraphic, pFaint
   if pFaint then
      set the blendLevel of graphic pGraphic to 75
   else
      set the blendLevel of graphic pGraphic to 0
   end if
end glFaint

-- "12 of 26": how many of the library's names this pad has
function glCountParts pNames, pKind
   local tName, tHas, tYes
   put 0 into tHas
   repeat for each item tName in pNames
      if pKind is "button" then
         put gpPadHasButton(sPad, tName) into tYes
      else
         put gpPadHasAxis(sPad, tName) into tYes
      end if
      if tYes then add 1 to tHas
   end repeat
   return tHas && "of" && the number of items of pNames
end glCountParts

command glShowAbilities
   local tText
   if sGhost is true then
      put "The recording: rumble yes, trigger motors yes, a light yes" into tText
   else if sPad is 0 then
      put empty into tText
   else
      put "This pad: rumble " & glYesNo(gpPadHasRumble(sPad)) & ", trigger motors " & \
            glYesNo(gpPadHasTriggerRumble(sPad)) & ", a light " & glYesNo(gpPadHasLED(sPad)) into tText
   end if
   set the text of field "abilities" to tText
end glShowAbilities

command glSetPlayer pPlayer
   if glDoPlayer(pPlayer) then
      glLog "player number set:" && glPlayerName(pPlayer)
   else if sPad is not 0 then
      glLog "no player number for this pad:" && gpLastError()
   end if
   glShowInfo
   glShowLog
end glSetPlayer

----------------------------------------------------------------
-- What the pad on show holds: from the library, or from the recording

command glRead
   put empty into sLeft
   put empty into sRight
   if sGhost is true then
      put glGhostStick("left") into sLeft
      put glGhostStick("right") into sRight
   else if sPad is not 0 then
      put gpPadStick(sPad, "left") into sLeft
      put gpPadStick(sPad, "right") into sRight
   end if
end glRead

function glHeldNow
   local tHeld, tName
   if sGhost is not true then return gpPadButtons(sPad)
   put empty into tHeld
   repeat for each item tName in kButtons
      if sGhostButtons[glGhostName(tName)] is true then put tName & comma after tHeld
   end repeat
   if tHeld is not empty then delete the last char of tHeld
   return tHeld
end glHeldNow

function glAxesNow
   local tAxes, tName
   if sGhost is not true then return gpPadAxes(sPad)
   put empty into tAxes
   repeat for each item tName in kAxes
      put (sGhostAxes[tName] + 0) & comma after tAxes
   end repeat
   delete the last char of tAxes
   return tAxes
end glAxesNow

function glAxisNow pAxis
   if sGhost is true then return sGhostAxes[pAxis] + 0
   return gpPadAxis(sPad, pAxis)
end glAxisNow

function glButtonNow pButton
   local tName
   if sGhost is not true then return gpPadButton(sPad, pButton)
   -- the recording's swapped mapping, as the library's would read
   put glGhostName(pButton) into tName
   return sGhostButtons[tName] is true
end glButtonNow

----------------------------------------------------------------
-- The drawing

command glDraw
   local tHeld, tAxes, tName
   if sPad is 0 and sGhost is not true then exit glDraw
   put glHeldNow() into tHeld
   if tHeld is not sHeld then
      repeat for each item tName in kButtons
         if sHeld is "-" or (tName is among the items of tHeld) is not (tName is among the items of sHeld) then
            glPaintButton tName, tName is among the items of tHeld
         end if
      end repeat
      put tHeld into sHeld
   end if
   put glAxesNow() into tAxes
   if tAxes is empty then put "0,0,0,0,0,0" into tAxes
   if tAxes is not sAxes then
      glDrawStick "left", item 1 of tAxes, item 2 of tAxes
      glDrawStick "right", item 3 of tAxes, item 4 of tAxes
      glDrawTrigger "left", item 5 of tAxes
      glDrawTrigger "right", item 6 of tAxes
      put tAxes into sAxes
   end if
   glReadout tHeld, tAxes
   glDrawRumble
   glDrawGlow
end glDraw

command glDrawNothing
   local tName
   repeat for each item tName in kButtons
      glPaintButton tName, false
   end repeat
   glDrawStick "left", 0, 0
   glDrawStick "right", 0, 0
   glDrawTrigger "left", 0
   glDrawTrigger "right", 0
   glMotors "0,0,0,0"
   set the topLeft of group "controller" to the cHome of group "controller"
   set the text of field "readout" to empty
   put empty into sReadout
   glShowPlayerLights -1
end glDrawNothing

command glPaintButton pName, pDown
   local tG
   put "btn_" & pName into tG
   if there is no graphic tG then exit glPaintButton
   if pDown then
      set the backgroundColor of graphic tG to glHeldColour(pName)
      -- a graphic's words are drawn in its line colour: dark on a lit fill
      if the showName of graphic tG then
         set the foregroundColor of graphic tG to kOnText
      end if
   else
      if pName is "leftstick" or pName is "rightstick" then
         set the backgroundColor of graphic tG to kKnob
      else
         set the backgroundColor of graphic tG to kIdle
      end if
      set the foregroundColor of graphic tG to the cLine of graphic tG
   end if
end glPaintButton

function glHeldColour pName
   switch pName
      case "south"
         return "96,200,110"
      case "east"
         return "232,92,82"
      case "west"
         return "82,152,244"
      case "north"
         return "242,204,72"
      default
         return kHeld
   end switch
end glHeldColour

-- A stick's knob, at the raw position the pad reports
command glDrawStick pSide, pX, pY
   local tC, tTravel
   put the loc of graphic ("well_" & pSide) into tC
   put (the width of graphic ("well_" & pSide) - the width of graphic ("btn_" & pSide & "stick")) / 2 into tTravel
   set the loc of graphic ("btn_" & pSide & "stick") to round(item 1 of tC + pX * tTravel), round(item 2 of tC + pY * tTravel)
end glDrawStick

-- A trigger fills its well from the bottom
command glDrawTrigger pSide, pValue
   local tW, tTop
   put the rect of graphic ("trigwell_" & pSide) into tW
   put item 4 of tW - round((item 4 of tW - item 2 of tW) * pValue) into tTop
   if tTop >= item 4 of tW - 1 then
      hide graphic ("trig_" & pSide)
   else
      set the rect of graphic ("trig_" & pSide) to item 1 of tW, tTop, item 3 of tW, item 4 of tW
      show graphic ("trig_" & pSide)
   end if
end glDrawTrigger

-- The dead zone: while the knob's edge stays inside the ring, gpPadStick
-- reads 0
command glShowDeadZone
   local tDZ, tSide, tC, tTravel, tR
   put glDeadZoneNow() into tDZ
   set the text of field "deadZoneLabel" to "Dead zone" && format("%.2f", tDZ) & ": the dashed ring in each stick"
   repeat for each item tSide in "left,right"
      put the loc of graphic ("well_" & tSide) into tC
      put (the width of graphic ("well_" & tSide) - the width of graphic ("btn_" & tSide & "stick")) / 2 into tTravel
      put round(tDZ * tTravel + the width of graphic ("btn_" & tSide & "stick") / 2) + 1 into tR
      set the rect of graphic ("dz_" & tSide) to item 1 of tC - tR, item 2 of tC - tR, item 1 of tC + tR, item 2 of tC + tR
   end repeat
end glShowDeadZone

function glDeadZoneNow
   if sGhost is true then return sGhostDZ
   if sLib is true then return gpDeadZone()
   return 0.15
end glDeadZoneNow

command glReadout pHeld, pAxes
   local tText
   put "Sticks as read:" && glPair(item 1 of pAxes, item 2 of pAxes) & "   " & glPair(item 3 of pAxes, item 4 of pAxes) & \
         "      gpPadStick:" && glPair(item 1 of sLeft, item 2 of sLeft) & "   " & glPair(item 1 of sRight, item 2 of sRight) & return & \
         "Triggers:" && format("%.2f", item 5 of pAxes) & "   " & format("%.2f", item 6 of pAxes) & \
         "      Held:" && glOr(pHeld, "nothing") into tText
   if tText is not sReadout then
      set the text of field "readout" to tText
      put tText into sReadout
   end if
end glReadout

-- Rumble as the pad was asked for it: a virtual pad says, a real one is
-- shown what this stack asked of it. The grips glow with the two motors,
-- the triggers' wells with theirs, and the drawing shakes.
command glDrawRumble
   local tR, tStrength, tHome
   if sGhost is true then
      put glGhostMotors() into tR
      glLightShown sGhostLED
   else if sPadVirtual then
      put gpVirtualRumble(sPad) into tR
      glLightShown gpVirtualLED(sPad)
   else if the milliseconds < sRumbleUntil then
      put sRumbleAsked into tR
   else
      put "0,0,0,0" into tR
   end if
   if tR is empty then put "0,0,0,0" into tR
   if tR is not sRumbleShown then
      glMotors tR
      put tR into sRumbleShown
   end if
   put max(item 1 of tR, item 2 of tR, item 3 of tR, item 4 of tR) into tStrength
   put the cHome of group "controller" into tHome
   if tStrength > 0 then
      add 1 to sShake
      set the topLeft of group "controller" to item 1 of tHome + (sShake mod 2 * 2 - 1) * round(1 + tStrength * 3), item 2 of tHome
   else if sShake is not 0 then
      put 0 into sShake
      set the topLeft of group "controller" to tHome
   end if
end glDrawRumble

command glMotors pR
   set the backgroundColor of graphic "grip_left" to glBlend(kBody, kHeld, item 1 of pR)
   set the backgroundColor of graphic "grip_right" to glBlend(kBody, kHeld, item 2 of pR)
   set the foregroundColor of graphic "trigwell_left" to glBlend(kWellLine, kHeld, item 3 of pR)
   set the foregroundColor of graphic "trigwell_right" to glBlend(kWellLine, kHeld, item 4 of pR)
end glMotors

-- A pad that has just come in glows round its edge for a moment
command glDrawGlow
   local tGlow
   put the milliseconds < sGreetUntil into tGlow
   if tGlow is sGlow then exit glDrawGlow
   put tGlow into sGlow
   if tGlow then
      set the foregroundColor of graphic "padBody" to kLive
      set the lineSize of graphic "padBody" to 3
   else
      set the foregroundColor of graphic "padBody" to kBody
      set the lineSize of graphic "padBody" to 1
   end if
end glDrawGlow

command glLightShown pRGB
   if pRGB is empty and sGhost is true then put sGhostLED into pRGB
   if pRGB is empty then put sLed into pRGB
   if pRGB is empty or pRGB is "0,0,0" then
      set the backgroundColor of graphic "lightbar" to "40,44,52"
   else
      set the backgroundColor of graphic "lightbar" to pRGB
   end if
end glLightShown

----------------------------------------------------------------
-- The playground: a game's few lines

command glPlay
   local tRect, tHit, tSize, tShown, tSpeed
   if sLeft is empty then exit glPlay
   put the rect of graphic "arena" into tRect
   -- what is held is read as state: the right trigger hurries the ball,
   -- west held slows it
   put 4 + 8 * glAxisNow("righttrigger") into tSpeed
   if glButtonNow("west") then put tSpeed / 3 into tSpeed
   add item 1 of sLeft * tSpeed to sBallX
   add item 2 of sLeft * tSpeed to sBallY
   -- a jump grows the ball for a moment
   put 20 into tSize
   if sJump > 0 then
      put 20 + round(sin(sJump / 16 * pi) * 16) into tSize
      subtract 1 from sJump
   end if
   put false into tHit
   if sBallX < item 1 of tRect + 12 then
      put item 1 of tRect + 12 into sBallX
      put true into tHit
   end if
   if sBallX > item 3 of tRect - 12 then
      put item 3 of tRect - 12 into sBallX
      put true into tHit
   end if
   -- the top wall is the caption's foot, and a ball that jumps there is
   -- pushed down rather than over the caption's words
   if sBallY < item 2 of tRect + kArenaCaption + 2 + tSize div 2 then
      put item 2 of tRect + kArenaCaption + 2 + tSize div 2 into sBallY
      put true into tHit
   end if
   if sBallY > item 4 of tRect - 12 then
      put item 4 of tRect - 12 into sBallY
      put true into tHit
   end if
   if tHit and sWasHit is not true then glBump
   put tHit into sWasHit
   put round(sBallX) & comma & round(sBallY) & comma & tSize into tShown
   if tShown is not sBallShown then
      set the rect of graphic "ball" to round(sBallX - tSize / 2), round(sBallY - tSize / 2), \
            round(sBallX - tSize / 2) + tSize, round(sBallY - tSize / 2) + tSize
      put tShown into sBallShown
   end if
   if sRight is empty or (item 1 of sRight = 0 and item 2 of sRight = 0) then
      hide graphic "aim"
   else
      set the points of graphic "aim" to round(sBallX) & comma & round(sBallY) & return & \
            round(sBallX + item 1 of sRight * 52) & comma & round(sBallY + item 2 of sRight * 52)
      show graphic "aim"
   end if
   if sFlash > 0 then
      subtract 1 from sFlash
      if sFlash is 0 then set the foregroundColor of graphic "arena" to kWellLine
   end if
end glPlay

-- A button press the playground answers
command glPressed pName
   switch pName
      case "south"
         put 16 into sJump
         break
      case "east"
         set the itemDelimiter to "|"
         add 1 to sBallColour
         if sBallColour > the number of items of kBallColours then put 1 into sBallColour
         set the backgroundColor of graphic "ball" to item sBallColour of kBallColours
         set the itemDelimiter to comma
         break
      case "start"
         glCentreBall
         break
   end switch
end glPressed

-- The ball meets a wall: a short bump, felt where the pad can rumble
command glBump
   if sGhost is true then
      get glDoRumble(0.5, 0.25, 90)
   else if sPad is not 0 and gpPadHasRumble(sPad) then
      if gpPadRumble(sPad, 0.5, 0.25, 90) then
         put the milliseconds + 90 into sRumbleUntil
         put "0.5,0.25,0,0" into sRumbleAsked
      end if
   end if
   set the foregroundColor of graphic "arena" to kHeld
   put 8 into sFlash
end glBump

command glCentreBall
   put item 1 of the loc of graphic "arena" into sBallX
   put item 2 of the loc of graphic "arena" into sBallY
   put 0 into sJump
   put empty into sBallShown
   set the rect of graphic "ball" to round(sBallX) - 10, round(sBallY) - 10, round(sBallX) + 10, round(sBallY) + 10
end glCentreBall

----------------------------------------------------------------
-- The showcases: each a few seconds of one thing, played on the touch
-- pad (or the recording) by setting its buttons and axes as time passes.
-- A step is worked out from the time, never counted in frames, so a slow
-- machine plays the same showcase in fewer frames.

command glPlayScene pScene
   glStopScene
   if pScene < 1 or pScene > 5 then exit glPlayScene
   if sRunning is not true then
      glLog "Start first: the showcases play while the window runs"
      glShowLog
      exit glPlayScene
   end if
   if sGhost is not true then
      if sStarted is not true then exit glPlayScene
      glAttachTouch
      if sTouch is 0 then exit glPlayScene
      if sPad is not sTouch then glSelect sTouch
   end if
   put pScene into sScene
   put the milliseconds into sSceneAt
   put empty into sDone
   put empty into sWay
   glVReset
   -- what a showcase changes, to put back when it ends
   put glDeadZoneNow() into sSaved["zone"]
   if sGhost is true then
      put 0 into sSaved["step"]
      put sGhostPlayer into sSaved["player"]
      put sGhostLED into sSaved["light"]
   else
      put gpAxisEvents() into sSaved["step"]
      put gpPadPlayer(sTouch) into sSaved["player"]
      put gpVirtualLED(sTouch) into sSaved["light"]
   end if
   glAbout glSceneText(pScene)
   glShowSceneButtons
   glChipUpdate the milliseconds
   glLog "showcase" && pScene & ":" && glSceneTitle(pScene)
end glPlayScene

-- Ends the showcase playing, if one is, and puts back what it changed
command glStopScene
   local tLED
   if sScene is not an integer or sScene is 0 then
      put 0 into sScene
      exit glStopScene
   end if
   put 0 into sScene
   glVReset
   if sGhost is true then
      put sSaved["zone"] into sGhostDZ
      put false into sGhostSwap
      put sSaved["player"] into sGhostPlayer
      put sSaved["light"] into sGhostLED
      put "0,0" into sGhostMotors
      put "0,0" into sGhostTrig
   else if sStarted is true then
      gpSetDeadZone sSaved["zone"]
      gpSetAxisEvents sSaved["step"]
      set the hilite of button "axisEvents" of me to sSaved["step"] > 0
      if sTouch is not 0 and gpPadIsConnected(sTouch) then
         if sDone["swap"] is true and sDone["unswap"] is not true then glMapBack
         put sSaved["light"] into tLED
         if tLED is empty then put "0,0,0" into tLED
         get gpPadSetLED(sTouch, item 1 of tLED, item 2 of tLED, item 3 of tLED)
         if sSaved["player"] is an integer then get gpPadSetPlayer(sTouch, sSaved["player"])
         get gpPadRumble(sTouch, 0, 0, 0)
         get gpPadRumbleTriggers(sTouch, 0, 0, 0)
      end if
   end if
   set the thumbPosition of scrollbar "deadZone" of me to round(sSaved["zone"] * 100)
   glShowDeadZone
   if sPad is not 0 or sGhost is true then glShowInfo
   glShowSceneButtons
end glStopScene

command glSceneStep pMs
   local tScene
   put sScene into tScene
   if pMs >= item tScene of kSceneMs then
      glStopScene
      if sTour is true then
         glPlayScene tScene mod 5 + 1
      else
         glAboutIdle
      end if
      exit glSceneStep
   end if
   switch tScene
      case 1
         glSceneButtons pMs
         break
      case 2
         glSceneSticks pMs
         break
      case 3
         glSceneRumble pMs
         break
      case 4
         glSceneMapping pMs
         break
      case 5
         glSceneGame pMs
         break
   end switch
end glSceneStep

-- 1. Every button in turn, then the four face buttons at once
command glSceneButtons pMs
   local tI, tName, tAt, tDown, tChord
   put the number of items of kWave * 340 + 200 into tChord
   put 0 into tI
   repeat for each item tName in kWave
      put tI * 340 into tAt
      put (pMs >= tAt) and (pMs < tAt + 280) into tDown
      if tName is among the items of "south,east,west,north" and pMs >= tChord and pMs < tChord + 700 then put true into tDown
      glVButton tName, tDown
      add 1 to tI
   end repeat
end glSceneButtons

-- 2. The left stick goes round, in towards the middle and out again,
-- while the dead zone's ring grows and shrinks; the right stick draws an
-- eight and the triggers take turns. With axis events on, half a stick's
-- travel is an event too.
command glSceneSticks pMs
   local tTurn, tReach, tZone
   put pMs / 2500 * 2 * pi into tTurn
   put 0.65 + 0.35 * cos(pMs / 6000 * 2 * pi) into tReach
   glVAxis "leftx", tReach * cos(tTurn)
   glVAxis "lefty", tReach * sin(tTurn)
   glVAxis "rightx", sin(pMs / 4000 * 2 * pi)
   glVAxis "righty", 0.8 * sin(pMs / 2000 * 2 * pi)
   glVAxis "lefttrigger", (1 - cos(pMs / 3000 * 2 * pi)) / 2
   glVAxis "righttrigger", (1 + cos(pMs / 3000 * 2 * pi)) / 2
   if glOnce("step", pMs, 400) and sGhost is not true then
      gpSetAxisEvents 0.5
      set the hilite of button "axisEvents" of me to true
      glLog "axis events on: a line each time an axis moves" && format("%.2f", gpAxisEvents()) && "of its travel"
   end if
   if glOnce("stepoff", pMs, 11000) and sGhost is not true then
      gpSetAxisEvents sSaved["step"]
      set the hilite of button "axisEvents" of me to sSaved["step"] > 0
      glLog "axis events back as they were"
   end if
   -- the ring: 0.15, out to 0.45 from 2 s to 4 s, back from 8 s to 10 s
   if pMs < 2000 then
      put sSaved["zone"] into tZone
   else if pMs < 4000 then
      put sSaved["zone"] + (0.45 - sSaved["zone"]) * (pMs - 2000) / 2000 into tZone
   else if pMs < 8000 then
      put 0.45 into tZone
   else if pMs < 10000 then
      put 0.45 + (sSaved["zone"] - 0.45) * (pMs - 8000) / 2000 into tZone
   else
      put sSaved["zone"] into tZone
   end if
   glZone round(tZone, 2)
end glSceneSticks

-- 3. Player numbers 1 to 4 and none, the light round the colour wheel,
-- and the motors: a heartbeat, a swell, the triggers' own, then all four
command glSceneRumble pMs
   local tTenth, tRGB, tBeat
   if glOnce("p1", pMs, 0) then get glDoPlayer(0)
   if glOnce("p2", pMs, 2000) then get glDoPlayer(1)
   if glOnce("p3", pMs, 4000) then get glDoPlayer(2)
   if glOnce("p4", pMs, 6000) then get glDoPlayer(3)
   if glOnce("p0", pMs, 8500) then get glDoPlayer(-1)
   put pMs div 100 into tTenth
   if tTenth is not sDone["light"] then
      put tTenth into sDone["light"]
      put glHue((pMs mod 4000) / 4000) into tRGB
      get glDoLED(item 1 of tRGB, item 2 of tRGB, item 3 of tRGB)
   end if
   -- a heartbeat on the light motor
   repeat for each item tBeat in "200,1000,1800"
      if glOnce("beat" & tBeat, pMs, tBeat) then get glDoRumble(0, 0.9, 120)
      if glOnce("echo" & tBeat, pMs, tBeat + 260) then get glDoRumble(0, 0.45, 120)
   end repeat
   -- the heavy motor swells, set five times a second
   if pMs >= 2600 and pMs < 4600 and pMs div 200 is not sDone["swell"] then
      put pMs div 200 into sDone["swell"]
      get glDoRumble((pMs - 2600) / 2000, 0, 260)
   end if
   -- the triggers' motors, left, right, then both
   if glOnce("tl", pMs, 5000) then get glDoRumbleTriggers(1, 0, 450)
   if glOnce("tr", pMs, 5600) then get glDoRumbleTriggers(0, 1, 450)
   if glOnce("tb", pMs, 6200) then get glDoRumbleTriggers(1, 1, 600)
   -- everything at once
   if glOnce("all", pMs, 7200) then
      get glDoRumble(1, 1, 900)
      get glDoRumbleTriggers(0.6, 0.6, 900)
   end if
   if glOnce("lightoff", pMs, 9400) then get glDoLED(0, 0, 0)
end glSceneRumble

-- 4. South pressed lights south; the pad's mapping is changed so that its
-- first two buttons swap, and the same press lights east; then the first
-- mapping is put back
command glSceneMapping pMs
   local tDown
   put glWithin(pMs, 400, 900) or glWithin(pMs, 3000, 3500) or glWithin(pMs, 4300, 4800) \
         or glWithin(pMs, 5600, 6100) or glWithin(pMs, 8400, 8900) or glWithin(pMs, 9500, 10000) into tDown
   glVButton "south", tDown
   if glOnce("swap", pMs, 1700) then glMapSwap
   if glOnce("unswap", pMs, 7000) then glMapBack
end glSceneMapping

-- 5. The small game: the left stick steers the ball round a course, the
-- right trigger hurries it, west slows it, south jumps, east changes its
-- colour, the right stick aims, and start brings it home
command glSceneGame pMs
   local tAim
   if glOnce("home", pMs, 0) then glCentreBall
   glSteer pMs
   glVAxis "righttrigger", glIfNumber(glWithin(pMs, 3600, 5600), 1, 0)
   glVButton "west", glWithin(pMs, 7400, 8600)
   glVButton "south", glWithin(pMs, 1800, 1950) or glWithin(pMs, 5000, 5150) or glWithin(pMs, 9800, 9950)
   glVButton "east", glWithin(pMs, 2800, 2950) or glWithin(pMs, 6600, 6750) or glWithin(pMs, 10400, 10550)
   if pMs >= 1000 and pMs < 11400 then
      put pMs / 1600 * 2 * pi into tAim
      glVAxis "rightx", cos(tAim)
      glVAxis "righty", sin(tAim)
   else
      glVAxis "rightx", 0
      glVAxis "righty", 0
   end if
   glVButton "start", glWithin(pMs, 11800, 11950)
end glSceneGame

-- The left stick, pointed at the next point of the course; a point beyond
-- a wall is left once the ball has hit the wall
command glSteer pMs
   local tRect, tPoint, tX, tY, tDX, tDY, tLen, tPush
   if pMs >= 11400 then
      glVAxis "leftx", 0
      glVAxis "lefty", 0
      exit glSteer
   end if
   if sWay is empty then
      put 1 into sWay
      put pMs into sWayAt
   end if
   put the rect of graphic "arena" into tRect
   set the itemDelimiter to "|"
   put item sWay of kCourse into tPoint
   set the itemDelimiter to comma
   put item 1 of tRect + (item 3 of tRect - item 1 of tRect) * item 1 of tPoint into tX
   put item 2 of tRect + (item 4 of tRect - item 2 of tRect) * item 2 of tPoint into tY
   put tX - sBallX into tDX
   put tY - sBallY into tDY
   put sqrt(tDX * tDX + tDY * tDY) into tLen
   if tLen < 16 or (sWasHit is true and pMs - sWayAt > 300) or pMs - sWayAt > 2600 then
      add 1 to sWay
      set the itemDelimiter to "|"
      if sWay > the number of items of kCourse then put 1 into sWay
      set the itemDelimiter to comma
      put pMs into sWayAt
      exit glSteer
   end if
   put min(1, tLen / 60) into tPush
   glVAxis "leftx", tDX / tLen * tPush
   glVAxis "lefty", tDY / tLen * tPush
end glSteer

-- The dead zone, set by a showcase: the library, the ring and the slider
command glZone pZone
   if abs(pZone - glDeadZoneNow()) < 0.005 then exit glZone
   if sGhost is true then
      put pZone into sGhostDZ
   else
      gpSetDeadZone pZone
   end if
   set the thumbPosition of scrollbar "deadZone" of me to round(pZone * 100)
   glShowDeadZone
end glZone

-- True once, the first time pMs reaches pAt; a late frame still takes it
function glOnce pKey, pMs, pAt
   if pMs < pAt or sDone[pKey] is true then return false
   put true into sDone[pKey]
   return true
end glOnce

function glWithin pMs, pFrom, pTo
   return pMs >= pFrom and pMs < pTo
end glWithin

function glSceneTitle pScene
   set the itemDelimiter to "|"
   return item pScene of kSceneTitles
end glSceneTitle

function glSceneText pScene
   switch pScene
      case 1
         return "Every button SDL knows, 26 of them, pressed in turn on the touch pad, a controller made in software. Each press reaches the stack twice: as state (gpPadButton, gpPadButtons), lit in the drawing, and as an event, a line of gpEvents() in the log. A real pad has the ones it has, and the others are drawn faint."
      case 2
         return "A stick reads from -1 to 1 and a trigger from 0 to 1 (gpPadAxis, gpPadAxes). gpPadStick takes out the dead zone, the dashed ring: while the knob stays inside it the stick reads 0, and past it the reading starts again from 0, so a worn stick never drifts. Here the ring grows to 0.45 and back (gpSetDeadZone), and with gpSetAxisEvents half a stick's travel is an event too."
      case 3
         return "gpPadSetPlayer numbers a pad, and the four lights show it. gpPadSetLED colours its light, here round the colour wheel. gpPadRumble runs its heavy and light motors for as long as you say, and gpPadRumbleTriggers the motors in its triggers. The touch pad tells what it was asked (gpVirtualRumble, gpVirtualLED), so the grips glow and the drawing shakes; a real pad buzzes."
      case 4
         return "SDL reads every pad through a mapping, one line saying which of the pad's own buttons is which (gpPadMapping). gpAddMapping changes it while the pad is open: here the touch pad's first two buttons swap, and the same press that lit south lights east. Then the first line goes back. gpAddMappingsFromFile reads a whole gamecontrollerdb.txt."
      case 5
         return "A game needs a few lines: gpPoll() from a timer, gpPadStick for where to go, gpPadButton and gpPadAxis for what is held, gpEvents() for what was pressed once. The left stick rolls the ball, the right trigger hurries it, west slows it, south jumps, east changes its colour, the right stick aims, and hitting a wall rumbles the pad."
   end switch
   return empty
end glSceneText

command glShowSceneButtons
   local tI
   repeat with tI = 1 to 5
      glButtonLook "show_" & tI, tI is sScene
   end repeat
   if sTour is true then
      set the label of button "playAll" of me to "Stop the tour"
   else
      set the label of button "playAll" of me to "Play all five"
   end if
   glButtonLook "playAll", sTour is true
end glShowSceneButtons

-- A showcase button that is playing wears the accent
command glButtonLook pName, pOn
   if pOn then
      set the backgroundColor of button pName of me to kAccent
      set the foregroundColor of button pName of me to kOnText
      set the borderColor of button pName of me to kAccent
   else
      set the backgroundColor of button pName of me to kButtonFill
      set the foregroundColor of button pName of me to kButtonText
      set the borderColor of button pName of me to kButtonLine
   end if
end glButtonLook

-- The person takes the touch pad: whatever was playing stops
command glUserTakes
   if sScene is 0 and sTour is not true then exit glUserTakes
   glStopScene
   put false into sTour
   glShowSceneButtons
   if sGhost is not true and sTouch is not 0 and sPad is not sTouch then glSelect sTouch
   glAboutIdle
end glUserTakes

command glAbout pText
   set the text of field "about" of me to pText
end glAbout

command glAboutIdle
   if sGhost is true then
      glAbout "gamepadxt is not in this OXT-Beyond, so nothing here can read a controller: the touch pad is a recording. A showcase plays it again, and the mouse and the keys move it. Open the stack in an OXT-Beyond with gamepadxt built in, or install the extension, to read a real controller."
   else if sPad is not 0 and sPad is not sTouch then
      glAbout sPadName && "is live. Everything here reads it now: its buttons and sticks in the drawing, its events in the log, Rumble, the light and the player number set on it. A part it does not have is drawn faint. The showcases still play on the touch pad."
   else
      glAbout "The touch pad is yours. Drag a stick or a trigger, click a button, or use the keys: the arrows move the left stick, Z X A S press south, east, west and north, Q and W the shoulders, Return start. Plug in a controller, or press a button on one, and it takes over."
   end if
end glAboutIdle

-- The line over the stage: what plays, and how far it has got
command glChipUpdate pNow
   local tText, tColour, tBar, tWell
   put -1 into tBar
   if sRunning is not true then
      put "Stopped" into tText
      put kDim into tColour
   else if sScene > 0 then
      put "Showcase" && sScene into tText
      if sTour is true then put " of 5" after tText
      put ":" && glSceneTitle(sScene) after tText
      if sGhost is true then put "  (a recording)" after tText
      put kAccent into tColour
      put min(1, (pNow - sSceneAt) / item sScene of kSceneMs) into tBar
   else if sGhost is true then
      put "A recording: gamepadxt is not installed" into tText
      put kDim into tColour
   else if sPad is 0 then
      put "No controller" into tText
      put kDim into tColour
   else if sPad is sTouch then
      put "Touch pad: drag it, click it or use the keys" into tText
      put kText into tColour
   else
      put sPadName & ": live" into tText
      put kLive into tColour
   end if
   if tText is not sChipText then
      set the text of field "chip" to tText
      put tText into sChipText
   end if
   if tColour is not sChipColour then
      set the backgroundColor of graphic "chipDot" to tColour
      set the foregroundColor of graphic "chipDot" to tColour
      put tColour into sChipColour
   end if
   if tBar < 0 then
      if sChipBar is not "off" then
         hide graphic "chipWell"
         hide graphic "chipBar"
         put "off" into sChipBar
      end if
   else if round(tBar * 100) is not sChipBar then
      put round(tBar * 100) into sChipBar
      put the rect of graphic "chipWell" into tWell
      set the rect of graphic "chipBar" to item 1 of tWell, item 2 of tWell, \
            item 1 of tWell + max(2, round((item 3 of tWell - item 1 of tWell) * tBar)), item 4 of tWell
      show graphic "chipWell"
      show graphic "chipBar"
   end if
end glChipUpdate

----------------------------------------------------------------
-- The touch pad's inputs, from a showcase, the mouse or the keys. A value
-- already sent is not sent again.

command glVButton pName, pDown
   if pDown is not true then put false into pDown
   if sVSet[pName] is pDown then exit glVButton
   put pDown into sVSet[pName]
   if sGhost is true then
      glGhostButton pName, pDown
   else if sTouch is not 0 then
      get gpVirtualSetButton(sTouch, pName, pDown)
   end if
end glVButton

command glVAxis pName, pValue
   if pName ends with "trigger" then
      put max(0, min(1, pValue)) into pValue
   else
      put max(-1, min(1, pValue)) into pValue
   end if
   if sVSet[pName] is a number and abs(sVSet[pName] - pValue) < 0.001 then exit glVAxis
   put pValue into sVSet[pName]
   if sGhost is true then
      put pValue into sGhostAxes[pName]
   else if sTouch is not 0 then
      get gpVirtualSetAxis(sTouch, pName, pValue)
   end if
end glVAxis

-- Every button up and every axis at rest
command glVReset
   local tName
   repeat for each item tName in kButtons
      glVButton tName, false
   end repeat
   repeat for each item tName in kAxes
      glVAxis tName, 0
   end repeat
end glVReset

-- What a showcase or a button asks of the pad on show: the touch pad
-- while a showcase plays, the recording with no library
function glDoRumble pLow, pHigh, pMs
   local tPad
   if sGhost is true then
      put pLow & comma & pHigh into sGhostMotors
      put the milliseconds + pMs into sGhostMotorsUntil
      return true
   end if
   put glTarget() into tPad
   if tPad is 0 then return false
   if not gpPadRumble(tPad, pLow, pHigh, round(pMs)) then return false
   if tPad is not sTouch then
      put the milliseconds + round(pMs) into sRumbleUntil
      put pLow & comma & pHigh & ",0,0" into sRumbleAsked
   end if
   return true
end glDoRumble

function glDoRumbleTriggers pLeft, pRight, pMs
   local tPad
   if sGhost is true then
      put pLeft & comma & pRight into sGhostTrig
      put the milliseconds + pMs into sGhostTrigUntil
      return true
   end if
   put glTarget() into tPad
   if tPad is 0 then return false
   if not gpPadRumbleTriggers(tPad, pLeft, pRight, round(pMs)) then return false
   if tPad is not sTouch then
      put the milliseconds + round(pMs) into sRumbleUntil
      put "0,0," & pLeft & comma & pRight into sRumbleAsked
   end if
   return true
end glDoRumbleTriggers

function glDoLED pRed, pGreen, pBlue
   local tPad
   if sGhost is true then
      put pRed & comma & pGreen & comma & pBlue into sGhostLED
      return true
   end if
   put glTarget() into tPad
   if tPad is 0 then return false
   if not gpPadSetLED(tPad, round(pRed), round(pGreen), round(pBlue)) then return false
   if tPad is not sTouch then put round(pRed) & comma & round(pGreen) & comma & round(pBlue) into sLed
   return true
end glDoLED

function glDoPlayer pPlayer
   local tPad
   if sGhost is true then
      put pPlayer into sGhostPlayer
      glShowPlayerLights pPlayer
      return true
   end if
   put glTarget() into tPad
   if tPad is 0 then return false
   if not gpPadSetPlayer(tPad, pPlayer) then return false
   glShowPlayerLights gpPadPlayer(tPad)
   return true
end glDoPlayer

-- The pad a showcase or a button acts on
function glTarget
   if sStarted is not true then return 0
   if sScene > 0 then return sTouch
   return sPad
end glTarget

----------------------------------------------------------------
-- The recording: the touch pad, kept by this script when there is no
-- library, with the library's dead zone and the showcase's swapped mapping

command glGhostReset
   local tName
   put empty into sGhostButtons
   repeat for each item tName in kAxes
      put 0 into sGhostAxes[tName]
   end repeat
   put 0.15 into sGhostDZ
   put false into sGhostSwap
   put -1 into sGhostPlayer
   put "0,0,0" into sGhostLED
   put "0,0" into sGhostMotors
   put 0 into sGhostMotorsUntil
   put "0,0" into sGhostTrig
   put 0 into sGhostTrigUntil
end glGhostReset

command glGhostButton pName, pDown
   put pDown into sGhostButtons[pName]
   if pDown then glPressed glGhostName(pName)
end glGhostButton

-- With the showcase's mapping, the pad's south reads east and its east
-- reads south
function glGhostName pName
   if sGhostSwap is not true then return pName
   if pName is "south" then return "east"
   if pName is "east" then return "south"
   return pName
end glGhostName

-- gpPadStick's sums: a round dead zone, the reading from 0 past it
function glGhostStick pSide
   local tX, tY, tMag, tOut
   put sGhostAxes[pSide & "x"] + 0 into tX
   put sGhostAxes[pSide & "y"] + 0 into tY
   put sqrt(tX * tX + tY * tY) into tMag
   if tMag <= sGhostDZ or tMag <= 0 then return "0,0"
   put min(1, (tMag - sGhostDZ) / (1 - sGhostDZ)) into tOut
   return (tX * tOut / tMag) & comma & (tY * tOut / tMag)
end glGhostStick

function glGhostMotors
   local tR
   if the milliseconds < sGhostMotorsUntil then
      put sGhostMotors into tR
   else
      put "0,0" into tR
   end if
   if the milliseconds < sGhostTrigUntil then
      put comma & sGhostTrig after tR
   else
      put ",0,0" after tR
   end if
   return tR
end glGhostMotors

----------------------------------------------------------------
-- Events, the dead zone, rumble, light, mappings

command glLog pLine
   put format("%.2f", (the milliseconds - sT0) / 1000) & tab & pLine & return after sLog
   if the number of lines of sLog > kLogLines then
      delete line 1 to (the number of lines of sLog - kLogLines) of sLog
   end if
   put true into sLogDirty
end glLog

-- At its end the log follows the newest line; a person who has scrolled
-- back to read keeps their place while lines arrive
command glShowLog
   local tWas, tEnd, tText
   put false into sLogDirty
   put the milliseconds into sLogShownAt
   put the vScroll of field "events" of me into tWas
   put glScrollEnd("events") into tEnd
   -- the last line's return left out, or the box would end on a blank line
   put sLog into tText
   if the last char of tText is return then delete the last char of tText
   set the text of field "events" of me to tText
   if tWas < tEnd - 2 and sLog is not empty then
      set the vScroll of field "events" of me to min(tWas, glScrollEnd("events"))
   else
      set the vScroll of field "events" of me to glScrollEnd("events")
   end if
   glScrollMark "events"
end glShowLog

-- How far a box scrolls: 0 when its words fit
function glScrollEnd pField
   local tWhole, tSeen
   put the formattedHeight of field pField of me into tWhole
   put the height of field pField of me into tSeen
   return max(0, tWhole - tSeen)
end glScrollEnd

-- A box's own scroll bar, a thin bar in its right margin, shown only when
-- its words are longer than it: its length the part in view, its place
-- where the view is. The engine's own scroll bar is drawn light whatever
-- the box's colours, on a dark system too.
command glScrollMark pField
   local tMark, tRect, tEnd, tLen, tAt, tTop
   put pField & "Mark" into tMark
   if there is not a graphic tMark of me then exit glScrollMark
   put glScrollEnd(pField) into tEnd
   if tEnd <= 0 then
      hide graphic tMark of me
      exit glScrollMark
   end if
   put the rect of field pField of me into tRect
   put glMarkLength(pField) into tLen
   put the vScroll of field pField of me into tAt
   put item 2 of tRect + 4 + round((glMarkTravel(pField) - tLen) * max(0, min(1, tAt / tEnd))) into tTop
   set the rect of graphic tMark of me to (item 3 of tRect - 9) & comma & tTop & comma & (item 3 of tRect - 3) & comma & (tTop + tLen)
   show graphic tMark of me
end glScrollMark

-- The length the bar runs in, and the bar's own: the part of the words in
-- view, but never too short to take hold of
function glMarkTravel pField
   return the height of field pField of me - 8
end glMarkTravel

function glMarkLength pField
   local tSeen, tWhole
   put the height of field pField of me into tSeen
   put the formattedHeight of field pField of me into tWhole
   if tWhole <= 0 then return glMarkTravel(pField)
   return max(16, min(glMarkTravel(pField), round(glMarkTravel(pField) * tSeen / tWhole)))
end glMarkLength

-- The wheel over the log or the mapping, or over its bar: three lines a
-- click. 65308 is the wheel turned towards the person (further down the
-- words), 65309 away.
function glWheel pName, pKey
   local tField, tStep, tAt
   if pName is "eventsMark" or pName is "mappingMark" then
      put char 1 to -5 of pName into tField
   else
      put pName into tField
   end if
   if tField is not "events" and tField is not "mapping" then return false
   put 3 * round(1.3 * the textSize of field tField of me) into tStep
   if pKey is 65309 then put -tStep into tStep
   put the vScroll of field tField of me + tStep into tAt
   set the vScroll of field tField of me to max(0, min(glScrollEnd(tField), tAt))
   glScrollMark tField
   return true
end glWheel

-- The bar taken hold of and dragged: the words follow it, the bar's whole
-- travel being the whole of the words
command glMarkDown pName, pY
   put char 1 to -5 of pName into sMarkDrag
   put pY into sMarkY
   put the vScroll of field sMarkDrag of me into sMarkScroll
end glMarkDown

command glMarkDrag pY
   local tRoom, tAt
   if sMarkDrag is empty then exit glMarkDrag
   put glMarkTravel(sMarkDrag) - glMarkLength(sMarkDrag) into tRoom
   if tRoom <= 0 then exit glMarkDrag
   put sMarkScroll + round((pY - sMarkY) * glScrollEnd(sMarkDrag) / tRoom) into tAt
   set the vScroll of field sMarkDrag of me to max(0, min(glScrollEnd(sMarkDrag), tAt))
   glScrollMark sMarkDrag
end glMarkDrag

command glMarkUp
   put empty into sMarkDrag
end glMarkUp

command glAxisEvents
   if sStarted is not true then
      set the hilite of button "axisEvents" of me to false
      glLog "axis events need gamepadxt"
      glShowLog
      exit glAxisEvents
   end if
   if the hilite of button "axisEvents" of me then
      gpSetAxisEvents 0.1
      -- the library keeps the step in its own units: 0.1 comes back as
      -- 0.100009
      glLog "axis events on: a line each time an axis moves" && format("%.2f", gpAxisEvents()) && "of its travel"
   else
      gpSetAxisEvents 0
      glLog "axis events off"
   end if
   glShowLog
end glAxisEvents

command glDeadZone
   local tZone
   put max(0, min(0.9, the thumbPosition of scrollbar "deadZone" of me / 100)) into tZone
   if sGhost is true then
      put tZone into sGhostDZ
   else if sStarted is true then
      gpSetDeadZone tZone
   end if
   glShowDeadZone
end glDeadZone

command glStrengths
   set the text of field "lowLabel" of me to "Heavy motor" && glPercent("low")
   set the text of field "highLabel" of me to "Light motor" && glPercent("high")
end glStrengths

function glPercent pScrollbar
   return round(the thumbPosition of scrollbar pScrollbar of me) & "%"
end glPercent

command glRumble pTriggers
   local tLow, tHigh, tOk
   if sPad is 0 and sGhost is not true then exit glRumble
   glUserTakes
   put max(0, min(1, the thumbPosition of scrollbar "low" of me / 100)) into tLow
   put max(0, min(1, the thumbPosition of scrollbar "high" of me / 100)) into tHigh
   if pTriggers is true then
      put glDoRumbleTriggers(tLow, tHigh, 600) into tOk
   else
      put glDoRumble(tLow, tHigh, 600) into tOk
   end if
   if tOk then
      glLog "rumble" && round(tLow * 100) & "%" && round(tHigh * 100) & "% for 600 ms" & glIf(pTriggers is true, " in the triggers")
   else
      glLog "no rumble:" && gpLastError()
   end if
   glShowLog
end glRumble

command glSetLed pIndex
   local tRGB
   if sPad is 0 and sGhost is not true then exit glSetLed
   glUserTakes
   set the itemDelimiter to "|"
   put item pIndex of kLeds into tRGB
   set the itemDelimiter to comma
   if glDoLED(item 1 of tRGB, item 2 of tRGB, item 3 of tRGB) then
      glLog "light set to" && tRGB
   else
      glLog "no light to set:" && gpLastError()
   end if
   glLightShown empty
   glShowLog
end glSetLed

-- The line in the box is the shown pad's mapping. Changed and added, it
-- teaches the library the pad anew: swap a:b0 and b:b1 and the touch
-- pad's south lights east. Restore adds back the line the pad had when
-- this stack first showed it.
command glApplyMapping
   local tLine, tGot
   if sStarted is not true then
      glLog "mappings need gamepadxt"
      glShowLog
      exit glApplyMapping
   end if
   put glMappingRead(line 1 of field "mapping" of me) into tLine
   if tLine is empty then
      glLog "no mapping line to add"
      glShowLog
      exit glApplyMapping
   end if
   put gpAddMapping(tLine) into tGot
   switch tGot
      case 1
         glLog "mapping added for" && item 2 of tLine
         break
      case 0
         glLog "mapping replaced for" && item 2 of tLine
         break
      default
         glLog "mapping refused:" && gpLastError()
   end switch
   put "-" into sHeld
   glShowLabels
   glShowLog
end glApplyMapping

command glRestoreMapping
   local tLine
   if sStarted is not true or sPad is 0 then
      glLog "no mapping to restore"
      glShowLog
      exit glRestoreMapping
   end if
   put sFirstMapping[gpPadGUID(sPad)] into tLine
   if tLine is empty then
      glLog "no mapping to restore"
   else if gpAddMapping(tLine) < 0 then
      glLog "mapping not restored:" && gpLastError()
   else
      glLog "mapping restored for" && item 2 of tLine
   end if
   put "-" into sHeld
   glShowMapping
   glShowLabels
   glShowLog
end glRestoreMapping

-- The fourth showcase's swap: the touch pad's first two buttons trade
-- places in its mapping
command glMapSwap
   local tLine
   if sGhost is true then
      put true into sGhostSwap
      glLog "the recording's south and east swap places"
      exit glMapSwap
   end if
   glShowMapping
   put glMappingRead(line 1 of field "mapping" of me) into tLine
   replace ",a:b0," with ",a:@," in tLine
   replace ",b:b1," with ",b:b0," in tLine
   replace ",a:@," with ",a:b1," in tLine
   if tLine contains ",a:b1," and tLine contains ",b:b0," then
      set the text of field "mapping" of me to glMappingShown(tLine)
      glScrollMark "mapping"
      glApplyMapping
   else
      glLog "this mapping has no a:b0 and b:b1 to swap"
   end if
end glMapSwap

command glMapBack
   if sGhost is true then
      put false into sGhostSwap
      glLog "the recording's buttons are back"
      exit glMapBack
   end if
   glRestoreMapping
end glMapBack

-- A whole gamecontrollerdb.txt; only the lines for this system count
command glLoadMappings
   local tPath, tGot
   if sStarted is not true then
      glLog "mappings need gamepadxt"
      glShowLog
      exit glLoadMappings
   end if
   answer file "Choose a file of mappings, such as gamecontrollerdb.txt"
   put it into tPath
   if tPath is empty then exit glLoadMappings
   put gpAddMappingsFromFile(tPath) into tGot
   if tGot < 0 then
      glLog "the file was not read:" && gpLastError()
   else
      set the itemDelimiter to slash
      glLog tGot && "mapping(s) added from" && the last item of tPath && "(only its lines for" && glSdlPlatform() & ")"
      set the itemDelimiter to comma
   end if
   glShowMapping
   glShowLog
end glLoadMappings

command glFooter
   local tText
   if sStarted is true then
      put "Controllers:" && gpPadCount() & "   Events pushed out of a full queue:" && gpDroppedEvents() & \
            "   SDL assertions:" && gpAssertCount() into tText
      if gpLastError() is not empty then
         put "   Last refusal:" && gpLastError() after tText
      end if
   else if sGhost is true then
      put "No gamepadxt here: the touch pad is a recording made by this stack's script." into tText
   else
      put "Stopped." into tText
   end if
   set the text of field "footer" to tText
end glFooter

command glStatus pLine
   set the text of field "status" of me to pLine
end glStatus

command glStatusLibrary
   glStatus gpLibraryVersion() & ", gamepadxt ABI" && gpABIVersion() & ": reading controllers"
end glStatusLibrary

----------------------------------------------------------------
-- The touch pad, driven by the mouse, a finger and the keys

command glTouchPad
   glUserTakes
   if sGhost is true then
      glLog "the touch pad is gamepadxt's: this one is a recording"
      glShowLog
      exit glTouchPad
   end if
   if sStarted is not true then
      glLog "Start first: the touch pad is gamepadxt's"
      glShowLog
      exit glTouchPad
   end if
   if sTouch is 0 then
      glAttachTouch
      if sTouch is not 0 then
         glSelect sTouch
      end if
   else
      -- its "disconnected" event comes with the next poll
      gpVirtualDetach sTouch
      put 0 into sTouch
   end if
   glTouchLabel
   glShowLog
end glTouchPad

command glTouchLabel
   if sGhost is true then
      set the label of button "touchPad" of me to "Touch pad: a recording"
   else if sTouch is 0 then
      set the label of button "touchPad" of me to "Add a touch pad"
   else
      set the label of button "touchPad" of me to "Remove the touch pad"
   end if
end glTouchLabel

command glTouchDown pName
   local tSide
   if sRunning is not true then exit glTouchDown
   if sGhost is not true and (sTouch is 0 or sPad is not sTouch) and sScene is 0 then
      glLog "the drawing presses only the touch pad's buttons: add it, or show it"
      glShowLog
      exit glTouchDown
   end if
   glUserTakes
   if sGhost is not true and sTouch is 0 then exit glTouchDown
   put the mouseLoc into sDragFrom
   put the milliseconds into sDragStart
   put false into sDragMoved
   set the itemDelimiter to "_"
   put item 2 of pName into tSide
   set the itemDelimiter to comma
   if pName is "btn_leftstick" or pName is "well_left" or pName is "dz_left" then
      put "left" into sDrag
   else if pName is "btn_rightstick" or pName is "well_right" or pName is "dz_right" then
      put "right" into sDrag
   else if pName begins with "trig" then
      put tSide & "trigger" into sDrag
      glDragTo item 1 of the mouseLoc, item 2 of the mouseLoc
   else if pName begins with "btn_" then
      put char 5 to -1 of pName into sDrag
      glVButton sDrag, true
   end if
end glTouchDown

command glDragTo pX, pY
   local tC, tDX, tDY, tLen, tTravel, tW
   switch sDrag
      case "left"
      case "right"
         -- a tap leaves the stick where it is (it clicks it in, below)
         if not sDragMoved and abs(pX - item 1 of sDragFrom) + abs(pY - item 2 of sDragFrom) < 5 then exit glDragTo
         put true into sDragMoved
         put the loc of graphic ("well_" & sDrag) into tC
         put (the width of graphic ("well_" & sDrag) - the width of graphic ("btn_" & sDrag & "stick")) / 2 into tTravel
         put (pX - item 1 of tC) / tTravel into tDX
         put (pY - item 2 of tC) / tTravel into tDY
         put sqrt(tDX * tDX + tDY * tDY) into tLen
         if tLen > 1 then
            divide tDX by tLen
            divide tDY by tLen
         end if
         glVAxis sDrag & "x", tDX
         glVAxis sDrag & "y", tDY
         break
      case "lefttrigger"
      case "righttrigger"
         put the rect of graphic ("trigwell_" & char 1 to -8 of sDrag) into tW
         put (item 4 of tW - pY) / (item 4 of tW - item 2 of tW) into tDX
         glVAxis sDrag, tDX
         break
   end switch
end glDragTo

command glTouchUp
   local tWhat
   put sDrag into tWhat
   put empty into sDrag
   switch tWhat
      case "left"
      case "right"
         glVAxis tWhat & "x", 0
         glVAxis tWhat & "y", 0
         if not sDragMoved and the milliseconds - sDragStart < 400 then
            -- a tap clicks the stick in: both reach the next poll
            glVButton tWhat & "stick", true
            glVButton tWhat & "stick", false
         end if
         break
      case "lefttrigger"
      case "righttrigger"
         glVAxis tWhat, 0
         break
      default
         if tWhat is not empty then glVButton tWhat, false
   end switch
end glTouchUp

----------------------------------------------------------------
-- The mouse and the keys

on mouseDown pWhich
   local tName
   put the short name of the target into tName
   if tName begins with "btn_" or tName begins with "well_" or tName begins with "trig" or tName begins with "dz_" then
      glTouchDown tName
   else if tName is "eventsMark" or tName is "mappingMark" then
      glMarkDown tName, item 2 of the mouseLoc
   end if
   pass mouseDown
end mouseDown

on mouseMove pX, pY
   if sDrag is not empty then glDragTo pX, pY
   if sMarkDrag is not empty then glMarkDrag pY
   pass mouseMove
end mouseMove

on mouseRelease pWhich
   if sDrag is not empty then glTouchUp
   glMarkUp
   pass mouseRelease
end mouseRelease

on mouseUp pWhich
   local tName
   glMarkUp
   if sDrag is not empty then
      glTouchUp
      pass mouseUp
   end if
   put the short name of the target into tName
   switch
      case tName begins with "show_"
         put false into sTour
         glPlayScene char 6 to -1 of tName
         break
      case tName is "playAll"
         if sTour is true then
            glUserTakes
         else
            put true into sTour
            glPlayScene 1
         end if
         glShowSceneButtons
         break
      case tName is "padList"
         glPickFromList
         break
      case tName is "touchPad"
         glTouchPad
         break
      case tName is "startStop"
         glStartStop
         break
      case tName is "axisEvents"
         glAxisEvents
         break
      case tName is "clearLog"
         put empty into sLog
         glShowLog
         break
      case tName is "rumble"
         glRumble false
         break
      case tName is "rumbleTriggers"
         glRumble true
         break
      case tName begins with "led_"
         glSetLed char 5 to -1 of tName
         break
      case tName begins with "player_"
         glUserTakes
         glSetPlayer char 8 to -1 of tName
         break
      case tName is "applyMapping"
         glUserTakes
         glApplyMapping
         break
      case tName is "restoreMapping"
         glUserTakes
         glRestoreMapping
         break
      case tName is "loadMappings"
         glLoadMappings
         break
      case tName is "mapping"
         glEditMapping
         break
   end switch
   pass mouseUp
end mouseUp

-- The mapping line is edited in place: a click opens the box, and leaving
-- it, or Return, closes it again (Return adds the line too)
command glEditMapping
   if the lockText of field "mapping" of me is false then exit glEditMapping
   set the lockText of field "mapping" of me to false
   set the traversalOn of field "mapping" of me to true
   focus on field "mapping" of me
   select after text of field "mapping" of me
   glScrollMark "mapping"
end glEditMapping

command glLockMapping
   set the lockText of field "mapping" of me to true
   set the traversalOn of field "mapping" of me to false
end glLockMapping

on closeField
   if the short name of the target is "mapping" then glLockMapping
   pass closeField
end closeField

-- Typing in the mapping, or moving in it, can scroll it: its bar follows
on textChanged
   if the short name of the target is "mapping" then glScrollMark "mapping"
   pass textChanged
end textChanged

on selectionChanged
   if the short name of the target is "mapping" then glScrollMark "mapping"
   pass selectionChanged
end selectionChanged

on exitField
   if the short name of the target is "mapping" then glLockMapping
   pass exitField
end exitField

on returnInField
   if the short name of the target is not "mapping" then pass returnInField
   glLockMapping
   focus on nothing
   glUserTakes
   glApplyMapping
end returnInField

on enterInField
   if the short name of the target is not "mapping" then pass enterInField
   glLockMapping
   focus on nothing
   glUserTakes
   glApplyMapping
end enterInField

on scrollbarDrag pValue
   switch the short name of the target
      case "deadZone"
         glDeadZone
         break
      case "low"
      case "high"
         glStrengths
         break
   end switch
   pass scrollbarDrag
end scrollbarDrag

-- Arrows move the touch pad's left stick; Z X A S are south, east, west
-- and north, Q and W the shoulders, Return start
on rawKeyDown pKey
   -- the mouse wheel, over a box that scrolls
   if pKey is 65308 or pKey is 65309 then
      if glWheel(the short name of the target, pKey) then exit rawKeyDown
      pass rawKeyDown
   end if
   if pKey >= 65 and pKey <= 90 then add 32 to pKey
   if sRunning is not true or (sTouch is 0 and sGhost is not true) or the selectedField is not empty or pKey is not among the items of kDriveKeys then
      pass rawKeyDown
   end if
   glUserTakes
   if sKeys[pKey] is not true then
      put true into sKeys[pKey]
      glKey pKey, true
   end if
end rawKeyDown

on rawKeyUp pKey
   if pKey >= 65 and pKey <= 90 then add 32 to pKey
   if sKeys[pKey] is true then
      put false into sKeys[pKey]
      glKey pKey, false
   end if
   pass rawKeyUp
end rawKeyUp

command glKey pKey, pDown
   local tX, tY
   switch pKey
      case 65361
      case 65362
      case 65363
      case 65364
         put 0 into tX
         put 0 into tY
         if sKeys[65361] is true then subtract 1 from tX
         if sKeys[65363] is true then add 1 to tX
         if sKeys[65362] is true then subtract 1 from tY
         if sKeys[65364] is true then add 1 to tY
         glVAxis "leftx", tX
         glVAxis "lefty", tY
         break
      case 122
         glVButton "south", pDown
         break
      case 120
         glVButton "east", pDown
         break
      case 97
         glVButton "west", pDown
         break
      case 115
         glVButton "north", pDown
         break
      case 113
         glVButton "leftshoulder", pDown
         break
      case 119
         glVButton "rightshoulder", pDown
         break
      case 65293
      case 65421
         glVButton "start", pDown
         break
   end switch
end glKey

----------------------------------------------------------------
-- Words

function glLabelText pLabel
   switch pLabel
      case "cross"
         return numToCodepoint(10005)
      case "circle"
         return numToCodepoint(9675)
      case "square"
         return numToCodepoint(9633)
      case "triangle"
         return numToCodepoint(9651)
      default
         return toUpper(pLabel)
   end switch
end glLabelText

function glHex pNumber
   local tHex
   put toLower(baseConvert(pNumber, 10, 16)) into tHex
   repeat while the number of chars of tHex < 4
      put "0" before tHex
   end repeat
   return "0x" & tHex
end glHex

function glPlayerName pPlayer
   if pPlayer is not an integer or pPlayer < 0 then return "none"
   return pPlayer + 1
end glPlayerName

function glBattery pPad
   local tLevel, tPower
   put gpPadBattery(pPad) into tLevel
   switch gpPadPower(pPad)
      case "onbattery"
         put "on battery" into tPower
         break
      case "nobattery"
         put "wired, no battery" into tPower
         break
      default
         put gpPadPower(pPad) into tPower
   end switch
   if tLevel is not an integer or tLevel < 0 then return tPower
   return tLevel & "%," && tPower
end glBattery

-- The name SDL gives this system in a mapping's platform: field
function glSdlPlatform
   switch the platform
      case "Win32"
         return "Windows"
      case "MacOS"
         return "Mac OS X"
      case "HTML5"
         return "Emscripten"
      default
         return the platform
   end switch
end glSdlPlatform

function glYesNo pBool
   if pBool is true then return "yes"
   return "no"
end glYesNo

function glPair pX, pY
   if pX is not a number then put 0 into pX
   if pY is not a number then put 0 into pY
   return format("%5.2f,%5.2f", pX, pY)
end glPair

function glOr pText, pElse
   if pText is empty then return pElse
   return pText
end glOr

function glIf pCondition, pText
   if pCondition then return pText
   return empty
end glIf

function glIfNumber pCondition, pYes, pNo
   if pCondition then return pYes
   return pNo
end glIfNumber

-- A colour pAmount (0 to 1) of the way from pFrom to pTo
function glBlend pFrom, pTo, pAmount
   local tI, tOut
   if pAmount is not a number then put 0 into pAmount
   put max(0, min(1, pAmount)) into pAmount
   put empty into tOut
   repeat with tI = 1 to 3
      put round(item tI of pFrom + (item tI of pTo - item tI of pFrom) * pAmount) & comma after tOut
   end repeat
   delete the last char of tOut
   return tOut
end glBlend

-- The colour at pFrac of the way round the colour wheel, at full strength
function glHue pFrac
   local tH, tI, tF, tDown, tUp
   put (pFrac mod 1) * 6 into tH
   put trunc(tH) into tI
   put tH - tI into tF
   put round(255 * (1 - tF)) into tDown
   put round(255 * tF) into tUp
   switch tI
      case 0
         return "255," & tUp & ",0"
      case 1
         return tDown & ",255,0"
      case 2
         return "0,255," & tUp
      case 3
         return "0," & tDown & ",255"
      case 4
         return tUp & ",0,255"
      default
         return "255,0," & tDown
   end switch
end glHue

----------------------------------------------------------------
-- The window, built by script the first time the stack opens (and again
-- when kGlUiVersion changes)

command glBuild
   local tI, tName, tLabels, tLeds, tX, tY
   set the defaultStack to the short name of me
   if the cGlUi of me is kGlUiVersion and there is a group "controller" then exit glBuild
   lock screen
   lock messages
   glClearCard
   set the width of this stack to kGlWidth
   set the height of this stack to kGlHeight
   set the label of this stack to "Gamepad Lab"
   set the resizable of this stack to false
   set the backgroundColor of this stack to kBg
   set the foregroundColor of this stack to kText
   set the hiliteColor of this stack to "70,92,128"
   set the textSize of this stack to 12

   -- The header: the name of the place, the demo's own, what it does, who
   -- made it, and what is running
   glField "brand", "18,6,560,22", "OXT-Beyond  |  xTalk Suite  |  gamepadxt", 11, kAccent, "bold"
   glField "title", "14,20,230,56", "Gamepad Lab", 24, "255,255,255", "bold"
   glField "tagline", "226,32,900,50", "Game controllers through gamepadxt (SDL 3): buttons, sticks, triggers, rumble, light and mappings.", 12, kDim
   glField "byline", "900,6,1166,24", "by Seth Morrow", 12, kText
   set the textAlign of field "byline" to "right"
   glField "status", "700,30,1166,50", empty, 11, kDim
   set the textAlign of field "status" to "right"
   glGraphic "rule", "rectangle", "0,58,1180,59", kPanelLine, kPanelLine

   -- The stage: what plays, the drawing of a controller, and the game
   glGraphic "stagePanel", "roundrect", "12,64,612,606", kStage, kPanelLine
   set the roundRadius of graphic "stagePanel" to 12
   glGraphic "chipDot", "oval", "26,75,36,85", kAccent, kAccent
   glField "chip", "40,68,600,90", empty, 12, kText, "bold"
   glGraphic "chipWell", "rectangle", "42,92,330,95", kPanelLine, kPanelLine
   glGraphic "chipBar", "rectangle", "42,92,44,95", kAccent, kAccent
   glBuildPad
   glField "readout", "24,362,600,394", empty, 11, kText
   glGraphic "arena", "rectangle", "24,398,600,598", "22,25,30", kWellLine
   set the lineSize of graphic "arena" to 2
   glField "arenaCaption", "30,401,594,417", "The game: left stick rolls, right trigger hurries, west slows, south jumps, east paints, start brings it home", 10, kDim
   glGraphic "ball", "oval", "302,488,322,508", "255,176,58", "200,130,30"
   glGraphic "aim", "line", "312,498,352,498", empty, "255,255,255"
   set the lineSize of graphic "aim" to 2
   set the points of graphic "aim" to "312,498" & return & "352,498"
   hide graphic "aim"

   -- The middle: the controllers, the one on show, and what to set on it
   glPanel "midPanel", "620,64,884,606"
   glHeader "hdrPads", "632,70,872,86", "CONTROLLERS"
   glField "padList", "632,88,872,146", empty, 12, kText
   set the listBehavior of field "padList" to true
   set the dontWrap of field "padList" to true
   set the opaque of field "padList" to true
   set the backgroundColor of field "padList" to "20,23,28"
   set the showBorder of field "padList" to true
   set the borderColor of field "padList" to kPanelLine
   set the hiliteColor of field "padList" to "70,92,128"
   set the margins of field "padList" to 4
   glButton "touchPad", "632,150,796,174", "Remove the touch pad"
   glButton "startStop", "802,150,872,174", "Stop"
   glHeader "hdrInfo", "632,182,872,198", "THIS CONTROLLER"
   glField "padInfo", "632,200,872,336", "No controller on show.", 11, kText
   glHeader "hdrPlayer", "632,340,872,356", "PLAYER NUMBER"
   repeat with tI = 0 to 3
      glButton "player_" & tI, (632 + tI * 46) & ",358," & (672 + tI * 46) & ",382", tI + 1
   end repeat
   glButton "player_-1", "816,358,872,382", "none"
   glHeader "hdrLight", "632,390,872,406", "LIGHT: CLICK A COLOUR"
   put kLeds into tLeds
   split tLeds by "|"
   repeat with tI = 1 to 7
      glGraphic "led_" & tI, "oval", (632 + (tI - 1) * 34) & ",408," & (656 + (tI - 1) * 34) & ",432", tLeds[tI], kWellLine
   end repeat
   set the backgroundColor of graphic "led_7" to "20,22,26"
   glLabel "led_7", "off", 9
   set the foregroundColor of graphic "led_7" to kDim
   glHeader "hdrRumble", "632,440,872,456", "RUMBLE"
   glField "lowLabel", "632,460,738,476", empty, 11, kText
   glScale "low", "742,459,872,477", 0, 100, 80
   glField "highLabel", "632,482,738,498", empty, 11, kText
   glScale "high", "742,481,872,499", 0, 100, 30
   glButton "rumble", "632,504,748,528", "Rumble"
   glButton "rumbleTriggers", "756,504,872,528", "Rumble triggers"
   glField "abilities", "632,532,872,562", empty, 11, kText
   glField "deadZoneLabel", "632,566,872,582", "Dead zone 0.15: the dashed ring in each stick", 11, kText
   glScale "deadZone", "632,584,872,602", 0, 90, 15

   -- The right: the showcases, what this shows, the events, the mapping
   glPanel "rightPanel", "892,64,1168,606"
   glHeader "hdrShow", "904,70,1156,86", "SHOWCASES"
   set the itemDelimiter to "|"
   repeat with tI = 1 to 5
      put 904 + ((tI - 1) mod 2) * 128 into tX
      put 90 + ((tI - 1) div 2) * 28 into tY
      glButton "show_" & tI, tX & comma & tY & comma & (tX + 124) & comma & (tY + 24), item tI of kSceneLabels
   end repeat
   set the itemDelimiter to comma
   glButton "playAll", "1032,146,1156,170", "Play all five"
   glHeader "hdrAbout", "904,180,1156,196", "WHAT THIS SHOWS"
   glField "about", "904,198,1156,322", empty, 11, kText
   glHeader "eventsHeader", "904,328,1096,344", "EVENTS FROM gpEvents()"
   glButton "clearLog", "1100,326,1156,344", "Clear"
   set the textSize of button "clearLog" to 10
   glField "events", "904,348,1156,470", empty, 10, kText
   set the opaque of field "events" to true
   set the backgroundColor of field "events" to "16,18,22"
   set the showBorder of field "events" to true
   set the borderColor of field "events" to kPanelLine
   -- a line too long for the box wraps under its words, its time out to
   -- the left; the right margin holds the box's own scroll bar
   set the margins of field "events" to 4
   set the leftMargin of field "events" to 50
   set the rightMargin of field "events" to 12
   set the firstIndent of field "events" to -46
   set the tabStops of field "events" to 46
   glMark "events"
   glCheckbox "axisEvents", "904,474,1156,492", "Report stick and trigger moves too"
   glHeader "mappingHeader", "904,500,1156,516", "MAPPING: THE LINE SDL READS IT BY"
   glField "mapping", "904,518,1156,562", empty, 10, kText
   -- locked until clicked: a field that takes the keyboard when the window
   -- opens would take the keys from the touch pad
   set the opaque of field "mapping" to true
   set the backgroundColor of field "mapping" to "20,23,28"
   set the showBorder of field "mapping" to true
   set the borderColor of field "mapping" to kPanelLine
   set the margins of field "mapping" to 4
   set the rightMargin of field "mapping" to 12
   glMark "mapping"
   glButton "applyMapping", "904,568,984,592", "Add"
   glButton "restoreMapping", "990,568,1070,592", "Restore"
   glButton "loadMappings", "1076,568,1156,592", "From a file"

   glField "footer", "16,612,1166,632", empty, 11, kDim
   set the cGlUi of me to kGlUiVersion
   unlock messages
   unlock screen
end glBuild

-- The drawing of a controller, in one group the rumble shakes
command glBuildPad
   local tI, tName, tLabels
   create group "controller"
   set the showBorder of group "controller" to false
   set the opaque of group "controller" to false
   set the margins of group "controller" to 0
   glPadGraphic "grip_left", "oval", "292,160,420,296", kBody, kBody
   glPadGraphic "grip_right", "oval", "540,160,668,296", kBody, kBody
   glPadGraphic "padBody", "roundrect", "296,84,664,260", kBody, kBody
   set the roundRadius of graphic "padBody" to 70
   -- shoulders, triggers, the light and the touch pad
   glPadGraphic "btn_leftshoulder", "roundrect", "318,66,410,82", kIdle, kIdle
   glPadGraphic "btn_rightshoulder", "roundrect", "550,66,642,82", kIdle, kIdle
   glPadGraphic "trigwell_left", "rectangle", "274,88,288,230", kWell, kWellLine
   glPadGraphic "trigwell_right", "rectangle", "672,88,686,230", kWell, kWellLine
   glPadGraphic "trig_left", "rectangle", "274,229,288,230", kHeld, kHeld
   glPadGraphic "trig_right", "rectangle", "672,229,686,230", kHeld, kHeld
   hide graphic "trig_left"
   hide graphic "trig_right"
   glPadGraphic "lightbar", "roundrect", "450,88,510,94", "40,44,52", "40,44,52"
   glPadGraphic "btn_touchpad", "roundrect", "430,98,530,130", kIdle, kLabelInk
   glLabel "btn_touchpad", "touchpad", 9
   -- back, guide and start, and the four player lights
   glPadGraphic "btn_back", "roundrect", "436,140,466,154", kIdle, kIdle
   glPadGraphic "btn_start", "roundrect", "494,140,524,154", kIdle, kIdle
   glPadCircle "btn_guide", 480, 164, 22, kIdle, kIdle
   repeat with tI = 1 to 4
      glPadCircle "plr_" & tI, 454 + tI * 12, 190, 8, kWell, kWellLine
   end repeat
   -- the sticks: a well, the dead zone's ring and the knob
   glPadStick "left", 360, 140
   glPadStick "right", 555, 215
   -- the face buttons, named by place; the label is what is printed
   glPadCircle "btn_north", 600, 121, 26, kIdle, kInk
   glPadCircle "btn_south", 600, 169, 26, kIdle, kInk
   glPadCircle "btn_west", 576, 145, 26, kIdle, kInk
   glPadCircle "btn_east", 624, 145, 26, kIdle, kInk
   repeat for each item tName in "north,south,west,east"
      set the textSize of graphic ("btn_" & tName) to 13
      set the textStyle of graphic ("btn_" & tName) to "bold"
   end repeat
   -- the cross
   glPadGraphic "btn_dpup", "roundrect", "395,191,415,211", kIdle, kIdle
   glPadGraphic "btn_dpdown", "roundrect", "395,219,415,239", kIdle, kIdle
   glPadGraphic "btn_dpleft", "roundrect", "381,205,401,225", kIdle, kIdle
   glPadGraphic "btn_dpright", "roundrect", "409,205,429,225", kIdle, kIdle
   -- the buttons few pads have: paddles and the extra ones
   put "leftpaddle1:LP1,leftpaddle2:LP2,misc1:M1,misc2:M2,misc3:M3,misc4:M4,misc5:M5,misc6:M6,rightpaddle2:RP2,rightpaddle1:RP1" into tLabels
   put 0 into tI
   repeat for each item tName in tLabels
      set the itemDelimiter to colon
      glPadGraphic "btn_" & item 1 of tName, "roundrect", (303 + tI * 36) & ",302," & (333 + tI * 36) & ",316", kIdle, kLabelInk
      glLabel "btn_" & item 1 of tName, item 2 of tName, 9
      set the itemDelimiter to comma
      add 1 to tI
   end repeat
   set the lockLoc of group "controller" to true
   set the rect of group "controller" to glMoved("268,62,692,320")
   set the cHome of group "controller" to the topLeft of group "controller"
end glBuildPad

-- Deletes what an older build left on the card
command glClearCard
   local tGuard
   if the cGlUi of me is empty and there is no group "controller" then exit glClearCard
   put 0 into tGuard
   repeat while the number of controls of this card > 0 and tGuard < 2000
      delete control 1 of this card
      add 1 to tGuard
   end repeat
end glClearCard

-- A rect of the drawing's builder, moved to where the drawing goes
function glMoved pRect
   local tDX, tDY
   put kPadLeft - 268 into tDX
   put kPadTop - 62 into tDY
   return (item 1 of pRect + tDX) & comma & (item 2 of pRect + tDY) & comma & (item 3 of pRect + tDX) & comma & (item 4 of pRect + tDY)
end glMoved

command glPadGraphic pName, pStyle, pRect, pFill, pLine
   glGraphic pName, pStyle, glMoved(pRect), pFill, pLine, "controller"
end glPadGraphic

-- A round graphic of the controller, by its centre and its size
command glPadCircle pName, pX, pY, pSize, pFill, pLine
   glPadGraphic pName, "oval", (pX - pSize div 2) & comma & (pY - pSize div 2) & comma & (pX + pSize div 2) & comma & (pY + pSize div 2), pFill, pLine
end glPadCircle

command glPadStick pSide, pX, pY
   glPadCircle "well_" & pSide, pX, pY, 72, kWell, kWellLine
   glPadCircle "dz_" & pSide, pX, pY, 30, empty, "96,104,120"
   set the dashes of graphic ("dz_" & pSide) to "3,3"
   glPadCircle "btn_" & pSide & "stick", pX, pY, 26, kKnob, "150,158,172"
end glPadStick

command glField pName, pRect, pText, pSize, pColour, pStyle
   create field pName
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the opaque of field pName to false
   set the showBorder of field pName to false
   set the threeD of field pName to false
   set the dontWrap of field pName to false
   set the margins of field pName to 2
   set the textSize of field pName to pSize
   set the foregroundColor of field pName to pColour
   set the backgroundColor of field pName to kStage
   if pStyle is not empty then set the textStyle of field pName to pStyle
   set the text of field pName to pText
end glField

-- A box's own scroll bar, hidden until its words are longer than it
command glMark pField
   glGraphic pField & "Mark", "roundrect", "0,0,6,20", kKnob, kKnob
   set the roundRadius of graphic (pField & "Mark") to 6
   hide graphic (pField & "Mark")
end glMark

command glHeader pName, pRect, pText
   glField pName, pRect, pText, 11, kAccent, "bold"
end glHeader

command glPanel pName, pRect
   glGraphic pName, "roundrect", pRect, kPanel, kPanelLine
   set the roundRadius of graphic pName to 12
end glPanel

command glButton pName, pRect, pLabel
   create button pName
   set the style of button pName to "roundrect"
   set the rect of button pName to pRect
   set the label of button pName to pLabel
   set the opaque of button pName to true
   set the threeD of button pName to false
   set the showBorder of button pName to true
   set the backgroundColor of button pName to kButtonFill
   set the borderColor of button pName to kButtonLine
   set the foregroundColor of button pName to kButtonText
   set the hiliteColor of button pName to kAccent
   set the showFocusBorder of button pName to false
   set the traversalOn of button pName to false
   set the autoHilite of button pName to true
   set the textSize of button pName to 11
end glButton

command glCheckbox pName, pRect, pLabel
   create button pName
   set the style of button pName to "checkbox"
   set the rect of button pName to pRect
   set the label of button pName to pLabel
   set the hilite of button pName to false
   set the autoHilite of button pName to true
   set the backgroundColor of button pName to kPanel
   set the foregroundColor of button pName to kText
   set the hiliteColor of button pName to kAccent
   set the showFocusBorder of button pName to false
   set the traversalOn of button pName to false
   set the textSize of button pName to 11
end glCheckbox

command glScale pName, pRect, pStart, pEnd, pValue
   create scrollbar pName
   set the style of scrollbar pName to "scale"
   set the rect of scrollbar pName to pRect
   set the startValue of scrollbar pName to pStart
   set the endValue of scrollbar pName to pEnd
   set the thumbPosition of scrollbar pName to pValue
   set the showValue of scrollbar pName to false
   set the lineIncrement of scrollbar pName to 1
   set the pageIncrement of scrollbar pName to 10
   set the backgroundColor of scrollbar pName to kPanel
   set the foregroundColor of scrollbar pName to kText
   set the traversalOn of scrollbar pName to false
end glScale

command glGraphic pName, pStyle, pRect, pFill, pLine, pGroup
   if pGroup is empty then
      create graphic pName
   else
      create graphic pName in group pGroup
   end if
   set the style of graphic pName to pStyle
   set the rect of graphic pName to pRect
   set the antialiased of graphic pName to true
   set the lineSize of graphic pName to 1
   if pFill is empty then
      set the opaque of graphic pName to false
   else
      set the opaque of graphic pName to true
      set the backgroundColor of graphic pName to pFill
   end if
   if pLine is empty then put pFill into pLine
   set the foregroundColor of graphic pName to pLine
   set the cLine of graphic pName to pLine
   set the showName of graphic pName to false
   if pStyle is "roundrect" then set the roundRadius of graphic pName to 6
end glGraphic

command glLabel pGraphic, pLabel, pSize
   set the label of graphic pGraphic to pLabel
   set the textSize of graphic pGraphic to pSize
   set the showName of graphic pGraphic to true
end glLabel
