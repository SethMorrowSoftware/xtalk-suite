script "DataChannelLoopback"

-- datachannel-loopback.livecodescript - the zero-infrastructure first-run
-- demo for DataChannelXT: TWO WebRTC peers living in ONE stack, their
-- signaling shuttled directly in script (no server, no network beyond the
-- machine itself), one data channel between them, and a chat pane for each.
-- It proves the whole pipeline - offer/answer, ICE, DTLS, SCTP, the channel,
-- both message kinds - before you ever build real signaling.
--
-- WHAT TO LOOK AT: the dcLocalDescription / dcLocalCandidate handlers ARE a
-- complete signaling implementation - each one just delivers the artifact to
-- the OTHER peer. In a real app, replace those two `dcSetRemoteDescription` /
-- `dcAddRemoteCandidate` calls with "send it to the far machine somehow"
-- (TorrentXT DHT rendezvous, a paste, anything) and the rest is identical.
--
-- HOW TO USE: put this script and the DataChannelXT extension in place, then:
--     (nothing - the poll dispatcher is embedded in this file)
--     go stack "DataChannelLoopback"           -- builds its UI on first open
-- Click "Connect", watch the states walk to connected + open, then type in
-- either pane's field and press Return.
--
-- HONESTY (the suite convention): the binding and an in-process loopback are
-- engine-proven (the suite harness drives its own, green 2026-08-12), but
-- THIS stack has no recorded engine run of its own and its UI was unified
-- onto the suite kit 2026-08-14 - verified statically; needs an OXT pass.
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

-- ---- datachannelxt/examples/datachannel-helpers.livecodescript ----

-- datachannel-helpers.livecodescript - the script-side poll dispatcher and
-- sugar for DataChannelXT. Insert this script into the message path (e.g.
-- `start using stack "dataChannelHelpers"` or as a behavior) so any stack can
-- drive WebRTC data channels with plain event handlers instead of a manual
-- poll loop.
--
-- The model (carried from TorrentXT/ShowControl): the engine NEVER calls back
-- into script. libdatachannel fires its callbacks on its own threads; the
-- native shim queues every event; we drain that queue on a timer with ONE FFI
-- round-trip (dcPoll), then `send` one semantic message per event. Throughput
-- and event integrity are independent of the poll cadence - only worst-case
-- latency scales with it - so the interval is a documented latency/CPU knob.
-- Data channels are REAL-TIME transport: poll at 16-33 ms for a live feel
-- (games, cursors), 100+ ms for chat-grade traffic.
--
-- The messages dispatched to the target (each with the event array as its
-- parameter; keys per docs/api-reference.md):
--   dcLocalDescription  pEvent["peer"], ["sdp"], ["sdpType"] - SHIP THESE to
--   dcLocalCandidate    pEvent["candidate"], ["mid"]           the far peer
--   dcStateChange       pEvent["state"] (see dcStateName below)
--   dcGatheringStateChange  pEvent["state"]
--   dcChannelIncoming   pEvent["channel"], ["label"], ["protocol"]
--   dcChannelOpen       pEvent["channel"] - NOW you can send
--   dcChannelClosed     pEvent["channel"]
--   dcMessage           pEvent["text"] (a text send) OR ["payload"] (binary)
--   dcChannelError      pEvent["error"]
--   dcBufferedLow       pEvent["channel"] - resume sending (backpressure)
--   dcQueueOverflow     pEvent["dropped"] - the app stopped polling too long
-- plus a catch-all "dataChannelEvent" fired for EVERY event.

-- script-local poll state (declared at top; LiveCode Script script-locals)
local sPollTarget       -- object that receives the semantic event messages
local sPollInterval     -- milliseconds between drains (the latency/CPU knob)
local sPolling          -- "true" while the timer loop is armed
local sPollNote         -- most recent dispatch failure, "" while healthy
local sPollDrains       -- drains attempted, so a failure can name which

