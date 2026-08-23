script "enetSelfTest"

-- enet-selftest.livecodescript - a self-building RUNTIME harness that drives
-- the enetxt public API in OXT and reports PASS / FAIL per
-- handler. This is the OXT-pass companion to the C++ smoke test: the smoke
-- test proves the shim against ENet in CI; this proves the .lcb BINDING (the
-- foreign-decl signatures, the record walkers, the buffer round-trips)
-- actually runs - the one layer CI cannot reach, since OXT has no headless
-- way to compile or run .lcb.
--
-- COVERAGE NOTE (honest): every public en* handler is now driven here.
-- enDisconnectNow, enResetPeer, enSetPeerTimeout, and enSetHostBandwidth run
-- in their own isolated section (a client host pointed at a dead port, so an
-- abrupt teardown cannot perturb the graceful loopback below), and
-- enHostStatus is asserted BOTH stale (empty) and live (peerCount, address).
-- The isolated section became a RUNTIME RESULT on 2026-08-10: this file's
-- synchronous half ran green on a real engine (21 checks, twice in one day),
-- folded into the suite selftest at the repository root, and all four abrupt
-- teardown handlers returned 0 against a live client host. And the async
-- loopback closed too: on 2026-08-13 THIS file ran STANDALONE on a real
-- engine, green end to end - the live enHostStatus pair (connected, then
-- zero peers after the disconnect), the enPeerStatus statistics (rtt,
-- packetLoss, the packet/byte counters), the echo/broadcast/binary round
-- trips, and the graceful close. Nothing in this file is verified
-- statically any more; the member's one remaining un-exercised surface is
-- the LAN chat demo between two real machines (suite runbook, item 6).
--
-- HOW TO USE: open OXT, make a one-card stack, paste THIS into the STACK
-- script (Object > Stack Script), then close+reopen. It builds its own UI,
-- runs the synchronous checks, then a LIVE LOOPBACK (a server host and a
-- client host in this one process, 127.0.0.1), message round-trips, and
-- teardown - and shows a green/red list. Needs the installed
-- org.openxtalk.library.enet extension.
--
-- The LCS lessons this file was written under (the LiveCodeScript/LCB gotcha
-- list carried in the family CLAUDE.md files): no
-- braces, no subscripted function results, array emptiness by counting keys,
-- binary payloads built with numToByte (string literals have no escapes),
-- byte-exact compares under caseSensitive, and zero-argument calls BARE in
-- statement position.

-- STATUS: the SYNC half last ran GREEN in the 2026-08-17 engine pass (Windows x86_64, NT 10.0, OXT 9.6.3) - 21/21, folded into
-- tests/suite-selftest.livecodescript. The ASYNC loopback is deliberately
-- NOT folded (two state machines in one process race for the event
-- handlers) and is verified by running this file on its own.

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

-- <<< END EMBEDDED LIBRARIES <<<

constant kStTitle = "enetxt - API Self-Test"
constant kStWidth = 660
constant kStHeight = 620

-- ---- state -------------------------------------------------------------------
local sServer, sClient  -- the two loopback hosts
local sClientPeer       -- client side: handle from enConnect
local sServerPeer       -- server side: handle born in its enetConnect event
local sGotEcho          -- "true" once the client received the echo
local sGotUnseq         -- "true" once the client received the channel-1 line
local sGotBinary        -- the binary payload the server received (a Data)
local sSentBinary       -- what the client sent (kept for byte-exact compare)
local sSawServerDisc    -- "true" once the server drained enetDisconnect
local sDeadline         -- the async phase's drop-dead time (ms clock)
local sPhase            -- "", "connecting", "messaging", "binary", "closing", "done"

-- ---- the scaffolding (carried) ----------------------------------------------
-- ==== SUITE HARNESS SCAFFOLD v1 BEGIN (verbatim copy; master: tools/harness-scaffold.livecodescript; gate: tools/check-harness-scaffold-drift.py) ====
-- The harness scaffolding as one carried block: counters, the window, the
-- assertion plumbing, the report surface. The adopting harness declares
-- kStTitle/kStWidth/kStHeight above this block, owns openStack/stRun/
-- stCleanup, calls stResetCounters first in stRun and stReportDone when
-- the run completes. Do not edit this block in place: change the master
-- and re-carry it.
local sTotal, sPassed, sFailed, sSkipped
local sResultText          -- the accumulated PASS/FAIL/SKIP/section lines
local sStRunDone           -- "true" once the run finished (drives the color)

