script "OscBoundaryTest"
-- ---------------------------------------------------------------------------
-- The LiveCode Script <-> LCB boundary, in a real engine (-ui, no window).
--
-- Every bug in ShowControl's first OXT runtime pass lived HERE, where no C test
-- and no lc-run test can reach: [...] literals that do not exist in Script,
-- nested Script arrays arriving in LCB as Arrays not Lists, numbers arriving as
-- Numbers or Strings depending on how they were made, Data vs String. These
-- tests drive the extension exactly as a user's stack does.
-- ---------------------------------------------------------------------------
-- requires: oscxt

-- Script has no [...] list literal: args are built by assignment into a flat
-- numerically keyed array, exactly as scAddArg does.
on TestFlatArgsFromScript
   local tArgs, tData
   put "i" into tArgs[1]
   put 1000 into tArgs[2]
   put "i" into tArgs[3]
   put -1 into tArgs[4]
   put "s" into tArgs[5]
   put "hello" into tArgs[6]
   put "f" into tArgs[7]
   put 1.234 into tArgs[8]
   put "f" into tArgs[9]
   put 5.678 into tArgs[10]
   put oscBuildMessage("/foo", tArgs) into tData
   -- the OSC 1.0 specification's own example, byte for byte
   TestAssertEqual "spec example built from Script numbers", TestHex(tData), \
         "2f666f6f000000002c69697366660000000003e8ffffffff68656c6c6f0000003f9df3b640b5b22d"
end TestFlatArgsFromScript

-- The engine hands a value to LCB as a Number or a String depending on its
-- history. Both must build the same bytes -- with or without the old `& empty`.
on TestNumberStringDuality
   local tA, tB, tC
   put "i" into tA[1]
   put 42 into tA[2]                 -- a literal: arrives as a Number
   put "i" into tB[1]
   put "42" into tB[2]               -- a String
   put "i" into tC[1]
   put 40 + 2 into tC[2]             -- computed
   TestAssertEqual "Number == String", TestHex(oscBuildMessage("/n", tA)), TestHex(oscBuildMessage("/n", tB))
   TestAssertEqual "computed == literal", TestHex(oscBuildMessage("/n", tC)), TestHex(oscBuildMessage("/n", tA))
   put "f" into tA[1]
   put 0.5 into tA[2]
   put "f" into tB[1]
   put (1 / 2) & empty into tB[2]
   TestAssertEqual "float Number == float String", TestHex(oscBuildMessage("/n", tA)), TestHex(oscBuildMessage("/n", tB))
end TestNumberStringDuality

-- Parsed results come back as a Script array: address/types are strings, int
-- args are numbers you can do arithmetic on, string args are strings, blobs
-- are binary data, booleans are true/false.
on TestParsedValuesInScript
   local tArgs, tMsg
   scAddArg tArgs, "i", 7
   scAddArg tArgs, "s", "seven"
   scAddArg tArgs, "b", numToByte(0) & numToByte(255)
   scAddArg tArgs, "T", empty
   scAddArg tArgs, "d", 2.5
   put oscParse(oscBuildMessage("/v", tArgs)) into tMsg
   TestAssertEqual "address", tMsg["address"], "/v"
   TestAssertEqual "types", tMsg["types"], "isbTd"
   TestAssert "int arg is a number", tMsg["args"][1] is a number
   TestAssertEqual "int arg arithmetic", tMsg["args"][1] + 1, 8
   TestAssertEqual "string arg", tMsg["args"][2], "seven"
   TestAssertEqual "blob arg bytes", TestHex(tMsg["args"][3]), "00ff"
   TestAssert "true arg is true", tMsg["args"][4] is true
   TestAssertEqual "double arg", tMsg["args"][5], 2.5
   TestAssertEqual "isBundle is false", tMsg["isBundle"], false
end TestParsedValuesInScript

-- Bundles from Script: the message list is a Script array of binary data, and
-- nested parse results are arrays of arrays.
on TestBundleFromScript
   local tArgs, tMsgs, tBundle, tParsed
   scAddArg tArgs, "i", 1
   put oscBuildMessage("/a", tArgs) into tMsgs[1]
   put empty into tArgs
   scAddArg tArgs, "s", "b"
   put oscBuildMessage("/b", tArgs) into tMsgs[2]
   put oscBuildBundle("1", tMsgs) into tBundle
   TestAssert "bundle built", tBundle is not empty
   put oscParse(tBundle) into tParsed
   TestAssertEqual "is a bundle", tParsed["isBundle"], true
   TestAssertEqual "two messages", the number of elements of tParsed["messages"], 2
   TestAssertEqual "nested access message 2 address", tParsed["messages"][2]["address"], "/b"
   TestAssertEqual "nested access message 2 arg", tParsed["messages"][2]["args"][1], "b"
end TestBundleFromScript

