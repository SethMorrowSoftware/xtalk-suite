script "dataChannelSelfTest"

-- datachannel-selftest.livecodescript - a self-building RUNTIME harness that
-- drives the DataChannelXT public API end to end in OXT and reports PASS /
-- FAIL per handler. This is the OXT-pass companion to the C++ smoke test: the
-- smoke test proves the shim against libdatachannel in CI; this proves the
-- .lcb BINDING (the foreign-decl signatures, the record walkers, the buffer
-- round-trips) actually runs - the one layer CI cannot reach, since OXT has
-- no headless way to compile or run .lcb.
--
-- COVERAGE NOTE (honest): the harness now drives every public dc* handler
-- (31 of them), including the ones that used to appear only in the
-- stale-handle section - dcCreateChannelEx, dcSetBufferedLowThreshold,
-- dcLocalDescriptionType, dcChannelProtocol, dcSetLocalDescription - and it
-- pins the non-trickle signaling contract (a live local description carries
-- "a=candidate", and the offer/answer roles match the flow). What is recorded:
-- on 2026-08-08 the suite selftest (tests/suite-selftest.livecodescript at
-- the repository root) ran green on a real OXT engine with a live loopback
-- that negotiated, opened both ends, round-tripped a payload byte-for-byte,
-- refused 60001 bytes with -4, and tore down through dcCleanup; and on
-- 2026-08-10 THIS file's synchronous half ran green folded into that same
-- harness (23 checks, twice in one day), which calls every one of the 31
-- public handlers by name and pins the whole stale-handle surface as harmless
-- no-ops. So the binding, the transfer spine, and the synchronous contracts
-- are observed. Still verified statically: this file's own async loopback
-- (the fold excludes it; the suite core drives its own) - the LIVE halves of
-- dcSendText, dcBufferedAmount, dcGatheringState, dcSelectedCandidatePair,
-- the dcBufferedLow EVENT after a cap-sized send, and the a=candidate/role
-- pins are what running THIS file standalone would turn into a runtime
-- result.
--
-- HOW TO USE: open OXT, make a one-card stack, paste THIS into the STACK
-- script (Object > Stack Script), then close+reopen. It builds its own UI,
-- runs the synchronous checks, then a LIVE LOOPBACK (two in-process peers,
-- script-shuttled signaling, a real DTLS/SCTP association on this machine),
-- message round-trips, and teardown - and shows a green/red list. Needs the
-- installed org.openxtalk.library.datachannel extension.
--
-- WHAT IT CHECKS: every public handler returns a sane value; stale handles
-- are harmless; the loopback connects; text and binary messages round-trip
-- byte-for-byte; the drain's arrays carry the documented keys; close/free/
-- cleanup are idempotent. The async phase has a deadline - a machine that
-- blocks ALL UDP (even to itself) fails the loopback section with a note
-- rather than hanging.

constant kStTitle = "DataChannelXT - API Self-Test"
constant kStWidth = 660
constant kStHeight = 620

