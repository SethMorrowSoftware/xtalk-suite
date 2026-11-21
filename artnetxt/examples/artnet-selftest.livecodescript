-- artnet-selftest.livecodescript
-- ---------------------------------------------------------------------------
-- HARDWARE-FREE self-test for the artnetxt extension, runnable inside
-- OpenXTalk. It needs NO lighting gear: it reads the extension's own packets
-- back, and sends one to itself.
--
-- HOW TO RUN
--   1. Install (or Test-load) the artnetxt extension in OXT.
--   2. Paste this whole script into a stack or card script.
--   3. In the Message Box, run:   put runArtnetSelfTest()
--      (an "ArtnetResults" field is created/updated if a card is open, and the
--       full log is also returned to the Message Box.)
--
-- WHAT IT PROVES, in two tiers:
--   Tier 1  build -> parse round trips, the exact bytes of the format's
--           byte-order traps, an ArtPollReply with its ports read back, and
--           the quiet refusals. No sockets.
--   Tier 2  an ArtDmx loopback over a real UDP socket to 127.0.0.1. No
--           hardware, but it depends on the engine's datagram-socket path.
--           Its result arrives asynchronously, a moment after the tally.
--
-- This is the Art-Net third of ShowControl's selftest.livecodescript (oscxt
-- and midixt carry the other two), with the reply's ports added and a Tier 2
-- that checks the levels it gets back (ShowControl's printed PASS for any
-- ArtDmx). tests/lcs/selftest_test.livecodescript and
-- tests/lcs/udp_test.livecodescript run it headlessly on every change.
-- ---------------------------------------------------------------------------

local sArtnetStPass, sArtnetStFail, sArtnetStLog, sArtnetStLoopPort

-- ===== entry point =========================================================

function runArtnetSelfTest
   put 0 into sArtnetStPass
   put 0 into sArtnetStFail
   put "artnetxt hardware-free self-test" into sArtnetStLog

   artnetStSection "TIER 1 - Art-Net build -> parse (no sockets)"
   artnetStDmx
   artnetStLengths
   artnetStPoll
   artnetStReply
   artnetStQuietFailures

   artnetStSection "TIER 2 - ArtDmx UDP loopback to 127.0.0.1 (no hardware)"
   artnetStStartLoopback

   put return & "==================================================" after sArtnetStLog
   put return & "  " & sArtnetStPass & " passed, " & sArtnetStFail & " failed (Tier 1)" after sArtnetStLog
   put return & "  The Tier 2 loopback result arrives asynchronously below." after sArtnetStLog
   artnetStShowResults
   return sArtnetStLog
end runArtnetSelfTest

-- The full log so far, INCLUDING the Tier 2 line that arrived asynchronously
-- after runArtnetSelfTest returned (an automated harness reads it after
-- pumping events; tests/lcs/udp_test does).
function artnetSelfTestLog
   return sArtnetStLog
end artnetSelfTestLog

-- ===== Tier 1 ================================================================

private command artnetStDmx
   local tCh, tPkt, tParsed
   put numToByte(255) & numToByte(128) & numToByte(0) & numToByte(64) into tCh
   put artnetBuildDmx(0, tCh) into tPkt
   artnetStAssert "artnetBuildDmx returns a packet", (tPkt is not empty)
   artnetStAssert "packet length is 18 + 4", ((the number of bytes in tPkt) is 22)
   artnetStAssert "it starts with the Art-Net ID", ((byte 1 to 8 of tPkt) is ("Art-Net" & numToByte(0)))

   -- the byte-order traps, checked byte for byte (1-based indices)
   artnetStAssert "OpCode is little-endian (00 50)", \
         (byteToNum(byte 9 of tPkt) is 0 and byteToNum(byte 10 of tPkt) is 80)
   artnetStAssert "ProtVer is big-endian (00 0E)", \
         (byteToNum(byte 11 of tPkt) is 0 and byteToNum(byte 12 of tPkt) is 14)
   artnetStAssert "Length is big-endian (00 04)", \
         (byteToNum(byte 17 of tPkt) is 0 and byteToNum(byte 18 of tPkt) is 4)

   put artnetParseDmx(tPkt) into tParsed
   artnetStAssert "opcode is ArtDmx", (tParsed["opcode"] is "ArtDmx")
   artnetStAssert "universe is 0", (tParsed["universe"] is 0)
   artnetStAssert "length is 4", (tParsed["length"] is 4)
   artnetStAssert "channel 1 round-trips (255)", (byteToNum(byte 1 of tParsed["channels"]) is 255)
   artnetStAssert "channel 4 round-trips (64)", (byteToNum(byte 4 of tParsed["channels"]) is 64)

   -- universe split: 258 -> SubUni 2, Net 1; and the top of the range
   put artnetBuildDmx(258, tCh) into tPkt
   artnetStAssert "universe 258 is SubUni 2 then Net 1 on the wire", \
         (byteToNum(byte 15 of tPkt) is 2 and byteToNum(byte 16 of tPkt) is 1)
   put artnetParseDmx(tPkt) into tParsed
   artnetStAssert "universe 258 round-trips", (tParsed["universe"] is 258)
   put artnetParseDmx(artnetBuildDmx(32767, tCh)) into tParsed
   artnetStAssert "universe 32767 (the highest) round-trips", (tParsed["universe"] is 32767)
