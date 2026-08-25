script "nostr-relay"
-- nostr-relay.livecodescript - the NostrXT relay client (public nxr*).
--
-- The stateful half of NostrXT: a websocket (RFC 6455) client over engine
-- sockets that speaks the NIP-01 relay protocol - REQ / CLOSE / EVENT out,
-- EVENT / OK / EOSE / CLOSED / NOTICE / AUTH in. It COMPOSES the pure-compute
-- core (src/nostrxt.livecodescript, nx*): url parsing, handshake and accept
-- derivation, frame encode/decode, message build/parse, event verification.
-- Load the core first; this file owns only sockets, buffers and handles.
--
-- THIS FILE IS DELIBERATELY NOT EMBEDDED IN THE SUITE PASTE: it defines the
-- engine's socketError / socketClosed / socketTimeout handlers, which the
-- embedded onionxt layer also defines, and the suite generator refuses (as
-- it must) an assembly that defines one handler twice. It ships in the demo
-- embed instead (the onion-httpd precedent), and its offline paths are
-- exercised by probe-guarded harness sections that SKIP in the paste.
--
-- STATUS, and it is SPLIT - read both halves before quoting either.
-- LIVE-PROVEN 2026-08-24 (Windows x86_64, OXT 9.6.3, wss://nos.lol): connect,
-- the websocket handshake, publish, and the relay's ok-true verdict arriving
-- back through the app callback. That run went over TLS, so it is also this
-- suite's FIRST exercised `open secure socket` - the wss:// path is no longer
-- the doubly-flagged unknown this banner used to describe, and
-- docs/OXT-ENGINE-NOTES.md 6.8 records exactly what the one run measured.
-- STILL UNPROVEN, and keeping "verified statically; needs a live-relay pass":
-- the whole RECEIVE leg - REQ/subscribe, the EVENT and EOSE callbacks,
-- CLOSED, NOTICE - and the NIP-42 auth exchange. So is every ws:// path: the
-- proven run was secure, and the plain form here still rests on onionxt's
-- engine-proven SOCKS idioms rather than on a run of its own.
--
-- Conventions (see CLAUDE.md): public API nxrPascalCase; commands report
-- through `the result` (empty on success, a "NostrXT relay: ..." string on
-- refusal; handle-yielding commands return the integer handle, so callers
-- test `the result is an integer`) - the onionxt shape for a stateful
-- layer. Async outcomes arrive through the app callback, never a blocking
-- return. Every wire error fails closed and tears the connection down;
-- every teardown is idempotent; the app frees what it opens (closeStack).
--
-- CALLBACK CONTRACT: nxrSetCallback registers <handler> per relay; it is
-- dispatched (try-guarded; a missing handler is a clean no-op) to the owner
-- set by nxrInit (default: the topStack) as:
--   <handler> pRelay, pKind, pArgOne, pArgTwo
--     pKind = "open"          handshake complete; the relay is usable
--     pKind = "event"         pArgOne = subscription id, pArgTwo = the raw
--                             event JSON. VERIFIED (id + signature) before
--                             delivery unless nxrSetVerify turned that off.
--     pKind = "invalid"       pArgOne = subscription id, pArgTwo = why the
--                             event was refused (failed verify, or CoinXT
--                             absent while verification is on - fail closed)
--     pKind = "eose"          pArgOne = subscription id
--     pKind = "ok"            pArgOne = event id, pArgTwo = "true" or
--                             "false", then a tab, then the relay's reason
--     pKind = "closed"        pArgOne = subscription id, pArgTwo = reason
--     pKind = "notice"        pArgOne = the notice text
--     pKind = "auth"          pArgOne = the NIP-42 challenge (also kept for
--                             nxrChallenge; answer with nxAuthBuild +
--                             nxEventSign + nxrAuth)
--     pKind = "error"         pArgOne = the failure; the relay is torn down
--     pKind = "disconnected"  pArgOne = the reason; the relay is gone

-- ==========================================================================
-- Constants.
-- ==========================================================================

constant kNxrHandshakeTimeout = 20000     -- milliseconds
-- The receive buffer cap: a peer that streams bytes without ever completing
-- a frame must hit a wall, not exhaust memory (fail closed).
constant kNxrMaxBuffer = 16777216

-- ==========================================================================
-- Script-local state. Handle tables keyed by integer handle and by engine
-- socket id; a stale id is a clean no-op (family rule 4's spirit).
-- ==========================================================================

local sNxrRelays             -- keyed by handle: socketID, state, url, host,
                             -- port, path, secure, wsKey, buffer, callback,
                             -- verify, challenge, fragOp, fragData, subs
local sNxrSockToRelay        -- socket id -> handle
local sNxrNextHandle         -- monotonic; 0 never valid
local sNxrOwner              -- long id the callbacks dispatch to

-- ==========================================================================
-- Wiring.
-- ==========================================================================

function nxrVersion
   return "NostrXT relay" && nxVersion()
end nxrVersion

command nxrInit pOwner
   -- Set the object whose script receives the callbacks (the demo passes
   -- `the long id of me` in preOpenStack). Idempotent.
   put pOwner into sNxrOwner
   return empty
end nxrInit

private function nxrCallbackTarget
   if sNxrOwner is not empty then
      return sNxrOwner
   end if
   return the topStack
end nxrCallbackTarget

private command nxrDispatch pRelay, pKind, pArgOne, pArgTwo
   -- Deliver one callback, try-guarded: a throwing app handler must not
   -- break the socket state machine, and a missing handler is a clean miss
   -- (the onionxt oxDispatch shape).
   local tError, tHandler
   put sNxrRelays[pRelay]["callback"] into tHandler
   if tHandler is empty then
      exit nxrDispatch
   end if
   try
      dispatch tHandler to nxrCallbackTarget() with pRelay, pKind, pArgOne, pArgTwo
   catch tError
      -- Swallowed on purpose: the app broke, the transport must not.
   end try
end nxrDispatch

private function nxrAllocHandle
   if sNxrNextHandle is empty then
      put 0 into sNxrNextHandle
   end if
   add 1 to sNxrNextHandle
   return sNxrNextHandle
end nxrAllocHandle

private function nxrRandomHex pByteCount
   -- Hex for pByteCount random bytes. Prefers SodiumXT; falls back to the
   -- engine's random(). ACCEPTABILITY: these bytes are websocket MASKS and
   -- handshake nonces - RFC 6455's masking defends proxy caches, not
   -- confidentiality - so a non-cryptographic fallback is honest here. Key
   -- material NEVER comes through this function (nxKeyGenerate refuses
   -- outright without SodiumXT).
   local tError, tData, tI
   try
      put sxRandomBytes(pByteCount) into tData
      if the number of bytes of tData is pByteCount then
         return nxHexEncode(tData)
      end if
   catch tError
      put empty into tData
   end try
   put empty into tData
   repeat with tI = 1 to pByteCount
      put numToByte(random(256) - 1) after tData
   end repeat
   return nxHexEncode(tData)
end nxrRandomHex

-- ==========================================================================
-- Connect and the handshake state machine.
-- ==========================================================================

command nxrConnect pUrl
   -- Returns an integer relay handle through `the result` immediately; the
   -- handshake completes asynchronously and the callback receives "open" or
   -- "error". States: connecting -> handshake -> open -> closing/gone.
   local tParsed, tHandle, tSocketID, tKeyHex
   put nxWsUrlParse(pUrl) into tParsed
   if tParsed is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   put nxrAllocHandle() into tHandle
   -- A named socket id so several relays at one host:port stay distinct
   -- (the onionxt |name discipline; store the engine's id verbatim).
   put tParsed["host"] & ":" & tParsed["port"] & "|nxr" & tHandle into tSocketID
   put tSocketID into sNxrRelays[tHandle]["socketID"]
   put "connecting" into sNxrRelays[tHandle]["state"]
   put pUrl into sNxrRelays[tHandle]["url"]
   put tParsed["host"] into sNxrRelays[tHandle]["host"]
   put tParsed["port"] into sNxrRelays[tHandle]["port"]
   put tParsed["path"] into sNxrRelays[tHandle]["path"]
   put tParsed["secure"] into sNxrRelays[tHandle]["secure"]
   put empty into sNxrRelays[tHandle]["buffer"]
   put empty into sNxrRelays[tHandle]["callback"]
   put true into sNxrRelays[tHandle]["verify"]
   put empty into sNxrRelays[tHandle]["challenge"]
   put empty into sNxrRelays[tHandle]["fragOp"]
   put empty into sNxrRelays[tHandle]["fragData"]
   -- The Sec-WebSocket-Key: 16 random bytes, base64.
   put nxrRandomHex(16) into tKeyHex
   put nxB64Encode(nxHexDecode(tKeyHex)) into sNxrRelays[tHandle]["wsKey"]
   put tHandle into sNxrSockToRelay[tSocketID]
   set the socketTimeoutInterval to kNxrHandshakeTimeout
   if tParsed["secure"] is true then
      -- ENGINE-ARMED 2026-08-24: this line is the suite's first and so far
      -- only exercised `open secure socket`, and it reached an ordinary
      -- public relay - so the form exists on OXT 9.6.3, connects, and carries
      -- the handshake and the framing below.
      -- VERIFY (on-engine), because "it connected" is not "it verifies": a
      -- REJECTED certificate was never tried, so whether an invalid one is
      -- refused or silently accepted is still unmeasured, as are the TLS
      -- versions offered and how a TLS failure is delivered (expected: a
      -- socketError message, as with the plain form). docs/07 gap #2 carries
      -- that remainder; engine notes 6.8 carries what the run did settle.
      open secure socket to tSocketID with message "nxrWsOpened"
   else
      open socket to tSocketID with message "nxrWsOpened"
   end if
   send ("nxrDeadline " & tHandle) to me in kNxrHandshakeTimeout milliseconds
   return tHandle
end nxrConnect

command nxrWsOpened pSocketID
   -- ENGINE-ARMED: TCP (or TLS) is up; send the upgrade request and start
   -- the one persistent read. A stale id is a clean no-op.
   local tHandle, tRequest
   put sNxrSockToRelay[pSocketID] into tHandle
   if tHandle is empty then
      exit nxrWsOpened
   end if
   put "handshake" into sNxrRelays[tHandle]["state"]
   put nxWsHandshakeRequest(sNxrRelays[tHandle]["host"], sNxrRelays[tHandle]["port"], sNxrRelays[tHandle]["path"], sNxrRelays[tHandle]["wsKey"], sNxrRelays[tHandle]["secure"]) into tRequest
   if tRequest is empty then
      nxrFail tHandle, "could not build the handshake request:" && nxLastError()
      exit nxrWsOpened
   end if
   write textEncode(tRequest, "UTF-8") to socket pSocketID
   read from socket pSocketID with message "nxrWsData"
end nxrWsOpened

command nxrWsData pSocketID, pData
   -- ENGINE-ARMED: the persistent read delivers whatever bytes arrived;
   -- append to the relay's buffer, run the state machine, and re-arm ONLY
   -- if the relay still exists (the callback may have torn it down - the
   -- onionxt oxStreamData discipline).
   local tHandle
   put sNxrSockToRelay[pSocketID] into tHandle
   if tHandle is empty then
      exit nxrWsData
   end if
   put pData after sNxrRelays[tHandle]["buffer"]
   if the number of bytes of sNxrRelays[tHandle]["buffer"] > kNxrMaxBuffer then
      nxrFail tHandle, "receive buffer exceeded" && kNxrMaxBuffer && "bytes"
      exit nxrWsData
   end if
   nxrProcessBuffer tHandle
   if sNxrSockToRelay[pSocketID] is not empty then
      read from socket pSocketID with message "nxrWsData"
   end if
end nxrWsData

command nxrDeadline pRelay
   -- Self-sent watchdog: a handshake that has not reached "open" by the
   -- deadline fails closed (a bootstrapping or stalled peer accepts TCP and
   -- then hangs; rule: timeouts are mandatory).
   if sNxrRelays[pRelay]["socketID"] is empty then
      exit nxrDeadline
   end if
   if sNxrRelays[pRelay]["state"] is "connecting" or sNxrRelays[pRelay]["state"] is "handshake" then
      nxrFail pRelay, "the websocket handshake timed out"
   end if
end nxrDeadline

private command nxrProcessBuffer pRelay
   -- Drive whichever phase the connection is in. The handshake phase eats
   -- the HTTP response; anything after it falls through to the frame phase.
   if sNxrRelays[pRelay]["state"] is "handshake" then
      nxrProcessHandshake pRelay
   end if
   if sNxrRelays[pRelay]["state"] is "open" or sNxrRelays[pRelay]["state"] is "closing" then
      nxrProcessFrames pRelay
   end if
end nxrProcessBuffer

private function nxrHeaderEnd pBuffer
   -- The byte position just PAST the CRLFCRLF terminator, or 0.
   local tI, tN
   put the number of bytes of pBuffer into tN
   repeat with tI = 1 to tN - 3
      if byteToNum(byte tI of pBuffer) is 13 and byteToNum(byte (tI + 1) of pBuffer) is 10 and byteToNum(byte (tI + 2) of pBuffer) is 13 and byteToNum(byte (tI + 3) of pBuffer) is 10 then
         return tI + 4
      end if
   end repeat
   return 0
end nxrHeaderEnd

private command nxrProcessHandshake pRelay
   -- Validate the 101 upgrade response: status code and the accept echo.
   -- Fail closed on anything else - a relay that answers 200 is a web page,
   -- not a websocket.
   local tEnd, tHeaderText, tSavedLineDelim, tStatusLine, tAcceptValue, tLineCount, tI, tLineText, tColonPos, tHeaderName
   put nxrHeaderEnd(sNxrRelays[pRelay]["buffer"]) into tEnd
   if tEnd is 0 then
      exit nxrProcessHandshake        -- headers not complete yet
   end if
   put textDecode(byte 1 to (tEnd - 1) of sNxrRelays[pRelay]["buffer"], "UTF-8") into tHeaderText
   -- Consume the header bytes; whatever follows is already frame data.
   if tEnd > the number of bytes of sNxrRelays[pRelay]["buffer"] then
      put empty into sNxrRelays[pRelay]["buffer"]
   else
      put byte tEnd to (the number of bytes of sNxrRelays[pRelay]["buffer"]) of sNxrRelays[pRelay]["buffer"] into sNxrRelays[pRelay]["buffer"]
   end if
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to numToChar(13) & numToChar(10)
   put line 1 of tHeaderText into tStatusLine
   put empty into tAcceptValue
   put the number of lines of tHeaderText into tLineCount
   repeat with tI = 2 to tLineCount
      put line tI of tHeaderText into tLineText
      put offset(":", tLineText) into tColonPos
      if tColonPos < 2 then
         next repeat
      end if
      put char 1 to (tColonPos - 1) of tLineText into tHeaderName
      -- Header names are case-insensitive by HTTP's own rule, so the folded
      -- compare `is` gives here is the CORRECT one for once.
      if nxrToLowerAscii(tHeaderName) is "sec-websocket-accept" then
         put char (tColonPos + 1) to (the number of chars of tLineText) of tLineText into tAcceptValue
         repeat while char 1 of tAcceptValue is " "
            delete char 1 of tAcceptValue
         end repeat
         repeat while char (the number of chars of tAcceptValue) of tAcceptValue is " "
            delete char (the number of chars of tAcceptValue) of tAcceptValue
         end repeat
      end if
   end repeat
   set the lineDelimiter to tSavedLineDelim
   if not (tStatusLine contains " 101 ") then
      nxrFail pRelay, "the server did not upgrade (status line: " & tStatusLine & ")"
      exit nxrProcessHandshake
   end if
   if not nxrStrEq(tAcceptValue, nxWsAcceptFor(sNxrRelays[pRelay]["wsKey"])) then
      nxrFail pRelay, "Sec-WebSocket-Accept mismatch (not a compliant websocket server)"
      exit nxrProcessHandshake
   end if
   put "open" into sNxrRelays[pRelay]["state"]
   nxrDispatch pRelay, "open", empty, empty
end nxrProcessHandshake

private function nxrToLowerAscii pText
   -- ASCII lowercase by byte value. Local copy for the same reason as
   -- nxrStrEq below: the core's nxToLowerAscii is PRIVATE to its own
   -- script when the two files load as separate stacks, and a private
   -- handler called cross-script is an execution error at the first
   -- handshake (the adversarial review traced exactly that).
   local tOut, tI, tCount, tCode
   put empty into tOut
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode >= 65 and tCode <= 90 then
         put numToChar(tCode + 32) after tOut
      else
         put numToChar(tCode) after tOut
      end if
   end repeat
   return tOut
end nxrToLowerAscii

private function nxrStrEq pA, pB
   -- Byte-exact equality (the accept value is base64: case matters and `is`
   -- folds case). Local copy: the core's nxStrEqExact is private to its own
   -- script when the two files load as separate stacks.
   local tA, tB, tI, tN
   put textEncode(pA, "UTF-8") into tA
   put textEncode(pB, "UTF-8") into tB
   put the number of bytes of tA into tN
   if tN is not the number of bytes of tB then
      return false
   end if
   repeat with tI = 1 to tN
      if byteToNum(byte tI of tA) is not byteToNum(byte tI of tB) then
         return false
      end if
   end repeat
   return true
end nxrStrEq

private command nxrProcessFrames pRelay
   -- Drain complete frames from the buffer. Client-bound frames from a
   -- server are unmasked; nxWsFrameDecode handles either. Fragmented text
   -- reassembles across continuation frames; control frames interleave.
   local tFrame, tRemaining, tTotal
   repeat forever
      if sNxrRelays[pRelay]["socketID"] is empty then
         exit repeat        -- torn down mid-drain
      end if
      put nxWsFrameDecode(sNxrRelays[pRelay]["buffer"]) into tFrame
      if tFrame["error"] is not empty then
         nxrFail pRelay, "websocket framing:" && tFrame["error"]
         exit repeat
      end if
      if tFrame["complete"] is not true then
         exit repeat
      end if
      put the number of bytes of sNxrRelays[pRelay]["buffer"] into tTotal
      if tFrame["consumed"] >= tTotal then
         put empty into sNxrRelays[pRelay]["buffer"]
      else
         put byte (tFrame["consumed"] + 1) to tTotal of sNxrRelays[pRelay]["buffer"] into sNxrRelays[pRelay]["buffer"]
      end if
      if tFrame["opcode"] >= 8 then
         nxrHandleControlFrame pRelay, tFrame["opcode"], tFrame["payload"]
      else
         nxrHandleDataFrame pRelay, tFrame["opcode"], tFrame["fin"], tFrame["payload"]
      end if
   end repeat
end nxrProcessFrames

private command nxrHandleControlFrame pRelay, pOpcode, pPayload
   local tMask, tFrame
   if pOpcode is 8 then
      -- Close: echo one close back (best effort), then tear down.
      if sNxrRelays[pRelay]["state"] is "open" then
         put "closing" into sNxrRelays[pRelay]["state"]
         put nxrRandomHex(4) into tMask
         put nxWsFrameEncode(8, pPayload, tMask) into tFrame
         if tFrame is not empty then
            write tFrame to socket sNxrRelays[pRelay]["socketID"]
         end if
      end if
      nxrTeardown pRelay, "the relay closed the connection"
   else if pOpcode is 9 then
      -- Ping: answer with a pong carrying the same payload.
      put nxrRandomHex(4) into tMask
      put nxWsFrameEncode(10, pPayload, tMask) into tFrame
      if tFrame is not empty then
         write tFrame to socket sNxrRelays[pRelay]["socketID"]
      end if
   end if
   -- Pong (10) and unknown control opcodes are ignored on purpose.
end nxrHandleControlFrame

private command nxrHandleDataFrame pRelay, pOpcode, pFin, pPayload
   -- Text (1) and continuation (0) frames carry the relay protocol; binary
   -- (2) is not part of NIP-01 and is ignored with a notice-level callback.
   local tMessage
   if pOpcode is 2 then
      nxrDispatch pRelay, "notice", "ignored a binary websocket frame", empty
      exit nxrHandleDataFrame
   end if
   if pOpcode is 1 then
      if pFin is true then
         nxrHandleMessage pRelay, pPayload
         exit nxrHandleDataFrame
      end if
      put 1 into sNxrRelays[pRelay]["fragOp"]
      put pPayload into sNxrRelays[pRelay]["fragData"]
      exit nxrHandleDataFrame
   end if
   if pOpcode is 0 then
      if sNxrRelays[pRelay]["fragOp"] is empty then
         nxrFail pRelay, "continuation frame with nothing to continue"
         exit nxrHandleDataFrame
      end if
      put pPayload after sNxrRelays[pRelay]["fragData"]
      if the number of bytes of sNxrRelays[pRelay]["fragData"] > kNxrMaxBuffer then
         nxrFail pRelay, "fragmented message exceeded" && kNxrMaxBuffer && "bytes"
         exit nxrHandleDataFrame
      end if
      if pFin is true then
         put sNxrRelays[pRelay]["fragData"] into tMessage
         put empty into sNxrRelays[pRelay]["fragOp"]
         put empty into sNxrRelays[pRelay]["fragData"]
         nxrHandleMessage pRelay, tMessage
      end if
   end if
end nxrHandleDataFrame

private command nxrHandleMessage pRelay, pPayloadData
   -- One complete text message: parse the relay protocol and dispatch. An
   -- unparseable message is surfaced, never silently dropped (fail closed
   -- in the visible sense: the app learns its relay is misbehaving).
   local tParsed, tEvent, tReason
   put nxRelayParse(textDecode(pPayloadData, "UTF-8")) into tParsed
   if tParsed is empty then
      nxrDispatch pRelay, "notice", "unparseable relay message:" && nxLastError(), empty
      exit nxrHandleMessage
   end if
   if tParsed["type"] is "EVENT" then
      if sNxrRelays[pRelay]["verify"] is true then
         put nxEventFromJson(tParsed["eventJson"]) into tEvent
         if tEvent is empty then
            nxrDispatch pRelay, "invalid", tParsed["subId"], "unparseable event:" && nxLastError()
            exit nxrHandleMessage
         end if
         if nxEventVerify(tEvent) is not true then
            put nxLastError() into tReason
            nxrDispatch pRelay, "invalid", tParsed["subId"], tReason
            exit nxrHandleMessage
         end if
      end if
      nxrDispatch pRelay, "event", tParsed["subId"], tParsed["eventJson"]
   else if tParsed["type"] is "OK" then
      nxrDispatch pRelay, "ok", tParsed["eventId"], tParsed["accepted"] & tab & tParsed["reason"]
   else if tParsed["type"] is "EOSE" then
      nxrDispatch pRelay, "eose", tParsed["subId"], empty
   else if tParsed["type"] is "CLOSED" then
      nxrDispatch pRelay, "closed", tParsed["subId"], tParsed["reason"]
   else if tParsed["type"] is "NOTICE" then
      nxrDispatch pRelay, "notice", tParsed["notice"], empty
   else if tParsed["type"] is "AUTH" then
      put tParsed["challenge"] into sNxrRelays[pRelay]["challenge"]
      nxrDispatch pRelay, "auth", tParsed["challenge"], empty
   else
      nxrDispatch pRelay, "notice", "unknown relay message type", empty
   end if
end nxrHandleMessage

-- ==========================================================================
-- The client verbs.
-- ==========================================================================

private command nxrSendText pRelay, pText
   -- Frame and send one text message; reports via `the result`.
   local tFrame
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "NostrXT relay: unknown relay handle" && pRelay
   end if
   if sNxrRelays[pRelay]["state"] is not "open" then
      return "NostrXT relay: relay" && pRelay && "is not open (state:" && sNxrRelays[pRelay]["state"] & ")"
   end if
   put nxWsFrameEncode(1, textEncode(pText, "UTF-8"), nxrRandomHex(4)) into tFrame
   if tFrame is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   write tFrame to socket sNxrRelays[pRelay]["socketID"]
   return empty
end nxrSendText

command nxrSetCallback pRelay, pHandlerName
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "NostrXT relay: unknown relay handle" && pRelay
   end if
   put pHandlerName into sNxrRelays[pRelay]["callback"]
   return empty
end nxrSetCallback

command nxrSetVerify pRelay, pVerify
   -- Event verification is ON by default and fails closed (no CoinXT means
   -- events arrive as "invalid", never as unverified "event"s). An app that
   -- explicitly wants raw delivery turns it off per relay, eyes open.
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "NostrXT relay: unknown relay handle" && pRelay
   end if
   if pVerify is not true and pVerify is not false then
      return "NostrXT relay: nxrSetVerify takes true or false"
   end if
   put pVerify into sNxrRelays[pRelay]["verify"]
   return empty
end nxrSetVerify

command nxrSubscribe pRelay, pSubId, pFiltersJson
   local tWire
   put nxClientReq(pSubId, pFiltersJson) into tWire
   if tWire is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   nxrSendText pRelay, tWire
   if the result is not empty then
      return the result
   end if
   put pFiltersJson into sNxrRelays[pRelay]["subs"][pSubId]
   return empty
end nxrSubscribe

command nxrUnsubscribe pRelay, pSubId
   local tWire
   put nxClientClose(pSubId) into tWire
   if tWire is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   nxrSendText pRelay, tWire
   if the result is not empty then
      return the result
   end if
   delete variable sNxrRelays[pRelay]["subs"][pSubId]
   return empty
end nxrUnsubscribe

command nxrPublish pRelay, pEvent
   -- Send a SIGNED event; the relay's verdict arrives as the "ok" callback
   -- keyed by the event id.
   local tWire
   put nxClientEvent(pEvent) into tWire
   if tWire is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   nxrSendText pRelay, tWire
   return the result
end nxrPublish

command nxrAuth pRelay, pSignedEvent
   -- Answer a NIP-42 challenge (nxAuthBuild + nxEventSign built it).
   local tWire
   put nxClientAuth(pSignedEvent) into tWire
   if tWire is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   nxrSendText pRelay, tWire
   return the result
end nxrAuth

command nxrSendRaw pRelay, pText
   -- The escape hatch for NIPs this layer does not speak yet: one text
   -- frame, verbatim. The caller owns the JSON.
   nxrSendText pRelay, pText
   return the result
end nxrSendRaw

command nxrPing pRelay
   -- An RFC 6455 ping (liveness probe); a compliant peer answers with a
   -- pong, which this layer ignores on arrival.
   local tFrame
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "NostrXT relay: unknown relay handle" && pRelay
   end if
   if sNxrRelays[pRelay]["state"] is not "open" then
      return "NostrXT relay: relay" && pRelay && "is not open"
   end if
   put nxWsFrameEncode(9, textEncode("nxr", "UTF-8"), nxrRandomHex(4)) into tFrame
   write tFrame to socket sNxrRelays[pRelay]["socketID"]
   return empty
end nxrPing

function nxrState pRelay
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "unknown"
   end if
   return sNxrRelays[pRelay]["state"]
end nxrState

function nxrUrl pRelay
   if sNxrRelays[pRelay]["socketID"] is empty then
      return empty
   end if
   return sNxrRelays[pRelay]["url"]
end nxrUrl

function nxrChallenge pRelay
   -- The most recent NIP-42 challenge this relay sent, or empty.
   if sNxrRelays[pRelay]["socketID"] is empty then
      return empty
   end if
   return sNxrRelays[pRelay]["challenge"]
end nxrChallenge

function nxrOpenRelays
   -- Every live relay handle, one per line (delimiter-guarded read of the
   -- handle table's keys).
   local tSavedLineDelim, tOut, tKeyList, tI, tCount
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   put the keys of sNxrRelays into tKeyList
   sort lines of tKeyList numeric
   put empty into tOut
   put the number of lines of tKeyList into tCount
   repeat with tI = 1 to tCount
      if tOut is not empty then
         put return after tOut
      end if
      put line tI of tKeyList after tOut
   end repeat
   set the lineDelimiter to tSavedLineDelim
   return tOut
end nxrOpenRelays

-- ==========================================================================
-- Teardown: idempotent, fail closed, own the lifecycle.
-- ==========================================================================

private command nxrSafeCloseSocket pSocketID
   -- Close only a socket the engine still lists (the onionxt idempotent-
   -- close shape; delimiter-guarded read of the openSockets).
   local tSavedLineDelim, tIsOpen
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   put (pSocketID is among the lines of the openSockets) into tIsOpen
   set the lineDelimiter to tSavedLineDelim
   if tIsOpen then
      close socket pSocketID
   end if
end nxrSafeCloseSocket

private command nxrDispatchTo pHandler, pRelay, pKind, pArgOne, pArgTwo
   -- nxrDispatch by EXPLICIT handler name, for callbacks delivered after
   -- the relay's table entry is already gone (teardown saves the name
   -- first). Same try guard, same clean-miss contract.
   local tError
   if pHandler is empty then
      exit nxrDispatchTo
   end if
   try
      dispatch pHandler to nxrCallbackTarget() with pRelay, pKind, pArgOne, pArgTwo
   catch tError
      -- Swallowed on purpose: the app broke, the transport must not.
   end try
end nxrDispatchTo

private command nxrTeardown pRelay, pReason
   -- Close and FORGET FIRST, tell the app once AFTER: the callback runs
   -- app code synchronously, and an app that answers "disconnected" by
   -- calling nxrDisconnect on the same handle must find the clean no-op
   -- the contract promises - dispatching while the tables were still
   -- populated re-entered a relay that looked fully open (a second close
   -- frame on the wire, a second callback, unbounded recursion; the
   -- adversarial review traced the loop). Safe to call twice.
   local tSocketID, tCallback
   put sNxrRelays[pRelay]["socketID"] into tSocketID
   if tSocketID is empty then
      exit nxrTeardown
   end if
   put sNxrRelays[pRelay]["callback"] into tCallback
   nxrSafeCloseSocket tSocketID
   delete variable sNxrSockToRelay[tSocketID]
   delete variable sNxrRelays[pRelay]
   nxrDispatchTo tCallback, pRelay, "disconnected", pReason, empty
end nxrTeardown

private command nxrFail pRelay, pReason
   -- A wire error: tear down FIRST (the reentrancy rule above), then
   -- surface "error" and "disconnected" from the saved callback name.
   local tSocketID, tCallback
   put sNxrRelays[pRelay]["socketID"] into tSocketID
   if tSocketID is empty then
      exit nxrFail
   end if
   put sNxrRelays[pRelay]["callback"] into tCallback
   nxrSafeCloseSocket tSocketID
   delete variable sNxrSockToRelay[tSocketID]
   delete variable sNxrRelays[pRelay]
   nxrDispatchTo tCallback, pRelay, "error", pReason, empty
   nxrDispatchTo tCallback, pRelay, "disconnected", pReason, empty
end nxrFail

command nxrDisconnect pRelay
   -- App-initiated close: send a close frame when the link is up, then
   -- tear down. Idempotent; a stale handle is a clean no-op.
   local tMask
   if sNxrRelays[pRelay]["socketID"] is empty then
      exit nxrDisconnect
   end if
   if sNxrRelays[pRelay]["state"] is "open" then
      put nxrRandomHex(4) into tMask
      write nxWsFrameEncode(8, numToByte(3) & numToByte(232), tMask) to socket sNxrRelays[pRelay]["socketID"]
   end if
   nxrTeardown pRelay, "disconnected by the app"
end nxrDisconnect

command nxrShutdown
   -- Close every relay (closeStack calls this; there is no deterministic
   -- unload hook in OXT, so the app frees what it opens).
   local tSavedLineDelim, tKeyList, tI, tCount
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   put the keys of sNxrRelays into tKeyList
   put the number of lines of tKeyList into tCount
   set the lineDelimiter to tSavedLineDelim
   repeat with tI = 1 to tCount
      -- Re-read the key list line by line under a fresh guard each pass:
      -- nxrDisconnect mutates the table while this walks a SNAPSHOT.
      put the lineDelimiter into tSavedLineDelim
      set the lineDelimiter to return
      nxrDisconnect (line tI of tKeyList)
      set the lineDelimiter to tSavedLineDelim
   end repeat
end nxrShutdown

-- ==========================================================================
-- The engine's socket messages. Act ONLY on our own socket ids and PASS the
-- rest: these three names are shared by every socket user in a stack, and
-- swallowing another library's message is a silent HANG no gate can see
-- (the family's socketError rule; two shipping apps re-derived it).
-- ==========================================================================

-- THE ENGINE'S THREE SOCKET MESSAGES, SPLIT IN TWO (2026-08-24), the same
-- way onionxt splits them and for the same reason: these names belong to the
-- ENGINE, so every socket library in the message path declares them, and one
-- script cannot define a name twice - which is what embedding a library into
-- an app's stack script does (tools/sync-demo-embeds.py). The LOGIC lives in
-- nxrSocketError / nxrSocketClosed / nxrSocketTimeout, which answer one
-- question: was that socket MINE, and did I handle it? The `on socket*`
-- handlers are pure dispatch. An embedder drops the three thin wrappers and
-- calls the named function from its own handler, so this logic is never
-- copied and cannot go stale.

-- Was pSocketID one of OUR relay sockets, and did we handle the error?
function nxrSocketError pSocketID, pError
   local tHandle
   put sNxrSockToRelay[pSocketID] into tHandle
   if tHandle is not empty then
      nxrFail tHandle, "socket error:" && pError
      return "true"
   end if
   return "false"
end nxrSocketError

on socketError pSocketID, pError
   if nxrSocketError(pSocketID, pError) then
      exit socketError
   end if
   pass socketError
end socketError

-- Was pSocketID one of OUR relay sockets, and did we handle the close?
function nxrSocketClosed pSocketID
   local tHandle
   put sNxrSockToRelay[pSocketID] into tHandle
   if tHandle is not empty then
      nxrTeardown tHandle, "the connection closed"
      return "true"
   end if
   return "false"
end nxrSocketClosed

on socketClosed pSocketID
   if nxrSocketClosed(pSocketID) then
      exit socketClosed
   end if
   pass socketClosed
end socketClosed

-- Was pSocketID one of OUR relay sockets, and did we handle the timeout?
function nxrSocketTimeout pSocketID
   -- socketTimeout REPEATS while a read is pending, so it is fatal only
   -- during the handshake; on an open relay an idle read is normal.
   local tHandle
   put sNxrSockToRelay[pSocketID] into tHandle
   if tHandle is not empty then
      if sNxrRelays[tHandle]["state"] is not "open" then
         nxrFail tHandle, "the websocket handshake timed out (socket timeout)"
      end if
      return "true"
   end if
   return "false"
end nxrSocketTimeout

on socketTimeout pSocketID
   if nxrSocketTimeout(pSocketID) then
      exit socketTimeout
   end if
   pass socketTimeout
end socketTimeout