-- The platform's own terminal face (the demo kit's uiMonoFont, by value).
function stMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end stMonoFont

-- ---- the window (idempotent; the fold drops this half) -----------------------
command stBuild
   -- the guard is on a control this VERSION of the scaffold adds, so a stack
   -- built by an older scaffold rebuilds once and picks up the new layout
   -- (the builders re-rect existing controls by name; nothing needs deleting)
   if there is a button "stCopy" then
      exit stBuild
   end if
   lock screen
   set the width of this stack to kStWidth
   set the height of this stack to kStHeight
   set the backgroundColor of this card to "240,242,246"
   set the title of this stack to kStTitle
   stMakeLabel "stTitle", "  " & kStTitle, "0,0," & kStWidth & ",30", 15
   set the opaque of field "stTitle" to true
   set the backgroundColor of field "stTitle" to "44,90,160"
   set the foregroundColor of field "stTitle" to "255,255,255"
   set the textStyle of field "stTitle" to "bold"
   stMakeLabel "stSummary", "Running...", "16,38," & (kStWidth - 200) & ",66", 13
   set the textStyle of field "stSummary" to "bold"
   stMakeButton "stCopy", "Copy results", (kStWidth - 184) & ",38," & (kStWidth - 100) & ",64"
   stMakeButton "stRerun", "Re-run", (kStWidth - 94) & ",38," & (kStWidth - 16) & ",64"
   stMakeList "stResults", "16,72," & (kStWidth - 16) & "," & (kStHeight - 16)
   unlock screen
end stBuild

command stMakeLabel pName, pText, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the textSize of field pName to pSize
   put pText into field pName
end stMakeLabel

command stMakeButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end stMakeButton

command stMakeList pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the vScrollbar of field pName to true
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to "225,229,236"
   set the opaque of field pName to true
   set the backgroundColor of field pName to "255,255,255"
   set the textSize of field pName to 11
   set the textFont of field pName to stMonoFont()
end stMakeList

-- ---- assertion plumbing (this half folds into the suite harness) -------------
command stResetCounters
   put 0 into sTotal
   put 0 into sPassed
   put 0 into sFailed
   put 0 into sSkipped
   put empty into sResultText
   put empty into sStRunDone
end stResetCounters

command stAssert pName, pOk
   add 1 to sTotal
   if pOk then
      add 1 to sPassed
      put "PASS  " & pName & return after sResultText
   else
      add 1 to sFailed
      put "FAIL  " & pName & return after sResultText
   end if
end stAssert

-- A SKIP is a first-class outcome, not a silent gap: it counts, it names
-- itself, and it says what would make it run.
command stSkip pName, pReason
   add 1 to sTotal
   add 1 to sSkipped
   put "SKIP  " & pName & "  (" & pReason & ")" & return after sResultText
end stSkip

command stSection pTitle
   put return & "== " & pTitle & " ==" & return after sResultText
end stSection

-- A section that threw is a FAIL, never a skip: a skip means "this piece is
-- not here", and something that blew up very much is.
command stSectionFailed pWhich, pError
   stAssert pWhich & " section ran to completion", false
   stNote "it raised:" && pError
   stNote "the other sections still ran; this one is a defect to report"
end stSectionFailed

command stNote pText
   put "      " & pText & return after sResultText
end stNote

