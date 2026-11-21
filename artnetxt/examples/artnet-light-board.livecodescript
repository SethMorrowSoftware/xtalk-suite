script "Art-Net Light Board"

-- artnet-light-board.livecodescript - artnetxt's showcase, by Seth Morrow.
--
-- A lighting BOARD and a lighting RIG in one window, talking Art-Net (DMX
-- lighting levels over a network) the way a desk and a node do. The board
-- sets the 512 channels of universe 0 and sends them as one ArtDmx packet,
-- thirty times a second, to 127.0.0.1; the rig is a virtual Art-Net node
-- that accepts datagrams on UDP port 6454, reads each packet back with
-- artnetParseDmx, and lights eight PAR cans and two moving heads from the
-- levels that arrived, and from nothing else. So the picture is the proof:
-- if the rig follows the board, the bytes went out, came back and were read.
--
-- It opens straight into motion and plays five scenes, one capability each:
--   1. Colour wash     four channels a PAR: dimmer, red, green, blue
--   2. Chase           levels changing in order, the heads following
--   3. Moving heads    six channels a head: pan and tilt move the beams
--   4. Whole universe  all 512 channels moving at once, each one shown
--   5. Find nodes      ArtPoll and ArtPollReply; bytes that are not for it
-- A scene button jumps to its scene; "Play them all" goes round them;
-- "Pause" stops the board, and the rig keeps what it last read.
--
-- HOW TO OPEN: start-here.livecodescript's Open button (it does the next
-- three steps for you), or paste THIS whole file into a new stack's STACK
-- script, Apply, then close the stack and open it again. Opening the file
-- itself loads the script and builds no window (the suite's engine notes,
-- 5.5). It needs the artnetxt extension installed; without it the window
-- still opens and says what is missing. artnet-helpers (scArtnetSetChannel,
-- scArtnetSend, scArtnetPoll, scLooksLikeArtnet) is embedded below, so there
-- is nothing else to load.
--
-- THE NETWORK: everything it SENDS goes to 127.0.0.1, this computer, and
-- nothing else; the rig answers an ArtPoll only from this computer. The rig
-- listens on UDP port 6454, the Art-Net port (the next free one up to 6464
-- when another Art-Net program holds it), so a lighting desk on your network
-- can drive it too: press Pause, and send universe 0 to this computer. To
-- drive a REAL node as well, put its address in kAlbAlsoTo below (for
-- example "192.168.1.50") and open the stack again: every frame of universe
-- 0 then goes there too, and only there. It never broadcasts. Windows may ask
-- whether OXT may use the network; the demo works either way, because it
-- only talks to itself. Nothing flashes fast: every change is a fade.
--
-- THE LOOK is OXT-Beyond's dark stage (the Render3D Tour's palette), not the
-- suite's light UI kit, by request (2026-11-21), so this stack is in
-- tools/check-ui-kit-drift.py's EXEMPT list. Every field and button sets its
-- own text colour, because OXT-Beyond gives a control without one white
-- text under a dark system theme, and every switch is a button, not a tick
-- box, which the system draws in its own colours.
--
-- FOR THE TESTS (tests/lcs/demo_test.livecodescript): albTestBegin stops
-- the clock's loop, albTestStep moves the show on by so many seconds and
-- draws, albGo jumps to a scene, albState() says how things are and
-- albPollReply() is the rig's answer to an ArtPoll, as bytes.
--
-- HONESTY (the suite convention): it built, ran every scene and passed its
-- loopback in OXT-Beyond's standalone engine (9.7.1-OXT, Linux x86_64,
-- headless with -ui) on 2026-11-21. Nobody has looked at its window on a
-- desktop yet: the look, the motion and the feel are verified statically;
-- need an OXT pass. No hardware node has met it.

-- ===== Sizes and the look ===================================================


-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- artnetxt/examples/artnet-helpers.livecodescript ----
-- artnet-helpers.livecodescript
-- ---------------------------------------------------------------------------
-- Reusable LiveCode Script helpers for the artnetxt extension (Art-Net: DMX
-- lighting levels over a network). Paste this into a stack or card script (or
-- a library stack you `start using`). To set lights:
--
--     local tLevels
--     scArtnetSetChannel tLevels, 1, 255          -- channel 1 at full
--     scArtnetSetChannel tLevels, 4, 128          -- channel 4 at half
--     scArtnetSend "192.168.1.50", 0, tLevels     -- universe 0 of that node
--
-- and to listen (levels from another controller, and node discovery):
--
--     accept datagram connections on port 6454 with message "scArtnetReceived"
--     on scArtnetDmx pUniverse, pChannels, pSender ... end scArtnetDmx
--     on scArtnetNodeFound pNode, pSender ... end scArtnetNodeFound
--     scArtnetPoll                                -- ask every node to answer
--
-- scArtnetSend, artnetSendDmx and scArtnetOneChannel are the Art-Net part of
-- ShowControl's showcontrol-helpers.livecodescript, under the same names; a
-- script that pasted the old combined file keeps working. Pasting this beside
-- oscxt's osc-helpers and midixt's midi-helpers defines no name twice (the
-- suite's tools/check-cross-library-names.py holds it). What changed from
-- ShowControl's, on purpose:
--   * A level is rounded and kept to 0..255. numToByte WRAPS, and rounds a
--     fraction or cuts it by where the value came from (the suite's engine
--     note 2.13), so ShowControl's scArtnetOneChannel sent a computed 255.6,
--     or 256, as level 0 (a light at full went dark), and 127.5 as 127 or
--     128 by how its caller had written it.
--   * A channel outside 1..512 is an error (it throws), where ShowControl's
--     built a frame past the 512 a universe holds, which the extension then
--     cut to 512 zeros: every light in the universe went dark.
--   * A send that cannot be built sends nothing, and the result says why;
--     ShowControl's wrote an empty datagram.
--   * A host may say its port ("192.168.1.50:6455", a node on another port,
--     or tools/sim/artnet_node.py on a test port); a plain host still goes
--     to 6454. ShowControl's always appended ":6454", which made a
--     "host:port" into "host:port:6454".
--   * The socket is opened by scArtnetEnsureSocket, this file's own name,
--     not osc-helpers' scEnsureDatagramSocket, so either file pastes alone.
--   * New: scArtnetSetChannel, scArtnetChannel, scArtnetPoll,
--     scArtnetReceived and scLooksLikeArtnet.
-- ---------------------------------------------------------------------------

-- ===== UDP transport ========================================================

-- Make sure a datagram socket to "host:port" is open before writing to it. The
-- engine only writes to an OPEN socket: `write ... to socket "h:p"` on a name
-- that was never opened sets the result to "socket is not open" and sends
-- NOTHING, silently (engine/src/exec-network.cpp, MCNetworkExecWriteToSocket).
-- Opening is idempotent here, so call it before every send.
command scArtnetEnsureSocket pHostPort
   if pHostPort is not among the lines of the openSockets then
      open datagram socket to pHostPort
   end if
end scArtnetEnsureSocket

-- ===== Building levels =======================================================

-- One level as the byte DMX sends: a number rounded and kept to 0..255.
-- (numToByte alone wraps, 256 becoming 0, and rounds or cuts a fraction by
-- where it came from: engine note 2.13. `round` reads it the same from all.)
private function scArtnetLevelByte pLevel, pWho
   if pLevel is not a number then
      throw pWho & ": a level must be a number from 0 to 255, not" && pLevel
   end if
   return numToByte(max(0, min(255, round(pLevel))))
end scArtnetLevelByte

-- A channel number must be a whole number from 1 to 512: a universe holds 512.
private command scArtnetCheckChannel pChannel, pWho
   if pChannel is not an integer then
      throw pWho & ": a channel must be a whole number from 1 to 512, not" && pChannel
   end if
   if pChannel < 1 or pChannel > 512 then
      throw pWho & ": a channel must be from 1 to 512, not" && pChannel
   end if
end scArtnetCheckChannel

-- Set one channel's level in a frame of levels (a variable, passed by
-- reference), adding channels at level 0 up to it when the frame is shorter.
--   local tLevels
--   scArtnetSetChannel tLevels, 3, 200     -- tLevels is now 0, 0, 200
command scArtnetSetChannel @pChannels, pChannel, pLevel
   local tByte
   scArtnetCheckChannel pChannel, "scArtnetSetChannel"
   put scArtnetLevelByte(pLevel, "scArtnetSetChannel") into tByte
   repeat while (the number of bytes in pChannels) < pChannel - 1
      put numToByte(0) after pChannels
   end repeat
   if (the number of bytes in pChannels) < pChannel then
      put tByte after pChannels
   else
      put tByte into byte pChannel of pChannels
   end if
end scArtnetSetChannel

-- The level (0..255) of one channel of a frame; 0 for a channel past its end.
function scArtnetChannel pChannels, pChannel
   scArtnetCheckChannel pChannel, "scArtnetChannel"
   if pChannel > (the number of bytes in pChannels) then
      return 0
   end if
   return byteToNum(byte pChannel of pChannels)
