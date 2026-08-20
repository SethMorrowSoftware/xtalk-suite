script "EnetLanChat"

-- enet-lan-chat.livecodescript - the Part III.7 milestone-3 demo: a LAN chat
-- that exercises the whole enetxt surface in the smallest useful app. One
-- machine clicks HOST (it becomes the server and a chatter); others enter its
-- ip[:port] and JOIN. The server relays every line to every peer with ONE
-- enBroadcast; presence (joins/leaves, with addresses) rides the
-- enetConnect/enetDisconnect events; the status line shows live peer count
-- and (clients) the RTT from enPeerStatus.
--
-- What to look at as a template:
--   * PUMP OR NOTHING - enStartPolling arms the heartbeat; nothing in ENet
--     progresses without it. 33 ms here (real-time feel).
--   * The server is ALSO a client of itself logically: its own lines go
--     straight to the log and out via enBroadcast; client lines go enSendText
--     to the server, which relays them.
--   * Channel 0 carries chat (reliable); the connect data carries a tiny
--     protocol version so mismatched builds refuse loudly.
--   * closeStack calls enDeinitialize - the one mandatory teardown (bare
--     command form: OXT cannot compile a zero-argument `name()` statement).
--
-- HOW TO USE (two+ machines on a LAN, or two stacks on one machine):
--   1. Install the enetxt extension on both. Open THIS script as a stack -
--      the helpers are embedded in this file already, so there is nothing
--      else to load.
--   2. Machine A clicks Host. Machine B types A's ip (port defaults to
--      27099) and clicks Join. Chat.
--
-- HONESTY (the suite convention): every en* call here is individually
-- engine-proven (member selftest green through 2026-08-13), but this stack
-- has not run BETWEEN TWO REAL MACHINES, and its UI was unified onto the
-- suite kit 2026-08-14 - so the stack as a whole is verified statically and
-- needs an OXT pass (the two-machine leg is the closing pass's item 6).
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here.

-- Bump when the generated UI changes so a saved stack rebuilds its controls.

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
local sPollTarget       -- object that receives the semantic event messages
local sPollInterval     -- milliseconds between drains (the latency knob)
local sPollNote         -- most recent pump failure, empty while healthy
local sPolling          -- "true" while the timer loop is armed

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
      put the long id of this card into sPollTarget
   else
      put pTarget into sPollTarget
   end if
   if pIntervalMs is empty or pIntervalMs is not a number or pIntervalMs < 1 then
      put 33 into sPollInterval
   else
      put pIntervalMs into sPollInterval
   end if
   if sPolling is not "true" then
      put "true" into sPolling
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
      put "false" into sPolling
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
      put "false" into sPolling
   end if
end enStopPolling

-- One pump pass: enPoll each registered host, dispatch each event by name,
-- then reschedule.
command enetPollOnce
   local tHost, tEvents, tEvent, tName, tSavedDelim, tErr
   if sPolling is not "true" then
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
         if sPollNote is empty then
            put "enPoll failed on host" && tHost & ": " & line 1 of tErr into sPollNote
         end if
         put empty into tEvents
      end try
      repeat for each element tEvent in tEvents
         put tEvent["name"] into tName
         try
            if tName is not empty then
               dispatch tName to sPollTarget with tEvent
            end if
            -- also fire a catch-all so one handler can observe the whole stream
            dispatch "enetEvent" to sPollTarget with tEvent
         catch tErr
            if sPollNote is empty then
               put "dispatch of" && tName & " failed: " & line 1 of tErr into sPollNote
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
   if sPolling is not "true" then
      exit enetPollOnce
   end if
   send "enetPollOnce" to me in (sPollInterval) milliseconds
end enetPollOnce

-- enPollLastError() -- empty while the pump is healthy; otherwise the FIRST
-- failure since the last enPollClearError, naming what threw. An app that
-- shows this in its own log turns "the demo went quiet" into a line a
-- maintainer can act on.
function enPollLastError
   return sPollNote
end enPollLastError

-- Clear it, so an app can report each distinct failure once.
command enPollClearError
   put empty into sPollNote
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

-- <<< END EMBEDDED LIBRARIES <<<

constant kEcUiVersion = "enetchat-kit2-1"
-- The connect-data protocol version: the server refuses a mismatch loudly
-- instead of garbling. Bump when the wire meaning of messages changes.
constant kEcProto = 1
constant kEcPort = 27099

-- ---- script-local state (declared at top) ------------------------------------
local sHost             -- our ENet host handle (server or client; 0/empty = none)
local sIsServer         -- "true" when we hosted
local sServerPeer       -- client role: the peer handle to the server
local sPeers            -- server role: array peer -> display address
local sReady            -- "true" once hosting/joined and (client) connected
local sHaveEn           -- "true" once the extension probe succeeded
local sDashOn           -- "true" while the 1 Hz dashboard chain may reschedule

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

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   ecBuild
   ecStart
   -- LAST, not first: the check reads state ecStart establishes (the extension
   -- probe, the armed dashboard) and asserting before it would test nothing.
   ecScRun
end openStack

on closeStack
   ecStop
end closeStack

on mouseUp
   switch the short name of the target
      case "ecHost"
         ecHost
         break
      case "ecJoin"
         ecJoin
         break
      case "ecLeave"
         ecLeave
         break
      case "ecSend"
         ecSendLine
         break
      default
         pass mouseUp
   end switch
end mouseUp

on returnInField
   switch the short name of the target
      case "ecMsg"
         ecSendLine
         break
      case "ecAddr"
         ecJoin
         break
      default
         pass returnInField
   end switch
end returnInField

-- ---- self-building UI (idempotent; rebuilds on a version bump) ----------------
command ecBuild
   if the uEcUiVersion of this stack is kEcUiVersion and there is a field "ecMsg" then
      exit ecBuild
   end if
   ecClearGeneratedUI
   lock screen
   uiChrome "enetxt LAN chat - reliable UDP, one broadcast, zero servers", 560, 600
   uiCap "ecTagline", "One machine Hosts; everyone else Joins its address. Lines relay through the host over reliable channel 0; joins and leaves announce themselves.", "16,56,544,90"
   -- host / join row
   uiButton "ecHost", "Host (port 27099)", "16,96,180,126"
   uiCap "ecAddrCap", "or join host at ip[:port]:", "190,98,350,116"
   uiInput "ecAddr", "190,120,470,144"
   uiButton "ecJoin", "Join", "476,118,544,148"
   -- name + leave
   uiCap "ecNameCap", "Your name:", "16,156,100,174"
   uiInput "ecName", "100,154,280,178"
   uiButton "ecLeave", "Leave", "416,152,544,180"
   -- log + message box (the status line is the kit's, under the title band)
   uiArea "ecLog", "16,188,544,508"
   uiInput "ecMsg", "16,516,420,542"
   uiButton "ecSend", "Send", "430,514,544,544"
   uiFooter \
         "Chat relays through the host IN THE CLEAR on your LAN - this is a" \
         & " transport demo, not a private messenger. Every en* handler is" \
         & " engine-proven; the two-machine run of THIS stack is the leg" \
         & " still open (runbook item 6).", \
         "16,552,544,596"
   set the uEcUiVersion of this stack to kEcUiVersion
   unlock screen
end ecBuild

command ecClearGeneratedUI
   local tI
   lock screen
   repeat with tI = the number of fields of this card down to 1
      if the short name of field tI of this card begins with "ec" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      if the short name of button tI of this card begins with "ec" then
         delete button tI of this card
      end if
   end repeat
   unlock screen
end ecClearGeneratedUI

-- ---- startup / teardown ------------------------------------------------------
command ecStart
   local tR
   -- probe the extension with a guarded call; fail closed with a clear
   -- message when it is missing (the family's SodiumXT probe pattern)
   put empty into sHaveEn
   try
      put enInitialize() into tR
   catch tErr
      ecLog "The enetxt extension is not installed (org.openxtalk.library.enet) - install it and reopen this stack."
      uiStatus "enetxt NOT loaded: install org.openxtalk.library.enet and reopen.", "bad"
      exit ecStart
   end try
   if tR is not 0 then
      ecLog "enetxt failed to initialise:" && enLastError()
      uiStatus "enetxt failed to initialise - see the log.", "bad"
      exit ecStart
   end if
   put "true" into sHaveEn
   ecLog "Ready (" & enLibraryVersion() & "). Host a room or Join one."
   uiStatus "Ready (" & enLibraryVersion() & "). Host, or Join a host's address.", "ok"
   -- arm the dashboard chain ONCE; a re-fired openStack must not stack a
   -- second chain (the dht-chat re-entrancy rule)
   if sDashOn is not "true" then
      put "true" into sDashOn
      send "ecDashOnce" to me in 800 milliseconds
   end if
end ecStart

command ecStop
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
      -- helpers stack already gone; nothing was polling
   end try
   -- the one mandatory teardown: destroys any surviving hosts and releases
   -- the socket layer (bare command form - see the header comment). Guarded
   -- like the ecStart probe: when the extension is missing, quitting the
   -- stack must not throw out of closeStack.
   try
      enDeinitialize
   catch tErr
      -- extension not installed; nothing to release
   end try
end ecStop

-- ---- host / join / leave -----------------------------------------------------
command ecHost
   if sHaveEn is not "true" then
      ecLog "enetxt is not loaded - install org.openxtalk.library.enet and reopen."
      exit ecHost
   end if
   if sHost is not empty and sHost is not 0 then
      ecLog "Already hosting or joined - Leave first."
      exit ecHost
   end if
   put enHostCreateServer("", kEcPort, 32, 2, 0, 0) into sHost
   if sHost is 0 or sHost is empty then
      ecLog "Could not host (port in use?):" && enLastError()
      put empty into sHost
      exit ecHost
   end if
   put "true" into sIsServer
   put empty into sPeers
   put "true" into sReady
   enStartPolling sHost, the long id of this card, 33
   ecLog "Hosting on port" && kEcPort & ". Others: enter this machine's ip and Join."
end ecHost

command ecJoin
   local tAddr, tHost, tPort, tOldDelim
   if sHaveEn is not "true" then
      ecLog "enetxt is not loaded - install org.openxtalk.library.enet and reopen."
      exit ecJoin
   end if
   if sHost is not empty and sHost is not 0 then
      ecLog "Already hosting or joined - Leave first."
      exit ecJoin
   end if
   put ecTrim(the text of field "ecAddr") into tAddr
   if tAddr is empty then
      ecLog "Enter the host's ip (or ip:port) first."
      exit ecJoin
   end if
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to ":"
   put item 1 of tAddr into tHost
   if the number of items of tAddr > 1 then
      put item 2 of tAddr into tPort
   else
      put kEcPort into tPort
   end if
   set the itemDelimiter to tOldDelim
   if tPort is not a number then
      put kEcPort into tPort
   end if
   put enHostCreateClient(1, 2, 0, 0) into sHost
   if sHost is 0 or sHost is empty then
      ecLog "Could not create a client host:" && enLastError()
      put empty into sHost
      exit ecJoin
   end if
   put "false" into sIsServer
   put enConnect(sHost, tHost, tPort, 2, kEcProto) into sServerPeer
   if sServerPeer is 0 or sServerPeer is empty then
      ecLog "Could not start connecting:" && enLastError()
      enHostDestroy sHost
      put empty into sHost
      exit ecJoin
   end if
   enStartPolling sHost, the long id of this card, 33
   ecLog "Connecting to" && tHost & ":" & tPort & "..."
   uiStatus "Connecting to" && tHost & ":" & tPort & "...", empty
   send "ecJoinWatch" to me in 15000 milliseconds
end ecJoin

-- The join watchdog: ENet retries quietly for ~30 s before giving up, so a
-- blocked port reads as a hang. Name the usual causes while it still tries;
-- the definitive verdict arrives in enetDisconnect below.
command ecJoinWatch
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sIsServer is "true" or sReady is "true" then
      exit ecJoinWatch
   end if
   if sHost is empty or sHost is 0 then
      exit ecJoinWatch
   end if
   ecLog "* still connecting. Usual causes, in order: (1) the HOST machine's firewall blocks inbound UDP" && kEcPort && "- allow the engine for private networks over there; (2) different networks (guest wifi isolates devices); (3) the host is not actually hosting"
end ecJoinWatch

command ecLeave
   if sHost is empty or sHost is 0 then
      exit ecLeave
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
   ecLog "Left."
   uiStatus "Not connected.", empty
end ecLeave

-- ---- events (dispatched by enet-helpers) -------------------------------------

on enetConnect pEvent
   if sIsServer is "true" then
      -- refuse a protocol mismatch loudly instead of garbling later
      if pEvent["data"] is not kEcProto then
         ecLog "* refused a peer with protocol" && pEvent["data"] && "(we speak" && kEcProto & ")"
         enDisconnectNow pEvent["peer"], 0
         exit enetConnect
      end if
      put pEvent["address"] into sPeers[pEvent["peer"]]
      ecLog "* " & pEvent["address"] && "joined (" & the number of lines of the keys of sPeers & " here)"
      ecRelay "* " & pEvent["address"] && "joined"
   else
      put "true" into sReady
      ecLog "* connected - say something!"
      uiStatus "Connected.", "ok"
   end if
end enetConnect

on enetDisconnect pEvent
   if sIsServer is "true" then
      if pEvent["peer"] is among the keys of sPeers then
         ecLog "* " & sPeers[pEvent["peer"]] && "left"
         ecRelay "* " & sPeers[pEvent["peer"]] && "left"
         delete variable sPeers[pEvent["peer"]]
      end if
   else
      if sReady is "true" then
         ecLog "* disconnected from the host"
         uiStatus "Not connected.", empty
      else
         -- no enetConnect ever arrived, so this is ENet giving up on the
         -- CONNECT, not a goodbye - say so, and name the usual causes
         ecLog "* could not connect (ENet gave up). Host-machine firewall (inbound UDP" && kEcPort & ")? Same network? Host actually hosting?"
         uiStatus "Connect FAILED - see the log.", "bad"
      end if
      put "false" into sReady
      -- Either way the half-open client host is useless now; release it so
      -- Join works again without a manual Leave first.
      --
      -- THE GUARD IS NOT DEFENSIVE PADDING. enHostDestroy is declared
      -- `in pHost as Integer`, and this handler empties sHost two lines down -
      -- so the SECOND enetDisconnect to arrive (ENet delivers one per peer,
      -- and a failed connect produces one of its own) handed the engine an
      -- empty value for a typed parameter. That is a hard runtime error -
      -- "type conversion error" - which killed the poll chain and left the
      -- demo silently dead. The same file already guards sHost this way in
      -- ten other places; this was the one path that did not.
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
      ecLog tLine
      ecRelay tLine
   else
      ecLog tLine
   end if
end enetReceive

on enetError pEvent
   ecLog "* transport error:" && pEvent["error"]
end enetError

-- ---- sending -----------------------------------------------------------------
command ecSendLine
   local tBody, tName, tLine, tR
   put ecTrim(the text of field "ecMsg") into tBody
   if tBody is empty then
      exit ecSendLine
   end if
   if sHost is empty or sHost is 0 then
      ecLog "Host or Join first."
      exit ecSendLine
   end if
   put ecTrim(the text of field "ecName") into tName
   if tName is empty then
      put "me" into tName
   end if
   put tName & ": " & tBody into tLine
   if sIsServer is "true" then
      ecLog tLine
      ecRelay tLine
   else
      if sReady is not "true" then
         ecLog "Not connected yet."
         exit ecSendLine
      end if
      put enSendText(sServerPeer, 0, tLine, 0) into tR -- 0 = reliable
      if tR is not 0 then
         ecLog "Send failed (" & tR & "):" && enLastError()
         exit ecSendLine
      end if
   end if
   set the text of field "ecMsg" to ""
end ecSendLine

-- Server fanout: ONE broadcast reaches every connected peer. The return is
-- checked because a failed relay is invisible to every participant including
-- the host - the one silent failure this demo cannot afford.
command ecRelay pLine
   local tR
   if sIsServer is "true" and sHost is not empty and sHost is not 0 then
      put enBroadcastText(sHost, 0, pLine, 0) into tR -- 0 = reliable
      if tR is not 0 then
         ecLog "* relay FAILED (" & tR & "):" && enLastError()
      end if
   end if
end ecRelay

-- ---- the 1 Hz dashboard ------------------------------------------------------
command ecDashOnce
   local tPS, tPollErr
   -- the chain dies with the stack: ecStop clears the flag and this exit
   -- path does NOT reschedule (the old version rescheduled unconditionally
   -- and outlived closeStack forever)
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sDashOn is not "true" then
      exit ecDashOnce
   end if
   send "ecDashOnce" to me in 1000 milliseconds
   -- Surface a pump failure ONCE, in this demo's own log, and clear it. The
   -- helpers keep the note instead of printing it (a library writing into an
   -- app it knows nothing about is a nuisance); showing it is the app's
   -- choice. Without this, a throw inside the pump is invisible - events just
   -- stop arriving and the window looks idle.
   put enPollLastError() into tPollErr
   if tPollErr is not empty then
      enPollClearError
      ecLog "* event pump problem:" && tPollErr
      ecLog "* (The chat keeps polling. Please report that line - it names what threw.)"
   end if
   if sHost is empty or sHost is 0 then
      exit ecDashOnce
   end if
   if sIsServer is "true" then
      uiStatus "Hosting on port" && kEcPort && "-" && the number of lines of the keys of sPeers && "peer(s)", "ok"
   else if sServerPeer is not empty and sServerPeer is not 0 then
      put enPeerStatus(sServerPeer) into tPS
      if the number of lines of the keys of tPS is 0 then
         uiStatus "Peer status unavailable.", empty
      else if tPS["state"] is 5 then
         uiStatus "Connected -" && tPS["rtt"] & " ms rtt -" && tPS["address"], "ok"
      else
         uiStatus "Peer state:" && enStateName(tPS["state"]), empty
      end if
   end if
end ecDashOnce

-- ---- small helpers -----------------------------------------------------------
command ecLog pMsg
   if there is no field "ecLog" then
      exit ecLog
   end if
   put pMsg & return after field "ecLog"
   set the vscroll of field "ecLog" to the formattedHeight of field "ecLog"
end ecLog

function ecTrim pText
   return word 1 to -1 of pText
end ecTrim

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
   local tName, tMissing
   set the defaultStack to the short name of this stack
   repeat for each item tName in pList
      if there is no field tName and there is no button tName then
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
   else
      scLine "      boot self-check has FAILURES above - report them before " \
            & "running any live leg"
   end if
end scFinish
-- ==== DEMO SELF-CHECK v1 END ====

-- Every control name this script references, derived from the source rather
-- than hand-picked: a subset would go stale the first time somebody renames
-- one, and a missing control is not cosmetic - it is the "Chunk: error in
-- object expression" class, found at boot instead of when somebody clicks.
constant kEcScControls = "ecAddr,ecHost,ecJoin,ecLeave,ecLog,ecMsg,ecName,ecSend,uiFooter,uiStatus,uiTitle"

command ecScRun
   local tMissing, tVer, tRc, tName, tBytes, tPollErr, tErr
   scBegin "ecLog"
   put scMissing(kEcScControls) into tMissing
   scAssert "all 11 controls this script names exist (missing: " \
         & scShow(tMissing) & ")", (tMissing is empty)

   -- A live handle here means the previous run leaked one, and on a re-opened
   -- stack that is exactly how port 27099 stays held while the UI says Ready.
   scAssert "no host handle at boot (sHost is " & scShow(sHost) & ")", \
         (sHost is empty or sHost is 0)
   scAssert "no peers at boot", (sPeers is empty)
   scAssert "the 1 Hz dashboard chain is armed", (sDashOn is "true")

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
      -- The helpers layer this file CARRIES. If these disagree, the demo is
      -- running a stale copy of the library its own poll pump depends on -
      -- the exact failure the embedding exists to prevent.
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
   scArmProbe
end ecScRun