-- THE REPORT IS A LIVE SURFACE, so its text is ambiguous by construction:
-- sResultText grows as the run goes, the async harnesses re-render it every
-- tick, and an unfinished report simply STOPS - with no marker, at whatever
-- section the pump had reached. That reads exactly like a hang. It cost a
-- round trip on the 2026-08-19 suite pass: a fully green run came back ending
-- mid-CROSS-section, and nothing in the pasted text could tell an early Copy
-- from a stalled pump. The async deadline is FORTY SECONDS (kStDeadlineMs in
-- the suite core), and the list stops visibly growing long before it expires,
-- so "it looks finished" is the normal state of a run that is not. Every
-- render of the report goes through here, so that state can never be silent
-- again - on screen or on the clipboard.
function stReportText
   if sStRunDone is "true" then
      return sResultText
   end if
   return sResultText \
         & "      ----------------------------------------------------" & return \
         & "      RUN NOT FINISHED - this is NOT the end of the report." & return \
         & "      An async section is still running. Wait for the SUMMARY" & return \
         & "      section at the bottom, then Copy." & return
end stReportText

command stShow
   -- PIN THE STACK, AND FAIL CLOSED IF THE WINDOW IS NOT THERE. An unqualified
   -- `field "stResults"` resolves against THE DEFAULTSTACK, not against the
   -- stack whose script is running (OXT-ENGINE-NOTES 5.3). Inside openStack
   -- those are the same object, which is why the synchronous half of every run
   -- has always rendered. This handler is ALSO called from an async pump, on a
   -- `send ... in` tick, where they are not: with another window in front the
   -- write would throw "Chunk: error in object expression", and in the suite
   -- core that throw lands in stPump, which is where the timer re-arms.
   -- PRECAUTIONARY, NOT DIAGNOSED. It was written on 2026-08-20 while chasing
   -- two engine reports that ended mid-CROSS-section, and that was the wrong
   -- cause: the third run, same build, completed 1981/0/1 through both
   -- loopbacks and the summary. Those two were early Copies, which is what the
   -- trailer in stReportText now says out loud. What stands on its own is the
   -- hazard class - engine-observed in enet-lan-chat's ecDashOnce on
   -- 2026-08-18 - and the fact that this is the same fault, and the same fix,
   -- as the ui-kit's uiStatus, one carried block over.
   set the defaultStack to the short name of this stack
   if there is no field "stResults" then exit stShow
   put stReportText() into field "stResults"
   put sPassed & " passed, " & sFailed & " failed, " & sSkipped & " skipped, " \
         & sTotal & " total" into field "stSummary"
   if sStRunDone is "true" then
      if sFailed is 0 then
         set the foregroundColor of field "stSummary" to "23,128,63"
      else
         set the foregroundColor of field "stSummary" to "176,58,46"
      end if
   end if
end stShow

-- paint the results list: red FAIL, green PASS, amber SKIP, muted the rest
command stPaint
   local tN, tI, tLine, tErr
   -- Pinned for the reason stShow above is: stReportDone calls this one too,
   -- and an async harness reaches stReportDone from a timer tick.
   set the defaultStack to the short name of this stack
   if there is no field "stResults" then exit stPaint
   put the number of lines of field "stResults" into tN
   lock screen
   try
      repeat with tI = 1 to tN
         put line tI of field "stResults" into tLine
         if tLine begins with "FAIL" then
            set the foregroundColor of line tI of field "stResults" to "176,58,46"
         else if tLine begins with "PASS" then
            set the foregroundColor of line tI of field "stResults" to "23,128,63"
         else if tLine begins with "SKIP" then
            set the foregroundColor of line tI of field "stResults" to "150,110,40"
         else
            set the foregroundColor of line tI of field "stResults" to "138,146,158"
         end if
      end repeat
   catch tErr
   end try
   set the vScroll of field "stResults" to 0
   unlock screen
end stPaint

-- The run's one epilogue: mark done, render, paint. Synchronous harnesses
-- call this at the end of stRun; async ones from the tick that ends the run.
command stReportDone
   put "true" into sStRunDone
   stShow
   stPaint
end stReportDone

