script "dataChannelSelfTest"

-- datachannel-selftest.livecodescript - a self-building RUNTIME harness that
-- drives the DataChannelXT public API end to end in OXT and reports PASS /
-- FAIL per handler. This is the OXT-pass companion to the C++ smoke test: the
-- smoke test proves the shim against libdatachannel in CI; this proves the
-- .lcb BINDING (the foreign-decl signatures, the record walkers, the buffer
-- round-trips) actually runs - the one layer CI cannot reach, since OXT has
-- no headless way to compile or run .lcb.
--
-- COVERAGE NOTE (honest): the harness now drives every public dc* handler
-- (31 of them), including the ones that used to appear only in the
-- stale-handle section - dcCreateChannelEx, dcSetBufferedLowThreshold,
-- dcLocalDescriptionType, dcChannelProtocol, dcSetLocalDescription - and it
-- pins the non-trickle signaling contract (a live local description carries
-- "a=candidate", and the offer/answer roles match the flow). What is recorded:
-- on 2026-08-08 the suite selftest (tests/suite-selftest.livecodescript at
-- the repository root) ran green on a real OXT engine with a live loopback
-- that negotiated, opened both ends, round-tripped a payload byte-for-byte,
-- refused 60001 bytes with -4, and tore down through dcCleanup; and on
-- 2026-08-10 THIS file's synchronous half ran green folded into that same
-- harness (23 checks, twice in one day), which calls every one of the 31
-- public handlers by name and pins the whole stale-handle surface as harmless
-- no-ops. So the binding, the transfer spine, and the synchronous contracts
-- are observed. CLOSED 2026-08-15: this file ran STANDALONE green end to
-- end, async loopback included (the fold still excludes that section; the
-- suite core drives its own) - the LIVE halves of
-- dcSendText, dcBufferedAmount, dcGatheringState, dcSelectedCandidatePair,
-- the dcBufferedLow EVENT after a cap-sized send, and the a=candidate/role
-- pins among them are all dated runtime results now. A green re-run needs
-- no label work.
--
-- ADDED 2026-08-17, and NOT observed: the four stale-handle ACTION checks now
-- assert the exact -2 instead of `< 0`, an oversize dcSendText pins the shim's
-- handle-before-size classification order, and dcSendText's embedded-NUL
-- refusal - the one refusal the .lcb has to make because the shim cannot see
-- a NUL that has become its terminator - is checked here for the first time.
-- Those five legs are verified statically; they need an OXT pass.
--
-- HOW TO USE: open OXT, make a one-card stack, paste THIS into the STACK
-- script (Object > Stack Script), then close+reopen. It builds its own UI,
-- runs the synchronous checks, then a LIVE LOOPBACK (two in-process peers,
-- script-shuttled signaling, a real DTLS/SCTP association on this machine),
-- message round-trips, and teardown - and shows a green/red list. Needs the
-- installed org.openxtalk.library.datachannel extension.
--
-- WHAT IT CHECKS: every public handler returns a sane value; stale handles
-- are harmless; the loopback connects; text and binary messages round-trip
-- byte-for-byte; the drain's arrays carry the documented keys; close/free/
-- cleanup are idempotent. The async phase has a deadline - a machine that
-- blocks ALL UDP (even to itself) fails the loopback section with a note
-- rather than hanging.


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
--   dcLocalDescriptionReady  pEvent["peer"], ["sdp"], ["sdpType"] - SHIP
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
local sPollNote         -- the FIRST poll fault since the last clear - a bad
                        -- drain, a bad dispatch, or a target that stopped
                        -- resolving; "" while healthy
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
   -- is inside dcPoll's buffer helper, so the throw was read as happening HERE,
   -- on the way in. Guarding only the half you have already been shown is how a
   -- diagnostic costs two passes instead of one, and THAT lesson stands: an
   -- unguarded `put dcPoll() into tEvents` takes the timer chain down before any
   -- dispatch is attempted, so both halves are guarded and both stay guarded.
   --
   -- WHERE THE THROW ACTUALLY WAS (OXT-ENGINE-NOTES 6.7, 2026-08-18). Once this
   -- pump reported the two halves distinctly - "dcPoll failed on drain #N"
   -- versus "dispatch of <name> failed" - the run printed the DISPATCH form,
   -- naming dcLocalDescription: an event name colliding with a public library
   -- handler of the same name. The drain was clean. So line 234 was an
   -- INFERENCE from a line number, not a location, and why that number was
   -- reported at all is still unexplained. That is not a reason to drop this
   -- guard: it is here because a throw on the way in kills the timer chain,
   -- which is true whether or not it has happened yet.
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
         --
         -- NO `+ 1` HERE. The increment happens above, BEFORE the try, so
         -- sPollDrains already counts this drain: the first one is #1. The
         -- version that shipped added one anyway and reported the first drain
         -- as #2 - inverting the single discrimination the counter exists to
         -- make, in the same commit whose message argued for it. An off-by-one
         -- in a diagnostic is not cosmetic; it is a diagnostic that lies.
         put "dcPoll failed on drain #" & sPollDrains & ": " & \
               line 1 of tErr into sPollNote
      end if
      -- Do NOT stop polling: a transient drain failure must not silently end
      -- the app's event delivery. Reschedule below and try again.
      put empty into tEvents
   end try
   repeat for each element tEvent in tEvents
      put tEvent["name"] into tName
      -- TRANSITION SHIM, and it is what makes this work without reinstalling
      -- the extension. Before 2026-08-18 the shim emitted "dcLocalDescription"
      -- for this event - a name this library ALSO exports as a getter. xTalk
      -- has one message namespace, so dispatching it reached
      -- dcLocalDescription(in pPeer as Integer) with the event Array and threw
      -- "cannot convert value"; no app handler was ever reached. The .lcb now
      -- emits the ...Ready spelling, but an extension packaged before that
      -- still emits the old one, so map it here and apps work against either.
      -- REMOVE THIS when no supported build emits the old name.
      if tName is "dcLocalDescription" then
         put "dcLocalDescriptionReady" into tName
      end if
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
   -- DO NOT RE-ARM IF A DISPATCH STOPPED US. The pass above runs app code, and
   -- app code legitimately calls dcStopPolling from inside a handler this
   -- very loop dispatched - enet-lan-chat does exactly that in `on
   -- enetDisconnect`. Re-arming unconditionally leaves a tick in flight after
   -- the flag went false, and the arm-once guard in dcStartPolling tests that
   -- same flag: the next start sees "not polling", arms a SECOND chain, and
   -- the stale tick then re-arms the first. Two permanent chains, neither
   -- stoppable on its own because both read one flag - which is the trap the
   -- arm-once guard was added to prevent, reached from the other side.
   if sPolling is not "true" then
      exit dcChannelPollOnce
   end if
   send "dcChannelPollOnce" to me in (sPollInterval) milliseconds
