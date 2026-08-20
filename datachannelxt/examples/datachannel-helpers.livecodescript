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
