-- midi-helpers.livecodescript
-- ---------------------------------------------------------------------------
-- Reusable LiveCode Script helpers for the midixt extension (realtime MIDI).
-- Paste this into a stack or card script (or a library stack you `start
-- using`), then your own handlers only need to react to events:
--
--     put midiOpenInput(0) into tIn     -- the first input; or midiOpenVirtualInput("My In")
--     scMidiStartListening tIn
--
--     on scNoteOn pChannel, pNote, pVelocity
--        ...
--     end scNoteOn
--
-- MIDI input is POLLED: nothing calls into script from RtMidi's thread (the
-- suite's rule 1), so scMidiStartListening runs a timer that drains midiPoll
-- and sends one message per event to the object that started it:
--
--     scNoteOn pChannel, pNote, pVelocity
--     scNoteOff pChannel, pNote, pVelocity     (a note-on of velocity 0 too)
--     scMidiCC pChannel, pController, pValue
--     scProgramChange pChannel, pProgram
--     scPitchBend pChannel, pValue14           (0 to 16383; 8192 is no bend)
--     scMidiOther pKind, pChannel, pEvent      (everything else: pEvent is the
--                                               whole midiPoll record, its raw
--                                               bytes in pEvent["bytes"])
--
-- This is the MIDI part of ShowControl's showcontrol-helpers.livecodescript,
-- with the same handler names, parameters and messages, so a stack written
-- against it keeps working. What changed is said at scMidiStartListening.
-- Pasting this beside oscxt's osc-helpers and artnetxt's artnet-helpers gives
-- the old combined file's handlers again: no name is defined in two of the
-- three (the suite's tools/check-cross-library-names.py holds that).
-- ---------------------------------------------------------------------------

-- One entry per input being listened to, keyed by its handle:
--    ["generation"]  which timer chain is the live one (see below)
--    ["ms"]          the poll interval
--    ["target"]      the long id of the object the events are sent to
local sMidiListeners
-- The last generation handed out. It only ever grows, so a timer message
-- still pending from a chain that was stopped can never match a later one.
local sMidiGeneration

-- ===== MIDI poll dispatcher ================================================

-- Start listening on an open input (a handle from midiOpenInput or
-- midiOpenVirtualInput). pIntervalMs is the poll interval (default 3); a
-- shorter one only lowers latency, since RtMidi queues every message with its
-- timing between polls. Events go to the object that called this handler, or
-- to pTarget (a long id) if given, and travel up ITS message path, so
-- `on scNoteOn` in that object, its card or its stack receives them.
--
-- Why the listener is remembered here: the poll re-arms itself with
-- `send ... to me in N milliseconds`, and inside a timer-delivered message
-- `the target` is this LIBRARY, not your card. Dispatching to `the target`
-- (as ShowControl's helper once did) silently delivered every timer-polled
-- event to the library itself whenever the helpers were used via
-- `start using` (tests/lcs/helpers_test.livecodescript).
--
-- What midixt changed, each pinned by tests/lcs/helpers_test.livecodescript:
--  * Each input has its OWN listener. ShowControl kept one interval and one
--    target for all of them, so starting a second input sent the first
--    one's events to the second one's target too.
--  * Starting again (the same input, or after scMidiStopListening) replaces
--    the running timer. ShowControl's never stopped: every stop-and-start
--    inside one interval left one more timer polling for good.
--  * A handle that is not a port (0 from an open that failed) starts nothing
--    and sets the result to why. ShowControl polled it every 3 ms for ever.
--  * A port closed while it is listened to stops its own timer at the next
--    poll (midiPoll says it is not an open input).
--  * scMidiIsListening(pHandle) tells whether an input is being listened to.
-- Unchanged on purpose: if one of your handlers throws, listening on that
-- input stops (as it always has: the throw skips the next poll) and the error
-- reaches you as before. scMidiIsListening turns false; start it again once
-- the handler is fixed.
on scMidiStartListening pHandle, pIntervalMs, pTarget
   local tGeneration
   if pIntervalMs is empty then put 3 into pIntervalMs
   if pIntervalMs is not a number then
      throw "scMidiStartListening: the poll interval must be a number of milliseconds, not" && pIntervalMs
   end if
   if pHandle is not an integer then
      throw "scMidiStartListening: pHandle must be a MIDI input handle, not" && pHandle
   end if
   if pHandle < 1 then
      -- 0 is what a port that would not open returns: there is nothing to poll
      return "scMidiStartListening: no open MIDI input (handle" && pHandle & ")"
   end if
   if pTarget is empty then put the long id of the target into pTarget
   add 1 to sMidiGeneration
   put sMidiGeneration into tGeneration
   -- pHandle + 0 is the key everywhere, so "3", 3 and 3.0 are one listener
   put tGeneration into sMidiListeners[pHandle + 0]["generation"]
   put pIntervalMs into sMidiListeners[pHandle + 0]["ms"]
   put pTarget into sMidiListeners[pHandle + 0]["target"]
   scMidiPollAndDispatch pHandle + 0, tGeneration
   return empty
end scMidiStartListening

-- Stop listening on one input, or on every input when pHandle is empty (all
-- ShowControl's version could do). Messages still waiting in the input stay
-- queued for a later poll. It does not close the port: midiClose does that.
on scMidiStopListening pHandle
   if pHandle is empty then
      put empty into sMidiListeners
   else if pHandle is a number then
      delete variable sMidiListeners[pHandle + 0]
   end if
end scMidiStopListening

-- True while the dispatcher is polling this input.
function scMidiIsListening pHandle
   if pHandle is not a number then return false
   return sMidiListeners[pHandle + 0]["generation"] is not empty
end scMidiIsListening

-- One poll: drain the input and send each event on. The timer calls it with
-- the generation of the chain that armed it; a tick from a chain that was
-- stopped or replaced ends there. Called without a generation (by hand, as
-- ShowControl's could be) it polls once and arms no timer of its own.
on scMidiPollAndDispatch pHandle, pGeneration
   local tEvents, tEvent, tTarget, tError, tFailed
   if not scMidiIsListening(pHandle) then exit scMidiPollAndDispatch
   put pHandle + 0 into pHandle
   if pGeneration is not empty and pGeneration is not sMidiListeners[pHandle]["generation"] then
      exit scMidiPollAndDispatch
   end if
   put sMidiListeners[pHandle]["target"] into tTarget
   put midiPoll(pHandle) into tEvents
   if tEvents is empty and midiLastError() contains "not an open input port" then
      -- closed under us (midiClose without scMidiStopListening): stop polling
      delete variable sMidiListeners[pHandle]
      exit scMidiPollAndDispatch
   end if
   put false into tFailed
   -- midiPoll's list is keyed 1..N, which `repeat for each element` walks in
   -- order (engine exec-keywords.cpp, bug 15457), so events keep their order.
   repeat for each element tEvent in tEvents
      try
         scMidiDispatchEvent tEvent, tTarget
      catch tError
         put true into tFailed
      end try
      if tFailed then exit repeat
   end repeat
   if tFailed then
      -- One of the handlers threw. Stop this listener, as the throw always
      -- did, but say so (scMidiIsListening) and hand the error on unchanged.
      -- (A throw inside `catch` never reaches the caller on OXT: hence here.)
      if pGeneration is sMidiListeners[pHandle]["generation"] then
         delete variable sMidiListeners[pHandle]
      end if
      throw tError
   end if
   -- Re-arm only the live chain, and only from a timer tick: a handler that
   -- stopped or restarted listening during this batch has the last word.
   if pGeneration is not empty and pGeneration is sMidiListeners[pHandle]["generation"] then
      send "scMidiPollAndDispatch" && pHandle & "," & pGeneration to me \
            in sMidiListeners[pHandle]["ms"] milliseconds
   end if
end scMidiPollAndDispatch

-- `dispatch ... with` passes REAL parameters. ShowControl's first form,
--    send "scNoteOn" && channel && note && velocity to ...
-- built the string "scNoteOn 1 60 100", and a message string's parameters
-- are separated by COMMAS, so the whole "1 60 100" arrived in pChannel and
-- pNote and pVelocity were empty (caught by tests/lcs/helpers_test).
private command scMidiDispatchEvent pEvent, pTarget
   switch pEvent["kind"]
      case "noteOn"
         dispatch "scNoteOn" to pTarget with pEvent["channel"], pEvent["data1"], pEvent["data2"]
         break
      case "noteOff"
         dispatch "scNoteOff" to pTarget with pEvent["channel"], pEvent["data1"], pEvent["data2"]
         break
      case "controlChange"
         dispatch "scMidiCC" to pTarget with pEvent["channel"], pEvent["data1"], pEvent["data2"]
         break
      case "programChange"
         dispatch "scProgramChange" to pTarget with pEvent["channel"], pEvent["data1"]
         break
      case "pitchBend"
         dispatch "scPitchBend" to pTarget with pEvent["channel"], pEvent["value14"]
         break
      default
         -- channelPressure / polyAftertouch / sysex / system: hand off the
         -- kind, the channel and the whole decoded record (raw bytes in
         -- ["bytes"])
         dispatch "scMidiOther" to pTarget with pEvent["kind"], pEvent["channel"], pEvent
   end switch
end scMidiDispatchEvent
