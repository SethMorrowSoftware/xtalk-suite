script "MidiDemoTest"
-- ---------------------------------------------------------------------------
-- The showcase stack, examples/midi-stage.livecodescript, opened the way
-- start-here's Open button opens it (a fresh stack, parked closed, given the
-- file's script, then a real `go invisible`), and run in the engine over the
-- MOCK midixt library (no MIDI service, no hardware):
--
--   * it opens straight into motion: the loop runs and the player plays
--     within a second and a half. The mock's virtual port is not listed
--     among its inputs, so here the stage reads each message with midiDecode,
--     and the footer says so and why;
--   * the window is 1100 x 620 (the suite's 1200 x 640 budget), every control
--     sits inside it, and every field and button carries its OWN text and
--     background colours, so a dark system theme cannot turn its words white
--     on white (OXT-Beyond's behaviour, reported 2026-11-21);
--   * every scene plays with nothing going wrong and does what its words
--     say, checked against the score worked out by hand;
--   * over a cable (the mock's loopback) every message the player sends
--     arrives; the stage draws ONLY what arrives (cut the cable and the keys
--     it last read stay down while the player plays on); each knob and the
--     wheel show the last value sent, read from the mock's own log of what
--     left; and the listener's own timer carries it all in real time;
--   * the bytes the player shows are the bytes that left;
--   * a keyboard on another input lights its keys in blue;
--   * Pause and every scene change leave no note sounding;
--   * Sound plays through the output the footer names, only when pressed,
--     and stops with "all notes off";
--   * the cable is found by name on each system (ALSA, CoreMIDI, loopMIDI),
--     a keyboard's own in and out are never taken for one, and Sound never
--     plays into a cable;
--   * where there are no virtual ports (Windows MM) it says so;
--   * without midixt, or without its native library, it still opens, the
--     player plays, nothing is sent and it says what is missing.
-- The window itself, the look, the feel and a real MIDI service need an OXT
-- pass; this is the half a headless engine can settle.
--
-- There is no TestSetup: the two tests without the library must not load it
-- (the mock's controls bind to the same library), so each other test resets
-- the mock itself.
-- ---------------------------------------------------------------------------
-- requires: midixt-mock

local sDemo

on TestTearDown
   if sDemo is not empty and there is a stack sDemo then
      close stack sDemo
      TestPump 50
   end if
end TestTearDown

function demoPath
   local tPath
   put $SC_HELPERS into tPath
   set the itemDelimiter to "/"
   put "midi-stage.livecodescript" into the last item of tPath
   set the itemDelimiter to ","
   return tPath
end demoPath

-- start-here's ritual (slPrepareStack and slOpenSelected): the `script`
-- line names the stack and is not script; the stack is parked CLOSED before
-- it has a script, so the `go` is a genuine open that fires preOpenStack
-- and openStack (the suite's engine notes, 5.5)
command demoOpen
   local tScript, tName
   put url ("file:" & demoPath()) into tScript
   if tScript is empty then
      throw "cannot read " & demoPath()
   end if
   put line 1 of tScript into tName
   set the itemDelimiter to quote
   put item 2 of tName into tName
   set the itemDelimiter to ","
   delete line 1 of tScript
   if there is a stack tName then
      delete stack tName
   end if
   create invisible stack tName
   close stack tName
   set the script of stack tName to tScript
   if the revAvailableHandlers of stack tName is empty then
      throw "the demo's script does not compile"
   end if
   put tName into sDemo
   go invisible stack tName
end demoOpen

function demoState
   dispatch function "mdsState" to stack sDemo
   return the result
end demoState

-- One entry of the state (a function's result cannot be subscripted)
function demoGet pKey
   local tState
   put demoState() into tState
   return tState[pKey]
end demoGet

-- Step the show by hand: the demo's own test clock, which reads the cable
-- once a frame as its listener's timer would
command demoStep pSeconds
   dispatch "mdsTestStep" to stack sDemo with pSeconds
end demoStep

-- Take the clock from the demo's loop: from here the test steps it
command demoHold
   dispatch "mdsTestBegin" to stack sDemo
end demoHold

command demoGo pScene
   dispatch "mdsGo" to stack sDemo with pScene
end demoGo

-- A click, as the user makes it: the button has no script, so the click
-- travels to the stack's mouseUp with the button as the target
command demoClick pButton
   send "mouseUp" to button pButton of stack sDemo
end demoClick

function demoText pField
   return the text of field pField of stack sDemo
end demoText

-- The mock's loopback as the cable: whatever an output sends arrives on the
-- mock's inbound queue, which the cable's input reads. (Port count 0 first,
-- in the test, so no other input of the demo shares that one queue.)
command demoCable
   local tIn, tOut
   put midiOpenVirtualInput("Stage test in") into tIn
   put midiOpenVirtualOutput("Stage test out") into tOut
   if not (tIn > 0 and tOut > 0) then
      throw "the mock would not open the test's cable: " & midiLastError()
   end if
   MockSetLoopback true, 1000
   dispatch "mdsTestCable" to stack sDemo with tIn, tOut
end demoCable

-- Bytes as the demo's log writes them: "90 3C 60"
function hexOf pBytes
   local tOut, tByte
   repeat for each byte tByte in pBytes
      put format("%02X", byteToNum(tByte)) & space after tOut
   end repeat
   delete the last char of tOut
   return tOut
end hexOf

-- The hex at the head of each of the player's log lines
function loggedHex pLog
   local tLine, tHex, tOut
   repeat for each line tLine in pLog
      -- a word of a char chunk does not compile: chunks nest larger first
      put char 1 to 10 of tLine into tHex
      put word 1 to -1 of tHex & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end loggedHex

-- The last pCount messages that left through the mock, as hex lines
function lastSentHex pCount
   local tI, tN, tOut
   put MockSentCount() into tN
   repeat with tI = max(1, tN - pCount + 1) to tN
      put hexOf(MockSent(tI)) & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end lastSentHex

-- Lit keys as the demo's state lists them ("60:96:player,"), but worked
-- out here from notes and velocities
function keysOf pNotes, pVel, pBassVel
   local tOut, tNote, tFirst
   put true into tFirst
   repeat for each word tNote in pNotes
      if tFirst and pBassVel is not empty then
         put tNote & ":" & pBassVel & ":player," after tOut
      else
         put tNote & ":" & pVel & ":player," after tOut
      end if
      put false into tFirst
   end repeat
   return tOut
end keysOf

function isRgb pColour
   return the number of items of pColour is 3 and item 1 of pColour is an integer and item 2 of pColour is an integer and item 3 of pColour is an integer
end isRgb

on TestOpensStraightIntoMotion
   local tState
   MockReset
   demoOpen
   TestAssert "the demo's stack is open", sDemo is among the lines of the openStacks
   TestPump 1500
   put demoState() into tState
   TestAssertEqual "nothing went wrong", tState["trouble"], empty
   TestAssertEqual "midixt answered", tState["haveMidi"], true
   TestAssertEqual "the loop is running", tState["running"], true
   TestAssertEqual "scene 1 plays first", tState["scene"], 1
   TestAssert "it drew frame after frame (" & tState["frames"] & ")", tState["frames"] >= 15
   TestAssert "the player played (" & tState["sent"] & " messages)", tState["sent"] >= 10
   TestAssertEqual "and the stage read every one", tState["read"], tState["sent"]
   TestAssert "keys are lit (" & tState["keys"] & ")", tState["keys"] is not empty
   TestAssert "the roll has bars in it (" & tState["bars"] & ")", tState["bars"] >= 3
   TestAssertEqual "the mock lists no virtual port, so the stage decodes", tState["mode"], "decode"
   TestAssert "and knows why (" & tState["noCable"] & ")", tState["noCable"] contains "did not come back as an input"
   TestAssert "the footer says so (" & demoText("mdsStatus") & ")", demoText("mdsStatus") begins with "No MIDI cable here: the stage decodes each message itself. (Its virtual port did not come back as an input.)"
   TestAssertEqual "its tooltip gives the reason in full", the tooltip of field "mdsStatus" of stack sDemo, "No MIDI cable: " & tState["noCable"]
   TestAssertEqual "and so does the stage's caption", demoText("mdsStageCap"), "THE STAGE   reads each message with midiDecode (no cable here)"
   TestAssertEqual "it listens to the mock's two inputs for a player", the number of lines of tState["youNames"], 2
   TestAssertEqual "it offers the first output to play through", tState["soundName"], "MockPort-0-aLongishName"
   TestAssertEqual "but plays nothing until asked", tState["soundOn"], false
   TestAssertEqual "so nothing left through the mock", MockSentCount(), 0
   TestAssert "the player's log shows what it built (" & line 1 of tState["sentLog"] & ")", tState["sentLog"] contains "note on"
   TestAssert "the wire shows what was read (" & line 1 of tState["log"] & ")", tState["log"] contains "noteOn"
   TestAssertEqual "the missing-library panel is hidden", the visible of field "mdsMissing" of stack sDemo, false
end TestOpensStraightIntoMotion

on TestTheWindowFitsAndKeepsItsColours
   local tI, tCount, tRect, tOutside, tNoColour, tType, tName
   MockReset
   demoOpen
   TestAssertEqual "the window is 1100 wide", the width of stack sDemo, 1100
   TestAssertEqual "and 620 high", the height of stack sDemo, 620
   TestAssert "which fits the suite's 1200 x 640", the width of stack sDemo <= 1200 and the height of stack sDemo <= 640
   TestAssertEqual "the header names OXT-Beyond", demoText("mdsBrand"), "OXT-BEYOND"
   TestAssertEqual "and the demo", demoText("mdsTitle"), "MIDI Stage"
   TestAssertEqual "and who made it", demoText("mdsByline"), "by Seth Morrow"
   TestAssert "and says what it does in one line", the number of lines of demoText("mdsSub") is 1
   put the number of controls of card 1 of stack sDemo into tCount
   TestAssert "it built its controls, a key for each of 37 notes among them (" & tCount & ")", tCount >= 240 and there is a graphic "mdsKey84" of stack sDemo and there is a graphic "mdsKey48" of stack sDemo
   put empty into tOutside
   put empty into tNoColour
   repeat with tI = 1 to tCount
      put the rect of control tI of card 1 of stack sDemo into tRect
      put the short name of control tI of card 1 of stack sDemo into tName
      if item 1 of tRect < 0 or item 2 of tRect < 0 or item 3 of tRect > 1100 or item 4 of tRect > 620 then
         put tName & " " & tRect & return after tOutside
      end if
      put word 1 of the name of control tI of card 1 of stack sDemo into tType
      if tType is "field" or tType is "button" then
         if the foregroundColor of control tI of card 1 of stack sDemo is empty or the backgroundColor of control tI of card 1 of stack sDemo is empty then
            put tName & return after tNoColour
         end if
         if the hiliteColor of control tI of card 1 of stack sDemo is empty then
            put tName & " (no hilite colour)" & return after tNoColour
         end if
      end if
      if tType is not "field" and tType is not "button" and tType is not "graphic" then
         put tName & " is a " & tType & ", which this demo never makes" & return after tNoColour
      end if
   end repeat
   TestAssertEqual "every control is inside the window", tOutside, empty
   TestAssertEqual "every field and button has its own colours", tNoColour, empty
   TestAssert "the stack's own text colour is set", the foregroundColor of stack sDemo is not empty
   -- a black key sits over the white keys either side of it
   TestAssert "C#4 is drawn over C4 and D4", the layer of graphic "mdsKey61" of stack sDemo > the layer of graphic "mdsKey60" of stack sDemo and the layer of graphic "mdsKey61" of stack sDemo > the layer of graphic "mdsKey62" of stack sDemo
   TestAssert "the knobs' rings are drawn under their holes", the layer of graphic "mdsKnobArc1" of stack sDemo < the layer of graphic "mdsKnobHole1" of stack sDemo
end TestTheWindowFitsAndKeepsItsColours

-- Each scene against the score, worked out by hand from its constants.
-- (Decoded here: the same stage code as over a cable, minus the cable.)
on TestEveryScenePlays
   local tState, tSent, tRead
   MockReset
   demoOpen
   demoHold
   -- 1. Arpeggio: C major up and back, eight to a bar, a bass note under
   demoGo 1
   put demoState() into tState
   put tState["sent"] into tSent
   demoStep 0.1
   put demoState() into tState
   TestAssertEqual "1: the downbeat sounds C4 hard and the bass C3 under it", tState["keys"], "48:84:player,60:96:player,"
   demoStep 0.25
   put demoState() into tState
   TestAssertEqual "then E4, softer, the bass still down", tState["keys"], "48:84:player,64:58:player,"
   -- in that frame the score played first and C4's note off fell due after
   TestAssertEqual "the player logged E4's note on (90: note on, channel 1)", line -2 of tState["sentLog"], "90 40 3A  note on   1  E4 58"
   TestAssertEqual "and then C4's note off", the last line of tState["sentLog"], "80 3C 00  note off  1  C4"
   demoStep 4
   put demoState() into tState
   TestAssert "1: notes went out and came in", tState["sent"] > tSent + 30 and tState["read"] is tState["sent"]
   TestAssertEqual "1: nothing went wrong", tState["trouble"], empty
   -- 2. Chords: four notes at once and the root an octave down, soft first
   demoGo 2
   demoStep 0.3
   put demoState() into tState
   TestAssertEqual "2: the first chord, C major seventh, at velocity 20, its bass at 30", tState["keys"], keysOf("48 60 64 67 71", 20, 30)
   demoStep 3.7
   put demoState() into tState
   -- 3.99 s: step 7 (3.75 s) is odd and plays nothing, so the chord of
   -- step 6 (3.21 s, for 0.99 s) sounds: the fourth voicing, G7, struck at
   -- 20 + round(107 * (0.5 - 0.5 * cos(2 pi 6 / 16))) = 20 + 91 = 111. Its
   -- bass, G2 (43), is below the keyboard and not listed.
   TestAssertEqual "2: at four seconds the G7 chord of step 6, struck at 111", tState["keys"], keysOf("55 59 62 65", 111, empty)
   TestAssertEqual "2: nothing went wrong", tState["trouble"], empty
   -- 3. Knobs: eight controllers under a held chord
   demoGo 3
   demoStep 1
   put demoState() into tState
   TestAssertEqual "3: the held chord, every note at 80", tState["keys"], keysOf("48 55 64 67 71 74", 80, empty)
   TestAssert "3: every knob has a value (" & tState["knobs"] & ")", isKnobs(tState["knobs"])
   TestAssertEqual "3: nothing went wrong", tState["trouble"], empty
   -- 4. Pitch bend: one held note, the wheel away from the middle
   demoGo 4
   demoStep 2
   put demoState() into tState
   TestAssertEqual "4: A4 held at 96", tState["keys"], "69:96:player,"
   TestAssert "4: the wheel is bent (" & tState["bend"] & ")", tState["bend"] is an integer and tState["bend"] is not 8192
   TestAssert "4: the bend's curve is drawn over the roll", the visible of graphic "mdsBendLine" of stack sDemo
   TestAssertEqual "4: nothing went wrong", tState["trouble"], empty
   -- 5. Drums and programs: channel 10, and a program change on bars 0, 2, 4
   demoGo 5
   demoStep 0.1
   put demoState() into tState
   TestAssertEqual "5: program 0 on the first bar", tState["program"], 0
   TestAssertEqual "5: and the stage names it", demoText("mdsProgram"), "Program 1   Acoustic Grand Piano"
   demoStep 4.4
   put demoState() into tState
   TestAssertEqual "5: program 4 on the third bar (4.29 s)", tState["program"], 4
   TestAssertEqual "5: Electric Piano 1", demoText("mdsProgram"), "Program 5   Electric Piano 1"
   TestAssertEqual "5: on channel 1", demoText("mdsProgramCh"), "the last program change that arrived, on channel 1"
   TestAssert "5: the drums are in their lane (" & tState["hits"] & " hits)", tState["hits"] >= 10
   TestAssert "5: the player named them (" & tState["sentLog"] & ")", tState["sentLog"] contains "kick" or tState["sentLog"] contains "closed hat"
   TestAssertEqual "5: nothing went wrong", tState["trouble"], empty
end TestEveryScenePlays

function isKnobs pKnobs
   local tV
   if the number of items of pKnobs is not 8 then
      return false
   end if
   repeat for each item tV in pKnobs
      if tV is not an integer or tV < 0 or tV > 127 then
         return false
      end if
   end repeat
   return true
end isKnobs

-- The touchstone: the stage draws what ARRIVES. Cut the cable and the player
-- plays on, but the stage reads nothing, and the chord it last read stays
-- down because its note-offs never came.
on TestTheStageDrawsOnlyWhatArrives
   local tState, tCut, tBack, tWant
   MockReset
   MockSetPortCount 0
   demoOpen
   demoHold
   demoCable
   demoGo 2
   demoStep 0.3
   put demoState() into tState
   TestAssertEqual "over the cable", tState["mode"], "cable"
   TestAssert "the footer says it is the test's cable (" & demoText("mdsStatus") & ")", demoText("mdsStatus") contains "the test's cable"
   put keysOf("48 60 64 67 71", 20, 30) into tWant
   TestAssertEqual "the chord arrived", tState["keys"], tWant
   TestAssertEqual "every message sent was read", tState["read"], tState["sent"]
   TestAssert "note-ons were timed from send to stage (" & tState["lagN"] & ")", tState["lagN"] >= 5
   -- cut it
   MockSetLoopback false, 0
   demoGo 1
   demoStep 2
   put demoState() into tCut
   TestAssert "cut, the player played on (" & tCut["sent"] - tState["sent"] & " more)", tCut["sent"] > tState["sent"] + 15
   TestAssertEqual "the stage read nothing more", tCut["read"], tState["read"]
   TestAssertEqual "and the chord it last read is still down", tCut["keys"], tWant
   TestAssertEqual "the wire shows nothing new", tCut["log"], tState["log"]
   -- mend it
   MockSetLoopback true, 1000
   demoStep 1.2
   put demoState() into tBack
   TestAssert "mended, it reads again (" & tBack["read"] - tCut["read"] & " more)", tBack["read"] > tCut["read"] + 5
   TestAssertEqual "everything sent since arrived", tBack["read"] - tCut["read"], tBack["sent"] - tCut["sent"]
   TestAssertEqual "nothing went wrong", tBack["trouble"], empty
end TestTheStageDrawsOnlyWhatArrives

-- The oracle is the mock's own log of what LEFT through the cable: each knob
-- must show the last value its controller was sent, the wheel the last bend,
-- and the player's log the very bytes that left
on TestTheKnobsAndTheWheelShowTheLastValueSent
   local tState, tStart, tI, tB, tLast, tWant, tCC, tBend, tCount
   MockReset
   MockSetPortCount 0
   demoOpen
   demoHold
   demoCable
   put demoState() into tStart
   demoGo 3
   demoStep 3
   put demoState() into tState
   put MockSentCount() into tCount
   TestAssertEqual "every message the player counted left through the mock", tCount, tState["sent"] - tStart["sent"]
   TestAssertEqual "and arrived", tState["read"], tState["sent"]
   repeat with tI = 1 to tCount
      put MockSent(tI) into tB
      if byteToNum(byte 1 of tB) is 176 then
         put byteToNum(byte 3 of tB) into tLast[byteToNum(byte 2 of tB)]
      end if
   end repeat
   put empty into tWant
   repeat for each item tCC in "1,7,10,11,71,74,91,93"
      put tLast[tCC] & comma after tWant
   end repeat
   TestAssert "the knobs moved (" & tWant & ")", isKnobs(tWant)
   TestAssertEqual "each knob shows the last value its controller was sent", tState["knobs"], tWant
   TestAssertEqual "each knob's number on the stage says so", the text of field "mdsKnobVal8" of stack sDemo, item 8 of tWant
   TestAssertEqual "the player's log is the bytes that left, line for line", loggedHex(tState["sentLog"]), lastSentHex(the number of lines of tState["sentLog"])
   -- the wheel
   demoGo 4
   demoStep 2
   put demoState() into tState
   put empty into tBend
   repeat with tI = tCount + 1 to MockSentCount()
      put MockSent(tI) into tB
      if byteToNum(byte 1 of tB) is 224 then
         put byteToNum(byte 2 of tB) + byteToNum(byte 3 of tB) * 128 into tBend
      end if
   end repeat
   TestAssert "the bend moved (" & tBend & ")", tBend is an integer and tBend is not 8192
   TestAssertEqual "the wheel shows the last bend sent", tState["bend"], tBend
   TestAssertEqual "and the log again shows the bytes that left", loggedHex(tState["sentLog"]), lastSentHex(the number of lines of tState["sentLog"])
   -- leaving the knobs scene reset the controllers (121) on the way out
   TestAssertEqual "controllers reset when the knobs scene ended (mod back to empty)", item 1 of tState["knobs"], empty
   TestAssertEqual "with volume where a synth starts it", item 2 of tState["knobs"], 100
   TestAssertEqual "nothing went wrong", tState["trouble"], empty
end TestTheKnobsAndTheWheelShowTheLastValueSent

-- The real thing: the loop on its own clock and midi-helpers' listener on
-- its own timer, not the test's hand
on TestTheListenerCarriesItInRealTime
   local tState
   MockReset
   MockSetPortCount 0
   demoOpen
   demoCable
   TestPump 3000
   put demoState() into tState
   TestAssertEqual "nothing went wrong", tState["trouble"], empty
   TestAssertEqual "the loop is running", tState["running"], true
   TestAssertEqual "over the cable", tState["mode"], "cable"
   TestAssert "the listener read what the player sent (" & tState["read"] & " of " & tState["sent"] & ")", tState["read"] >= 15 and tState["sent"] - tState["read"] <= 12
   TestAssert "note-ons were timed (" & tState["lagN"] & ")", tState["lagN"] >= 5
   TestAssert "a note took under 100 ms from send to stage (" & round(tState["lagSum"] / max(1, tState["lagN"])) & " ms)", tState["lagSum"] / max(1, tState["lagN"]) < 100
   TestAssert "the stats line says so (" & demoText("mdsStats") & ")", demoText("mdsStats") contains "ms send to stage"
end TestTheListenerCarriesItInRealTime

-- Pause, and a scene change: everything sounding stops, with each note's own
-- note off and then "all notes off" on both channels the player uses
on TestPauseAndSceneChangesLeaveNoNoteSounding
   local tState, tSent
   MockReset
   MockSetPortCount 0
   demoOpen
   demoHold
   demoCable
   demoGo 1
   demoStep 1
   -- a scene change: only the new scene's notes are down after it
   demoGo 3
   demoStep 0.05
   put demoState() into tState
   TestAssertEqual "after a scene change only the new chord is down", tState["keys"], keysOf("48 55 64 67 71 74", 80, empty)
   -- pause
   demoGo 2
   demoStep 0.3
   TestAssert "a chord is down", demoGet("keys") is not empty
   demoClick "mdsPause"
   demoStep 0.1
   put demoState() into tState
   TestAssertEqual "paused", tState["paused"], true
   TestAssertEqual "the Pause button is lit", the hilite of button "mdsPause" of stack sDemo, true
   TestAssertEqual "no note-off is left to send", tState["offs"], empty
   TestAssertEqual "no key is down on the stage", tState["keys"], empty
   TestAssertEqual "the last two messages were all notes off, channel 1 then 10", lastSentHex(2), "B0 7B 00" & return & "B9 7B 00"
   put tState["sent"] into tSent
   demoStep 1
   TestAssertEqual "paused, the player sends nothing", demoGet("sent"), tSent
   demoClick "mdsPause"
   demoStep 1
   TestAssert "unpaused, it plays again", demoGet("sent") > tSent
   TestAssertEqual "the Pause button is dark", the hilite of button "mdsPause" of stack sDemo, false
end TestPauseAndSceneChangesLeaveNoNoteSounding

-- Another input: a keyboard's notes light up in blue, and its controllers
-- move the knobs, read straight with midiPoll
on TestYourPlayingShowsInBlue
   local tState, tColour
   MockReset
   demoOpen
   demoHold
   demoClick "mdsPause"
   demoStep 0.1
   put demoState() into tState
   TestAssertEqual "the player is quiet", tState["keys"], empty
   TestAssert "a push into the mock's inbound queue arrives on an input", MockPush(numToByte(144) & numToByte(62) & numToByte(100), 2500)
   demoStep 0.1
   put demoState() into tState
   TestAssertEqual "your note is down, as yours", tState["keys"], "62:100:you,"
   TestAssertEqual "read as yours", tState["youRead"], 1
   TestAssert "the wire says whose, and its timing (" & the last line of tState["log"] & ")", the last line of tState["log"] begins with "you  noteOn    1  D4 100"
   put the backgroundColor of graphic "mdsKey62" of stack sDemo into tColour
   TestAssert "the key is blue (" & tColour & ")", isRgb(tColour) and item 3 of tColour > item 1 of tColour + 40
   put the backgroundColor of graphic "mdsLed1" of stack sDemo into tColour
   TestAssert "channel 1's light is blue (" & tColour & ")", isRgb(tColour) and item 3 of tColour > item 1 of tColour + 40
   TestAssert "and the stats line counts it (" & demoText("mdsStats") & ")", demoText("mdsStats") contains "1 yours"
   MockPush numToByte(176) & numToByte(1) & numToByte(99), 1000
   MockPush numToByte(128) & numToByte(62) & numToByte(0), 1000
   demoStep 0.1
   put demoState() into tState
   TestAssertEqual "your note off let it go", tState["keys"], empty
   TestAssertEqual "and your mod wheel moved the first knob", item 1 of tState["knobs"], 99
   TestAssertEqual "three messages of yours", tState["youRead"], 3
   TestAssertEqual "nothing went wrong", tState["trouble"], empty
end TestYourPlayingShowsInBlue

-- Sound: off until pressed; then the same bytes go to the output the footer
-- names; pressed again, "all notes off" and then nothing
on TestSoundPlaysOnlyWhenAskedAndStopsClean
   local tState, tCount
   MockReset
   MockSetPortCount 1
   demoOpen
   demoHold
   put demoState() into tState
   TestAssertEqual "it offers the mock's output", tState["soundName"], "MockPort-0-aLongishName"
   TestAssert "the footer says how to hear it (" & demoText("mdsStatus") & ")", demoText("mdsStatus") contains "Press Sound to hear it through MockPort-0-aLongishName."
   demoStep 1
   TestAssertEqual "nothing was played before Sound was pressed", MockSentCount(), 0
   demoClick "mdsSound"
   put demoState() into tState
   TestAssertEqual "Sound is on", tState["soundOn"], true
   TestAssertEqual "and its button is lit", the hilite of button "mdsSound" of stack sDemo, true
   TestAssert "the footer says where it plays (" & demoText("mdsStatus") & ")", demoText("mdsStatus") contains "Sound plays through MockPort-0-aLongishName."
   demoGo 1
   demoStep 2
   put demoState() into tState
   TestAssert "the player's messages went to the output (" & MockSentCount() & ")", MockSentCount() >= 13
   TestAssertEqual "the very bytes the player shows", loggedHex(tState["sentLog"]), lastSentHex(the number of lines of tState["sentLog"])
   demoClick "mdsSound"
   TestAssertEqual "Sound is off", demoGet("soundOn"), false
   TestAssertEqual "and the output was told all notes off on both channels", lastSentHex(2), "B0 7B 00" & return & "B9 7B 00"
   put MockSentCount() into tCount
   demoStep 1
   TestAssertEqual "then nothing more was played", MockSentCount(), tCount
   TestAssertEqual "nothing went wrong", demoGet("trouble"), empty
end TestSoundPlaysOnlyWhenAskedAndStopsClean

function demoFind pHandler, pA, pB
   dispatch function pHandler to stack sDemo with pA, pB
   return the result
end demoFind

-- The port names each system gives, written out from what each lists
on TestFindsTheCableOnEverySystem
   local tWin, tLinux
   MockReset
   demoOpen
   -- the virtual port, found again among the inputs
   TestAssertEqual "ALSA lists it as client:port", demoFind("mdsFindVirtual", "Midi Through:Midi Through Port-0 14:0" & return & "RtMidi Output Client:MIDI Stage 128:0", "MIDI Stage"), 1
   TestAssertEqual "CoreMIDI by its name", demoFind("mdsFindVirtual", "IAC Driver Bus 1" & return & "MIDI Stage", "MIDI Stage"), 1
   TestAssertEqual "absent, -1", demoFind("mdsFindVirtual", "Midi Through:Midi Through Port-0 14:0", "MIDI Stage"), -1
   -- a loopback driver's pair
   put "Microsoft GS Wavetable Synth 0" & return & "loopMIDI Port 1" into tWin
   TestAssertEqual "loopMIDI: Windows numbers each list, the names still pair", demoFind("mdsFindPair", "loopMIDI Port 0", tWin), "0,1"
   TestAssertEqual "a keyboard's own in and out are never a cable", demoFind("mdsFindPair", "Arturia KeyStep 32 0", "Microsoft GS Wavetable Synth 0" & return & "Arturia KeyStep 32 1"), empty
   TestAssertEqual "a loopMIDI port among keyboards", demoFind("mdsFindPair", "Arturia KeyStep 32 0" & return & "loopMIDI Port 1", "Microsoft GS Wavetable Synth 0" & return & "Arturia KeyStep 32 1" & return & "loopMIDI Port 2"), "1,2"
   TestAssertEqual "macOS's IAC bus", demoFind("mdsFindPair", "IAC Driver Bus 1", "IAC Driver Bus 1"), "0,0"
   TestAssertEqual "Linux's Midi Through", demoFind("mdsFindPair", "Midi Through:Midi Through Port-0 14:0", "Midi Through:Midi Through Port-0 14:0"), "0,0"
   TestAssertEqual "the base of a numbered name", demoFind("mdsBaseName", "loopMIDI Port 12"), "loopMIDI Port"
   TestAssertEqual "a name of nothing but digits has no base", demoFind("mdsBaseName", "123"), empty
   -- the output to play through
   TestAssertEqual "Windows: its own synth", demoFind("mdsFindSound", tWin, "loopMIDI Port 0"), 0
   put "Midi Through:Midi Through Port-0 14:0" & return & "FLUID Synth (1234):Synth input port (1234:0) 128:0" into tLinux
   TestAssertEqual "Linux: a synth, never the loop", demoFind("mdsFindSound", tLinux, "Midi Through:Midi Through Port-0 14:0"), 1
   TestAssertEqual "never the cable itself", demoFind("mdsFindSound", "loopMIDI Port 1", "loopMIDI Port 0"), -1
   TestAssertEqual "never this demo's own port", demoFind("mdsFindSound", "RtMidi Input Client:MIDI Stage 129:0", empty), -1
   TestAssertEqual "and none where there is no output", demoFind("mdsFindSound", empty, empty), -1
end TestFindsTheCableOnEverySystem

on TestWindowsMMHasNoVirtualPortsAndSaysSo
   local tState
   MockReset
   MockSetApi 4
   demoOpen
   TestPump 800
   put demoState() into tState
   TestAssertEqual "nothing went wrong", tState["trouble"], empty
   TestAssertEqual "the stage decodes", tState["mode"], "decode"
   TestAssertEqual "and says why, in the library's words", tState["noCable"], "this MIDI backend has no virtual ports (on Windows use a loopback driver such as loopMIDI)"
   TestAssert "the footer says what makes one (" & demoText("mdsStatus") & ")", demoText("mdsStatus") begins with "No MIDI cable here: the stage decodes each message itself. A loopMIDI port makes one."
   TestAssertEqual "and its tooltip gives the library's words", the tooltip of field "mdsStatus" of stack sDemo, "No MIDI cable: this MIDI backend has no virtual ports (on Windows use a loopback driver such as loopMIDI)"
   TestAssert "the show goes on (" & tState["read"] & " read)", tState["read"] >= 4 and tState["read"] is tState["sent"]
end TestWindowsMMHasNoVirtualPortsAndSaysSo

on TestWithoutMidixtItSaysWhatIsMissing
   local tState, tLog
   -- this process never touched the library: unload the extension itself
   unload extension "org.openxtalk.library.midi"
   demoOpen
   TestPump 800
   put demoState() into tState
   TestAssertEqual "midixt is not there", tState["haveMidi"], false
   TestAssertEqual "and it says why, in words", tState["whyNot"], "midixt is not loaded in this OXT: nothing answered midiVersion()."
   TestAssertEqual "the show still runs", tState["running"], true
   TestAssertEqual "with nothing going wrong", tState["trouble"], empty
   TestAssertEqual "nothing was sent", tState["sent"], 0
   TestAssertEqual "and nothing read", tState["read"], 0
   TestAssertEqual "there is no cable to speak of", tState["mode"], "none"
   TestAssert "the stage says what is missing", the visible of field "mdsMissing" of stack sDemo and demoText("mdsMissing") contains "midixt"
   TestAssert "and so does the footer (" & demoText("mdsStatus") & ")", demoText("mdsStatus") begins with "Missing: midixt."
   TestAssertEqual "whose tooltip says why", the tooltip of field "mdsStatus" of stack sDemo, tState["whyNot"]
   put tState["sentLog"] into tLog
   TestAssert "the player still plays (" & line 1 of tLog & ")", tLog contains "note on"
   TestPump 400
   TestAssert "and moves on", demoGet("sentLog") is not tLog
end TestWithoutMidixtItSaysWhatIsMissing

on TestWithoutItsNativeLibraryItSaysWhatIsMissing
   local tState
   -- the library this process would load is not there: the first call of
   -- the binding throws, as it does in an OXT without midixt's library
   set the revLibraryMapping["midixt"] to "/nonexistent/midixt-gone/midixt.so"
   demoOpen
   TestPump 600
   put demoState() into tState
   TestAssertEqual "midixt is not there", tState["haveMidi"], false
   TestAssert "and it says why, in words (" & tState["whyNot"] & ")", tState["whyNot"] begins with "midixt is loaded, but its native library did not load: unable to load foreign library"
   TestAssertEqual "the show still runs", tState["running"], true
   TestAssertEqual "with nothing going wrong", tState["trouble"], empty
   TestAssertEqual "and nothing sent", tState["sent"], 0
   TestAssert "the footer says what is missing (" & demoText("mdsStatus") & ")", demoText("mdsStatus") begins with "Missing: midixt."
end TestWithoutItsNativeLibraryItSaysWhatIsMissing
