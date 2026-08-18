script "enetSelfTest"

-- enet-selftest.livecodescript - a self-building RUNTIME harness that drives
-- the enetxt public API in OXT and reports PASS / FAIL per
-- handler. This is the OXT-pass companion to the C++ smoke test: the smoke
-- test proves the shim against ENet in CI; this proves the .lcb BINDING (the
-- foreign-decl signatures, the record walkers, the buffer round-trips)
-- actually runs - the one layer CI cannot reach, since OXT has no headless
-- way to compile or run .lcb.
--
-- COVERAGE NOTE (honest): every public en* handler is now driven here.
-- enDisconnectNow, enResetPeer, enSetPeerTimeout, and enSetHostBandwidth run
-- in their own isolated section (a client host pointed at a dead port, so an
-- abrupt teardown cannot perturb the graceful loopback below), and
-- enHostStatus is asserted BOTH stale (empty) and live (peerCount, address).
-- The isolated section became a RUNTIME RESULT on 2026-08-10: this file's
-- synchronous half ran green on a real engine (21 checks, twice in one day),
-- folded into the suite selftest at the repository root, and all four abrupt
-- teardown handlers returned 0 against a live client host. And the async
-- loopback closed too: on 2026-08-13 THIS file ran STANDALONE on a real
-- engine, green end to end - the live enHostStatus pair (connected, then
-- zero peers after the disconnect), the enPeerStatus statistics (rtt,
-- packetLoss, the packet/byte counters), the echo/broadcast/binary round
-- trips, and the graceful close. Nothing in this file is verified
-- statically any more; the member's one remaining un-exercised surface is
-- the LAN chat demo between two real machines (suite runbook, item 6).
--
-- HOW TO USE: open OXT, make a one-card stack, paste THIS into the STACK
-- script (Object > Stack Script), then close+reopen. It builds its own UI,
-- runs the synchronous checks, then a LIVE LOOPBACK (a server host and a
-- client host in this one process, 127.0.0.1), message round-trips, and
-- teardown - and shows a green/red list. Needs the installed
-- org.openxtalk.library.enet extension.
--
-- The LCS lessons this file was written under (the LiveCodeScript/LCB gotcha
-- list carried in the family CLAUDE.md files): no
-- braces, no subscripted function results, array emptiness by counting keys,
-- binary payloads built with numToByte (string literals have no escapes),
-- byte-exact compares under caseSensitive, and zero-argument calls BARE in
-- statement position.

-- STATUS: the SYNC half last ran GREEN in the 2026-08-17 engine pass (Windows x86_64, NT 10.0, OXT 9.6.3) - 21/21, folded into
-- tests/suite-selftest.livecodescript. The ASYNC loopback is deliberately
-- NOT folded (two state machines in one process race for the event
-- handlers) and is verified by running this file on its own.
constant kStTitle = "enetxt - API Self-Test"
constant kStWidth = 660
constant kStHeight = 620

-- ---- state -------------------------------------------------------------------
local sServer, sClient  -- the two loopback hosts
local sClientPeer       -- client side: handle from enConnect
local sServerPeer       -- server side: handle born in its enetConnect event
local sGotEcho          -- "true" once the client received the echo
local sGotUnseq         -- "true" once the client received the channel-1 line
local sGotBinary        -- the binary payload the server received (a Data)
local sSentBinary       -- what the client sent (kept for byte-exact compare)
local sSawServerDisc    -- "true" once the server drained enetDisconnect
local sDeadline         -- the async phase's drop-dead time (ms clock)
local sPhase            -- "", "connecting", "messaging", "binary", "closing", "done"

-- ---- the scaffolding (carried) ----------------------------------------------
-- ==== SUITE HARNESS SCAFFOLD v1 BEGIN (verbatim copy; master: tools/harness-scaffold.livecodescript; gate: tools/check-harness-scaffold-drift.py) ====
-- The harness scaffolding as one carried block: counters, the window, the
-- assertion plumbing, the report surface. The adopting harness declares
-- kStTitle/kStWidth/kStHeight above this block, owns openStack/stRun/
-- stCleanup, calls stResetCounters first in stRun and stReportDone when
-- the run completes. Do not edit this block in place: change the master
-- and re-carry it.
local sTotal, sPassed, sFailed, sSkipped
local sResultText          -- the accumulated PASS/FAIL/SKIP/section lines
local sStRunDone           -- "true" once the run finished (drives the color)

-- The platform's own terminal face (the demo kit's uiMonoFont, by value).
function stMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end stMonoFont

