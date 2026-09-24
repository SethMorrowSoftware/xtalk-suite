script "DcBrowserPeer"

-- datachannel-browser-peer.livecodescript - the OXT half of DataChannelXT's
-- browser-interop leg (suite runbook row 40). Its partner is the static page
-- tests/browser-peer.html; the procedure is docs/browser-interop.md.
--
-- WHY IT EXISTS: every engine record of this member is OXT talking to OXT
-- (the in-process loopbacks, the DHT chat). "Browser-interoperable" is the
-- claim this member's README leads with, and only a browser can say what a
-- dcSendText or a dcSendData actually BECOMES on the far side: a JavaScript
-- string for text (the SCTP "WebRTC String" PPID) and an ArrayBuffer for
-- binary. The page checks that side; this script checks the reverse (the
-- page's string arrives here as pEvent["text"], its ArrayBuffer as
-- pEvent["payload"], byte-exact).
--
-- SIGNALING IS COPY/PASTE, ONE BLOB EACH WAY (non-trickle, getting-started
-- section 3): wait for ICE gathering to complete, then ship the local
-- description, which by then CONTAINS every candidate, as
--     dcLocalDescriptionType(peer) & LF & dcLocalDescription(peer)
-- - datachannel-dht-chat's signaling body without its DHT-only nonce. The
-- clipboard carries it: this script writes the clipboard when its blob is
-- ready and reads the page's blob from it.
--
-- HOW TO USE (the paste-and-reopen ritual; never File > Open Stack on this
-- file, which builds nothing - suite engine note 5.5):
--   1. File > New Mainstack, Object > Stack Script, paste ALL of this file,
--      Apply, then close the stack and reopen it. The usage prints in the
--      message box. It builds no window: everything reports there.
--   2. Open tests/browser-peer.html in Chrome, Edge or Firefox.
--   3. In the message box: bpOffer. When it says the offer is on the
--      clipboard, paste it into the page's box 1 and press Apply; copy the
--      page's answer (box 2), then in the message box: bpAccept.
--   4. The channel opens; this script sends its text and its bytes at once,
--      and the page ticks its checks. Press the page's "Send test pair";
--      this script prints what arrived and how.
--   5. bpReport copies the record to the clipboard; bpStop tears down.
--   Other direction: the page's "make an offer here", copy it, bpAnswer,
--   paste the answer it copies back into the page and press Apply.
--
-- It polls dcPoll itself on its own timer (as the member harness does), so
-- it needs no helpers stack, and it must be the ONLY DataChannelXT stack open:
-- the event queue is process-wide and a second poller would steal events.
--
-- HONESTY (the suite convention): this script has never run on an engine -
-- verified statically; needs an OXT pass. Its partner page ran in headless
-- Chromium on 2026-09-24, against itself and against the committed
-- x86_64-linux library through the C ABI (docs/browser-interop.md says
-- exactly what that proves); every dc* handler it calls is engine-proven in
-- the member harness.

constant kBpText = "hello from OXT"
constant kBpPairText = "hello from the browser"
constant kBpLabel = "browser-interop"
constant kBpPollMs = 33
constant kBpGatherMs = 15000
constant kBpOpenMs = 30000

local sBpPeer          -- our peer handle, empty when idle
local sBpChan          -- our channel handle, empty until known
local sBpRole          -- "offerer" (bpOffer) or "answerer" (bpAnswer)
local sBpPhase         -- idle / gathering / waiting / connecting / open
local sBpDeadline      -- the milliseconds at which the current phase gives up
local sBpTicking       -- "true" while the poll timer chain is armed
local sBpLog           -- every line printed, for bpReport
local sBpSent          -- what dcSendText / dcSendData returned
local sBpGotText       -- PASS / FAIL line for the browser's string
local sBpGotBytes      -- PASS / FAIL line for the browser's ArrayBuffer
local sBpOpened        -- PASS line once the channel opened

on openStack
   local tVersion, tErr
   bpLog "DataChannelXT browser peer - the OXT half of runbook row 40"
   -- Probe once, guarded: a missing extension should say so here, not as an
   -- execution error on the first bp command.
   try
      put dcLibraryVersion() into tVersion
      bpLog "  loaded: " & tVersion
   catch tErr
      bpLog "  DataChannelXT is NOT loaded - install org.openxtalk.library.datachannel and reopen (" & tErr & ")"
   end try
   bpLog "  bpOffer   OXT offers; the offer lands on the clipboard"
   bpLog "  bpAccept  apply the page's answer from the clipboard"
   bpLog "  bpAnswer  the page offered: apply its offer, answer via the clipboard"
   bpLog "  bpSend    send the text and the bytes again"
   bpLog "  bpReport  print the record and copy it to the clipboard"
   bpLog "  bpStop    tear everything down (also runs on close)"
   pass openStack
