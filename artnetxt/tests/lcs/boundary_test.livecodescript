script "ArtnetBoundaryTest"
-- ---------------------------------------------------------------------------
-- The LiveCode Script <-> LCB boundary, in a real engine (-ui, no window).
--
-- Every bug in ShowControl's first OXT runtime pass lived HERE, where no
-- lc-run test can reach: numbers arriving as Numbers or Strings depending on
-- how they were made, Data vs String, LCB lists arriving in Script as arrays.
-- These tests drive the extension exactly as a user's stack does.
-- ---------------------------------------------------------------------------
-- requires:

on TestArtnetFromScript
   local tCh, tPkt, tP
   put numToByte(255) & numToByte(128) & numToByte(0) & numToByte(64) into tCh
   put artnetBuildDmx(258, tCh) into tPkt
   TestAssertEqual "ArtDmx bytes from Script", TestHex(tPkt), "4172742d4e6574000050000e000002010004ff800040"
   put artnetParseDmx(tPkt) into tP
   TestAssertEqual "universe", tP["universe"], 258
   TestAssertEqual "channel 1 via byteToNum", byteToNum(byte 1 of tP["channels"]), 255
   -- a Script STRING for the channel data is accepted as its bytes
   put artnetParseDmx(artnetBuildDmx(0, "AB")) into tP
   TestAssertEqual "string channels become bytes", TestHex(tP["channels"]), "4142"
end TestArtnetFromScript

-- A universe typed into a field arrives as text; a computed one as a number.
-- Both cross into the LCB Integer parameter.
on TestUniverseAsTextOrNumber
   local tP
   put artnetParseDmx(artnetBuildDmx("258", numToByte(1))) into tP
   TestAssertEqual "text 258", tP["universe"], 258
   put artnetParseDmx(artnetBuildDmx(256 + 2, numToByte(1))) into tP
   TestAssertEqual "computed 258", tP["universe"], 258
end TestUniverseAsTextOrNumber

-- A FRACTIONAL universe is not refused (LCB's Integer is Number) and is cut
-- toward zero where it becomes a byte (the suite's engine note 6.15).
on TestFractionalUniverseTruncates
   local tP
   put artnetParseDmx(artnetBuildDmx(258.9, numToByte(1))) into tP
   TestAssertEqual "258.9 sends universe 258", tP["universe"], 258
end TestFractionalUniverseTruncates

-- Refusals never throw: they return empty, and artnetLastError says why.
on TestQuietFailures
   local tP
   TestAssertEqual "out-of-range universe builds nothing", artnetBuildDmx(40000, numToByte(1)), empty
   TestAssert "artnetLastError explains", artnetLastError() contains "out of range"
   TestAssertEqual "a negative one too", artnetBuildDmx(-1, numToByte(1)), empty
   put artnetParseDmx("not an art-net packet") into tP
   TestAssertEqual "garbage reads as no ArtDmx", tP["opcode"], empty
   TestAssert "  and says why", artnetLastError() contains "not an Art-Net packet"
   TestAssertEqual "  and has no universe (empty, not a throw, in Script)", tP["universe"], empty
   put artnetParseReply(artnetBuildDmx(1, numToByte(1))) into tP
   TestAssertEqual "an ArtDmx is not an ArtPollReply", tP["opcode"], empty
end TestQuietFailures

-- An EMPTY value into a typed Integer parameter is an engine type-conversion
-- error at the boundary (the suite's engine note 6.4) -- it throws. Pin that,
-- so the docs' advice (never pass empty) stays true.
on TestEmptyIntoIntegerThrows
   local tThrew, tErr
   put false into tThrew
   try
      get artnetBuildDmx(empty, numToByte(1))
   catch tErr
      put true into tThrew
   end try
   TestAssert "empty universe throws a type error (documented)", tThrew
end TestEmptyIntoIntegerThrows

-- The reply's port lists are LCB Lists: in Script they are numbered arrays,
-- 1 to N, which `repeat for each element` walks in order (an empty list is an
-- array with no elements).
on TestReplyListsArriveAsArrays
   local tHex, tNode, tU, tSeen
   put "4172742d4e65740000210a00000736190102010200000000000051756164206e" into tHex
   put "6f64650000000000000000006172746e6574787420342d706f7274206e6f6465" after tHex
   put "0000000000000000000000000000000000000000000000000000000000000000" after tHex
   put "0000000000000000000000002330303031205b303034325d20506f776572204f" after tHex
   put "6e205465737473207375636365737366756c0000000000000000000000000000" after tHex
   put "0000000000000000000000000004808040c00000000000000000000005060304" after tHex
   put "000600000000000000001a2b3c4d5e0a00000701000000000000000000000000" after tHex
   put "000000000000000000000000000000" after tHex
   put artnetParseReply(TestUnhex(tHex)) into tNode
   TestAssertEqual "it parses", tNode["opcode"], "ArtPollReply"
   TestAssert "outputUniverses is an array", tNode["outputUniverses"] is an array
   TestAssertEqual "with three elements", the number of elements of tNode["outputUniverses"], 3
   TestAssertEqual "numbered from 1", tNode["outputUniverses"][1], 291
   TestAssertEqual "  to 3", tNode["outputUniverses"][3], 294
   repeat for each element tU in tNode["outputUniverses"]
      put tU & "," after tSeen
   end repeat
   TestAssertEqual "repeat for each element walks them in order", tSeen, "291,292,294,"
   put artnetParseReply(TestUnhex("4172742d4e6574000021" & "0a000009" & "3619" & "0000" & "0000" & "000000000000")) into tNode
   TestAssertEqual "a short reply's empty list has no elements", the number of elements of tNode["inputUniverses"], 0
   TestAssertEqual "  and its MAC is empty", tNode["mac"], empty
end TestReplyListsArriveAsArrays