end artnetStDmx

private command artnetStLengths
   local tParsed, tMany
   put artnetParseDmx(artnetBuildDmx(0, numToByte(10) & numToByte(20) & numToByte(30))) into tParsed
   artnetStAssert "an odd channel count is padded to even (4)", (tParsed["length"] is 4)
   artnetStAssert "  with level 0", (byteToNum(byte 4 of tParsed["channels"]) is 0)
   put artnetParseDmx(artnetBuildDmx(0, empty)) into tParsed
   artnetStAssert "no levels at all sends the minimum of 2", (tParsed["length"] is 2)
   repeat 600 times
      put numToByte(7) after tMany
   end repeat
   put artnetParseDmx(artnetBuildDmx(0, tMany)) into tParsed
   artnetStAssert "600 levels are cut to the 512 a universe holds", (tParsed["length"] is 512)
end artnetStLengths

private command artnetStPoll
   local tPkt
   put artnetBuildPoll() into tPkt
   artnetStAssert "ArtPoll is the exact 14 bytes", \
         (artnetStHex(tPkt) is "4172742d4e6574000020000e0000")
end artnetStPoll

-- A full Art-Net 4 ArtPollReply (239 bytes) from a four-port node: outputs on
-- ports 1, 2 and 4, inputs on ports 3 and 4. The bytes are the shared vector
-- "four ports: two outputs, an input, one both" (tests/vectors/artnet.json),
-- which the clean-room codec checks.
private command artnetStReply
   local tHex, tNode
   put "4172742d4e65740000210a00000736190102010200000000000051756164206e" into tHex
   put "6f64650000000000000000006172746e6574787420342d706f7274206e6f6465" after tHex
   put "0000000000000000000000000000000000000000000000000000000000000000" after tHex
   put "0000000000000000000000002330303031205b303034325d20506f776572204f" after tHex
   put "6e205465737473207375636365737366756c0000000000000000000000000000" after tHex
   put "0000000000000000000000000004808040c00000000000000000000005060304" after tHex
   put "000600000000000000001a2b3c4d5e0a00000701000000000000000000000000" after tHex
   put "000000000000000000000000000000" after tHex
   put artnetParseReply(binaryEncode("H*", tHex)) into tNode
   artnetStAssert "the reply is 239 bytes", ((the length of tHex) is 478)
   artnetStAssert "ArtPollReply parses", (tNode["opcode"] is "ArtPollReply")
   artnetStAssert "  ip 10.0.0.7, port 6454", (tNode["ip"] is "10.0.0.7" and tNode["port"] is 6454)
   artnetStAssert "  names", (tNode["shortName"] is "Quad node" and tNode["longName"] is "artnetxt 4-port node")
   artnetStAssert "  node report", (tNode["nodeReport"] is "#0001 [0042] Power On Tests successful")
   artnetStAssert "  three output universes: 291, 292, 294", \
         (artnetStList(tNode["outputUniverses"]) is "291,292,294")
   artnetStAssert "  two input universes: 293, 294", (artnetStList(tNode["inputUniverses"]) is "293,294")
   artnetStAssert "  MAC and bind index", (tNode["mac"] is "00:1a:2b:3c:4d:5e" and tNode["bindIndex"] is 1)
end artnetStReply

private command artnetStQuietFailures
   local tParsed
   artnetStAssert "universe 40000 builds nothing", (artnetBuildDmx(40000, numToByte(1)) is empty)
   artnetStAssert "  and artnetLastError says why", (artnetLastError() is not empty)
   put artnetParseDmx("not art-net at all") into tParsed
   artnetStAssert "garbage reads as no ArtDmx", (tParsed["opcode"] is empty)
   artnetStAssert "  and says why", (artnetLastError() is not empty)
   put artnetParseReply(artnetBuildPoll()) into tParsed
   artnetStAssert "an ArtPoll is not an ArtPollReply", (tParsed["opcode"] is empty)