-- ---- state -------------------------------------------------------------------
local sPeerA, sPeerB    -- the loopback peers
local sChanA, sChanB    -- A's channel; B's (learned from dcChannelIncoming)
local sAOpen, sBOpen    -- "true" once each side's channel open arrived
local sGotText          -- the text B received
local sGotBytes         -- the binary payload A received back (a Data)
local sSentBytes        -- the binary payload B sent (kept for byte-exact compare)
local sGotBufferedLow   -- "true" once A's channel reported dcBufferedLow
local sBigLen           -- the cap-sized payload length for the buffered-low leg
local sDeadline         -- the async phase's drop-dead time (ms clock)
local sPhase            -- "", "opening", "messaging", "done"

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
   local tPair
   stResetCounters
   put empty into sPhase

   stSection "lifecycle & diagnostics"
   stAssert "dcInit returns 0", dcInit() is 0
   stAssert "dcInit idempotent", dcInit() is 0
   stAssert "dcLibraryVersion mentions libdatachannel", dcLibraryVersion() contains "libdatachannel"
   dcClearError
   stAssert "dcLastError empty after clear", dcLastError() is empty

   stSection "stale handles are harmless no-ops"
   stAssert "dcClosePeer(0) errors", dcClosePeer(0) < 0
   stAssert "dcPeerState(0) is -1", dcPeerState(0) is -1
   stAssert "dcGatheringState(0) is -1", dcGatheringState(0) is -1
   stAssert "dcLocalDescription(0) empty", dcLocalDescription(0) is empty
   -- an Array crosses from LCB; LiveCode Script has NO `{}` literal, and a
   -- bare `is empty` on an array is vacuously true (arrays stringify to
   -- empty) - so emptiness is asserted by counting keys of a LOCAL (a
   -- function result cannot be subscripted or keyed directly in LCS either)
   put dcSelectedCandidatePair(0) into tPair
   stAssert "dcSelectedCandidatePair(0) empty", the number of lines of the keys of tPair is 0
   stAssert "dcCreateChannel(0) is 0", dcCreateChannel(0, "x") is 0
   stAssert "dcSendText(0) errors", dcSendText(0, "x") < 0
   stAssert "dcChannelLabel(0) empty", dcChannelLabel(0) is empty
   stAssert "dcChannelStreamId(0) is -1", dcChannelStreamId(0) is -1
   stAssert "dcChannelIsOpen(0) is false", dcChannelIsOpen(0) is false
   stAssert "dcChannelPeer(0) is 0", dcChannelPeer(0) is 0
   stAssert "dcBufferedAmount(0) is -1", dcBufferedAmount(0) is -1
   stAssert "dcLocalDescriptionType(0) empty", dcLocalDescriptionType(0) is empty
   stAssert "dcChannelProtocol(0) empty", dcChannelProtocol(0) is empty
   stAssert "dcSetLocalDescription(0) errors", dcSetLocalDescription(0, "offer") < 0
   stAssert "dcSetBufferedLowThreshold(0) errors", dcSetBufferedLowThreshold(0, 4096) < 0
   stAssert "dcCreateChannelEx(0) is 0", \
         dcCreateChannelEx(0, "x", "proto", false, -1, -1, false, -1) is 0
   dcFreePeer(0)      -- must not crash
   dcFreeChannel(0)   -- must not crash
   stAssert "dcFreePeer/dcFreeChannel(0) survived", true
   stAssert "dcSendText(0) left a last-error", dcLastError() is not empty
   dcClearError

   stSection "loopback: create + negotiate (async)"
   put dcCreatePeer("") into sPeerA
   put dcCreatePeer("") into sPeerB
   stAssert "dcCreatePeer A > 0", sPeerA > 0
   stAssert "dcCreatePeer B > 0", sPeerB > 0
   stAssert "peers distinct", sPeerA is not sPeerB
   stAssert "new peer state is new/connecting", dcPeerState(sPeerA) >= 0
   put dcCreateChannel(sPeerA, "selftest") into sChanA
   stAssert "dcCreateChannel > 0", sChanA > 0
   stAssert "dcChannelPeer maps back", dcChannelPeer(sChanA) is sPeerA
   put empty into sChanB
   put empty into sAOpen
   put empty into sBOpen
   put empty into sGotText
   put empty into sGotBytes
   put empty into sSentBytes
   put empty into sGotBufferedLow
   put empty into sBigLen
   put "opening" into sPhase
   put the milliseconds + 20000 into sDeadline
   stShow
   send "stPump" to me in 33 milliseconds
end stRun

