script "EnetInternetChat"

-- enet-internet-chat.livecodescript - ENet across the REAL internet, provably.
-- The LAN chat's sibling with one job: show that enetxt's reliable UDP works
-- between two machines on DIFFERENT networks, with the proof ON SCREEN rather
-- than asserted. One machine clicks Host: the demo opens the router's UDP port
-- automatically (TorrentXT's btMapPort - UPnP/NAT-PMP), learns the machine's
-- public IP (TorrentXT's externalIp event), and shows a one-line INVITE
-- (ip:port). The other machine - a friend's house, a phone hotspot, anywhere -
-- pastes the invite and Joins. The chat itself is PURE ENet: TorrentXT is only
-- the doorman (port + IP discovery); every chat byte rides enSendText /
-- enBroadcastText on reliable channel 0.
--
-- THE PROOF PANEL is the point. The pill above the log goes INTERNET LIVE
-- (green) only when the remote peer's address is a genuinely PUBLIC one - a
-- private/LAN address (10.x, 192.168.x, 172.16-31.x, 127.x, 169.254.x) shows
-- amber "LAN only", so a same-network test cannot masquerade as the internet
-- claim. Beside it: the live RTT, packet loss and byte counters from
-- enPeerStatus - reliable UDP measured across the real path.
--
-- HOW TO USE (two machines on DIFFERENT networks):
--   1. Install the enetxt AND torrentxt extensions on the HOST machine
--      (joiners need only enetxt). Paste this file into a stack script on
--      both and reopen the stack; opening the file itself builds no window
--      (docs/OXT-ENGINE-NOTES.md 5.5).
--   2. Machine A clicks Host. Wait for the invite line to fill in (the router
--      confirms the port, then the public IP arrives - typically seconds).
--      Copy the invite and send it to your friend any way you like.
--   3. Machine B pastes the invite and clicks Join. Chat. Watch the pill.
--   If the router refuses UPnP, the log says so and names the manual fix
--   (forward UDP 27199 to this machine); the invite still fills in once the
--   public IP is known, because libtorrent learns it from DHT traffic too.
--
-- HONESTY (the suite convention): every en* and bt* call here is individually
-- engine-proven (member harnesses green through 2026-08-24), and the UPnP +
-- externalIp flow is ported from torrent-quickshare, whose clearweb layer has
-- an engine pass behind it - but THIS stack is new, and its whole point is a
-- leg no single machine can prove: verified statically; needs a TWO-MACHINE,
-- TWO-NETWORK OXT pass. The boot self-check below is the single-machine half.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here.

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- enetxt/examples/enet-helpers.livecodescript ----

-- enet-helpers.livecodescript - the script-side poll dispatcher and sugar for
-- enetxt. Insert this script into the message path (e.g. `start using stack
-- "enetHelpers"` or as a behavior) so any stack can drive ENet with plain
-- event handlers instead of a manual poll loop.
--
-- THE MODEL, which this loop embodies: PUMP OR NOTHING. ENet has no threads;
-- connects, sends, retransmissions, pings, and receives ALL progress inside
-- enPoll. So this timer loop is not a convenience - it is the transport's
-- heartbeat, and its interval is the latency floor (16-33 ms feels real-time;
-- 100+ ms is fine for chat-grade traffic). One enPoll call per host per tick
-- drains every pending event in ONE FFI round-trip.
--
-- Unlike the datachannel sibling, polling here is PER HOST (an app can run a
-- server host and a client host at once - the LAN chat demo does). Register
-- each host with enStartPolling; each tick services every registered host and
-- dispatches its events to the target:
--   enetConnect     pEvent["host"], ["peer"], ["address"], ["data"]
--   enetDisconnect  pEvent["host"], ["peer"], ["data"]
--   enetReceive     pEvent["host"], ["peer"], ["channel"], ["payload"] (Data)
--   enetError       pEvent["host"], ["error"] (+["peer"] when known)
-- plus a catch-all "enetEvent" fired for EVERY event.

-- script-local poll state (declared at top; LiveCode Script script-locals)
local sPollHosts        -- comma list of host handles being pumped
local sEnPollTarget       -- object that receives the semantic event messages
local sEnPollInterval     -- milliseconds between drains (the latency knob)
local sEnPollNote         -- most recent pump failure, empty while healthy
local sEnPolling          -- "true" while the timer loop is armed

-- enStartPolling HOST, TARGET, INTERVALMS
-- Add HOST to the pump set and (first call) arm the loop. TARGET empty means
-- the current card; INTERVALMS defaults to 33 (about 30 Hz). One target and
-- one interval serve every registered host (last caller wins).
command enStartPolling pHost, pTarget, pIntervalMs
   local tSavedDelim
   if pHost is empty or pHost is 0 then
      exit enStartPolling
   end if
   -- sPollHosts is a COMMA list, but `among the items of` splits on whatever
   -- the itemDelimiter currently is - global mutable state this handler
   -- INHERITS from whoever called it (the family's LCS gotcha: set it
   -- immediately before use, never assume it). Set it around our own read and
   -- put back what we found: a helper must not decide the delimiter for the
   -- handler that called it. The writes below are delimiter-free (they append
   -- a literal comma), so only the read needs bracketing.
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   if pHost is not among the items of sPollHosts then
      if sPollHosts is empty then
         put pHost into sPollHosts
      else
         put comma & pHost after sPollHosts
      end if
   end if
   set the itemDelimiter to tSavedDelim
   if pTarget is empty then
      put the long id of this card into sEnPollTarget
   else
      put pTarget into sEnPollTarget
   end if
   if pIntervalMs is empty or pIntervalMs is not a number or pIntervalMs < 1 then
      put 33 into sEnPollInterval
   else
      put pIntervalMs into sEnPollInterval
   end if
   if sEnPolling is not "true" then
      put "true" into sEnPolling
      send "enetPollOnce" to me in 0 milliseconds
   end if
end enStartPolling

-- enStopPolling [HOST]
-- Remove one host from the pump set, or stop everything when HOST is empty.
-- Stopping the pump FREEZES the transport for the remaining app lifetime
-- (nothing progresses unpumped) - stop only what you are done with.
command enStopPolling pHost
   local tI, tNew, tSavedDelim
   if pHost is empty then
      put empty into sPollHosts
      put "false" into sEnPolling
      exit enStopPolling
   end if
   put empty into tNew
   -- Same bracketing as enStartPolling: this walk re-splits the comma list, so
   -- it sets the delimiter it needs and restores the caller's. Dropping the
   -- restore would leave OUR comma behind in the caller's handler, which is
   -- the same class of bug from the other direction.
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   repeat for each item tI in sPollHosts
      if tI is not pHost then
         if tNew is empty then
            put tI into tNew
         else
            put comma & tI after tNew
         end if
      end if
   end repeat
   set the itemDelimiter to tSavedDelim
   put tNew into sPollHosts
   if sPollHosts is empty then
      put "false" into sEnPolling
   end if
end enStopPolling

-- One pump pass: enPoll each registered host, dispatch each event by name,
-- then reschedule.
command enetPollOnce
   local tHost, tEvents, tEvent, tName, tSavedDelim, tErr
   if sEnPolling is not "true" then
      exit enetPollOnce
   end if
   -- The pump pass OWNS the delimiter for its whole length, not just for the
   -- split: every dispatch below runs app code, and app code that set the
   -- itemDelimiter would otherwise decide how the pump set is read for the
   -- rest of this pass. Comma is also the engine default, so a dispatched
   -- handler sees the same delimiter it would have seen from a bare timer
   -- message. Restored before we reschedule.
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   -- BOTH THE DRAIN AND THE DISPATCH ARE GUARDED, and each event is isolated.
   -- Two things this loop does can throw on a real engine: enPoll itself (its
   -- .lcb buffer helper is where the datachannel sibling reported "cannot
   -- convert value"), and the app code a dispatch reaches. Unguarded, either
   -- one kills the timer chain and the demo goes quiet with no symptom at all
   -- - the failure mode that turns one bug into several engine passes. A
   -- reported, skipped event costs one line of log; a dead pump costs a
   -- session. The note is READ rather than printed: see enPollLastError.
   repeat for each item tHost in sPollHosts
      put empty into tEvents
      try
         put enPoll(tHost) into tEvents
      catch tErr
         if sEnPollNote is empty then
            put "enPoll failed on host" && tHost & ": " & line 1 of tErr into sEnPollNote
         end if
         put empty into tEvents
      end try
      repeat for each element tEvent in tEvents
         put tEvent["name"] into tName
         try
            if tName is not empty then
               dispatch tName to sEnPollTarget with tEvent
            end if
            -- also fire a catch-all so one handler can observe the whole stream
            dispatch "enetEvent" to sEnPollTarget with tEvent
         catch tErr
            if sEnPollNote is empty then
               put "dispatch of" && tName & " failed: " & line 1 of tErr into sEnPollNote
            end if
         end try
      end repeat
   end repeat
   set the itemDelimiter to tSavedDelim
   -- DO NOT RE-ARM IF A DISPATCH STOPPED US. The pass above runs app code, and
   -- app code legitimately calls enStopPolling from inside a handler this
   -- very loop dispatched - enet-lan-chat does exactly that in `on
   -- enetDisconnect`. Re-arming unconditionally leaves a tick in flight after
   -- the flag went false, and the arm-once guard in enStartPolling tests that
   -- same flag: the next start sees "not polling", arms a SECOND chain, and
   -- the stale tick then re-arms the first. Two permanent chains, neither
   -- stoppable on its own because both read one flag - which is the trap the
   -- arm-once guard was added to prevent, reached from the other side.
   if sEnPolling is not "true" then
      exit enetPollOnce
   end if
   send "enetPollOnce" to me in (sEnPollInterval) milliseconds
end enetPollOnce

-- enPollLastError() -- empty while the pump is healthy; otherwise the FIRST
-- failure since the last enPollClearError, naming what threw. An app that
-- shows this in its own log turns "the demo went quiet" into a line a
-- maintainer can act on.
function enPollLastError
   return sEnPollNote
end enPollLastError

-- Clear it, so an app can report each distinct failure once.
command enPollClearError
   put empty into sEnPollNote
end enPollClearError

-- enStateName N -- map a kPeerState* value (enPeerStatus "state") to a label.
function enStateName pState
   switch pState
      case 0
         return "disconnected"
      case 1
      case 2
      case 3
      case 4
         return "connecting"
      case 5
         return "connected"
      case 6
      case 7
      case 8
         return "disconnecting"
      case 9
         return "zombie"
      default
         return "unknown"
   end switch
end enStateName

-- enFormatBytes N -- a small humaniser for dashboards (KiB/MiB/GiB).
function enFormatBytes pBytes
   local tUnits, tVal, tI, tSavedDelim, tOut
   if pBytes is empty or pBytes is not a number then
      return "0 B"
   end if
   put "B,KiB,MiB,GiB,TiB" into tUnits
   put pBytes into tVal
   put 1 into tI
   -- TWO reads need the comma, not one: the loop guard COUNTS the units and
   -- the return picks one. The `set` used to sit BETWEEN them, so the guard
   -- counted under whatever delimiter was in force rather than the one this
   -- data is written in - and under any delimiter but comma that string is a
   -- ONE-item list, so the loop never runs and a gigabyte reports itself in
   -- bytes. Set once before the FIRST read; restore before returning, since a
   -- humaniser has no business changing its caller's delimiter (the family's
   -- LCS gotcha: itemDelimiter is global mutable state - set it immediately
   -- before use, and put back what you found). Not a precaution: holde-em's
   -- v0.15 audit found three real leaks of exactly this shape - heStackFolder
   -- returning with the delimiter left at a slash, heSwapExt at a dot - and
   -- answered all three with save-and-restore.
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   repeat while tVal >= 1024 and tI < the number of items of tUnits
      put tVal / 1024 into tVal
      add 1 to tI
   end repeat
   put (the round of (tVal * 10) / 10) && (item tI of tUnits) into tOut
   set the itemDelimiter to tSavedDelim
   return tOut
end enFormatBytes

-- ---- torrentxt/examples/torrent-helpers.livecodescript ----

-- torrent-helpers.livecodescript - the script-side poll dispatcher and sugar
-- for TorrentXT (plan section 3). Insert this script into the message path (e.g.
-- `start using stack "torrentHelpers"` or as a behavior) so any stack can drive
-- the engine with plain event handlers instead of a manual poll loop.
--
-- The model (plan section 3, carried verbatim from ShowControl): the engine NEVER
-- calls back into script. libtorrent buffers every event on its own threads;
-- we drain that buffer on a timer with ONE FFI round-trip (btPoll), then `send`
-- one semantic message per event. Throughput and event integrity are
-- independent of the poll cadence - only worst-case latency scales with it - so
-- the interval is a documented latency/CPU knob (250 ms is plenty for a UI;
-- tighten only for very smooth live dashboards).

-- script-local poll state (declared at top; LiveCode Script script-locals)
local sPollSession      -- the session handle currently being polled (0/empty = none)
local sPollTarget       -- object that receives the semantic event messages
local sPollInterval     -- milliseconds between drains (the latency/CPU knob)
local sPolling          -- "true" while the timer loop is armed

-- btStartPolling SESSION, TARGET, INTERVALMS
-- Begin draining SESSION's events and dispatching them to TARGET. If TARGET is
-- empty, events go to the current card. INTERVALMS defaults to 250. Calling it
-- again while polling re-points the session, target and interval (last caller
-- wins); it does NOT arm a second chain.
command btStartPolling pSession, pTarget, pIntervalMs
   put pSession into sPollSession
   if pTarget is empty then
      put the long id of this card into sPollTarget
   else
      put pTarget into sPollTarget
   end if
   if pIntervalMs is empty or pIntervalMs is not a number or pIntervalMs < 1 then
      put 250 into sPollInterval
   else
      put pIntervalMs into sPollInterval
   end if
   -- Arm the chain ONCE - the guard enet-helpers has carried since it was
   -- written, and the one this file lacked. A second chain does not duplicate
   -- EVENTS: each pass drains the whole alert queue in one btPoll (and one
   -- btRp1Poll), so the second chain mostly finds it empty. What doubles,
   -- permanently, is the FFI drain RATE and the timer churn - and neither
   -- chain can be stood down on its own, because both read this one flag.
   if sPolling is not "true" then
      put "true" into sPolling
      -- kick the loop immediately; it reschedules itself
      send "btTorrentPollOnce" to me in 0 milliseconds
   end if
end btStartPolling

-- Stop the timer loop. Safe to call when not polling.
command btStopPolling
   put "false" into sPolling
end btStopPolling

-- One drain pass: pull all pending events with a single btPoll, dispatch each,
-- then reschedule. btPoll returns a list of event arrays (see the key list in
-- docs/api-reference.md); each array carries a "name" (the semantic message)
-- and a "torrent" handle plus event-specific keys.
command btTorrentPollOnce
   local tEvents, tEvent, tName
   if sPolling is not "true" then
      exit btTorrentPollOnce
   end if
   if sPollSession is empty or sPollSession is 0 then
      exit btTorrentPollOnce
   end if
   put btPoll(sPollSession) into tEvents
   repeat for each element tEvent in tEvents
      put tEvent["name"] into tName
      if tName is not empty then
         dispatch tName to sPollTarget with tEvent
      end if
      -- also fire a catch-all so one handler can observe the whole stream
      dispatch "torrentEvent" to sPollTarget with tEvent
   end repeat
   -- ALSO drain the rp1 extension's own event stream (peer up/down, handshake,
   -- message). It is a SEPARATE queue from btPoll and returns empty when rp1 is
   -- not enabled on the session, so this is a harmless no-op for normal apps and
   -- gives rp1 apps the same dispatch-by-name flow (rp1PeerConnected, rp1Handshake,
   -- rp1Message, rp1PeerDisconnected).
   put btRp1Poll(sPollSession) into tEvents
   repeat for each element tEvent in tEvents
      put tEvent["name"] into tName
      if tName is not empty then
         dispatch tName to sPollTarget with tEvent
      end if
      dispatch "torrentEvent" to sPollTarget with tEvent
   end repeat
   -- reschedule (libtorrent keeps buffering between drains)
   send "btTorrentPollOnce" to me in (sPollInterval) milliseconds
end btTorrentPollOnce

-- btFormatBytes N -- a small humaniser for dashboards (KiB/MiB/GiB).
function btFormatBytes pBytes
   local tUnits, tVal, tI, tSavedDelim, tOut
   if pBytes is empty or pBytes is not a number then
      return "0 B"
   end if
   put "B,KiB,MiB,GiB,TiB" into tUnits
   put pBytes into tVal
   put 1 into tI
   -- TWO reads need the comma, not one: the loop guard COUNTS the units and
   -- the return picks one. The `set` used to sit BETWEEN them, so the guard
   -- counted under whatever delimiter was in force rather than the one this
   -- data is written in - and under any delimiter but comma that string is a
   -- ONE-item list, so the loop never runs and a gigabyte reports itself in
   -- bytes. Set once before the FIRST read; restore before returning, since a
   -- humaniser has no business changing its caller's delimiter (the family's
   -- LCS gotcha: itemDelimiter is global mutable state - set it immediately
   -- before use, and put back what you found). Not a precaution: holde-em's
   -- v0.15 audit found three real leaks of exactly this shape - heStackFolder
   -- returning with the delimiter left at a slash, heSwapExt at a dot - and
   -- answered all three with save-and-restore.
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   repeat while tVal >= 1024 and tI < the number of items of tUnits
      put tVal / 1024 into tVal
      add 1 to tI
   end repeat
   put (the round of (tVal * 10) / 10) && (item tI of tUnits) into tOut
   set the itemDelimiter to tSavedDelim
   return tOut
