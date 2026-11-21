script "OSC Show Surface"

-- osc-show-surface.livecodescript - oscxt's showcase, by Seth Morrow.
--
-- Two programs talking Open Sound Control in one window: a SURFACE (six
-- faders, an XY pad) that sends real OSC, and a show RIG (twelve lamps with
-- their beams, a spotlight on a floor, a six-channel mixer) that draws ONLY
-- what arrives. Between them is a real UDP socket on this computer: the
-- surface writes each message to 127.0.0.1, the rig accepts datagrams on
-- port 9000, and oscParse reads every one back before anything on the rig
-- moves. So the picture is the proof: if the lamps follow the faders, the
-- bytes went out, came back and were read.
--
-- It opens straight into motion and plays five scenes, one capability each:
--   1. Faders      floats, thirty messages a second per fader
--   2. XY pad      two floats and a 32-bit integer per message
--   3. Patterns    one message, many lamps: OSC address patterns, oscMatch
--   4. Timed cues  bundles with an NTP timetag 1.2 s ahead, applied on time
--   5. Bad bytes   malformed datagrams thrown at the rig, each refused
-- A scene button jumps to its scene; "Play them all" goes round them;
-- "Pause" holds the picture still.
--
-- HOW TO OPEN: start-here.livecodescript's Open button (it does the next
-- three steps for you), or paste THIS whole file into a new stack's STACK
-- script, Apply, then close the stack and open it again. Opening the file
-- itself loads the script and builds no window (the suite's engine notes,
-- 5.5). It needs the oscxt extension installed; without it the window still
-- opens and says what is missing. osc-helpers (scAddArg,
-- scEnsureDatagramSocket, scOscRoute) is embedded below, so there is
-- nothing else to load.
--
-- THE NETWORK: everything it SENDS goes to 127.0.0.1, this computer, and
-- nothing else. The rig listens on UDP port 9000 (the next free one up to
-- 9009 when 9000 is taken), which any device on your network can reach: to
-- drive the rig from a phone, point TouchOSC (or any OSC app) at this
-- computer, port 9000, and send /mixer/1/level or /lamp/3 as the scenes do.
-- Windows may ask whether OXT may use the network; the demo works either
-- way, because it only talks to itself.
--
-- THE LOOK is OXT-Beyond's dark stage (the Render3D Tour's palette), not the
-- suite's light UI kit, by request (2026-11-21), so this stack is in
-- tools/check-ui-kit-drift.py's EXEMPT list. Every field and button sets its
-- own text colour, because OXT-Beyond gives a control without one white
-- text under a dark system theme, and every switch is a button, not a tick
-- box, which the system draws in its own colours.
--
-- FOR THE TESTS (tests/lcs/demo_test.livecodescript): osdTestBegin stops
-- the clock's loop, osdTestStep moves the show on by so many seconds and
-- draws, osdGo jumps to a scene, and osdState() says how things are.
--
-- HONESTY (the suite convention): it built, ran every scene and passed its
-- loopback in OXT-Beyond's standalone engine (9.7.1-OXT, Linux x86_64,
-- headless with -ui) on 2026-11-21. Nobody has looked at its window yet:
-- the look, the motion and the feel are verified statically; need an OXT
-- pass.

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- oscxt/examples/osc-helpers.livecodescript ----
-- osc-helpers.livecodescript
-- ---------------------------------------------------------------------------
-- Reusable LiveCode Script helpers for the oscxt extension (Open Sound
-- Control). Paste this into a stack or card script (or a library stack you
-- `start using`), then your own handlers only need to react to messages:
--
--     accept datagram connections on port 9000 with message "socketReceived"
--     on scOscMessage pAddress, pArgs, pSender ... end scOscMessage
--
-- and to send:
--
--     local tArgs
--     scAddArg tArgs, "f", 0.8
--     scOscSend "127.0.0.1", 9000, "/1/fader1", tArgs
--
-- These are the OSC half of ShowControl's showcontrol-helpers.livecodescript,
-- unchanged in name and behaviour: a script that pasted the old combined file
-- keeps working, and pasting this one beside midixt's midi-helpers and
-- artnetxt's artnet-helpers gives the same handlers again (no name is defined
-- in two of the three files, which the suite's
-- tools/check-cross-library-names.py holds).
-- ---------------------------------------------------------------------------

-- ===== UDP transport ========================================================

-- Make sure a datagram socket to "host:port" is open before writing to it. The
-- engine only writes to an OPEN socket: `write ... to socket "h:p"` on a name
-- that was never opened sets the result to "socket is not open" and sends
-- NOTHING, silently (engine/src/exec-network.cpp, MCNetworkExecWriteToSocket).
-- Opening is idempotent here, so call it before every send.
-- (Broadcast additionally needs `set the allowDatagramBroadcasts to true`.)
command scEnsureDatagramSocket pHostPort
   if pHostPort is not among the lines of the openSockets then
      open datagram socket to pHostPort
   end if
end scEnsureDatagramSocket

-- ===== Building and sending =================================================

-- Build an OSC args list the way LiveCode Script must. xTalk has NO [...]
-- list-literal expression (that is LiveCode Builder syntax), so you cannot write
-- oscBuildMessage("/x", [["i", 60]]) in a .livecodescript. Instead build the args
-- array by assignment: scAddArg appends one type/value pair as TWO consecutive
-- elements (a FLAT list -- a nested LiveCode array does not survive the Script->LCB
-- boundary as a list-of-lists, so we flatten to scalars), to an args array passed
-- BY REFERENCE. Hand the finished array to oscBuildMessage / scOscSend. For the
-- no-value OSC types (T/F/N/I) pass empty for the value -- it is ignored.
--
--   local tArgs
--   scAddArg tArgs, "i", 60
--   scAddArg tArgs, "f", 0.8
--   put oscBuildMessage("/synth/note", tArgs) into tData
command scAddArg @pArgs, pType, pValue
   put pType into pArgs[(the number of elements of pArgs) + 1]
   if pType is "b" then
      -- Blob: raw Data must cross unchanged (oscBuildMessage reads it as Data).
      put pValue into pArgs[(the number of elements of pArgs) + 1]
   else
      -- Force every non-blob value to a STRING before it enters the args list.
      -- `& empty` is LiveCode's force-to-string: it collapses the number/string
      -- duality to a pure string, which arrives in LCB as a String and is parsed
      -- in C. (Pass floats/doubles you need at full precision as strings -- a
      -- string is preserved verbatim; a number is stringified via numberFormat.)
      put (pValue & empty) into pArgs[(the number of elements of pArgs) + 1]
   end if
end scAddArg

-- Send one OSC message to host:port. pArgs is an args array built with scAddArg.
-- Builds nothing and sends nothing when the message cannot be built
-- (oscLastError() says why).
on scOscSend pHost, pPort, pAddress, pArgs
   local tData
   put oscBuildMessage(pAddress, pArgs) into tData
   if tData is empty then
      exit scOscSend
   end if
   scEnsureDatagramSocket pHost & ":" & pPort
   write tData to socket (pHost & ":" & pPort)
end scOscSend

-- ===== Receiving and routing ================================================

-- Route inbound OSC by address. Wire it up with
--     accept datagram connections on port 9000 with message "socketReceived"
-- and write your own `on scOscMessage pAddress, pArgs, pSender` to react
-- (pArgs is the parsed argument array; bundles are unpacked, nested ones too).
--
-- The engine calls a datagram message with (sender "host:port", data, socket)
-- -- in THAT order (engine/src/opensslsocket.cpp, MCSocket::readsome). This
-- handler once declared (pData, pHostAndPort), so it parsed the sender's address
-- as OSC and never routed anything; it also issued a blocking `read from socket`,
-- which an accepted datagram socket does not need (every datagram arrives as its
-- own message). For callers wired the old way round, a packet in the first
-- parameter is still recognised.
on socketReceived pSender, pData
   local tMsg
   if scLooksLikeOsc(pSender) and not scLooksLikeOsc(pData) then
      put oscParse(pSender) into tMsg
      put pData into pSender
   else
      put oscParse(pData) into tMsg
   end if
   scOscRoute tMsg, pSender, the long id of the target
end socketReceived

-- Deliver one parsed message (or every message of a bundle, recursively).
command scOscRoute pMsg, pSender, pTarget
   local tSub
   if pMsg["isBundle"] is true then
      repeat for each element tSub in pMsg["messages"]
         scOscRoute tSub, pSender, pTarget
      end repeat
   else if pMsg["address"] is not empty then
      dispatch "scOscMessage" to pTarget with pMsg["address"], pMsg["args"], pSender
   end if
end scOscRoute

