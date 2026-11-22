script "MidiSelfTestHwTest"
-- ---------------------------------------------------------------------------
-- The shipped self-test (examples/midi-selftest.livecodescript) over the REAL
-- midixt library: RtMidi over this machine's own MIDI service (ALSA, CoreMIDI
-- or Windows MM). Where there is no service, or no virtual ports (Windows),
-- the tiers that need one SKIP with the reason, and this still asserts that
-- nothing failed and nothing threw.
--
-- MIDIXT_REQUIRE_SERVICE=1 turns those skips into failures: set it where a
-- MIDI service with virtual ports is known to be there (a Linux machine with
-- the ALSA sequencer, a Mac), so the Tier 3 loopback must really run.
-- ---------------------------------------------------------------------------
-- requires: midixt

on TestShippedSelfTestOnTheRealLibrary
   local tPath, tLog, tTally
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
   if $MIDIXT_REQUIRE_SERVICE is "1" then
      TestAssert "MIDIXT_REQUIRE_SERVICE=1: nothing skipped  (" & word 1 to 6 of tTally & ")", \
            tTally contains " 0 skipped"
   else if not (tTally contains " 0 skipped") then
      TestSkip "the loopback through the MIDI service", "no MIDI service with virtual ports here (MIDIXT_REQUIRE_SERVICE=1 makes this a failure)"
   end if
end TestShippedSelfTestOnTheRealLibrary
