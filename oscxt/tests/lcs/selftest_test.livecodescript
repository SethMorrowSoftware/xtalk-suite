script "OscSelfTestTest"
-- ---------------------------------------------------------------------------
-- Runs the SHIPPED hardware-free self-test (examples/osc-selftest.livecodescript)
-- headlessly, exactly as a user would after pasting it into a stack:
--     put runOscSelfTest()
-- and asserts its synchronous tier (1) reports zero failures. That turns the
-- in-OXT self-test from a manual ritual into a CI gate, and proves the example
-- itself still compiles and runs against the current extension. (Tier 2 -- the
-- async UDP loopback -- is covered by udp_test, which only runs where the
-- engine can deliver socket events without a UI.)
-- ---------------------------------------------------------------------------
-- requires: oscxt

on TestShippedSelfTestPasses
   local tPath, tLog, tTally
   put $SC_HELPERS into tPath
   set the itemDelimiter to "/"
   put "osc-selftest.livecodescript" into the last item of tPath
   set the itemDelimiter to ","
   TestLoadScriptAsLibrary tPath, "OscSelfTest"
   put runOscSelfTest() into tLog
   TestDiagnostic tLog
   put line (lineOffset("passed,", tLog)) of tLog into tTally
   TestAssert "the self-test printed a tally", tTally is not empty
   TestAssert "Tier 1: 0 failed  (" & word 1 to 4 of tTally & ")", tTally contains " 0 failed"
   TestAssert "Tier 1 ran a meaningful number of checks", word 1 of tTally >= 25
   -- stop the Tier 2 listener the self-test opened, so the engine can quit cleanly
   oscStopSelfTest
end TestShippedSelfTestPasses
