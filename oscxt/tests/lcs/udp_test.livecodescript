script "OscUdpTest"
-- ---------------------------------------------------------------------------
-- Real UDP through the ENGINE's own sockets, to 127.0.0.1 -- the transport every
-- OSC app uses (the extension only builds/parses Data; the engine owns the
-- socket). No hardware: the engine talks to itself.
--
-- Runs only where the engine delivers socket events without a UI (the runner's
-- probe decides; OXT-Beyond >= 0.2.1-rc.2 on Windows). Elsewhere it SKIPS, and
-- under --require-all (CI) a skip is a failure.
-- ---------------------------------------------------------------------------
-- needs: sockets
-- requires: oscxt

local sDatagrams, sOscSeen

on TestSetup
   put empty into sDatagrams
   put empty into sOscSeen
end TestSetup

on udpArrived pSender, pData, pSocket
   put pSender & tab & TestHex(pData) & return after sDatagrams
end udpArrived

function udpCount
   if sDatagrams is empty then
      return empty
   end if
   return the number of lines of sDatagrams
end udpCount

on scOscMessage pAddress, pArgs, pSender
   put pAddress & "|" & pArgs[1] & "|" & pArgs[2] & return after sOscSeen
end scOscMessage

function oscSeen
   return sOscSeen
end oscSeen

-- Pins the engine's datagram-callback contract the helpers rely on:
-- (sender "host:port", data, socket), data intact byte for byte.
on TestDatagramCallbackContract
   local tPort, tPkt, tArgs
   put TestPortBase() + 11 into tPort
   accept datagram connections on port tPort with message "udpArrived"
   TestAssertEqual "accept succeeded", the result, empty
   scAddArg tArgs, "b", numToByte(1) & numToByte(0) & numToByte(255)
   put oscBuildMessage("/contract", tArgs) into tPkt
   open datagram socket to ("127.0.0.1:" & tPort)
   write tPkt to socket ("127.0.0.1:" & tPort)
   TestAssert "a datagram arrived", TestWaitFor(the long id of me, "udpCount", 3000)
   set the itemDelimiter to tab
   TestAssert "param 1 is the sender host:port", item 1 of line 1 of sDatagrams contains "127.0.0.1:"
   TestAssertEqual "param 2 is the data, intact", item 2 of line 1 of sDatagrams, TestHex(tPkt)
   set the itemDelimiter to comma
   close socket tPort
   close socket ("127.0.0.1:" & tPort)
end TestDatagramCallbackContract

-- Pins the contract the examples were missing: writing to a "host:port" that was
-- never OPENED sends nothing and says so in the result (exec-network.cpp).
on TestUnopenedWriteSendsNothing
   local tPort, tResult
   put TestPortBase() + 14 into tPort
   accept datagram connections on port tPort with message "udpArrived"
   write "never-opened" to socket ("127.0.0.1:" & tPort)
   put the result into tResult
   TestPump 500
   -- exec-network.cpp sets the result to "socket is not open"; not every engine
   -- build surfaces it, so pin the observable effect and record the result.
   TestDiagnostic "result of the unopened write: [" & tResult & "]"
   TestAssertEqual "nothing was delivered", sDatagrams, empty
   close socket tPort
end TestUnopenedWriteSendsNothing

-- The documented helper path, end to end over a real socket: scOscSend out,
-- socketReceived (the helper) in, scOscMessage delivered here.
on TestOscThroughHelpersOverUdp
   local tPort, tArgs
   put TestPortBase() + 12 into tPort
   accept datagram connections on port tPort with message "socketReceived"
   scAddArg tArgs, "s", "over-udp"
   scAddArg tArgs, "i", 99
   scOscSend "127.0.0.1", tPort, "/udp/helper", tArgs
   TestAssert "scOscMessage delivered", TestWaitFor(the long id of me, "oscSeen", 3000)
   TestAssertEqual "address and args survived UDP", line 1 of sOscSeen, "/udp/helper|over-udp|99"
   close socket tPort
end TestOscThroughHelpersOverUdp