end scArtnetChannel

-- Build a single-channel DMX frame (1-based channel, 0..255 level) - handy for
-- driving one dimmer from a fader without assembling 512 bytes by hand. Every
-- channel before it is 0.
function scArtnetOneChannel pChannel, pLevel
   local tChannels
   scArtnetCheckChannel pChannel, "scArtnetOneChannel"
   put empty into tChannels
   scArtnetSetChannel tChannels, pChannel, pLevel
   return tChannels
end scArtnetOneChannel

-- ===== Sending ===============================================================

-- "host" -> "host:6454", the Art-Net port; a "host:port" is kept as given (a
-- node on another port, or tools/sim/artnet_node.py on a test port).
private function scArtnetHostPort pHost
   if pHost contains ":" then
      return pHost
   end if
   return pHost & ":6454"
end scArtnetHostPort

-- Send a DMX universe (pChannels: up to 512 levels, one byte each) to an
-- Art-Net node at pHost (port 6454 unless pHost says "host:port"). When the
-- frame cannot be built (a universe outside 0..32767) nothing is sent and the
-- result says why; otherwise the result is the write's (empty when it went).
on scArtnetSend pHost, pUniverse, pChannels
   local tPacket, tHostPort
   put artnetBuildDmx(pUniverse, pChannels) into tPacket
   if tPacket is empty then
      return artnetLastError()
   end if
   put scArtnetHostPort(pHost) into tHostPort
   scArtnetEnsureSocket tHostPort
   write tPacket to socket tHostPort
   return the result
end scArtnetSend

-- ShowControl's "optional convenience" verb, the arguments in the order its
-- API reference gave them: scArtnetSend with the host last.
on artnetSendDmx pUniverse, pChannels, pHost
   scArtnetSend pHost, pUniverse, pChannels
   return the result
end artnetSendDmx

-- Ask Art-Net nodes to say who they are. With no host, the ArtPoll goes to
-- every computer on the network (255.255.255.255), which needs the engine's
-- allowDatagramBroadcasts, so this sets it to true; a host ending in .255 is a
-- broadcast too. Nodes answer to port 6454 of this computer: listen there
-- first (accept datagram connections on port 6454 with message
-- "scArtnetReceived"), and each answer arrives as scArtnetNodeFound.
on scArtnetPoll pHost
   local tHostPort, tBroadcast
   if pHost is empty then
      put "255.255.255.255" into pHost
   end if
   put scArtnetHostPort(pHost) into tHostPort
   set the itemDelimiter to ":"
   put item 1 of tHostPort into pHost
   set the itemDelimiter to "."
   put (the last item of pHost is "255") into tBroadcast
   set the itemDelimiter to comma
   if tBroadcast then
      set the allowDatagramBroadcasts to true
   end if
   scArtnetEnsureSocket tHostPort
   write artnetBuildPoll() to socket tHostPort
   return the result
end scArtnetPoll

-- ===== Receiving =============================================================