-- Failure is quiet at the boundary: empty results and an error string, never
-- an exception into the user's script.
on TestQuietFailures
   local tMsg, tArgs
   put oscParse("not osc") into tMsg
   TestAssertEqual "garbage parses to no address", tMsg["address"], empty
   TestAssert "garbage reports why", tMsg["error"] is not empty
   TestAssert "oscLastError agrees", oscLastError() is tMsg["error"]
   scAddArg tArgs, "q", 1
   TestAssertEqual "unknown type builds nothing", oscBuildMessage("/x", tArgs), empty
end TestQuietFailures

-- oscVersion is the ABI the loaded library reports; the binding refuses any
-- other (checkABI), so a stale library is an error at the first call, not a
-- crash somewhere later.
on TestAbiFromScript
   TestAssertEqual "oscVersion() is the binding's ABI", oscVersion(), 2
end TestAbiFromScript

-- A COMPUTED script number reaches LCB as a real, and the binding once wrote a
-- real with LCB's "%g" (six significant digits) before the shim parsed it: an
-- integer of a million or more arrived as its first digit. Only args built
-- through scAddArg (whose `& empty` formats with the numberFormat) escaped.
on TestComputedNumbersFromScript
   local tA, tMsg, tMs
   put "i" into tA[1]
   put 1000 * 1234 into tA[2]
   TestAssertEqual "computed 1234000 as i (was 1)", TestHex(oscBuildMessage("/x", tA)), \
         "2f7800002c690000" & "0012d450"
   put the milliseconds into tMs
   put "h" into tA[1]
   put tMs into tA[2]
   put oscParse(oscBuildMessage("/x", tA)) into tMsg
   TestAssert "the milliseconds as h is exact (was 1)", tMsg["args"][1] is (tMs & empty)
   put "d" into tA[1]
   put 1/3 into tA[2]
   -- compared as bytes: the engine's own < and = are not IEEE at this scale
   -- (engine notes 2.10), and 0.333333 vs 1/3 is a byte question anyway
   TestAssertEqual "1/3 as d is the double 3fd5555555555555 (was 0.333333)", \
         TestHex(oscBuildMessage("/x", tA)), "2f7800002c640000" & "3fd5555555555555"
   put "s" into tA[1]
   put 1000 * 1234 into tA[2]
   -- compared as hex: script would call "1.234e+06" and "1234000" EQUAL as numbers
   put oscParse(oscBuildMessage("/x", tA)) into tMsg
   TestAssertEqual "computed 1234000 as s is the text 1234000", \
         TestHex(tMsg["args"][1]), TestHex("1234000")
   put "i" into tA[1]
   put 3000000000 into tA[2]
   TestAssertEqual "3000000000 as i clamps to 2147483647 on every platform", \
         TestHex(oscBuildMessage("/x", tA)), "2f7800002c690000" & "7fffffff"
end TestComputedNumbersFromScript

-- What scripts hand over by mistake must never throw into them: a NUL in any
-- string (the engine threw "cannot export char U+0000" from inside the
-- binding), and a Number where a type code goes (it threw at the call).
on TestMistakesNeverThrowFromScript
   local tA, tData, tThrew, tErr
   put "s" into tA[1]
   put "a" & numToChar(0) & "b" into tA[2]
   put false into tThrew
   try
      put oscBuildMessage("/x", tA) into tData
   catch tErr
      put true into tThrew
   end try
   TestAssert "NUL in a string arg does not throw", not tThrew
   TestAssertEqual "NUL in a string arg builds nothing", tData, empty
   TestAssert "and oscLastError says why", oscLastError() contains "NUL"
   put false into tThrew
   try
      put oscMatch("/a" & numToChar(0), "/a") into tData
   catch tErr
      put true into tThrew
   end try
   TestAssert "NUL in a match pattern does not throw", not tThrew
   TestAssertEqual "NUL in a match pattern matches nothing", tData, false
   put empty into tA
   put 7 into tA[1]
   put 1 into tA[2]
   put false into tThrew
   try
      put oscBuildMessage("/x", tA) into tData
   catch tErr
      put true into tThrew
   end try
   TestAssert "a number as the type code does not throw", not tThrew
   TestAssertEqual "a number as the type code builds nothing", tData, empty
end TestMistakesNeverThrowFromScript

-- A timetag computed in script reaches oscBuildBundle's String parameter.
on TestComputedTimetagFromScript
   local tMsgs, tBundle, tThrew, tParsed, tErr
   put oscBuildMessage("/a", empty) into tMsgs[1]
   put false into tThrew
   try
      put oscBuildBundle(2 + 3, tMsgs) into tBundle
   catch tErr
      put true into tThrew
      TestDiagnostic "oscBuildBundle threw: " & line 1 of tErr
   end try
   TestAssert "a computed timetag does not throw", not tThrew
   put oscParse(tBundle) into tParsed
   TestAssertEqual "a computed timetag is used", tParsed["timetag"], "5"
end TestComputedTimetagFromScript
