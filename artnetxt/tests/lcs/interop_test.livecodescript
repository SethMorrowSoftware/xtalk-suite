script "ArtnetInteropTest"
-- ---------------------------------------------------------------------------
-- INTEROP without hardware: the engine + artnetxt on one end of a real UDP
-- socket, an INDEPENDENT implementation on the other -- the virtual node in
-- tools/sim/artnet_node.py (a clean-room Python codec that shares no code
-- with artnetxt, itself proven by tests/simulators_test.py). Loopback proves
-- artnetxt is self-consistent; this proves a different implementation agrees
-- with it, which is what a real node needs.
--
-- The runner starts the node on a free port (echo on universe + 1) and passes
-- it in SC_ARTNET_PEER_PORT. The node answers to the port a packet came from.
-- ---------------------------------------------------------------------------
-- needs: sockets
-- peers: artnet
-- requires:

local sReplies, sSeen

on TestSetup
   put empty into sReplies
   put empty into sSeen
end TestSetup

-- What the helpers route here (TestHelpersHearTheNodeThroughTheirOwnSocket).
on scArtnetDmx pUniverse, pChannels, pSender
   put "dmx|" & pUniverse & "|" & TestHex(pChannels) & "|" & pSender & return after sSeen
end scArtnetDmx

on scArtnetNodeFound pNode, pSender
   put "node|" & pNode["shortName"] & "|" & pSender & return after sSeen
end scArtnetNodeFound

function seenCount
   if sSeen is empty then
      return empty
   end if
   return the number of lines of sSeen
end seenCount

on peerReplied pSender, pData, pSocket
   put TestHex(pData) & return after sReplies
end peerReplied

-- Replies to an OPENED datagram socket: open it plainly (synchronously), then
-- `read from socket ... with message` -- for a datagram socket that registers
-- the per-datagram message (engine opensslsocket.cpp MCS_read_socket). NOT
-- `open datagram socket ... with message`: there the message is the
-- asynchronous open-complete callback, and an immediate write races the name
-- resolution.
command scOpenForReplies pHostPort
   open datagram socket to pHostPort
   read from socket pHostPort with message "peerReplied"
end scOpenForReplies

function replyCount
   if sReplies is empty then
      return empty
   end if
   return the number of lines of sReplies
end replyCount

-- Art-Net discovery against the virtual node, then a DMX frame it echoes back
-- on universe + 1.
on TestArtnetNodeDiscoveryAndDmx
   local tNode, tReply, tEcho
   put "127.0.0.1:" & $SC_ARTNET_PEER_PORT into tNode
   scOpenForReplies tNode
   write artnetBuildPoll() to socket tNode
   TestAssert "the node answered ArtPoll", TestWaitFor(the long id of me, "replyCount", 3000)
   put artnetParseReply(TestUnhex(line 1 of sReplies)) into tReply
   TestAssertEqual "ArtPollReply parsed", tReply["opcode"], "ArtPollReply"
   TestAssertEqual "node short name", tReply["shortName"], "SimNode"
   TestAssertEqual "node address and port", tReply["ip"] & ":" & tReply["port"], "127.0.0.1:6454"
   TestAssertEqual "its one output port is on universe 0", the number of elements of tReply["outputUniverses"], 1
   TestAssertEqual "  (that universe)", tReply["outputUniverses"][1], 0
   TestAssertEqual "node MAC", tReply["mac"], "02:00:00:00:00:01"
   TestAssert "node report", tReply["nodeReport"] contains "artnetxt virtual node"
   put empty into sReplies
   write artnetBuildDmx(41, numToByte(10) & numToByte(20) & numToByte(30)) to socket tNode
   TestAssert "the node echoed the frame", TestWaitFor(the long id of me, "replyCount", 3000)
   put artnetParseDmx(TestUnhex(line 1 of sReplies)) into tEcho
   TestAssertEqual "echo is on universe + 1", tEcho["universe"], 42
   TestAssertEqual "levels survived the round trip", TestHex(tEcho["channels"]), "0a141e00"
   close socket tNode
end TestArtnetNodeDiscoveryAndDmx

-- The helper's send path to the independent node: a full 512-channel frame
-- through scArtnetSend ("host:port"), echoed back intact.
on TestHelperSendToTheNode
   local tNode, tFrame, tIndex, tEcho
   put "127.0.0.1:" & $SC_ARTNET_PEER_PORT into tNode
   scOpenForReplies tNode
   repeat with tIndex = 1 to 512
      scArtnetSetChannel tFrame, tIndex, tIndex mod 256
   end repeat
   scArtnetSend tNode, 100, tFrame
   TestAssertEqual "the send went", the result, empty
   TestAssert "the node echoed it", TestWaitFor(the long id of me, "replyCount", 3000)
   put artnetParseDmx(TestUnhex(line 1 of sReplies)) into tEcho
   TestAssertEqual "on universe 101", tEcho["universe"], 101
   TestAssertEqual "all 512 levels", tEcho["length"], 512
   TestAssertEqual "the node read the same bytes", TestHex(tEcho["channels"]), TestHex(tFrame)
   close socket tNode
end TestHelperSendToTheNode

-- The getting-started guide's no-hardware recipe (its section 8), as written:
-- the helpers' own socket to the node, asked for its datagrams, so the node's
-- answer to a poll and its echo of a frame both arrive through
-- scArtnetReceived, as a `read from socket ... with message` delivers them.
on TestHelpersHearTheNodeThroughTheirOwnSocket
   local tNode, tLevels
   put "127.0.0.1:" & $SC_ARTNET_PEER_PORT into tNode
   scArtnetEnsureSocket tNode
   read from socket tNode with message "scArtnetReceived"
   scArtnetPoll tNode
   TestAssertEqual "the poll went", the result, empty
   TestAssert "the node's answer arrived", TestWaitFor(the long id of me, "seenCount", 3000)
   TestAssertEqual "as scArtnetNodeFound, from the node", line 1 of sSeen, "node|SimNode|" & tNode
   put empty into sSeen
   scArtnetSetChannel tLevels, 1, 200
   scArtnetSend tNode, 7, tLevels
   TestAssertEqual "the send went", the result, empty
   TestAssert "the echo arrived", TestWaitFor(the long id of me, "seenCount", 3000)
   TestAssertEqual "as scArtnetDmx on universe 8, from the node", line 1 of sSeen, "dmx|8|c800|" & tNode
   close socket tNode
end TestHelpersHearTheNodeThroughTheirOwnSocket