end openStack

on closeStack
   bpStop
   pass closeStack
end closeStack

-- Print to the message box AND keep the line for bpReport.
command bpLog pLine
   put pLine & return after sBpLog
   put pLine & return after msg
end bpLog

-- The bytes this script sends: NUL and high-bit bytes both, so a text path
-- (which would stop at the NUL or mangle 0x80..0xFF) cannot pass for binary.
function bpBytes
   return numToByte(0) & numToByte(1) & numToByte(127) & numToByte(128) \
         & numToByte(254) & numToByte(255)
end bpBytes

-- The page's "Send test pair" bytes: the same six, reversed.
function bpPairBytes
   return numToByte(255) & numToByte(254) & numToByte(128) & numToByte(127) \
         & numToByte(1) & numToByte(0)
end bpPairBytes

function bpHex pData
   local tOut, tByte, tHex
   repeat for each byte tByte in pData
      put toLower(baseConvert(byteToNum(tByte), 10, 16)) into tHex
      if the number of chars of tHex < 2 then
         put "0" before tHex
      end if
      put tHex & " " after tOut
   end repeat
   return word 1 to -1 of tOut
end bpHex

-- Split "<type> LF <sdp>" off the clipboard. A blob that starts at "v=" (no
-- type line) takes pExpect. Returns the type, and the SDP in pSdp; empty type
-- means refused (the reason is already printed).
function bpReadBlob pExpect, @pSdp
   local tBlob, tType
   put the clipboardData["text"] into tBlob
   -- bare LFs from here on: libdatachannel reads an SDP line by line and
   -- trims each line's end, so it takes LF and CRLF alike
   replace numToChar(13) with empty in tBlob
   -- words break on spaces, tabs and returns, so this trims both ends and
   -- leaves every line inside intact
   put word 1 to -1 of tBlob into tBlob
   if tBlob is empty then
      bpLog "REFUSED: the clipboard is empty - copy the page's blob first"
      return empty
   end if
   put word 1 of line 1 of tBlob into tType
   if char 1 to 2 of tType is "v=" then
      put tBlob into pSdp
      return pExpect
   end if
   if tType is not "offer" and tType is not "answer" then
      bpLog "REFUSED: the clipboard's first line is not offer or answer: " & char 1 to 40 of line 1 of tBlob
      return empty
   end if
   put line 2 to -1 of tBlob into pSdp
   if char 1 to 2 of pSdp is not "v=" then
      bpLog "REFUSED: no SDP after the type line (expected v=0)"
      return empty
   end if
   return tType
end bpReadBlob

command bpOffer
   if sBpPeer is not empty then
      bpLog "a session is open - bpStop first"
      exit bpOffer
   end if
   bpReset
   put "offerer" into sBpRole
   put dcCreatePeer("") into sBpPeer
   if sBpPeer is not a number or sBpPeer <= 0 then
      bpLog "dcCreatePeer failed: " & dcLastError()
      put empty into sBpPeer
      exit bpOffer
   end if
   -- the first channel triggers the offer (auto-negotiation)
   put dcCreateChannel(sBpPeer, kBpLabel) into sBpChan
   if sBpChan is not a number or sBpChan <= 0 then
      bpLog "dcCreateChannel failed: " & dcLastError()
      put empty into sBpChan
      exit bpOffer
   end if
   bpLog "peer " & sBpPeer & ", channel " & sBpChan & " (" & kBpLabel & "): gathering candidates..."
   bpPhase "gathering", kBpGatherMs
end bpOffer

command bpAccept
   local tSdp, tType, tR
   if sBpRole is not "offerer" or sBpPhase is not "waiting" then
      bpLog "bpAccept completes an offer made by bpOffer once it is on the clipboard"
      exit bpAccept
   end if
   put bpReadBlob("answer", tSdp) into tType
   if tType is empty then
      exit bpAccept
   end if
   if tType is not "answer" then
      bpLog "REFUSED: the clipboard holds an " & tType & ", not the page's answer"
      exit bpAccept
   end if
   put dcSetRemoteDescription(sBpPeer, tSdp, "answer") into tR
   bpLog "dcSetRemoteDescription(answer) returned " & tR & bpErr(tR)
   if tR is 0 then
      bpPhase "connecting", kBpOpenMs
   end if
end bpAccept

