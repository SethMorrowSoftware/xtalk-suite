script "suiteClosingPass"

-- suite-closing-pass.livecodescript - ONE stack for the remaining runbook
-- legs. Install the suite on two machines, paste this on both, and each
-- section prints PASS lines as its leg closes. It exists so the closing
-- sessions are a checklist, not an expedition.
--
-- THE LEGS (and the runbook items they close):
--   A  DataChannel local async (single machine): the member harness's still
--      -static live halves - live dcSendText, dcBufferedAmount, gathering
--      state 2, selected candidate pair, the dcBufferedLow event, the
--      a=candidate/role pins.
--   B  ENet chat between two machines (item 6, enetxt's last leg).
--   C  Torrent seed/leech with a hash-verified payload, plus resume saved
--      to DISK and re-added - across an OXT restart if you quit between
--      the save and the resume (item 6 + the plan's resume gate).
--   D  rp1 chat between two machines over a DHT rendezvous (item 6).
--   E  DataChannel chat with the WebRTC handshake carried as signed BEP44
--      items over the real DHT (item 6; cross-NAT capable - the selected
--      pair line records host vs srflx).
--   F  Tor, single machine: Mode B (oxLaunchTor against a real tor binary,
--      item 4) and a live onion ECHO - listen, dial your own onion through
--      the Tor network, exact bytes both ways (live evidence for the
--      oxTransport* handlers). Quick Share Model C (item 5) stays the
--      quickshare demo's own run.
--
-- HONESTY (the suite convention): this stack is verified statically and
-- needs its OXT passes - each PASS line below is the evidence to record.
-- Every handler it calls is individually engine-proven except the seven
-- live-Tor ones section F exists to close.
--
-- SETUP, per machine: install sodiumxt + torrentxt + enetxt +
-- datachannelxt (packaged), and for section F put the onionxt library in
-- the message path (start using stack "onionxt"). ONE torrent session per
-- process (runbook trap 5.1): close every other torrent-flavoured stack,
-- and restart OXT before any re-paste of this script.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here.

-- ---- constants ---------------------------------------------------------------
constant kEnetPort = 27300
constant kEnetHello = "closing-pass hello"
constant kShareFolder = "closing-pass-share"
constant kPayloadFile = "payload.bin"
constant kResumeFile = "closing-pass.resume"
constant kSaltOffer = "cp-o"
constant kSaltAnswer = "cp-a"
constant kHeadMagic = "CP1C"
constant kChunkMax = 900
constant kPollMs = 250
constant kRefetchMs = 4000
constant kTorPing = "closing-pass-ping"

-- ==== SUITE UI KIT v1 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====
-- The family look as one carried block: the kit owns colors, chrome, and
-- control construction; the adopting demo owns layout (explicit rects) and
-- logic. Builders are idempotent (create-if-missing), so a rebuild on
-- reopen is safe. Do not edit this block in place: change the master and
-- re-carry it.
constant kUiBg = "237,239,243"
constant kUiAccent = "44,90,160"
constant kUiAccentText = "255,255,255"
constant kUiOk = "20,120,40"
constant kUiWarn = "160,90,10"
constant kUiBad = "170,30,30"
constant kUiMuted = "90,96,110"
constant kUiMono = "Courier"

-- The window chrome every adopter shares: stack size, ground color, the
-- title band, and the one status line under it (write it with uiStatus).
command uiChrome pTitle, pWidth, pHeight
   set the width of this stack to pWidth
   set the height of this stack to pHeight
   set the backgroundColor of this card to kUiBg
   set the title of this stack to pTitle
   uiLabel "uiTitle", "  " & pTitle, "0,0," & pWidth & ",30", 15
   set the opaque of field "uiTitle" to true
   set the backgroundColor of field "uiTitle" to kUiAccent
   set the foregroundColor of field "uiTitle" to kUiAccentText
   set the textStyle of field "uiTitle" to "bold"
   uiLabel "uiStatus", empty, "16,34," & (pWidth - 16) & ",52", 11
end uiChrome

-- The status line, colored by what it reports: "ok", "warn", "bad", or
-- anything else for neutral/muted. Demos route probe results through this
-- so a stack that cannot run says so in red, at the top, immediately.
command uiStatus pText, pKind
   put pText into field "uiStatus"
   if pKind is "ok" then
      set the foregroundColor of field "uiStatus" to kUiOk
   else if pKind is "warn" then
      set the foregroundColor of field "uiStatus" to kUiWarn
   else if pKind is "bad" then
      set the foregroundColor of field "uiStatus" to kUiBad
   else
      set the foregroundColor of field "uiStatus" to kUiMuted
   end if
end uiStatus

-- A numbered bold section header.
command uiSection pName, pText, pRect
   uiLabel pName, pText, pRect, 13
   set the textStyle of field pName to "bold"
end uiSection

-- A static caption (idempotent, borderless, transparent).
command uiLabel pName, pText, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the textSize of field pName to pSize
   put pText into field pName
end uiLabel

-- A one-line entry field, mono because hex, addresses and paths are what
-- this suite's demos edit.
command uiInput pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to false
   set the textSize of field pName to 11
   set the textFont of field pName to kUiMono
end uiInput

-- A read-only output/list area: mono, scrolling.
command uiArea pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the vScrollbar of field pName to true
   set the textSize of field pName to 10
   set the textFont of field pName to kUiMono
end uiArea

command uiButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end uiButton

-- The honesty/custody footer every demo carries: what the stack is, what
-- it is not, and its engine-evidence state.
command uiFooter pText, pRect
   uiLabel "uiFooter", pText, pRect, 11
   set the textStyle of field "uiFooter" to "italic"
   set the foregroundColor of field "uiFooter" to kUiMuted
end uiFooter
-- ==== SUITE UI KIT v1 END ====

-- ---- state -------------------------------------------------------------------
-- shared plumbing
local sPolling         -- "true" while the one pump chain is armed
local sSession         -- THE torrent session (this stack owns it; C/D/E share it)
local sDcReady         -- "true" once dcInit succeeded (A and E share the drain)
-- A: datachannel local async
local sAPeerA, sAPeerB, sAChanA, sAChanB
local sAOpenA, sAOpenB, sAGotText, sAGotBytes, sABigLen, sAGotLow, sAPhase
-- B: enet chat
local sEnHost          -- the one host this machine runs (server or client)
local sEnRole          -- "host" or "join"
local sEnPeer          -- the connected peer handle
local sEnSent, sEnGotText, sEnGotEcho
-- C: torrent seed/leech
local sShareTorrent, sLeechTorrent, sLeechHash, sLeechDone
-- D: rp1
local sRp1Room, sRp1Peers, sRp1Sent, sRp1Got
-- E: dc over the DHT
local sEKeys           -- btDhtKeypair array (the room code IS the seed)
local sERole           -- "host" or "join"
local sEPhase          -- "", "gathering", "publish", "fetch-offer", "waiting-answer", "open", "done"
local sENonce, sEPeer, sEChan, sEChunks, sEWant, sENextFetch, sESentHello
-- F: tor
local sTorHandle       -- the transport-listen service handle
local sTorStream       -- the dialing (client) stream
local sTorGotEcho, sTorConnectTries

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   cpBuild
   cpProbe
   if sPolling is not "true" then
      put "true" into sPolling
      send "cpPump" to me in kPollMs milliseconds
   end if
end openStack

on closeStack
   local tErr
   put empty into sPolling
   try
      if sSession is an integer and sSession > 0 then
         btStopSession sSession
      end if
   catch tErr
   end try
   put empty into sSession
   try
      if sDcReady is "true" then
         dcCleanup
      end if
   catch tErr
   end try
   put empty into sDcReady
   try
      if sEnHost is an integer and sEnHost > 0 then
         enHostDestroy sEnHost
      end if
      enDeinitialize
   catch tErr
   end try
   put empty into sEnHost
   try
      oxShutdown
   catch tErr
   end try
end closeStack

on mouseUp
   switch the short name of the target
      case "cpARun"
         cpARun
         break
      case "cpBHost"
         cpBStart "host"
         break
      case "cpBJoin"
         cpBStart "join"
         break
      case "cpCShare"
         cpCShare
         break
      case "cpCFetch"
         cpCFetch
         break
      case "cpCSaveDrop"
         cpCSaveDrop
         break
      case "cpCResume"
         cpCResume
         break
      case "cpDJoin"
         cpDJoin
         break
      case "cpDSend"
         cpDSend
         break
      case "cpEHost"
         cpEStart "host"
         break
      case "cpEJoin"
         cpEStart "join"
         break
      case "cpFLaunch"
         cpFLaunch
         break
      case "cpFEcho"
         cpFEcho
         break
      case "cpFStop"
         cpFStop
         break
      default
         pass mouseUp
   end switch
end mouseUp

-- ---- UI ----------------------------------------------------------------------
command cpBuild
   if there is a field "uiTitle" then
      exit cpBuild
   end if
   lock screen
   uiChrome "Suite closing pass - the remaining runbook legs", 780, 1010

   uiSection "cpSecA", "A. DataChannel local async (single machine; the last static harness halves)", "16,58,764,76"
   uiButton "cpARun", "Run A", "16,80,120,104"
   uiArea "cpAOut", "130,80,764,168"

   uiSection "cpSecB", "B. ENet chat, two machines (host on one, join from the other)", "16,174,764,192"
   uiLabel "cpBL1", "host ip:", "16,196,70,214", 11
   uiInput "cpBAddr", "74,196,260,216"
   uiButton "cpBHost", "Host", "270,196,340,220"
   uiButton "cpBJoin", "Join", "346,196,416,220"
   uiArea "cpBOut", "424,196,764,290"

   uiSection "cpSecC", "C. Torrent seed/leech + resume-from-disk (share on one, fetch on the other)", "16,296,764,314"
   uiButton "cpCShare", "Share", "16,318,120,342"
   uiButton "cpCFetch", "Fetch", "16,348,120,372"
   uiButton "cpCSaveDrop", "Save+drop", "16,378,120,402"
   uiButton "cpCResume", "Resume", "16,408,120,432"
   uiLabel "cpCL1", "code (infohash + payload hash):", "130,318,360,336", 11
   uiInput "cpCCode", "130,338,764,360"
   uiArea "cpCOut", "130,366,764,446"

   uiSection "cpSecD", "D. rp1 chat, two machines (same room word on both; needs the session)", "16,452,764,470"
   uiLabel "cpDL1", "room:", "16,474,60,492", 11
   uiInput "cpDRoom", "64,474,260,494"
   put "closing-pass" into field "cpDRoom"
   uiButton "cpDJoin", "Join room", "270,474,370,498"
   uiButton "cpDSend", "Send", "376,474,446,498"
   uiArea "cpDOut", "454,474,764,560"

   uiSection "cpSecE", "E. DataChannel chat SIGNALED OVER THE DHT (host mints the code; join pastes it)", "16,566,764,584"
   uiLabel "cpEL1", "room code (64 hex):", "16,588,150,606", 11
   uiInput "cpECode", "154,588,560,608"
   uiButton "cpEHost", "Host", "566,588,636,612"
   uiButton "cpEJoin", "Join", "642,588,712,612"
   uiArea "cpEOut", "16,616,764,710"

   uiSection "cpSecF", "F. Tor, single machine: Mode B launch + a live onion echo (needs onionxt in use)", "16,716,764,734"
   uiLabel "cpFL1", "tor binary:", "16,738,90,756", 11
   uiInput "cpFTorPath", "94,738,560,758"
   uiButton "cpFLaunch", "Launch", "566,738,660,762"
   uiButton "cpFStop", "Stop tor", "666,738,764,762"
   uiLabel "cpFL2", "data dir:", "16,762,90,780", 11
   uiInput "cpFDataDir", "94,762,560,782"
   uiButton "cpFEcho", "Onion echo", "566,768,764,792"
   uiArea "cpFOut", "16,788,764,900"

   uiFooter \
         "One torrent session per process: close other torrent stacks, and" \
         & " restart OXT before re-pasting this script. Two-machine legs" \
         & " need both machines online together; the DHT needs a minute to" \
         & " bootstrap before C, D and E find anything (watch the status" \
         & " line). Every PASS line here is a runbook record - copy each" \
         & " section's text back.", \
         "16,908,764,1000"
   put cpTempDir() & "/closing-tor" into field "cpFDataDir"
   unlock screen
end cpBuild

command cpProbe
   local tMissing, tErr
   put empty into tMissing
   try
      get sxVersion()
   catch tErr
      put " sodiumxt" after tMissing
   end try
   try
      get enLibraryVersion()
   catch tErr
      put " enetxt" after tMissing
   end try
   try
      get dcLibraryVersion()
   catch tErr
      put " datachannelxt" after tMissing
   end try
   try
      get btListenPort(0)
   catch tErr
      put " torrentxt" after tMissing
   end try
   if tMissing is empty then
      uiStatus "Ready: sodiumxt + torrentxt + enetxt + datachannelxt present. Section F additionally needs onionxt in the message path.", "ok"
   else
      uiStatus "Missing:" && tMissing & ". Sections needing them will refuse; the rest still run.", "warn"
   end if
end cpProbe

command cpSay pField, pText
   put pText & return after field pField
end cpSay

-- ---- the one pump ------------------------------------------------------------
-- One standing chain drains every queue this stack owns: btPoll and
-- btRp1Poll (separate queues, both every tick), dcPoll, and the enet hosts.
-- Each drain rides its own try so one bad tick cannot break the chain and
-- orphan the session (trap 5.1.1).
command cpPump
   local tEvents, tEvent, tErr
   if sPolling is not "true" then
      exit cpPump
   end if
   if sSession is an integer and sSession > 0 then
      try
         put btPoll(sSession) into tEvents
         repeat for each element tEvent in tEvents
            cpOnBtEvent tEvent
         end repeat
      catch tErr
      end try
      try
         put btRp1Poll(sSession) into tEvents
         repeat for each element tEvent in tEvents
            cpOnRp1Event tEvent
         end repeat
      catch tErr
      end try
   end if
   if sDcReady is "true" then
      try
         put dcPoll() into tEvents
         repeat for each element tEvent in tEvents
            cpOnDcEvent tEvent
         end repeat
      catch tErr
      end try
   end if
   if sEnHost is an integer and sEnHost > 0 then
      try
         put enPoll(sEnHost) into tEvents
         repeat for each element tEvent in tEvents
            cpOnEnEvent tEvent
         end repeat
      catch tErr
      end try
   end if
   cpETick
   send "cpPump" to me in kPollMs milliseconds
end cpPump

-- The shared torrent session: started once, DHT + rp1 armed immediately
-- (btRp1Enable must precede the rendezvous swarm add).
command cpEnsureSession
   local tSession, tErr
   if sSession is an integer and sSession > 0 then
      exit cpEnsureSession
   end if
   try
      put btStartSession() into tSession
      if tSession > 0 then
         put tSession into sSession
         btSetBool sSession, "enable_dht", true
         btSetBool sSession, "enable_lsd", true
         btDhtAddBootstrap sSession, "router.bittorrent.com", 6881
         btDhtAddBootstrap sSession, "router.utorrent.com", 6881
         btDhtAddBootstrap sSession, "dht.transmissionbt.com", 6881
         btRp1Enable sSession
         uiStatus "Torrent session up; DHT bootstrapping (give it a minute before C/D/E).", "ok"
      else
         uiStatus "btStartSession refused: another torrent stack holds THE session (trap 5.1). Restart OXT.", "bad"
      end if
   catch tErr
      uiStatus "No torrentxt:" && tErr, "bad"
   end try
end cpEnsureSession

command cpOnBtEvent pEvent
   switch pEvent["name"]
      case "dhtBootstrap"
         uiStatus "DHT bootstrapped.", "ok"
         break
      case "metadataReceived"
         if sLeechTorrent is an integer and sLeechTorrent > 0 then
            cpSay "cpCOut", "metadata arrived:" && pEvent["torrentName"]
         end if
         break
      case "torrentFinished"
         cpCFinished pEvent["torrent"]
         break
      case "resumeDataReady"
         cpCResumeReady pEvent["resumeData"]
         break
      case "dhtMutableItem"
         cpEOnMutable pEvent
         break
      case "dhtImmutableItem"
         cpEOnImmutable pEvent
         break
   end switch
end cpOnBtEvent

-- ---- A: datachannel local async ---------------------------------------------
-- The member harness's still-static live halves, driven the same way its
-- async loopback drives them; a green A is the evidence those labels flip on.
command cpARun
   local tErr
   put empty into field "cpAOut"
   try
      dcInit
      put "true" into sDcReady
   catch tErr
      cpSay "cpAOut", "datachannelxt missing:" && tErr
      exit cpARun
   end try
   put dcCreatePeer("") into sAPeerA
   put dcCreatePeer("") into sAPeerB
   put dcCreateChannel(sAPeerA, "closing") into sAChanA
   put empty into sAChanB
   put empty into sAOpenA
   put empty into sAOpenB
   put empty into sAGotText
   put empty into sAGotBytes
   put empty into sAGotLow
   put empty into sABigLen
   put "opening" into sAPhase
   cpSay "cpAOut", "loopback negotiating..."
end cpARun

command cpOnDcEvent pEvent
   local tDest, tPair, tOk
   -- the in-process shuttle for section A only; section E ships blobs via
   -- the DHT instead, so its peers never appear in this branch
   if pEvent["name"] is "dcLocalDescription" then
      put cpAOther(pEvent["peer"]) into tDest
      if tDest is not empty then
         dcSetRemoteDescription tDest, pEvent["sdp"], pEvent["sdpType"]
      end if
   else if pEvent["name"] is "dcLocalCandidate" then
      put cpAOther(pEvent["peer"]) into tDest
      if tDest is not empty then
         dcAddRemoteCandidate tDest, pEvent["candidate"], pEvent["mid"]
      end if
   else if pEvent["name"] is "dcChannelIncoming" then
      if pEvent["peer"] is sAPeerB and sAChanB is empty then
         put pEvent["channel"] into sAChanB
      end if
      if sERole is not empty and pEvent["peer"] is sEPeer then
         put pEvent["channel"] into sEChan
      end if
   else if pEvent["name"] is "dcChannelOpen" then
      if pEvent["channel"] is sAChanA then
         put "true" into sAOpenA
      else if sAChanB is not empty and pEvent["channel"] is sAChanB then
         put "true" into sAOpenB
      end if
      if sEChan is not empty and pEvent["channel"] is sEChan then
         cpEOpen
      end if
   else if pEvent["name"] is "dcMessage" then
      cpOnDcMessage pEvent
   else if pEvent["name"] is "dcBufferedLow" then
      if pEvent["channel"] is sAChanA then
         put "true" into sAGotLow
      end if
   else if pEvent["name"] is "dcGatheringStateChange" then
      cpEOnGathering pEvent
   end if
   cpAAdvance
end cpOnDcEvent

command cpOnDcMessage pEvent
   if pEvent["channel"] is sAChanB or pEvent["channel"] is sAChanA then
      if pEvent["text"] is not empty then
         put pEvent["text"] into sAGotText
      else
         put pEvent["payload"] into sAGotBytes
      end if
   else if sEChan is not empty and pEvent["channel"] is sEChan then
      cpSay "cpEOut", "them:" && pEvent["text"]
      if sESentHello is "true" then
         cpSay "cpEOut", "PASS text both directions over the DHT-signaled channel"
         put "done" into sEPhase
      end if
   end if
end cpOnDcMessage

command cpAAdvance
   local tPair, tCap
   if sAPhase is "opening" then
      if sAOpenA is "true" and sAOpenB is "true" then
         cpSay "cpAOut", "PASS loopback connected, both channels open"
         put dcSelectedCandidatePair(sAPeerA) into tPair
         cpSay "cpAOut", "PASS live dcSelectedCandidatePair:" && tPair["localCandidate"]
         cpSay "cpAOut", "PASS live dcBufferedAmount >= 0:" && dcBufferedAmount(sAChanA)
         if dcLocalDescription(sAPeerA) contains "a=candidate" then
            cpSay "cpAOut", "PASS local description carries a=candidate"
         else
            cpSay "cpAOut", "FAIL local description carries a=candidate"
         end if
         if dcLocalDescriptionType(sAPeerA) is "offer" and dcLocalDescriptionType(sAPeerB) is "answer" then
            cpSay "cpAOut", "PASS offer/answer roles match the flow"
         else
            cpSay "cpAOut", "FAIL offer/answer roles"
         end if
         get dcSetBufferedLowThreshold(sAChanA, 4096)
         get dcSendText(sAChanA, "live-text")
         put "text" into sAPhase
      end if
   else if sAPhase is "text" then
      if sAGotText is "live-text" then
         cpSay "cpAOut", "PASS live dcSendText round-tripped"
         put dcChannelMaxMessage(sAChanA) into tCap
         put tCap into sABigLen
         get dcSendData(sAChanA, cpRepeatByte(66, tCap))
         put "low" into sAPhase
      end if
   else if sAPhase is "low" then
      if sAGotLow is "true" and the number of bytes of sAGotBytes is sABigLen then
         cpSay "cpAOut", "PASS dcBufferedLow fired after the cap-sized send (" & sABigLen && "bytes arrived whole)"
         if dcGatheringState(sAPeerA) is 2 and dcGatheringState(sAPeerB) is 2 then
            cpSay "cpAOut", "PASS live dcGatheringState is complete (2) on both peers"
         else
            cpSay "cpAOut", "FAIL live dcGatheringState"
         end if
         get dcCloseChannel(sAChanA)
         dcFreeChannel sAChanA
         dcFreePeer sAPeerA
         dcFreePeer sAPeerB
         cpSay "cpAOut", "PASS teardown clean - SECTION A COMPLETE"
         put "done" into sAPhase
      end if
   end if
end cpAAdvance

function cpAOther pPeer
   if pPeer is sAPeerA then
      return sAPeerB
   else if pPeer is sAPeerB then
      return sAPeerA
   end if
   return empty
end cpAOther

-- ---- B: enet two-machine chat -------------------------------------------------
command cpBStart pRole
   local tErr
   put empty into field "cpBOut"
   try
      get enInitialize()
   catch tErr
      cpSay "cpBOut", "enetxt missing:" && tErr
      exit cpBStart
   end try
   put pRole into sEnRole
   put empty into sEnPeer
   put empty into sEnSent
   put empty into sEnGotText
   put empty into sEnGotEcho
   if pRole is "host" then
      put enHostCreateServer("0.0.0.0", kEnetPort, 8, 2, 0, 0) into sEnHost
      cpSay "cpBOut", "hosting on UDP" && kEnetPort & "; join from the other machine with this machine's LAN ip"
   else
      put enHostCreateClient(1, 2, 0, 0) into sEnHost
      put enConnect(sEnHost, word 1 of field "cpBAddr", kEnetPort, 2, 99) into sEnPeer
      cpSay "cpBOut", "connecting to" && word 1 of field "cpBAddr" & ":" & kEnetPort & "..."
   end if
end cpBStart

command cpOnEnEvent pEvent
   local tBin
   switch pEvent["name"]
      case "enetConnect"
         if sEnRole is "host" then
            put pEvent["peer"] into sEnPeer
            cpSay "cpBOut", "PASS peer connected from" && pEvent["address"]
         else
            cpSay "cpBOut", "PASS connected to the host"
            get enSendText(sEnPeer, 0, kEnetHello, 0)
            put textEncode("bin", "utf-8") & numToByte(0) & numToByte(1) & textEncode("tail", "utf-8") into tBin
            get enSend(sEnPeer, 1, tBin, 0)
            put "true" into sEnSent
         end if
         break
      case "enetReceive"
         if sEnRole is "host" then
            -- echo whatever arrives, same channel, so the joiner proves
            -- both directions and byte-exactness in one round trip
            get enSend(sEnPeer, pEvent["channel"], pEvent["payload"], 0)
            cpSay "cpBOut", "PASS received + echoed on channel" && pEvent["channel"]
         else
            if pEvent["channel"] is 0 then
               if textDecode(pEvent["payload"], "utf-8") is kEnetHello then
                  put "true" into sEnGotText
                  cpSay "cpBOut", "PASS text echoed byte-exact across the LAN"
               end if
            else
               set the caseSensitive to true
               put textEncode("bin", "utf-8") & numToByte(0) & numToByte(1) & textEncode("tail", "utf-8") into tBin
               if pEvent["payload"] is tBin then
                  put "true" into sEnGotEcho
                  cpSay "cpBOut", "PASS binary (incl. NUL) echoed byte-exact - SECTION B COMPLETE; close with the window to disconnect gracefully"
               end if
            end if
         end if
         break
      case "enetDisconnect"
         cpSay "cpBOut", "PASS graceful disconnect observed (data" && pEvent["data"] & ")"
         break
   end switch
end cpOnEnEvent

-- ---- C: torrent seed/leech + resume -------------------------------------------
command cpCShare
   local tDir, tFile, tPayload, tMeta, tHash, tErr
   cpEnsureSession
   if sSession is not an integer or sSession <= 0 then
      exit cpCShare
   end if
   put empty into field "cpCOut"
   try
      put cpTempDir() & "/" & kShareFolder into tDir
      if there is no folder tDir then
         create folder tDir
      end if
      -- a patterned ~180 KB payload: deterministic to WRITE, but verified by
      -- HASH on the fetch side, so the transfer is proven, not assumed
      put "closing-pass payload " & the seconds & " " into tPayload
      repeat 13 times
         put tPayload after tPayload
      end repeat
      put tDir & "/" & kPayloadFile into tFile
      put tPayload into url ("binfile:" & tFile)
      put btCreateTorrent(tDir, 0, 0, "") into tMeta
      if the number of bytes of tMeta is 0 then
         cpSay "cpCOut", "btCreateTorrent failed:" && btLastError()
         exit cpCShare
      end if
      -- add pointing at the PARENT so libtorrent rechecks + seeds
      put btAddTorrentFile(sSession, tMeta, cpTempDir()) into sShareTorrent
      put textDecode(sxBin2Hex(sxHashFile(tFile, 32)), "ascii") into tHash
      put btInfoHash(sShareTorrent) && tHash into field "cpCCode"
      cpSay "cpCOut", "seeding; the code above carries the infohash + the payload's BLAKE2b-256. Paste it on the other machine and Fetch."
   catch tErr
      cpSay "cpCOut", "share failed:" && tErr
   end try
end cpCShare

command cpCFetch
   local tCode, tErr
   cpEnsureSession
   if sSession is not an integer or sSession <= 0 then
      exit cpCFetch
   end if
   put empty into field "cpCOut"
   put field "cpCCode" into tCode
   if the number of words of tCode is not 2 or the number of chars of word 1 of tCode is not 40 then
      cpSay "cpCOut", "paste the two-part code from the sharing machine first"
      exit cpCFetch
   end if
   put word 2 of tCode into sLeechHash
   put empty into sLeechDone
   try
      put btAddMagnet(sSession, "magnet:?xt=urn:btih:" & word 1 of tCode, cpTempDir()) into sLeechTorrent
      cpSay "cpCOut", "fetching via the DHT (trackerless); metadata + pieces will report here..."
   catch tErr
      cpSay "cpCOut", "fetch failed:" && tErr
   end try
end cpCFetch

command cpCFinished pTorrent
   local tHash
   if pTorrent is sShareTorrent then
      cpSay "cpCOut", "PASS share rechecked complete - now seeding"
      exit cpCFinished
   end if
   if pTorrent is not sLeechTorrent or sLeechDone is "true" then
      exit cpCFinished
   end if
   put "true" into sLeechDone
   put textDecode(sxBin2Hex(sxHashFile(cpTempDir() & "/" & kShareFolder & "/" & kPayloadFile, 32)), "ascii") into tHash
   if tHash is sLeechHash then
      cpSay "cpCOut", "PASS download complete and the payload hash MATCHES the sharer's - exact bytes via the real swarm. SECTION C's transfer leg COMPLETE"
   else
      cpSay "cpCOut", "FAIL hash mismatch: got" && tHash
   end if
end cpCFinished

-- Mid-download resume: ask for resume data; when it arrives (async) it is
-- written to DISK and the torrent removed. Resume re-adds from the file -
-- in this launch, or after quitting OXT entirely, which is the plan's
-- restart gate.
command cpCSaveDrop
   if sLeechTorrent is not an integer or sLeechTorrent <= 0 then
      cpSay "cpCOut", "nothing to save: Fetch first (and click before it finishes)"
      exit cpCSaveDrop
   end if
   get btSaveResumeData(sLeechTorrent)
   cpSay "cpCOut", "resume data requested (async)..."
end cpCSaveDrop

command cpCResumeReady pBytes
   put pBytes into url ("binfile:" & cpTempDir() & "/" & kResumeFile)
   get btRemoveTorrent(sSession, sLeechTorrent, false)
   put empty into sLeechTorrent
   cpSay "cpCOut", "PASS resume data (" & the number of bytes of pBytes && "bytes) saved to disk and the torrent dropped. Resume now - or quit OXT, relaunch, re-paste, Start session, and Resume: that is the restart gate."
end cpCResumeReady

command cpCResume
   local tBytes, tErr
   cpEnsureSession
   if sSession is not an integer or sSession <= 0 then
      exit cpCResume
   end if
   try
      put url ("binfile:" & cpTempDir() & "/" & kResumeFile) into tBytes
      if the number of bytes of tBytes is 0 then
         cpSay "cpCOut", "no saved resume file found"
         exit cpCResume
      end if
      put btAddTorrentWithResume(sSession, tBytes, cpTempDir()) into sLeechTorrent
      if field "cpCCode" is not empty then
         put word 2 of field "cpCCode" into sLeechHash
      end if
      put empty into sLeechDone
      cpSay "cpCOut", "PASS re-added from saved resume data - progress restores and completion will hash-verify"
   catch tErr
      cpSay "cpCOut", "resume failed:" && tErr
   end try
end cpCResume

-- ---- D: rp1 two-machine chat --------------------------------------------------
command cpDJoin
   local tRoom, tId, tErr
   cpEnsureSession
   if sSession is not an integer or sSession <= 0 then
      exit cpDJoin
   end if
   put empty into field "cpDOut"
   put empty into sRp1Peers
   put empty into sRp1Sent
   put empty into sRp1Got
   put word 1 of field "cpDRoom" into tRoom
   put cpToHex(sha1Digest(tRoom)) into tId
   put tId into sRp1Room
   try
      get btAddInfohash(sSession, tId, cpTempDir())
      btDhtAnnounce sSession, tId, 0
      cpSay "cpDOut", "rendezvous" && char 1 to 12 of tId & "...; waiting for the other machine (both must be in the room)"
   catch tErr
      cpSay "cpDOut", "join failed:" && tErr
   end try
end cpDJoin

command cpOnRp1Event pEvent
   local tPeer
   put pEvent["peer"] into tPeer
   switch pEvent["name"]
      case "rp1PeerConnected"
         cpSay "cpDOut", "peer connected:" && pEvent["endpoint"]
         break
      case "rp1Handshake"
         if pEvent["supportsRp1"] is "1" then
            put "1" into sRp1Peers[tPeer]
            cpSay "cpDOut", "PASS rp1 handshake with peer" && tPeer
            cpDSend
         end if
         break
      case "rp1Message"
         put "true" into sRp1Got
         cpSay "cpDOut", "them:" && textDecode(pEvent["payload"], "utf-8")
         if sRp1Sent is "true" then
            cpSay "cpDOut", "PASS rp1 messages both directions - SECTION D COMPLETE"
         end if
         break
      case "rp1PeerDisconnected"
         delete variable sRp1Peers[tPeer]
         cpSay "cpDOut", "peer" && tPeer && "left"
         break
   end switch
end cpOnRp1Event

command cpDSend
   local tPeer
   if sSession is not an integer or sSession <= 0 then
      exit cpDSend
   end if
   repeat for each key tPeer in sRp1Peers
      btRp1Send sSession, tPeer, textEncode("rp1 hello from the closing pass", "utf-8")
      put "true" into sRp1Sent
   end repeat
   if sRp1Sent is "true" then
      cpSay "cpDOut", "sent"
   end if
end cpDSend

-- ---- E: datachannel over the DHT ----------------------------------------------
-- The riptide-proven substrate carrying WebRTC signaling: non-trickle SDP
-- blobs as chunked immutable items under a mutable head, one salt per role.
command cpEStart pRole
   local tKp, tCode, tErr
   cpEnsureSession
   if sSession is not an integer or sSession <= 0 then
      exit cpEStart
   end if
   put empty into field "cpEOut"
   try
      dcInit
      put "true" into sDcReady
   catch tErr
      cpSay "cpEOut", "datachannelxt missing:" && tErr
      exit cpEStart
   end try
   put pRole into sERole
   put empty into sEChan
   put empty into sESentHello
   put empty into sEChunks
   put empty into sEWant
   put the milliseconds into sENextFetch
   if pRole is "host" then
      put btDhtKeypair("") into sEKeys
      put sEKeys["seed"] into field "cpECode"
      put "h" & the milliseconds into sENonce
      put dcCreatePeer("stun:stun.l.google.com:19302") into sEPeer
      put dcCreateChannel(sEPeer, "closing-dht") into sEChan
      put "gathering" into sEPhase
      cpSay "cpEOut", "code minted (share it with the join side); gathering, then publishing the offer..."
   else
      put word 1 of field "cpECode" into tCode
      if the number of chars of tCode is not 64 then
         cpSay "cpEOut", "paste the 64-hex room code from the host first"
         exit cpEStart
      end if
      put btDhtKeypair(tCode) into sEKeys
      put "j" & the milliseconds into sENonce
      put "fetch-offer" into sEPhase
      cpSay "cpEOut", "fetching the offer from the DHT..."
   end if
end cpEStart

command cpEOnGathering pEvent
   if pEvent["peer"] is not sEPeer or pEvent["state"] is not 2 then
      exit cpEOnGathering
   end if
   if sEPhase is "gathering" then
      cpEPublish
   end if
end cpEOnGathering

command cpEPublish
   local tSalt, tBody, tZip, tChunk, tTargets, tHead, tStart
   if sERole is "host" then
      put kSaltOffer into tSalt
      put "waiting-answer" into sEPhase
   else
      put kSaltAnswer into tSalt
      put "open" into sEPhase
   end if
   put sENonce & linefeed & dcLocalDescriptionType(sEPeer) & linefeed & dcLocalDescription(sEPeer) into tBody
   put compress(textEncode(tBody, "UTF-8")) into tZip
   -- ALWAYS chunked (uniform path): 900-byte immutable pieces, the mutable
   -- head carrying the comma list of their 40-hex targets
   put empty into tTargets
   put 1 into tStart
   repeat while tStart <= the number of bytes of tZip
      put byte tStart to (tStart + kChunkMax - 1) of tZip into tChunk
      if tTargets is not empty then
         put comma after tTargets
      end if
      put btDhtPutImmutable(sSession, tChunk) after tTargets
      add kChunkMax to tStart
   end repeat
   put textEncode(kHeadMagic & tTargets, "UTF-8") into tHead
   get btDhtPutMutable(sSession, sEKeys["publicKey"], sEKeys["secretKey"], tSalt, tHead)
   cpSay "cpEOut", "published" && dcLocalDescriptionType(sEPeer) && "as" && (the number of items of tTargets) && "chunk(s)"
end cpEPublish

-- The standing re-request: while a slot is awaited, ask the DHT again every
-- few seconds (propagation is eventual; the first get usually misses).
command cpETick
   local tSalt
   if sSession is not an integer or sSession <= 0 then
      exit cpETick
   end if
   if sEPhase is not "fetch-offer" and sEPhase is not "waiting-answer" then
      exit cpETick
   end if
   if the milliseconds < sENextFetch then
      exit cpETick
   end if
   put the milliseconds + kRefetchMs into sENextFetch
   if sEPhase is "fetch-offer" then
      put kSaltOffer into tSalt
   else
      put kSaltAnswer into tSalt
   end if
   get btDhtGetMutable(sSession, sEKeys["publicKey"], tSalt)
end cpETick

command cpEOnMutable pEvent
   local tHeadText
   if sERole is empty or pEvent["publicKey"] is not sEKeys["publicKey"] then
      exit cpEOnMutable
   end if
   if sEPhase is "fetch-offer" and pEvent["salt"] is kSaltOffer then
      put textDecode(pEvent["value"], "UTF-8") into tHeadText
      cpEWantChunks tHeadText
   else if sEPhase is "waiting-answer" and pEvent["salt"] is kSaltAnswer then
      put textDecode(pEvent["value"], "UTF-8") into tHeadText
      cpEWantChunks tHeadText
   end if
end cpEOnMutable

command cpEWantChunks pHeadText
   local tList, tTarget
   if char 1 to 4 of pHeadText is not kHeadMagic then
      exit cpEWantChunks
   end if
   put char 5 to -1 of pHeadText into tList
   if tList is sEWant then
      exit cpEWantChunks
   end if
   put tList into sEWant
   put empty into sEChunks
   repeat for each item tTarget in tList
      get btDhtGetImmutable(sSession, tTarget)
   end repeat
   cpSay "cpEOut", "head arrived:" && (the number of items of tList) && "chunk(s) to fetch"
end cpEWantChunks

command cpEOnImmutable pEvent
   local tTarget, tZip, tBody, tNonce, tType, tSdp, tR
   if sEWant is empty then
      exit cpEOnImmutable
   end if
   put pEvent["target"] into tTarget
   if tTarget is not among the items of sEWant then
      exit cpEOnImmutable
   end if
   put pEvent["value"] into sEChunks[tTarget]
   -- assemble once every wanted chunk is present, in list order
   repeat for each item tTarget in sEWant
      if sEChunks[tTarget] is empty then
         exit cpEOnImmutable
      end if
      put sEChunks[tTarget] after tZip
   end repeat
   put textDecode(decompress(tZip), "UTF-8") into tBody
   put line 1 of tBody into tNonce
   put line 2 of tBody into tType
   put line 3 to -1 of tBody into tSdp
   if tNonce is sENonce then
      exit cpEOnImmutable
   end if
   put empty into sEWant
   if sERole is "join" and tType is "offer" then
      put dcCreatePeer("stun:stun.l.google.com:19302") into sEPeer
      put dcSetRemoteDescription(sEPeer, tSdp, "offer") into tR
      put "gathering" into sEPhase
      cpSay "cpEOut", "offer applied; answering..."
   else if sERole is "host" and tType is "answer" then
      put dcSetRemoteDescription(sEPeer, tSdp, "answer") into tR
      put "open" into sEPhase
      cpSay "cpEOut", "answer applied; waiting for the channel..."
   end if
end cpEOnImmutable

command cpEOpen
   local tPair
   put dcSelectedCandidatePair(sEPeer) into tPair
   cpSay "cpEOut", "PASS channel OPEN across machines; selected pair:" && tPair["localCandidate"]
   cpSay "cpEOut", "(a srflx/prflx pair here is cross-NAT evidence; host/host means one LAN)"
   get dcSendText(sEChan, "dc-dht hello from" && sERole)
   put "true" into sESentHello
end cpEOpen

-- ---- F: tor - Mode B + onion echo ---------------------------------------------
command cpFLaunch
   local tPath, tDir, tErr, tR
   put word 1 to -1 of field "cpFTorPath" into tPath
   put word 1 to -1 of field "cpFDataDir" into tDir
   if tPath is empty then
      cpSay "cpFOut", "point the tor-binary field at a real tor executable first"
      exit cpFLaunch
   end if
   try
      if there is no folder tDir then
         create folder tDir
      end if
      oxSetCallbackOwner the long id of this card
      oxSetStatusCallback "cpOnTorStatus"
      oxSetPeerCallback "cpOnTorPeer"
      oxLaunchTor tPath, tDir, "", ""
      put the result into tR
      if tR is not empty then
         cpSay "cpFOut", "oxLaunchTor refused:" && tR
         exit cpFLaunch
      end if
      cpSay "cpFOut", "PASS oxLaunchTor accepted (torrc written, process started; processId" && the processId & ")"
      put 0 into sTorConnectTries
      send "cpFConnect" to me in 2000 milliseconds
   catch tErr
      cpSay "cpFOut", "launch failed (is onionxt in use?):" && tErr
   end try
end cpFLaunch

-- The control port takes a moment to open and write its cookie; retry the
-- connect until it authenticates, and give up loudly rather than forever.
command cpFConnect
   local tR
   if oxIsControlAuthenticated() then
      exit cpFConnect
   end if
   add 1 to sTorConnectTries
   oxConnectControl
   put the result into tR
   if tR is empty then
      cpSay "cpFOut", "control connecting..."
   else if sTorConnectTries < 15 then
      send "cpFConnect" to me in 2000 milliseconds
   else
      cpSay "cpFOut", "control never opened:" && tR
   end if
end cpFConnect

on cpOnTorStatus pKind, pInfo
   if pKind is "control" then
      if pInfo is "authenticated" then
         cpSay "cpFOut", "PASS control connected + authenticated (SAFECOOKIE against the LAUNCHED tor)"
      else
         cpSay "cpFOut", "control:" && pInfo
      end if
   else if pKind is "bootstrap" then
      uiStatus "tor bootstrap:" && pInfo & "%", empty
      if pInfo is 100 then
         cpSay "cpFOut", "PASS Bootstrapped 100% - MODE B (runbook item 4) COMPLETE; the onion echo can run now"
      end if
   else if pKind is "service" then
      cpSay "cpFOut", "onion address:" && pInfo
   else if pKind is "serviceReady" then
      cpSay "cpFOut", "PASS descriptor uploaded (serviceReady); dialing our own onion through the Tor network..."
      cpFDial
   end if
end cpOnTorStatus

command cpFEcho
   local tErr
   if not oxIsReady() then
      cpSay "cpFOut", "wait for bootstrap 100% first"
      exit cpFEcho
   end if
   put empty into sTorGotEcho
   try
      oxTransportListen sxRandomBytes(32), 80, 9099
      put the result into sTorHandle
      if sTorHandle is not an integer then
         cpSay "cpFOut", "listen refused:" && sTorHandle
         put empty into sTorHandle
         exit cpFEcho
      end if
      cpSay "cpFOut", "listening; publishing the service (descriptor upload takes a minute)..."
   catch tErr
      cpSay "cpFOut", "listen failed:" && tErr
   end try
end cpFEcho

command cpFDial
   local tAddr, tR
   put oxServiceAddress(sTorHandle) into tAddr
   if tAddr is empty then
      cpSay "cpFOut", "no address yet; will retry on serviceReady"
      exit cpFDial
   end if
   oxTransportDial tAddr, 80
   put the result into sTorStream
   if sTorStream is not an integer then
      cpSay "cpFOut", "dial failed:" && sTorStream
      exit cpFDial
   end if
   oxTransportRecv sTorStream, "cpTorClientStream"
end cpFDial

on cpOnTorPeer pStream, pService, pPeerAddr
   -- inbound side of our own dial, arriving through the real Tor network;
   -- echo every byte straight back
   oxTransportRecv pStream, "cpTorServerStream"
end cpOnTorPeer

on cpTorServerStream pStream, pEvent, pData
   if pEvent is "data" then
      oxTransportSend pStream, pData
   end if
end cpTorServerStream

on cpTorClientStream pStream, pEvent, pData
   if pEvent is "open" then
      oxTransportSend pStream, textEncode(kTorPing, "utf-8")
   else if pEvent is "data" then
      if textDecode(pData, "utf-8") is kTorPing then
         put "true" into sTorGotEcho
         cpSay "cpFOut", "PASS exact bytes echoed through the LIVE TOR NETWORK (listen + dial + send + recv all live) - SECTION F's echo COMPLETE"
      end if
   else if pEvent is "error" then
      cpSay "cpFOut", "stream error:" && pData
   end if
end cpTorClientStream

command cpFStop
   local tErr
   try
      oxStopTor
      oxStopTor
      cpSay "cpFOut", "PASS oxStopTor sent (twice: the duplicate is a harmless no-op)"
   catch tErr
      cpSay "cpFOut", "stop failed:" && tErr
   end try
end cpFStop

-- ---- helpers ------------------------------------------------------------------
function cpTempDir
   local tDir
   put specialFolderPath("temporary") into tDir
   if tDir is empty then
      put specialFolderPath("documents") into tDir
   end if
   if char -1 of tDir is "/" then
      delete char -1 of tDir
   end if
   put tDir & "/suite-closing-pass" into tDir
   if there is no folder tDir then
      create folder tDir
   end if
   return tDir
end cpTempDir

-- 20 raw bytes to 40 lowercase hex without binaryEncode format folklore
-- (the rp1-chat discipline).
function cpToHex pData
   local tHex, tI, tByte
   put empty into tHex
   repeat with tI = 1 to the number of bytes of pData
      put byteToNum(byte tI of pData) into tByte
      put char (tByte div 16 + 1) of "0123456789abcdef" after tHex
      put char (tByte mod 16 + 1) of "0123456789abcdef" after tHex
   end repeat
   return tHex
end cpToHex

-- pCount copies of byte pCode, by doubling (no string-escape folklore).
function cpRepeatByte pCode, pCount
   local tOut
   put numToByte(pCode) into tOut
   repeat while the number of bytes of tOut < pCount
      put tOut & tOut into tOut
   end repeat
   return byte 1 to pCount of tOut
end cpRepeatByte
