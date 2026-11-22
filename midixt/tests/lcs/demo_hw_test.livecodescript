script "MidiDemoHwTest"
-- ---------------------------------------------------------------------------
-- The showcase stack, examples/midi-stage.livecodescript, over the REAL
-- midixt library: RtMidi over this machine's own MIDI service, whatever it
-- has. Opened as start-here opens it, it must run with nothing going wrong
-- either way:
--
--   * with a service that makes virtual ports (Linux with the ALSA
--     sequencer, a Mac), the player's messages travel through the "MIDI
--     Stage" port and the service back to the stage, every one of them;
--   * without one (no sequencer, or Windows without a loopback driver), the
--     stage reads with midiDecode and the footer says why, in the library's
--     words.
-- Closing it closes every port it opened.
--
-- MIDIXT_REQUIRE_SERVICE=1 makes the second case a failure (as for the
-- self-test's hardware run): set it where a service is known to be there.
-- ---------------------------------------------------------------------------
-- requires: midixt

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

-- start-here's ritual: see demo_test.livecodescript
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

on TestTheStageRunsOnThisMachinesMidi
   local tState, tStatus, tName
   demoOpen
   TestPump 2500
   put demoState() into tState
   put the text of field "mdsStatus" of stack sDemo into tStatus
   TestDiagnostic "mode " & tState["mode"] & " (" & tState["cableHow"] & "): " & tStatus
   TestAssertEqual "nothing went wrong", tState["trouble"], empty
   TestAssertEqual "midixt answered", tState["haveMidi"], true
   TestAssertEqual "the loop is running", tState["running"], true
   TestAssert "the player played (" & tState["sent"] & ")", tState["sent"] >= 10
   if tState["mode"] is "cable" then
      TestAssert "through the service's own port (" & tState["cableName"] & ")", tState["cableName"] is not empty
      TestAssert "and the stage read what it sent (" & tState["read"] & " of " & tState["sent"] & ")", tState["read"] >= 10 and tState["sent"] - tState["read"] <= 12
      TestAssert "timed from send to stage (" & tState["lagN"] & " notes)", tState["lagN"] >= 3
   else
      TestAssertEqual "with no cable the stage decodes", tState["mode"], "decode"
      TestAssert "and knows why (" & tState["noCable"] & ")", tState["noCable"] is not empty
      TestAssert "the footer says so", tStatus begins with "No MIDI cable here: the stage decodes each message itself."
      TestAssertEqual "and its tooltip gives the library's words", the tooltip of field "mdsStatus" of stack sDemo, "No MIDI cable: " & tState["noCable"]
      TestAssertEqual "and the stage read every message it decoded", tState["read"], tState["sent"]
      if $MIDIXT_REQUIRE_SERVICE is "1" then
         TestAssert "MIDIXT_REQUIRE_SERVICE=1: a cable was found", false
      else
         TestSkip "the cable through the MIDI service", "no MIDI service with virtual ports here (MIDIXT_REQUIRE_SERVICE=1 makes this a failure)"
      end if
   end if
   -- closing it closes what it opened: a second open finds it all again
   put sDemo into tName
   close stack tName
   TestPump 100
   demoOpen
   TestPump 1000
   put demoState() into tState
   TestAssertEqual "opened again, nothing went wrong", tState["trouble"], empty
   TestAssert "and it plays again (" & tState["sent"] & ")", tState["sent"] >= 4
end TestTheStageRunsOnThisMachinesMidi