command stCopyResults
   -- The whole point of the button: the maintainer pastes the run back
   -- verbatim into the OXT-pass record, so nobody has to retype a result.
   -- It copies stReportText(), not sResultText, so an early copy carries its
   -- own "not finished" trailer into the record - and says so here too,
   -- because the one moment a maintainer is looking at this window is the
   -- moment the dialog appears.
   --
   -- The COUNTS ride along, ahead of the lines. They live in their own field
   -- (stSummary) and used to be left behind, so the runbook taught a message
   -- box incantation to fetch them by hand - one more step between a finished
   -- run and a recorded one, at the exact moment the operator is done. A
   -- report with no totals cannot be checked against the next run's.
   local tError
   try
      set the clipboardData["text"] to sPassed & " passed, " & sFailed \
            & " failed, " & sSkipped & " skipped, " & sTotal & " total" \
            & return & return & stReportText()
      if sStRunDone is "true" then
         answer "Results copied to the clipboard."
      else
         answer "Copied - but the run has NOT finished. An async section is" \
               && "still going; wait for the SUMMARY section, then copy again."
      end if
   catch tError
      answer "Could not reach the clipboard:" && tError
   end try
end stCopyResults

on closeStack
   stCleanup
end closeStack

on mouseUp
   if the short name of the target is "stRerun" then
      stCleanup
      stRun
   else if the short name of the target is "stCopy" then
      stCopyResults
   else
      pass mouseUp
   end if
end mouseUp
-- ==== SUITE HARNESS SCAFFOLD v1 END ====

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   stBuild
   stRun
end openStack











