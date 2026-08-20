-- preflight.livecodescript - the xTalk suite's ONE-PASTE ENGINE PREFLIGHT.
--
-- GENERATED - do not edit by hand. Regenerate with tools/build-preflight.py
-- (its --check runs in the gate set), and edit the generator, never this file:
-- the six expected-ABI numbers below are READ from the C shims, so a hand edit
-- here is a number that no longer traces to anything.
--
-- WHY THIS FILE EXISTS. Engine access is sparse (docs/OXT-PASS-RUNBOOK.md's
-- sparse-access plan budgets a whole session at sixty minutes), and the
-- expensive way to lose one is not a red check - it is discovering at minute
-- fifteen that the INSTALL cannot run the thing you sat down to run. The
-- wrong-ABI hazard is live and recorded: a member's binding compares the native
-- library's ABI against its own with STRICT EQUALITY and throws on any skew, so
-- one stale library blocks that whole member and everything built on it. This
-- paste answers "can this machine run the pass at all?" in the first minute, as
-- ONE table you can screenshot into the record.
--
-- TO RUN: new mainstack -> Object menu -> Stack Script -> paste this whole file
-- -> Apply -> close and reopen the stack (openStack builds the window and
-- runs). No daemon, no second machine, no `start using` step, nothing to
-- install first - the point is to run BEFORE all of that is known to work.
--
-- WHAT A GREEN RUN PROVES, EXACTLY. That each listed extension LOADS in this
-- engine and that its own ABI guard accepted the library shipped inside it. For
-- five of the six that is an INFERENCE and this file says so in the table: the
-- guards are PRIVATE handlers that compare native-against-binding and throw,
-- so a call that returned proves equality without ever exposing the number.
-- Box2Dxt is the exception - b2Version() hands the native ABI back to script -
-- so its row is the one real found-vs-expected comparison here.
--
-- WHAT IT DOES NOT DO. It runs no member's test surface (that is the suite
-- paste, tests/suite-selftest.livecodescript, and this is not a substitute for
-- it); it does not probe the tor daemon (a control-port dial is asynchronous,
-- needs the onionxt script layer in the message path, and has side effects -
-- runbook 2.3's torrc and its "Opening Control listener" log line stay that
-- test); and it cannot see this repository, only what is installed in the
-- engine it is running in. A SKIP here means "not installed on THIS machine",
-- never "missing from the suite".
--
-- Honesty label: verified statically; needs an OXT pass. Not one line of this
-- file has run on an engine.

-- ---- expected ABI, read from the C shims -------------------------------------
-- GENERATED. Each number is the macro named beside it, and tools/build-preflight.py
-- proves it equals the literal that member's own .lcb binding compares against
-- before it writes this file - so these six lines and the twelve places they
-- come from cannot disagree without failing the suite build.
-- sodiumxt/src/sodium_shim.h (SXT_ABI_VERSION), cross-checked against sodiumxt/src/sodium.lcb
constant kAbiSodium = 9
-- torrentxt/src/btx_abi.h (BTX_ABI_VERSION), cross-checked against torrentxt/src/torrent.lcb
constant kAbiTorrent = 11
-- enetxt/src/enx_abi.h (ENX_ABI_VERSION), cross-checked against enetxt/src/enet.lcb
constant kAbiEnet = 2
-- datachannelxt/src/dcx_abi.h (DCX_ABI_VERSION), cross-checked against datachannelxt/src/datachannel.lcb
constant kAbiDc = 1
-- coinxt/native/coinxt.c (CNX_ABI_VERSION), cross-checked against coinxt/src/coinxt.lcb
constant kAbiCoin = 6
-- box2dxt/src/box2d_lc.c (LC_ABI_VERSION), cross-checked against box2dxt/src/box2dxt.lcb
constant kAbiBox2d = 4

constant kStTitle = "xTalk Suite - engine preflight"
constant kStWidth = 720
constant kStHeight = 560

-- ---- state -------------------------------------------------------------------
-- The table is built up as the probes run and printed ONCE, because a table
-- split across six places in a log is not a table and does not screenshot.
local sRows                -- one preformatted row per member
local sDetails             -- version strings, and the raw text of anything thrown
local sSeen                -- the member names already in sRows (one row each)
local sSession             -- the torrent session this run took (0 = none held)
local sEnetUp              -- "true" while an enInitialize is unbalanced
local sDcUp                -- "true" while a dcInit is unbalanced