-- dcStartPolling TARGET, INTERVALMS
-- Begin draining events and dispatching them to TARGET. If TARGET is empty,
-- events go to the current card. INTERVALMS defaults to 33 (about 30 Hz -
-- real-time feel without measurable CPU cost). Calling it again while polling
-- re-points the target and the interval (last caller wins); it does NOT arm a
-- second chain.
command dcStartPolling pTarget, pIntervalMs
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
   -- Arm the chain ONCE - the guard enet-helpers has carried since it was
   -- written, and the one this file lacked. A second chain does not duplicate
   -- EVENTS: each pass drains the whole queue in one dcPoll, so the second
   -- chain mostly finds it empty. What doubles, permanently, is the FFI drain
   -- RATE and the timer churn - and neither chain can be stood down on its
   -- own, because both read this one flag. Every in-tree caller
   -- (datachannel-loopback, datachannel-dht-chat) arms once at startup, so
   -- this is a trap laid for the NEXT caller rather than a live regression.
   if sPolling is not "true" then
      put "true" into sPolling
      if sPollDrains is not a number then
         put 0 into sPollDrains
      end if
      -- kick the loop immediately; it reschedules itself
      send "dcChannelPollOnce" to me in 0 milliseconds
   end if
end dcStartPolling

-- Stop the timer loop. Safe to call when not polling. (This stops DELIVERY
-- only - the native queue keeps buffering, bounded, until you poll again or
-- call dcCleanup.)
command dcStopPolling
   put "false" into sPolling
end dcStopPolling

-- One drain pass: pull all pending events with a single dcPoll, dispatch
-- each, then reschedule.
--
-- WHY THIS IS WRAPPED, AND WHY THE WRAP IS NOT BELT-AND-BRACES.
-- The 2026-08-18 Linux pass reported, on hosting a chat:
--
--   execution error at line 178 (call: type conversion error), char 1
--
-- - line 178 of the merged demo being the `dispatch tName` below. That is the
-- whole product of an engine session: a statement, and a phrase. It does not
-- say which EVENT was in flight, whether the target still resolved, or
-- whether the throw came from the dispatch itself or from a handler it
-- reached, and those are three different bugs. Static reading could not tell
-- them apart either: `dispatch <name> to <obj> with <array>` is proven
-- on-engine elsewhere in this suite (onion-httpd routes an array of headers
-- that way and serves real pages), so the obvious suspect is already ruled
-- out. So this pass now records what it saw.
--
-- It also STOPS TAKING THE CHAIN DOWN. An uncaught throw here kills the timer
-- and the app goes quiet with no further symptom - the failure mode that makes
-- an intermittent event bug cost several passes instead of one. Each event is
-- isolated: one bad event is reported and skipped, the rest of the drain and
-- every later drain still run. The note is READ, not printed, because printing
-- from a library into an app it knows nothing about is how a diagnostic
-- becomes a nuisance: see dcPollLastError.
command dcChannelPollOnce
   local tEvents, tEvent, tName, tErr, tTarget, tProbe
   if sPolling is not "true" then
      exit dcChannelPollOnce
   end if
   -- Resolve the target ONCE per pass and prove it still RESOLVES. A long id
   -- whose object has gone (a closed stack, a rebuilt card) is the classic way
   -- a dispatch target goes stale.
   --
   -- The probe is a guarded property READ, not `there is an object tTarget`.
   -- That spelling reads better and nothing in this suite has ever compiled
   -- it, so putting it here would risk trading a reported error for an
   -- unreported one in three demo files at once. The try/catch shape below is
   -- the one box2dxt's harness uses to re-resolve a stale long id, and it has
   -- run green on an engine.
   put sPollTarget into tTarget
   put empty into tProbe
   if tTarget is not empty then
      try
         put the short name of tTarget into tProbe
      catch tErr
         put empty into tProbe
      end try
   end if
   if tProbe is empty then
      put the long id of this card into tTarget
      if sPollNote is empty then
         put "poll target no longer resolves; fell back to this card" into sPollNote
      end if
   end if
   -- THE DRAIN IS INSIDE THE TRY TOO, and the first version of this wrap got
   -- that wrong. It guarded the dispatch, because the engine had named the
   -- dispatch line - but the NEXT report named datachannel.lcb line 234, which
   -- is inside dcPoll's buffer helper. That throw happens HERE, on the way in,
   -- and an unguarded `put dcPoll() into tEvents` takes the timer chain down
   -- before any dispatch is attempted. Guarding only the half you have already
   -- been shown is how a diagnostic costs two passes instead of one.
   add 1 to sPollDrains
   put empty into tEvents
   try
      put dcPoll() into tEvents
   catch tErr
      if sPollNote is empty then
         -- NAME THE DRAIN NUMBER. _ensureDrain has exactly two callers and
         -- they are told apart by WHEN they run: the first drain passes the
         -- constant kDrainCap, and only a later one can reach the
         -- grow-and-retry path that computes its size from the shim's return.
         -- "cannot convert value" on drain 1 and on drain 400 are different
         -- bugs, and this counter is the whole difference between them - at
         -- no cost, and with no extension rebuild to find out.
         put "dcPoll failed on drain #" & (sPollDrains + 1) & ": " & \
               line 1 of tErr into sPollNote
      end if
      -- Do NOT stop polling: a transient drain failure must not silently end
      -- the app's event delivery. Reschedule below and try again.
      put empty into tEvents
   end try
   repeat for each element tEvent in tEvents
      put tEvent["name"] into tName
      try
         if tName is not empty then
            dispatch tName to tTarget with tEvent
         end if
         -- also fire a catch-all so one handler can observe the whole stream
         dispatch "dataChannelEvent" to tTarget with tEvent
      catch tErr
         -- Keep the FIRST failure: it is the one with a clean cause. Later
         -- ones are usually the same bug repeating at 10 Hz, and overwriting
         -- would leave whichever event happened to be last.
         if sPollNote is empty then
            put "dispatch of" && tName & " failed: " & line 1 of tErr into sPollNote
         end if
      end try
   end repeat
   -- Reschedule (the native queue keeps buffering between drains). The
   -- interval is guarded because `in () milliseconds` on an empty value is
   -- itself a type conversion error - and a poll loop that dies while
   -- reporting a poll error would be a poor diagnostic.
   if sPollInterval is not a number or sPollInterval < 1 then
      put 33 into sPollInterval
   end if
   send "dcChannelPollOnce" to me in (sPollInterval) milliseconds
