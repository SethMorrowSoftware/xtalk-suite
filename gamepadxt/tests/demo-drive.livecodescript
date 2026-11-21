script "GamepadLabDrive"
-- demo-drive.livecodescript - examples/gamepad-lab.livecodescript driven on
-- a real engine with no person at it.
--
--    GL_LCM=<gamepadxt.lcm> GL_LIBRARY=<library, no extension> \
--    GL_DEMO=examples/gamepad-lab.livecodescript \
--       <OXT-Beyond>/LiveCode-Community -ui tests/demo-drive.livecodescript
--
-- With GL_LCM it loads gamepadxt and opens the window as another stack
-- would find it: the library already started, its dead zone set to 0.20 and
-- a controller plugged in (a virtual pad named "Early pad"). It watches the
-- window open playing and the five showcases play through as the tour plays
-- them, then does what a person would: the keys, the drawing's sticks,
-- trigger and buttons, rumble, the light, the player number, the dead zone,
-- axis events and a changed mapping, a press on the early pad and a second
-- pad plugged in mid-run (each takes over and is greeted), the showcase
-- buttons, Stop and Start, the window's size and colours, and closing it.
--
-- With no GL_LCM it opens the window in an engine with no gamepadxt, where
-- it must still open moving and say so in words: the recording, each
-- showcase from its button, the keys and the buttons.
--
-- The native lane runs both (the suite's .github/workflows/
-- native-gamepadxt.yml, job `engine`) and wants an exit of 0 AND a last
-- line "DRIVE <passed> 0" from each: an engine that printed nothing must not
-- read as a pass.
--
-- A click is the message the engine sends (mouseUp, scrollbarDrag,
-- rawKeyDown, returnInField); a press or a drag ON THE DRAWING is the
-- handler the window's mouse handlers call with the point they read
-- (glTouchDown, glDragTo, glTouchUp), since no pointer moves here. "From a
-- file" opens a dialog and is not driven.
--
-- GL_SHOTS (optional) names a folder for pictures of the window at a moment
-- of each showcase. It needs a display (xvfb-run).
--
-- WHAT THIS IS EVIDENCE OF: the window's logic and its timing on
-- OXT-Beyond's Linux engine without a display, over virtual pads. It is not
-- a person at a screen, a real controller or another platform.

constant kStack = "GamepadLabRun"
constant kWave = "south,east,west,north,leftshoulder,rightshoulder,dpup,dpright,dpdown,dpleft,back,guide,start,leftstick,rightstick,touchpad,leftpaddle1,leftpaddle2,rightpaddle1,rightpaddle2,misc1,misc2,misc3,misc4,misc5,misc6"
-- The window's colours this drive looks for
constant kIdleFill = "62,69,82"
constant kBodyFill = "44,49,58"
constant kLiveColour = "96,200,110"
constant kAccentColour = "255,150,60"
constant kQuietFill = "40,46,60"
constant kDarkWords = "24,26,32"
constant kWellFill = "30,34,41"

local sPassed, sFailed, sTouch, sEarly, sShots, sOpenedAt
local sPlayerBefore, sLedBefore
-- The boxes seen showing less than all their words, and how many times
-- the drive looked
local sUnfit, sFitLooks
-- Each moment the game's ball was found over its caption's words
local sCovered

on startup
   local tError
   put 0 into sPassed
   put 0 into sFailed
   put $GL_SHOTS into sShots
   try
      if $GL_LCM is not empty then
         drLibraryRun
      else
         drRecordingRun
      end if
   catch tError
      drCheck false, "the drive ran to its end", line 1 to 3 of tError
   end try
   drSay "DRIVE" && sPassed && sFailed
   if sFailed is 0 and sPassed > 0 then
      quit 0
   end if
   quit 1
end startup

----------------------------------------------------------------
-- Checks and the window's controls

command drSay pLine
   write pLine & return to stdout
end drSay

command drCheck pOk, pLabel, pDetail
   if pOk is true then
      add 1 to sPassed
      drSay "PASS  " & pLabel
   else
      add 1 to sFailed
      drSay "FAIL  " & pLabel & "  [" & pDetail & "]"
   end if
end drCheck

function drText pField
   return the text of field pField of card 1 of stack kStack
end drText

function drBg pControl
   return the backgroundColor of control pControl of card 1 of stack kStack
end drBg

function drFg pControl
   return the foregroundColor of control pControl of card 1 of stack kStack
end drFg

function drLabel pButton
   return the label of button pButton of card 1 of stack kStack
end drLabel

function drShown pControl
   return the visible of control pControl of card 1 of stack kStack
end drShown

function drLog
   return the text of field "events" of card 1 of stack kStack
end drLog

-- The mapping box's line as SDL reads it: the box shows a space after each
-- comma, so that the line wraps
function drMapping
   local tLine
   put line 1 of drText("mapping") into tLine
   replace comma & space with comma in tLine
   return tLine
end drMapping

-- The last pLines lines of the window's event log
function drTail pLines
   local tLog
   put drLog() into tLog
   return line max(1, the number of lines of tLog - pLines + 1) to -1 of tLog
end drTail

-- Whether the drawing of a controller is where it rests
function drAtHome
   return the topLeft of group "controller" of card 1 of stack kStack is the cHome of group "controller" of card 1 of stack kStack
end drAtHome

-- A click, as the engine sends it
command drClick pControl
   dispatch "mouseUp" to control pControl of card 1 of stack kStack with 1
end drClick

-- One of the window's own handlers, with what its mouse handlers would pass
command drCall pHandler, pA, pB
   dispatch pHandler to stack kStack with pA, pB
end drCall

command drKey pKey, pDown
   if pDown then
      dispatch "rawKeyDown" to card 1 of stack kStack with pKey
   else
      dispatch "rawKeyUp" to card 1 of stack kStack with pKey
   end if
end drKey

command drSlide pScrollbar, pValue
   set the thumbPosition of scrollbar pScrollbar of card 1 of stack kStack to pValue
   dispatch "scrollbarDrag" to scrollbar pScrollbar of card 1 of stack kStack with pValue
end drSlide

command drWait pMs
   wait pMs milliseconds with messages
end drWait

-- Waits, with the window running, until the line over its stage begins
-- with pText, at most pMs
function drChipWait pText, pMs
   local tUntil
   put the milliseconds + pMs into tUntil
   repeat while the milliseconds < tUntil
      if drText("chip") begins with pText then return true
      wait 10 milliseconds with messages
   end repeat
   return drText("chip") begins with pText
end drChipWait

-- How many frames the window drew in pMs, counted by the timer messages it
-- sends itself
function drFrames pMs
   local tUntil, tSeen, tLine, tCount
   put the milliseconds + pMs into tUntil
   put 0 into tCount
   repeat while the milliseconds < tUntil
      repeat for each line tLine in the pendingMessages
         if item 3 of tLine is "glFrame" and tSeen[item 1 of tLine] is not true then
            put true into tSeen[item 1 of tLine]
            add 1 to tCount
         end if
      end repeat
      wait 3 milliseconds with messages
   end repeat
   return tCount
end drFrames

function drFramePending
   local tLine
   repeat for each line tLine in the pendingMessages
      if item 3 of tLine is "glFrame" then return true
   end repeat
   return false
end drFramePending

command drNoFrameError pWhen
   local tLog
   put drLog() into tLog
   drCheck not (tLog contains "error in the frame"), "no frame failed (" & pWhen & ")", line lineOffset("error in the frame", tLog) of tLog
end drNoFrameError

