-- onionxt-demo-standalone.livecodescript - the FULL OnionXT tabbed demo, ALL IN ONE
-- stack script: dial through Tor, host a page or share a folder over an onion (via
-- the bundled onion-httpd layer), the offline address tools, and the About-tab
-- self-test (the bundled onionxt-tests harness). Nothing else needs loading.
--
-- TO TEST: new mainstack -> Object menu -> Stack Script -> paste this whole file ->
-- Apply. Have a tor daemon with the control port enabled (see the OnionXT README
-- Troubleshooting); load sodiumxt too for the seed-derived onion / SAFECOOKIE paths.
-- Reopen the stack (so preOpenStack builds the UI), then Connect on the Status tab,
-- and use the Dial / Service / Address / About tabs. Open a published .onion in Tor
-- Browser (keep the demo running).
--
-- GENERATED - do not edit by hand. Regenerate with tools/build-standalone.py after
-- changing any source it concatenates (the sources of truth listed below). It joins
-- the OnionXT libraries and an example app into one script, so you can paste it
-- straight into a single mainstack's stack script with no "start using" wiring:
-- every ox* / oxh* / demo handler lives in the one script and self-builds the UI on
-- preOpenStack. (For a real project, prefer the libraries; this is paste-and-run.)



-- ========================================================================
-- ==== OnionXT library  (src/onionxt.livecodescript)
-- ========================================================================