end btFormatBytes

-- btStateName N -- map a libtorrent torrent_status::state_t int to a label.
function btStateName pState
   switch pState
      case 1
         return "checking"
      case 2
         return "fetching metadata"
      case 3
         return "downloading"
      case 4
         return "finished"
      case 5
         return "seeding"
      case 7
         return "checking resume"
      default
         return "queued"
   end switch
end btStateName

-- <<< END EMBEDDED LIBRARIES <<<

-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kEiUiVersion = "enetinet-kit2-2"
-- The connect-data protocol version (distinct from the LAN chat's, so a
-- mis-paste between the two demos refuses loudly instead of garbling).
constant kEiProto = 2
-- A port of our own: the LAN chat holds 27099 on the same machine.
constant kEiPort = 27199

-- ---- script-local state (declared at top) ------------------------------------
local sHost             -- our ENet host handle (server or client; 0/empty = none)
local sIsServer         -- "true" when we hosted
local sServerPeer       -- client role: the peer handle to the server
local sPeers            -- server role: array peer -> display address
local sReady            -- "true" once hosting/joined and (client) connected
local sHaveEn           -- "true" once the enetxt probe succeeded
local sHaveBt           -- "true" once the torrentxt probe succeeded (host side only needs it)
local sDashOn           -- "true" while the 1 Hz dashboard chain may reschedule
-- the internet layer (host role; all empty when torrentxt is absent)
local sBtSession        -- the TorrentXT session handle driving UPnP + IP discovery
local sMapId            -- the btMapPort mapping id (0/empty = none)
local sMapped           -- "true" once portMapped confirmed the router opened our UDP port
local sExtIp            -- the discovered public IP (externalIp event), or empty

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
-- ---- contextual menus -------------------------------------------------------
--
-- A RIGHT-CLICK MENU, as one hidden popup button per menu.
--
-- The engine's contextual menu is a BUTTON whose style is "menu" and whose
-- menuMode is "popup": its text is the item list, one per line, `popup`
-- shows it at a point, and choosing an item sends `menuPick` with the item's
-- LABEL. The button needs no script - with no handler of its own the message
-- walks the hierarchy and arrives at the card and then the stack, which is
-- where an adopter's router already lives.
--
-- OPT-IN, AND THAT IS DELIBERATE. This block is carried byte-identical by
-- every demo in the suite, so a kit that BUILT a menu would change eighteen
-- stacks to serve one. Nothing here runs unless an adopter calls
-- uiContextMenu, and a demo that never does is unchanged in behaviour.
--
-- NONE OF THIS HAS RUN ON AN ENGINE. `popup`, `menuMode` and `menuPick` are
-- documented LiveCode and OpenXTalk is a fork of it, but this suite has never
-- exercised a menu and the headless runners model no mouse button at all - so
-- an adopter's right-click handler belongs in a `try`, and losing the menu
-- must never cost the ordinary click. uiPopupMenu answers whether it worked
-- rather than throwing, so the caller can decide.

