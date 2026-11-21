-- osc-selftest.livecodescript
-- ---------------------------------------------------------------------------
-- HARDWARE-FREE self-test for the oscxt extension, runnable inside OpenXTalk.
-- It needs NO controllers or DAWs: it round-trips the extension's own output
-- back through its own input.
--
-- HOW TO RUN
--   1. Install (or Test-load) the oscxt extension in OXT.
--   2. Paste this whole script into a stack or card script.
--   3. In the Message Box, run:   put runOscSelfTest()
--      (an "OSCResults" field is created/updated if a card is open, and the full
--       log is also returned to the Message Box.)
--
-- WHAT IT PROVES, in two tiers:
--   Tier 1  pure build -> parse round-trips, bundles, pattern matching and
--           golden bytes. No sockets. If these pass, Data <-> pointer
--           marshalling works in your engine build.
--   Tier 2  an OSC loopback over a real UDP socket to 127.0.0.1. No hardware,
--           but it depends on the engine's datagram-socket path. Its result
--           arrives asynchronously, a moment after the tally.
--
-- This is the OSC third of ShowControl's selftest.livecodescript (midixt and
-- artnetxt carry the other two). tests/lcs/selftest_test.livecodescript and
-- tests/lcs/udp_test.livecodescript run it headlessly on every change.
-- ---------------------------------------------------------------------------

local sOscStPass, sOscStFail, sOscStLog, sOscStLoopPort
local sOscStLoopFrom   -- each sender the loopback listener heard, a key

-- ===== entry point =========================================================

function runOscSelfTest
   put 0 into sOscStPass
   put 0 into sOscStFail
   put "oscxt hardware-free self-test" into sOscStLog

   oscStSection "TIER 1 - OSC build -> parse (no sockets)"
   oscStRoundTrip
   oscStBundle
   oscStMatch
   oscStGolden
   oscStQuietFailures

   oscStSection "TIER 2 - OSC UDP loopback to 127.0.0.1 (no hardware)"
   oscStStartLoopback

   put return & "==================================================" after sOscStLog
   put return & "  " & sOscStPass & " passed, " & sOscStFail & " failed (Tier 1)" after sOscStLog
   put return & "  The Tier 2 loopback result arrives asynchronously below." after sOscStLog
   oscStShowResults
   return sOscStLog
end runOscSelfTest

-- The full log so far, INCLUDING the Tier 2 line that arrived asynchronously
-- after runOscSelfTest returned (an automated harness reads it after pumping
-- events; tests/lcs/udp_test does).
function oscSelfTestLog
   return sOscStLog
end oscSelfTestLog

-- ===== Tier 1 ================================================================

private command oscStRoundTrip
   local tData, tMsg, tArgs, tBuild, tBig
   -- Build the args by assignment -- xTalk has NO [...] list literal (that is
   -- LiveCode Builder syntax). oscStAddArg appends one type, value pair; the
   -- no-value types (T/F) take an ignored empty value.
   oscStAddArg tBuild, "i", -42
   oscStAddArg tBuild, "f", 0.5
   oscStAddArg tBuild, "s", "hello"
   oscStAddArg tBuild, "d", 3.25
   oscStAddArg tBuild, "T", ""
   oscStAddArg tBuild, "F", ""
   put oscBuildMessage("/test/all", tBuild) into tData
   oscStAssert "oscBuildMessage returns non-empty Data", (tData is not empty)
   oscStAssert "datagram length is a multiple of 4", ((the number of bytes in tData) mod 4 is 0)

   put oscParse(tData) into tMsg
   oscStAssert "parsed isBundle is false", (tMsg["isBundle"] is false)
   oscStAssert "address round-trips", (tMsg["address"] is "/test/all")
   oscStAssert "type tag round-trips (ifsdTF)", (tMsg["types"] is "ifsdTF")

   put tMsg["args"] into tArgs
   oscStAssert "arg 1 int  == -42", (tArgs[1] is -42)
   oscStAssert "arg 2 float ~ 0.5", (abs(tArgs[2] - 0.5) < 0.0001)
   oscStAssert "arg 3 string == hello", (tArgs[3] is "hello")
   oscStAssert "arg 4 double ~ 3.25", (abs(tArgs[4] - 3.25) < 0.0001)
   oscStAssert "arg 5 true  is true", (tArgs[5] is true)
   oscStAssert "arg 6 false is false", (tArgs[6] is false)
   put return & "    (args element count: " & (the number of elements of tArgs) & ")" after sOscStLog

   -- 64-bit int crosses as a decimal STRING end to end.
   oscStAddArg tBig, "h", "9223372036854775807"
   put oscParse(oscBuildMessage("/big", tBig)) into tMsg
   put tMsg["args"] into tArgs
   oscStAssert "int64 round-trips as decimal string", (tArgs[1] is "9223372036854775807")
