script "MidiHelpersTest"
-- ---------------------------------------------------------------------------
-- The shipped helper library (examples/midi-helpers.livecodescript), loaded
-- the way the docs recommend -- as a library stack in the message path
-- (`start using`) -- and driven headlessly in a real engine.
--
-- The MIDI poll dispatcher is the interesting part: it re-arms itself with
-- `send ... in N milliseconds` and fires scNoteOn / scMidiCC / ... back at the
-- caller. Inbound MIDI comes from the MOCK midixt library (no hardware), so
-- the whole loop -- timer, poll, drain, decode, dispatch -- runs for real.
--
-- The handlers after TestDispatcherWithLoopback pin the midixt fixes; each
-- failed against ShowControl's helper, as its comment says, bar the last,
-- which pins behaviour kept on purpose.
-- ---------------------------------------------------------------------------
-- requires: midixt-mock

local sEvents

on TestSetup
   global gMidiOtherEvents
   put empty into sEvents
   put empty into gMidiOtherEvents
   MockReset
end TestSetup

on TestTearDown
   scMidiStopListening
   if there is a stack "MidiOtherTarget" then
      delete stack "MidiOtherTarget"
   end if
end TestTearDown

-- the dispatcher's callbacks land here (this stack started the listening)
on scNoteOn pChannel, pNote, pVelocity
   put "noteOn" && pChannel && pNote && pVelocity & return after sEvents
   if pNote is 13 then
      throw "a handler that throws on note 13"
   end if
end scNoteOn

on scNoteOff pChannel, pNote, pVelocity
   put "noteOff" && pChannel && pNote && pVelocity & return after sEvents
end scNoteOff

on scMidiCC pChannel, pController, pValue
   put "cc" && pChannel && pController && pValue & return after sEvents
end scMidiCC

on scProgramChange pChannel, pProgram
   put "program" && pChannel && pProgram & return after sEvents
end scProgramChange

on scPitchBend pChannel, pValue14
   put "bend" && pChannel && pValue14 & return after sEvents
end scPitchBend

on scMidiOther pKind, pChannel, pEvent
   put "other" && pKind && pChannel && the number of bytes in pEvent["bytes"] & return after sEvents
end scMidiOther

-- How many dispatcher ticks are waiting to fire (one per live timer chain).
function midiTicksPending
   local tLine, tCount
   put 0 into tCount
   repeat for each line tLine in the pendingMessages
      if tLine contains "scMidiPollAndDispatch" then add 1 to tCount
   end repeat
   return tCount
end midiTicksPending

-- A second object to send events to, recording what it gets in a global.
on midiMakeOtherTarget
   global gMidiOtherEvents
   put empty into gMidiOtherEvents
   if there is a stack "MidiOtherTarget" then
      delete stack "MidiOtherTarget"
   end if
   create invisible stack "MidiOtherTarget"
   set the script of stack "MidiOtherTarget" to \
         "on scNoteOn pChannel, pNote, pVelocity" & return & \
         "   global gMidiOtherEvents" & return & \
         "   put " & quote & "noteOn" & quote & " && pChannel && pNote && pVelocity & return after gMidiOtherEvents" & return & \
         "end scNoteOn"
end midiMakeOtherTarget

-- Events that arrive AFTER listening started -- i.e. on the timer-driven
-- polls, not the first synchronous one -- reach this stack, in order.
on TestDispatcherDeliversTimerPolledEvents
   local tIn
   put midiOpenVirtualInput("helpers in") into tIn
   TestAssert "opened the mock input", tIn > 0
   scMidiStartListening tIn, 2
   TestPump 30                                  -- several poll ticks, nothing queued yet
   MockPush numToByte(144) & numToByte(60) & numToByte(100), 0
   MockPush numToByte(176) & numToByte(7) & numToByte(64), 0
   MockPush numToByte(194) & numToByte(5), 0
   MockPush numToByte(224) & numToByte(0) & numToByte(64), 0
   MockPush numToByte(128) & numToByte(60) & numToByte(0), 0
   MockPush numToByte(240) & numToByte(126) & numToByte(247), 0
   TestPump 200
   scMidiStopListening
   -- 0 here means the timer polls DID drain the queue, so any missing event was
   -- dispatched to the wrong object; 6 would mean the timer never polled.
   TestAssertEqual "the timer-driven polls drained the queue", MockQueueDepth(), 0
   TestAssertEqual "all six events dispatched to the listening stack", the number of lines of sEvents, 6
   TestAssertEqual "note on", line 1 of sEvents, "noteOn 1 60 100"
   TestAssertEqual "control change", line 2 of sEvents, "cc 1 7 64"
   TestAssertEqual "program change ch3", line 3 of sEvents, "program 3 5"
   TestAssertEqual "pitch bend centre", line 4 of sEvents, "bend 1 8192"
   TestAssertEqual "note off", line 5 of sEvents, "noteOff 1 60 0"
   TestAssertEqual "sysex handed off whole, raw bytes included", line 6 of sEvents, "other sysex 0 3"
   midiClose tIn
