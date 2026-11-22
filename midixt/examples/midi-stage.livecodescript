script "MIDI Stage"

-- midi-stage.livecodescript - midixt's showcase, by Seth Morrow.
--
-- A PLAYER and a STAGE in one window, talking realtime MIDI. The player
-- plays: notes, chords, eight knobs, a pitch bend, drums and program changes,
-- each one a real MIDI message sent with midixt. The stage draws ONLY what
-- arrives: a piano roll, a keyboard, the knobs, the wheels, the program and a
-- light for each channel. Between them, where this computer allows, is a
-- real MIDI cable: a virtual port named "MIDI Stage" that the player sends
-- into and the stage reads back from the system's own MIDI service with
-- midiPoll (macOS, and Linux with ALSA), or a loopback driver such as
-- loopMIDI (Windows). Where there is no cable, the stage reads every message
-- the player builds with midiDecode, and says so: nothing travels then.
--
-- It opens straight into motion and plays five scenes, one capability each:
--   1. Arpeggio             note on and note off, in time
--   2. Chords and velocity  many notes at once, each as hard as it was struck
--   3. Knobs                eight controllers moving at once
--   4. Pitch bend           a held note bent with a 14-bit value
--   5. Drums and programs   channel 10's drums; program changes on channel 1
-- A scene button jumps to its scene; "Play them all" goes round them;
-- "Pause" stops the player (and silences it); "Sound" plays the player
-- through a MIDI output as well: on Windows, the Microsoft GS Wavetable Synth
-- every Windows has. Sound starts OFF.
--
-- A MIDI keyboard plugged in? The stage listens to every other input too:
-- play, and your notes light up in blue beside the player's orange.
--
-- HOW TO OPEN: start-here.livecodescript's Open button (it does the next
-- three steps for you), or paste THIS whole file into a new stack's STACK
-- script, Apply, then close the stack and open it again. Opening the file
-- itself loads the script and builds no window (the suite's engine notes,
-- 5.5). It needs the midixt extension installed; without it the window still
-- opens and says what is missing. midi-helpers (scMidiStartListening and its
-- scNoteOn, scMidiCC, ... messages) is embedded below, so there is nothing
-- else to load.
--
-- WHAT IT TOUCHES: it makes one virtual MIDI port, "MIDI Stage", which other
-- MIDI programs can see while the stack is open; it opens your MIDI inputs to
-- read them; it sends to a MIDI output only when you press Sound, and then
-- only to the one the footer names. Every stop, pause and scene change sends
-- note-offs and "all notes off", so nothing is left sounding.
--
-- THE LOOK is OXT-Beyond's dark stage (the Render3D Tour's palette), not the
-- suite's light UI kit, by request (2026-11-21), so this stack is in
-- tools/check-ui-kit-drift.py's EXEMPT list. Every field and button sets its
-- own text colour, because OXT-Beyond gives a control without one white
-- text under a dark system theme, and every switch is a button, not a tick
-- box, which the system draws in its own colours.
--
-- FOR THE TESTS (tests/lcs/demo_test.livecodescript, over the mock library):
-- mdsTestBegin stops the clock's loop, mdsTestStep moves the show on by so
-- many seconds and draws, mdsGo jumps to a scene, mdsTestCable hands the
-- demo two ports to use as its cable, and mdsState() says how things are.
--
-- HONESTY (the suite convention): it built, ran every scene and passed its
-- tests in OXT-Beyond's standalone engine (9.7.1-OXT, Linux x86_64, headless
-- with -ui) on 2026-11-21, over the mock library (its cable a mock loopback)
-- and over the real one on a machine with no MIDI service (where it reads
-- with midiDecode and says why). No MIDI service has carried its messages
-- and nobody has heard it: the cable, the sound, the look and the feel are
-- verified statically; need an OXT pass.

-- ===== Sizes and the look ===================================================