end dcChannelPollOnce

-- dcPollLastError() -- empty while the dispatcher is healthy; otherwise the
-- FIRST fault since the last dcPollClearError: a drain failure (carrying a
-- drain counter, so an early one and a late one are distinguishable), a
-- dispatch failure (naming the event), or a poll target that stopped
-- resolving (saying it fell back to this card).
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

constant kStTitle = "DataChannelXT - API Self-Test"
constant kStWidth = 660
constant kStHeight = 620

-- ---- state -------------------------------------------------------------------
local sPeerA, sPeerB    -- the loopback peers
local sChanA, sChanB    -- A's channel; B's (learned from dcChannelIncoming)
local sAOpen, sBOpen    -- "true" once each side's channel open arrived
local sGotText          -- the text B received
local sGotBytes         -- the binary payload A received back (a Data)
local sSentBytes        -- the binary payload B sent (kept for byte-exact compare)
local sGotBufferedLow   -- "true" once A's channel reported dcBufferedLow
local sBigLen           -- the cap-sized payload length for the buffered-low leg
local sDeadline         -- the async phase's drop-dead time (ms clock)
local sPhase            -- "", "opening", "messaging", "done"

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
   local tPair, tBig, tNulR, tNulErr
   stResetCounters
   put empty into sPhase

   stSection "lifecycle & diagnostics"
   stAssert "dcInit returns 0", dcInit() is 0
   stAssert "dcInit idempotent", dcInit() is 0
   stAssert "dcLibraryVersion mentions libdatachannel", dcLibraryVersion() contains "libdatachannel"
   dcClearError
   stAssert "dcLastError empty after clear", dcLastError() is empty

   stSection "stale handles are harmless no-ops"
   -- The ACTION calls assert the EXACT code, not `< 0`. -2 (DCX_ERR_BAD_HANDLE)
   -- is what the shim's classification order produces: every dcx_* action
   -- validates the handle FIRST, then the argument, then the size, so a stale
   -- handle can only ever answer -2. `< 0` also passed for -6, the firewall's
   -- "a native throw was caught" - which would mean the stale-handle path is
   -- THROWING somewhere inside libdatachannel rather than being the harmless
   -- no-op this whole section exists to prove. Tightened 2026-08-17; the
   -- values are pinned to dcx_abi.h by tools/check-record-registry.py so a
   -- renumber cannot leave these literals quietly wrong.
   stAssert "dcClosePeer(0) is -2", dcClosePeer(0) is -2
   stAssert "dcPeerState(0) is -1", dcPeerState(0) is -1
   stAssert "dcGatheringState(0) is -1", dcGatheringState(0) is -1
   stAssert "dcLocalDescription(0) empty", dcLocalDescription(0) is empty
   -- an Array crosses from LCB; LiveCode Script has NO `{}` literal, and a
   -- bare `is empty` on an array is vacuously true (arrays stringify to
   -- empty) - so emptiness is asserted by counting keys of a LOCAL (a
   -- function result cannot be subscripted or keyed directly in LCS either)
   put dcSelectedCandidatePair(0) into tPair
   stAssert "dcSelectedCandidatePair(0) empty", the number of lines of the keys of tPair is 0
   stAssert "dcCreateChannel(0) is 0", dcCreateChannel(0, "x") is 0
   stAssert "dcSendText(0) is -2", dcSendText(0, "x") is -2
   -- The classification ORDER itself, pinned: an oversize message on a stale
   -- handle is still -2, because dcx_send_text checks the handle before it
   -- measures. (The live -4 legs need an open channel and live in the async
   -- half, which the suite fold deliberately leaves out.)
   put stRepeatByte(65, 60001) into tBig
   stAssert "oversize dcSendText on a stale handle is still -2", dcSendText(0, tBig) is -2
   stAssert "dcChannelLabel(0) empty", dcChannelLabel(0) is empty
   stAssert "dcChannelStreamId(0) is -1", dcChannelStreamId(0) is -1
   stAssert "dcChannelIsOpen(0) is false", dcChannelIsOpen(0) is false
   stAssert "dcChannelPeer(0) is 0", dcChannelPeer(0) is 0
   stAssert "dcBufferedAmount(0) is -1", dcBufferedAmount(0) is -1
   stAssert "dcLocalDescriptionType(0) empty", dcLocalDescriptionType(0) is empty
   stAssert "dcChannelProtocol(0) empty", dcChannelProtocol(0) is empty
   stAssert "dcSetLocalDescription(0) is -2", dcSetLocalDescription(0, "offer") is -2
   stAssert "dcSetBufferedLowThreshold(0) is -2", dcSetBufferedLowThreshold(0, 4096) is -2
   stAssert "dcCreateChannelEx(0) is 0", \
         dcCreateChannelEx(0, "x", "proto", false, -1, -1, false, -1) is 0
   dcFreePeer(0)      -- must not crash
   dcFreeChannel(0)   -- must not crash
   stAssert "dcFreePeer/dcFreeChannel(0) survived", true
   stAssert "dcSendText(0) left a last-error", dcLastError() is not empty

   -- The embedded-NUL refusal, which the BINDING makes because the shim
   -- CANNOT: pText crosses as ZStringUTF8, so by the time dcx_send_text holds
   -- it the NUL has become the terminator and the tail of the message is
   -- gone. -3 on a STALE handle is the tell that the .lcb refused before the
   -- FFI - a shim that saw this call would have answered -2 for the handle.
   -- It sits BETWEEN the assertion above and the clear below on purpose: that
   -- assertion has just proved the shim's last-error is DIRTY, so the empty
   -- assertion here can only pass if this refusal cleared it. Placed after
   -- the dcClearError instead, it would have passed whether the refusal ran
   -- or not - a check that answers the question nobody asks twice.
   -- Try-guarded because what the LCS -> LCB String bridge does with a NUL
   -- char is itself unobserved engine behaviour: a throw at the marshalling
   -- boundary must be a reported FAIL carrying its message, not the end of a
   -- 500-check run.
   put "" into tNulR
   try
      put dcSendText(0, "a" & numToByte(0) & "b") into tNulR
   catch tNulErr
      put "threw:" && tNulErr into tNulR
   end try
   stAssert "dcSendText refuses an embedded NUL with -3", tNulR is -3
   stAssert "the NUL refusal cleared the shim last-error", dcLastError() is empty
   dcClearError

   -- ---- the poll dispatcher library --------------------------------------
   -- datachannel-helpers.livecodescript is a SHIPPED library, and until
   -- 2026-08-19 none of its eight public handlers was named by any test. It
   -- lives under examples/, so tools/check-suite-coverage.py could not see it
   -- (the datachannelxt row scopes to src/). tools/sync-demo-embeds.py carries
   -- it into this harness so the two are one script.
   --
   -- WHAT THIS SECTION DELIBERATELY DOES NOT DO: arm the pump. dcStartPolling
   -- registers a target and schedules dcChannelPollOnce, which calls dcPoll and
   -- DISPATCHES what it drains. This harness's synchronous half is folded into
   -- the suite paste, where the core drives its own DataChannel loopback off
   -- the same queue - so arming a second drainer here would steal the events
   -- that loopback is waiting for. It is the same "two state machines racing
   -- for the event handlers" rule that keeps this member's async loopback out
   -- of the fold, and those two handlers carry it as a written coverage
   -- exemption rather than a test that would be unsafe where it runs.
   stSection "the poll dispatcher library (datachannel-helpers, embedded above)"
   stAssert "dcStateName(0) is new", dcStateName(0) is "new"
   stAssert "dcStateName(2) is connected", dcStateName(2) is "connected"
   stAssert "dcStateName answers for an unknown state", dcStateName(99) is not empty
   stAssert "dcGatheringName(0) is not empty", dcGatheringName(0) is not empty
   stAssert "dcGatheringName(2) names the complete state", dcGatheringName(2) is not empty
   stAssert "dcGatheringName answers for an unknown state", dcGatheringName(99) is not empty
   stAssert "dcStateName and dcGatheringName are different maps", \
         dcStateName(1) is not dcGatheringName(1)
   stAssert "dcFormatBytes(0)", dcFormatBytes(0) is "0 B"
   stAssert "dcFormatBytes refuses a non-number, fail-closed", dcFormatBytes("x") is "0 B"
   stAssert "dcFormatBytes refuses empty", dcFormatBytes(empty) is "0 B"
   stAssert "dcFormatBytes scales past a kilobyte", dcFormatBytes(2048) is not "2048 B"
   dcPollClearError
   stAssert "dcPollLastError is empty while the pump is healthy", dcPollLastError() is empty
   -- safe on its own: it only lowers the flag, and nothing here raised it
   dcStopPolling
   stAssert "dcStopPolling is safe when nothing is polling", dcPollLastError() is empty

   stSection "loopback: create + negotiate (async)"
   put dcCreatePeer("") into sPeerA
   put dcCreatePeer("") into sPeerB
   stAssert "dcCreatePeer A > 0", sPeerA > 0
   stAssert "dcCreatePeer B > 0", sPeerB > 0
   stAssert "peers distinct", sPeerA is not sPeerB
   stAssert "new peer state is new/connecting", dcPeerState(sPeerA) >= 0
   put dcCreateChannel(sPeerA, "selftest") into sChanA
   stAssert "dcCreateChannel > 0", sChanA > 0
   stAssert "dcChannelPeer maps back", dcChannelPeer(sChanA) is sPeerA
   put empty into sChanB
   put empty into sAOpen
   put empty into sBOpen
   put empty into sGotText
   put empty into sGotBytes
   put empty into sSentBytes
   put empty into sGotBufferedLow
   put empty into sBigLen
   put "opening" into sPhase
   put the milliseconds + 20000 into sDeadline
   stShow
   send "stPump" to me in 33 milliseconds