-- One poll pass of the async phase; reschedules itself until done/deadline.
command stPump
   local tEvents, tEvent, tDest, tPair, tExChan
   if sPhase is "done" or sPhase is empty then
      exit stPump
   end if
   put dcPoll() into tEvents
   repeat for each element tEvent in tEvents
      -- the in-script signaling shuttle (the whole point of the loopback)
      if tEvent["name"] is "dcLocalDescription" then
         put stOtherPeer(tEvent["peer"]) into tDest
         if tDest is not empty then
            dcSetRemoteDescription tDest, tEvent["sdp"], tEvent["sdpType"]
         end if
      else if tEvent["name"] is "dcLocalCandidate" then
         put stOtherPeer(tEvent["peer"]) into tDest
         if tDest is not empty then
            dcAddRemoteCandidate tDest, tEvent["candidate"], tEvent["mid"]
         end if
      else if tEvent["name"] is "dcChannelIncoming" then
         -- FIRST incoming only: the later dcCreateChannelEx check opens a
         -- second channel, whose incoming event must not retarget sChanB.
         if tEvent["peer"] is sPeerB and sChanB is empty then
            put tEvent["channel"] into sChanB
         end if
      else if tEvent["name"] is "dcChannelOpen" then
         if tEvent["channel"] is sChanA then
            put "true" into sAOpen
         else if sChanB is not empty and tEvent["channel"] is sChanB then
            put "true" into sBOpen
         end if
      else if tEvent["name"] is "dcMessage" then
         if tEvent["text"] is not empty then
            put tEvent["text"] into sGotText
         else
            put tEvent["payload"] into sGotBytes
         end if
      else if tEvent["name"] is "dcBufferedLow" then
         -- only A's channel is armed (threshold 4096, above); an event
         -- naming any other channel would be a contract violation, so the
         -- flag is set only for the armed one and the assertion below
         -- would time out loudly on a misdelivered event.
         if tEvent["channel"] is sChanA then
            put "true" into sGotBufferedLow
         end if
      end if
   end repeat

   if sPhase is "opening" then
      if sAOpen is "true" and sBOpen is "true" then
         stAssert "loopback connected + both channels open", true
         stAssert "incoming label is selftest", dcChannelLabel(sChanB) is "selftest"
         stAssert "peer A connected", dcPeerState(sPeerA) is 2
         stAssert "dcChannelIsOpen(A)", dcChannelIsOpen(sChanA) is true
         stAssert "stream id assigned", dcChannelStreamId(sChanA) >= 0
         stAssert "negotiated max message > 0", dcChannelMaxMessage(sChanA) > 0
         stAssert "buffered amount >= 0", dcBufferedAmount(sChanA) >= 0
         -- keyed access needs a local (LCS cannot subscript a function result)
         put dcSelectedCandidatePair(sPeerA) into tPair
         stAssert "selected pair has localCandidate", tPair["localCandidate"] is not empty
         -- The NON-TRICKLE signaling contract on live peers: once negotiated,
         -- each side's local description is a real SDP carrying its candidates,
         -- and the offer/answer roles are the ones the flow assigned (A made
         -- the channel, so A offered). This is the call the DHT-chat demo ships
         -- as one blob; the stale-handle half is asserted above.
         stAssert "local description is a real SDP", dcLocalDescription(sPeerA) contains "v=0"
         stAssert "local description carries candidates", \
               dcLocalDescription(sPeerA) contains "a=candidate"
         stAssert "peer A describes itself as the offer", dcLocalDescriptionType(sPeerA) is "offer"
         stAssert "peer B describes itself as the answer", dcLocalDescriptionType(sPeerB) is "answer"
         -- a channel created without a protocol reports none (the live half of
         -- the stale-handle assertion above)
         stAssert "dcChannelProtocol empty when unset", dcChannelProtocol(sChanA) is empty
         stAssert "dcSetBufferedLowThreshold on a live channel returns 0", \
               dcSetBufferedLowThreshold(sChanA, 4096) is 0
         stAssert "dcSendText returns 0", dcSendText(sChanA, "hello oxt") is 0
         put "messaging" into sPhase
      end if
   else if sPhase is "messaging" then
      -- a distinct phase per step, so a slow delivery cannot re-fire the send
      -- (and re-count the assertions) on every 33 ms pump pass
      if sGotText is not empty then
         stAssert "text arrived intact", sGotText is "hello oxt"
         -- REAL embedded NUL/0x01 bytes (LCS string literals have no escape
         -- syntax - a "\0" would be two ordinary characters), so this proves
         -- a Data crosses unmangled, not merely that ASCII survives
         put textEncode("binary", "UTF-8") & numToByte(0) & textEncode("byte", "UTF-8") \
               & numToByte(1) & textEncode("round-trip", "UTF-8") into sSentBytes
         stAssert "dcSendData returns 0", dcSendData(sChanB, sSentBytes) is 0
         put "binary-wait" into sPhase
      end if
   else if sPhase is "binary-wait" then
      if sGotBytes is not empty then
         -- byte-exact: `is` is case-insensitive by default, which would let
         -- 0x41 match 0x61 inside binary data
         set the caseSensitive to true
         stAssert "binary arrived byte-for-byte (incl. NUL)", sGotBytes is sSentBytes
         -- dcCreateChannelEx on a LIVE peer, last so its extra negotiation
         -- cannot disturb the checks above. The protocol is a property of the
         -- local object, set at creation, so it reads back without waiting for
         -- the far side to open the channel.
         put dcCreateChannelEx(sPeerA, "extra", "oxt-proto", true, 0, -1, false, -1) into tExChan
         stAssert "dcCreateChannelEx > 0", tExChan > 0
         stAssert "dcChannelProtocol round-trips", dcChannelProtocol(tExChan) is "oxt-proto"
         stAssert "dcChannelLabel round-trips", dcChannelLabel(tExChan) is "extra"
         dcFreeChannel tExChan
         -- the LIVE half of the gathering-state getter (the stale half is
         -- pinned at -1 above). The a=candidate assertion already proved
         -- candidates were gathered, and with no ICE servers configured
         -- gathering has nothing left to wait for, so by the time the
         -- binary round-trip has completed both peers must report
         -- kGatheringComplete (2).
         stAssert "gathering state is complete (2) on both peers", \
               dcGatheringState(sPeerA) is 2 and dcGatheringState(sPeerB) is 2
         -- the dcBufferedLow EVENT - the live half of the threshold setter
         -- asserted above. A's channel is armed at 4096, so one payload at
         -- the negotiated cap (60000 under the suite budget) must push the
         -- send buffer past the threshold, and the drain back under it
         -- fires the event. Waited on with the same deadline as the rest
         -- of the async phase, so a machine that never fires it fails
         -- loudly instead of hanging.
         put dcChannelMaxMessage(sChanA) into sBigLen
         put empty into sGotBytes
         stAssert "cap-sized send returns 0", \
               dcSendData(sChanA, stRepeatByte(66, sBigLen)) is 0
         put "bufferedlow-wait" into sPhase
      end if
   else if sPhase is "bufferedlow-wait" then
      if sGotBufferedLow is "true" and the number of bytes in sGotBytes is sBigLen then
         stAssert "dcBufferedLow fired once the cap-sized send drained", true
         stAssert "the cap-sized payload arrived whole", true
         stFinish
         exit stPump
      end if
   end if

   if the milliseconds > sDeadline then
      stAssert "async loopback finished before the deadline", false
      stNote "UDP to this machine's own address may be blocked; see docs."
      stFinish
      exit stPump
   end if
   stShow
   send "stPump" to me in 33 milliseconds
