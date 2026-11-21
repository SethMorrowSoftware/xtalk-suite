script "xlsxtBuildDemoStack"
-- build-demo-stack.livecodescript - saves xlsxt-demo.livecodescript as a
-- stack file, for places that take a stack and not a script: the Stack
-- Player and the community stacks gallery, where it plays in a browser.
--
--    XLSXT_DEMO=examples/xlsxt-demo.livecodescript XLSXT_OUT="<dir>/xlsxt Demo.oxtstack" \
--       <OXT-Beyond>/LiveCode-Community -ui examples/build-demo-stack.livecodescript
--
-- The stack it saves holds the demo's script and NO controls: the demo
-- builds its window when the stack opens, on the engine that opens it, so
-- the status line tells the truth about that engine's library. Only the
-- size is set here (the demo's own 960 x 640), so a player can lay the
-- page out before the stack has run.
on startup
   local tError, tName
   put "xlsxtDemo" into tName
   try
      if $XLSXT_DEMO is empty or $XLSXT_OUT is empty then
         throw "set XLSXT_DEMO and XLSXT_OUT"
      end if
      set the lockMessages to true
      create invisible stack tName
      set the width of stack tName to 960
      set the height of stack tName to 640
      set the title of stack tName to "Spreadsheet Studio - xlsxt"
      set the script of stack tName to textDecode(URL ("binfile:" & $XLSXT_DEMO), "UTF-8")
      set the visible of stack tName to true
      save stack tName as $XLSXT_OUT
      if the result is not empty then
         throw the result
      end if
   catch tError
      write "FATAL " & line 1 of tError & return to stdout
      quit 2
   end try
   write "MADE " & $XLSXT_OUT & return to stdout
   quit 0
end startup