end stRun

-- One poll pass of the async phase; reschedules itself until done/deadline.
command stPump
   local tEvents, tEvent, tDest, tPair, tExChan
   if sPhase is "done" or sPhase is empty then
      exit stPump
   end if
   put dcPoll() into tEvents
   repeat for each element tEvent in tEvents
      -- the in-script signaling shuttle (the whole point of the loopback)
      -- Either spelling: the .lcb emits "dcLocalDescriptionReady" since
      -- 2026-08-18, an extension packaged before that still emits the old
      -- name. Accepting both keeps this green across the transition.
      if tEvent["name"] is among the items of "dcLocalDescription,dcLocalDescriptionReady" then
         put stOtherPeer(tEvent["peer"]) into tDest
         if tDest is not empty then
            dcSetRemoteDescription tDest, tEvent["sdp"], tEvent["sdpType"]
         end if
      else if tEvent["name"] is "dcLocalCandidate" then
         put stOtherPeer(tEvent["peer"]) into tDest
         if tDest is not empty then
            dcAddRemoteCandidate tDest, tEvent["candidate"], tEvent["mid"]
         end if
      else if tEvent["name"] is "dcChannelIncoming" then
         -- FIRST incoming only: the later dcCreateChannelEx check opens a
         -- second channel, whose incoming event must not retarget sChanB.
         if tEvent["peer"] is sPeerB and sChanB is empty then
            put tEvent["channel"] into sChanB
         end if
      else if tEvent["name"] is "dcChannelOpen" then
         if tEvent["channel"] is sChanA then
            put "true" into sAOpen
         else if sChanB is not empty and tEvent["channel"] is sChanB then
            put "true" into sBOpen
         end if
      else if tEvent["name"] is "dcMessage" then
         if tEvent["text"] is not empty then
            put tEvent["text"] into sGotText
         else
            put tEvent["payload"] into sGotBytes
         end if
      else if tEvent["name"] is "dcBufferedLow" then
         -- only A's channel is armed (threshold 4096, above); an event
         -- naming any other channel would be a contract violation, so the
         -- flag is set only for the armed one and the assertion below
         -- would time out loudly on a misdelivered event.
         if tEvent["channel"] is sChanA then
            put "true" into sGotBufferedLow
         end if
      end if
   end repeat

   if sPhase is "opening" then
      if sAOpen is "true" and sBOpen is "true" then
         stAssert "loopback connected + both channels open", true
         stAssert "incoming label is selftest", dcChannelLabel(sChanB) is "selftest"
         stAssert "peer A connected", dcPeerState(sPeerA) is 2
         stAssert "dcChannelIsOpen(A)", dcChannelIsOpen(sChanA) is true
         stAssert "stream id assigned", dcChannelStreamId(sChanA) >= 0
         stAssert "negotiated max message > 0", dcChannelMaxMessage(sChanA) > 0
         stAssert "buffered amount >= 0", dcBufferedAmount(sChanA) >= 0
         -- keyed access needs a local (LCS cannot subscript a function result)
         put dcSelectedCandidatePair(sPeerA) into tPair
         stAssert "selected pair has localCandidate", tPair["localCandidate"] is not empty
         -- The NON-TRICKLE signaling contract on live peers: once negotiated,
         -- each side's local description is a real SDP carrying its candidates,
         -- and the offer/answer roles are the ones the flow assigned (A made
         -- the channel, so A offered). This is the call the DHT-chat demo ships
         -- as one blob; the stale-handle half is asserted above.
         stAssert "local description is a real SDP", dcLocalDescription(sPeerA) contains "v=0"
         stAssert "local description carries candidates", \
               dcLocalDescription(sPeerA) contains "a=candidate"
         stAssert "peer A describes itself as the offer", dcLocalDescriptionType(sPeerA) is "offer"
         stAssert "peer B describes itself as the answer", dcLocalDescriptionType(sPeerB) is "answer"
         -- a channel created without a protocol reports none (the live half of
         -- the stale-handle assertion above)
         stAssert "dcChannelProtocol empty when unset", dcChannelProtocol(sChanA) is empty
         stAssert "dcSetBufferedLowThreshold on a live channel returns 0", \
               dcSetBufferedLowThreshold(sChanA, 4096) is 0
         stAssert "dcSendText returns 0", dcSendText(sChanA, "hello oxt") is 0
         put "messaging" into sPhase
      end if
   else if sPhase is "messaging" then
      -- a distinct phase per step, so a slow delivery cannot re-fire the send
      -- (and re-count the assertions) on every 33 ms pump pass
      if sGotText is not empty then
         stAssert "text arrived intact", sGotText is "hello oxt"
         -- REAL embedded NUL/0x01 bytes (LCS string literals have no escape
         -- syntax - a "\0" would be two ordinary characters), so this proves
         -- a Data crosses unmangled, not merely that ASCII survives
         put textEncode("binary", "UTF-8") & numToByte(0) & textEncode("byte", "UTF-8") \
               & numToByte(1) & textEncode("round-trip", "UTF-8") into sSentBytes
         stAssert "dcSendData returns 0", dcSendData(sChanB, sSentBytes) is 0
         put "binary-wait" into sPhase
      end if
   else if sPhase is "binary-wait" then
      if sGotBytes is not empty then
         -- byte-exact: `is` is case-insensitive by default, which would let
         -- 0x41 match 0x61 inside binary data
         set the caseSensitive to true
         stAssert "binary arrived byte-for-byte (incl. NUL)", sGotBytes is sSentBytes
         -- dcCreateChannelEx on a LIVE peer, last so its extra negotiation
         -- cannot disturb the checks above. The protocol is a property of the
         -- local object, set at creation, so it reads back without waiting for
         -- the far side to open the channel.
         put dcCreateChannelEx(sPeerA, "extra", "oxt-proto", true, 0, -1, false, -1) into tExChan
         stAssert "dcCreateChannelEx > 0", tExChan > 0
         stAssert "dcChannelProtocol round-trips", dcChannelProtocol(tExChan) is "oxt-proto"
         stAssert "dcChannelLabel round-trips", dcChannelLabel(tExChan) is "extra"
         dcFreeChannel tExChan
         -- the LIVE half of the gathering-state getter (the stale half is
         -- pinned at -1 above). The a=candidate assertion already proved
         -- candidates were gathered, and with no ICE servers configured
         -- gathering has nothing left to wait for, so by the time the
         -- binary round-trip has completed both peers must report
         -- kGatheringComplete (2).
         stAssert "gathering state is complete (2) on both peers", \
               dcGatheringState(sPeerA) is 2 and dcGatheringState(sPeerB) is 2
         -- the dcBufferedLow EVENT - the live half of the threshold setter
         -- asserted above. A's channel is armed at 4096, so one payload at
         -- the negotiated cap (60000 under the suite budget) must push the
         -- send buffer past the threshold, and the drain back under it
         -- fires the event. Waited on with the same deadline as the rest
         -- of the async phase, so a machine that never fires it fails
         -- loudly instead of hanging.
         put dcChannelMaxMessage(sChanA) into sBigLen
         put empty into sGotBytes
         stAssert "cap-sized send returns 0", \
               dcSendData(sChanA, stRepeatByte(66, sBigLen)) is 0
         put "bufferedlow-wait" into sPhase
      end if
   else if sPhase is "bufferedlow-wait" then
      if sGotBufferedLow is "true" and the number of bytes in sGotBytes is sBigLen then
         stAssert "dcBufferedLow fired once the cap-sized send drained", true
         stAssert "the cap-sized payload arrived whole", true
         stFinish
         exit stPump
      end if
   end if

   if the milliseconds > sDeadline then
      stAssert "async loopback finished before the deadline", false
      stNote "UDP to this machine's own address may be blocked; see docs."
      stFinish
      exit stPump
   end if
   stShow
   send "stPump" to me in 33 milliseconds