-- Every box must show all its words: none may run off its right edge (a
-- word the engine cannot break, or a line that does not wrap), and none
-- but the two that scroll (the log and the mapping) may run off its
-- bottom. What does is noted with the moment. The words change as the window
-- plays, so this looks at many moments and drWindowLook gives the verdict.
command drFits pWhen
   local tI, tC, tName, tOver
   add 1 to sFitLooks
   repeat with tI = 1 to the number of fields of card 1 of stack kStack
      put the long id of field tI of card 1 of stack kStack into tC
      put the short name of tC into tName
      if not the visible of tC or the text of tC is empty then next repeat
      if tName is not "events" and tName is not "mapping" and the formattedHeight of tC > the height of tC then
         put tName && "(" & pWhen & ": its words need" && the formattedHeight of tC && "of" && the height of tC & ") " after sUnfit
      end if
      -- a wrapped line measures up to 3 points over the width it was
      -- wrapped to (the engine rounds its pieces up, and the box's margin
      -- holds them); a word too long to wrap, or a line that does not
      -- wrap, runs further
      put the formattedWidth of tC - the width of tC into tOver
      if tOver > 0 and (the dontWrap of tC or tOver > 3) then
         put tName && "(" & pWhen & ": a line needs" && the formattedWidth of tC && "of" && the width of tC & ") " after sUnfit
      end if
   end repeat
   if not drBallUnder() then put "(" & pWhen & ":" && drBallTop() & ") " after sCovered
end drFits

-- Whether the game's ball is clear of the caption across the arena's top:
-- its top at or below the caption's foot
function drBallUnder
   return item 2 of the rect of graphic "ball" of card 1 of stack kStack >= item 4 of the rect of field "arenaCaption" of card 1 of stack kStack
end drBallUnder

function drBallTop
   return "the ball" && the rect of graphic "ball" of card 1 of stack kStack & ", the caption" && the rect of field "arenaCaption" of card 1 of stack kStack
end drBallTop

-- A picture of the window, when GL_SHOTS names a folder
command drShot pName
   if sShots is empty then exit drShot
   export snapshot from rect (the rect of card 1 of stack kStack) of card 1 of stack kStack to file (sShots & slash & pName & ".png") as PNG
end drShot

command drShotAt pName, pWhen
   if sShots is empty then exit drShotAt
   repeat while the milliseconds < pWhen
      wait 5 milliseconds with messages
   end repeat
   drShot pName
end drShotAt

-- The first pad of that name, 0 for none
function drPadNamed pName
   local tPad
   repeat for each item tPad in gpPads()
      if gpPadName(tPad) is pName then return tPad
   end repeat
   return 0
end drPadNamed

function drPadsNamed pName
   local tPad, tCount
   put 0 into tCount
   repeat for each item tPad in gpPads()
      if gpPadName(tPad) is pName then add 1 to tCount
   end repeat
   return tCount
end drPadsNamed

function drAllZero pList
   local tValue
   if pList is empty then return false
   repeat for each item tValue in pList
      if tValue is not a number or tValue is not 0 then return false
   end repeat
   return true
end drAllZero

----------------------------------------------------------------
-- Opening the window

command drOpen
   local tTook
   create stack kStack
   set the script of stack kStack to textDecode(URL ("binfile:" & $GL_DEMO), "UTF-8")
   drCheck the result is empty, "the window's script compiles", the result
   -- as the window's header tells a person: the script pasted, the stack
   -- closed and opened again (a stack just created is already open, and
   -- going to it sends no opening message)
   close stack kStack
   put the milliseconds into sOpenedAt
   go stack kStack
   put the milliseconds - sOpenedAt into tTook
   drCheck tTook < 1000, "it is built and playing within a second of opening", tTook && "ms"
   drCheck the width of stack kStack is 1180 and the height of stack kStack is 640, "the window is 1180 x 640, inside 720p's 1200 x 640", the width of stack kStack && the height of stack kStack
   drCheck drText("brand") is "OXT-Beyond  |  xTalk Suite  |  gamepadxt" and drText("title") is "Gamepad Lab" \
         and drText("byline") is "by Seth Morrow" and drText("tagline") is not empty, \
         "the header: OXT-Beyond, the demo's name, what it does, by Seth Morrow", drText("brand") & "/" & drText("title") & "/" & drText("byline")
end drOpen

-- The first second, watched: the drawing lights each button the showcase
-- presses
command drFirstSecond @rSeen
   local tUntil, tName, tColour
   put empty into rSeen
   put sOpenedAt + 900 into tUntil
   repeat while the milliseconds < tUntil
      repeat for each item tName in "south,east,west"
         put drBg("btn_" & tName) into tColour
         if tColour is not kIdleFill then put tColour into rSeen[tName]
      end repeat
      wait 8 milliseconds with messages
   end repeat
end drFirstSecond

----------------------------------------------------------------
-- With gamepadxt

command drLibraryRun
   set the revLibraryMapping["gamepadxt"] to $GL_LIBRARY
   load extension from file $GL_LCM
   drCheck the result is empty, "gamepadxt loads", the result
   -- as another stack would leave things: the library started, a dead
   -- zone of its own and a controller plugged in
   drCheck gpStart(), "the drive starts the library first, as another stack would", gpLastError()
   gpSetDeadZone 0.2
   put gpVirtualAttach("Early pad") into sEarly
   drCheck sEarly > 0, "a controller is plugged in before the window opens", gpLastError()
   drOpen
   drCheck drText("status") begins with "SDL 3." and drText("status") ends with "gamepadxt ABI 1: reading controllers", \
         "the status names SDL and the library's ABI", drText("status")
   drOpening
   drShowcase1
   drShowcase2
   drShowcase3
   drShowcase4
   drShowcase5
   drHandsOn
   drTakeOvers
   drScrolling
   drShowcaseButtons
   drStopStart
   drWindowLook
   drClosing
end drLibraryRun

command drOpening
   local tSeen, tLog, tFrames, tLine
   drFirstSecond tSeen
   put drPadNamed("Touch pad") into sTouch
   drCheck sTouch > 0 and gpPadIsVirtual(sTouch), "it attached a touch pad to play the showcases on", gpPads()
   drCheck drText("chip") begins with "Showcase 1 of 5: Every button", "it opens playing: showcase 1 of 5", drText("chip")
   drCheck drShown("chipBar") and drShown("chipWell"), "with a bar for how far it has got", drShown("chipBar")
   drCheck tSeen["south"] is "96,200,110" and tSeen["east"] is "232,92,82" and tSeen["west"] is "82,152,244", \
         "within the first second the drawing lights south, east and west, each in its colour", tSeen["south"] & "/" & tSeen["east"] & "/" & tSeen["west"]
   put drLog() into tLog
   drCheck tLog contains ("button," & sTouch & ",south,down") and tLog contains ("button," & sTouch & ",east,down"), \
         "and each press is a line of gpEvents() in its log", line -4 to -1 of tLog
   drCheck tLog contains "found: Early pad: press a button on it to take over" \
         and drText("status") is "Found Early pad: press a button on it to take over", \
         "the controller already plugged in is named, and waits for a press while the tour plays", drText("status")
   drCheck drText("padList") contains "Early pad (made in software)" and drText("padList") contains "Touch pad (made in software)", \
         "both are listed", drText("padList")
   put line (the hilitedLine of field "padList" of card 1 of stack kStack) of drText("padList") into tLine
   drCheck tLine begins with "Touch pad", "the touch pad is the one on show", tLine
   drCheck drText("padInfo") begins with "Name: Touch pad" and drText("padInfo") contains "Buttons: 26 of 26, axes: 6 of 6", \
         "what it is: a pad with every button and axis", line 1 to 7 of drText("padInfo")
   drCheck drText("deadZoneLabel") begins with "Dead zone 0.20" and the thumbPosition of scrollbar "deadZone" of card 1 of stack kStack is 20, \
         "the dead zone shown is the library's, as it found it", drText("deadZoneLabel")
   drCheck drLabel("playAll") is "Stop the tour" and drBg("show_1") is kAccentColour and drBg("show_2") is kQuietFill, \
         "the playing showcase's button is lit, and the tour can be stopped", drLabel("playAll") && drBg("show_1")
   drCheck drText("about") begins with "Every button SDL knows", "what it shows is said beside it", line 1 of drText("about")
   put drFrames(1000) into tFrames
   drCheck tFrames >= 30, "a timer draws it, at least 30 frames a second", tFrames && "frames in a second"
   drFits "the opening"