-- ---- the window (idempotent; the fold drops this half) -----------------------
command stBuild
   -- the guard is on a control this VERSION of the scaffold adds, so a stack
   -- built by an older scaffold rebuilds once and picks up the new layout
   -- (the builders re-rect existing controls by name; nothing needs deleting)
   if there is a button "stCopy" then
      exit stBuild
   end if
   lock screen
   set the width of this stack to kStWidth
   set the height of this stack to kStHeight
   set the backgroundColor of this card to "240,242,246"
   set the title of this stack to kStTitle
   stMakeLabel "stTitle", "  " & kStTitle, "0,0," & kStWidth & ",30", 15
   set the opaque of field "stTitle" to true
   set the backgroundColor of field "stTitle" to "44,90,160"
   set the foregroundColor of field "stTitle" to "255,255,255"
   set the textStyle of field "stTitle" to "bold"
   stMakeLabel "stSummary", "Running...", "16,38," & (kStWidth - 200) & ",66", 13
   set the textStyle of field "stSummary" to "bold"
   stMakeButton "stCopy", "Copy results", (kStWidth - 184) & ",38," & (kStWidth - 100) & ",64"
   stMakeButton "stRerun", "Re-run", (kStWidth - 94) & ",38," & (kStWidth - 16) & ",64"
   stMakeList "stResults", "16,72," & (kStWidth - 16) & "," & (kStHeight - 16)
   unlock screen
end stBuild

command stMakeLabel pName, pText, pRect, pSize
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
end stMakeLabel

command stMakeButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end stMakeButton

command stMakeList pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the vScrollbar of field pName to true
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to "225,229,236"
   set the opaque of field pName to true
   set the backgroundColor of field pName to "255,255,255"
   set the textSize of field pName to 11
   set the textFont of field pName to stMonoFont()
end stMakeList

-- ---- assertion plumbing (this half folds into the suite harness) -------------
command stResetCounters
   put 0 into sTotal
   put 0 into sPassed
   put 0 into sFailed
   put 0 into sSkipped
   put empty into sResultText
   put empty into sStRunDone
end stResetCounters

command stAssert pName, pOk
   add 1 to sTotal
   if pOk then
      add 1 to sPassed
      put "PASS  " & pName & return after sResultText
   else
      add 1 to sFailed
      put "FAIL  " & pName & return after sResultText
   end if
end stAssert

-- A SKIP is a first-class outcome, not a silent gap: it counts, it names
-- itself, and it says what would make it run.
command stSkip pName, pReason
   add 1 to sTotal
   add 1 to sSkipped
   put "SKIP  " & pName & "  (" & pReason & ")" & return after sResultText
end stSkip

command stSection pTitle
   put return & "== " & pTitle & " ==" & return after sResultText
end stSection

-- A section that threw is a FAIL, never a skip: a skip means "this piece is
-- not here", and something that blew up very much is.
command stSectionFailed pWhich, pError
   stAssert pWhich & " section ran to completion", false
   stNote "it raised:" && pError
   stNote "the other sections still ran; this one is a defect to report"
end stSectionFailed

command stNote pText
   put "      " & pText & return after sResultText
end stNote

command stShow
   put sResultText into field "stResults"
   put sPassed & " passed, " & sFailed & " failed, " & sSkipped & " skipped, " \
         & sTotal & " total" into field "stSummary"
   if sStRunDone is "true" then
      if sFailed is 0 then
         set the foregroundColor of field "stSummary" to "23,128,63"
      else
         set the foregroundColor of field "stSummary" to "176,58,46"
      end if
   end if
end stShow

-- paint the results list: red FAIL, green PASS, amber SKIP, muted the rest
command stPaint
   local tN, tI, tLine, tErr
   put the number of lines of field "stResults" into tN
   lock screen
   try
      repeat with tI = 1 to tN
         put line tI of field "stResults" into tLine
         if tLine begins with "FAIL" then
            set the foregroundColor of line tI of field "stResults" to "176,58,46"
         else if tLine begins with "PASS" then
            set the foregroundColor of line tI of field "stResults" to "23,128,63"
         else if tLine begins with "SKIP" then
            set the foregroundColor of line tI of field "stResults" to "150,110,40"
         else
            set the foregroundColor of line tI of field "stResults" to "138,146,158"
         end if
      end repeat
   catch tErr
   end try
   set the vScroll of field "stResults" to 0
   unlock screen
end stPaint

