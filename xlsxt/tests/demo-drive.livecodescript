script "xlsxtDemoDrive"
-- demo-drive.livecodescript - examples/xlsxt-demo.livecodescript driven on a
-- real engine with no person at it.
--
--    XLSXT_LCM=<xlsxt.lcm> XLSXT_LIB=<library, no extension> \
--    XLSXT_DEMO=examples/xlsxt-demo.livecodescript \
--       <OXT-Beyond>/LiveCode-Community -ui tests/demo-drive.livecodescript
--
-- It puts the demo's script on a new stack (as the demo's header tells a
-- person to), builds the window, and then does what a person would: opens
-- each tab by clicking its button, makes each tab's workbook and the one
-- with everything, clicks a tick box, shows the workbook in the Read tab,
-- clicks a cell, and runs every check from the About tab. The native lane
-- runs it (the suite's .github/workflows/native-xlsxt.yml, job `engine`)
-- and wants BOTH an exit of 0 and a last line "DRIVE <passed> 0": an
-- engine that printed nothing must not read as a pass.
--
-- XLSXT_SHOT (optional) names a PNG to write of the tab XLSXT_TAB, which
-- needs a display (xvfb-run), for a picture of the window.
--
-- WHAT THIS IS EVIDENCE OF: the demo's logic and its window on OXT-Beyond's
-- Linux engine without a display. It is not a person using the window, and
-- not a file opened in Excel.

constant kStack = "xlsxtDemoRun"

local sPassed, sFailed, sOut

command drCheck pOk, pLabel, pDetail
   if pOk is true then
      add 1 to sPassed
      put "PASS  " & pLabel & return after sOut
   else
      add 1 to sFailed
      put "FAIL  " & pLabel & "  [" & pDetail & "]" & return after sOut
   end if
end drCheck

-- A click on a control of the demo, as the engine delivers one: the
-- message goes to the control and up to the stack script's mouseUp.
command drClick pControl
   dispatch "mouseUp" to pControl with 1
end drClick

on startup
   local tError, tKey, tResult, tReport, tWas
   put 0 into sPassed
   put 0 into sFailed
   try
      set the revLibraryMapping["xlsxt"] to $XLSXT_LIB
      load extension from file $XLSXT_LCM
      drCheck the result is empty, "the extension loads", the result
      create stack kStack
      set the script of stack kStack to textDecode(URL ("binfile:" & $XLSXT_DEMO), "UTF-8")
      go stack kStack
      set the defaultStack to kStack
      send "preOpenStack" to stack kStack
      drCheck the width of stack kStack is 960 and the height of stack kStack is 620, "the window is 960 x 620", the rect of stack kStack
      drCheck field "uiStatus" begins with "Ready (xlsxt ABI", "the status line names the library", field "uiStatus"
      drCheck the visible of field "tbl:data" and not the visible of field "about:log", "it opens on the Table tab", the visible of field "tbl:data"

      -- a second preOpenStack rebuilds nothing (the version guard)
      put the number of controls of card 1 of stack kStack into tWas
      send "preOpenStack" to stack kStack
      drCheck the number of controls of card 1 of stack kStack is tWas, "reopening adds no control", the number of controls of card 1 of stack kStack

      repeat for each item tKey in "tbl,sty,fx,ch,pg"
         drClick the long id of button ("ui:" & tKey)
         drCheck the visible of field (tKey & ":h") and the visible of button "act:make", "the tab " & tKey & " shows with the action row", tKey
         drClick the long id of button "act:make"
         put field "act:result" into tResult
         drCheck tResult begins with "Made and read back:", "Make this workbook on " & tKey, tResult
         put "      " & tResult & return after sOut
      end repeat

      -- a tick box flips on a click, and the builder obeys it
      drClick the long id of button "ui:pg"
      drCheck the hilite of button "pg:hidden", "the hidden-sheet box starts ticked", the hilite of button "pg:hidden"
      drClick the long id of button "pg:hidden"
      drCheck not the hilite of button "pg:hidden", "a click unticks it", the hilite of button "pg:hidden"
      drClick the long id of button "act:make"
      drCheck field "act:result" begins with "Made and read back: 1 sheet", "and the workbook then has one sheet", field "act:result"
      drClick the long id of button "pg:hidden"

      -- one chart of every kind
      drClick the long id of button "ui:ch"
      drClick the long id of button "ch:every"
      drClick the long id of button "act:make"
      drCheck "Every chart" is in field "act:result", "a sheet with one chart of every kind", field "act:result"
      drClick the long id of button "ch:every"

      drClick the long id of button "act:all"
      put field "act:result" into tResult
      drCheck tResult begins with "Made and read back: 6 sheet(s)", "Make one with everything", tResult

      drClick the long id of button "ui:rd"
      drCheck not the visible of button "act:make", "the Read tab has no action row", the visible of button "act:make"
      drCheck line 1 of field "rd:sheets" is "Table" and "Hidden notes (hidden)" is among the lines of field "rd:sheets", "the Read tab lists the sheets", field "rd:sheets"
      set the itemDelimiter to tab
      drCheck item 2 of line 2 of field "rd:grid" is "January", "and shows the cells", line 2 of field "rd:grid"
      set the itemDelimiter to comma
      set the hilitedLine of field "rd:sheets" to 2
      drClick the long id of field "rd:sheets"
      drCheck field "rd:file" contains "sheet 2 of 6" and field "rd:file" contains "Merged: A1:E1", "a click on a sheet shows it", field "rd:file"
      set the hilitedLine of field "rd:grid" to 4
      drClick the long id of field "rd:grid"
      drCheck line 1 of field "rd:cell" begins with "Cell A4" and field "rd:cell" contains "kind:     text", "a click on a row describes its cell", line 1 of field "rd:cell"

      drClick the long id of button "ui:about"
      drClick the long id of button "about:run"
      put field "about:log" into tReport
      put tReport & return after sOut
      drCheck the last line of tReport begins with "SUMMARY" and the last word of tReport is 0 and word 2 of the last line of tReport > 30, \
            "Run every check: all pass", the last line of tReport
      drCheck field "about:sum" contains "none failed", "and the window says so", field "about:sum"

      if $XLSXT_SHOT is not empty then
         drClick the long id of button ("ui:" & $XLSXT_TAB)
         export snapshot from rect (the rect of card 1 of stack kStack) of card 1 of stack kStack to file $XLSXT_SHOT as PNG
      end if
   catch tError
      drCheck false, "the drive ran to its end", tError
   end try
   write sOut & "DRIVE" && sPassed && sFailed & return to stdout
   if sFailed is 0 and sPassed > 0 then
      quit 0
   end if
   quit 1
end startup