end stPump

function stOtherPeer pPeer
   if pPeer is sPeerA then
      return sPeerB
   else if pPeer is sPeerB then
      return sPeerA
   end if
   return empty
end stOtherPeer

command stFinish
   stSection "teardown"
   -- THE HANDLES MAY NEVER HAVE BEEN MINTED, and until 2026-08-18 this
   -- section assumed they were. Every dc* handler below takes a typed
   -- Integer parameter, and an EMPTY value does not convert - it is a hard
   -- "type conversion error", not a no-op. So on a machine where the
   -- loopback could not start (blocked UDP is the documented case), the run
   -- did not lose the loopback section: it lost EVERYTHING, at teardown,
   -- with an engine error dialog instead of a report. The suite's own
   -- history has this exact shape written down - one uncaught error taking
   -- six harnesses' results with it - and this is the same failure one layer
   -- down. A skip is a result; a dead run is not.
   if sPeerA is empty and sPeerB is empty then
      stSkip "teardown", "no peers were created, so there is nothing to tear down"
   else
      stAssert "dcCloseChannel returns 0", dcCloseChannel(sChanA) is 0
      dcFreeChannel(sChanA)
      dcFreeChannel(sChanA)   -- double free: no-op
      stAssert "double dcFreeChannel survived", true
      dcFreePeer(sPeerA)
      dcFreePeer(sPeerB)
      dcFreePeer(sPeerA)      -- double free: no-op
      stAssert "freed peer answers -1", dcPeerState(sPeerA) is -1
   end if
   stAssert "dcCleanup returns 0", dcCleanup() is 0
   stAssert "dcCleanup idempotent", dcCleanup() is 0
   put empty into sPeerA
   put empty into sPeerB
   put "done" into sPhase
   stSection "summary"
   stNote "A green run proves the stale-handle surface AND a live in-process"
   stNote "loopback (ICE/DTLS/SCTP) on THIS machine. Browser interop and the"
   stNote "two-machine DHT-signaled path stay the datachannel demos' runs."
   stReportDone
