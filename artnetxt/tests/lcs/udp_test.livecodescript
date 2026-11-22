script "ArtnetUdpTest"
-- ---------------------------------------------------------------------------
-- Real UDP through the ENGINE's own sockets, to 127.0.0.1 -- the transport
-- every Art-Net app uses (the extension only builds/parses Data; the engine
-- owns the socket). No hardware: the engine talks to itself.
--
-- Runs only where the engine delivers socket events without a UI (the
-- runner's probe decides; OXT-Beyond >= 0.2.1-rc.2 on Windows). Elsewhere it
-- SKIPS, and under --require-all (CI) a skip is a failure.
-- ---------------------------------------------------------------------------
-- needs: sockets
-- requires:

local sDatagrams, sSeen

on TestSetup
   put empty into sDatagrams
   put empty into sSeen
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

on scArtnetDmx pUniverse, pChannels, pSender
   put "dmx|" & pUniverse & "|" & TestHex(pChannels) & return after sSeen
end scArtnetDmx

on scArtnetNodeFound pNode, pSender
   put "node|" & pNode["shortName"] & "|" & pNode["ip"] & "|" & pNode["outputUniverses"][1] & return after sSeen
end scArtnetNodeFound

function seenCount
   if sSeen is empty then
      return empty
   end if
   return the number of lines of sSeen
end seenCount

-- Pins the engine's datagram-callback contract the helpers rely on:
-- (sender "host:port", data, socket), data intact byte for byte.
on TestDatagramCallbackContract
   local tPort, tPkt
   put TestPortBase() + 11 into tPort
   accept datagram connections on port tPort with message "udpArrived"
   TestAssertEqual "accept succeeded", the result, empty
   put artnetBuildDmx(7, numToByte(1) & numToByte(2) & numToByte(3)) into tPkt
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

on TestArtnetFramesOverUdp
   local tPort, tIndex, tP, tLine, tOk
   put TestPortBase() + 13 into tPort
   accept datagram connections on port tPort with message "udpArrived"
   open datagram socket to ("127.0.0.1:" & tPort)
   repeat with tIndex = 0 to 9
      write artnetBuildDmx(tIndex, numToByte(tIndex * 20) & numToByte(255 - tIndex)) to socket ("127.0.0.1:" & tPort)
   end repeat
   TestPump 300
   TestAssertEqual "ten ArtDmx frames arrived", the number of lines of sDatagrams, 10
   put true into tOk
   set the itemDelimiter to tab
   repeat for each line tLine in sDatagrams
      put artnetParseDmx(TestUnhex(item 2 of tLine)) into tP
      if tP["opcode"] is not "ArtDmx" or byteToNum(byte 1 of tP["channels"]) is not tP["universe"] * 20 then
         put false into tOk
      end if
   end repeat
   set the itemDelimiter to comma
   TestAssert "every frame parses with its own universe and levels", tOk
   close socket tPort
   close socket ("127.0.0.1:" & tPort)
end TestArtnetFramesOverUdp

-- The documented helper path, end to end over a real socket: scArtnetSend
-- out (to "host:port"), scArtnetReceived (the helper) in, scArtnetDmx
-- delivered here.
on TestArtnetThroughHelpersOverUdp
   local tPort, tFrame
   put TestPortBase() + 12 into tPort
   accept datagram connections on port tPort with message "scArtnetReceived"
   scArtnetSetChannel tFrame, 1, 255
   scArtnetSetChannel tFrame, 3, 64
   scArtnetSend "127.0.0.1:" & tPort, 42, tFrame
   TestAssertEqual "the send went", the result, empty
   TestAssert "scArtnetDmx delivered", TestWaitFor(the long id of me, "seenCount", 3000)
   TestAssertEqual "universe and levels survived UDP", line 1 of sSeen, "dmx|42|ff004000"
   close socket tPort
   close socket ("127.0.0.1:" & tPort)
end TestArtnetThroughHelpersOverUdp

-- Discovery the way it runs on a show network, every hop a real datagram:
-- scArtnetPoll asks; a stand-in node (this test, listening on its own port)
-- hears the ArtPoll and answers to port 6454 of the computer that asked, as
-- hardware does; the helper, listening on 6454, routes the answer to
-- scArtnetNodeFound. Port 6454 must be free: another Art-Net program holding
-- it makes this a skip, not a failure.
local sPollsHeard

on fakeNodeHeard pSender, pData, pSocket
   local tHex, tHeard
   put artnetParseReply(pData) into tHeard
   if tHeard["opcode"] is not empty then
      exit fakeNodeHeard                 -- a reply is not a poll: do not answer it
   end if
   put pSender & return after sPollsHeard
   put "4172742d4e6574000021" & "7f000001" & "3619" & "0000" & "0000" & "000000000000" into tHex
   put "4661646572206e6f646500000000000000" & "00" after tHex      -- ShortName "Fader node"
   repeat 64 + 64 + 2 times
      put "00" after tHex                                              -- LongName, NodeReport, NumPorts
   end repeat
   put "80000000" & "0000000000000000" & "00000000" & "05000000" after tHex   -- one output, SwOut 5
   open datagram socket to "127.0.0.1:6454"
   write TestUnhex(tHex) to socket "127.0.0.1:6454"
end fakeNodeHeard

function pollsHeard
   if sPollsHeard is empty then
      return empty
   end if
   return the number of lines of sPollsHeard
end pollsHeard

on TestDiscoveryThroughHelpersOverUdp
   local tNodePort, tResult
   put empty into sPollsHeard
   accept datagram connections on port 6454 with message "scArtnetReceived"
   put the result into tResult
   if tResult is not empty then
      TestSkip "discovery over UDP", "port 6454 is taken on this machine (" & tResult & ")"
      exit TestDiscoveryThroughHelpersOverUdp
   end if
   put TestPortBase() + 14 into tNodePort
   accept datagram connections on port tNodePort with message "fakeNodeHeard"
   scArtnetPoll "127.0.0.1:" & tNodePort
   TestAssertEqual "the poll went", the result, empty
   TestAssert "the node heard the ArtPoll", TestWaitFor(the long id of me, "pollsHeard", 3000)
   TestAssert "its answer reached scArtnetNodeFound", TestWaitFor(the long id of me, "seenCount", 3000)
   TestAssertEqual "with its name, address and universe", line 1 of sSeen, "node|Fader node|127.0.0.1|5"
   close socket tNodePort
   close socket 6454
   close socket ("127.0.0.1:" & tNodePort)
   close socket "127.0.0.1:6454"
end TestDiscoveryThroughHelpersOverUdp

-- The shipped self-test's Tier 2 (async loopback) -- the part selftest_test
-- cannot check without sockets. Its stop leaves no socket listed: the engine
-- lists one more for each sender a datagram listener hears, on the listener's
-- descriptor, and one left listed after the listener closes kept the engine's
-- socket thread spinning, a whole core on Linux (the suite's engine notes,
-- 6.21; a self-test left open in an IDE would have kept it so)
on TestShippedSelfTestTier2
   local tPath, tLog, tBefore
   put udpSocketList() into tBefore
   put $SC_HELPERS into tPath
   set the itemDelimiter to "/"
   put "artnet-selftest.livecodescript" into the last item of tPath
   set the itemDelimiter to ","
   TestLoadScriptAsLibrary tPath, "ArtnetSelfTest"
   put runArtnetSelfTest() into tLog
   TestPump 1500
   put artnetSelfTestLog() into tLog          -- the log INCLUDING the async Tier 2 line
   TestDiagnostic tLog
   TestAssert "Tier 2 Art-Net loopback reported PASS", tLog contains "[PASS] Tier 2 Art-Net loopback"
   artnetStopSelfTest
   TestPump 100
   TestAssertEqual "its stop leaves no socket listed", udpSocketList(), tBefore
end TestShippedSelfTestTier2

-- The runner closes what a run left listed before it quits (scCloseLeftSockets,
-- tests/lcs/_runner.livecodescript): a sender's name left listed after its
-- listener closed keeps the engine's socket thread spinning, and at quit the
-- engine frees its sockets without that thread's lock (the suite's engine
-- notes, 6.21). This leaves one on purpose, as a test that closes only its
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