-- ---- the scaffolding (carried) -----------------------------------------------
-- Carried verbatim from tools/harness-scaffold.livecodescript by the generator,
-- which is why this file is not registered in tools/check-harness-scaffold-drift.py:
-- generated carriers are pinned to the master by their own freshness gate
-- (--check), exactly as the onionxt standalones are. It also carries the Copy
-- results button, which is how this run reaches the OXT-pass record without
-- anybody retyping a table.
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

-- THE REPORT IS A LIVE SURFACE, so its text is ambiguous by construction:
-- sResultText grows as the run goes, the async harnesses re-render it every
-- tick, and an unfinished report simply STOPS - with no marker, at whatever
-- section the pump had reached. That reads exactly like a hang. It cost a
-- round trip on the 2026-08-19 suite pass: a fully green run came back ending
-- mid-CROSS-section, and nothing in the pasted text could tell an early Copy
-- from a stalled pump. The async deadline is FORTY SECONDS (kStDeadlineMs in
-- the suite core), and the list stops visibly growing long before it expires,
-- so "it looks finished" is the normal state of a run that is not. Every
-- render of the report goes through here, so that state can never be silent
-- again - on screen or on the clipboard.
function stReportText
   if sStRunDone is "true" then
      return sResultText
   end if
   return sResultText \
         & "      ----------------------------------------------------" & return \
         & "      RUN NOT FINISHED - this is NOT the end of the report." & return \
         & "      An async section is still running. Wait for the SUMMARY" & return \
         & "      section at the bottom, then Copy." & return
end stReportText

command stShow
   put stReportText() into field "stResults"
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
   -- It copies stReportText(), not sResultText, so an early copy carries its
   -- own "not finished" trailer into the record - and says so here too,
   -- because the one moment a maintainer is looking at this window is the
   -- moment the dialog appears.
   --
   -- The COUNTS ride along, ahead of the lines. They live in their own field
   -- (stSummary) and used to be left behind, so the runbook taught a message
   -- box incantation to fetch them by hand - one more step between a finished
   -- run and a recorded one, at the exact moment the operator is done. A
   -- report with no totals cannot be checked against the next run's.
   local tError
   try
      set the clipboardData["text"] to sPassed & " passed, " & sFailed \
            & " failed, " & sSkipped & " skipped, " & sTotal & " total" \
            & return & return & stReportText()
      if sStRunDone is "true" then
         answer "Results copied to the clipboard."
      else
         answer "Copied - but the run has NOT finished. An async section is" \
               && "still going; wait for the SUMMARY section, then copy again."
      end if
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

-- ---- the run -----------------------------------------------------------------

on openStack
   stBuild
   stRun
end openStack

-- Release anything a probe took. Every probe already balances itself inline, so
-- this is the belt-and-braces path the scaffold's Re-run button and closeStack
-- go through - and it matters more here than in a member harness: a preflight
-- that leaked the single libtorrent session would break the very run it exists
-- to de-risk (runbook 5.1.1), and these flags are the only record of what this
-- stack took.
command stCleanup
   local tError, tRc

   try
      if sSession is not empty and sSession > 0 then
         btStopSession sSession
      end if
   catch tError
      -- TorrentXT absent, or the session was already released: nothing to free.
   end try
   put 0 into sSession

   try
      if sEnetUp is "true" then
         put enDeinitialize() into tRc
      end if
   catch tError
      -- enetxt absent, or already deinitialized.
   end try
   put "false" into sEnetUp

   try
      if sDcUp is "true" then
         -- EXPRESSION position, so the parentheses are REQUIRED. The STATEMENT
         -- spelling of a zero-argument call must be BARE (`dcCleanup`): the
         -- parenthesised statement hands the parser `()`, which is not an
         -- expression, and one such line took a whole 4400-line paste with it
         -- on 2026-08-09. Same characters, opposite verdict.
         put dcCleanup() into tRc
      end if
   catch tError
      -- DataChannelXT absent, or already cleaned up.
   end try
   put "false" into sDcUp
end stCleanup

