script "OscHelpersTest"
-- ---------------------------------------------------------------------------
-- The shipped helper library (examples/osc-helpers.livecodescript), loaded the
-- way the docs recommend -- as a library stack in the message path
-- (`start using`) -- and driven headlessly in a real engine.
--
-- The routing tests call the datagram message the way the engine does --
-- (sender, data, socket), engine opensslsocket.cpp -- so the routing is proven
-- even where sockets cannot run (udp_test does the real-socket version).
-- ---------------------------------------------------------------------------
-- requires: oscxt

local sOscSeen

on TestSetup
   put empty into sOscSeen
end TestSetup

on scOscMessage pAddress, pArgs, pSender
   put pAddress & "|" & pArgs[1] & "|" & pSender & return after sOscSeen
end scOscMessage

on TestAddArgBuildsFlatArgs
   local tArgs, tMsg
   scAddArg tArgs, "i", 60
   scAddArg tArgs, "f", 0.8
   scAddArg tArgs, "s", "go"
   scAddArg tArgs, "b", numToByte(1) & numToByte(2)
   scAddArg tArgs, "T", empty
   TestAssertEqual "scAddArg writes type,value pairs", the number of elements of tArgs, 10
   put oscParse(oscBuildMessage("/synth/note", tArgs)) into tMsg
   TestAssertEqual "types survive", tMsg["types"], "ifsbT"
   TestAssertEqual "int survives", tMsg["args"][1], 60
   TestAssertEqual "blob survives", TestHex(tMsg["args"][4]), "0102"
end TestAddArgBuildsFlatArgs

on TestSocketReceivedRoutesOsc
   local tArgs
   scAddArg tArgs, "i", 42
   socketReceived "127.0.0.1:5000", oscBuildMessage("/route/me", tArgs), "9000"
   TestAssertEqual "routed with address, args and sender", line 1 of sOscSeen, "/route/me|42|127.0.0.1:5000"
end TestSocketReceivedRoutesOsc

on TestSocketReceivedUnpacksBundles
   local tArgs, tA, tInner, tMsgs, tOuter
   scAddArg tArgs, "s", "x"
   put oscBuildMessage("/a", tArgs) into tA
   put tA into tMsgs[1]
   put oscBuildBundle("1", tMsgs) into tInner
   put tInner into tMsgs[1]
   put oscBuildMessage("/b", tArgs) into tMsgs[2]
   put oscBuildBundle("1", tMsgs) into tOuter
   socketReceived "10.0.0.2:8000", tOuter, "9000"
   TestAssertEqual "nested bundle: both messages routed", the number of lines of sOscSeen, 2
   TestAssertEqual "inner message first", line 1 of sOscSeen, "/a|x|10.0.0.2:8000"
   TestAssertEqual "then the outer one", line 2 of sOscSeen, "/b|x|10.0.0.2:8000"
end TestSocketReceivedUnpacksBundles

-- Callers wired the OLD way round (data first) still route.
on TestSocketReceivedToleratesLegacyOrder
   local tArgs
   scAddArg tArgs, "i", 1
   socketReceived oscBuildMessage("/legacy", tArgs), "127.0.0.1:7000"
   TestAssertEqual "legacy (data, sender) order", line 1 of sOscSeen, "/legacy|1|127.0.0.1:7000"
end TestSocketReceivedToleratesLegacyOrder

on TestSocketReceivedIgnoresGarbage
   socketReceived "127.0.0.1:5000", "not an osc packet", "9000"
   TestAssertEqual "garbage routes nothing (and does not throw)", sOscSeen, empty
end TestSocketReceivedIgnoresGarbage

-- A message that cannot be built sends nothing and does not throw.
on TestOscSendRefusesAnUnbuildableMessage
   local tArgs, tBefore
   scAddArg tArgs, "q", 1
   put the openSockets into tBefore
   scOscSend "127.0.0.1", TestPortBase() + 20, "/x", tArgs
   TestAssertEqual "no socket was opened for it", the openSockets, tBefore
   TestAssert "oscLastError says why", oscLastError() is not empty
end TestOscSendRefusesAnUnbuildableMessage

on TestLooksLikeOsc
   TestAssert "a message is OSC", scLooksLikeOsc("/a" & numToByte(0) & numToByte(0))
   TestAssert "a bundle is OSC", scLooksLikeOsc("#bundle" & numToByte(0) & "12345678")
   TestAssert "a host:port is not", not scLooksLikeOsc("127.0.0.1:9000")
   TestAssert "empty is not", not scLooksLikeOsc(empty)
end TestLooksLikeOsc
