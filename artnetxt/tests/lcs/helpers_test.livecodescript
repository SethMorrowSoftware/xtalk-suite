script "ArtnetHelpersTest"
-- ---------------------------------------------------------------------------
-- The shipped helper library (examples/artnet-helpers.livecodescript), loaded
-- the way the docs recommend -- as a library stack in the message path
-- (`start using`) -- and driven headlessly in a real engine.
--
-- The routing tests call the datagram message the way the engine does --
-- (sender, data, socket), engine opensslsocket.cpp -- so the routing is proven
-- even where sockets cannot run (udp_test does the real-socket version).
-- ---------------------------------------------------------------------------
-- requires:

local sSeen

on TestSetup
   put empty into sSeen
end TestSetup

on scArtnetDmx pUniverse, pChannels, pSender
   put "dmx|" & pUniverse & "|" & TestHex(pChannels) & "|" & pSender & return after sSeen
end scArtnetDmx

on scArtnetNodeFound pNode, pSender
   put "node|" & pNode["shortName"] & "|" & pNode["ip"] & "|" & pSender & return after sSeen
end scArtnetNodeFound

-- Does pHandler throw when called with these arguments (as a function when
-- pIsFunction)? Answers the error text, or empty when it did not throw.
function helperThrows pIsFunction, pHandler, pA, pB, pC
   local tErr, tFrame
   try
      if pIsFunction then
         get value(pHandler & "(pA, pB)")
      else
         put pA into tFrame
         do pHandler && "tFrame, pB, pC"
      end if
   catch tErr
      return tErr
   end try
   return empty
end helperThrows

on TestOneChannel
   local tCh
   put scArtnetOneChannel(3, 200) into tCh
   TestAssertEqual "one-channel frame", TestHex(tCh), "0000c8"
   put scArtnetOneChannel(1, 255) into tCh
   TestAssertEqual "channel 1", TestHex(tCh), "ff"
   put scArtnetOneChannel(512, 1) into tCh
   TestAssertEqual "channel 512 is the 512th byte", the number of bytes of tCh, 512
end TestOneChannel