end dcChannelPollOnce

-- dcPollLastError() -- empty while the dispatcher is healthy; otherwise the
-- FIRST dispatch failure since the last dcPollClearError, naming the event.
-- An app that shows this in its own log turns "the demo went quiet" into a
-- line a maintainer can act on.
function dcPollLastError
   return sPollNote
end dcPollLastError

-- Clear it, so an app can report each distinct failure once rather than
-- repeating one line forever.
command dcPollClearError
   put empty into sPollNote
end dcPollClearError

-- dcStateName N -- map a kPeerState* int to a label for status displays.
function dcStateName pState
   switch pState
      case 0
         return "new"
      case 1
         return "connecting"
      case 2
         return "connected"
      case 3
         return "disconnected"
      case 4
         return "failed"
      case 5
         return "closed"
      default
         return "unknown"
   end switch
end dcStateName

-- dcGatheringName N -- map a kGathering* int to a label.
function dcGatheringName pState
   switch pState
      case 0
         return "new"
      case 1
         return "gathering"
      case 2
         return "complete"
      default
         return "unknown"
   end switch
end dcGatheringName

-- dcFormatBytes N -- a small humaniser for buffered-amount displays.
function dcFormatBytes pBytes
   local tUnits, tVal, tI, tSavedDelim, tOut
   if pBytes is empty or pBytes is not a number then
      return "0 B"
   end if
   put "B,KiB,MiB,GiB" into tUnits
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
end dcFormatBytes

-- <<< END EMBEDDED LIBRARIES <<<

constant kLbUiVersion = "loopback-kit2-1"
-- The loopback should be OPEN well inside this; a machine that blocks even
-- UDP-to-itself is the known way for it to hang, and the watchdog says so.
constant kLbDeadlineMs = 20000

-- ---- script-local state (declared at top) ------------------------------------
local sPeerA          -- peer handle A (the offerer)
local sPeerB          -- peer handle B (the answerer)
local sChanA          -- A's channel handle (created -> triggers the offer)
local sChanB          -- B's channel handle (learned from dcChannelIncoming)
local sHaveDc         -- "true" once the extension probe succeeded
local sOpenSeen       -- "true" once either channel reported open
local sWatchArmed     -- "true" while a connect watchdog is pending

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
   lbBuild
   lbStart