command stRun
   local tError

   stResetCounters
   put empty into sRows
   put empty into sSeen
   put empty into sDetails
   put 0 into sSession
   put "false" into sEnetUp
   put "false" into sDcUp

   put "xTalk Suite - engine preflight" & return into sResultText
   put "Can this machine run the pass at all? One paste, no setup, no daemon." & return after sResultText
   put "An absent member SKIPS. A member whose ABI does not match FAILS - that" & return after sResultText
   put "member, and everything downstream of it, cannot be tested here today." & return after sResultText

   -- Every section is CONTAINED, for the reason the suite harness records: a
   -- throw must cost EXACTLY ITSELF. A preflight that died on its second member
   -- would be read as a verdict about the machine when it is a defect in here.
   try
      pfEngineSection
   catch tError
      stSectionFailed "engine facts", tError
   end try

   stSection "extensions (guarded: absent SKIPS, wrong ABI FAILS)"
   try
      pfProbeSodium
   catch tError
      stSectionFailed "SodiumXT probe", tError
      pfRecord "SodiumXT", kAbiSodium, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeTorrent
   catch tError
      stSectionFailed "TorrentXT probe", tError
      pfRecord "TorrentXT", kAbiTorrent, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeEnet
   catch tError
      stSectionFailed "enetxt probe", tError
      pfRecord "enetxt", kAbiEnet, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeDc
   catch tError
      stSectionFailed "DataChannelXT probe", tError
      pfRecord "DataChannelXT", kAbiDc, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeCoin
   catch tError
      stSectionFailed "CoinXT probe", tError
      pfRecord "CoinXT", kAbiCoin, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeBox2d
   catch tError
      stSectionFailed "Box2Dxt probe", tError
      pfRecord "Box2Dxt", kAbiBox2d, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeScriptLayers
   catch tError
      stSectionFailed "script layers", tError
   end try

   pfTableSection
   pfDetailSection
   pfNextSection
   stReportDone
end stRun

-- ---- what engine is this? ----------------------------------------------------
-- The runbook carries a recorded green run whose platform was never captured,
-- and a result you cannot attribute to a machine is a result you cannot re-use.
-- Each fact sits in its OWN try and each is spelled out rather than looked up
-- through a variable: a computed property name (`the (tName) of ...`) is
-- engine-shaky on OXT and refused by the static gate, and losing the whole
-- header because one engine build lacks one property would be the wrong trade.
command pfEngineSection
   local tError, tValue

   stSection "engine"

   put "(unavailable)" into tValue
   try
      put the platform into tValue
   catch tError
      put "(unavailable: " & tError & ")" into tValue
   end try
   stNote "platform:       " & tValue

   put "(unavailable)" into tValue
   try
      put the processor into tValue
   catch tError
      put "(unavailable: " & tError & ")" into tValue
   end try
   stNote "processor:      " & tValue

   put "(unavailable)" into tValue
   try
      put the systemVersion into tValue
   catch tError
      put "(unavailable: " & tError & ")" into tValue
   end try
   stNote "systemVersion:  " & tValue

   put "(unavailable)" into tValue
   try
      put the version into tValue
   catch tError
      put "(unavailable: " & tError & ")" into tValue
   end try
   stNote "engine version: " & tValue
end pfEngineSection

-- ---- the probes --------------------------------------------------------------
-- ORDER OF OPERATIONS INSIDE EACH PROBE IS THE POINT, and it is not tidiness.
-- Each one calls a handler that runs its member's ABI GUARD FIRST, and never one
-- that skips it. enLibraryVersion, dcLibraryVersion and btLastError all reach
-- into the native library with NO guard in front of them - which is precisely
-- what you must not do to a possibly-mismatched binary, since refusing before
-- any call that could corrupt memory is the whole reason those guards exist. So
-- the guarded call goes first, and a version string is read only afterwards,
-- once the library has been established to be the right one.

command pfProbeSodium
   local tError, tOk, tVersion

   put "false" into tOk
   put empty into tVersion
   try
      -- sxVersion() runs sPrepare() - the ABI guard plus libsodium's init -
      -- before it reads anything, so a returned string is proof of both.
      put sxVersion() into tVersion
      put "true" into tOk
   catch tError
      put "false" into tOk
   end try
   pfReport "SodiumXT", kAbiSodium, tOk, tError, tVersion
end pfProbeSodium