end stPump

function stOtherPeer pPeer
   if pPeer is sPeerA then
      return sPeerB
   else if pPeer is sPeerB then
      return sPeerA
   end if
   return empty
end stOtherPeer

command stFinish
   stSection "teardown"
   stAssert "dcCloseChannel returns 0", dcCloseChannel(sChanA) is 0
   dcFreeChannel(sChanA)
   dcFreeChannel(sChanA)   -- double free: no-op
   stAssert "double dcFreeChannel survived", true
   dcFreePeer(sPeerA)
   dcFreePeer(sPeerB)
   dcFreePeer(sPeerA)      -- double free: no-op
   stAssert "freed peer answers -1", dcPeerState(sPeerA) is -1
   stAssert "dcCleanup returns 0", dcCleanup() is 0
   stAssert "dcCleanup idempotent", dcCleanup() is 0
   put empty into sPeerA
   put empty into sPeerB
   put "done" into sPhase
   stSection "summary"
   stNote "A green run proves the stale-handle surface AND a live in-process"
   stNote "loopback (ICE/DTLS/SCTP) on THIS machine. Browser interop and the"
   stNote "two-machine DHT-signaled path stay the datachannel demos' runs."
   stReportDone
end stFinish

command stCleanup
   put "done" into sPhase
   if sPeerA is not empty and sPeerA is not 0 then
      dcFreePeer(sPeerA)
   end if
   if sPeerB is not empty and sPeerB is not 0 then
      dcFreePeer(sPeerB)
   end if
   put empty into sPeerA
   put empty into sPeerB
   -- BARE, not dcCleanup(). A zero-argument call in STATEMENT position parses
   -- as a command taking `()` as its argument, and `()` is not an expression,
   -- so it is a compile error. In EXPRESSION position (the two stAssert lines
   -- above) the parenthesised form is correct and required. Try-guarded the
   -- way enet's harness guards enDeinitialize: closing the stack with the
   -- extension absent must not throw a second error out of closeStack.
   local tCleanupErr
   try
      dcCleanup
   catch tCleanupErr
      -- extension not installed; nothing to release
   end try
end stCleanup

-- pCount copies of byte pCode (the cap-sized buffered-low payload). Built by
-- doubling - O(log n) concatenations, not 60000 - and with numToByte, since
-- string literals have no escape syntax.
function stRepeatByte pCode, pCount
   local tOut
   put numToByte(pCode) into tOut
   repeat while the number of bytes in tOut < pCount
      put tOut & tOut into tOut
   end repeat
   return byte 1 to pCount of tOut
end stRepeatByte