end openStack

on closeStack
   -- both guarded: quitting with the helpers stack or the extension absent
   -- must not throw out of closeStack (the enet-lan-chat teardown rule)
   local tErr
   try
      dcStopPolling
   catch tErr
      -- helpers stack already gone; nothing was polling
   end try
   try
      -- BARE, not dcCleanup(): a zero-argument call in STATEMENT position
      -- parses as a command whose argument is `()`, and `()` is not an
      -- expression. dcStopPolling above is the same idiom.
      dcCleanup
   catch tErr
      -- extension not installed; nothing to release
   end try
end closeStack

on mouseUp
   switch the short name of the target
      case "lbConnect"
         connectLoopback
         break
      case "lbDisconnect"
         disconnectLoopback
         break
      default
         pass mouseUp
   end switch
end mouseUp

-- ---- self-building UI (idempotent; rebuilds on a version bump) ----------------
command lbBuild
   if the uLbUiVersion of this stack is kLbUiVersion and there is a field "lbLogA" then
      exit lbBuild
   end if
   lbClearGeneratedUI
   lock screen
   uiChrome "DataChannelXT loopback - two WebRTC peers in one stack", 640, 460
   uiButton "lbConnect", "Connect", "16,58,136,84"
   uiButton "lbDisconnect", "Disconnect", "146,58,266,84"
   uiCap "lbStatusA", "A: idle", "16,92,312,110"
   uiCap "lbStatusB", "B: idle", "328,92,624,110"
   uiArea "lbLogA", "16,114,312,368"
   uiArea "lbLogB", "328,114,624,368"
   uiInput "lbSayA", "16,376,312,400"
   uiInput "lbSayB", "328,376,624,400"
   uiFooter \
         "Everything here stays on this machine: the signaling is a script" \
         & " variable, the transport is a loopback. It proves the pipeline," \
         & " not the network. Verified statically; needs an OXT pass.", \
         "16,408,624,452"
   set the uLbUiVersion of this stack to kLbUiVersion
   unlock screen
end lbBuild

command lbClearGeneratedUI
   local tI, tName
   lock screen
   repeat with tI = the number of fields of this card down to 1
      put the short name of field tI of this card into tName
      -- "lb"-prefixed controls are this version's; the bare names are the
      -- pre-kit build's, deleted once on the version bump (spelled out
      -- rather than item-matched: itemDelimiter is global mutable state)
      if tName begins with "lb" or tName is "statusA" or tName is "statusB" \
            or tName is "logA" or tName is "logB" \
            or tName is "sayA" or tName is "sayB" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      put the short name of button tI of this card into tName
      if tName begins with "lb" or tName is "Connect" or tName is "Disconnect" then
         delete button tI of this card
      end if
   end repeat
   unlock screen
end lbClearGeneratedUI