-- The run's one epilogue: mark done, render, paint. Synchronous harnesses
-- call this at the end of stRun; async ones from the tick that ends the run.
command stReportDone
   put "true" into sStRunDone
   stShow
   stPaint
end stReportDone

command stCopyResults
   -- The whole point of the button: the maintainer pastes the run back
   -- verbatim into the OXT-pass record, so nobody has to retype a result.
   local tError
   try
      set the clipboardData["text"] to sResultText
      answer "Results copied to the clipboard."
   catch tError
      answer "Could not reach the clipboard:" && tError
   end try
end stCopyResults

on closeStack
   stCleanup
end closeStack

on mouseUp
   if the short name of the target is "stRerun" then
      stCleanup
      stRun
   else if the short name of the target is "stCopy" then
      stCopyResults
   else
      pass mouseUp
   end if
end mouseUp
-- ==== SUITE HARNESS SCAFFOLD v1 END ====

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   stBuild
   stRun
end openStack











-- ---- the run -----------------------------------------------------------------
command stRun
   local tPS, tHS, tBig
   local tAbruptHost, tAbruptPeer, tResetPeer
   stResetCounters
   put empty into sPhase

   stSection "lifecycle & diagnostics"
   stAssert "enInitialize returns 0", enInitialize() is 0
   stAssert "enInitialize idempotent", enInitialize() is 0
   stAssert "enLibraryVersion names enet", enLibraryVersion() begins with "enet "
   enClearError
   stAssert "enLastError empty after clear", enLastError() is empty

   stSection "stale handles are harmless no-ops"
   stAssert "enSend(0) errors", enSend(0, 0, stTinyData(), 0) < 0
   stAssert "enDisconnect(0) errors", enDisconnect(0, 0) < 0
   put enPeerStatus(0) into tPS
   stAssert "enPeerStatus(0) empty", the number of lines of the keys of tPS is 0
   put enHostStatus(0) into tHS
   stAssert "enHostStatus(0) empty", the number of lines of the keys of tHS is 0
   stAssert "enHostDestroy(0) is a no-op 0", enHostDestroy(0) is 0
   stAssert "enConnect on stale host is 0", enConnect(0, "127.0.0.1", 1, 1, 0) is 0
   stAssert "enFlush(0) errors", enFlush(0) < 0
   -- enBroadcast is the server-fanout primitive, so a stale host is the case
   -- that matters most: a broadcast that quietly "succeeded" against a
   -- destroyed host is a server believing it told every client something it
   -- never sent. It takes the same stale-handle path as enSend.
   stAssert "enBroadcast(0) errors", enBroadcast(0, 0, stTinyData(), 0) < 0
   stAssert "enBroadcastText(0) errors", enBroadcastText(0, 0, "x", 0) < 0

   stSection "tuning + abrupt teardown (isolated: nothing listens on 27099)"
   -- These four binds have no place in the graceful loopback below: a second
   -- live connection would race the server's event handlers (which assert on
   -- the FIRST connect's data payload), and an abrupt teardown would satisfy
   -- the "closing" phase early. So drive them on their own client host aimed
   -- at a port nothing listens on. enConnect is asynchronous - the handshake
   -- never has to complete for these to be exercised, because peer timeout,
   -- host bandwidth, disconnect-now, and reset are all LOCAL operations.
   put enHostCreateClient(2, 2, 0, 0) into tAbruptHost
   stAssert "abrupt-test client host created", tAbruptHost > 0
   put enConnect(tAbruptHost, "127.0.0.1", 27099, 2, 77) into tAbruptPeer
   stAssert "abrupt-test peer handle", tAbruptPeer > 0
   stAssert "enSetPeerTimeout returns 0", enSetPeerTimeout(tAbruptPeer, 32, 5000, 30000) is 0
   stAssert "enSetHostBandwidth returns 0", enSetHostBandwidth(tAbruptHost, 0, 0) is 0
   stAssert "enDisconnectNow returns 0", enDisconnectNow(tAbruptPeer, 9) is 0
   -- A second peer for the reset path: enResetPeer tears the connection down
   -- with no notification at all, so it needs its own victim.
   put enConnect(tAbruptHost, "127.0.0.1", 27099, 2, 78) into tResetPeer
   stAssert "reset-test peer handle", tResetPeer > 0
   stAssert "enResetPeer returns 0", enResetPeer(tResetPeer) is 0
   stAssert "abrupt-test host destroyed", enHostDestroy(tAbruptHost) is 0

   stSection "loopback: hosts + connect (async)"
   put enHostCreateServer("127.0.0.1", 27098, 8, 2, 0, 0) into sServer
   stAssert "server host created", sServer > 0
   put enHostCreateClient(1, 2, 0, 0) into sClient
   stAssert "client host created", sClient > 0
   put enConnect(sClient, "127.0.0.1", 27098, 2, 42) into sClientPeer
   stAssert "enConnect returns a peer handle", sClientPeer > 0
   stAssert "send on out-of-range channel is -3", enSend(sClientPeer, 5, stTinyData(), 0) is -3
   -- the budget: one byte over must refuse with -4, never truncate
   put stRepeatByte(65, 60001) into tBig
   stAssert "send over the budget is -4", enSend(sClientPeer, 0, tBig, 0) is -4

   put empty into sServerPeer
   put empty into sGotEcho
   put empty into sGotUnseq
   put empty into sGotBinary
   put empty into sSentBinary
   put empty into sSawServerDisc
   put "connecting" into sPhase
   put the milliseconds + 15000 into sDeadline
   stShow
   send "stPump" to me in 33 milliseconds