-- numToByte WRAPS (the suite's engine note 2.13): ShowControl's helper sent a
-- computed 255.6, or 256, as level 0. Levels are rounded and kept to 0..255.
-- (A literal passed in arrives as a parameter, the case numToByte TRUNCATES;
-- TestLevelsAreTheSameFromEverySource below covers the cases it rounds.)
on TestOneChannelClampsLevels
   TestAssertEqual "255.6 is full, not 0", TestHex(scArtnetOneChannel(1, 255.6)), "ff"
   TestAssertEqual "256 is full, not 0", TestHex(scArtnetOneChannel(1, 256)), "ff"
   TestAssertEqual "300 is full, not 44", TestHex(scArtnetOneChannel(1, 300)), "ff"
   TestAssertEqual "-1 is 0, not 255", TestHex(scArtnetOneChannel(1, -1)), "00"
   TestAssertEqual "127.5 rounds to 128", TestHex(scArtnetOneChannel(1, 127.5)), "80"
   TestAssertEqual "127.4 rounds to 127", TestHex(scArtnetOneChannel(1, 127.4)), "7f"
   TestAssertEqual "a level as text", TestHex(scArtnetOneChannel(1, "64")), "40"
   TestAssert "a level that is not a number throws, and says why", \
         helperThrows(true, "scArtnetOneChannel", 1, "bright") contains "a level must be a number"
end TestOneChannelClampsLevels

-- numToByte rounds a fraction or cuts it by where the value came from (engine
-- note 2.13, pinned in engine_notes_test): 255.6 is byte 255 from a variable
-- put from a literal and byte 0 when computed or read from text. A level is
-- the same byte whatever made it.
on TestLevelsAreTheSameFromEverySource
   local tN, tText, tFrame
   put "255.6,127.5,127.4" into tText
   put 255.6 into tN
   TestAssertEqual "255.6 from a variable put from a literal is full", TestHex(scArtnetOneChannel(1, tN)), "ff"
   TestAssertEqual "255.6 computed is full", TestHex(scArtnetOneChannel(1, 2556 / 10)), "ff"
   TestAssertEqual "255.6 as text never read as a number is full", TestHex(scArtnetOneChannel(1, item 1 of tText)), "ff"
   put 127.5 into tN
   TestAssertEqual "127.5 from a variable rounds to 128", TestHex(scArtnetOneChannel(1, tN)), "80"
   TestAssertEqual "127.5 computed rounds to 128", TestHex(scArtnetOneChannel(1, 255 / 2)), "80"
   TestAssertEqual "127.5 as text rounds to 128", TestHex(scArtnetOneChannel(1, item 2 of tText)), "80"
   TestAssertEqual "127.4 as text rounds to 127", TestHex(scArtnetOneChannel(1, item 3 of tText)), "7f"
   put 2556 / 10 into tN
   scArtnetSetChannel tFrame, 1, tN
   TestAssertEqual "scArtnetSetChannel reads a computed variable the same", TestHex(tFrame), "ff"
end TestLevelsAreTheSameFromEverySource

-- A channel outside 1..512 is an error: ShowControl's built a frame past 512,
-- which the extension cut to 512 zeros (every light in the universe dark).
on TestChannelRangeIsChecked
   TestAssert "channel 513 throws", helperThrows(true, "scArtnetOneChannel", 513, 255) contains "from 1 to 512"
   TestAssert "channel 0 throws", helperThrows(true, "scArtnetOneChannel", 0, 255) contains "from 1 to 512"
   TestAssert "channel 2.5 throws", helperThrows(true, "scArtnetOneChannel", 2.5, 255) contains "whole number"
   TestAssert "an empty channel throws", helperThrows(true, "scArtnetOneChannel", empty, 255) contains "whole number"
   TestAssert "scArtnetChannel checks too", helperThrows(true, "scArtnetChannel", numToByte(1), 600) contains "from 1 to 512"
   TestAssert "scArtnetSetChannel checks too", helperThrows(false, "scArtnetSetChannel", empty, 0, 1) contains "from 1 to 512"
end TestChannelRangeIsChecked

on TestSetAndReadChannels
   local tFrame
   scArtnetSetChannel tFrame, 1, 255
   scArtnetSetChannel tFrame, 4, 128
   TestAssertEqual "frame grows with zeros", TestHex(tFrame), "ff000080"
   scArtnetSetChannel tFrame, 1, 10
   TestAssertEqual "an existing channel is overwritten in place", TestHex(tFrame), "0a000080"
   scArtnetSetChannel tFrame, 5, 300
   TestAssertEqual "the next channel appends, clamped", TestHex(tFrame), "0a000080ff"
   TestAssertEqual "read channel 4", scArtnetChannel(tFrame, 4), 128
   TestAssertEqual "read a channel past the end as 0", scArtnetChannel(tFrame, 100), 0
   TestAssertEqual "the frame sends as is", TestHex(byte 19 to -1 of artnetBuildDmx(0, tFrame)), "0a000080ff00"
end TestSetAndReadChannels

-- A frame that cannot be built sends nothing (ShowControl's wrote an empty
-- datagram), opens no socket, and the result says why.
on TestSendRefusesABadUniverse
   local tBefore, tResult
   put the openSockets into tBefore
   scArtnetSend "127.0.0.1", 40000, numToByte(1)
   put the result into tResult
   TestAssert "the result says why", tResult contains "out of range"
   TestAssertEqual "no socket was opened for it", the openSockets, tBefore
   artnetSendDmx -5, numToByte(1), "127.0.0.1"
   TestAssert "artnetSendDmx (ShowControl's order) passes the reason on", the result contains "out of range"
end TestSendRefusesABadUniverse

on TestReceivedRoutesDmx
   scArtnetReceived "10.0.0.2:6454", artnetBuildDmx(5, numToByte(1) & numToByte(2)), "6454"
   TestAssertEqual "routed with universe, levels and sender", line 1 of sSeen, "dmx|5|0102|10.0.0.2:6454"
end TestReceivedRoutesDmx

on TestReceivedRoutesNodeReplies
   local tHex
   put "4172742d4e6574000021" & "02000014" & "3619" & "0000" & "0000" & "000000000000" into tHex
   put "4c616d70000000000000000000000000" & "0000" after tHex
   scArtnetReceived "2.0.0.20:6454", TestUnhex(tHex), "6454"
   TestAssertEqual "routed with the node's name, ip and sender", line 1 of sSeen, "node|Lamp|2.0.0.20|2.0.0.20:6454"
end TestReceivedRoutesNodeReplies

on TestReceivedIgnoresTheRest
   scArtnetReceived "127.0.0.1:5000", artnetBuildPoll(), "6454"
   scArtnetReceived "127.0.0.1:5000", "not an art-net packet", "6454"
   scArtnetReceived "127.0.0.1:5000", empty, "6454"
   scArtnetReceived "127.0.0.1:5000", byte 1 to 12 of artnetBuildDmx(1, numToByte(1)), "6454"
   TestAssertEqual "an ArtPoll, garbage, nothing and a cut ArtDmx route nothing", sSeen, empty
end TestReceivedIgnoresTheRest

on TestLooksLikeArtnet
   TestAssert "an ArtDmx", scLooksLikeArtnet(artnetBuildDmx(0, numToByte(1)))
   TestAssert "an ArtPoll", scLooksLikeArtnet(artnetBuildPoll())
   TestAssert "not text", not scLooksLikeArtnet("Art-Net but not the ID")
   TestAssert "not empty", not scLooksLikeArtnet(empty)
end TestLooksLikeArtnet
