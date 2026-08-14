-- spike.livecodescript - share a folder of files over Tor, from OpenXTalk.
--
-- Pick a folder, and every file in it is served at a private <56>.onion address
-- with an auto-generated directory-listing page (names and download links,
-- browse into subfolders). Built entirely on OnionXT's accept loop via the
-- onion-httpd.livecodescript module (oxh*) - no engine-shipped HTTPD Library, so
-- it runs wherever OnionXT runs.
--
-- HOW TO RUN: make a new mainstack, set its stack script to this file, and put
-- BOTH src/onionxt.livecodescript AND src/onion-httpd.livecodescript in the
-- message path (start using them as libraries). Have a tor daemon with the
-- control port enabled (OnionXT README Troubleshooting). Click Start, then Share
-- Folder and pick a folder; wait for REACHABLE, then open the printed
-- http://<address>.onion/ in Tor Browser to browse and download the files.
--
-- HONESTY (the suite convention): the serve-a-folder path is confirmed
-- on-engine per this folder's README, but the UI was unified onto the suite
-- kit 2026-08-14, so the stack as a whole is verified statically and needs
-- an OXT re-pass.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here.

constant kVirtualPort = 80       -- the onion's public port (URL needs no :port)
constant kLocalPort = 8090       -- loopback forward port (8080 is often reserved)
constant kControlPort = 9051     -- system tor control port (Tor Browser: 9151)
constant kSocksPort = 9050
-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kOhUiVersion = "httpd-spike-kit2-1"

local sSvcHandle
local sOnionAddress
local sSvcReady          -- true once HS_DESC UPLOADED arrived (gates the watchdog)

-- ==== SUITE UI KIT v2 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====
-- The family look as one carried block: the kit owns colors, chrome, and
-- control construction; the adopting demo owns layout (explicit rects) and
-- logic. Builders are idempotent (create-if-missing), so a rebuild on
-- reopen is safe. Do not edit this block in place: change the master and
-- re-carry it.
constant kUiBg = "240,242,246"
constant kUiCard = "255,255,255"
constant kUiCardLine = "225,229,236"
constant kUiAccent = "44,90,160"
constant kUiAccentText = "255,255,255"
constant kUiAccentSub = "199,216,241"
constant kUiInk = "28,34,46"
constant kUiInkSoft = "95,104,118"
constant kUiMuted = "138,146,158"
constant kUiOk = "23,128,63"
constant kUiWarn = "150,110,40"
constant kUiBad = "176,58,46"
constant kUiFieldLine = "203,210,222"
constant kUiCodeBg = "244,246,250"
constant kUiCodeLine = "210,217,229"

-- The platform's own terminal face for codes, keys, tables and logs, so
-- the monospace surfaces look native instead of typewriter-Courier. A
-- missing face substitutes the engine default - a soft, safe failure.
function uiMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end uiMonoFont

