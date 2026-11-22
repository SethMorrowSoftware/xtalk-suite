script "audioxtDemoDrive"
-- demo-drive.livecodescript - examples/audioxt-demo.livecodescript (Sound
-- Stage) driven on a real engine with no person at it, and no sound card.
--
--    AUDIOXT_LCM=<audioxt.lcm> AUDIOXT_LIB=<library, no extension> \
--    AUDIOXT_DEMO=examples/audioxt-demo.livecodescript \
--       <OXT-Beyond>/LiveCode-Community -ui tests/demo-drive.livecodescript
--
-- With AUDIOXT_LCM empty it drives the window WITHOUT the extension, as a
-- person who has not installed it would see it: the window must build,
-- say plainly what is missing and survive every click.
--
-- It puts the demo's script on a new stack (as the demo's header tells a
-- person to), with every variable required to be declared (an undeclared
-- one would otherwise read as its own name), opens it and then watches, as
-- a person would: the window opens straight into the show and plays every
-- scene in turn (the beat, the sound round your head, the synth, the tape),
-- and the drive checks each one at its moments. Then it does what a person
-- would, by clicking: picks the silent microphone from the sound devices
-- panel and plays the microphone scene, then plays it again with a
-- microphone that sends nothing (a page that may not use one, as the
-- community gallery's, gets none), pauses and resumes, drags the
-- volume, moves the sound to the silent device, runs every check and
-- copies the results, and closes the stack. A CI machine has no sound card:
-- the window itself falls back to the silent device, and says so.
--
-- The native lane runs it (the suite's .github/workflows/native-audioxt.yml,
-- job `engine`) and wants BOTH an exit of 0 and a last line
-- "DRIVE <passed> 0": an engine that printed nothing must not read as a
-- pass.
--
-- AUDIOXT_SHOTS (optional) names a folder for PNG pictures of the window at
-- its moments. They need a display (xvfb-run, or Xvfb and DISPLAY) and the
-- windowed engine, not -ui: there, run the engine with this file copied to
-- Toolset/home.rev in its working folder (the windowed engine's startup
-- stack). Without a display the pictures are skipped, never failed.
--
-- WHAT THIS IS EVIDENCE OF: the demo's logic and its window on OXT-Beyond's
-- Linux engine through miniaudio's silent device. It is not a person using
-- the window, and not a sound anyone heard.

constant kStack = "audioxtDemoRun"

local sPassed, sFailed, sOut

command drCheck pOk, pLabel, pDetail
   if pOk is true then
      add 1 to sPassed
      put "PASS  " & pLabel & return after sOut
   else
      add 1 to sFailed
      put "FAIL  " & pLabel & "  [" & pDetail & "]" & return after sOut
   end if
end drCheck

-- A click on a control of the demo, as the engine delivers one: the
-- message goes to the control and up to the stack script's mouseUp.
command drClick pName
   dispatch "mouseUp" to button pName of card 1 of stack kStack with 1
end drClick

-- What the demo holds (its adProbe), by name.
function drHandle pWhat
   dispatch function "adProbe" to stack kStack with pWhat
   return the result
end drHandle

function drField pName
   return field pName of card 1 of stack kStack
end drField

-- Lets the demo's timer run: its frames come while this waits.
command drWait pMs
   wait pMs milliseconds with messages
end drWait

-- Waits (letting the frames come) until the demo's pWhat is pValue, or
-- pMs have passed; answers whether it came.
function drWaitFor pWhat, pValue, pMs
   local tUntil
   put the milliseconds + pMs into tUntil
   repeat while the milliseconds < tUntil
      if drHandle(pWhat) is pValue then
         return true
      end if
      wait 40 milliseconds with messages
   end repeat
   return drHandle(pWhat) is pValue
end drWaitFor

-- Waits until the scene's own clock reads pSeconds (at most pMs).
command drAtTime pSeconds, pMs
   local tUntil
   put the milliseconds + pMs into tUntil
   repeat while the milliseconds < tUntil and drHandle("scenetime") < pSeconds
      wait 40 milliseconds with messages
   end repeat
end drAtTime

-- Is a control on show: visible, and every group it is in visible?
function drShowing pObject
   local tOwner
   if not the visible of pObject then
      return false
   end if
   put the long id of the owner of pObject into tOwner
   repeat while word 1 of the name of tOwner is "group"
      if not the visible of tOwner then
         return false
      end if
      put the long id of the owner of tOwner into tOwner
   end repeat
   return true
end drShowing

-- No words cut off: every field and button on show fits its words, in
-- this system's font (a line, its width; words that wrap, their height).
-- Linux's font is wider than Windows', so a fit here is a fit there.
command drFits pWhere
   local tI, tObject, tBad
   repeat with tI = 1 to the number of controls of card 1 of stack kStack
      put the long id of control tI of card 1 of stack kStack into tObject
      if word 1 of the name of tObject is not among the items of "field,button" or not drShowing(tObject) then
         next repeat
      end if
      if word 1 of the name of tObject is "field" and not the dontWrap of tObject then
         if the formattedHeight of tObject > the height of tObject then
            put the short name of tObject & " " after tBad
         end if
      else if the formattedWidth of tObject > the width of tObject then
         put the short name of tObject & " " after tBad
      end if
   end repeat
   drCheck tBad is empty, "no words are cut off (" & pWhere & ")", tBad
end drFits

-- A picture of the window, when there is a display to take it from; and,
-- at every such moment, that no words are cut off.
command drShot pName
   local tError
   drFits pName
   if $AUDIOXT_SHOTS is empty then
      exit drShot
   end if
   try
      export snapshot from card 1 of stack kStack to file ($AUDIOXT_SHOTS & "/" & pName & ".png") as PNG
   catch tError
      put "INFO  no picture " & pName & ": " & line 1 of tError & return after sOut
   end try
end drShot

-- Is the oscilloscope's line anything but flat?
function drScopeMoves
   local tPoint
   repeat for each line tPoint in the points of graphic "Scope" of card 1 of stack kStack
      if item 2 of tPoint is not 468 then
         return true
      end if
   end repeat
   return false
end drScopeMoves

-- Every sound in a list is a sound the library knows.
function drAllValid pList, pCount
   local tSound
   if the number of items of pList is not pCount then
      return false
   end if
   repeat for each item tSound in pList
      if not auSoundIsValid(tSound) then
         return false
      end if
   end repeat
   return true
end drAllValid

-- Opens the sound devices panel and clicks the row that picks pPick.
command drPick pPick
   local tButton
   drClick "Device"
   dispatch function "adDeviceButton" to stack kStack with pPick
   put the result into tButton
   drCheck tButton is not empty, "the devices panel has a row for " & pPick, drHandle("menu")
   if tButton is not empty then
      drClick tButton
   end if
end drPick

-- An IDE's ear, in front of every object while the window is built.
-- OXT-Beyond's IDE answers each control a script makes, names or deletes
-- (engine note 5.15): its frontscript hears newField, newButton,
-- newGraphic or newGroup (and newBackground), and nameChanged, and queues
-- a message to its project browser for each, and its backscript stamps
-- the control. Built with messages on, the window took 59 s to open in
-- that IDE on Windows (2026-11-21), where the engine alone builds it in
-- about 30 ms. The demo builds it with messages locked, so the ear hears
-- nothing; it counts every such message the engine has (the script before
-- that fix made 520: 268 new-control messages and 252 nameChanged).
command drEar pOn
   local tScript, tName
   if pOn then
      put "local sHeard" & return into tScript
      repeat for each item tName in "newField,newButton,newGraphic,newGroup,newBackground,newImage,newPlayer,newScrollbar,newWidget," \
            & "nameChanged,deleteField,deleteButton,deleteGraphic,deleteGroup,deleteBackground"
         put "on" && tName & return & "add 1 to sHeard" & return & "pass" && tName & return \
               & "end" && tName & return after tScript
      end repeat
      put "function earHeard" & return & "return sHeard + 0" & return & "end earHeard" & return after tScript
      create invisible stack "audioxtDemoEar"
      set the script of stack "audioxtDemoEar" to tScript
      insert the script of stack "audioxtDemoEar" into front
   else
      remove the script of stack "audioxtDemoEar" from front
      delete stack "audioxtDemoEar"
   end if
end drEar

-- How many messages of a control made, named or deleted the ear has heard.
function drEarHeard
   dispatch function "earHeard" to stack "audioxtDemoEar"
   return the result
end drEarHeard

-- Is all of a window of pRect, and a title bar above it, inside one of
-- pScreens? Worked out here, not asked of the demo, so a demo that never
-- places its window fails it.
function drOnScreen pRect, pScreens
   local tScreen
   repeat for each line tScreen in pScreens
      if item 1 of pRect >= item 1 of tScreen and item 2 of pRect - 32 >= item 2 of tScreen \
            and item 3 of pRect <= item 3 of tScreen and item 4 of pRect <= item 4 of tScreen then
         return true
      end if
   end repeat
   return false
end drOnScreen

-- Where the demo would move a window of pWindow on screens pScreens (its
-- adPlacedLoc): empty to leave it, or the loc it moves it to.
function drPlaced pWindow, pScreens
   dispatch function "adPlacedLoc" to stack kStack with pWindow, pScreens
   return the result
end drPlaced

-- The demo's script on a new stack, compiled with every variable declared,
-- and the window opened.
command drOpen
   local tScript, tResult, tHeard
   put textDecode(URL ("binfile:" & $AUDIOXT_DEMO), "UTF-8") into tScript
   drCheck the number of lines of tScript > 1000, "the demo's script is read", $AUDIOXT_DEMO
   create stack kStack
   -- A script that does not compile is set all the same and answers no
   -- message, so the proof is a call that is handled.
   set the explicitVariables to true
   set the script of stack kStack to tScript
   set the explicitVariables to false
   dispatch function "adProbe" to stack kStack with "scene"
   put it into tResult
   drCheck tResult is "handled", "it compiles with every variable declared", tResult
   -- the ear goes in before `go`, which builds the window in a windowed
   -- engine
   drEar true
   go stack kStack
   set the defaultStack to kStack
   -- a windowed engine sends it on `go`; -ui does not, so it is sent here
   -- (the window is built once: a second one builds nothing)
   send "preOpenStack" to stack kStack
   put drEarHeard() into tHeard
   drEar false
   set the defaultStack to kStack
   drCheck the number of controls of card 1 of stack kStack > 200 and tHeard is 0, \
         "its window is built with messages locked: an IDE hears of none of its controls", \
         tHeard && "messages for" && the number of controls of card 1 of stack kStack && "controls"
end drOpen

-- The look, for a system in dark mode: every field and button has its own
-- text and background colours (with none, such a system gives it white
-- text), and nothing is a system tick box, menu or slider, which would draw
-- in the system's own colours.
command drLook
   local tI, tName, tBad, tSystem, tCount
   put 0 into tCount
   repeat with tI = 1 to the number of controls of card 1 of stack kStack
      put the name of control tI of card 1 of stack kStack into tName
      if word 1 of tName is "scrollbar" or word 1 of tName is "player" then
         put tName & " " after tSystem
      end if
      if word 1 of tName is "button" then
         if the style of control tI of card 1 of stack kStack is among the items of "checkbox,radioButton,menu" then
            put tName & " " after tSystem
         end if
      end if
      if word 1 of tName is among the items of "field,button" then
         add 1 to tCount
         if the foregroundColor of control tI of card 1 of stack kStack is empty \
               or the backgroundColor of control tI of card 1 of stack kStack is empty then
            put tName & " " after tBad
         end if
      end if
   end repeat
   drCheck tCount > 80 and tBad is empty, "all " & tCount & " fields and buttons have their own text and background colours", tBad
   drCheck tSystem is empty, "and none is a system tick box, menu or slider", tSystem
end drLook

-- The window, its header and its size, and that reopening rebuilds nothing.
command drWindow
   local tWas
   drCheck the width of stack kStack is 960 and the height of stack kStack is 600, "the window is 960 x 600 (it fits 1200 x 640)", \
         the rect of stack kStack
   drCheck the title of stack kStack is "Sound Stage - audioxt", "its title", the title of stack kStack
   drCheck drField("Brand") is "OXT-BEYOND" and drField("Heading") is "Sound Stage" and drField("Credit") is "by Seth Morrow" \
         and drField("Sub") is not empty, "the header: the family, the stage's name, what it does, and whose", drField("Credit")
   drCheck the backgroundColor of stack kStack is "#12151F", "a dark stage", the backgroundColor of stack kStack
   drLook
   -- Where it opens: on this engine's screen, when it has one (-ui has
   -- none); and on screens it has not got, a window above and left of
   -- every screen, as the stack file opened on Windows (2026-11-21), is
   -- centred on the first; one on any screen, title bar and all, stays; a
   -- screen too short for it keeps its title bar on the screen; an engine
   -- with no display moves nothing.
   if item 3 of line 1 of the working screenRects > 0 then
      drCheck drOnScreen(the rect of stack kStack, the working screenRects), "it opens on the screen, its title bar too", \
            the rect of stack kStack && "on" && line 1 of the working screenRects
   else
      put "INFO  no screen here: where the window opens is not seen" & return after sOut
   end if
   drCheck drPlaced("-320,-140,640,460", "0,0,1821,920") is "910,476", \
         "a window above and left of the screen is centred on it", drPlaced("-320,-140,640,460", "0,0,1821,920")
   drCheck drPlaced("120,100,1080,700", "0,0,1821,920") is empty \
         and drPlaced("2000,100,2960,700", "0,0,1821,920" & return & "1821,0,3741,1040") is empty, \
         "a window on any screen stays where it is", drPlaced("2000,100,2960,700", "0,0,1821,920" & return & "1821,0,3741,1040")
   drCheck drPlaced("120,10,1080,610", "0,0,1280,600") is "640,332", \
         "on a screen too short for it, its title bar stays on the screen", drPlaced("120,10,1080,610", "0,0,1280,600")
   drCheck drPlaced("-320,-140,640,460", "0,0,0,0") is empty and drPlaced("-320,-140,640,460", empty) is empty, \
         "with no display it moves nothing", drPlaced("-320,-140,640,460", "0,0,0,0")
   put the number of controls of card 1 of stack kStack into tWas
   send "preOpenStack" to stack kStack
   drCheck the number of controls of card 1 of stack kStack is tWas, "reopening adds no control", \
         the number of controls of card 1 of stack kStack