-- A burst: fifty messages, every one delivered and parsed, in order.
on TestOscBurstOverUdp
   local tPort, tArgs, tIndex, tLine, tOk, tMsg
   put TestPortBase() + 13 into tPort
   accept datagram connections on port tPort with message "udpArrived"
   open datagram socket to ("127.0.0.1:" & tPort)
   repeat with tIndex = 1 to 50
      put empty into tArgs
      scAddArg tArgs, "i", tIndex
      scAddArg tArgs, "f", tIndex / 4
      write oscBuildMessage("/burst/" & tIndex, tArgs) to socket ("127.0.0.1:" & tPort)
   end repeat
   TestPump 500
   TestAssertEqual "fifty datagrams arrived", the number of lines of sDatagrams, 50
   put true into tOk
   put 0 into tIndex
   set the itemDelimiter to tab
   repeat for each line tLine in sDatagrams
      add 1 to tIndex
      put oscParse(TestUnhex(item 2 of tLine)) into tMsg
      if tMsg["address"] is not ("/burst/" & tIndex) or tMsg["args"][1] is not tIndex then
         put false into tOk
      end if
   end repeat
   set the itemDelimiter to comma
   TestAssert "every message parses, in order, with its own values", tOk
   close socket tPort
   close socket ("127.0.0.1:" & tPort)
end TestOscBurstOverUdp

-- The shipped self-test's Tier 2 (async loopback) -- the part selftest_test
-- cannot check without sockets. Its stop leaves no socket listed: the engine
-- lists one more for each sender a datagram listener hears, on the listener's
-- descriptor, and one left listed after the listener closes kept the engine's
-- socket thread spinning, a whole core on Linux (the suite's engine notes,
-- 6.20; a self-test left open in an IDE would have kept it so)
on TestShippedSelfTestTier2
   local tPath, tLog, tBefore
   put udpSocketList() into tBefore
   put $SC_HELPERS into tPath
   set the itemDelimiter to "/"
   put "osc-selftest.livecodescript" into the last item of tPath
   set the itemDelimiter to ","
   TestLoadScriptAsLibrary tPath, "OscSelfTest"
   put runOscSelfTest() into tLog
   TestPump 1500
   put oscSelfTestLog() into tLog          -- the log INCLUDING the async Tier 2 line
   TestDiagnostic tLog
   TestAssert "Tier 2 OSC loopback reported PASS", tLog contains "[PASS] Tier 2 OSC loopback"
   oscStopSelfTest
   TestPump 100
   TestAssertEqual "its stop leaves no socket listed", udpSocketList(), tBefore
end TestShippedSelfTestTier2

-- The runner closes what a run left listed before it quits (scCloseLeftSockets,
-- tests/lcs/_runner.livecodescript): a sender's name left listed after its
-- listener closed keeps the engine's socket thread spinning, and at quit the
-- engine frees its sockets without that thread's lock (the suite's engine
-- notes, 6.20). This leaves one on purpose, as a test that closes only its
-- listener does, and has the runner's handler close it.
on TestTheRunnerClosesWhatARunLeftListed
   global gLeftFrom
   local tPort, tDeadline
   put TestPortBase() + 15 into tPort
   put empty into gLeftFrom
   accept datagram connections on port tPort with message "leftArrived"
   TestAssertEqual "accept succeeded", the result, empty
   open datagram socket to ("127.0.0.1:" & tPort)
   write "left" to socket ("127.0.0.1:" & tPort)
   put the milliseconds + 3000 into tDeadline
   repeat until gLeftFrom is not empty or the milliseconds > tDeadline
      wait 10 milliseconds with messages
   end repeat
   TestAssert "the listener heard the datagram", gLeftFrom is not empty
   close socket ("127.0.0.1:" & tPort)
   close socket tPort
   TestAssert "its sender's name is still listed after the listener closed (" & udpSocketList() & ")", \
         gLeftFrom is among the lines of the openSockets
   scCloseLeftSockets
   TestAssertEqual "the runner's handler closed it", udpSocketList(), empty
end TestTheRunnerClosesWhatARunLeftListed

on leftArrived pSender, pData
   global gLeftFrom
   put pSender into gLeftFrom
end leftArrived

-- The openSockets on one line, for a label or a comparison
function udpSocketList
   local tList
   put the openSockets into tList
   replace return with comma in tList
   return tList
end udpSocketList