-- The window chrome every adopter shares: stack size, page ground, the
-- title band, and the one status line under it (write it with uiStatus).
-- pBandH is optional (default 30); a taller band leaves room for an
-- adopter's tagline or status pill, placed by the adopter.
command uiChrome pTitle, pWidth, pHeight, pBandH
   local tFH
   if pBandH is empty then
      put 30 into pBandH
   end if
   set the width of this stack to pWidth
   set the height of this stack to pHeight
   set the backgroundColor of this card to kUiBg
   set the title of this stack to pTitle
   uiGfx "uiBand", "0,0," & pWidth & "," & pBandH
   set the style of graphic "uiBand" to "rectangle"
   set the filled of graphic "uiBand" to true
   set the backgroundColor of graphic "uiBand" to kUiAccent
   set the lineSize of graphic "uiBand" to 0
   uiLabel "uiTitle", "  " & pTitle, "0,0," & pWidth & "," & pBandH, 15
   set the foregroundColor of field "uiTitle" to kUiAccentText
   set the textStyle of field "uiTitle" to "bold"
   -- center the title on the band midline by MEASURED height (never guess
   -- font metrics - the family's OXT passes clipped hand-sized labels)
   put the formattedHeight of field "uiTitle" into tFH
   if tFH > 0 and tFH < pBandH then
      set the height of field "uiTitle" to tFH
      set the top of field "uiTitle" to ((pBandH - tFH) div 2)
   end if
   uiLabel "uiStatus", empty, "16," & (pBandH + 4) & "," & (pWidth - 16) & "," & (pBandH + 22), 11
end uiChrome

-- The status line, colored by what it reports: "ok", "warn", "bad", or
-- anything else for neutral/muted. Demos route probe results through this
-- so a stack that cannot run says so in red, at the top, immediately.
command uiStatus pText, pKind
   put pText into field "uiStatus"
   if pKind is "ok" then
      set the foregroundColor of field "uiStatus" to kUiOk
   else if pKind is "warn" then
      set the foregroundColor of field "uiStatus" to kUiWarn
   else if pKind is "bad" then
      set the foregroundColor of field "uiStatus" to kUiBad
   else
      set the foregroundColor of field "uiStatus" to kUiInkSoft
   end if
end uiStatus

-- A static caption at a FIXED rect (idempotent, borderless, transparent).
-- Use uiWrap instead when the text may wrap or the exact height matters.
command uiLabel pName, pText, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the threeD of field pName to false
   set the textSize of field pName to pSize
   set the foregroundColor of field pName to kUiInk
   put pText into field pName
end uiLabel

-- A caption FIT to its measured text height (top pinned). The fit does
-- double duty: it prevents clipping (hand-sized rects clipped text on a
-- real Windows pass), and it makes `the height of field` equal the TEXT
-- height, which midline centering relies on. GUARD: only resize on a sane
-- measurement - a 0/blank formattedHeight (possible before the window is
-- fully realized) would collapse the label. Empty labels are skipped
-- (they receive their text later).
command uiWrap pName, pText, pRect, pSize
   local tOldDelim, tTop, tFH
   uiLabel pName, pText, pRect, pSize
   if pText is not empty then
      put the itemDelimiter into tOldDelim
      set the itemDelimiter to comma
      put item 2 of pRect into tTop
      set the itemDelimiter to tOldDelim
      put the formattedHeight of field pName into tFH
      if tFH > 0 then
         set the height of field pName to tFH
         set the top of field pName to tTop
      end if
   end if
end uiWrap

-- A small, muted caption (hints, toggle descriptions, empty states).
command uiCap pName, pText, pRect
   uiWrap pName, pText, pRect, 10
   set the foregroundColor of field pName to kUiMuted
end uiCap

-- A numbered bold section header with a hairline divider placed below the
-- label's ACTUAL (fit-to-text) bottom, so it tracks the real header
-- height on any platform's line metrics.
command uiSection pName, pText, pRect
   local tOldDelim, tL, tR, tB
   uiWrap pName, pText, pRect, 13
   set the textStyle of field pName to "bold"
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 1 of pRect into tL
   put item 3 of pRect into tR
   set the itemDelimiter to tOldDelim
   put the bottom of field pName into tB
   uiGfx (pName & "Line"), (tL & comma & (tB + 1) & comma & tR & comma & (tB + 2))
   set the style of graphic (pName & "Line") to "rectangle"
   set the filled of graphic (pName & "Line") to true
   set the backgroundColor of graphic (pName & "Line") to kUiCardLine
   set the lineSize of graphic (pName & "Line") to 0
end uiSection

-- A one-line entry field, mono and flat ("modern input" chrome instead of
-- the engine's sunken-3D default), because hex, addresses and paths are
-- what this suite's demos edit.
command uiInput pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to false
   set the traversalOn of field pName to true
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiFieldLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   -- 4-item margins form ONLY: OXT ignored the single-number form on a
   -- real engine pass
   set the margins of field pName to "6,6,6,6"
   set the textSize of field pName to 11
   set the textFont of field pName to uiMonoFont()
end uiInput

-- A read-only output/log area: mono, flat, scrolling, hairline-bordered.
command uiArea pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiCardLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   set the margins of field pName to "6,6,6,6"
   set the vScrollbar of field pName to true
   set the textSize of field pName to 10
   set the textFont of field pName to uiMonoFont()
end uiArea

-- A row-selectable table: uiArea plus list behavior and tab stops
-- ("230,340"-style comma lists). Pair it with a uiLabel header carrying
-- the same tabStops, set by the adopter.
command uiTable pName, pRect, pTabStops
   uiArea pName, pRect
   set the listBehavior of field pName to true
   if pTabStops is not empty then
      set the tabStops of field pName to pTabStops
   end if
end uiTable

command uiButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end uiButton

-- A script-managed checkbox: autoHilite OFF because the family drives
-- toggle state from script locals (a mode the environment cannot honour
-- must never stay silently armed - the quickshare pill lesson), so the
-- hilite is set explicitly by the adopter's state machine.
command uiCheckbox pName, pLabel, pRect
   uiButton pName, pLabel, pRect
   set the style of button pName to "checkbox"
   set the autoHilite of button pName to false
end uiCheckbox

-- Create-or-reuse a named graphic: the chrome layer (cards, pills,
-- dividers, drop targets). Created BEFORE the controls that sit on it, so
-- it stays behind them in z-order. roundRect + antialiased by default;
-- callers restyle.
command uiGfx pName, pRect
   if there is no graphic pName then
      create graphic
      set the name of the last graphic to pName
   end if
   set the rect of graphic pName to pRect
   set the style of graphic pName to "roundRect"
   set the antialiased of graphic pName to true
end uiGfx

-- A dashboard card: a rounded, hairline-bordered, softly shadowed panel
-- placed BEHIND a group of controls. It only groups visually; clicks on
-- it fall through to the adopter's `default: pass mouseUp`.
command uiPanel pName, pRect
   local tShadow, tErr
   uiGfx pName, pRect
   set the roundRadius of graphic pName to 14
   set the filled of graphic pName to true
   set the backgroundColor of graphic pName to kUiCard
   set the lineSize of graphic pName to 1
   -- a graphic strokes its outline in the foregroundColor; borderColor is
   -- set too so whichever the engine honours, the hairline lands
   set the foregroundColor of graphic pName to kUiCardLine
   set the borderColor of graphic pName to kUiCardLine
   -- soft drop shadow is an LC-9-era feature, so it is a PURE
   -- enhancement: an engine without it just skips it (the try) and the
   -- hairline still separates the card from the page
   try
      put "90,98,114" into tShadow["color"]
      put 30 into tShadow["opacity"]
      put 10 into tShadow["size"]
      put 0 into tShadow["spread"]
      put 2 into tShadow["distance"]
      put 90 into tShadow["angle"]
      set the dropShadow of graphic pName to tShadow
   catch tErr
   end try
end uiPanel

-- A status pill: rounded chip + centered label, colored by state kind -
-- "ok" green, "wait" amber, "bad" red, anything else the muted on-band
-- blue. The adopter repaints it from ONE place so its handlers cannot
-- disagree about the colors (the nocloud Tor-pill discipline).
command uiPill pName, pText, pRect, pKind
   local tOldDelim, tTop, tBot, tFH
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 2 of pRect into tTop
   put item 4 of pRect into tBot
   set the itemDelimiter to tOldDelim
   uiGfx (pName & "Bg"), pRect
   set the roundRadius of graphic (pName & "Bg") to (tBot - tTop)
   set the filled of graphic (pName & "Bg") to true
   set the lineSize of graphic (pName & "Bg") to 0
   if pKind is "ok" then
      set the backgroundColor of graphic (pName & "Bg") to "205,240,214"
   else if pKind is "wait" then
      set the backgroundColor of graphic (pName & "Bg") to "250,240,199"
   else if pKind is "bad" then
      set the backgroundColor of graphic (pName & "Bg") to "243,215,213"
   else
      set the backgroundColor of graphic (pName & "Bg") to "31,64,116"
   end if
   uiLabel pName, pText, pRect, 10
   set the textAlign of field pName to "center"
   if pKind is "ok" then
      set the foregroundColor of field pName to "22,101,52"
   else if pKind is "wait" then
      set the foregroundColor of field pName to "133,98,14"
   else if pKind is "bad" then
      set the foregroundColor of field pName to "135,44,38"
   else
      set the foregroundColor of field pName to kUiAccentSub
   end if
   -- center the label on the chip midline by measured height
   put the formattedHeight of field pName into tFH
   if tFH > 0 and tFH < (tBot - tTop) then
      set the height of field pName to tFH
      set the top of field pName to (tTop + ((tBot - tTop - tFH) div 2))
   end if
end uiPill

-- Click-to-copy feedback: flash the button's label to "Copied!" for
-- 1200 ms, then restore the real label (stashed in uRealLabel).
command uiCopyFlash pBtn
   if there is no button pBtn then
      exit uiCopyFlash
   end if
   if the uRealLabel of button pBtn is empty then
      set the uRealLabel of button pBtn to the label of button pBtn
   end if
   set the label of button pBtn to "Copied!"
   send ("uiCopyFlashReset" && quote & pBtn & quote) to me in 1200 milliseconds
end uiCopyFlash

command uiCopyFlashReset pBtn
   if there is no button pBtn then
      exit uiCopyFlashReset
   end if
   if the uRealLabel of button pBtn is not empty then
      set the label of button pBtn to the uRealLabel of button pBtn
   end if
end uiCopyFlashReset

-- The honesty/custody footer every demo carries: what the stack is, what
-- it is not, and its engine-evidence state.
command uiFooter pText, pRect
   uiWrap "uiFooter", pText, pRect, 11
   set the textStyle of field "uiFooter" to "italic"
   set the foregroundColor of field "uiFooter" to kUiMuted
end uiFooter
-- ==== SUITE UI KIT v2 END ====

on preOpenStack
   demoBuildUI
   -- The wiring is guarded so a stack opened WITHOUT its two libraries
   -- still builds and says what to load, in red, instead of dying on the
   -- first ox* call of the open (the UI above must exist first so the
   -- catch has a status line to paint).
   try
      oxSetCallbackOwner the long id of me
      oxSetStatusCallback "onStatus"
      oxhInit the long id of me
   catch tErr
      uiStatus "Libraries NOT loaded: start using stack " & quote & "onionxt" & quote \
            & " and stack " & quote & "onion-httpd" & quote & ", then reopen.", "bad"
   end try
   pass preOpenStack
end preOpenStack

on onStatus pKind, pInfo
   if pKind is "control" then
      if pInfo is "authenticated" then
         demoLog "control authenticated - now click 'Share Folder' and pick a folder"
         uiStatus "control authenticated - Share Folder next", "ok"
      else if pInfo begins with "authfailed" or pInfo begins with "error" then
         demoLog "control error: " & pInfo
         uiStatus "control error - see the log", "bad"
      else
         demoLog "control: " & pInfo
      end if
   else if pKind is "service" then
      put pInfo into sOnionAddress
      put false into sSvcReady
      put "http://" & pInfo & "/" into field "demo:url"
      demoLog "onion address: " & pInfo
      uiStatus "published, awaiting descriptor upload ...", "warn"
      -- PUBLISH WATCHDOG: readiness only ever arrives from HS_DESC UPLOADED
      -- (the serviceReady branch below), so a wedged upload otherwise reads
      -- as an eternal wait. demoPublishWatch names it after 90 s.
      send "demoPublishWatch" to me in 90000 milliseconds
   else if pKind is "serviceReady" then
      put true into sSvcReady
      demoLog "REACHABLE - open  http://" & sOnionAddress & "/  in Tor Browser to browse the files"
      uiStatus "REACHABLE - open the printed URL in Tor Browser", "ok"
   end if
end onStatus

-- The publish watchdog (armed by onStatus's "service" branch). REPORT ONLY:
-- the upload may still land late and Stop stays the user's call, so nothing
-- is torn down here - the wait just stops masquerading as progress at 90 s.
command demoPublishWatch
   if sSvcReady is true then
      exit demoPublishWatch
   end if
   if sSvcHandle is empty then
      exit demoPublishWatch
   end if
   uiStatus "descriptor upload has not confirmed in 90 s - check the tor daemon's log; Stop and retry", "bad"
   demoLog "! no HS_DESC UPLOADED confirmation after 90 s"
end demoPublishWatch

private command demoShareFolder
   local tFolder, tErr
   answer folder "Choose a folder to share over Tor"
   put it into tFolder
   if tFolder is empty then
      exit demoShareFolder       -- cancelled
   end if
   oxhServeFiles tFolder
   -- oxh commands report through the result (empty = ok). Today
   -- oxhServeFiles validates nothing and always reports empty, but a
   -- failure must never log as "sharing folder", so the report is checked
   -- rather than assumed (the shipped-is-not-run lesson).
   put the result into tErr
   if tErr is not empty then
      demoLog "share failed: " & tErr
      uiStatus "share failed - see the log", "bad"
      exit demoShareFolder
   end if
   demoLog "sharing folder: " & tFolder
   if sSvcHandle is an integer then
      demoLog "(already published; the new folder is live at the same .onion)"
      exit demoShareFolder
   end if
   oxhServe kVirtualPort, kLocalPort
   put the result into sSvcHandle
   if sSvcHandle is an integer then
      demoLog "publishing the onion (port " & kVirtualPort & " -> 127.0.0.1:" & kLocalPort & ") ..."
   else
      demoLog "serve failed: " & sSvcHandle
      uiStatus "serve failed - see the log", "bad"
   end if
end demoShareFolder

-- Minimal UI + lifecycle, on the kit's builders (create-if-missing, so a
-- reopen no longer duplicates controls; a version bump clears and rebuilds).
private command demoBuildUI
   if the uOhUiVersion of this stack is kOhUiVersion and there is a field "demo:out" then
      exit demoBuildUI
   end if
   demoClearGeneratedUI
   lock screen
   uiChrome "onion-httpd spike - a folder on an onion", 660, 440
   uiButton "demo:start", "Start", "16,60,140,90"
   uiButton "demo:share", "Share Folder", "150,60,300,90"
   uiButton "demo:stop", "Stop", "310,60,430,90"
   -- The URL line is OUTPUT: uiInput for the mono flat look, locked so a
   -- click cannot edit what it should only copy.
   uiInput "demo:url", "16,98,644,124"
   set the lockText of field "demo:url" to true
   put "(the .onion URL will appear here once published)" into field "demo:url"
   uiArea "demo:out", "16,132,644,400"
   uiFooter \
         "Shares the picked folder IN THE CLEAR to whoever has the address." \
         & " Serve path confirmed on-engine (folder README); this kit UI" \
         & " needs an OXT re-pass.", \
         "16,408,644,436"
   set the uOhUiVersion of this stack to kOhUiVersion
   unlock screen
end demoBuildUI

-- The rebuild's clear pass: every generated control's short name carries a
-- ":" ("demo:role"), while the kit's own chrome (uiTitle, uiStatus, uiBand,
-- uiFooter) has none and survives to be restyled in place.
private command demoClearGeneratedUI
   local tI
   lock screen
   repeat with tI = the number of fields of this card down to 1
      if the short name of field tI of this card contains ":" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      if the short name of button tI of this card contains ":" then
         delete button tI of this card
      end if
   end repeat
   repeat with tI = the number of graphics of this card down to 1
      if the short name of graphic tI of this card contains ":" then
         delete graphic tI of this card
      end if
   end repeat
   unlock screen
end demoClearGeneratedUI

on mouseUp
   local tName
   put the short name of the target into tName
   if tName is "demo:start" then
      demoStart
   else if tName is "demo:share" then
      demoShareFolder
   else if tName is "demo:stop" then
      demoStop
   end if
end mouseUp

private command demoStart
   local tErr
   put empty into field "demo:out"
   put empty into sOnionAddress
   demoLog "connecting to the tor control port 127.0.0.1:" & kControlPort & " ..."
   uiStatus "connecting to the tor control port ...", empty
   oxSetControlPort kControlPort
   oxSetSocksPort kSocksPort
   oxConnectControl
   put the result into tErr
   if tErr is not empty then
      demoLog "control connect error: " & tErr
      uiStatus "control connect error - see the log", "bad"
   end if
end demoStart

private command demoStop
   if sSvcHandle is an integer then
      oxhStop sSvcHandle
      put empty into sSvcHandle
      put false into sSvcReady
      demoLog "onion removed"
   end if
   oxDisconnectControl
end demoStop

on closeStack
   -- Guarded teardown: with the libraries missing there is nothing to stop,
   -- and closing the stack must not throw out of closeStack.
   try
      demoStop
      oxShutdown
   catch tErr
      -- not loaded; nothing to release
   end try
   pass closeStack
end closeStack

private command demoLog pText
   put pText & return after field "demo:out"
   set the scroll of field "demo:out" to the formattedHeight of field "demo:out"
end demoLog
