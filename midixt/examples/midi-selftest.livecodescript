-- midi-selftest.livecodescript
-- ---------------------------------------------------------------------------
-- HARDWARE-FREE self-test for the midixt extension, runnable inside OpenXTalk.
-- It needs NO keyboards, synthesizers or MIDI interfaces.
--
-- HOW TO RUN
--   1. Install (or Test-load) the midixt extension in OXT.
--   2. Paste this whole script into a stack or card script.
--   3. In the Message Box, run:   put runMidiSelfTest()
--      (a "MIDIResults" field is created/updated if a card is open, and the
--       full log is also returned to the Message Box.)
--
-- WHAT IT PROVES, in three tiers of increasing dependency:
--   Tier 1  decoding: every kind of message read into its event array. Pure,
--           no MIDI service needed. If these pass, Data crosses the boundary.
--   Tier 2  the ports: listing, refusals with reasons, a virtual output opened,
--           used and closed. Needs nothing; on Windows (no virtual ports) and
--           on a machine with no MIDI service the virtual part says why.
--   Tier 3  a loopback through the system's own MIDI service: a virtual
--           output is opened, found among the inputs, opened as one, and a
--           note, a controller, a bend and a SysEx sent through it are read
--           back. Linux (ALSA) and macOS (CoreMIDI); skipped, with the reason,
--           where there are no virtual ports or no service.
--
-- This is the MIDI third of ShowControl's selftest.livecodescript (oscxt and
-- artnetxt carry the other two). tests/lcs/selftest_test.livecodescript runs
-- it headlessly on every change, over the mock library and the real one.
-- ---------------------------------------------------------------------------

local sMidiStPass, sMidiStFail, sMidiStSkip, sMidiStLog

-- ===== entry point =========================================================

function runMidiSelfTest
   put 0 into sMidiStPass
   put 0 into sMidiStFail
   put 0 into sMidiStSkip
   put "midixt hardware-free self-test (midiVersion " & midiVersion() & ")" into sMidiStLog

   midiStSection "TIER 1 - MIDI decode (no MIDI service needed)"
   midiStDecode

   midiStSection "TIER 2 - ports, refusals, a virtual output (no hardware)"
   midiStPorts

   midiStSection "TIER 3 - loopback through the system's MIDI service"
   midiStLoopback

   put return & "==================================================" after sMidiStLog
   put return & "  " & sMidiStPass & " passed, " & sMidiStFail & " failed, " \
         & sMidiStSkip & " skipped" after sMidiStLog
   midiStShowResults
   return sMidiStLog
end runMidiSelfTest

-- The log of the last run.
function midiSelfTestLog
   return sMidiStLog
end midiSelfTestLog

-- ===== Tier 1: decode ======================================================

