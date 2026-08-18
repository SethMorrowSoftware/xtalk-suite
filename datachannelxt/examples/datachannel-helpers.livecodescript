script "dataChannelHelpers"

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
   put dcPoll() into tEvents
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