-- Route inbound Art-Net. Wire it up with
--     accept datagram connections on port 6454 with message "scArtnetReceived"
-- and write your own handlers for what you want to hear:
--     on scArtnetDmx pUniverse, pChannels, pSender     (levels: one byte each)
--     on scArtnetNodeFound pNode, pSender              (pNode: artnetParseReply's array)
-- Anything else (an ArtPoll, your own broadcast coming back, an OpCode this
-- extension does not read, bytes that are not Art-Net) is ignored.
-- The engine calls a datagram message with (sender "host:port", data, socket),
-- in that order (engine/src/opensslsocket.cpp, MCSocket::readsome).
on scArtnetReceived pSender, pData, pSocket
   local tFrame, tNode, tTarget
   if not scLooksLikeArtnet(pData) then
      exit scArtnetReceived
   end if
   put the long id of the target into tTarget
   put artnetParseDmx(pData) into tFrame
   if tFrame["opcode"] is "ArtDmx" then
      dispatch "scArtnetDmx" to tTarget with tFrame["universe"], tFrame["channels"], pSender
      exit scArtnetReceived
   end if
   put artnetParseReply(pData) into tNode
   if tNode["opcode"] is "ArtPollReply" then
      dispatch "scArtnetNodeFound" to tTarget with tNode, pSender
   end if
end scArtnetReceived

-- Does this value look like an Art-Net packet ("Art-Net", a NUL, an OpCode)?
function scLooksLikeArtnet pX
   if (the number of bytes in pX) < 10 then
      return false
   end if
   return (byte 1 to 8 of pX) is ("Art-Net" & numToByte(0))
end scLooksLikeArtnet

-- <<< END EMBEDDED LIBRARIES <<<

constant kAlbW = 1100
constant kAlbH = 620
constant kAlbFrameMs = 33          -- about thirty frames a second, as desks send
constant kAlbPortFirst = 6454      -- the Art-Net port
constant kAlbPortLast = 6464
constant kAlbHost = "127.0.0.1"
constant kAlbUniverse = 0
-- A real node to drive as well, by its address ("192.168.1.50", or with a
-- port, "192.168.1.50:6454"). Empty: nothing leaves this computer.
constant kAlbAlsoTo = ""
constant kAlbChannels = 512
constant kAlbPars = 8
constant kAlbFixtures = 10
constant kAlbHeadBase = 32         -- head 1 is channels 33 to 38, head 2 39 to 44
constant kAlbScenes = 5
constant kAlbSceneNames = "Colour wash,Chase,Moving heads,Whole universe,Find nodes"
constant kAlbSceneSecs = "10,10,12,12,12"
constant kAlbWireLines = 6
constant kAlbShades = 12
constant kAlbCols = 32
constant kAlbRows = 16

-- OXT-Beyond's dark stage: the Render3D Tour's colours, as r,g,b so the
-- picture can mix them
constant kAlbPage = "18,21,31"
constant kAlbPanel = "28,33,48"
constant kAlbWell = "12,15,23"
constant kAlbInk = "238,241,247"
constant kAlbSoft = "169,178,199"
constant kAlbAccent = "255,138,61"
constant kAlbButton = "42,49,70"
constant kAlbLine = "58,66,92"
constant kAlbLampOff = "44,49,66"
constant kAlbCellOff = "30,35,50"

-- The geometry, in one place
constant kAlbStageL = 16
constant kAlbStageT = 84
constant kAlbStageR = 780
constant kAlbStageB = 588
constant kAlbFloorL = 30
constant kAlbFloorT = 178
constant kAlbFloorR = 520
constant kAlbFloorB = 350
constant kAlbTrussY = 126
constant kAlbLampY = 148
constant kAlbFixX0 = 54
constant kAlbFixDX = 48
constant kAlbGridL = 541
constant kAlbGridT = 114
constant kAlbCellW = 7
constant kAlbCellH = 8
constant kAlbFaderL = 44
constant kAlbFaderDX = 26
constant kAlbFaderT = 400
constant kAlbFaderB = 540
constant kAlbPadL = 314
constant kAlbPadT = 396
constant kAlbPadS = 156
constant kAlbSideL = 796
constant kAlbSideR = 1084

-- The rig's own name, as its ArtPollReply gives it
constant kAlbNodeShort = "OXT Rig"
constant kAlbNodeLong = "OXT-Beyond virtual rig (Art-Net Light Board)"
constant kAlbNodeMac = "2,79,88,84,0,1"     -- 02:4f:58:54:00:01, "OXT", locally made

-- ===== State =================================================================

local sMyStack            -- the stack's short name: every delayed message pins it
local sRunning, sGen      -- the loop runs; its generation (a stale tick dies)
local sClockMs            -- the milliseconds at the last frame
local sFrames             -- pictures drawn since the stack opened
local sScene, sSceneT     -- the scene playing, and the seconds it has played
local sNextAt, sStep      -- a scene's own schedule
local sTour, sPaused
local sHaveArt, sWhyNot   -- artnetxt answers; why not, when it does not
local sPort, sDest        -- the rig's UDP port; "127.0.0.1:<port>"
local sPeers              -- each sender the rig heard, a key (engine note 6.20)
local sNoNet              -- why the rig cannot listen, when it cannot
local sAlso, sAlsoWhy     -- the real node to drive too ("host:port"); why not
local sTrouble            -- an error the loop caught
-- the board: what the script sets
local sFrame              -- the 512 levels it sends, one byte each
local sOut                -- the same levels, 0 to 1, for the board's picture
local sLastPacket, sPacketView
-- the rig: only what arrived
local sGot                 -- the 512 levels the node read, 0 to 255
local sShade, sShadeRgb, sCellId
local sNodeCard, sPollCard, sPolls
-- what the board found
local sFound, sFoundCard
-- the wire
local sSent, sArrived, sRead, sIgnored, sAlsoSent
local sRateMark, sRateBase, sRate
local sWireLog

-- ===== The stack's own messages =============================================

on preOpenStack
   put the short name of this stack into sMyStack
   albBuild
end preOpenStack

on openStack
   albStart
end openStack

on closeStack
   albStop
end closeStack

on mouseUp
   local tName
   put the short name of the target into tName
   if tName begins with "albScene" and char 9 to -1 of tName is an integer then
      albGo char 9 to -1 of tName
   else if tName is "albTour" then
      put (sTour is not true) into sTour
      albShowSwitches
   else if tName is "albPause" then
      put (sPaused is not true) into sPaused
      albShowSwitches
   else
      pass mouseUp
   end if
end mouseUp

-- ===== Starting and stopping ================================================

command albStart
   if sMyStack is empty then
      put the short name of this stack into sMyStack
   end if
   if there is not a graphic "albStage" then
      albBuild
   end if
   albStop
   albResetRig
   put true into sTour
   put false into sPaused
   put empty into sTrouble
   put 0 into sFrames
   albProbe
   albListen
   albAlsoTo
   albShowStatus
   albShowSwitches
   albGo 1
   put true into sRunning
   add 1 to sGen
   put the milliseconds into sClockMs
   albFrame sGen
end albStart

command albStop
   local tOpen, tPeer
   put false into sRunning
   add 1 to sGen
   -- the senders the rig heard first, while the descriptor they share is open
   put the openSockets into tOpen
   repeat for each key tPeer in sPeers
      if tPeer is empty or tPeer is sDest or tPeer is sAlso then
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
   if sAlso is not empty and sAlso is among the lines of the openSockets then
      close socket sAlso
   end if
   put empty into sPort
   put empty into sDest
   put empty into sAlso
end albStop

-- Is artnetxt here? It is pure LiveCode Builder, so "here" means its module
-- is loaded: the first call of a handler nobody defines throws.
command albProbe
   local tErr, tPoll
   put false into sHaveArt
   put empty into sWhyNot
   try
      put artnetBuildPoll() into tPoll
      put (the number of bytes in tPoll is 14) into sHaveArt
      if not sHaveArt then
         put "artnetxt answered, but its ArtPoll is " & the number of bytes in tPoll & " bytes, not the 14 this demo is written for." into sWhyNot
      end if
   catch tErr
      put "artnetxt is not loaded in this OXT: nothing answered artnetBuildPoll()." into sWhyNot
   end try
end albProbe

-- The rig listens on 6454, or the next free port up to 6464. A port that will
-- not open says so only in the result (the suite's engine notes, 6.12).
command albListen
   local tPort
   put empty into sPort
   put empty into sDest
   put empty into sNoNet
   repeat with tPort = kAlbPortFirst to kAlbPortLast
      accept datagram connections on port tPort with message "albReceived"
      if the result is empty then
         put tPort into sPort
         exit repeat
      end if
   end repeat
   if sPort is empty then
      put "No UDP port from " & kAlbPortFirst & " to " & kAlbPortLast & " would open here, so the rig cannot listen." into sNoNet
      exit albListen
   end if
   put kAlbHost & ":" & sPort into sDest
   scArtnetEnsureSocket sDest
end albListen

-- kAlbAlsoTo, checked: one IPv4 address that is not a broadcast. Anything
-- else sends nothing, and the status line says why.
command albAlsoTo
   local tHost, tPort, tPart, tOk
   put empty into sAlso
   put empty into sAlsoWhy
   if kAlbAlsoTo is empty then
      exit albAlsoTo
   end if
   put kAlbAlsoTo into tHost
   put 6454 into tPort
   set the itemDelimiter to ":"
   if the number of items of tHost is 2 then
      put item 2 of tHost into tPort
      put item 1 of tHost into tHost
   end if
   set the itemDelimiter to "."
   put (the number of items of tHost is 4) and tPort is an integer and tPort > 0 and tPort < 65536 into tOk
   repeat for each item tPart in tHost
      if tPart is not an integer or tPart < 0 or tPart > 255 then
         put false into tOk
      end if
   end repeat
   if tOk and (item 4 of tHost is 255 or item 1 of tHost is 0) then
      put false into tOk
   end if
   set the itemDelimiter to comma
   if not tOk then
      put "kAlbAlsoTo (" & kAlbAlsoTo & ") is not one node's IPv4 address, so nothing goes there. This demo never broadcasts." into sAlsoWhy
      exit albAlsoTo
   end if
   put tHost & ":" & tPort into sAlso
end albAlsoTo

-- ===== The loop =============================================================

on albFrame pGen
   local tNow, tDt, tErr
   if pGen is not sGen or sRunning is not true then
      exit albFrame
   end if
   if sMyStack is not empty then
      -- A closed window stops its own show. closeStack stops it, but a
      -- close made with messages locked sends none, and the IDE keeps a
      -- closed stack in memory, where this loop would run on unseen with
      -- its sockets open (after each close in OXT-Beyond 0.2.8-dp.1's IDE on
      -- Windows a frame was still queued, 2026-11-21). An invisible window
      -- is open: only a closed stack is mode 0.
      if the mode of stack sMyStack is 0 then
         albStop
         exit albFrame
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
         albTick tDt
      end if
      albRender
   catch tErr
      put tErr into sTrouble
      put false into sRunning
      albShowStatus
      exit albFrame
   end try
   send ("albFrame" && pGen) to me in kAlbFrameMs milliseconds
end albFrame

command albTick pDt
   add pDt to sSceneT
   switch sScene
      case 1
         albSceneWash
         break
      case 2
         albSceneChase
         break
      case 3
         albSceneHeads
         break
      case 4
         albSceneUniverse
         break
      case 5
         albSceneFind
         break
   end switch
   albSendFrame
   albRate
   if sTour is true and sSceneT >= item sScene of kAlbSceneSecs then
      albGo (sScene mod kAlbScenes) + 1
   end if
end albTick

-- Jump to a scene: its words, its wire view, its button lit, every channel
-- back to 0 (a scene sets only the channels it uses)
command albGo pScene
   local tI
   if pScene < 1 or pScene > kAlbScenes then
      exit albGo
   end if
   put pScene into sScene
   put 0 into sSceneT
   put 0 into sNextAt
   put 0 into sStep
   put empty into sWireLog
   if pScene is 5 then
      -- discovery starts again from nothing, so it can be watched
      put empty into sFound
      put empty into sFoundCard
      put empty into sPollCard
   end if
   albClearFrame
   lock screen
   repeat with tI = 1 to kAlbScenes
      set the hilite of button ("albScene" & tI) to (tI is pScene)
   end repeat
   set the text of field "albAbout" to albAbout(pScene)
   if pScene is 5 then
      set the text of field "albWireCap" to "ON THE WIRE   what artnetxt read"
   else
      set the text of field "albWireCap" to "ON THE WIRE   channels 1-48, as read"
   end if
   unlock screen
end albGo

function albAbout pScene
   switch pScene
      case 1
         return "A PAR can takes four channels: dimmer, red, green and blue. The board rolls a rainbow across eight of them and sends all 512 channels of universe 0 as one ArtDmx packet, thirty times a second."
      case 2
         return "A chase is levels changing in order. A soft pulse runs along the PARs' dimmer channels and back, and the two moving heads aim at it. Only levels travel: the motion is the rig reading them."
      case 3
         return "A moving head takes six channels: pan, tilt, dimmer, red, green, blue. The board traces two figure-eights on its pad, and the heads read pan and tilt from what arrived and sweep the floor."
      case 4
         return "A universe is 512 channels, and here every one of them moves. The grid shows each channel as the node read it, from a packet of 530 bytes. The fixtures are just the first 44."
      case 5
         return "The board asks who is there with an ArtPoll; the rig answers like a real node, with a 239-byte ArtPollReply that artnetParseReply reads. Bytes that are not for the rig are ignored, each with its reason."
   end switch
   return empty
end albAbout

-- ===== The board: levels ====================================================

-- Every channel back to 0: the frame the board sends is always all 512
command albClearFrame
   local tI
   put empty into sFrame
   repeat with tI = 1 to kAlbChannels
      put numToByte(0) after sFrame
      put 0 into sOut[tI]
   end repeat
end albClearFrame

-- One channel's level, 0 to 1, into the frame. scArtnetSetChannel (the
-- helpers) rounds it to a byte and keeps it to 0..255.
command albSetLevel pChannel, pLevel
   put max(0, min(1, pLevel)) into pLevel
   put pLevel into sOut[pChannel]
   scArtnetSetChannel sFrame, pChannel, pLevel * 255
end albSetLevel

-- A PAR: dimmer, red, green, blue at channels 4k-3 to 4k
command albSetPar pK, pDim, pRgb
   local tBase
   put (pK - 1) * 4 into tBase
   albSetLevel tBase + 1, pDim
   albSetLevel tBase + 2, item 1 of pRgb / 255
   albSetLevel tBase + 3, item 2 of pRgb / 255
   albSetLevel tBase + 4, item 3 of pRgb / 255
end albSetPar

-- A moving head: pan, tilt, dimmer, red, green, blue
command albSetHead pH, pPan, pTilt, pDim, pRgb
   local tBase
   put kAlbHeadBase + (pH - 1) * 6 into tBase
   albSetLevel tBase + 1, pPan
   albSetLevel tBase + 2, pTilt
   albSetLevel tBase + 3, pDim
   albSetLevel tBase + 4, item 1 of pRgb / 255
   albSetLevel tBase + 5, item 2 of pRgb / 255
   albSetLevel tBase + 6, item 3 of pRgb / 255
end albSetHead

-- Scene 1: a rainbow rolling across the PARs, the heads in the opposite hue
command albSceneWash
   local tK, tHue
   repeat with tK = 1 to kAlbPars
      put sSceneT * 40 + (tK - 1) * 40 into tHue
      albSetPar tK, 0.78 + 0.22 * sin(sSceneT * 1.1 + tK * 0.7), albHue(tHue, 1, 1)
   end repeat
   put sSceneT * 40 + 180 into tHue
   albSetHead 1, 0.32 + 0.08 * sin(sSceneT * 0.6), 0.62, 0.45, albHue(tHue, 0.6, 1)
   albSetHead 2, 0.68 + 0.08 * sin(sSceneT * 0.6 + 1.5), 0.62, 0.45, albHue(tHue + 40, 0.6, 1)
end albSceneWash

-- Scene 2: a soft pulse running along the PARs and back; the heads follow it
command albSceneChase
   local tK, tPos, tPhase, tRgb
   -- 1 to 8 and back every 3.2 seconds, eased at the ends
   put (sSceneT / 3.2) - trunc(sSceneT / 3.2) into tPhase
   put 1 + 7 * (0.5 - 0.5 * cos(tPhase * 2 * pi)) into tPos
   put albHue(30 - 22 * (0.5 - 0.5 * cos(sSceneT * 0.5)), 0.85, 1) into tRgb
   repeat with tK = 1 to kAlbPars
      albSetPar tK, 0.06 + 0.94 * exp(-((tK - tPos) ^ 2) / 0.9), tRgb
   end repeat
   albSetHead 1, (tPos - 1) / 7 * 0.8 + 0.1, 0.45, 0.6, "255,244,224"
   albSetHead 2, (tPos - 1) / 7 * 0.8 + 0.1, 0.75, 0.6, "255,244,224"
end albSceneChase

-- Scene 3: two figure-eights, the PARs a low blue wash beneath them
command albSceneHeads
   local tK, tT
   repeat with tK = 1 to kAlbPars
      albSetPar tK, 0.22 + 0.06 * sin(sSceneT * 0.8 + tK), "30,60,255"
   end repeat
   put sSceneT * 1.15 into tT
   albSetHead 1, 0.5 + 0.42 * sin(tT), 0.5 + 0.38 * sin(tT * 2), 1, albHue(300, 0.75, 1)
   albSetHead 2, 0.5 - 0.42 * sin(tT + 0.9), 0.5 + 0.38 * sin(tT * 2 + 1.8), 1, albHue(186, 0.8, 1)
end albSceneHeads

-- Scene 4: a slow pattern across all 512 channels. The fixtures are the
-- first 44 of them, so they move with it.
command albSceneUniverse
   local tC, tRow, tCol, tV
   repeat with tC = 1 to kAlbChannels
      put (tC - 1) div kAlbCols into tRow
      put (tC - 1) mod kAlbCols into tCol
      put 0.5 + 0.5 * sin(tCol * 0.33 + sSceneT * 1.7) * cos(tRow * 0.42 - sSceneT * 1.1) into tV
      albSetLevel tC, tV
   end repeat
end albSceneUniverse

-- Scene 5: a warm, still look while the board looks for nodes. An ArtPoll
-- every three seconds; between them, bytes that are not for the rig.
command albSceneFind
   local tK, tCut
   repeat with tK = 1 to kAlbPars
      albSetPar tK, 0.5 + 0.12 * sin(sSceneT * 0.9 + tK * 0.5), "255,196,140"
   end repeat
   albSetHead 1, 0.35, 0.55, 0.3, "255,244,224"
   albSetHead 2, 0.65, 0.55, 0.3, "255,244,224"
   if sSceneT < sNextAt then
      exit albSceneFind
   end if
   add 1 to sStep
   put 0.6 + sStep * 1.5 into sNextAt
   switch sStep mod 4
      case 1
         albPollNow
         break
      case 2
         if sStep mod 8 is 2 then
            albSendRaw "hello rig"
         else
            albSendRaw artnetBuildDmx(1, sFrame)
         end if
         break
      case 3
         albPollNow
         break
      case 0
         -- an ArtDmx cut short: its Length says 512, six levels arrived
         put byte 1 to 24 of artnetBuildDmx(kAlbUniverse, sFrame) into tCut
         albSendRaw tCut
         break
   end switch
end albSceneFind

-- ===== The board: sending ===================================================

-- The frame to the rig through the helpers' scArtnetSend (which builds it
-- with artnetBuildDmx), and to kAlbAlsoTo's node when there is one
command albSendFrame
   local tWhy
   if sHaveArt is not true or sDest is empty then
      exit albSendFrame
   end if
   scArtnetSend sDest, kAlbUniverse, sFrame
   put the result into tWhy
   if tWhy is not empty then
      albLog "board  could not send: " & tWhy
      exit albSendFrame
   end if
   add 1 to sSent
   if sAlso is not empty then
      scArtnetSend sAlso, kAlbUniverse, sFrame
      if the result is empty then
         add 1 to sAlsoSent
      end if
   end if
   if sScene is not 5 then
      -- the bytes the view shows are the bytes that went: the same call
      put artnetBuildDmx(kAlbUniverse, sFrame) into sLastPacket
      put albDmxView(sLastPacket) into sPacketView
   end if