end drOpening

command drShowcase1
   local tLog, tName, tMissing, tAt, tAfter, tOk
   drShotAt "1-every-button", sOpenedAt + 9350
   drFits "showcase 1"
   drCheck drChipWait("Showcase 2 of 5", 12000), "showcase 1 ends, and the tour goes on to 2", drText("chip")
   put drLog() into tLog
   put empty into tMissing
   repeat for each item tName in kWave
      if not (tLog contains ("button," & sTouch & comma & tName & ",down")) then put tName & " " after tMissing
   end repeat
   drCheck tMissing is empty, "showcase 1 pressed all 26 buttons, each a line of the log", tMissing
   put offset("," & sTouch & ",misc6,down", tLog) into tAt
   put tAt > 0 into tOk
   if tOk then
      put char tAt to -1 of tLog into tAfter
      repeat for each item tName in "south,east,west,north"
         if not (tAfter contains ("button," & sTouch & comma & tName & ",down")) then put false into tOk
      end repeat
   end if
   drCheck tOk, "then the four face buttons, together", line 1 to 10 of tAfter
   drNoFrameError "showcase 1"
end drShowcase1

function drZoneWait pZone, pMs
   local tUntil
   put the milliseconds + pMs into tUntil
   repeat while the milliseconds < tUntil
      if abs(gpDeadZone() - pZone) < 0.004 then return true
      wait 10 milliseconds with messages
   end repeat
   return false
end drZoneWait

command drShowcase2
   local tRing, tAxes, tStick, tMag, tWant, tGot
   put the width of graphic "dz_left" of card 1 of stack kStack into tRing
   drCheck drZoneWait(0.45, 6000), "showcase 2 widens the dead zone to 0.45 (gpSetDeadZone)", gpDeadZone()
   drShot "2-sticks-and-dead-zone"
   drFits "showcase 2"
   drCheck the thumbPosition of scrollbar "deadZone" of card 1 of stack kStack is 45 and drText("deadZoneLabel") begins with "Dead zone 0.45", \
         "the slider and its words follow", drText("deadZoneLabel")
   drCheck the width of graphic "dz_left" of card 1 of stack kStack > tRing + 8, "the dashed ring in each stick grows", \
         tRing && "->" && the width of graphic "dz_left" of card 1 of stack kStack
   drCheck format("%.2f", gpAxisEvents()) is "0.50" and the hilite of button "axisEvents" of card 1 of stack kStack, \
         "axis events are on for it (gpSetAxisEvents 0.5), and the box says so", gpAxisEvents()
   drWait 400
   drCheck drLog() contains ("axis," & sTouch & ",leftx,"), "a stick's move is a line of the log too", drTail(3)
   -- gpPadStick against the axes it reads, the wide zone taken out
   put gpPadAxes(sTouch) into tAxes
   put gpPadStick(sTouch, "left") into tStick
   -- no power inside a larger expression (engine note 1.9)
   put sqrt(item 1 of tAxes * item 1 of tAxes + item 2 of tAxes * item 2 of tAxes) into tMag
   if tMag <= gpDeadZone() then
      put 0 into tWant
   else
      put min(1, (tMag - gpDeadZone()) / (1 - gpDeadZone())) into tWant
   end if
   put sqrt(item 1 of tStick * item 1 of tStick + item 2 of tStick * item 2 of tStick) into tGot
   drCheck abs(tGot - tWant) < 0.02, "what gpPadStick reads is the stick with the zone taken out", tAxes && "->" && tStick
   -- what showcase 3 changes, as it is before
   put gpPadPlayer(sTouch) into sPlayerBefore
   put gpVirtualLED(sTouch) into sLedBefore
   drCheck drChipWait("Showcase 3 of 5", 9000), "showcase 2 ends, and the tour goes on to 3", drText("chip")
   drCheck abs(gpDeadZone() - 0.2) < 0.004 and the thumbPosition of scrollbar "deadZone" of card 1 of stack kStack is 20, \
         "the dead zone is put back as it was, 0.20", gpDeadZone()
   drCheck gpAxisEvents() is 0 and not the hilite of button "axisEvents" of card 1 of stack kStack, "and axis events are off again", gpAxisEvents()
   drNoFrameError "showcase 2"
end drShowcase2

command drShowcase3
   local tStart, tPlayers, tLights, tBars, tMax, tR, tI, tShook, tGrip, tLit, tShot
   put the milliseconds into tStart
   put "0,0,0,0" into tMax
   put false into tShook
   put false into tGrip
   repeat until drText("chip") begins with "Showcase 4 of 5" or the milliseconds - tStart > 12000
      put true into tPlayers[gpPadPlayer(sTouch)]
      put true into tLights[gpVirtualLED(sTouch)]
      put true into tBars[drBg("lightbar")]
      put gpVirtualRumble(sTouch) into tR
      repeat with tI = 1 to 4
         if item tI of tR > item tI of tMax then put item tI of tR into item tI of tMax
      end repeat
      if not drAtHome() then put true into tShook
      if drBg("grip_left") is not kBodyFill then put true into tGrip
      repeat with tI = 1 to 4
         if drBg("plr_" & tI) is kLiveColour then put true into tLit[tI]
      end repeat
      if tShot is empty and the milliseconds - tStart >= 7500 then
         drShot "3-rumble-light-players"
         drFits "showcase 3"
         put true into tShot
      end if
      wait 12 milliseconds with messages
   end repeat
   drCheck drText("chip") begins with "Showcase 4 of 5", "showcase 3 ends, and the tour goes on to 4", drText("chip")
   drCheck tPlayers[0] is true and tPlayers[1] is true and tPlayers[2] is true and tPlayers[3] is true and tPlayers[-1] is true, \
         "it numbered the pad player 1 to 4 and then none (gpPadSetPlayer)", the keys of tPlayers
   drCheck tLit[1] is true and tLit[2] is true and tLit[3] is true and tLit[4] is true, "the drawing's four lights showed each", the keys of tLit
   drCheck the number of lines of the keys of tLights >= 8, "the pad's light went round the colour wheel (gpPadSetLED)", \
         the number of lines of the keys of tLights && "colours"
   drCheck the number of lines of the keys of tBars >= 8, "and the drawing's light with it", the number of lines of the keys of tBars && "colours"
   drCheck item 1 of tMax > 0.95 and item 2 of tMax > 0.85, "both motors ran (gpPadRumble), as the touch pad reports them (gpVirtualRumble)", tMax
   drCheck item 3 of tMax > 0.95 and item 4 of tMax > 0.95, "and the motors in the triggers (gpPadRumbleTriggers)", tMax
   drCheck tShook and tGrip, "the drawing shook and its grips glowed while it rumbled", tShook && tGrip
   drCheck drAllZero(gpVirtualRumble(sTouch)), "every motor stopped after", gpVirtualRumble(sTouch)
   drCheck gpPadPlayer(sTouch) is sPlayerBefore and gpVirtualLED(sTouch) is sLedBefore, "its player number and light were put back", \
         gpPadPlayer(sTouch) && gpVirtualLED(sTouch) && "were" && sPlayerBefore && sLedBefore
   drNoFrameError "showcase 3"
end drShowcase3