end drWindow

-- Without the extension: the window says so, and every click is safe.
command drMissing
   local tName
   drOpen
   drWindow
   drWait 400
   drCheck the visible of field "Missing" of card 1 of stack kStack and drField("Missing") contains "needs audioxt", \
         "without the extension the stage says plainly what it needs", drField("Missing")
   drCheck drField("Status") contains "not loaded", "and so does the status line", drField("Status")
   drCheck drField("Caption") contains "not here", "and the caption over the stage", drField("Caption")
   drShot "0-missing"
   repeat for each item tName in "Sc1,Sc5,PlayAll,Pause,Device,Checks"
      drClick tName
   end repeat
   dispatch "mouseDown" to graphic "VolKnob" of card 1 of stack kStack with 1
   dispatch "mouseMove" to graphic "VolKnob" of card 1 of stack kStack with 818, 348
   dispatch "mouseUp" to graphic "VolKnob" of card 1 of stack kStack with 1
   drWait 200
   drCheck drHandle("scene") is 0 and the visible of field "Missing" of card 1 of stack kStack, \
         "every button and the volume answer with the same words, and nothing breaks", drHandle("scene")
   drCheck drField("VolText") is "50%", "the volume knob still moves", drField("VolText")
   send "closeStack" to stack kStack
   drCheck drHandle("engine") is 0, "it closes", drHandle("engine")