end artnetStQuietFailures

-- ===== Tier 2: real UDP loopback to 127.0.0.1 (no hardware) =================
-- Sends one ArtDmx to ourselves over a genuine datagram socket. The result
-- arrives asynchronously (in artnetStLoopbackArrived), so it appends to the
-- log a moment later rather than in the pass/fail tally above.

private command artnetStStartLoopback
   put 9996 into sArtnetStLoopPort
   try
      close socket sArtnetStLoopPort   -- an accepted socket is named by its port alone
   end try
   accept datagram connections on port sArtnetStLoopPort with message "artnetStLoopbackArrived"
   send "artnetStSendLoopback" to me in 200 milliseconds
   put return & "    (loopback listener opened on udp:" & sArtnetStLoopPort \
         & " -- watch for the result below)" after sArtnetStLog
end artnetStStartLoopback

command artnetStSendLoopback
   -- The engine only writes to an OPEN socket (an unopened "host:port" name is
   -- "socket is not open" and nothing is sent), so open it first.
   if ("127.0.0.1:" & sArtnetStLoopPort) is not among the lines of the openSockets then
      open datagram socket to ("127.0.0.1:" & sArtnetStLoopPort)
   end if
   write artnetBuildDmx(7, numToByte(200) & numToByte(100)) to socket ("127.0.0.1:" & sArtnetStLoopPort)
end artnetStSendLoopback

-- OXT-Beyond calls a datagram message with (sender "host:port", data, socket).
on artnetStLoopbackArrived pSender, pData
   local tFrame, tLine
   -- The engine calls this later, with whatever stack is in front: pin the
   -- stack the results field belongs to (the suite's engine note 5.3).
   set the defaultStack to the short name of this stack
   put artnetParseDmx(pData) into tFrame
   if tFrame["opcode"] is "ArtDmx" and tFrame["universe"] is 7 \
         and byteToNum(byte 1 of tFrame["channels"]) is 200 \
         and byteToNum(byte 2 of tFrame["channels"]) is 100 then
      put "  [PASS] Tier 2 Art-Net loopback: universe 7, levels 200 and 100 round-tripped over UDP" into tLine
   else
      put "  [FAIL] Tier 2 Art-Net loopback: got opcode '" & tFrame["opcode"] & "', universe '" \
            & tFrame["universe"] & "'" into tLine
   end if
   put return & tLine after sArtnetStLog
   artnetStShowResults
   -- accepted datagram connections keep delivering; nothing to re-read
end artnetStLoopbackArrived

-- Stop the Tier 2 listener (the harness calls this so the engine quits cleanly).
command artnetStopSelfTest
   try
      close socket sArtnetStLoopPort
   end try
   try
      close socket ("127.0.0.1:" & sArtnetStLoopPort)
   end try
end artnetStopSelfTest

-- ===== helpers and reporting =================================================

private function artnetStHex pData
   local tHex
   get binaryDecode("H*", pData, tHex)   -- returns a COUNT; the hex lands in tHex
   return tHex
end artnetStHex

-- A list the extension returned (a numbered array in Script) as "a,b,c".
private function artnetStList pList
   local tOut, tIndex
   repeat with tIndex = 1 to the number of elements of pList
      put pList[tIndex] & comma after tOut
   end repeat
   delete the last char of tOut
   return tOut
end artnetStList

private command artnetStSection pTitle
   put return & return & "== " & pTitle & " ==" after sArtnetStLog
end artnetStSection

private command artnetStAssert pName, pOk
   if pOk then
      add 1 to sArtnetStPass
      put return & "  [PASS] " & pName after sArtnetStLog
   else
      add 1 to sArtnetStFail
      put return & "  [FAIL] " & pName after sArtnetStLog
   end if
end artnetStAssert

private command artnetStShowResults
   -- Mirror the log into a field if we can; harmless if there is no card. The
   -- colours are set, not inherited: a dark desktop theme otherwise paints
   -- the text white on the field's white.
   try
      if there is not a field "ArtnetResults" then
         create field "ArtnetResults"
         set the rect of field "ArtnetResults" to "16,16,640,560"
         set the dontWrap of field "ArtnetResults" to true
         set the opaque of field "ArtnetResults" to true
         set the backgroundColor of field "ArtnetResults" to "255,255,255"
         set the foregroundColor of field "ArtnetResults" to "0,0,0"
      end if
      set the text of field "ArtnetResults" to sArtnetStLog
   end try
end artnetStShowResults