command uiContextMenu pName, pItems
   -- One hidden popup button, created once and refilled on every call so a
   -- menu can change with the screen it belongs to. The rect is small and
   -- inside the window because a stack's controls are measured by
   -- tools/check-stack-size.py whether they are visible or not.
   if there is no button pName then
      -- THE KIT'S OWN IDIOM, and not `create button pName`. Every other
      -- builder in this block creates the control unnamed and then names the
      -- last one, which is the spelling the family's headless runners model
      -- and the one every adopter has already been through an engine with.
      create button
      set the name of the last button to pName
   end if
   set the style of button pName to "menu"
   set the menuMode of button pName to "popup"
   set the text of button pName to pItems
   set the rect of button pName to "2,2,18,18"
   set the visible of button pName to false
end uiContextMenu

function uiPopupMenu pName
   -- WHICH menu, recorded before it opens. menuPick carries the item's label
   -- and nothing else, so an adopter with two menus would otherwise have to
   -- keep every label in the stack globally unique - a constraint that is
   -- invisible until the day two screens both want "Copy".
   --
   -- Answers true or false rather than throwing: on an engine without popup
   -- menus the right thing is for the click to do nothing, not for the
   -- adopter's mouseDown to die.
   local tError
   if there is no button pName then
      return false
   end if
   set the uUiMenu of this stack to pName
   try
      popup button pName at the clickLoc
   catch tError
      set the uUiMenu of this stack to empty
      return false
   end try
   return true