end albSendFrame

-- An ArtPoll to the rig, through the helpers' scArtnetPoll
command albPollNow
   local tPoll
   if sHaveArt is not true or sDest is empty then
      exit albPollNow
   end if
   scArtnetPoll sDest
   if the result is empty then
      add 1 to sSent
   end if
   if sAlso is not empty then
      scArtnetPoll sAlso
   end if
   put artnetBuildPoll() into tPoll
   put albPollView(tPoll) into sPacketView
end albPollNow

-- Bytes as they are (scene 5's strangers)
command albSendRaw pData
   if sHaveArt is not true or sDest is empty then
      exit albSendRaw
   end if
   write pData to socket sDest
   add 1 to sSent
end albSendRaw

-- The ArtDmx the board just sent, header byte by byte, every number in the
-- words decoded from those bytes
function albDmxView pPkt
   local tText, tOpCode, tVer, tUni, tLen
   put albByte(pPkt, 9) + 256 * albByte(pPkt, 10) into tOpCode
   put 256 * albByte(pPkt, 11) + albByte(pPkt, 12) into tVer
   put 256 * albByte(pPkt, 16) + albByte(pPkt, 15) into tUni
   put 256 * albByte(pPkt, 17) + albByte(pPkt, 18) into tLen
   put "ArtDmx to " & sDest & ", " & the number of bytes in pPkt & " bytes" & return into tText
   put albHexBytes(pPkt, 1, 8) & "  Art-Net + NUL" & return after tText
   put albHexBytes(pPkt, 9, 10) & "  OpCode 0x" & format("%04X", tOpCode) & ", low byte first" & return after tText
   put albHexBytes(pPkt, 11, 12) & "  ProtVer " & tVer & ", high byte first" & return after tText
   put albHexBytes(pPkt, 13, 14) & "  Sequence, Physical" & return after tText
   put albHexBytes(pPkt, 15, 16) & "  SubUni, Net: universe " & tUni & return after tText
   put albHexBytes(pPkt, 17, 18) & "  Length " & tLen & ", high byte first" & return after tText
   put albHexBytes(pPkt, 19, 24) & "  channels 1 to 6" after tText
   return tText
end albDmxView

function albPollView pPkt
   local tText, tOpCode, tVer
   put albByte(pPkt, 9) + 256 * albByte(pPkt, 10) into tOpCode
   put 256 * albByte(pPkt, 11) + albByte(pPkt, 12) into tVer
   put "ArtPoll to " & sDest & ", " & the number of bytes in pPkt & " bytes" & return into tText
   put albHexBytes(pPkt, 1, 8) & "  Art-Net + NUL" & return after tText
   put albHexBytes(pPkt, 9, 10) & "  OpCode 0x" & format("%04X", tOpCode) & ", low byte first" & return after tText
   put albHexBytes(pPkt, 11, 12) & "  ProtVer " & tVer & ", high byte first" & return after tText
   put albHexBytes(pPkt, 13, 14) & "  Flags, DiagPriority" after tText
   return tText
end albPollView

function albByte pData, pIndex
   if pIndex > the number of bytes in pData then
      return 0
   end if
   return byteToNum(byte pIndex of pData)
end albByte

function albHexBytes pData, pFrom, pTo
   local tI, tOut
   repeat with tI = pFrom to min(pTo, the number of bytes in pData)
      put format("%02X", byteToNum(byte tI of pData)) & space after tOut
   end repeat
   delete the last char of tOut
   return tOut
end albHexBytes

-- ===== Receiving: the rig, a virtual Art-Net node ===========================

-- Every datagram that reaches the rig's port, from this computer or any
-- other. The engine calls it with (sender, data, socket), in that order.
on albReceived pSender, pData, pSocket
   local tFrame, tNode, tOpCode, tFrom
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
   if sHaveArt is not true then
      exit albReceived
   end if
   if not scLooksLikeArtnet(pData) then
      add 1 to sIgnored
      albLog "node   " & the number of bytes in pData & " B, not Art-Net: ignored"
      exit albReceived
   end if
   put artnetParseDmx(pData) into tFrame
   if tFrame["opcode"] is "ArtDmx" then
      if tFrame["universe"] is not kAlbUniverse then
         add 1 to sIgnored
         albLog "node   ArtDmx for universe " & tFrame["universe"] & ": not mine"
         exit albReceived
      end if
      add 1 to sRead
      albNodeTake tFrame, pSender
      exit albReceived
   end if
   put albByte(pData, 9) + 256 * albByte(pData, 10) into tOpCode
   if tOpCode is 8192 then
      -- an ArtPoll (OpCode 0x2000): a node answers it, to port 6454 of the
      -- computer that asked; this one answers only this computer
      add 1 to sRead
      set the itemDelimiter to ":"
      put item 1 of pSender into tFrom
      set the itemDelimiter to comma
      if tFrom is not kAlbHost then
         albLog "node   ArtPoll from " & tFrom & ": not answered"
         exit albReceived
      end if
      add 1 to sPolls
      write albPollReply() to socket sDest
      add 1 to sSent
      albLog "node   ArtPoll from " & tFrom & ": answered"
      put "ArtPoll from " & pSender & return & "answered with an ArtPollReply," & return & "239 bytes, to port " & sPort & return & "polls answered: " & sPolls into sPollCard
      exit albReceived
   end if
   put artnetParseReply(pData) into tNode
   if tNode["opcode"] is "ArtPollReply" then
      add 1 to sRead
      albBoardFound tNode, pSender
      exit albReceived
   end if
   add 1 to sIgnored
   albLog "node   OpCode 0x" & format("%04X", tOpCode) & ": not one it reads"
end albReceived

-- The rig takes the levels that arrived. A packet cut short changes only the
-- channels it carries: artnetParseDmx reads as far as its bytes go.
command albNodeTake pFrame, pSender
   local tC, tByte, tLevels
   put pFrame["channels"] into tLevels
   put 0 into tC
   repeat for each byte tByte in tLevels
      add 1 to tC
      put byteToNum(tByte) into sGot[tC]
   end repeat
   if pFrame["length"] < kAlbChannels then
      albLog "node   ArtDmx cut short: " & pFrame["length"] & " of 512 read"
   end if
   put "ArtDmx from " & pSender & return & "universe " & pFrame["universe"] & "   (Net " & pFrame["net"] & ", SubUni " & pFrame["subuni"] & ")" & return & "length   " & pFrame["length"] & " channels" & return & "sequence " & pFrame["sequence"] & "   physical " & pFrame["physical"] into sNodeCard
end albNodeTake

-- The board reads a node's ArtPollReply (artnetParseReply's array)
command albBoardFound pNode, pSender
   local tOuts, tI
   put pNode into sFound[pNode["ip"] & ":" & pNode["port"]]
   repeat with tI = 1 to the number of elements of pNode["outputUniverses"]
      put pNode["outputUniverses"][tI] & comma after tOuts
   end repeat
   delete the last char of tOuts
   put "FOUND  " & pNode["shortName"] & " at " & pNode["ip"] & ":" & pNode["port"] & return & "universe " & tOuts & " out, MAC " & pNode["mac"] into sFoundCard
   albLog "board  ArtPollReply: " & pNode["shortName"] & ", universe " & tOuts