-- ---- the run -----------------------------------------------------------------
command stRun
   local tPS, tHS, tBig
   local tAbruptHost, tAbruptPeer, tResetPeer
   stResetCounters
   put empty into sPhase

   stSection "lifecycle & diagnostics"
   stAssert "enInitialize returns 0", enInitialize() is 0
   stAssert "enInitialize idempotent", enInitialize() is 0
   stAssert "enLibraryVersion names enet", enLibraryVersion() begins with "enet "
   enClearError
   stAssert "enLastError empty after clear", enLastError() is empty

   stSection "stale handles are harmless no-ops"
   stAssert "enSend(0) errors", enSend(0, 0, stTinyData(), 0) < 0
   stAssert "enDisconnect(0) errors", enDisconnect(0, 0) < 0
   put enPeerStatus(0) into tPS
   stAssert "enPeerStatus(0) empty", the number of lines of the keys of tPS is 0
   put enHostStatus(0) into tHS
   stAssert "enHostStatus(0) empty", the number of lines of the keys of tHS is 0
   stAssert "enHostDestroy(0) is a no-op 0", enHostDestroy(0) is 0
   stAssert "enConnect on stale host is 0", enConnect(0, "127.0.0.1", 1, 1, 0) is 0
   stAssert "enFlush(0) errors", enFlush(0) < 0
   -- enBroadcast is the server-fanout primitive, so a stale host is the case
   -- that matters most: a broadcast that quietly "succeeded" against a
   -- destroyed host is a server believing it told every client something it
   -- never sent. It takes the same stale-handle path as enSend.
   stAssert "enBroadcast(0) errors", enBroadcast(0, 0, stTinyData(), 0) < 0
   stAssert "enBroadcastText(0) errors", enBroadcastText(0, 0, "x", 0) < 0

   -- ---- the poll dispatcher library --------------------------------------
   -- enet-helpers.livecodescript is a SHIPPED library - the layer enet-lan-chat
   -- drives and every doc teaches - and until 2026-08-19 not one of its seven
   -- public handlers was named by any test in the tree. It lives under
   -- examples/, so tools/check-suite-coverage.py could not even see it: the
   -- enetxt row scopes to src/. It is carried into this harness by
   -- tools/sync-demo-embeds.py so the two are one script and these can run.
   stSection "the poll dispatcher library (enet-helpers, embedded above)"
   stAssert "enStateName(0) is disconnected", enStateName(0) is "disconnected"
   stAssert "enStateName names the connected state", enStateName(5) is not empty
   stAssert "enStateName answers something for every state 0..9", \
         (enStateName(0) is not empty) and (enStateName(9) is not empty)
   stAssert "enStateName does not answer empty for an unknown state", \
         enStateName(99) is not empty
   stAssert "enFormatBytes(0)", enFormatBytes(0) is "0 B"
   stAssert "enFormatBytes refuses a non-number, fail-closed", enFormatBytes("x") is "0 B"
   stAssert "enFormatBytes refuses empty", enFormatBytes(empty) is "0 B"
   stAssert "enFormatBytes scales past a kilobyte", enFormatBytes(2048) is not "2048 B"
   enPollClearError
   stAssert "enPollLastError is empty while the pump is healthy", enPollLastError() is empty
   -- fail-closed: a bad host arms nothing and must not throw
   enStartPolling 0, empty, 33
   stAssert "enStartPolling(0) is a harmless no-op", enPollLastError() is empty
   enStartPolling empty, empty, 33
   stAssert "enStartPolling(empty) is a harmless no-op", enPollLastError() is empty
   -- the pump exits at its own guard when nothing is armed (this is also the
   -- 2026-08-19 re-arm guard: it must NOT schedule a chain from here)
   enetPollOnce
   stAssert "enetPollOnce with nothing armed is a no-op", enPollLastError() is empty
   enStopPolling empty
   stAssert "enStopPolling(empty) clears every registered host", enPollLastError() is empty

   stSection "tuning + abrupt teardown (isolated: nothing listens on 27099)"
   -- These four binds have no place in the graceful loopback below: a second
   -- live connection would race the server's event handlers (which assert on
   -- the FIRST connect's data payload), and an abrupt teardown would satisfy
   -- the "closing" phase early. So drive them on their own client host aimed
   -- at a port nothing listens on. enConnect is asynchronous - the handshake
   -- never has to complete for these to be exercised, because peer timeout,
   -- host bandwidth, disconnect-now, and reset are all LOCAL operations.
   put enHostCreateClient(2, 2, 0, 0) into tAbruptHost
   stAssert "abrupt-test client host created", tAbruptHost > 0
   put enConnect(tAbruptHost, "127.0.0.1", 27099, 2, 77) into tAbruptPeer
   stAssert "abrupt-test peer handle", tAbruptPeer > 0
   stAssert "enSetPeerTimeout returns 0", enSetPeerTimeout(tAbruptPeer, 32, 5000, 30000) is 0
   stAssert "enSetHostBandwidth returns 0", enSetHostBandwidth(tAbruptHost, 0, 0) is 0
   stAssert "enDisconnectNow returns 0", enDisconnectNow(tAbruptPeer, 9) is 0
   -- A second peer for the reset path: enResetPeer tears the connection down
   -- with no notification at all, so it needs its own victim.
   put enConnect(tAbruptHost, "127.0.0.1", 27099, 2, 78) into tResetPeer
   stAssert "reset-test peer handle", tResetPeer > 0
   stAssert "enResetPeer returns 0", enResetPeer(tResetPeer) is 0
   stAssert "abrupt-test host destroyed", enHostDestroy(tAbruptHost) is 0

   stSection "loopback: hosts + connect (async)"
   put enHostCreateServer("127.0.0.1", 27098, 8, 2, 0, 0) into sServer
   stAssert "server host created", sServer > 0
   put enHostCreateClient(1, 2, 0, 0) into sClient
   stAssert "client host created", sClient > 0
   put enConnect(sClient, "127.0.0.1", 27098, 2, 42) into sClientPeer
   stAssert "enConnect returns a peer handle", sClientPeer > 0
   stAssert "send on out-of-range channel is -3", enSend(sClientPeer, 5, stTinyData(), 0) is -3
   -- the budget: one byte over must refuse with -4, never truncate
   put stRepeatByte(65, 60001) into tBig
   stAssert "send over the budget is -4", enSend(sClientPeer, 0, tBig, 0) is -4

   put empty into sServerPeer
   put empty into sGotEcho
   put empty into sGotUnseq
   put empty into sGotBinary
   put empty into sSentBinary
   put empty into sSawServerDisc
   put "connecting" into sPhase
   put the milliseconds + 15000 into sDeadline
   stShow
   send "stPump" to me in 33 milliseconds
end stRun