end oscStRoundTrip

private command oscStBundle
   local tA, tB, tBundle, tParsed, tMsgs, tArgs, tMsgList
   oscStAddArg tArgs, "i", 1
   put oscBuildMessage("/a", tArgs) into tA
   put empty into tArgs                 -- reset the args array for the next message
   oscStAddArg tArgs, "f", 2.0
   put oscBuildMessage("/b", tArgs) into tB
   -- the bundle's message list is also an array, built by assignment
   put tA into tMsgList[1]
   put tB into tMsgList[2]
   put oscBuildBundle("1", tMsgList) into tBundle
   oscStAssert "oscBuildBundle returns non-empty", (tBundle is not empty)

   put oscParse(tBundle) into tParsed
   oscStAssert "parsed isBundle is true", (tParsed["isBundle"] is true)
   oscStAssert "bundle timetag is 1", (tParsed["timetag"] is "1")
   put tParsed["messages"] into tMsgs
   oscStAssert "bundle has 2 messages", ((the number of elements of tMsgs) is 2)
   oscStAssert "sub-message 1 is /a", (tMsgs[1]["address"] is "/a")
   oscStAssert "sub-message 2 is /b", (tMsgs[2]["address"] is "/b")
end oscStBundle

private command oscStMatch
   oscStAssert "'*' matches within a segment", oscMatch("/1/fader*", "/1/fader1")
   oscStAssert "'*' does not cross '/'", (not oscMatch("/*", "/a/b"))
   oscStAssert "'?' matches one char", oscMatch("/fader?", "/fader7")
   oscStAssert "'[0-9]' range matches", oscMatch("/ch[0-9]", "/ch5")
   oscStAssert "'[!0-9]' negation excludes", (not oscMatch("/ch[!0-9]", "/ch5"))
   oscStAssert "'{foo,bar}' alternation matches", oscMatch("/{foo,bar}/x", "/bar/x")
   oscStAssert "literal mismatch fails", (not oscMatch("/a/b", "/a/c"))
end oscStMatch

-- The OSC 1.0 specification's own example message, byte for byte: what another
-- implementation reads is what this one writes.
private command oscStGolden
   local tArgs, tHex, tData, tIndex
   oscStAddArg tArgs, "i", 1000
   oscStAddArg tArgs, "i", -1
   oscStAddArg tArgs, "s", "hello"
   oscStAddArg tArgs, "f", 1.234
   oscStAddArg tArgs, "f", 5.678
   put oscBuildMessage("/foo", tArgs) into tData
   put empty into tHex
   repeat with tIndex = 1 to the number of bytes in tData
      put format("%02x", byteToNum(byte tIndex of tData)) after tHex
   end repeat
   oscStAssert "the OSC 1.0 spec example, byte for byte", \
         (tHex is "2f666f6f000000002c69697366660000000003e8ffffffff68656c6c6f0000003f9df3b640b5b22d")
end oscStGolden

-- Failure is quiet at the boundary: an empty result and a reason, never an
-- exception into the caller's script.
private command oscStQuietFailures
   local tMsg, tArgs
   put oscParse("not osc") into tMsg
   oscStAssert "garbage parses to no address", (tMsg["address"] is empty)
   oscStAssert "  and says why", (tMsg["error"] is not empty)
   oscStAddArg tArgs, "q", 1
   oscStAssert "an unknown type code builds nothing", (oscBuildMessage("/x", tArgs) is empty)
end oscStQuietFailures

-- ===== Tier 2: real UDP loopback to 127.0.0.1 (no hardware) =================
-- Sends OSC to ourselves over a genuine datagram socket. The result arrives
-- asynchronously (in oscStLoopbackArrived), so it appends to the log a moment
-- later rather than in the pass/fail tally above.