end uiPopupMenu

function uiMenuSource
   -- The name of the menu the last menuPick came from.
   return the uUiMenu of this stack
end uiMenuSource

-- ==== SUITE UI KIT v2 END ====

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   eiBuild
   eiStart
   -- LAST, not first: the check reads state eiStart establishes (the probes,
   -- the armed dashboard) and asserting before it would test nothing.
   eiScRun
end openStack

on closeStack
   eiStop
end closeStack

on mouseUp
   switch the short name of the target
      case "eiHost"
         eiHost
         break
      case "eiJoin"
         eiJoin
         break
      case "eiLeave"
         eiLeave
         break
      case "eiSend"
         eiSendLine
         break
      case "eiCopy"
         eiCopyInvite
         break
      default
         pass mouseUp
   end switch
end mouseUp

on returnInField
   switch the short name of the target
      case "eiMsg"
         eiSendLine
         break
      case "eiAddr"
         eiJoin
         break
      default
         pass returnInField
   end switch
end returnInField

-- ---- self-building UI (idempotent; rebuilds on a version bump) ----------------
command eiBuild
   if the uEiUiVersion of this stack is kEiUiVersion and there is a field "eiMsg" then
      exit eiBuild
   end if
   eiClearGeneratedUI
   lock screen
   uiChrome "enetxt INTERNET chat - reliable UDP across the real internet", 560, 640
   uiCap "eiTagline", "Host opens the router port itself (UPnP via TorrentX" \
         & "T) and shows an invite. A friend on ANOTHER network pastes it and" \
         & " Joins. The chat bytes are pure ENet; the pill below turns green" \
         & " only when the remote address is genuinely public.", "16,56,544,96"
   -- host row: the button, then the invite readout + copy
   uiButton "eiHost", "Host (UDP " & kEiPort & ")", "16,102,180,132"
   uiCap "eiInviteCap", "your invite (give this to the joiner):", "190,100,544,116"
   uiInput "eiInvite", "190,118,470,142"
   set the lockText of field "eiInvite" to true
   uiButton "eiCopy", "Copy", "476,116,544,146"
   -- join row
   uiCap "eiAddrCap", "or paste an invite (ip[:port]) and:", "16,152,300,168"
   uiInput "eiAddr", "16,170,410,194"
   uiButton "eiJoin", "Join", "416,168,478,198"
   uiButton "eiLeave", "Leave", "484,168,544,198"
   -- name + the proof panel
   uiCap "eiNameCap", "Your name:", "16,208,100,226"
   uiInput "eiName", "100,206,240,230"
   uiPill "eiNetPill", "OFFLINE", "250,206,360,228", empty
   uiLabel "eiProof", empty, "368,208,544,226", 10
   set the textFont of field "eiProof" to uiMonoFont()
   -- log + message box (the status line is the kit's, under the title band)
   uiArea "eiLog", "16,238,544,528"
   uiInput "eiMsg", "16,536,420,562"
   uiButton "eiSend", "Send", "430,534,544,564"
   uiFooter \
         "Chat relays through the host IN THE CLEAR - a transport demo, not a" \
         & " private messenger. The pill is the claim: green means the peer" \
         & " address is public, so these bytes crossed the internet. Verified" \
         & " statically; the two-network run is the leg this stack exists for.", \
         "16,572,544,634"
   set the uEiUiVersion of this stack to kEiUiVersion
   unlock screen
end eiBuild

command eiClearGeneratedUI
   local tI
   lock screen
   repeat with tI = the number of fields of this card down to 1
      if the short name of field tI of this card begins with "ei" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      if the short name of button tI of this card begins with "ei" then
         delete button tI of this card
      end if
   end repeat
   repeat with tI = the number of graphics of this card down to 1
      if the short name of graphic tI of this card begins with "ei" then
         delete graphic tI of this card
      end if
   end repeat
   unlock screen
end eiClearGeneratedUI

-- ---- startup / teardown ------------------------------------------------------
command eiStart
   local tR, tErr
   -- probe enetxt with a guarded call; fail closed with a clear message when
   -- it is missing (the family's SodiumXT probe pattern)
   put empty into sHaveEn
   try
      put enInitialize() into tR
   catch tErr
      eiLog "The enetxt extension is not installed (org.openxtalk.library.enet) - install it and reopen this stack."
      uiStatus "enetxt NOT loaded: install org.openxtalk.library.enet and reopen.", "bad"
      exit eiStart
   end try
   if tR is not 0 then
      eiLog "enetxt failed to initialise:" && enLastError()
      uiStatus "enetxt failed to initialise - see the log.", "bad"
      exit eiStart
   end if
   put "true" into sHaveEn
   -- probe torrentxt the same way: a stale-handle getter is a harmless no-op
   -- when the extension is present, and a hard `handler not found` when it is
   -- not. Only the HOST role needs it; a joiner without it still joins.
   put empty into sHaveBt
   try
      get btListenPort(0)
      put "true" into sHaveBt
   catch tErr
      put empty into sHaveBt
   end try
   if sHaveBt is "true" then
      eiLog "Ready (" & enLibraryVersion() & " + TorrentXT for the door). Host, or paste an invite and Join."
   else
      eiLog "Ready (" & enLibraryVersion() & "). TorrentXT is NOT installed: Hosting needs a manually forwarded UDP port" && kEiPort & "; Joining works as-is."
   end if
   uiStatus "Ready. Host (invite appears), or paste an invite and Join.", "ok"
   eiPill "OFFLINE", empty
   -- arm the dashboard chain ONCE; a re-fired openStack must not stack a
   -- second chain (the dht-chat re-entrancy rule)
   if sDashOn is not "true" then
      put "true" into sDashOn
      send "eiDashOnce" to me in 800 milliseconds
   end if
end eiStart

command eiStop
   local tErr
   put "false" into sDashOn
   if sHost is not empty and sHost is not 0 then
      enHostDestroy sHost
   end if
   put empty into sHost
   put empty into sServerPeer
   put empty into sPeers
   put "false" into sReady
   try
      enStopPolling
   catch tErr
      -- helpers gone; nothing was polling
   end try
   -- withdraw the router mapping and release the TorrentXT session. Both
   -- guarded twice over: the handles may never have existed (join role, or no
   -- torrentxt), and closeStack must never throw.
   try
      if sBtSession is not empty and sBtSession is not 0 then
         if sMapId is not empty and sMapId is not 0 then
            get btUnmapPort(sBtSession, sMapId)
         end if
         btStopPolling
         btStopSession sBtSession
      end if
   catch tErr
      -- extension gone or session already dead; nothing to release
   end try
   put empty into sBtSession
   put empty into sMapId
   put "false" into sMapped
   put empty into sExtIp
   -- the one mandatory enet teardown (bare command form - OXT cannot compile
   -- a zero-argument name() statement). Guarded like the eiStart probe.
   try
      enDeinitialize
   catch tErr
      -- extension not installed; nothing to release
   end try
end eiStop

-- ---- host / join / leave -----------------------------------------------------
command eiHost
   if sHaveEn is not "true" then
      eiLog "enetxt is not loaded - install org.openxtalk.library.enet and reopen."
      exit eiHost
   end if
   if sHost is not empty and sHost is not 0 then
      eiLog "Already hosting or joined - Leave first."
      exit eiHost
   end if
   put enHostCreateServer("", kEiPort, 32, 2, 0, 0) into sHost
   if sHost is 0 or sHost is empty then
      eiLog "Could not host (port in use?):" && enLastError()
      put empty into sHost
      exit eiHost
   end if
   put "true" into sIsServer
   put empty into sPeers
   put "true" into sReady
   enStartPolling sHost, the long id of this card, 33
   eiLog "Hosting on UDP" && kEiPort & "."
   -- the internet door: a TorrentXT session whose only jobs are (1) ask the
   -- router to open OUR UDP port and (2) learn this machine's public IP. The
   -- DHT is enabled because IP discovery rides real traffic: libtorrent
   -- reports the external address it is seen as (the externalIp event) once
   -- bootstrap answers arrive. Chat traffic never touches this session.
   if sHaveBt is not "true" then
      eiLog "* TorrentXT is not installed, so the router will NOT be opened automatically. Forward UDP" && kEiPort && "to this machine and give the joiner <your-public-ip>:" & kEiPort & "."
      eiShowInvite
      exit eiHost
   end if
   put btStartSession() into sBtSession
   if sBtSession is 0 or sBtSession is empty then
      eiLog "* TorrentXT session failed to start - falling back to a manual port forward (UDP" && kEiPort & ")."
      put empty into sBtSession
      eiShowInvite
      exit eiHost
   end if
   btSetBool sBtSession, "enable_upnp", true
   btSetBool sBtSession, "enable_natpmp", true
   btSetBool sBtSession, "enable_dht", true
   btDhtAddBootstrap sBtSession, "router.bittorrent.com", 6881
   btDhtAddBootstrap sBtSession, "router.utorrent.com", 6881
   btDhtAddBootstrap sBtSession, "dht.transmissionbt.com", 6881
   btStartPolling sBtSession, the long id of this card, 500
   -- FALSE = UDP: quickshare maps TCP for its HTTP link; ENet is UDP, and a
   -- TCP mapping would test green at the router while every packet drops.
   put btMapPort(sBtSession, kEiPort, kEiPort, false) into sMapId
   if sMapId is 0 or sMapId is empty then
      eiLog "* no router port-mapper answered (no UPnP/NAT-PMP?) - a portMapError may still follow. Manual fix: forward UDP" && kEiPort && "to this machine."
   else
      eiLog "* asked the router to open UDP" && kEiPort && "- waiting for it to confirm (portMapped) and for the public IP (externalIp)..."
   end if
   eiShowInvite
end eiHost

command eiJoin
   local tParsed, tHost, tPort, tSavedDelim
   if sHaveEn is not "true" then
      eiLog "enetxt is not loaded - install org.openxtalk.library.enet and reopen."
      exit eiJoin
   end if
   if sHost is not empty and sHost is not 0 then
      eiLog "Already hosting or joined - Leave first."
      exit eiJoin
   end if
   put eiParseInvite(eiTrim(the text of field "eiAddr")) into tParsed
   if tParsed is empty then
      eiLog "Paste the host's invite (ip or ip:port) first."
      exit eiJoin
   end if
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "|"
   put item 1 of tParsed into tHost
   put item 2 of tParsed into tPort
   set the itemDelimiter to tSavedDelim
   put enHostCreateClient(1, 2, 0, 0) into sHost
   if sHost is 0 or sHost is empty then
      eiLog "Could not create a client host:" && enLastError()
      put empty into sHost
      exit eiJoin
   end if
   put "false" into sIsServer
   put enConnect(sHost, tHost, tPort, 2, kEiProto) into sServerPeer
   if sServerPeer is 0 or sServerPeer is empty then
      eiLog "Could not start connecting:" && enLastError()
      enHostDestroy sHost
      put empty into sHost
      exit eiJoin
   end if
   enStartPolling sHost, the long id of this card, 33
   eiLog "Connecting to" && tHost & ":" & tPort & "..."
   uiStatus "Connecting to" && tHost & ":" & tPort & "...", empty
   eiPill "CONNECTING", "wait"
   send "eiJoinWatch" to me in 15000 milliseconds
end eiJoin

-- The join watchdog: ENet retries quietly for ~30 s before giving up, so a
-- blocked path reads as a hang. Name the INTERNET causes while it still
-- tries; the definitive verdict arrives in enetDisconnect below.
command eiJoinWatch
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and
   -- every control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sIsServer is "true" or sReady is "true" then
      exit eiJoinWatch
   end if
   if sHost is empty or sHost is 0 then
      exit eiJoinWatch
   end if
   eiLog "* still connecting. Internet causes, in order: (1) the host's router has not opened UDP - the HOST's log must say the port was confirmed (portMapped), else they forward it by hand; (2) the invite IP is stale (routers re-lease); (3) the host machine's own firewall blocks inbound UDP" && kEiPort & "; (4) a carrier-grade NAT on the host's line that no mapper can open - host from the other side instead; (5) BOTH machines are on the SAME network - the invite points at your shared router's PUBLIC ip, and most home routers refuse to hairpin that back inside (engine-reported 2026-08-27). Same network: use the LAN chat demo. The real internet leg needs the joiner on a different network (a phone hotspot is the easy one)."
end eiJoinWatch

command eiLeave
   if sHost is empty or sHost is 0 then
      exit eiLeave
   end if
   -- polite goodbye when we are a connected client; the host just vanishes
   -- (its peers all see enetDisconnect within their timeout)
   if sIsServer is not "true" and sServerPeer is not empty and sServerPeer is not 0 then
      enDisconnect sServerPeer, 0
      enFlush sHost
   end if
   enStopPolling sHost
   enHostDestroy sHost
   put empty into sHost
   put empty into sServerPeer
   put empty into sPeers
   put "false" into sReady
   eiLog "Left."
   uiStatus "Not connected.", empty
   eiPill "OFFLINE", empty
end eiLeave

-- ---- the TorrentXT door events (dispatched by torrent-helpers) ---------------

on externalIp pEvent
   put pEvent["externalIp"] into sExtIp
   if sIsServer is "true" then
      eiLog "* your public IP is" && sExtIp & "."
      eiShowInvite
   end if
end externalIp

on portMapped pEvent
   if sIsServer is "true" then
      put "true" into sMapped
      eiLog "* router opened UDP" && pEvent["externalPort"] && "via" && pEvent["transport"] && "- the door is open."
      eiShowInvite
   end if
end portMapped

on portMapError pEvent
   if sIsServer is "true" then
      eiLog "* the router refused to open the port automatically. Manual fix: forward UDP" && kEiPort && "to this machine in the router settings; the invite below still fills in once the public IP is known."
      eiShowInvite
   end if
end portMapError

-- The invite line + status, from ONE place so its states cannot disagree.
command eiShowInvite
   local tInvite
   if sIsServer is not "true" then
      exit eiShowInvite
   end if
   if sExtIp is empty then
      put "waiting for the public IP..." into tInvite
   else
      put sExtIp & ":" & kEiPort into tInvite
   end if
   if there is a field "eiInvite" then
      put tInvite into field "eiInvite"
   end if
   if sExtIp is not empty and sMapped is "true" then
      uiStatus "Hosting - the door is OPEN. Send the invite:" && tInvite, "ok"
   else if sExtIp is not empty then
      uiStatus "Hosting - invite ready; router NOT confirmed (see the log).", "warn"
   else
      uiStatus "Hosting - waiting for the router and the public IP...", empty
   end if
end eiShowInvite

command eiCopyInvite
   local tInvite
   if there is no field "eiInvite" then
      exit eiCopyInvite
   end if
   put the text of field "eiInvite" into tInvite
   if tInvite is empty or tInvite contains "waiting" then
      eiLog "Nothing to copy yet - Host first, then wait for the invite to fill in."
      exit eiCopyInvite
   end if
   set the clipboardData["text"] to tInvite
   uiCopyFlash "eiCopy"
end eiCopyInvite

-- ---- events (dispatched by enet-helpers) -------------------------------------

on enetConnect pEvent
   if sIsServer is "true" then
      -- refuse a protocol mismatch loudly instead of garbling later (a paste
      -- into the LAN chat, or an old build, lands here)
      if pEvent["data"] is not kEiProto then
         eiLog "* refused a peer with protocol" && pEvent["data"] && "(we speak" && kEiProto & ")"
         enDisconnectNow pEvent["peer"], 0
         exit enetConnect
      end if
      put pEvent["address"] into sPeers[pEvent["peer"]]
      eiLog "* " & pEvent["address"] && "joined (" & the number of lines of the keys of sPeers & " here)" && eiNetTag(pEvent["address"])
      eiRelay "* " & pEvent["address"] && "joined"
   else
      put "true" into sReady
      eiLog "* connected - say something!"
      uiStatus "Connected.", "ok"
   end if
end enetConnect

on enetDisconnect pEvent
   if sIsServer is "true" then
      if pEvent["peer"] is among the keys of sPeers then
         eiLog "* " & sPeers[pEvent["peer"]] && "left"
         eiRelay "* " & sPeers[pEvent["peer"]] && "left"
         delete variable sPeers[pEvent["peer"]]
      end if
   else
      if sReady is "true" then
         eiLog "* disconnected from the host"
         uiStatus "Not connected.", empty
         eiPill "OFFLINE", empty
      else
         -- no enetConnect ever arrived: ENet gave up on the CONNECT. Name the
         -- internet causes (the watchdog's list, now definitive).
         eiLog "* could not connect (ENet gave up). Is the host's router port confirmed open (their log says portMapped)? Is the invite current? Are you on the SAME network as the host (the public-ip invite cannot hairpin on most routers - use the LAN chat demo there)? See the watchdog list above."
         uiStatus "Connect FAILED - see the log.", "bad"
         eiPill "FAILED", "bad"
      end if
      put "false" into sReady
      -- release the half-open client host so Join works again. THE GUARD IS
      -- NOT DEFENSIVE PADDING: enHostDestroy is `in pHost as Integer`, this
      -- handler empties sHost below, and ENet delivers one enetDisconnect per
      -- peer - the second one handed EMPTY to a typed parameter, which is a
      -- hard runtime error that killed the LAN chat's poll chain on a real
      -- engine (OXT-ENGINE-NOTES 6.4).
      if sHost is not empty and sHost is not 0 then
         enStopPolling sHost
         enHostDestroy sHost
      end if
      put empty into sHost
      put empty into sServerPeer
   end if
end enetDisconnect

on enetReceive pEvent
   local tLine
   put textDecode(pEvent["payload"], "utf-8") into tLine
   if sIsServer is "true" then
      -- a client's line: show it here and relay to everyone (including the
      -- sender - the echo doubles as their delivery receipt)
      eiLog tLine
      eiRelay tLine
   else
      eiLog tLine
   end if
end enetReceive

on enetError pEvent
   eiLog "* transport error:" && pEvent["error"]
end enetError

-- ---- sending -----------------------------------------------------------------
command eiSendLine
   local tBody, tName, tLine, tR
   put eiTrim(the text of field "eiMsg") into tBody
   if tBody is empty then
      exit eiSendLine
   end if
   if sHost is empty or sHost is 0 then
      eiLog "Host or Join first."
      exit eiSendLine
   end if
   put eiTrim(the text of field "eiName") into tName
   if tName is empty then
      put "me" into tName
   end if
   put tName & ": " & tBody into tLine
   if sIsServer is "true" then
      eiLog tLine
      eiRelay tLine
   else
      if sReady is not "true" then
         eiLog "Not connected yet."
         exit eiSendLine
      end if
      put enSendText(sServerPeer, 0, tLine, 0) into tR -- 0 = reliable
      if tR is not 0 then
         eiLog "Send failed (" & tR & "):" && enLastError()
         exit eiSendLine
      end if
   end if
   set the text of field "eiMsg" to ""
end eiSendLine

-- Server fanout: ONE broadcast reaches every connected peer. The return is
-- checked because a failed relay is invisible to every participant including
-- the host - the one silent failure this demo cannot afford.
command eiRelay pLine
   local tR
   if sIsServer is "true" and sHost is not empty and sHost is not 0 then
      put enBroadcastText(sHost, 0, pLine, 0) into tR -- 0 = reliable
      if tR is not 0 then
         eiLog "* relay FAILED (" & tR & "):" && enLastError()
      end if
   end if
end eiRelay

-- ---- the 1 Hz dashboard + the proof panel ------------------------------------
command eiDashOnce
   local tPS, tPollErr, tAddr, tPub, tAny, tPeer, tCount
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and
   -- every control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sDashOn is not "true" then
      exit eiDashOnce
   end if
   send "eiDashOnce" to me in 1000 milliseconds
   -- surface a pump failure ONCE, in this demo's own log (the LAN chat's
   -- lesson: a throw inside the pump is otherwise invisible)
   put enPollLastError() into tPollErr
   if tPollErr is not empty then
      enPollClearError
      eiLog "* event pump problem:" && tPollErr
      eiLog "* (The chat keeps polling. Please report that line - it names what threw.)"
   end if
   if sHost is empty or sHost is 0 then
      exit eiDashOnce
   end if
   if sIsServer is "true" then
      put the number of lines of the keys of sPeers into tCount
      -- the proof, host side: any peer whose address is PUBLIC proves the
      -- path crossed the internet; all-private peers are an honest LAN test
      put "false" into tAny
      repeat for each line tPeer in the keys of sPeers
         if eiIsPrivateAddr(sPeers[tPeer]) is false then
            put "true" into tAny
         end if
      end repeat
      if tCount is 0 then
         eiPill "WAITING", "wait"
         eiProofLine "no peers yet"
      else if tAny is "true" then
         eiPill "INTERNET LIVE", "ok"
         eiProofLine tCount && "peer(s), public address seen"
      else
         eiPill "LAN ONLY", "wait"
         eiProofLine tCount && "peer(s), all private addresses"
      end if
      uiStatus "Hosting on UDP" && kEiPort && "-" && tCount && "peer(s). Invite:" && the text of field "eiInvite", "ok"
   else if sServerPeer is not empty and sServerPeer is not 0 then
      put enPeerStatus(sServerPeer) into tPS
      if the number of lines of the keys of tPS is 0 then
         uiStatus "Peer status unavailable.", empty
      else if tPS["state"] is 5 then
         put tPS["address"] into tAddr
         put (eiIsPrivateAddr(tAddr) is false) into tPub
         if tPub is true then
            eiPill "INTERNET LIVE", "ok"
         else
            eiPill "LAN ONLY", "wait"
         end if
         eiProofLine tPS["rtt"] & "ms" && tPS["packetLoss"] & "% loss" && enFormatBytes(tPS["bytesReceived"]) && "rx"
         uiStatus "Connected to" && tAddr && "-" && tPS["rtt"] & " ms rtt -" && enFormatBytes(tPS["bytesSent"]) && "tx /" && enFormatBytes(tPS["bytesReceived"]) && "rx", "ok"
      else
         uiStatus "Peer state:" && enStateName(tPS["state"]), empty
      end if
   end if
end eiDashOnce

-- The pill, from ONE place so its states cannot disagree (the nocloud
-- Tor-pill discipline; uiPill is idempotent, so a repaint is a rebuild).
command eiPill pText, pKind
   uiPill "eiNetPill", pText, "250,206,360,228", pKind
end eiPill

command eiProofLine pText
   if there is no field "eiProof" then
      exit eiProofLine
   end if
   put pText into field "eiProof"
end eiProofLine

-- ---- small helpers -----------------------------------------------------------

-- Is this "ip:port" (or bare ip) a PRIVATE/non-routable IPv4 address? The
-- proof pill turns on its answer, so the ranges are spelled out rather than
-- guessed: RFC 1918 (10/8, 172.16/12, 192.168/16), loopback (127/8), and
-- link-local (169.254/16). Anything else - including IPv6, which ENet
-- prints bracketed - counts as public here; a false green from an exotic
-- private range is a cosmetic error, and the address is printed beside the
-- pill so a human can always overrule it.
function eiIsPrivateAddr pAddr
   local tHost, tSavedDelim, tA, tB
   if pAddr is empty then
      return true
   end if
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to ":"
   put item 1 of pAddr into tHost
   set the itemDelimiter to "."
   put item 1 of tHost into tA
   put item 2 of tHost into tB
   set the itemDelimiter to tSavedDelim
   if tA is not a number then
      return false
   end if
   if tA is 10 or tA is 127 then
      return true
   end if
   if tA is 169 and tB is 254 then
      return true
   end if
   if tA is 172 and tB is a number and tB >= 16 and tB <= 31 then
      return true
   end if
   if tA is 192 and tB is 168 then
      return true
   end if
   return false
end eiIsPrivateAddr

-- Parse an invite: "ip" or "ip:port" -> "host|port" (default kEiPort), or
-- empty for nothing usable. A function so the boot self-check can drive it.
function eiParseInvite pText
   local tHost, tPort, tSavedDelim
   if pText is empty then
      return empty
   end if
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to ":"
   put item 1 of pText into tHost
   if the number of items of pText > 1 then
      put item 2 of pText into tPort
   else
      put kEiPort into tPort
   end if
   set the itemDelimiter to tSavedDelim
   if tHost is empty then
      return empty
   end if
   if tPort is not a number then
      put kEiPort into tPort
   end if
   return tHost & "|" & tPort
end eiParseInvite

-- The address tag the host logs beside a join: names the class the proof
-- pill will report, so the log carries the evidence too.
function eiNetTag pAddr
   if eiIsPrivateAddr(pAddr) is true then
      return "[private address - LAN]"
   end if
   return "[PUBLIC address - internet]"
end eiNetTag

command eiLog pMsg
   if there is no field "eiLog" then
      exit eiLog
   end if
   put pMsg & return after field "eiLog"
   set the vscroll of field "eiLog" to the formattedHeight of field "eiLog"
end eiLog

function eiTrim pText
   return word 1 to -1 of pText
end eiTrim

-- ---- the boot self-check ------------------------------------------------------
-- The plumbing is CARRIED (master: tools/demo-selfcheck.livecodescript; gate:
-- tools/check-demo-selfcheck-drift.py). What this file owns is the list of
-- assertions below - what is true about THIS demo at boot.
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
   local tName, tMissing, tC, tFound
   set the defaultStack to the short name of this stack
   repeat for each item tName in pList
      -- ALL FOUR CONTROL TYPES. The kit builds fields (uiLabel/uiWrap/uiCap/
      -- uiSection/uiInput/uiArea/uiTable), buttons (uiButton/uiCheckbox) AND
      -- GRAPHICS (uiGfx/uiPanel/uiPill). The first version of this asked only
      -- about fields and buttons, so every uiPill a demo builds - the Tor
      -- pills in both Quick Shares, for one - reported as a missing control on
      -- a stack where it exists.
      --
      -- AND IMAGES (2026-08-31), for the same reason one step further out. A
      -- demo may build a control the KIT does not: coinxt's wallet paints a
      -- QR into an image, which is the only way a BMP this family builds
      -- becomes something a phone can read. Registered and built, it reported
      -- as missing - found by coinxt/tools/check-wallet-boot.py, which boots
      -- the stack headlessly, so this one cost no engine time. The lesson is
      -- the one this block already carries twice: the list of types a demo
      -- can build is not the list of types the KIT builds.
      --
      -- AND EVERY CARD (2026-08-29). Unqualified `there is a field X` answers
      -- for the CURRENT card only (engine notes 5.6) - OBSERVED when
      -- riptide's five-card boot reported all 63 off-card controls missing
      -- from a stack where every one existed. A single-card demo walks its
      -- one card here, exactly the old behaviour.
      put false into tFound
      repeat with tC = 1 to the number of cards of this stack
         if there is a field tName of card tC \
               or there is a button tName of card tC \
               or there is a graphic tName of card tC \
               or there is an image tName of card tC then
            put true into tFound
            exit repeat
         end if
      end repeat
      if not tFound then
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

-- Every control name this script references, derived from the source rather
-- than hand-picked: a subset would go stale the first time somebody renames
-- one, and a missing control is not cosmetic - it is the "Chunk: error in
-- object expression" class, found at boot instead of when somebody clicks.
constant kEiScControls = "eiAddr,eiAddrCap,eiCopy,eiHost,eiInvite,eiInviteCap,eiJoin,eiLeave,eiLog,eiMsg,eiName,eiNameCap,eiNetPill,eiProof,eiSend,eiTagline,uiFooter,uiStatus,uiTitle"

command eiScRun
   local tMissing, tVer, tRc, tName, tBytes, tPollErr, tErr, tParsed
   scBegin "eiLog"
   put scMissing(kEiScControls) into tMissing
   scAssert "all 19 controls this script names exist (missing: " \
         & scShow(tMissing) & ")", (tMissing is empty)

   -- A live handle here means the previous run leaked one, and on a re-opened
   -- stack that is exactly how a port stays held while the UI says Ready.
   scAssert "no host handle at boot (sHost is " & scShow(sHost) & ")", \
         (sHost is empty or sHost is 0)
   scAssert "no TorrentXT session at boot (sBtSession is " \
         & scShow(sBtSession) & ")", (sBtSession is empty or sBtSession is 0)
   scAssert "no peers at boot", (sPeers is empty)
   scAssert "the 1 Hz dashboard chain is armed", (sDashOn is "true")

   -- The proof pill's own truth table: these five rows ARE the internet
   -- claim, so they are pinned here where a wrong range fails at boot.
   scAssert "192.168.1.5:1 is private", (eiIsPrivateAddr("192.168.1.5:1") is true)
   scAssert "10.0.0.7 is private", (eiIsPrivateAddr("10.0.0.7") is true)
   scAssert "172.20.3.4:27199 is private", (eiIsPrivateAddr("172.20.3.4:27199") is true)
   scAssert "8.8.8.8:53 is public", (eiIsPrivateAddr("8.8.8.8:53") is false)
   scAssert "203.0.113.9 is public", (eiIsPrivateAddr("203.0.113.9") is false)
   -- the invite parser, both spellings and the default port
   put eiParseInvite("203.0.113.9:31000") into tParsed
   scAssert "invite ip:port parses (got " & scShow(tParsed) & ")", \
         (tParsed is "203.0.113.9|31000")
   put eiParseInvite("203.0.113.9") into tParsed
   scAssert "a bare ip defaults the port (got " & scShow(tParsed) & ")", \
         (tParsed is "203.0.113.9|" & kEiPort)
   scAssert "an empty invite refuses", (eiParseInvite("") is empty)

   if sHaveEn is not "true" then
      scSkip "the enetxt surface and the carried enet-helpers layer", \
            "the extension is not installed"
   else
      put enLibraryVersion() into tVer
      scAssert "enLibraryVersion names enet (" & tVer & ")", (tVer contains "enet")
      -- The one destructive-looking call that is not: handle 0 is never live,
      -- and the shim's contract is that a stale handle is a harmless no-op.
      put enHostDestroy(0) into tRc
      scAssert "enHostDestroy(0) is a harmless no-op (got " & tRc & ")", (tRc is 0)
      put enLastError() into tErr
      scAssert "enLastError is empty after a clean boot (" & scShow(tErr) & ")", \
            (tErr is empty)
      put enStateName(0) into tName
      scAssert "enStateName(0) is disconnected (got " & scShow(tName) & ")", \
            (tName is "disconnected")
      put enFormatBytes(0) into tBytes
      scAssert "enFormatBytes(0) answers (got " & scShow(tBytes) & ")", \
            (tBytes is not empty)
      put enPollLastError() into tPollErr
      scAssert "the poll pump reports no error (" & scShow(tPollErr) & ")", \
            (tPollErr is empty)
   end if
   if sHaveBt is not "true" then
      scSkip "the TorrentXT door (UPnP + public-IP discovery)", \
            "the torrentxt extension is not installed - hosting needs a manual port forward"
   else
      -- stale-handle contract, same shape as the enet half: 0 is never live
      put btListenPort(0) into tRc
      scAssert "btListenPort(0) is a harmless no-op (got " & scShow(tRc) & ")", \
            (tRc is 0 or tRc is empty)
      put btStateName(0) into tName
      scAssert "the carried torrent-helpers layer answers (btStateName(0) is " \
            & scShow(tName) & ")", (tName is not empty)
   end if
   scArmProbe
end eiScRun
