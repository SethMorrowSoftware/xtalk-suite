script "xlsxtDemoDrive"
-- demo-drive.livecodescript - examples/xlsxt-demo.livecodescript driven on a
-- real engine with no person at it.
--
--    XLSXT_LCM=<xlsxt.lcm> XLSXT_LIB=<library, no extension> \
--    XLSXT_DEMO=examples/xlsxt-demo.livecodescript \
--       <OXT-Beyond>/LiveCode-Community -ui tests/demo-drive.livecodescript
--
-- It puts the demo's script on a new stack (as the demo's header tells a
-- person to), builds the window, and then does what a person would: plays
-- each of the Showcase's four scenes by clicking its button (each writes a
-- file and reads it back) and leaves one half way, opens each tab by
-- clicking its button, makes each tab's workbook and the one with
-- everything, clicks a tick box, shows the workbook in the Read tab, clicks
-- a cell, and runs every check from the About tab. The native lane
-- runs it (the suite's .github/workflows/native-xlsxt.yml, job `engine`)
-- and wants BOTH an exit of 0 and a last line "DRIVE <passed> 0": an
-- engine that printed nothing must not read as a pass.
--
-- XLSXT_SHOT (optional) names a PNG to write of the tab XLSXT_TAB, which
-- needs a display (xvfb-run), for a picture of the window. For the tab
-- "show" it first plays scene XLSXT_SCENE (1 to 4, default 1) at its real
-- speed for XLSXT_WAIT milliseconds (default 4000).
--
-- WHAT THIS IS EVIDENCE OF: the demo's logic and its window on OXT-Beyond's
-- Linux engine without a display. It is not a person using the window, and
-- not a file opened in Excel.

constant kStack = "xlsxtDemoRun"
constant kScenes = "sheet,formulas,charts,many"

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

-- Lets the engine run the demo's timer for up to pMs milliseconds, until
-- the stack's uXdShowDone begins with pScene (the scene has said what it
-- found). Answers what it says, or empty if it never did.
function drUntilDone pScene, pMs
   local tStart
   put the milliseconds into tStart
   repeat until the milliseconds - tStart > pMs
      if word 1 of the uXdShowDone of stack kStack is pScene then
         return the uXdShowDone of stack kStack
      end if
      wait 5 milliseconds with messages
   end repeat
   return empty
end drUntilDone

-- The first cell of field pField whose words run past the right edge of
-- its column, as "line L, column K: <words> end at X, the column at Y",
-- or empty when every cell fits. The engine clips a cell of a field with
-- a vertical grid at its column's edge, so a number one digit too wide
-- for its column shows one digit short (the Showcase's last column did,
-- 2026-11-21: 69772 read 6977). A column ends at its tab stop; past the
-- last stop the last gap repeats, as the engine lays the field out.
-- Measured from the field's own words (formattedLeft and formattedWidth
-- of each cell), so the font this engine draws with is the one judged.
function drClippedCell pField
   local tStops, tStop, tCount, tLine, tItem, tRight, tEnd, tOrigin
   -- A chunk of a variable is a chunk of its text, never of the field it
   -- names, so every chunk below names the field itself.
   put the tabStops of field pField into tStops
   put the number of items of tStops into tCount
   repeat with tItem = 1 to tCount
      put item tItem of tStops into tStop[tItem]
   end repeat
   put (the left of field pField) + (the leftMargin of field pField) into tOrigin
   set the itemDelimiter to tab
   repeat with tLine = 1 to the number of lines of field pField
      repeat with tItem = 1 to the number of items of line tLine of field pField
         if item tItem of line tLine of field pField is empty then
            next repeat
         end if
         if tItem <= tCount then
            put tStop[tItem] into tRight
         else if tCount > 1 then
            put tStop[tCount] + ((tItem - tCount) * (tStop[tCount] - tStop[tCount - 1])) into tRight
         else
            put tItem * tStop[1] into tRight
         end if
         put (the formattedLeft of item tItem of line tLine of field pField) \
               + (the formattedWidth of item tItem of line tLine of field pField) - tOrigin into tEnd
         if tEnd > tRight then
            return "line" && tLine & ", column" && tItem & ":" && (item tItem of line tLine of field pField) \
                  && "ends at" && tEnd & ", the column at" && tRight
         end if
      end repeat
   end repeat
   return empty
end drClippedCell

