script "MidiSelfTestTest"
-- ---------------------------------------------------------------------------
-- Runs the SHIPPED hardware-free self-test (examples/midi-selftest.livecodescript)
-- headlessly, exactly as a user would after pasting it into a stack:
--     put runMidiSelfTest()
-- over the MOCK library, and asserts it reports zero failures. That turns the
-- in-OXT self-test from a manual ritual into a CI gate, and proves the example
-- itself still compiles and runs against the current extension. (Its Tier 3,
-- the loopback through the system's MIDI service, skips over the mock:
-- selftest_hw_test runs it on the real library.)
-- ---------------------------------------------------------------------------
-- requires: midixt-mock

on TestShippedSelfTestPasses
   local tPath, tLog, tTally, tBefore
   MockReset
   -- the shim keeps one enumerator per direction open for good: count them in
   get midiInputPorts()
   get midiOutputPorts()
   put MockLiveWrappers() into tBefore
   put $SC_HELPERS into tPath
   set the itemDelimiter to "/"
   put "midi-selftest.livecodescript" into the last item of tPath
   set the itemDelimiter to ","
   TestLoadScriptAsLibrary tPath, "MidiSelfTest"
   put runMidiSelfTest() into tLog
   TestDiagnostic tLog
   put line (lineOffset(" passed, ", tLog)) of tLog into tTally
   TestAssert "the self-test printed a tally", tTally is not empty
   TestAssert "0 failed  (" & word 1 to 6 of tTally & ")", tTally contains " 0 failed"
   TestAssert "it ran a meaningful number of checks", word 1 of tTally >= 30
   TestAssertEqual "no ports left open", MockLiveWrappers(), tBefore
end TestShippedSelfTestPasses