end albBoardFound

-- The rig's answer to an ArtPoll: an Art-Net 4 ArtPollReply, 239 bytes, at
-- the offsets of the specification (and of tools/sim/artnet_node.py). The
-- Port and the OpCode go low byte first, NumPorts high byte first.
function albPollReply
   local tB, tI
   put "Art-Net" & numToByte(0) into tB                     -- 1-8 ID
   put numToByte(0) & numToByte(33) after tB                -- 9-10 OpCode 0x2100
   put numToByte(127) & numToByte(0) & numToByte(0) & numToByte(1) after tB  -- 11-14 IP
   put numToByte(sPort mod 256) & numToByte(sPort div 256) after tB          -- 15-16 Port
   put numToByte(0) & numToByte(1) after tB                 -- 17-18 VersInfo 1
   put numToByte(0) & numToByte(0) after tB                 -- 19-20 NetSwitch, SubSwitch
   put albZeros(6) after tB                                 -- 21-26 Oem, Ubea, Status1, EstaMan
   put albPadded(kAlbNodeShort, 18) after tB                -- 27-44 ShortName
   put albPadded(kAlbNodeLong, 64) after tB                 -- 45-108 LongName
   put albPadded("#0001 [" & format("%04d", sPolls mod 10000) & "] rig ready: 10 fixtures, universe 0", 64) after tB  -- 109-172 NodeReport
   put numToByte(0) & numToByte(1) after tB                 -- 173-174 NumPorts 1
   put numToByte(128) & albZeros(3) after tB                -- 175-178 PortTypes: port 1 outputs DMX
   put albZeros(4) after tB                                 -- 179-182 GoodInput
   put numToByte(128) & albZeros(3) after tB                -- 183-186 GoodOutputA: data going out
   put albZeros(4) after tB                                 -- 187-190 SwIn
   put numToByte(kAlbUniverse mod 16) & albZeros(3) after tB  -- 191-194 SwOut
   put albZeros(6) after tB                                 -- 195-200 Acn, Macro, Remote, Spare
   put numToByte(0) after tB                                -- 201 Style: a node
   repeat for each item tI in kAlbNodeMac
      put numToByte(tI) after tB                            -- 202-207 MAC, high byte first
   end repeat
   put numToByte(127) & numToByte(0) & numToByte(0) & numToByte(1) after tB  -- 208-211 BindIp
   put numToByte(1) after tB                                -- 212 BindIndex
   put albZeros(239 - the number of bytes in tB) after tB   -- 213-239 Status2 on, all 0
   return tB
end albPollReply

function albZeros pN
   local tOut
   repeat pN times
      put numToByte(0) after tOut
   end repeat
   return tOut
end albZeros

-- Text in a field of pLen bytes, NUL-padded (always at least one NUL)
function albPadded pText, pLen
   put char 1 to pLen - 1 of pText into pText
   return pText & albZeros(pLen - the number of chars of pText)
end albPadded

-- ===== The wire: what was read ==============================================

command albLog pLine
   put pLine & return after sWireLog
   if the number of lines of sWireLog > kAlbWireLines then
      delete line 1 to (the number of lines of sWireLog - kAlbWireLines) of sWireLog
   end if
end albLog

-- The first 48 channels as the node read them, eight to a line
function albChannelTable
   local tText, tRow, tC
   repeat with tRow = 0 to 5
      put format("%3d ", tRow * 8 + 1) after tText
      repeat with tC = tRow * 8 + 1 to tRow * 8 + 8
         put format("%4d", sGot[tC]) after tText
      end repeat
      put return after tText
   end repeat
   delete the last char of tText
   return tText
end albChannelTable

-- Frames read a second, over the last second
command albRate
   local tNow
   put the milliseconds into tNow
   if sRateMark is empty or tNow - sRateMark >= 1000 then
      if sRateMark is not empty then
         put round((sRead - sRateBase) * 1000 / (tNow - sRateMark)) into sRate
      end if
      put tNow into sRateMark
      put sRead into sRateBase
   end if
end albRate

-- ===== The picture ==========================================================

