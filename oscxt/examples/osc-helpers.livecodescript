-- osc-helpers.livecodescript
-- ---------------------------------------------------------------------------
-- Reusable LiveCode Script helpers for the oscxt extension (Open Sound
-- Control). Paste this into a stack or card script (or a library stack you
-- `start using`), then your own handlers only need to react to messages:
--
--     accept datagram connections on port 9000 with message "socketReceived"
--     on scOscMessage pAddress, pArgs, pSender ... end scOscMessage
--
-- and to send:
--
--     local tArgs
--     scAddArg tArgs, "f", 0.8
--     scOscSend "127.0.0.1", 9000, "/1/fader1", tArgs
--
-- These are the OSC half of ShowControl's showcontrol-helpers.livecodescript,
-- unchanged in name and behaviour: a script that pasted the old combined file
-- keeps working, and pasting this one beside midixt's midi-helpers and
-- artnetxt's artnet-helpers gives the same handlers again (no name is defined
-- in two of the three files, which the suite's
-- tools/check-cross-library-names.py holds).
-- ---------------------------------------------------------------------------

-- ===== UDP transport ========================================================

-- Make sure a datagram socket to "host:port" is open before writing to it. The
-- engine only writes to an OPEN socket: `write ... to socket "h:p"` on a name
-- that was never opened sets the result to "socket is not open" and sends
-- NOTHING, silently (engine/src/exec-network.cpp, MCNetworkExecWriteToSocket).
-- Opening is idempotent here, so call it before every send.
-- (Broadcast additionally needs `set the allowDatagramBroadcasts to true`.)
command scEnsureDatagramSocket pHostPort
   if pHostPort is not among the lines of the openSockets then
      open datagram socket to pHostPort
   end if
end scEnsureDatagramSocket

-- ===== Building and sending =================================================

-- Build an OSC args list the way LiveCode Script must. xTalk has NO [...]
-- list-literal expression (that is LiveCode Builder syntax), so you cannot write
-- oscBuildMessage("/x", [["i", 60]]) in a .livecodescript. Instead build the args
-- array by assignment: scAddArg appends one type/value pair as TWO consecutive
-- elements (a FLAT list -- a nested LiveCode array does not survive the Script->LCB
-- boundary as a list-of-lists, so we flatten to scalars), to an args array passed
-- BY REFERENCE. Hand the finished array to oscBuildMessage / scOscSend. For the
-- no-value OSC types (T/F/N/I) pass empty for the value -- it is ignored.
--
--   local tArgs
--   scAddArg tArgs, "i", 60
--   scAddArg tArgs, "f", 0.8
--   put oscBuildMessage("/synth/note", tArgs) into tData
command scAddArg @pArgs, pType, pValue
   put pType into pArgs[(the number of elements of pArgs) + 1]
   if pType is "b" then
      -- Blob: raw Data must cross unchanged (oscBuildMessage reads it as Data).
      put pValue into pArgs[(the number of elements of pArgs) + 1]
   else
      -- Force every non-blob value to a STRING before it enters the args list.
      -- `& empty` is LiveCode's force-to-string: it collapses the number/string
      -- duality to a pure string, which arrives in LCB as a String and is parsed
      -- in C. (Pass floats/doubles you need at full precision as strings -- a
      -- string is preserved verbatim; a number is stringified via numberFormat.)
      put (pValue & empty) into pArgs[(the number of elements of pArgs) + 1]
   end if
end scAddArg

-- Send one OSC message to host:port. pArgs is an args array built with scAddArg.
-- Builds nothing and sends nothing when the message cannot be built
-- (oscLastError() says why).
on scOscSend pHost, pPort, pAddress, pArgs
   local tData
   put oscBuildMessage(pAddress, pArgs) into tData
   if tData is empty then
      exit scOscSend
   end if
   scEnsureDatagramSocket pHost & ":" & pPort
   write tData to socket (pHost & ":" & pPort)
end scOscSend

-- ===== Receiving and routing ================================================

-- Route inbound OSC by address. Wire it up with
--     accept datagram connections on port 9000 with message "socketReceived"
-- and write your own `on scOscMessage pAddress, pArgs, pSender` to react
-- (pArgs is the parsed argument array; bundles are unpacked, nested ones too).
--
-- The engine calls a datagram message with (sender "host:port", data, socket)
-- -- in THAT order (engine/src/opensslsocket.cpp, MCSocket::readsome). This
-- handler once declared (pData, pHostAndPort), so it parsed the sender's address
-- as OSC and never routed anything; it also issued a blocking `read from socket`,
-- which an accepted datagram socket does not need (every datagram arrives as its
-- own message). For callers wired the old way round, a packet in the first
-- parameter is still recognised.
on socketReceived pSender, pData
   local tMsg
   if scLooksLikeOsc(pSender) and not scLooksLikeOsc(pData) then
      put oscParse(pSender) into tMsg
      put pData into pSender
   else
      put oscParse(pData) into tMsg
   end if
   scOscRoute tMsg, pSender, the long id of the target
end socketReceived

-- Deliver one parsed message (or every message of a bundle, recursively).
command scOscRoute pMsg, pSender, pTarget
   local tSub
   if pMsg["isBundle"] is true then
      repeat for each element tSub in pMsg["messages"]
         scOscRoute tSub, pSender, pTarget
      end repeat
   else if pMsg["address"] is not empty then
      dispatch "scOscMessage" to pTarget with pMsg["address"], pMsg["args"], pSender
   end if
end scOscRoute

-- Does this value look like an OSC packet (a message or a bundle)?
function scLooksLikeOsc pX
   if char 1 of pX is "/" then
      return true
   end if
   return (byte 1 to 8 of pX) is ("#bundle" & numToByte(0))
end scLooksLikeOsc
