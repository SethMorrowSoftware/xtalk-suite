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
-- The browser transport (2026-10-21): how often, in milliseconds, the
-- events the page's WebSocket queued are drained, and how many one drain
-- takes before it yields to the engine for a turn.
constant kNxrWebPollMs = 40
constant kNxrWebPollBatch = 64

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
local sNxrWebPolling         -- true while a browser-transport drain is pending

-- ==========================================================================
-- Wiring.
-- ==========================================================================

/**
Title: NostrXT Relay Client
Author: Seth Morrow Software
Description:
The NostrXT Relay Client is a websocket (RFC 6455) client over engine
sockets that speaks the NIP-01 relay protocol: it sends REQ, CLOSE,
EVENT and AUTH, and receives EVENT, OK, EOSE, CLOSED, NOTICE and AUTH.
It composes the NostrXT core library, so load that first; this library
owns only the sockets, buffers and relay handles.

In a web page (the platform is "HTML5": OXT-Beyond's web IDE or a web
standalone), which has no engine sockets, each relay is the browser's own
WebSocket instead, driven through JavaScript; the handles, commands and
callbacks are the same.

Each relay is an integer handle from <nxrConnect>. Commands report
through the result: empty on success, or text starting
"NostrXT relay:" for a refusal. Everything that happens later arrives through the callback
handler you register with <nxrSetCallback>, dispatched to the object set
by <nxrInit>.

Inbound events are verified (id and signature) before delivery unless
you turn that off with <nxrSetVerify>. Call <nxrShutdown>
from closeStack: there is no automatic unload.

The library defines the engine's socketError, socketClosed and
socketTimeout messages and passes on any that are not for its own
sockets. If your stack script handles those messages too, it must pass
the ones that are not its own, or another library will hang.

Tags: Networking, Nostr
*/
/**
Summary: Returns the relay client's version.

Returns: The text "NostrXT relay" followed by the core's version string.

Example:
put nxrVersion() into field "versionField"

Description:
It calls <nxVersion>, so it also proves the core library is loaded.

References: nxVersion (handler)
*/
function nxrVersion
   return "NostrXT relay" && nxVersion()
end nxrVersion

/**
Summary: Sets the object whose script receives relay callbacks.

pOwner: The long id of the object, or empty for the topStack.

Example:
nxrInit the long id of me

Description:
Call it once at startup, for example in preOpenStack. Until it is set,
callbacks are dispatched to the topStack, which may not be the stack you
expect. Calling it again replaces the owner.

References: nxrSetCallback (handler), nxrConnect (handler)
*/
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

/**
Summary: Opens a connection to a Nostr relay.

pUrl: The relay URL, starting wss:// or ws://.

Returns: The integer relay handle, or a "NostrXT relay:" refusal.

Example:
nxrConnect "wss://relay.example.com"
put the result into tRelay
if tRelay is an integer then nxrSetCallback tRelay, "relayEvent"

Description:
<nxrConnect> returns at once with the handle in the result; test it with
"is an integer". The connection and the websocket handshake complete
later, and the callback receives "open" when the relay is usable or
"error" and "disconnected" when it fails. A handshake that has not
finished within 20 seconds fails closed. Connecting also sets the
engine's socketTimeoutInterval to 20 seconds.

The callback handler is called with the relay handle, a kind, and up to
two arguments. The kinds are "open"; "event" (subscription id, the
verified event JSON); "invalid" (subscription id, why the event was
refused); "eose" (subscription id); "ok" (event id, then "true" or
"false", a tab and the relay's reason); "closed" (subscription id,
reason); "notice" (the text); "auth" (the NIP-42 challenge); "error"
(the failure); and "disconnected" (the reason).

A wss:// connection has been made on an engine; whether a bad
certificate is refused has not been measured. The ws:// path has not
yet run on an engine.

References: nxrSetCallback (handler), nxrDisconnect (handler), nxrState (handler)
*/
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
   if nxrIsBrowser() then
      -- No engine sockets in a web page: the browser's WebSocket does the
      -- TCP, the TLS and RFC 6455 itself (the browser transport, below).
      return nxrWebConnect(tHandle, pUrl)
   end if
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