command albRender
   local tK, tX, tBase, tDim, tRgb, tPan, tTilt, tTx, tTy, tC, tS, tId, tY
   add 1 to sFrames
   lock screen
   -- the rig, from what arrived: PARs
   repeat with tK = 1 to kAlbPars
      put (tK - 1) * 4 into tBase
      put sGot[tBase + 1] / 255 into tDim
      put sGot[tBase + 2] & comma & sGot[tBase + 3] & comma & sGot[tBase + 4] into tRgb
      set the backgroundColor of graphic ("albCore" & tK) to albMix(kAlbLampOff, tRgb, tDim)
      set the backgroundColor of graphic ("albHalo" & tK) to tRgb
      set the blendLevel of graphic ("albHalo" & tK) to 100 - round(tDim * 70)
      set the backgroundColor of graphic ("albBeam" & tK) to tRgb
      set the blendLevel of graphic ("albBeam" & tK) to 100 - round(tDim * 36)
   end repeat
   -- the moving heads: pan and tilt aim the beam at the floor
   repeat with tK = 1 to 2
      put kAlbHeadBase + (tK - 1) * 6 into tBase
      put sGot[tBase + 1] / 255 into tPan
      put sGot[tBase + 2] / 255 into tTilt
      put sGot[tBase + 3] / 255 into tDim
      put sGot[tBase + 4] & comma & sGot[tBase + 5] & comma & sGot[tBase + 6] into tRgb
      put kAlbFixX0 + (kAlbPars + tK - 1) * kAlbFixDX into tX
      put kAlbFloorL + 40 + tPan * (kAlbFloorR - kAlbFloorL - 80) into tTx
      put kAlbFloorT + 22 + tTilt * (kAlbFloorB - kAlbFloorT - 44) into tTy
      set the points of graphic ("albHeadBeam" & tK) to (tX - 5) & comma & (kAlbLampY + 8) & return & (tX + 5) & comma & (kAlbLampY + 8) & return & round(tTx + 24) & comma & round(tTy) & return & round(tTx - 24) & comma & round(tTy) & return & (tX - 5) & comma & (kAlbLampY + 8)
      set the backgroundColor of graphic ("albHeadBeam" & tK) to tRgb
      set the blendLevel of graphic ("albHeadBeam" & tK) to 100 - round(tDim * 42)
      set the rect of graphic ("albPool" & tK) to round(tTx - 38), round(tTy - 12), round(tTx + 38), round(tTy + 12)
      set the backgroundColor of graphic ("albPool" & tK) to tRgb
      set the blendLevel of graphic ("albPool" & tK) to 100 - round(tDim * 60)
      set the backgroundColor of graphic ("albLens" & tK) to albMix(kAlbLampOff, tRgb, tDim)
      set the backgroundColor of graphic ("albHeadHalo" & tK) to tRgb
      set the blendLevel of graphic ("albHeadHalo" & tK) to 100 - round(tDim * 60)
   end repeat
   -- the universe: a square per channel, set only when its shade changes
   repeat with tC = 1 to kAlbChannels
      put round(sGot[tC] * (kAlbShades - 1) / 255) into tS
      if tS is not sShade[tC] then
         put tS into sShade[tC]
         put sCellId[tC] into tId
         set the backgroundColor of graphic id tId to sShadeRgb[tS]
      end if
   end repeat
   -- the board, from its own levels: a fader a fixture, and the pad
   repeat with tK = 1 to kAlbFixtures
      if tK <= kAlbPars then
         put (tK - 1) * 4 into tBase
         put sOut[tBase + 1] into tDim
         put albRgbOf(tBase + 2) into tRgb
      else
         put kAlbHeadBase + (tK - kAlbPars - 1) * 6 into tBase
         put sOut[tBase + 3] into tDim
         put albRgbOf(tBase + 4) into tRgb
      end if
      put kAlbFaderL + (tK - 1) * kAlbFaderDX into tX
      put round(kAlbFaderB - tDim * (kAlbFaderB - kAlbFaderT)) into tY
      set the rect of graphic ("albFaderFill" & tK) to tX + 7, tY, tX + 11, kAlbFaderB
      set the backgroundColor of graphic ("albFaderFill" & tK) to albMix(kAlbLine, tRgb, 0.35 + 0.65 * albPeak(tRgb))
      set the rect of graphic ("albFaderCap" & tK) to tX, tY - 7, tX + 18, tY + 7
   end repeat
   repeat with tK = 1 to 2
      put kAlbHeadBase + (tK - 1) * 6 into tBase
      put kAlbPadL + 10 + sOut[tBase + 1] * (kAlbPadS - 20) into tX
      put kAlbPadT + 10 + sOut[tBase + 2] * (kAlbPadS - 20) into tY
      set the rect of graphic ("albPuck" & tK) to round(tX - 8), round(tY - 8), round(tX + 8), round(tY + 8)
      set the backgroundColor of graphic ("albPuck" & tK) to albMix(kAlbLine, albRgbOf(tBase + 4), 0.85)
   end repeat
   -- words
   if sScene is 5 then
      albSetText "albWire", sWireLog
      if sFoundCard is empty then
         albSetText "albPacket", sPacketView & return & "waiting for an answer"
      else
         albSetText "albPacket", sPacketView & return & sFoundCard
      end if
   else
      albSetText "albWire", albChannelTable()
      albSetText "albPacket", sPacketView
   end if
   if sScene is 5 and sPollCard is not empty then
      albSetText "albNodeCard", sPollCard
   else
      albSetText "albNodeCard", sNodeCard
   end if
   albSetText "albStats", sSent & " sent   " & sRead & " read   " & sIgnored & " ignored   " & sRate & " a second"
   unlock screen
end albRender

-- A channel triple of the board's own levels as "r,g,b"
function albRgbOf pFirst
   return round(sOut[pFirst] * 255) & comma & round(sOut[pFirst + 1] * 255) & comma & round(sOut[pFirst + 2] * 255)
end albRgbOf

-- How bright a colour is at its brightest channel, 0 to 1
function albPeak pRgb
   return max(item 1 of pRgb, item 2 of pRgb, item 3 of pRgb) / 255
end albPeak

-- Only touch a field when its words change: a field redrawn thirty times a
-- second for nothing costs more than everything else in a frame
command albSetText pField, pText
   if the text of field pField is not pText then
      set the text of field pField to pText
   end if
end albSetText

command albResetRig
   local tI
   put 0 into sSent
   put 0 into sArrived
   put 0 into sRead
   put 0 into sIgnored
   put 0 into sAlsoSent
   put 0 into sPolls
   put 0 into sRate
   put empty into sRateMark
   put empty into sWireLog
   put empty into sFound
   put empty into sFoundCard
   put empty into sNodeCard
   put empty into sPollCard
   put empty into sPacketView
   put empty into sLastPacket
   repeat with tI = 1 to kAlbChannels
      put 0 into sGot[tI]
   end repeat
   albClearFrame
end albResetRig

-- "r,g,b" between two colours, pT from 0 to 1
function albMix pA, pB, pT
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
end albMix

-- A hue (any number of degrees) as "r,g,b", at a saturation and value from 0
-- to 1
function albHue pHue, pSat, pVal
   local tH, tI, tF, tP, tQ, tT, tR, tG, tB
   if pHue is not a number then
      put 0 into pHue
   end if
   put (pHue mod 360) / 60 into tH
   if tH < 0 then
      add 6 to tH
   end if
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
end albHue

-- ===== What is missing, and how it went =====================================

command albShowStatus
   local tText, tMissing
   if sTrouble is not empty then
      put "Something went wrong and the show stopped: " & line 1 of sTrouble & ". Close the stack and open it again." into tText
      put tText into tMissing
   else if sHaveArt is not true then
      put "Missing: artnetxt. " & sWhyNot & " Install it (Tools > Extension Manager) and open this stack again. The board still runs, but nothing is sent." into tText
      put "This demo needs artnetxt, the suite's Art-Net extension." & return & sWhyNot & return & "Install it, then open this stack again." into tMissing
   else if sNoNet is not empty then
      put "Missing: a UDP port. " & sNoNet & " Close the program that holds port 6454 and open this stack again." into tText
      put sNoNet into tMissing
   else if sAlsoWhy is not empty then
      put sAlsoWhy into tText
   else if sAlso is not empty then
      put "Also sending universe 0 to the node at " & sAlso & ", as kAlbAlsoTo asks. Empty kAlbAlsoTo, and nothing leaves this computer." into tText
   else if sPort is not kAlbPortFirst then
      put "Nothing to set up: the board sends to this computer. Port 6454 was taken (another Art-Net program?), so the rig listens on " & sPort & ", where a lighting desk will not look." into tText
   else
      put "Nothing to set up and no gear needed: the board sends to this computer and the rig listens on UDP port 6454, as a node does. Pause, and a desk sending universe 0 here drives the rig." into tText
   end if
   lock screen
   set the text of field "albStatus" to tText
   if tMissing is empty and sAlsoWhy is empty then
      set the foregroundColor of field "albStatus" to kAlbSoft
      set the visible of field "albMissing" to false
   else
      set the foregroundColor of field "albStatus" to kAlbAccent
      set the text of field "albMissing" to tMissing
      set the visible of field "albMissing" to (tMissing is not empty)
   end if
   if sPort is empty then
      set the text of field "albRigCap" to "THE RIG   a virtual node, lit only by what arrives"
      set the text of field "albBoardCap" to "THE BOARD"
   else
      set the text of field "albRigCap" to "THE RIG   a virtual node on UDP port " & sPort & ", lit only by what arrives"
      set the text of field "albBoardCap" to "THE BOARD   sends real Art-Net to " & sDest & ", universe " & kAlbUniverse
   end if
   unlock screen
end albShowStatus

command albShowSwitches
   lock screen
   set the hilite of button "albTour" to (sTour is true)
   set the hilite of button "albPause" to (sPaused is true)
   unlock screen
end albShowSwitches

-- ===== For the tests ========================================================

-- Take the clock out of the loop's hands: the test steps it
command albTestBegin
   put false into sRunning
   add 1 to sGen
   put false into sTour