-- One pump pass over BOTH hosts; reschedules itself until done/deadline.
-- (The selftest drives enPoll directly - the helpers stack is exercised by
-- the demo; here the binding itself is under test.)
command stPump
   local tEvents, tEvent, tPS
   if sPhase is "done" or sPhase is empty then
      exit stPump
   end if
   put enPoll(sServer) into tEvents
   repeat for each element tEvent in tEvents
      stHandleServer tEvent
   end repeat
   put enPoll(sClient) into tEvents
   repeat for each element tEvent in tEvents
      stHandleClient tEvent
   end repeat

   if sPhase is "connecting" then
      if sServerPeer is not empty and sGotEcho is empty then
         -- connected both ways; the message flow was kicked in the handlers
         put "messaging" into sPhase
      end if
   else if sPhase is "messaging" then
      if sGotEcho is "true" and sGotUnseq is "true" then
         stAssert "echo + broadcast both arrived", true
         -- peer status while connected
         put enPeerStatus(sClientPeer) into tPS
         stAssert "peer state is connected (5)", tPS["state"] is 5
         stAssert "peer status names the server port", tPS["address"] is "127.0.0.1:27098"
         -- the statistics half of the record: by echo time the client has
         -- sent at least the hello, so the counters must be populated. Exact
         -- values are timing-dependent (rtt starts at ENet's default until
         -- an ack updates it, loss on loopback is normally 0), so these pin
         -- presence and documented range, not a number a fast loopback
         -- would make flaky.
         stAssert "live peer rtt is a number >= 0", tPS["rtt"] >= 0
         stAssert "live peer packetLoss within 0..1", \
               tPS["packetLoss"] >= 0 and tPS["packetLoss"] <= 1
         stAssert "live peer counted its sends", \
               tPS["packetsSent"] > 0 and tPS["bytesSent"] > 0
         -- enHostStatus on a LIVE host (the stale-handle case is asserted
         -- above; this is the half that proves the record actually populates).
         put enHostStatus(sServer) into tHS
         stAssert "live enHostStatus counts the connected peer", tHS["peerCount"] is 1
         stAssert "live enHostStatus names the bound port", tHS["address"] is "127.0.0.1:27098"
         stAssert "tuning setters return 0", enSetPeerPingInterval(sClientPeer, 250) is 0
         -- binary with REAL embedded NUL/0x01 bytes, byte-exact both ways
         put textEncode("bin", "utf-8") & numToByte(0) & numToByte(1) \
               & textEncode("tail", "utf-8") into sSentBinary
         stAssert "enSend binary returns 0", enSend(sClientPeer, 1, sSentBinary, 0) is 0
         put "binary" into sPhase
      end if
   else if sPhase is "binary" then
      if sGotBinary is not empty then
         set the caseSensitive to true
         stAssert "binary arrived byte-for-byte (incl. NUL)", sGotBinary is sSentBinary
         stAssert "enDisconnect returns 0", enDisconnect(sClientPeer, 7) is 0
         put "closing" into sPhase
      end if
   else if sPhase is "closing" then
      if sSawServerDisc is "true" then
         stFinish
         exit stPump
      end if
   end if

   if the milliseconds > sDeadline then
      stAssert "async loopback finished before the deadline", false
      stNote "UDP to 127.0.0.1 may be blocked on this machine; see docs."
      stFinish
      exit stPump
   end if
   stShow
   send "stPump" to me in 33 milliseconds
end stPump

command stHandleServer pEvent
   local tR
   switch pEvent["name"]
      case "enetConnect"
         put pEvent["peer"] into sServerPeer
         stAssert "server enetConnect carries data 42", pEvent["data"] is 42
         stAssert "server enetConnect names an address", pEvent["address"] begins with "127.0.0.1:"
         break
      case "enetReceive"
         if pEvent["channel"] is 0 then
            -- the hello: echo it back reliably + a channel-1 broadcast
            stAssert "hello payload intact", textDecode(pEvent["payload"], "utf-8") is "hello enet"
            put enSendText(sServerPeer, 0, "echo!", 0) into tR
            stAssert "server echo send returns 0", tR is 0
            put enBroadcastText(sServer, 1, "fanout", 2) into tR
            stAssert "server broadcast returns 0", tR is 0
         else
            -- the binary phase payload arrives on channel 1
            put pEvent["payload"] into sGotBinary
         end if
         break
      case "enetDisconnect"
         put "true" into sSawServerDisc
         stAssert "server enetDisconnect carries data 7", pEvent["data"] is 7
         break
   end switch
