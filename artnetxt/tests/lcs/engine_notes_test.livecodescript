script "ArtnetEngineNotesTest"
-- ---------------------------------------------------------------------------
-- What the engine does that artnetxt's helpers are built around, pinned in a
-- real engine: the suite's engine note 2.13 (numToByte WRAPS, and a fraction
-- is rounded or truncated by where the value came from). Each check is an
-- OBSERVATION, not a wish: an engine that changes one fails here, and the note
-- (docs/OXT-ENGINE-NOTES.md in the suite) changes with it.
--
-- The calls are written out in each test on purpose: passing a value to a
-- helper handler makes it a PARAMETER, which is one of the cases being told
-- apart.
-- ---------------------------------------------------------------------------
-- requires:

on TestNumToByteWraps
   TestAssertEqual "256 wraps to 0", byteToNum(numToByte(256)), 0
   TestAssertEqual "257 wraps to 1", byteToNum(numToByte(257)), 1
   TestAssertEqual "300 wraps to 44", byteToNum(numToByte(300)), 44
   TestAssertEqual "-1 wraps to 255", byteToNum(numToByte(-1)), 255
end TestNumToByteWraps

-- Rounded half away from zero: a literal in the call, a computed value, and
-- text never read as a number.
on TestFractionsRoundFromLiteralsComputationsAndText
   local tText
   TestAssertEqual "the literal 255.6 in the call rounds to 256: byte 0", byteToNum(numToByte(255.6)), 0
   TestAssertEqual "the literal 127.5 in the call rounds to 128", byteToNum(numToByte(127.5)), 128
   TestAssertEqual "computed 2556 / 10 rounds to 256: byte 0", byteToNum(numToByte(2556 / 10)), 0
   TestAssertEqual "computed 255 / 2 rounds to 128", byteToNum(numToByte(255 / 2)), 128
   put "255.6,1.6" into tText
   TestAssertEqual "text 255.6 rounds to 256: byte 0", byteToNum(numToByte(item 1 of tText)), 0
   TestAssertEqual "text 1.6 rounds to 2", byteToNum(numToByte(item 2 of tText)), 2
end TestFractionsRoundFromLiteralsComputationsAndText

-- Truncated toward zero: a variable or parameter holding a number that was
-- written as a literal (its text keeps the number the parser read).
on TestFractionsTruncateWhenHeldFromALiteral
   local tN
   put 255.6 into tN
   TestAssertEqual "a variable put from the literal 255.6 truncates to 255", byteToNum(numToByte(tN)), 255
   put 127.5 into tN
   TestAssertEqual "  and from 127.5 to 127", byteToNum(numToByte(tN)), 127
   TestAssertEqual "a parameter given the literal 255.6 truncates to 255", engineNoteByteOf(255.6), 255
   put 66.6 into tN
   TestAssertEqual "numToChar converts the same way: a variable gives 66", charToNum(numToChar(tN)), 66
   TestAssertEqual "  and the literal itself 67", charToNum(numToChar(66.6)), 67
end TestFractionsTruncateWhenHeldFromALiteral

function engineNoteByteOf pX
   return byteToNum(numToByte(pX))
end engineNoteByteOf

-- Reading text as a whole number stores the ROUNDED number back on the text,
-- and arithmetic reads that afterwards. (Compared with a letter in front, so
-- `is` compares texts and not the numbers they read as: engine note 2.11.)
on TestReadingTextAsAWholeNumberRewritesIt
   local tText, tN
   put "255.6,x" into tText
   put item 1 of tText into tN
   get numToByte(tN)
   TestAssertEqual "after numToByte, tN + 0 is the rounded 256", tN + 0, 256
   TestAssert "while tN still shows 255.6", ("x" & tN) is "x255.6"
end TestReadingTextAsAWholeNumberRewritesIt

-- What the helpers do instead: round is arithmetic and reads every source
-- the same way, rounding half away from zero.
on TestRoundReadsEverySourceTheSame
   local tN, tText
   TestAssertEqual "round(127.5) is 128", round(127.5), 128
   TestAssertEqual "round(-0.5) is -1", round(-0.5), -1
   put 127.5 into tN
   TestAssertEqual "round of a variable put from 127.5 is 128", round(tN), 128
   put "127.5" into tText
   TestAssertEqual "round of the text 127.5 is 128", round(item 1 of tText), 128
   put 255.6 into tN
   TestAssertEqual "the helpers' clamp keeps 255.6 at 255", byteToNum(numToByte(max(0, min(255, round(tN))))), 255
end TestRoundReadsEverySourceTheSame