end albTestBegin

-- Move the show on by pSeconds, a frame at a time, drawing each frame
command albTestStep pSeconds
   local tSteps, tI
   put max(1, round(pSeconds * 1000 / kAlbFrameMs)) into tSteps
   repeat with tI = 1 to tSteps
      albTick kAlbFrameMs / 1000
      albRender
   end repeat
end albTestStep

function albState
   local tState, tI, tByte
   put sScene into tState["scene"]
   put sSceneT into tState["sceneTime"]
   put sFrames into tState["frames"]
   put sSent into tState["sent"]
   put sArrived into tState["arrived"]
   put sRead into tState["read"]
   put sIgnored into tState["ignored"]
   put sAlsoSent into tState["alsoSent"]
   put sAlso into tState["also"]
   put sPolls into tState["polls"]
   put sStep into tState["step"]
   put sHaveArt into tState["haveArt"]
   put sWhyNot into tState["whyNot"]
   put sPort into tState["port"]
   put sNoNet into tState["noNet"]
   put sTrouble into tState["trouble"]
   put sRunning into tState["running"]
   put sPaused into tState["paused"]
   put the keys of sFound into tState["found"]
   put sFoundCard into tState["foundCard"]
   put sNodeCard into tState["nodeCard"]
   put sPacketView into tState["packetView"]
   put sWireLog into tState["log"]
   repeat for each byte tByte in sFrame
      put byteToNum(tByte) & comma after tState["sentLevels"]
   end repeat
   repeat with tI = 1 to kAlbChannels
      put sGot[tI] & comma after tState["readLevels"]
      put sShade[tI] & comma after tState["shades"]
   end repeat
   repeat with tI = 1 to kAlbShades
      put sShadeRgb[tI - 1] & ";" after tState["shadeColours"]
   end repeat
   return tState
end albState

-- ===== Building the window ==================================================