end TestDispatcherDeliversTimerPolledEvents

-- scMidiStopListening really stops: nothing dispatched after it.
on TestDispatcherStops
   local tIn
   put midiOpenVirtualInput("stop in") into tIn
   scMidiStartListening tIn, 2
   TestPump 20
   scMidiStopListening
   TestPump 20
   MockPush numToByte(144) & numToByte(1) & numToByte(1), 0
   TestPump 100
   TestAssertEqual "no dispatch after stop", the number of lines of sEvents, 0
   TestAssertEqual "the message is still queued for a later poll", MockQueueDepth(), 1
   midiClose tIn
end TestDispatcherStops

-- The loopback cable end to end through the helper: send with the convenience
-- senders, receive through the dispatcher.
on TestDispatcherWithLoopback
   local tIn, tOut
   MockSetLoopback true, 0
   put midiOpenVirtualInput("loop in") into tIn
   put midiOpenVirtualOutput("loop out") into tOut
   scMidiStartListening tIn, 2
   TestPump 10
   midiNoteOn tOut, 10, 36, 127
   midiControlChange tOut, 16, 1, 0
   TestPump 150
   scMidiStopListening
   TestAssertEqual "drum note on ch10", line 1 of sEvents, "noteOn 10 36 127"
   TestAssertEqual "mod wheel ch16", line 2 of sEvents, "cc 16 1 0"
   midiClose tIn
   midiClose tOut
end TestDispatcherWithLoopback

-- Each input sends to its own target. ShowControl kept ONE target for every
-- listener, so starting a second input redirected the first one's events.
-- (The mock has one queue for every input, so the polls are made by hand,
-- and long intervals keep the timers out of the way.)
on TestEachInputKeepsItsOwnTarget
   global gMidiOtherEvents
   local tA, tB
   midiMakeOtherTarget
   put midiOpenVirtualInput("input A") into tA
   put midiOpenVirtualInput("input B") into tB
   scMidiStartListening tA, 5000
   scMidiStartListening tB, 5000, the long id of stack "MidiOtherTarget"
   MockPush numToByte(144) & numToByte(61) & numToByte(1), 0
   scMidiPollAndDispatch tA
   TestAssertEqual "input A's note reached the stack that started A", line 1 of sEvents, "noteOn 1 61 1"
   TestAssertEqual "  and not B's target", gMidiOtherEvents, empty
   MockPush numToByte(144) & numToByte(62) & numToByte(2), 0
   scMidiPollAndDispatch tB
   TestAssertEqual "input B's note reached B's target", line 1 of gMidiOtherEvents, "noteOn 1 62 2"
   TestAssertEqual "  and not A's", the number of lines of sEvents, 1
   midiClose tA
   midiClose tB
end TestEachInputKeepsItsOwnTarget

-- Stopping and starting again replaces the timer. ShowControl's old timer
-- survived every restart inside one interval, so each left one more chain
-- polling for good.
on TestRestartingLeavesOneTimer
   local tIn, tCycle
   put midiOpenVirtualInput("restart in") into tIn
   scMidiStartListening tIn, 20
   repeat with tCycle = 1 to 5
      scMidiStopListening
      scMidiStartListening tIn, 20
   end repeat
   scMidiStartListening tIn, 20                -- and once more without a stop
   TestPump 100
   TestAssertEqual "one timer chain after six restarts", midiTicksPending(), 1
   MockPush numToByte(144) & numToByte(60) & numToByte(100), 0
   TestPump 100
   TestAssertEqual "and every event dispatched once", the number of lines of sEvents, 1
   scMidiStopListening
   TestPump 60
   TestAssertEqual "no timer after the stop", midiTicksPending(), 0
   midiClose tIn
end TestRestartingLeavesOneTimer

-- 0 is what an open that failed returns. ShowControl polled it every few
-- milliseconds for ever; now nothing starts, and the result says why.
on TestAFailedOpenStartsNothing
   local tResult
   scMidiStartListening 0
   put the result into tResult
   TestAssert "the result says why: " & tResult, tResult contains "no open MIDI input"
   TestAssertEqual "not listening", scMidiIsListening(0), false
   TestPump 30
   TestAssertEqual "and no timer", midiTicksPending(), 0
