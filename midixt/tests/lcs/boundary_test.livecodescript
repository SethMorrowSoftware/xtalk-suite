script "MidiBoundaryTest"
-- ---------------------------------------------------------------------------
-- The LiveCode Script <-> LCB boundary, in a real engine (-ui, no window).
--
-- Every bug in ShowControl's first OXT runtime pass lived at this boundary,
-- where no C test and no lc-run test can reach: what a Script value becomes
-- when it meets a typed LCB parameter, and what an LCB List or Array becomes
-- when it comes back. These tests drive the extension exactly as a user's
-- stack does, over the MOCK midixt library (no MIDI service).
-- ---------------------------------------------------------------------------
-- requires: midixt-mock

on TestSetup
   MockReset
end TestSetup

on TestMidiFromScript
   local tDec, tPorts, tIn, tOut, tEv
   put midiDecode(numToByte(229) & numToByte(0) & numToByte(64)) into tDec
   TestAssertEqual "midiDecode kind", tDec["kind"], "pitchBend"
   TestAssertEqual "midiDecode value14", tDec["value14"], 8192
   put midiInputPorts() into tPorts
   TestAssertEqual "port list arrives as a Script array", the number of elements of tPorts, 2
   TestAssertEqual "port name", tPorts[1], "MockPort-0-aLongishName"
   MockSetLoopback true, 0
   put midiOpenVirtualInput("lcs in") into tIn
   put midiOpenVirtualOutput("lcs out") into tOut
   midiControlChange tOut, 2, 7, 100
   put midiPoll(tIn) into tEv
   TestAssertEqual "polled one event", the number of elements of tEv, 1
   TestAssertEqual "kind", tEv[1]["kind"], "controlChange"
   TestAssertEqual "channel", tEv[1]["channel"], 2
   TestAssertEqual "value", tEv[1]["data2"], 100
   midiClose tIn
   midiClose tOut
end TestMidiFromScript

-- A poll's list arrives as an array keyed 1..N that `repeat for each element`
-- walks in order, and each record's raw bytes are binary data.
on TestPollRecordsInScript
   local tIn, tOut, tEv, tEvent, tKinds
   MockSetLoopback true, 2500
   put midiOpenVirtualInput("records in") into tIn
   put midiOpenVirtualOutput("records out") into tOut
   midiNoteOn tOut, 1, 60, 100
   midiProgramChange tOut, 3, 5
   midiPitchBend tOut, 16, 16383
   midiSend tOut, numToByte(240) & numToByte(126) & numToByte(127) & numToByte(247)
   put midiPoll(tIn) into tEv
   TestAssertEqual "four events", the number of elements of tEv, 4
   TestAssertEqual "keyed 1 to 4", line 1 to 4 of (the keys of tEv), "1" & return & "2" & return & "3" & return & "4"
   repeat for each element tEvent in tEv
      put tEvent["kind"] & comma after tKinds
   end repeat
   TestAssertEqual "walked in arrival order", tKinds, "noteOn,programChange,pitchBend,sysex,"
   TestAssertEqual "raw bytes are data", TestHex(tEv[1]["bytes"]), "903c64"
   TestAssertEqual "the sysex arrives whole", TestHex(tEv[4]["bytes"]), "f07e7ff7"
   TestAssertEqual "pitch bend full scale", tEv[3]["value14"], 16383
   TestAssertEqual "channel 16 is 16", tEv[3]["channel"], 16
   TestAssert "delta is a number of seconds", tEv[1]["delta"] is a number
   TestAssert "  (2.5 ms from the mock cable)", abs(tEv[2]["delta"] - 0.0025) < 0.0001
   midiClose tIn
   midiClose tOut
end TestPollRecordsInScript

-- A number the engine kept as text and one it kept as a number cross the same.
on TestNumbersAsTextOrNumbers
   local tOut
   put midiOpenVirtualOutput("numbers") into tOut
   MockSentClear
   midiNoteOn tOut, "1", "60", "100"
   midiNoteOn tOut, 1, 60, 100
   midiNoteOn tOut, 0 + 1, 59 + 1, 99 + 1
   TestAssertEqual "three sends", MockSentCount(), 3
   TestAssertEqual "text", TestHex(MockSent(1)), "903c64"
   TestAssertEqual "number", TestHex(MockSent(2)), "903c64"
   TestAssertEqual "computed", TestHex(MockSent(3)), "903c64"
   midiClose tOut
end TestNumbersAsTextOrNumbers

-- A FRACTIONAL number into an LCB Integer parameter is not refused (LCB's
-- Integer is Number) and is TRUNCATED where it becomes a byte (the suite's
-- engine note 6.15, first observed by this test): 60.6 plays note 60, not 61,
-- and nothing says so. The docs ask for whole numbers.
on TestFractionalIntoIntegerTruncates
   local tOut, tError
   put midiOpenVirtualOutput("fraction") into tOut
   MockSentClear
   try
      midiNoteOn tOut, 1, 60.6, 100
      midiNoteOn tOut, 1, 99.99, 127.9
   catch tError
   end try
   TestAssertEqual "no throw", tError, empty
   TestAssertEqual "60.6 sent note 60", TestHex(MockSent(1)), "903c64"
   TestAssertEqual "99.99 and 127.9 sent 99 and 127", TestHex(MockSent(2)), "90637f"
   midiClose tOut
end TestFractionalIntoIntegerTruncates

-- An EMPTY value into a typed Integer parameter is a hard runtime error (the
-- suite's engine note 6.4): the helpers and demos must never pass one.
on TestEmptyIntoIntegerThrows
   local tOut, tError, tThrew
   put midiOpenVirtualOutput("empty") into tOut
   put false into tThrew
   try
      midiNoteOn tOut, 1, empty, 100
   catch tError
      put true into tThrew
   end try
   TestAssert "empty into an Integer parameter throws", tThrew
   TestAssertEqual "and nothing was sent", MockSentCount(), 0
   midiClose tOut
end TestEmptyIntoIntegerThrows

-- Refusals never throw: they return 0 or do nothing, and midiLastError says why.
on TestRefusalsAreQuiet
   local tH
   put midiOpenOutput(99) into tH
   TestAssertEqual "an out-of-range port gives 0", tH, 0
   TestAssert "  and a reason", midiLastError() contains "out of range"
   midiNoteOn 0, 1, 60, 100
   TestAssert "a send on handle 0 does nothing, and says why", midiLastError() contains "not an open output port"
   TestAssertEqual "a poll of handle 0 is empty", the number of elements of midiPoll(0), 0
   midiClose 0
   midiClose 12345
   TestAssert "closing handles that are not open is harmless", true
   put midiOpenVirtualOutput("bad" & numToChar(0) & "name") into tH
   TestAssertEqual "a name holding a NUL gives 0", tH, 0
   TestAssert "  and a reason", midiLastError() contains "NUL"
end TestRefusalsAreQuiet

-- A port name that is not ASCII crosses as UTF-8 both ways.
on TestUnicodePortName
   local tH, tName
   put "B" & numToCodepoint(252) & "hne " & numToCodepoint(9835) into tName
   put midiOpenVirtualOutput(tName) into tH
   TestAssert "opened", tH > 0
   TestAssertEqual "RtMidi was given the name in UTF-8", MockLastPortName(), tName
   midiClose tH
end TestUnicodePortName
