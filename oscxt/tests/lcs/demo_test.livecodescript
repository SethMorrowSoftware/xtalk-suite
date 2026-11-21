script "OscDemoTest"
-- ---------------------------------------------------------------------------
-- The showcase stack, examples/osc-show-surface.livecodescript, opened the way
-- start-here's Open button opens it (a fresh stack, parked closed, given the
-- file's script, then a real `go invisible`), and run in the engine:
--
--   * it opens straight into motion: the loop runs, messages go out over UDP
--     and come back, and the rig reads them, within a second and a half;
--   * the window is 1100 x 620 (the suite's 1200 x 640 budget), every control
--     sits inside it, and every field and button carries its OWN text and
--     background colours, so a dark system theme cannot turn its words white
--     on white (OXT-Beyond's behaviour, reported 2026-11-21);
--   * it builds that window with messages locked, so no create, rename or
--     delete message reaches the IDE's script (the suite's engine notes,
--     5.15), and it opens centred on the screen: each failed in OXT-Beyond's
--     IDE on Windows, 2026-11-21;
--   * closing the window stops the show and closes its port, and so does a
--     close made with messages locked, which sends no closeStack: the loop
--     stops itself at its next frame (after each close in that IDE a frame was
--     still queued, 2026-11-21); and no socket of the show's is left listed,
--     the name the engine lists for each sender it heard included (the
--     suite's engine notes, 6.20: one was left after each close, there and
--     here);
--   * every scene plays with nothing going wrong, and each does what its
--     words say: the meters follow the faders, the spot follows the pad, each
--     address pattern lights exactly the lamps OSC 1.0 says it names (an
--     oracle written here, not read from the demo), a cue waits for its
--     timetag and then lands whole, and every bad datagram is refused;
--   * its NTP timetag text is exact (values worked out by Python, by hand);
--   * without oscxt's library it still opens, moves, sends nothing and says
--     what is missing.
-- The window itself, the look and the feel need an OXT pass; this is the
-- half a headless engine can settle.
-- ---------------------------------------------------------------------------
-- needs: sockets
-- requires: oscxt

local sDemo

-- What a scripted create, rename and delete send (the suite's engine notes,
-- 5.15). In the IDE each one runs the IDE's own script.
constant kDemoQuietMessages = "newButton,newField,newGraphic,newImage,newGroup,newScrollbar,newPlayer,newWidget,newBackground,deleteButton,deleteField,deleteGraphic,deleteImage,deleteGroup,deleteScrollbar,deletePlayer,deleteWidget,deleteBackground,nameChanged"

on TestTearDown
   demoStopListening
   if sDemo is not empty and there is a stack sDemo then
      close stack sDemo
      TestPump 50
   end if
end TestTearDown

function demoPath
   local tPath
   put $SC_HELPERS into tPath
   set the itemDelimiter to "/"
   put "osc-show-surface.livecodescript" into the last item of tPath
   set the itemDelimiter to ","
   return tPath
end demoPath

-- start-here's ritual (slPrepareStack and slOpenSelected): the `script`
-- line names the stack and is not script; the stack is parked CLOSED before
-- it has a script, so the `go` is a genuine open that fires preOpenStack
-- and openStack (the suite's engine notes, 5.5)
command demoPrepare
   local tScript, tName
   put url ("file:" & demoPath()) into tScript
   if tScript is empty then
      throw "cannot read " & demoPath()
   end if
   put line 1 of tScript into tName
   set the itemDelimiter to quote
   put item 2 of tName into tName
   set the itemDelimiter to ","
   delete line 1 of tScript
   if there is a stack tName then
      delete stack tName
   end if
   create invisible stack tName
   close stack tName
   set the script of stack tName to tScript
   if the revAvailableHandlers of stack tName is empty then
      throw "the demo's script does not compile"
   end if
   put tName into sDemo
end demoPrepare

command demoOpen
   demoPrepare
   go invisible stack sDemo
end demoOpen

function demoState
   dispatch function "osdState" to stack sDemo
   return the result
end demoState

-- Let the engine deliver what is in flight (datagrams, timers)
command demoSettle
   TestPump 40
end demoSettle

-- Step the show by hand, letting each frame's datagrams arrive
command demoStep pSeconds
   local tI, tFrames
   put max(1, round(pSeconds / 0.1)) into tFrames
   repeat with tI = 1 to tFrames
      dispatch "osdTestStep" to stack sDemo with 0.1
      TestPump 8
   end repeat
end demoStep

function lampsAbove pLevels, pAt
   local tI, tOut
   put empty into tOut
   repeat with tI = 1 to 12
      if item tI of pLevels > pAt then
         put tI & space after tOut
      end if
   end repeat
   return word 1 to -1 of tOut
end lampsAbove

on TestOpensStraightIntoMotion
   local tState, tI
   demoOpen
   TestAssert "the demo's stack is open", sDemo is among the lines of the openStacks
   TestPump 1500
   put demoState() into tState
   TestAssertEqual "nothing went wrong", tState["trouble"], empty
   TestAssertEqual "oscxt answered", tState["haveOsc"], true
   TestAssert "the rig listens on a port from 9000 to 9009 (" & tState["port"] & ")", tState["port"] >= 9000 and tState["port"] <= 9009
   TestAssertEqual "the loop is running", tState["running"], true
   TestAssertEqual "scene 1 plays first", tState["scene"], 1
   TestAssert "frames were drawn in a second and a half (" & tState["frames"] & ")", tState["frames"] >= 15
   TestAssert "messages went out (" & tState["sent"] & ")", tState["sent"] >= 60
   TestAssert "and came back over UDP (" & tState["arrived"] & ")", tState["arrived"] >= 60
   TestAssert "and oscParse read them (" & tState["read"] & ")", tState["read"] >= 60
   TestAssertEqual "none refused", tState["refused"], 0
   -- stop the clock and let the last frame's datagrams land: then every
   -- meter must show exactly what its fader sent
   dispatch "osdTestBegin" to stack sDemo
   TestPump 60
   put demoState() into tState
   TestAssertEqual "every datagram sent arrived", tState["arrived"], tState["sent"]
   repeat with tI = 1 to 6
      TestAssert "meter " & tI & " shows fader " & tI & " (" & item tI of tState["meters"] & " / " & item tI of tState["faders"] & ")", abs(item tI of tState["meters"] - item tI of tState["faders"]) < 0.0001
   end repeat
end TestOpensStraightIntoMotion

on TestTheWindowFitsAndKeepsItsColours
   local tI, tCount, tRect, tOutside, tNoColour, tType, tName
   demoOpen
   TestAssertEqual "the window is 1100 wide", the width of stack sDemo, 1100
   TestAssertEqual "and 620 high", the height of stack sDemo, 620
   TestAssert "which fits the suite's 1200 x 640", the width of stack sDemo <= 1200 and the height of stack sDemo <= 640
   TestAssertEqual "the header names OXT-Beyond", the text of field "osdBrand" of stack sDemo, "OXT-BEYOND"
   TestAssertEqual "and the demo", the text of field "osdTitle" of stack sDemo, "OSC Show Surface"
   TestAssertEqual "and who made it", the text of field "osdByline" of stack sDemo, "by Seth Morrow"
   TestAssert "and says what it does in one line", the number of lines of the text of field "osdSub" of stack sDemo is 1
   put the number of controls of card 1 of stack sDemo into tCount
   TestAssert "it built its controls (" & tCount & ")", tCount >= 100
   put empty into tOutside
   put empty into tNoColour
   repeat with tI = 1 to tCount
      put the rect of control tI of card 1 of stack sDemo into tRect
      put the short name of control tI of card 1 of stack sDemo into tName
      if item 1 of tRect < 0 or item 2 of tRect < 0 or item 3 of tRect > 1100 or item 4 of tRect > 620 then
         put tName & " " & tRect & return after tOutside
      end if
      put word 1 of the name of control tI of card 1 of stack sDemo into tType
      if tType is "field" or tType is "button" then
         if the foregroundColor of control tI of card 1 of stack sDemo is empty or the backgroundColor of control tI of card 1 of stack sDemo is empty then
            put tName & return after tNoColour
         end if
         if tType is "field" and the hiliteColor of control tI of card 1 of stack sDemo is empty then
            put tName & " (no hilite colour)" & return after tNoColour
         end if
      end if
      if tType is not "field" and tType is not "button" and tType is not "graphic" then
         put tName & " is a " & tType & ", which this demo never makes" & return after tNoColour
      end if
   end repeat
   TestAssertEqual "every control is inside the window", tOutside, empty
   TestAssertEqual "every field and button has its own colours", tNoColour, empty
   TestAssert "the stack's own text colour is set", the foregroundColor of stack sDemo is not empty
end TestTheWindowFitsAndKeepsItsColours

on TestEveryScenePlays
   local tScene, tState, tBefore
   demoOpen
   dispatch "osdTestBegin" to stack sDemo
   repeat with tScene = 1 to 5
      put demoState() into tBefore
      dispatch "osdGo" to stack sDemo with tScene
      demoStep 6
      demoSettle
      put demoState() into tState
      TestAssertEqual "scene " & tScene & " is the one playing", tState["scene"], tScene
      TestAssertEqual "scene " & tScene & " played with nothing going wrong", tState["trouble"], empty
      TestAssert "scene " & tScene & " sent messages (" & tState["sent"] - tBefore["sent"] & ")", tState["sent"] > tBefore["sent"]
      TestAssertEqual "scene " & tScene & ": everything sent arrived", tState["arrived"], tState["sent"]
   end repeat
end TestEveryScenePlays

on TestThePadMovesTheSpot
   local tState
   demoOpen
   dispatch "osdTestBegin" to stack sDemo
   dispatch "osdGo" to stack sDemo with 2
   demoStep 2
   demoSettle
   put demoState() into tState
   -- the spot's place is what the last /stage/spot carried: the pad's
   -- place when it was sent, read back through a 32-bit float
   dispatch function "osdPuck" to stack sDemo
   TestAssert "the spot is where the puck is (" & item 1 to 2 of tState["spot"] & " / " & the result & ")", abs(item 1 of tState["spot"] - item 1 of the result) < 0.0001 and abs(item 2 of tState["spot"] - item 2 of the result) < 0.0001
end TestThePadMovesTheSpot

on TestPatternsLightTheLampsTheyName
   local tWant, tK, tState, tStep, tLit, tGuard
   -- the oracle, from OSC 1.0's matching rules, written out by hand: one
   -- line per pattern, in the order the scene sends them
   put "/lamp/*|1 2 3 4 5 6 7 8 9 10 11 12" & return into tWant
   put "/lamp/?|1 2 3 4 5 6 7 8 9" & return after tWant
   put "/lamp/1?|10 11 12" & return after tWant
   put "/lamp/[1-4]|1 2 3 4" & return after tWant
   put "/lamp/[!1-4]|5 6 7 8 9" & return after tWant
   put "/lamp/{2,4,6,8,10,12}|2 4 6 8 10 12" & return after tWant
   put "/lamp/{1,3,5,7,9,11}|1 3 5 7 9 11" & return after tWant
   put "/lamp/*[05]|5 10" & return after tWant
   put "/lamp/[5-8]|5 6 7 8" & return after tWant
   put "/lamp/1[!0]|11 12" after tWant
   demoOpen
   dispatch "osdTestBegin" to stack sDemo
   dispatch "osdGo" to stack sDemo with 3
   put 0 into tStep
   repeat with tK = 1 to the number of lines of tWant
      -- step a frame at a time until the scene sends its next pattern
      put 0 into tGuard
      repeat until tStep >= tK or tGuard > 60
         dispatch "osdTestStep" to stack sDemo with 0.033
         put demoState() into tState
         put tState["step"] into tStep
         add 1 to tGuard
      end repeat
      demoSettle
      put demoState() into tState
      set the itemDelimiter to "|"
      TestAssert "the scene sent " & item 1 of line tK of tWant, tState["sends"] contains item 1 of line tK of tWant
      put lampsAbove(tState["lamps"], 0.5) into tLit
      TestAssertEqual item 1 of line tK of tWant & " lights lamps " & item 2 of line tK of tWant, tLit, item 2 of line tK of tWant
      set the itemDelimiter to ","
   end repeat
end TestPatternsLightTheLampsTheyName

on TestACueWaitsForItsTimetag
   local tState, tBefore
   demoOpen
   dispatch "osdTestBegin" to stack sDemo
   TestPump 60
   put demoState() into tBefore
   dispatch "osdGo" to stack sDemo with 4
   dispatch "osdTestStep" to stack sDemo with 0.033
   demoSettle
   put demoState() into tState
   TestAssertEqual "cue 1 went out as one bundle and is held", tState["pending"], 1
   TestAssert "its timetag went out as decimal text (" & line 3 of tState["sends"] & ")", word 2 of line 3 of tState["sends"] is an integer and the number of chars of word 2 of line 3 of tState["sends"] >= 19
   TestAssertEqual "nothing changed before it was due", tState["lamps"], tBefore["lamps"]
   TestPump 700
   dispatch "osdTestStep" to stack sDemo with 0.033
   put demoState() into tState
   TestAssertEqual "still held 0.7 s later", tState["pending"], 1
   TestAssertEqual "and still nothing changed", tState["lamps"], tBefore["lamps"]
   TestPump 700
   dispatch "osdTestStep" to stack sDemo with 0.033
   put demoState() into tState
   TestAssertEqual "1.4 s later it has come due", tState["pending"], 0
   TestAssertEqual "and every lamp took cue 1's level at once", roundList(tState["lamps"]), "0.2,0.3,0.5,0.7,0.9,1,1,0.9,0.7,0.5,0.3,0.2"
   TestAssertEqual "and every meter its fader level", roundList(tState["meters"]), "0.2,0.3,0.4,0.3,0.2,0.1"
   TestAssertEqual "and the spot its place, size and hue", roundList(tState["spot"]), "0.2,0.3,0.7,35"
end TestACueWaitsForItsTimetag

-- "0.200000002,0.3," -> "0.2,0.3": floats come back through 32 bits
function roundList pList
   local tOut, tItem
   put empty into tOut
   repeat for each item tItem in pList
      if tItem is empty then
         next repeat
      end if
      put (round(tItem * 1000) / 1000) & comma after tOut
   end repeat
   delete the last char of tOut
   return tOut
end roundList

on TestTimetagTextIsExact
   demoOpen
   -- (1795226601 + 2208988800) * 2^32 + 2^31, and with 2^30, worked out in
   -- Python's exact integers; and the last second before NTP's era rolls
   -- over in 2036 (seconds since 1900 = 2^32 - 1)
   dispatch function "osdTimetagAt" to stack sDemo with 1795226601.5
   TestAssertEqual "a half second", the result, "17197974195582009344"
   dispatch function "osdTimetagAt" to stack sDemo with 1795226601.25
   TestAssertEqual "a quarter second", the result, "17197974194508267520"
   dispatch function "osdTimetagAt" to stack sDemo with 2085978495.5
   TestAssertEqual "the end of NTP era 0", the result, "18446744071562067968"
   dispatch function "osdTimetagMs" to stack sDemo with "17197974195582009344"
   TestAssert "and it reads back to the millisecond (" & the result & ")", abs(the result - 1795226601500) < 1
   dispatch function "osdTimetagMs" to stack sDemo with "1"
   TestAssertEqual "1 means at once", the result, 0
end TestTimetagTextIsExact

on TestBadBytesAreRefusedAndTheShowGoesOn
   local tState
   demoOpen
   dispatch "osdTestBegin" to stack sDemo
   dispatch "osdGo" to stack sDemo with 5
   -- every one of the thirteen bad datagrams, and a few more
   demoStep 7
   demoSettle
   put demoState() into tState
   TestAssert "bad datagrams went out (" & tState["badSent"] & ")", tState["badSent"] >= 13
   TestAssertEqual "every one was refused", tState["refused"], tState["badSent"]
   TestAssertEqual "and every one arrived", tState["arrived"], tState["sent"]
   TestAssert "while the good ones were read (" & tState["read"] & ")", tState["read"] >= 60
   TestAssert "the wire says why (" & line 1 of tState["log"] & ")", tState["log"] contains "REFUSED"
   TestAssertEqual "and nothing went wrong", tState["trouble"], empty
end TestBadBytesAreRefusedAndTheShowGoesOn

-- A refusal is one line of the wire: the library's reason, and the size when
-- it fits (the wire's one line is 44 characters, kOsdWireChars)
on TestARefusalFitsTheWire
   local tLine
   demoOpen
   dispatch function "osdRefusedLine" to stack sDemo with "datagram too short", 3
   put the result into tLine
   TestAssertEqual "a short reason keeps the size", tLine, "REFUSED datagram too short (3 B)"
   dispatch function "osdRefusedLine" to stack sDemo with "truncated / malformed argument data", 8
   put the result into tLine
   TestAssertEqual "the longest reason drops it", tLine, "REFUSED truncated / malformed argument data"
   TestAssert "and fits the wire (" & the number of chars of tLine & " characters)", the number of chars of tLine <= 44
end TestARefusalFitsTheWire

on TestWithoutTheLibraryItSaysWhatIsMissing
   local tState, tFaders
   -- the library this process would load is not there: the first call of
   -- the binding throws, as it does in an OXT without oscxt's library
   set the revLibraryMapping["oscxt"] to "/nonexistent/oscxt-gone/oscxt.so"
   demoOpen
   TestPump 400
   put demoState() into tState
   put tState["faders"] into tFaders
   TestAssertEqual "oscxt is not there", tState["haveOsc"], false
   TestAssert "and it says why, in words (" & tState["whyNot"] & ")", tState["whyNot"] begins with "oscxt is loaded, but its native library did not load: unable to load foreign library"
   TestAssertEqual "the show still runs", tState["running"], true
   TestAssertEqual "with nothing going wrong", tState["trouble"], empty
   TestAssertEqual "and nothing sent", tState["sent"], 0
   TestAssert "the rig says what is missing", the visible of field "osdMissing" of stack sDemo and the text of field "osdMissing" of stack sDemo contains "oscxt"
   TestAssert "and so does the footer (" & the text of field "osdStatus" of stack sDemo & ")", the text of field "osdStatus" of stack sDemo begins with "Missing: oscxt"
   TestPump 400
   put demoState() into tState
   TestAssert "the surface still moves", tState["faders"] is not tFaders
end TestWithoutTheLibraryItSaysWhatIsMissing

-- ===== Opened quietly, and on the screen ===================================
-- On OXT-Beyond 0.2.8-dp.1 on Windows (2026-11-21) all three ShowControl
-- showcases opened with their left 390 pixels past the screen's edge, and
-- held the IDE for 42 to 112 seconds as they opened: built with messages
-- unlocked, every create, rename and delete ran the IDE's own script (the
-- suite's engine notes, 5.15). The window now centres itself and is built
-- with messages locked.

-- A front script that hears every such message the engine sends, from any
-- object, and notes it with the name of its target
command demoListen
   local tScript, tMsg
   global gDemoHeard
   put "global gDemoHeard" & return into tScript
   repeat for each item tMsg in kDemoQuietMessages
      put "on " & tMsg & return & "put " & quote & tMsg & space & quote & " & the short name of the target & return after gDemoHeard" & return & "pass " & tMsg & return & "end " & tMsg & return after tScript
   end repeat
   if there is not a stack "DemoQuietEar" then
      create invisible stack "DemoQuietEar"
      set the script of stack "DemoQuietEar" to tScript
      insert the script of stack "DemoQuietEar" into front
   end if
   put empty into gDemoHeard
end demoListen

command demoStopListening
   if there is a stack "DemoQuietEar" then
      remove the script of stack "DemoQuietEar" from front
      delete stack "DemoQuietEar"
   end if
end demoStopListening

function demoHeard
   global gDemoHeard
   return gDemoHeard
end demoHeard

-- A field made and deleted with messages on, in a stack of its own: what
-- the ear must hear, or its silence proves nothing. The engine sends
-- newField before the field has its name, so the ear hears it as
-- "field id N"; nameChanged then gives the name.
command demoEarProbe
   local tOld
   put the defaultStack into tOld
   if there is not a stack "DemoEarProbe" then
      create invisible stack "DemoEarProbe"
   end if
   set the defaultStack to "DemoEarProbe"
   create field "demoProbeField"
   delete field "demoProbeField"
   if tOld is not empty and there is a stack tOld then
      set the defaultStack to tOld
   end if
end demoEarProbe

on TestTheWindowIsBuiltQuietly
   local tHeard
   demoPrepare
   demoListen
   demoEarProbe
   put demoHeard() into tHeard
   replace return with "; " in tHeard
   TestAssert "the ear hears a create (" & tHeard & ")", tHeard contains "newField field id"
   TestAssert "the name it gives", tHeard contains "nameChanged demoProbeField"
   TestAssert "and a delete", tHeard contains "deleteField demoProbeField"
   -- the demo, opened as start-here opens it
   demoListen
   go invisible stack sDemo
   put demoHeard() into tHeard
   TestAssert "the window was built", there is a graphic "osdStage" of stack sDemo
   TestAssertEqual "sending no create, rename or delete message (the first: " & line 1 of tHeard & ")", the number of lines of tHeard, 0
   -- the show plays, and makes, renames and deletes nothing as it plays
   TestPump 1500
   put demoHeard() into tHeard
   TestAssertEqual "nor as it plays (the first: " & line 1 of tHeard & ")", the number of lines of tHeard, 0
   -- a reopen deletes the window it built and builds it again
   close stack sDemo
   TestPump 50
   demoListen
   go invisible stack sDemo
   put demoHeard() into tHeard
   TestAssert "a reopen built the window again", there is a graphic "osdStage" of stack sDemo
   TestAssertEqual "quietly too (the first: " & line 1 of tHeard & ")", the number of lines of tHeard, 0
end TestTheWindowIsBuiltQuietly

-- A headless engine has no screen (its screenLoc is 0,0), so this settles
-- that the build centres the window by the screen the engine reports, not
-- where that lands on a real one (an OXT pass)
on TestTheWindowOpensCentredOnTheScreen
   demoPrepare
   -- where the three showcases opened on Windows
   set the rect of stack sDemo to "-390,-3,710,617"
   go invisible stack sDemo
   TestAssertEqual "the window opens centred on the screen", the loc of stack sDemo, the screenLoc
   TestAssertEqual "at its own size", the width of stack sDemo & "x" & the height of stack sDemo, "1100x620"
end TestTheWindowOpensCentredOnTheScreen

-- Closing the window stops the show. closeStack stops it, and a close made
-- with messages locked, which sends no closeStack, stops it at the loop's
-- next frame: the IDE keeps a closed stack in memory, where a loop that ran
-- on would run unseen with its port open (after each close in OXT-Beyond
-- 0.2.8-dp.1's IDE on Windows a frame was still queued, 2026-11-21). And
-- none of its sockets is left listed: the engine lists one more for each
-- sender a datagram listener hears and keeps it after the listener closes
-- (the suite's engine notes, 6.20), so the show closes those names too
on TestAClosedWindowStopsItsShow
   local tState, tPort, tBefore
   put demoSocketList() into tBefore
   demoOpen
   TestPump 300
   TestAssert "the loop runs while the window is open", demoFramesQueued() > 0
   TestAssert "with sockets open (" & demoSocketList() & ")", demoSocketList() is not tBefore
   close stack sDemo
   TestPump 200
   TestAssertEqual "a close stops it", demoFramesQueued(), 0
   put demoState() into tState
   TestAssertEqual "and the show says so", tState["running"], false
   TestAssertEqual "and leaves none of its sockets open", demoSocketList(), tBefore
   go invisible stack sDemo
   TestPump 300
   TestAssert "a reopen starts it again", demoFramesQueued() > 0
   put demoState() into tState
   put tState["port"] into tPort
   TestAssert "listening on a port again (" & tPort & ")", tPort is among the lines of the openSockets
   lock messages
   close stack sDemo
   unlock messages
   TestPump 200
   TestAssertEqual "a close with messages locked stops it too", demoFramesQueued(), 0
   put demoState() into tState
   TestAssertEqual "the show stopped itself", tState["running"], false
   TestAssert "and closed its port (" & tPort & ")", tPort is not among the lines of the openSockets
   TestAssertEqual "and every other socket it had", demoSocketList(), tBefore
end TestAClosedWindowStopsItsShow

-- The openSockets on one line, for a label or a comparison
function demoSocketList
   local tList
   put the openSockets into tList
   replace return with comma in tList
   return tList
end demoSocketList

-- The frame messages queued for the demo's loop
function demoFramesQueued
   local tLine, tN
   put 0 into tN
   repeat for each line tLine in the pendingMessages
      if item 3 of tLine begins with "osdFrame" then
         add 1 to tN
      end if
   end repeat
   return tN
end demoFramesQueued