private command midiStDecode
   local tDec
   put midiDecode(numToByte(144) & numToByte(60) & numToByte(100)) into tDec   -- ch1 note on
   midiStAssert "note on: kind", (tDec["kind"] is "noteOn")
   midiStAssert "note on: channel 1", (tDec["channel"] is 1)
   midiStAssert "note on: data1 60", (tDec["data1"] is 60)
   midiStAssert "note on: data2 100", (tDec["data2"] is 100)
   midiStAssert "note on: the raw bytes come too", (the number of bytes in tDec["bytes"] is 3)

   put midiDecode(numToByte(144) & numToByte(60) & numToByte(0)) into tDec      -- note on vel 0
   midiStAssert "note on velocity 0 decodes as noteOff", (tDec["kind"] is "noteOff")

   put midiDecode(numToByte(128) & numToByte(60) & numToByte(64)) into tDec     -- ch1 note off
   midiStAssert "note off: kind", (tDec["kind"] is "noteOff")
   midiStAssert "note off: release velocity 64", (tDec["data2"] is 64)

   put midiDecode(numToByte(176) & numToByte(7) & numToByte(96)) into tDec      -- ch1 CC7
   midiStAssert "control change: kind", (tDec["kind"] is "controlChange")
   midiStAssert "control change: controller 7", (tDec["data1"] is 7)
   midiStAssert "control change: value 96", (tDec["data2"] is 96)

   put midiDecode(numToByte(195) & numToByte(5)) into tDec                      -- ch4 program change
   midiStAssert "program change: kind", (tDec["kind"] is "programChange")
   midiStAssert "program change: channel 4", (tDec["channel"] is 4)
   midiStAssert "program change: program 5", (tDec["data1"] is 5)

   put midiDecode(numToByte(229) & numToByte(0) & numToByte(64)) into tDec      -- ch6 pitch bend
   midiStAssert "pitch bend: kind", (tDec["kind"] is "pitchBend")
   midiStAssert "pitch bend: channel 6", (tDec["channel"] is 6)
   midiStAssert "pitch bend: value14 8192 (centre)", (tDec["value14"] is 8192)
   put midiDecode(numToByte(239) & numToByte(127) & numToByte(127)) into tDec   -- ch16 full up
   midiStAssert "pitch bend: channel 16, value14 16383", (tDec["channel"] is 16 and tDec["value14"] is 16383)

   put midiDecode(numToByte(210) & numToByte(64)) into tDec                     -- ch3 pressure
   midiStAssert "channel pressure: kind and channel", (tDec["kind"] is "channelPressure" and tDec["channel"] is 3)
   put midiDecode(numToByte(160) & numToByte(60) & numToByte(30)) into tDec     -- poly aftertouch
   midiStAssert "poly aftertouch: kind", (tDec["kind"] is "polyAftertouch")

   put midiDecode(numToByte(240) & numToByte(126) & numToByte(127) & numToByte(247)) into tDec
   midiStAssert "sysex: kind", (tDec["kind"] is "sysex")
   midiStAssert "sysex: all 4 bytes kept", (the number of bytes in tDec["bytes"] is 4)
   put midiDecode(numToByte(248)) into tDec                                     -- timing clock
   midiStAssert "clock: a system message on channel 0", (tDec["kind"] is "system" and tDec["channel"] is 0)
end midiStDecode

-- ===== Tier 2: ports =======================================================

private command midiStPorts
   local tIns, tOuts, tOut
   put midiInputPorts() into tIns
   put midiOutputPorts() into tOuts
   -- Reaching here means the calls returned without throwing (the real test).
   midiStAssert "midiInputPorts() returned without error", true
   midiStAssert "midiOutputPorts() returned without error", true
   put return & "    (inputs: " & (the number of elements of tIns) \
         & ", outputs: " & (the number of elements of tOuts) & ")" after sMidiStLog
   if the number of elements of tIns is 0 and midiLastError() is not empty then
      put return & "    (" & midiLastError() & ")" after sMidiStLog
   end if

   -- refusals are deterministic and hardware-free
   midiStAssert "opening an out-of-range output fails (0)", (midiOpenOutput(99999) is 0)
   midiStAssert "  and midiLastError says why", (midiLastError() is not empty)
   midiNoteOn 0, 1, 60, 100
   midiStAssert "a send on handle 0 does nothing, and says why", (midiLastError() contains "not an open output port")
   midiStAssert "a poll of handle 0 is empty", (the number of elements of midiPoll(0) is 0)

   -- virtual ports work on macOS and Linux; Windows (WinMM) has none and
   -- returns 0 with the reason, the documented behaviour, so this branches.
   put midiOpenVirtualOutput("midixt Self-Test") into tOut
   if tOut is 0 then
      midiStSkip "a virtual output", midiLastError()
   else
      midiStAssert "opened a virtual output port", true
      midiNoteOn tOut, 1, 60, 100
      midiStAssert "a note on went out with no error", (midiLastError() is empty)
      midiNoteOff tOut, 1, 60, 0
      midiClose tOut
      midiNoteOn tOut, 1, 60, 100
      midiStAssert "after midiClose the handle is refused", (midiLastError() contains "not an open output port")
   end if
end midiStPorts

-- ===== Tier 3: loopback through the system's MIDI service ==================

