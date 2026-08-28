script "xtEngineProbe"

-- engine-probe.livecodescript - ONE script that ASKS THE ENGINE what it can do,
-- and writes the answer down in a form a gate can read.
--
-- WHY THIS EXISTS, AND WHY IT IS FIRST. Seventy-four places in this tree assert
-- that "OXT has no headless way to compile or run .livecodescript or .lcb", and
-- every static gate in tools/ is a stand-in built on that premise. On 2026-08-27
-- a LiveCode community reply to the suite's forum post said the premise is
-- wrong - that the server engine and the LCB compiler both run headless, and
-- that editors already lint LiveCodeScript that way. That claim is worth a great
-- deal if it is true and worth nothing if it is repeated without evidence, which
-- is exactly the class this repo's honesty convention exists for.
--
-- So NOTHING in this file assumes an answer. Every probe below is a question
-- whose result is DUMPED VERBATIM, including the questions this project would
-- rather hear "yes" to. The file is deliberately not a test: a test decides, and
-- deciding is what we cannot yet do. It is an instrument.
--
-- THE EVIDENCE RULE (docs/OXT-ENGINE-NOTES.md) IS THE POINT. Everything anyone
-- currently believes about the headless surfaces is DOCUMENTED at best - recalled
-- from a language reference, not seen. One run of this file turns the subset it
-- covers into OBSERVED, on a dated record, and tools/check-engine-lint.py refuses
-- to enable any check whose capability this probe has not confirmed. That is the
-- whole architecture: the probe measures, the gates obey the measurement.
--
-- HOW TO RUN IT, EITHER WAY:
--
--   A. HEADLESS (the thing being tested). Let the driver build the wrapper:
--        python3 tools/check-engine-lint.py --engine /path/to/livecode-server --probe
--      It strips the `script "..."` header (engine notes 1.1: that line is a
--      stack-NAME marker, meaningful only when the file IS its own stack) and
--      wraps the body for the server engine. If the server engine cannot run
--      this file at all, THAT is the headline result and the driver says so.
--
--   B. AT A GUI ENGINE (the route every pass in this tree has used, so it is the
--      control). Per OXT-PASS-RUNBOOK 3.1: File > New Mainstack, Object > Stack
--      Script, paste this whole file, Apply, close and reopen. Then in the
--      message box:   put xtProbeRun()
--      and copy the text. Or write it straight to a file:
--        put xtProbeRun() into url ("file:" & "/tmp/xtprobe.txt")
--      Running it BOTH ways on the same machine is the highest-value use of this
--      file: the GUI column is the known-good control, so any row where the two
--      columns disagree is a real headless divergence rather than a bug in the
--      probe.
--
-- THE REPORT FORMAT is one record per line, tab-separated, four fields:
--     PROBE <tab> name <tab> verdict <tab> evidence
--   verdict is one of YES / NO / ERROR / INFO. INFO rows carry a measurement
--   rather than a capability (the engine's own version, say). Evidence is raw
--   and never interpreted here; returns inside it are folded to the literal
--   token <NL> so one record stays one line.
--
-- THE LAST LINE IS A COMPLETENESS MARKER, and it is not decoration. This repo
-- has already paid for a report that simply STOPPED - a live harness surface
-- that ends mid-section reads exactly like a finished run, and three truncated
-- pastes were diagnosed as a hung pump before anyone noticed they were early
-- copies (see the scaffold's RUN NOT FINISHED trailer, root CLAUDE.md). A probe
-- run that dies halfway through would otherwise report a tidy subset of
-- capabilities as if it were the whole answer, so the driver REFUSES any report
-- without the marker, and the marker carries the record count so a truncation
-- that happens to keep the last line still fails.

constant kXtProbeVersion = "1"
constant kXtProbeEnd = "XTPROBE-END"
constant kXtProbeStart = "XTPROBE-BEGIN"
constant kXtProbeHost = "xtProbeHostStack"

-- Set by the timer probe below; read by it a few lines later. Script-local so
-- the `send` target can reach it (engine notes 1.2: script-level names resolve
-- by LEXICAL POSITION, so this sits above every handler that touches it).
local sXtProbeTicked
local sXtProbeLines
local sXtProbeCount


-- ==================================================================== --
--  Record plumbing
-- ==================================================================== --

-- One record. Evidence is flattened here and NOWHERE else, so there is exactly
-- one place that can get the escaping wrong.
private command xtProbeEmit pName, pVerdict, pEvidence
   local tFlat
   put pEvidence into tFlat
   replace return with "<NL>" in tFlat
   replace numToChar(10) with "<NL>" in tFlat
   replace numToChar(13) with "<NL>" in tFlat
   replace tab with " " in tFlat
   put "PROBE" & tab & pName & tab & pVerdict & tab & tFlat & return after sXtProbeLines
   add 1 to sXtProbeCount
end xtProbeEmit


-- A capability probe's THREE outcomes are deliberately distinct. YES/NO is the
-- capability answering; ERROR is the probe itself failing, which is not the same
-- thing and must never be folded into NO - a NO would quietly disable a gate
-- that the engine may in fact support.
private command xtProbeYesNo pName, pOk, pEvidence
   if pOk then
      xtProbeEmit pName, "YES", pEvidence
   else
      xtProbeEmit pName, "NO", pEvidence
   end if
end xtProbeYesNo


-- ==================================================================== --
--  The probes
-- ==================================================================== --

-- 0. WHO IS ANSWERING. `the environment` is the discriminator that matters most
--    here: it reads "server" under the server engine, "development" in the IDE
--    and "standalone" in a built app, so a report can never be mistaken for one
--    taken in a different context - which is the whole risk of running the GUI
--    control and the headless run on the same machine and comparing columns.
private command xtProbeIdentity
   -- ONE TRY PER PROPERTY, and the reason is a real defect this file shipped
   -- with: all eight lived in a single `try`, so an engine that does not answer
   -- `the machine` would have cost the seven rows around it - including
   -- `the environment` and `the version`, which are the two that pin a result
   -- to a build. A property's absence is itself a finding worth recording.
   -- THE TWO ROWS THAT PIN A RESULT TO A BUILD ARE READ DIRECTLY, not through
   -- the `do` helper below. Every other row can afford the helper's compactness;
   -- these two cannot, because if `do` turns out NOT to share the calling
   -- handler's scope on this engine, `put the environment into tValue` would
   -- assign into a variable nobody reads and the row would be emitted EMPTY -
   -- present, well-formed, and worthless. The driver refuses a report it cannot
   -- pin to a build, so an empty value here has to be impossible rather than
   -- merely unlikely.
   xtProbeDirectIdentity
   xtProbeProperty "engine.buildNumber", "the buildNumber"
   xtProbeProperty "engine.platform", "the platform"
   xtProbeProperty "engine.processor", "the processor"
   xtProbeProperty "engine.systemVersion", "the systemVersion"
   xtProbeProperty "engine.machine", "the machine"
   xtProbeEmit "probe.version", "INFO", kXtProbeVersion
end xtProbeIdentity


private command xtProbeDirectIdentity
   local tErr, tValue
   try
      put the environment into tValue
      xtProbeEmit "engine.environment", "INFO", tValue
   catch tErr
      xtProbeEmit "engine.environment", "UNAVAILABLE", tErr
   end try
   try
      put the version into tValue
      xtProbeEmit "engine.version", "INFO", tValue
   catch tErr
      xtProbeEmit "engine.version", "UNAVAILABLE", tErr
   end try
end xtProbeDirectIdentity


-- Read one property by name, through `do`, so the remaining rows are single
-- statements rather than copies of a try block. Whether `do` shares this
-- handler's scope is not recorded anywhere in this tree; if it does not, these
-- rows come back empty and that is itself a finding - which is why the two rows
-- the driver depends on are read directly, above.
private command xtProbeProperty pName, pExpression
   local tErr, tValue
   try
      do ("put" && pExpression && "into tValue")
      xtProbeEmit pName, "INFO", tValue
   catch tErr
      xtProbeEmit pName, "UNAVAILABLE", tErr
   end try
end xtProbeProperty


-- 1. IS THERE AN OBJECT MODEL? Everything downstream needs somewhere to PUT a
--    script, and `create stack` is the cheapest somewhere. If this is NO under
--    the server engine, the lint idiom needs a different target and the driver
--    must say so rather than reporting zero lint failures.
private command xtProbeObjectModel
   local tErr, tMade
   put false into tMade
   try
      if there is a stack kXtProbeHost then
         delete stack kXtProbeHost
      end if
      create invisible stack kXtProbeHost
      put (there is a stack kXtProbeHost) into tMade
      xtProbeYesNo "object.createStack", tMade, "there is a stack ->" && tMade
   catch tErr
      xtProbeEmit "object.createStack", "ERROR", tErr
   end try
end xtProbeObjectModel


-- 2. THE LINT MECHANISM ITSELF, and it is asked as a PAIR on purpose.
--
--    A gate that only ever checks "does a good script compile?" cannot tell the
--    difference between an engine that compiles everything and an engine that
--    compiles nothing and reports nothing - both look green. So the negative
--    control runs first in the report and the driver requires BOTH: known-good
--    must come back clean AND known-bad must come back dirty. This tree has
--    shipped a coverage gate that counted a SKIP NOTE as coverage and a constant
--    gate that printed what it had parsed as what it had checked; the pair is
--    the cheapest defence against joining that list.
--
--    The known-bad script is engine note 3.3's own bug - a zero-argument call in
--    STATEMENT position - because it is the single defect that has actually cost
--    this project an engine session (one `dcCleanup()` took a 4400-line paste
--    down), and because a compiler catching it is the smallest complete proof
--    that the headless route would have paid for itself.
private command xtProbeCompile
   local tErr, tGoodRes, tBadRes, tGood, tBad
   put "on xtProbeNoop" & return & "end xtProbeNoop" into tGood
   put "on xtProbeBroken" & return & "  xtProbeNoop()" & return & "end xtProbeBroken" into tBad

   try
      set the script of stack kXtProbeHost to tGood
      put the result into tGoodRes
      xtProbeYesNo "compile.goodIsClean", (tGoodRes is empty), "the result ->" && tGoodRes
   catch tErr
      -- A THROW here is itself an answer, and a usable one: it means compile
      -- failures surface as errors rather than through `the result`. Recorded as
      -- ERROR because a good script throwing is not a capability answer.
      xtProbeEmit "compile.goodIsClean", "ERROR", "threw:" && tErr
   end try

   try
      set the script of stack kXtProbeHost to tBad
      put the result into tBadRes
      xtProbeYesNo "compile.badIsReported", (tBadRes is not empty), "the result ->" && tBadRes
      xtProbeEmit "compile.errorFormat", "INFO", tBadRes
   catch tErr
      -- The other half of the same either/or. Both shapes are fine; the driver
      -- only needs to know WHICH, and it learns it here rather than assuming.
      xtProbeEmit "compile.badIsReported", "YES", "threw:" && tErr
      xtProbeEmit "compile.errorFormat", "INFO", "throw:" && tErr
   end try
end xtProbeCompile


-- 3. DOES THE ERROR CARRY A LINE NUMBER? The difference between a usable gate
--    and an annoying one. The bad token sits on line 4 of a 6-line script and
--    the whole answer is dumped, so whoever reads the report can see the format
--    instead of trusting a parser written against a guess.
private command xtProbeErrorDetail
   local tErr, tRes, tScript
   put "on xtProbeL1" & return into tScript
   put "  put 1 into tOne" & return after tScript
   put "end xtProbeL1" & return after tScript
   put "on xtProbeL4" & return after tScript
   put "  put into into into" & return after tScript
   put "end xtProbeL4" after tScript
   try
      set the script of stack kXtProbeHost to tScript
      put the result into tRes
      xtProbeEmit "compile.lineNumbers", "INFO", "bad token is on line 5; the result ->" && tRes
   catch tErr
      xtProbeEmit "compile.lineNumbers", "INFO", "bad token is on line 5; threw ->" && tErr
   end try
end xtProbeErrorDetail


-- 4. THE ONE WITH THE LARGEST PRIZE. `the explicitVariables` makes the use of an
--    undeclared name a COMPILE error rather than a silent evaluation.
--
--    Engine note 2.1 (OBSERVED) is that an undeclared name evaluates to the
--    LITERAL TEXT OF ITS OWN NAME. That is this tree's most expensive class of
--    bug precisely because it never errors: the generator's 106-declaration fold
--    ran `add "cx1sPassed" to sPassed` and reported a tidy wrong answer, and the
--    checker carries a whole hand-written rule (check_undeclared_k_constants)
--    approximating one flag the engine already has. If this probe comes back YES,
--    a headless lint can promote that entire class from runtime-silent to
--    compile-loud for the whole corpus at once - which is a bigger win than the
--    lint itself. Restored afterwards, because leaving it set would change the
--    behaviour of anything else running in this engine.
private command xtProbeExplicitVars
   local tErr, tRes, tWas, tScript
   put "on xtProbeUndeclared" & return & "  put 1 into tNeverDeclaredAnywhere" & return & "end xtProbeUndeclared" into tScript
   try
      put the explicitVariables into tWas
      set the explicitVariables to true
      set the script of stack kXtProbeHost to tScript
      put the result into tRes
      xtProbeYesNo "compile.explicitVariables", (tRes is not empty), "the result ->" && tRes
      set the explicitVariables to tWas
   catch tErr
      xtProbeEmit "compile.explicitVariables", "ERROR", tErr
      try
         set the explicitVariables to tWas
      catch tErr
         xtProbeEmit "compile.explicitVariablesRestore", "ERROR", tErr
      end try
   end try
end xtProbeExplicitVars


-- 5. IS THERE A MESSAGE LOOP? This is the question that decides whether the
--    40,000-line suite harness could ever run headless, because its async half
--    is driven entirely by `send "stPump" to me in 33 milliseconds`. A compile
--    lane needs none of this; a TEST lane needs all of it. Asked separately from
--    everything above so a NO here cannot be read as a NO on linting.
private command xtProbeMessageLoop
   local tErr
   put false into sXtProbeTicked
   try
      send "xtProbeTick" to me in 1 millisecond
      wait 120 milliseconds with messages
      xtProbeYesNo "runtime.sendInTime", sXtProbeTicked, "ticked ->" && sXtProbeTicked
   catch tErr
      xtProbeEmit "runtime.sendInTime", "ERROR", tErr
   end try
end xtProbeMessageLoop


on xtProbeTick
   put true into sXtProbeTicked
end xtProbeTick


-- 6. CAN IT READ AND WRITE FILES? A lint driver hands the engine a manifest and
--    reads a report back, so both directions are load-bearing. Probed rather
--    than assumed because the server engine's file access is exactly the sort of
--    thing a sandbox or a policy can narrow.
private command xtProbeFiles
   local tErr, tPath, tBack
   try
      put xtProbeTempFolder() & "/xtprobe-rw.txt" into tPath
      put "roundtrip" into url ("file:" & tPath)
      put url ("file:" & tPath) into tBack
      xtProbeYesNo "io.fileRoundTrip", (tBack is "roundtrip"), "wrote to" && tPath & "; read back ->" && tBack
   catch tErr
      xtProbeEmit "io.fileRoundTrip", "ERROR", tErr
   end try
end xtProbeFiles


private function xtProbeTempFolder
   local tFolder, tErr, tWasDelim
   put empty into tFolder
   put the itemDelimiter into tWasDelim
   try
      put the tempName into tFolder
      -- Restored below, on BOTH paths. `the itemDelimiter` is global mutable
      -- state (engine notes 2.3), so leaving it set to "/" would silently
      -- change how every `item` expression after this point behaves - and this
      -- file parses `item 1 of` a comma-joined verdict a few handlers later.
      set the itemDelimiter to "/"
      delete the last item of tFolder
   catch tErr
      -- Caught into its OWN name on purpose. `catch tFolder` would bind the
      -- error text to the variable being built, and the emptiness test below
      -- would then pass an error message off as a directory - a fail-open of
      -- exactly the shape this tree keeps finding in its own gates.
      put empty into tFolder
   end try
   set the itemDelimiter to tWasDelim
   if tFolder is empty then
      put "/tmp" into tFolder
   end if
   return tFolder
end xtProbeTempFolder


-- 7. CAN A SCRIPT-ONLY STACK BE LOADED FROM DISK? Thirty-five of this tree's
--    forty-nine .livecodescript files carry a `script "Name"` first line, which
--    makes them script-only stacks the engine can load directly. If this works
--    headlessly it is a SECOND lint route - and a better one for those 35,
--    because it exercises the same path a user's `start using stack` takes
--    rather than a synthetic `set the script of`. Probed against this very file,
--    which is the one script-only stack guaranteed to be present.
private command xtProbeStartUsing pSelfPath
   local tErr, tOk
   if pSelfPath is empty then
      xtProbeEmit "load.startUsingStack", "INFO", "no path supplied; skipped"
      exit xtProbeStartUsing
   end if
   local tRes
   try
      start using stack pSelfPath
      -- Captured ONCE. `the result` is clobbered by the next command that sets
      -- it, so reading it twice - once for the verdict and once for the
      -- evidence - can report a verdict the evidence does not support.
      put the result into tRes
      put (tRes is empty) into tOk
      xtProbeYesNo "load.startUsingStack", tOk, "path" && pSelfPath & "; the result ->" && tRes
      stop using stack pSelfPath
   catch tErr
      xtProbeEmit "load.startUsingStack", "ERROR", tErr
   end try
end xtProbeStartUsing


-- 8. DOES THE EXTENSION LOADER EXIST HEADLESS? Asked INDIRECTLY, and the
--    indirection is the trick worth keeping: pointing `load extension from file`
--    at a path that certainly does not exist separates the two failures that
--    matter. A "can't find the file" style error proves the COMMAND EXISTS and
--    only the argument was wrong; a parse error proves it does not. Either way
--    nothing is loaded, so the probe cannot disturb an engine that already has
--    the suite's extensions installed.
private command xtProbeExtensionLoader
   local tErr, tRes
   try
      load extension from file (xtProbeTempFolder() & "/xt-no-such-extension.lcm")
      put the result into tRes
      xtProbeEmit "load.extensionCommand", "YES", "command parsed; the result ->" && tRes
   catch tErr
      -- A parse failure and a missing-file failure both land here on some
      -- engines, so the TEXT is dumped rather than classified. The driver, and
      -- the human reading the report, get the raw string.
      xtProbeEmit "load.extensionCommand", "INFO", "raised ->" && tErr
   end try
   try
      xtProbeEmit "load.loadedExtensions", "INFO", the loadedExtensions
   catch tErr
      xtProbeEmit "load.loadedExtensions", "ERROR", tErr
   end try
end xtProbeExtensionLoader


-- 9. HOW BIG A SCRIPT WILL IT TAKE? The generated suite paste is 1.95 MB and
--    42,014 lines, so "the engine compiles scripts" is not yet "the engine
--    compiles OUR script". A synthetic block of the same order is cheaper to
--    build than to read from disk and answers the size question on its own.
private command xtProbeLargeScript
   local tErr, tBig, tIndex, tRes, tSize
   try
      put "on xtProbeBig" & return into tBig
      repeat with tIndex = 1 to 20000
         put "  put" && tIndex && "into tScratch" & return after tBig
      end repeat
      put "end xtProbeBig" after tBig
      set the script of stack kXtProbeHost to tBig
      put the result into tRes
      -- The char count goes into a local FIRST. Written inline,
      -- `the number of chars of tBig && "chars..."` binds as
      -- `the number of chars of (tBig && "chars...")` - a chunk expression over
      -- the concatenation, not the count of tBig - and the reported number
      -- would be quietly wrong rather than an error.
      put the number of chars of tBig into tSize
      xtProbeYesNo "compile.largeScript", (tRes is empty), "20002 lines," && tSize && "chars; the result ->" && tRes
   catch tErr
      xtProbeEmit "compile.largeScript", "ERROR", tErr
   end try
end xtProbeLargeScript



-- MANDATORY ROWS: did this engine actually EXECUTE the probe?
--
-- The rows below must be YES on any engine that ran this file at all, and
-- tools/check-engine-lint.py REFUSES a report in which they are not. They exist
-- because every capability row above can legitimately answer NO, so a report of
-- all-NO is indistinguishable from a report produced by something that printed
-- the scaffolding and evaluated nothing - and the first version of the driver
-- treated that as a successful probe worth committing. These separate the two.
--
-- The round-trip row is the more interesting of the two: it feeds a value
-- containing a TAB and a RETURN through the same xtProbeEmit that every other
-- row uses, and asserts the flattening happened. A probe whose own record
-- format is broken would otherwise report tidy rows that the Python parser
-- silently mis-splits.
private command xtProbeMandatory
   local tErr, tSum, tDirty, tFlatOk
   try
      put 2 + 2 into tSum
      xtProbeYesNo "probe.selfArithmetic", (tSum is 4), "2 + 2 ->" && tSum
   catch tErr
      xtProbeEmit "probe.selfArithmetic", "ERROR", tErr
   end try
   try
      put "a" & tab & "b" & return & "c" into tDirty
      put (tDirty contains tab) into tFlatOk
      -- Emitted through the ordinary path; the driver checks that the record it
      -- receives carries NO raw tab beyond the field separators and no split.
      xtProbeEmit "probe.emitRoundTrip", "YES", tDirty
   catch tErr
      xtProbeEmit "probe.emitRoundTrip", "ERROR", tErr
   end try
end xtProbeMandatory


-- DOES `set the script of` CLEAR `the result` ON SUCCESS?
--
-- This row settles the single most dangerous ambiguity in the lint idiom. If a
-- successful `set the script of` leaves `the result` UNCHANGED rather than
-- emptying it, then a stale error from any earlier command - the file read
-- immediately before it, or the previous file's genuine compile failure - is
-- read as this file's verdict, and a corpus lint cascades: one real failure
-- makes every file after it fail with the same text. The driver carries a
-- cascade detector for exactly that, but a detector is a backstop; this is the
-- measurement.
private command xtProbeResultClearing
   local tErr, tRes, tGood
   put "on xtProbeClean" & return & "end xtProbeClean" into tGood
   try
      -- Dirty `the result` deliberately. `there is a stack` does not set it, so
      -- a command that fails is used: the point is to leave something behind.
      try
         delete stack "xtProbeNoSuchStackAnywhere"
      catch tErr
         -- expected; the throw is the dirtying
      end try
      set the script of stack kXtProbeHost to tGood
      put the result into tRes
      xtProbeYesNo "compile.resultClearedOnSuccess", (tRes is empty), "after a deliberately dirtied result, a GOOD compile left the result ->" && tRes
   catch tErr
      xtProbeEmit "compile.resultClearedOnSuccess", "ERROR", tErr
   end try
end xtProbeResultClearing

-- ==================================================================== --
--  The runner
-- ==================================================================== --

-- pSelfPath is optional and is only used by probe 7. The driver passes the
-- absolute path of this file; a human running it from the message box can pass
-- nothing and get an explicit skip rather than a missing row.
function xtProbeRun pSelfPath
   local tErr
   put empty into sXtProbeLines
   put 0 into sXtProbeCount
   put kXtProbeStart & tab & kXtProbeVersion & return into sXtProbeLines

   -- Each probe is called inside its own try. A probe that takes the engine
   -- down would otherwise cost every row BELOW it, and this repo's own harness
   -- learned that lesson the expensive way: one uncaught error in a counter
   -- merge lost six harnesses' worth of results and could not name the member
   -- it came from.
   try
      xtProbeMandatory
   catch tErr
      xtProbeEmit "probe.mandatory", "ERROR", tErr
   end try
   try
      xtProbeIdentity
   catch tErr
      xtProbeEmit "probe.identity", "ERROR", tErr
   end try
   try
      xtProbeObjectModel
   catch tErr
      xtProbeEmit "probe.objectModel", "ERROR", tErr
   end try
   try
      xtProbeCompile
   catch tErr
      xtProbeEmit "probe.compile", "ERROR", tErr
   end try
   try
      xtProbeErrorDetail
   catch tErr
      xtProbeEmit "probe.errorDetail", "ERROR", tErr
   end try
   try
      xtProbeResultClearing
   catch tErr
      xtProbeEmit "probe.resultClearing", "ERROR", tErr
   end try
   try
      xtProbeExplicitVars
   catch tErr
      xtProbeEmit "probe.explicitVars", "ERROR", tErr
   end try
   try
      xtProbeMessageLoop
   catch tErr
      xtProbeEmit "probe.messageLoop", "ERROR", tErr
   end try
   try
      xtProbeFiles
   catch tErr
      xtProbeEmit "probe.files", "ERROR", tErr
   end try
   try
      xtProbeStartUsing pSelfPath
   catch tErr
      xtProbeEmit "probe.startUsing", "ERROR", tErr
   end try
   try
      xtProbeExtensionLoader
   catch tErr
      xtProbeEmit "probe.extensionLoader", "ERROR", tErr
   end try
   try
      xtProbeLargeScript
   catch tErr
      xtProbeEmit "probe.largeScript", "ERROR", tErr
   end try

   -- Teardown is best-effort and never allowed to cost the report: the rows are
   -- already assembled by here, and a failure to delete a scratch stack is not a
   -- reason to lose them.
   try
      if there is a stack kXtProbeHost then
         delete stack kXtProbeHost
      end if
   catch tErr
      xtProbeEmit "probe.teardown", "ERROR", tErr
   end try

   put kXtProbeEnd & tab & sXtProbeCount after sXtProbeLines
   return sXtProbeLines
end xtProbeRun