end stRun

-- One pump pass over BOTH hosts; reschedules itself until done/deadline.
-- (The selftest drives enPoll directly - the helpers stack is exercised by
-- the demo; here the binding itself is under test.)
command stPump
   local tEvents, tEvent, tPS
   if sPhase is "done" or sPhase is empty then
      exit stPump
   end if
   put enPoll(sServer) into tEvents
   repeat for each element tEvent in tEvents
      stHandleServer tEvent
   end repeat
   put enPoll(sClient) into tEvents
   repeat for each element tEvent in tEvents
      stHandleClient tEvent
   end repeat

   if sPhase is "connecting" then
      if sServerPeer is not empty and sGotEcho is empty then
         -- connected both ways; the message flow was kicked in the handlers
         put "messaging" into sPhase
      end if
   else if sPhase is "messaging" then
      if sGotEcho is "true" and sGotUnseq is "true" then
         stAssert "echo + broadcast both arrived", true
         -- peer status while connected
         put enPeerStatus(sClientPeer) into tPS
         stAssert "peer state is connected (5)", tPS["state"] is 5
         stAssert "peer status names the server port", tPS["address"] is "127.0.0.1:27098"
         -- the statistics half of the record: by echo time the client has
         -- sent at least the hello, so the counters must be populated. Exact
         -- values are timing-dependent (rtt starts at ENet's default until
         -- an ack updates it, loss on loopback is normally 0), so these pin
         -- presence and documented range, not a number a fast loopback
         -- would make flaky.
         stAssert "live peer rtt is a number >= 0", tPS["rtt"] >= 0
         stAssert "live peer packetLoss within 0..1", \
               tPS["packetLoss"] >= 0 and tPS["packetLoss"] <= 1
         stAssert "live peer counted its sends", \
               tPS["packetsSent"] > 0 and tPS["bytesSent"] > 0
         -- enHostStatus on a LIVE host (the stale-handle case is asserted
         -- above; this is the half that proves the record actually populates).
         put enHostStatus(sServer) into tHS
         stAssert "live enHostStatus counts the connected peer", tHS["peerCount"] is 1
         stAssert "live enHostStatus names the bound port", tHS["address"] is "127.0.0.1:27098"
         stAssert "tuning setters return 0", enSetPeerPingInterval(sClientPeer, 250) is 0
         -- binary with REAL embedded NUL/0x01 bytes, byte-exact both ways
         put textEncode("bin", "utf-8") & numToByte(0) & numToByte(1) \
               & textEncode("tail", "utf-8") into sSentBinary
         stAssert "enSend binary returns 0", enSend(sClientPeer, 1, sSentBinary, 0) is 0
         put "binary" into sPhase
      end if
   else if sPhase is "binary" then
      if sGotBinary is not empty then
         set the caseSensitive to true
         stAssert "binary arrived byte-for-byte (incl. NUL)", sGotBinary is sSentBinary
         stAssert "enDisconnect returns 0", enDisconnect(sClientPeer, 7) is 0
         put "closing" into sPhase
      end if
   else if sPhase is "closing" then
      if sSawServerDisc is "true" then
         stFinish
         exit stPump
      end if
   end if

   if the milliseconds > sDeadline then
      stAssert "async loopback finished before the deadline", false
      stNote "UDP to 127.0.0.1 may be blocked on this machine; see docs."
      stFinish
      exit stPump
   end if
   stShow
   send "stPump" to me in 33 milliseconds
