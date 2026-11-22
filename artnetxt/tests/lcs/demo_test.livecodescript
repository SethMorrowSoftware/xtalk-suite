script "ArtnetDemoTest"
-- ---------------------------------------------------------------------------
-- The showcase stack, examples/artnet-light-board.livecodescript, opened the
-- way start-here's Open button opens it (a fresh stack, parked closed, given
-- the file's script, then a real `go invisible`), and run in the engine:
--
--   * it opens straight into motion: the loop runs, ArtDmx packets go out
--     over UDP and come back, and the rig reads them, within a second and a
--     half; then every one of the 512 levels the rig holds is the level the
--     board sent;
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
--     suite's engine notes, 6.21: one was left after each close, there and
--     here);
--   * every scene plays with nothing going wrong, and each does what its
--     words say: the rig's lamps are drawn from the levels that ARRIVED, the
--     chase lights the PAR it is at, the heads aim where pan and tilt say,
--     all 512 channels cross in scene 4, and in scene 5 the board finds the
--     rig through ArtPoll and ArtPollReply while the rig ignores bytes that
--     are not for it, each with its reason;
--   * the rig's ArtPollReply is right byte by byte (an oracle written here
--     from the Art-Net 4 field table, not read from the demo), and
--     artnetParseReply reads it back;
--   * the packet it shows is the packet it sent, mixed byte order and all;
--   * paused, a desk elsewhere drives the rig on universe 0, and not on 1;
--   * kAlbAlsoTo sends to one more node only when it names one, and never a
--     broadcast;
--   * without artnetxt it still opens, moves, sends nothing and says what is
--     missing.
-- The window itself, the look and the feel need an OXT pass; this is the
-- half a headless engine can settle.
-- ---------------------------------------------------------------------------
-- needs: sockets

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
   put "artnet-light-board.livecodescript" into the last item of tPath
   set the itemDelimiter to ","
   return tPath
end demoPath

