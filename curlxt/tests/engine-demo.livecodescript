script "curlxtDemoRun"

-- engine-demo.livecodescript - curlxt Live (examples/curlxt-live.livecodescript)
-- run start to finish on OXT-Beyond's DESKTOP engine, with no screen.
--
-- WHY THE DESKTOP ENGINE. The demo serves its own scenes: it listens on
-- 127.0.0.1 with `accept connections`. OXT-Beyond's server engine opens such
-- a listener and never delivers a connection to it (measured 2026-11-21 on
-- 0.2.7-rc.6; the suite's engine note 6.15), so tests/engine-selftest.lc's
-- engine cannot host the demo. The desktop standalone engine of the same
-- -binaries archive, started with -ui, runs a script-only stack with no
-- display and delivers every socket message (engine note 6.16).
--
-- HOW. tools/run-engine-demo.py starts
--    standalone-community -ui tests/engine-demo.livecodescript
-- with three environment variables: CURLXT_DEMO_MODULE (curl.lcm, compiled
-- by the same release's lc-compile), CURLXT_DEMO_LIBRARY (the curlxt library
-- without its extension) and CURLXT_DEMO_STACK (the demo's file). This stack
-- loads the extension, opens the demo the way start-here's launcher does (a
-- closed stack, its script set, then a genuine open, so the demo gets its
-- own openStack), and reads the demo's own log as each scene says how it
-- went. It presses each scene's button itself, and keeps ITSELF the default
-- stack while it waits, so every timer and socket message of the demo
-- arrives while another stack is the default (engine note 5.3): a missing
-- pin stops a scene with "no such object", and the scene's line says so.
--
-- WHAT IT CANNOT SEE is anything drawn: the window is never shown. It sees
-- the scripts, the engine's sockets, the demo's server and libcurl working
-- together, each scene's own verdict, and a clean close and reopen.
--
-- It prints PASS and FAIL lines, INFO lines, the demo's log, and last a line
-- "SUMMARY passed failed"; it quits with the number of failures.

constant kDrvDemo = "curlxtLive"
constant kDrvLimitMs = 240000

local sPassed, sFailed, sFinished

on openStack
   send "drvRun" to me in 20 milliseconds
end openStack

on drvRun
   local tErr
   put 0 into sPassed
   put 0 into sFailed
   put "false" into sFinished
   drvSay "INFO engine " & the version && the platform && the processor
   -- a run that hangs still ends, and says where
   send "drvWatchdog" to me in kDrvLimitMs milliseconds
   try
      drvMain
   catch tErr
      drvCheck "the run finished", false, tErr
   end try
   drvFinish
end drvRun

on drvWatchdog
   drvCheck "the run finished within " & (kDrvLimitMs div 1000) & " s", false, drvTail(6)
   drvFinish
end drvWatchdog

command drvMain
   local tText, tWas, tLine, tCount, tFirst, tLater
   set the revLibraryMapping["curlxt"] to $CURLXT_DEMO_LIBRARY
   load extension from file $CURLXT_DEMO_MODULE
   put the result into tWas
   drvCheck "the extension loads", (tWas is empty \
         and "org.openxtalk.library.curl" is among the lines of the loadedExtensions), tWas
   if sFailed > 0 then
      exit drvMain
   end if
   drvSay "INFO " & cuLibraryVersion()

   -- the demo, opened as start-here opens it (slPrepareStack, then go)
   put url ("file:" & $CURLXT_DEMO_STACK) into tText
   drvCheck "the demo's file reads", (line 1 of tText is ("script" && quote & kDrvDemo & quote)), \
         line 1 of tText
   if sFailed > 0 then
      exit drvMain
   end if
   delete line 1 of tText
   create invisible stack kDrvDemo
   close stack kDrvDemo
   set the script of stack kDrvDemo to tText
   put the result into tWas
   drvCheck "the demo's script compiles", (tWas is empty), tWas
   if sFailed > 0 then
      exit drvMain
   end if
   go invisible stack kDrvDemo
   drvCheck "the demo's boot self-check is green", drvWaitFor("boot self-check GREEN", 1, 8000), drvTail(8)
   drvSay "INFO " & drvLineWith("defaultStack on entry")

   -- scene 1 starts by itself, says how its fast run went, and keeps going
   drvCheck "scene 1 starts by itself", drvWaitFor("scene 1: Round trips", 1, 3000), drvTail(4)
   drvCheck "scene 1 says how its fast run went", drvWaitFor("scene 1 done:", 1, 25000), drvTail(4)
   put drvLineWith("scene 1 done:") into tLine
   drvSay "INFO " & tLine
   put word 1 of drvAfter(tLine, "done: ") into tCount
   drvCheck "scene 1 made at least 30 round trips", (tCount is an integer and tCount >= 30), tLine
   put field "cdBig4" of stack kDrvDemo into tFirst
   drvPause 2600
   put field "cdBig4" of stack kDrvDemo into tLater
   drvCheck "scene 1 keeps going after its fast run (sent / back " & tFirst & ", then " & tLater & ")", \
         (word 1 of tFirst is an integer and word 1 of tLater > word 1 of tFirst), tLater

   -- each other scene, from its button
   drvScene 2, "all 8 back identical", 25000
   drvScene 3, "every one back in order", 40000
   put drvLineWith("scene 3 done:") into tLine
   put word 1 of drvAfter(tLine, "done: ") into tCount
   drvCheck "scene 3 echoed at least 500 messages at full speed", (tCount is an integer and tCount >= 500), tLine
   drvScene 4, "15 of 15 local requests answered", 30000
   drvScene 5, "closed cleanly (1000), heard the server go", 30000
   drvCheck "the server going away reached the client as close code 1001", \
         (drvCount("code 1001") > 0), drvLineWith("closed, code")
   drvCheck "no scene stopped on an error", (drvCount("stopped:") is 0), drvLineWith("stopped:")
   drvCheck "nothing curlxt's timer delivered failed", (drvCount("curlxt's timer:") is 0), \
         drvLineWith("curlxt's timer:")

   -- closing gives everything back; the demo then opens again from scratch
   close stack kDrvDemo
   drvPause 300
   drvCheck "closing the demo leaves no request or socket in curlxt", (cuLiveCount() is 0), cuLiveCount()
   drvCheck "closing the demo leaves no engine socket open", (the openSockets is empty), the openSockets
   go invisible stack kDrvDemo
   drvCheck "the demo opens again with a green boot self-check", \
         drvWaitFor("boot self-check GREEN", 2, 8000), drvTail(8)
   drvCheck "and scene 1 starts again by itself", drvWaitFor("scene 1: Round trips", 2, 3000), drvTail(4)
   drvPause 1500
   put field "cdBig4" of stack kDrvDemo into tLater
   drvCheck "round trips land again after the reopen (sent / back " & tLater & ")", \
         (word 3 of tLater is an integer and word 3 of tLater > 0), tLater
   close stack kDrvDemo
   drvPause 300
   drvCheck "the second close leaves nothing behind either", \
         (cuLiveCount() is 0 and the openSockets is empty), cuLiveCount() & " / " & the openSockets
end drvMain

-- Press scene pN's button and wait for the scene's own verdict.
command drvScene pN, pWant, pMs
   local tBefore, tLine
   put drvCount("scene " & pN & " done:") into tBefore
   set the defaultStack to the short name of this stack
   send "mouseUp" to button ("cdScene" & pN) of stack kDrvDemo
   drvCheck "scene " & pN & " ends by itself", \
         drvWaitFor("scene " & pN & " done:", tBefore + 1, pMs), drvTail(4)
   put drvLineWith("scene " & pN & " done:") into tLine
   drvSay "INFO " & tLine
   drvCheck "scene " & pN & ": " & pWant, (tLine contains pWant), tLine
end drvScene

-- True once the demo's log holds pText pCount times; false after pMs. The
-- demo's timers and sockets run during the wait, with THIS stack the
-- default.
function drvWaitFor pText, pCount, pMs
   local tEnd
   put the milliseconds + pMs into tEnd
   repeat
      if drvCount(pText) >= pCount then
         return true
      end if
      if the milliseconds > tEnd then
         return false
      end if
      set the defaultStack to the short name of this stack
      wait 40 milliseconds with messages
   end repeat
end drvWaitFor

command drvPause pMs
   local tEnd
   put the milliseconds + pMs into tEnd
   repeat while the milliseconds < tEnd
      set the defaultStack to the short name of this stack
      wait 40 milliseconds with messages
   end repeat
end drvPause

function drvLog
   if there is no stack kDrvDemo then
      return empty
   end if
   if there is no field "cdLog" of card 1 of stack kDrvDemo then
      return empty
   end if
   return field "cdLog" of card 1 of stack kDrvDemo
end drvLog

-- How many times pText is in the demo's log.
function drvCount pText
   local tLog, tAt, tN
   put drvLog() into tLog
   put 0 into tN
   repeat
      put offset(pText, tLog) into tAt
      if tAt is 0 then
         exit repeat
      end if
      add 1 to tN
      delete char 1 to (tAt + the number of chars of pText - 1) of tLog
   end repeat
   return tN
end drvCount

-- The last line of the demo's log that holds pText.
function drvLineWith pText
   local tLine, tHit
   repeat for each line tLine in drvLog()
      if tLine contains pText then
         put tLine into tHit
      end if
   end repeat
   return tHit
end drvLineWith

function drvAfter pLine, pMark
   local tAt
   put offset(pMark, pLine) into tAt
   if tAt is 0 then
      return empty
   end if
   return char (tAt + the number of chars of pMark) to -1 of pLine
end drvAfter

function drvTail pN
   local tLog
   put drvLog() into tLog
   return line max(1, the number of lines of tLog - pN + 1) to -1 of tLog
end drvTail

command drvCheck pName, pOk, pDetail
   if pOk is true then
      add 1 to sPassed
      drvSay "PASS " & pName
   else
      add 1 to sFailed
      drvSay "FAIL " & pName & ": " & drvOneLine(pDetail)
   end if
end drvCheck

function drvOneLine pText
   replace return with " | " in pText
   return pText
end drvOneLine

command drvSay pText
   write pText & return to stdout
end drvSay

-- Once: the demo's whole log (the record of what it did), then the summary.
command drvFinish
   local tLine
   if sFinished is "true" then
      exit drvFinish
   end if
   put "true" into sFinished
   repeat for each line tLine in drvLog()
      drvSay "LOG " & tLine
   end repeat
   drvSay "SUMMARY " & sPassed && sFailed
   quit sFailed
end drvFinish