-- Does this value look like an OSC packet (a message or a bundle)?
function scLooksLikeOsc pX
   if char 1 of pX is "/" then
      return true
   end if
   return (byte 1 to 8 of pX) is ("#bundle" & numToByte(0))
end scLooksLikeOsc

-- <<< END EMBEDDED LIBRARIES <<<

-- ===== Sizes and the look ===================================================

constant kOsdW = 1100
constant kOsdH = 620
constant kOsdFrameMs = 33          -- about thirty pictures a second
constant kOsdPortFirst = 9000
constant kOsdPortLast = 9009
constant kOsdHost = "127.0.0.1"
constant kOsdLamps = 12
constant kOsdFaders = 6
constant kOsdScenes = 5
constant kOsdSceneNames = "Faders,XY pad,Patterns,Timed cues,Bad bytes"
constant kOsdSceneSecs = "10,10,14,13,12"
constant kOsdWireLines = 6
-- a wire line's most characters: 10-point mono in the wire's 272 pixels,
-- measured in DejaVu Sans Mono, the widest of the three systems' fonts
constant kOsdWireChars = 44
constant kOsdTrail = 8

-- OXT-Beyond's dark stage: the Render3D Tour's colours, as r,g,b so the
-- picture can mix them
constant kOsdPage = "18,21,31"
constant kOsdPanel = "28,33,48"
constant kOsdWell = "12,15,23"
constant kOsdInk = "238,241,247"
constant kOsdSoft = "169,178,199"
constant kOsdAccent = "255,138,61"
constant kOsdButton = "42,49,70"
constant kOsdLine = "58,66,92"
constant kOsdLampOff = "44,49,66"
constant kOsdBad = "255,107,107"

-- The geometry, in one place
constant kOsdStageL = 16
constant kOsdStageT = 84
constant kOsdStageR = 780
constant kOsdStageB = 588
constant kOsdFloorL = 30
constant kOsdFloorT = 172
constant kOsdFloorR = 680
constant kOsdFloorB = 350
constant kOsdLampY = 140
constant kOsdLampX0 = 62
constant kOsdLampDX = 54
constant kOsdMeterL = 700
constant kOsdMeterT = 140
constant kOsdMeterB = 334
constant kOsdFaderL = 44
constant kOsdFaderDX = 30
constant kOsdFaderT = 400
constant kOsdFaderB = 552
constant kOsdPadL = 236
constant kOsdPadT = 398
constant kOsdPadS = 160
constant kOsdSideL = 796
constant kOsdSideR = 1084

-- The bad datagrams of scene 5: tests/vectors/osc.json's malformed set,
-- which the shim's C tests and the LCB suite refuse too (name|hex).
constant kOsdBadBytes = "three bytes|2f6100,a length that is not a multiple of 4|2f6100002c00,no slash before the address|616263002c000000,no comma before the type tags|2f61000069000000,type tags with no end|2f6100002c696969,an integer cut off|2f6100002c690000,a type tag nobody knows (x)|2f6100002c78000000000000,a blob that runs past the end|2f6100002c6200000000001001020304,a blob that is minus one byte long|2f6100002c620000ffffffff,a blob that says it is 2 GB|2f6100002c6200007ffffffc,a string with no end|2f6100002c73000061626364,a bundle element past the end|2362756e646c65000000000000000001000000102f610000,a bundle element that says 2 GB|2362756e646c650000000000000000017ffffff02f610000"

-- Scene 3's patterns, and the lamps each one names (pattern|lamps). The
-- entries are split on ";", since a {2,4} pattern holds commas of its own.
constant kOsdPatterns = "/lamp/*|1 2 3 4 5 6 7 8 9 10 11 12;/lamp/?|1 2 3 4 5 6 7 8 9;/lamp/1?|10 11 12;/lamp/[1-4]|1 2 3 4;/lamp/[!1-4]|5 6 7 8 9;/lamp/{2,4,6,8,10,12}|2 4 6 8 10 12;/lamp/{1,3,5,7,9,11}|1 3 5 7 9 11;/lamp/*[05]|5 10;/lamp/[5-8]|5 6 7 8;/lamp/1[!0]|11 12"

-- Scene 4's cues: name|fader levels|spot x,y,size,hue|lamp hue|lamp levels
constant kOsdCues = "Dawn|0.2 0.3 0.4 0.3 0.2 0.1|0.2,0.3,0.7,35|30|0.2 0.3 0.5 0.7 0.9 1 1 0.9 0.7 0.5 0.3 0.2;Noon|0.9 0.9 0.8 0.8 0.9 0.9|0.5,0.55,1.2,55|50|1 1 1 1 1 1 1 1 1 1 1 1;Sunset|0.7 0.5 0.3 0.5 0.7 0.9|0.8,0.4,0.9,15|10|1 0.8 0.6 0.4 0.2 0.1 0.1 0.2 0.4 0.6 0.8 1;Night|0.1 0.2 0.1 0.2 0.1 0.2|0.5,0.7,0.5,220|230|0.1 0 0.3 0 0.1 0 0 0.1 0 0.3 0 0.1"

-- ===== State =================================================================

local sMyStack            -- the stack's short name: every delayed message pins it
local sRunning, sGen      -- the loop runs; its generation (a stale tick dies)
local sClockMs            -- the milliseconds at the last frame
local sFrames             -- pictures drawn since the stack opened
local sScene, sSceneT     -- the scene playing, and the seconds it has played
local sNextAt, sStep      -- a scene's own schedule
local sTour, sPaused
local sHaveOsc, sWhyNot   -- oscxt answers; why not, when it does not
local sPort, sDest        -- the rig's UDP port; "127.0.0.1:<port>"
local sPeers              -- each sender the rig heard, a key (engine note 6.20)
local sNoNet              -- why the rig cannot listen, when it cannot
local sTrouble            -- an error the loop caught
-- the surface: what the script moves
local sFader, sPuckX, sPuckY, sTrailX, sTrailY, sSends
-- the rig: only what arrived
local sMeter, sPeak, sLamp, sLampHue
local sSpotX, sSpotY, sSpotSize, sSpotHue
local sPending, sPendingN, sCueText, sCueDue, sCueSpan
-- the wire
local sSent, sArrived, sRefused, sRead, sBadSent
local sRateMark, sRateBase, sRate
local sWireLog, sWireTable, sWireMode

-- ===== The stack's own messages =============================================

on preOpenStack
   put the short name of this stack into sMyStack
   osdBuild
end preOpenStack

on openStack
   osdStart
end openStack

on closeStack
   osdStop
end closeStack

on mouseUp
   local tName
   put the short name of the target into tName
   if tName begins with "osdScene" and char 9 to -1 of tName is an integer then
      osdGo char 9 to -1 of tName
   else if tName is "osdTour" then
      put (sTour is not true) into sTour
      osdShowSwitches
   else if tName is "osdPause" then
      put (sPaused is not true) into sPaused
      osdShowSwitches
   else
      pass mouseUp
   end if
end mouseUp

-- ===== Starting and stopping ================================================

command osdStart
   if sMyStack is empty then
      put the short name of this stack into sMyStack
   end if
   if there is not a graphic "osdStage" then
      osdBuild
   end if
   osdStop
   osdResetRig
   put true into sTour
   put false into sPaused
   put empty into sTrouble
   put 0 into sFrames
   osdProbe
   osdListen
   osdShowStatus
   osdShowSwitches
   osdGo 1
   put true into sRunning
   add 1 to sGen
   put the milliseconds into sClockMs
   osdFrame sGen
end osdStart

command osdStop
   local tOpen, tPeer
   put false into sRunning
   add 1 to sGen
   -- the senders the rig heard first, while the descriptor they share is open
   put the openSockets into tOpen
   repeat for each key tPeer in sPeers
      if tPeer is empty or tPeer is sDest then
         next repeat
      end if
      if tPeer is among the lines of tOpen then
         close socket tPeer
      end if
   end repeat
   put empty into sPeers
   if sPort is not empty then
      close socket sPort
   end if
   if sDest is not empty and sDest is among the lines of the openSockets then
      close socket sDest
   end if
   put empty into sPort
   put empty into sDest
end osdStop

-- Is oscxt here? The first call of an LCB library that is not loaded throws
-- (no such handler), and so does one whose native library did not load; the
-- loaded extensions tell the two apart.
command osdProbe
   local tErr, tAbi
   put false into sHaveOsc
   put empty into sWhyNot
   try
      put oscVersion() into tAbi
      put (tAbi is 2) into sHaveOsc
      if not sHaveOsc then
         put "oscxt's native library is ABI " & tAbi & ", and this demo is written for 2." into sWhyNot
      end if
   catch tErr
      if "org.openxtalk.library.osc" is among the lines of the loadedExtensions then
         put "oscxt is loaded, but its native library did not load: " & osdEngineSays(tErr) & "." into sWhyNot
      else
         put "oscxt is not loaded in this OXT: nothing answered oscVersion()." into sWhyNot
      end if
   end try