-- start-here's ritual (slPrepareStack and slOpenSelected): the `script`
-- line names the stack and is not script; the stack is parked CLOSED before
-- it has a script, so the `go` is a genuine open that fires preOpenStack
-- and openStack (the suite's engine notes, 5.5). pEdit, when given, is
-- "old|new": one line of the script changed first (kAlbAlsoTo's tests).
command demoPrepare pEdit
   local tScript, tName
   put url ("file:" & demoPath()) into tScript
   if tScript is empty then
      throw "cannot read " & demoPath()
   end if
   if pEdit is not empty then
      set the itemDelimiter to "|"
      if not (tScript contains item 1 of pEdit) then
         throw "the demo has no line " & item 1 of pEdit
      end if
      replace item 1 of pEdit with item 2 of pEdit in tScript
      set the itemDelimiter to ","
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

command demoOpen pEdit
   demoPrepare pEdit
   go invisible stack sDemo
end demoOpen

function demoState
   dispatch function "albState" to stack sDemo
   return the result
end demoState

-- Let the engine deliver what is in flight (datagrams, timers)
command demoSettle
   TestPump 60
end demoSettle

-- Step the show by hand, letting each frame's datagrams arrive
command demoStep pSeconds
   local tI, tFrames
   put max(1, round(pSeconds / 0.1)) into tFrames
   repeat with tI = 1 to tFrames
      dispatch "albTestStep" to stack sDemo with 0.1
      TestPump 8
   end repeat
end demoStep

-- A level list item, 0 when the list is shorter
function levelOf pList, pChannel
   if item pChannel of pList is empty then
      return 0
   end if
   return item pChannel of pList
end levelOf

-- "r,g,b" between two colours, pT from 0 to 1, as the rig mixes a lamp
-- (written out here again, so the test does not trust the demo's own)
function mixOf pA, pB, pT
   local tI, tOut
   put max(0, min(1, pT)) into pT
   repeat with tI = 1 to 3
      put round(item tI of pA + (item tI of pB - item tI of pA) * pT) & comma after tOut
   end repeat
   delete the last char of tOut
   return tOut
end mixOf

on TestOpensStraightIntoMotion
   local tState, tWant, tGot
   demoOpen
   TestAssert "the demo's stack is open", sDemo is among the lines of the openStacks
   TestPump 1500
   put demoState() into tState
   TestAssertEqual "nothing went wrong", tState["trouble"], empty
   TestAssertEqual "artnetxt answered", tState["haveArt"], true
   TestAssert "the rig listens on a port from 6454 to 6464 (" & tState["port"] & ")", tState["port"] >= 6454 and tState["port"] <= 6464
   TestAssertEqual "the loop is running", tState["running"], true
   TestAssertEqual "scene 1 plays first", tState["scene"], 1
   TestAssert "frames were drawn in a second and a half (" & tState["frames"] & ")", tState["frames"] >= 15
   TestAssert "packets went out (" & tState["sent"] & ")", tState["sent"] >= 15
   TestAssert "and came back over UDP (" & tState["arrived"] & ")", tState["arrived"] >= 15
   TestAssert "and artnetParseDmx read them (" & tState["read"] & ")", tState["read"] >= 15
   TestAssertEqual "none ignored", tState["ignored"], 0
   TestAssertEqual "and only to this computer", tState["alsoSent"], 0
   -- stop the clock and let the last frame land: then the rig must hold
   -- exactly the 512 levels the board sent
   dispatch "albTestBegin" to stack sDemo
   demoSettle
   put demoState() into tState
   TestAssertEqual "every packet sent arrived", tState["arrived"], tState["sent"]
   TestAssertEqual "and was read", tState["read"], tState["sent"]
   put tState["sentLevels"] into tWant
   put tState["readLevels"] into tGot
   TestAssertEqual "the board sends all 512 channels", the number of items of tWant, 512
   TestAssertEqual "the rig holds all 512 levels the board sent", tGot, tWant
   TestAssert "and the PARs are lit (" & item 1 to 8 of tGot & ")", item 1 of tGot > 100
end TestOpensStraightIntoMotion

on TestTheWindowFitsAndKeepsItsColours
   local tI, tCount, tRect, tOutside, tNoColour, tType, tName
   demoOpen
   TestAssertEqual "the window is 1100 wide", the width of stack sDemo, 1100
   TestAssertEqual "and 620 high", the height of stack sDemo, 620
   TestAssert "which fits the suite's 1200 x 640", the width of stack sDemo <= 1200 and the height of stack sDemo <= 640
   TestAssertEqual "the header names OXT-Beyond", the text of field "albBrand" of stack sDemo, "OXT-BEYOND"
   TestAssertEqual "and the demo", the text of field "albTitle" of stack sDemo, "Art-Net Light Board"
   TestAssertEqual "and who made it", the text of field "albByline" of stack sDemo, "by Seth Morrow"
   TestAssert "and says what it does in one line", the number of lines of the text of field "albSub" of stack sDemo is 1
   put the number of controls of card 1 of stack sDemo into tCount
   TestAssert "it built its controls, a square for each of 512 channels among them (" & tCount & ")", tCount >= 600 and there is a graphic "albCell512" of stack sDemo
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
   dispatch "albTestBegin" to stack sDemo
   repeat with tScene = 1 to 5
      put demoState() into tBefore
      dispatch "albGo" to stack sDemo with tScene
      demoStep 4
      demoSettle
      put demoState() into tState
      TestAssertEqual "scene " & tScene & " is the one playing", tState["scene"], tScene
      TestAssertEqual "scene " & tScene & " played with nothing going wrong", tState["trouble"], empty
      TestAssert "scene " & tScene & " sent packets (" & tState["sent"] - tBefore["sent"] & ")", tState["sent"] > tBefore["sent"]
      TestAssertEqual "scene " & tScene & ": everything sent arrived", tState["arrived"], tState["sent"]
      TestAssertEqual "scene " & tScene & ": everything that arrived was read or ignored", tState["read"] + tState["ignored"], tState["arrived"]
      TestAssertEqual "scene " & tScene & ": the rig holds what the board sent last", tState["readLevels"], tState["sentLevels"]
   end repeat
end TestEveryScenePlays

on TestTheRigIsDrawnFromWhatArrived
   local tState, tGot, tK, tBase, tRgb, tWant, tBad, tPeak, tBest, tShade
   demoOpen
   dispatch "albTestBegin" to stack sDemo
   dispatch "albGo" to stack sDemo with 2
   -- 48 frames: the pulse is at PAR 8, the end of its run
   demoStep 1.6
   demoSettle
   -- draw once more now that the last packet is in: the picture is of it
   dispatch "albRender" to stack sDemo
   put demoState() into tState
   put tState["readLevels"] into tGot
   put empty into tBad
   repeat with tK = 1 to 8
      put (tK - 1) * 4 into tBase
      put item tBase + 2 to tBase + 4 of tGot into tRgb
      put mixOf("44,49,66", tRgb, levelOf(tGot, tBase + 1) / 255) into tWant
      if the backgroundColor of graphic ("albCore" & tK) of stack sDemo is not tWant then
         put "PAR " & tK & ": " & the backgroundColor of graphic ("albCore" & tK) of stack sDemo & " not " & tWant & return after tBad
      end if
   end repeat
   TestAssertEqual "each PAR's lamp is its colour at its dimmer, from the levels read", tBad, empty
   -- the chase: the brightest PAR is the one the pulse is at
   put 0 into tPeak
   repeat with tK = 1 to 8
      if levelOf(tGot, (tK - 1) * 4 + 1) > tPeak then
         put levelOf(tGot, (tK - 1) * 4 + 1) into tPeak
         put tK into tBest
      end if
   end repeat
   TestAssertEqual "the pulse is at PAR 8 (" & item 1 to 32 of tGot & ")", tBest, 8
   TestAssert "which is at full (" & tPeak & ")", tPeak >= 250
   TestAssert "and the others fall away from it", levelOf(tGot, 25) < levelOf(tGot, 29) and levelOf(tGot, 21) < levelOf(tGot, 25) and levelOf(tGot, 13) < 40
   -- the grid: a square a channel, its shade the level read
   put empty into tBad
   repeat with tK = 1 to 44
      put round(levelOf(tGot, tK) * 11 / 255) into tShade
      if item tK of tState["shades"] is not tShade then
         put "channel " & tK & ": shade " & item tK of tState["shades"] & " not " & tShade & return after tBad
      end if
   end repeat
   TestAssertEqual "each channel's square has the shade of its level", tBad, empty
   put item 1 of tState["shades"] + 1 into tShade
   set the itemDelimiter to ";"
   put item tShade of tState["shadeColours"] into tRgb
   set the itemDelimiter to ","
   TestAssertEqual "channel 1's square is drawn in that shade", the backgroundColor of graphic "albCell1" of stack sDemo, tRgb
end TestTheRigIsDrawnFromWhatArrived

on TestTheHeadsAimWherePanAndTiltSay
   local tState, tGot, tPan, tTilt, tRect, tX, tY
   demoOpen
   dispatch "albTestBegin" to stack sDemo
   dispatch "albGo" to stack sDemo with 3
   demoStep 2.2
   demoSettle
   dispatch "albRender" to stack sDemo
   put demoState() into tState
   put tState["readLevels"] into tGot
   -- head 1: pan is channel 33, tilt 34; its pool on the floor is where
   -- they point (the floor runs from 30 to 520 across, 178 to 350 deep)
   put levelOf(tGot, 33) / 255 into tPan
   put levelOf(tGot, 34) / 255 into tTilt
   put the rect of graphic "albPool1" of stack sDemo into tRect
   put (item 1 of tRect + item 3 of tRect) / 2 into tX
   put (item 2 of tRect + item 4 of tRect) / 2 into tY
   TestAssert "head 1's pool is across the floor by its pan (" & tX & " for " & tPan & ")", abs(tX - (70 + tPan * 410)) <= 1
   TestAssert "and deep by its tilt (" & tY & " for " & tTilt & ")", abs(tY - (200 + tTilt * 128)) <= 1
   TestAssert "the head is lit (" & levelOf(tGot, 35) & ")", levelOf(tGot, 35) is 255
   -- the two heads move: a second later neither is where it was
   demoStep 1
   demoSettle
   put demoState() into tState
   TestAssert "head 1 moved", item 33 to 34 of tState["readLevels"] is not item 33 to 34 of tGot
   TestAssert "and head 2 moved", item 39 to 40 of tState["readLevels"] is not item 39 to 40 of tGot
end TestTheHeadsAimWherePanAndTiltSay

on TestTheWholeUniverseCrosses
   local tState, tGot, tSeen, tLevel, tN, tMs
   demoOpen
   dispatch "albTestBegin" to stack sDemo
   dispatch "albGo" to stack sDemo with 4
   demoStep 1.5
   demoSettle
   -- how long one frame of the busiest scene takes here: the board sets
   -- 512 channels, sends, and the picture redraws (the rig's reading lands
   -- in the pump); a diagnostic, not a promise, since machines differ
   put the milliseconds into tMs
   dispatch "albTestStep" to stack sDemo with 0.99
   put the milliseconds - tMs into tMs
   TestDiagnostic "scene 4: 30 frames in " & tMs & " ms (" & round(tMs / 30, 1) & " ms a frame, board and picture)"
   put the milliseconds into tMs
   demoSettle
   TestDiagnostic "the rig read 30 frames of 512 channels in at most " & the milliseconds - tMs & " ms"
   dispatch "albRender" to stack sDemo
   put demoState() into tState
   put tState["readLevels"] into tGot
   TestAssertEqual "all 512 levels the board sent are the rig's", tGot, tState["sentLevels"]
   put 0 into tN
   repeat for each item tLevel in tGot
      if tSeen[tLevel] is empty then
         put true into tSeen[tLevel]
         add 1 to tN
      end if
   end repeat
   TestAssert "and they are not a few repeated values (" & tN & " different levels)", tN >= 100
   TestAssert "the last channel crossed too (" & item 512 of tGot & ")", item 512 of tGot is item 512 of tState["sentLevels"] and item 512 of tGot is not empty
   TestAssertEqual "the last square is drawn too", item 512 of tState["shades"], round(item 512 of tGot * 11 / 255)
end TestTheWholeUniverseCrosses

on TestTheBoardFindsTheRig
   local tState, tGuard
   demoOpen
   dispatch "albTestBegin" to stack sDemo
   dispatch "albGo" to stack sDemo with 5
   dispatch "albTestStep" to stack sDemo with 0.033
   put 0 into tGuard
   repeat until tGuard > 20
      TestPump 20
      put demoState() into tState
      if tState["found"] is not empty then
         exit repeat
      end if
      add 1 to tGuard
   end repeat
   TestAssertEqual "the rig answered one ArtPoll", tState["polls"], 1
   TestAssertEqual "and the board found it", tState["found"], "127.0.0.1:" & tState["port"]
   TestAssert "the board says who it found (" & line 1 of tState["foundCard"] & ")", line 1 of tState["foundCard"] is "FOUND  OXT Rig at 127.0.0.1:" & tState["port"]
   TestAssertEqual "with its universe and MAC", line 2 of tState["foundCard"], "universe 0 out, MAC 02:4f:58:54:00:01"
   TestAssert "the board shows the ArtPoll it sent (" & line 1 of tState["packetView"] & ")", line 1 of tState["packetView"] contains "ArtPoll" and line 1 of tState["packetView"] contains "14 bytes"
   TestAssertEqual "its OpCode low byte first", word 1 to 2 of line 3 of tState["packetView"], "00 20"
   TestAssert "the wire says so", tState["log"] contains "ArtPoll from 127.0.0.1: answered" and tState["log"] contains "ArtPollReply: OXT Rig"
end TestTheBoardFindsTheRig

-- The rig's ArtPollReply, against the Art-Net 4 field table written out
-- here (the same offsets as tools/sim/refcodec.py's), byte by byte
on TestTheRigsReplyIsRightByteByByte
   local tReply, tPort, tNode, tWant, tI, tName
   demoOpen
   dispatch "albTestBegin" to stack sDemo
   put demoState() into tNode
   put tNode["port"] into tPort
   dispatch function "albPollReply" to stack sDemo
   put the result into tReply
   TestAssertEqual "it is 239 bytes, as Art-Net 4 says", the number of bytes in tReply, 239
   TestAssertEqual "Art-Net and a NUL", byte 1 to 8 of tReply, "Art-Net" & numToByte(0)
   TestAssertEqual "OpCode 0x2100, low byte first", byteToNum(byte 9 of tReply) & "," & byteToNum(byte 10 of tReply), "0,33"
   TestAssertEqual "IP 127.0.0.1", byteToNum(byte 11 of tReply) & "." & byteToNum(byte 12 of tReply) & "." & byteToNum(byte 13 of tReply) & "." & byteToNum(byte 14 of tReply), "127.0.0.1"
   TestAssertEqual "its port, low byte first", byteToNum(byte 15 of tReply) + 256 * byteToNum(byte 16 of tReply), tPort
   put byte 27 to 44 of tReply into tName
   TestAssertEqual "ShortName at 27, NUL-padded to 18", tName, "OXT Rig" & numToByte(0) & numToByte(0) & numToByte(0) & numToByte(0) & numToByte(0) & numToByte(0) & numToByte(0) & numToByte(0) & numToByte(0) & numToByte(0) & numToByte(0)
   TestAssertEqual "LongName at 45", byte 45 to 88 of tReply, "OXT-Beyond virtual rig (Art-Net Light Board)"
   TestAssert "NodeReport at 109 (" & byte 109 to 120 of tReply & ")", byte 109 to 114 of tReply is "#0001 "
   TestAssertEqual "NumPorts 1, high byte first", byteToNum(byte 173 of tReply) & "," & byteToNum(byte 174 of tReply), "0,1"
   TestAssertEqual "port 1 outputs DMX (PortTypes bit 7)", byteToNum(byte 175 of tReply), 128
   TestAssertEqual "on universe 0 (SwOut)", byteToNum(byte 191 of tReply), 0
   TestAssertEqual "it is a node (Style 0)", byteToNum(byte 201 of tReply), 0
   put empty into tWant
   repeat with tI = 202 to 207
      put byteToNum(byte tI of tReply) & "," after tWant
   end repeat
   TestAssertEqual "its MAC, high byte first", tWant, "2,79,88,84,0,1,"
   TestAssertEqual "BindIndex 1", byteToNum(byte 212 of tReply), 1
   -- and the extension reads it back
   put artnetParseReply(tReply) into tNode
   TestAssertEqual "artnetParseReply reads an ArtPollReply", tNode["opcode"], "ArtPollReply"
   TestAssertEqual "its short name", tNode["shortName"], "OXT Rig"
   TestAssertEqual "its long name", tNode["longName"], "OXT-Beyond virtual rig (Art-Net Light Board)"
   TestAssertEqual "its address", tNode["ip"], "127.0.0.1"
   TestAssertEqual "its port", tNode["port"], tPort
   TestAssertEqual "its output universe", tNode["outputUniverses"][1], 0
   TestAssertEqual "one output only", the number of elements of tNode["outputUniverses"], 1
   TestAssertEqual "its MAC", tNode["mac"], "02:4f:58:54:00:01"
   TestAssertEqual "its BindIndex", tNode["bindIndex"], 1
end TestTheRigsReplyIsRightByteByByte

on TestBytesNotForTheRigAreIgnored
   local tState
   demoOpen
   dispatch "albTestBegin" to stack sDemo
   dispatch "albGo" to stack sDemo with 5
   -- the scene's strangers come at 2.1 s (not Art-Net), 5.1 s (an ArtDmx
   -- cut short) and 8.1 s (universe 1); the wire keeps six lines, so look
   -- after each
   demoStep 2.4
   demoSettle
   put demoState() into tState
   TestAssert "nine bytes that are not Art-Net were ignored (" & tState["log"] & ")", tState["log"] contains "node   9 B, not Art-Net: ignored"
   TestAssertEqual "one ignored so far", tState["ignored"], 1
   demoStep 3
   demoSettle
   put demoState() into tState
   TestAssert "a packet cut short was read as far as it went, and no further (" & tState["log"] & ")", tState["log"] contains "node   ArtDmx cut short: 6 of 512 read"
   demoStep 3
   demoSettle
   put demoState() into tState
   TestAssert "a packet for universe 1 was not taken (" & tState["log"] & ")", tState["log"] contains "node   ArtDmx for universe 1: not mine"
   TestAssertEqual "two packets were ignored", tState["ignored"], 2
   TestAssertEqual "everything that arrived was read or ignored", tState["read"] + tState["ignored"], tState["arrived"]
   TestAssertEqual "and nothing went wrong", tState["trouble"], empty
   TestAssertEqual "the rig still holds what the board sent", tState["readLevels"], tState["sentLevels"]
end TestBytesNotForTheRigAreIgnored

on TestThePacketShownIsThePacketSent
   local tState, tView, tI, tHex
   demoOpen
   dispatch "albTestBegin" to stack sDemo
   dispatch "albGo" to stack sDemo with 1
   demoStep 0.5
   demoSettle
   dispatch "albRender" to stack sDemo
   put demoState() into tState
   put tState["packetView"] into tView
   TestAssertEqual "it shows an ArtDmx of 530 bytes", line 1 of tView, "ArtDmx to 127.0.0.1:" & tState["port"] & ", 530 bytes"
   TestAssertEqual "the ID", line 2 of tView, "41 72 74 2D 4E 65 74 00  Art-Net + NUL"
   TestAssertEqual "the OpCode, low byte first", line 3 of tView, "00 50  OpCode 0x5000, low byte first"
   TestAssertEqual "the version, high byte first", line 4 of tView, "00 0E  ProtVer 14, high byte first"
   TestAssertEqual "the universe, SubUni then Net", line 6 of tView, "00 00  SubUni, Net: universe 0"
   TestAssertEqual "the Length, high byte first", line 7 of tView, "02 00  Length 512, high byte first"
   -- the levels on the last line are the first six the board sent
   put empty into tHex
   repeat with tI = 1 to 6
      put format("%02X", item tI of tState["sentLevels"]) & space after tHex
   end repeat
   TestAssertEqual "and its first six levels", word 1 to 6 of line 8 of tView, word 1 to -1 of tHex
   TestAssertEqual "the side shows the levels read", word 2 of line 1 of the text of field "albWire" of stack sDemo, item 1 of tState["readLevels"]
end TestThePacketShownIsThePacketSent

-- Paused, the board sends nothing, and a desk elsewhere (this test, from its
-- own socket) drives the rig on universe 0; a packet for universe 1 changes
-- nothing
on TestPausedADeskDrivesTheRig
   local tState, tDest, tLevels, tSent
   demoOpen
   TestPump 300
   send "mouseUp" to button "albPause" of stack sDemo
   TestPump 200
   put demoState() into tState
   put tState["sent"] into tSent
   TestAssertEqual "the board is paused", tState["paused"], true
   put "127.0.0.1:" & tState["port"] into tDest
   open datagram socket to tDest
   put empty into tLevels
   scArtnetSetChannel tLevels, 9, 255
   scArtnetSetChannel tLevels, 10, 255
   scArtnetSetChannel tLevels, 11, 0
   scArtnetSetChannel tLevels, 12, 0
   write artnetBuildDmx(0, tLevels) to socket tDest
   TestPump 200
   put demoState() into tState
   TestAssertEqual "the board sent nothing more", tState["sent"], tSent
   TestAssertEqual "PAR 3 took the desk's red at full", item 9 to 12 of tState["readLevels"], "255,255,0,0"
   TestAssertEqual "and the rest went to 0, as the desk sent", item 1 to 4 of tState["readLevels"], "0,0,0,0"
   TestAssertEqual "PAR 3's lamp is red", the backgroundColor of graphic "albCore3" of stack sDemo, "255,0,0"
   put empty into tLevels
   scArtnetSetChannel tLevels, 9, 10
   write artnetBuildDmx(1, tLevels) to socket tDest
   TestPump 200
   put demoState() into tState
   TestAssertEqual "a packet for universe 1 changed nothing", item 9 to 12 of tState["readLevels"], "255,255,0,0"
   TestAssert "and the wire says why", tState["log"] contains "ArtDmx for universe 1: not mine"
   close socket tDest
end TestPausedADeskDrivesTheRig

-- kAlbAlsoTo: empty, nothing leaves this computer; a node's address, every
-- frame goes there too; a broadcast, nothing does, and the footer says why
on TestAlsoToSendsOnlyWhenItNamesANode
   global gAlsoGot, gAlsoFrom
   local tPort, tState, tFrom
   put $SC_PORT_BASE + 7 into tPort
   accept datagram connections on port tPort with message "alsoReceived"
   if the result is not empty then
      TestSkip "kAlbAlsoTo", "port " & tPort & " would not open: " & the result
      exit TestAlsoToSendsOnlyWhenItNamesANode
   end if
   put 0 into gAlsoGot
   put empty into gAlsoFrom
   demoOpen "constant kAlbAlsoTo = " & quote & quote & "|constant kAlbAlsoTo = " & quote & "127.0.0.1:" & tPort & quote
   TestPump 800
   put demoState() into tState
   TestAssertEqual "it took the address", tState["also"], "127.0.0.1:" & tPort
   TestAssert "frames went there too (" & tState["alsoSent"] & ")", tState["alsoSent"] >= 5
   TestAssert "and arrived (" & gAlsoGot & ")", gAlsoGot >= 5
   TestAssert "the footer says so", the text of field "albStatus" of stack sDemo begins with "Also sending universe 0 to the node at 127.0.0.1:" & tPort
   close stack sDemo
   TestPump 100
   demoOpen "constant kAlbAlsoTo = " & quote & quote & "|constant kAlbAlsoTo = " & quote & "192.168.1.255" & quote
   TestPump 400
   put demoState() into tState
   TestAssertEqual "a broadcast address is not taken", tState["also"], empty
   TestAssertEqual "so nothing goes there", tState["alsoSent"], 0
   TestAssert "and the footer says why (" & the text of field "albStatus" of stack sDemo & ")", the text of field "albStatus" of stack sDemo contains "never broadcasts"
   -- This listener's senders first: the engine lists one socket for each, on
   -- the listener's descriptor, and one left listed after the listener closes
   -- keeps the engine's socket thread spinning (the suite's engine notes, 6.21)
   repeat for each key tFrom in gAlsoFrom
      if tFrom is among the lines of the openSockets then
         close socket tFrom
      end if
   end repeat
   close socket tPort
end TestAlsoToSendsOnlyWhenItNamesANode

on alsoReceived pSender, pData, pSocket
   global gAlsoGot, gAlsoFrom
   local tFrame
   put true into gAlsoFrom[pSender]
   put artnetParseDmx(pData) into tFrame
   if tFrame["opcode"] is "ArtDmx" then
      add 1 to gAlsoGot
   end if
end alsoReceived

on TestWithoutTheLibraryItSaysWhatIsMissing
   local tState, tFaders
   -- an OXT without artnetxt: the module is not loaded, so the first call of
   -- a handler it would define throws
   unload extension "org.openxtalk.library.artnet"
   demoOpen
   TestPump 400
   put demoState() into tState
   TestAssertEqual "artnetxt is not there", tState["haveArt"], false
   TestAssert "and it says why (" & tState["whyNot"] & ")", tState["whyNot"] contains "artnetxt is not loaded"
   TestAssertEqual "the show still runs", tState["running"], true
   TestAssertEqual "with nothing going wrong", tState["trouble"], empty
   TestAssertEqual "and nothing sent", tState["sent"], 0
   TestAssert "the rig says what is missing", the visible of field "albMissing" of stack sDemo and the text of field "albMissing" of stack sDemo contains "artnetxt"
   TestAssert "and so does the footer (" & the text of field "albStatus" of stack sDemo & ")", the text of field "albStatus" of stack sDemo begins with "Missing: artnetxt"
   put tState["sentLevels"] into tFaders
   TestPump 400
   put demoState() into tState
   TestAssert "the board still moves", tState["sentLevels"] is not tFaders
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
   TestAssert "the window was built", there is a graphic "albStage" of stack sDemo
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
   TestAssert "a reopen built the window again", there is a graphic "albStage" of stack sDemo
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
-- on would run unseen with its sockets open (after each close in OXT-Beyond
-- 0.2.8-dp.1's IDE on Windows a frame was still queued, 2026-11-21). And
-- none of its sockets is left listed: the engine lists one more for each
-- sender a datagram listener hears and keeps it after the listener closes
-- (the suite's engine notes, 6.21), so the show closes those names too
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
      if item 3 of tLine begins with "albFrame" then
         add 1 to tN
      end if
   end repeat
   return tN
end demoFramesQueued