end stPump

command stHandleServer pEvent
   local tR
   switch pEvent["name"]
      case "enetConnect"
         put pEvent["peer"] into sServerPeer
         stAssert "server enetConnect carries data 42", pEvent["data"] is 42
         stAssert "server enetConnect names an address", pEvent["address"] begins with "127.0.0.1:"
         break
      case "enetReceive"
         if pEvent["channel"] is 0 then
            -- the hello: echo it back reliably + a channel-1 broadcast
            stAssert "hello payload intact", textDecode(pEvent["payload"], "utf-8") is "hello enet"
            put enSendText(sServerPeer, 0, "echo!", 0) into tR
            stAssert "server echo send returns 0", tR is 0
            put enBroadcastText(sServer, 1, "fanout", 2) into tR
            stAssert "server broadcast returns 0", tR is 0
         else
            -- the binary phase payload arrives on channel 1
            put pEvent["payload"] into sGotBinary
         end if
         break
      case "enetDisconnect"
         put "true" into sSawServerDisc
         stAssert "server enetDisconnect carries data 7", pEvent["data"] is 7
         break
   end switch
end stHandleServer

command stHandleClient pEvent
   local tR
   switch pEvent["name"]
      case "enetConnect"
         stAssert "client enetConnect names the enConnect handle", pEvent["peer"] is sClientPeer
         put enSendText(sClientPeer, 0, "hello enet", 0) into tR
         stAssert "client hello send returns 0", tR is 0
         break
      case "enetReceive"
         if textDecode(pEvent["payload"], "utf-8") is "echo!" then
            put "true" into sGotEcho
            stAssert "echo on channel 0", pEvent["channel"] is 0
         else if textDecode(pEvent["payload"], "utf-8") is "fanout" then
            put "true" into sGotUnseq
            stAssert "broadcast on channel 1", pEvent["channel"] is 1
         end if
         break
   end switch
end stHandleClient

command stFinish
   local tPS, tHS
   stSection "retirement + teardown"
   put enPeerStatus(sClientPeer) into tPS
   stAssert "client peer retired after disconnect", the number of lines of the keys of tPS is 0
   -- the AFTER-disconnect half of the live enHostStatus pair: the host
   -- outlives its one peer, so the record must still populate and count zero
   -- (a host that still counted the departed peer would leak the slot).
   put enHostStatus(sServer) into tHS
   stAssert "live enHostStatus counts zero peers after disconnect", tHS["peerCount"] is 0
   stAssert "enHostDestroy(server) is 0", enHostDestroy(sServer) is 0
   stAssert "double destroy is a no-op 0", enHostDestroy(sServer) is 0
   stAssert "enHostDestroy(client) is 0", enHostDestroy(sClient) is 0
   stAssert "enDeinitialize returns 0", enDeinitialize() is 0
   stAssert "extra deinitialize is a no-op 0", enDeinitialize() is 0
   put empty into sServer
   put empty into sClient
   put "done" into sPhase
   stSection "summary"
   stNote "A green run proves the sync surface AND a live async loopback on"
   stNote "THIS machine. The two-machine LAN chat leg is the one thing it"
   stNote "cannot prove - that stays the enet-lan-chat / closing-pass run."
   stReportDone
end stFinish

command stCleanup
   put "done" into sPhase
   if sServer is not empty and sServer is not 0 then
      enHostDestroy sServer
   end if
   if sClient is not empty and sClient is not 0 then
      enHostDestroy sClient
   end if
   put empty into sServer
   put empty into sClient
   -- bare command form: OXT cannot compile a zero-argument name() statement;
   -- guarded so closing a stack whose extension is missing (the run already
   -- threw loudly at enInitialize) cannot throw a second time from closeStack
   try
      enDeinitialize
   catch tErr
      -- extension not installed; nothing to release
   end try
end stCleanup

-- ---- small helpers -----------------------------------------------------------
-- One byte of payload (enSend needs a Data; "x" as a literal would be text).
function stTinyData
   return textEncode("x", "utf-8")
end stTinyData

-- pCount copies of byte pCode, built without string-escape folklore.
function stRepeatByte pCode, pCount
   local tOne, tOut, tI
   put numToByte(pCode) into tOne
   put empty into tOut
   -- double up to size, then trim: O(log n) concatenations, not 60001
   put tOne into tOut
   repeat while the number of bytes in tOut < pCount
      put tOut & tOut into tOut
   end repeat
   return byte 1 to pCount of tOut
end stRepeatByte