private command oscStStartLoopback
   put 9997 into sOscStLoopPort
   try
      close socket sOscStLoopPort   -- an accepted socket is named by its port alone
   end try
   accept datagram connections on port sOscStLoopPort with message "oscStLoopbackArrived"
   send "oscStSendLoopback" to me in 200 milliseconds
   put return & "    (loopback listener opened on udp:" & sOscStLoopPort \
       & " -- watch for the result below)" after sOscStLog
end oscStStartLoopback

command oscStSendLoopback
   -- The engine only writes to an OPEN socket (an unopened "host:port" name is
   -- "socket is not open" and nothing is sent), so open it first.
   local tArgs
   if ("127.0.0.1:" & sOscStLoopPort) is not among the lines of the openSockets then
      open datagram socket to ("127.0.0.1:" & sOscStLoopPort)
   end if
   oscStAddArg tArgs, "s", "loopback-ok"
   oscStAddArg tArgs, "i", 7
   write oscBuildMessage("/selftest/osc", tArgs) to socket ("127.0.0.1:" & sOscStLoopPort)
end oscStSendLoopback

-- OXT-Beyond calls a datagram message with (sender "host:port", data, socket);
-- an engine that hands the data first is tolerated (the osc-helpers precedent).
on oscStLoopbackArrived pSender, pData
   local tMsg, tLine
   -- The engine calls this later, with whatever stack is in front: pin the
   -- stack the results field belongs to (the suite's engine note 5.3).
   set the defaultStack to the short name of this stack
   put true into sOscStLoopFrom[pSender]
   if char 1 of pSender is "/" then
      put pSender into pData
   end if
   put oscParse(pData) into tMsg
   if tMsg["address"] is "/selftest/osc" and tMsg["args"][1] is "loopback-ok" and tMsg["args"][2] is 7 then
      put "  [PASS] Tier 2 OSC loopback: address & args round-tripped over UDP" into tLine
   else
      put "  [FAIL] Tier 2 OSC loopback: got address '" & tMsg["address"] & "'" into tLine
   end if
   put return & tLine after sOscStLog
   oscStShowResults
   -- accepted datagram connections keep delivering; nothing to re-read
end oscStLoopbackArrived

-- Stop the Tier 2 listener (the harness calls this so the engine quits cleanly).
command oscStopSelfTest
   local tFrom
   -- The senders the listener heard first: the engine lists one socket for
   -- each, on the listener's descriptor, and one left listed after the
   -- listener closes kept the engine's socket thread spinning, a whole core
   -- on Linux (the suite's engine notes, 6.20).
   repeat for each key tFrom in sOscStLoopFrom
      if tFrom is among the lines of the openSockets then
         try
            close socket tFrom
         end try
      end if
   end repeat
   put empty into sOscStLoopFrom
   try
      close socket sOscStLoopPort
   end try
   try
      close socket ("127.0.0.1:" & sOscStLoopPort)
   end try
end oscStopSelfTest

-- ===== reporting =============================================================

-- Append one OSC type/value pair as TWO consecutive elements (a FLAT list) to
-- an args array passed BY REFERENCE. A self-contained copy of osc-helpers'
-- scAddArg, so this file runs pasted on its own.
private command oscStAddArg @pArgs, pType, pValue
   put pType into pArgs[(the number of elements of pArgs) + 1]
   if pType is "b" then
      put pValue into pArgs[(the number of elements of pArgs) + 1]   -- raw Data
   else
      put (pValue & empty) into pArgs[(the number of elements of pArgs) + 1]
   end if
end oscStAddArg

private command oscStSection pTitle
   put return & return & "== " & pTitle & " ==" after sOscStLog
end oscStSection

private command oscStAssert pName, pOk
   if pOk then
      add 1 to sOscStPass
      put return & "  [PASS] " & pName after sOscStLog
   else
      add 1 to sOscStFail
      put return & "  [FAIL] " & pName after sOscStLog
   end if
end oscStAssert

private command oscStShowResults
   -- Mirror the log into a field if we can; harmless if there is no card. The
   -- colours are set, not inherited: a dark desktop theme otherwise paints
   -- the text white on the field's white.
   try
      if there is not a field "OSCResults" then
         create field "OSCResults"
         set the rect of field "OSCResults" to "16,16,640,560"
         set the dontWrap of field "OSCResults" to true
         set the opaque of field "OSCResults" to true
         set the backgroundColor of field "OSCResults" to "255,255,255"
         set the foregroundColor of field "OSCResults" to "0,0,0"
      end if
      set the text of field "OSCResults" to sOscStLog
   end try
end oscStShowResults