-- ---- startup (probe, fail closed) --------------------------------------------
command lbStart
   local tErr
   put empty into sHaveDc
   -- probe the extension with a guarded call; fail closed with a clear
   -- message when it is missing (the family's SodiumXT probe pattern)
   try
      if dcInit() is 0 then
         put "true" into sHaveDc
      end if
   catch tErr
      -- reported below
   end try
   if sHaveDc is not "true" then
      uiStatus "DataChannelXT NOT loaded: install org.openxtalk.library.datachannel and reopen.", "bad"
      exit lbStart
   end if
   try
      dcStartPolling the long id of this card, 33
   catch tErr
      uiStatus "The poll dispatcher is missing. It is EMBEDDED in this demo, so this means the embedded copy is damaged - re-paste the whole file.", "bad"
      exit lbStart
   end try
   uiStatus "Ready. Click Connect to negotiate the loopback.", "ok"
end lbStart

-- ---- connect / disconnect ----------------------------------------------------
command connectLoopback
   if sHaveDc is not "true" then
      uiStatus "DataChannelXT is not loaded - see above.", "bad"
      exit connectLoopback
   end if
   if sPeerA is not empty and sPeerA is not 0 then
      exit connectLoopback -- already connected
   end if
   -- loopback needs no ICE servers: host candidates carry it
   put dcCreatePeer("") into sPeerA
   put dcCreatePeer("") into sPeerB
   if sPeerA is 0 or sPeerA is empty or sPeerB is 0 or sPeerB is empty then
      uiStatus "Could not create a peer:" && dcLastError(), "bad"
      -- free whichever half DID come up, or a retry leaks it
      disconnectLoopback
      exit connectLoopback
   end if
   -- creating the first channel starts the negotiation; everything else
   -- arrives as events below
   put dcCreateChannel(sPeerA, "loopback-chat") into sChanA
   if sChanA is 0 or sChanA is empty then
      uiStatus "Could not create the channel:" && dcLastError(), "bad"
      disconnectLoopback
      exit connectLoopback
   end if
   put empty into sChanB
   put empty into sOpenSeen
   lbSetPeerStatus sPeerA, "connecting..."
   lbSetPeerStatus sPeerB, "waiting for offer..."
   uiStatus "Negotiating (offer/answer, ICE, DTLS, SCTP)...", empty
   if sWatchArmed is not "true" then
      put "true" into sWatchArmed
      send "lbConnectWatch" to me in kLbDeadlineMs milliseconds
   end if
end connectLoopback

-- The connect watchdog: a loopback that has not opened inside the deadline
-- is not slow, it is stuck - the known cause is a machine that blocks ALL
-- UDP, even to itself. Say so instead of hanging silently.
command lbConnectWatch
   local tPollErr
   put empty into sWatchArmed
   if sOpenSeen is "true" then
      exit lbConnectWatch
   end if
   if sPeerA is empty or sPeerA is 0 then
      exit lbConnectWatch
   end if
   -- Blocked UDP is the usual reason this deadline is reached, but it is not
   -- the only one: a dispatch that threw would ALSO look exactly like this -
   -- peers created, nothing ever opening - and blaming a firewall for a
   -- script fault sends the reader somewhere there is nothing to find. So ask
   -- the dispatcher first and report whichever cause is real.
   put dcPollLastError() into tPollErr
   if tPollErr is not empty then
      dcPollClearError
      uiStatus "The event dispatcher failed - see the logs. This is NOT a firewall problem.", "bad"
      logLine sPeerA, "* event dispatch problem:" && tPollErr
      exit lbConnectWatch
   end if
   uiStatus "Still not open after" && (kLbDeadlineMs div 1000) && "s - this machine may block UDP to itself (VPN/firewall). See the logs.", "bad"
   logLine sPeerA, "* not open after" && (kLbDeadlineMs div 1000) && "s: check for a firewall/VPN blocking loopback UDP"
end lbConnectWatch

command disconnectLoopback
   if sPeerA is not empty and sPeerA is not 0 then
      dcFreePeer(sPeerA)
   end if
   if sPeerB is not empty and sPeerB is not 0 then
      dcFreePeer(sPeerB)
   end if
   put empty into sPeerA
   put empty into sPeerB
   put empty into sChanA
   put empty into sChanB
   put empty into sOpenSeen
   lbSetPeerStatusRaw "lbStatusA", "A: idle"
   lbSetPeerStatusRaw "lbStatusB", "B: idle"
end disconnectLoopback

-- ---- signaling, in miniature -------------------------------------------------
-- These two handlers ARE the signaling layer. Loopback edition: hand each
-- artifact straight to the other peer. Real edition: transmit it instead.
-- Both returns are CHECKED - a swallowed signaling failure is a demo that
-- sits at "connecting..." forever with nothing to debug (the dht-chat
-- pattern; the old version discarded both).

on dcLocalDescription pEvent
   local tDest, tR
   put otherPeer(pEvent["peer"]) into tDest
   if tDest is not empty then
      put dcSetRemoteDescription(tDest, pEvent["sdp"], pEvent["sdpType"]) into tR
      if tR is not 0 then
         logLine tDest, "* set remote description FAILED (" & tR & "):" && dcLastError()
         uiStatus "Signaling failed - see the logs.", "bad"
      else
         logLine pEvent["peer"], "-> shipped" && pEvent["sdpType"]
      end if
   end if
end dcLocalDescription

on dcLocalCandidate pEvent
   local tDest, tR
   put otherPeer(pEvent["peer"]) into tDest
   if tDest is not empty then
      put dcAddRemoteCandidate(tDest, pEvent["candidate"], pEvent["mid"]) into tR
      if tR is not 0 then
         logLine tDest, "* add candidate FAILED (" & tR & "):" && dcLastError()
      end if
   end if
end dcLocalCandidate

function otherPeer pPeer
   if pPeer is sPeerA then
      return sPeerB
   else if pPeer is sPeerB then
      return sPeerA
   end if
   return empty
end otherPeer

-- ---- events ------------------------------------------------------------------

on dcStateChange pEvent
   local tLabel
   put dcStateName(pEvent["state"]) into tLabel
   lbSetPeerStatus pEvent["peer"], tLabel
   -- state 4 is "failed": say what to do rather than printing a bare word
   if pEvent["state"] is 4 then
      uiStatus "A peer reported FAILED - on a loopback that means blocked local UDP.", "bad"
   end if
end dcStateChange

on dcChannelIncoming pEvent
   -- B learns its channel handle here (A made its own with dcCreateChannel)
   if pEvent["peer"] is sPeerB then
      put pEvent["channel"] into sChanB
      logLine sPeerB, "incoming channel" && quote & pEvent["label"] & quote
   end if
end dcChannelIncoming

on dcChannelOpen pEvent
   put "true" into sOpenSeen
   logLine dcChannelPeer(pEvent["channel"]), "channel open - say something!"
   uiStatus "Open both ends - type in either pane and press Return.", "ok"
end dcChannelOpen

on dcChannelClosed pEvent
   logLine dcChannelPeer(pEvent["channel"]), "channel closed"
end dcChannelClosed

on dcMessage pEvent
   -- text sends arrive under "text"; binary sends under "payload" (a Data)
   if pEvent["text"] is not empty then
      logLine pEvent["peer"], "received:" && pEvent["text"]
   else
      logLine pEvent["peer"], "received" && the number of bytes in pEvent["payload"] && "binary bytes"
   end if
end dcMessage

on dcChannelError pEvent
   logLine pEvent["peer"], "ERROR:" && pEvent["error"]
end dcChannelError

-- ---- chat --------------------------------------------------------------------

on returnInField
   local tShort, tText, tR
   put the short name of the target into tShort
   put the text of the target into tText
   if tText is empty then
      exit returnInField
   end if
   if tShort is "lbSayA" then
      if sChanA is not empty and dcChannelIsOpen(sChanA) then
         put dcSendText(sChanA, tText) into tR
         if tR is 0 then
            logLine sPeerA, "sent:" && tText
            put empty into field "lbSayA"
         else
            logLine sPeerA, "* send FAILED (" & tR & "):" && dcLastError()
         end if
      end if
   else if tShort is "lbSayB" then
      if sChanB is not empty and dcChannelIsOpen(sChanB) then
         put dcSendText(sChanB, tText) into tR
         if tR is 0 then
            logLine sPeerB, "sent:" && tText
            put empty into field "lbSayB"
         else
            logLine sPeerB, "* send FAILED (" & tR & "):" && dcLastError()
         end if
      end if
   else
      pass returnInField
   end if
end returnInField

-- ---- small helpers -----------------------------------------------------------
command lbSetPeerStatus pPeer, pText
   if pPeer is sPeerA then
      lbSetPeerStatusRaw "lbStatusA", "A:" && pText
   else if pPeer is sPeerB then
      lbSetPeerStatusRaw "lbStatusB", "B:" && pText
   end if
end lbSetPeerStatus

command lbSetPeerStatusRaw pField, pText
   if there is a field pField then
      put pText into field pField
   end if
end lbSetPeerStatusRaw

command logLine pPeer, pLine
   local tField
   if pPeer is sPeerA then
      put "lbLogA" into tField
   else if pPeer is sPeerB then
      put "lbLogB" into tField
   else
      exit logLine
   end if
   put pLine & return after field tField
   -- keep the tail visible without an every-event relayout storm
   set the vScroll of field tField to the formattedHeight of field tField
end logLine