command pfProbeTorrent
   local tError, tOk, tDetail

   put "false" into tOk
   put empty into tDetail
   try
      -- btStartSession() runs _checkABI() BEFORE it creates anything, so even
      -- the 0 return below is proof the ABI matched - the guard threw or it did
      -- not. Taking the session is the only guarded torrent entry point there
      -- is, so this takes it and gives it straight back: there is exactly one
      -- per process and the pass itself needs it.
      put btStartSession() into sSession
      put "true" into tOk
      if sSession > 0 then
         btStopSession sSession
         put 0 into sSession
      else
         put "loaded and the ABI guard passed, but a session was already live in this process - quit and relaunch OXT before any torrent-bearing paste (runbook 5.1.1)" into tDetail
      end if
   catch tError
      put "false" into tOk
      put 0 into sSession
   end try
   pfReport "TorrentXT", kAbiTorrent, tOk, tError, tDetail
end pfProbeTorrent

command pfProbeEnet
   local tError, tOk, tDetail, tRc

   put "false" into tOk
   put empty into tDetail
   try
      -- enInitialize() is the cheapest GUARDED entry point (it is refcounted,
      -- and enLibraryVersion() carries no guard at all), so it goes first and
      -- is balanced immediately afterwards.
      put enInitialize() into tRc
      put "true" into tOk
      put "true" into sEnetUp
      if tRc is not 0 then
         put "enInitialize returned " & tRc & " - the ABI guard still passed" into tDetail
      else
         put enLibraryVersion() into tDetail
      end if
      put enDeinitialize() into tRc
      put "false" into sEnetUp
   catch tError
      put "false" into tOk
   end try
   pfReport "enetxt", kAbiEnet, tOk, tError, tDetail
end pfProbeEnet

command pfProbeDc
   local tError, tOk, tDetail, tRc

   put "false" into tOk
   put empty into tDetail
   try
      -- dcInit() is the guarded one; dcLibraryVersion() is not. dcInit also
      -- warms the DTLS certificate, so this is the same call a real app makes
      -- at startup.
      put dcInit() into tRc
      put "true" into tOk
      put "true" into sDcUp
      if tRc is not 0 then
         put "dcInit returned " & tRc & " - the ABI guard still passed" into tDetail
      else
         put dcLibraryVersion() into tDetail
      end if
      -- EXPRESSION position: the parentheses are REQUIRED here and forbidden in
      -- the statement spelling. See the note in stCleanup.
      put dcCleanup() into tRc
      put "false" into sDcUp
   catch tError
      put "false" into tOk
   end try
   pfReport "DataChannelXT", kAbiDc, tOk, tError, tDetail
end pfProbeDc

command pfProbeCoin
   local tError, tOk

   put "false" into tOk
   try
      -- cxCheckABI is `returns nothing` and throws on skew, so silence is the
      -- pass and there is no value to inspect. BARE, because a zero-argument
      -- call in STATEMENT position must not carry parentheses.
      cxCheckABI
      put "true" into tOk
   catch tError
      put "false" into tOk
   end try
   pfReport "CoinXT", kAbiCoin, tOk, tError, "the extension half; CoinXT's script layer has its own row below"
end pfProbeCoin

command pfProbeBox2d
   local tError, tOk, tFound

   put "false" into tOk
   put empty into tFound

   -- The Kit's loader assist, in its OWN try and deliberately ignored. It seeds
   -- revLibraryMapping from the folder beside this stack, which is what lets a
   -- Linux box load box2dxt.so with no sudo and no LD_LIBRARY_PATH - but it
   -- lives in the b2k Kit script, which this paste does not carry. Its absence
   -- is not a verdict about box2dxt, so it must not be able to make one: the
   -- suite harness can afford one try around both because it embeds the Kit.
   try
      b2kEnsureNativeLib
   catch tError
      put empty into tError
   end try

   try
      -- THE ONE MEMBER THAT HANDS THE NUMBER BACK. b2Version() returns the
      -- native b2lc_abi_version() with no guard in front of it, so this row is
      -- a real reading rather than the inference the other five rows make - and
      -- a skew shows up here as a NUMBER instead of a thrown message.
      put b2Version() into tFound
      put "true" into tOk
   catch tError
      put "false" into tOk
   end try

   if tOk is not "true" then
      pfReport "Box2Dxt", kAbiBox2d, "false", tError, empty
      exit pfProbeBox2d
   end if
   if tFound is kAbiBox2d then
      stAssert "Box2Dxt native ABI is " & kAbiBox2d & " (read, not inferred)", true
      pfRecord "Box2Dxt", kAbiBox2d, tFound, "LOADED", "b2Version() read the native ABI directly"
   else
      stAssert "Box2Dxt native ABI is " & kAbiBox2d & " (b2Version reported " & tFound & ")", false
      pfRecord "Box2Dxt", kAbiBox2d, tFound, "ABI SKEW", \
            "b2Version() returned " & tFound & "; the binding refuses anything but " & kAbiBox2d & " at world creation"
   end if
