script "enetHelpers"

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