command drShowcase4
   local tStart, tEast, tSwapped, tLog, tSpan, tSeq, tLine, tShot
   put the milliseconds into tStart
   put false into tEast
   put false into tSwapped
   repeat until drText("chip") begins with "Showcase 5 of 5" or the milliseconds - tStart > 13000
      if drBg("btn_east") is "232,92,82" then
         put true into tEast
         if tShot is empty then
            drShot "4-remap-a-button"
            drFits "showcase 4"
            put true into tShot
         end if
      end if
      if drMapping() contains ",a:b1," then put true into tSwapped
      wait 12 milliseconds with messages
   end repeat
   drCheck drText("chip") begins with "Showcase 5 of 5", "showcase 4 ends, and the tour goes on to 5", drText("chip")
   -- a letter a step: S south down, E east down, + the swapped line added,
   -- R the first line put back
   put drLog() into tLog
   put char offset("showcase 4:", tLog) to -1 of tLog into tSpan
   put empty into tSeq
   repeat for each line tLine in tSpan
      if tLine ends with ("button," & sTouch & ",south,down") then
         put "S" after tSeq
      else if tLine ends with ("button," & sTouch & ",east,down") then
         put "E" after tSeq
      else if tLine contains "mapping added for Touch pad" or tLine contains "mapping replaced for Touch pad" then
         put "+" after tSeq
      else if tLine contains "mapping restored for Touch pad" then
         put "R" after tSeq
      end if
   end repeat
   drCheck tSeq is "S+EEERSS", "south reads south; with the swapped mapping the same press reads east; put back, south again", tSeq
   drCheck tEast, "the drawing lit east for those presses", tEast
   drCheck tSwapped, "the mapping box showed the swapped line", tSwapped
   drCheck drMapping() contains ",a:b0,b:b1,", "and shows the first line again after", drMapping()
   drNoFrameError "showcase 4"
end drShowcase4

command drShowcase5
   local tStart, tLoc, tMinX, tMaxX, tMinY, tMaxY, tBig, tColours, tAim, tFlash, tBump, tTrig, tShot, tHome
   put the milliseconds into tStart
   put 99999 into tMinX
   put -99999 into tMaxX
   put 99999 into tMinY
   put -99999 into tMaxY
   repeat until drText("chip") begins with "Showcase 1 of 5" or the milliseconds - tStart > 15000
      put the loc of graphic "ball" of card 1 of stack kStack into tLoc
      put min(tMinX, item 1 of tLoc) into tMinX
      put max(tMaxX, item 1 of tLoc) into tMaxX
      put min(tMinY, item 2 of tLoc) into tMinY
      put max(tMaxY, item 2 of tLoc) into tMaxY
      if the width of graphic "ball" of card 1 of stack kStack > 24 then put true into tBig
      put true into tColours[drBg("ball")]
      if drShown("aim") then put true into tAim
      if drFg("arena") is "255,176,58" then put true into tFlash
      if item 1 of gpVirtualRumble(sTouch) >= 0.45 then put true into tBump
      if drShown("trig_right") then put true into tTrig
      if tShot is empty and the milliseconds - tStart >= 6300 then
         drShot "5-a-small-game"
         drFits "showcase 5"
         put true into tShot
      end if
      wait 12 milliseconds with messages
   end repeat
   put the loc of graphic "ball" of card 1 of stack kStack into tLoc
   put the loc of graphic "arena" of card 1 of stack kStack into tHome
   drCheck drText("chip") begins with "Showcase 1 of 5", "showcase 5 ends, and the tour plays again from 1", drText("chip")
   drCheck tMaxX - tMinX > 300 and tMaxY - tMinY > 80, "the left stick rolled the ball round the course", \
         tMinX & "-" & tMaxX & " x " & tMinY & "-" & tMaxY
   drCheck tBig is true, "south made it jump", tBig
   drCheck the number of lines of the keys of tColours >= 3, "east changed its colour", the keys of tColours
   drCheck tAim is true, "the right stick aimed", tAim
   drCheck tTrig is true, "the right trigger was pulled to hurry it", tTrig
   drCheck tFlash is true and tBump is true, "it hit a wall: the arena flashed and the pad was told to rumble", tFlash && tBump
   drCheck abs(item 1 of tLoc - item 1 of tHome) <= 2 and abs(item 2 of tLoc - item 2 of tHome) <= 2, "start brought it home", tLoc && tHome
   drNoFrameError "showcase 5"
end drShowcase5