-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- midixt/examples/midi-helpers.livecodescript ----
-- midi-helpers.livecodescript
-- ---------------------------------------------------------------------------
-- Reusable LiveCode Script helpers for the midixt extension (realtime MIDI).
-- Paste this into a stack or card script (or a library stack you `start
-- using`), then your own handlers only need to react to events:
--
--     put midiOpenInput(0) into tIn     -- the first input; or midiOpenVirtualInput("My In")
--     scMidiStartListening tIn
--
--     on scNoteOn pChannel, pNote, pVelocity
--        ...
--     end scNoteOn
--
-- MIDI input is POLLED: nothing calls into script from RtMidi's thread (the
-- suite's rule 1), so scMidiStartListening runs a timer that drains midiPoll
-- and sends one message per event to the object that started it:
--
--     scNoteOn pChannel, pNote, pVelocity
--     scNoteOff pChannel, pNote, pVelocity     (a note-on of velocity 0 too)
--     scMidiCC pChannel, pController, pValue
--     scProgramChange pChannel, pProgram
--     scPitchBend pChannel, pValue14           (0 to 16383; 8192 is no bend)
--     scMidiOther pKind, pChannel, pEvent      (everything else: pEvent is the
--                                               whole midiPoll record, its raw
--                                               bytes in pEvent["bytes"])
--
-- This is the MIDI part of ShowControl's showcontrol-helpers.livecodescript,
-- with the same handler names, parameters and messages, so a stack written
-- against it keeps working. What changed is said at scMidiStartListening.
-- Pasting this beside oscxt's osc-helpers and artnetxt's artnet-helpers gives
-- the old combined file's handlers again: no name is defined in two of the
-- three (the suite's tools/check-cross-library-names.py holds that).
-- ---------------------------------------------------------------------------

-- One entry per input being listened to, keyed by its handle:
--    ["generation"]  which timer chain is the live one (see below)
--    ["ms"]          the poll interval
--    ["target"]      the long id of the object the events are sent to
local sMidiListeners
-- The last generation handed out. It only ever grows, so a timer message
-- still pending from a chain that was stopped can never match a later one.
local sMidiGeneration

-- ===== MIDI poll dispatcher ================================================

-- Start listening on an open input (a handle from midiOpenInput or
-- midiOpenVirtualInput). pIntervalMs is the poll interval (default 3); a
-- shorter one only lowers latency, since RtMidi queues every message with its
-- timing between polls. Events go to the object that called this handler, or
-- to pTarget (a long id) if given, and travel up ITS message path, so
-- `on scNoteOn` in that object, its card or its stack receives them.
--
-- Why the listener is remembered here: the poll re-arms itself with
-- `send ... to me in N milliseconds`, and inside a timer-delivered message
-- `the target` is this LIBRARY, not your card. Dispatching to `the target`
-- (as ShowControl's helper once did) silently delivered every timer-polled
-- event to the library itself whenever the helpers were used via
-- `start using` (tests/lcs/helpers_test.livecodescript).
--
-- What midixt changed, each pinned by tests/lcs/helpers_test.livecodescript:
--  * Each input has its OWN listener. ShowControl kept one interval and one
--    target for all of them, so starting a second input sent the first
--    one's events to the second one's target too.
--  * Starting again (the same input, or after scMidiStopListening) replaces
--    the running timer. ShowControl's never stopped: every stop-and-start
--    inside one interval left one more timer polling for good.
--  * A handle that is not a port (0 from an open that failed) starts nothing
--    and sets the result to why. ShowControl polled it every 3 ms for ever.
--  * A port closed while it is listened to stops its own timer at the next
--    poll (midiPoll says it is not an open input).
--  * scMidiIsListening(pHandle) tells whether an input is being listened to.
-- Unchanged on purpose: if one of your handlers throws, listening on that
-- input stops (as it always has: the throw skips the next poll) and the error
-- reaches you as before. scMidiIsListening turns false; start it again once
-- the handler is fixed.
on scMidiStartListening pHandle, pIntervalMs, pTarget
   local tGeneration
   if pIntervalMs is empty then put 3 into pIntervalMs
   if pIntervalMs is not a number then
      throw "scMidiStartListening: the poll interval must be a number of milliseconds, not" && pIntervalMs
   end if
   if pHandle is not an integer then
      throw "scMidiStartListening: pHandle must be a MIDI input handle, not" && pHandle
   end if
   if pHandle < 1 then
      -- 0 is what a port that would not open returns: there is nothing to poll
      return "scMidiStartListening: no open MIDI input (handle" && pHandle & ")"
   end if
   if pTarget is empty then put the long id of the target into pTarget
   add 1 to sMidiGeneration
   put sMidiGeneration into tGeneration
   -- pHandle + 0 is the key everywhere, so "3", 3 and 3.0 are one listener
   put tGeneration into sMidiListeners[pHandle + 0]["generation"]
   put pIntervalMs into sMidiListeners[pHandle + 0]["ms"]
   put pTarget into sMidiListeners[pHandle + 0]["target"]
   scMidiPollAndDispatch pHandle + 0, tGeneration
   return empty
end scMidiStartListening

-- Stop listening on one input, or on every input when pHandle is empty (all
-- ShowControl's version could do). Messages still waiting in the input stay
-- queued for a later poll. It does not close the port: midiClose does that.
on scMidiStopListening pHandle
   if pHandle is empty then
      put empty into sMidiListeners
   else if pHandle is a number then
      delete variable sMidiListeners[pHandle + 0]
   end if
end scMidiStopListening

-- True while the dispatcher is polling this input.
function scMidiIsListening pHandle
   if pHandle is not a number then return false
   return sMidiListeners[pHandle + 0]["generation"] is not empty
end scMidiIsListening

-- One poll: drain the input and send each event on. The timer calls it with
-- the generation of the chain that armed it; a tick from a chain that was
-- stopped or replaced ends there. Called without a generation (by hand, as
-- ShowControl's could be) it polls once and arms no timer of its own.
on scMidiPollAndDispatch pHandle, pGeneration
   local tEvents, tEvent, tTarget, tError, tFailed
   if not scMidiIsListening(pHandle) then exit scMidiPollAndDispatch
   put pHandle + 0 into pHandle
   if pGeneration is not empty and pGeneration is not sMidiListeners[pHandle]["generation"] then
      exit scMidiPollAndDispatch
   end if
   put sMidiListeners[pHandle]["target"] into tTarget
   put midiPoll(pHandle) into tEvents
   if tEvents is empty and midiLastError() contains "not an open input port" then
      -- closed under us (midiClose without scMidiStopListening): stop polling
      delete variable sMidiListeners[pHandle]
      exit scMidiPollAndDispatch
   end if
   put false into tFailed
   -- midiPoll's list is keyed 1..N, which `repeat for each element` walks in
   -- order (engine exec-keywords.cpp, bug 15457), so events keep their order.
   repeat for each element tEvent in tEvents
      try
         scMidiDispatchEvent tEvent, tTarget
      catch tError
         put true into tFailed
      end try
      if tFailed then exit repeat
   end repeat
   if tFailed then
      -- One of the handlers threw. Stop this listener, as the throw always
      -- did, but say so (scMidiIsListening) and hand the error on unchanged.
      -- (A throw inside `catch` never reaches the caller on OXT: hence here.)
      if pGeneration is sMidiListeners[pHandle]["generation"] then
         delete variable sMidiListeners[pHandle]
      end if
      throw tError
   end if
   -- Re-arm only the live chain, and only from a timer tick: a handler that
   -- stopped or restarted listening during this batch has the last word.
   if pGeneration is not empty and pGeneration is sMidiListeners[pHandle]["generation"] then
      send "scMidiPollAndDispatch" && pHandle & "," & pGeneration to me \
            in sMidiListeners[pHandle]["ms"] milliseconds
   end if
end scMidiPollAndDispatch

-- `dispatch ... with` passes REAL parameters. ShowControl's first form,
--    send "scNoteOn" && channel && note && velocity to ...
-- built the string "scNoteOn 1 60 100", and a message string's parameters
-- are separated by COMMAS, so the whole "1 60 100" arrived in pChannel and
-- pNote and pVelocity were empty (caught by tests/lcs/helpers_test).
private command scMidiDispatchEvent pEvent, pTarget
   switch pEvent["kind"]
      case "noteOn"
         dispatch "scNoteOn" to pTarget with pEvent["channel"], pEvent["data1"], pEvent["data2"]
         break
      case "noteOff"
         dispatch "scNoteOff" to pTarget with pEvent["channel"], pEvent["data1"], pEvent["data2"]
         break
      case "controlChange"
         dispatch "scMidiCC" to pTarget with pEvent["channel"], pEvent["data1"], pEvent["data2"]
         break
      case "programChange"
         dispatch "scProgramChange" to pTarget with pEvent["channel"], pEvent["data1"]
         break
      case "pitchBend"
         dispatch "scPitchBend" to pTarget with pEvent["channel"], pEvent["value14"]
         break
      default
         -- channelPressure / polyAftertouch / sysex / system: hand off the
         -- kind, the channel and the whole decoded record (raw bytes in
         -- ["bytes"])
         dispatch "scMidiOther" to pTarget with pEvent["kind"], pEvent["channel"], pEvent
   end switch
end scMidiDispatchEvent

-- <<< END EMBEDDED LIBRARIES <<<

constant kMdsW = 1100
constant kMdsH = 620
constant kMdsFrameMs = 33          -- about thirty pictures a second
constant kMdsPortName = "MIDI Stage"
constant kMdsPollMs = 4            -- the cable's poll interval
constant kMdsLow = 48              -- C3, the keyboard's lowest key
constant kMdsHigh = 84             -- C6, its highest
constant kMdsBeat = 0.5357         -- 112 beats a minute
constant kMdsScenes = 5
constant kMdsSceneNames = "Arpeggio,Chords and velocity,Knobs,Pitch bend,Drums and programs"
constant kMdsSceneSecs = "13,12,12,12,13"
constant kMdsWireLines = 6
constant kMdsSentLines = 12
constant kMdsBars = 56
constant kMdsHits = 36
constant kMdsRollSecs = 4
constant kMdsYouMax = 4
constant kMdsKnobCCs = "1,7,10,11,71,74,91,93"
constant kMdsKnobNames = "mod,vol,pan,expr,reso,cutoff,reverb,chorus"

-- OXT-Beyond's dark stage: the Render3D Tour's colours, as r,g,b so the
-- picture can mix them
constant kMdsPage = "18,21,31"
constant kMdsPanel = "28,33,48"
constant kMdsWell = "12,15,23"
constant kMdsInk = "238,241,247"
constant kMdsSoft = "169,178,199"
constant kMdsAccent = "255,138,61"
constant kMdsButton = "42,49,70"
constant kMdsLine = "58,66,92"
constant kMdsOff = "44,49,66"
constant kMdsYou = "92,200,255"
constant kMdsWhite = "214,219,230"
constant kMdsBlack = "30,34,46"

-- The geometry, in one place
constant kMdsStageL = 16
constant kMdsStageT = 84
constant kMdsStageR = 780
constant kMdsStageB = 588
constant kMdsRollL = 30
constant kMdsRollT = 110
constant kMdsRollR = 766
constant kMdsRollB = 252
constant kMdsDrumT = 218
constant kMdsKeysL = 35
constant kMdsKeysT = 258
constant kMdsKeysB = 344
constant kMdsWhiteW = 33
constant kMdsKnobL = 40
constant kMdsKnobDX = 58
constant kMdsKnobT = 383
constant kMdsKnobS = 42
constant kMdsWheelT = 452
constant kMdsWheelB = 566
constant kMdsSideL = 796
constant kMdsSideR = 1084

-- The General MIDI sound set, so a program number reads as an instrument
constant kMdsPrograms = "Acoustic Grand Piano;Bright Acoustic Piano;Electric Grand Piano;Honky-tonk Piano;Electric Piano 1;Electric Piano 2;Harpsichord;Clavi;Celesta;Glockenspiel;Music Box;Vibraphone;Marimba;Xylophone;Tubular Bells;Dulcimer;Drawbar Organ;Percussive Organ;Rock Organ;Church Organ;Reed Organ;Accordion;Harmonica;Tango Accordion;Acoustic Guitar (nylon);Acoustic Guitar (steel);Electric Guitar (jazz);Electric Guitar (clean);Electric Guitar (muted);Overdriven Guitar;Distortion Guitar;Guitar Harmonics;Acoustic Bass;Electric Bass (finger);Electric Bass (pick);Fretless Bass;Slap Bass 1;Slap Bass 2;Synth Bass 1;Synth Bass 2;Violin;Viola;Cello;Contrabass;Tremolo Strings;Pizzicato Strings;Orchestral Harp;Timpani;String Ensemble 1;String Ensemble 2;Synth Strings 1;Synth Strings 2;Choir Aahs;Voice Oohs;Synth Voice;Orchestra Hit;Trumpet;Trombone;Tuba;Muted Trumpet;French Horn;Brass Section;Synth Brass 1;Synth Brass 2;Soprano Sax;Alto Sax;Tenor Sax;Baritone Sax;Oboe;English Horn;Bassoon;Clarinet;Piccolo;Flute;Recorder;Pan Flute;Blown Bottle;Shakuhachi;Whistle;Ocarina;Lead 1 (square);Lead 2 (sawtooth);Lead 3 (calliope);Lead 4 (chiff);Lead 5 (charang);Lead 6 (voice);Lead 7 (fifths);Lead 8 (bass and lead);Pad 1 (new age);Pad 2 (warm);Pad 3 (polysynth);Pad 4 (choir);Pad 5 (bowed);Pad 6 (metallic);Pad 7 (halo);Pad 8 (sweep);FX 1 (rain);FX 2 (soundtrack);FX 3 (crystal);FX 4 (atmosphere);FX 5 (brightness);FX 6 (goblins);FX 7 (echoes);FX 8 (sci-fi);Sitar;Banjo;Shamisen;Koto;Kalimba;Bagpipe;Fiddle;Shanai;Tinkle Bell;Agogo;Steel Drums;Woodblock;Taiko Drum;Melodic Tom;Synth Drum;Reverse Cymbal;Guitar Fret Noise;Breath Noise;Seashore;Bird Tweet;Telephone Ring;Helicopter;Applause;Gunshot"

-- The player's music (an original arpeggio over C, G, A minor and F):
-- each chord's arpeggio, its bass note, and scene 2's four voicings
constant kMdsArps = "60 64 67 72 76 72 67 64;62 67 71 74 79 74 71 67;64 69 72 76 81 76 72 69;65 69 72 77 81 77 72 69"
constant kMdsBass = "48 55 57 53"
constant kMdsVoicings = "60 64 67 71;57 60 64 67;62 65 69 72;55 59 62 65"
-- Scene 5: the programs it changes through (0-based, as sent), and a riff
constant kMdsScenePrograms = "0,4,11,24,80"
constant kMdsRiff = "60 67 72 76;57 64 69 72;62 65 69 74;55 62 67 71"

-- ===== State =================================================================

local sMyStack            -- the stack's short name: every delayed message pins it
local sRunning, sGen      -- the loop runs; its generation (a stale tick dies)
local sClockMs            -- the milliseconds at the last frame
local sFrames             -- pictures drawn since the stack opened
local sScene, sSceneT     -- the scene playing, and the seconds it has played
local sStepDone           -- the last step of the scene's score played
local sTour, sPaused
local sHaveMidi, sWhyNot  -- midixt answers; why not, when it does not
local sMode               -- "cable", "decode" or "none"
local sCableIn, sCableOut, sCableName, sCableHow, sNoCable
local sYouIns, sYouNames  -- other inputs, read for the player at the keys
local sSoundOut, sSoundName, sSoundOn, sSoundWhy
local sTrouble            -- an error the loop caught
-- the player
local sOffs               -- note-offs to come: "due|channel|note" lines
local sCCLast, sBendLast, sSentLog, sSentAt
-- the stage: only what arrived
local sKeyVel, sKeyWho, sKeyShown
local sBar, sNextBar, sHit, sNextHit
local sCCVal, sCCShown, sBend, sProgram, sProgramCh, sGlow
local sBendTrail, sHeld
local sWireLog
-- the counts
local sSent, sRead, sYouRead, sLagSum, sLagN
local sRateMark, sRateBase, sRate

-- ===== The stack's own messages =============================================

on preOpenStack
   put the short name of this stack into sMyStack
   mdsBuild
end preOpenStack

on openStack
   mdsStart
end openStack

on closeStack
   mdsStop
end closeStack

on mouseUp
   local tName
   put the short name of the target into tName
   if tName begins with "mdsScene" and char 9 to -1 of tName is an integer then
      mdsGo char 9 to -1 of tName
   else if tName is "mdsTour" then
      put (sTour is not true) into sTour
      mdsShowSwitches
   else if tName is "mdsPause" then
      put (sPaused is not true) into sPaused
      if sPaused then
         mdsSilence
      end if
      mdsShowSwitches
   else if tName is "mdsSound" then
      mdsSoundSwitch
   else
      pass mouseUp
   end if
end mouseUp

-- ===== Starting and stopping ================================================

command mdsStart
   if sMyStack is empty then
      put the short name of this stack into sMyStack
   end if
   if there is not a graphic "mdsStage" then
      mdsBuild
   end if
   mdsStop
   mdsResetStage
   put true into sTour
   put false into sPaused
   put false into sSoundOn
   put empty into sTrouble
   put 0 into sFrames
   mdsProbe
   mdsConnect
   mdsShowStatus
   mdsShowSwitches
   mdsGo 1
   put true into sRunning
   add 1 to sGen
   put the milliseconds into sClockMs
   mdsFrame sGen
end mdsStart

command mdsStop
   local tI
   put false into sRunning
   add 1 to sGen
   if sHaveMidi is true then
      mdsSilence
      scMidiStopListening
      repeat for each item tI in sCableIn & comma & sCableOut & comma & sSoundOut
         if tI is an integer and tI > 0 then
            midiClose tI
         end if
      end repeat
      repeat for each element tI in sYouIns
         midiClose tI
      end repeat
   end if
   put empty into sCableIn
   put empty into sCableOut
   put empty into sSoundOut
   put empty into sYouIns
   put empty into sYouNames
end mdsStop

-- Is midixt here? The first call of an LCB library that is not loaded throws
-- (no such handler), and so does one whose native library did not load; the
-- loaded extensions tell the two apart.
command mdsProbe
   local tErr, tAbi
   put false into sHaveMidi
   put empty into sWhyNot
   try
      put midiVersion() into tAbi
      put (tAbi is 2) into sHaveMidi
      if not sHaveMidi then
         put "midixt's native library is ABI " & tAbi & ", and this demo is written for 2." into sWhyNot
      end if
   catch tErr
      if "org.openxtalk.library.midi" is among the lines of the loadedExtensions then
         put "midixt is loaded, but its native library did not load: " & mdsEngineSays(tErr) & "." into sWhyNot
      else
         put "midixt is not loaded in this OXT: nothing answered midiVersion()." into sWhyNot
      end if
   end try
end mdsProbe

-- The sentence in an engine error (its lines are code,line,column,hint, and
-- one hint is the message itself): the first hint with a space in it
function mdsEngineSays pErr
   local tLine
   repeat for each line tLine in pErr
      if item 4 to -1 of tLine contains space then
         return item 4 to -1 of tLine
      end if
   end repeat
   return "the engine gave no reason"
end mdsEngineSays

-- Find a cable, the other inputs and an output to play through
command mdsConnect
   local tIns, tOuts, tOut, tIndex, tPair, tI, tH
   put empty into sCableIn
   put empty into sCableOut
   put empty into sCableName
   put empty into sCableHow
   put empty into sNoCable
   put empty into sYouIns
   put empty into sYouNames
   put empty into sSoundOut
   put empty into sSoundName
   put empty into sSoundWhy
   if sHaveMidi is not true then
      put "none" into sMode
      exit mdsConnect
   end if
   put "decode" into sMode
   -- 1. a virtual port, found again among the inputs (macOS, Linux)
   put midiOpenVirtualOutput(kMdsPortName) into tOut
   if tOut > 0 then
      put mdsPortLines(midiInputPorts()) into tIns
      put mdsFindVirtual(tIns, kMdsPortName) into tIndex
      if tIndex >= 0 then
         put midiOpenInput(tIndex) into tH
         if tH > 0 then
            put tOut into sCableOut
            put tH into sCableIn
            put line (tIndex + 1) of tIns into sCableName
            put "virtual" into sCableHow
         end if
      end if
      if sCableIn is empty then
         midiClose tOut
         put "the virtual port " & quote & kMdsPortName & quote & " was made, but did not come back as an input" into sNoCable
      end if
   else
      put midiLastError() into sNoCable
      if sNoCable begins with "midi: " then
         delete char 1 to 6 of sNoCable
      end if
   end if
   put mdsPortLines(midiInputPorts()) into tIns
   put mdsPortLines(midiOutputPorts()) into tOuts
   -- 2. a loopback driver's pair of ports (loopMIDI, LoopBe, IAC, Midi Through)
   if sCableIn is empty then
      put mdsFindPair(tIns, tOuts) into tPair
      if tPair is not empty then
         put midiOpenOutput(item 2 of tPair) into tOut
         put midiOpenInput(item 1 of tPair) into tH
         if tOut > 0 and tH > 0 then
            put tOut into sCableOut
            put tH into sCableIn
            put line (item 1 of tPair + 1) of tIns into sCableName
            put "driver" into sCableHow
         else
            if tOut > 0 then
               midiClose tOut
            end if
            if tH > 0 then
               midiClose tH
            end if
         end if
      end if
   end if
   if sCableIn is not empty then
      put "cable" into sMode
      scMidiStartListening sCableIn, kMdsPollMs, the long id of me
   end if
   -- 3. every other input, for someone at a keyboard (a few at most)
   repeat with tI = 1 to the number of lines of tIns
      if the number of elements of sYouIns >= kMdsYouMax then
         exit repeat
      end if
      if line tI of tIns is sCableName or line tI of tIns contains kMdsPortName then
         next repeat
      end if
      put midiOpenInput(tI - 1) into tH
      if tH > 0 then
         put tH into sYouIns[the number of elements of sYouIns + 1]
         put line tI of tIns & return after sYouNames
      end if
   end repeat
   -- 4. an output to play through when Sound is on (opened only then)
   put mdsFindSound(tOuts, sCableName) into tIndex
   if tIndex >= 0 then
      put line (tIndex + 1) of tOuts into sSoundName
   else
      put "There is no MIDI output here to play through." into sSoundWhy
   end if
end mdsConnect

-- Port names, one a line, from midiInputPorts() or midiOutputPorts() (an
-- LCB List arrives as an array numbered from 1)
function mdsPortLines pList
   local tOut, tI
   repeat with tI = 1 to the number of elements of pList
      put pList[tI] & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end mdsPortLines

-- The 0-based index of the input that is our own virtual port: ALSA lists
-- it as "RtMidi Output Client:MIDI Stage 128:0", CoreMIDI as "MIDI Stage"
function mdsFindVirtual pIns, pName
   local tI
   repeat with tI = 1 to the number of lines of pIns
      if line tI of pIns contains pName then
         return tI - 1
      end if
   end repeat
   return -1
end mdsFindVirtual

-- A loopback driver's ports: an input and an output of the same name from a
-- driver that loops (a keyboard's own in and out share a name too, and do not
-- loop, so only these). "in,out" as 0-based indexes, or empty.
function mdsFindPair pIns, pOuts
   local tI, tJ, tName
   repeat with tI = 1 to the number of lines of pIns
      put line tI of pIns into tName
      if not mdsLoops(tName) then
         next repeat
      end if
      repeat with tJ = 1 to the number of lines of pOuts
         if mdsBaseName(line tJ of pOuts) is mdsBaseName(tName) then
            return (tI - 1) & comma & (tJ - 1)
         end if
      end repeat
   end repeat
   return empty
end mdsFindPair

function mdsLoops pName
   return pName contains "loopMIDI" or pName contains "LoopBe" or pName contains "IAC Driver" or pName contains "Midi Through"
end mdsLoops

-- "loopMIDI Port 1" -> "loopMIDI Port": Windows numbers its port names
function mdsBaseName pName
   repeat while the last char of pName is a number or the last char of pName is space
      delete the last char of pName
      if pName is empty then
         exit repeat
      end if
   end repeat
   return pName
end mdsBaseName

-- The output to play through: the synth every Windows has, else the first
-- output that is not a cable (sending to a loopback would play nothing)
function mdsFindSound pOuts, pCableName
   local tI, tName
   repeat with tI = 1 to the number of lines of pOuts
      if line tI of pOuts contains "GS Wavetable" then
         return tI - 1
      end if
   end repeat
   repeat with tI = 1 to the number of lines of pOuts
      put line tI of pOuts into tName
      if tName contains kMdsPortName or mdsLoops(tName) or (pCableName is not empty and mdsBaseName(tName) is mdsBaseName(pCableName)) then
         next repeat
      end if
      return tI - 1
   end repeat
   return -1
end mdsFindSound

-- Sound on and off. On opens the output the footer names; off silences it.
command mdsSoundSwitch
   local tOuts, tIndex, tI
   if sHaveMidi is not true then
      exit mdsSoundSwitch
   end if
   if sSoundOn is true then
      mdsSilence
      put false into sSoundOn
   else if sSoundName is empty then
      put false into sSoundOn
   else
      if sSoundOut is empty or sSoundOut < 1 then
         -- found again by its whole name ("Port 1" is inside "Port 10")
         put mdsPortLines(midiOutputPorts()) into tOuts
         put -1 into tIndex
         repeat with tI = 1 to the number of lines of tOuts
            if line tI of tOuts is sSoundName then
               put tI - 1 into tIndex
               exit repeat
            end if
         end repeat
         put midiOpenOutput(max(0, tIndex)) into sSoundOut
         if tIndex < 0 then
            if sSoundOut > 0 then
               midiClose sSoundOut
            end if
            put 0 into sSoundOut
         end if
         if sSoundOut < 1 then
            put "The output " & sSoundName & " would not open: " & midiLastError() into sSoundWhy
            put empty into sSoundName
            put empty into sSoundOut
         end if
      end if
      put (sSoundOut > 0) into sSoundOn
   end if
   mdsShowStatus
   mdsShowSwitches
end mdsSoundSwitch

-- ===== The loop =============================================================

on mdsFrame pGen
   local tNow, tDt, tErr
   if pGen is not sGen or sRunning is not true then
      exit mdsFrame
   end if
   if sMyStack is not empty then
      -- A closed window stops its own show. closeStack stops it, but a
      -- close made with messages locked sends none, and the IDE keeps a
      -- closed stack in memory, where this loop would run on unseen with
      -- its ports open (after each close in OXT-Beyond 0.2.8-dp.1's IDE on
      -- Windows a frame was still queued, 2026-11-21). An invisible window
      -- is open: only a closed stack is mode 0.
      if the mode of stack sMyStack is 0 then
         mdsStop
         exit mdsFrame
      end if
      set the defaultStack to sMyStack
   end if
   put the milliseconds into tNow
   put (tNow - sClockMs) / 1000 into tDt
   put tNow into sClockMs
   -- a stall (a dialog, a drag of the window) must not jump the show ahead
   if tDt > 0.2 then
      put 0.2 into tDt
   end if
   try
      if sPaused is not true then
         mdsTick tDt
      end if
      mdsPollYou
      mdsRender
   catch tErr
      put tErr into sTrouble
   end try
   if sTrouble is not empty then
      put false into sRunning
      mdsShowStatus
      exit mdsFrame
   end if
   send ("mdsFrame" && pGen) to me in kMdsFrameMs milliseconds
end mdsFrame

command mdsTick pDt
   local tLen, tNow, tI
   add pDt to sSceneT
   -- the score: every step whose time has come, in order
   put mdsStepLen(sScene) into tLen
   put trunc(sSceneT / tLen) into tNow
   repeat with tI = sStepDone + 1 to tNow
      mdsStep tI
   end repeat
   put max(sStepDone, tNow) into sStepDone
   -- and what moves every frame
   if sScene is 3 then
      mdsKnobsNow
   else if sScene is 4 then
      mdsBendNow
   end if
   mdsDueOffs
   mdsRate
   if sTour is true and sSceneT >= item sScene of kMdsSceneSecs then
      mdsGo (sScene mod kMdsScenes) + 1
   end if
end mdsTick

-- Jump to a scene: everything sounding stops first
command mdsGo pScene
   local tI
   if pScene < 1 or pScene > kMdsScenes then
      exit mdsGo
   end if
   mdsSilence
   put pScene into sScene
   put 0 into sSceneT
   put -1 into sStepDone
   put empty into sCCLast
   put 8192 into sBendLast
   put empty into sBendTrail
   lock screen
   repeat with tI = 1 to kMdsScenes
      set the hilite of button ("mdsScene" & tI) to (tI is pScene)
   end repeat
   set the text of field "mdsAbout" to mdsAbout(pScene)
   unlock screen
end mdsGo

function mdsAbout pScene
   switch pScene
      case 1
         return "An arpeggio over C, G, A minor and F: a note on when a key goes down and a note off when it comes up, eight to a bar, with a bass note under each chord. The stage lights each key only when its message arrives."
      case 2
         return "Chords: four note-ons at once, struck softly and then hard and back. Velocity is the third byte of a note on, from 1 to 127; the stage shows it as how bright each key and each bar of the roll is."
      case 3
         return "Eight controllers at once, each a control change: mod wheel, volume, pan, expression, resonance, cutoff, reverb and chorus, under a held chord. A knob moves only when its value arrives."
      case 4
         return "A held note, bent up and down with pitch bend: a 14-bit value, 0 to 16383, sent as two 7-bit bytes, 8192 in the middle. The wheel and the curve over the roll follow what arrives."
      case 5
         return "Channel 10 is drums in General MIDI: a kick, a snare and hats. On channel 1 a program change every two bars picks another instrument: hear them with Sound on."
   end switch
   return empty
end mdsAbout

-- ===== The player ===========================================================

function mdsStepLen pScene
   switch pScene
      case 1
         return kMdsBeat / 2
      case 2
         return kMdsBeat
      case 3
         return kMdsBeat * 4
      case 4
         return kMdsBeat * 8
      case 5
         return kMdsBeat / 4
   end switch
   return kMdsBeat
end mdsStepLen

command mdsStep pStep
   switch sScene
      case 1
         mdsStepArpeggio pStep
         break
      case 2
         mdsStepChords pStep
         break
      case 3
         if pStep is 0 then
            mdsChord "48 55 64 67 71 74", 80, (item 3 of kMdsSceneSecs) - 0.4
         end if
         break
      case 4
         mdsNote 1, 69, 96, kMdsBeat * 8 - 0.1
         break
      case 5
         mdsStepDrums pStep
         break
   end switch
end mdsStep

-- Scene 1: eight notes a bar, up the chord and back, a bass note under it
command mdsStepArpeggio pStep
   local tChord, tAt, tVel
   put (pStep div 8) mod 4 + 1 into tChord
   put pStep mod 8 into tAt
   -- the downbeat loudest, the half bar next: an arpeggio that breathes
   if tAt is 0 then
      put 96 into tVel
   else if tAt is 4 then
      put 72 into tVel
   else
      put 58 into tVel
   end if
   mdsNote 1, word (tAt + 1) of mdsArp(tChord), tVel, kMdsBeat / 2 - 0.03
   if tAt is 0 then
      mdsNote 1, word tChord of kMdsBass, 84, kMdsBeat * 4 - 0.1
   end if
end mdsStepArpeggio

function mdsArp pChord
   set the itemDelimiter to ";"
   get item pChord of kMdsArps
   set the itemDelimiter to comma
   return it
end mdsArp

-- Scene 2: a chord every two beats, its velocity swelling and falling
command mdsStepChords pStep
   local tVoicing, tVel
   if pStep mod 2 is 1 then
      exit mdsStepChords
   end if
   set the itemDelimiter to ";"
   put item ((pStep div 2) mod 4 + 1) of kMdsVoicings into tVoicing
   set the itemDelimiter to comma
   put 20 + round(107 * (0.5 - 0.5 * cos(2 * pi * pStep / 16))) into tVel
   mdsChord tVoicing, tVel, kMdsBeat * 2 - 0.08
   mdsNote 1, (word 1 of tVoicing) - 12, max(30, tVel - 20), kMdsBeat * 2 - 0.08
end mdsStepChords

-- Scene 3: eight controllers, each sent only when its 7-bit value changes
command mdsKnobsNow
   local tT, tI, tCC, tV
   put sSceneT into tT
   repeat with tI = 1 to 8
      put item tI of kMdsKnobCCs into tCC
      switch tI
         case 1
            put 63.5 + 63.5 * sin(tT * 1.3) into tV
            break
         case 2
            put 100 + 20 * sin(tT * 0.7) into tV
            break
         case 3
            put 64 + 60 * sin(tT * 0.9) into tV
            break
         case 4
            put 90 + 37 * sin(tT * 0.5 + 1) into tV
            break
         case 5
            put 64 + 50 * sin(tT * 0.35) into tV
            break
         case 6
            put 64 + 60 * sin(tT * 1.7) into tV
            break
         case 7
            put 40 + 30 * sin(tT * 0.25) into tV
            break
         default
            put 30 + 25 * sin(tT * 0.45 + 2) into tV
      end switch
      put max(0, min(127, round(tV))) into tV
      if tV is not sCCLast[tCC] then
         put tV into sCCLast[tCC]
         mdsOut 176, tCC, tV
      end if
   end repeat
end mdsKnobsNow

-- Scene 4: the bend, every frame it changes
command mdsBendNow
   local tV
   put 8192 + round(8191 * 0.8 * sin(sSceneT * 1.6)) into tV
   put max(0, min(16383, tV)) into tV
   if tV is not sBendLast then
      put tV into sBendLast
      mdsOut 224, tV mod 128, tV div 128
   end if
end mdsBendNow

-- Scene 5: sixteen steps a bar on channel 10, and on channel 1 a program
-- change every two bars and a riff in the new sound
command mdsStepDrums pStep
   local tAt, tBar, tProgram, tWord
   put pStep mod 16 into tAt
   put pStep div 16 into tBar
   if tAt is 0 or tAt is 6 or tAt is 8 or tAt is 11 then
      if tAt is 11 then
         mdsNote 10, 36, 90, 0.1
      else
         mdsNote 10, 36, 112, 0.1
      end if
   end if
   if tAt is 4 or tAt is 12 then
      mdsNote 10, 38, 104, 0.1
   end if
   if tAt mod 2 is 0 and tAt is not 14 then
      if tAt mod 4 is 0 then
         mdsNote 10, 42, 74, 0.08
      else
         mdsNote 10, 42, 54, 0.08
      end if
   end if
   if tAt is 14 then
      mdsNote 10, 46, 70, 0.2
   end if
   if tAt is 0 and tBar mod 2 is 0 then
      put item ((tBar div 2) mod 5 + 1) of kMdsScenePrograms into tProgram
      mdsOut 192, tProgram, empty
   end if
   if tAt is 0 or tAt is 3 or tAt is 6 or tAt is 10 then
      -- the riff's four notes fall on steps 0, 3, 6 and 10
      if tAt is 0 then
         put 1 into tWord
      else if tAt is 3 then
         put 2 into tWord
      else if tAt is 6 then
         put 3 into tWord
      else
         put 4 into tWord
      end if
      set the itemDelimiter to ";"
      get item (tBar mod 4 + 1) of kMdsRiff
      set the itemDelimiter to comma
      mdsNote 1, word tWord of it, 92, kMdsBeat * 0.7
   end if
end mdsStepDrums

-- Several notes at once
command mdsChord pNotes, pVel, pDur
   local tNote
   repeat for each word tNote in pNotes
      mdsNote 1, tNote, pVel, pDur
   end repeat
end mdsChord

-- A note on now and its note off pDur seconds later. A note still sounding
-- is let go first, so no note is ever left on.
command mdsNote pCh, pNote, pVel, pDur
   local tAt
   put lineOffset("|" & pCh & "|" & pNote & "|", sOffs) into tAt
   if tAt > 0 then
      delete line tAt of sOffs
      mdsOut 127 + pCh, pNote, 0
   end if
   mdsOut 143 + pCh, pNote, pVel
   put (sSceneT + pDur) & "|" & pCh & "|" & pNote & "|" & return after sOffs
end mdsNote

command mdsDueOffs
   local tLine, tKeep, tDue, tCh, tNote
   repeat for each line tLine in sOffs
      -- the "|" items are read first: a chunk is read with the delimiter
      -- set when it is EVALUATED (artnetxt's light board learnt it)
      set the itemDelimiter to "|"
      put item 1 of tLine into tDue
      put item 2 of tLine into tCh
      put item 3 of tLine into tNote
      set the itemDelimiter to comma
      if tDue <= sSceneT then
         mdsOut 127 + tCh, tNote, 0
      else
         put tLine & return after tKeep
      end if
   end repeat
   put tKeep into sOffs
end mdsDueOffs

-- Everything that sounds stops: each note's own note off, then "all notes
-- off" and "reset all controllers" on the two channels it plays, and the
-- bend back to the middle
command mdsSilence
   local tLine, tCh, tNote
   repeat for each line tLine in sOffs
      set the itemDelimiter to "|"
      put item 2 of tLine into tCh
      put item 3 of tLine into tNote
      set the itemDelimiter to comma
      mdsOut 127 + tCh, tNote, 0
   end repeat
   put empty into sOffs
   if sScene is 3 then
      mdsOut 176, 121, 0
   end if
   if sScene is 4 and sBendLast is not 8192 then
      mdsOut 224, 0, 64
      put 8192 into sBendLast
   end if
   mdsOut 176, 123, 0
   mdsOut 185, 123, 0
end mdsSilence

-- One message from the player. The bytes are built here, shown, and sent
-- with midixt's own senders (midiNoteOn, midiControlChange, ...) through the
-- cable, or read back with midiDecode where there is none; with Sound on the
-- same bytes go to the output too, with midiSend. pD2 empty: two bytes.
command mdsOut pStatus, pD1, pD2
   local tBytes, tKind, tCh, tEvent
   -- numToByte WRAPS (256 is 0) and makes a fraction whole by where it came
   -- from (the suite's engine notes, 2.13): every byte is made whole and
   -- held in range first
   put max(0, min(127, round(pD1))) into pD1
   if pD2 is not empty then
      put max(0, min(127, round(pD2))) into pD2
   end if
   put numToByte(pStatus) & numToByte(pD1) into tBytes
   if pD2 is not empty then
      put numToByte(pD2) after tBytes
   end if
   put pStatus div 16 into tKind
   put pStatus mod 16 + 1 into tCh
   mdsLogSent tBytes, tKind, tCh, pD1, pD2
   if sMode is "none" then
      exit mdsOut
   end if
   add 1 to sSent
   if sMode is "cable" then
      switch tKind
         case 9
            midiNoteOn sCableOut, tCh, pD1, pD2
            put the milliseconds into sSentAt[tCh & "," & pD1]
            break
         case 8
            midiNoteOff sCableOut, tCh, pD1, pD2
            break
         case 11
            midiControlChange sCableOut, tCh, pD1, pD2
            break
         case 12
            midiProgramChange sCableOut, tCh, pD1
            break
         case 14
            midiPitchBend sCableOut, tCh, pD1 + pD2 * 128
            break
         default
            midiSend sCableOut, tBytes
      end switch
   else
      put midiDecode(tBytes) into tEvent
      mdsArrive tEvent, "player"
   end if
   if sSoundOn is true and sSoundOut > 0 then
      midiSend sSoundOut, tBytes
   end if
end mdsOut

-- What the player sent, newest last: the bytes in hex, then what they mean
command mdsLogSent pBytes, pKind, pCh, pD1, pD2
   local tLine
   put mdsHex(pBytes) into tLine
   repeat while the number of chars of tLine < 10
      put space after tLine
   end repeat
   switch pKind
      case 9
         put "note on  " & format("%2d", pCh) & "  " & mdsNoteName(pD1, pCh) & " " & pD2 after tLine
         break
      case 8
         put "note off " & format("%2d", pCh) & "  " & mdsNoteName(pD1, pCh) after tLine
         break
      case 11
         put "control  " & format("%2d", pCh) & "  " & pD1 & " = " & pD2 after tLine
         break
      case 12
         put "program  " & format("%2d", pCh) & "  " & pD1 + 1 after tLine
         break
      case 14
         put "bend     " & format("%2d", pCh) & "  " & pD1 + pD2 * 128 after tLine
         break
   end switch
   put tLine & return after sSentLog
   if the number of lines of sSentLog > kMdsSentLines then
      delete line 1 to (the number of lines of sSentLog - kMdsSentLines) of sSentLog
   end if
end mdsLogSent

function mdsHex pBytes
   local tOut, tByte
   repeat for each byte tByte in pBytes
      put format("%02X", byteToNum(tByte)) & space after tOut
   end repeat
   delete the last char of tOut
   return tOut
end mdsHex

-- 60 -> "C4"; on channel 10 a drum's name
function mdsNoteName pNote, pCh
   if pCh is 10 then
      switch pNote
         case 36
            return "kick"
         case 38
            return "snare"
         case 42
            return "closed hat"
         case 46
            return "open hat"
      end switch
   end if
   return word ((pNote mod 12) + 1) of "C C# D D# E F F# G G# A A# B" & ((pNote div 12) - 1)
end mdsNoteName

-- ===== The stage: what arrives ==============================================

-- midi-helpers' listener sends these, one per message the cable carried
on scNoteOn pChannel, pNote, pVelocity
   mdsArriveParts "noteOn", pChannel, pNote, pVelocity
end scNoteOn

on scNoteOff pChannel, pNote, pVelocity
   mdsArriveParts "noteOff", pChannel, pNote, pVelocity
end scNoteOff

on scMidiCC pChannel, pController, pValue
   mdsArriveParts "controlChange", pChannel, pController, pValue
end scMidiCC

on scProgramChange pChannel, pProgram
   mdsArriveParts "programChange", pChannel, pProgram, 0
end scProgramChange

on scPitchBend pChannel, pValue14
   mdsArriveParts "pitchBend", pChannel, pValue14 mod 128, pValue14 div 128
end scPitchBend

on scMidiOther pKind, pChannel, pEvent
   mdsArrive pEvent, "player"
end scMidiOther

command mdsArriveParts pKind, pCh, pD1, pD2
   local tEvent, tErr
   put pKind into tEvent["kind"]
   put pCh into tEvent["channel"]
   put pD1 into tEvent["data1"]
   put pD2 into tEvent["data2"]
   if pKind is "pitchBend" then
      put pD1 + pD2 * 128 into tEvent["value14"]
   end if
   -- A throw here would stop the listener without a word (midi-helpers
   -- hands it on to the engine): it is kept instead, and the next frame
   -- stops the show and says what it was. Nothing here touches a control,
   -- so the listener's timer needs no stack of its own.
   try
      mdsArrive tEvent, "player"
   catch tErr
      if sTrouble is empty then
         put tErr into sTrouble
      end if
   end try
end mdsArriveParts

-- The other inputs, read straight with midiPoll (which gives each message's
-- bytes and timing too)
command mdsPollYou
   local tH, tEvents, tEvent
   repeat for each element tH in sYouIns
      put midiPoll(tH) into tEvents
      repeat for each element tEvent in tEvents
         mdsArrive tEvent, "you"
      end repeat
   end repeat
end mdsPollYou

-- One message reaches the stage: the stage's whole state comes from here
command mdsArrive pEvent, pWho
   local tKind, tCh, tD1, tD2, tNow, tSlot, tLine
   put pEvent["kind"] into tKind
   put pEvent["channel"] into tCh
   put pEvent["data1"] into tD1
   put pEvent["data2"] into tD2
   put the milliseconds into tNow
   if pWho is "you" then
      add 1 to sYouRead
   else
      add 1 to sRead
   end if
   if tCh >= 1 and tCh <= 16 then
      put 1 into sGlow[tCh]
      put pWho into sGlow[tCh & "who"]
   end if
   switch tKind
      case "noteOn"
         if tCh is 10 then
            mdsHitAt tD1, tD2, pWho, tNow
         else
            put tD2 into sKeyVel[tD1]
            put pWho into sKeyWho[tD1]
            put tD1 into sHeld
            mdsBarOn tD1, tD2, tCh, pWho, tNow
         end if
         if pWho is "player" and sSentAt[tCh & "," & tD1] is not empty then
            add tNow - sSentAt[tCh & "," & tD1] to sLagSum
            add 1 to sLagN
            delete variable sSentAt[tCh & "," & tD1]
         end if
         put "noteOn   " & format("%2d", tCh) & "  " & mdsNoteName(tD1, tCh) & " " & tD2 into tLine
         break
      case "noteOff"
         if tCh is not 10 then
            put 0 into sKeyVel[tD1]
            mdsBarOff tD1, tCh, pWho, tNow
         end if
         put "noteOff  " & format("%2d", tCh) & "  " & mdsNoteName(tD1, tCh) into tLine
         break
      case "controlChange"
         put tD2 into sCCVal[tD1]
         if tD1 is 121 then
            -- reset all controllers: each back to where a synth starts it
            put empty into sCCVal
            put 100 into sCCVal[7]
            put 64 into sCCVal[10]
            put 127 into sCCVal[11]
            put 8192 into sBend
         else if tD1 is 123 then
            -- all notes off
            repeat for each key tSlot in sKeyVel
               if sKeyWho[tSlot] is pWho then
                  put 0 into sKeyVel[tSlot]
               end if
            end repeat
            mdsBarsOff pWho, tCh, tNow
         end if
         put "control  " & format("%2d", tCh) & "  " & tD1 & " = " & tD2 into tLine
         break
      case "programChange"
         put tD1 into sProgram
         put tCh into sProgramCh
         put "program  " & format("%2d", tCh) & "  " & tD1 + 1 into tLine
         break
      case "pitchBend"
         put pEvent["value14"] into sBend
         put "bend     " & format("%2d", tCh) & "  " & pEvent["value14"] into tLine
         break
      default
         put tKind & "  " & mdsHex(pEvent["bytes"]) into tLine
   end switch
   if pWho is "you" then
      put "you  " & tLine & "  +" & round(pEvent["delta"] * 1000) & " ms" into tLine
   end if
   -- the wire shows the player's notes and the knobs it moved, never a flood
   -- of one controller: the last line of the same kind is replaced
   if tKind is "pitchBend" and the last line of sWireLog begins with "bend" then
      put tLine into the last line of sWireLog
   else
      put tLine & return after sWireLog
   end if
   if the number of lines of sWireLog > kMdsWireLines then
      delete line 1 to (the number of lines of sWireLog - kMdsWireLines) of sWireLog
   end if
end mdsArrive

-- A bar of the piano roll for a note that began, from the pool (the oldest
-- goes when they are all in use)
command mdsBarOn pNote, pVel, pCh, pWho, pNow
   add 1 to sNextBar
   if sNextBar > kMdsBars then
      put 1 into sNextBar
   end if
   put pNote into sBar[sNextBar]["note"]
   put pVel into sBar[sNextBar]["vel"]
   put pCh into sBar[sNextBar]["ch"]
   put pWho into sBar[sNextBar]["who"]
   put pNow into sBar[sNextBar]["on"]
   put empty into sBar[sNextBar]["off"]
   put true into sBar[sNextBar]["new"]
end mdsBarOn

command mdsBarOff pNote, pCh, pWho, pNow
   local tI, tN
   -- the newest bar of this note still sounding
   repeat with tI = 0 to kMdsBars - 1
      put ((sNextBar - tI - 1 + kMdsBars) mod kMdsBars) + 1 into tN
      if sBar[tN]["note"] is pNote and sBar[tN]["ch"] is pCh and sBar[tN]["who"] is pWho and sBar[tN]["off"] is empty and sBar[tN]["on"] is not empty then
         put pNow into sBar[tN]["off"]
         exit repeat
      end if
   end repeat
end mdsBarOff

command mdsBarsOff pWho, pCh, pNow
   local tI
   repeat with tI = 1 to kMdsBars
      if sBar[tI]["who"] is pWho and sBar[tI]["off"] is empty and sBar[tI]["on"] is not empty then
         put pNow into sBar[tI]["off"]
      end if
   end repeat
end mdsBarsOff

-- A drum hit in the roll's lane: kick at the bottom, snare, hats at the top
command mdsHitAt pNote, pVel, pWho, pNow
   add 1 to sNextHit
   if sNextHit > kMdsHits then
      put 1 into sNextHit
   end if
   if pNote <= 36 then
      put 3 into sHit[sNextHit]["row"]
   else if pNote <= 40 then
      put 2 into sHit[sNextHit]["row"]
   else
      put 1 into sHit[sNextHit]["row"]
   end if
   put pVel into sHit[sNextHit]["vel"]
   put pWho into sHit[sNextHit]["who"]
   put pNow into sHit[sNextHit]["on"]
end mdsHitAt

-- ===== The picture ==========================================================

command mdsRender
   local tNow, tI, tX1, tX2, tY, tColour, tP, tShown, tV, tCC, tR, tPx
   add 1 to sFrames
   put the milliseconds into tNow
   put (kMdsRollR - kMdsRollL - 8) / kMdsRollSecs into tPx
   lock screen
   -- the keys: only those whose state changed
   repeat with tP = kMdsLow to kMdsHigh
      put sKeyVel[tP] & sKeyWho[tP] into tShown
      if tShown is not sKeyShown[tP] then
         put tShown into sKeyShown[tP]
         if sKeyVel[tP] > 0 then
            if sKeyWho[tP] is "you" then
               put kMdsYou into tColour
            else
               put kMdsAccent into tColour
            end if
            put mdsMix(mdsKeyBase(tP), tColour, 0.45 + 0.55 * sKeyVel[tP] / 127) into tColour
         else
            put mdsKeyBase(tP) into tColour
         end if
         set the backgroundColor of graphic ("mdsKey" & tP) to tColour
      end if
   end repeat
   -- the roll: each bar from its note on to its note off (or now)
   repeat with tI = 1 to kMdsBars
      if sBar[tI]["on"] is empty then
         next repeat
      end if
      if sBar[tI]["off"] is empty then
         put kMdsRollR - 4 into tX2
      else
         put kMdsRollR - 4 - (tNow - sBar[tI]["off"]) / 1000 * tPx into tX2
      end if
      put kMdsRollR - 4 - (tNow - sBar[tI]["on"]) / 1000 * tPx into tX1
      if tX2 < kMdsRollL + 2 then
         put empty into sBar[tI]["on"]
         set the visible of graphic ("mdsBar" & tI) to false
         next repeat
      end if
      put mdsNoteY(sBar[tI]["note"]) into tY
      set the rect of graphic ("mdsBar" & tI) to round(max(kMdsRollL + 2, tX1)), tY - 2, round(max(tX1 + 3, tX2)), tY + 2
      if sBar[tI]["new"] is true then
         put false into sBar[tI]["new"]
         if sBar[tI]["who"] is "you" then
            put kMdsYou into tColour
         else
            put kMdsAccent into tColour
         end if
         set the backgroundColor of graphic ("mdsBar" & tI) to mdsMix(kMdsOff, tColour, 0.35 + 0.65 * sBar[tI]["vel"] / 127)
         set the visible of graphic ("mdsBar" & tI) to true
      end if
   end repeat
   -- the drum lane
   repeat with tI = 1 to kMdsHits
      if sHit[tI]["on"] is empty then
         next repeat
      end if
      put kMdsRollR - 8 - (tNow - sHit[tI]["on"]) / 1000 * tPx into tX1
      if tX1 < kMdsRollL + 2 then
         put empty into sHit[tI]["on"]
         set the visible of graphic ("mdsHit" & tI) to false
         next repeat
      end if
      put kMdsDrumT + 2 + (sHit[tI]["row"] - 1) * 10 into tY
      set the rect of graphic ("mdsHit" & tI) to round(tX1), tY, round(tX1) + 7, tY + 7
      if the visible of graphic ("mdsHit" & tI) is false then
         if sHit[tI]["who"] is "you" then
            put kMdsYou into tColour
         else
            put kMdsAccent into tColour
         end if
         set the backgroundColor of graphic ("mdsHit" & tI) to mdsMix(kMdsOff, tColour, 0.4 + 0.6 * sHit[tI]["vel"] / 127)
         set the visible of graphic ("mdsHit" & tI) to true
      end if
   end repeat
   -- the bend's curve over the roll (scene 4)
   mdsRenderBend tNow, tPx
   -- the knobs: only those whose value changed
   repeat with tI = 1 to 8
      put item tI of kMdsKnobCCs into tCC
      put sCCVal[tCC] into tV
      if tV is not sCCShown[tCC] then
         put tV into sCCShown[tCC]
         if tV is empty then
            put 0 into tV
         end if
         set the arcAngle of graphic ("mdsKnobArc" & tI) to max(1, round(tV / 127 * 270))
         set the startAngle of graphic ("mdsKnobArc" & tI) to 225 - round(tV / 127 * 270)
         set the text of field ("mdsKnobVal" & tI) to sCCVal[tCC]
      end if
   end repeat
   -- the wheels
   put kMdsWheelT + 6 + (1 - sBend / 16383) * (kMdsWheelB - kMdsWheelT - 12) into tY
   set the rect of graphic "mdsBendThumb" to 38, round(tY) - 6, 72, round(tY) + 6
   put kMdsWheelT + 6 + (1 - sCCVal[1] / 127) * (kMdsWheelB - kMdsWheelT - 12) into tY
   set the rect of graphic "mdsModThumb" to 78, round(tY) - 6, 112, round(tY) + 6
   -- the program, and a light per channel
   if sProgram is empty then
      mdsSetText "mdsProgram", "no program change yet"
      mdsSetText "mdsProgramCh", empty
   else
      set the itemDelimiter to ";"
      mdsSetText "mdsProgram", "Program " & (sProgram + 1) & "   " & item (sProgram + 1) of kMdsPrograms
      set the itemDelimiter to comma
      mdsSetText "mdsProgramCh", "the last program change that arrived, on channel " & sProgramCh
   end if
   repeat with tI = 1 to 16
      if sGlow[tI] > 0 or sGlow[tI & "shown"] > 0 then
         if sGlow[tI & "who"] is "you" then
            put kMdsYou into tColour
         else
            put kMdsAccent into tColour
         end if
         set the backgroundColor of graphic ("mdsLed" & tI) to mdsMix(kMdsOff, tColour, sGlow[tI])
         put sGlow[tI] into sGlow[tI & "shown"]
         put max(0, sGlow[tI] - 0.12) into sGlow[tI]
      end if
   end repeat
   -- words
   mdsSetText "mdsWire", sWireLog
   mdsSetText "mdsSent", sSentLog
   put sSent & " sent   " & sRead & " read" into tR
   if sYouRead > 0 then
      put "   " & sYouRead & " yours" after tR
   end if
   if sLagN > 0 then
      put "   " & round(sLagSum / sLagN) & " ms send to stage" after tR
   else
      put "   " & sRate & " a second" after tR
   end if
   mdsSetText "mdsStats", tR
   unlock screen
end mdsRender

command mdsRenderBend pNow, pPx
   local tPoints, tLine, tX, tY, tKeep
   if sScene is not 4 then
      if the visible of graphic "mdsBendLine" then
         set the visible of graphic "mdsBendLine" to false
      end if
      exit mdsRenderBend
   end if
   if sKeyVel[sHeld] > 0 then
      put pNow & comma & (sHeld + (sBend - 8192) / 8192 * 2) & return after sBendTrail
   end if
   repeat for each line tLine in sBendTrail
      put kMdsRollR - 4 - (pNow - item 1 of tLine) / 1000 * pPx into tX
      if tX < kMdsRollL + 2 then
         next repeat
      end if
      put tLine & return after tKeep
      put mdsNoteY(item 2 of tLine) into tY
      put round(tX) & comma & round(tY) & return after tPoints
   end repeat
   put tKeep into sBendTrail
   if the number of lines of tPoints >= 2 then
      set the points of graphic "mdsBendLine" to tPoints
      set the visible of graphic "mdsBendLine" to true
   end if
end mdsRenderBend

-- A note's height on the roll (any note: one out of the keyboard's range
-- sits on its edge)
function mdsNoteY pNote
   put max(kMdsLow, min(kMdsHigh, pNote)) into pNote
   return round(kMdsDrumT - 6 - (pNote - kMdsLow) * (kMdsDrumT - kMdsRollT - 14) / (kMdsHigh - kMdsLow))
end mdsNoteY

function mdsIsBlack pNote
   return (pNote mod 12) is among the items of "1,3,6,8,10"
end mdsIsBlack

function mdsKeyBase pNote
   if mdsIsBlack(pNote) then
      return kMdsBlack
   end if
   return kMdsWhite
end mdsKeyBase

-- Only touch a field when its words change: a field redrawn thirty times a
-- second for nothing costs more than everything else in a frame
command mdsSetText pField, pText
   if the text of field pField is not pText then
      set the text of field pField to pText
   end if
end mdsSetText

-- Messages read a second, over the last second
command mdsRate
   local tNow
   put the milliseconds into tNow
   if sRateMark is empty or tNow - sRateMark >= 1000 then
      if sRateMark is not empty then
         put round((sRead - sRateBase) * 1000 / (tNow - sRateMark)) into sRate
      end if
      put tNow into sRateMark
      put sRead into sRateBase
   end if
end mdsRate

command mdsResetStage
   put 0 into sSent
   put 0 into sRead
   put 0 into sYouRead
   put 0 into sLagSum
   put 0 into sLagN
   put 0 into sRate
   put empty into sRateMark
   put empty into sOffs
   put empty into sSentLog
   put empty into sSentAt
   put empty into sWireLog
   put empty into sKeyVel
   put empty into sKeyWho
   put empty into sKeyShown
   put empty into sBar
   put 0 into sNextBar
   put empty into sHit
   put 0 into sNextHit
   put empty into sCCVal
   put empty into sCCShown
   put 8192 into sBend
   put empty into sProgram
   put empty into sProgramCh
   put empty into sGlow
   put empty into sBendTrail
   put empty into sHeld
end mdsResetStage

-- "r,g,b" between two colours, pT from 0 to 1
function mdsMix pA, pB, pT
   local tI, tOut
   if pT is not a number then
      put 0 into pT
   end if
   put max(0, min(1, pT)) into pT
   repeat with tI = 1 to 3
      put round(item tI of pA + (item tI of pB - item tI of pA) * pT) & comma after tOut
   end repeat
   delete the last char of tOut
   return tOut
end mdsMix

-- ===== What is missing, and how it went =====================================

-- The footer is ONE line, 1068 pixels at 11 points: each sentence below
-- was measured to fit it with room to spare (a long reason in the library's
-- own words goes in its tooltip, and the stage's panel shows what is
-- missing in full)
command mdsShowStatus
   local tText, tMissing, tSound, tTip
   if sSoundOn is true then
      put " Sound plays through " & sSoundName & "." into tSound
   else if sSoundName is not empty then
      put " Press Sound to hear it through " & sSoundName & "." into tSound
   else if sSoundWhy is not empty then
      put " " & sSoundWhy into tSound
   end if
   if sTrouble is not empty then
      put "Something went wrong and the show stopped: " & line 1 of sTrouble & ". Close the stack and open it again." into tText
      put tText into tMissing
      put sTrouble into tTip
   else if sHaveMidi is not true then
      put "Missing: midixt. Install it (Tools > Extension Manager) and open this stack again; until then nothing is sent." into tText
      put "This demo needs midixt, the suite's MIDI extension." & return & sWhyNot & return & "Install it, then open this stack again." into tMissing
      put sWhyNot into tTip
   else if sMode is "cable" and sCableHow is "virtual" then
      put "Nothing to set up: the player sends through a virtual port, " & quote & kMdsPortName & quote & ", and the stage reads it back from your MIDI service." & tSound into tText
   else if sMode is "cable" then
      put "The player sends through " & sCableName & ", a loopback, and the stage reads it back with midiPoll." & tSound into tText
   else
      put "No MIDI cable here: the stage decodes each message itself." & mdsCableHint(sNoCable) & tSound into tText
      put "No MIDI cable: " & sNoCable into tTip
   end if
   lock screen
   set the text of field "mdsStatus" to tText
   set the tooltip of field "mdsStatus" to tTip
   if tMissing is empty then
      set the foregroundColor of field "mdsStatus" to kMdsSoft
      set the visible of field "mdsMissing" to false
   else
      set the foregroundColor of field "mdsStatus" to kMdsAccent
      set the text of field "mdsMissing" to tMissing
      set the visible of field "mdsMissing" to true
   end if
   switch sMode
      case "cable"
         set the text of field "mdsStageCap" to "THE STAGE   reads " & sCableName & " with midiPoll"
         set the text of field "mdsWireCap" to "ON THE WIRE   what midiPoll read"
         set the text of field "mdsPlayerCap" to "THE PLAYER   sent through the cable"
         break
      case "decode"
         set the text of field "mdsStageCap" to "THE STAGE   reads each message with midiDecode (no cable here)"
         set the text of field "mdsWireCap" to "ON THE WIRE   what midiDecode read"
         set the text of field "mdsPlayerCap" to "THE PLAYER   the messages it built"
         break
      default
         set the text of field "mdsStageCap" to "THE STAGE"
         set the text of field "mdsWireCap" to "ON THE WIRE"
         set the text of field "mdsPlayerCap" to "THE PLAYER   what it would send"
   end switch
   if the number of lines of sYouNames > 0 then
      set the text of field "mdsYouCap" to "and your playing, in blue, from " & the number of lines of sYouNames & " MIDI input(s)"
   else
      set the text of field "mdsYouCap" to "plug in a MIDI keyboard and your notes show in blue"
   end if
   unlock screen
end mdsShowStatus

-- What would make a cable here, from why there is none (the library's words)
function mdsCableHint pWhy
   if pWhy contains "no virtual ports" then
      -- Windows MM: RtMidi cannot make a virtual port there
      return " A loopMIDI port makes one."
   else if pWhy contains "backend init failed" then
      if the platform is "Linux" then
         return " The ALSA sequencer (snd-seq) makes one."
      end if
      return " A running MIDI service makes one."
   else if pWhy contains "did not come back" then
      return " (Its virtual port did not come back as an input.)"
   else if pWhy is not empty then
      return " (" & pWhy & ")"
   end if
   return empty
end mdsCableHint

command mdsShowSwitches
   lock screen
   set the hilite of button "mdsTour" to (sTour is true)
   set the hilite of button "mdsPause" to (sPaused is true)
   set the hilite of button "mdsSound" to (sSoundOn is true)
   unlock screen
end mdsShowSwitches

-- ===== For the tests ========================================================

-- Take the clock out of the loop's hands: the test steps it
command mdsTestBegin
   put false into sRunning
   add 1 to sGen
   put false into sTour
end mdsTestBegin

-- Move the show on by pSeconds, a frame at a time, drawing each frame
command mdsTestStep pSeconds
   local tSteps, tI
   put max(1, round(pSeconds * 1000 / kMdsFrameMs)) into tSteps
   repeat with tI = 1 to tSteps
      -- what mdsFrame does, in the same order
      if sPaused is not true then
         mdsTick kMdsFrameMs / 1000
      end if
      -- the listener's own poll, by hand: called with no generation it
      -- reads once and arms no timer (midi-helpers says so)
      if sMode is "cable" then
         scMidiPollAndDispatch sCableIn
      end if
      mdsPollYou
      mdsRender
   end repeat
end mdsTestStep

-- Two open ports to use as the cable (the tests' mock loopback)
command mdsTestCable pIn, pOut
   scMidiStopListening
   put pIn into sCableIn
   put pOut into sCableOut
   put "the test's cable" into sCableName
   put "test" into sCableHow
   put "cable" into sMode
   scMidiStartListening sCableIn, kMdsPollMs, the long id of me
   mdsShowStatus
end mdsTestCable

function mdsState
   local tState, tP, tI
   put sScene into tState["scene"]
   put sSceneT into tState["sceneTime"]
   put sFrames into tState["frames"]
   put sSent into tState["sent"]
   put sRead into tState["read"]
   put sYouRead into tState["youRead"]
   put sHaveMidi into tState["haveMidi"]
   put sWhyNot into tState["whyNot"]
   put sMode into tState["mode"]
   put sCableName into tState["cableName"]
   put sCableHow into tState["cableHow"]
   put sNoCable into tState["noCable"]
   put sYouNames into tState["youNames"]
   put sSoundName into tState["soundName"]
   put sSoundOn into tState["soundOn"]
   put sSoundOut into tState["soundOut"]
   put sTrouble into tState["trouble"]
   put sRunning into tState["running"]
   put sPaused into tState["paused"]
   put sProgram into tState["program"]
   put sBend into tState["bend"]
   put sOffs into tState["offs"]
   put sSentLog into tState["sentLog"]
   put sWireLog into tState["log"]
   put sLagN into tState["lagN"]
   put sLagSum into tState["lagSum"]
   repeat with tP = kMdsLow to kMdsHigh
      if sKeyVel[tP] > 0 then
         put tP & ":" & sKeyVel[tP] & ":" & sKeyWho[tP] & comma after tState["keys"]
      end if
   end repeat
   repeat with tI = 1 to 8
      put sCCVal[item tI of kMdsKnobCCs] & comma after tState["knobs"]
   end repeat
   repeat with tI = 1 to kMdsBars
      if sBar[tI]["on"] is not empty then
         add 1 to tState["bars"]
      end if
   end repeat
   repeat with tI = 1 to kMdsHits
      if sHit[tI]["on"] is not empty then
         add 1 to tState["hits"]
      end if
   end repeat
   return tState
end mdsState

-- ===== Building the window ==================================================

command mdsBuild
   local tI, tX, tY, tP, tWhite, tCx, tWasQuiet
   -- Built with messages locked. In the IDE every scripted create, rename
   -- and delete sends an engine message that runs the IDE's own script
   -- (the suite's engine note 5.15): built with them unlocked, this window
   -- held OXT-Beyond 0.2.8-dp.1's IDE on Windows for 81 seconds as it
   -- opened (2026-11-21). Nothing here asks a question or needs an engine
   -- message, and the caller's lock is given back at the end.
   put the lockMessages into tWasQuiet
   lock screen
   lock messages
   mdsClear
   set the width of this stack to kMdsW
   set the height of this stack to kMdsH
   -- Then centred on the screen. A new stack is 32,32,288,288 and a size
   -- set keeps its centre (engine note 5.18), so 1100 wide put its left at
   -- -390: the window opened 390 pixels past the screen's edge on Windows
   -- (the same day). start-here centres a window it opens; one opened any
   -- other way now centres itself.
   set the loc of this stack to the screenLoc
   set the resizable of this stack to false
   set the label of this stack to "MIDI Stage - OXT-Beyond"
   set the backgroundColor of this stack to kMdsPage
   set the foregroundColor of this stack to kMdsInk
   set the textSize of this stack to 13
   set the backgroundColor of this card to kMdsPage
   set the foregroundColor of this card to kMdsInk

   -- the header: OXT-Beyond, the demo's name, what it does, who made it
   mdsLabel "mdsBrand", "OXT-BEYOND", 11, kMdsAccent, "bold", 20, 6, 400, 27
   mdsLabel "mdsTitle", "MIDI Stage", 22, kMdsInk, "bold", 20, 22, 560, 59
   mdsLabel "mdsSub", "Realtime MIDI from xTalk with midixt: a player and a stage, every note, knob and bend drawn as it arrives.", 12, kMdsSoft, "plain", 20, 56, 900, 78
   mdsLabel "mdsByline", "by Seth Morrow", 12, kMdsSoft, "plain", 880, 30, kMdsSideR, 52
   set the textAlign of field "mdsByline" to "right"

   -- the stage: the roll and the keyboard
   mdsRect "mdsStage", kMdsPanel, kMdsStageL, kMdsStageT, kMdsStageR, kMdsStageB
   mdsLabel "mdsStageCap", "THE STAGE", 11, kMdsAccent, "bold", 30, 86, 766, 107
   mdsRect "mdsRoll", kMdsWell, kMdsRollL, kMdsRollT, kMdsRollR, kMdsRollB
   mdsRect "mdsDrumLane", "17,20,30", kMdsRollL, kMdsDrumT, kMdsRollR, kMdsRollB
   mdsLabel "mdsDrumTag", "drums, channel 10", 9, kMdsSoft, "plain", kMdsRollL + 4, kMdsRollB - 18, kMdsRollL + 140, kMdsRollB - 2
   mdsRect "mdsNowLine", kMdsLine, kMdsRollR - 4, kMdsRollT + 4, kMdsRollR - 3, kMdsRollB - 4
   repeat with tI = 1 to kMdsBars
      mdsRect "mdsBar" & tI, kMdsAccent, 0, 0, 4, 4
      set the visible of graphic ("mdsBar" & tI) to false
   end repeat
   repeat with tI = 1 to kMdsHits
      mdsRect "mdsHit" & tI, kMdsAccent, 0, 0, 7, 7
      set the visible of graphic ("mdsHit" & tI) to false
   end repeat
   create graphic "mdsBendLine"
   set the style of graphic "mdsBendLine" to "polygon"
   set the opaque of graphic "mdsBendLine" to false
   set the lineSize of graphic "mdsBendLine" to 2
   set the foregroundColor of graphic "mdsBendLine" to kMdsInk
   set the backgroundColor of graphic "mdsBendLine" to kMdsInk
   set the points of graphic "mdsBendLine" to "40,120" & return & "41,120"
   set the visible of graphic "mdsBendLine" to false
   -- white keys first, so the black keys draw over them
   put 0 into tWhite
   repeat with tP = kMdsLow to kMdsHigh
      if not mdsIsBlack(tP) then
         put kMdsKeysL + tWhite * kMdsWhiteW into tX
         mdsRect "mdsKey" & tP, kMdsWhite, tX, kMdsKeysT, tX + kMdsWhiteW - 1, kMdsKeysB
         if tP mod 12 is 0 then
            mdsLabel "mdsKeyName" & tP, mdsNoteName(tP, 1), 9, "96,104,124", "plain", tX + 1, kMdsKeysB - 18, tX + kMdsWhiteW - 2, kMdsKeysB - 2
            set the textAlign of field ("mdsKeyName" & tP) to "center"
         end if
         add 1 to tWhite
      end if
   end repeat
   put 0 into tWhite
   repeat with tP = kMdsLow to kMdsHigh
      if mdsIsBlack(tP) then
         put kMdsKeysL + tWhite * kMdsWhiteW - 1 into tCx
         mdsRect "mdsKey" & tP, kMdsBlack, tCx - 10, kMdsKeysT, tCx + 10, kMdsKeysT + 54
      else
         add 1 to tWhite
      end if
   end repeat
   mdsText "mdsMissing", empty, 14, kMdsInk, kMdsRollL + 60, kMdsRollT + 20, kMdsRollR - 60, kMdsRollB - 20
   set the textAlign of field "mdsMissing" to "center"
   set the opaque of field "mdsMissing" to true
   set the backgroundColor of field "mdsMissing" to kMdsWell
   set the visible of field "mdsMissing" to false

   -- the controls, as they arrived
   mdsRect "mdsSplit", kMdsLine, kMdsStageL + 14, 352, kMdsStageR - 14, 353
   mdsLabel "mdsCtlCap", "CONTROLS   as they arrived", 11, kMdsAccent, "bold", 30, 358, 500, 379
   repeat with tI = 1 to 8
      put kMdsKnobL + (tI - 1) * kMdsKnobDX into tX
      mdsOval "mdsKnobWell" & tI, kMdsWell, tX, kMdsKnobT, tX + kMdsKnobS, kMdsKnobT + kMdsKnobS
      mdsOval "mdsKnobArc" & tI, kMdsAccent, tX, kMdsKnobT, tX + kMdsKnobS, kMdsKnobT + kMdsKnobS
      set the startAngle of graphic ("mdsKnobArc" & tI) to 225
      set the arcAngle of graphic ("mdsKnobArc" & tI) to 1
      mdsOval "mdsKnobHole" & tI, kMdsPanel, tX + 7, kMdsKnobT + 7, tX + kMdsKnobS - 7, kMdsKnobT + kMdsKnobS - 7
      mdsLabel "mdsKnobVal" & tI, empty, 10, kMdsInk, "bold", tX + 4, kMdsKnobT + 12, tX + kMdsKnobS - 4, kMdsKnobT + 30
      set the textAlign of field ("mdsKnobVal" & tI) to "center"
      mdsLabel "mdsKnobTag" & tI, item tI of kMdsKnobCCs & " " & item tI of kMdsKnobNames, 9, kMdsSoft, "plain", tX - 7, kMdsKnobT + kMdsKnobS + 2, tX + kMdsKnobS + 7, kMdsKnobT + kMdsKnobS + 18
      set the textAlign of field ("mdsKnobTag" & tI) to "center"
   end repeat
   mdsRect "mdsBendSlot", kMdsWell, 44, kMdsWheelT, 66, kMdsWheelB
   mdsRect "mdsBendMid", kMdsLine, 40, (kMdsWheelT + kMdsWheelB) div 2, 70, (kMdsWheelT + kMdsWheelB) div 2 + 1
   mdsRoundRect "mdsBendThumb", kMdsInk, 38, 500, 72, 512
   mdsRect "mdsModSlot", kMdsWell, 84, kMdsWheelT, 106, kMdsWheelB
   mdsRoundRect "mdsModThumb", kMdsInk, 78, 550, 112, 562
   mdsLabel "mdsBendTag", "bend", 9, kMdsSoft, "plain", 30, kMdsWheelB + 2, 80, kMdsWheelB + 18
   set the textAlign of field "mdsBendTag" to "center"
   mdsLabel "mdsModTag", "mod", 9, kMdsSoft, "plain", 70, kMdsWheelB + 2, 120, kMdsWheelB + 18
   set the textAlign of field "mdsModTag" to "center"
   mdsLabel "mdsProgram", empty, 15, kMdsInk, "bold", 132, 452, 500, 476
   mdsLabel "mdsProgramCh", empty, 10, kMdsSoft, "plain", 132, 478, 500, 496
   repeat with tI = 1 to 16
      put 134 + (tI - 1) * 22 into tX
      mdsOval "mdsLed" & tI, kMdsOff, tX, 512, tX + 12, 524
      mdsLabel "mdsLedTag" & tI, tI, 9, kMdsSoft, "plain", tX - 5, 526, tX + 17, 542
      set the textAlign of field ("mdsLedTag" & tI) to "center"
   end repeat
   mdsLabel "mdsLedCap", "a light per channel, as its messages arrive", 9, kMdsSoft, "plain", 130, 544, 500, 560
   mdsLabel "mdsYouCap", empty, 9, kMdsYou, "plain", 130, 560, 500, 576

   -- the player: what it sent
   mdsLabel "mdsPlayerCap", "THE PLAYER", 11, kMdsAccent, "bold", 512, 358, 766, 379
   mdsText "mdsSent", empty, 10, kMdsInk, 512, 382, 766, 582
   set the textFont of field "mdsSent" to mdsMonoFont()
   set the dontWrap of field "mdsSent" to true
   mdsWell "mdsSent"

   -- the side: scenes, switches, what this shows, the wire, the counts
   mdsLabel "mdsScenesCap", "SCENES", 11, kMdsAccent, "bold", kMdsSideL, 82, kMdsSideR, 103
   repeat with tI = 1 to kMdsScenes
      put 106 + (tI - 1) * 30 into tY
      mdsButton "mdsScene" & tI, tI & ".  " & item tI of kMdsSceneNames, kMdsSideL, tY, kMdsSideR, tY + 26
   end repeat
   mdsButton "mdsTour", "Play them all", kMdsSideL, 258, kMdsSideL + 112, 282
   mdsButton "mdsPause", "Pause", kMdsSideL + 120, 258, kMdsSideL + 200, 282
   mdsButton "mdsSound", "Sound", kMdsSideL + 208, 258, kMdsSideR, 282
   mdsLabel "mdsAboutCap", "WHAT THIS SHOWS", 11, kMdsAccent, "bold", kMdsSideL, 288, kMdsSideR, 309
   mdsText "mdsAbout", empty, 12, kMdsInk, kMdsSideL, 310, kMdsSideR, 424
   mdsLabel "mdsWireCap", "ON THE WIRE", 11, kMdsAccent, "bold", kMdsSideL, 426, kMdsSideR, 447
   mdsText "mdsWire", empty, 10, kMdsInk, kMdsSideL, 448, kMdsSideR, 560
   set the textFont of field "mdsWire" to mdsMonoFont()
   set the dontWrap of field "mdsWire" to true
   mdsWell "mdsWire"
   mdsLabel "mdsStats", empty, 10, kMdsSoft, "plain", kMdsSideL, 563, kMdsSideR, 582

   -- the footer: what is missing, or that nothing is
   mdsLabel "mdsStatus", empty, 11, kMdsSoft, "plain", kMdsStageL, 593, kMdsSideR, 614
   mdsShowSwitches
   set the lockMessages to tWasQuiet
   unlock screen
end mdsBuild

-- Remove what an earlier build made (and only that): every control this
-- stack makes is named mds...
command mdsClear
   local tI
   repeat with tI = the number of controls of this card down to 1
      if the short name of control tI of this card begins with "mds" then
         delete control tI of this card
      end if
   end repeat
end mdsClear

function mdsMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end mdsMonoFont

-- One line of words nobody types into
command mdsLabel pName, pText, pSize, pColor, pStyle, pL, pT, pR, pB
   create field pName
   mdsQuiet pName, pSize, pColor
   set the dontWrap of field pName to true
   set the textStyle of field pName to pStyle
   set the rect of field pName to pL, pT, pR, pB
   set the text of field pName to pText
end mdsLabel

-- Words that wrap
command mdsText pName, pText, pSize, pColor, pL, pT, pR, pB
   create field pName
   mdsQuiet pName, pSize, pColor
   set the dontWrap of field pName to false
   set the rect of field pName to pL, pT, pR, pB
   set the text of field pName to pText
end mdsText

-- Lines tall enough for any system's font: left alone, a line is as tall
-- as the font the stack was BUILT with wants, and on Windows the tops of
-- the capitals were cut off (the Render3D Tour, 2026-11-21). Every colour
-- is the field's own, so a dark system theme changes nothing.
command mdsQuiet pName, pSize, pColor
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the opaque of field pName to false
   set the showBorder of field pName to false
   set the threeD of field pName to false
   set the borderWidth of field pName to 0
   set the margins of field pName to 2
   set the vScrollbar of field pName to false
   set the hScrollbar of field pName to false
   set the autoHilite of field pName to false
   set the listBehavior of field pName to false
   set the textSize of field pName to pSize
   set the fixedLineHeight of field pName to true
   set the textHeight of field pName to round(pSize * 1.5)
   set the foregroundColor of field pName to pColor
   set the backgroundColor of field pName to kMdsPage
   set the hiliteColor of field pName to kMdsButton
   set the borderColor of field pName to kMdsLine
end mdsQuiet

-- A sunken panel for a field of mono text
command mdsWell pName
   set the opaque of field pName to true
   set the backgroundColor of field pName to kMdsWell
   set the margins of field pName to 8
end mdsWell

-- A flat button: the Render3D Tour's. Lit (hilited) means on or chosen.
command mdsButton pName, pLabel, pL, pT, pR, pB
   create button pName
   set the label of button pName to pLabel
   set the style of button pName to "roundrect"
   set the opaque of button pName to true
   set the showBorder of button pName to false
   set the threeD of button pName to false
   set the shadow of button pName to false
   set the traversalOn of button pName to false
   set the autoHilite of button pName to false
   set the textSize of button pName to 12
   set the backgroundColor of button pName to kMdsButton
   set the foregroundColor of button pName to kMdsInk
   set the hiliteColor of button pName to kMdsAccent
   set the borderColor of button pName to kMdsLine
   set the rect of button pName to pL, pT, pR, pB
end mdsButton

command mdsRect pName, pColor, pL, pT, pR, pB
   create graphic pName
   set the style of graphic pName to "rectangle"
   mdsFill pName, pColor
   set the rect of graphic pName to pL, pT, pR, pB
end mdsRect

command mdsRoundRect pName, pColor, pL, pT, pR, pB
   create graphic pName
   set the style of graphic pName to "roundrect"
   set the roundRadius of graphic pName to 4
   mdsFill pName, pColor
   set the rect of graphic pName to pL, pT, pR, pB
end mdsRoundRect

command mdsOval pName, pColor, pL, pT, pR, pB
   create graphic pName
   set the style of graphic pName to "oval"
   mdsFill pName, pColor
   set the rect of graphic pName to pL, pT, pR, pB
end mdsOval

command mdsFill pName, pColor
   set the opaque of graphic pName to true
   set the lineSize of graphic pName to 0
   set the backgroundColor of graphic pName to pColor
   set the foregroundColor of graphic pName to pColor
   set the lockLocation of graphic pName to true
end mdsFill
