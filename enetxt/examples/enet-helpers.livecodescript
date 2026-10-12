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
local sEnPollTarget       -- object that receives the semantic event messages
local sEnPollInterval     -- milliseconds between drains (the latency knob)
local sEnPollNote         -- most recent pump failure, empty while healthy
local sEnPolling          -- "true" while the timer loop is armed

/**
Title: enetxt Helpers
Author: Seth Morrow Software
Description:
The poll pump and small helpers for enetxt. Put the enetHelpers stack in
use (start using stack "enetHelpers") and register each host with
<enStartPolling>: a timer services every registered host with <enPoll>
and sends one message per event to your card or object, so an app
handles plain messages instead of running its own pump.

ENet makes no progress unless it is pumped, so this timer is the
transport's heartbeat. The messages are enetConnect, enetDisconnect,
enetReceive and enetError, each with the event array as its parameter,
plus a catch-all enetEvent for every event.

Tags: Networking, Library
*/
-- enStartPolling HOST, TARGET, INTERVALMS
-- Add HOST to the pump set and (first call) arm the loop. TARGET empty means
-- the current card; INTERVALMS defaults to 33 (about 30 Hz). One target and
-- one interval serve every registered host (last caller wins).
/**
Summary: Add a host to the pump and dispatch its events as messages.

pHost: The host handle to service; empty or 0 is ignored.

pTarget: The object that receives the event messages; empty means the current card.

pIntervalMs: Milliseconds between pump passes; empty or less than 1 means 33.

Example:
put enHostCreateServer("", 27000, 32, 2, 0, 0) into sHost
if sHost is not 0 then enStartPolling sHost, the long id of this card, 33

Description:
Use <enStartPolling> once for each host you create, server or client.
Every interval the timer calls <enPoll> on each registered host and
dispatches each event to the target by its name (enetConnect,
enetDisconnect, enetReceive or enetError), followed by a catch-all
enetEvent message, each with the event array as its parameter.

The interval is the latency floor: 16 to 33 milliseconds feels
real-time, 100 or more is fine for chat. One target and one interval
serve every host; the last call sets them. Registering a host twice has
no effect, and only one timer ever runs. A failed poll or dispatch does
not stop the timer; it is recorded for <enPollLastError>.

References: enStopPolling (handler), enPoll (handler), enPollLastError (handler)
*/
command enStartPolling pHost, pTarget, pIntervalMs
   local tSavedDelim
   if pHost is empty or pHost is 0 then
      exit enStartPolling
   end if
   -- sPollHosts is a COMMA list, and `among the items of` splits on whatever
   -- the itemDelimiter is at that line (the family's LCS gotcha: set it
   -- immediately before use, never assume it). Set it around our own read and
   -- put back what we found. This once said the handler INHERITED its
   -- caller's delimiter; engine note 2.3 has since OBSERVED it handler-local
   -- on Windows and Linux (both directions; no Mac run), so there a call
   -- starts at comma and ours cannot reach back. The bracket keeps the rest
   -- of this handler on what it found and costs nothing. The writes below are
   -- delimiter-free (they append a literal comma), so only the read needs
   -- bracketing.
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
/**
Summary: Remove a host from the pump, or stop the pump entirely.

pHost: The host handle to remove; empty stops pumping every host.

Example:
enStopPolling sHost
get enHostDestroy(sHost)

Description:
Use <enStopPolling> with a host when you are done with that host. A
host that is not pumped makes no progress at all: nothing connects,
sends or receives. The timer stops when the last host is removed.

The pump is shared by every stack that uses the helpers, so an empty
host stops other stacks' hosts too; remove your own hosts one by one.
It may be called from inside an event handler the timer dispatched.

References: enStartPolling (handler), enHostDestroy (handler)
*/
command enStopPolling pHost
   local tI, tNew, tSavedDelim
   if pHost is empty then
      put empty into sPollHosts
      put "false" into sEnPolling
      exit enStopPolling
   end if
   put empty into tNew
   -- Same bracketing as enStartPolling: this walk re-splits the comma list, so
   -- it sets the delimiter it needs and restores what it found. Dropping the
   -- restore would leave OUR comma for the rest of this handler; it would not
   -- reach the caller's on Windows or Linux (engine note 2.3, handler-local),
   -- which is what this comment once said.
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
/**
Summary: The first failure the pump recorded since the last clear.

Returns: Empty while the pump is healthy; otherwise a one-line description of the first failure.

Example:
put enPollLastError() into tNote
if tNote is not empty then put tNote & return after field "Log"
enPollClearError

Description:
Use <enPollLastError> to find out why events stopped arriving. The pump
never stops on a failure; it records the first one instead, naming the
host for a failed poll or the event for a failed dispatch. It survives
a stop and restart; only <enPollClearError> clears it.

References: enPollClearError (handler), enStartPolling (handler)
*/
function enPollLastError
   return sEnPollNote
end enPollLastError

-- Clear it, so an app can report each distinct failure once.
/**
Summary: Clear the pump's recorded failure.

Example:
enPollClearError

Description:
Use <enPollClearError> after reading <enPollLastError>, so each
distinct failure is reported once.

References: enPollLastError (handler)
*/
command enPollClearError
   put empty into sEnPollNote
end enPollClearError

-- enStateName N -- map a kPeerState* value (enPeerStatus "state") to a label.
/**
Summary: A label for an ENet peer state number.

pState: The "state" value from <enPeerStatus>.

Returns: "disconnected", "connecting", "connected", "disconnecting", "zombie", or "unknown".

Example:
put enPeerStatus(sPeer) into tStatus
put enStateName(tStatus["state"]) into field "Status"

Description:
Use <enStateName> for status displays. It folds ENet's ten states into
five labels: 1 to 4 are connecting, 5 is connected, and 6 to 8 are
disconnecting.

References: enPeerStatus (handler)
*/
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
/**
Summary: Format a byte count for display.

pBytes: A number of bytes.

Returns: A short string such as "512 B", "1.5 KiB" or "3.2 MiB"; "0 B" when the value is empty or not a number.

Example:
put enPeerStatus(sPeer) into tStatus
put enFormatBytes(tStatus["bytesSent"]) into field "Sent"

Description:
Use <enFormatBytes> for dashboards. It rounds to one decimal place and
uses B, KiB, MiB, GiB and TiB.

References: enPeerStatus (handler), enHostStatus (handler)
*/
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
   -- bytes. Set once before the FIRST read; restore before returning (the
   -- family's LCS gotcha: set it immediately before use, and put back what
   -- you found). This was written when the family took the itemDelimiter for
   -- global state that a caller could hand in and a humaniser could hand
   -- back, and holde-em's v0.15 audit fixed three handlers of this shape on
   -- that reading - heStackFolder returning with the delimiter left at a
   -- slash, heSwapExt at a dot. Engine note 2.3 has since OBSERVED it
   -- handler-LOCAL on Windows and Linux (both directions; no Mac run), so
   -- there a call starts at comma and cannot change its caller's. The rule
   -- still holds for the rest of THIS handler, and the restore costs nothing.
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