command albBuild
   local tI, tX, tY, tTag, tCol, tRow, tWasQuiet
   -- Built with messages locked. In the IDE every scripted create, rename
   -- and delete sends an engine message that runs the IDE's own script
   -- (the suite's engine note 5.15): built with them unlocked, this window
   -- held OXT-Beyond 0.2.8-dp.1's IDE on Windows for 112 seconds as it
   -- opened (2026-11-21). Nothing here asks a question or needs an engine
   -- message, and the caller's lock is given back at the end.
   put the lockMessages into tWasQuiet
   lock screen
   lock messages
   albClear
   set the width of this stack to kAlbW
   set the height of this stack to kAlbH
   -- Then centred on the screen. A new stack is 32,32,288,288 and a size
   -- set keeps its centre (engine note 5.17), so 1100 wide put its left at
   -- -390: the window opened 390 pixels past the screen's edge on Windows
   -- (the same day). start-here centres a window it opens; one opened any
   -- other way now centres itself.
   set the loc of this stack to the screenLoc
   set the resizable of this stack to false
   set the label of this stack to "Art-Net Light Board - OXT-Beyond"
   set the backgroundColor of this stack to kAlbPage
   set the foregroundColor of this stack to kAlbInk
   set the textSize of this stack to 13
   set the backgroundColor of this card to kAlbPage
   set the foregroundColor of this card to kAlbInk

   -- the header: OXT-Beyond, the demo's name, what it does, who made it
   albLabel "albBrand", "OXT-BEYOND", 11, kAlbAccent, "bold", 20, 6, 400, 27
   albLabel "albTitle", "Art-Net Light Board", 22, kAlbInk, "bold", 20, 22, 560, 59
   albLabel "albSub", "DMX lighting from xTalk with artnetxt: a board and a virtual rig talking real Art-Net over UDP, every packet read back.", 12, kAlbSoft, "plain", 20, 56, 900, 78
   albLabel "albByline", "by Seth Morrow", 12, kAlbSoft, "plain", 880, 30, kAlbSideR, 52
   set the textAlign of field "albByline" to "right"

   -- the stage: the rig above, the board below
   albRect "albStage", kAlbPanel, kAlbStageL, kAlbStageT, kAlbStageR, kAlbStageB
   albLabel "albRigCap", "THE RIG", 11, kAlbAccent, "bold", 30, 86, 524, 107
   albRect "albFloor", kAlbWell, kAlbFloorL, kAlbFloorT, kAlbFloorR, kAlbFloorB
   albRect "albTruss", kAlbLine, kAlbFloorL + 6, kAlbTrussY, kAlbFloorR - 6, kAlbTrussY + 4
   -- beams first, so the lamps draw over them
   repeat with tI = 1 to kAlbPars
      put kAlbFixX0 + (tI - 1) * kAlbFixDX into tX
      albBeam "albBeam" & tI, tX
   end repeat
   repeat with tI = 1 to 2
      albPolygon "albHeadBeam" & tI, kAlbAccent
      albOval "albPool" & tI, kAlbAccent, 0, 0, 10, 10
      set the blendLevel of graphic ("albPool" & tI) to 100
   end repeat
   repeat with tI = 1 to kAlbFixtures
      put kAlbFixX0 + (tI - 1) * kAlbFixDX into tX
      if tI <= kAlbPars then
         put ((tI - 1) * 4 + 1) & "-" & (tI * 4) into tTag
         albRect "albHanger" & tI, kAlbLine, tX - 1, kAlbTrussY + 4, tX + 1, kAlbLampY - 10
         albOval "albHalo" & tI, kAlbAccent, tX - 22, kAlbLampY - 22, tX + 22, kAlbLampY + 22
         set the blendLevel of graphic ("albHalo" & tI) to 100
         albOval "albCore" & tI, kAlbLampOff, tX - 12, kAlbLampY - 12, tX + 12, kAlbLampY + 12
      else
         put (kAlbHeadBase + (tI - kAlbPars - 1) * 6 + 1) & "-" & (kAlbHeadBase + (tI - kAlbPars) * 6) into tTag
         albOval "albHeadHalo" & (tI - kAlbPars), kAlbAccent, tX - 20, kAlbLampY - 16, tX + 20, kAlbLampY + 24
         set the blendLevel of graphic ("albHeadHalo" & (tI - kAlbPars)) to 100
         albRoundRect "albYoke" & (tI - kAlbPars), kAlbButton, tX - 14, kAlbTrussY + 4, tX + 14, kAlbLampY + 12
         albOval "albLens" & (tI - kAlbPars), kAlbLampOff, tX - 9, kAlbLampY - 6, tX + 9, kAlbLampY + 12
      end if
      albLabel "albFixTag" & tI, tTag, 9, kAlbSoft, "plain", tX - 24, 106, tX + 24, 124
      set the textAlign of field ("albFixTag" & tI) to "center"
   end repeat
   albLabel "albFloorCap", "8 PARs, channels 1-32;  2 moving heads, 33-44", 10, kAlbSoft, "plain", kAlbFloorL + 6, kAlbFloorB - 21, kAlbFloorR - 6, kAlbFloorB - 2
   albText "albMissing", empty, 14, kAlbInk, kAlbFloorL + 40, kAlbFloorT + 30, kAlbFloorR - 40, kAlbFloorB - 30
   set the textAlign of field "albMissing" to "center"
   set the visible of field "albMissing" to false

   -- the universe as the node read it: 32 channels a row, 16 rows
   albLabel "albUniCap", "UNIVERSE " & kAlbUniverse & "   512 channels, as read", 10, kAlbSoft, "bold", kAlbGridL - 7, 88, kAlbStageR - 6, 107
   albRect "albGridWell", kAlbWell, kAlbGridL - 6, kAlbGridT - 6, kAlbGridL + kAlbCols * kAlbCellW + 5, kAlbGridT + kAlbRows * kAlbCellH + 5
   repeat with tI = 1 to kAlbChannels
      put (tI - 1) mod kAlbCols into tCol
      put (tI - 1) div kAlbCols into tRow
      put kAlbGridL + tCol * kAlbCellW into tX
      put kAlbGridT + tRow * kAlbCellH into tY
      albRect "albCell" & tI, kAlbCellOff, tX, tY, tX + kAlbCellW - 1, tY + kAlbCellH - 1
      put the id of graphic ("albCell" & tI) into sCellId[tI]
      put 0 into sShade[tI]
   end repeat
   albLabel "albGridTag", "a square a channel, 1-32 on the top row", 9, kAlbSoft, "plain", kAlbGridL - 7, kAlbGridT + kAlbRows * kAlbCellH + 7, kAlbStageR - 6, kAlbGridT + kAlbRows * kAlbCellH + 25
   albText "albNodeCard", empty, 10, kAlbInk, kAlbGridL - 7, 272, kAlbStageR - 12, 346
   set the textFont of field "albNodeCard" to albMonoFont()
   set the dontWrap of field "albNodeCard" to true
   albWell "albNodeCard", 6
   repeat with tI = 0 to kAlbShades - 1
      if tI is 0 then
         put kAlbCellOff into sShadeRgb[tI]
      else if tI <= 8 then
         put albMix("70,48,36", kAlbAccent, (tI - 1) / 7) into sShadeRgb[tI]
      else
         put albMix(kAlbAccent, "255,238,220", (tI - 8) / 3) into sShadeRgb[tI]
      end if
   end repeat

   -- the board
   albRect "albSplit", kAlbLine, kAlbStageL + 14, 360, kAlbStageR - 14, 361
   albLabel "albBoardCap", "THE BOARD", 11, kAlbAccent, "bold", 30, 368, 760, 389
   repeat with tI = 1 to kAlbFixtures
      put kAlbFaderL + (tI - 1) * kAlbFaderDX into tX
      albRect "albFaderTrack" & tI, kAlbLine, tX + 7, kAlbFaderT, tX + 11, kAlbFaderB
      albRect "albFaderFill" & tI, kAlbAccent, tX + 7, kAlbFaderB - 1, tX + 11, kAlbFaderB
      albRoundRect "albFaderCap" & tI, kAlbInk, tX, kAlbFaderB - 7, tX + 18, kAlbFaderB + 7
      if tI <= kAlbPars then
         put tI into tTag
      else
         put "H" & (tI - kAlbPars) into tTag
      end if
      albLabel "albFaderTag" & tI, tTag, 9, kAlbSoft, "plain", tX - 4, kAlbFaderB + 10, tX + 22, kAlbFaderB + 27
      set the textAlign of field ("albFaderTag" & tI) to "center"
   end repeat
   albLabel "albFadersTag", "the dimmer of each fixture", 9, kAlbSoft, "plain", kAlbFaderL - 4, kAlbFaderB + 28, kAlbFaderL + 270, kAlbFaderB + 46
   albRect "albPad", kAlbWell, kAlbPadL, kAlbPadT, kAlbPadL + kAlbPadS, kAlbPadT + kAlbPadS
   albRect "albPadH", kAlbLine, kAlbPadL + 8, kAlbPadT + kAlbPadS div 2, kAlbPadL + kAlbPadS - 8, kAlbPadT + kAlbPadS div 2 + 1
   albRect "albPadV", kAlbLine, kAlbPadL + kAlbPadS div 2, kAlbPadT + 8, kAlbPadL + kAlbPadS div 2 + 1, kAlbPadT + kAlbPadS - 8
   albOval "albPuck1", kAlbAccent, 0, 0, 16, 16
   albOval "albPuck2", kAlbAccent, 0, 0, 16, 16
   albLabel "albPadTag", "pan and tilt of the two heads", 9, kAlbSoft, "plain", kAlbPadL - 2, kAlbPadT + kAlbPadS + 4, kAlbPadL + kAlbPadS + 40, kAlbPadT + kAlbPadS + 22
   -- 292 wide: its widest line, "41 72 74 2D 4E 65 74 00  Art-Net + NUL",
   -- needs 266 pixels of 11-point mono (DejaVu Sans Mono) inside the margins
   albText "albPacket", empty, 11, kAlbInk, 480, 394, 772, 556
   set the textFont of field "albPacket" to albMonoFont()
   set the dontWrap of field "albPacket" to true
   albWell "albPacket", 8
   albLabel "albPacketTag", "what the board just sent, byte by byte", 9, kAlbSoft, "plain", 480, 558, 772, 576

   -- the side: scenes, switches, what this shows, the wire, the counts
   albLabel "albScenesCap", "SCENES", 11, kAlbAccent, "bold", kAlbSideL, 82, kAlbSideR, 103
   repeat with tI = 1 to kAlbScenes
      put 106 + (tI - 1) * 30 into tY
      albButton "albScene" & tI, tI & ".  " & item tI of kAlbSceneNames, kAlbSideL, tY, kAlbSideR, tY + 26
   end repeat
   albButton "albTour", "Play them all", kAlbSideL, 258, kAlbSideL + 140, 282
   albButton "albPause", "Pause", kAlbSideL + 148, 258, kAlbSideR, 282
   albLabel "albAboutCap", "WHAT THIS SHOWS", 11, kAlbAccent, "bold", kAlbSideL, 288, kAlbSideR, 309
   albText "albAbout", empty, 12, kAlbInk, kAlbSideL, 310, kAlbSideR, 424
   albLabel "albWireCap", "ON THE WIRE", 11, kAlbAccent, "bold", kAlbSideL, 426, kAlbSideR, 447
   albText "albWire", empty, 10, kAlbInk, kAlbSideL, 448, kAlbSideR, 560
   set the textFont of field "albWire" to albMonoFont()
   set the dontWrap of field "albWire" to true
   albWell "albWire", 8
   albLabel "albStats", empty, 10, kAlbSoft, "plain", kAlbSideL, 563, kAlbSideR, 582

   -- the footer: what is missing, or that nothing is
   albLabel "albStatus", empty, 11, kAlbSoft, "plain", kAlbStageL, 593, kAlbSideR, 614
   albShowSwitches
   set the lockMessages to tWasQuiet
   unlock screen
end albBuild

-- Remove what an earlier build made (and only that): every control this
-- stack makes is named alb...
command albClear
   local tI
   repeat with tI = the number of controls of this card down to 1
      if the short name of control tI of this card begins with "alb" then
         delete control tI of this card
      end if
   end repeat
end albClear

function albMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end albMonoFont

-- One line of words nobody types into
command albLabel pName, pText, pSize, pColor, pStyle, pL, pT, pR, pB
   create field pName
   albQuiet pName, pSize, pColor
   set the dontWrap of field pName to true
   set the textStyle of field pName to pStyle
   set the rect of field pName to pL, pT, pR, pB
   set the text of field pName to pText
end albLabel

-- Words that wrap
command albText pName, pText, pSize, pColor, pL, pT, pR, pB
   create field pName
   albQuiet pName, pSize, pColor
   set the dontWrap of field pName to false
   set the rect of field pName to pL, pT, pR, pB
   set the text of field pName to pText
end albText

-- Lines tall enough for any system's font: left alone, a line is as tall
-- as the font the stack was BUILT with wants, and on Windows the tops of
-- the capitals were cut off (the Render3D Tour, 2026-11-21). Every colour
-- is the field's own, so a dark system theme changes nothing.
command albQuiet pName, pSize, pColor
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
   set the backgroundColor of field pName to kAlbPage
   set the hiliteColor of field pName to kAlbButton
   set the borderColor of field pName to kAlbLine
end albQuiet

-- A sunken panel for a field of mono text
command albWell pName, pMargins
   set the opaque of field pName to true
   set the backgroundColor of field pName to kAlbWell
   set the margins of field pName to pMargins
end albWell

-- A flat button: the Render3D Tour's. Lit (hilited) means on or chosen.
command albButton pName, pLabel, pL, pT, pR, pB
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
   set the backgroundColor of button pName to kAlbButton
   set the foregroundColor of button pName to kAlbInk
   set the hiliteColor of button pName to kAlbAccent
   set the borderColor of button pName to kAlbLine
   set the rect of button pName to pL, pT, pR, pB
end albButton

command albRect pName, pColor, pL, pT, pR, pB
   create graphic pName
   set the style of graphic pName to "rectangle"
   albFill pName, pColor
   set the rect of graphic pName to pL, pT, pR, pB
end albRect

command albRoundRect pName, pColor, pL, pT, pR, pB
   create graphic pName
   set the style of graphic pName to "roundrect"
   set the roundRadius of graphic pName to 4
   albFill pName, pColor
   set the rect of graphic pName to pL, pT, pR, pB
end albRoundRect

command albOval pName, pColor, pL, pT, pR, pB
   create graphic pName
   set the style of graphic pName to "oval"
   albFill pName, pColor
   set the rect of graphic pName to pL, pT, pR, pB
end albOval

-- A moving head's beam: its points are set every frame
command albPolygon pName, pColor
   create graphic pName
   set the style of graphic pName to "polygon"
   albFill pName, pColor
   set the points of graphic pName to "0,0" & return & "1,0" & return & "1,1" & return & "0,0"
   set the blendLevel of graphic pName to 100
end albPolygon

-- A PAR's beam: a cone from the lamp to the floor's far edge
command albBeam pName, pX
   local tPoints
   create graphic pName
   set the style of graphic pName to "polygon"
   albFill pName, kAlbAccent
   put (pX - 7) & comma & (kAlbLampY + 8) & return & (pX + 7) & comma & (kAlbLampY + 8) & return & (pX + 26) & comma & kAlbFloorB & return & (pX - 26) & comma & kAlbFloorB & return & (pX - 7) & comma & (kAlbLampY + 8) into tPoints
   set the points of graphic pName to tPoints
   set the blendLevel of graphic pName to 100
end albBeam

command albFill pName, pColor
   set the opaque of graphic pName to true
   set the lineSize of graphic pName to 0
   set the backgroundColor of graphic pName to pColor
   set the foregroundColor of graphic pName to pColor
   set the lockLocation of graphic pName to true
end albFill
