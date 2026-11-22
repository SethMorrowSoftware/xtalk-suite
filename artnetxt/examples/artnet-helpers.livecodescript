-- artnet-helpers.livecodescript
-- ---------------------------------------------------------------------------
-- Reusable LiveCode Script helpers for the artnetxt extension (Art-Net: DMX
-- lighting levels over a network). Paste this into a stack or card script (or
-- a library stack you `start using`). To set lights:
--
--     local tLevels
--     scArtnetSetChannel tLevels, 1, 255          -- channel 1 at full
--     scArtnetSetChannel tLevels, 4, 128          -- channel 4 at half
--     scArtnetSend "192.168.1.50", 0, tLevels     -- universe 0 of that node
--
-- and to listen (levels from another controller, and node discovery):
--
--     accept datagram connections on port 6454 with message "scArtnetReceived"
--     on scArtnetDmx pUniverse, pChannels, pSender ... end scArtnetDmx
--     on scArtnetNodeFound pNode, pSender ... end scArtnetNodeFound
--     scArtnetPoll                                -- ask every node to answer
--
-- scArtnetSend, artnetSendDmx and scArtnetOneChannel are the Art-Net part of
-- ShowControl's showcontrol-helpers.livecodescript, under the same names; a
-- script that pasted the old combined file keeps working. Pasting this beside
-- oscxt's osc-helpers and midixt's midi-helpers defines no name twice (the
-- suite's tools/check-cross-library-names.py holds it). What changed from
-- ShowControl's, on purpose:
--   * A level is rounded and kept to 0..255. numToByte WRAPS, and rounds a
--     fraction or cuts it by where the value came from (the suite's engine
--     note 2.13), so ShowControl's scArtnetOneChannel sent a computed 255.6,
--     or 256, as level 0 (a light at full went dark), and 127.5 as 127 or
--     128 by how its caller had written it.
--   * A channel outside 1..512 is an error (it throws), where ShowControl's
--     built a frame past the 512 a universe holds, which the extension then
--     cut to 512 zeros: every light in the universe went dark.
--   * A send that cannot be built sends nothing, and the result says why;
--     ShowControl's wrote an empty datagram.
--   * A host may say its port ("192.168.1.50:6455", a node on another port,
--     or tools/sim/artnet_node.py on a test port); a plain host still goes
--     to 6454. ShowControl's always appended ":6454", which made a
--     "host:port" into "host:port:6454".
--   * The socket is opened by scArtnetEnsureSocket, this file's own name,
--     not osc-helpers' scEnsureDatagramSocket, so either file pastes alone.
--   * New: scArtnetSetChannel, scArtnetChannel, scArtnetPoll,
--     scArtnetReceived and scLooksLikeArtnet.
-- ---------------------------------------------------------------------------

-- ===== UDP transport ========================================================

-- Make sure a datagram socket to "host:port" is open before writing to it. The
-- engine only writes to an OPEN socket: `write ... to socket "h:p"` on a name
-- that was never opened sets the result to "socket is not open" and sends
-- NOTHING, silently (engine/src/exec-network.cpp, MCNetworkExecWriteToSocket).
-- Opening is idempotent here, so call it before every send.
command scArtnetEnsureSocket pHostPort
   if pHostPort is not among the lines of the openSockets then
      open datagram socket to pHostPort
   end if
end scArtnetEnsureSocket

-- ===== Building levels =======================================================

-- One level as the byte DMX sends: a number rounded and kept to 0..255.
-- (numToByte alone wraps, 256 becoming 0, and rounds or cuts a fraction by
-- where it came from: engine note 2.13. `round` reads it the same from all.)
private function scArtnetLevelByte pLevel, pWho
   if pLevel is not a number then
      throw pWho & ": a level must be a number from 0 to 255, not" && pLevel
   end if
   return numToByte(max(0, min(255, round(pLevel))))
end scArtnetLevelByte

-- A channel number must be a whole number from 1 to 512: a universe holds 512.
private command scArtnetCheckChannel pChannel, pWho
   if pChannel is not an integer then
      throw pWho & ": a channel must be a whole number from 1 to 512, not" && pChannel
   end if
   if pChannel < 1 or pChannel > 512 then
      throw pWho & ": a channel must be from 1 to 512, not" && pChannel
   end if
end scArtnetCheckChannel

-- Set one channel's level in a frame of levels (a variable, passed by
-- reference), adding channels at level 0 up to it when the frame is shorter.
--   local tLevels
--   scArtnetSetChannel tLevels, 3, 200     -- tLevels is now 0, 0, 200
command scArtnetSetChannel @pChannels, pChannel, pLevel
   local tByte
   scArtnetCheckChannel pChannel, "scArtnetSetChannel"
   put scArtnetLevelByte(pLevel, "scArtnetSetChannel") into tByte
   repeat while (the number of bytes in pChannels) < pChannel - 1
      put numToByte(0) after pChannels
   end repeat
   if (the number of bytes in pChannels) < pChannel then
      put tByte after pChannels
   else
      put tByte into byte pChannel of pChannels
   end if