command drHandsOn
   local tBall, tShook, tGrip, tI, tR, tLine, tSwapped, tUnder, tBiggest
   -- a key takes the touch pad from the tour
   drKey 122, true
   drWait 120
   drCheck drText("chip") begins with "Touch pad: drag it", "a key takes the touch pad: the tour stops", drText("chip")
   drCheck drLabel("playAll") is "Play all five" and drBg("show_1") is kQuietFill, "and no showcase is lit", drLabel("playAll")
   drCheck drText("about") begins with "The touch pad is yours", "the words beside it say how to drive it", line 1 of drText("about")
   drCheck drBg("btn_south") is "96,200,110" and drFg("btn_south") is kDarkWords, "Z holds south: lit green, its letter dark on it", drBg("btn_south") && drFg("btn_south")
   drCheck drTail(4) contains ("button," & sTouch & ",south,down"), "the press is logged", drTail(4)
   drCheck drText("readout") contains "Held: south", "the readout names what is held", line 2 of drText("readout")
   drFits "the touch pad taken"
   drKey 122, false
   drWait 120
   drCheck drBg("btn_south") is kIdleFill and drFg("btn_south") is not kDarkWords, "let go, it goes dark again", drBg("btn_south")
   -- the arrows: the left stick, and the ball rolls
   put the loc of graphic "ball" of card 1 of stack kStack into tBall
   drKey 65363, true
   drWait 300
   drCheck drText("readout") contains "gpPadStick:  1.00, 0.00", "the right arrow holds the left stick right", line 1 of drText("readout")
   drCheck item 1 of the loc of graphic "ball" of card 1 of stack kStack > item 1 of tBall + 20, "and the ball rolls right", \
         tBall && the loc of graphic "ball" of card 1 of stack kStack
   drKey 65363, false
   drWait 120
   drCheck drText("readout") contains "gpPadStick:  0.00, 0.00", "let go, the stick is back", line 1 of drText("readout")
   -- up and left held: the ball runs into the top left corner, where the
   -- caption across the arena's top is, and stops below it; and a jump
   -- there grows it downwards, never over the caption's words
   drKey 65362, true
   drKey 65361, true
   drWait 2500
   drCheck drBallUnder() and item 1 of the loc of graphic "ball" of card 1 of stack kStack < item 1 of the rect of graphic "arena" of card 1 of stack kStack + 20, \
         "held into the top left corner, the ball stops below the game's caption", drBallTop()
   drKey 122, true
   put true into tUnder
   put 0 into tBiggest
   repeat with tI = 1 to 40
      if not drBallUnder() then put false into tUnder
      put max(tBiggest, the width of graphic "ball" of card 1 of stack kStack) into tBiggest
      drWait 16
   end repeat
   drKey 122, false
   drCheck tUnder and tBiggest > 30, "and jumping there, it grows down from the caption, never over its words", tBiggest && drBallTop()
   drKey 65362, false
   drKey 65361, false
   drWait 120
   -- the mouse on the drawing
   drCall "glTouchDown", "btn_rightstick"
   drCall "glDragTo", 432, 253
   drWait 120
   drCheck drShown("aim"), "a right stick dragged aims", drText("readout")
   drCall "glTouchUp"
   drWait 120
   drCheck not drShown("aim"), "and lets go", drText("readout")
   drCall "glTouchDown", "trigwell_right"
   drCall "glDragTo", 511, 197
   drWait 120
   drCheck drShown("trig_right") and round(gpPadAxis(sTouch, "righttrigger") * 10) is 5, "a trigger dragged half way reads 0.5 and fills half its well", \
         gpPadAxis(sTouch, "righttrigger")
   drCall "glTouchUp"
   drWait 120
   drCheck not drShown("trig_right") and gpPadAxis(sTouch, "righttrigger") is 0, "and empties when let go", gpPadAxis(sTouch, "righttrigger")
   drCall "glTouchDown", "btn_dpup"
   drWait 120
   drCheck gpPadButton(sTouch, "dpup") and drBg("btn_dpup") is "255,176,58", "a button clicked is held, and lit", drBg("btn_dpup")
   drCall "glTouchUp"
   drWait 120
   drCheck not gpPadButton(sTouch, "dpup"), "and let go", gpPadButtons(sTouch)
   drCall "glTouchDown", "btn_leftstick"
   drCall "glTouchUp"
   drWait 150
   drCheck drTail(6) contains ("button," & sTouch & ",leftstick,down") and drTail(6) contains ("button," & sTouch & ",leftstick,up"), \
         "a tap on a stick clicks it in and out", drTail(6)
   -- rumble: the touch pad reports it, the drawing shakes and its grip glows
   drClick "rumble"
   put false into tShook
   put false into tGrip
   repeat with tI = 1 to 25
      if not drAtHome() then put true into tShook
      if drBg("grip_left") is "213,151,58" then put true into tGrip
      drWait 16
   end repeat
   drCheck drTail(3) contains "rumble 80% 30% for 600 ms", "Rumble asks for the two motors at the sliders' strengths", drTail(3)
   put gpVirtualRumble(sTouch) into tR
   drCheck round(item 1 of tR * 10) is 8 and round(item 2 of tR * 10) is 3, "the touch pad was told 0.8 and 0.3 (gpVirtualRumble)", tR
   drCheck tShook and tGrip, "the drawing shakes, the heavy motor's grip glowing 80%", tShook && tGrip
   drWait 650
   drCheck drAllZero(gpVirtualRumble(sTouch)) and drAtHome() and drBg("grip_left") is kBodyFill, "it stops by itself, and the drawing is still", gpVirtualRumble(sTouch)
   drClick "rumbleTriggers"
   drWait 100
   put gpVirtualRumble(sTouch) into tR
   drCheck item 3 of tR > 0.7 and item 4 of tR > 0.2 and drFg("trigwell_left") is not "70,78,92", \
         "Rumble triggers runs the motors in the triggers, and their wells glow", tR
   drWait 650
   -- the light and the player number
   drClick "led_4"
   drWait 60
   drCheck gpVirtualLED(sTouch) is "60,210,230" and drBg("lightbar") is "60,210,230", "a colour clicked sets the pad's light, and the drawing's", gpVirtualLED(sTouch)
   drClick "player_1"
   drCheck drText("padInfo") contains "Player: 2" and drBg("plr_2") is kLiveColour and gpPadPlayer(sTouch) is 1, \
         "player 2: the pad is numbered, the info says so and the second light is lit", gpPadPlayer(sTouch)
   drClick "player_-1"
   drCheck drText("padInfo") contains "Player: none" and drBg("plr_2") is kWellFill and gpPadPlayer(sTouch) is -1, "none: no light", gpPadPlayer(sTouch)
   -- the dead zone
   drSlide "deadZone", 50
   drCheck abs(gpDeadZone() - 0.5) < 0.004 and drText("deadZoneLabel") begins with "Dead zone 0.50", "the slider sets the dead zone", gpDeadZone()
   get gpVirtualSetAxis(sTouch, "leftx", 0.4)
   drWait 120
   drCheck drText("readout") contains "Sticks as read:  0.40, 0.00" and drText("readout") contains "gpPadStick:  0.00, 0.00", \
         "a tilt of 0.4 inside it reads 0", line 1 of drText("readout")
   get gpVirtualSetAxis(sTouch, "leftx", 0.8)
   drWait 120
   drCheck drText("readout") contains "gpPadStick:  0.60, 0.00", "past it the reading starts again from 0: 0.8 reads 0.6", line 1 of drText("readout")
   get gpVirtualSetAxis(sTouch, "leftx", 0)
   drSlide "deadZone", 20
   drWait 120
   -- axis events
   set the hilite of button "axisEvents" of card 1 of stack kStack to true
   drClick "axisEvents"
   drCheck format("%.2f", gpAxisEvents()) is "0.10" and drTail(2) contains "axis events on: a line each time an axis moves 0.10 of its travel", \
         "the box turns axis events on", drTail(2)
   get gpVirtualSetAxis(sTouch, "lefty", -1)
   drWait 150
   drCheck drTail(4) contains ("axis," & sTouch & ",lefty,-1"), "a stick's move is now a line of the log", drTail(4)
   get gpVirtualSetAxis(sTouch, "lefty", 0)
   drWait 150
   set the hilite of button "axisEvents" of card 1 of stack kStack to false
   drClick "axisEvents"
   drCheck gpAxisEvents() is 0 and drTail(2) contains "axis events off", "and off", drTail(2)
   -- a mapping changed by hand: south and east swap places
   put drMapping() into tLine
   put tLine into tSwapped
   replace ",a:b0," with ",a:@," in tSwapped
   replace ",b:b1," with ",b:b0," in tSwapped
   replace ",a:@," with ",a:b1," in tSwapped
   drCheck tSwapped contains ",a:b1," and tSwapped contains ",b:b0,", "the box holds the touch pad's mapping", tLine
   drCheck the lockText of field "mapping" of card 1 of stack kStack and not the traversalOn of field "mapping" of card 1 of stack kStack, \
         "the box is shut until clicked, so it never takes the keys from the touch pad", the traversalOn of field "mapping" of card 1 of stack kStack
   drClick "mapping"
   drCheck not the lockText of field "mapping" of card 1 of stack kStack and the traversalOn of field "mapping" of card 1 of stack kStack, \
         "a click opens it for editing", the lockText of field "mapping" of card 1 of stack kStack
   -- typed with no space after its commas, as a line copied from a file
   set the text of field "mapping" of card 1 of stack kStack to tSwapped
   dispatch "returnInField" to field "mapping" of card 1 of stack kStack
   drCheck the lockText of field "mapping" of card 1 of stack kStack, "Return shuts it again", the lockText of field "mapping" of card 1 of stack kStack
   drCheck drTail(3) contains "mapping added for Touch pad" or drTail(3) contains "mapping replaced for Touch pad", "and adds the line (gpAddMapping)", drTail(3)
   get gpVirtualSetButton(sTouch, "south", true)
   drWait 120
   drCheck gpPadButtons(sTouch) is "east" and drBg("btn_east") is "232,92,82", "the touch pad's south now reads east, and the drawing lights east", gpPadButtons(sTouch)
   get gpVirtualSetButton(sTouch, "south", false)
   drWait 120
   drClick "restoreMapping"
   drCheck drTail(3) contains "mapping restored for Touch pad" and drMapping() contains ",a:b0,b:b1,", "Restore puts back the line it first had", drTail(3)
   get gpVirtualSetButton(sTouch, "south", true)
   drWait 120
   drCheck gpPadButtons(sTouch) is "south", "south is south again", gpPadButtons(sTouch)
   get gpVirtualSetButton(sTouch, "south", false)
   drWait 120
   drNoFrameError "the hands-on part"
end drHandsOn

-- Watches pMs for a pad's greeting: its glow, the strongest light motor
-- it was told, and the footer in the frame the glow was first seen
command drWatchGreeting pPad, pMs, pShot, @rGlow, @rMax, @rFooter
   local tUntil, tR, tShot
   put false into rGlow
   put 0 into rMax
   put empty into rFooter
   put the milliseconds + pMs into tUntil
   repeat while the milliseconds < tUntil
      put gpVirtualRumble(pPad) into tR
      if item 2 of tR > rMax then put item 2 of tR into rMax
      if drFg("padBody") is kLiveColour then
         if rGlow is not true then put drText("footer") into rFooter
         put true into rGlow
         if pShot is not empty and tShot is empty then
            drShot pShot
            put true into tShot
         end if
      end if
      wait 8 milliseconds with messages
   end repeat
end drWatchGreeting