end stFinish

command stCleanup
   put "done" into sPhase
   if sPeerA is not empty and sPeerA is not 0 then
      dcFreePeer(sPeerA)
   end if
   if sPeerB is not empty and sPeerB is not 0 then
      dcFreePeer(sPeerB)
   end if
   put empty into sPeerA
   put empty into sPeerB
   -- BARE, not dcCleanup(). A zero-argument call in STATEMENT position parses
   -- as a command taking `()` as its argument, and `()` is not an expression,
   -- so it is a compile error. In EXPRESSION position (the two stAssert lines
   -- above) the parenthesised form is correct and required. Try-guarded the
   -- way enet's harness guards enDeinitialize: closing the stack with the
   -- extension absent must not throw a second error out of closeStack.
   local tCleanupErr
   try
      dcCleanup
   catch tCleanupErr
      -- extension not installed; nothing to release
   end try
end stCleanup

-- pCount copies of byte pCode (the cap-sized buffered-low payload). Built by
-- doubling - O(log n) concatenations, not 60000 - and with numToByte, since
-- string literals have no escape syntax.
function stRepeatByte pCode, pCount
   local tOut
   put numToByte(pCode) into tOut
   repeat while the number of bytes in tOut < pCount
      put tOut & tOut into tOut
   end repeat
   return byte 1 to pCount of tOut
end stRepeatByte