-- onionxt.livecodescript - the OnionXT library.
--
-- OnionXT is a Tor transport and rendezvous layer for OpenXTalk / the xTalk
-- family. It speaks SOCKS5 (RFC 1928 + Tor extensions) and the Tor control
-- protocol to a LOCALLY-RUNNING tor daemon; it does not embed or ship Tor. It
-- adds no cryptography (SodiumXT does that) and, in this form, no native code:
-- the SOCKS5 and control clients are engine socket I/O, and base32 / the
-- ed25519 scalar clamp are pure byte manipulation.
--
-- STATUS: implemented AND run on a real OXT engine against a live tor daemon.
-- The core paths are confirmed on-engine: dialing through the SOCKS proxy, the
-- control-port connect + SAFECOOKIE auth, GETINFO / SETEVENTS, publishing a v3
-- onion service, accepting an inbound (Tor-forwarded) connection, streaming data
-- both ways, and bootstrap/HS_DESC events. The only path NOT yet exercised is the
-- optional Mode B (launching a bundled tor via `open process`), still flagged
-- "VERIFY:" below. The pure-compute paths are pinned by tools/onion-kat.py.
--
-- Conventions (see CLAUDE.md): public API oxPascalCase; locals t..., params
-- p..., script-locals s..., constants k...; SOCKS5 is BINARY (byte / numToByte /
-- byteToNum), the control protocol is CRLF text; every socket op is async
-- (open / read / accept with message) so the one interpreter thread never blocks
-- on the network; loopback (127.0.0.1) only; every open has an idempotent close;
-- every wire error fails closed and tears the resource down.
--
-- The async model (CLAUDE.md): oxDial and oxCreateService return a HANDLE
-- immediately and complete later; the app learns the outcome through the
-- callbacks below, never by a blocking return. The callback contracts are:
--   status callback  <handler> pKind, pInfo
--       pKind = "control"   pInfo = "connected"|"authenticated"|"disconnected"
--                                   |"authfailed: <reason>"|"error: <reason>"
--       pKind = "bootstrap" pInfo = 0..100          (coalesced to <= ~4 Hz)
--       pKind = "ready"     pInfo = empty           (bootstrap reached 100)
--       pKind = "service"   pInfo = <address>.onion (ADD_ONION returned it)
--       pKind = "serviceReady" pInfo = <address>    (descriptor uploaded)
--       pKind = "notice"    pInfo = <diagnostic>    (e.g. an accepted peer's raw id)
--       pKind = "event"     pInfo = <raw 650 line>  (advanced; opt-in noise)
--   stream callback  <handler> pStream, pEvent, pData
--       pEvent = "open"   the SOCKS tunnel (or inbound peer) is live
--       pEvent = "data"   pData is an inbound Data chunk (app frames its own)
--       pEvent = "closed" the peer closed the stream
--       pEvent = "error"  pData is the error; the stream has been torn down
--   peer callback    <handler> pStream, pService, pPeerAddr
--       a remote peer reached a published service; pStream is a fresh inbound
--       stream handle (register a stream callback on it), pService its service
--       handle, pPeerAddr the (loopback) peer address Tor forwarded from.
--
-- Callbacks are delivered with `dispatch` to the callback owner (oxSetCallbackOwner,
-- default the topStack); a missing handler is a clean no-op, so an app wires only
-- the callbacks it needs.

-- ==========================================================================
-- Constants. Loopback host is fixed; only the ports are configurable (and
-- loopback-locked). Declared before first use (OXT resolves a constant by
-- lexical position; a forward reference silently evaluates to nothing).
-- ==========================================================================

constant kOxHost = "127.0.0.1"
constant kOxSocksPortDefault = 9050
constant kOxControlPortDefault = 9051
constant kOxVersion = "1.0.0"

-- A bootstrapping daemon accepts the TCP connection then stalls; bound every
-- handshake so a silent stall becomes a clean error (docs/02 state machine).
constant kOxHandshakeTimeout = 20000     -- milliseconds
-- Coalesce bootstrap/status updates so a flood of 650 lines cannot thrash a
-- field (CLAUDE.md: <= ~4 Hz). 250 ms = 4 Hz.
constant kOxStatusThrottle = 250         -- milliseconds
-- RFC 4648 base32, lowercase, no padding (docs/04). Pure bytes, no crypto.
constant kOxBase32Alphabet = "abcdefghijklmnopqrstuvwxyz234567"
-- The v3 address checksum preimage prefix and version byte (docs/04). SHA3-256
-- of (kOxChecksumPrefix & pubkey & version) gives the 2-byte checksum; the hash
-- itself is a SodiumXT call, never hand-rolled here.
constant kOxChecksumPrefix = ".onion checksum"
-- The two SAFECOOKIE HMAC key strings, verbatim from the Tor control-spec.
constant kOxSafeCookieServerKey = "Tor safe cookie authentication server-to-controller hash"
constant kOxSafeCookieClientKey = "Tor safe cookie authentication controller-to-server hash"

-- ==========================================================================
-- Script-local state. Handle tables are LiveCode associative arrays keyed by a
-- small integer handle or by the engine's socket id; a stale or closed id must
-- be a clean no-op / error, never a crash.
-- ==========================================================================

-- Configurable ports (default to a system tor; Tor Browser uses 9150 / 9151).
local sSocksPort
local sControlPort

-- Control connection and bootstrap state (see docs/03-control-port.md).
local sControlSocket        -- engine id of the open control socket, or empty
local sControlState         -- disconnected|connecting|protocolinfo|authenticating|authenticated|failed
local sControlMethods       -- offered auth methods (comma list) from PROTOCOLINFO
local sControlCookieFile     -- cookie-file path from PROTOCOLINFO (unescaped)
local sControlPassword       -- app-set password for HASHEDPASSWORD auth
local sControlCookieBytes    -- the 32 raw cookie bytes (SAFECOOKIE flow)
local sControlClientNonce    -- our SAFECOOKIE client nonce (raw bytes)
local sControlTorVersion     -- tor version string from GETINFO version
local sBootstrap             -- 0..100 bootstrap percent from STATUS_CLIENT

-- Control command pipeline. One command in flight at a time so replies match
-- commands (docs/03); further commands queue. Reply lines accumulate until the
-- space-separated final line terminates the reply.
local sCtlInFlight           -- label of the in-flight command, or empty
local sCtlReplyLines         -- accumulated reply text (newline-joined)
local sCtlInData             -- true while inside a 250+ CmdData block
local sCtlData               -- accumulated CmdData block text
local sCtlQueue              -- pending commands: lines of "label" & TAB & "command"

-- App-registered callback handler names and the object they dispatch to.
local sStatusCallback
local sPeerCallback
local sCallbackOwner         -- long id of the object whose script has the callbacks
local sLastStatusTick        -- `the milliseconds` of the last coalesced update

-- Handle tables.
local sStreams               -- keyed by integer stream handle (nested array)
local sSockToStream          -- keyed by socket id string -> stream handle
local sServices              -- keyed by integer service handle (nested array)
local sLocalToService        -- keyed by local port -> service handle
local sNextHandle            -- monotonic handle allocator (0 is never valid)

-- ==========================================================================
-- Configuration.
-- ==========================================================================

command oxSetSocksPort pPort
   -- Loopback-locked: only the port is settable, never the host (CLAUDE.md
   -- socket gotcha 6). Take effect on the next oxDial.
   put pPort into sSocksPort
end oxSetSocksPort

command oxSetControlPort pPort
   put pPort into sControlPort
end oxSetControlPort

command oxSetControlPassword pPassword
   -- Only used if the daemon offers HASHEDPASSWORD auth (docs/03 step 2).
   put pPassword into sControlPassword
end oxSetControlPassword

command oxSetCallbackOwner pObjectLongId
   -- The object whose script holds the app callbacks. If unset, callbacks
   -- dispatch to the topStack; setting this explicitly (as the demo does) removes
   -- any ambiguity about which stack. Confirmed on-engine: with an explicit owner,
   -- onStatus / onPeer / onStreamData all resolve and fire.
   put pObjectLongId into sCallbackOwner
end oxSetCallbackOwner

command oxSetStatusCallback pHandlerName
   put pHandlerName into sStatusCallback
end oxSetStatusCallback

command oxSetPeerCallback pHandlerName
   put pHandlerName into sPeerCallback
end oxSetPeerCallback

function oxVersion
   -- The library version, plus the tor version once the control connection has
   -- answered GETINFO version (docs/05).
   if sControlTorVersion is empty then
      return kOxVersion
   end if
   return kOxVersion & " (tor " & sControlTorVersion & ")"
end oxVersion

-- ==========================================================================
-- Control connection, authentication, and the command pipeline
-- (docs/03-control-port.md). The connection is opened and authenticated
-- asynchronously; the app learns the outcome through the status callback.
-- ==========================================================================

command oxConnectControl
   -- Idempotent-ish: refuse a second concurrent connect rather than leak a
   -- socket. Disconnect first to reconnect.
   if sControlSocket is not empty then
      return "OnionXT: control connection already open (oxDisconnectControl first)"
   end if
   local tSocketID
   -- A named connection (|oxctl) so the id is stable and distinct from streams.
   put kOxHost & ":" & effectiveControlPort() & "|oxctl" into tSocketID
   put tSocketID into sControlSocket
   put "connecting" into sControlState
   put empty into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlQueue
   -- Bound the connect/handshake so a stalled daemon fails cleanly.
   set the socketTimeoutInterval to kOxHandshakeTimeout
   open socket to tSocketID with message "oxCtlOpened"
   -- A watchdog independent of the (repeating) socketTimeout: if we are not
   -- authenticated within the deadline, tear the connection down.
   send ("oxCtlDeadline " & quote & tSocketID & quote) to me in kOxHandshakeTimeout milliseconds
   return empty
end oxConnectControl

command oxDisconnectControl
   -- Idempotent close of the control socket and reset of all control state.
   if sControlSocket is not empty then
      oxSafeCloseSocket sControlSocket
   end if
   put empty into sControlSocket
   put "disconnected" into sControlState
   put empty into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlQueue
   put empty into sControlCookieBytes
   put empty into sControlClientNonce
end oxDisconnectControl

function oxIsControlAuthenticated
   return (sControlState is "authenticated")
end oxIsControlAuthenticated

function oxBootstrapProgress
   if sBootstrap is empty then
      return 0
   end if
   return sBootstrap
end oxBootstrapProgress

function oxIsReady
   -- Ready to carry traffic once bootstrapped to 100 and the control port is
   -- authenticated. A published service's own reachability is reported
   -- separately via the "serviceReady" status (HS_DESC UPLOADED).
   return (sBootstrap is 100) and (sControlState is "authenticated")
end oxIsReady

command oxCtlOpened pSocketID
   -- The control TCP connection is up. Start the single persistent line reader
   -- and kick the auth dance with PROTOCOLINFO (allowed pre-auth).
   if pSocketID is not sControlSocket then
      exit oxCtlOpened          -- a stale socket; ignore
   end if
   put "protocolinfo" into sControlState
   oxStatusUpdate "control", "connected"
   -- One outstanding CRLF read at a time; re-armed at the end of oxCtlLine.
   read from socket pSocketID until crlf with message "oxCtlLine"
   oxCtlSend "PROTOCOLINFO 1", "protocolinfo"
end oxCtlOpened

private command oxCtlSend pCommand, pLabel
   -- Send a control command, or queue it if one is already in flight so replies
   -- always match commands (docs/03: keep a single in-flight command queue).
   if sControlSocket is empty then
      exit oxCtlSend
   end if
   if sCtlInFlight is not empty then
      put pLabel & tab & pCommand & return after sCtlQueue
      exit oxCtlSend
   end if
   put pLabel into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlData
   -- Commands are ASCII text; textEncode gives the exact wire bytes, then the
   -- CRLF terminator (docs/03 line framing).
   write textEncode(pCommand & oxCrlf(), "UTF-8") to socket sControlSocket
end oxCtlSend

private command oxCtlDrainQueue
   -- Send the next queued command, if any. Called when a reply completes.
   if sCtlQueue is empty then
      exit oxCtlDrainQueue
   end if
   local tLine, tLabel, tCommand, tSaved
   put line 1 of sCtlQueue into tLine
   delete line 1 of sCtlQueue
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put item 1 of tLine into tLabel
   put item 2 to -1 of tLine into tCommand
   set the itemDelimiter to tSaved
   oxCtlSend tCommand, tLabel
end oxCtlDrainQueue

command oxCtlLine pSocketID, pData
   -- The persistent control-port line reader. Demultiplexes unsolicited 650
   -- events from command replies, reassembles multi-line replies, and honours
   -- the 250-/250+/'.'/250 space framing (docs/03).
   if pSocketID is not sControlSocket then
      exit oxCtlLine            -- a stale socket; ignore
   end if
   local tLine
   -- Control replies are ASCII; decode as text, then strip the line terminator.
   -- Confirmed on-engine: `read until crlf` returns the trailing CRLF and
   -- oxStripLineEnd removes it, so auth / GETINFO / events all parse correctly.
   put textDecode(pData, "UTF-8") into tLine
   put oxStripLineEnd(tLine) into tLine

   if sCtlInData then
      -- Inside a 250+ CmdData block: a lone "." ends it; other lines are data
      -- with any doubled leading dot un-stuffed (docs/03, RFC 2821 dot-stuffing).
      if tLine is "." then
         put false into sCtlInData
      else
         if char 1 to 2 of tLine is ".." then
            delete char 1 of tLine
         end if
         put tLine & return after sCtlData
      end if
      oxCtlRearm pSocketID
      exit oxCtlLine
   end if

   if the length of tLine < 3 then
      oxCtlRearm pSocketID      -- malformed / empty; skip
      exit oxCtlLine
   end if

   local tCode, tSep
   put char 1 to 3 of tLine into tCode
   put char 4 of tLine into tSep

   if tCode is "650" then
      -- An asynchronous event. Route it to the event handler, never to the
      -- pending-command continuation.
      oxHandleEvent tLine
      oxCtlRearm pSocketID
      exit oxCtlLine
   end if

   -- A command-reply line. Accumulate it and act on the frame control byte.
   put tLine & return after sCtlReplyLines
   if tSep is "+" then
      put true into sCtlInData
   else if tSep is space or tSep is empty then
      -- Space (or a 3-char line) terminates the reply.
      oxCtlReplyComplete
      put empty into sCtlInFlight
      put empty into sCtlReplyLines
      oxCtlDrainQueue
   end if
   -- "-" continuation: just keep reading.
   oxCtlRearm pSocketID
end oxCtlLine

private command oxCtlRearm pSocketID
   -- Keep exactly one read outstanding, but only while the socket is still ours.
   if pSocketID is sControlSocket then
      read from socket pSocketID until crlf with message "oxCtlLine"
   end if
end oxCtlRearm

private command oxCtlReplyComplete
   -- Dispatch the just-completed reply to the continuation for the in-flight
   -- command. if/else-if, not switch (the static gate rejects `end switch`).
   -- tReplyOp, NOT tOp: a t-prefixed "tOp" lowercases to `top`, a reserved OXT
   -- property, and the engine would parse it as the keyword, not this variable
   -- (the prefixed-token-shadow trap, CLAUDE.md gotcha 2).
   local tLabel, tReplyOp, tArg, tSaved
   put sCtlInFlight into tLabel
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   put item 1 of tLabel into tReplyOp
   put item 2 to -1 of tLabel into tArg
   set the itemDelimiter to tSaved

   if tReplyOp is "protocolinfo" then
      oxParseProtocolInfo sCtlReplyLines
      oxChooseAuthAndStart
   else if tReplyOp is "authchallenge" then
      oxHandleAuthChallenge sCtlReplyLines
   else if tReplyOp is "authenticate" then
      oxHandleAuthResult sCtlReplyLines
   else if tReplyOp is "setevents" then
      -- 250 OK expected; nothing to do on success.
   else if tReplyOp is "getinfo-version" then
      oxParseTorVersion sCtlReplyLines
   else if tReplyOp is "getinfo-bootstrap" then
      oxParseBootstrapPhase sCtlReplyLines
   else if tReplyOp is "add_onion" then
      oxHandleAddOnionReply tArg, sCtlReplyLines
   else if tReplyOp is "del_onion" then
      -- 250 OK on success, 552 if unknown; the removal already forgot local
      -- state, so nothing further is required here.
   end if
end oxCtlReplyComplete

private command oxParseProtocolInfo pReply
   -- Extract the offered auth methods and (for cookie auth) the cookie-file path
   -- from the PROTOCOLINFO reply (docs/03 step 1).
   put empty into sControlMethods
   put empty into sControlCookieFile
   local tLine
   repeat for each line tLine in pReply
      if "AUTH METHODS=" is in tLine then
         -- METHODS=<comma list> [COOKIEFILE="<quoted, C-escaped path>"]
         put oxFieldAfter(tLine, "METHODS=") into sControlMethods
         if "COOKIEFILE=" is in tLine then
            put oxCUnescape(oxQuotedValueAfter(tLine, "COOKIEFILE=")) into sControlCookieFile
         end if
      end if
   end repeat
end oxParseProtocolInfo

private command oxChooseAuthAndStart
   -- Priority SAFECOOKIE > COOKIE > NULL > HASHEDPASSWORD (docs/03), but degrade
   -- past any method whose prerequisite is missing rather than fail: SAFECOOKIE
   -- needs SodiumXT HMAC-SHA256 and randomness (docs/08), COOKIE needs the
   -- readable cookie file, HASHEDPASSWORD needs an app-set password.
   put "authenticating" into sControlState

   if oxMethodOffered("SAFECOOKIE") and oxSodiumHasHmac() and oxSodiumHasRandom() then
      if oxLoadCookie() then
         oxStartSafeCookie
         exit oxChooseAuthAndStart
      end if
   end if
   if oxMethodOffered("COOKIE") then
      if oxLoadCookie() then
         local tHex
         put oxBytesToHex(sControlCookieBytes) into tHex
         oxCtlSend "AUTHENTICATE " & tHex, "authenticate"
         exit oxChooseAuthAndStart
      end if
   end if
   if oxMethodOffered("NULL") then
      oxCtlSend "AUTHENTICATE", "authenticate"
      exit oxChooseAuthAndStart
   end if
   if oxMethodOffered("HASHEDPASSWORD") and sControlPassword is not empty then
      -- Quote the password; escape backslash and double-quote (docs/03).
      oxCtlSend "AUTHENTICATE " & quote & oxQuoteEscape(sControlPassword) & quote, "authenticate"
      exit oxChooseAuthAndStart
   end if

   put "failed" into sControlState
   oxStatusUpdate "control", "authfailed: no usable auth method (offered " & sControlMethods & ")"
   oxDisconnectControl
end oxChooseAuthAndStart

private command oxStartSafeCookie
   -- SAFECOOKIE step A: send a 32-byte client nonce as hex (docs/03 step 2).
   put oxRandomBytes(32) into sControlClientNonce
   oxCtlSend "AUTHCHALLENGE SAFECOOKIE " & oxBytesToHex(sControlClientNonce), "authchallenge"
end oxStartSafeCookie

private command oxHandleAuthChallenge pReply
   -- SAFECOOKIE step B/C/D. The reply is a SINGLE final line:
   -- 250 AUTHCHALLENGE SERVERHASH=<hex> SERVERNONCE=<hex> (docs/03; the reply is
   -- space-separated, not a 250- continuation).
   local tLine, tServerHashHex, tServerNonceHex
   put line 1 of pReply into tLine
   if char 1 to 3 of tLine is not "250" then
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: AUTHCHALLENGE rejected (" & tLine & ")"
      oxDisconnectControl
      exit oxHandleAuthChallenge
   end if
   put oxFieldAfter(tLine, "SERVERHASH=") into tServerHashHex
   put oxFieldAfter(tLine, "SERVERNONCE=") into tServerNonceHex

   local tServerNonce, tMessage, tExpected, tOk
   put oxHexToBytes(tServerNonceHex) into tServerNonce
   -- HMAC message = CookieBytes || ClientNonce || ServerNonce (docs/03).
   put sControlCookieBytes & sControlClientNonce & tServerNonce into tMessage
   put oxHmac(kOxSafeCookieServerKey, tMessage) into tExpected
   -- Verify the server hash in constant time; a mismatch means the far end does
   -- not hold the cookie (not the real Tor), so abort and do NOT authenticate.
   put oxConstantTimeEqual(tExpected, oxHexToBytes(tServerHashHex)) into tOk
   if not tOk then
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: SAFECOOKIE server hash mismatch (not the real Tor?)"
      oxDisconnectControl
      exit oxHandleAuthChallenge
   end if
   -- Step D: authenticate with the controller-to-server hash.
   local tClientHash
   put oxHmac(kOxSafeCookieClientKey, tMessage) into tClientHash
   oxCtlSend "AUTHENTICATE " & oxBytesToHex(tClientHash), "authenticate"
end oxHandleAuthChallenge

private command oxHandleAuthResult pReply
   -- 250 OK => authenticated; anything else (515 bad auth, 514 required) fails
   -- closed (docs/03; there is no unauthenticated fallback, CLAUDE.md rule 4).
   local tLine
   put line 1 of pReply into tLine
   if char 1 to 3 of tLine is "250" then
      put "authenticated" into sControlState
      oxStatusUpdate "control", "authenticated"
      -- Subscribe to the events we care about and learn the tor version.
      oxCtlSend "SETEVENTS STATUS_CLIENT HS_DESC CIRC STREAM", "setevents"
      oxCtlSend "GETINFO version", "getinfo-version"
      -- Query the CURRENT bootstrap phase once. STATUS_CLIENT BOOTSTRAP events
      -- only fire WHILE tor is bootstrapping, so a daemon already at 100% when we
      -- connect emits none and the UI would sit at 0. This one GETINFO seeds it.
      oxCtlSend "GETINFO status/bootstrap-phase", "getinfo-bootstrap"
   else
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: " & tLine
      oxDisconnectControl
   end if
end oxHandleAuthResult

private command oxParseTorVersion pReply
   -- 250-version=<x> then 250 OK (docs/03). Pull the version value.
   local tLine
   repeat for each line tLine in pReply
      if "version=" is in tLine then
         put oxFieldAfter(tLine, "version=") into sControlTorVersion
      end if
   end repeat
end oxParseTorVersion

private command oxParseBootstrapPhase pReply
   -- Reply to GETINFO status/bootstrap-phase, carrying the CURRENT bootstrap state
   -- (unlike the STATUS_CLIENT event, which only fires while bootstrapping). Line:
   --   250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=100 TAG=done SUMMARY="..."
   -- Parse PROGRESS= the same way as the live event so the UI is seeded on connect.
   local tLine, tProgress
   repeat for each line tLine in pReply
      if "PROGRESS=" is in tLine then
         put oxFieldAfter(tLine, "PROGRESS=") into tProgress
         if tProgress is not empty and tProgress is an integer then
            put tProgress into sBootstrap
            oxStatusUpdate "bootstrap", tProgress
            if tProgress is 100 then
               oxStatusUpdate "ready", empty
            end if
         end if
      end if
   end repeat
end oxParseBootstrapPhase

command oxCtlDeadline pSocketID
   -- Handshake watchdog: if this control socket never reached authenticated,
   -- tear it down with a clean error (docs/07: a stalled bootstrap must not hang).
   if pSocketID is not sControlSocket then
      exit oxCtlDeadline
   end if
   if sControlState is not "authenticated" then
      oxStatusUpdate "control", "error: control authentication timed out"
      oxDisconnectControl
   end if
end oxCtlDeadline

-- ==========================================================================
-- Event handling: bootstrap progress and onion-descriptor readiness
-- (docs/03 step 5). 650 lines are tolerant-parsed; never hard-fail on an
-- unrecognized token (the control-spec requires controllers to tolerate them).
-- ==========================================================================

private command oxHandleEvent pLine
   local tType
   put word 2 of pLine into tType
   if tType is "STATUS_CLIENT" then
      if "BOOTSTRAP" is in pLine then
         local tProgress
         put oxFieldAfter(pLine, "PROGRESS=") into tProgress
         if tProgress is not empty and tProgress is an integer then
            put tProgress into sBootstrap
            oxStatusUpdate "bootstrap", tProgress
            if tProgress is 100 then
               oxStatusUpdate "ready", empty
            end if
         end if
      end if
   else if tType is "HS_DESC" then
      -- Positional: HS_DESC <Action> <HSAddress> ... . Our service is reachable
      -- once we see UPLOADED for its address (docs/03 step 5).
      local tAction, tAddress
      put word 3 of pLine into tAction
      put word 4 of pLine into tAddress
      if tAction is "UPLOADED" then
         oxMarkServiceReady tAddress
         oxStatusUpdate "serviceReady", tAddress
      end if
   else
      -- CIRC / STREAM and anything else are diagnostic; surface raw for advanced
      -- apps that opted into an "event" status, otherwise ignored.
      oxStatusUpdate "event", pLine
   end if
end oxHandleEvent

private command oxMarkServiceReady pAddress
   local tKey, tCore
   -- The event carries the ServiceID (no ".onion"); match either spelling.
   put pAddress into tCore
   if tCore ends with ".onion" then
      put char 1 to -7 of tCore into tCore
   end if
   repeat for each key tKey in sServices
      if sServices[tKey]["serviceID"] is tCore then
         put true into sServices[tKey]["ready"]
      end if
   end repeat
end oxMarkServiceReady

private command oxStatusUpdate pKind, pInfo
   -- Deliver a status update to the app, coalescing the high-frequency bootstrap
   -- stream to <= ~4 Hz (CLAUDE.md). Terminal/rare kinds are always delivered.
   if pKind is "bootstrap" and pInfo is not 100 then
      local tNow
      put the milliseconds into tNow
      if sLastStatusTick is not empty and (tNow - sLastStatusTick) < kOxStatusThrottle then
         exit oxStatusUpdate   -- coalesce: drop this intermediate tick
      end if
      put tNow into sLastStatusTick
   end if
   oxDispatch sStatusCallback, pKind, pInfo, empty
end oxStatusUpdate

-- ==========================================================================
-- Outbound: dialing through SOCKS5 (docs/02-socks5-client.md). A callback-driven
-- state machine: greet, CONNECT with ATYP=3 (Tor resolves the name; never a
-- local DNS lookup), parse the reply, hand up a raw byte-stream tunnel.
-- ==========================================================================

command oxDial pHost, pPort
   -- Reports a stream handle through `the result` immediately; the SOCKS
   -- handshake completes asynchronously and the stream's callback receives
   -- "open" or "error" (CLAUDE.md async model).
   if pHost is empty then
      return "OnionXT: oxDial needs a host (a .onion or clearnet name)"
   end if
   if pPort is not an integer or pPort < 1 or pPort > 65535 then
      return "OnionXT: oxDial needs a port in 1..65535"
   end if
   local tHandle, tConnName, tSocketID
   put oxAllocHandle() into tHandle
   -- A NON-numeric connection name so several streams to 127.0.0.1:9050 get
   -- distinct socket ids, and so they never collide with the numeric names the
   -- accept loop assigns (the id separator is a vertical bar, docs LiveCode ref).
   put "oxs" & tHandle into tConnName
   put kOxHost & ":" & effectiveSocksPort() & "|" & tConnName into tSocketID
   put tSocketID into sStreams[tHandle]["socketID"]
   put "connecting" into sStreams[tHandle]["state"]
   put pHost into sStreams[tHandle]["host"]
   put pPort into sStreams[tHandle]["port"]
   put "dial" into sStreams[tHandle]["kind"]
   put empty into sStreams[tHandle]["callback"]
   put tHandle into sSockToStream[tSocketID]
   set the socketTimeoutInterval to kOxHandshakeTimeout
   open socket to tSocketID with message "oxSocksOpened"
   send ("oxStreamDeadline " & tHandle) to me in kOxHandshakeTimeout milliseconds
   return tHandle
end oxDial

command oxSetStreamCallback pStream, pHandlerName
   if sStreams[pStream]["socketID"] is empty then
      return "OnionXT: unknown stream handle " & pStream
   end if
   put pHandlerName into sStreams[pStream]["callback"]
   return empty
end oxSetStreamCallback

command oxWrite pStream, pData
   -- Write app bytes (already sealed by the app via SodiumXT) to the
   -- tunnel. OnionXT does not encrypt (docs/02).
   if sStreams[pStream]["state"] is not "connected" then
      return "OnionXT: stream " & pStream & " is not open"
   end if
   write pData to socket sStreams[pStream]["socketID"]
   return empty
end oxWrite

command oxCloseStream pStream
   -- Idempotent close of the stream socket; forget the handle. A stale handle is
   -- a clean no-op.
   if sStreams[pStream]["socketID"] is empty then
      exit oxCloseStream
   end if
   oxSafeCloseSocket sStreams[pStream]["socketID"]
   delete variable sSockToStream[sStreams[pStream]["socketID"]]
   delete variable sStreams[pStream]
end oxCloseStream

function oxStreamState pStream
   if sStreams[pStream]["socketID"] is empty then
      return "unknown"
   end if
   return sStreams[pStream]["state"]
end oxStreamState

command oxSocksOpened pSocketID
   -- TCP up: send the method-negotiation greeting 05 01 00 (VER=5, 1 method,
   -- method 00 = no auth) and read the 2-byte method selection (docs/02 step 1).
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksOpened        -- stale
   end if
   put "greeting" into sStreams[tHandle]["state"]
   write numToByte(5) & numToByte(1) & numToByte(0) to socket pSocketID
   read from socket pSocketID for 2 with message "oxSocksMethod"
end oxSocksOpened

command oxSocksMethod pSocketID, pData
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksMethod
   end if
   if the number of bytes of pData < 2 then
      oxStreamFail tHandle, "SOCKS greeting reply truncated"
      exit oxSocksMethod
   end if
   local tVer, tMethod
   put byteToNum(byte 1 of pData) into tVer
   put byteToNum(byte 2 of pData) into tMethod
   if tVer is not 5 then
      oxStreamFail tHandle, "SOCKS server is not version 5"
      exit oxSocksMethod
   end if
   if tMethod is not 0 then
      -- 0xFF = no acceptable methods; anything non-zero we do not offer. Fail
      -- closed; on loopback no auth is needed and its absence is a misconfig to
      -- surface, not paper over (docs/02).
      oxStreamFail tHandle, "SOCKS server demands an auth method OnionXT does not offer (0x" & oxByteHex(tMethod) & ")"
      exit oxSocksMethod
   end if
   -- Method OK: send the CONNECT request with ATYP=3 (domain name) so TOR
   -- resolves pHost. This is the anonymity-critical choice (docs/02 step 2).
   put "connect" into sStreams[tHandle]["state"]
   local tHost, tHostBytes, tPort, tRequest
   put sStreams[tHandle]["host"] into tHost
   put textEncode(tHost, "UTF-8") into tHostBytes
   if the number of bytes of tHostBytes > 255 then
      oxStreamFail tHandle, "SOCKS host name exceeds 255 bytes"
      exit oxSocksMethod
   end if
   put sStreams[tHandle]["port"] into tPort
   -- 05 01 00 03 <len> <host bytes> <port-hi> <port-lo>. The port is 2 bytes
   -- big-endian; build it by hand so the wire bytes are self-evident (do not use
   -- binaryEncode "S", which is host order, docs LiveCode ref).
   put numToByte(5) & numToByte(1) & numToByte(0) & numToByte(3) into tRequest
   put numToByte(the number of bytes of tHostBytes) after tRequest
   put tHostBytes after tRequest
   put numToByte(tPort div 256) & numToByte(tPort mod 256) after tRequest
   write tRequest to socket pSocketID
   -- Read the fixed 4-byte reply head (VER REP RSV ATYP); the BND.ADDR that
   -- follows is variable and framed by ATYP (docs/02 step 3).
   put "replyhead" into sStreams[tHandle]["state"]
   read from socket pSocketID for 4 with message "oxSocksReplyHead"
end oxSocksMethod

command oxSocksReplyHead pSocketID, pData
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyHead
   end if
   if the number of bytes of pData < 4 then
      oxStreamFail tHandle, "SOCKS reply head truncated"
      exit oxSocksReplyHead
   end if
   local tVer, tRep, tAtyp
   put byteToNum(byte 1 of pData) into tVer
   put byteToNum(byte 2 of pData) into tRep
   put byteToNum(byte 4 of pData) into tAtyp
   if tRep is not 0 then
      -- Any non-zero REP is failure. Map it (incl. Tor's onion 0xF0..0xF7) to a
      -- human message and tear down (docs/02 REP table; CLAUDE.md rule 4).
      oxStreamFail tHandle, oxSocksRepMessage(tRep)
      exit oxSocksReplyHead
   end if
   put tAtyp into sStreams[tHandle]["atyp"]
   -- Consume BND.ADDR + 2-byte BND.PORT. Length depends on ATYP: 01 -> 4, 04 ->
   -- 16, 03 -> one length byte then that many. We do not use BND.ADDR; we just
   -- frame past it so the socket is left at the start of the tunnel payload.
   if tAtyp is 1 then
      put "replyrest" into sStreams[tHandle]["state"]
      read from socket pSocketID for 6 with message "oxSocksReplyDone"     -- 4 + 2
   else if tAtyp is 4 then
      put "replyrest" into sStreams[tHandle]["state"]
      read from socket pSocketID for 18 with message "oxSocksReplyDone"    -- 16 + 2
   else if tAtyp is 3 then
      put "replylen" into sStreams[tHandle]["state"]
      read from socket pSocketID for 1 with message "oxSocksReplyLen"
   else
      oxStreamFail tHandle, "SOCKS reply has an unknown address type (" & tAtyp & ")"
   end if
end oxSocksReplyHead

command oxSocksReplyLen pSocketID, pData
   -- ATYP=3 domain BND.ADDR: one length byte, then that many, then 2 port bytes.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyLen
   end if
   if the number of bytes of pData < 1 then
      oxStreamFail tHandle, "SOCKS reply address length truncated"
      exit oxSocksReplyLen
   end if
   local tLen
   put byteToNum(byte 1 of pData) + 2 into tLen     -- address bytes + 2 port bytes
   put "replyrest" into sStreams[tHandle]["state"]
   read from socket pSocketID for tLen with message "oxSocksReplyDone"
end oxSocksReplyLen

command oxSocksReplyDone pSocketID, pData
   -- The SOCKS reply is fully consumed and REP was 0: the socket is now a
   -- transparent tunnel. Hand it up and start the streaming inbound reader.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyDone
   end if
   put "connected" into sStreams[tHandle]["state"]
   oxInvokeStreamCallback tHandle, "open", empty
   -- Begin the persistent read; each inbound chunk is delivered as "data".
   -- Confirmed on-engine: the no-quantifier `read ... with message` streams
   -- available bytes as they arrive (a dialed SOCKS tunnel and an inbound onion
   -- HTTP request both deliver chunk by chunk); it does not block to EOF.
   read from socket pSocketID with message "oxStreamData"
end oxSocksReplyDone

command oxStreamData pSocketID, pData
   -- Inbound bytes on a live stream (dialed OR inbound-accepted; both are unified
   -- through the stream tables). Deliver the chunk and re-arm the read.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxStreamData          -- stale / already torn down
   end if
   if the number of bytes of pData > 0 then
      oxInvokeStreamCallback tHandle, "data", pData
   end if
   -- Re-arm only if the stream is still live (the callback may have closed it).
   if sSockToStream[pSocketID] is not empty then
      read from socket pSocketID with message "oxStreamData"
   end if
end oxStreamData

command oxStreamDeadline pStream
   -- Handshake watchdog for a dialed stream: if it never reached "connected",
   -- tear it down (docs/02: a silent stall is the worst failure).
   if sStreams[pStream]["socketID"] is empty then
      exit oxStreamDeadline
   end if
   local tState
   put sStreams[pStream]["state"] into tState
   if tState is not "connected" and tState is not "closed" then
      oxStreamFail pStream, "SOCKS handshake timed out"
   end if
end oxStreamDeadline

private command oxStreamFail pStream, pError
   -- Fail closed: report the error to the app, then close and forget the stream.
   if sStreams[pStream]["socketID"] is empty then
      exit oxStreamFail
   end if
   put "failed" into sStreams[pStream]["state"]
   oxInvokeStreamCallback pStream, "error", pError
   oxSafeCloseSocket sStreams[pStream]["socketID"]
   delete variable sSockToStream[sStreams[pStream]["socketID"]]
   delete variable sStreams[pStream]
end oxStreamFail

private function oxSocksRepMessage pRep
   -- Map a SOCKS REP code to a clear message. Standard RFC 1928 0x00..0x08 plus
   -- Tor's onion extensions 0xF0..0xF7 (docs/02; the extended band only appears
   -- when the SocksPort has ExtendedErrors set, so 0x01/0x04 must map sensibly
   -- too, since without that flag Tor collapses onion failures onto them).
   if pRep is 1 then
      return "general SOCKS server failure"
   else if pRep is 2 then
      return "connection not allowed by ruleset"
   else if pRep is 3 then
      return "network unreachable"
   else if pRep is 4 then
      return "host unreachable"
   else if pRep is 5 then
      return "connection refused"
   else if pRep is 6 then
      return "TTL expired"
   else if pRep is 7 then
      return "command not supported"
   else if pRep is 8 then
      return "address type not supported"
   else if pRep is 240 then
      return "onion service not found (wrong or offline .onion address)"
   else if pRep is 241 then
      return "onion service descriptor is invalid"
   else if pRep is 242 then
      return "onion service introduction failed"
   else if pRep is 243 then
      return "onion service rendezvous failed"
   else if pRep is 244 then
      return "onion service missing client authorization"
   else if pRep is 245 then
      return "onion service wrong client authorization"
   else if pRep is 246 then
      return "onion service invalid address (malformed .onion)"
   else if pRep is 247 then
      return "onion service introduction timed out"
   end if
   return "SOCKS request failed (REP 0x" & oxByteHex(pRep) & ")"
end oxSocksRepMessage

-- ==========================================================================
-- Inbound: onion services (docs/03 step 3-4, docs/04). Listen on loopback
-- FIRST, then ADD_ONION, so a peer that connects the moment the descriptor
-- publishes is answered (CLAUDE.md socket gotcha 5).
-- ==========================================================================

command oxCreateService pVirtualPort, pLocalPort
   -- Ephemeral service, Tor generates the key. Reports a service handle through
   -- `the result`; the .onion address arrives asynchronously (status "service"
   -- and oxServiceAddress) once ADD_ONION replies.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   local tHandle
   put oxStartService(pVirtualPort, pLocalPort) into tHandle
   if tHandle is not an integer then
      return tHandle          -- listener did not bind; surfaced verbatim
   end if
   -- Flags=Detach keeps the service published even if the control connection
   -- drops (a transient socketClosed/socketError, or a reconnect): without it, an
   -- ADD_ONION service dies with its control connection while its descriptor
   -- lingers in the DHT for ~3h, so a later visit hits "unable to find hidden
   -- service identity key" at rendezvous. oxRemoveService / oxShutdown DEL_ONION
   -- it explicitly; a hard crash leaves it until DEL_ONION or a tor restart.
   oxCtlSend "ADD_ONION NEW:ED25519-V3 Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxCreateService

command oxCreateServiceFromSeed pSeed, pVirtualPort, pLocalPort
   -- Deterministic, reproducible address: derive the ed25519 identity from pSeed
   -- and pass Tor the 64-byte ED25519-V3 expanded key (docs/04). The expansion is
   -- SodiumXT's sxSignSeedToExpandedKey (docs/08 gap #1, SHIPPED in ABI 6); we
   -- compose it and fail with a clear message if it is absent, never hand-roll
   -- SHA-512. Same seed -> same .onion on every run.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   if the number of bytes of pSeed is not 32 then
      return "OnionXT: oxCreateServiceFromSeed needs a 32-byte seed"
   end if
   local tExpanded
   put oxExpandedKeyFromSeed(pSeed) into tExpanded
   if the number of bytes of tExpanded is not 64 then
      return tExpanded          -- a capability error, surfaced verbatim
   end if
   -- Tor's ADD_ONION ED25519-V3: wants STANDARD RFC 4648 base64 (the +/ alphabet
   -- with = padding). The engine's base64Encode emits exactly that; do NOT use
   -- SodiumXT's sxBin2Base64, which is url-safe and unpadded and tor rejects.
   -- Strip any line-wrap whitespace the encoder may insert (docs/04 base64 note).
   local tBlob
   put oxStripWhitespace(base64Encode(tExpanded)) into tBlob
   local tHandle
   put oxStartService(pVirtualPort, pLocalPort) into tHandle
   if tHandle is not an integer then
      return tHandle          -- listener did not bind; surfaced verbatim
   end if
   -- Flags=Detach: keep the service alive across a control-connection drop (see
   -- oxCreateService); DEL_ONION on teardown still removes it.
   oxCtlSend "ADD_ONION ED25519-V3:" & tBlob & " Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxCreateServiceFromSeed

command oxPublishService pVirtualPort, pLocalPort
   -- Publish an onion whose virtual port Tor forwards to a loopback port that
   -- SOMETHING ELSE is already accepting on (LiveCode's built-in HTTPD Library, or
   -- any local server). Unlike oxCreateService, OnionXT does NOT start its own
   -- accept loop: the external server owns the socket, parses the request, and
   -- replies. Teardown DEL_ONIONs the service but leaves that socket alone. Reports
   -- a service handle through `the result`; the .onion address arrives
   -- asynchronously (status "service", oxServiceAddress) once ADD_ONION replies.
   --
   -- SECURITY (the caller's responsibility): `accept connections on port` usually
   -- binds ALL interfaces, so the external server's local port may be reachable
   -- from the LAN, bypassing Tor. The external server MUST enforce loopback itself
   -- (reject any non-127.0.0.1 peer before responding), exactly as OnionXT's own
   -- oxPeerAccepted does. Bind the server to loopback if it supports it.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   local tHandle
   put oxAllocHandle() into tHandle
   put pVirtualPort into sServices[tHandle]["virtualPort"]
   put pLocalPort into sServices[tHandle]["localPort"]
   put empty into sServices[tHandle]["serviceID"]
   put empty into sServices[tHandle]["address"]
   put empty into sServices[tHandle]["privateKey"]
   put false into sServices[tHandle]["ready"]
   -- Mark it external so oxRemoveService DEL_ONIONs it but does not close the
   -- socket (which OnionXT never opened; the external server owns it).
   put true into sServices[tHandle]["external"]
   -- No accept loop here (contrast oxStartService). Flags=Detach as in
   -- oxCreateService, so a control-connection blip does not un-publish it.
   oxCtlSend "ADD_ONION NEW:ED25519-V3 Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxPublishService

private function oxCheckServiceArgs pVirtualPort, pLocalPort
   if sControlState is not "authenticated" then
      return "OnionXT: connect and authenticate the control port first (oxConnectControl)"
   end if
   if pVirtualPort is not an integer or pVirtualPort < 1 or pVirtualPort > 65535 then
      return "OnionXT: virtual port must be 1..65535"
   end if
   if pLocalPort is not an integer or pLocalPort < 1 or pLocalPort > 65535 then
      return "OnionXT: local port must be 1..65535"
   end if
   return empty
end oxCheckServiceArgs

private function oxStartService pVirtualPort, pLocalPort
   -- Allocate the handle and START the loopback listener before ADD_ONION so a
   -- forwarded connection is never refused (docs/03 step 4, ordering gotcha).
   local tHandle
   put oxAllocHandle() into tHandle
   put pVirtualPort into sServices[tHandle]["virtualPort"]
   put pLocalPort into sServices[tHandle]["localPort"]
   put empty into sServices[tHandle]["serviceID"]
   put empty into sServices[tHandle]["address"]
   put empty into sServices[tHandle]["privateKey"]
   put false into sServices[tHandle]["ready"]
   if sLocalToService[pLocalPort] is empty then
      -- Bind loopback only. The classic `accept connections on port` has no
      -- bind-address argument (may listen on all interfaces), so oxPeerAccepted
      -- enforces loopback by rejecting any non-loopback peer before reading.
      -- Confirmed on-engine: Tor-forwarded onion connections are accepted here.
      accept connections on port pLocalPort with message "oxPeerAccepted"
      if the result is not empty then
         -- The listener did not bind (most often the local port is already in use
         -- by a prior run or another app). Fail closed: with no listener, Tor
         -- forwards inbound onion traffic to a dead port and the visitor gets an
         -- empty response, which looks exactly like a broken onion.
         delete variable sServices[tHandle]
         return "OnionXT: cannot listen on 127.0.0.1:" & pLocalPort & " (" & the result & ")"
      end if
      put true into sServices[tHandle]["listening"]
   end if
   put tHandle into sLocalToService[pLocalPort]
   return tHandle
end oxStartService

private command oxHandleAddOnionReply pHandle, pReply
   -- Parse ServiceID (and PrivateKey unless discarded) from the ADD_ONION reply
   -- (docs/03 step 3). On failure, fail closed and tear the half-built service.
   local tLine
   if char 1 to 3 of (line 1 of pReply) is not "250" and "ServiceID=" is not in pReply then
      oxRemoveService pHandle
      oxStatusUpdate "control", "error: ADD_ONION failed (" & (line 1 of pReply) & ")"
      exit oxHandleAddOnionReply
   end if
   repeat for each line tLine in pReply
      if "ServiceID=" is in tLine then
         put oxFieldAfter(tLine, "ServiceID=") into sServices[pHandle]["serviceID"]
      else if "PrivateKey=" is in tLine then
         put oxFieldAfter(tLine, "PrivateKey=") into sServices[pHandle]["privateKey"]
      end if
   end repeat
   if sServices[pHandle]["serviceID"] is not empty then
      put sServices[pHandle]["serviceID"] & ".onion" into sServices[pHandle]["address"]
      oxStatusUpdate "service", sServices[pHandle]["address"]
   end if
end oxHandleAddOnionReply

command oxRemoveService pService
   -- DEL_ONION and stop the listener. Idempotent: a stale handle is a no-op.
   if sServices[pService]["localPort"] is empty then
      exit oxRemoveService
   end if
   local tServiceID, tLocalPort
   put sServices[pService]["serviceID"] into tServiceID
   put sServices[pService]["localPort"] into tLocalPort
   if tServiceID is not empty and sControlState is "authenticated" then
      oxCtlSend "DEL_ONION " & tServiceID, "del_onion:" & pService
   end if
   -- Stop accepting on the loopback port, but ONLY if WE own the listener
   -- (oxCreateService / oxCreateServiceFromSeed). A publish-only service
   -- (oxPublishService) forwards to a socket an external server owns; leave it
   -- alone, or we would close it out from under that server.
   if sServices[pService]["external"] is not true then
      if sLocalToService[tLocalPort] is pService then
         oxSafeCloseSocket tLocalPort
         delete variable sLocalToService[tLocalPort]
      end if
   end if
   delete variable sServices[pService]
end oxRemoveService

function oxServiceAddress pService
   return sServices[pService]["address"]
end oxServiceAddress

function oxServiceIsReady pService
   return (sServices[pService]["ready"] is true)
end oxServiceIsReady

command oxPeerAccepted pSocketID
   -- Tor forwarded an inbound onion connection to our loopback listener. Enforce
   -- loopback (security-critical: reject any non-loopback peer before reading a
   -- byte), wrap the accepted socket as an inbound stream, and hand it to the app.
   -- Emit a diagnostic notice with the RAW accepted id so a misparse is visible.
   oxStatusUpdate "notice", "accepted connection id=[" & pSocketID & "]"
   local tPeerHost
   put oxHostOfSocket(pSocketID) into tPeerHost
   if not oxHostIsLoopback(tPeerHost) then
      -- Not a Tor-forwarded loopback connection: refuse it (docs LiveCode ref;
      -- the listener may be bound to all interfaces).
      oxStatusUpdate "notice", "rejected non-loopback peer host [" & tPeerHost & "]"
      oxSafeCloseSocket pSocketID
      exit oxPeerAccepted
   end if
   local tHandle
   put oxAllocHandle() into tHandle
   put pSocketID into sStreams[tHandle]["socketID"]
   put "connected" into sStreams[tHandle]["state"]
   put "inbound" into sStreams[tHandle]["kind"]
   put empty into sStreams[tHandle]["callback"]
   put tHandle into sSockToStream[pSocketID]
   -- Hand the stream to the app FIRST so it can register a stream callback (the
   -- dispatch is synchronous), THEN arm the read so no inbound chunk is delivered
   -- before there is a callback to receive it.
   oxDispatch sPeerCallback, tHandle, oxGuessService(pSocketID), tPeerHost
   if sSockToStream[pSocketID] is not empty then
      read from socket pSocketID with message "oxStreamData"
   end if
end oxPeerAccepted

private function oxGuessService pSocketID
   -- Best-effort service association for the peer callback. The accept callback
   -- carries the PEER address, not our local port, so we cannot always know which
   -- service was reached (VERIFY the accepted-socket id format on-engine). If a
   -- single service is live, return it; otherwise return empty and let the app
   -- key on distinct local ports.
   local tKeys, tCount, tKey
   put the keys of sServices into tKeys
   put the number of lines of tKeys into tCount
   if tCount is 1 then
      return line 1 of tKeys
   end if
   return empty
end oxGuessService

private function oxHostIsLoopback pHost
   -- Accept a Tor-forwarded (loopback) peer no matter how the engine spells the
   -- local address in the accepted-socket id: "127.0.0.1", any "127.x" in the
   -- 127.0.0.0/8 block, IPv6 "::1" / "[::1]", the name "localhost", or empty
   -- (some engines report no host for a local accept). Reject anything else, so a
   -- listener that bound to all interfaces cannot be reached by a routable peer.
   local tHost
   put pHost into tHost
   if tHost is empty then
      return true
   end if
   if tHost is kOxHost then
      return true
   end if
   if tHost begins with "127." then
      return true
   end if
   if tHost is "::1" or tHost is "[::1]" then
      return true
   end if
   if tHost is "localhost" then
      return true
   end if
   return false
end oxHostIsLoopback

-- ==========================================================================
-- Address helpers: a v3 .onion address IS an ed25519 public key
-- (docs/04-onion-rendezvous.md). base32 and the layout are pure byte work; only
-- the checksum needs SHA3-256, which is composed from SodiumXT (docs/08).
-- ==========================================================================

function oxPublicKeyFromAddress pOnionAddress
   -- Strip ".onion", base32-decode 56 chars -> 35 bytes, return the first 32 (the
   -- ed25519 public key). No crypto needed. Empty on a structural error.
   local tCore, tRaw
   put oxNormalizeAddress(pOnionAddress) into tCore
   if the number of chars of tCore is not 56 then
      return empty
   end if
   put oxBase32Decode(tCore) into tRaw
   if the number of bytes of tRaw is not 35 then
      return empty
   end if
   if byteToNum(byte 35 of tRaw) is not 3 then
      return empty            -- not a version-3 address
   end if
   return byte 1 to 32 of tRaw
end oxPublicKeyFromAddress

function oxAddressFromPublicKey pEd25519Pub
   -- base32( pubkey || checksum || 0x03 ) & ".onion" (docs/04). The checksum is
   -- SHA3-256(".onion checksum" || pubkey || 0x03)[:2], composed from SodiumXT;
   -- absent that primitive, return a clear error rather than a wrong address.
   if the number of bytes of pEd25519Pub is not 32 then
      return "OnionXT: oxAddressFromPublicKey needs a 32-byte ed25519 public key"
   end if
   local tChecksum
   put oxOnionChecksum(pEd25519Pub) into tChecksum
   if the number of bytes of tChecksum is not 2 then
      return tChecksum         -- capability error, surfaced verbatim
   end if
   return oxBase32Encode(pEd25519Pub & tChecksum & numToByte(3)) & ".onion"
end oxAddressFromPublicKey

function oxIsValidAddress pOnionAddress
   -- Structural checks always (length, alphabet, version byte); checksum
   -- verification too when SodiumXT SHA3-256 is available (docs/04, docs/08).
   local tCore, tRaw
   put oxNormalizeAddress(pOnionAddress) into tCore
   if the number of chars of tCore is not 56 then
      return false
   end if
   local tI, tCh
   repeat with tI = 1 to 56
      put char tI of tCore into tCh
      if offset(tCh, kOxBase32Alphabet) is 0 then
         return false
      end if
   end repeat
   put oxBase32Decode(tCore) into tRaw
   if the number of bytes of tRaw is not 35 then
      return false
   end if
   if byteToNum(byte 35 of tRaw) is not 3 then
      return false
   end if
   -- Checksum verification when we can compute it; otherwise structural-only
   -- (the real authentication is Tor's connect-time descriptor-signature check).
   local tChecksum
   put oxOnionChecksum(byte 1 to 32 of tRaw) into tChecksum
   if the number of bytes of tChecksum is not 2 then
      return true             -- no SHA3-256 available; accept the structure
   end if
   return oxConstantTimeEqual(tChecksum, byte 33 to 34 of tRaw)
end oxIsValidAddress

private function oxNormalizeAddress pOnionAddress
   -- Trim, lowercase, and strip a trailing ".onion".
   local tCore
   put oxTrim(pOnionAddress) into tCore
   put toLower(tCore) into tCore
   if tCore ends with ".onion" then
      put char 1 to -7 of tCore into tCore
   end if
   return tCore
end oxNormalizeAddress

private function oxPow2 pN
   -- 2 to the pN, as an exact integer, WITHOUT the ^ operator (some xTalk
   -- parsers reject `^` in a div/mod expression). pN is small in base32 (0..12),
   -- so this is a few multiplies and stays well within exact-integer range.
   local tR, tI
   put 1 into tR
   repeat with tI = 1 to pN
      multiply tR by 2
   end repeat
   return tR
end oxPow2

private function oxIntDiv pA, pB
   -- Integer division (floor, for the non-negative operands base32 uses) WITHOUT
   -- the `div` operator, to sidestep any xTalk parser that mishandles div/mod/^
   -- inside a compound expression. Operands here are small (base32 bit math).
   return trunc(pA / pB)
end oxIntDiv

private function oxIntMod pA, pB
   -- pA modulo pB WITHOUT the `mod` operator (see oxIntDiv).
   return pA - pB * oxIntDiv(pA, pB)
end oxIntMod

private function oxBase32Encode pData
   -- RFC 4648 base32, lowercase, no padding. Pure bit-packing: accumulate input
   -- bytes MSB-first into a small buffer and emit 5-bit groups. The buffer is
   -- masked to its pending bits each iteration so it never grows past ~13 bits
   -- (staying in exact-integer range; a 280-bit accumulator would lose precision).
   local tOut, tBits, tValue, tI, tN, tIndex
   put "" into tOut
   put 0 into tBits
   put 0 into tValue
   put the number of bytes of pData into tN
   repeat with tI = 1 to tN
      put tValue * 256 + byteToNum(byte tI of pData) into tValue
      add 8 to tBits
      repeat while tBits >= 5
         subtract 5 from tBits
         put oxIntMod(oxIntDiv(tValue, oxPow2(tBits)), 32) into tIndex
         put char (tIndex + 1) of kOxBase32Alphabet after tOut
      end repeat
      put oxIntMod(tValue, oxPow2(tBits)) into tValue        -- keep only the pending bits
   end repeat
   if tBits > 0 then
      -- Left-align the final partial group and emit it (canonical no-pad tail).
      put oxIntMod(tValue * oxPow2(5 - tBits), 32) into tIndex
      put char (tIndex + 1) of kOxBase32Alphabet after tOut
   end if
   return tOut
end oxBase32Encode

private function oxBase32Decode pText
   -- Inverse of oxBase32Encode. Accumulate 5 bits per input char and emit a byte
   -- whenever 8 bits are available; leftover (< 5) bits of the final group are
   -- discarded (canonical). Returns empty on any character outside the alphabet.
   local tOut, tBits, tValue, tI, tN, tCh, tIndex, tByteOut
   put "" into tOut
   put 0 into tBits
   put 0 into tValue
   put the number of chars of pText into tN
   repeat with tI = 1 to tN
      put char tI of pText into tCh
      put offset(tCh, kOxBase32Alphabet) into tIndex     -- 1..32, or 0 if absent
      if tIndex is 0 then
         return empty
      end if
      put tValue * 32 + (tIndex - 1) into tValue
      add 5 to tBits
      if tBits >= 8 then
         subtract 8 from tBits
         put oxIntMod(oxIntDiv(tValue, oxPow2(tBits)), 256) into tByteOut
         put numToByte(tByteOut) after tOut
         put oxIntMod(tValue, oxPow2(tBits)) into tValue
      end if
   end repeat
   return tOut
end oxBase32Decode

private function oxOnionChecksum pEd25519Pub
   -- SHA3-256(".onion checksum" || pubkey || 0x03)[:2] (docs/04). H = SHA3-256 is
   -- a SodiumXT primitive (docs/08); compose it and report a capability error if
   -- it is absent, never hand-roll a hash (CLAUDE.md rule 1).
   local tPreimage, tHash
   put textEncode(kOxChecksumPrefix, "UTF-8") & pEd25519Pub & numToByte(3) into tPreimage
   put oxSha3_256(tPreimage) into tHash
   -- A valid SHA3-256 is exactly 32 bytes; any other length is the capability
   -- error string from oxSha3_256, surfaced verbatim (robust against comparing a
   -- string prefix against binary data).
   if the number of bytes of tHash is not 32 then
      return tHash
   end if
   return byte 1 to 2 of tHash
end oxOnionChecksum

private function oxExpandedKeyFromSeed pSeed
   -- Compose SodiumXT's ABI-6 helper (docs/08 gap #1, now SHIPPED): a 32-byte seed
   -- becomes the 64-byte Tor ED25519-V3 expanded secret key (SHA-512(seed) with the
   -- ed25519 scalar clamp, all done inside SodiumXT so OnionXT hand-rolls nothing).
   -- This is exactly the key ADD_ONION ED25519-V3:<key> wants (docs/04), and its
   -- public key equals sxSignKeypairFromSeed(pSeed)'s, so the .onion address and the
   -- app's signing identity stay consistent. Requires SodiumXT ABI >= 6.
   local tExpanded
   try
      put sxSignSeedToExpandedKey(pSeed) into tExpanded
   catch tError
      return "OnionXT: oxCreateServiceFromSeed needs SodiumXT sxSignSeedToExpandedKey (requires SodiumXT ABI >= 6; see docs/08)"
   end try
   if the number of bytes of tExpanded is not 64 then
      return "OnionXT: sxSignSeedToExpandedKey returned " & the number of bytes of tExpanded & " bytes, expected 64"
   end if
   return tExpanded
end oxExpandedKeyFromSeed

-- ==========================================================================
-- Pluggable transport seam (docs/06). Thin wrappers so any higher-layer protocol
-- can treat OnionXT as a transport: dial by rendezvous address, listen at a
-- seed-derived address, send/recv bytes. OnionXT stays a transport: no crypto,
-- no framing opinion; the payload is sealed by the app via SodiumXT.
-- ==========================================================================

function oxTransportInfo
   -- Advertise the transport and which optional SodiumXT-backed capabilities are
   -- available, so a caller can negotiate transports and fall back visibly
   -- rather than silently (docs/06). Returns a LiveCode array.
   local tInfo
   put "ox" into tInfo["transport"]
   put kOxVersion into tInfo["version"]
   put (oxSodiumHasHmac() and oxSodiumHasRandom()) into tInfo["safeCookieAuth"]
   put oxSodiumHasExpansion() into tInfo["deterministicOnion"]
   put oxSodiumHasSha3() into tInfo["offlineAddress"]
   return tInfo
end oxTransportInfo

command oxTransportDial pAddress, pPort
   -- Dial a rendezvous address. Accepts a full <56>.onion, or a 32-byte ed25519
   -- public key / 64-hex string, which it maps to an address first (docs/06).
   local tPort, tHost
   if pPort is empty then
      put 80 into tPort
   else
      put pPort into tPort
   end if
   put pAddress into tHost
   if not (tHost ends with ".onion") then
      local tPub
      if the number of chars of tHost is 64 then
         put oxHexToBytes(tHost) into tPub
      else
         put tHost into tPub
      end if
      if the number of bytes of tPub is 32 then
         put oxAddressFromPublicKey(tPub) into tHost
         if tHost begins with "OnionXT:" then
            return tHost
         end if
      end if
   end if
   oxDial tHost, tPort
   return the result
end oxTransportDial

command oxTransportListen pSeed, pVirtualPort, pLocalPort
   -- Publish a reproducible rendezvous point from a seed (docs/06).
   oxCreateServiceFromSeed pSeed, pVirtualPort, pLocalPort
   return the result
end oxTransportListen

command oxTransportSend pStream, pData
   oxWrite pStream, pData
   return the result
end oxTransportSend

command oxTransportRecv pStream, pHandlerName
   -- Register where inbound bytes are delivered (the stream callback).
   oxSetStreamCallback pStream, pHandlerName
   return the result
end oxTransportRecv

-- ==========================================================================
-- Lifecycle and teardown. Central socket-message handlers and a master
-- oxShutdown so an app can free everything it opened, e.g. on closeStack (there
-- is no deterministic unload hook in OXT; CLAUDE.md handles-and-state).
-- ==========================================================================

command oxShutdown
   -- Idempotent: close every stream, remove every service, disconnect control.
   -- Safe to call twice.
   local tKey, tKeys
   put the keys of sStreams into tKeys
   repeat for each line tKey in tKeys
      oxCloseStream tKey
   end repeat
   put the keys of sServices into tKeys
   repeat for each line tKey in tKeys
      oxRemoveService tKey
   end repeat
   oxDisconnectControl
end oxShutdown

on socketError pSocketID, pError
   -- The engine's socket-failure message. If the socket closes because of an
   -- error, this arrives instead of socketClosed. Look up the owner and fail
   -- closed (docs LiveCode ref). A message for an unknown id is a clean no-op.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      oxStreamFail tHandle, "socket error: " & pError
      exit socketError
   end if
   if pSocketID is sControlSocket then
      oxStatusUpdate "control", "error: " & pError
      oxDisconnectControl
   end if
end socketError

on socketClosed pSocketID
   -- The remote side closed cleanly. Deliver "closed" to a stream's app callback
   -- and forget it; for the control socket, mark disconnected.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      oxInvokeStreamCallback tHandle, "closed", empty
      delete variable sSockToStream[pSocketID]
      delete variable sStreams[tHandle]
      exit socketClosed
   end if
   if pSocketID is sControlSocket then
      oxStatusUpdate "control", "disconnected"
      oxDisconnectControl
   end if
end socketClosed

on socketTimeout pSocketID
   -- socketTimeout REPEATS every interval while a read/write is pending (docs
   -- LiveCode ref), so it is only fatal during a handshake; on a connected stream
   -- it is just an idle read and must be ignored. Tear down only handshakes.
   local tHandle, tState
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      put sStreams[tHandle]["state"] into tState
      if tState is not "connected" then
         oxStreamFail tHandle, "SOCKS handshake timed out"
      end if
      exit socketTimeout
   end if
   -- Control socket: only fatal before authentication completes.
   if pSocketID is sControlSocket and sControlState is not "authenticated" then
      oxStatusUpdate "control", "error: control handshake timed out"
      oxDisconnectControl
   end if
end socketTimeout

-- ==========================================================================
-- Optional Mode B: launch and supervise a bundled tor (docs/07). This is a
-- CONVENIENCE layer, NOT the default and NOT the tested path; the assume-running
-- daemon (Mode A) is the trusted, recommended base. VERIFY every step on-engine.
-- ==========================================================================

command oxLaunchTor pTorPath, pDataDir, pSocksPort, pControlPort
   -- Write a minimal torrc into pDataDir and launch pTorPath against it, so tor
   -- exits with the app (__OwningControllerProcess) and uses cookie auth. Returns
   -- empty on a clean launch attempt, or an error string. The caller then polls
   -- oxConnectControl / oxBootstrapProgress; this does not wait for bootstrap.
   if pTorPath is empty or pDataDir is empty then
      return "OnionXT: oxLaunchTor needs a tor binary path and a data directory"
   end if
   local tSocks, tControl, tTorrc, tRcPath
   if pSocksPort is empty then
      put kOxSocksPortDefault into tSocks
   else
      put pSocksPort into tSocks
   end if
   if pControlPort is empty then
      put kOxControlPortDefault into tControl
   else
      put pControlPort into tControl
   end if
   put "SocksPort " & tSocks & oxCrlf() after tTorrc
   put "ControlPort " & tControl & oxCrlf() after tTorrc
   put "CookieAuthentication 1" & oxCrlf() after tTorrc
   put "DataDirectory " & pDataDir & oxCrlf() after tTorrc
   -- Tie tor's lifetime to this process where the platform supports it.
   put "__OwningControllerProcess " & oxProcessId() & oxCrlf() after tTorrc
   put pDataDir & "/onionxt-torrc" into tRcPath
   put tTorrc into url ("binfile:" & tRcPath)
   oxSetSocksPort tSocks
   oxSetControlPort tControl
   -- open process is platform-specific; launch tor detached with -f <torrc>.
   -- VERIFY: process launch and teardown on your target OXT build.
   open process (pTorPath & " -f " & tRcPath) for read
   return empty
end oxLaunchTor

command oxStopTor
   -- Ask tor to shut down over the control port, then disconnect. If Mode B was
   -- not used this simply disconnects control (idempotent).
   if sControlState is "authenticated" then
      oxCtlSend "SIGNAL SHUTDOWN", "signal"
   end if
   oxDisconnectControl
end oxStopTor

-- ==========================================================================
-- SodiumXT composition helpers (requires SodiumXT ABI >= 6 for the deterministic
-- onion and SAFECOOKIE paths). Each sx* primitive is called DIRECTLY and wrapped
-- in try/catch: an absent handler raises a catchable execution error, so a missing
-- primitive degrades to a clear capability error rather than crashing, and the
-- function's return value comes back unambiguously (CLAUDE.md rule 1; no crypto is
-- hand-rolled here). base32 and the base64 encode are pure byte ops, NOT here.
-- ==========================================================================

private function oxSha3_256 pData
   -- Deferred gap (docs/08 #2): libsodium has no SHA-3, so SodiumXT does not ship
   -- sxSha3_256. Compose it if it ever lands; else a clear error. The checksum is a
   -- nicety, not a security dependency (tor authenticates the onion at connect
   -- time), so callers degrade to structural-only address checks.
   local tOut
   try
      put sxSha3_256(pData) into tOut
   catch tError
      return "OnionXT: the offline .onion checksum needs SodiumXT SHA3-256 (sxSha3_256, deferred gap, docs/08)"
   end try
   return tOut
end oxSha3_256

private function oxHmac pKeyString, pMessage
   -- HMAC-SHA256 (SodiumXT ABI >= 6). The ASCII key string crosses as its bytes.
   local tOut
   try
      put sxHmacSha256(textEncode(pKeyString, "UTF-8"), pMessage) into tOut
   catch tError
      return "OnionXT: SAFECOOKIE auth needs SodiumXT HMAC-SHA256 (sxHmacSha256, SodiumXT ABI >= 6, docs/08)"
   end try
   return tOut
end oxHmac

private function oxRandomBytes pCount
   local tOut
   try
      put sxRandomBytes(pCount) into tOut
   catch tError
      return empty
   end try
   return tOut
end oxRandomBytes

private function oxConstantTimeEqual pA, pB
   -- Prefer SodiumXT's constant-time compare; fall back to a plain compare only
   -- when it is unavailable (acceptable on a loopback control port).
   local tOut
   try
      put sxMemEqual(pA, pB) into tOut
      return (tOut is true)
   catch tError
      return (pA is pB)
   end try
end oxConstantTimeEqual

private function oxSodiumHasHmac
   -- True if SodiumXT (ABI >= 6) provides HMAC-SHA256. A benign 1-byte probe.
   local tOut
   try
      put sxHmacSha256(numToByte(0), numToByte(0)) into tOut
      return (the number of bytes of tOut is 32)
   catch tError
      return false
   end try
end oxSodiumHasHmac

private function oxSodiumHasRandom
   local tOut
   try
      put sxRandomBytes(1) into tOut
      return (the number of bytes of tOut is 1)
   catch tError
      return false
   end try
end oxSodiumHasRandom

private function oxSodiumHasSha3
   -- Deferred gap: expected false until SodiumXT ships SHA3-256 (docs/08 #2).
   try
      get sxSha3_256(empty)
      return true
   catch tError
      return false
   end try
end oxSodiumHasSha3

private function oxSodiumHasExpansion
   -- True if SodiumXT (ABI >= 6) provides the seed -> expanded-key helper.
   local tOut
   try
      put sxSignSeedToExpandedKey(oxZeroBytes(32)) into tOut
      return (the number of bytes of tOut is 64)
   catch tError
      return false
   end try
end oxSodiumHasExpansion

private function oxLoadCookie
   -- Read the 32 raw cookie bytes from the authoritative PROTOCOLINFO path
   -- (docs/03). binfile is binary-safe. Returns true on a plausible 32-byte read.
   if sControlCookieFile is empty then
      return false
   end if
   local tBytes
   put url ("binfile:" & sControlCookieFile) into tBytes
   if the number of bytes of tBytes is not 32 then
      return false
   end if
   put tBytes into sControlCookieBytes
   return true
end oxLoadCookie

-- ==========================================================================
-- Small pure helpers.
-- ==========================================================================

private function effectiveSocksPort
   if sSocksPort is empty then
      return kOxSocksPortDefault
   end if
   return sSocksPort
end effectiveSocksPort

private function effectiveControlPort
   if sControlPort is empty then
      return kOxControlPortDefault
   end if
   return sControlPort
end effectiveControlPort

private function oxAllocHandle
   -- Monotonic; 0 is never a valid handle so a zero/empty is always a clean miss.
   if sNextHandle is empty then
      put 0 into sNextHandle
   end if
   add 1 to sNextHandle
   return sNextHandle
end oxAllocHandle

private command oxSafeCloseSocket pSocketID
   -- Idempotent close: only close ids the engine still lists as open, so closing
   -- a stale/unknown id is a clean no-op (VERIFY the engine tolerates it anyway).
   if pSocketID is empty then
      exit oxSafeCloseSocket
   end if
   if pSocketID is among the lines of the openSockets then
      close socket pSocketID
   end if
end oxSafeCloseSocket

private command oxInvokeStreamCallback pStream, pEvent, pData
   oxDispatch sStreams[pStream]["callback"], pStream, pEvent, pData
end oxInvokeStreamCallback

private command oxDispatch pHandlerName, pArg1, pArg2, pArg3
   -- Deliver to the app; a missing handler is a clean no-op so an app wires only
   -- the callbacks it uses. Guard the call so a throwing app handler cannot break
   -- the state machine.
   if pHandlerName is empty then
      exit oxDispatch
   end if
   local tTarget
   put oxCallbackTarget() into tTarget      -- a local, not a function call inline
   try
      dispatch pHandlerName to tTarget with pArg1, pArg2, pArg3
   catch tIgnore
      -- Swallow app-side callback errors; the transport must keep running.
   end try
end oxDispatch

private function oxCallbackTarget
   -- The object the app callbacks live in. Explicitly set is authoritative;
   -- otherwise the topStack is the best default (VERIFY it is the app's stack).
   if sCallbackOwner is not empty then
      return sCallbackOwner
   end if
   return the topStack
end oxCallbackTarget

private function oxCrlf
   -- The wire line terminator as explicit bytes-to-be (U+000D U+000A), so the
   -- byte value never depends on how the engine defines the `crlf` constant.
   return numToChar(13) & numToChar(10)
end oxCrlf

private function oxStripLineEnd pLine
   -- Strip a trailing LF and/or CR from a decoded reply line, in either order.
   -- A plain function (returns the trimmed line) rather than a @-by-reference
   -- command, to avoid the less-common reference-parameter construct.
   repeat while pLine is not empty and (the last char of pLine is numToChar(10) or the last char of pLine is numToChar(13))
      delete the last char of pLine
   end repeat
   return pLine
end oxStripLineEnd

private function oxFieldAfter pText, pMarker
   -- The whitespace-delimited token immediately following pMarker in pText, or
   -- empty. Used for METHODS=, PROGRESS=, ServiceID=, version=, SERVERHASH=, etc.
   -- itemDelimiter is global mutable state, so save and restore it (gotcha 7).
   local tPos, tRest, tSaved, tOut
   put offset(pMarker, pText) into tPos
   if tPos is 0 then
      return empty
   end if
   put char (tPos + the number of chars of pMarker) to -1 of pText into tRest
   -- Stop at the first space (values here are single tokens; quoted values use
   -- oxQuotedValueAfter instead).
   put the itemDelimiter into tSaved
   set the itemDelimiter to space
   put item 1 of tRest into tOut
   set the itemDelimiter to tSaved
   return tOut
end oxFieldAfter

private function oxQuotedValueAfter pText, pMarker
   -- The C-quoted string value following pMarker (e.g. COOKIEFILE="..."). Returns
   -- the raw (still-escaped) inside of the quotes; the caller un-escapes.
   local tPos, tRest, tOut, tI, tCh, tEsc
   put offset(pMarker, pText) into tPos
   if tPos is 0 then
      return empty
   end if
   put char (tPos + the number of chars of pMarker) to -1 of pText into tRest
   if char 1 of tRest is not quote then
      -- Unquoted value: take up to the next space (save/restore itemDelimiter).
      -- tOut is already declared at the handler top; only tSaved is new here.
      local tSaved
      put the itemDelimiter into tSaved
      set the itemDelimiter to space
      put item 1 of tRest into tOut
      set the itemDelimiter to tSaved
      return tOut
   end if
   -- Walk from just after the opening quote to the matching unescaped quote.
   put empty into tOut
   put false into tEsc
   repeat with tI = 2 to the number of chars of tRest
      put char tI of tRest into tCh
      if tEsc then
         put tCh after tOut
         put false into tEsc
      else if tCh is "\" then
         put tCh after tOut
         put true into tEsc
      else if tCh is quote then
         exit repeat
      else
         put tCh after tOut
      end if
   end repeat
   return tOut
end oxQuotedValueAfter

private function oxCUnescape pStr
   -- Undo Tor's C-style string escapes (docs/03): \n \t \r, octal \0..\377, and
   -- backslash-before-any-other-char is that literal char.
   local tOut, tI, tN, tCh, tNext, tOct
   put empty into tOut
   put the number of chars of pStr into tN
   put 1 into tI
   repeat while tI <= tN
      put char tI of pStr into tCh
      if tCh is "\" and tI < tN then
         put char (tI + 1) of pStr into tNext
         if tNext is "n" then
            put numToChar(10) after tOut
            add 2 to tI
         else if tNext is "t" then
            put numToChar(9) after tOut
            add 2 to tI
         else if tNext is "r" then
            put numToChar(13) after tOut
            add 2 to tI
         else if tNext is in "01234567" then
            -- Up to 3 octal digits.
            put empty into tOct
            add 1 to tI
            repeat while tI <= tN and (the number of chars of tOct) < 3 and (char tI of pStr) is in "01234567"
               put char tI of pStr after tOct
               add 1 to tI
            end repeat
            put numToChar(oxOctalToNum(tOct)) after tOut
         else
            put tNext after tOut
            add 2 to tI
         end if
      else
         put tCh after tOut
         add 1 to tI
      end if
   end repeat
   return tOut
end oxCUnescape

private function oxOctalToNum pOct
   local tVal, tI
   put 0 into tVal
   repeat with tI = 1 to the number of chars of pOct
      put tVal * 8 + (charToNum(char tI of pOct) - 48) into tVal
   end repeat
   return tVal
end oxOctalToNum

private function oxQuoteEscape pStr
   -- Escape backslash and double-quote for a control-port QuotedString.
   local tOut
   put pStr into tOut
   replace "\" with "\\" in tOut
   replace quote with ("\" & quote) in tOut
   return tOut
end oxQuoteEscape

private function oxBytesToHex pData
   -- Lowercase hex (high nibble first). H* unpacks the whole run. binaryDecode is
   -- a FUNCTION (it returns the count decoded and fills the output variable, which
   -- must already exist), so it must be called as a function; `get` discards the
   -- count into `it` while tHex is filled.
   local tHex
   get binaryDecode("H*", pData, tHex)
   return tHex
end oxBytesToHex

private function oxHexToBytes pHex
   return binaryEncode("H*", pHex)
end oxHexToBytes

private function oxByteHex pNum
   -- Two-digit hex for one byte value (for error messages).
   return oxBytesToHex(numToByte(pNum))
end oxByteHex

private function oxHostOfSocket pSocketID
   -- The host part of an engine socket id "host:port" or "host:port|name".
   local tSaved, tOut
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   put item 1 of pSocketID into tOut
   set the itemDelimiter to tSaved
   return tOut
end oxHostOfSocket

private function oxMethodOffered pMethod
   -- sControlMethods is a comma list; force comma before testing membership.
   local tSaved, tResult
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put (pMethod is among the items of sControlMethods) into tResult
   set the itemDelimiter to tSaved
   return tResult
end oxMethodOffered

private function oxStripWhitespace pStr
   local tOut
   put pStr into tOut
   replace numToChar(10) with empty in tOut
   replace numToChar(13) with empty in tOut
   replace space with empty in tOut
   replace tab with empty in tOut
   return tOut
end oxStripWhitespace

private function oxTrim pStr
   -- The `tOut is not empty` guard is essential: the empty string is "in" every
   -- string, so without it an all-whitespace or empty input would loop forever
   -- (the first/last char of empty is empty, which `is in` any charset).
   local tOut, tWhite
   put pStr into tOut
   put space & tab & numToChar(10) & numToChar(13) into tWhite
   repeat while tOut is not empty and (the first char of tOut) is in tWhite
      delete the first char of tOut
   end repeat
   repeat while tOut is not empty and (the last char of tOut) is in tWhite
      delete the last char of tOut
   end repeat
   return tOut
end oxTrim

private function oxZeroBytes pCount
   local tOut, tI
   put empty into tOut
   repeat with tI = 1 to pCount
      put numToByte(0) after tOut
   end repeat
   return tOut
end oxZeroBytes

private function oxProcessId
   -- Best-effort current process id for __OwningControllerProcess (Mode B).
   -- VERIFY the available accessor on your OXT build; empty is tolerated by tor.
   return the processId
end oxProcessId



-- ========================================================================
-- ==== onion-httpd library  (src/onion-httpd.livecodescript)
-- ========================================================================

-- onion-httpd.livecodescript - a small, self-contained HTTP/1.1 server for Tor
-- onion services, built ENTIRELY on OnionXT's accept loop (oxCreateService).
--
-- WHY this instead of the engine's HTTPD Library: LiveCode's built-in HTTPD
-- Library is not present on every OpenXTalk engine (httpdStart raised "handler
-- not found" on-engine). This module needs nothing but OnionXT, which already
-- owns the socket, enforces loopback, and streams inbound bytes - the path the
-- main demo proved works. So it runs wherever OnionXT runs.
--
-- USAGE (in an app that has `start using` onionxt.livecodescript AND this file):
--   oxSetCallbackOwner the long id of me     -- your stack owns onStatus + routes
--   oxSetStatusCallback "onStatus"
--   oxhInit the long id of me                -- where your route handlers live
--   oxhSetRoot "/path/to/site"               -- optional: serve static files
--   oxhRoute "GET", "/hello", "myHello"      -- optional: a dynamic route
--   ... oxConnectControl, and when authenticated:
--   oxhServe 80, 8090                         -- publish an onion + serve HTTP on it
-- A route handler:  command myHello pStream, pRequest ; oxhReply pStream, 200, "hi",
--   "Content-Type: text/plain" ; end myHello
--
-- Public API: oxhInit / oxhServe / oxhSetRoot / oxhServeFiles / oxhRoute /
-- oxhUnroute / oxhReply / oxhStop.
-- It composes OnionXT (ox*); it adds no cryptography and owns no long-lived socket
-- of its own (OnionXT does). Public API `oxhCamelCase`, matching the family style.

constant kOxhCloseDelay = 500     -- ms to let the response flush before closing
constant kOxhMaxRequest = 262144  -- refuse a request head bigger than 256 KB (abuse guard)

local sOxhRoot        -- static-file root folder, or empty
local sOxhAutoIndex   -- true: auto-generate a directory-listing page for folders
local sOxhRoutes      -- array: (METHOD & space & path) -> handler name
local sOxhReq         -- array: stream handle -> accumulated request bytes
local sOxhServed      -- array: stream handle -> true once answered
local sOxhOwner       -- object whose script holds the route handlers

-- ==========================================================================
-- Public API
-- ==========================================================================

command oxhInit pOwner
   -- Remember where the app's route handlers live (default: the topStack).
   put pOwner into sOxhOwner
end oxhInit

command oxhServe pVirtualPort, pLocalPort
   -- Publish an onion and serve HTTP on it via OnionXT's accept loop (OnionXT owns
   -- the socket and rejects non-loopback peers - the proven path). Point OnionXT's
   -- peer callback at this module first, then create the service. Reports the
   -- service handle through `the result` (an integer on success).
   oxSetPeerCallback "oxhPeer"
   oxCreateService pVirtualPort, pLocalPort
   return the result
end oxhServe

command oxhSetRoot pFolder
   -- Static-site mode: serve files from pFolder ("/" maps to /index.html); a folder
   -- with no index.html is a 404 (no directory listing - the safe default for a
   -- site). Empty disables static serving.
   put oxhStripTrailingSlash(pFolder) into sOxhRoot
   put false into sOxhAutoIndex
end oxhSetRoot

command oxhServeFiles pFolder
   -- File-sharing mode: serve every file under pFolder by path AND auto-generate a
   -- directory-listing page (names, sizes, download links) for "/" and each
   -- subfolder, so a visitor can browse and download without you writing an index.
   -- A folder's own index.html, if present, still takes precedence over the listing.
   put oxhStripTrailingSlash(pFolder) into sOxhRoot
   put true into sOxhAutoIndex
end oxhServeFiles

command oxhRoute pMethod, pPath, pHandler
   -- Register a dynamic route (exact path match in v1). pHandler is a command in
   -- the owner's script, called as: pHandler pStream, pRequest.
   put pHandler into sOxhRoutes[toUpper(pMethod) & space & pPath]
end oxhRoute

command oxhUnroute pMethod, pPath
   -- Remove a route registered with oxhRoute. Lets an app switch what a path serves
   -- at runtime (e.g. drop the "/" route so a shared folder's listing shows there
   -- instead). Removing an unregistered route is a harmless no-op.
   delete variable sOxhRoutes[toUpper(pMethod) & space & pPath]
end oxhUnroute

command oxhStop pService
   -- Tear down one served onion (DEL_ONION + stop OnionXT's listener).
   oxRemoveService pService
end oxhStop

command oxhReply pStream, pCode, pBodyText, pHeaders
   -- Send a text response (HTML, JSON, plain) from a route handler. pBodyText is
   -- TEXT; it is UTF-8 encoded and its exact byte length becomes Content-Length.
   oxhSendBytes pStream, pCode, textEncode(pBodyText, "UTF-8"), pHeaders
end oxhReply

-- ==========================================================================
-- OnionXT callbacks (public: reached through the message path). OnionXT has
-- already enforced loopback before oxhPeer fires.
-- ==========================================================================

command oxhPeer pStream, pService, pPeerAddr
   oxSetStreamCallback pStream, "oxhStream"
   put empty into sOxhReq[pStream]
   put false into sOxhServed[pStream]
end oxhPeer

command oxhStream pStream, pEvent, pData
   if pEvent is "data" then
      if sOxhServed[pStream] is true then
         exit oxhStream           -- already answered; ignore the rest of the request
      end if
      put pData after sOxhReq[pStream]
      if the number of bytes of sOxhReq[pStream] > kOxhMaxRequest then
         put true into sOxhServed[pStream]
         delete variable sOxhReq[pStream]     -- free the buffer now; do not hold it
         oxhSendBytes pStream, 413, textEncode("Request too large", "UTF-8"), "Content-Type: text/plain"
         exit oxhStream
      end if
      if oxhRequestComplete(sOxhReq[pStream]) then
         put true into sOxhServed[pStream]
         oxhHandle pStream, sOxhReq[pStream]
         delete variable sOxhReq[pStream]
      end if
   else if pEvent is "closed" or pEvent is "error" then
      delete variable sOxhReq[pStream]
      delete variable sOxhServed[pStream]
   end if
end oxhStream

-- ==========================================================================
-- Request framing and parsing. Byte discipline on the raw request; text ops only
-- on the decoded (ASCII) header block.
-- ==========================================================================

private function oxhHeaderEnd pData
   -- 1-indexed byte position of the first CR of the CRLFCRLF that ends the header
   -- block, or 0 if not present yet. No char/line on binary (gotcha): scan bytes.
   -- Bytes go into locals so the match is a single-line `if` (the static gate does
   -- not join `\` continuations, and a long condition would look unbalanced).
   local tN, tI, tB1, tB2, tB3, tB4
   put the number of bytes of pData into tN
   if tN < 4 then
      return 0
   end if
   repeat with tI = 1 to tN - 3
      put byteToNum(byte tI of pData) into tB1
      if tB1 is 13 then
         put byteToNum(byte (tI + 1) of pData) into tB2
         put byteToNum(byte (tI + 2) of pData) into tB3
         put byteToNum(byte (tI + 3) of pData) into tB4
         if tB2 is 10 and tB3 is 13 and tB4 is 10 then
            return tI
         end if
      end if
   end repeat
   return 0
end oxhHeaderEnd

private function oxhRequestComplete pData
   local tHeadEnd, tHeaders, tContentLen, tBodyStart, tHave
   put oxhHeaderEnd(pData) into tHeadEnd
   if tHeadEnd is 0 then
      return false             -- headers not fully received yet
   end if
   put oxhParseHeaders(byte 1 to (tHeadEnd - 1) of pData) into tHeaders
   put tHeaders["content-length"] into tContentLen
   if tContentLen is empty or tContentLen is not an integer then
      return true              -- no declared body (typical GET)
   end if
   put tHeadEnd + 4 into tBodyStart
   put (the number of bytes of pData) - tBodyStart + 1 into tHave
   return (tHave >= tContentLen)
end oxhRequestComplete

private function oxhParseHeaders pHeaderBytes
   -- pHeaderBytes is the ASCII header block (request line + header lines, no body).
   -- Returns an array: lowercased header names -> values, plus __method / __path /
   -- __query / __resource from the request line. Save and restore the delimiters.
   local tText, tSavedLD, tSavedID, tReqLine, tRes, tI, tLine, tColon, tName, tValue, tOut
   put textDecode(pHeaderBytes, "UTF-8") into tText     -- headers are ASCII
   put the lineDelimiter into tSavedLD
   put the itemDelimiter into tSavedID
   set the lineDelimiter to (numToChar(13) & numToChar(10))
   put line 1 of tText into tReqLine
   put word 1 of tReqLine into tOut["__method"]
   put word 2 of tReqLine into tOut["__resource"]
   set the itemDelimiter to "?"
   put item 1 of tOut["__resource"] into tOut["__path"]
   if the number of items of tOut["__resource"] > 1 then
      put item 2 to -1 of tOut["__resource"] into tOut["__query"]
   end if
   repeat with tI = 2 to the number of lines of tText
      put line tI of tText into tLine
      if tLine is empty then
         next repeat
      end if
      put offset(":", tLine) into tColon
      if tColon > 1 then
         put toLower(oxhTrim(char 1 to (tColon - 1) of tLine)) into tName
         put oxhTrim(char (tColon + 1) to -1 of tLine) into tValue
         put tValue into tOut[tName]
      end if
   end repeat
   set the lineDelimiter to tSavedLD
   set the itemDelimiter to tSavedID
   return tOut
end oxhParseHeaders

-- ==========================================================================
-- Routing: a registered route, else a static file, else 404.
-- ==========================================================================

private command oxhHandle pStream, pData
   local tHeadEnd, tHeaders, tKey, tBodyStart, tContentLen, tBodyEnd
   put oxhHeaderEnd(pData) into tHeadEnd
   put oxhParseHeaders(byte 1 to (tHeadEnd - 1) of pData) into tHeaders
   -- Attach the raw body bytes for a POST handler, CAPPED to the declared
   -- Content-Length. Without the cap, trailing or pipelined bytes in the same read
   -- would bleed into __body and a form/upload route would parse the next request
   -- as part of this body.
   put tHeadEnd + 4 into tBodyStart
   put tHeaders["content-length"] into tContentLen
   if tContentLen is an integer and tContentLen > 0 and (the number of bytes of pData) >= tBodyStart then
      put tBodyStart + tContentLen - 1 into tBodyEnd
      if tBodyEnd > the number of bytes of pData then
         put the number of bytes of pData into tBodyEnd   -- defensive clamp
      end if
      put byte tBodyStart to tBodyEnd of pData into tHeaders["__body"]
   else
      put empty into tHeaders["__body"]
   end if
   put toUpper(tHeaders["__method"]) & space & tHeaders["__path"] into tKey
   if sOxhRoutes[tKey] is not empty then
      dispatch sOxhRoutes[tKey] to oxhOwnerObject() with pStream, tHeaders
      exit oxhHandle
   end if
   if sOxhRoot is not empty and tHeaders["__method"] is "GET" then
      oxhServeStatic pStream, tHeaders["__path"]
      exit oxhHandle
   end if
   oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
end oxhHandle

private command oxhServeStatic pStream, pRawPath
   local tPath, tFile, tIndex
   put urlDecode(pRawPath) into tPath        -- %20 etc. -> real chars for disk mapping
   if tPath is empty then
      put "/" into tPath
   end if
   -- Path-traversal guard AFTER decoding (catches %2e%2e), before touching disk.
   if ".." is in tPath then
      oxhSendBytes pStream, 403, textEncode("Forbidden", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
      exit oxhServeStatic
   end if
   put sOxhRoot & tPath into tFile
   if there is a folder tFile then
      -- A folder URL must end in "/" so relative links in the listing resolve;
      -- redirect if it does not (send the browser back with the slash added).
      if the last char of tPath is not "/" then
         oxhSendBytes pStream, 301, empty, "Location: " & pRawPath & "/"
         exit oxhServeStatic
      end if
      put tFile & "index.html" into tIndex    -- tFile ends with "/" here
      if there is a file tIndex then
         oxhSendFile pStream, tIndex, "index.html"
      else if sOxhAutoIndex is true then
         oxhSendBytes pStream, 200, textEncode(oxhListingHtml(tFile, tPath), "UTF-8"), "Content-Type: text/html; charset=utf-8"
      else
         oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
      end if
      exit oxhServeStatic
   end if
   if there is a file tFile then
      oxhSendFile pStream, tFile, tPath
      exit oxhServeStatic
   end if
   oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
end oxhServeStatic

private command oxhSendFile pStream, pDiskPath, pForMime
   -- Read a file as bytes and serve it with a MIME type from pForMime's extension.
   local tContent
   put url ("binfile:" & pDiskPath) into tContent
   if the result is not empty then
      oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
      exit oxhSendFile
   end if
   oxhSendBytes pStream, 200, tContent, "Content-Type: " & oxhMimeType(pForMime)
end oxhSendFile

private function oxhListingHtml pDiskFolder, pUrlPath
   -- Build a directory-listing page for pDiskFolder (a disk path ending in "/"),
   -- served at pUrlPath (a URL path ending in "/"). Uses `the files` / `the folders`
   -- (portable; `the detailedFiles` is not recognized on every OXT engine and is a
   -- compile-time "bad factor" there). Names are HTML-escaped (a file named
   -- "<script>" cannot inject) and path-encoded for the hrefs; links are relative
   -- to pUrlPath, so a subfolder link browses in and ".." goes up.
   local tSaved, tFiles, tFolders, tName, tOut
   put the defaultFolder into tSaved
   set the defaultFolder to pDiskFolder
   put the files into tFiles
   put the folders into tFolders
   set the defaultFolder to tSaved
   put "<!doctype html><html><head><meta charset='utf-8'><title>Shared files</title>" into tOut
   put "<style>body{font-family:system-ui,sans-serif;max-width:44em;margin:2em auto;padding:0 1em}h1{font-size:1.2em}ul{list-style:none;padding:0}li{padding:.3em 0;border-bottom:1px solid #eee}a{text-decoration:none}</style>" after tOut
   put "</head><body><h1>Shared files: " & oxhHtmlEscape(pUrlPath) & "</h1><ul>" after tOut
   if pUrlPath is not "/" then
      put "<li><a href='../'>.. (up)</a></li>" after tOut
   end if
   repeat for each line tName in tFolders
      if tName is "." or tName is ".." then
         next repeat
      end if
      put "<li><a href='" & oxhPathEncode(tName) & "/'>" & oxhHtmlEscape(tName) & "/</a></li>" after tOut
   end repeat
   repeat for each line tName in tFiles
      if tName is empty then
         next repeat
      end if
      put "<li><a href='" & oxhPathEncode(tName) & "'>" & oxhHtmlEscape(tName) & "</a></li>" after tOut
   end repeat
   put "</ul></body></html>" after tOut
   return tOut
end oxhListingHtml

-- ==========================================================================
-- Response building. The proven demo pattern: exact BYTE Content-Length,
-- Connection: close, then a delayed close so the write flushes cleanly.
-- ==========================================================================

private command oxhSendBytes pStream, pCode, pBodyBytes, pHeaders
   local tCrlf, tResp
   put (numToChar(13) & numToChar(10)) into tCrlf
   put "HTTP/1.1 " & pCode & space & oxhReason(pCode) & tCrlf into tResp
   if pHeaders is not empty then
      put oxhNormalizeHeaders(pHeaders) after tResp
   end if
   put "Content-Length: " & (the number of bytes of pBodyBytes) & tCrlf after tResp
   put "Connection: close" & tCrlf after tResp
   put tCrlf after tResp
   oxWrite pStream, (textEncode(tResp, "UTF-8") & pBodyBytes)
   send ("oxhClose " & pStream) to me in kOxhCloseDelay milliseconds
end oxhSendBytes

command oxhClose pStream
   -- Deferred, idempotent close of a served connection (public: reached via send).
   -- Clear BOTH per-stream tables here as the catch-all: oxCloseStream removes the
   -- OnionXT stream, so no later socketClosed/"closed" event will arrive to clean
   -- the HTTP state, and every response path (200/404/413/301/...) routes through
   -- oxhSendBytes which schedules this. A double-delete on the normal path is a
   -- harmless no-op.
   oxCloseStream pStream
   delete variable sOxhReq[pStream]
   delete variable sOxhServed[pStream]
end oxhClose

private function oxhNormalizeHeaders pHeaders
   -- Turn caller headers ("Name: value", LF- or CRLF-separated) into CRLF lines,
   -- dropping any Content-Length / Connection (this module sets those).
   local tCrlf, tSaved, tI, tLine, tOut, tLow
   put (numToChar(13) & numToChar(10)) into tCrlf
   put the lineDelimiter into tSaved
   set the lineDelimiter to lf
   put empty into tOut
   repeat with tI = 1 to the number of lines of pHeaders
      put line tI of pHeaders into tLine
      if the last char of tLine is (numToChar(13)) then
         delete the last char of tLine   -- tolerate CRLF-separated input
      end if
      if tLine is empty then
         next repeat
      end if
      put toLower(tLine) into tLow
      if tLow begins with "content-length" or tLow begins with "connection" then
         next repeat
      end if
      put tLine & tCrlf after tOut
   end repeat
   set the lineDelimiter to tSaved
   return tOut
end oxhNormalizeHeaders

-- ==========================================================================
-- Small helpers.
-- ==========================================================================

private function oxhMimeType pPath
   local tSaved, tExtn
   put the itemDelimiter into tSaved
   set the itemDelimiter to "."
   put toLower(the last item of pPath) into tExtn
   set the itemDelimiter to tSaved
   if tExtn is "html" or tExtn is "htm" then
      return "text/html; charset=utf-8"
   else if tExtn is "css" then
      return "text/css; charset=utf-8"
   else if tExtn is "js" then
      return "application/javascript; charset=utf-8"
   else if tExtn is "json" then
      return "application/json; charset=utf-8"
   else if tExtn is "txt" then
      return "text/plain; charset=utf-8"
   else if tExtn is "png" then
      return "image/png"
   else if tExtn is "jpg" or tExtn is "jpeg" then
      return "image/jpeg"
   else if tExtn is "gif" then
      return "image/gif"
   else if tExtn is "svg" then
      return "image/svg+xml"
   else if tExtn is "ico" then
      return "image/x-icon"
   else if tExtn is "wasm" then
      return "application/wasm"
   else if tExtn is "pdf" then
      return "application/pdf"
   end if
   return "application/octet-stream"
end oxhMimeType

private function oxhReason pCode
   if pCode is 200 then
      return "OK"
   else if pCode is 204 then
      return "No Content"
   else if pCode is 301 then
      return "Moved Permanently"
   else if pCode is 302 then
      return "Found"
   else if pCode is 400 then
      return "Bad Request"
   else if pCode is 403 then
      return "Forbidden"
   else if pCode is 404 then
      return "Not Found"
   else if pCode is 405 then
      return "Method Not Allowed"
   else if pCode is 413 then
      return "Payload Too Large"
   else if pCode is 500 then
      return "Internal Server Error"
   end if
   return "OK"
end oxhReason

private function oxhTrim pText
   -- Strip leading/trailing spaces and tabs. Guard the empty-string-is-in trap.
   local tOut, tTab
   put pText into tOut
   put numToChar(9) into tTab
   repeat while tOut is not empty and (the first char of tOut is space or the first char of tOut is tTab)
      delete the first char of tOut
   end repeat
   repeat while tOut is not empty and (the last char of tOut is space or the last char of tOut is tTab)
      delete the last char of tOut
   end repeat
   return tOut
end oxhTrim

private function oxhOwnerObject
   if sOxhOwner is not empty then
      return sOxhOwner
   end if
   return the topStack
end oxhOwnerObject

private function oxhStripTrailingSlash pFolder
   local tOut
   put pFolder into tOut
   if tOut is not empty and (the last char of tOut is "/" or the last char of tOut is "\") then
      delete the last char of tOut
   end if
   return tOut
end oxhStripTrailingSlash

private function oxhPathEncode pName
   -- Encode a name for a URL PATH segment. urlEncode uses "+" for space (form
   -- style); a path wants "%20", so fix that up.
   local tEnc
   put urlEncode(pName) into tEnc
   replace "+" with "%20" in tEnc
   return tEnc
end oxhPathEncode

private function oxhHtmlEscape pText
   -- Escape a value for HTML text/attribute context so a crafted file name cannot
   -- inject markup. `&` first, then the rest.
   local tOut
   put pText into tOut
   replace "&" with "&amp;" in tOut
   replace "<" with "&lt;" in tOut
   replace ">" with "&gt;" in tOut
   replace quote with "&quot;" in tOut
   return tOut
end oxhHtmlEscape



-- ========================================================================
-- ==== self-test harness  (examples/onionxt-tests.livecodescript)
-- ========================================================================

-- onionxt-tests.livecodescript - OnionXT's self-test harness.
--
-- Formatted like the sibling family's test harnesses (SodiumXT's
-- sodium-tests.livecodescript: module-level sLog/sPass/sFail, an sxCheck
-- assertion helper, sxSection headers, known-answer vectors, and negative-path
-- checks under try/catch). Start using this stack alongside onionxt.livecodescript
-- and call oxSelfTest() (from a message box, a button, or the "Run self-test"
-- button on examples/onionxt-demo.livecodescript's About tab).
--
-- WHY this suite is PURE and OFFLINE, unlike SodiumXT's (read this before you
-- extend it): SodiumXT is stateless compute with zero I/O, so its self-test can
-- exercise every primitive end-to-end with no external process. OnionXT's whole
-- job is long-lived network I/O against a real tor daemon (CLAUDE.md: "OnionXT
-- owns long-lived network state... is asynchronous and event-driven"), and a
-- synchronous test function fundamentally cannot wait for an async callback
-- without blocking the one interpreter thread, which the library forbids
-- (CLAUDE.md: "never block the interpreter thread on the network"). So this
-- harness deliberately tests only what is reachable WITHOUT a daemon:
--   1. the pure address / base32 logic (docs/04), cross-checked against the
--      same known-answer vectors pinned in tools/onion-kat.py;
--   2. the fail-closed contract on every public command (CLAUDE.md rule 4:
--      argument validation, "not authenticated yet", unknown-handle misses);
--   3. idempotent teardown (duplicate close/remove/disconnect/shutdown);
--   4. the two SodiumXT ABI-6 primitives OnionXT composes (sxSignSeedToExpandedKey,
--      sxHmacSha256) against their pinned vectors - gated on SodiumXT being loaded,
--      skipped (not failed) otherwise. Needs SodiumXT ABI >= 6, not a tor daemon.
-- The actual wire handshakes (SOCKS5 dial, control auth, ADD_ONION) are an
-- on-engine / integration concern: run examples/onionxt-demo.livecodescript or
-- examples/onion-roundtrip against a real tor daemon for those (see
-- IMPLEMENTATION-PLAN.md phase 4 and CLAUDE.md's on-engine VERIFY checklist).
--
-- CAUTION - side effects on shared state: OnionXT's connection/service/stream
-- state is a script-local singleton shared by the whole message path (not
-- per-object), so the idempotent-teardown section below really does call
-- oxDisconnectControl / oxShutdown. If a live demo session (or any other code
-- using this same OnionXT instance) currently has an open control connection,
-- streams, or published services, running oxSelfTest CLOSES THEM as part of
-- proving teardown is idempotent. Run this in a fresh session, or expect it to
-- tear down whatever is currently open.
--
-- STATUS: designed and statically reasoned; needs an on-engine pass like the
-- rest of OnionXT, though everything here is pure script with no socket I/O of
-- its own, so the risk surface is much smaller than the library itself.

-- Two real, published v3 onion addresses, the same vectors pinned in
-- tools/onion-kat.py, so the Python KAT and this livecodescript suite agree.
constant kTestAddrTorProject = "2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion"
constant kTestAddrDuckDuckGo = "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"

local sLog
local sPass
local sFail

-- ==========================================================================
-- Entry point.
-- ==========================================================================

function oxSelfTest
   put empty into sLog
   put 0 into sPass
   put 0 into sFail

   testVersionAndCapabilities
   testInitialState
   testFailClosedArguments
   testUnknownHandlesAreCleanMisses
   testIdempotentTeardown
   testAddressRoundTrip
   testAddressNegativePaths
   testSodiumComposition

   local tSummary
   put sPass & " passed, " & sFail & " failed" into tSummary
   return tSummary & return & "----------------------------------------" & return & sLog
end oxSelfTest

-- ==========================================================================
-- Assertion helpers (SodiumXT's sxCheck / sxSection convention).
-- ==========================================================================

private command oxCheck pCondition, pLabel
   if pCondition then
      add 1 to sPass
      put sLog & "  ok   " & pLabel & return into sLog
   else
      add 1 to sFail
      put sLog & "  FAIL " & pLabel & return into sLog
   end if
end oxCheck

private command oxSection pTitle
   put sLog & return & "-- " & pTitle & " --" & return into sLog
end oxSection

-- ==========================================================================
-- Section 1: version string and the transport capability probe.
-- ==========================================================================

private command testVersionAndCapabilities
   oxSection "version and capabilities"
   oxCheck (oxVersion() is not empty), "oxVersion reports a non-empty string"

   local tInfo
   put oxTransportInfo() into tInfo
   oxCheck (tInfo["transport"] is "ox"), "oxTransportInfo advertises the ox transport"
   oxCheck (tInfo["version"] is oxVersion()), "oxTransportInfo version matches oxVersion"
   -- The three capability flags are always present, true or false, whether or
   -- not SodiumXT is loaded (CLAUDE.md rule 1: a missing primitive degrades to
   -- a clear flag/error, never a crash).
   oxCheck (tInfo["safeCookieAuth"] is true or tInfo["safeCookieAuth"] is false), \
      "safeCookieAuth capability flag is a boolean"
   oxCheck (tInfo["deterministicOnion"] is true or tInfo["deterministicOnion"] is false), \
      "deterministicOnion capability flag is a boolean"
   oxCheck (tInfo["offlineAddress"] is true or tInfo["offlineAddress"] is false), \
      "offlineAddress capability flag is a boolean"
end testVersionAndCapabilities

-- ==========================================================================
-- Section 2: state before any connection has ever been made. Control state is
-- a script-local singleton shared by the whole message path (CLAUDE.md: state
-- is script-local, not per-object), so if this session already called
-- oxConnectControl (for example via examples/onionxt-demo.livecodescript's
-- Status tab) these checks would otherwise be a false failure, not a real bug.
-- Skip them with a clear note rather than asserting something session order
-- can make untrue; run oxSelfTest first, before connecting, for full coverage.
-- ==========================================================================

private command testInitialState
   oxSection "initial state (before oxConnectControl)"
   if oxIsControlAuthenticated() then
      put sLog & "  --   (skipped: this session is already control-authenticated; " & \
         "run oxSelfTest before oxConnectControl for this section)" & return into sLog
      exit testInitialState
   end if
   oxCheck (oxBootstrapProgress() is 0), "bootstrap progress starts at 0"
   oxCheck (not oxIsReady()), "oxIsReady is false before connecting"
   oxCheck (not oxIsControlAuthenticated()), "control is not authenticated before connecting"
end testInitialState

-- ==========================================================================
-- Section 3: fail-closed argument validation (CLAUDE.md rule 4). Every one of
-- these needs no network access; the library rejects the request before it
-- ever opens a socket or sends a command.
-- ==========================================================================

private command testFailClosedArguments
   oxSection "fail-closed argument validation"

   -- oxDial / oxCreateService* are COMMANDS: invoke them as statements and read
   -- their handle-or-error from `the result` (you cannot call a command with
   -- function-call parentheses; that syntax needs a `function` handler). Only
   -- oxAddressFromPublicKey below is a function, so it takes parentheses.
   local tResult
   oxDial empty, 80
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxDial rejects an empty host"

   oxDial "example.onion", 99999
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxDial rejects a port outside 1..65535"

   -- These two prove the pre-auth fail-closed guard specifically, so they are
   -- only meaningful while nothing has authenticated yet in this session (see
   -- the note on testInitialState above); skip rather than false-fail if a
   -- prior oxConnectControl in this session already succeeded.
   if oxIsControlAuthenticated() then
      put sLog & "  --   (skipped: pre-auth guard on oxCreateService* needs a " & \
         "session that has not authenticated yet)" & return into sLog
   else
      oxCreateService 80, 8080
      put the result into tResult
      oxCheck (tResult begins with "OnionXT:"), \
         "oxCreateService fails closed without an authenticated control connection"

      oxCreateServiceFromSeed testZeroSeed(), 80, 8080
      put the result into tResult
      oxCheck (tResult begins with "OnionXT:"), \
         "oxCreateServiceFromSeed also fails closed without an authenticated control connection"
   end if

   put oxAddressFromPublicKey("short") into tResult
   oxCheck (tResult begins with "OnionXT:"), \
      "oxAddressFromPublicKey rejects a public key that is not 32 bytes"
end testFailClosedArguments

-- ==========================================================================
-- Section 4: an unknown / stale handle is a clean miss, never a crash
-- (CLAUDE.md handles-and-state: "a stale or closed id must be a clean no-op /
-- error, never a crash").
-- ==========================================================================

private command testUnknownHandlesAreCleanMisses
   oxSection "unknown handles are clean misses"
   local tUnknown, tResult
   put 999999 into tUnknown

   -- oxStreamState / oxServiceAddress / oxServiceIsReady are functions (parens);
   -- oxSetStreamCallback / oxWrite are commands (statement + `the result`).
   oxCheck (oxStreamState(tUnknown) is "unknown"), "an unknown stream handle reports state unknown"
   oxCheck (oxServiceAddress(tUnknown) is empty), "an unknown service handle has no address"
   oxCheck (not oxServiceIsReady(tUnknown)), "an unknown service handle is not ready"

   oxSetStreamCallback tUnknown, "someHandler"
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxSetStreamCallback on an unknown handle fails closed"

   oxWrite tUnknown, "x"
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxWrite to an unknown/unconnected stream fails closed"
end testUnknownHandlesAreCleanMisses

-- ==========================================================================
-- Section 5: idempotent teardown. Every close/remove/disconnect is safe to
-- call twice, and safe to call on something that was never opened.
-- ==========================================================================

private command testIdempotentTeardown
   oxSection "idempotent teardown (duplicate close is a no-op)"
   local tOk
   put true into tOk
   try
      oxCloseStream 999999
      oxCloseStream 999999
      oxRemoveService 999999
      oxRemoveService 999999
      oxDisconnectControl
      oxDisconnectControl
      oxShutdown
      oxShutdown
   catch tError
      put false into tOk
   end try
   oxCheck tOk, "double close / remove / disconnect / shutdown never throws"
   oxCheck (not oxIsControlAuthenticated()), "control is disconnected after teardown"
end testIdempotentTeardown

-- ==========================================================================
-- Section 6: the v3 address <-> public key mapping, cross-checked against two
-- REAL, published onion addresses (the same vectors tools/onion-kat.py pins).
-- No crypto here except the optional SHA3-256 checksum re-encode, which is
-- skipped (not failed) when SodiumXT does not provide it.
-- ==========================================================================

private command testAddressRoundTrip
   oxSection "v3 address <-> public key (docs/04), against real onions"
   testOneKnownAddress kTestAddrTorProject, "torproject.org's onion"
   testOneKnownAddress kTestAddrDuckDuckGo, "DuckDuckGo's onion"
end testAddressRoundTrip

private command testOneKnownAddress pAddress, pLabel
   local tPub, tInfo
   put oxPublicKeyFromAddress(pAddress) into tPub
   oxCheck (the number of bytes of tPub is 32), \
      pLabel & ": oxPublicKeyFromAddress returns a 32-byte public key"
   oxCheck oxIsValidAddress(pAddress), pLabel & ": oxIsValidAddress accepts it"

   put oxTransportInfo() into tInfo
   if tInfo["offlineAddress"] is true then
      oxCheck (oxAddressFromPublicKey(tPub) is pAddress), \
         pLabel & ": oxAddressFromPublicKey re-encodes the exact same address"
   else
      put sLog & "  --   (skipped: " & pLabel & " re-encode needs SodiumXT sxSha3_256, docs/08)" & return into sLog
   end if
end testOneKnownAddress

-- ==========================================================================
-- Section 7: structural negative paths. A malformed address must not crash
-- and must be rejected, never silently accepted (CLAUDE.md rule 4).
-- ==========================================================================

private command testAddressNegativePaths
   oxSection "address negative paths"
   oxCheck (not oxIsValidAddress("tooshort.onion")), "a too-short address is rejected"
   oxCheck (not oxIsValidAddress("not a valid onion address at all")), "garbage input is rejected"
   oxCheck (oxPublicKeyFromAddress("short.onion") is empty), \
      "a malformed address yields an empty key, not a crash"

   -- Flip the first character of a known-good address (to something else in
   -- the base32 alphabet); it must no longer validate, either structurally (if
   -- the flip breaks the version byte) or by checksum when SHA3-256 is
   -- available.
   local tTampered, tInfo
   put kTestAddrTorProject into tTampered
   if char 1 of tTampered is "2" then
      put "3" into char 1 of tTampered
   else
      put "2" into char 1 of tTampered
   end if
   put oxTransportInfo() into tInfo
   if tInfo["offlineAddress"] is true then
      oxCheck (not oxIsValidAddress(tTampered)), "a tampered address fails checksum validation"
   else
      put sLog & "  --   (skipped: tamper-detection needs SodiumXT sxSha3_256, docs/08)" & return into sLog
   end if
end testAddressNegativePaths

-- ==========================================================================
-- Section 8: the two SodiumXT ABI-6 primitives OnionXT composes, against the
-- known-answer vectors pinned in tools/onion-kat.py. Gated on availability
-- (oxTransportInfo): skipped, not failed, when SodiumXT (ABI >= 6) is not loaded.
-- These call the sx* public handlers directly, confirming the deterministic-onion
-- (gap #1) and SAFECOOKIE (gap #3) compositions produce the right bytes.
-- ==========================================================================

private command testSodiumComposition
   oxSection "SodiumXT ABI-6 composition (docs/08 gaps #1, #3)"
   local tInfo
   put oxTransportInfo() into tInfo

   -- Gap #1 (SHIPPED): sxSignSeedToExpandedKey(seed = 0x42 x 32), 64-byte result.
   if tInfo["deterministicOnion"] is true then
      local tExpanded, tExpectExp
      put "90e7595fc89e52fdfddce9c6a43d74dbf6047025ee0462d2d172e8b6a2841d6ee" & \
          "da66ce2983f7ff7e47c49615220e78c25c775a040957316b7bafd5985450f90" into tExpectExp
      put sxSignSeedToExpandedKey(testRepeatByte(66, 32)) into tExpanded
      oxCheck (testHex(tExpanded) is tExpectExp), \
         "sxSignSeedToExpandedKey(seed 0x42 x 32) matches the pinned expanded-key vector"
   else
      put sLog & "  --   (skipped: sxSignSeedToExpandedKey needs SodiumXT ABI >= 6)" & return into sLog
   end if

   -- Gap #3 (SHIPPED): sxHmacSha256("Jefe","what do ya want for nothing?") RFC 4231 TC2.
   if tInfo["safeCookieAuth"] is true then
      local tMac, tExpectMac
      put "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843" into tExpectMac
      put sxHmacSha256(textEncode("Jefe", "UTF-8"), textEncode("what do ya want for nothing?", "UTF-8")) into tMac
      oxCheck (testHex(tMac) is tExpectMac), \
         "sxHmacSha256 (RFC 4231 Test Case 2) matches the pinned HMAC vector"
   else
      put sLog & "  --   (skipped: sxHmacSha256 needs SodiumXT ABI >= 6)" & return into sLog
   end if
end testSodiumComposition

-- ==========================================================================
-- Small local helpers (test glue only).
-- ==========================================================================

private function testHex pData
   -- binaryDecode is a function that fills its output var; `get` discards the count.
   local tHex
   get binaryDecode("H*", pData, tHex)
   return tHex
end testHex

private function testRepeatByte pByteVal, pCount
   local tOut, tI
   put empty into tOut
   repeat with tI = 1 to pCount
      put numToByte(pByteVal) after tOut
   end repeat
   return tOut
end testRepeatByte

private function testZeroSeed
   return testRepeatByte(0, 32)
end testZeroSeed



-- ========================================================================
-- ==== tabbed demo app  (examples/onionxt-demo.livecodescript)
-- ========================================================================

-- onionxt-demo.livecodescript - an interactive, tabbed showcase of OnionXT.
--
-- Formatted like the sibling family's example stacks (SodiumXT's sodium-demo /
-- sodium-tests split, TorrentXT's examples/): a single stack, built entirely in
-- script on preOpenStack (no IDE design work needed), with a header bar, a tab
-- strip, a persistent status bar, and one content panel per feature. Controls use
-- a "prefix:role" naming scheme (the prefix is the owning tab, the role is the
-- control's job), so a single mouseUp router dispatches every click by parsing
-- the target's name, and each tab shows/hides its controls by name (no groups -
-- LiveCode has no "set the owner" reparent).
--
-- HOW TO RUN: make a new mainstack, set its stack script to this file, and put
-- onionxt.livecodescript in the message path first (start using it as a library).
-- The Service tab now HOSTS over Tor (serve a page or share a folder), so also
-- start using onion-httpd.livecodescript (the oxh* HTTP layer over OnionXT's accept
-- loop). Load sodiumxt too for the seed-derived service and SAFECOOKIE (SodiumXT
-- ABI >= 6), and start using onionxt-tests.livecodescript for the About tab's
-- self-test. Everything here goes through the public ox* / oxh* surface (docs/05,
-- docs/10, examples/onion-httpd); nothing reaches into any private internals.
-- (examples/onionxt-demo-standalone.livecodescript is all four bundled into one
-- paste-and-run stack, generated by tools/build-standalone.py.)
--
-- WHY the flow differs from SodiumXT's demo: SodiumXT is synchronous pure compute
-- (a click calls sx* and the result is ready on the next line). OnionXT owns
-- long-lived network state and is asynchronous (CLAUDE.md), so a click KICKS OFF a
-- dial / publish / connect and the outcome arrives later through a callback. The
-- callbacks (onStatus, onDialStream) drive the UI: they update the status bar,
-- enable/disable buttons, and append to the logs. The Service tab delegates the
-- inbound-HTTP side (accept, parse, reply, close) to onion-httpd, so the demo only
-- supplies a route handler (demoServePage) for page mode and a folder for share
-- mode. Buttons are enabled only when their action is valid, so the flow guides you.
--
-- STATUS: designed and statically reasoned, like the rest of OnionXT; the UI
-- object-creation calls (create field/button/graphic, set properties, show/hide
-- by name, enable/scroll) need an on-engine pass the same way the socket code
-- does. The ox* calls are the real feature surface being demonstrated.

-- ==========================================================================
-- Constants: window geometry, ports (docs/07: system tor 9050/9051, Tor Browser
-- 9150/9151), and defaults for the Dial / Address tabs.
-- ==========================================================================

constant kWinWidth = 820
constant kWinHeight = 560
constant kMargin = 24
constant kContentRight = 796      -- kWinWidth - kMargin
constant kDemoDefaultSocksPort = 9050
constant kDemoDefaultControlPort = 9051
constant kDemoDefaultDialHost = "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"
constant kDemoDefaultDialPort = 80
constant kDemoKnownAddress = "2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion"
-- A SINGLE font name: LiveCode's textFont reads a comma as "fontname,language"
-- (a Unicode language tag), NOT a CSS-style fallback list, so a list would be
-- misparsed. "Courier" is the one monospace name that resolves on every platform.
constant kMono = "Courier"
constant kDemoTabs = "stat,dial,svc,addr,about"

-- ==========================================================================
-- Script-local state. The demo tracks just enough state to drive the status bar
-- and the button enable/disable logic; the authoritative state lives in OnionXT.
-- ==========================================================================

local sTab                  -- the currently visible tab key
local sTabControls          -- array: tab key -> comma list of that tab's control names
local sConnState            -- control-connection state, mirrored from onStatus
local sBootPct              -- last bootstrap percent seen (0..100)
local sDialStream           -- the Dial tab's stream handle, or empty
local sDialOpen             -- true once the dial stream's "open" event arrived
local sSvcHandle            -- the Service tab's published service handle, or empty
local sSvcMode              -- "page" (serve the editor HTML) or "folder" (share a folder)

on preOpenStack
   -- Size and centre the window, then build the whole UI in script (no IDE design
   -- work). Point OnionXT's callbacks at this stack's script.
   set the width of this stack to kWinWidth
   set the height of this stack to kWinHeight
   set the backgroundColor of this stack to demoColor("bg")
   oxSetCallbackOwner the long id of me
   oxSetStatusCallback "onStatus"
   -- The Service tab hosts via onion-httpd; oxhServe sets OnionXT's peer callback
   -- to oxhPeer when it publishes, so the demo does not set one here. oxhInit tells
   -- onion-httpd this stack's script holds the route handlers (demoServePage).
   oxhInit the long id of me
   put "stat" into sTab
   put "disconnected" into sConnState
   put 0 into sBootPct
   demoBuildChrome
   demoBuildStatusTab
   demoBuildDialTab
   demoBuildServiceTab
   demoBuildAddressTab
   demoBuildAboutTab
   demoShowTab "stat"
   demoUpdateStatusBar
   demoUpdateButtons
   pass preOpenStack
end preOpenStack

-- ==========================================================================
-- Palette: one function, literal RGB triples, so every control is consistent.
-- ==========================================================================

private function demoColor pName
   -- Multi-line block form (the return on its own line), matching the library's
   -- own chained-if idiom; the single-line "then return" chain confuses the
   -- static gate and is less certain on-engine.
   if pName is "header" then
      return "20,28,54"
   else if pName is "headerText" then
      return "236,240,248"
   else if pName is "bg" then
      return "244,246,250"
   else if pName is "panel" then
      return "255,255,255"
   else if pName is "border" then
      return "205,210,220"
   else if pName is "accent" then
      return "44,98,200"
   else if pName is "tabIdle" then
      return "225,229,236"
   else if pName is "statusbar" then
      return "30,36,52"
   else if pName is "statusText" then
      return "205,212,224"
   else if pName is "text" then
      return "28,32,40"
   else if pName is "muted" then
      return "108,116,130"
   else if pName is "ok" then
      return "22,140,70"
   else if pName is "warn" then
      return "176,120,20"
   else if pName is "fail" then
      return "198,54,54"
   end if
   return "0,0,0"
end demoColor

-- ==========================================================================
-- Control factory: consistent helpers over the standard LiveCode object commands.
-- ==========================================================================

private command demoMakeRect pName, pRect, pColorName
   create graphic pName
   set the style of graphic pName to "rectangle"
   set the rect of graphic pName to pRect
   set the filled of graphic pName to true
   set the lineSize of graphic pName to 0
   set the backgroundColor of graphic pName to demoColor(pColorName)
end demoMakeRect

private command demoMakeLabel pName, pRect, pText
   -- A muted, right-nothing caption label; no border, blends with the window bg.
   create field pName
   set the rect of field pName to pRect
   set the text of field pName to pText
   set the backgroundColor of field pName to demoColor("bg")
   set the foregroundColor of field pName to demoColor("muted")
   set the borderWidth of field pName to 0
   set the threeD of field pName to false
   set the lockText of field pName to true
end demoMakeLabel

private command demoMakeTitle pName, pRect, pText
   create field pName
   set the rect of field pName to pRect
   set the text of field pName to pText
   set the backgroundColor of field pName to demoColor("bg")
   set the foregroundColor of field pName to demoColor("text")
   set the textStyle of field pName to "bold"
   set the borderWidth of field pName to 0
   set the threeD of field pName to false
   set the lockText of field pName to true
end demoMakeTitle

private command demoMakeHint pName, pRect, pText
   -- A muted, wrapping, multi-line caption (torrc reference, blurb, etc.).
   create field pName
   set the rect of field pName to pRect
   set the text of field pName to pText
   set the backgroundColor of field pName to demoColor("bg")
   set the foregroundColor of field pName to demoColor("muted")
   set the borderWidth of field pName to 0
   set the threeD of field pName to false
   set the lockText of field pName to true
   set the dontWrap of field pName to false
end demoMakeHint

private command demoMakeInput pName, pRect, pDefaultText, pMono
   create field pName
   set the rect of field pName to pRect
   set the text of field pName to pDefaultText
   set the backgroundColor of field pName to demoColor("panel")
   set the foregroundColor of field pName to demoColor("text")
   set the borderColor of field pName to demoColor("border")
   set the borderWidth of field pName to 1
   set the threeD of field pName to false
   set the opaque of field pName to true
   if pMono is "mono" then
      set the textFont of field pName to kMono
   end if
end demoMakeInput

private command demoMakeValue pName, pRect
   -- A locked, monospace, single-line display of one value (address, pubkey).
   create field pName
   set the rect of field pName to pRect
   set the text of field pName to empty
   set the backgroundColor of field pName to demoColor("panel")
   set the foregroundColor of field pName to demoColor("text")
   set the borderColor of field pName to demoColor("border")
   set the borderWidth of field pName to 1
   set the threeD of field pName to false
   set the opaque of field pName to true
   set the lockText of field pName to true
   set the textFont of field pName to kMono
   set the dontWrap of field pName to true
end demoMakeValue

private command demoMakeLog pName, pRect
   -- A locked, monospace, scrolling, append-only log / output box.
   create field pName
   set the rect of field pName to pRect
   set the text of field pName to empty
   set the backgroundColor of field pName to demoColor("panel")
   set the foregroundColor of field pName to demoColor("text")
   set the borderColor of field pName to demoColor("border")
   set the borderWidth of field pName to 1
   set the threeD of field pName to false
   set the opaque of field pName to true
   set the lockText of field pName to true
   set the textFont of field pName to kMono
   set the dontWrap of field pName to false
   set the vScrollbar of field pName to true
end demoMakeLog

private command demoMakeEditor pName, pRect
   -- An EDITABLE, monospace, wrapping, scrolling multi-line input (the page HTML).
   create field pName
   set the rect of field pName to pRect
   set the text of field pName to empty
   set the backgroundColor of field pName to demoColor("panel")
   set the foregroundColor of field pName to demoColor("text")
   set the borderColor of field pName to demoColor("border")
   set the borderWidth of field pName to 1
   set the threeD of field pName to false
   set the opaque of field pName to true
   set the lockText of field pName to false
   set the textFont of field pName to kMono
   set the dontWrap of field pName to false
   set the vScrollbar of field pName to true
end demoMakeEditor

private command demoMakeButton pName, pRect, pLabel
   create button pName
   set the rect of button pName to pRect
   set the label of button pName to pLabel
   set the style of button pName to "rectangle"
end demoMakeButton

-- ==========================================================================
-- Chrome: header bar, tab strip, and the persistent bottom status bar.
-- ==========================================================================

private command demoBuildChrome
   demoMakeRect "chrome:header", "0,0," & kWinWidth & ",46", "header"
   demoMakeTitle "chrome:title", "24,10,520,38", "OnionXT demo"
   -- The title/subtitle sit ON the dark header, so their backgrounds must be the
   -- header colour, not the light window bg, or light text lands on a light box.
   set the backgroundColor of field "chrome:title" to demoColor("header")
   set the foregroundColor of field "chrome:title" to demoColor("headerText")
   demoMakeLabel "chrome:subtitle", "360,14,796,38", "Tor transport + self-authenticating rendezvous"
   set the backgroundColor of field "chrome:subtitle" to demoColor("header")
   set the foregroundColor of field "chrome:subtitle" to demoColor("statusText")
   set the textAlign of field "chrome:subtitle" to "right"

   local tNames, tI, tKey, tX, tSaved
   put "Status,Dial,Service,Address,About" into tNames
   put 24 into tX
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of items of kDemoTabs
      put item tI of kDemoTabs into tKey
      demoMakeButton "tabbtn:" & tKey, tX & ",54," & (tX + 112) & ",84", item tI of tNames
      add 118 to tX
   end repeat
   set the itemDelimiter to tSaved

   -- The bottom status bar is chrome (never in a tab list), so it stays visible
   -- on every tab and gives constant feedback about the tor connection.
   demoMakeRect "chrome:statusrect", "0," & (kWinHeight - 44) & "," & kWinWidth & "," & kWinHeight, "statusbar"
   demoMakeLabel "chrome:statusbar", "24," & (kWinHeight - 34) & ",796," & (kWinHeight - 10), ""
   set the backgroundColor of field "chrome:statusbar" to demoColor("statusbar")
   set the foregroundColor of field "chrome:statusbar" to demoColor("statusText")

   demoRestyleTabs
end demoBuildChrome

private command demoShowTab pKey
   -- Show the chosen tab's controls, hide every other tab's, by name (no groups).
   local tI, tCandidate, tSaved, tJ, tCtrl
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of items of kDemoTabs
      put item tI of kDemoTabs into tCandidate
      repeat with tJ = 1 to the number of items of sTabControls[tCandidate]
         put item tJ of sTabControls[tCandidate] into tCtrl
         set the visible of control tCtrl to (tCandidate is pKey)
      end repeat
   end repeat
   set the itemDelimiter to tSaved
   put pKey into sTab
   demoRestyleTabs
end demoShowTab

private command demoRestyleTabs
   local tI, tKey, tSaved
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of items of kDemoTabs
      put item tI of kDemoTabs into tKey
      if tKey is sTab then
         set the backgroundColor of button ("tabbtn:" & tKey) to demoColor("accent")
         set the foregroundColor of button ("tabbtn:" & tKey) to "255,255,255"
      else
         set the backgroundColor of button ("tabbtn:" & tKey) to demoColor("tabIdle")
         set the foregroundColor of button ("tabbtn:" & tKey) to demoColor("text")
      end if
   end repeat
   set the itemDelimiter to tSaved
end demoRestyleTabs

-- ==========================================================================
-- The status bar and button-enable logic: the flow's feedback, updated from the
-- callbacks so the UI always reflects the real connection state.
-- ==========================================================================

private command demoUpdateStatusBar
   local tState, tColor
   put sConnState into tState
   if tState is empty then
      put "disconnected" into tState
   end if
   if tState is "authenticated" then
      put "ok" into tColor
   else if tState is "failed" then
      put "fail" into tColor
   else
      put "statusText" into tColor
   end if
   put "Tor control: " & tState & "     Bootstrap: " & sBootPct & "%" into field "chrome:statusbar"
   set the foregroundColor of field "chrome:statusbar" to demoColor(tColor)
end demoUpdateStatusBar

private command demoUpdateButtons
   -- Enable each action only when it is currently valid, so a disabled button
   -- (which cannot be clicked) tells the user what to do next.
   local tConnected
   put (sConnState is not "disconnected" and sConnState is not "failed" and sConnState is not empty) into tConnected
   set the enabled of button "stat:connect" to (not tConnected)
   set the enabled of button "stat:disconnect" to tConnected
   set the enabled of button "svc:page" to oxIsControlAuthenticated()
   set the enabled of button "svc:folder" to oxIsControlAuthenticated()
   set the enabled of button "svc:remove" to (sSvcHandle is not empty)
   set the enabled of button "dial:send" to (sDialOpen is true)
end demoUpdateButtons

private command demoSetStatus pField, pText, pColorName
   set the foregroundColor of field pField to demoColor(pColorName)
   put pText into field pField
end demoSetStatus

private function demoConnectHint pMsg
   -- A raw socket-connect failure is cryptic (Windows reports WSAECONNREFUSED as
   -- "Error 10061"; other platforms say "connection refused"). All of them mean
   -- the same thing: nothing is listening on that port. Add one actionable line
   -- pointing at the always-visible torrc reference so the demo guides the fix.
   if "10061" is in pMsg or "refused" is in pMsg or "connection" is in pMsg then
      return pMsg & return & \
         "Connection refused: no tor daemon on that port. Start tor and enable the control port (torrc reference below); Tor Browser uses 9151."
   end if
   return pMsg
end demoConnectHint

private function demoListenHint pMsg
   -- A failed local listen is cryptic too. Error 10013 (Windows WSAEACCES) on a
   -- listen almost always means the local port is RESERVED or blocked by the OS
   -- (Hyper-V / WSL2 / Docker reserve whole port ranges), NOT that another app has
   -- it (that is 10048). Either way, the fix is a different local port.
   if "10013" is in pMsg or "cannot listen" is in pMsg or "10048" is in pMsg then
      return pMsg & return & \
         "The local port is reserved or blocked by the OS (common on Windows with Hyper-V/WSL/Docker). Change 'Local port' to another value (e.g. 8090) and Publish again; leave Virtual port at 80."
   end if
   return pMsg
end demoListenHint

private command demoAppendLog pField, pText
   -- Append a line and scroll to the bottom (formattedHeight is the full content
   -- height; setting scroll past the max clamps to the bottom).
   put pText & return after field pField
   set the scroll of field pField to the formattedHeight of field pField
end demoAppendLog

-- ==========================================================================
-- Tab: Status. Connects the ONE shared control connection every other tab relies
-- on (docs/03, 07). The bottom status bar shows live bootstrap / control state.
-- ==========================================================================

private command demoBuildStatusTab
   demoMakeTitle "stat:title", "24,100,796,124", "1. Connect to the tor control port"
   demoMakeHint "stat:hint", "24,128,796,150", \
      "Start here. Publishing an onion service and reading bootstrap progress need this connection."
   demoMakeLabel "stat:socksLbl", "24,166,124,188", "SOCKS port:"
   demoMakeInput "stat:socks", "128,163,220,189", kDemoDefaultSocksPort, ""
   demoMakeLabel "stat:ctlLbl", "240,166,344,188", "Control port:"
   demoMakeInput "stat:ctl", "348,163,440,189", kDemoDefaultControlPort, ""
   demoMakeButton "stat:connect", "468,161,588,191", "Connect"
   demoMakeButton "stat:disconnect", "596,161,716,191", "Disconnect"
   demoMakeLabel "stat:detail", "24,206,796,262", "not connected"
   demoMakeLabel "stat:version", "24,268,796,290", "version: " & oxVersion()
   demoMakeHint "stat:torrc", "24,300,796,408", \
      "Needs a tor daemon reachable on loopback. Reference torrc:" & return & \
      "    SocksPort 9050" & return & "    ControlPort 9051" & return & \
      "    CookieAuthentication 1" & return & \
      "(Tor Browser uses SOCKS 9150, control 9151, and needs the control port enabled.)"

   demoRegisterTab "stat", \
      "title,hint,socksLbl,socks,ctlLbl,ctl,connect,disconnect,detail,version,torrc"
end demoBuildStatusTab

private command handleStat pRole
   if pRole is "connect" then
      local tError
      oxSetSocksPort field "stat:socks"
      oxSetControlPort field "stat:ctl"
      put "connecting" into sConnState
      demoSetStatus "stat:detail", "connecting to 127.0.0.1:" & (field "stat:ctl") & " ...", "muted"
      demoUpdateStatusBar
      demoUpdateButtons
      oxConnectControl
      put the result into tError
      if tError is not empty then
         put "failed" into sConnState
         demoSetStatus "stat:detail", demoConnectHint(tError), "fail"
         demoUpdateStatusBar
         demoUpdateButtons
      end if
   else if pRole is "disconnect" then
      oxDisconnectControl
      put "disconnected" into sConnState
      put 0 into sBootPct
      demoSetStatus "stat:detail", "disconnected", "muted"
      demoUpdateStatusBar
      demoUpdateButtons
   end if
end handleStat

-- ==========================================================================
-- Tab: Dial. Outbound SOCKS5 through Tor (docs/02): dial, then send/receive once
-- the "open" stream event arrives. Needs a running tor SOCKS proxy, not control.
-- ==========================================================================

private command demoBuildDialTab
   demoMakeTitle "dial:title", "24,100,796,124", "Dial a host through Tor (SOCKS5)"
   demoMakeHint "dial:hint", "24,128,796,150", \
      "The far end never sees your IP. The name is resolved inside Tor (ATYP=3), never locally."
   demoMakeLabel "dial:hostLbl", "24,166,74,188", "Host:"
   demoMakeInput "dial:host", "80,163,600,189", kDemoDefaultDialHost, "mono"
   demoMakeLabel "dial:portLbl", "616,166,658,188", "Port:"
   demoMakeInput "dial:port", "662,163,748,189", kDemoDefaultDialPort, ""
   demoMakeButton "dial:go", "24,199,148,229", "Dial"
   demoMakeLabel "dial:status", "160,203,796,227", "not dialed"
   demoMakeLabel "dial:msgLbl", "24,241,120,263", "Request:"
   demoMakeInput "dial:msg", "124,238,648,300", "GET / HTTP/1.0" & return & return, "mono"
   demoMakeButton "dial:send", "664,238,784,268", "Send"
   demoMakeLog "dial:log", "24,312,796,500"

   demoRegisterTab "dial", \
      "title,hint,hostLbl,host,portLbl,port,go,status,msgLbl,msg,send,log"
end demoBuildDialTab

private command handleDial pRole
   if pRole is "go" then
      demoStartDial
   else if pRole is "send" then
      demoSendDial
   end if
end handleDial

private command demoStartDial
   local tHandle
   put false into sDialOpen
   put empty into field "dial:log"
   demoSetStatus "dial:status", "dialing " & (field "dial:host") & " ...", "muted"
   demoUpdateButtons
   oxDial field "dial:host", (field "dial:port")
   put the result into tHandle
   if tHandle is an integer then
      put tHandle into sDialStream
      oxSetStreamCallback sDialStream, "onDialStream"
   else
      put empty into sDialStream
      demoSetStatus "dial:status", tHandle, "fail"
   end if
end demoStartDial

private command demoSendDial
   if not sDialOpen then
      demoSetStatus "dial:status", "the tunnel is not open yet", "warn"
      exit demoSendDial
   end if
   -- Convert the request's line endings to CRLF (what HTTP wants) and send it as
   -- bytes. OnionXT does not encrypt; a real protocol would seal with SodiumXT.
   local tRequest
   put field "dial:msg" into tRequest
   replace return with (numToChar(13) & numToChar(10)) in tRequest
   oxWrite sDialStream, textEncode(tRequest, "UTF-8")
   demoAppendLog "dial:log", "> sent " & (the number of bytes of textEncode(tRequest, "UTF-8")) & " bytes"
end demoSendDial

-- The Dial tab's stream callback. Stale-guard against a handle that has already
-- moved on (the app may have redialed since this event was queued).
on onDialStream pStream, pEvent, pData
   if pStream is not sDialStream then
      exit onDialStream
   end if
   if pEvent is "open" then
      put true into sDialOpen
      demoSetStatus "dial:status", "tunnel open - send your request", "ok"
      demoUpdateButtons
   else if pEvent is "data" then
      demoAppendLog "dial:log", textDecode(pData, "UTF-8")
   else if pEvent is "closed" then
      put false into sDialOpen
      put empty into sDialStream
      demoSetStatus "dial:status", "connection closed", "muted"
      demoAppendLog "dial:log", "-- closed --"
      demoUpdateButtons
   else if pEvent is "error" then
      put false into sDialOpen
      put empty into sDialStream
      demoSetStatus "dial:status", pData, "fail"
      demoUpdateButtons
   end if
end onDialStream

-- ==========================================================================
-- Tab: Service. HOST over Tor via onion-httpd (oxh*): publish a v3 onion (docs/03/
-- 04) and either serve the editable HTML page (page mode) or share a folder as a
-- browsable, auto-listed file share (folder mode). onion-httpd owns the inbound
-- accept / parse / reply / close; the demo only supplies the page route and the
-- folder. Both modes live at the SAME .onion and switch without republishing.
-- Requires the Status tab's control connection to be authenticated.
-- ==========================================================================

private command demoBuildServiceTab
   demoMakeTitle "svc:title", "24,100,796,124", "Host over Tor: serve a page or share a folder (view in Tor Browser)"
   demoMakeHint "svc:hint", "24,128,796,158", \
      "Needs an authenticated control connection (Status tab). 'Serve page' hosts the HTML below; 'Share folder' shares a folder as a browsable file list. Both answer at http://<address>.onion/ (leave the virtual port at 80)."
   demoMakeLabel "svc:vLbl", "24,170,116,192", "Virtual port:"
   demoMakeInput "svc:vport", "120,167,200,193", 80, ""
   demoMakeLabel "svc:lLbl", "216,170,304,192", "Local port:"
   demoMakeInput "svc:lport", "308,167,390,193", 8090, ""
   demoMakeButton "svc:page", "400,165,520,195", "Serve page"
   demoMakeButton "svc:folder", "528,165,660,195", "Share folder"
   demoMakeButton "svc:remove", "668,165,786,195", "Remove"
   demoMakeLabel "svc:status", "24,206,796,228", "not published"
   demoMakeLabel "svc:addrLbl", "24,236,116,258", "Address:"
   demoMakeValue "svc:address", "120,233,796,259"
   demoMakeLabel "svc:htmlLbl", "24,266,796,286", "Page for 'Serve page' mode ({{ADDRESS}} becomes the live address). 'Share folder' serves a file list instead."
   demoMakeEditor "svc:html", "24,288,796,398"
   put demoDefaultHtml() into field "svc:html"
   demoMakeLog "svc:log", "24,408,796,500"

   demoRegisterTab "svc", \
      "title,hint,vLbl,vport,lLbl,lport,page,folder,remove,status,addrLbl,address,htmlLbl,html,log"
end demoBuildServiceTab

private command handleSvc pRole
   if pRole is "page" then
      demoServePageMode
   else if pRole is "folder" then
      demoShareFolderMode
   else if pRole is "remove" then
      demoRemoveService
   end if
end handleSvc

private command demoServePageMode
   if not oxIsControlAuthenticated() then
      demoSetStatus "svc:status", "connect and authenticate on the Status tab first", "warn"
      exit demoServePageMode
   end if
   -- Page mode: demoServePage answers "/" with the editable HTML (so {{ADDRESS}} is
   -- substituted live at request time). Clear any static-folder root so the route
   -- wins, and register the route.
   put "page" into sSvcMode
   oxhSetRoot empty
   oxhRoute "GET", "/", "demoServePage"
   demoPublishOrSwitch "serving the edited page"
end demoServePageMode

private command demoShareFolderMode
   local tFolder
   if not oxIsControlAuthenticated() then
      demoSetStatus "svc:status", "connect and authenticate on the Status tab first", "warn"
      exit demoShareFolderMode
   end if
   answer folder "Choose a folder to share over Tor"
   put it into tFolder
   if tFolder is empty then
      exit demoShareFolderMode      -- cancelled
   end if
   -- Folder mode: onion-httpd serves every file plus an auto directory listing.
   -- Drop the page route so "/" shows the listing, not the page.
   put "folder" into sSvcMode
   oxhUnroute "GET", "/"
   oxhServeFiles tFolder
   demoAppendLog "svc:log", "sharing folder: " & tFolder
   demoPublishOrSwitch "sharing that folder"
end demoShareFolderMode

private command demoPublishOrSwitch pWhat
   -- Publish the onion the FIRST time; after that a mode/root change is live at the
   -- SAME .onion (onion-httpd just serves differently), so there is no republish and
   -- the address does not change. Reports the handle through `the result` (oxhServe).
   local tHandle
   if sSvcHandle is an integer then
      demoAppendLog "svc:log", "now " & pWhat & " (live at the same .onion)"
      demoSetStatus "svc:status", "reachable - " & pWhat, "ok"
      exit demoPublishOrSwitch
   end if
   demoSetStatus "svc:status", "publishing ...", "muted"
   put empty into field "svc:address"
   oxhServe (field "svc:vport"), (field "svc:lport")
   put the result into tHandle
   if tHandle is an integer then
      put tHandle into sSvcHandle
      demoAppendLog "svc:log", "service handle " & tHandle & " requested; awaiting ADD_ONION reply ..."
      demoUpdateButtons
   else
      demoSetStatus "svc:status", "publish failed (see log)", "fail"
      demoAppendLog "svc:log", demoListenHint(tHandle)
   end if
end demoPublishOrSwitch

private command demoRemoveService
   if sSvcHandle is not empty then
      oxhStop sSvcHandle      -- onion-httpd: DEL_ONION + stop OnionXT's listener
      demoAppendLog "svc:log", "removed service " & sSvcHandle
   end if
   put empty into sSvcHandle
   put empty into sSvcMode
   put empty into field "svc:address"
   demoSetStatus "svc:status", "not published", "muted"
   demoUpdateButtons
end demoRemoveService

-- The "/" route handler for page mode. onion-httpd dispatches it through the
-- message path (oxhInit named this stack the owner), so it is a PUBLIC command,
-- not private. onion-httpd owns the request framing and the clean, delayed close;
-- the demo only builds the body, substituting the live address for {{ADDRESS}}.
command demoServePage pStream, pRequest
   local tBody
   put field "svc:html" into tBody
   if tBody is empty then
      put demoDefaultHtml() into tBody
   end if
   replace "{{ADDRESS}}" with (field "svc:address") in tBody
   demoAppendLog "svc:log", "served the page to a visitor"
   oxhReply pStream, 200, tBody, "Content-Type: text/html; charset=utf-8"
end demoServePage

private function demoDefaultHtml
   -- A small self-contained page. HTML attributes use SINGLE quotes on purpose:
   -- livecodescript string literals are double-quote-delimited with no escape, so a
   -- double quote cannot appear inside one; HTML accepts single-quoted attributes.
   local tH
   put "<!doctype html>" & return into tH
   put "<html>" & return after tH
   put "<head><meta charset='utf-8'><title>OnionXT onion service</title></head>" & return after tH
   put "<body style='font-family:system-ui,sans-serif;max-width:38em;margin:3em auto;padding:0 1em;line-height:1.5'>" & return after tH
   put "<h1>It works.</h1>" & return after tH
   put "<p>This page is served by an <strong>OnionXT</strong> demo onion service running inside an OpenXTalk / LiveCode app - no web server, no port forwarding, and no DNS.</p>" & return after tH
   put "<p>You reached it at its self-authenticating v3 address:</p>" & return after tH
   put "<pre style='white-space:pre-wrap;word-break:break-all;background:#f4f6fa;padding:.6em;border-radius:.4em'>{{ADDRESS}}</pre>" & return after tH
   put "<p>That address is an ed25519 public key, so reaching it proved you connected to the holder of that key - no certificate authority involved.</p>" & return after tH
   put "</body></html>" & return after tH
   return tH
end demoDefaultHtml

-- ==========================================================================
-- Tab: Address. Pure, offline helpers (docs/04): base32 + the address<->key
-- mapping. No network, no tor daemon needed.
-- ==========================================================================

private command demoBuildAddressTab
   demoMakeTitle "addr:title", "24,100,796,124", "Address tools (pure, no network)"
   demoMakeHint "addr:hint", "24,128,796,150", \
      "A v3 .onion address IS an ed25519 public key. Decoding needs no crypto; re-encoding needs SodiumXT SHA3-256 (deferred)."
   demoMakeLabel "addr:pasteLbl", "24,166,150,188", "Onion address:"
   demoMakeInput "addr:paste", "158,163,636,189", kDemoKnownAddress, "mono"
   demoMakeButton "addr:decode", "652,161,772,191", "Decode"
   demoMakeLabel "addr:pubLbl", "24,206,150,228", "Public key:"
   demoMakeValue "addr:pubkey", "158,203,796,229"
   demoMakeButton "addr:encode", "24,239,224,269", "Re-encode from key"
   demoMakeValue "addr:reencoded", "236,240,796,266"
   demoMakeLabel "addr:valid", "24,284,796,322", ""

   demoRegisterTab "addr", \
      "title,hint,pasteLbl,paste,decode,pubLbl,pubkey,encode,reencoded,valid"
end demoBuildAddressTab

private command handleAddr pRole
   if pRole is "decode" then
      demoDecodeAddress
   else if pRole is "encode" then
      demoEncodeAddress
   end if
end handleAddr

private command demoDecodeAddress
   local tAddress, tPub
   put field "addr:paste" into tAddress
   put oxPublicKeyFromAddress(tAddress) into tPub
   if the number of bytes of tPub is 32 then
      put demoBytesToHex(tPub) into field "addr:pubkey"
   else
      put "(not a structurally valid v3 address)" into field "addr:pubkey"
   end if
   if oxIsValidAddress(tAddress) then
      demoSetStatus "addr:valid", "structurally valid (checksum also verified when SodiumXT SHA3-256 is available)", "ok"
   else
      demoSetStatus "addr:valid", "not a valid v3 onion address", "fail"
   end if
end demoDecodeAddress

private command demoEncodeAddress
   local tPubHex, tAddr
   put field "addr:pubkey" into tPubHex
   if the number of chars of tPubHex is not 64 then
      put empty into field "addr:reencoded"
      demoSetStatus "addr:valid", "decode an address above first, or paste a 64-hex-char public key", "warn"
      exit demoEncodeAddress
   end if
   -- Re-encode needs the SHA3-256 checksum (SodiumXT gap #2, deferred), so a
   -- capability error comes back as an "OnionXT:" string, not an address. Route
   -- it to the wrapping status line instead of the cramped single-line field.
   put oxAddressFromPublicKey(binaryEncode("H*", tPubHex)) into tAddr
   if tAddr begins with "OnionXT:" then
      put empty into field "addr:reencoded"
      demoSetStatus "addr:valid", tAddr, "warn"
   else
      put tAddr into field "addr:reencoded"
      demoSetStatus "addr:valid", "re-encoded; matches the pasted address when the key is unchanged", "ok"
   end if
end demoEncodeAddress

-- ==========================================================================
-- Tab: About. Version, the composition story, capability flags, and the
-- self-test entry point.
-- ==========================================================================

private command demoBuildAboutTab
   demoMakeTitle "about:title", "24,100,796,124", "OnionXT " & oxVersion()
   demoMakeHint "about:blurb", "24,130,796,224", \
      "A Tor transport and self-authenticating rendezvous layer for OXT / LiveCode." & return & \
      "Adds no cryptography of its own: it composes SodiumXT (ABI >= 6) for the" & return & \
      "seed-derived onion key and SAFECOOKIE HMAC, and assumes a locally-running tor" & return & \
      "daemon. Status: designed and statically reasoned; needs an on-engine pass."
   demoMakeLabel "about:capsLbl", "24,232,796,254", "Capabilities (oxTransportInfo):"
   demoMakeLog "about:caps", "24,258,796,352"
   demoMakeButton "about:runTests", "24,362,224,392", "Run self-test"
   demoMakeLog "about:testlog", "24,400,796,500"

   demoRegisterTab "about", "title,blurb,capsLbl,caps,runTests,testlog"
   demoShowCapabilities
end demoBuildAboutTab

private command demoShowCapabilities
   local tInfo, tOut
   put oxTransportInfo() into tInfo
   put "transport           : " & tInfo["transport"] & return into tOut
   put "version             : " & tInfo["version"] & return after tOut
   put "safeCookieAuth      : " & tInfo["safeCookieAuth"] & "   (SodiumXT sxHmacSha256 + sxRandomBytes)" & return after tOut
   put "deterministicOnion  : " & tInfo["deterministicOnion"] & "   (SodiumXT sxSignSeedToExpandedKey)" & return after tOut
   put "offlineAddress      : " & tInfo["offlineAddress"] & "   (SodiumXT sxSha3_256, deferred gap #2)" after tOut
   put tOut into field "about:caps"
end demoShowCapabilities

private command handleAbout pRole
   if pRole is "runTests" then
      demoRunSelfTest
   end if
end handleAbout

private command demoRunSelfTest
   -- The full suite lives in the sibling onionxt-tests.livecodescript, started
   -- using as a library so oxSelfTest resolves through the normal message path.
   -- Detect it missing the same way the library capability-gates SodiumXT.
   local tReport
   dispatch function "oxSelfTest"
   if it is "unhandled" then
      put "onionxt-tests.livecodescript is not loaded; start using it alongside this demo to run the self-test." into field "about:testlog"
      exit demoRunSelfTest
   end if
   put the result into tReport
   put tReport into field "about:testlog"
   set the scroll of field "about:testlog" to 0
end demoRunSelfTest

-- ==========================================================================
-- Shared status callback: control state, bootstrap, and service readiness. Drives
-- the always-visible status bar and the button-enable logic, so background events
-- (which may arrive while you are on another tab) always update the UI.
-- ==========================================================================

on onStatus pKind, pInfo
   if pKind is "control" then
      if pInfo is "authenticated" then
         put "authenticated" into sConnState
         demoSetStatus "stat:detail", "authenticated - ready", "ok"
         put "version: " & oxVersion() into field "stat:version"
      else if pInfo begins with "authfailed" or pInfo begins with "error" then
         put "failed" into sConnState
         demoSetStatus "stat:detail", demoConnectHint(pInfo), "fail"
      else if pInfo is "disconnected" then
         put "disconnected" into sConnState
         demoSetStatus "stat:detail", "disconnected", "muted"
      else
         put pInfo into sConnState
         demoSetStatus "stat:detail", pInfo, "muted"
      end if
      demoUpdateStatusBar
      demoUpdateButtons
   else if pKind is "bootstrap" then
      put pInfo into sBootPct
      demoUpdateStatusBar
   else if pKind is "ready" then
      put 100 into sBootPct
      demoUpdateStatusBar
   else if pKind is "service" then
      put pInfo into field "svc:address"
      demoSetStatus "svc:status", "published, awaiting descriptor upload ...", "warn"
      demoAppendLog "svc:log", "address: " & pInfo
   else if pKind is "serviceReady" then
      demoSetStatus "svc:status", "reachable - open it in Tor Browser now", "ok"
      demoAppendLog "svc:log", "descriptor uploaded; the onion is reachable"
      demoAppendLog "svc:log", "open  http://" & (field "svc:address") & "/  in Tor Browser (keep this demo running)"
   else if pKind is "notice" then
      -- Library diagnostics (e.g. every accepted connection's raw socket id, so a
      -- misparse or a rejected loopback peer is visible in the Service log).
      demoAppendLog "svc:log", pInfo
   end if
end onStatus

-- ==========================================================================
-- Central click router: parse "prefix:role" from the clicked control's short name
-- and dispatch to that tab's handler. Disabled buttons never reach here.
-- ==========================================================================

on mouseUp
   local tName, tPrefix, tRole, tSaved
   put the short name of the target into tName
   if tName begins with "tabbtn:" then
      demoShowTab (char 8 to -1 of tName)
      exit mouseUp
   end if
   if "chrome:" is in tName then
      exit mouseUp
   end if
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   put item 1 of tName into tPrefix
   put item 2 to -1 of tName into tRole
   set the itemDelimiter to tSaved

   if tPrefix is "stat" then
      handleStat tRole
   else if tPrefix is "dial" then
      handleDial tRole
   else if tPrefix is "svc" then
      handleSvc tRole
   else if tPrefix is "addr" then
      handleAddr tRole
   else if tPrefix is "about" then
      handleAbout tRole
   end if
end mouseUp

-- Free everything OnionXT opened when the demo closes (there is no deterministic
-- unload hook; the app frees what it opened, CLAUDE.md).
on closeStack
   oxShutdown
   pass closeStack
end closeStack

-- ==========================================================================
-- Small local helpers (demo glue only, not part of the ox* surface).
-- ==========================================================================

private command demoRegisterTab pTabKey, pRoleList
   -- Record this tab's full control names ("prefix:role") in sTabControls and hide
   -- them; demoShowTab toggles their visibility. No groups, no reparenting.
   local tI, tRole, tSaved, tNames, tCtrl
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put empty into tNames
   repeat with tI = 1 to the number of items of pRoleList
      put item tI of pRoleList into tRole
      put pTabKey & ":" & tRole into tCtrl
      if tNames is empty then
         put tCtrl into tNames
      else
         put comma & tCtrl after tNames
      end if
      set the visible of control tCtrl to false
   end repeat
   put tNames into sTabControls[pTabKey]
   set the itemDelimiter to tSaved
end demoRegisterTab

private function demoBytesToHex pData
   -- binaryDecode is a function that fills its output var; `get` discards the
   -- count (this is how the library's own oxBytesToHex works).
   local tHex
   get binaryDecode("H*", pData, tHex)
   return tHex
end demoBytesToHex