command drTakeOvers
   local tGlow, tMax, tSecond, tFooter
   -- a press on the controller that was there at the start
   get gpVirtualSetButton(sEarly, "south", true)
   drWatchGreeting sEarly, 300, empty, tGlow, tMax, tFooter
   drCheck drText("chip") is "Early pad: live", "a press on the waiting controller takes over", drText("chip")
   drCheck drText("padInfo") begins with "Name: Early pad", "everything reads it now", line 1 of drText("padInfo")
   drCheck drTail(8) contains "hello, Early pad" and drText("status") ends with "reading controllers", "it is greeted, and the status is the library's again", drText("status")
   drCheck tGlow and the lineSize of graphic "padBody" of card 1 of stack kStack is 3, "the drawing glows round its edge", drFg("padBody")
   drCheck gpVirtualLED(sEarly) is "80,220,100" and drBg("lightbar") is "80,220,100", "its light turns green", gpVirtualLED(sEarly)
   drCheck tMax > 0.5, "and it buzzes", tMax
   drCheck drBg("btn_south") is "96,200,110", "the south it holds is lit", drBg("btn_south")
   drFits "a controller taking over"
   get gpVirtualSetButton(sEarly, "south", false)
   drWait 1300
   drCheck drFg("padBody") is kBodyFill and the lineSize of graphic "padBody" of card 1 of stack kStack is 1, "the glow fades after a moment", drFg("padBody")
   -- back to the touch pad, from the list
   set the hilitedLine of field "padList" of card 1 of stack kStack to lineOffset("Touch pad", drText("padList"))
   drClick "padList"
   drWait 80
   drCheck drText("chip") begins with "Touch pad: drag it", "a click in the list shows the touch pad again", drText("chip")
   -- a controller plugged in mid-run
   put gpVirtualAttach("Second pad") into tSecond
   drCheck tSecond > 0, "a second controller is plugged in mid-run", gpLastError()
   drWatchGreeting tSecond, 400, "6-plugged-in", tGlow, tMax, tFooter
   drCheck drText("chip") is "Second pad: live" and drText("padInfo") begins with "Name: Second pad", "it takes over at once, with no press", drText("chip")
   drCheck tGlow and gpVirtualLED(tSecond) is "80,220,100" and tMax > 0.5, "and lights up: the glow, a green light and a buzz", \
         tGlow && gpVirtualLED(tSecond) && tMax
   drCheck drText("padList") contains "Second pad (made in software)" and drTail(8) contains ("connected," & tSecond) and drTail(8) contains "hello, Second pad", \
         "it is listed, and its arrival logged", drTail(8)
   drCheck tFooter begins with "Controllers: 3" and gpPadCount() is 3, "and the footer counts it in the frame it arrives", tFooter
   drFits "a second controller"
   -- unplugged, it hands back to the controller still there
   gpVirtualDetach tSecond
   drWait 150
   drCheck drTail(6) contains ("disconnected," & tSecond) and drText("chip") is "Early pad: live", "unplugged, it hands back to the controller still there", drText("chip")
   gpVirtualDetach sEarly
   put 0 into sEarly
   drWait 150
   drCheck drText("chip") begins with "Touch pad: drag it" and drText("padList") is "Touch pad (made in software)", \
         "and with no controller left, to the touch pad", drText("chip")
   drNoFrameError "the take-overs"
end drTakeOvers

-- The log and the mapping scroll with no scroll bar of the engine's (it is
-- light on a dark system whatever a box's colours): the wheel, a thin bar
-- of the window's own, and a log that keeps a reader's place
command drScrolling
   local tLog, tMap, tEnd, tMark, tAt, tY, tWas
   put the long id of field "events" of card 1 of stack kStack into tLog
   put the formattedHeight of tLog - the height of tLog into tEnd
   put the rect of graphic "eventsMark" of card 1 of stack kStack into tMark
   drCheck tEnd > 0 and the vScroll of tLog >= tEnd - 1, "the log is longer than its box and shows its newest line", the vScroll of tLog && tEnd
   drCheck drShown("eventsMark") and abs(item 4 of tMark - (item 4 of the rect of tLog - 4)) <= 1 and item 3 of tMark < item 3 of the rect of tLog, \
         "a thin bar of its own, inside the box, says so from the bottom", tMark && the rect of tLog
   dispatch "rawKeyDown" to tLog with 65309
   drCheck the vScroll of tLog < tEnd - 1 and item 2 of the rect of graphic "eventsMark" of card 1 of stack kStack < item 2 of tMark, \
         "the wheel turned away scrolls it back, the bar with it", the vScroll of tLog && tEnd
   put the vScroll of tLog into tAt
   get gpVirtualSetButton(sTouch, "north", true)
   drWait 120
   get gpVirtualSetButton(sTouch, "north", false)
   drWait 150
   drCheck drTail(2) contains ("button," & sTouch & ",north,up") and the vScroll of tLog is tAt, \
         "a reader scrolled back keeps their place while lines arrive", the vScroll of tLog && tAt
   repeat 60 times
      dispatch "rawKeyDown" to tLog with 65308
   end repeat
   put the formattedHeight of tLog - the height of tLog into tEnd
   drCheck the vScroll of tLog is tEnd, "turned towards them it scrolls to the end, and no further", the vScroll of tLog && tEnd
   get gpVirtualSetButton(sTouch, "north", true)
   drWait 120
   get gpVirtualSetButton(sTouch, "north", false)
   drWait 150
   put the formattedHeight of tLog - the height of tLog into tEnd
   drCheck the vScroll of tLog >= tEnd - 1, "at the end it follows the newest line again", the vScroll of tLog && tEnd
   -- the bar taken hold of and dragged up, as the window's mouse handlers
   -- call it with the point they read
   put item 2 of the loc of graphic "eventsMark" of card 1 of stack kStack into tY
   put the vScroll of tLog into tWas
   drCall "glMarkDown", "eventsMark", tY
   drCall "glMarkDrag", tY - 30
   drCheck the vScroll of tLog < tWas and item 2 of the loc of graphic "eventsMark" of card 1 of stack kStack < tY - 20, \
         "the bar dragged up scrolls the log back with it", the vScroll of tLog && tWas
   drCall "glMarkDrag", tY + 400
   drCheck the vScroll of tLog is tWas, "and dragged past the end, to the end", the vScroll of tLog && tWas
   drCall "glMarkUp"
   -- the mapping
   put the long id of field "mapping" of card 1 of stack kStack into tMap
   drCheck drText("mapping") contains ", a:b0, b:b1, " and the formattedWidth of tMap <= the width of tMap + 3, \
         "the mapping wraps inside its box (drFits' slack): a space after each comma, as the engine breaks a line only at a space", the formattedWidth of tMap && the width of tMap
   drCheck the formattedHeight of tMap > the height of tMap and drShown("mappingMark") and the vScroll of tMap is 0, \
         "the touch pad's mapping is longer than its box: it shows its start, and its bar", the formattedHeight of tMap && the height of tMap
   dispatch "rawKeyDown" to tMap with 65308
   drCheck the vScroll of tMap > 0, "the wheel scrolls the mapping too", the vScroll of tMap
   dispatch "rawKeyDown" to graphic "mappingMark" of card 1 of stack kStack with 65309
   drCheck the vScroll of tMap is 0, "and over its bar, back to the start", the vScroll of tMap
   dispatch "rawKeyDown" to card 1 of stack kStack with 65308
   drCheck the vScroll of tMap is 0 and the vScroll of tLog >= tEnd - 1, "the wheel anywhere else scrolls neither", the vScroll of tMap && the vScroll of tLog
   drClick "clearLog"
   drCheck drLog() is empty and not drShown("eventsMark"), "Clear empties the log, and its bar goes", drLog()
end drScrolling