on nxrWsOpened pSocketID
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

on nxrWsData pSocketID, pData
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

on nxrDeadline pRelay
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
   if sNxrRelays[pRelay]["web"] is not empty then
      return nxrWebSend(pRelay, pText)
   end if
   put nxWsFrameEncode(1, textEncode(pText, "UTF-8"), nxrRandomHex(4)) into tFrame
   if tFrame is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   write tFrame to socket sNxrRelays[pRelay]["socketID"]
   return empty
end nxrSendText

/**
Summary: Registers the handler that receives a relay's callbacks.

pRelay: The relay handle.

pHandlerName: The name of the handler to dispatch to.

Example:
nxrConnect "wss://relay.example.com"
put the result into tRelay
nxrSetCallback tRelay, "relayEvent"

Description:
The handler is dispatched to the object set by <nxrInit>, with
four arguments: the relay handle, the kind, and two kind-specific
arguments (the kinds are listed under <nxrConnect>). Set it straight
after connecting, before the "open" callback arrives.

Dispatch is guarded: an error in your handler does not break the
connection, and a missing handler is ignored. An unknown handle returns
a refusal in the result.

References: nxrConnect (handler), nxrInit (handler)
*/
command nxrSetCallback pRelay, pHandlerName
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "NostrXT relay: unknown relay handle" && pRelay
   end if
   put pHandlerName into sNxrRelays[pRelay]["callback"]
   return empty
end nxrSetCallback

/**
Summary: Turns event verification on or off for one relay.

pRelay: The relay handle.

pVerify: true to verify inbound events (the default), false to deliver them unverified.

Example:
nxrSetVerify tRelay, false

Description:
Verification is on by default and fails closed: an event whose id or
signature does not check, or any event while CoinXT is missing, arrives
as "invalid", never as "event". Turning it off is a per-relay decision;
then verify events yourself with <nxEventVerify>. A value other than
true or false is refused.

References: nxEventVerify (handler), nxrSetCallback (handler)
*/
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

/**
Summary: Sends a REQ to open a subscription on a relay.

pRelay: The relay handle.

pSubId: The subscription id, 1 to 64 characters.

pFiltersJson: One filter JSON object per line, as from nxFilterBuild.

Example:
put tPubkey into tFilter["authors"]
put "1" into tFilter["kinds"]
nxrSubscribe tRelay, "my-feed", nxFilterBuild(tFilter)
if the result is not empty then answer the result

Description:
The relay must be open. Matching events arrive as "event" callbacks
with the subscription id, followed by "eose" once the stored events are
sent. A relay can end the subscription with "closed".

References: nxrUnsubscribe (handler), nxFilterBuild (handler), nxClientReq (handler)
*/
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

/**
Summary: Sends a CLOSE to end a subscription.

pRelay: The relay handle.

pSubId: The subscription id.

Example:
nxrUnsubscribe tRelay, "my-feed"

Description:
The relay must be open. Refusals come back in the result.

References: nxrSubscribe (handler), nxClientClose (handler)
*/
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

/**
Summary: Sends a signed event to a relay.

pRelay: The relay handle.

pEvent: The signed event array.

Example:
put nxEventSign(nxEventBuild(1, "Hello", empty, empty), tSeckey, empty) into tSigned
nxrPublish tRelay, tSigned
if the result is not empty then answer the result

Description:
The relay must be open, and the event must be signed with
<nxEventSign>. The relay's verdict arrives later as an "ok" callback
with the event id.

References: nxEventSign (handler), nxClientEvent (handler)
*/
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

/**
Summary: Answers a relay's NIP-42 authentication challenge.

pRelay: The relay handle.

pSignedEvent: The signed kind 22242 event.

Example:
put nxAuthBuild(nxrUrl(tRelay), nxrChallenge(tRelay), empty) into tAuth
nxrAuth tRelay, nxEventSign(tAuth, tSeckey, empty)

Description:
Use it after an "auth" callback. Build the event with <nxAuthBuild> and
sign it with <nxEventSign>. The relay must be open; the relay's answer
arrives as an "ok" callback.

References: nxAuthBuild (handler), nxrChallenge (handler), nxClientAuth (handler)
*/
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