end drMissing

on startup
   local tError
   put 0 into sPassed
   put 0 into sFailed
   try
      if $AUDIOXT_LCM is empty then
         drMissing
      else
         drStage
      end if
   catch tError
      drCheck false, "the drive ran to its end", tError
   end try
   write sOut & "DRIVE" && sPassed && sFailed & return to stdout
   if sFailed is 0 and sPassed > 0 then
      quit 0
   end if
   quit 1
end startup

command drStage
   local tEngine, tKit, tDrums, tBee, tWhere, tFacing, tChord, tPath, tWas, tNew, tReport, tMic, tOpened
   set the revLibraryMapping["audioxt"] to $AUDIOXT_LIB
   load extension from file $AUDIOXT_LCM
   drCheck the result is empty, "the extension loads", the result
   drOpen
   -- the window is built and up: the clock a person would start
   put the milliseconds into tOpened
   drWindow

   -- straight into the show, with no click
   drCheck drWaitFor("scene", 1, 3000), "it opens straight into the first scene", drHandle("scene")
   -- the oscilloscope moves within a second of the window: watched, since
   -- between two hits of a beat it is flat for a moment
   repeat while not drScopeMoves() and the milliseconds - tOpened < 1000
      wait 20 milliseconds with messages
   end repeat
   drCheck drScopeMoves(), "something moves within a second of opening", the milliseconds - tOpened
   drShot "0-open"
   drCheck drHandle("playall") is true and the hilite of button "PlayAll" of card 1 of stack kStack, \
         "playing every scene in turn", drHandle("playall")
   put drHandle("engine") into tEngine
   drCheck tEngine > 0 and auEngineIsValid(tEngine), "an engine opens by itself", drField("Status")
   if drHandle("enginenote") is not empty then
      drCheck drHandle("device") is 0 and drField("Status") contains "silent device", \
            "with no sound card it plays on the silent device, and says so", drField("Status")
   end if

   -- 1. Beat machine
   drCheck drWaitFor("phase", "playing", 3000), "the drums are made in script, one a frame", drHandle("phase")
   put drHandle("kit") into tKit
   drCheck drAllValid(tKit, 5), "kick, snare, hat, bell and crash are sounds", tKit
   put drHandle("drums") into tDrums
   drCheck auGroupIsValid(tDrums), "the drums play in a group", tDrums
   drAtTime 2.6, 5000
   drCheck drHandle("notes") >= 8, "the beat plays: notes are started on the engine's clock", drHandle("notes")
   drCheck drScopeMoves(), "the oscilloscope draws what the device plays", the number of lines of the points of graphic "Scope"
   drCheck the height of graphic "MeterL" of card 1 of stack kStack > 4, "and the meter rises", the rect of graphic "MeterL"
   drCheck drField("Caption") contains "bar", "the caption says what the bar does", drField("Caption")
   drShot "1-beat"
   drAtTime 5.2, 5000
   drCheck auGroupPan(tDrums) is not 0, "bar 3 pans the whole group", auGroupPan(tDrums)
   drAtTime 7.4, 5000
   drCheck auGroupPitch(tDrums) > 1, "bar 4 raises its pitch", auGroupPitch(tDrums)
   drShot "1-beat-bar4"
   drCheck drWaitFor("scene", 2, 9000), "Play all goes on to the next scene", drHandle("scene")
   drCheck auGroupPan(tDrums) is 0 and auGroupPitch(tDrums) is 1, "and puts the group back", auGroupPan(tDrums)

   -- 2. Round your head
   put drHandle("bee") into tBee
   drCheck tBee > 0 and auSoundIsPlaying(tBee) and auSoundIsSpatial(tBee), "a sound with a place in the room", tBee
   put auSoundPositionXYZ(tBee) into tWhere
   drWait 300
   drCheck auSoundPositionXYZ(tBee) is not tWhere, "it circles you", tWhere && auSoundPositionXYZ(tBee)
   drAtTime 1.9, 4000
   drShot "2-round"
   drAtTime 6.6, 7000
   drCheck drHandle("phase") is "past" and abs(item 1 of drHandle("beexz")) < 14, "then flies past", drHandle("phase")
   drShot "2-past"
   drAtTime 11.6, 7000
   put drHandle("facing") into tFacing
   drCheck tFacing > 20 and tFacing < 360 and auEngineListenerDirection(drHandle("engine")) is not "0,0,-1", \
         "then holds still while you turn", tFacing
   drShot "2-turn"
   drCheck drWaitFor("scene", 3, 5000), "and Play all goes on", drHandle("scene")
   drCheck auSoundIsValid(tBee) is false, "the scene's sound is freed with it", tBee

   -- 3. Synth and fades
   drCheck drAllValid(drHandle("voices"), 4), "the four shapes are tones", drHandle("voices")
   drAtTime 2.9, 5000
   drCheck drHandle("voicenow") > 0 and drField("yName") is not empty, "they play in turn, each named", drField("yName")
   drShot "3-synth"
   drAtTime 10, 9000
   put drHandle("chord") into tChord
   drCheck drAllValid(tChord, 4) and auSoundIsPlaying(item 1 of tChord) and auSoundIsPlaying(drHandle("noise")), \
         "then a chord, over pink noise", tChord
   drCheck auSoundPan(item 1 of tChord) < 0 and auSoundPan(item 4 of tChord) > 0, "spread from left to right", \
         auSoundPan(item 1 of tChord) && auSoundPan(item 4 of tChord)
   drShot "3-chord"
   drCheck drWaitFor("scene", 4, 6000), "and Play all goes on", drHandle("scene")

   -- 4. A tape made here
   drCheck drWaitFor("phase", "stream", 5000), "the tape is made a piece a frame, then plays", drHandle("phase")
   put drHandle("tapepath") into tPath
   drCheck drHandle("tapebytes") is 352844 and there is a file tPath, "two seconds of stereo WAV, written to a file", \
         drHandle("tapebytes") && tPath
   drCheck auSoundIsPlaying(drHandle("tapestream")), "streamed back from that file", drHandle("tapestream")
   drWait 700
   drShot "4-tape"
   drCheck drWaitFor("phase", "clones", 4000), "then three clones at once", drHandle("phase")
   drCheck drAllValid(drHandle("clones"), 3), "three sounds sharing the tape", drHandle("clones")
   drWait 500
   drShot "4-clones"
   drCheck drWaitFor("phase", "loop", 4000) and auSoundIsLooping(drHandle("tape")), "then a loop over its middle", drHandle("phase")
   drCheck drWaitFor("scene", 0, 10000), "Play all ends after the fourth scene", drHandle("scene")
   drCheck the visible of group "gEnd" of card 1 of stack kStack and drField("EndName") is "A tape made here" \
         and drHandle("playall") is false, "and a card says what that was and what to do next", drField("EndName")
   drCheck not the visible of group "gTape" of card 1 of stack kStack, "over a clear stage", drHandle("scene")
   drShot "4-end"

   -- the sound devices panel: the silent microphone, for the next scene
   drPick "listen,-1"
   drCheck drHandle("micdevice") is -1 and not the visible of group "gDevices" of card 1 of stack kStack, \
         "a pick takes effect and closes the panel", drHandle("micdevice")
   drClick "Device"
   drCheck the visible of group "gDevices" of card 1 of stack kStack and the label of button "dvP1" of card 1 of stack kStack \
         is "The system's default" and the label of button "dvL2" of card 1 of stack kStack contains "silent", \
         "the panel lists what to play through and what to listen with", the label of button "dvL2" of card 1 of stack kStack
   drCheck the hilite of button "dvL2" of card 1 of stack kStack, "the one in use is lit", drHandle("menu")
   drShot "5-devices"
   drClick "dvClose"
   drCheck not the visible of group "gDevices" of card 1 of stack kStack, "Close closes it", empty

   -- 5. Your microphone
   drClick "Sc5"
   put drHandle("mic") into tMic
   drCheck drHandle("scene") is 5 and tMic > 0 and auCaptureIsRunning(tMic), "the microphone scene listens", drField("mFacts")
   drWait 1200
   drCheck drHandle("micbytes") > 16000, "what it hears is kept as it arrives", drHandle("micbytes")
   drShot "5-mic"
   drCheck drWaitFor("phase", "play", 8000), "after five seconds it plays it back", drHandle("phase")
   drCheck auSoundIsPlaying(drHandle("micsound")) and auCaptureIsValid(tMic) is false, "from memory, the microphone closed", \
         drHandle("micsound")
   drCheck drField("mFacts") contains "decodes back to" and drField("mFacts") contains "0 frames dropped", \
         "the file written beside it is read back", drField("mFacts")
   drShot "5-playback"
   drCheck drWaitFor("phase", "faster", 8000), "then once more, faster", drHandle("phase")
   drCheck drWaitFor("scene", 0, 8000) and drField("EndName") is "Your microphone", "and the card comes", drField("EndName")

   -- 5 again, with a microphone that sends nothing, as a page that may not
   -- use one gets (in a community gallery play page, 2026-11-22, the reason
   -- was on the stage for one frame and the status line was cut off at its
   -- end). The silent microphone always sends silence, so the capture is
   -- closed under the scene before it has read anything.
   drClick "Sc5"
   put drHandle("mic") into tMic
   drCheck drHandle("scene") is 5 and tMic > 0 and auCaptureIsRunning(tMic), "the microphone scene listens again", \
         drField("mFacts")
   auCaptureClose tMic
   drCheck drWaitFor("phase", "none", 14000), "with nothing heard, after its wait it says so", drHandle("phase")
   drCheck drField("Caption") is "No microphone here" and drField("mRecText") is empty \
         and drField("mFacts") contains "No sound arrived from the microphone." \
         and drField("Status") is drHandle("micnosound"), "plainly, on the stage and in one status line", drField("Status")
   drShot "5-none"
   drWait 2000
   drCheck drHandle("scene") is 5 and drHandle("phase") is "none", "and leaves the reason up to be read", drHandle("phase")
   drCheck drWaitFor("scene", 0, 8000) and drField("EndName") is "Your microphone" \
         and drField("Status") is drHandle("micnosound"), "then the card comes, the status line still saying why", \
         drField("Status")
   drFits "5-none-end"

   -- pause, resume, the volume knob
   drClick "Sc2"
   drWait 300
   put drHandle("engine") into tEngine
   drClick "Pause"
   put auEngineTime(tEngine) into tWas
   drWait 300
   drCheck drHandle("paused") is true and auEngineTime(tEngine) is tWas and the label of button "Pause" of card 1 of stack kStack \
         is "Paused: resume", "Pause stops the clock, and every scene with it", tWas && auEngineTime(tEngine)
   drClick "Pause"
   drWait 300
   drCheck auEngineTime(tEngine) > tWas and drHandle("paused") is false, "and it goes on", auEngineTime(tEngine)
   dispatch "mouseDown" to graphic "VolKnob" of card 1 of stack kStack with 1
   dispatch "mouseMove" to graphic "VolKnob" of card 1 of stack kStack with 818, 348
   dispatch "mouseUp" to graphic "VolKnob" of card 1 of stack kStack with 1
   drCheck auEngineVolume(tEngine) is 0.5 and drField("VolText") is "50%", "the volume knob drags", auEngineVolume(tEngine)
   dispatch "mouseMove" to graphic "VolKnob" of card 1 of stack kStack with 900, 348
   drCheck auEngineVolume(tEngine) is 0.5, "and stops when it is let go", auEngineVolume(tEngine)

   -- another device: the engine is made again and the scene starts again
   drPick "play,-1"
   put drHandle("engine") into tNew
   drCheck tNew is not tEngine and auEngineIsValid(tNew) and auEngineIsValid(tEngine) is false and drHandle("device") is -1, \
         "playing through another device makes a new engine", tEngine && tNew
   drCheck drHandle("scene") is 2 and auSoundIsPlaying(drHandle("bee")), "and the scene plays on it", drHandle("scene")
   drCheck drNear(auEngineVolume(tNew), 0.5), "at the volume set", auEngineVolume(tNew)

   -- the checks, a step a frame
   drClick "Checks"
   drCheck drHandle("scene") is 6, "Run the checks", drHandle("scene")
   drWait 100
   drCheck drHandle("ckdone") is false, "they run a step a frame, so the window never stops", drHandle("cklog")
   drCheck drWaitFor("ckdone", true, 30000), "and come to their end", drHandle("cklog")
   put drHandle("cklog") into tReport
   put tReport & return after sOut
   drCheck the last line of tReport begins with "SUMMARY" and the last word of tReport is 0 and word 2 of the last line of tReport > 60, \
         "every check passes", the last line of tReport
   drCheck drField("cSum") contains "none failed" and the visible of button "cCopy" of card 1 of stack kStack, \
         "the window says so, and offers to copy them", drField("cSum")
   drShot "6-checks"
   drClick "cCopy"
   drCheck drField("Status") contains "on the clipboard", "Copy the results", drField("Status")

   -- closing the stack closes every device
   put drHandle("engine") into tEngine
   send "closeStack" to stack kStack
   drCheck auEngineIsValid(tEngine) is false and drHandle("engine") is 0, "closing the stack closes all sound", drHandle("engine")
end drStage

function drNear pA, pB
   return pA is a number and abs(pA - pB) < 0.001
end drNear