end TestAFailedOpenStartsNothing

-- A port closed while it is listened to stops its own timer. ShowControl's
-- polled the dead handle for ever.
on TestAClosedPortStopsItsTimer
   local tIn
   put midiOpenVirtualInput("closing in") into tIn
   scMidiStartListening tIn, 2
   TestPump 20
   TestAssertEqual "listening", scMidiIsListening(tIn), true
   midiClose tIn
   TestPump 60
   TestAssertEqual "the dispatcher noticed the port is gone", scMidiIsListening(tIn), false
   TestAssertEqual "and its timer stopped", midiTicksPending(), 0
end TestAClosedPortStopsItsTimer

-- scMidiStopListening with a handle stops that input alone (ShowControl's
-- took no handle and stopped everything); with none it still stops all.
on TestStopOneLeavesTheOther
   local tA, tB
   put midiOpenVirtualInput("keep") into tA
   put midiOpenVirtualInput("drop") into tB
   scMidiStartListening tA, 5
   scMidiStartListening tB, 5
   scMidiStopListening tB
   TestAssertEqual "the stopped input is not listened to", scMidiIsListening(tB), false
   TestAssertEqual "the other one still is", scMidiIsListening(tA), true
   MockPush numToByte(144) & numToByte(64) & numToByte(64), 0
   TestPump 80
   TestAssertEqual "and still dispatches", line 1 of sEvents, "noteOn 1 64 64"
   scMidiStopListening
   TestAssertEqual "no handle: everything stops", scMidiIsListening(tA), false
   midiClose tA
   midiClose tB
end TestStopOneLeavesTheOther

-- Called by hand (no timer generation), a poll dispatches what is waiting and
-- arms no timer of its own. ShowControl's armed one more chain each time.
on TestAPollByHandArmsNoTimer
   local tIn
   put midiOpenVirtualInput("by hand") into tIn
   scMidiStartListening tIn, 5000
   TestAssertEqual "one timer after the start", midiTicksPending(), 1
   MockPush numToByte(176) & numToByte(1) & numToByte(2), 0
   scMidiPollAndDispatch tIn
   scMidiPollAndDispatch tIn
   TestAssertEqual "the event went out", line 1 of sEvents, "cc 1 1 2"
   TestAssertEqual "still one timer", midiTicksPending(), 1
   scMidiStopListening
   midiClose tIn
end TestAPollByHandArmsNoTimer

-- A poll interval that is not a number is refused at the start, with a reason
-- (ShowControl failed at its first re-arm, after dispatching a batch).
on TestABadIntervalIsRefused
   local tIn, tError
   put midiOpenVirtualInput("bad interval") into tIn
   try
      scMidiStartListening tIn, "soon"
   catch tError
   end try
   TestAssert "refused with a reason: " & line 1 of tError, tError contains "must be a number of milliseconds"
   TestAssertEqual "and nothing listens", scMidiIsListening(tIn), false
   midiClose tIn
end TestABadIntervalIsRefused

-- Kept on purpose: a handler that throws stops listening on its input, as it
-- always has (the throw skips the next poll), and the error still reaches the
-- engine. What is new is that it says so: scMidiIsListening turns false, and
-- starting again picks up where it stopped.
on TestAThrowingHandlerStopsListening
   local tIn, tErrors
   put midiOpenVirtualInput("throwing in") into tIn
   scMidiStartListening tIn, 2
   TestPump 10
   MockPush numToByte(144) & numToByte(13) & numToByte(1), 0
   TestPump 60
   TestAssertEqual "the throwing handler ran", line 1 of sEvents, "noteOn 1 13 1"
   TestAssertEqual "listening stopped", scMidiIsListening(tIn), false
   TestAssertEqual "with no timer left", midiTicksPending(), 0
   put TestTakeErrorDialogs() into tErrors
   TestAssert "and the error reached the engine's errorDialog", \
         tErrors contains "a handler that throws on note 13"
   MockPush numToByte(144) & numToByte(14) & numToByte(1), 0
   TestPump 60
   TestAssertEqual "nothing more is dispatched", the number of lines of sEvents, 1
   scMidiStartListening tIn, 2
   TestPump 60
   TestAssertEqual "a new start delivers what waited", line 2 of sEvents, "noteOn 1 14 1"
   midiClose tIn
end TestAThrowingHandlerStopsListening