/**
Summary: Sends one text message to a relay exactly as given.

pRelay: The relay handle.

pText: The message text, usually a JSON array.

Example:
nxrSendRaw tRelay, tWire

Description:
The escape hatch for NIPs this library does not speak yet. The text is
sent as one websocket text frame; you are responsible for the JSON. The
relay must be open.

References: nxrPublish (handler), nxrSubscribe (handler)
*/
command nxrSendRaw pRelay, pText
   -- The escape hatch for NIPs this layer does not speak yet: one text
   -- frame, verbatim. The caller owns the JSON.
   nxrSendText pRelay, pText
   return the result
end nxrSendRaw

/**
Summary: Sends a websocket ping to a relay.

pRelay: The relay handle.

Example:
nxrPing tRelay

Description:
A liveness probe. The relay must be open; its pong is consumed silently.

References: nxrState (handler)
*/
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
   if sNxrRelays[pRelay]["web"] is not empty then
      -- A page cannot send a ping: the browser answers the relay's pings
      -- and keeps the connection alive itself.
      return empty
   end if
   put nxWsFrameEncode(9, textEncode("nxr", "UTF-8"), nxrRandomHex(4)) into tFrame
   write tFrame to socket sNxrRelays[pRelay]["socketID"]
   return empty
end nxrPing

/**
Summary: Returns the connection state of a relay.

pRelay: The relay handle.

Returns: "connecting", "handshake", "open" or "closing", or "unknown" for a handle that is not live.

Example:
if nxrState(tRelay) is "open" then nxrPublish tRelay, tSigned

Description:
Only an "open" relay accepts subscriptions, publishes and other sends.

References: nxrConnect (handler), nxrOpenRelays (handler)
*/
function nxrState pRelay
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "unknown"
   end if
   return sNxrRelays[pRelay]["state"]
end nxrState

/**
Summary: Returns the URL a relay was opened with.

pRelay: The relay handle.

Returns: The URL, or empty for a handle that is not live.

Example:
put nxrUrl(tRelay) into tUrl

Description:
Useful for <nxAuthBuild>, which needs the relay URL.

References: nxrConnect (handler), nxAuthBuild (handler)
*/
function nxrUrl pRelay
   if sNxrRelays[pRelay]["socketID"] is empty then
      return empty
   end if
   return sNxrRelays[pRelay]["url"]
end nxrUrl

/**
Summary: Returns the most recent NIP-42 challenge a relay sent.

pRelay: The relay handle.

Returns: The challenge text, or empty.

Example:
put nxrChallenge(tRelay) into tChallenge

Description:
The same challenge arrives with the "auth" callback; this keeps it for
when you answer later.

References: nxrAuth (handler), nxAuthBuild (handler)
*/
function nxrChallenge pRelay
   -- The most recent NIP-42 challenge this relay sent, or empty.
   if sNxrRelays[pRelay]["socketID"] is empty then
      return empty
   end if
   return sNxrRelays[pRelay]["challenge"]
end nxrChallenge