end pfProbeBox2d

-- The two members that ship a SECOND, pure-script half. Neither is needed for
-- the suite paste - which embeds both - so an absent one is a SKIP with the one
-- line that makes it run, not a defect.
command pfProbeScriptLayers
   local tError, tVersion, tHex

   stSection "pure-script layers (only their own demos need these loaded)"

   put empty into tVersion
   try
      put oxVersion() into tVersion
   catch tError
      put empty into tVersion
   end try
   if tVersion is not empty then
      stAssert "OnionXT script layer is in the message path", true
      pfNote "OnionXT: " & tVersion
   else
      stSkip "OnionXT script layer", "open onionxt/src/onionxt.livecodescript and start using it - the suite paste embeds it, so this is not needed for that run"
   end if

   put empty into tHex
   try
      -- A real vector rather than a version sniff: cxHexEncode of the two bytes
      -- 222,173 is "dead", so a present script layer is a WORKING one.
      put cxHexEncode(numToByte(222) & numToByte(173)) into tHex
   catch tError
      put empty into tHex
   end try
   if tHex is "dead" then
      stAssert "CoinXT script layer answers a known vector", true
   else if tHex is empty then
      stSkip "CoinXT script layer", "start using stack " & quote & "coinxt" & quote & " - the suite paste embeds it, so this is not needed for that run"
   else
      stAssert "CoinXT script layer answers a known vector", false
      pfNote "CoinXT script layer: cxHexEncode returned " & tHex & " where " & quote & "dead" & quote & " was expected"
   end if
end pfProbeScriptLayers

-- ---- the table ---------------------------------------------------------------

command pfTableSection
   local tI, tCount

   stSection "THE TABLE - found vs expected (screenshot this)"
   stNote pfRow("member", "expected", "found", "verdict")
   stNote pfRow("------", "--------", "-----", "-------")
   put the number of lines of sRows into tCount
   repeat with tI = 1 to tCount
      stNote line tI of sRows
   end repeat
   stNote ""
   stNote "'= expected' is an INFERENCE, and an honest one: that member's ABI"
   stNote "guard is private, compares with strict equality, and did not throw."
   stNote "Box2Dxt's found column is a READING - b2Version() returns the number."
end pfTableSection

command pfDetailSection
   local tI, tCount

   stSection "details (version strings, and the exact text of anything thrown)"
   put the number of lines of sDetails into tCount
   if tCount is 0 then
      stNote "nothing to add: no probe threw, and no member reported a version."
      exit pfDetailSection
   end if
   repeat with tI = 1 to tCount
      stNote line tI of sDetails
   end repeat
end pfDetailSection

command pfNextSection
   local tError, tPlatform

   stSection "what to do with this"
   stNote "If the summary above says 0 failed, this install can run the pass:"
   stNote "go to the suite paste, tests/suite-selftest.livecodescript (S1 item 1)."
   stNote "A SKIP is not a defect - that member is not installed HERE."
   stNote "An ABI SKEW row is a BLOCKED member: it, and everything downstream"
   stNote "of it, cannot be tested on this machine until that library is"
   stNote "rebuilt and repackaged. Record the block and run what still runs."

   put empty into tPlatform
   try
      put the platform into tPlatform
   catch tError
      put empty into tPlatform
   end try
   if tPlatform is "MacOS" then
      -- Quoted from sodiumxt/CLAUDE.md's platform table by the generator, so
      -- these two numbers cannot drift from the member's own record of them.
      stNote ""
      stNote "MACOS: a SodiumXT ABI SKEW above is the KNOWN RECORDED STATE here,"
      stNote "not a new defect - the committed universal-mac dylib is at ABI 6"
      stNote "against this binding's 9 (sodiumxt/CLAUDE.md's platform table;"
      stNote "runbook section 2.1's warning). Record it once and move to what a"
      stNote "Mac CAN run today (runbook S5); it needs the manual lipo build."
   end if

   stNote ""
   stNote "The tor daemon is NOT probed here: runbook 2.3's torrc and its"
   stNote quote & "Opening Control listener" & quote & " log line stay the S2/S4 prerequisite."
   stNote "This whole file is unexecuted until you run it: verified statically;"
   stNote "needs an OXT pass. Report anything it gets wrong as a defect in it."