private command midiStLoopback
   local tOut, tIn, tIns, tIndex, tKey, tEvents, tEvent, tGot, tDeadline, tSysex
   put midiOpenVirtualOutput("midixt Loopback") into tOut
   if tOut is 0 then
      midiStSkip "the loopback", "no virtual output here: " & midiLastError()
      exit midiStLoopback
   end if
   -- The virtual output is a source every MIDI client can read, this one
   -- included: find it among the inputs.
   put midiInputPorts() into tIns
   put -1 into tIndex
   repeat for each key tKey in tIns
      if tIns[tKey] contains "midixt Loopback" then put tKey - 1 into tIndex
   end repeat
   if tIndex < 0 then
      midiClose tOut
      midiStSkip "the loopback", "the virtual output is not listed as an input here"
      exit midiStLoopback
   end if
   put midiOpenInput(tIndex) into tIn
   midiStAssert "opened the virtual output as an input", (tIn > 0)
   if tIn is 0 then
      midiClose tOut
      exit midiStLoopback
   end if
   midiIgnoreTypes tIn, false, true, true        -- let SysEx through
   put numToByte(240) & numToByte(125) & numToByte(1) & numToByte(2) & numToByte(247) into tSysex
   midiNoteOn tOut, 2, 61, 101
   midiControlChange tOut, 3, 74, 9
   midiPitchBend tOut, 4, 12345
   midiSend tOut, tSysex
   -- the service delivers in well under a millisecond; allow it half a second
   put the milliseconds + 500 into tDeadline
   repeat until the number of lines of tGot >= 4 or the milliseconds > tDeadline
      put midiPoll(tIn) into tEvents
      repeat for each element tEvent in tEvents
         put tEvent["kind"] && tEvent["channel"] && tEvent["data1"] && tEvent["data2"] \
               && tEvent["value14"] && the number of bytes in tEvent["bytes"] & return after tGot
      end repeat
      wait 5 milliseconds with messages
   end repeat
   midiStAssert "four messages came back", (the number of lines of tGot is 4)
   midiStAssert "  a note on, channel 2", (line 1 of tGot is "noteOn 2 61 101  3")
   midiStAssert "  a controller, channel 3", (line 2 of tGot is "controlChange 3 74 9  3")
   midiStAssert "  a pitch bend of 12345, channel 4", (word 1 to 2 of line 3 of tGot is "pitchBend 4" and word 5 of line 3 of tGot is 12345)
   midiStAssert "  the SysEx, all 5 bytes", (word 1 of line 4 of tGot is "sysex" and word -1 of line 4 of tGot is 5)
   if the number of lines of tGot is not 4 then
      put return & "    (got:" & return & tGot & ")" after sMidiStLog
   end if
   midiClose tIn
   midiClose tOut
end midiStLoopback

-- ===== reporting =============================================================

private command midiStSection pTitle
   put return & return & "== " & pTitle & " ==" after sMidiStLog
end midiStSection

private command midiStAssert pName, pOk
   if pOk then
      add 1 to sMidiStPass
      put return & "  [PASS] " & pName after sMidiStLog
   else
      add 1 to sMidiStFail
      put return & "  [FAIL] " & pName after sMidiStLog
   end if
end midiStAssert

private command midiStSkip pName, pWhy
   add 1 to sMidiStSkip
   put return & "  [SKIP] " & pName & " (" & pWhy & ")" after sMidiStLog
end midiStSkip

private command midiStShowResults
   -- Mirror the log into a field if we can; harmless if there is no card. The
   -- colours are set, not inherited: a dark desktop theme otherwise paints
   -- the text white on the field's white.
   try
      if there is not a field "MIDIResults" then
         create field "MIDIResults"
         set the rect of field "MIDIResults" to "16,16,640,560"
         set the dontWrap of field "MIDIResults" to true
         set the opaque of field "MIDIResults" to true
         set the backgroundColor of field "MIDIResults" to "255,255,255"
         set the foregroundColor of field "MIDIResults" to "0,0,0"
      end if
      set the text of field "MIDIResults" to sMidiStLog
   end try
end midiStShowResults