command drShowcaseButtons
   drClick "show_3"
   drWait 100
   drCheck drText("chip") begins with "Showcase 3: Rumble, light and players", "a showcase's button plays that one alone", drText("chip")
   drCheck drBg("show_3") is kAccentColour and drLabel("playAll") is "Play all five", "its button is lit", drBg("show_3")
   drCheck drChipWait("Touch pad: drag it", 12000), "it ends by itself, and the touch pad is the person's again", drText("chip")
   drCheck drBg("show_3") is kQuietFill, "and its button goes quiet", drBg("show_3")
   drClick "playAll"
   drWait 100
   drCheck drText("chip") begins with "Showcase 1 of 5" and drLabel("playAll") is "Stop the tour", "Play all five starts the tour again", drText("chip")
   drClick "playAll"
   drWait 100
   drCheck drText("chip") begins with "Touch pad: drag it" and drLabel("playAll") is "Play all five", "and Stop the tour stops it", drText("chip")
   drNoFrameError "the showcase buttons"
end drShowcaseButtons

command drStopStart
   drClick "startStop"
   drWait 100
   drCheck drLabel("startStop") is "Start" and drText("chip") is "Stopped" and drText("status") is "Stopped", "Stop stops it", drText("chip")
   drCheck drTail(3) contains "stopped here; another stack still reads controllers" and gpIsStarted(), \
         "another stack's start keeps the library going", drTail(3)
   drCheck drPadNamed("Touch pad") is 0, "its touch pad goes with it", gpPads()
   drCheck not drFramePending(), "no timer runs while it is stopped", the pendingMessages
   drFits "stopped"
   drClick "startStop"
   drWait 200
   put drPadNamed("Touch pad") into sTouch
   drCheck drLabel("startStop") is "Stop" and drText("chip") begins with "Showcase 1 of 5" and sTouch > 0, "Start plays the tour again, on a new touch pad", drText("chip")
   drCheck drPadsNamed("Touch pad") is 1, "and only one", gpPads()
end drStopStart

----------------------------------------------------------------
-- The window: inside its size, its own colours, words that read

-- The colour behind a point: the panel it is on, or the window
function drUnder pLoc
   local tPanel
   repeat for each item tPanel in "rightPanel,midPanel,stagePanel"
      if pLoc is within the rect of graphic tPanel of card 1 of stack kStack then
         return the backgroundColor of graphic tPanel of card 1 of stack kStack
      end if
   end repeat
   return the backgroundColor of stack kStack
end drUnder

-- WCAG's relative luminance of "r,g,b"
function drLuminance pRGB
   local tSum, tI, tC
   put 0 into tSum
   repeat with tI = 1 to 3
      put item tI of pRGB / 255 into tC
      if tC <= 0.03928 then
         put tC / 12.92 into tC
      else
         -- the power in a statement of its own (engine note 1.9)
         put (tC + 0.055) / 1.055 into tC
         put tC ^ 2.4 into tC
      end if
      add tC * item tI of "0.2126,0.7152,0.0722" to tSum
   end repeat
   return tSum
end drLuminance

function drContrast pA, pB
   local tA, tB
   put drLuminance(pA) into tA
   put drLuminance(pB) into tB
   return (max(tA, tB) + 0.05) / (min(tA, tB) + 0.05)
end drContrast

command drWindowLook
   local tI, tC, tType, tName, tRect, tOutside, tBare, tWorst, tWorstAt, tFg, tBg, tRatio, tCount, tWas, tBars
   put empty into tOutside
   put empty into tBare
   put empty into tBars
   put 99 into tWorst
   put 0 into tCount
   repeat with tI = 1 to the number of controls of card 1 of stack kStack
      put the long id of control tI of card 1 of stack kStack into tC
      put word 1 of tC into tType
      put the short name of tC into tName
      put the rect of tC into tRect
      if item 1 of tRect < 0 or item 2 of tRect < 0 or item 3 of tRect > 1180 or item 4 of tRect > 640 then put tName & " " after tOutside
      put empty into tFg
      put empty into tBg
      switch tType
         case "field"
            if the foregroundColor of tC is empty or the backgroundColor of tC is empty then put tName & " " after tBare
            if the vScrollbar of tC or the hScrollbar of tC then put tName & " " after tBars
            if the listBehavior of tC and the hiliteColor of tC is empty then put tName & "(hilite) " after tBare
            if the text of tC is not empty then
               put the foregroundColor of tC into tFg
               if the opaque of tC then
                  put the backgroundColor of tC into tBg
               else
                  put drUnder(the loc of tC) into tBg
               end if
            end if
            break
         case "button"
            if the foregroundColor of tC is empty or the backgroundColor of tC is empty then put tName & " " after tBare
            if the label of tC is not empty then
               put the foregroundColor of tC into tFg
               if the opaque of tC then
                  put the backgroundColor of tC into tBg
               else
                  put drUnder(the loc of tC) into tBg
               end if
            end if
            break
         case "scrollbar"
            if the foregroundColor of tC is empty or the backgroundColor of tC is empty then put tName & " " after tBare
            break
         case "graphic"
            if the showName of tC and the label of tC is not empty and the opaque of tC then
               put the foregroundColor of tC into tFg
               put the backgroundColor of tC into tBg
            end if
            break
      end switch
      if tFg is not empty and tBg is not empty then
         add 1 to tCount
         put drContrast(tFg, tBg) into tRatio
         if tRatio < tWorst then
            put tRatio into tWorst
            put tName && tFg && "on" && tBg into tWorstAt
         end if
      end if
   end repeat
   drCheck tOutside is empty, "every control is inside the window", tOutside
   drCheck tBare is empty, "every field, button and slider sets its own colours (a list its hilite too), so a dark system theme changes none", tBare
   drCheck tCount > 40 and tWorst >= 4.5, "every word on it reads at 4.5 to 1 or better against what is behind it (" & tCount && "checked)", \
         format("%.2f", tWorst) && tWorstAt
   drCheck tBars is empty, "no box draws the engine's own scroll bar, which is light on a dark system whatever the box's colours", tBars
   drFits "the end"
   drCheck sUnfit is empty and sFitLooks >= 6, "every box that does not scroll showed all its words, each of the" && sFitLooks && "times the drive looked", sUnfit
   drCheck sCovered is empty, "and the game's ball never covered its caption", sCovered
   put the number of controls of card 1 of stack kStack into tWas
   send "preOpenStack" to stack kStack
   drCheck the number of controls of card 1 of stack kStack is tWas, "opening it again builds nothing twice", tWas && the number of controls of card 1 of stack kStack
end drWindowLook

command drClosing
   -- left changed, as a person might leave them
   drSlide "deadZone", 35
   set the hilite of button "axisEvents" of card 1 of stack kStack to true
   drClick "axisEvents"
   drCheck abs(gpDeadZone() - 0.35) < 0.004 and format("%.2f", gpAxisEvents()) is "0.10", "(the dead zone and axis events changed before it closes)", gpDeadZone() && gpAxisEvents()
   drNoFrameError "the end"
   close stack kStack
   drCheck drPadNamed("Touch pad") is 0, "closing the window takes its touch pad away", gpPads()
   drCheck abs(gpDeadZone() - 0.2) < 0.004 and gpAxisEvents() is 0, "and puts back the dead zone and axis events it found", gpDeadZone() && gpAxisEvents()
   drCheck gpIsStarted(), "another stack's start still holds the library", gpIsStarted()
   drCheck gpAssertCount() is 0, "SDL asserted nothing", gpAssertCount()
   drCheck gpDroppedEvents() is 0, "no event was pushed out of the queue", gpDroppedEvents()
   gpStop
   drCheck not gpIsStarted(), "the drive's own stop is the last", gpIsStarted()
end drClosing

----------------------------------------------------------------
-- With no gamepadxt: the recording