/**
Summary: Lists every live relay handle.

Returns: The handles, one per line, in numeric order.

Example:
put nxrOpenRelays() into tHandles

Description:
A handle leaves the list when its connection is torn down.

References: nxrState (handler), nxrShutdown (handler)
*/
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
-- The browser transport (2026-10-21). A web page has no engine sockets
-- (OXT-Beyond's web engine opens none), but the browser has WebSocket, which
-- does the TCP, the TLS and RFC 6455 itself. So in a page each relay is a
-- browser WebSocket, driven with `do ... as "javascript"`, and everything
-- above the transport (the handles, nxrHandleMessage, verification, the
-- callbacks, teardown) is the same code as over engine sockets.
--
-- The page's WebSocket events are QUEUED in JavaScript and DRAINED by a
-- script timer (nxrWebPoll), never delivered by calling a handler from
-- JavaScript: the family's poll-drain rule (suite rule 1), and it keeps
-- every callback on the engine's own message loop, in order. Text crosses
-- the boundary as base64 of its UTF-8 bytes in both directions, so no
-- escaping is involved and a quote, a backslash or a line break in an
-- event cannot change the JavaScript that carries it.
--
-- The relay's "socketID" is "nxrweb:<n>", <n> the page's id for the
-- WebSocket: never an engine socket name, so the engine's socket messages
-- and nxrSocketError/Closed/Timeout never match it.
--
-- STATUS: verified statically; needs a browser pass.
-- ==========================================================================

private function nxrIsBrowser
   return the platform is "HTML5"
end nxrIsBrowser

private function nxrWebScript
   -- The page-side helper, installed on window.oxtNxrWeb once per page (a
   -- second install keeps the first: its sockets stay reachable).
   local tJs
   put "(function(){if(window.oxtNxrWeb)return 'ok';" & \
         "var R={n:0,s:{}};" & \
         "R.b64=function(t){var b=new TextEncoder().encode(t),r='';" & \
         "for(var i=0;i<b.length;i+=8192){r+=String.fromCharCode.apply(null,b.subarray(i,i+8192));}" & \
         "return btoa(r);};" & \
         "R.text=function(x){var a=atob(x),b=new Uint8Array(a.length);" & \
         "for(var i=0;i<a.length;i++){b[i]=a.charCodeAt(i);}" & \
         "return new TextDecoder().decode(b);};" & \
         "R.open=function(u){var id=++R.n,q=[],w;" & \
         "try{w=new WebSocket(u);}catch(e){return 'error:'+R.b64(String(e&&e.message||e));}" & \
         "R.s[id]={w:w,q:q};" & \
         "w.onopen=function(){q.push('open:');};" & \
         "w.onmessage=function(e){q.push('message:'+R.b64(typeof e.data==='string'?e.data:''));};" & \
         "w.onerror=function(){q.push('error:'+R.b64('the WebSocket failed'));};" & \
         "w.onclose=function(e){q.push('close:'+R.b64(e.code+' '+(e.reason||'')));};" & \
         "return 'id:'+id;};" & \
         "R.send=function(id,x){var s=R.s[id];if(!s)return 'gone';" & \
         "try{s.w.send(R.text(x));return 'ok';}catch(e){return 'error:'+R.b64(String(e&&e.message||e));}};" & \
         "R.next=function(id){var s=R.s[id];if(!s)return 'gone:';" & \
         "return s.q.length?s.q.shift():'';};" & \
         "R.close=function(id){var s=R.s[id];if(!s)return 'gone';delete R.s[id];" & \
         "s.w.onopen=s.w.onmessage=s.w.onerror=s.w.onclose=null;" & \
         "try{s.w.close(1000);}catch(e){}return 'ok';};" & \
         "window.oxtNxrWeb=R;return 'ok';})()" into tJs
   return tJs
end nxrWebScript

private function nxrWebEval pJs
   -- Run one piece of JavaScript in the page and return its value as text,
   -- or "error:" and the reason when it threw (the engine's result is then
   -- "execution error").
   local tError
   try
      do nxrWebScript() as "javascript"
      if the result is not "ok" then
         return "error:" & base64Encode(textEncode("could not install the page's WebSocket helper:" && the result, "UTF-8"))
      end if
      do pJs as "javascript"
      return the result
   catch tError
      return "error:" & base64Encode(textEncode("JavaScript is not available:" && tError, "UTF-8"))
   end try
end nxrWebEval

private function nxrWebDecode pBase64
   -- The text a base64 payload from the page carries (UTF-8 inside).
   return textDecode(base64Decode(pBase64), "UTF-8")
end nxrWebDecode

private function nxrWebConnect pRelay, pUrl
   local tReply, tSocketID
   put nxrWebEval("window.oxtNxrWeb.open(window.oxtNxrWeb.text('" & nxB64Encode(textEncode(pUrl, "UTF-8")) & "'))") into tReply
   if tReply begins with "error:" then
      delete variable sNxrRelays[pRelay]
      return "NostrXT relay: the browser could not open the WebSocket:" && nxrWebDecode(char 7 to -1 of tReply)
   end if
   if not (tReply begins with "id:") then
      delete variable sNxrRelays[pRelay]
      return "NostrXT relay: the browser could not open the WebSocket (" & tReply & ")"
   end if
   put "nxrweb:" & char 4 to -1 of tReply into tSocketID
   put tSocketID into sNxrRelays[pRelay]["socketID"]
   put char 4 to -1 of tReply into sNxrRelays[pRelay]["web"]
   put "handshake" into sNxrRelays[pRelay]["state"]
   put pRelay into sNxrSockToRelay[tSocketID]
   send ("nxrDeadline " & pRelay) to me in kNxrHandshakeTimeout milliseconds
   nxrWebArm
   return pRelay
end nxrWebConnect

private command nxrWebArm
   -- One drain timer for every browser relay; a second arm is a no-op.
   if sNxrWebPolling is true then
      exit nxrWebArm
   end if
   put true into sNxrWebPolling
   send "nxrWebPoll" to me in kNxrWebPollMs milliseconds
end nxrWebArm

private function nxrWebSend pRelay, pText
   local tReply
   put nxrWebEval("window.oxtNxrWeb.send(" & sNxrRelays[pRelay]["web"] & ",'" & nxB64Encode(textEncode(pText, "UTF-8")) & "')") into tReply
   if tReply is "ok" then
      return empty
   end if
   if tReply begins with "error:" then
      return "NostrXT relay: the browser could not send:" && nxrWebDecode(char 7 to -1 of tReply)
   end if
   return "NostrXT relay: the browser's WebSocket for relay" && pRelay && "is gone"
end nxrWebSend

private command nxrWebClose pSocketID
   -- Idempotent: the page forgets the id on the first close.
   local tReply
   put nxrWebEval("window.oxtNxrWeb.close(" & char 8 to -1 of pSocketID & ")") into tReply
end nxrWebClose

/**
Summary: Delivers the events a web page's relay WebSockets have queued.

Example:
send "nxrWebPoll" to stack "nostr-relay" in 40 milliseconds

Description:
Used only in a web page, where each relay is the browser's WebSocket:
<nxrConnect> starts it, and it sends itself again while any browser relay
is live. It is public only so that the engine can send it; a script has
no reason to call it.

References: nxrConnect (handler)
*/
command nxrWebPoll
   -- Drain each browser relay's queue (up to kNxrWebPollBatch events a
   -- relay a pass), then re-arm while any browser relay is live. Every
   -- event re-reads the tables: a callback may have torn the relay down.
   local tSavedLineDelim, tKeys, tRelay, tCount, tEvent, tKind, tPayload, tColon, tLive
   put false into sNxrWebPolling
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   put the keys of sNxrRelays into tKeys
   set the lineDelimiter to tSavedLineDelim
   put false into tLive
   repeat for each line tRelay in tKeys
      repeat with tCount = 1 to kNxrWebPollBatch
         if sNxrRelays[tRelay]["web"] is empty then
            exit repeat
         end if
         put nxrWebEval("window.oxtNxrWeb.next(" & sNxrRelays[tRelay]["web"] & ")") into tEvent
         if tEvent is empty then
            exit repeat
         end if
         put offset(":", tEvent) into tColon
         if tColon is 0 then
            nxrFail tRelay, "the page's WebSocket helper answered" && tEvent
            exit repeat
         end if
         put char 1 to (tColon - 1) of tEvent into tKind
         put char (tColon + 1) to -1 of tEvent into tPayload
         nxrWebEvent tRelay, tKind, tPayload
      end repeat
      if sNxrRelays[tRelay]["web"] is not empty then
         put true into tLive
      end if
   end repeat
   if tLive then
      nxrWebArm
   end if