command bpAnswer
   local tSdp, tType, tR
   if sBpPeer is not empty then
      bpLog "a session is open - bpStop first"
      exit bpAnswer
   end if
   put bpReadBlob("offer", tSdp) into tType
   if tType is empty then
      exit bpAnswer
   end if
   if tType is not "offer" then
      bpLog "REFUSED: the clipboard holds an " & tType & ", not the page's offer"
      exit bpAnswer
   end if
   bpReset
   put "answerer" into sBpRole
   put dcCreatePeer("") into sBpPeer
   if sBpPeer is not a number or sBpPeer <= 0 then
      bpLog "dcCreatePeer failed: " & dcLastError()
      put empty into sBpPeer
      exit bpAnswer
   end if
   -- auto-negotiation answers as soon as the offer is applied
   put dcSetRemoteDescription(sBpPeer, tSdp, "offer") into tR
   bpLog "dcSetRemoteDescription(offer) returned " & tR & bpErr(tR)
   if tR is 0 then
      bpLog "peer " & sBpPeer & ": gathering candidates for the answer..."
      bpPhase "gathering", kBpGatherMs
   end if
end bpAnswer

function bpErr pR
   if pR is 0 then
      return empty
   end if
   return " (" & dcLastError() & ")"
end bpErr

command bpReset
   put empty into sBpChan
   put empty into sBpRole
   put empty into sBpSent
   put empty into sBpGotText
   put empty into sBpGotBytes
   put empty into sBpOpened
   put "idle" into sBpPhase
end bpReset

command bpPhase pPhase, pMs
   put pPhase into sBpPhase
   put the milliseconds + pMs into sBpDeadline
   if sBpTicking is not "true" then
      put "true" into sBpTicking
      send "bpTick" to me in kBpPollMs milliseconds
   end if
end bpPhase

-- One pass of the timer chain: drain, then advance the phase. Guarded, so a
-- bad event names itself instead of silently ending the chain (engine note 6.6).
command bpTick
   local tEvents, tEvent, tErr
   if sBpPeer is empty then
      put empty into sBpTicking
      exit bpTick
   end if
   try
      put dcPoll() into tEvents
      repeat for each element tEvent in tEvents
         bpOnEvent tEvent
      end repeat
      bpAdvance
   catch tErr
      bpLog "POLL FAILED: " & tErr
   end try
   send "bpTick" to me in kBpPollMs milliseconds
end bpTick

command bpAdvance
   local tBlob
   if sBpPhase is "gathering" then
      -- 2 is kGatheringComplete: the description now carries the candidates
      if dcGatheringState(sBpPeer) is 2 or the milliseconds > sBpDeadline then
         if dcGatheringState(sBpPeer) is not 2 then
            bpLog "WARNING: gathering did not complete; shipping what exists"
         end if
         put dcLocalDescriptionType(sBpPeer) & LF & dcLocalDescription(sBpPeer) into tBlob
         set the clipboardData["text"] to tBlob
         bpLog "the " & dcLocalDescriptionType(sBpPeer) & " is on the clipboard (" \
               & bpCount("a=candidate", tBlob) & " candidates, " & the number of chars of tBlob & " chars)"
         if sBpRole is "offerer" then
            bpLog "  paste it into the page's box 1, press Apply, copy the page's answer, then: bpAccept"
            bpPhase "waiting", kBpOpenMs * 20
         else
            bpLog "  paste it into the page's box 1 and press Apply; the channel opens here"
            bpPhase "connecting", kBpOpenMs
         end if
      end if
   else if sBpPhase is "connecting" then
      if the milliseconds > sBpDeadline then
         bpLog "NOT OPEN after " & kBpOpenMs & " ms: peer state " & dcPeerState(sBpPeer) \
               & ", last error: " & dcLastError()
         put "stalled" into sBpPhase
      end if
   end if
end bpAdvance

function bpCount pNeedle, pText
   local tN, tOffset
   put 0 into tN
   put offset(pNeedle, pText) into tOffset
   repeat while tOffset > 0
      add 1 to tN
      delete char 1 to tOffset of pText
      put offset(pNeedle, pText) into tOffset
   end repeat
   return tN
end bpCount