end osdProbe

-- The sentence in an engine error (its lines are code,line,column,hint, and
-- one hint is the message itself): the first hint with a space in it
function osdEngineSays pErr
   local tLine
   repeat for each line tLine in pErr
      if item 4 to -1 of tLine contains space then
         return item 4 to -1 of tLine
      end if
   end repeat
   return "the engine gave no reason"
end osdEngineSays

-- The rig listens on 9000, or the next free port up to 9009. A port that will
-- not open says so only in the result (the suite's engine notes, 6.12).
command osdListen
   local tPort
   put empty into sPort
   put empty into sDest
   put empty into sNoNet
   repeat with tPort = kOsdPortFirst to kOsdPortLast
      accept datagram connections on port tPort with message "osdReceived"
      if the result is empty then
         put tPort into sPort
         exit repeat
      end if
   end repeat
   if sPort is empty then
      put "No UDP port from " & kOsdPortFirst & " to " & kOsdPortLast & " would open here, so the rig cannot listen." into sNoNet
      exit osdListen
   end if
   put kOsdHost & ":" & sPort into sDest
   scEnsureDatagramSocket sDest
end osdListen

-- ===== The loop =============================================================

on osdFrame pGen
   local tNow, tDt, tErr
   if pGen is not sGen or sRunning is not true then
      exit osdFrame
   end if
   if sMyStack is not empty then
      -- A closed window stops its own show. closeStack stops it, but a
      -- close made with messages locked sends none, and the IDE keeps a
      -- closed stack in memory, where this loop would run on unseen with
      -- its port open (after each close in OXT-Beyond 0.2.8-dp.1's IDE on
      -- Windows a frame was still queued, 2026-11-21). An invisible window
      -- is open: only a closed stack is mode 0.
      if the mode of stack sMyStack is 0 then
         osdStop
         exit osdFrame
      end if
      set the defaultStack to sMyStack
   end if
   put the milliseconds into tNow
   put (tNow - sClockMs) / 1000 into tDt
   put tNow into sClockMs
   -- a stall (a dialog, a drag of the window) must not jump the show ahead
   if tDt > 0.2 then
      put 0.2 into tDt
   end if
   try
      if sPaused is not true then
         osdTick tDt
      end if
      osdRender
   catch tErr
      put tErr into sTrouble
      put false into sRunning
      osdShowStatus
      exit osdFrame
   end try
   send ("osdFrame" && pGen) to me in kOsdFrameMs milliseconds
end osdFrame

command osdTick pDt
   add pDt to sSceneT
   switch sScene
      case 1
         osdSceneFaders
         break
      case 2
         osdScenePad
         break
      case 3
         osdScenePatterns
         break
      case 4
         osdSceneCues
         break
      case 5
         osdSceneBad
         break
   end switch
   osdApplyDue
   osdRigEase pDt
   osdRate
   if sTour is true and sSceneT >= item sScene of kOsdSceneSecs then
      osdGo (sScene mod kOsdScenes) + 1
   end if
end osdTick

-- Jump to a scene: its words, its wire view, its button lit
command osdGo pScene
   local tI
   if pScene < 1 or pScene > kOsdScenes then
      exit osdGo
   end if
   put pScene into sScene
   put 0 into sSceneT
   put 0 into sNextAt
   put 0 into sStep
   put empty into sWireLog
   put empty into sWireTable
   put empty into sCueText
   put empty into sPending
   put 0 into sPendingN
   if pScene is 1 or pScene is 2 then
      put "table" into sWireMode
   else
      put "log" into sWireMode
   end if
   lock screen
   repeat with tI = 1 to kOsdScenes
      set the hilite of button ("osdScene" & tI) to (tI is pScene)
   end repeat
   set the text of field "osdAbout" to osdAbout(pScene)
   set the visible of field "osdCue" to (pScene is 4)
   set the visible of graphic "osdCueBar" to (pScene is 4)
   set the visible of graphic "osdCueTrack" to (pScene is 4)
   set the visible of field "osdShield" to (pScene is 5)
   unlock screen
end osdGo

function osdAbout pScene
   switch pScene
      case 1
         return "Six faders send /mixer/1/level to /mixer/6/level as 32-bit floats, thirty times a second each, every message its own UDP datagram to this computer. The mixer and the lamps move only on what oscParse reads back."
      case 2
         return "The pad sends /stage/spot with two floats, x and y, and /stage/spot/hue with a 32-bit integer. The spotlight on the rig's floor follows what arrives, and so does its colour."
      case 3
         return "One message, many lamps. The surface sends an address PATTERN and the rig asks oscMatch which of its twelve lamps it names: * any run, ? one character, [1-4] a range, [!1-4] one not in it, {2,4,6} a list."
      case 4
         return "A cue is a bundle: 21 messages in one datagram, with an NTP timetag 1.2 seconds ahead. The rig holds it and changes everything at once when it comes due. The timetag crosses as decimal text, exactly."
      case 5
         return "Bytes from the network are untrusted. Between good messages the surface throws malformed datagrams at the rig; oscParse refuses each one with its reason and never reads past the end, and the show goes on."
   end switch
   return empty
end osdAbout

-- ===== Sending ==============================================================

-- One message to the rig. Builds through oscBuildMessage and writes to the
-- socket osdListen opened; false when nothing could go.
function osdSendMsg pAddress, pArgs
   local tData
   if sHaveOsc is not true or sDest is empty then
      return false
   end if
   put oscBuildMessage(pAddress, pArgs) into tData
   if tData is empty then
      osdLog "could not build " & pAddress & ": " & oscLastError(), true
      return false
   end if
   write tData to socket sDest
   add 1 to sSent
   return true
end osdSendMsg

-- Raw bytes to the rig (scene 5's bad datagrams)
command osdSendBytes pData
   if sHaveOsc is not true or sDest is empty then
      exit osdSendBytes
   end if
   write pData to socket sDest
   add 1 to sSent
end osdSendBytes

-- Scene 1: six faders in a slow wave, every level every frame
command osdSceneFaders
   local tI, tV, tArgs, tText
   repeat with tI = 1 to kOsdFaders
      put 0.5 + 0.4 * sin(sSceneT * 1.3 + tI * 0.8) * (0.65 + 0.35 * sin(sSceneT * 0.45 + tI * 1.7)) into tV
      put max(0, min(1, tV)) into tV
      put tV into sFader[tI]
      put empty into tArgs
      scAddArg tArgs, "f", tV
      get osdSendMsg("/mixer/" & tI & "/level", tArgs)
      put "/mixer/" & tI & "/level  f  " & format("%.3f", tV) & return after tText
   end repeat
   put "SENDS, every frame:" & return & tText into sSends
end osdSceneFaders

-- Scene 2: the puck draws a figure of eight; the hue goes round
command osdScenePad
   local tArgs, tHue
   put 0.5 + 0.38 * sin(sSceneT * 1.1) into sPuckX
   put 0.5 + 0.34 * sin(sSceneT * 2.2 + 0.6) into sPuckY
   put round(sSceneT * 36) mod 360 into tHue
   put empty into tArgs
   scAddArg tArgs, "f", sPuckX
   scAddArg tArgs, "f", sPuckY
   get osdSendMsg("/stage/spot", tArgs)
   put empty into tArgs
   scAddArg tArgs, "i", tHue
   get osdSendMsg("/stage/spot/hue", tArgs)
   put "SENDS, every frame:" & return & "/stage/spot  ff  " & format("%.3f", sPuckX) & "  " & format("%.3f", sPuckY) & return & "/stage/spot/hue  i  " & tHue into sSends
end osdScenePad

-- Scene 3: a pattern every 1.3 s, in a new colour each time
command osdScenePatterns
   local tEntry, tPattern, tArgs, tHue
   if sSceneT < sNextAt then
      exit osdScenePatterns
   end if
   add 1 to sStep
   put sNextAt + 1.3 into sNextAt
   put osdPatternAt(sStep) into tEntry
   set the itemDelimiter to "|"
   put item 1 of tEntry into tPattern
   set the itemDelimiter to comma
   put (sStep * 47) mod 360 into tHue
   put empty into tArgs
   scAddArg tArgs, "f", 1
   scAddArg tArgs, "i", tHue
   get osdSendMsg(tPattern, tArgs)
   put "SENDS one message:" & return & tPattern & "  fi  1.0  " & tHue & return & return & "and the rig asks oscMatch about each" & return & "of /lamp/1 to /lamp/12" into sSends
end osdScenePatterns

-- The Nth "pattern|lamps" entry of kOsdPatterns, going round
function osdPatternAt pN
   local tEntry
   set the itemDelimiter to ";"
   put item ((pN - 1) mod (the number of items of kOsdPatterns) + 1) of kOsdPatterns into tEntry
   set the itemDelimiter to comma
   return tEntry
end osdPatternAt

-- Scene 4: a cue every 3.2 s, as ONE bundle due 1.2 s after it is sent
command osdSceneCues
   local tCue, tName, tTag, tData
   if sSceneT < sNextAt then
      exit osdSceneCues
   end if
   add 1 to sStep
   put sNextAt + 3.2 into sNextAt
   set the itemDelimiter to ";"
   put item ((sStep - 1) mod 4 + 1) of kOsdCues into tCue
   set the itemDelimiter to "|"
   put item 1 of tCue into tName
   set the itemDelimiter to comma
   osdRecallCue tCue
   put osdTimetagIn(1.2) into tTag
   put empty into tData
   if sHaveOsc is true and sDest is not empty then
      put osdCueBundle(tCue, tTag) into tData
      if tData is empty then
         osdLog "could not build the cue: " & oscLastError(), true
      else
         write tData to socket sDest
         add 1 to sSent
      end if
   end if
   put "SENDS cue " & ((sStep - 1) mod 4 + 1) & ", " & quote & tName & quote & ", as ONE bundle:" & return & "#bundle  " & (kOsdFaders + 3 + kOsdLamps) & " messages  " & the number of bytes in tData & " bytes" & return & "timetag " & tTag & return & "  = now + 1.2 s, as NTP decimal text" into sSends
   put tName into sCueText
end osdSceneCues

-- The surface shows the cue it sends: its faders and its puck go there
command osdRecallCue pCue
   local tLevels, tSpot, tI
   set the itemDelimiter to "|"
   put item 2 of pCue into tLevels
   put item 3 of pCue into tSpot
   set the itemDelimiter to comma
   repeat with tI = 1 to kOsdFaders
      put word tI of tLevels into sFader[tI]
   end repeat
   put item 1 of tSpot into sPuckX
   put item 2 of tSpot into sPuckY
end osdRecallCue

-- One cue (name|faders|spot|lamp hue|lamps) as a bundle of 21 messages:
-- six faders, the spot's place, size and hue, and twelve lamps
function osdCueBundle pCue, pTag
   local tMsgs, tN, tI, tArgs, tLevels, tSpot, tHue
   put 0 into tN
   set the itemDelimiter to "|"
   put item 2 of pCue into tLevels
   put item 3 of pCue into tSpot
   put item 4 of pCue into tHue
   set the itemDelimiter to comma
   repeat with tI = 1 to kOsdFaders
      put empty into tArgs
      scAddArg tArgs, "f", word tI of tLevels
      add 1 to tN
      put oscBuildMessage("/mixer/" & tI & "/level", tArgs) into tMsgs[tN]
   end repeat
   put empty into tArgs
   scAddArg tArgs, "f", item 1 of tSpot
   scAddArg tArgs, "f", item 2 of tSpot
   add 1 to tN
   put oscBuildMessage("/stage/spot", tArgs) into tMsgs[tN]
   put empty into tArgs
   scAddArg tArgs, "f", item 3 of tSpot
   add 1 to tN
   put oscBuildMessage("/stage/spot/size", tArgs) into tMsgs[tN]
   put empty into tArgs
   scAddArg tArgs, "i", item 4 of tSpot
   add 1 to tN
   put oscBuildMessage("/stage/spot/hue", tArgs) into tMsgs[tN]
   set the itemDelimiter to "|"
   put item 5 of pCue into tLevels
   set the itemDelimiter to comma
   repeat with tI = 1 to kOsdLamps
      put empty into tArgs
      scAddArg tArgs, "f", word tI of tLevels
      scAddArg tArgs, "i", tHue
      add 1 to tN
      put oscBuildMessage("/lamp/" & tI, tArgs) into tMsgs[tN]
   end repeat
   return oscBuildBundle(pTag, tMsgs)
end osdCueBundle

-- Scene 5: a good lamp message every frame (a chase), and a bad datagram
-- every 0.45 s
command osdSceneBad
   local tArgs, tLamp, tEntry, tName, tHex, tData
   put (round(sSceneT * 8) mod kOsdLamps) + 1 into tLamp
   put empty into tArgs
   scAddArg tArgs, "f", 1
   scAddArg tArgs, "i", 200
   get osdSendMsg("/lamp/" & tLamp, tArgs)
   if sSceneT < sNextAt then
      exit osdSceneBad
   end if
   add 1 to sStep
   put sNextAt + 0.45 into sNextAt
   put item ((sStep - 1) mod (the number of items of kOsdBadBytes) + 1) of kOsdBadBytes into tEntry
   set the itemDelimiter to "|"
   put item 1 of tEntry into tName
   put item 2 of tEntry into tHex
   set the itemDelimiter to comma
   put binaryEncode("H*", tHex) into tData
   osdSendBytes tData
   if sHaveOsc is true and sDest is not empty then
      add 1 to sBadSent
   end if
   put "THROWS " & tName & ":" & return & osdHexSpaced(tHex) & return & return & "and a good /lamp/n every frame between them" into sSends
end osdSceneBad

-- "2f6100002c00" -> "2f 61 00 00 2c 00"
function osdHexSpaced pHex
   local tOut, tI
   put empty into tOut
   repeat with tI = 1 to the number of chars of pHex
      put char tI of pHex after tOut
      if tI mod 2 is 0 and tI < the number of chars of pHex then
         put space after tOut
      end if
   end repeat
   return tOut
end osdHexSpaced

-- An NTP timetag pSeconds from now, as the decimal text OSC bundles carry
function osdTimetagIn pSeconds
   return osdTimetagAt(the milliseconds / 1000 + pSeconds)
end osdTimetagIn

-- The NTP timetag of a moment (seconds since 1970, as the milliseconds count
-- them, over 1000). The value is (seconds since 1900) * 2^32 + fraction,
-- about 1.7e19: more than a script number holds exactly (2^53), so it is put
-- together in pieces small enough to be exact: S * 2^32 is S * 4294 * 10^6
-- plus S * 967296, and each product stays below 2^53 until 2036.
function osdTimetagAt pUnix
   local tS, tF, tA, tB, tQ, tR
   put trunc(pUnix) + 2208988800 into tS
   put round((pUnix - trunc(pUnix)) * 4294967296) into tF
   if tF > 4294967295 then
      put 4294967295 into tF
   end if
   put tS * 4294 into tA
   put tS * 967296 + tF into tB
   put trunc(tB / 1000000) into tQ
   put tB - tQ * 1000000 into tR
   if tR < 0 then
      subtract 1 from tQ
      add 1000000 to tR
   else if tR >= 1000000 then
      add 1 to tQ
      subtract 1000000 from tR
   end if
   return format("%.0f", tA + tQ) & format("%06d", tR)
end osdTimetagAt

-- The milliseconds (since 1970, as `the milliseconds` counts) a timetag
-- names; 0 for "1", which means at once
function osdTimetagMs pText
   if pText is empty or pText is "1" or pText is "0" then
      return 0
   end if
   return (pText / 4294967296 - 2208988800) * 1000
end osdTimetagMs

-- ===== Receiving: the rig ===================================================

-- Every datagram that reaches the rig's port, from this computer or any
-- other. The engine calls it with (sender, data, socket), in that order.
on osdReceived pSender, pData, pSocket
   local tMsg, tDue
   if sMyStack is not empty then
      set the defaultStack to sMyStack
   end if
   -- A datagram from a sender the rig has not heard makes the engine list
   -- one more socket, named by that sender ("127.0.0.1:41273") and sharing
   -- the listener's descriptor, so that a reply can be written to it. Closing
   -- the listener leaves that name listed (the suite's engine notes, 6.20), so
   -- the rig remembers each sender, and the show closes them when it stops.
   put true into sPeers[pSender]
   add 1 to sArrived
   if sHaveOsc is not true then
      exit osdReceived
   end if
   put oscParse(pData) into tMsg
   if tMsg["isBundle"] is true then
      add 1 to sRead
      put osdTimetagMs(tMsg["timetag"]) into tDue
      osdNoteBundle tMsg, tDue
      if tDue <= the milliseconds then
         scOscRoute tMsg, pSender, the long id of me
      else
         add 1 to sPendingN
         put tDue into sPending[sPendingN]["due"]
         put tMsg into sPending[sPendingN]["msg"]
         put pSender into sPending[sPendingN]["from"]
         put tDue into sCueDue
         put tDue - the milliseconds into sCueSpan
      end if
   else if tMsg["address"] is empty then
      add 1 to sRefused
      osdLog osdRefusedLine(osdReason(tMsg["error"]), the number of bytes in pData), true
   else
      add 1 to sRead
      osdNoteMessage tMsg, pSender
      scOscRoute tMsg, pSender, the long id of me
   end if
end osdReceived

-- osc-helpers' scOscRoute calls this for each message (bundles unpacked)
on scOscMessage pAddress, pArgs, pSender
   local tN, tLamp
   if pAddress begins with "/mixer/" then
      set the itemDelimiter to "/"
      put item 3 of pAddress into tN
      set the itemDelimiter to comma
      if tN is an integer and tN >= 1 and tN <= kOsdFaders and pArgs[1] is a number then
         put max(0, min(1, pArgs[1])) into sMeter[tN]
         -- the rig's own rule: mixer channel n also drives lamps 2n-1 and 2n
         put sMeter[tN] into sLamp[tN * 2 - 1]
         put sMeter[tN] into sLamp[tN * 2]
         put 32 into sLampHue[tN * 2 - 1]
         put 32 into sLampHue[tN * 2]
      end if
   else if pAddress is "/stage/spot" then
      if pArgs[1] is a number and pArgs[2] is a number then
         put max(0, min(1, pArgs[1])) into sSpotX
         put max(0, min(1, pArgs[2])) into sSpotY
         -- the rig's own rule: the lamps nearest the spot light up in its
         -- colour, so the truss follows the performer across the stage
         repeat with tLamp = 1 to kOsdLamps
            put max(sLamp[tLamp], 1 - abs((tLamp - 0.5) / kOsdLamps - sSpotX) * 5) into sLamp[tLamp]
            put sSpotHue into sLampHue[tLamp]
         end repeat
      end if
   else if pAddress is "/stage/spot/hue" then
      if pArgs[1] is a number then
         put round(pArgs[1]) mod 360 into sSpotHue
      end if
   else if pAddress is "/stage/spot/size" then
      if pArgs[1] is a number then
         put max(0.2, min(1.6, pArgs[1])) into sSpotSize
      end if
   else if pAddress begins with "/lamp/" then
      -- the address may be a PATTERN: ask about every lamp the rig has
      repeat with tLamp = 1 to kOsdLamps
         if oscMatch(pAddress, "/lamp/" & tLamp) then
            if pArgs[1] is a number then
               put max(0, min(1, pArgs[1])) into sLamp[tLamp]
            end if
            if pArgs[2] is a number then
               put round(pArgs[2]) mod 360 into sLampHue[tLamp]
            end if
         end if
      end repeat
   end if
end scOscMessage

-- A held bundle whose time has come goes to the rig all at once
command osdApplyDue
   local tSlots, tSlot, tNow
   put the milliseconds into tNow
   put the keys of sPending into tSlots
   repeat for each line tSlot in tSlots
      if sPending[tSlot]["due"] <= tNow then
         scOscRoute sPending[tSlot]["msg"], sPending[tSlot]["from"], the long id of me
         osdLog "cue " & quote & sCueText & quote & " came due: all 21 at once", false
         delete variable sPending[tSlot]
      end if
   end repeat
end osdApplyDue

-- Lamps settle back down when nothing new arrives; the mixer's peaks fall
command osdRigEase pDt
   local tI
   repeat with tI = 1 to kOsdFaders
      if sMeter[tI] > sPeak[tI] then
         put sMeter[tI] into sPeak[tI]
      else
         put max(sMeter[tI], sPeak[tI] - pDt * 0.5) into sPeak[tI]
      end if
   end repeat
   -- a lamp a scene does not hold settles to a glow, so the next scene's
   -- lamps read clearly (scenes 1 and 4 hold theirs with every message)
   if sScene is not 1 and sScene is not 4 then
      repeat with tI = 1 to kOsdLamps
         put max(0.06, sLamp[tI] - pDt * 1.4) into sLamp[tI]
      end repeat
   end if
end osdRigEase

-- ===== The wire: what was read ==============================================

command osdNoteMessage pMsg, pSender
   local tVals, tI
   put empty into tVals
   repeat with tI = 1 to the number of chars of pMsg["types"]
      put osdShowArg(char tI of pMsg["types"], pMsg["args"][tI]) & "  " after tVals
   end repeat
   if sWireMode is "table" then
      put pMsg["types"] & "|" & tVals & "|" & pSender into sWireTable[pMsg["address"]]
   else if sScene is 5 then
      -- the good chase is counted, not listed: the refusals are the point
      exit osdNoteMessage
   else
      osdLog pMsg["address"] & "  " & pMsg["types"] & "  " & tVals, false
   end if
end osdNoteMessage

command osdNoteBundle pMsg, pDue
   local tN, tWhen
   put the number of elements of pMsg["messages"] into tN
   if pDue > 0 then
      put format("%.1f", (pDue - the milliseconds) / 1000) & " s from now" into tWhen
   else
      put "now" into tWhen
   end if
   osdLog "#bundle  " & tN & " messages, due " & tWhen, false
end osdNoteBundle

function osdShowArg pType, pValue
   if pType is "f" or pType is "d" then
      if pValue is a number then
         return format("%.3f", pValue)
      end if
   end if
   return pValue
end osdShowArg

-- "oscParse: missing type tag" -> "missing type tag"
-- "REFUSED <the library's reason> (<size> B)", the size left off when the
-- line would not fit the wire (kOsdWireChars): the longest reason,
-- "truncated / malformed argument data", fits without it
function osdRefusedLine pReason, pBytes
   local tLine
   put "REFUSED " & pReason into tLine
   if the number of chars of tLine + the number of chars of pBytes + 4 <= kOsdWireChars then
      put " (" & pBytes & " B)" after tLine
   end if
   return tLine
end osdRefusedLine

function osdReason pError
   if pError begins with "oscParse: " then
      delete char 1 to 10 of pError
   end if
   return pError
end osdReason

command osdLog pLine, pBad
   put pLine & return after sWireLog
   if the number of lines of sWireLog > kOsdWireLines then
      delete line 1 to (the number of lines of sWireLog - kOsdWireLines) of sWireLog
   end if
end osdLog

-- Messages a second, over the last second
command osdRate
   local tNow
   put the milliseconds into tNow
   if sRateMark is empty or tNow - sRateMark >= 1000 then
      if sRateMark is not empty then
         put round((sArrived - sRateBase) * 1000 / (tNow - sRateMark)) into sRate
      end if
      put tNow into sRateMark
      put sArrived into sRateBase
   end if
end osdRate

-- ===== The picture ==========================================================

command osdRender
   local tI, tX, tLevel, tHueRgb, tW, tH, tY, tText, tRows, tRow
   add 1 to sFrames
   lock screen
   -- the lamps and their beams: level -> brightness, hue -> colour
   repeat with tI = 1 to kOsdLamps
      put sLamp[tI] into tLevel
      if tLevel is not a number then
         put 0 into tLevel
      end if
      put osdHue(sLampHue[tI], 0.75, 1) into tHueRgb
      set the backgroundColor of graphic ("osdLampCore" & tI) to osdMix(kOsdLampOff, tHueRgb, tLevel)
      set the backgroundColor of graphic ("osdLampHalo" & tI) to tHueRgb
      set the blendLevel of graphic ("osdLampHalo" & tI) to 100 - round(tLevel * 70)
      set the backgroundColor of graphic ("osdBeam" & tI) to tHueRgb
      set the blendLevel of graphic ("osdBeam" & tI) to 100 - round(tLevel * 34)
   end repeat
   -- the spotlight on the floor
   put kOsdFloorL + 60 + sSpotX * (kOsdFloorR - kOsdFloorL - 120) into tX
   put kOsdFloorT + 26 + sSpotY * (kOsdFloorB - kOsdFloorT - 52) into tY
   put round(110 * sSpotSize) into tW
   put round(38 * sSpotSize) into tH
   put osdHue(sSpotHue, 0.55, 1) into tHueRgb
   set the rect of graphic "osdSpotHalo" to round(tX - tW), round(tY - tH), round(tX + tW), round(tY + tH)
   set the backgroundColor of graphic "osdSpotHalo" to tHueRgb
   set the rect of graphic "osdSpot" to round(tX - tW / 2), round(tY - tH / 2), round(tX + tW / 2), round(tY + tH / 2)
   set the backgroundColor of graphic "osdSpot" to osdMix(tHueRgb, "255,255,255", 0.35)
   -- the mixer
   repeat with tI = 1 to kOsdFaders
      put kOsdMeterL + (tI - 1) * 12 into tX
      put round(kOsdMeterB - sMeter[tI] * (kOsdMeterB - kOsdMeterT)) into tY
      set the rect of graphic ("osdMeter" & tI) to tX, tY, tX + 8, kOsdMeterB
      put round(kOsdMeterB - sPeak[tI] * (kOsdMeterB - kOsdMeterT)) into tY
      set the rect of graphic ("osdPeak" & tI) to tX, tY - 1, tX + 8, tY + 1
   end repeat
   -- the surface: faders and the pad
   repeat with tI = 1 to kOsdFaders
      put kOsdFaderL + (tI - 1) * kOsdFaderDX into tX
      put round(kOsdFaderB - sFader[tI] * (kOsdFaderB - kOsdFaderT)) into tY
      set the rect of graphic ("osdFaderFill" & tI) to tX + 7, tY, tX + 11, kOsdFaderB
      set the rect of graphic ("osdFaderCap" & tI) to tX, tY - 7, tX + 18, tY + 7
   end repeat
   osdTrailPush
   repeat with tI = 1 to kOsdTrail
      put kOsdPadL + 10 + sTrailX[tI] * (kOsdPadS - 20) into tX
      put kOsdPadT + 10 + sTrailY[tI] * (kOsdPadS - 20) into tY
      put 9 - round(tI * 0.6) into tW
      set the rect of graphic ("osdTrail" & tI) to round(tX - tW / 2), round(tY - tW / 2), round(tX + tW / 2), round(tY + tW / 2)
   end repeat
   put kOsdPadL + 10 + sPuckX * (kOsdPadS - 20) into tX
   put kOsdPadT + 10 + sPuckY * (kOsdPadS - 20) into tY
   set the rect of graphic "osdPuck" to round(tX - 9), round(tY - 9), round(tX + 9), round(tY + 9)
   -- words
   osdSetText "osdSends", sSends
   if sWireMode is "table" then
      put empty into tText
      put the keys of sWireTable into tRows
      sort lines of tRows ascending text
      repeat for each line tRow in tRows
         set the itemDelimiter to "|"
         put tRow & "  " & item 1 of sWireTable[tRow] & "  " & item 2 of sWireTable[tRow] & return after tText
         set the itemDelimiter to comma
      end repeat
      osdSetText "osdWire", tText
   else
      osdSetText "osdWire", sWireLog
   end if
   osdSetText "osdStats", sSent & " sent   " & sRead & " read   " & sRefused & " refused   " & sRate & " a second"
   if sScene is 4 then
      osdRenderCue
   else if sScene is 5 then
      osdSetText "osdShield", sRefused & " of " & sBadSent & " bad datagrams refused" & return & sRead & " good messages read"
   end if
   unlock screen
end osdRender

command osdRenderCue
   local tLeft, tW, tFrac
   if the number of elements of sPending > 0 and sCueSpan > 0 then
      put max(0, min(1, (sCueDue - the milliseconds) / sCueSpan)) into tFrac
      osdSetText "osdCue", "cue " & quote & sCueText & quote & " is here and waits: due in " & format("%.1f", max(0, (sCueDue - the milliseconds) / 1000)) & " s"
   else
      put 0 into tFrac
      if sCueText is empty then
         osdSetText "osdCue", "waiting for the first cue"
      else
         osdSetText "osdCue", "cue " & quote & sCueText & quote & " is on"
      end if
   end if
   put the left of graphic "osdCueTrack" into tLeft
   put round((the width of graphic "osdCueTrack") * tFrac) into tW
   set the rect of graphic "osdCueBar" to tLeft, the top of graphic "osdCueTrack", tLeft + max(1, tW), the bottom of graphic "osdCueTrack"
end osdRenderCue

-- Only touch a field when its words change: a field redrawn thirty times a
-- second for nothing costs more than everything else in a frame
command osdSetText pField, pText
   if the text of field pField is not pText then
      set the text of field pField to pText
   end if
end osdSetText

command osdTrailPush
   local tI
   repeat with tI = kOsdTrail down to 2
      put sTrailX[tI - 1] into sTrailX[tI]
      put sTrailY[tI - 1] into sTrailY[tI]
   end repeat
   put sPuckX into sTrailX[1]
   put sPuckY into sTrailY[1]
end osdTrailPush

command osdResetRig
   local tI
   put empty into sPending
   put 0 into sPendingN
   put 0 into sSent
   put 0 into sArrived
   put 0 into sRefused
   put 0 into sRead
   put 0 into sBadSent
   put 0 into sRate
   put empty into sRateMark
   put empty into sWireLog
   put empty into sWireTable
   repeat with tI = 1 to kOsdFaders
      put 0 into sFader[tI]
      put 0 into sMeter[tI]
      put 0 into sPeak[tI]
   end repeat
   repeat with tI = 1 to kOsdLamps
      put 0.06 into sLamp[tI]
      put 32 into sLampHue[tI]
   end repeat
   repeat with tI = 1 to kOsdTrail
      put 0.5 into sTrailX[tI]
      put 0.5 into sTrailY[tI]
   end repeat
   put 0.5 into sPuckX
   put 0.5 into sPuckY
   put 0.5 into sSpotX
   put 0.5 into sSpotY
   put 1 into sSpotSize
   put 40 into sSpotHue
end osdResetRig

-- "r,g,b" between two colours, pT from 0 to 1
function osdMix pA, pB, pT
   local tI, tOut
   if pT is not a number then
      put 0 into pT
   end if
   put max(0, min(1, pT)) into pT
   repeat with tI = 1 to 3
      put round(item tI of pA + (item tI of pB - item tI of pA) * pT) & comma after tOut
   end repeat
   delete the last char of tOut
   return tOut
end osdMix

-- A hue (0 to 359) as "r,g,b", at a saturation and value from 0 to 1
function osdHue pHue, pSat, pVal
   local tH, tI, tF, tP, tQ, tT, tR, tG, tB
   if pHue is not a number then
      put 0 into pHue
   end if
   put (pHue mod 360) / 60 into tH
   put trunc(tH) into tI
   put tH - tI into tF
   put pVal * (1 - pSat) into tP
   put pVal * (1 - pSat * tF) into tQ
   put pVal * (1 - pSat * (1 - tF)) into tT
   switch tI
      case 0
         put pVal into tR
         put tT into tG
         put tP into tB
         break
      case 1
         put tQ into tR
         put pVal into tG
         put tP into tB
         break
      case 2
         put tP into tR
         put pVal into tG
         put tT into tB
         break
      case 3
         put tP into tR
         put tQ into tG
         put pVal into tB
         break
      case 4
         put tT into tR
         put tP into tG
         put pVal into tB
         break
      default
         put pVal into tR
         put tP into tG
         put tQ into tB
   end switch
   return round(tR * 255) & comma & round(tG * 255) & comma & round(tB * 255)
end osdHue

function osdFirstLine pText
   return line 1 of pText
end osdFirstLine

-- ===== What is missing, and how it went =====================================

command osdShowStatus
   local tText, tMissing
   if sTrouble is not empty then
      put "Something went wrong and the show stopped: " & osdFirstLine(sTrouble) & ". Close the stack and open it again." into tText
      put tText into tMissing
   else if sHaveOsc is not true then
      put "Missing: oscxt. " & sWhyNot & " Install it (Tools > Extension Manager) and open this stack again. The surface still moves, but nothing is sent." into tText
      put "This demo needs oscxt, the suite's Open Sound Control extension." & return & sWhyNot & return & "Install it, then open this stack again." into tMissing
   else if sNoNet is not empty then
      put "Missing: a UDP port. " & sNoNet & " Close the program that holds port 9000 and open this stack again." into tText
      put sNoNet into tMissing
   else
      put "Nothing to set up and no gear needed: the surface sends to this computer and the rig listens on UDP port " & sPort & ". Point TouchOSC at this computer, port " & sPort & ", to drive the rig yourself." into tText
   end if
   lock screen
   set the text of field "osdStatus" to tText
   if tMissing is empty then
      set the foregroundColor of field "osdStatus" to kOsdSoft
      set the visible of field "osdMissing" to false
   else
      set the foregroundColor of field "osdStatus" to kOsdAccent
      set the text of field "osdMissing" to tMissing
      set the visible of field "osdMissing" to true
   end if
   if sPort is empty then
      set the text of field "osdRigCap" to "THE RIG   draws only what arrives"
      set the text of field "osdSurfCap" to "THE SURFACE"
   else
      set the text of field "osdRigCap" to "THE RIG   listens on UDP port " & sPort & " and draws only what arrives"
      set the text of field "osdSurfCap" to "THE SURFACE   sends real OSC to " & sDest
   end if
   unlock screen
end osdShowStatus

command osdShowSwitches
   lock screen
   set the hilite of button "osdTour" to (sTour is true)
   set the hilite of button "osdPause" to (sPaused is true)
   unlock screen
end osdShowSwitches

-- ===== For the tests ========================================================

-- Take the clock out of the loop's hands: the test steps it
command osdTestBegin
   put false into sRunning
   add 1 to sGen
   put false into sTour
end osdTestBegin

-- Move the show on by pSeconds, a frame at a time, drawing each frame
command osdTestStep pSeconds
   local tSteps, tI
   put max(1, round(pSeconds * 1000 / kOsdFrameMs)) into tSteps
   repeat with tI = 1 to tSteps
      osdTick kOsdFrameMs / 1000
      osdRender
   end repeat
end osdTestStep

-- Where the surface's puck is now, "x,y"
function osdPuck
   return sPuckX & comma & sPuckY
end osdPuck

function osdState
   local tState, tI
   put sScene into tState["scene"]
   put sSceneT into tState["sceneTime"]
   put sFrames into tState["frames"]
   put sSent into tState["sent"]
   put sArrived into tState["arrived"]
   put sRead into tState["read"]
   put sRefused into tState["refused"]
   put sBadSent into tState["badSent"]
   put sStep into tState["step"]
   put sHaveOsc into tState["haveOsc"]
   put sWhyNot into tState["whyNot"]
   put sPort into tState["port"]
   put sNoNet into tState["noNet"]
   put sTrouble into tState["trouble"]
   put sRunning into tState["running"]
   put the number of elements of sPending into tState["pending"]
   put sCueText into tState["cue"]
   put sSpotX & comma & sSpotY & comma & sSpotSize & comma & sSpotHue into tState["spot"]
   repeat with tI = 1 to kOsdLamps
      put sLamp[tI] & comma after tState["lamps"]
      put sLampHue[tI] & comma after tState["lampHues"]
   end repeat
   repeat with tI = 1 to kOsdFaders
      put sMeter[tI] & comma after tState["meters"]
      put sFader[tI] & comma after tState["faders"]
   end repeat
   put sWireLog into tState["log"]
   put sSends into tState["sends"]
   return tState
end osdState

-- ===== Building the window ==================================================

command osdBuild
   local tI, tX, tY, tWasQuiet
   -- Built with messages locked. In the IDE every scripted create, rename
   -- and delete sends an engine message that runs the IDE's own script
   -- (the suite's engine note 5.15): built with them unlocked, this window
   -- held OXT-Beyond 0.2.8-dp.1's IDE on Windows for 42 seconds as it
   -- opened (2026-11-21). Nothing here asks a question or needs an engine
   -- message, and the caller's lock is given back at the end.
   put the lockMessages into tWasQuiet
   lock screen
   lock messages
   osdClear
   set the width of this stack to kOsdW
   set the height of this stack to kOsdH
   -- Then centred on the screen. A new stack is 32,32,288,288 and a size
   -- set keeps its centre (engine note 5.18), so 1100 wide put its left at
   -- -390: the window opened 390 pixels past the screen's edge on Windows
   -- (the same day). start-here centres a window it opens; one opened any
   -- other way now centres itself.
   set the loc of this stack to the screenLoc
   set the resizable of this stack to false
   set the label of this stack to "OSC Show Surface - OXT-Beyond"
   set the backgroundColor of this stack to kOsdPage
   set the foregroundColor of this stack to kOsdInk
   set the textSize of this stack to 13
   set the backgroundColor of this card to kOsdPage
   set the foregroundColor of this card to kOsdInk

   -- the header: OXT-Beyond, the demo's name, what it does, who made it
   osdLabel "osdBrand", "OXT-BEYOND", 11, kOsdAccent, "bold", 20, 6, 400, 27
   osdLabel "osdTitle", "OSC Show Surface", 22, kOsdInk, "bold", 20, 22, 560, 59
   osdLabel "osdSub", "Open Sound Control from xTalk with oscxt: a surface and a show rig talking real OSC over UDP, every message read back.", 12, kOsdSoft, "plain", 20, 56, 900, 78
   osdLabel "osdByline", "by Seth Morrow", 12, kOsdSoft, "plain", 880, 30, kOsdSideR, 52
   set the textAlign of field "osdByline" to "right"

   -- the stage: the rig above, the surface below
   osdRect "osdStage", kOsdPanel, kOsdStageL, kOsdStageT, kOsdStageR, kOsdStageB
   osdLabel "osdRigCap", "THE RIG", 11, kOsdAccent, "bold", 30, 86, 680, 107
   osdRect "osdFloor", kOsdWell, kOsdFloorL, kOsdFloorT, kOsdFloorR, kOsdFloorB
   osdLabel "osdFloorCap", "/stage/spot", 10, kOsdSoft, "plain", kOsdFloorL + 6, kOsdFloorB - 21, kOsdFloorL + 200, kOsdFloorB - 2
   -- beams first, so the lamps and the spot draw over them
   repeat with tI = 1 to kOsdLamps
      put kOsdLampX0 + (tI - 1) * kOsdLampDX into tX
      osdBeam "osdBeam" & tI, tX
   end repeat
   osdOval "osdSpotHalo", kOsdAccent, 0, 0, 10, 10
   set the blendLevel of graphic "osdSpotHalo" to 78
   osdOval "osdSpot", kOsdInk, 0, 0, 10, 10
   set the blendLevel of graphic "osdSpot" to 25
   repeat with tI = 1 to kOsdLamps
      put kOsdLampX0 + (tI - 1) * kOsdLampDX into tX
      osdOval "osdLampHalo" & tI, kOsdAccent, tX - 23, kOsdLampY - 23, tX + 23, kOsdLampY + 23
      set the blendLevel of graphic ("osdLampHalo" & tI) to 100
      osdOval "osdLampCore" & tI, kOsdLampOff, tX - 12, kOsdLampY - 12, tX + 12, kOsdLampY + 12
      osdLabel "osdLampTag" & tI, "/lamp/" & tI, 9, kOsdSoft, "plain", tX - 27, 106, tX + 27, 124
      set the textAlign of field ("osdLampTag" & tI) to "center"
   end repeat
   -- the mixer
   osdLabel "osdMixCap", "MIXER", 10, kOsdSoft, "bold", kOsdMeterL - 4, 116, kOsdStageR - 6, 135
   repeat with tI = 1 to kOsdFaders
      put kOsdMeterL + (tI - 1) * 12 into tX
      osdRect "osdMeterTrack" & tI, kOsdWell, tX, kOsdMeterT, tX + 8, kOsdMeterB
      osdRect "osdMeter" & tI, "92,214,150", tX, kOsdMeterB - 1, tX + 8, kOsdMeterB
      osdRect "osdPeak" & tI, kOsdInk, tX, kOsdMeterB - 2, tX + 8, kOsdMeterB
   end repeat
   osdLabel "osdMixTag", "/mixer/n", 9, kOsdSoft, "plain", kOsdMeterL - 4, kOsdMeterB + 2, kOsdStageR - 2, kOsdMeterB + 20
   -- what a cue and a refusal look like, over the floor
   osdLabel "osdCue", empty, 12, kOsdInk, "bold", kOsdFloorL + 200, kOsdFloorT + 6, kOsdFloorR - 10, kOsdFloorT + 28
   set the textAlign of field "osdCue" to "right"
   osdRect "osdCueTrack", kOsdButton, kOsdFloorR - 210, kOsdFloorT + 32, kOsdFloorR - 10, kOsdFloorT + 38
   osdRect "osdCueBar", kOsdAccent, kOsdFloorR - 210, kOsdFloorT + 32, kOsdFloorR - 209, kOsdFloorT + 38
   osdText "osdShield", empty, 13, kOsdInk, kOsdFloorR - 330, kOsdFloorT + 6, kOsdFloorR - 10, kOsdFloorT + 56
   set the textAlign of field "osdShield" to "right"
   set the textStyle of field "osdShield" to "bold"
   osdText "osdMissing", empty, 14, kOsdInk, kOsdFloorL + 60, kOsdFloorT + 36, kOsdFloorR - 60, kOsdFloorB - 24
   set the textAlign of field "osdMissing" to "center"
   set the visible of field "osdMissing" to false

   -- the surface
   osdRect "osdSplit", kOsdLine, kOsdStageL + 14, 360, kOsdStageR - 14, 361
   osdLabel "osdSurfCap", "THE SURFACE", 11, kOsdAccent, "bold", 30, 368, 760, 389
   repeat with tI = 1 to kOsdFaders
      put kOsdFaderL + (tI - 1) * kOsdFaderDX into tX
      osdRect "osdFaderTrack" & tI, kOsdLine, tX + 7, kOsdFaderT, tX + 11, kOsdFaderB
      osdRect "osdFaderFill" & tI, kOsdAccent, tX + 7, kOsdFaderB - 1, tX + 11, kOsdFaderB
      osdRoundRect "osdFaderCap" & tI, kOsdInk, tX, kOsdFaderB - 7, tX + 18, kOsdFaderB + 7
      osdLabel "osdFaderTag" & tI, tI, 9, kOsdSoft, "plain", tX - 2, kOsdFaderB + 10, tX + 20, kOsdFaderB + 28
      set the textAlign of field ("osdFaderTag" & tI) to "center"
   end repeat
   osdRect "osdPad", kOsdWell, kOsdPadL, kOsdPadT, kOsdPadL + kOsdPadS, kOsdPadT + kOsdPadS
   osdRect "osdPadH", kOsdLine, kOsdPadL + 8, kOsdPadT + kOsdPadS div 2, kOsdPadL + kOsdPadS - 8, kOsdPadT + kOsdPadS div 2 + 1
   osdRect "osdPadV", kOsdLine, kOsdPadL + kOsdPadS div 2, kOsdPadT + 8, kOsdPadL + kOsdPadS div 2 + 1, kOsdPadT + kOsdPadS - 8
   repeat with tI = kOsdTrail down to 1
      osdOval "osdTrail" & tI, kOsdAccent, 0, 0, 4, 4
      set the blendLevel of graphic ("osdTrail" & tI) to 30 + tI * 8
   end repeat
   osdOval "osdPuck", kOsdAccent, 0, 0, 18, 18
   osdLabel "osdPadTag", "/stage/spot", 9, kOsdSoft, "plain", kOsdPadL, kOsdPadT + kOsdPadS + 2, kOsdPadL + kOsdPadS, kOsdPadT + kOsdPadS + 20
   osdText "osdSends", empty, 12, kOsdInk, 420, 394, 768, 556
   set the textFont of field "osdSends" to osdMonoFont()
   osdWell "osdSends"
   osdLabel "osdSendsTag", "what the surface just sent", 9, kOsdSoft, "plain", 420, 558, 768, 576

   -- the side: scenes, switches, what this shows, the wire, the counts
   osdLabel "osdScenesCap", "SCENES", 11, kOsdAccent, "bold", kOsdSideL, 82, kOsdSideR, 103
   repeat with tI = 1 to kOsdScenes
      put 106 + (tI - 1) * 30 into tY
      osdButton "osdScene" & tI, tI & ".  " & item tI of kOsdSceneNames, kOsdSideL, tY, kOsdSideR, tY + 26
   end repeat
   osdButton "osdTour", "Play them all", kOsdSideL, 258, kOsdSideL + 140, 282
   osdButton "osdPause", "Pause", kOsdSideL + 148, 258, kOsdSideR, 282
   osdLabel "osdAboutCap", "WHAT THIS SHOWS", 11, kOsdAccent, "bold", kOsdSideL, 288, kOsdSideR, 309
   osdText "osdAbout", empty, 12, kOsdInk, kOsdSideL, 310, kOsdSideR, 424
   osdLabel "osdWireCap", "ON THE WIRE   what oscParse read", 11, kOsdAccent, "bold", kOsdSideL, 426, kOsdSideR, 447
   osdText "osdWire", empty, 10, kOsdInk, kOsdSideL, 448, kOsdSideR, 560
   set the textFont of field "osdWire" to osdMonoFont()
   set the dontWrap of field "osdWire" to true
   osdWell "osdWire"
   osdLabel "osdStats", empty, 10, kOsdSoft, "plain", kOsdSideL, 563, kOsdSideR, 582

   -- the footer: what is missing, or that nothing is
   osdLabel "osdStatus", empty, 11, kOsdSoft, "plain", kOsdStageL, 593, kOsdSideR, 614
   osdShowSwitches
   set the lockMessages to tWasQuiet
   unlock screen
end osdBuild

-- Remove what an earlier build made (and only that): every control this
-- stack makes is named osd...
command osdClear
   local tI
   repeat with tI = the number of controls of this card down to 1
      if the short name of control tI of this card begins with "osd" then
         delete control tI of this card
      end if
   end repeat
end osdClear

function osdMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end osdMonoFont

-- One line of words nobody types into
command osdLabel pName, pText, pSize, pColor, pStyle, pL, pT, pR, pB
   create field pName
   osdQuiet pName, pSize, pColor
   set the dontWrap of field pName to true
   set the textStyle of field pName to pStyle
   set the rect of field pName to pL, pT, pR, pB
   set the text of field pName to pText
end osdLabel

-- Words that wrap
command osdText pName, pText, pSize, pColor, pL, pT, pR, pB
   create field pName
   osdQuiet pName, pSize, pColor
   set the dontWrap of field pName to false
   set the rect of field pName to pL, pT, pR, pB
   set the text of field pName to pText
end osdText

-- Lines tall enough for any system's font: left alone, a line is as tall
-- as the font the stack was BUILT with wants, and on Windows the tops of
-- the capitals were cut off (the Render3D Tour, 2026-11-21). Every colour
-- is the field's own, so a dark system theme changes nothing.
command osdQuiet pName, pSize, pColor
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the opaque of field pName to false
   set the showBorder of field pName to false
   set the threeD of field pName to false
   set the borderWidth of field pName to 0
   set the margins of field pName to 2
   set the vScrollbar of field pName to false
   set the hScrollbar of field pName to false
   set the autoHilite of field pName to false
   set the listBehavior of field pName to false
   set the textSize of field pName to pSize
   set the fixedLineHeight of field pName to true
   set the textHeight of field pName to round(pSize * 1.5)
   set the foregroundColor of field pName to pColor
   set the backgroundColor of field pName to kOsdPage
   set the hiliteColor of field pName to kOsdButton
   set the borderColor of field pName to kOsdLine
end osdQuiet

-- A sunken panel for a field of mono text
command osdWell pName
   set the opaque of field pName to true
   set the backgroundColor of field pName to kOsdWell
   set the margins of field pName to 8
end osdWell

-- A flat button: the Render3D Tour's. Lit (hilited) means on or chosen.
command osdButton pName, pLabel, pL, pT, pR, pB
   create button pName
   set the label of button pName to pLabel
   set the style of button pName to "roundrect"
   set the opaque of button pName to true
   set the showBorder of button pName to false
   set the threeD of button pName to false
   set the shadow of button pName to false
   set the traversalOn of button pName to false
   set the autoHilite of button pName to false
   set the textSize of button pName to 12
   set the backgroundColor of button pName to kOsdButton
   set the foregroundColor of button pName to kOsdInk
   set the hiliteColor of button pName to kOsdAccent
   set the borderColor of button pName to kOsdLine
   set the rect of button pName to pL, pT, pR, pB
end osdButton

command osdRect pName, pColor, pL, pT, pR, pB
   create graphic pName
   set the style of graphic pName to "rectangle"
   osdFill pName, pColor
   set the rect of graphic pName to pL, pT, pR, pB
end osdRect

command osdRoundRect pName, pColor, pL, pT, pR, pB
   create graphic pName
   set the style of graphic pName to "roundrect"
   set the roundRadius of graphic pName to 4
   osdFill pName, pColor
   set the rect of graphic pName to pL, pT, pR, pB
end osdRoundRect

command osdOval pName, pColor, pL, pT, pR, pB
   create graphic pName
   set the style of graphic pName to "oval"
   osdFill pName, pColor
   set the rect of graphic pName to pL, pT, pR, pB
end osdOval

-- A lamp's beam: a cone from the lamp to the floor's far edge
command osdBeam pName, pX
   local tPoints
   create graphic pName
   set the style of graphic pName to "polygon"
   osdFill pName, kOsdAccent
   put (pX - 7) & comma & (kOsdLampY + 8) & return & (pX + 7) & comma & (kOsdLampY + 8) & return & (pX + 30) & comma & kOsdFloorB & return & (pX - 30) & comma & kOsdFloorB & return & (pX - 7) & comma & (kOsdLampY + 8) into tPoints
   set the points of graphic pName to tPoints
   set the blendLevel of graphic pName to 100
end osdBeam

command osdFill pName, pColor
   set the opaque of graphic pName to true
   set the lineSize of graphic pName to 0
   set the backgroundColor of graphic pName to pColor
   set the foregroundColor of graphic pName to pColor
   set the lockLocation of graphic pName to true
end osdFill
