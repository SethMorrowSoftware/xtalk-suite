script "xtEngineLint"

-- engine-lint.livecodescript - hand the ENGINE every script in the tree and
-- write down what it says.
--
-- WHAT THIS IS. The compiler this repository has never had. Twenty-odd Python
-- rules in tools/check-livecodescript.py exist to approximate a parse we could
-- not run; this file runs the parse. It reads a manifest of absolute paths, sets
-- each file's text as the script of a scratch stack, and emits one record per
-- file saying whether the engine accepted it and, when it did not, exactly what
-- the engine said.
--
-- WHAT IT IS NOT. It is not a test of BEHAVIOUR. A file that compiles here has
-- been proven to PARSE, and nothing more - every runtime entry in
-- docs/OXT-ENGINE-NOTES.md (the case-folding `is`, the trailing-delimiter eat,
-- the defaultStack rule for timers, an empty value into a typed .lcb parameter)
-- would sail straight through. Roughly seven of that file's twenty-five entries
-- are compile-time; the other eighteen are not, and no result from this file may
-- be used to promote one of them. The honesty label a green run here earns is
-- "parses on <engine> <version>, dated" - not "verified".
--
-- THE TWO CONTROLS ARE THE WHOLE POINT, and they are built IN HERE rather than
-- in the driver. A lint that only ever asks "did this compile?" cannot tell an
-- engine that accepts everything from an engine that silently accepts nothing:
-- both report zero failures. So every run emits a KNOWN-GOOD record that must
-- come back clean and a KNOWN-BAD record that must come back dirty, and
-- tools/check-engine-lint.py refuses the whole report unless both behaved. The
-- known-bad is engine note 3.3's own defect - a zero-argument call in statement
-- position - because that is the one compile error that has actually cost this
-- project a session.
--
-- HOW IT RUNS: see tools/check-engine-lint.py, which writes the manifest, builds
-- the wrapper for whichever engine it found, and parses what comes back. At a
-- GUI engine, paste this file per OXT-PASS-RUNBOOK 3.1 and call
--   put xtLintRun("/abs/path/to/manifest.txt")
-- The two routes must agree; where they do not, the GUI is the control.

constant kXtLintBegin = "XTLINT-BEGIN"
constant kXtLintEnd = "XTLINT-END"
constant kXtLintVersion = "1"
constant kXtLintHost = "xtLintHostStack"

local sXtLintLines
local sXtLintCount


on xtLintNoop
   -- Exists only so `send "xtLintNoop" to me` above is a HANDLED message: an
   -- unhandled send sets the result to "Message not handled", which would dirty
   -- the very thing the send is there to clean.
end xtLintNoop


private command xtLintEmit pKind, pName, pVerdict, pDetail
   local tFlat
   put pDetail into tFlat
   replace return with "<NL>" in tFlat
   replace numToChar(10) with "<NL>" in tFlat
   replace numToChar(13) with "<NL>" in tFlat
   replace tab with " " in tFlat
   put pKind & tab & pName & tab & pVerdict & tab & tFlat & return after sXtLintLines
   add 1 to sXtLintCount
end xtLintEmit


-- Compile one piece of TEXT and return the engine's verdict as a two-item
-- answer: item 1 is OK / FAIL / ERROR, the rest is whatever the engine said.
--
-- The three outcomes stay distinct deliberately. OK and FAIL are the compiler
-- answering; ERROR is this handler failing to ask, which is not the same thing
-- and must never be folded into either - a probe fault reported as FAIL would
-- send someone hunting a syntax error that is not there, and reported as OK
-- would hide a real one.
private function xtLintCompileText pText
   local tErr, tRes
   try
      -- CLEAR `the result` FIRST, and this line is load-bearing.
      --
      -- If a successful `set the script of` leaves `the result` UNCHANGED
      -- rather than emptying it, then whatever the previous command left there
      -- becomes this file's verdict - the `put url (file:...)` read three lines
      -- up in xtLintOne, or the genuine compile error of the PREVIOUS file. The
      -- second is the dangerous one: one real failure would make every file
      -- after it fail with the same text, and a maintainer would read a cascade
      -- as a corpus full of defects.
      --
      -- `send` to a handler that exists sets the result to empty, which is why
      -- a no-op message is used rather than an assignment (an assignment does
      -- not touch the result at all). Whether the clear is even NECESSARY is
      -- the probe's compile.resultClearedOnSuccess row; it is done
      -- unconditionally because doing it when it is unneeded costs one message
      -- dispatch, and not doing it when it is needed costs the whole run. The
      -- driver carries a cascade detector as well - a backstop, not a
      -- substitute.
      send "xtLintNoop" to me
      set the script of stack kXtLintHost to pText
      put the result into tRes
      if tRes is empty then
         return "OK"
      end if
      return "FAIL" & comma & tRes
   catch tErr
      -- A throw is a legitimate way for an engine to report a bad compile, so it
      -- counts as FAIL, not ERROR: the probe asked its question and got an
      -- answer. Which shape a given engine uses is recorded by
      -- tools/engine-probe.livecodescript's compile.badIsReported row.
      return "FAIL" & comma & "threw:" && tErr
   end try
end xtLintCompileText