end scArtnetSetChannel

-- The level (0..255) of one channel of a frame; 0 for a channel past its end.
function scArtnetChannel pChannels, pChannel
   scArtnetCheckChannel pChannel, "scArtnetChannel"
   if pChannel > (the number of bytes in pChannels) then
      return 0
   end if
   return byteToNum(byte pChannel of pChannels)
end scArtnetChannel

-- Build a single-channel DMX frame (1-based channel, 0..255 level) - handy for
-- driving one dimmer from a fader without assembling 512 bytes by hand. Every
-- channel before it is 0.
function scArtnetOneChannel pChannel, pLevel
   local tChannels
   scArtnetCheckChannel pChannel, "scArtnetOneChannel"
   put empty into tChannels
   scArtnetSetChannel tChannels, pChannel, pLevel
   return tChannels
end scArtnetOneChannel

-- ===== Sending ===============================================================

-- "host" -> "host:6454", the Art-Net port; a "host:port" is kept as given (a
-- node on another port, or tools/sim/artnet_node.py on a test port).
private function scArtnetHostPort pHost
   if pHost contains ":" then
      return pHost
   end if
   return pHost & ":6454"
end scArtnetHostPort

-- Send a DMX universe (pChannels: up to 512 levels, one byte each) to an
-- Art-Net node at pHost (port 6454 unless pHost says "host:port"). When the
-- frame cannot be built (a universe outside 0..32767) nothing is sent and the
-- result says why; otherwise the result is the write's (empty when it went).
on scArtnetSend pHost, pUniverse, pChannels
   local tPacket, tHostPort
   put artnetBuildDmx(pUniverse, pChannels) into tPacket
   if tPacket is empty then
      return artnetLastError()
   end if
   put scArtnetHostPort(pHost) into tHostPort
   scArtnetEnsureSocket tHostPort
   write tPacket to socket tHostPort
   return the result
end scArtnetSend

-- ShowControl's "optional convenience" verb, the arguments in the order its
-- API reference gave them: scArtnetSend with the host last.
on artnetSendDmx pUniverse, pChannels, pHost
   scArtnetSend pHost, pUniverse, pChannels
   return the result
end artnetSendDmx

-- Ask Art-Net nodes to say who they are. With no host, the ArtPoll goes to
-- every computer on the network (255.255.255.255), which needs the engine's
-- allowDatagramBroadcasts, so this sets it to true; a host ending in .255 is a
-- broadcast too. Nodes answer to port 6454 of this computer: listen there
-- first (accept datagram connections on port 6454 with message
-- "scArtnetReceived"), and each answer arrives as scArtnetNodeFound.
on scArtnetPoll pHost
   local tHostPort, tBroadcast
   if pHost is empty then
      put "255.255.255.255" into pHost
   end if
   put scArtnetHostPort(pHost) into tHostPort
   set the itemDelimiter to ":"
   put item 1 of tHostPort into pHost
   set the itemDelimiter to "."
   put (the last item of pHost is "255") into tBroadcast
   set the itemDelimiter to comma
   if tBroadcast then
      set the allowDatagramBroadcasts to true
   end if
   scArtnetEnsureSocket tHostPort
   write artnetBuildPoll() to socket tHostPort
   return the result
end scArtnetPoll

-- ===== Receiving =============================================================

-- Route inbound Art-Net. Wire it up with
--     accept datagram connections on port 6454 with message "scArtnetReceived"
-- and write your own handlers for what you want to hear:
--     on scArtnetDmx pUniverse, pChannels, pSender     (levels: one byte each)
--     on scArtnetNodeFound pNode, pSender              (pNode: artnetParseReply's array)
-- Anything else (an ArtPoll, your own broadcast coming back, an OpCode this
-- extension does not read, bytes that are not Art-Net) is ignored.
-- The engine calls a datagram message with (sender "host:port", data, socket),
-- in that order (engine/src/opensslsocket.cpp, MCSocket::readsome).
on scArtnetReceived pSender, pData, pSocket
   local tFrame, tNode, tTarget
   if not scLooksLikeArtnet(pData) then
      exit scArtnetReceived
   end if
   put the long id of the target into tTarget
   put artnetParseDmx(pData) into tFrame
   if tFrame["opcode"] is "ArtDmx" then
      dispatch "scArtnetDmx" to tTarget with tFrame["universe"], tFrame["channels"], pSender
      exit scArtnetReceived
   end if
   put artnetParseReply(pData) into tNode
   if tNode["opcode"] is "ArtPollReply" then
      dispatch "scArtnetNodeFound" to tTarget with tNode, pSender
   end if
end scArtnetReceived

-- Does this value look like an Art-Net packet ("Art-Net", a NUL, an OpCode)?
function scLooksLikeArtnet pX
   if (the number of bytes in pX) < 10 then
      return false
   end if
   return (byte 1 to 8 of pX) is ("Art-Net" & numToByte(0))
end scLooksLikeArtnet