end stHandleServer

command stHandleClient pEvent
   local tR
   switch pEvent["name"]
      case "enetConnect"
         stAssert "client enetConnect names the enConnect handle", pEvent["peer"] is sClientPeer
         put enSendText(sClientPeer, 0, "hello enet", 0) into tR
         stAssert "client hello send returns 0", tR is 0
         break
      case "enetReceive"
         if textDecode(pEvent["payload"], "utf-8") is "echo!" then
            put "true" into sGotEcho
            stAssert "echo on channel 0", pEvent["channel"] is 0
         else if textDecode(pEvent["payload"], "utf-8") is "fanout" then
            put "true" into sGotUnseq
            stAssert "broadcast on channel 1", pEvent["channel"] is 1
         end if
         break
   end switch
end stHandleClient

command stFinish
   local tPS, tHS
   stSection "retirement + teardown"
   -- THE HOSTS MAY NEVER HAVE BEEN CREATED. enHostStatus/enHostDestroy take a
   -- typed Integer, and EMPTY does not convert - it throws "type conversion
   -- error" rather than answering the harmless no-op these lines are written
   -- to expect. Blocked loopback UDP is the documented way to reach that
   -- state (trap 5.5), and this harness is FOLDED into the suite paste - so
   -- an unguarded teardown here does not cost the enet section, it costs the
   -- whole run, at the very end, for every member. Skip is a result.
   if sServer is empty and sClient is empty then
      stSkip "retirement + teardown", "no hosts were created, so there is nothing to retire"
   else
      put enPeerStatus(sClientPeer) into tPS
      stAssert "client peer retired after disconnect", the number of lines of the keys of tPS is 0
      -- the AFTER-disconnect half of the live enHostStatus pair: the host
      -- outlives its one peer, so the record must still populate and count zero
      -- (a host that still counted the departed peer would leak the slot).
      put enHostStatus(sServer) into tHS
      stAssert "live enHostStatus counts zero peers after disconnect", tHS["peerCount"] is 0
      stAssert "enHostDestroy(server) is 0", enHostDestroy(sServer) is 0
      stAssert "double destroy is a no-op 0", enHostDestroy(sServer) is 0
      stAssert "enHostDestroy(client) is 0", enHostDestroy(sClient) is 0
   end if
   stAssert "enDeinitialize returns 0", enDeinitialize() is 0
   stAssert "extra deinitialize is a no-op 0", enDeinitialize() is 0
   put empty into sServer
   put empty into sClient
   put "done" into sPhase
   stSection "summary"
   stNote "A green run proves the sync surface AND a live async loopback on"
   stNote "THIS machine. The two-machine LAN chat leg is the one thing it"
   stNote "cannot prove - that stays the enet-lan-chat / closing-pass run."
   stReportDone
end stFinish

command stCleanup
   put "done" into sPhase
   if sServer is not empty and sServer is not 0 then
      enHostDestroy sServer
   end if
   if sClient is not empty and sClient is not 0 then
      enHostDestroy sClient
   end if
   put empty into sServer
   put empty into sClient
   -- bare command form: OXT cannot compile a zero-argument name() statement;
   -- guarded so closing a stack whose extension is missing (the run already
   -- threw loudly at enInitialize) cannot throw a second time from closeStack
   try
      enDeinitialize
   catch tErr
      -- extension not installed; nothing to release
   end try
end stCleanup

-- ---- small helpers -----------------------------------------------------------
-- One byte of payload (enSend needs a Data; "x" as a literal would be text).
function stTinyData
   return textEncode("x", "utf-8")
end stTinyData

-- pCount copies of byte pCode, built without string-escape folklore.
function stRepeatByte pCode, pCount
   local tOne, tOut, tI
   put numToByte(pCode) into tOne
   put empty into tOut
   -- double up to size, then trim: O(log n) concatenations, not 60001
   put tOne into tOut
   repeat while the number of bytes in tOut < pCount
      put tOut & tOut into tOut
   end repeat
   return byte 1 to pCount of tOut
end stRepeatByte