command drRecordingRun
   local tSeen, tRing, tUntil, tLit, tBars, tShook, tGrip, tI, tEast, tMinX, tMaxX, tBig, tColours, tAim, tLoc, tStart
   if "org.openxtalk.library.gamepadxt" is among the lines of the loadedExtensions then
      unload extension "org.openxtalk.library.gamepadxt"
   end if
   drCheck "org.openxtalk.library.gamepadxt" is not among the lines of the loadedExtensions, "this engine has no gamepadxt: the window must play a recording", the loadedExtensions
   drOpen
   drCheck drText("status") is "gamepadxt is not installed: a recording plays", "the status says so, in words", drText("status")
   drFirstSecond tSeen
   drShot "7-a-recording"
   drFits "a recording"
   drCheck drText("chip") begins with "Showcase 1 of 5: Every button" and drText("chip") ends with "(a recording)", "it opens playing showcase 1 of 5, as a recording", drText("chip")
   drCheck tSeen["south"] is "96,200,110" and tSeen["east"] is "232,92,82" and tSeen["west"] is "82,152,244", \
         "within the first second the drawing lights south, east and west", tSeen["south"] & "/" & tSeen["east"] & "/" & tSeen["west"]
   drCheck drText("padList") is "Touch pad (a recording)" and drText("padInfo") begins with "Name: Touch pad, a recording", "the list and the info say what plays", drText("padList")
   drCheck drText("footer") begins with "No gamepadxt here", "and the footer", drText("footer")
   drCheck drText("mapping") begins with "SDL's mappings are in gamepadxt" and not drShown("mappingMark"), "and the mapping box, short enough to need no bar", drText("mapping")
   drCheck the label of graphic "btn_south" of card 1 of stack kStack is "A" and the showName of graphic "btn_south" of card 1 of stack kStack, "the face buttons are lettered", the label of graphic "btn_south" of card 1 of stack kStack
   drCheck drLabel("touchPad") is "Touch pad: a recording", "the touch pad's button says what it is", drLabel("touchPad")
   drCheck drFrames(1000) >= 30, "a timer draws it, at least 30 frames a second", empty
   -- each showcase from its button
   put the width of graphic "dz_left" of card 1 of stack kStack into tRing
   drClick "show_2"
   drWait 50
   drCheck drText("chip") begins with "Showcase 2: Sticks and the dead zone", "a showcase's button plays it", drText("chip")
   put the milliseconds + 6000 into tUntil
   repeat until drText("deadZoneLabel") begins with "Dead zone 0.45" or the milliseconds > tUntil
      wait 10 milliseconds with messages
   end repeat
   drCheck drText("deadZoneLabel") begins with "Dead zone 0.45" and the width of graphic "dz_left" of card 1 of stack kStack > tRing + 8, \
         "the recording's dead zone widens to 0.45, the ring with it", drText("deadZoneLabel")
   drCheck drText("readout") contains "gpPadStick:", "the readout shows the sticks as the recording reads them", line 1 of drText("readout")
   drFits "the recording's showcase 2"
   drClick "show_3"
   put the milliseconds into tStart
   put false into tShook
   put false into tGrip
   repeat while the milliseconds - tStart < 8000
      repeat with tI = 1 to 4
         if drBg("plr_" & tI) is kLiveColour then put true into tLit[tI]
      end repeat
      put true into tBars[drBg("lightbar")]
      if not drAtHome() then put true into tShook
      if drBg("grip_left") is not kBodyFill then put true into tGrip
      wait 12 milliseconds with messages
   end repeat
   drFits "the recording's showcase 3"
   drCheck tLit[1] is true and tLit[2] is true and tLit[3] is true and tLit[4] is true, "showcase 3: the four player lights in turn", the keys of tLit
   drCheck the number of lines of the keys of tBars >= 8, "the light round the colour wheel", the number of lines of the keys of tBars
   drCheck tShook and tGrip, "the drawing shakes and its grips glow", tShook && tGrip
   drClick "show_4"
   put the milliseconds into tStart
   put false into tEast
   repeat while the milliseconds - tStart < 7500
      if drBg("btn_east") is "232,92,82" then put true into tEast
      wait 12 milliseconds with messages
   end repeat
   drCheck tEast and drLog() contains "the recording's south and east swap places" and drLog() contains "the recording's buttons are back", \
         "showcase 4: with the swap, south's press lights east, and the buttons come back", tEast
   drFits "the recording's showcase 4"
   drClick "show_5"
   put the milliseconds into tStart
   put 99999 into tMinX
   put -99999 into tMaxX
   put false into tBig
   put false into tAim
   repeat while the milliseconds - tStart < 9000
      put the loc of graphic "ball" of card 1 of stack kStack into tLoc
      put min(tMinX, item 1 of tLoc) into tMinX
      put max(tMaxX, item 1 of tLoc) into tMaxX
      if the width of graphic "ball" of card 1 of stack kStack > 24 then put true into tBig
      put true into tColours[drBg("ball")]
      if drShown("aim") then put true into tAim
      wait 12 milliseconds with messages
   end repeat
   drCheck tMaxX - tMinX > 250 and tBig and tAim and the number of lines of the keys of tColours >= 2, "showcase 5: the ball rolls, jumps, aims and changes colour", \
         tMinX & "-" & tMaxX && tBig && tAim && the number of lines of the keys of tColours
   drNoFrameError "the recording's showcases"
   drFits "the recording's showcase 5"
   -- by hand
   drKey 122, true
   drWait 120
   drCheck drText("chip") is "A recording: gamepadxt is not installed" and drBg("btn_south") is "96,200,110" and drText("readout") contains "Held: south", \
         "a key takes the recording's touch pad: Z holds south", drText("chip")
   drFits "the recording, taken"
   drKey 122, false
   drWait 120
   -- the recording's game is the same game: held into the top left corner,
   -- its ball stops below the caption too
   drKey 65362, true
   drKey 65361, true
   drWait 2500
   drCheck drBallUnder() and item 1 of the loc of graphic "ball" of card 1 of stack kStack < item 1 of the rect of graphic "arena" of card 1 of stack kStack + 20, \
         "the arrows roll the recording's ball into the top left corner, below the game's caption", drBallTop()
   drKey 65362, false
   drKey 65361, false
   drWait 120
   drClick "rumble"
   put false into tShook
   put false into tGrip
   repeat with tI = 1 to 25
      if not drAtHome() then put true into tShook
      if drBg("grip_left") is not kBodyFill then put true into tGrip
      drWait 16
   end repeat
   drCheck drTail(3) contains "rumble 80% 30% for 600 ms" and tShook and tGrip, "Rumble shakes the drawing", drTail(3)
   drClick "led_4"
   drWait 60
   drCheck drBg("lightbar") is "60,210,230", "a colour clicked lights the drawing", drBg("lightbar")
   drClick "player_1"
   drCheck drBg("plr_2") is kLiveColour, "a player number lights its light", drBg("plr_2")
   drSlide "deadZone", 50
   drCheck drText("deadZoneLabel") begins with "Dead zone 0.50", "the dead zone slider", drText("deadZoneLabel")
   set the hilite of button "axisEvents" of card 1 of stack kStack to true
   drClick "axisEvents"
   drCheck drTail(2) contains "axis events need gamepadxt" and not the hilite of button "axisEvents" of card 1 of stack kStack, "what needs the library says so", drTail(2)
   drClick "applyMapping"
   drCheck drTail(2) contains "mappings need gamepadxt", "and the mapping", drTail(2)
   drClick "touchPad"
   drCheck drTail(2) contains "the touch pad is gamepadxt's: this one is a recording", "and the touch pad", drTail(2)
   drClick "startStop"
   drWait 100
   drCheck drText("chip") is "Stopped" and drLabel("startStop") is "Start" and not drFramePending(), "Stop stops the recording", drText("chip")
   drFits "the recording stopped"
   drClick "startStop"
   drWait 150
   drCheck drText("chip") begins with "Showcase 1 of 5" and drText("chip") ends with "(a recording)", "Start plays it again", drText("chip")
   drWindowLook
   drNoFrameError "the end"
   close stack kStack
   drCheck not drFramePending(), "closed, nothing runs", the pendingMessages
end drRecordingRun
