script "ShowControlLcsRunner"
-- ---------------------------------------------------------------------------
-- _runner.livecodescript - runs ONE LiveCode Script test handler inside a real
-- OXT engine with no user interface, and reports it as TAP on stdout.
--
-- Launched by tools/run-lcs-tests.py as
--     standalone-community -ui tests/lcs/_runner.livecodescript
-- with everything else passed in environment variables (engine flags are parsed
-- out of argv anywhere on the command line, so arguments are fragile):
--     SC_MODE        list | run | probe-sockets
--     SC_TEST_FILE   absolute path of the test stack (*.livecodescript)
--     SC_TEST        handler to run (run mode)
--     SC_EXT_ROOT    folder holding one subfolder per extension, each with
--                    module.lcm and code/<platform-id>/<lib> -- the packaged
--                    extension layout
--     SC_HELPERS     path of the member's helper script, examples/*-helpers
--                    (HELPERS in tools/runner_config.py)
--     SC_PORT_BASE   first UDP port this test may use
--
-- Why our own runner (not OXT's tests/_testrunner.livecodescript): that one is
-- GPLv3 and drags in the engine's source tree; this one is MIT like the rest of
-- the member and does only what these suites need. The TAP it prints matches
-- the LCB unittest output, so tools/run-lcs-tests.py parses both identically.
--
-- Native libraries are mapped EXACTLY the way the IDE maps an installed
-- extension's code/ folder (revideextensionlibrary __MapCodeLibraryForIDE):
-- folders matching the platform, then `the processor` first. So a run also
-- proves the committed code/<platform-id>/ naming is what the engine looks for.
-- ---------------------------------------------------------------------------

local sPass, sFail, sSkip, sErrorDialogs

on startup
   local tMode, tErr
   put 0 into sPass
   put 0 into sFail
   put 0 into sSkip
   put $SC_MODE into tMode
   try
      if tMode is "probe-sockets" then
         scProbeSockets
      else if tMode is "compile-check" then
         scCompileCheck $SC_FILES
      else if tMode is "list" then
         scListTests $SC_TEST_FILE
      else
         scLoadEverything
         scRunOne $SC_TEST_FILE, $SC_TEST
      end if
   catch tErr
      TestAssert "runner: " & scErrorLine(tErr), false
      TestDiagnostic tErr
   end try
   if sFail > 99 then
      quit 99
   end if
   quit sFail
end startup

-- ===== assertion API (called from test stacks) ==============================

on TestAssert pDesc, pOk
   if pOk is true then
      add 1 to sPass
      scWrite "ok - " & scClean(pDesc)
   else
      add 1 to sFail
      scWrite "not ok - " & scClean(pDesc)
   end if
end TestAssert

-- Assert equality, printing what was seen when it fails (every assertion must
-- show the value it saw -- a bare "not ok" is useless in a CI log).
on TestAssertEqual pDesc, pGot, pWant
   if pGot is pWant then
      TestAssert pDesc, true
   else
      TestAssert pDesc, false
      TestDiagnostic "  got:  " & scShow(pGot)
      TestDiagnostic "  want: " & scShow(pWant)
   end if
end TestAssertEqual

on TestSkip pDesc, pReason
   add 1 to sSkip
   scWrite "ok - " & scClean(pDesc) & " # SKIP " & scClean(pReason)
end TestSkip

on TestDiagnostic pMsg
   local tLine
   repeat for each line tLine in pMsg
      scWrite "# " & tLine
   end repeat
end TestDiagnostic

-- Service engine events (socket callbacks, `send ... in`) for up to pMs
-- milliseconds, or until the named script-local of the TEST stack (read via
-- the function scFlag pName, which a test defines) becomes non-empty.
function TestWaitFor pTarget, pFlagFunc, pMs
   local tDeadline, tVal
   put the milliseconds + pMs into tDeadline
   repeat until the milliseconds > tDeadline
      put empty into tVal
      if pFlagFunc is not empty then
         dispatch function pFlagFunc to pTarget
         put the result into tVal
         if tVal is not empty and tVal is not false then
            return true
         end if
      end if
      wait 5 milliseconds with messages
   end repeat
   return false
end TestWaitFor

-- An error nothing caught in a message the engine delivered LATER (a `send ...
-- in` timer, a socket callback) never reaches the test handler: the engine
-- hands it to errorDialog instead (engine object.cpp, MCObject::senderror). The
-- runner collects them; a test that expects one takes them with
-- TestTakeErrorDialogs, and any left over fail the test (scRunOne), so an error
-- in a timer can never pass unseen.
on errorDialog pError
   put pError & return after sErrorDialogs
end errorDialog

function TestTakeErrorDialogs
   local tErrors
   put sErrorDialogs into tErrors
   put empty into sErrorDialogs
   return tErrors
end TestTakeErrorDialogs

-- Service engine events for exactly pMs milliseconds.
on TestPump pMs
   local tDeadline
   put the milliseconds + pMs into tDeadline
   repeat until the milliseconds > tDeadline
      wait 5 milliseconds with messages
   end repeat
end TestPump

function TestPortBase
   if $SC_PORT_BASE is an integer then
      return $SC_PORT_BASE
   end if
   return 47800
end TestPortBase

-- "true" when the runner found the engine can do UDP without a UI.
function TestSocketsUsable
   return $SC_SOCKETS is "1"
end TestSocketsUsable

-- Hex helpers (byte-exact assertions read as hex in a CI log).
function TestHex pData
   local tOut, i
   put empty into tOut
   repeat with i = 1 to the number of bytes in pData
      put format("%02x", byteToNum(byte i of pData)) after tOut
   end repeat
   return tOut
end TestHex

function TestUnhex pHex
   -- (no `repeat ... step 2`: the step clause is not honoured on every engine)
   local tOut, i
   put empty into tOut
   repeat with i = 1 to (the length of pHex) div 2
      put numToByte(baseConvert(char (2 * i - 1) to (2 * i) of pHex, 16, 10)) after tOut
   end repeat
   return tOut
end TestUnhex

-- ===== loading ===============================================================

on scLoadEverything
   local tRoot, tFolders, tFolder
   put $SC_EXT_ROOT into tRoot
   if tRoot is not empty then
      put folders(tRoot) into tFolders
      repeat for each line tFolder in tFolders
         if tFolder is "." or tFolder is ".." or char 1 of tFolder is "." then
            next repeat
         end if
         scLoadExtension tRoot & "/" & tFolder
      end repeat
   end if
   if $SC_HELPERS is not empty then
      TestLoadScriptAsLibrary $SC_HELPERS, "ShowControlHelpers"
   end if
   -- our own handlers (TestAssert ...) must be reachable from the test stack
   start using stack (the short name of me)
end scLoadEverything

-- The examples are PASTE-IN scripts (no `script "name"` header), not script-only
-- stack files, so they cannot be opened with `start using stack <file>`. Host one
-- in a fresh in-memory stack exactly as a user would paste it, fail loudly on a
-- compile error (setting a script reports it in the result), then put it in the
-- message path with `start using`.
on TestLoadScriptAsLibrary pPath, pName
   local tScript, tResult
   put url ("file:" & pPath) into tScript
   if tScript is empty then
      throw "cannot read " & pPath
   end if
   if there is a stack pName then
      delete stack pName
   end if
   create invisible stack pName
   set the script of stack pName to tScript
   -- A compile error is SILENT here: the result stays empty and the script
   -- simply has no handlers. revAvailableHandlers is the reliable signal.
   if the revAvailableHandlers of stack pName is empty then
      throw "script of " & pPath & " does not compile (" & scFirstBadHandler(tScript) & ")"
   end if
   start using stack pName
end TestLoadScriptAsLibrary

-- Map code/<platform-id>/<lib> into the revLibraryMapping, then load module.lcm.
on scLoadExtension pFolder
   local tCode, tAll, tSub, tCandidates, tFile, tLib, tResult
   put pFolder & "/code" into tCode
   if there is a folder tCode then
      put folders(tCode) into tAll
      put empty into tCandidates
      repeat for each line tSub in tAll
         if char 1 of tSub is "." then
            next repeat
         end if
         if scFolderMatchesHost(tSub) then
            put tSub & return after tCandidates
         end if
      end repeat
      repeat for each line tSub in tCandidates
         put files(tCode & "/" & tSub) into tAll
         repeat for each line tFile in tAll
            if char 1 of tFile is "." then
               next repeat
            end if
            put tFile into tLib
            if tLib contains "." then
               set the itemDelimiter to "."
               delete the last item of tLib
               set the itemDelimiter to ","
            end if
            -- Just SET it. Do not test first: reading an unmapped key THROWS
            -- (EE_BAD_LIBRARY_MAPPING) instead of returning empty, and the
            -- un-keyed `the revLibraryMapping` is not readable at all
            -- (EE_PROPERTY_NOPROP) -- both in exec-engine.cpp.
            set the revLibraryMapping[tLib] to tCode & "/" & tSub & "/" & tFile
            TestDiagnostic "mapped " & tLib & " -> code/" & tSub & "/" & tFile
         end repeat
      end repeat
   end if
   load extension from file (pFolder & "/module.lcm")
   put the result into tResult
   if tResult is not empty then
      throw "load extension " & pFolder & ": " & tResult
   end if
end scLoadExtension

-- The IDE's rule: the platform part (win32 / mac / linux) must match, and the
-- architecture part must be `the processor` (or universal on macOS).
function scFolderMatchesHost pSub
   local tPlat
   switch the platform
      case "Win32"
         put "-win32" into tPlat
         break
      case "MacOS"
         put "-mac" into tPlat
         break
      default
         put "-" & toLower(the platform) into tPlat
   end switch
   -- NOT `does not contain`: OXT cannot parse it, and the failure is silent --
   -- the whole script-only stack never opens (startup is never sent).
   if not (pSub contains tPlat) then
      return false
   end if
   if pSub begins with (the processor & "-") then
      return true
   end if
   if the platform is "MacOS" and pSub begins with "universal-" then
      return true
   end if
   return false
end scFolderMatchesHost

-- ===== listing / running =====================================================

on scListTests pFile
   local tScript, tLine, tName
   put url ("file:" & pFile) into tScript
   repeat for each line tLine in tScript
      if word 1 of tLine is "on" and word 2 of tLine begins with "Test" then
         put word 2 of tLine into tName
         if tName is not "TestSetup" and tName is not "TestTearDown" then
            scWrite tName
         end if
      end if
   end repeat
end scListTests

on scRunOne pFile, pHandler
   local tStack, tErr
   put the short name of stack pFile into tStack
   TestAssert "test stack compiles and opens", tStack is not empty
   dispatch "TestSetup" to stack tStack       -- "unhandled" when there is none
   try
      dispatch pHandler to stack tStack
      if it is "unhandled" then
         TestAssert "handler " & pHandler & " exists", false
      end if
   catch tErr
      TestAssert "execute " & pHandler & ": " & scErrorLine(tErr), false
      TestDiagnostic tErr
   end try
   try
      dispatch "TestTearDown" to stack tStack
   end try
   -- errorDialog is itself delivered later: give one still queued its turn
   wait 10 milliseconds with messages
   if sErrorDialogs is not empty then
      TestAssert "no error went uncaught in a delayed message: " & scErrorLine(line 1 of sErrorDialogs), false
      TestDiagnostic sErrorDialogs
      put empty into sErrorDialogs
   end if
end scRunOne

-- ===== in-engine compile gate =================================================
-- The engine's own compiler is the only authority on what parses. For each file
-- (one path per line in pFiles), compile its script on a scratch stack and check
-- it produced handlers -- a compile error is otherwise SILENT (set the script
-- leaves the result empty; a broken script-only stack just never opens). On
-- failure, compile handler by handler to name the one that breaks.
on scCompileCheck pFiles
   local tFile, tScript, tHandlers, tName
   repeat for each line tFile in pFiles
      if tFile is empty then
         next repeat
      end if
      put url ("file:" & tFile) into tScript
      if word 1 of line 1 of tScript is "script" then
         delete line 1 of tScript
      end if
      put tFile into tName
      replace numToChar(92) with "/" in tName          -- Windows separators
      set the itemDelimiter to "/"
      put the last item of tName into tName
      set the itemDelimiter to ","
      put scCompiledHandlers(tScript) into tHandlers
      if tHandlers is not empty then
         TestAssert "engine compiles " & tName & " (" & the number of lines of tHandlers & " handlers)", true
      else
         TestAssert "engine compiles " & tName, false
         TestDiagnostic "  first handler that fails to compile on its own: " & scFirstBadHandler(tScript)
      end if
   end repeat
end scCompileCheck

-- A UNIQUE scratch stack per call: deleting and re-creating one name in quick
-- succession can leave the old stack addressed, which misreports a good script.
local sProbeSeq

function scCompiledHandlers pScript
   local tName, tResult
   add 1 to sProbeSeq
   put "SCCompileProbe" & sProbeSeq into tName
   create invisible stack tName
   set the script of stack tName to pScript
   put the revAvailableHandlers of stack tName into tResult
   return tResult
end scCompiledHandlers

-- Split a script into its top-level handlers (plus the script-level lines, so
-- constants and locals still resolve) and compile each alone; return the first
-- one that produces nothing, as "name (line N)".
function scFirstBadHandler pScript
   local tPreamble, tChunk, tInHandler, tLine, tLineNo, tStart, tName
   put empty into tPreamble
   put false into tInHandler
   put 0 into tLineNo
   repeat for each line tLine in pScript
      add 1 to tLineNo
      if not tInHandler then
         if word 1 of tLine is among the items of "on,command,function,getprop,setprop,before,after,private" then
            put true into tInHandler
            put tLine & return into tChunk
            put tLineNo into tStart
            if word 1 of tLine is "private" then
               put word 3 of tLine into tName
            else
               put word 2 of tLine into tName
            end if
         else if word 1 of tLine is "local" or word 1 of tLine is "constant" or word 1 of tLine is "global" then
            put tLine & return after tPreamble
         end if
      else
         put tLine & return after tChunk
         if word 1 of tLine is "end" and word 2 of tLine is tName then
            put false into tInHandler
            if scCompiledHandlers(tPreamble & tChunk) is empty then
               return tName & " (line " & tStart & ")"
            end if
         end if
      end if
   end repeat
   return "no single handler fails alone -- check script-level lines"
end scFirstBadHandler

-- ===== socket capability probe ================================================
-- Older engines could not deliver socket events without a UI on Windows (fixed
-- in OXT-Beyond 0.2.1-rc.2) or delayed them on macOS. Socket tests are only
-- meaningful where this round-trip works; the Python runner skips (or, under
-- --require-all, fails) them otherwise.
local sProbeGot

on scProbeSockets
   local tPort, tDeadline
   put TestPortBase() into tPort
   put empty into sProbeGot
   accept datagram connections on port tPort with message "scProbeArrived"
   TestDiagnostic "accept: [" & the result & "]"
   -- the engine only writes to an OPEN socket (exec-network.cpp)
   open datagram socket to ("127.0.0.1:" & tPort)
   TestDiagnostic "open: [" & the result & "]"
   write "showcontrol-probe" to socket ("127.0.0.1:" & tPort)
   TestDiagnostic "write: [" & the result & "]"
   put the milliseconds + 3000 into tDeadline
   repeat until sProbeGot is not empty or the milliseconds > tDeadline
      wait 10 milliseconds with messages
   end repeat
   TestAssert "engine delivers UDP to itself without a UI", sProbeGot is not empty
   try
      close socket tPort
      close socket ("127.0.0.1:" & tPort)
   end try
end scProbeSockets

on scProbeArrived pA, pB
   put pA & pB into sProbeGot
end scProbeArrived

-- ===== output =================================================================

on scWrite pLine
   write textEncode(pLine & return, "UTF8") to stdout
end scWrite

-- TAP descriptions: one line, no '#' (a directive), trimmed.
function scClean pText
   replace return with " " in pText
   replace "#" with "no." in pText
   return pText
end scClean

-- An engine error is "code,line,column,detail" lines; report the first line
-- whose detail is prose (the message), plus where it happened.
-- An engine error is "code,line,column,detail" lines; report the first detail
-- that reads as a message (not an object reference or a bare token).
function scErrorLine pErr
   local tLine, tDetail
   repeat for each line tLine in pErr
      put item 4 to -1 of tLine into tDetail
      if tDetail contains " " and word 1 of tDetail is not among the items of "stack,card,button,field,group" then
         return tDetail & " (line " & item 2 of line 1 of pErr & ")"
      end if
   end repeat
   return line 1 of pErr
end scErrorLine

function scShow pV
   if pV is an array then
      return "<array of " & the number of elements of pV & ">"
   end if
   if pV is a number then
      return pV
   end if
   return quote & pV & quote & " (" & the number of bytes in pV & " bytes)"
end scShow
