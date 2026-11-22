script "audioxtBuildDemoStack"
-- build-demo-stack.livecodescript - saves audioxt-demo.livecodescript (Sound
-- Stage) as a stack file, for places that take a stack and not a script:
-- opening it from the File menu, the Stack Player, and the community
-- stacks gallery, where it plays in a browser.
--
--    AUDIOXT_DEMO=examples/audioxt-demo.livecodescript AUDIOXT_OUT=<dir>/audioxt-demo.oxtstack \
--       <OXT-Beyond>/LiveCode-Community -ui examples/build-demo-stack.livecodescript
--
-- The stack it saves holds the demo's script and NO controls: the demo
-- builds its window when the stack opens, on the engine that opens it, so
-- the status line tells the truth about that engine's library and devices,
-- and every font is measured on the machine that shows it. Only the size,
-- the place and the colour are set here (the demo's own 960 x 600, centred
-- on a 1280 x 720 screen, its dark page), so a player can lay the page out
-- before the stack has run and nothing white flashes first.
on startup
   local tError, tName, tRect
   put "audioxtDemo" into tName
   try
      if $AUDIOXT_DEMO is empty or $AUDIOXT_OUT is empty then
         throw "set AUDIOXT_DEMO and AUDIOXT_OUT"
      end if
      set the lockMessages to true
      create invisible stack tName
      set the width of stack tName to 960
      set the height of stack tName to 600
      -- Where it opens, its title bar on the screen too. A size set alone
      -- grows round the engine's first centre (160,160): this file was
      -- once saved at -320,-140, above and left of every screen, and
      -- opened there on Windows (2026-11-21). The demo also moves a
      -- window that is off its screens when it opens (adPlaceWindow); this
      -- place is for whatever opens the file with its messages locked.
      set the topLeft of stack tName to 160,60
      set the backgroundColor of stack tName to "#12151F"
      set the title of stack tName to "Sound Stage - audioxt"
      set the script of stack tName to textDecode(URL ("binfile:" & $AUDIOXT_DEMO), "UTF-8")
      set the visible of stack tName to true
      put the rect of stack tName into tRect
      save stack tName as $AUDIOXT_OUT
      if the result is not empty then
         throw the result
      end if
   catch tError
      write "FATAL " & line 1 of tError & return to stdout
      quit 2
   end try
   write "MADE " & $AUDIOXT_OUT & " at " & tRect & return to stdout
   quit 0
end startup