end pfNextSection

-- ---- reporting plumbing ------------------------------------------------------

-- ONE place decides PASS / SKIP / FAIL, because the three are not
-- interchangeable and confusing them is exactly how a preflight lies. ABSENT is
-- a SKIP: the machine legitimately does not have that member, and that must
-- never read as a defect. SKEW is a FAIL: the member is installed and unusable,
-- which is the whole reason this file exists. Anything unclassified is ALSO a
-- FAIL, printed raw - an error we cannot name is a result to report, not one to
-- round down to a skip.
command pfReport pName, pExpected, pOk, pError, pDetail
   local tKind

   if pOk is "true" then
      stAssert pName && "loads; its ABI guard accepted the installed library (expects ABI " & pExpected & ")", true
      pfRecord pName, pExpected, "= expected", "LOADED", pDetail
      exit pfReport
   end if

   put pfClassify(pError) into tKind
   if tKind is "absent" then
      stSkip pName && "(expects ABI " & pExpected & ")", "not installed in this engine"
      pfRecord pName, pExpected, "-", "NOT INSTALLED", pError
   else if tKind is "skew" then
      stAssert pName && "ABI matches the installed native library", false
      pfRecord pName, pExpected, "MISMATCH", "ABI SKEW", pError
   else
      stAssert pName && "probe ran without an unexpected error", false
      pfRecord pName, pExpected, "?", "UNCLASSIFIED", pError
   end if
end pfReport

-- Which of the three things happened, read off the thrown text - because five
-- of the six guards are private handlers that never expose the number they
-- compared, so the message is all there is.
--
-- THE FAMILY'S SIX ABI GUARDS ALL SAY "ABI " IN THEIR MESSAGE, and
-- tools/build-preflight.py re-proves that against all six .lcb sources every
-- time it runs: a reworded guard fails the suite build instead of quietly
-- turning every skew on every engine into an UNCLASSIFIED row. The trailing
-- space is load-bearing - it is what keeps an engine message that merely says
-- "capability" (c-ap-ABI-lity) out of the skew bucket.
function pfClassify pError
   local tText

   put toLower(pError) into tText
   if tText contains "abi " then
      return "skew"
   end if
   -- The ABSENT spelling is the ENGINE's, not ours, and this file has never run
   -- on one - so it matches loosely and prints the raw text either way. A miss
   -- here costs a mislabelled row; it can never cost the fact itself.
   if tText contains "handler" then
      return "absent"
   end if
   if tText contains "not found" then
      return "absent"
   end if
   if tText contains "can't find" then
      return "absent"
   end if
   return "unknown"
end pfClassify

-- FIRST WRITE WINS, and that is what makes the table complete rather than
-- merely usually complete. Each probe records its own row, and stRun records a
-- PROBE ERROR row from the catch around it - so a member whose probe died in
-- its own scaffolding still HAS a row (a missing row reads as "not checked",
-- which is the one thing this file must never say by accident), and a member
-- that threw after recording does not get a second one.
command pfRecord pName, pExpected, pFound, pVerdict, pDetail
   if pName is among the lines of sSeen then
      exit pfRecord
   end if
   put pName & return after sSeen
   put pfRow(pName, pExpected, pFound, pVerdict) & return after sRows
   if pDetail is not empty then
      put pfPad(pName & ":", 16) & pDetail & return after sDetails
   end if
end pfRecord

command pfNote pText
   put pText & return after sDetails
end pfNote

function pfRow pName, pExpected, pFound, pVerdict
   return pfPad(pName, 16) & pfPad(pExpected, 10) & pfPad(pFound, 13) & pVerdict
end pfRow

-- Left-justify pText in pWidth columns. The table has to line up in the report
-- field's mono face to be one screenshot; a value LONGER than its column pushes
-- its row out rather than being truncated, because a truncated ABI number is
-- exactly the small lie this file exists to prevent.
function pfPad pText, pWidth
   local tOut, tI, tNeed

   put pText into tOut
   put pWidth - the number of chars of pText into tNeed
   repeat with tI = 1 to tNeed
      put space after tOut
   end repeat
   return tOut
end pfPad
