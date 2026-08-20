-- harness-scaffold.livecodescript - the pasteable self-test scaffolding,
-- as ONE carried block.
--
-- WHY THIS EXISTS. The five window-building harnesses (enetxt,
-- datachannelxt, torrentxt, coinxt, and the suite core) grew from one
-- lineage and were measured 99% byte-identical - but the last 1% was
-- exactly the kind of drift the checker unification exists to prevent:
-- torrentxt spelled sections "---" where everyone else spelled them "==",
-- used different greens, and formatted its summary so the suite's report
-- parser could never have read it; the Copy-results button, the SKIP
-- outcome, the per-line result coloring and the section-failure isolation
-- each lived in only one or two copies. This file is the union, carried
-- VERBATIM into each harness the way the demo kit and the checker are,
-- with tools/check-harness-scaffold-drift.py failing the build on any
-- divergence.
--
-- WHAT AN ADOPTING HARNESS DOES:
--   1. declares, ABOVE the block (OXT resolves constants by lexical
--      position):  constant kStTitle  / kStWidth / kStHeight
--   2. owns openStack (usually stBuild + stRun), stRun, and stCleanup
--      (a member with nothing to release ships an empty stCleanup and
--      says why - the Re-run button and closeStack call it regardless);
--   3. calls stResetCounters FIRST thing in stRun, and stReportDone at
--      the point the run is complete (synchronous harnesses at the end
--      of stRun; async ones from the tick that finishes the run);
--   4. reports through stAssert / stSkip / stSection / stSectionFailed /
--      stNote, and may call stShow mid-run for live progress.
--
-- THE FOLDED SUITE HARNESS: tools/build-suite-selftest.py DROPS this
-- block's window half from folded members (openStack/closeStack/mouseUp,
-- stBuild, the stMake* builders, stMonoFont, stShow/stPaint/
-- stCopyResults - the core owns the one window there) and stubs
-- stShow/stPaint where folded code still calls them; the counters and
-- the assertion plumbing fold in and RUN. Keep that split in mind before
-- adding a handler here: UI goes in the droppable set, accounting does
-- not.
--
-- The look matches the demo kit's v2 values by VALUE (page ground, band
-- blue, the ok/warn/bad set, the platform mono face) but the block is
-- deliberately kit-independent: harnesses are tools, fold into the suite
-- paste, and must not carry a second 300-line block to stay pasteable.

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
   -- PIN THE STACK, AND FAIL CLOSED IF THE WINDOW IS NOT THERE. An unqualified
   -- `field "stResults"` resolves against THE DEFAULTSTACK, not against the
   -- stack whose script is running (OXT-ENGINE-NOTES 5.3). Inside openStack
   -- those are the same object, which is why the synchronous half of every run
   -- has always rendered. This handler is ALSO called from an async pump, on a
   -- `send ... in` tick, where they are not: with another window in front the
   -- write would throw "Chunk: error in object expression", and in the suite
   -- core that throw lands in stPump, which is where the timer re-arms.
   -- PRECAUTIONARY, NOT DIAGNOSED. It was written on 2026-08-20 while chasing
   -- two engine reports that ended mid-CROSS-section, and that was the wrong
   -- cause: the third run, same build, completed 1981/0/1 through both
   -- loopbacks and the summary. Those two were early Copies, which is what the
   -- trailer in stReportText now says out loud. What stands on its own is the
   -- hazard class - engine-observed in enet-lan-chat's ecDashOnce on
   -- 2026-08-18 - and the fact that this is the same fault, and the same fix,
   -- as the ui-kit's uiStatus, one carried block over.
   set the defaultStack to the short name of this stack
   if there is no field "stResults" then exit stShow
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
   -- Pinned for the reason stShow above is: stReportDone calls this one too,
   -- and an async harness reaches stReportDone from a timer tick.
   set the defaultStack to the short name of this stack
   if there is no field "stResults" then exit stPaint
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
