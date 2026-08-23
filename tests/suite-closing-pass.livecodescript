script "suiteClosingPass"

-- suite-closing-pass.livecodescript - ONE stack for the remaining runbook
-- legs. Install the suite on two machines, paste this on both, and each
-- section prints PASS lines as its leg closes. It exists so the closing
-- sessions are a checklist, not an expedition.
--
-- THE LEGS (and the runbook items they close):
--   A  DataChannel local async (single machine): the member harness's still
--      -static live halves - live dcSendText, dcBufferedAmount, gathering
--      state 2, selected candidate pair, the dcBufferedLow event, the
--      a=candidate/role pins.
--   B  ENet chat between two machines (item 6, enetxt's last leg).
--   C  Torrent seed/leech with a hash-verified payload, plus resume saved
--      to DISK and re-added - across an OXT restart if you quit between
--      the save and the resume (item 6 + the plan's resume gate).
--   D  rp1 chat between two machines over a DHT rendezvous (item 6).
--   E  DataChannel chat with the WebRTC handshake carried as signed BEP44
--      items over the real DHT (item 6; cross-NAT capable - the selected
--      pair line records host vs srflx).
--   F  Tor, single machine: Mode B (oxLaunchTor against a real tor binary,
--      item 4) and a live onion ECHO - listen, dial your own onion through
--      the Tor network, exact bytes both ways (live evidence for the
--      oxTransport* handlers). Quick Share Model C (item 5) stays the
--      quickshare demo's own run.
--
-- HONESTY (the suite convention): this stack is verified statically and
-- needs its OXT passes - each PASS line below is the evidence to record.
-- Every handler it calls is individually engine-proven except the seven
-- live-Tor ones section F exists to close.
--
-- SETUP, per machine: install sodiumxt + torrentxt + enetxt +
-- datachannelxt (packaged). NOTHING ELSE TO WIRE - the ox* layer for section
-- F is CARRIED inside this file (tools/sync-demo-embeds.py, since
-- 2026-08-17), so this is one paste. These lines used to say "for section F
-- put the onionxt library in the message path (start using stack
-- onionxt)", which had been false for three days short of a year's worth of
-- engine sessions and would load a SECOND copy of every ox* handler.
-- ONE torrent session per process (runbook trap 5.1): close every other
-- torrent-flavoured stack, and restart OXT before any re-paste of this
-- script.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here.

-- ---- constants ---------------------------------------------------------------

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- onionxt/src/onionxt.livecodescript ----
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
   local tHandle, tPrior
   put sLocalToService[pLocalPort] into tPrior
   if tPrior is not empty and sServices[tPrior]["localPort"] is not empty then
      -- Fail closed: a second service on an in-use local port would overwrite
      -- the port-to-service mapping, and removing either service would then
      -- close (or orphan) the shared listener out from under the other, so Tor
      -- keeps forwarding to a dead port - which looks exactly like a broken
      -- onion. One local port, one service; pick another local port.
      -- (Verified statically; needs an OXT pass.)
      return "OnionXT: local port " & pLocalPort & " already forwards for another service (one service per local port; pick another local port)"
   end if
   if tPrior is not empty then
      -- The mapping is stale (its service is gone); reclaim it and rebind below.
      delete variable sLocalToService[pLocalPort]
   end if
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
      -- the listener may be bound to all interfaces). Print the RAW id next to
      -- the parsed host, because since oxHostIsLoopback stopped treating an
      -- unparseable id as loopback this notice is also how a socket-id spelling
      -- oxHostOfSocket does not know announces itself (it arrives here with an
      -- empty host); one self-contained line is what a tester can act on.
      oxStatusUpdate "notice", "rejected non-loopback peer host [" & tPeerHost & \
         "] from id [" & pSocketID & "]"
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
   -- Accept a Tor-forwarded peer no matter how the engine spells the local
   -- address in the accepted-socket id, and NOTHING else: `accept connections on
   -- port` takes no bind address (see oxStartService), so the listener may be
   -- reachable from the network and this is the only thing standing between a
   -- routable peer and our stream tables. Takes the host oxHostOfSocket parsed,
   -- so the brackets of "[::1]" are already gone and there is exactly one
   -- spelling of each address to test. Comparisons are case-insensitive by
   -- default, so "::FFFF:" matches "::ffff:" without folding anything.
   --
   -- EMPTY IS A REFUSAL NOW, and that is the point of this change rather than a
   -- side effect. It used to return true, with "some engines report no host for
   -- a local accept" as the reason - but the old parser handed this guard an
   -- empty string for EVERY IPv6-shaped id, so "the engine reported no host" and
   -- "we could not parse this id" were indistinguishable, and the permissive
   -- branch let "::ffff:203.0.113.9:1234" - a routable peer wearing an
   -- IPv4-mapped hat - in as loopback. A guard whose default is accept is a
   -- fail-open guard; CLAUDE.md rule 4 says fail closed on anything we do not
   -- understand. So an unrecognized spelling is refused and oxPeerAccepted
   -- prints the RAW id alongside the parsed host: if a real engine is ever seen
   -- spelling an accepted id with no host at all (or with the fully expanded
   -- "0:0:0:0:0:0:0:1"), the fix is to teach oxHostOfSocket that spelling, never
   -- to re-open this branch.
   local tHost
   put pHost into tHost
   if tHost is empty then
      return false
   end if
   if tHost is kOxHost then
      return true
   end if
   if tHost begins with "127." then
      return true
   end if
   if tHost is "::1" then
      return true
   end if
   if tHost begins with "::ffff:" then
      -- The IPv4-mapped form a dual-stack listener can report. It is the SAME
      -- address with a prefix, so strip it and re-test the v4 rules: that admits
      -- "::ffff:127.0.0.1" (genuinely loopback, and unroutable) and refuses
      -- "::ffff:203.0.113.9" (genuinely routable), which the old empty-item-1
      -- parse could not tell apart.
      delete char 1 to 7 of tHost
      if tHost is kOxHost or tHost begins with "127." then
         return true
      end if
      return false
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
   -- QUOTE BOTH PATHS. The command line is split on whitespace, so an unquoted
   -- "C:/Program Files/Tor/tor.exe" arrives as the two arguments "C:/Program"
   -- and "Files/Tor/tor.exe" and the launch fails - and a data directory under
   -- "Application Support" or a user folder with a space in the name is the
   -- normal case on Windows and macOS, not an edge case. The same applies to
   -- the torrc path, which is derived from pDataDir.
   -- VERIFY: process launch and teardown on your target OXT build.
   open process (quote & pTorPath & quote & " -f " & quote & tRcPath & quote) for read
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
   -- Composed since SodiumXT ABI 7 (docs/08 gap #2, closed 2026-08-11):
   -- sxSha3_256 is the vendored FIPS-202 primitive SodiumXT ships precisely
   -- for this checksum. Against an older installed SodiumXT the absent handler
   -- still raises here and degrades to the clear capability error below. The
   -- checksum is a nicety, not a security dependency (tor authenticates the
   -- onion at connect time), so callers degrade to structural-only checks.
   local tOut
   try
      put sxSha3_256(pData) into tOut
   catch tError
      return "OnionXT: the offline .onion checksum needs SodiumXT SHA3-256 (sxSha3_256, ABI 7+; this SodiumXT predates it - docs/08 #2)"
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
   -- Capability probe: true on SodiumXT ABI 7+ (sxSha3_256 shipped 2026-08-11,
   -- docs/08 #2 CLOSED); false only against an older installed SodiumXT.
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
   -- The HOST part of an engine socket id: "host:port", optionally with a
   -- "|name" suffix (we mint "127.0.0.1:9050|oxs3" ourselves; an ACCEPTED id is
   -- whatever the engine spells the PEER address as, so its shape is the
   -- engine's choice, not ours).
   --
   -- This is security-critical input, not a display helper: oxPeerAccepted feeds
   -- the result straight to oxHostIsLoopback, which decides whether an inbound
   -- peer is let in. The obvious "item 1 with the itemDelimiter set to colon"
   -- was wrong in BOTH directions on an IPv6 id, and one of those directions
   -- FAILED OPEN:
   --   "::1:54321"                -> item 1 is EMPTY, and the guard's old
   --                                 empty-is-loopback branch accepted it;
   --   "::ffff:203.0.113.9:1234"  -> item 1 is EMPTY too, so a ROUTABLE peer in
   --                                 IPv4-mapped form was accepted as loopback;
   --   "[::1]:54321"              -> item 1 is "[", so a real loopback peer was
   --                                 refused (the harmless direction).
   -- Parse by SHAPE instead, which also makes the guard's "::1" branch reachable
   -- for the first time (it never could be: item 1 of anything containing a
   -- colon cannot itself contain one):
   --   1. drop any "|name" suffix - the name half is ours and never part of the
   --      host, and it can carry digits that would otherwise look like a port;
   --   2. a bracketed group IS the host, verbatim and unbracketed - the brackets
   --      exist precisely to separate an IPv6 host's colons from the port colon,
   --      and stripping them here means the guard sees ONE spelling of ::1;
   --   3. otherwise the host is everything up to the LAST colon, which is right
   --      for "127.0.0.1:9050" and for a bare "::1:54321" alike;
   --   4. a colon-less id has no port to strip, so it is all host.
   -- Anything this cannot make sense of comes back EMPTY, which oxHostIsLoopback
   -- now REFUSES (it used to accept it); that is the fail-closed direction.
   local tSaved, tRaw, tCut, tOut
   put pSocketID into tRaw
   put offset("|", tRaw) into tCut
   if tCut > 0 then
      delete char tCut to -1 of tRaw
   end if
   if char 1 of tRaw is "[" then
      put offset("]", tRaw) into tCut
      if tCut < 3 then
         return empty              -- unclosed or empty brackets: not a host
      end if
      return char 2 to (tCut - 1) of tRaw
   end if
   if ":" is not in tRaw then
      return tRaw
   end if
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   -- `item 1 to -2` REJOINS its items with the delimiter, which is exactly what
   -- a bare IPv6 host needs: the three empty/short items of "::1:54321" come
   -- back as "::1", while "127.0.0.1:9050" comes back unchanged.
   put item 1 to -2 of tRaw into tOut
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

-- <<< END EMBEDDED LIBRARIES <<<

constant kEnetPort = 27300
constant kEnetHello = "closing-pass hello"
constant kShareFolder = "closing-pass-share"
constant kPayloadFile = "payload.bin"
constant kResumeFile = "closing-pass.resume"
constant kSaltOffer = "cp-o"
constant kSaltAnswer = "cp-a"
constant kHeadMagic = "CP1C"
constant kChunkMax = 900
constant kPollMs = 250
constant kRefetchMs = 4000
constant kTorPing = "closing-pass-ping"

-- ==== SUITE UI KIT v2 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====
-- The family look as one carried block: the kit owns colors, chrome, and
-- control construction; the adopting demo owns layout (explicit rects) and
-- logic. Builders are idempotent (create-if-missing), so a rebuild on
-- reopen is safe. Do not edit this block in place: change the master and
-- re-carry it.
constant kUiBg = "240,242,246"
constant kUiCard = "255,255,255"
constant kUiCardLine = "225,229,236"
constant kUiAccent = "44,90,160"
constant kUiAccentText = "255,255,255"
constant kUiAccentSub = "199,216,241"
constant kUiInk = "28,34,46"
constant kUiInkSoft = "95,104,118"
constant kUiMuted = "138,146,158"
constant kUiOk = "23,128,63"
constant kUiWarn = "150,110,40"
constant kUiBad = "176,58,46"
constant kUiFieldLine = "203,210,222"
constant kUiCodeBg = "244,246,250"
constant kUiCodeLine = "210,217,229"

-- The platform's own terminal face for codes, keys, tables and logs, so
-- the monospace surfaces look native instead of typewriter-Courier. A
-- missing face substitutes the engine default - a soft, safe failure.
function uiMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end uiMonoFont

-- The window chrome every adopter shares: stack size, page ground, the
-- title band, and the one status line under it (write it with uiStatus).
-- pBandH is optional (default 30); a taller band leaves room for an
-- adopter's tagline or status pill, placed by the adopter.
command uiChrome pTitle, pWidth, pHeight, pBandH
   local tFH
   if pBandH is empty then
      put 30 into pBandH
   end if
   set the width of this stack to pWidth
   set the height of this stack to pHeight
   set the backgroundColor of this card to kUiBg
   set the title of this stack to pTitle
   uiGfx "uiBand", "0,0," & pWidth & "," & pBandH
   set the style of graphic "uiBand" to "rectangle"
   set the filled of graphic "uiBand" to true
   set the backgroundColor of graphic "uiBand" to kUiAccent
   set the lineSize of graphic "uiBand" to 0
   uiLabel "uiTitle", "  " & pTitle, "0,0," & pWidth & "," & pBandH, 15
   set the foregroundColor of field "uiTitle" to kUiAccentText
   set the textStyle of field "uiTitle" to "bold"
   -- center the title on the band midline by MEASURED height (never guess
   -- font metrics - the family's OXT passes clipped hand-sized labels)
   put the formattedHeight of field "uiTitle" into tFH
   if tFH > 0 and tFH < pBandH then
      set the height of field "uiTitle" to tFH
      set the top of field "uiTitle" to ((pBandH - tFH) div 2)
   end if
   uiLabel "uiStatus", empty, "16," & (pBandH + 4) & "," & (pWidth - 16) & "," & (pBandH + 22), 11
end uiChrome

-- The status line, colored by what it reports: "ok", "warn", "bad", or
-- anything else for neutral/muted. Demos route probe results through this
-- so a stack that cannot run says so in red, at the top, immediately.
command uiStatus pText, pKind
   -- PIN THE STACK, THEN CHECK THE FIELD EXISTS. Both halves were missing and
   -- both are load-bearing on a TIMER-driven call.
   --
   -- An unqualified `field "uiStatus"` resolves against the DEFAULTSTACK, not
   -- against the stack whose script is running. Inside openStack those are the
   -- same thing, which is why every demo's startup status line always worked.
   -- A handler arriving from `send ... in` has no such guarantee: with a second
   -- stack in front, the write lands in the wrong stack or resolves to nothing.
   --
   -- THE PIN RESTS ON THE DOCUMENTED RESOLUTION RULE, NOT ON A THROW WE SAW.
   -- This comment used to cite enet-lan-chat's once-a-second dashboard throwing
   -- "Chunk: error in object expression" REPEATEDLY on 2026-08-18, and dht-chat
   -- hiding the same fault behind a guard. Neither half held up: that throw was
   -- the ARGUMENT at the call site (`the number of keys of sPeers`, which does
   -- not parse - OXT-ENGINE-NOTES 1.7) and never reached uiStatus at all, and
   -- the guard credited to the kit was dht-chat's own wxSetStatus wrapper - the
   -- master had no existence check until the same commit that added this pin.
   -- What a guarded call site WOULD do if the defaultStack diverged is fail
   -- silently, which is the argument for a gate rather than for more guards.
   -- See OXT-ENGINE-NOTES 5.3, now classed DOCUMENTED.
   --
   -- The pin is holde-em's idiom, engine-proven there, and its comment names
   -- this exact hazard. The existence check stays as well: a demo may call the
   -- status line before its chrome is built, and a cosmetic line must never
   -- take down a poll chain.
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      exit uiStatus
   end if
   put pText into field "uiStatus"
   if pKind is "ok" then
      set the foregroundColor of field "uiStatus" to kUiOk
   else if pKind is "warn" then
      set the foregroundColor of field "uiStatus" to kUiWarn
   else if pKind is "bad" then
      set the foregroundColor of field "uiStatus" to kUiBad
   else
      set the foregroundColor of field "uiStatus" to kUiInkSoft
   end if
end uiStatus

-- A static caption at a FIXED rect (idempotent, borderless, transparent).
-- Use uiWrap instead when the text may wrap or the exact height matters.
command uiLabel pName, pText, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the threeD of field pName to false
   set the textSize of field pName to pSize
   set the foregroundColor of field pName to kUiInk
   put pText into field pName
end uiLabel

-- A caption FIT to its measured text height (top pinned). The fit does
-- double duty: it prevents clipping (hand-sized rects clipped text on a
-- real Windows pass), and it makes `the height of field` equal the TEXT
-- height, which midline centering relies on. GUARD: only resize on a sane
-- measurement - a 0/blank formattedHeight (possible before the window is
-- fully realized) would collapse the label. Empty labels are skipped
-- (they receive their text later).
command uiWrap pName, pText, pRect, pSize
   local tOldDelim, tTop, tFH
   uiLabel pName, pText, pRect, pSize
   if pText is not empty then
      put the itemDelimiter into tOldDelim
      set the itemDelimiter to comma
      put item 2 of pRect into tTop
      set the itemDelimiter to tOldDelim
      put the formattedHeight of field pName into tFH
      if tFH > 0 then
         set the height of field pName to tFH
         set the top of field pName to tTop
      end if
   end if
end uiWrap

-- A small, muted caption (hints, toggle descriptions, empty states).
command uiCap pName, pText, pRect
   uiWrap pName, pText, pRect, 10
   set the foregroundColor of field pName to kUiMuted
end uiCap

-- A numbered bold section header with a hairline divider placed below the
-- label's ACTUAL (fit-to-text) bottom, so it tracks the real header
-- height on any platform's line metrics.
command uiSection pName, pText, pRect
   local tOldDelim, tL, tR, tB
   uiWrap pName, pText, pRect, 13
   set the textStyle of field pName to "bold"
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 1 of pRect into tL
   put item 3 of pRect into tR
   set the itemDelimiter to tOldDelim
   put the bottom of field pName into tB
   uiGfx (pName & "Line"), (tL & comma & (tB + 1) & comma & tR & comma & (tB + 2))
   set the style of graphic (pName & "Line") to "rectangle"
   set the filled of graphic (pName & "Line") to true
   set the backgroundColor of graphic (pName & "Line") to kUiCardLine
   set the lineSize of graphic (pName & "Line") to 0
end uiSection

-- A one-line entry field, mono and flat ("modern input" chrome instead of
-- the engine's sunken-3D default), because hex, addresses and paths are
-- what this suite's demos edit.
command uiInput pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to false
   set the traversalOn of field pName to true
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiFieldLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   -- 4-item margins form ONLY: OXT ignored the single-number form on a
   -- real engine pass
   set the margins of field pName to "6,6,6,6"
   set the textSize of field pName to 11
   set the textFont of field pName to uiMonoFont()
end uiInput

-- A read-only output/log area: mono, flat, scrolling, hairline-bordered.
command uiArea pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiCardLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   set the margins of field pName to "6,6,6,6"
   set the vScrollbar of field pName to true
   set the textSize of field pName to 10
   set the textFont of field pName to uiMonoFont()
end uiArea

-- A row-selectable table: uiArea plus list behavior and tab stops
-- ("230,340"-style comma lists). Pair it with a uiLabel header carrying
-- the same tabStops, set by the adopter.
command uiTable pName, pRect, pTabStops
   uiArea pName, pRect
   set the listBehavior of field pName to true
   if pTabStops is not empty then
      set the tabStops of field pName to pTabStops
   end if
end uiTable

command uiButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end uiButton

-- A script-managed checkbox: autoHilite OFF because the family drives
-- toggle state from script locals (a mode the environment cannot honour
-- must never stay silently armed - the quickshare pill lesson), so the
-- hilite is set explicitly by the adopter's state machine.
command uiCheckbox pName, pLabel, pRect
   uiButton pName, pLabel, pRect
   set the style of button pName to "checkbox"
   set the autoHilite of button pName to false
end uiCheckbox

-- Create-or-reuse a named graphic: the chrome layer (cards, pills,
-- dividers, drop targets). Created BEFORE the controls that sit on it, so
-- it stays behind them in z-order. roundRect + antialiased by default;
-- callers restyle.
command uiGfx pName, pRect
   if there is no graphic pName then
      create graphic
      set the name of the last graphic to pName
   end if
   set the rect of graphic pName to pRect
   set the style of graphic pName to "roundRect"
   set the antialiased of graphic pName to true
end uiGfx

-- A dashboard card: a rounded, hairline-bordered, softly shadowed panel
-- placed BEHIND a group of controls. It only groups visually; clicks on
-- it fall through to the adopter's `default: pass mouseUp`.
command uiPanel pName, pRect
   local tShadow, tErr
   uiGfx pName, pRect
   set the roundRadius of graphic pName to 14
   set the filled of graphic pName to true
   set the backgroundColor of graphic pName to kUiCard
   set the lineSize of graphic pName to 1
   -- a graphic strokes its outline in the foregroundColor; borderColor is
   -- set too so whichever the engine honours, the hairline lands
   set the foregroundColor of graphic pName to kUiCardLine
   set the borderColor of graphic pName to kUiCardLine
   -- soft drop shadow is an LC-9-era feature, so it is a PURE
   -- enhancement: an engine without it just skips it (the try) and the
   -- hairline still separates the card from the page
   try
      put "90,98,114" into tShadow["color"]
      put 30 into tShadow["opacity"]
      put 10 into tShadow["size"]
      put 0 into tShadow["spread"]
      put 2 into tShadow["distance"]
      put 90 into tShadow["angle"]
      set the dropShadow of graphic pName to tShadow
   catch tErr
   end try
end uiPanel

-- A status pill: rounded chip + centered label, colored by state kind -
-- "ok" green, "wait" amber, "bad" red, anything else the muted on-band
-- blue. The adopter repaints it from ONE place so its handlers cannot
-- disagree about the colors (the nocloud Tor-pill discipline).
command uiPill pName, pText, pRect, pKind
   local tOldDelim, tTop, tBot, tFH
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 2 of pRect into tTop
   put item 4 of pRect into tBot
   set the itemDelimiter to tOldDelim
   uiGfx (pName & "Bg"), pRect
   set the roundRadius of graphic (pName & "Bg") to (tBot - tTop)
   set the filled of graphic (pName & "Bg") to true
   set the lineSize of graphic (pName & "Bg") to 0
   if pKind is "ok" then
      set the backgroundColor of graphic (pName & "Bg") to "205,240,214"
   else if pKind is "wait" then
      set the backgroundColor of graphic (pName & "Bg") to "250,240,199"
   else if pKind is "bad" then
      set the backgroundColor of graphic (pName & "Bg") to "243,215,213"
   else
      set the backgroundColor of graphic (pName & "Bg") to "31,64,116"
   end if
   uiLabel pName, pText, pRect, 10
   set the textAlign of field pName to "center"
   if pKind is "ok" then
      set the foregroundColor of field pName to "22,101,52"
   else if pKind is "wait" then
      set the foregroundColor of field pName to "133,98,14"
   else if pKind is "bad" then
      set the foregroundColor of field pName to "135,44,38"
   else
      set the foregroundColor of field pName to kUiAccentSub
   end if
   -- center the label on the chip midline by measured height
   put the formattedHeight of field pName into tFH
   if tFH > 0 and tFH < (tBot - tTop) then
      set the height of field pName to tFH
      set the top of field pName to (tTop + ((tBot - tTop - tFH) div 2))
   end if
end uiPill

-- Click-to-copy feedback: flash the button's label to "Copied!" for
-- 1200 ms, then restore the real label (stashed in uRealLabel).
command uiCopyFlash pBtn
   if there is no button pBtn then
      exit uiCopyFlash
   end if
   if the uRealLabel of button pBtn is empty then
      set the uRealLabel of button pBtn to the label of button pBtn
   end if
   set the label of button pBtn to "Copied!"
   send ("uiCopyFlashReset" && quote & pBtn & quote) to me in 1200 milliseconds
end uiCopyFlash

command uiCopyFlashReset pBtn
   -- Pinned for the same reason uiStatus is: this one arrives 1200ms later by
   -- `send`, so the defaultStack is whatever is current THEN, not the stack
   -- that flashed the button. Its existence guard means the failure is silent
   -- rather than loud - the label just never comes back, or comes back on
   -- another stack's button - which is why it needed finding rather than
   -- reporting itself.
   set the defaultStack to the short name of this stack
   if there is no button pBtn then
      exit uiCopyFlashReset
   end if
   if the uRealLabel of button pBtn is not empty then
      set the label of button pBtn to the uRealLabel of button pBtn
   end if
end uiCopyFlashReset

-- The honesty/custody footer every demo carries: what the stack is, what
-- it is not, and its engine-evidence state.
command uiFooter pText, pRect
   uiWrap "uiFooter", pText, pRect, 11
   set the textStyle of field "uiFooter" to "italic"
   set the foregroundColor of field "uiFooter" to kUiMuted
end uiFooter
-- ==== SUITE UI KIT v2 END ====

-- ---- state -------------------------------------------------------------------
-- shared plumbing
local sPolling         -- "true" while the one pump chain is armed
local sSession         -- THE torrent session (this stack owns it; C/D/E share it)
local sDcReady         -- "true" once dcInit succeeded (A and E share the drain)
-- A: datachannel local async
local sAPeerA, sAPeerB, sAChanA, sAChanB
local sAOpenA, sAOpenB, sAGotText, sAGotBytes, sABigLen, sAGotLow, sAPhase
-- B: enet chat
local sEnHost          -- the one host this machine runs (server or client)
local sEnRole          -- "host" or "join"
local sEnPeer          -- the connected peer handle
local sEnConnected     -- "true" once enetConnect arrived (a late enetDisconnect
                       -- with this empty is a FAILED connect, not a goodbye)
local sEnSent, sEnGotText, sEnGotEcho
-- C: torrent seed/leech
local sShareTorrent, sLeechTorrent, sLeechHash, sLeechDone
-- D: rp1
local sRp1Room, sRp1Peers, sRp1Sent, sRp1Got
-- E: dc over the DHT
local sEKeys           -- btDhtKeypair array (the room code IS the seed)
local sERole           -- "host" or "join"
local sEPhase          -- "", "gathering", "publish", "fetch-offer", "waiting-answer", "open", "done"
local sENonce, sEPeer, sEChan, sEChunks, sEWant, sENextFetch, sESentHello
local sEWatchArmed     -- "true" while a leg-E watchdog tick is pending
-- F: tor
local sTorHandle       -- the transport-listen service handle
local sTorStream       -- the dialing (client) stream
local sTorGotEcho, sTorConnectTries

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   cpBuild
   cpProbe
   -- Section 0 runs on OPEN, not behind a button, for the reason the demos'
   -- boot self-checks do: the run we care about is the one somebody does
   -- anyway, and a record nobody remembers to produce is a record that does
   -- not exist. It costs nothing - no port, no session of its own, no daemon.
   cpScRun
   if sPolling is not "true" then
      put "true" into sPolling
      send "cpPump" to me in kPollMs milliseconds
   end if
end openStack

on closeStack
   local tErr
   put empty into sPolling
   try
      if sSession is an integer and sSession > 0 then
         btStopSession sSession
      end if
   catch tErr
   end try
   put empty into sSession
   try
      if sDcReady is "true" then
         dcCleanup
      end if
   catch tErr
   end try
   put empty into sDcReady
   try
      if sEnHost is an integer and sEnHost > 0 then
         enHostDestroy sEnHost
      end if
      enDeinitialize
   catch tErr
   end try
   put empty into sEnHost
   try
      oxShutdown
   catch tErr
   end try
end closeStack

on mouseUp
   switch the short name of the target
      case "cpARun"
         cpARun
         break
      case "cpBHost"
         cpBStart "host"
         break
      case "cpBJoin"
         cpBStart "join"
         break
      case "cpCShare"
         cpCShare
         break
      case "cpCFetch"
         cpCFetch
         break
      case "cpCSaveDrop"
         cpCSaveDrop
         break
      case "cpCResume"
         cpCResume
         break
      case "cpDJoin"
         cpDJoin
         break
      case "cpDSend"
         cpDSend
         break
      case "cpEHost"
         cpEStart "host"
         break
      case "cpEJoin"
         cpEStart "join"
         break
      case "cpFLaunch"
         cpFLaunch
         break
      case "cpFEcho"
         cpFEcho
         break
      case "cpFStop"
         cpFStop
         break
      default
         pass mouseUp
   end switch
end mouseUp

-- ---- UI ----------------------------------------------------------------------
command cpBuild
   if there is a field "uiTitle" then
      exit cpBuild
   end if
   lock screen
   -- two columns inside the family's 720p budget (1200 x 640, the
   -- check-stack-size.py cap): A/B/C left, D/E/F right
   uiChrome "Suite closing pass - the remaining runbook legs", 1200, 640

   uiSection "cpSecA", "0 + A. Boot surface (prints on open) then DataChannel local async - both single-machine", "16,58,592,76"
   uiButton "cpARun", "Run A", "16,80,120,104"
   uiArea "cpAOut", "130,80,592,168"

   uiSection "cpSecB", "B. ENet chat, two machines (host on one, join from the other)", "16,174,592,192"
   uiLabel "cpBL1", "host ip[:port]:", "16,196,110,214", 11
   uiInput "cpBAddr", "114,196,300,216"
   uiButton "cpBHost", "Host", "306,196,376,220"
   uiButton "cpBJoin", "Join", "382,196,452,220"
   uiArea "cpBOut", "16,226,592,320"

   uiSection "cpSecC", "C. Torrent seed/leech + resume-from-disk (share on one, fetch on the other)", "16,326,592,344"
   uiButton "cpCShare", "Share", "16,348,120,372"
   uiButton "cpCFetch", "Fetch", "16,378,120,402"
   uiButton "cpCSaveDrop", "Save+drop", "16,408,120,432"
   uiButton "cpCResume", "Resume", "16,438,120,462"
   uiLabel "cpCL1", "code (infohash + payload hash):", "130,348,420,366", 11
   uiInput "cpCCode", "130,368,592,390"
   uiArea "cpCOut", "130,396,592,500"

   uiSection "cpSecD", "D. rp1 chat, two machines (same room word on both; needs the session)", "608,58,1184,76"
   uiLabel "cpDL1", "room:", "608,80,652,98", 11
   uiInput "cpDRoom", "656,80,830,100"
   put "closing-pass" into field "cpDRoom"
   uiButton "cpDJoin", "Join room", "836,80,936,104"
   uiButton "cpDSend", "Send", "942,80,1012,104"
   uiArea "cpDOut", "608,110,1184,180"

   uiSection "cpSecE", "E. DataChannel chat SIGNALED OVER THE DHT (host mints the code; join pastes it)", "608,186,1184,204"
   uiLabel "cpEL1", "room code (64 hex):", "608,208,752,226", 11
   uiInput "cpECode", "756,208,1050,228"
   uiButton "cpEHost", "Host", "1056,208,1116,232"
   uiButton "cpEJoin", "Join", "1122,208,1184,232"
   uiArea "cpEOut", "608,238,1184,330"

   uiSection "cpSecF", "F. Tor, single machine: Mode B launch + a live onion echo (needs a tor BINARY on disk)", "608,336,1184,354"
   uiLabel "cpFL1", "tor binary:", "608,358,688,376", 11
   uiInput "cpFTorPath", "692,358,1050,378"
   uiButton "cpFLaunch", "Launch", "1056,358,1120,382"
   uiButton "cpFStop", "Stop tor", "1126,358,1184,382"
   uiLabel "cpFL2", "data dir:", "608,382,688,400", 11
   uiInput "cpFDataDir", "692,384,1050,404"
   uiButton "cpFEcho", "Onion echo", "1056,388,1184,412"
   uiArea "cpFOut", "608,416,1184,560"

   uiFooter \
         "One torrent session per process: close other torrent stacks, and" \
         & " restart OXT before re-pasting this script. Two-machine legs" \
         & " need both machines online together; the DHT needs a minute to" \
         & " bootstrap before C, D and E find anything (watch the status" \
         & " line). Every PASS line here is a runbook record - copy each" \
         & " section's text back.", \
         "16,570,1184,632"
   put cpTempDir() & "/closing-tor" into field "cpFDataDir"
   unlock screen
end cpBuild

command cpProbe
   local tMissing, tErr
   put empty into tMissing
   try
      get sxVersion()
   catch tErr
      put " sodiumxt" after tMissing
   end try
   try
      get enLibraryVersion()
   catch tErr
      put " enetxt" after tMissing
   end try
   try
      get dcLibraryVersion()
   catch tErr
      put " datachannelxt" after tMissing
   end try
   try
      get btListenPort(0)
   catch tErr
      put " torrentxt" after tMissing
   end try
   -- The ox* layer is EMBEDDED in this file, so its absence is not a missing
   -- install - it is a damaged paste, and saying so sends the operator to the
   -- right fix (re-paste, or re-run tools/sync-demo-embeds.py).
   try
      get oxVersion()
   catch tErr
      put " onionxt (EMBEDDED - re-paste this file)" after tMissing
   end try
   if tMissing is empty then
      uiStatus "Ready: sodiumxt + torrentxt + enetxt + datachannelxt present, ox* carried in this file. Section F additionally needs a tor BINARY on disk.", "ok"
   else
      uiStatus "Missing:" && tMissing & ". Sections needing them will refuse; the rest still run.", "warn"
   end if
end cpProbe

command cpSay pField, pText
   put pText & return after field pField
end cpSay

-- ---- the one pump ------------------------------------------------------------
-- One standing chain drains every queue this stack owns: btPoll and
-- btRp1Poll (separate queues, both every tick), dcPoll, and the enet hosts.
-- Each drain rides its own try so one bad tick cannot break the chain and
-- orphan the session (trap 5.1.1).
command cpPump
   local tEvents, tEvent, tErr
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sPolling is not "true" then
      exit cpPump
   end if
   if sSession is an integer and sSession > 0 then
      try
         put btPoll(sSession) into tEvents
         repeat for each element tEvent in tEvents
            cpOnBtEvent tEvent
         end repeat
      catch tErr
      end try
      try
         put btRp1Poll(sSession) into tEvents
         repeat for each element tEvent in tEvents
            cpOnRp1Event tEvent
         end repeat
      catch tErr
      end try
   end if
   if sDcReady is "true" then
      try
         put dcPoll() into tEvents
         repeat for each element tEvent in tEvents
            cpOnDcEvent tEvent
         end repeat
      catch tErr
      end try
   end if
   if sEnHost is an integer and sEnHost > 0 then
      try
         put enPoll(sEnHost) into tEvents
         repeat for each element tEvent in tEvents
            cpOnEnEvent tEvent
         end repeat
      catch tErr
      end try
   end if
   cpETick
   send "cpPump" to me in kPollMs milliseconds
end cpPump

-- The shared torrent session: started once, DHT + rp1 armed immediately
-- (btRp1Enable must precede the rendezvous swarm add).
command cpEnsureSession
   local tSession, tErr
   if sSession is an integer and sSession > 0 then
      exit cpEnsureSession
   end if
   try
      put btStartSession() into tSession
      if tSession > 0 then
         put tSession into sSession
         btSetBool sSession, "enable_dht", true
         btSetBool sSession, "enable_lsd", true
         btDhtAddBootstrap sSession, "router.bittorrent.com", 6881
         btDhtAddBootstrap sSession, "router.utorrent.com", 6881
         btDhtAddBootstrap sSession, "dht.transmissionbt.com", 6881
         btRp1Enable sSession
         uiStatus "Torrent session up; DHT bootstrapping (give it a minute before C/D/E).", "ok"
      else
         uiStatus "btStartSession refused: another torrent stack holds THE session (trap 5.1). Restart OXT.", "bad"
      end if
   catch tErr
      uiStatus "No torrentxt:" && tErr, "bad"
   end try
end cpEnsureSession

command cpOnBtEvent pEvent
   switch pEvent["name"]
      case "dhtBootstrap"
         uiStatus "DHT bootstrapped.", "ok"
         break
      case "metadataReceived"
         if sLeechTorrent is an integer and sLeechTorrent > 0 then
            cpSay "cpCOut", "metadata arrived:" && pEvent["torrentName"]
         end if
         break
      case "torrentFinished"
         cpCFinished pEvent["torrent"]
         break
      case "resumeDataReady"
         cpCResumeReady pEvent["resumeData"]
         break
      case "dhtMutableItem"
         cpEOnMutable pEvent
         break
      case "dhtImmutableItem"
         cpEOnImmutable pEvent
         break
   end switch
end cpOnBtEvent

-- ---- A: datachannel local async ---------------------------------------------
-- The member harness's still-static live halves, driven the same way its
-- async loopback drives them; a green A is the evidence those labels flip on.
command cpARun
   local tErr
   put empty into field "cpAOut"
   try
      dcInit
      put "true" into sDcReady
   catch tErr
      cpSay "cpAOut", "datachannelxt missing:" && tErr
      exit cpARun
   end try
   put dcCreatePeer("") into sAPeerA
   put dcCreatePeer("") into sAPeerB
   put dcCreateChannel(sAPeerA, "closing") into sAChanA
   put empty into sAChanB
   put empty into sAOpenA
   put empty into sAOpenB
   put empty into sAGotText
   put empty into sAGotBytes
   put empty into sAGotLow
   put empty into sABigLen
   put "opening" into sAPhase
   cpSay "cpAOut", "loopback negotiating..."
end cpARun

command cpOnDcEvent pEvent
   local tDest, tPair, tOk
   -- the in-process shuttle for section A only; section E ships blobs via
   -- the DHT instead, so its peers never appear in this branch
   -- Either spelling: the .lcb emits "dcLocalDescriptionReady" since
   -- 2026-08-18, an extension packaged before that still emits the old
   -- name. Accepting both keeps this green across the transition.
   if pEvent["name"] is among the items of "dcLocalDescription,dcLocalDescriptionReady" then
      put cpAOther(pEvent["peer"]) into tDest
      if tDest is not empty then
         dcSetRemoteDescription tDest, pEvent["sdp"], pEvent["sdpType"]
      end if
   else if pEvent["name"] is "dcLocalCandidate" then
      put cpAOther(pEvent["peer"]) into tDest
      if tDest is not empty then
         dcAddRemoteCandidate tDest, pEvent["candidate"], pEvent["mid"]
      end if
   else if pEvent["name"] is "dcChannelIncoming" then
      if pEvent["peer"] is sAPeerB and sAChanB is empty then
         put pEvent["channel"] into sAChanB
      end if
      if sERole is not empty and pEvent["peer"] is sEPeer then
         put pEvent["channel"] into sEChan
      end if
   else if pEvent["name"] is "dcChannelOpen" then
      if pEvent["channel"] is sAChanA then
         put "true" into sAOpenA
      else if sAChanB is not empty and pEvent["channel"] is sAChanB then
         put "true" into sAOpenB
      end if
      if sEChan is not empty and pEvent["channel"] is sEChan then
         cpEOpen
      end if
   else if pEvent["name"] is "dcMessage" then
      cpOnDcMessage pEvent
   else if pEvent["name"] is "dcBufferedLow" then
      if pEvent["channel"] is sAChanA then
         put "true" into sAGotLow
      end if
   else if pEvent["name"] is "dcGatheringStateChange" then
      cpEOnGathering pEvent
   end if
   cpAAdvance
end cpOnDcEvent

command cpOnDcMessage pEvent
   if pEvent["channel"] is sAChanB or pEvent["channel"] is sAChanA then
      if pEvent["text"] is not empty then
         put pEvent["text"] into sAGotText
      else
         put pEvent["payload"] into sAGotBytes
      end if
   else if sEChan is not empty and pEvent["channel"] is sEChan then
      cpSay "cpEOut", "them:" && pEvent["text"]
      if sESentHello is "true" then
         cpSay "cpEOut", "PASS text both directions over the DHT-signaled channel"
         put "done" into sEPhase
      end if
   end if
end cpOnDcMessage

command cpAAdvance
   local tPair, tCap
   if sAPhase is "opening" then
      if sAOpenA is "true" and sAOpenB is "true" then
         cpSay "cpAOut", "PASS loopback connected, both channels open"
         put dcSelectedCandidatePair(sAPeerA) into tPair
         cpSay "cpAOut", "PASS live dcSelectedCandidatePair:" && tPair["localCandidate"]
         cpSay "cpAOut", "PASS live dcBufferedAmount >= 0:" && dcBufferedAmount(sAChanA)
         if dcLocalDescription(sAPeerA) contains "a=candidate" then
            cpSay "cpAOut", "PASS local description carries a=candidate"
         else
            cpSay "cpAOut", "FAIL local description carries a=candidate"
         end if
         if dcLocalDescriptionType(sAPeerA) is "offer" and dcLocalDescriptionType(sAPeerB) is "answer" then
            cpSay "cpAOut", "PASS offer/answer roles match the flow"
         else
            cpSay "cpAOut", "FAIL offer/answer roles"
         end if
         get dcSetBufferedLowThreshold(sAChanA, 4096)
         get dcSendText(sAChanA, "live-text")
         put "text" into sAPhase
      end if
   else if sAPhase is "text" then
      if sAGotText is "live-text" then
         cpSay "cpAOut", "PASS live dcSendText round-tripped"
         put dcChannelMaxMessage(sAChanA) into tCap
         put tCap into sABigLen
         get dcSendData(sAChanA, cpRepeatByte(66, tCap))
         put "low" into sAPhase
      end if
   else if sAPhase is "low" then
      if sAGotLow is "true" and the number of bytes of sAGotBytes is sABigLen then
         cpSay "cpAOut", "PASS dcBufferedLow fired after the cap-sized send (" & sABigLen && "bytes arrived whole)"
         if dcGatheringState(sAPeerA) is 2 and dcGatheringState(sAPeerB) is 2 then
            cpSay "cpAOut", "PASS live dcGatheringState is complete (2) on both peers"
         else
            cpSay "cpAOut", "FAIL live dcGatheringState"
         end if
         get dcCloseChannel(sAChanA)
         dcFreeChannel sAChanA
         dcFreePeer sAPeerA
         dcFreePeer sAPeerB
         cpSay "cpAOut", "PASS teardown clean - SECTION A COMPLETE"
         put "done" into sAPhase
      end if
   end if
end cpAAdvance

function cpAOther pPeer
   if pPeer is sAPeerA then
      return sAPeerB
   else if pPeer is sAPeerB then
      return sAPeerA
   end if
   return empty
end cpAOther

-- ---- B: enet two-machine chat -------------------------------------------------
-- The failure modes here are SILENT at the transport (a refused bind returns
-- 0, a bad address returns 0, a blocked connect just times out), so every
-- return is validated the way enet-lan-chat does it, and a watchdog names
-- the usual LAN culprits while ENet is still quietly retrying.
command cpBStart pRole
   local tErr, tAddr, tHostAddr, tPort, tOldDelim, tIps
   put empty into field "cpBOut"
   try
      get enInitialize()
   catch tErr
      cpSay "cpBOut", "enetxt missing:" && tErr
      exit cpBStart
   end try
   if sEnHost is an integer and sEnHost > 0 then
      cpSay "cpBOut", "already hosting or joined; restart OXT to re-run this leg cleanly"
      exit cpBStart
   end if
   put pRole into sEnRole
   put empty into sEnPeer
   put empty into sEnSent
   put empty into sEnGotText
   put empty into sEnGotEcho
   put empty into sEnConnected
   if pRole is "host" then
      -- empty bind host = ENET_HOST_ANY (the shim's documented LAN spelling;
      -- a named host would go through the resolver instead)
      put enHostCreateServer("", kEnetPort, 8, 2, 0, 0) into sEnHost
      if sEnHost is 0 or sEnHost is empty then
         cpSay "cpBOut", "could not host (port in use? another stack still bound?):" && enLastError()
         put empty into sEnHost
         exit cpBStart
      end if
      cpSay "cpBOut", "hosting on UDP" && kEnetPort & "; join from the other machine with this machine's LAN ip"
      try
         put hostNameToAddress(the hostName) into tIps
         replace return with comma & space in tIps
         cpSay "cpBOut", "this machine's address(es):" && tIps
         cpSay "cpBOut", "(use the 192.168.*/10.* one; if the join stalls, allow the engine through THIS machine's firewall - inbound UDP" && kEnetPort & ")"
      catch tErr
         cpSay "cpBOut", "(could not list local addresses; read the LAN ip from the OS network settings)"
      end try
   else
      -- accept ip or ip:port, the lan-chat convention
      put word 1 of field "cpBAddr" into tAddr
      if tAddr is empty then
         cpSay "cpBOut", "enter the host machine's ip first"
         exit cpBStart
      end if
      put the itemDelimiter into tOldDelim
      set the itemDelimiter to ":"
      put item 1 of tAddr into tHostAddr
      if the number of items of tAddr > 1 and item 2 of tAddr is a number then
         put item 2 of tAddr into tPort
      else
         put kEnetPort into tPort
      end if
      set the itemDelimiter to tOldDelim
      put enHostCreateClient(1, 2, 0, 0) into sEnHost
      if sEnHost is 0 or sEnHost is empty then
         cpSay "cpBOut", "could not create a client host:" && enLastError()
         put empty into sEnHost
         exit cpBStart
      end if
      put enConnect(sEnHost, tHostAddr, tPort, 2, 99) into sEnPeer
      if sEnPeer is 0 or sEnPeer is empty then
         cpSay "cpBOut", "could not start connecting (bad address?):" && enLastError()
         enHostDestroy sEnHost
         put empty into sEnHost
         exit cpBStart
      end if
      cpSay "cpBOut", "connecting to" && tHostAddr & ":" & tPort & "..."
      send "cpBCheckStuck" to me in 15000 milliseconds
   end if
end cpBStart

-- The join watchdog: ENet retries quietly for ~30 seconds before giving up,
-- so a blocked port reads as a hang. Name the usual causes while it still
-- tries; the definitive FAIL arrives as an enetDisconnect with no prior
-- enetConnect.
command cpBCheckStuck
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sEnRole is not "join" or sEnConnected is "true" then
      exit cpBCheckStuck
   end if
   if sEnHost is not an integer or sEnHost <= 0 then
      exit cpBCheckStuck
   end if
   cpSay "cpBOut", "still connecting. Usual causes, in order: (1) the HOST machine's firewall blocks inbound UDP" && kEnetPort && "- allow the OXT engine for private networks over there, then Host + Join again; (2) the machines are on different networks (guest wifi isolates devices); (3) the host stack is not actually hosting - its section B must say so"
end cpBCheckStuck

command cpOnEnEvent pEvent
   local tBin
   switch pEvent["name"]
      case "enetConnect"
         put "true" into sEnConnected
         if sEnRole is "host" then
            put pEvent["peer"] into sEnPeer
            cpSay "cpBOut", "PASS peer connected from" && pEvent["address"]
         else
            cpSay "cpBOut", "PASS connected to the host"
            get enSendText(sEnPeer, 0, kEnetHello, 0)
            put textEncode("bin", "utf-8") & numToByte(0) & numToByte(1) & textEncode("tail", "utf-8") into tBin
            get enSend(sEnPeer, 1, tBin, 0)
            put "true" into sEnSent
         end if
         break
      case "enetReceive"
         if sEnRole is "host" then
            -- echo whatever arrives, same channel, so the joiner proves
            -- both directions and byte-exactness in one round trip
            get enSend(sEnPeer, pEvent["channel"], pEvent["payload"], 0)
            cpSay "cpBOut", "PASS received + echoed on channel" && pEvent["channel"]
         else
            if pEvent["channel"] is 0 then
               if textDecode(pEvent["payload"], "utf-8") is kEnetHello then
                  put "true" into sEnGotText
                  cpSay "cpBOut", "PASS text echoed byte-exact across the LAN"
               end if
            else
               set the caseSensitive to true
               put textEncode("bin", "utf-8") & numToByte(0) & numToByte(1) & textEncode("tail", "utf-8") into tBin
               if pEvent["payload"] is tBin then
                  put "true" into sEnGotEcho
                  cpSay "cpBOut", "PASS binary (incl. NUL) echoed byte-exact - SECTION B COMPLETE; close with the window to disconnect gracefully"
               end if
            end if
         end if
         break
      case "enetDisconnect"
         if sEnRole is "join" and sEnConnected is not "true" then
            cpSay "cpBOut", "connect FAILED (ENet gave up after ~30 s). Work the watchdog checklist: host-machine firewall first, then same-network"
         else
            cpSay "cpBOut", "PASS graceful disconnect observed (data" && pEvent["data"] & ")"
         end if
         break
   end switch
end cpOnEnEvent

-- ---- C: torrent seed/leech + resume -------------------------------------------
command cpCShare
   local tDir, tFile, tPayload, tMeta, tHash, tErr
   cpEnsureSession
   if sSession is not an integer or sSession <= 0 then
      exit cpCShare
   end if
   put empty into field "cpCOut"
   try
      put cpTempDir() & "/" & kShareFolder into tDir
      if there is no folder tDir then
         create folder tDir
      end if
      -- a patterned ~180 KB payload: deterministic to WRITE, but verified by
      -- HASH on the fetch side, so the transfer is proven, not assumed
      put "closing-pass payload " & the seconds & " " into tPayload
      repeat 13 times
         put tPayload after tPayload
      end repeat
      put tDir & "/" & kPayloadFile into tFile
      put tPayload into url ("binfile:" & tFile)
      put btCreateTorrent(tDir, 0, 0, "") into tMeta
      if the number of bytes of tMeta is 0 then
         cpSay "cpCOut", "btCreateTorrent failed:" && btLastError()
         exit cpCShare
      end if
      -- add pointing at the PARENT so libtorrent rechecks + seeds
      put btAddTorrentFile(sSession, tMeta, cpTempDir()) into sShareTorrent
      -- Checked because btCreateTorrent two lines up IS - the inconsistency
      -- inside one handler is what marks this an oversight rather than a
      -- decision. A 0 here gives btInfoHash nothing to read, so the code field
      -- fills with a bare hash the other machine cannot fetch, and the leg
      -- fails on the FAR side of the paste.
      if sShareTorrent is not a number or sShareTorrent <= 0 then
         cpSay "cpCOut", "FAIL btAddTorrentFile returned no handle:" && btLastError()
         exit cpCShare
      end if
      put textDecode(sxBin2Hex(sxHashFile(tFile, 32)), "ascii") into tHash
      put btInfoHash(sShareTorrent) && tHash into field "cpCCode"
      cpSay "cpCOut", "seeding; the code above carries the infohash + the payload's BLAKE2b-256. Paste it on the other machine and Fetch."
   catch tErr
      cpSay "cpCOut", "share failed:" && tErr
   end try
end cpCShare

command cpCFetch
   local tCode, tErr
   cpEnsureSession
   if sSession is not an integer or sSession <= 0 then
      exit cpCFetch
   end if
   put empty into field "cpCOut"
   put field "cpCCode" into tCode
   if the number of words of tCode is not 2 or the number of chars of word 1 of tCode is not 40 then
      cpSay "cpCOut", "paste the two-part code from the sharing machine first"
      exit cpCFetch
   end if
   put word 2 of tCode into sLeechHash
   put empty into sLeechDone
   try
      put btAddMagnet(sSession, "magnet:?xt=urn:btih:" & word 1 of tCode, cpTempDir()) into sLeechTorrent
      if sLeechTorrent is not a number or sLeechTorrent <= 0 then
         cpSay "cpCOut", "FAIL btAddMagnet returned no handle:" && btLastError() \
               & ". Check the code was pasted whole (infohash, then a space, " \
               & "then the BLAKE2b-256)."
         exit cpCFetch
      end if
      cpSay "cpCOut", "fetching via the DHT (trackerless); metadata + pieces will report here..."
   catch tErr
      cpSay "cpCOut", "fetch failed:" && tErr
   end try
end cpCFetch

command cpCFinished pTorrent
   local tHash
   if pTorrent is sShareTorrent then
      cpSay "cpCOut", "PASS share rechecked complete - now seeding"
      exit cpCFinished
   end if
   if pTorrent is not sLeechTorrent or sLeechDone is "true" then
      exit cpCFinished
   end if
   put "true" into sLeechDone
   put textDecode(sxBin2Hex(sxHashFile(cpTempDir() & "/" & kShareFolder & "/" & kPayloadFile, 32)), "ascii") into tHash
   if tHash is sLeechHash then
      cpSay "cpCOut", "PASS download complete and the payload hash MATCHES the sharer's - exact bytes via the real swarm. SECTION C's transfer leg COMPLETE"
   else
      cpSay "cpCOut", "FAIL hash mismatch: got" && tHash
   end if
end cpCFinished

-- Mid-download resume: ask for resume data; when it arrives (async) it is
-- written to DISK and the torrent removed. Resume re-adds from the file -
-- in this launch, or after quitting OXT entirely, which is the plan's
-- restart gate.
command cpCSaveDrop
   if sLeechTorrent is not an integer or sLeechTorrent <= 0 then
      cpSay "cpCOut", "nothing to save: Fetch first (and click before it finishes)"
      exit cpCSaveDrop
   end if
   get btSaveResumeData(sLeechTorrent)
   cpSay "cpCOut", "resume data requested (async)..."
end cpCSaveDrop

command cpCResumeReady pBytes
   put pBytes into url ("binfile:" & cpTempDir() & "/" & kResumeFile)
   -- btRemoveTorrent takes a typed Integer, and this handler empties the
   -- handle below - so a second resume-data event (libtorrent can emit more
   -- than one, and cpCSaveDrop can be clicked twice) reached it with EMPTY,
   -- which throws rather than no-oping. Guarded, a repeat is silent.
   if sLeechTorrent is an integer and sLeechTorrent > 0 then
      get btRemoveTorrent(sSession, sLeechTorrent, false)
   end if
   put empty into sLeechTorrent
   cpSay "cpCOut", "PASS resume data (" & the number of bytes of pBytes && "bytes) saved to disk and the torrent dropped. Resume now - or quit OXT, relaunch, re-paste, Start session, and Resume: that is the restart gate."
end cpCResumeReady

command cpCResume
   local tBytes, tErr
   cpEnsureSession
   if sSession is not an integer or sSession <= 0 then
      exit cpCResume
   end if
   try
      put url ("binfile:" & cpTempDir() & "/" & kResumeFile) into tBytes
      if the number of bytes of tBytes is 0 then
         cpSay "cpCOut", "no saved resume file found"
         exit cpCResume
      end if
      put btAddTorrentWithResume(sSession, tBytes, cpTempDir()) into sLeechTorrent
      if field "cpCCode" is not empty then
         put word 2 of field "cpCCode" into sLeechHash
      end if
      put empty into sLeechDone
      cpSay "cpCOut", "PASS re-added from saved resume data - progress restores and completion will hash-verify"
   catch tErr
      cpSay "cpCOut", "resume failed:" && tErr
   end try
end cpCResume

-- ---- D: rp1 two-machine chat --------------------------------------------------
command cpDJoin
   local tRoom, tId, tErr, tRc
   cpEnsureSession
   if sSession is not an integer or sSession <= 0 then
      exit cpDJoin
   end if
   put empty into field "cpDOut"
   put empty into sRp1Peers
   put empty into sRp1Sent
   put empty into sRp1Got
   put word 1 of field "cpDRoom" into tRoom
   put cpToHex(sha1Digest(tRoom)) into tId
   put tId into sRp1Room
   try
      -- Both of these were `get`/bare and their returns discarded. rp1 has no
      -- other way to find a peer: if the swarm was never joined, this machine
      -- waits for an event that cannot arrive, and says "waiting for the other
      -- machine" while the fault is on this one.
      put btAddInfohash(sSession, tId, cpTempDir()) into tRc
      if tRc is not a number or tRc <= 0 then
         cpSay "cpDOut", "FAIL btAddInfohash did not join the rendezvous swarm:" \
               && btLastError()
         exit cpDJoin
      end if
      btDhtAnnounce sSession, tId, 0
      put the result into tRc
      if tRc is a number and tRc < 0 then
         cpSay "cpDOut", "FAIL btDhtAnnounce refused (" & tRc & "):" && btLastError() \
               & ". The swarm is joined but this machine is not announcing, so " \
               & "the other one will never see it."
         exit cpDJoin
      end if
      cpSay "cpDOut", "rendezvous" && char 1 to 12 of tId & "...; waiting for the other machine (both must be in the room)"
   catch tErr
      cpSay "cpDOut", "join failed:" && tErr
   end try
end cpDJoin

command cpOnRp1Event pEvent
   local tPeer
   put pEvent["peer"] into tPeer
   switch pEvent["name"]
      case "rp1PeerConnected"
         cpSay "cpDOut", "peer connected:" && pEvent["endpoint"]
         break
      case "rp1Handshake"
         if pEvent["supportsRp1"] is "1" then
            put "1" into sRp1Peers[tPeer]
            cpSay "cpDOut", "PASS rp1 handshake with peer" && tPeer
            cpDSend
         end if
         break
      case "rp1Message"
         put "true" into sRp1Got
         cpSay "cpDOut", "them:" && textDecode(pEvent["payload"], "utf-8")
         if sRp1Sent is "true" then
            cpSay "cpDOut", "PASS rp1 messages both directions - SECTION D COMPLETE"
         end if
         break
      case "rp1PeerDisconnected"
         delete variable sRp1Peers[tPeer]
         cpSay "cpDOut", "peer" && tPeer && "left"
         break
   end switch
end cpOnRp1Event

command cpDSend
   local tPeer
   if sSession is not an integer or sSession <= 0 then
      exit cpDSend
   end if
   repeat for each key tPeer in sRp1Peers
      btRp1Send sSession, tPeer, textEncode("rp1 hello from the closing pass", "utf-8")
      put "true" into sRp1Sent
   end repeat
   if sRp1Sent is "true" then
      cpSay "cpDOut", "sent"
   end if
end cpDSend

-- ---- E: datachannel over the DHT ----------------------------------------------
-- The riptide-proven substrate carrying WebRTC signaling: non-trickle SDP
-- blobs as chunked immutable items under a mutable head, one salt per role.
command cpEStart pRole
   local tKp, tCode, tErr
   cpEnsureSession
   if sSession is not an integer or sSession <= 0 then
      exit cpEStart
   end if
   put empty into field "cpEOut"
   try
      dcInit
      put "true" into sDcReady
   catch tErr
      cpSay "cpEOut", "datachannelxt missing:" && tErr
      exit cpEStart
   end try
   put pRole into sERole
   put empty into sEChan
   put empty into sESentHello
   put empty into sEChunks
   put empty into sEWant
   put the milliseconds into sENextFetch
   if pRole is "host" then
      put btDhtKeypair("") into sEKeys
      put sEKeys["seed"] into field "cpECode"
      put "h" & the milliseconds into sENonce
      put dcCreatePeer("stun:stun.l.google.com:19302") into sEPeer
      put dcCreateChannel(sEPeer, "closing-dht") into sEChan
      put "gathering" into sEPhase
      cpSay "cpEOut", "code minted (share it with the join side); gathering, then publishing the offer..."
   else
      put word 1 of field "cpECode" into tCode
      if the number of chars of tCode is not 64 then
         cpSay "cpEOut", "paste the 64-hex room code from the host first"
         exit cpEStart
      end if
      put btDhtKeypair(tCode) into sEKeys
      put "j" & the milliseconds into sENonce
      put "fetch-offer" into sEPhase
      cpSay "cpEOut", "fetching the offer from the DHT..."
   end if
   -- Arm the watchdog once per start, on leg B's model. Leg E is the leg with
   -- the most ways to wait silently - a slow DHT, a lost chunk, a room code
   -- pasted on one machine only - and until 2026-08-20 it had none, so a stall
   -- looked exactly like a leg still working.
   if sEWatchArmed is not "true" then
      put "true" into sEWatchArmed
      send "cpECheckStuck" to me in 20000 milliseconds
   end if
end cpEStart

-- The leg-E watchdog. It names WHICH chunks are outstanding, because "still
-- waiting" is the one thing the operator can already see.
command cpECheckStuck
   local tTarget, tMissing, tHave
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   put "false" into sEWatchArmed
   if sEPhase is "open" or sEPhase is "done" or sEPhase is empty then
      exit cpECheckStuck
   end if
   if sEPhase is "failed" then
      exit cpECheckStuck
   end if
   if sEWant is empty then
      cpSay "cpEOut", "still waiting for the other machine's head (phase" && sEPhase \
            & "). Usual causes, in order: (1) the other machine has not pressed " \
            & "its button yet; (2) the room code differs - it must be the SAME " \
            & "64 hex characters on both; (3) this machine's DHT has no nodes " \
            & "yet - section A's node count says so."
   else
      put 0 into tMissing
      put 0 into tHave
      repeat for each item tTarget in sEWant
         if sEChunks[tTarget] is empty then
            add 1 to tMissing
         else
            add 1 to tHave
         end if
      end repeat
      cpSay "cpEOut", "head arrived but" && tMissing && "of" && (tMissing + tHave) \
            && "chunk(s) are still missing; re-asking every" && (kRefetchMs div 1000) \
            & "s. If this does not clear, the DHT is not propagating between " \
            & "these two machines - try leg D first, which uses the same DHT."
   end if
   put "true" into sEWatchArmed
   send "cpECheckStuck" to me in 20000 milliseconds
end cpECheckStuck

command cpEOnGathering pEvent
   if pEvent["peer"] is not sEPeer or pEvent["state"] is not 2 then
      exit cpEOnGathering
   end if
   if sEPhase is "gathering" then
      cpEPublish
   end if
end cpEOnGathering

command cpEPublish
   local tSalt, tBody, tZip, tChunk, tTargets, tHead, tStart, tTarget, tRc
   if sERole is "host" then
      put kSaltOffer into tSalt
      put "waiting-answer" into sEPhase
   else
      put kSaltAnswer into tSalt
      put "open" into sEPhase
   end if
   put sENonce & linefeed & dcLocalDescriptionType(sEPeer) & linefeed & dcLocalDescription(sEPeer) into tBody
   put compress(textEncode(tBody, "UTF-8")) into tZip
   -- ALWAYS chunked (uniform path): 900-byte immutable pieces, the mutable
   -- head carrying the comma list of their 40-hex targets
   put empty into tTargets
   put 1 into tStart
   repeat while tStart <= the number of bytes of tZip
      put byte tStart to (tStart + kChunkMax - 1) of tZip into tChunk
      -- CHECK THE PUT. btDhtPutImmutable returns the EMPTY STRING on failure
      -- (torrent.lcb, both the len<=0 and count<=0 paths), and this line used
      -- to append it unchecked. One failed chunk therefore produced a target
      -- list with a doubled or trailing comma; the head was still published
      -- claiming N chunks; the joining machine then issued a get for an EMPTY
      -- target, which no event can ever answer, so its assembly loop hit
      -- `if sEChunks[tTarget] is empty then exit` on every later chunk -
      -- forever, silently, on both machines. Refusing to publish a head that
      -- does not describe the DHT is the only honest exit.
      put btDhtPutImmutable(sSession, tChunk) into tTarget
      if tTarget is empty then
         cpSay "cpEOut", "FAIL btDhtPutImmutable refused a chunk:" && btLastError() \
               & ". Not publishing a head that would name it - the other " \
               & "machine would wait on a target that does not exist. Re-run " \
               & "this leg."
         put "failed" into sEPhase
         exit cpEPublish
      end if
      if tTargets is not empty then
         put comma after tTargets
      end if
      put tTarget after tTargets
      add kChunkMax to tStart
   end repeat
   put textEncode(kHeadMagic & tTargets, "UTF-8") into tHead
   put btDhtPutMutable(sSession, sEKeys["publicKey"], sEKeys["secretKey"], tSalt, tHead) into tRc
   -- Same class, one level up: a negative rc here means the head never went out,
   -- and claiming "published" would send the operator looking at the OTHER
   -- machine for a fault that is on this one.
   if tRc is a number and tRc < 0 then
      cpSay "cpEOut", "FAIL btDhtPutMutable refused the head (" & tRc & "):" \
            && btLastError() & ". The chunks are on the DHT but nothing points " \
            & "at them. Re-run this leg."
      put "failed" into sEPhase
      exit cpEPublish
   end if
   cpSay "cpEOut", "published" && dcLocalDescriptionType(sEPeer) && "as" && (the number of items of tTargets) && "chunk(s)"
end cpEPublish

-- The standing re-request: while a slot is awaited, ask the DHT again every
-- few seconds (propagation is eventual; the first get usually misses).
command cpETick
   local tSalt
   if sSession is not an integer or sSession <= 0 then
      exit cpETick
   end if
   if sEPhase is not "fetch-offer" and sEPhase is not "waiting-answer" then
      exit cpETick
   end if
   if the milliseconds < sENextFetch then
      exit cpETick
   end if
   put the milliseconds + kRefetchMs into sENextFetch
   if sEPhase is "fetch-offer" then
      put kSaltOffer into tSalt
   else
      put kSaltAnswer into tSalt
   end if
   get btDhtGetMutable(sSession, sEKeys["publicKey"], tSalt)
end cpETick

command cpEOnMutable pEvent
   local tHeadText
   if sERole is empty or pEvent["publicKey"] is not sEKeys["publicKey"] then
      exit cpEOnMutable
   end if
   if sEPhase is "fetch-offer" and pEvent["salt"] is kSaltOffer then
      put textDecode(pEvent["value"], "UTF-8") into tHeadText
      cpEWantChunks tHeadText
   else if sEPhase is "waiting-answer" and pEvent["salt"] is kSaltAnswer then
      put textDecode(pEvent["value"], "UTF-8") into tHeadText
      cpEWantChunks tHeadText
   end if
end cpEOnMutable

command cpEWantChunks pHeadText
   local tList, tTarget, tMissing
   if char 1 to 4 of pHeadText is not kHeadMagic then
      exit cpEWantChunks
   end if
   put char 5 to -1 of pHeadText into tList
   if tList is sEWant then
      -- A REPEAT HEAD IS A RETRY, NOT A NO-OP. This used to exit here, which
      -- meant the 4-second cpETick head-refetch re-fetched the HEAD and never
      -- re-asked for a single missing chunk. DHT propagation is eventual and a
      -- first get routinely misses, so one lost chunk left both machines
      -- waiting with nothing on either screen and no way to tell why. Re-issue
      -- for the outstanding targets only; the arrived ones are already in
      -- sEChunks and a duplicate answer is harmless.
      put empty into tMissing
      repeat for each item tTarget in sEWant
         if sEChunks[tTarget] is empty then
            get btDhtGetImmutable(sSession, tTarget)
            add 1 to tMissing
         end if
      end repeat
      if tMissing > 0 then
         cpSay "cpEOut", "re-asking the DHT for" && tMissing && "chunk(s) still missing of" \
               && (the number of items of sEWant)
      end if
      exit cpEWantChunks
   end if
   put tList into sEWant
   put empty into sEChunks
   repeat for each item tTarget in tList
      get btDhtGetImmutable(sSession, tTarget)
   end repeat
   cpSay "cpEOut", "head arrived:" && (the number of items of tList) && "chunk(s) to fetch"
end cpEWantChunks

command cpEOnImmutable pEvent
   local tTarget, tZip, tBody, tNonce, tType, tSdp, tR
   if sEWant is empty then
      exit cpEOnImmutable
   end if
   put pEvent["target"] into tTarget
   if tTarget is not among the items of sEWant then
      exit cpEOnImmutable
   end if
   put pEvent["value"] into sEChunks[tTarget]
   -- assemble once every wanted chunk is present, in list order
   repeat for each item tTarget in sEWant
      if sEChunks[tTarget] is empty then
         exit cpEOnImmutable
      end if
      put sEChunks[tTarget] after tZip
   end repeat
   put textDecode(decompress(tZip), "UTF-8") into tBody
   put line 1 of tBody into tNonce
   put line 2 of tBody into tType
   put line 3 to -1 of tBody into tSdp
   if tNonce is sENonce then
      exit cpEOnImmutable
   end if
   put empty into sEWant
   if sERole is "join" and tType is "offer" then
      put dcCreatePeer("stun:stun.l.google.com:19302") into sEPeer
      put dcSetRemoteDescription(sEPeer, tSdp, "offer") into tR
      put "gathering" into sEPhase
      cpSay "cpEOut", "offer applied; answering..."
   else if sERole is "host" and tType is "answer" then
      put dcSetRemoteDescription(sEPeer, tSdp, "answer") into tR
      put "open" into sEPhase
      cpSay "cpEOut", "answer applied; waiting for the channel..."
   end if
end cpEOnImmutable

command cpEOpen
   local tPair
   put dcSelectedCandidatePair(sEPeer) into tPair
   cpSay "cpEOut", "PASS channel OPEN across machines; selected pair:" && tPair["localCandidate"]
   cpSay "cpEOut", "(a srflx/prflx pair here is cross-NAT evidence; host/host means one LAN)"
   get dcSendText(sEChan, "dc-dht hello from" && sERole)
   put "true" into sESentHello
end cpEOpen

-- ---- F: tor - Mode B + onion echo ---------------------------------------------
command cpFLaunch
   local tPath, tDir, tErr, tR
   put word 1 to -1 of field "cpFTorPath" into tPath
   put word 1 to -1 of field "cpFDataDir" into tDir
   if tPath is empty then
      cpSay "cpFOut", "point the tor-binary field at a real tor executable first"
      exit cpFLaunch
   end if
   try
      if there is no folder tDir then
         create folder tDir
      end if
      oxSetCallbackOwner the long id of this card
      oxSetStatusCallback "cpOnTorStatus"
      oxSetPeerCallback "cpOnTorPeer"
      -- EXPLICIT PORTS, and this is the difference between settling Mode B and
      -- appearing to. Empty ports default to kOxSocksPortDefault /
      -- kOxControlPortDefault - 9050 and 9051, which is exactly where a SYSTEM
      -- tor listens. On a machine already running tor (likely: the other Tor
      -- legs want one) the launched process cannot bind them, and the
      -- oxConnectControl that follows then authenticates against the system
      -- daemon instead - so leg F prints PASS for a tor it did not launch,
      -- which is a false PASS on the single claim it exists to make.
      oxLaunchTor tPath, tDir, 9250, 9251
      put the result into tR
      if tR is not empty then
         cpSay "cpFOut", "oxLaunchTor refused:" && tR
         exit cpFLaunch
      end if
      cpSay "cpFOut", "PASS oxLaunchTor accepted on SOCKS 9250 / control 9251 (not the system pair; torrc written, process started; processId" && the processId & ")"
      put 0 into sTorConnectTries
      send "cpFConnect" to me in 2000 milliseconds
   catch tErr
      cpSay "cpFOut", "launch failed (the ox* layer is embedded in this file, so a throw here means the paste is damaged):" && tErr
   end try
end cpFLaunch

-- The control port takes a moment to open and write its cookie; retry the
-- connect until it authenticates, and give up loudly rather than forever.
command cpFConnect
   local tR
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if oxIsControlAuthenticated() then
      exit cpFConnect
   end if
   add 1 to sTorConnectTries
   oxConnectControl
   put the result into tR
   if tR is empty then
      cpSay "cpFOut", "control connecting..."
   else if sTorConnectTries < 15 then
      send "cpFConnect" to me in 2000 milliseconds
   else
      cpSay "cpFOut", "control never opened:" && tR
   end if
end cpFConnect

on cpOnTorStatus pKind, pInfo
   if pKind is "control" then
      if pInfo is "authenticated" then
         cpSay "cpFOut", "PASS control connected + authenticated (SAFECOOKIE against the LAUNCHED tor)"
      else
         cpSay "cpFOut", "control:" && pInfo
      end if
   else if pKind is "bootstrap" then
      uiStatus "tor bootstrap:" && pInfo & "%", empty
      if pInfo is 100 then
         cpSay "cpFOut", "PASS Bootstrapped 100% - MODE B (runbook item 4) COMPLETE; the onion echo can run now"
      end if
   else if pKind is "service" then
      cpSay "cpFOut", "onion address:" && pInfo
   else if pKind is "serviceReady" then
      cpSay "cpFOut", "PASS descriptor uploaded (serviceReady); dialing our own onion through the Tor network..."
      cpFDial
   end if
end cpOnTorStatus

command cpFEcho
   local tErr
   if not oxIsReady() then
      cpSay "cpFOut", "wait for bootstrap 100% first"
      exit cpFEcho
   end if
   put empty into sTorGotEcho
   try
      oxTransportListen sxRandomBytes(32), 80, 9099
      put the result into sTorHandle
      if sTorHandle is not an integer then
         cpSay "cpFOut", "listen refused:" && sTorHandle
         put empty into sTorHandle
         exit cpFEcho
      end if
      cpSay "cpFOut", "listening; publishing the service (descriptor upload takes a minute)..."
   catch tErr
      cpSay "cpFOut", "listen failed:" && tErr
   end try
end cpFEcho

command cpFDial
   local tAddr, tR
   put oxServiceAddress(sTorHandle) into tAddr
   if tAddr is empty then
      cpSay "cpFOut", "no address yet; will retry on serviceReady"
      exit cpFDial
   end if
   oxTransportDial tAddr, 80
   put the result into sTorStream
   if sTorStream is not an integer then
      cpSay "cpFOut", "dial failed:" && sTorStream
      exit cpFDial
   end if
   oxTransportRecv sTorStream, "cpTorClientStream"
end cpFDial

on cpOnTorPeer pStream, pService, pPeerAddr
   -- inbound side of our own dial, arriving through the real Tor network;
   -- echo every byte straight back
   oxTransportRecv pStream, "cpTorServerStream"
end cpOnTorPeer

on cpTorServerStream pStream, pEvent, pData
   if pEvent is "data" then
      oxTransportSend pStream, pData
   end if
end cpTorServerStream

on cpTorClientStream pStream, pEvent, pData
   if pEvent is "open" then
      oxTransportSend pStream, textEncode(kTorPing, "utf-8")
   else if pEvent is "data" then
      if textDecode(pData, "utf-8") is kTorPing then
         put "true" into sTorGotEcho
         cpSay "cpFOut", "PASS exact bytes echoed through the LIVE TOR NETWORK (listen + dial + send + recv all live) - SECTION F's echo COMPLETE"
      end if
   else if pEvent is "error" then
      cpSay "cpFOut", "stream error:" && pData
   end if
end cpTorClientStream

command cpFStop
   local tErr
   try
      oxStopTor
      oxStopTor
      cpSay "cpFOut", "PASS oxStopTor sent (twice: the duplicate is a harmless no-op)"
   catch tErr
      cpSay "cpFOut", "stop failed:" && tErr
   end try
end cpFStop

-- ---- helpers ------------------------------------------------------------------
function cpTempDir
   local tDir
   put specialFolderPath("temporary") into tDir
   if tDir is empty then
      put specialFolderPath("documents") into tDir
   end if
   if char -1 of tDir is "/" then
      delete char -1 of tDir
   end if
   put tDir & "/suite-closing-pass" into tDir
   if there is no folder tDir then
      create folder tDir
   end if
   return tDir
end cpTempDir

-- 20 raw bytes to 40 lowercase hex without binaryEncode format folklore
-- (the rp1-chat discipline).
function cpToHex pData
   local tHex, tI, tByte
   put empty into tHex
   repeat with tI = 1 to the number of bytes of pData
      put byteToNum(byte tI of pData) into tByte
      put char (tByte div 16 + 1) of "0123456789abcdef" after tHex
      put char (tByte mod 16 + 1) of "0123456789abcdef" after tHex
   end repeat
   return tHex
end cpToHex

-- pCount copies of byte pCode, by doubling (no string-escape folklore).
function cpRepeatByte pCode, pCount
   local tOut
   put numToByte(pCode) into tOut
   repeat while the number of bytes of tOut < pCount
      put tOut & tOut into tOut
   end repeat
   return byte 1 to pCount of tOut
end cpRepeatByte
-- ==== DEMO SELF-CHECK v1 BEGIN (verbatim copy; master: tools/demo-selfcheck.livecodescript; gate: tools/check-demo-selfcheck-drift.py) ====
-- The sentinel is a CONSTANT so the probe compares against one spelling; a
-- literal repeated at the write and the read is a check that can pass while
-- disagreeing with itself.
constant kScProbe = "self-check: delayed write reached the status line"
local sScLines          -- the whole block, kept so a Copy button has something
local sScPassed, sScFailed, sScSkipped
local sScLogField       -- the adopting demo's own log field, set by scBegin

command scBegin pLogField
   put pLogField into sScLogField
   put empty into sScLines
   put 0 into sScPassed
   put 0 into sScFailed
   put 0 into sScSkipped
   scLine "== boot self-check (nothing is hosted, connected, or bound) =="
end scBegin

-- Each line is LOGGED as it is made, not accumulated and flushed at the end.
-- The first draft did both - a flush after the synchronous half and another
-- after the probe - which printed every synchronous line twice.
command scLine pText
   put pText & return after sScLines
   -- pin the stack: scFinish reaches here from a `send ... in` tick, and the
   -- field is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sScLogField is empty or there is no field sScLogField then
      exit scLine
   end if
   put pText & return after field sScLogField
   set the vscroll of field sScLogField to the formattedHeight of field sScLogField
end scLine

command scAssert pName, pOk
   if pOk then
      add 1 to sScPassed
      scLine "PASS  " & pName
   else
      add 1 to sScFailed
      scLine "FAIL  " & pName
   end if
end scAssert

-- SKIP, never FAIL, for an absent extension: a missing member is an
-- environment, and only a present-and-broken member is a defect.
command scSkip pName, pReason
   add 1 to sScSkipped
   scLine "SKIP  " & pName & " (" & pReason & ")"
end scSkip

-- An empty value prints as nothing, which reads as a missing check rather than
-- an answer of empty; every observed value in a self-check goes through here.
-- This is the playLoudness lesson (OXT-ENGINE-NOTES 5.4) as a helper: a check
-- that reports only its own name costs a whole engine pass to diagnose.
function scShow pValue
   if pValue is empty then
      return "empty"
   end if
   return pValue
end scShow

-- Returns the comma-list of control names in pList that do not exist, or empty.
-- The adopter passes EVERY control name its own script references, derived from
-- the source rather than hand-picked: a missing control is not cosmetic, it is
-- the "Chunk: error in object expression" class, and finding it at boot beats
-- finding it when somebody clicks.
function scMissing pList
   local tName, tMissing
   set the defaultStack to the short name of this stack
   repeat for each item tName in pList
      -- ALL THREE CONTROL TYPES. The kit builds fields (uiLabel/uiWrap/uiCap/
      -- uiSection/uiInput/uiArea/uiTable), buttons (uiButton/uiCheckbox) AND
      -- GRAPHICS (uiGfx/uiPanel/uiPill). The first version of this asked only
      -- about fields and buttons, so every uiPill a demo builds - the Tor
      -- pills in both Quick Shares, for one - reported as a missing control on
      -- a stack where it exists.
      if there is no field tName and there is no button tName \
            and there is no graphic tName then
         put tName & comma after tMissing
      end if
   end repeat
   if tMissing is empty then
      return empty
   end if
   return char 1 to -2 of tMissing
end scMissing

-- Call LAST in <pfx>ScRun. It arms the probe below; 400ms lands it before the
-- usual 800ms dashboard tick, so nothing races for the status line.
--
-- SAY THAT THE REPORT IS UNFINISHED, for the reason the suite harness carries a
-- RUN NOT FINISHED trailer: a report that simply stops reads exactly like a
-- report that ended, and the difference cost that harness a round trip on
-- 2026-08-19. One line is cheaper than the ambiguity.
command scArmProbe
   scLine "      ...one delayed-write check still to come; the count line " \
         & "below it is the end of the block"
   send "scTickProbe" to me in 400 milliseconds
end scArmProbe

-- THE ONE CHECK THAT NEEDS A TIMER.
--
-- OXT-ENGINE-NOTES 5.3 says an unqualified control reference inside a delayed
-- handler resolves against THE DEFAULTSTACK, not the stack whose script is
-- running - and that entry is classed DOCUMENTED, not OBSERVED, because this
-- tree has never actually watched the unpinned form fail. It also names the run
-- that would settle it: open a second stack in front and let a `send ... in`
-- handler write an unqualified field.
--
-- So this probe READS the defaultStack before pinning and PRINTS what it found.
-- On an ordinary run that line is context. On a run with another window in front
-- it is the measurement 5.3 is missing, taken for free and at no risk, because
-- the pin lands immediately afterwards and the write is verified.
command scTickProbe
   local tWas, tPrev, tPrevColor, tGot, tErr
   put the defaultStack into tWas
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      scSkip "a delayed handler writes the status line", "the chrome is not built"
      scFinish
      exit scTickProbe
   end if
   -- RESTORE THE COLOUR TOO, not just the text. uiStatus takes a KIND, and
   -- handing it back "ok" would repaint a "bad" line green - so a stack whose
   -- extension is missing would end this probe claiming to be fine.
   put field "uiStatus" into tPrev
   put the foregroundColor of field "uiStatus" into tPrevColor
   try
      uiStatus kScProbe, empty
      put field "uiStatus" into tGot
   catch tErr
      put "THREW:" && tErr into tGot
   end try
   uiStatus tPrev, empty
   set the foregroundColor of field "uiStatus" to tPrevColor
   scAssert "a delayed handler writes the status line " \
         & "(defaultStack on entry: " & scShow(tWas) & ")", (tGot is kScProbe)
   scFinish
end scTickProbe

command scFinish
   scLine "      " & sScPassed & " passed, " & sScFailed & " failed, " \
         & sScSkipped & " skipped - select this block and copy it into the " \
         & "OXT pass record"
   if sScFailed is 0 then
      scLine "      boot self-check GREEN (this is the single-machine claim; " \
            & "the live legs are the runbook's)"
      exit scFinish
   end if
   scLine "      boot self-check has FAILURES above - report them before " \
         & "running any live leg"
   -- ONLY ON FAILURE does this touch the status line, and the asymmetry is
   -- deliberate. Green, the demo's own "Ready ..." line is the more useful
   -- thing to be reading and the detail is in the log a few lines up. Red, the
   -- log may be on a tab nobody has clicked - so the one surface a person is
   -- certainly looking at has to say so. Fail loud, pass quiet.
   uiStatus "Boot self-check: " & sScFailed & " FAILED (see the log)", "bad"
end scFinish
-- ==== DEMO SELF-CHECK v1 END ====

-- torproject.org's real v3 onion, and the same address with ONE character
-- changed so its checksum fails. Pure compute: no daemon is touched.
constant kCpScRealOnion = "2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion"
constant kCpScBadOnion = "3gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion"

-- ---- section 0: the boot surface ----------------------------------------------
-- The plumbing is CARRIED (master: tools/demo-selfcheck.livecodescript; gate:
-- tools/check-demo-selfcheck-drift.py). What this file owns is the list below.
--
-- WHY THIS SECTION IS HERE. Eleven demos each print a boot self-check, and the
-- half of each that is about a MEMBER rather than about that demo's own window
-- is the same half. Running it once, in the stack the operator installs on both
-- machines anyway, means a two-machine session records the state of every
-- extension on BOTH machines before a single leg is attempted - which is the
-- question a failed leg makes you ask afterwards, from the wrong end.
--
-- WHAT IT DELIBERATELY DOES NOT COVER, so nobody reads it as more than it is:
--   * each demo's own CONTROLS - eleven windows cannot be one window, and the
--     eleven prefixes collide anyway (two demos use qs, two use demo);
--   * the CARRIED HELPER LAYERS (enet-helpers, datachannel-helpers) - all three
--     of those files and this one declare `sPolling`, so no two of them can
--     share a script. That is not a limitation to work around: it is a hard
--     compile error, and tools/check-duplicate-declarations.py exists to refuse
--     it. Their coverage lives in the member selftests, folded into the suite
--     paste.
--   * the DEEP member harnesses - that is tests/suite-selftest.livecodescript,
--     one machine, ~1985 checks.
--
-- Nothing here hosts, connects, binds a port or takes a singleton beyond the
-- session cpProbe already opened.

-- Every control name this script names OR builds, derived from the source with
-- comments cut and string literals kept.
constant kCpScControls = "cpAOut,cpARun,cpBAddr,cpBHost,cpBJoin,cpBL1,cpBOut,cpCCode,cpCFetch,cpCL1,cpCOut,cpCResume,cpCSaveDrop,cpCShare,cpDJoin,cpDL1,cpDOut,cpDRoom,cpDSend,cpECode,cpEHost,cpEJoin,cpEL1,cpEOut,cpFDataDir,cpFEcho,cpFL1,cpFL2,cpFLaunch,cpFOut,cpFStop,cpFTorPath,cpSecA,cpSecB,cpSecC,cpSecD,cpSecE,cpSecF,uiFooter,uiStatus,uiTitle"

command cpScRun
   local tMissing, tVer, tRc, tErr, tState, tPort, tInfo
   scBegin "cpAOut"
   put scMissing(kCpScControls) into tMissing
   scAssert "all 41 controls this script names exist (missing: " \
         & scShow(tMissing) & ")", (tMissing is empty)

   -- SodiumXT: the one member every other leg composes with.
   -- Each member is probed HERE rather than read off a flag: cpProbe builds a
   -- one-line "Missing: ..." summary for the status line and keeps no per-member
   -- state, and a second guarded call is cheaper than a flag that could drift
   -- from what the extension actually does.
   put empty into tVer
   try
      put sxVersion() into tVer
   catch tErr
      put empty into tVer
   end try
   if tVer is empty then
      scSkip "sodiumxt", "not installed - legs C and E seal their payloads with it"
   else
      scAssert "sxVersion names libsodium (" & tVer & ")", (tVer contains "libsodium")
   end if

   -- TorrentXT: legs C, D and E all ride this ONE session.
   if sSession is empty or sSession is 0 then
      scSkip "the torrentxt session (legs C, D, E)", \
            "no session - the extension is absent, or another TorrentXT stack " \
            & "holds THE session (runbook trap 5.1). Those three legs will refuse."
   else
      put btListenPort(sSession) into tPort
      scAssert "the session is listening (handle " & scShow(sSession) \
            & ", port " & scShow(tPort) & ")", (tPort > 0)
      put btLastError() into tErr
      scAssert "btLastError is empty after a clean boot (" & scShow(tErr) & ")", \
            (tErr is empty)
   end if

   -- ENetXT: leg B. enHostDestroy(0) is the stale-handle contract, and the one
   -- destructive-looking call that is not - handle 0 is never live.
   put empty into tVer
   try
      put enLibraryVersion() into tVer
   catch tErr
      put empty into tVer
   end try
   if tVer is empty then
      scSkip "enetxt (leg B)", "not installed"
   else
      scAssert "enLibraryVersion names enet (" & tVer & ")", (tVer contains "enet")
      put enHostDestroy(0) into tRc
      scAssert "enHostDestroy(0) is a harmless no-op (got " & tRc & ")", (tRc is 0)
      put enLastError() into tErr
      scAssert "enLastError is empty after a clean boot (" & scShow(tErr) & ")", \
            (tErr is empty)
   end if

   -- DataChannelXT: legs A and E.
   put empty into tVer
   try
      put dcLibraryVersion() into tVer
   catch tErr
      put empty into tVer
   end try
   if tVer is empty then
      scSkip "datachannelxt (legs A and E)", "not installed"
   else
      scAssert "dcLibraryVersion names libdatachannel (" & tVer & ")", \
            (tVer contains "libdatachannel")
      put dcPeerState(0) into tState
      scAssert "dcPeerState(0) is -1 for a stale handle (got " & tState & ")", \
            (tState is -1)
      put dcLastError() into tErr
      scAssert "dcLastError is empty after a clean boot (" & scShow(tErr) & ")", \
            (tErr is empty)
   end if

   -- OnionXT: leg F. The layer is CARRIED in this file, so an absent oxVersion
   -- is a damaged paste, not a missing install - and these four are pure
   -- compute: no daemon is touched, so they answer the same before and after
   -- Launch.
   put empty into tVer
   try
      put oxVersion() into tVer
   catch tErr
      put empty into tVer
   end try
   if tVer is empty then
      scSkip "the carried onionxt layer (leg F)", \
            "oxVersion did not answer - the embedded copy is damaged; re-paste " \
            & "this file, or run tools/sync-demo-embeds.py"
   else
      scAssert "oxVersion answers (" & tVer & ")", (tVer is not empty)
      put oxTransportInfo() into tInfo
      scAssert "oxTransportInfo's version agrees with oxVersion", \
            (tInfo["version"] is tVer)
      -- A true here would mean a control connection inherited from an earlier
      -- run in this process, which changes what leg F is proving.
      scAssert "oxIsReady is false before anything connects", (oxIsReady() is false)
      scAssert "oxIsValidAddress accepts a real v3 address and refuses a " \
            & "tampered one", \
            (oxIsValidAddress(kCpScRealOnion) is true \
             and oxIsValidAddress(kCpScBadOnion) is false)
   end if
   scArmProbe
end cpScRun