end nxrWebPoll

private command nxrWebEvent pRelay, pKind, pPayload
   local tMessage
   if pKind is "open" then
      if sNxrRelays[pRelay]["state"] is "handshake" then
         put "open" into sNxrRelays[pRelay]["state"]
         nxrDispatch pRelay, "open", empty, empty
      end if
   else if pKind is "message" then
      put base64Decode(pPayload) into tMessage
      if the number of bytes of tMessage > kNxrMaxBuffer then
         nxrFail pRelay, "a message exceeded" && kNxrMaxBuffer && "bytes"
         exit nxrWebEvent
      end if
      nxrHandleMessage pRelay, tMessage
   else if pKind is "error" then
      nxrFail pRelay, nxrWebDecode(pPayload)
   else if pKind is "close" then
      nxrTeardown pRelay, "the connection closed (" & nxrWebDecode(pPayload) & ")"
   else if pKind is "gone" then
      nxrTeardown pRelay, "the page's WebSocket is gone"
   end if
end nxrWebEvent

-- ==========================================================================
-- Teardown: idempotent, fail closed, own the lifecycle.
-- ==========================================================================

private command nxrSafeCloseSocket pSocketID
   -- Close only a socket the engine still lists (the onionxt idempotent-
   -- close shape; delimiter-guarded read of the openSockets).
   local tSavedLineDelim, tIsOpen
   if pSocketID begins with "nxrweb:" then
      nxrWebClose pSocketID
      exit nxrSafeCloseSocket
   end if
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