command bpOnEvent pEvent
   if pEvent["name"] is "dcStateChange" then
      bpLog "peer state " & pEvent["state"]
   else if pEvent["name"] is "dcChannelIncoming" then
      if sBpChan is empty and pEvent["peer"] is sBpPeer then
         put pEvent["channel"] into sBpChan
      end if
      bpLog "incoming channel " & pEvent["channel"] & " label " & pEvent["label"]
   else if pEvent["name"] is "dcChannelOpen" then
      if sBpChan is not empty and pEvent["channel"] is sBpChan then
         put "open" into sBpPhase
         put "PASS  the channel opened (" & dcChannelLabel(sBpChan) & ")" into sBpOpened
         bpLog "CHANNEL OPEN - sending the text and the bytes"
         bpSend
         bpLog "selected pair: " & bpPair()
      end if
   else if pEvent["name"] is "dcChannelClosed" then
      bpLog "channel " & pEvent["channel"] & " closed"
   else if pEvent["name"] is "dcChannelError" then
      bpLog "channel error: " & pEvent["error"]
   else if pEvent["name"] is "dcMessage" then
      bpOnMessage pEvent
   end if
end bpOnEvent

-- The reverse direction: the page's string must arrive as TEXT and its
-- ArrayBuffer as a PAYLOAD, byte-exact. The wrong key for either is a FAIL.
command bpOnMessage pEvent
   set the caseSensitive to true
   if pEvent["text"] is not empty then
      bpLog "RECV text (" & the number of chars of pEvent["text"] & " chars): " & pEvent["text"]
      if pEvent["text"] is kBpPairText then
         put "PASS  the browser's string arrived as text" into sBpGotText
      else if pEvent["text"] is bpPairBytes() then
         put "FAIL  the browser's ArrayBuffer arrived as text" into sBpGotBytes
      end if
   else
      bpLog "RECV payload (" & the number of bytes of pEvent["payload"] & " bytes): " \
            & bpHex(pEvent["payload"])
      if pEvent["payload"] is bpPairBytes() then
         put "PASS  the browser's ArrayBuffer arrived as a payload, byte-exact" into sBpGotBytes
      else if pEvent["payload"] is textEncode(kBpPairText, "UTF-8") then
         put "FAIL  the browser's string arrived as a payload" into sBpGotText
      end if
   end if
end bpOnMessage

command bpSend
   local tR
   if sBpChan is empty or sBpPhase is not "open" then
      bpLog "no open channel"
      exit bpSend
   end if
   put dcSendText(sBpChan, kBpText) into tR
   bpLog "dcSendText " & quote & kBpText & quote & " returned " & tR & bpErr(tR)
   put "dcSendText " & tR & return after sBpSent
   put dcSendData(sBpChan, bpBytes()) into tR
   bpLog "dcSendData " & bpHex(bpBytes()) & " returned " & tR & bpErr(tR)
   put "dcSendData " & tR & return after sBpSent
end bpSend

function bpPair
   local tPair
   put dcSelectedCandidatePair(sBpPeer) into tPair
   if tPair["localCandidate"] is empty then
      return "not selected yet"
   end if
   return "local " & tPair["localCandidate"] & " / remote " & tPair["remoteCandidate"]
end bpPair

command bpReport
   local tOut
   put "DataChannelXT browser peer (OXT side) - " & the long date && the long time & return into tOut
   put "engine: " & the version & ", " & the platform & ", " & dcLibraryVersion() & return after tOut
   put "role: " & sBpRole & "; phase: " & sBpPhase & return after tOut
   if sBpPeer is not empty then
      put "selected pair: " & bpPair() & return after tOut
   end if
   put bpOr(sBpOpened, "PENDING  the channel opened") & return after tOut
   put sBpSent after tOut
   put bpOr(sBpGotText, "PENDING  the browser's string arrived as text") & return after tOut
   put bpOr(sBpGotBytes, "PENDING  the browser's ArrayBuffer arrived as a payload") & return after tOut
   -- The suite harness convention: an unfinished report says so.
   if word 1 of sBpOpened is not "PASS" or word 1 of sBpGotText is not "PASS" \
         or word 1 of sBpGotBytes is not "PASS" then
      put "RUN NOT FINISHED" & return after tOut
   end if
   bpLog tOut
   set the clipboardData["text"] to tOut & return & "-- log --" & return & sBpLog
   bpLog "(the record and the log are on the clipboard)"
end bpReport

function bpOr pValue, pElse
   if pValue is empty then
      return pElse
   end if
   return pValue
end bpOr

-- The timer chain is left to end itself: its next tick finds no peer and
-- clears sBpTicking. Clearing the flag HERE would let a bpOffer typed before
-- that tick arm a second chain beside the pending one.
command bpStop
   if sBpPeer is not empty then
      put empty into sBpPeer
      put empty into sBpChan
      put "idle" into sBpPhase
      -- frees every peer and channel and joins libdatachannel's threads;
      -- written BARE (a zero-argument call in statement position, engine
      -- note 3.3)
      dcCleanup
      bpLog "stopped: dcCleanup done"
   end if
end bpStop