on startup
   local tError, tKey, tResult, tReport, tWas, tI, tBlank, tScene, tDone, tWait, tClipped
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
      drCheck the width of stack kStack is 960 and the height of stack kStack is 640, "the window is 960 x 640", the rect of stack kStack
      drCheck field "uiStatus" begins with "Ready (xlsxt ABI", "the status line names the library", field "uiStatus"
      drCheck the visible of field "show:grid" and not the visible of field "tbl:data" and not the visible of button "act:make", \
            "it opens on the Showcase", the visible of field "show:grid"
      drCheck field "show:h" contains "A sheet fills itself" and "xdShowFrame" is in the pendingMessages, \
            "and its tour is already playing", field "show:h"
      drCheck field "hd:by" is "by Seth Morrow" and field "hd:brand" is "OXT-BEYOND" and field "uiTitle" is "Spreadsheet Studio", \
            "the header names OXT-Beyond, the demo and who made it", field "uiTitle"

      -- Every field and tick box names its own text colour. One left to
      -- the system theme takes a dark theme's white, on the white the kit
      -- paints: on Windows (2026-11-21) the Table tab's grid and every
      -- tick box's words could not be seen. A property, so this engine
      -- needs no theme and no display to hold it.
      repeat with tI = 1 to the number of fields of card 1 of stack kStack
         if the foregroundColor of field tI of card 1 of stack kStack is empty then
            put the short name of field tI of card 1 of stack kStack & space after tBlank
         end if
      end repeat
      repeat with tI = 1 to the number of buttons of card 1 of stack kStack
         if the style of button tI of card 1 of stack kStack is "checkbox" \
               and the foregroundColor of button tI of card 1 of stack kStack is empty then
            put the short name of button tI of card 1 of stack kStack & space after tBlank
         end if
      end repeat
      drCheck tBlank is empty, "every field and tick box names its text colour", tBlank

      -- a second preOpenStack rebuilds nothing (the version guard)
      put the number of controls of card 1 of stack kStack into tWas
      send "preOpenStack" to stack kStack
      drCheck the number of controls of card 1 of stack kStack is tWas, "reopening adds no control", the number of controls of card 1 of stack kStack

      -- The Showcase: each scene, from its button, as fast as the engine
      -- goes (uXdFast), to its end. Each writes a file and reads it back,
      -- and leaves no workbook or reader open.
      set the uXdFast of stack kStack to true
      repeat with tI = 1 to 4
         put item tI of kScenes into tScene
         set the uXdShowDone of stack kStack to empty
         drClick the long id of button ("show:s" & tI)
         put drUntilDone(tScene, 60000) into tDone
         drCheck word 2 of tDone is "ok", "scene " & tI & " (" & tScene & ") plays to its end and reads back what it wrote", \
               tDone && field "show:count"
         put drClippedCell("show:grid") into tClipped
         drCheck tClipped is empty, "and every cell it shows fits its column", tClipped
         put "      " & field "show:count" & return after sOut
         wait 20 milliseconds with messages
         drCheck xlWorkbookCount() is 0 and xlReadCount() is 0, "and leaves nothing open", xlWorkbookCount() && xlReadCount()
      end repeat
      drCheck field "show:count" contains "10,000 cells written in", "the last scene says how long the library took", field "show:count"
      -- Play all four: the tour, from the first scene to the last
      set the uXdShowDone of stack kStack to empty
      drClick the long id of button "show:all"
      put drUntilDone("many", 120000) into tDone
      drCheck word 2 of tDone is "ok", "Play all four plays the four in turn", tDone
      wait 50 milliseconds with messages
      drCheck field "show:h" is "That was the tour", "and the heading says the tour is over", field "show:h"
      -- a scene left half way: leaving the tab stops it and closes its file
      drClick the long id of button "show:s4"
      repeat 400 times
         if field "show:count" begins with "Reading:" then
            exit repeat
         end if
         wait 2 milliseconds with messages
      end repeat
      drCheck xlReadCount() is 1, "the ten thousand cells are being read", field "show:count"
      drClick the long id of button "ui:tbl"
      drCheck xlWorkbookCount() is 0 and xlReadCount() is 0 and "xdShowFrame" is not in the pendingMessages, \
            "leaving the tab mid-scene stops it and closes its reader", xlWorkbookCount() && xlReadCount()
      set the uXdFast of stack kStack to false

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
         if $XLSXT_TAB is "show" then
            put $XLSXT_WAIT into tWait
            if tWait is not an integer then
               put 4000 into tWait
            end if
            put $XLSXT_SCENE into tI
            if tI is not an integer then
               put 1 into tI
            end if
            drClick the long id of button ("show:s" & tI)
            wait tWait milliseconds with messages
         end if
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
