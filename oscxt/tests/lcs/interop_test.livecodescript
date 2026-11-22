script "OscInteropTest"
-- ---------------------------------------------------------------------------
-- INTEROP without hardware: the engine + oscxt on one end of a real UDP
-- socket, an INDEPENDENT implementation on the other -- the virtual peer in
-- tools/sim/osc_peer.py (a clean-room Python codec that shares no code with
-- oscxt, itself proven by tests/simulators_test.py). Loopback proves oscxt is
-- self-consistent; this proves a different implementation agrees with it,
-- which is what a real controller or DAW needs.
--
-- The runner starts the peer on a free port and passes it in SC_OSC_PEER_PORT.
-- ---------------------------------------------------------------------------
-- needs: sockets
-- peers: osc
-- requires: oscxt

local sReplies

on TestSetup
   put empty into sReplies
end TestSetup

on peerReplied pSender, pData, pSocket
   put TestHex(pData) & return after sReplies
end peerReplied

-- Replies to an OPENED datagram socket: open it plainly (synchronously), then
-- `read from socket ... with message` -- for a datagram socket that registers the
-- per-datagram message (engine opensslsocket.cpp MCS_read_socket). NOT
-- `open datagram socket ... with message`: there the message is the asynchronous
-- open-complete callback, and an immediate write races the name resolution.
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

-- Send every OSC type to the Python peer; it acks with what IT decoded,
-- each argument rendered canonically (tools/sim/osc_peer.py).
on TestOscPeerReadsWhatWeSend
   local tPeer, tArgs, tAck
   put "127.0.0.1:" & $SC_OSC_PEER_PORT into tPeer
   scOpenForReplies tPeer
   scAddArg tArgs, "i", -42
   scAddArg tArgs, "f", 0.5
   scAddArg tArgs, "s", "interop"
   scAddArg tArgs, "b", numToByte(222) & numToByte(173)
   scAddArg tArgs, "h", "9223372036854775807"
   scAddArg tArgs, "d", 3.25
   scAddArg tArgs, "T", empty
   write oscBuildMessage("/interop/all", tArgs) to socket tPeer
   TestAssert "the peer acknowledged", TestWaitFor(the long id of me, "replyCount", 3000)
   put oscParse(TestUnhex(line 1 of sReplies)) into tAck
   TestAssertEqual "peer ack address", tAck["address"], "/oscpeer/ack"
   TestAssertEqual "peer decoded our address", tAck["args"][1], "/interop/all"
   TestAssertEqual "peer decoded our type tags", tAck["args"][2], "ifsbhdT"
   TestAssertEqual "int32", tAck["args"][3], "-42"
   TestAssertEqual "float32", tAck["args"][4], "0.5"
   TestAssertEqual "string", tAck["args"][5], "interop"
   TestAssertEqual "blob", tAck["args"][6], "dead"
   TestAssertEqual "int64", tAck["args"][7], "9223372036854775807"
   TestAssertEqual "double", tAck["args"][8], "3.25"
   close socket tPeer
end TestOscPeerReadsWhatWeSend

-- A bundle, decoded by the peer.
on TestOscPeerReadsOurBundles
   local tPeer, tArgs, tMsgs, tAck
   put "127.0.0.1:" & $SC_OSC_PEER_PORT into tPeer
   scOpenForReplies tPeer
   scAddArg tArgs, "i", 1
   put oscBuildMessage("/a", tArgs) into tMsgs[1]
   put oscBuildMessage("/b", tArgs) into tMsgs[2]
   put oscBuildMessage("/c", tArgs) into tMsgs[3]
   write oscBuildBundle("16045690984503098046", tMsgs) to socket tPeer
   TestAssert "the peer acknowledged the bundle", TestWaitFor(the long id of me, "replyCount", 3000)
   put oscParse(TestUnhex(line 1 of sReplies)) into tAck
   TestAssertEqual "peer saw a bundle", tAck["address"], "/oscpeer/ack-bundle"
   TestAssertEqual "peer decoded the unsigned timetag", tAck["args"][1], "16045690984503098046"
   TestAssertEqual "peer counted 3 elements", tAck["args"][2], 3
   close socket tPeer
end TestOscPeerReadsOurBundles