-- The controls, and there are now three questions rather than one.
--
-- PRE AND POST. The first version ran the pair once, before the corpus. That
-- cannot see an engine that degrades PARTWAY - runs out of a script-object
-- budget, or starts accepting everything after N compiles - and a degraded
-- engine's silence is a clean report. The pair runs again after the last file,
-- under DISTINCT names, and the driver requires all four and refuses a report
-- carrying any control name twice. Distinct names matter: with one name and two
-- records, a parser that keeps the first sees the healthy answer and a parser
-- that keeps the last sees the degraded one, and neither is a refusal.
--
-- AT SCALE. Both small controls are about sixty bytes. Nothing in them speaks
-- for the sizes this corpus actually reaches - the generated suite paste is
-- 1.95 MB and 42,014 lines - so a size-dependent degradation, where an engine
-- silently stops checking past some threshold, would leave every small control
-- green. The large control is a synthetic ~20,000-line module carrying the same
-- defect, and it must be rejected too.
private command xtLintControls pWhen
   local tGood, tBad, tVerdict
   put "on xtLintControlNoop" & return & "end xtLintControlNoop" into tGood
   put xtLintCompileText(tGood) into tVerdict
   xtLintEmit "CONTROL", "known-good-" & pWhen, item 1 of tVerdict, item 2 to -1 of tVerdict

   put "on xtLintControlBroken" & return & "  xtLintControlNoop()" & return & "end xtLintControlBroken" into tBad
   put xtLintCompileText(tBad) into tVerdict
   xtLintEmit "CONTROL", "known-bad-" & pWhen, item 1 of tVerdict, item 2 to -1 of tVerdict
end xtLintControls


private command xtLintLargeControl
   local tBig, tIndex, tVerdict, tErr
   try
      put "on xtLintBigBroken" & return into tBig
      repeat with tIndex = 1 to 20000
         put "  put" && tIndex && "into tScratch" & return after tBig
      end repeat
      -- The same defect as the small known-bad: engine note 3.3's zero-argument
      -- call in statement position, buried 20,000 lines deep.
      put "  xtLintControlNoop()" & return after tBig
      put "end xtLintBigBroken" after tBig
      put xtLintCompileText(tBig) into tVerdict
      xtLintEmit "CONTROL", "known-bad-large", item 1 of tVerdict, item 2 to -1 of tVerdict
   catch tErr
      xtLintEmit "CONTROL", "known-bad-large", "ERROR", tErr
   end try
end xtLintLargeControl


-- One manifest entry. The file is read as TEXT through the `file:` scheme; every
-- script in this tree is ASCII by gate (check-livecodescript's first rule), so
-- there is no encoding question to get wrong here - and if that ever stops being
-- true, the ASCII gate fails first and loudly.
--
-- AN EMPTY READ IS AN ERROR, NOT AN EMPTY SCRIPT. An empty script compiles
-- cleanly, so a path typo, a permission failure or a truncated read would report
-- OK for a file the engine never saw. That is the exact silent-green shape this
-- repo's CLAUDE.md catalogues, so emptiness is refused here and the driver
-- cross-checks the byte count it expected against the one reported.
private command xtLintOne pPath
   local tText, tVerdict, tErr, tSize
   try
      put url ("file:" & pPath) into tText
      if tText is empty then
         xtLintEmit "FILE", pPath, "ERROR", "read returned nothing - missing, unreadable, or empty"
         exit xtLintOne
      end if
      -- Counted into a local FIRST: written inline,
      -- `the number of chars of tText & "; "` binds as
      -- `the number of chars of (tText & "; ")`, so the byte count the driver
      -- cross-checks would be silently two too high.
      put the number of chars of tText into tSize
      put xtLintCompileText(tText) into tVerdict
      xtLintEmit "FILE", pPath, item 1 of tVerdict, "chars=" & tSize & "; " & (item 2 to -1 of tVerdict)
   catch tErr
      xtLintEmit "FILE", pPath, "ERROR", tErr
   end try
end xtLintOne


function xtLintRun pManifestPath
   local tManifest, tLine, tErr, tPath

   put empty into sXtLintLines
   put 0 into sXtLintCount
   put kXtLintBegin & tab & kXtLintVersion & return into sXtLintLines

   try
      if there is a stack kXtLintHost then
         delete stack kXtLintHost
      end if
      create invisible stack kXtLintHost
   catch tErr
      -- Without a scratch object nothing below can run, and saying so as ONE
      -- loud record beats emitting forty-nine identical ERROR rows.
      xtLintEmit "FATAL", "host-stack", "ERROR", tErr
      put kXtLintEnd & tab & sXtLintCount after sXtLintLines
      return sXtLintLines
   end try

   xtLintControls "pre"
   xtLintLargeControl

   put empty into tManifest
   try
      put url ("file:" & pManifestPath) into tManifest
   catch tErr
      xtLintEmit "FATAL", "manifest", "ERROR", tErr
   end try

   if tManifest is empty then
      -- A zero-length manifest would otherwise produce a report with two clean
      -- controls and no files, which reads green. The driver also enforces a
      -- floor; this is the same refusal on the engine side, because a gate with
      -- one place to fail open is a gate with one place to be wrong.
      xtLintEmit "FATAL", "manifest", "ERROR", "manifest" && pManifestPath && "is empty or unreadable"
   else
      repeat for each line tLine in tManifest
         put word 1 to -1 of tLine into tPath
         if tPath is not empty then
            xtLintOne tPath
         end if
      end repeat
   end if

   -- After the corpus, so a degradation that set in partway through is visible.
   xtLintControls "post"

   try
      if there is a stack kXtLintHost then
         delete stack kXtLintHost
      end if
   catch tErr
      xtLintEmit "TEARDOWN", "host-stack", "ERROR", tErr
   end try

   put kXtLintEnd & tab & sXtLintCount after sXtLintLines
   return sXtLintLines
end xtLintRun