/**
Summary: Closes a relay connection.

pRelay: The relay handle.

Example:
nxrDisconnect tRelay

Description:
Sends a websocket close frame when the connection is open, then closes
the socket and forgets the handle. The callback receives "disconnected".
A handle that is not live is a no-op, so calling it twice is safe.

References: nxrConnect (handler), nxrShutdown (handler)
*/
command nxrDisconnect pRelay
   -- App-initiated close: send a close frame when the link is up, then
   -- tear down. Idempotent; a stale handle is a clean no-op.
   local tMask
   if sNxrRelays[pRelay]["socketID"] is empty then
      exit nxrDisconnect
   end if
   if sNxrRelays[pRelay]["state"] is "open" and sNxrRelays[pRelay]["web"] is empty then
      put nxrRandomHex(4) into tMask
      write nxWsFrameEncode(8, numToByte(3) & numToByte(232), tMask) to socket sNxrRelays[pRelay]["socketID"]
   end if
   -- (A browser WebSocket sends its own close frame: nxrSafeCloseSocket
   -- closes it with code 1000.)
   nxrTeardown pRelay, "disconnected by the app"
end nxrDisconnect

/**
Summary: Closes every relay connection.

Example:
nxrShutdown

Description:
Call it from closeStack: there is no automatic unload, so the app frees
what it opens. Safe to call more than once.

References: nxrDisconnect (handler), nxrOpenRelays (handler)
*/
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
/**
Summary: Handles a socketError message if it belongs to one of this library's relays.

pSocketID: The socket id from the socketError message.

pError: The error text from the socketError message.

Returns: "true" when the socket was a relay's and the error was handled, "false" otherwise.

Example:
if nxrSocketError(pSocketID, pError) then exit socketError
pass socketError

Description:
For a stack that embeds this library in its own script and so must
define socketError itself: call it from your handler where you would
otherwise pass the message on. For a relay socket, the relay fails
closed ("error" and "disconnected" callbacks). Ordinary apps that use
the library as a stack never call it.

References: nxrSocketClosed (handler), nxrSocketTimeout (handler)
*/
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
/**
Summary: Handles a socketClosed message if it belongs to one of this library's relays.

pSocketID: The socket id from the socketClosed message.

Returns: "true" when the socket was a relay's and the close was handled, "false" otherwise.

Example:
if nxrSocketClosed(pSocketID) then exit socketClosed
pass socketClosed

Description:
For a stack that embeds this library and defines socketClosed itself.
For a relay socket, the relay is torn down and the callback receives
"disconnected". Ordinary apps never call it.

References: nxrSocketError (handler), nxrSocketTimeout (handler)
*/
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
/**
Summary: Handles a socketTimeout message if it belongs to one of this library's relays.

pSocketID: The socket id from the socketTimeout message.

Returns: "true" when the socket was a relay's, "false" otherwise.

Example:
if nxrSocketTimeout(pSocketID) then exit socketTimeout
pass socketTimeout

Description:
For a stack that embeds this library and defines socketTimeout itself.
The engine repeats socketTimeout while a read waits, so a timeout fails
the relay only before its handshake completes; on an open relay an idle
read is normal and the message is simply consumed. Ordinary apps never
call it.

References: nxrSocketError (handler), nxrSocketClosed (handler)
*/
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
