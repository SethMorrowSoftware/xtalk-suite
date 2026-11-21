script "xlsxtDemo"

-- xlsxt-demo.livecodescript - the xlsxt showcase stack.
--
-- One window that makes real Excel files and reads them back, a tab for
-- each thing the library does: a whole table in one call; fonts, colours,
-- borders and number formats; formulas, dates, links, notes and drop-down
-- lists; charts of every kind; page setup, protection and a picture; and
-- the reader, which opens any .xlsx and shows its sheets and cells. The
-- last tab runs every check in one click.
--
-- Every "Make" button does the same three things, so the window is honest
-- about what happened: it WRITES a workbook to a temporary file, READS that
-- file back with the reader, and says what it found. "Save the .xlsx" then
-- hands you the file. In a browser (OXT-Beyond's web engine, where the
-- library is linked into the engine) the file is written into the page's
-- own file system and Save downloads it.
--
-- HOW TO USE (requires the xlsxt extension, org.openxtalk.library.xlsxt):
-- paste this into a stack's script, then close and reopen that stack (or
-- `send "preOpenStack" to <that stack>` without closing). Opening this file
-- itself loads the script and builds no window - that is the engine, not
-- this demo: docs/OXT-ENGINE-NOTES.md 5.5.
--
-- Conventions: rows, columns and sheets count from 1. A call that is given
-- something it cannot use does nothing and returns 0 or empty; it never
-- throws, and xlLastError() says why. A workbook counts its own refusals,
-- so the builders here write freely and ask once before closing.
--
-- HONESTY (the suite convention): see the footer line this stack paints,
-- which is kept true to what has run.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here.

-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kXdUiVersion = "xlsxt-kit2-1"
constant kXdWidth = 960
constant kXdHeight = 620
-- The tabs, in order: key, then the label on its button.
constant kXdTabs = "tbl,sty,fx,ch,pg,rd,about"
constant kXdTabLabels = "Table,Formats,Formulas,Charts,Page,Read,About"
-- The chart kinds xlWorkbookAddChart takes, as the Charts tab lists them.
constant kXdChartKinds = "column,column stacked,column percent,bar,bar stacked,line,area,area stacked,pie,doughnut,scatter,scatter lines,scatter smooth,radar,radar markers"
-- A 40 x 40 PNG (a small green grid), for the picture the Page tab places:
-- carried as text so the demo stays one paste-and-run file.
constant kXdPicture = "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAIAAAADnC86AAAAS0lEQVR42u3UMQ0AIAxFQaxgBkP4wAducAQY6NiQkCOfqcNtr9TenqzcP9eIlnQFg8HfwM/KteOXdAWDwd/AygUGg5VLucBgAcndAfsIXhyXnhvJAAAAAElFTkSuQmCC"

local sTab          -- active tab key, one of kXdTabs
local sLastPath     -- the workbook the last Make wrote (a temporary file)
local sLastWhat     -- which builder made it: a tab key, or "all"
local sReadPath     -- the file the Read tab is showing
local sReadSheet    -- the sheet of it that is shown, from 1
local sCkPass       -- About: passing checks
local sCkFail       -- About: failing checks
local sCkLog        -- About: the running transcript

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
   -- PIN THE STACK, THEN CHECK THE FIELD EXISTS. Both halves were missing and
   -- both are load-bearing on a TIMER-driven call.
   --
   -- An unqualified `field "uiStatus"` resolves against the DEFAULTSTACK, not
   -- against the stack whose script is running. Inside openStack those are the
   -- same thing, which is why every demo's startup status line always worked.
   -- A handler arriving from `send ... in` has no such guarantee: with a second
   -- stack in front, the write lands in the wrong stack or resolves to nothing.
   --
   -- THE PIN RESTS ON THE DOCUMENTED RESOLUTION RULE, NOT ON A THROW WE SAW.
   -- This comment used to cite enet-lan-chat's once-a-second dashboard throwing
   -- "Chunk: error in object expression" REPEATEDLY on 2026-08-18, and dht-chat
   -- hiding the same fault behind a guard. Neither half held up: that throw was
   -- the ARGUMENT at the call site (`the number of keys of sPeers`, which does
   -- not parse - OXT-ENGINE-NOTES 1.7) and never reached uiStatus at all, and
   -- the guard credited to the kit was dht-chat's own wxSetStatus wrapper - the
   -- master had no existence check until the same commit that added this pin.
   -- What a guarded call site WOULD do if the defaultStack diverged is fail
   -- silently, which is the argument for a gate rather than for more guards.
   -- See OXT-ENGINE-NOTES 5.3, now classed DOCUMENTED.
   --
   -- The pin is holde-em's idiom, engine-proven there, and its comment names
   -- this exact hazard. The existence check stays as well: a demo may call the
   -- status line before its chrome is built, and a cosmetic line must never
   -- take down a poll chain.
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      exit uiStatus
   end if
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
   -- Pinned for the same reason uiStatus is: this one arrives 1200ms later by
   -- `send`, so the defaultStack is whatever is current THEN, not the stack
   -- that flashed the button. Its existence guard means the failure is silent
   -- rather than loud - the label just never comes back, or comes back on
   -- another stack's button - which is why it needed finding rather than
   -- reporting itself.
   set the defaultStack to the short name of this stack
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
-- ---- contextual menus -------------------------------------------------------
--
-- A RIGHT-CLICK MENU, as one hidden popup button per menu.
--
-- The engine's contextual menu is a BUTTON whose style is "menu" and whose
-- menuMode is "popup": its text is the item list, one per line, `popup`
-- shows it at a point, and choosing an item sends `menuPick` with the item's
-- LABEL. The button needs no script - with no handler of its own the message
-- walks the hierarchy and arrives at the card and then the stack, which is
-- where an adopter's router already lives.
--
-- OPT-IN, AND THAT IS DELIBERATE. This block is carried byte-identical by
-- every demo in the suite, so a kit that BUILT a menu would change eighteen
-- stacks to serve one. Nothing here runs unless an adopter calls
-- uiContextMenu, and a demo that never does is unchanged in behaviour.
--
-- NONE OF THIS HAS RUN ON AN ENGINE. `popup`, `menuMode` and `menuPick` are
-- documented LiveCode and OpenXTalk is a fork of it, but this suite has never
-- exercised a menu and the headless runners model no mouse button at all - so
-- an adopter's right-click handler belongs in a `try`, and losing the menu
-- must never cost the ordinary click. uiPopupMenu answers whether it worked
-- rather than throwing, so the caller can decide.

command uiContextMenu pName, pItems
   -- One hidden popup button, created once and refilled on every call so a
   -- menu can change with the screen it belongs to. The rect is small and
   -- inside the window because a stack's controls are measured by
   -- tools/check-stack-size.py whether they are visible or not.
   if there is no button pName then
      -- THE KIT'S OWN IDIOM, and not `create button pName`. Every other
      -- builder in this block creates the control unnamed and then names the
      -- last one, which is the spelling the family's headless runners model
      -- and the one every adopter has already been through an engine with.
      create button
      set the name of the last button to pName
   end if
   set the style of button pName to "menu"
   set the menuMode of button pName to "popup"
   set the text of button pName to pItems
   set the rect of button pName to "2,2,18,18"
   set the visible of button pName to false
end uiContextMenu

function uiPopupMenu pName
   -- WHICH menu, recorded before it opens. menuPick carries the item's label
   -- and nothing else, so an adopter with two menus would otherwise have to
   -- keep every label in the stack globally unique - a constraint that is
   -- invisible until the day two screens both want "Copy".
   --
   -- Answers true or false rather than throwing: on an engine without popup
   -- menus the right thing is for the click to do nothing, not for the
   -- adopter's mouseDown to die.
   local tError
   if there is no button pName then
      return false
   end if
   set the uUiMenu of this stack to pName
   try
      popup button pName at the clickLoc
   catch tError
      set the uUiMenu of this stack to empty
      return false
   end try
   return true
end uiPopupMenu

function uiMenuSource
   -- The name of the menu the last menuPick came from.
   return the uUiMenu of this stack
end uiMenuSource

-- ==== SUITE UI KIT v2 END ====

on preOpenStack
   xdBuildUI
   xdShowTab "tbl"
end preOpenStack

on closeStack
   -- A workbook or reader left open holds memory in the library until it
   -- is closed. Every builder here closes what it opens on the same click,
   -- error paths included; the Read tab opens its reader per repaint. So
   -- there is nothing to release, and nothing persists between handlers.
end closeStack

-- ==========================================================================
-- UI construction. Every generated control is named "prefix:role"; the
-- prefix is its tab (or "ui" for the tab bar, "act" for the action row),
-- so one loop shows a tab and one handler routes a click.
-- ==========================================================================

on xdBuildUI
   local tIndex, tKey, tLeft, tError
   -- Version-guarded rebuild: a saved stack keeps its controls, so only a
   -- kit or layout bump (kXdUiVersion) rebuilds them.
   if the uXdUiVersion of this stack is kXdUiVersion and there is a button "ui:tbl" then
      exit xdBuildUI
   end if
   xdClearUI
   lock screen
   -- 960 x 620 is held by tools/check-stack-size.py (every window fits 720p).
   uiChrome "xlsxt - Excel files written and read", kXdWidth, kXdHeight
   try
      uiStatus "Ready (" & xlLibraryVersion() & ").", "ok"
   catch tError
      uiStatus "xlsxt is NOT loaded: install org.openxtalk.library.xlsxt and reopen.", "bad"
   end try

   put 0 into tIndex
   repeat for each item tKey in kXdTabs
      add 1 to tIndex
      put 16 + (tIndex - 1) * 110 into tLeft
      uiButton "ui:" & tKey, item tIndex of kXdTabLabels, tLeft & ",60," & (tLeft + 104) & ",88"
   end repeat

   -- The card is created BEFORE the tab content so it sits behind it.
   uiPanel "ui:panel", "16,96,944,558"
   uiFooter \
         "Backed by libxlsxwriter, zlib and Expat through the xlsxt C shim. Every Make writes a real" \
         & " .xlsx and reads it back. The library has run on OXT-Beyond's Linux engine; this window" \
         & " is verified statically; needs an OXT pass. No file it wrote has been opened in Excel on the record.", \
         "16,564,944,616"

   xdBuildTable
   xdBuildFormats
   xdBuildFormulas
   xdBuildCharts
   xdBuildPage
   xdBuildRead
   xdBuildAbout

   -- The action row, shared by the five tabs that make a workbook.
   uiButton "act:make", "Make this workbook", "32,506,196,532"
   uiButton "act:all", "Make one with everything", "204,506,400,532"
   uiButton "act:save", "Save the .xlsx...", "408,506,552,532"
   uiLabel "act:result", "Nothing made yet. Pick a tab and click Make this workbook.", "32,535,928,554", 11
   set the foregroundColor of field "act:result" to kUiInkSoft

   set the uXdUiVersion of this stack to kXdUiVersion
   unlock screen
end xdBuildUI

-- The rebuild's clear pass: a generated control's short name carries a
-- ":", while the kit's own chrome (uiTitle, uiStatus, uiBand, uiFooter) has
-- none - so the colon IS the ownership tag.
private command xdClearUI
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
end xdClearUI

-- A tab's heading and its paragraph of explanation, at the same place on
-- every tab.
private command xdHeading pTab, pTitle, pWords
   uiWrap pTab & ":h", pTitle, "32,106,928,130", 15
   set the textStyle of field (pTab & ":h") to "bold"
   uiWrap pTab & ":exp", pWords, "32,132,928,176", 11
   set the foregroundColor of field (pTab & ":exp") to kUiInkSoft
end xdHeading

-- A checkbox that starts ticked or not. The kit's checkboxes are driven
-- from script (autoHilite off), so xdToggle flips them on a click.
private command xdCheck pName, pLabel, pRect, pOn
   uiCheckbox pName, pLabel, pRect
   -- a tick box is its tick and its words: no button frame around them
   set the showBorder of button pName to false
   set the shadow of button pName to false
   set the opaque of button pName to false
   set the hiliteBorder of button pName to false
   set the threeD of button pName to false
   set the hilite of button pName to pOn
end xdCheck

on xdBuildTable
   xdHeading "tbl", "A whole table in one call", \
         "xlSheetWriteGrid takes text with tabs between cells and returns between rows - the way a field," \
         & " a database query or the clipboard already holds a table - and writes every cell. Edit the table" \
         & " below (press Tab between cells), choose how cells are read, then Make this workbook."
   uiInput "tbl:data", "32,184,560,500"
   set the dontWrap of field "tbl:data" to true
   set the tabStops of field "tbl:data" to "130,230,330,430"
   set the vScrollbar of field "tbl:data" to true
   put xdSampleTable() into field "tbl:data"
   xdCheck "tbl:header", "The first row is a heading: bold, frozen, with filter buttons", "580,184,928,206", true
   xdCheck "tbl:numbers", "Cells that read as numbers are written as numbers", "580,214,928,236", true
   xdCheck "tbl:formulas", "Cells that begin with = are written as formulas", "580,244,928,266", true
   xdCheck "tbl:widths", "Fit the column widths to the longest cell", "580,274,928,296", true
   uiCap "tbl:note", "A leading zero (00420) stays text, so a part number or a postcode survives. Try typing" \
         & " =SUM(B2:B5) in a cell. Text outside ASCII is written as UTF-8 and comes back the same.", \
         "580,310,928,380"
end xdBuildTable

on xdBuildFormats
   xdHeading "sty", "Fonts, colours, borders and number formats", \
         "A format is made once with xlWorkbookAddFormat, described with the xlFormatSet calls, and handed to" \
         & " any call that writes a cell. This tab writes a small invoice that uses them all: a merged title," \
         & " a coloured heading row, money, percentages, dates, wrapped and rotated text, and a boxed total."
   uiLabel "sty:lt", "Title on the sheet", "32,186,200,206", 11
   uiInput "sty:title", "32,208,460,236"
   put "Quarterly invoice" into field "sty:title"
   uiLabel "sty:lc", "Heading colour (a name, #RRGGBB or r,g,b)", "480,186,928,206", 11
   uiInput "sty:color", "480,208,700,236"
   put "#1F4E78" into field "sty:color"
   uiArea "sty:list", "32,250,928,500"
   put xdFormatsList() into field "sty:list"
end xdBuildFormats

on xdBuildFormulas
   xdHeading "fx", "Formulas, dates, true and false, links, notes and lists", \
         "A formula is written as text and Excel works it out when the file opens; xlSheetWriteFormulaValue" \
         & " also stores a result, for readers that do not calculate. Dates are numbers with a date format." \
         & " This tab writes one of each kind of cell, a name for a cell, and a drop-down list."
   uiLabel "fx:ln", "Numbers to add up (commas between them)", "32,186,460,206", 11
   uiInput "fx:numbers", "32,208,460,236"
   put "12.5, 7, 30.25, 4" into field "fx:numbers"
   uiLabel "fx:ll", "A link to write", "480,186,928,206", 11
   uiInput "fx:link", "480,208,928,236"
   put "https://openxtalk.org/" into field "fx:link"
   uiLabel "fx:lv", "Choices for the drop-down list (commas between them)", "32,246,460,266", 11
   uiInput "fx:items", "32,268,460,296"
   put "yes,no,maybe" into field "fx:items"
   uiLabel "fx:lm", "A note to pin on a cell", "480,246,928,266", 11
   uiInput "fx:note", "480,268,928,296"
   put "Checked by the demo." into field "fx:note"
   uiArea "fx:list", "32,310,928,500"
   put xdFormulasList() into field "fx:list"
end xdBuildFormulas

on xdBuildCharts
   local tKinds
   xdHeading "ch", "Charts", \
         "A chart shows cells of the workbook: make it with xlWorkbookAddChart, give it series with" \
         & " xlChartAddSeries, then place it with xlSheetInsertChart. Pick a kind on the left. The workbook" \
         & " gets a sheet of figures and the chart beside them, drawn by Excel when the file is opened."
   uiTable "ch:kinds", "32,184,240,500", empty
   put kXdChartKinds into tKinds
   replace comma with return in tKinds
   put tKinds into field "ch:kinds"
   set the hilitedLine of field "ch:kinds" to 1
   uiLabel "ch:lt", "Chart title", "260,186,600,206", 11
   uiInput "ch:title", "260,208,600,236"
   put "Units and revenue by month" into field "ch:title"
   xdCheck "ch:labels", "Show each value on the chart", "260,250,600,272", true
   xdCheck "ch:two", "Two series (units and revenue)", "260,280,600,302", true
   xdCheck "ch:smooth", "Smooth the lines, with markers (line and scatter charts)", "260,310,700,332", false
   xdCheck "ch:every", "Also add a sheet with one chart of every kind", "260,340,700,362", false
   uiCap "ch:note", "Also set here: the legend's place, the titles and number format of the axes, gridlines," \
         & " a colour for each series and one of Excel's chart styles.", "260,376,928,430"
end xdBuildCharts

on xdBuildPage
   xdHeading "pg", "Page setup, protection and pictures", \
         "What the sheet looks like on paper and on screen: orientation, paper, margins, a header and footer," \
         & " rows repeated on every page, the print area, zoom, gridlines and the colour of the tab. A sheet" \
         & " can be protected or hidden, columns and rows hidden, and a PNG or JPEG picture placed on it."
   xdCheck "pg:landscape", "Landscape, on A4, fitted to one page wide", "32,186,460,208", true
   xdCheck "pg:picture", "Place a picture on the sheet", "32,216,460,238", true
   xdCheck "pg:protect", "Protect the sheet (only the unlocked cells can be typed in)", "32,246,460,268", true
   xdCheck "pg:hidden", "Add a second, hidden sheet", "32,276,460,298", true
   uiLabel "pg:lh", "Header (&L left, &C centre, &R right, &P page, &N pages, &D date)", "480,186,928,206", 11
   uiInput "pg:header", "480,208,928,236"
   put "&LMade with xlsxt&CPage &P of &N&R&D" into field "pg:header"
   uiLabel "pg:lf", "Footer", "480,246,928,266", 11
   uiInput "pg:footer", "480,268,928,296"
   put "&C&A" into field "pg:footer"
   uiLabel "pg:lw", "Password for the protection (may be empty)", "480,306,928,326", 11
   uiInput "pg:password", "480,328,700,356"
   uiArea "pg:list", "32,370,928,500"
   put xdPageList() into field "pg:list"
end xdBuildPage

on xdBuildRead
   xdHeading "rd", "Read any .xlsx", \
         "xlReadOpen opens a workbook written by Excel, LibreOffice, Numbers or this library and returns" \
         & " what is in its cells: text, numbers, dates as dates, formulas with their stored results." \
         & " Pick a sheet, then click a cell to see its kind, formula and number format."
   uiButton "rd:open", "Open an .xlsx file...", "32,184,200,212"
   uiButton "rd:last", "Show the last one made", "208,184,388,212"
   uiWrap "rd:file", "No file open.", "400,188,928,208", 11
   set the foregroundColor of field "rd:file" to kUiInkSoft
   uiLabel "rd:ls", "Sheets", "32,222,200,240", 11
   uiTable "rd:sheets", "32,242,200,420", empty
   uiLabel "rd:lg", "Cells (the first 200 rows and 26 columns)", "212,222,928,240", 11
   uiTable "rd:grid", "212,242,928,420", "40,150,260,370,480,590"
   set the dontWrap of field "rd:grid" to true
   set the hScrollbar of field "rd:grid" to true
   uiLabel "rd:lc", "The cell you clicked", "32,428,300,446", 11
   uiArea "rd:cell", "32,448,928,548"
end xdBuildRead

on xdBuildAbout
   xdHeading "about", "What this is, and a check of all of it", \
         "xlsxt writes Excel workbooks with libxlsxwriter and reads them with a reader of its own over zlib" \
         & " and Expat, all inside one library with nothing else to install. Run every check makes the" \
         & " complete workbook, reads it back cell by cell, and tries the things that must be refused."
   uiButton "about:run", "Run every check", "32,184,200,212"
   uiWrap "about:sum", "Not run yet.", "212,188,928,208", 11
   uiArea "about:log", "32,222,928,548"
end xdBuildAbout

-- ==========================================================================
-- Tabs.
-- ==========================================================================

on xdShowTab pKey
   local tI, tName, tShown, tKey
   put pKey into sTab
   lock screen
   repeat with tI = 1 to the number of controls of this card
      put the short name of control tI of this card into tName
      if tName contains ":" then
         set the itemDelimiter to ":"
         put item 1 of tName into tKey
         set the itemDelimiter to comma
         if tKey is "ui" then
            put true into tShown
         else if tKey is "act" then
            -- the action row belongs to the tabs that make a workbook
            put (pKey is not "rd" and pKey is not "about") into tShown
         else
            put (tKey is pKey) into tShown
         end if
         set the visible of control tI of this card to tShown
      end if
   end repeat
   repeat for each item tKey in kXdTabs
      if tKey is pKey then
         set the textStyle of button ("ui:" & tKey) to "bold"
      else
         set the textStyle of button ("ui:" & tKey) to "plain"
      end if
   end repeat
   unlock screen
   if pKey is "rd" and sReadPath is empty and sLastPath is not empty then
      xdReadShow sLastPath, 1
   end if
end xdShowTab

-- ==========================================================================
-- Click routing: a control's short name is "prefix:role".
-- ==========================================================================

on mouseUp
   local tName, tPrefix, tRole
   put the short name of the target into tName
   if tName contains ":" then
      set the itemDelimiter to ":"
      put item 1 of tName into tPrefix
      put item 2 of tName into tRole
      set the itemDelimiter to comma
      if tPrefix is "ui" then
         if tRole is among the items of kXdTabs then
            xdShowTab tRole
         end if
      else if word 1 of the target is "button" and the style of the target is "checkbox" then
         set the hilite of the target to not the hilite of the target
      else if tPrefix is "act" then
         xdAction tRole
      else if tPrefix is "rd" then
         xdReadClick tRole
      else if tName is "about:run" then
         xdRunChecks
      end if
   else
      pass mouseUp
   end if
end mouseUp

on xdAction pRole
   if pRole is "make" then
      xdMake sTab
   else if pRole is "all" then
      xdMake "all"
   else if pRole is "save" then
      xdSave
   end if
end xdAction

-- ==========================================================================
-- Making a workbook: write it, read it back, say what was found.
-- ==========================================================================

-- Where the demo writes: the engine's temporary folder, which a browser has
-- too (the page's own file system). The library is told to assemble its
-- parts there as well.
function xdTempFile pName
   local tFolder
   put the temporary folder into tFolder
   if tFolder is empty then
      put specialFolderPath("temporary") into tFolder
   end if
   return tFolder & "/" & pName
end xdTempFile

command xdResult pWords, pKind
   set the defaultStack to the short name of this stack
   if there is a field "act:result" then
      put pWords into field "act:result"
      if pKind is "bad" then
         set the foregroundColor of field "act:result" to kUiBad
      else if pKind is "ok" then
         set the foregroundColor of field "act:result" to kUiOk
      else
         set the foregroundColor of field "act:result" to kUiInkSoft
      end if
   end if
end xdResult

-- Builds the workbook of one tab (or of all five), and returns empty or the
-- reason it could not be made. On success sLastPath names the file.
function xdBuildBook pWhich
   local tPath, tBook, tRefused, tFirst, tError
   put xdTempFile("xlsxt-demo-" & pWhich & ".xlsx") into tPath
   try
      xlSetTempFolder the temporary folder
      put xlWorkbookNew(tPath) into tBook
   catch tError
      return "xlsxt is not loaded (" & line 1 of tError & ")"
   end try
   if tBook is 0 then
      return xlLastError()
   end if
   xlWorkbookSetProperty tBook, "title", "xlsxt demo"
   xlWorkbookSetProperty tBook, "author", "xlsxt demo stack"
   xlWorkbookSetProperty tBook, "comments", "Written by xlsxt-demo.livecodescript"
   if pWhich is "tbl" or pWhich is "all" then
      xdSheetTable tBook
   end if
   if pWhich is "sty" or pWhich is "all" then
      xdSheetFormats tBook
   end if
   if pWhich is "fx" or pWhich is "all" then
      xdSheetFormulas tBook
   end if
   if pWhich is "ch" or pWhich is "all" then
      xdSheetCharts tBook
   end if
   if pWhich is "pg" or pWhich is "all" then
      xdSheetPage tBook
   end if
   -- One question for the whole workbook: was any call refused?
   put xlWorkbookErrorCount(tBook) into tRefused
   put xlWorkbookFirstError(tBook) into tFirst
   if not xlWorkbookClose(tBook) then
      return "The file could not be written: " & xlLastError()
   end if
   put tPath into sLastPath
   put pWhich into sLastWhat
   if tRefused > 0 then
      return "Written, but" && tRefused && "call(s) were refused. The first: " & tFirst
   end if
   return empty
end xdBuildBook

on xdMake pWhich
   local tProblem, tSummary
   if pWhich is not "all" and pWhich is not among the items of "tbl,sty,fx,ch,pg" then
      exit xdMake
   end if
   put xdBuildBook(pWhich) into tProblem
   if tProblem is not empty and not (tProblem begins with "Written, but") then
      xdResult tProblem, "bad"
      uiStatus "Not made.", "bad"
      exit xdMake
   end if
   put xdSummary(sLastPath) into tSummary
   if tProblem is not empty then
      xdResult tProblem, "bad"
   else
      xdResult "Made and read back: " & tSummary, "ok"
   end if
   uiStatus "Workbook written to " & sLastPath, "ok"
   -- the Read tab shows the newest file the next time it is opened
   put empty into sReadPath
end xdMake

-- What the reader finds in a file, in one line: each sheet and its size.
function xdSummary pPath
   local tReader, tCount, tSheet, tOut, tBytes
   put xlReadOpen(pPath) into tReader
   if tReader is 0 then
      return "the reader refused it: " & xlLastError()
   end if
   put xlReadSheetCount(tReader) into tCount
   repeat with tSheet = 1 to tCount
      if tOut is not empty then
         put ", " after tOut
      end if
      put xlReadSheetName(tReader, tSheet) after tOut
      if xlReadLoad(tReader, tSheet) then
         put " (" & xlReadRowCount(tReader, tSheet) & " x " & xlReadColumnCount(tReader, tSheet) & ")" after tOut
      end if
      if xlReadSheetIsHidden(tReader, tSheet) then
         put " hidden" after tOut
      end if
   end repeat
   xlReadClose tReader
   put the number of bytes of URL ("binfile:" & pPath) into tBytes
   return tCount && "sheet(s), " & tBytes & " bytes: " & tOut
end xdSummary

-- Save: the user names a file and the temporary workbook is copied to it.
-- In a browser `ask file` answers a path under /downloads, and a file
-- written there by the engine is handed to the browser as a download.
on xdSave
   local tName, tTarget
   if sLastPath is empty or there is no file sLastPath then
      xdResult "Make a workbook first, then save it.", "bad"
      exit xdSave
   end if
   put "xlsxt-demo.xlsx" into tName
   ask file "Save the workbook as:" with tName
   put it into tTarget
   if tTarget is empty then
      exit xdSave
   end if
   put URL ("binfile:" & sLastPath) into URL ("binfile:" & tTarget)
   if the result is not empty then
      xdResult "It could not be saved: " & the result, "bad"
   else if the platform is "HTML5" then
      xdResult "Downloaded. Your browser has the file in its downloads.", "ok"
   else
      xdResult "Saved as " & tTarget, "ok"
   end if
end xdSave

-- ==========================================================================
-- The builders: each adds its sheet(s) to an open workbook.
-- ==========================================================================

function xdSampleTable
   return "Month" & tab & "Units" & tab & "Price" & tab & "Code" & return & \
         "January" & tab & "12" & tab & "9.5" & tab & "00420" & return & \
         "February" & tab & "7" & tab & "10.25" & tab & "00421" & return & \
         "March" & tab & "15" & tab & "8.75" & tab & "00422" & return & \
         "April" & tab & "9" & tab & "11" & tab & "00423"
end xdSampleTable

-- The table of the Table tab, as typed (or the sample before the window
-- exists, which is how the checks and the "everything" workbook run).
function xdTableText
   local tTable
   set the defaultStack to the short name of this stack
   if there is a field "tbl:data" then
      put field "tbl:data" into tTable
   end if
   if tTable is empty then
      put xdSampleTable() into tTable
   end if
   return tTable
end xdTableText

-- A tick box's state, or pDefault while the window has not been built.
function xdTicked pName, pDefault
   set the defaultStack to the short name of this stack
   if there is a button pName then
      return the hilite of button pName
   end if
   return pDefault
end xdTicked

-- A field's text, or pDefault while the window has not been built or the
-- field is empty.
function xdTyped pName, pDefault
   local tGot
   set the defaultStack to the short name of this stack
   if there is a field pName then
      put line 1 of field pName into tGot
   end if
   if tGot is empty then
      return pDefault
   end if
   return tGot
end xdTyped

command xdSheetTable pBook
   local tSheet, tTable, tMode, tHead, tRows, tColumns, tLine, tCell, tIndex, tWidths, tWide
   put xlWorkbookAddSheet(pBook, "Table") into tSheet
   put xdTableText() into tTable
   if xdTicked("tbl:formulas", true) then
      put "formulas" into tMode
   else if xdTicked("tbl:numbers", true) then
      put "numbers" into tMode
   else
      put "text" into tMode
   end if
   -- the whole table, one call
   get xlSheetWriteGrid(tSheet, 1, 1, tTable, tMode, 0)

   put the number of lines of tTable into tRows
   put 0 into tColumns
   set the itemDelimiter to tab
   repeat for each line tLine in tTable
      put max(tColumns, the number of items of tLine) into tColumns
      put 0 into tIndex
      repeat for each item tCell in tLine
         add 1 to tIndex
         if tWidths[tIndex] is empty or the number of chars of tCell > tWidths[tIndex] then
            put the number of chars of tCell into tWidths[tIndex]
         end if
      end repeat
   end repeat

   if xdTicked("tbl:header", true) and tRows > 0 and tColumns > 0 then
      put xlWorkbookAddFormat(pBook) into tHead
      xlFormatSetBold tHead, true
      xlFormatSetBackgroundColor tHead, "#DDEBF7"
      xlFormatSetBorderSide tHead, "bottom", "medium"
      -- the heading row again, with the format: a later write replaces a cell
      put 0 into tIndex
      repeat for each item tCell in line 1 of tTable
         add 1 to tIndex
         xlSheetWriteText tSheet, 1, tIndex, tCell, tHead
      end repeat
      xlSheetFreeze tSheet, 1, 0
      xlSheetAutofilter tSheet, 1, 1, tRows, tColumns
   end if
   if xdTicked("tbl:widths", true) then
      repeat with tIndex = 1 to tColumns
         put min(60, max(8, tWidths[tIndex] + 3)) into tWide
         xlSheetSetColumns tSheet, tIndex, tIndex, tWide, 0
      end repeat
   end if
   set the itemDelimiter to comma
end xdSheetTable

function xdFormatsList
   return "What Make this workbook writes on the sheet 'Formats':" & return & return & \
         "A1:E1   merged title - 16 pt bold white on the heading colour, centred both ways, row 30 high" & return & \
         "A3:E3   heading row - bold, white on the heading colour, thin white borders, centred" & return & \
         "A4:A7   item names - wrapped text, top aligned, indented one step" & return & \
         "B4:B7   quantities - number format 0, right aligned" & return & \
         "C4:C7   prices - #,##0.00 in the font Courier New" & return & \
         "D4:D7   discounts - 0% in italic dark red" & return & \
         "E4:E7   dates - d mmm yyyy" & return & \
         "A8:E8   total row - bold, double line above, thick line below, formulas in money format" & return & \
         "G3      text turned 45 degrees        G4  struck through      G5  underlined twice" & return & \
         "G6      H2O with a subscript format    G7  shrunk to fit       G8  a hair border in a colour" & return & \
         "columns A to E are set wide; column F is hidden; row 2 is hidden"
end xdFormatsList

command xdSheetFormats pBook
   local tSheet, tColor, tTitle, tHead, tName, tQty, tMoney, tPct, tDate, tTotal, tRow, tItems, tLine, tAny
   put xlWorkbookAddSheet(pBook, "Formats") into tSheet
   put xdTyped("sty:color", "#1F4E78") into tColor

   put xlWorkbookAddFormat(pBook) into tTitle
   xlFormatSetBold tTitle, true
   xlFormatSetFontSize tTitle, 16
   xlFormatSetFontColor tTitle, "white"
   xlFormatSetBackgroundColor tTitle, tColor
   xlFormatSetAlign tTitle, "center"
   xlFormatSetVerticalAlign tTitle, "middle"
   xlSheetMerge tSheet, 1, 1, 1, 5, xdTyped("sty:title", "Quarterly invoice"), tTitle
   xlSheetSetRow tSheet, 1, 30, 0
   xlSheetHideRow tSheet, 2

   put xlWorkbookAddFormat(pBook) into tHead
   xlFormatSetBold tHead, true
   xlFormatSetFontColor tHead, "255,255,255"
   xlFormatSetBackgroundColor tHead, tColor
   xlFormatSetAlign tHead, "center"
   xlFormatSetBorder tHead, "thin"
   xlFormatSetBorderColor tHead, "white"
   get xlSheetWriteGrid(tSheet, 3, 1, "Item" & tab & "Quantity" & tab & "Price" & tab & "Discount" & tab & "Ordered", "text", tHead)

   put xlWorkbookAddFormat(pBook) into tName
   xlFormatSetTextWrap tName, true
   xlFormatSetVerticalAlign tName, "top"
   xlFormatSetIndent tName, 1
   put xlWorkbookAddFormat(pBook) into tQty
   xlFormatSetNumberFormat tQty, "0"
   xlFormatSetAlign tQty, "right"
   put xlWorkbookAddFormat(pBook) into tMoney
   xlFormatSetNumberFormat tMoney, "#,##0.00"
   xlFormatSetFontName tMoney, "Courier New"
   put xlWorkbookAddFormat(pBook) into tPct
   xlFormatSetNumberFormat tPct, "0%"
   xlFormatSetItalic tPct, true
   xlFormatSetFontColor tPct, "#990000"
   put xlWorkbookAddFormat(pBook) into tDate
   xlFormatSetNumberFormat tDate, "d mmm yyyy"

   put "Desk lamp, brass, with a long description that wraps onto a second line|4|89.5|0.1|2026,1,14" & return & \
         "Office chair|12|240|0.15|2026,2,3" & return & \
         "Monitor arm|6|119.99|0|2026,2,27" & return & \
         "Whiteboard|2|1250|0.05|2026,3,9" into tItems
   put 3 into tRow
   set the itemDelimiter to "|"
   repeat for each line tLine in tItems
      add 1 to tRow
      xlSheetWriteText tSheet, tRow, 1, item 1 of tLine, tName
      xlSheetWriteNumber tSheet, tRow, 2, item 2 of tLine, tQty
      xlSheetWriteNumber tSheet, tRow, 3, item 3 of tLine, tMoney
      xlSheetWriteNumber tSheet, tRow, 4, item 4 of tLine, tPct
      xlSheetWriteDate tSheet, tRow, 5, xdDateSerial(item 5 of tLine), tDate
   end repeat
   set the itemDelimiter to comma

   put xlWorkbookAddFormat(pBook) into tTotal
   xlFormatSetBold tTotal, true
   xlFormatSetNumberFormat tTotal, "#,##0.00"
   xlFormatSetBorderSide tTotal, "top", "double"
   xlFormatSetBorderSide tTotal, "bottom", "thick"
   xlSheetWriteText tSheet, 8, 1, "Total", tTotal
   xlSheetWriteFormula tSheet, 8, 2, "=SUM(B4:B7)", tTotal
   xlSheetWriteFormulaValue tSheet, 8, 3, "=SUMPRODUCT(B4:B7,C4:C7,1-D4:D7)", 5865.14, tTotal
   xlSheetWriteBlank tSheet, 8, 4, tTotal
   xlSheetWriteBlank tSheet, 8, 5, tTotal

   -- one cell for each of the rarer settings
   put xlWorkbookAddFormat(pBook) into tAny
   xlFormatSetRotation tAny, 45
   xlSheetWriteText tSheet, 3, 7, "turned", tAny
   put xlWorkbookAddFormat(pBook) into tAny
   xlFormatSetStrikeout tAny, true
   xlSheetWriteText tSheet, 4, 7, "struck through", tAny
   put xlWorkbookAddFormat(pBook) into tAny
   xlFormatSetUnderline tAny, "double"
   xlSheetWriteText tSheet, 5, 7, "underlined twice", tAny
   put xlWorkbookAddFormat(pBook) into tAny
   xlFormatSetScript tAny, "subscript"
   xlSheetWriteText tSheet, 6, 7, "subscript", tAny
   put xlWorkbookAddFormat(pBook) into tAny
   xlFormatSetShrink tAny, true
   xlSheetWriteText tSheet, 7, 7, "shrunk to fit its cell however long it is", tAny
   put xlWorkbookAddFormat(pBook) into tAny
   xlFormatSetBorder tAny, "hair"
   xlFormatSetBorderColor tAny, "0,128,0"
   xlSheetWriteText tSheet, 8, 7, "boxed", tAny

   xlSheetSetColumns tSheet, 1, 1, 34, 0
   xlSheetSetColumns tSheet, 2, 5, 14, 0
   xlSheetHideColumns tSheet, 6, 6
   xlSheetSetColumns tSheet, 7, 7, 18, 0
end xdSheetFormats

-- "2026,2,3" to its date serial.
function xdDateSerial pYMD
   set the itemDelimiter to comma
   return xlDateToSerial(item 1 of pYMD, item 2 of pYMD, item 3 of pYMD, 0, 0, 0)
end xdDateSerial

function xdFormulasList
   return "What Make this workbook writes on the sheet 'Formulas':" & return & return & \
         "A2 down   your numbers, one to a row" & return & \
         "C2        =SUM of them, with the result stored beside the formula" & return & \
         "C3        =AVERAGE of them, left for Excel to work out" & return & \
         "C4        =Total*2, where Total is a name defined for C2 (xlWorkbookDefineName)" & return & \
         "E2 E3     true and false" & return & \
         "E4 E5 E6  today as a date, now as a date and time, and a time of day alone" & return & \
         "E7        the seconds, converted with xlSecondsToSerial" & return & \
         "G2        your link; G3 a link to a cell of this workbook; G4 a link to send mail" & return & \
         "G6        a cell with your note pinned to it" & return & \
         "G8        a cell that only takes one of your choices (a drop-down list)" & return & \
         "A12       text outside ASCII, and A13 two lines in one cell"
end xdFormulasList

command xdSheetFormulas pBook
   local tSheet, tNumbers, tNumber, tRow, tSum, tCount, tBold, tLast, tWide
   put xlWorkbookAddSheet(pBook, "Formulas") into tSheet
   put xlWorkbookAddFormat(pBook) into tBold
   xlFormatSetBold tBold, true
   get xlSheetWriteGrid(tSheet, 1, 1, "Numbers" & tab & tab & "Results" & tab & tab & "Values" & tab & tab & "Links and notes", "text", tBold)

   put xdTyped("fx:numbers", "12.5, 7, 30.25, 4") into tNumbers
   put 1 into tRow
   put 0 into tSum
   put 0 into tCount
   repeat for each item tNumber in tNumbers
      put word 1 to -1 of tNumber into tNumber
      if tNumber is a number then
         add 1 to tRow
         add 1 to tCount
         add tNumber to tSum
         xlSheetWriteNumber tSheet, tRow, 1, tNumber, 0
      end if
   end repeat
   if tCount is 0 then
      -- nothing usable was typed: one number keeps the formulas meaningful
      put 2 into tRow
      put 1 into tCount
      xlSheetWriteNumber tSheet, 2, 1, 0, 0
   end if
   put "A2:A" & tRow into tLast
   xlSheetWriteFormulaValue tSheet, 2, 3, "=SUM(" & tLast & ")", tSum, 0
   xlSheetWriteFormula tSheet, 3, 3, "=AVERAGE(" & tLast & ")", 0
   xlWorkbookDefineName pBook, "Total", xlRangeFormula("Formulas", 2, 3, 2, 3)
   xlSheetWriteFormula tSheet, 4, 3, "=Total*2", 0

   xlSheetWriteBoolean tSheet, 2, 5, true, 0
   xlSheetWriteBoolean tSheet, 3, 5, false, 0
   xlSheetWriteDate tSheet, 4, 5, xlDateToSerial(2026, 11, 20, 0, 0, 0), 0
   xlSheetWriteDate tSheet, 5, 5, xlDateToSerial(2026, 11, 20, 14, 30, 0), 0
   xlSheetWriteDate tSheet, 6, 5, xlDateToSerial(0, 0, 0, 9, 15, 0), 0
   xlSheetWriteDate tSheet, 7, 5, xlSecondsToSerial(the seconds), 0

   xlSheetWriteLink tSheet, 2, 7, xdTyped("fx:link", "https://openxtalk.org/"), "Your link", 0
   xlSheetWriteLink tSheet, 3, 7, "internal:Formulas!A1", "Back to A1", 0
   xlSheetWriteLink tSheet, 4, 7, "mailto:someone@example.com", "Write to someone", 0
   xlSheetWriteText tSheet, 6, 7, "Hover for the note", 0
   xlSheetWriteComment tSheet, 6, 7, xdTyped("fx:note", "Checked by the demo.")
   xlSheetWriteText tSheet, 8, 7, word 1 of xdFirstChoice(), 0
   xlSheetValidateList tSheet, 8, 7, 8, 7, xdTyped("fx:items", "yes,no,maybe")

   -- text outside ASCII, built by number because this file is ASCII: Latin-1,
   -- a snowman (three bytes of UTF-8) and a face outside the BMP (four)
   put "caf" & numToCodepoint(233) && numToCodepoint(9731) && numToCodepoint(128512) into tWide
   xlSheetWriteText tSheet, 12, 1, tWide, 0
   xlSheetWriteText tSheet, 13, 1, "two" & numToChar(10) & "lines", 0

   xlSheetSetColumns tSheet, 1, 1, 16, 0
   xlSheetSetColumns tSheet, 3, 3, 14, 0
   xlSheetSetColumns tSheet, 5, 5, 20, 0
   xlSheetSetColumns tSheet, 7, 7, 22, 0
end xdSheetFormulas

function xdFirstChoice
   local tItems
   put xdTyped("fx:items", "yes,no,maybe") into tItems
   return item 1 of tItems
end xdFirstChoice

-- The chart kind picked in the list, or "column".
function xdChartKind
   local tKind
   set the defaultStack to the short name of this stack
   if there is a field "ch:kinds" then
      put the hilitedText of field "ch:kinds" into tKind
   end if
   if tKind is empty or tKind is not among the items of kXdChartKinds then
      put "column" into tKind
   end if
   return tKind
end xdChartKind

command xdSheetCharts pBook
   local tSheet, tChart, tSeries, tKind, tCats, tUnits, tRevenue, tEvery, tRow, tColumn, tIndex
   put xlWorkbookAddSheet(pBook, "Charts") into tSheet
   get xlSheetWriteGrid(tSheet, 1, 1, "Month" & tab & "Units" & tab & "Revenue" & return & \
         "January" & tab & "12" & tab & "114" & return & \
         "February" & tab & "7" & tab & "71.75" & return & \
         "March" & tab & "15" & tab & "131.25" & return & \
         "April" & tab & "9" & tab & "99" & return & \
         "May" & tab & "18" & tab & "171" & return & \
         "June" & tab & "11" & tab & "110", "numbers", 0)
   put xlRangeFormula("Charts", 2, 1, 7, 1) into tCats
   put xlRangeFormula("Charts", 2, 2, 7, 2) into tUnits
   put xlRangeFormula("Charts", 2, 3, 7, 3) into tRevenue

   put xdChartKind() into tKind
   put xlWorkbookAddChart(pBook, tKind) into tChart
   -- a scatter chart plots numbers against numbers: units along the bottom
   if tKind begins with "scatter" then
      put xlChartAddSeries(tChart, tUnits, tRevenue) into tSeries
      xlChartSeriesSetName tChart, tSeries, "Revenue by units"
      xlChartSetAxisTitle tChart, "x", "Units"
   else
      put xlChartAddSeries(tChart, tCats, tUnits) into tSeries
      xlChartSeriesSetName tChart, tSeries, "=Charts!$B$1"
      xlChartSetAxisTitle tChart, "x", "Month"
   end if
   xlChartSeriesSetColor tChart, tSeries, "#2E75B6"
   xlChartSeriesSetLabels tChart, tSeries, xdTicked("ch:labels", true)
   if xdTicked("ch:smooth", false) then
      xlChartSeriesSetSmooth tChart, tSeries, true
      xlChartSeriesSetMarker tChart, tSeries, "circle"
   end if
   if xdTicked("ch:two", true) and not (tKind begins with "scatter") and tKind is not "pie" and tKind is not "doughnut" then
      put xlChartAddSeries(tChart, tCats, tRevenue) into tSeries
      xlChartSeriesSetName tChart, tSeries, "=Charts!$C$1"
      xlChartSeriesSetColor tChart, tSeries, "237,125,49"
      xlChartSeriesSetMarker tChart, tSeries, "diamond"
   end if
   xlChartSetTitle tChart, xdTyped("ch:title", "Units and revenue by month")
   xlChartSetAxisTitle tChart, "y", "Amount"
   xlChartSetAxisRange tChart, "y", 0, 200
   xlChartSetAxisNumberFormat tChart, "y", "#,##0"
   xlChartSetAxisGridlines tChart, "y", true
   xlChartSetLegend tChart, "bottom"
   xlChartSetStyle tChart, 10
   xlSheetInsertChart tSheet, 2, 5, tChart, 1.2, 1.2
   xlSheetSetColumns tSheet, 1, 3, 12, 0

   if xdTicked("ch:every", false) then
      put xlWorkbookAddSheet(pBook, "Every chart") into tEvery
      put 0 into tIndex
      repeat for each item tKind in kXdChartKinds
         put xlWorkbookAddChart(pBook, tKind) into tChart
         if tKind begins with "scatter" then
            get xlChartAddSeries(tChart, tUnits, tRevenue)
         else
            get xlChartAddSeries(tChart, tCats, tUnits)
         end if
         xlChartSetTitle tChart, tKind
         xlChartSetLegend tChart, "none"
         -- three to a row, each 8 columns wide and 15 rows tall
         put 1 + (tIndex div 3) * 16 into tRow
         put 1 + (tIndex mod 3) * 8 into tColumn
         xlSheetInsertChart tEvery, tRow, tColumn, tChart, 1, 1
         add 1 to tIndex
      end repeat
   end if
end xdSheetCharts

function xdPageList
   return "What Make this workbook writes on the sheet 'Page':" & return & return & \
         "sixty rows of figures under a heading row that repeats on every printed page (rows 1 to 1)" & return & \
         "margins of half an inch; the print area A1:F61; zoom 120%; gridlines printed; a green tab" & return & \
         "the heading row frozen; the formulas of column F hidden once the sheet is protected" & return & \
         "the 'Notes' column (E) unlocked, so it can still be typed in on a protected sheet" & return & \
         "this sheet is the one that is selected when the file opens (xlSheetActivate)"
end xdPageList

command xdSheetPage pBook
   local tSheet, tHead, tOpen, tSecret, tRow, tPicture, tHidden
   put xlWorkbookAddSheet(pBook, "Page") into tSheet
   put xlWorkbookAddFormat(pBook) into tHead
   xlFormatSetBold tHead, true
   xlFormatSetBackgroundColor tHead, "silver"
   get xlSheetWriteGrid(tSheet, 1, 1, "Line" & tab & "Amount" & tab & "Rate" & tab & "Due" & tab & "Notes" & tab & "Sum", "text", tHead)
   -- unlocked cells stay editable on a protected sheet; a hidden formula
   -- shows its result and not how it was worked out
   put xlWorkbookAddFormat(pBook) into tOpen
   xlFormatSetLocked tOpen, false
   xlFormatSetBackgroundColor tOpen, "#FFF2CC"
   put xlWorkbookAddFormat(pBook) into tSecret
   xlFormatSetFormulaHidden tSecret, true
   repeat with tRow = 2 to 61
      xlSheetWriteNumber tSheet, tRow, 1, tRow - 1, 0
      xlSheetWriteNumber tSheet, tRow, 2, (tRow - 1) * 12.5, 0
      xlSheetWriteNumber tSheet, tRow, 3, 0.2, 0
      xlSheetWriteBlank tSheet, tRow, 5, tOpen
      xlSheetWriteFormula tSheet, tRow, 6, "=B" & tRow & "*(1+C" & tRow & ")", tSecret
   end repeat

   if xdTicked("pg:landscape", true) then
      xlSheetSetLandscape tSheet, true
      xlSheetSetPaper tSheet, 9
      xlSheetFitToPages tSheet, 1, 0
   end if
   xlSheetSetMargins tSheet, 0.5, 0.5, 0.5, 0.5
   xlSheetSetHeader tSheet, xdTyped("pg:header", "&LMade with xlsxt&CPage &P of &N&R&D")
   xlSheetSetFooter tSheet, xdTyped("pg:footer", "&C&A")
   xlSheetRepeatRows tSheet, 1, 1
   xlSheetPrintArea tSheet, 1, 1, 61, 6
   xlSheetSetZoom tSheet, 120
   xlSheetShowGridlines tSheet, true, true
   xlSheetSetTabColor tSheet, "green"
   xlSheetFreeze tSheet, 1, 0
   xlSheetSetColumns tSheet, 5, 5, 30, 0

   if xdTicked("pg:picture", true) then
      put xdTempFile("xlsxt-demo-picture.png") into tPicture
      put base64Decode(kXdPicture) into URL ("binfile:" & tPicture)
      -- the file is read when the workbook is closed, so it stays until then
      xlSheetInsertImage tSheet, 3, 8, tPicture, 2, 2
   end if
   if xdTicked("pg:hidden", true) then
      put xlWorkbookAddSheet(pBook, "Hidden notes") into tHidden
      xlSheetWriteText tHidden, 1, 1, "A sheet that is in the file but has no tab until it is unhidden.", 0
      xlSheetHide tHidden
   end if
   if xdTicked("pg:protect", true) then
      xlSheetProtect tSheet, xdTyped("pg:password", empty)
   end if
   xlSheetActivate tSheet
end xdSheetPage

-- ==========================================================================
-- The Read tab.
-- ==========================================================================

on xdReadClick pRole
   local tPath
   if pRole is "open" then
      answer file "Open an Excel workbook (.xlsx):"
      put it into tPath
      if tPath is not empty then
         xdReadShow tPath, 1
      end if
   else if pRole is "last" then
      if sLastPath is empty then
         put "Nothing has been made yet: use Make this workbook on another tab." into field "rd:file"
      else
         xdReadShow sLastPath, 1
      end if
   else if pRole is "sheets" then
      if sReadPath is not empty and the hilitedLine of field "rd:sheets" > 0 then
         xdReadShow sReadPath, the hilitedLine of field "rd:sheets"
      end if
   else if pRole is "grid" then
      xdReadCell
   end if
end xdReadClick

-- Opens pPath, lists its sheets, shows sheet pSheet, and closes it again:
-- the tab keeps a path, never an open reader.
command xdReadShow pPath, pSheet
   local tReader, tCount, tIndex, tNames, tRows, tColumns, tGrid, tOut, tRow, tLine, tName, tError
   set the defaultStack to the short name of this stack
   try
      put xlReadOpen(pPath) into tReader
   catch tError
      put "xlsxt is not loaded." into field "rd:file"
      exit xdReadShow
   end try
   if tReader is 0 then
      put "Not opened: " & xlLastError() into field "rd:file"
      set the foregroundColor of field "rd:file" to kUiBad
      exit xdReadShow
   end if
   put pPath into sReadPath
   put xlReadSheetCount(tReader) into tCount
   put max(1, min(pSheet, tCount)) into sReadSheet
   repeat with tIndex = 1 to tCount
      put xlReadSheetName(tReader, tIndex) into tName
      if xlReadSheetIsHidden(tReader, tIndex) then
         put " (hidden)" after tName
      end if
      put tName & return after tNames
   end repeat
   delete the last char of tNames
   put tNames into field "rd:sheets"
   set the hilitedLine of field "rd:sheets" to sReadSheet

   put empty into tOut
   put 0 into tRows
   put 0 into tColumns
   if xlReadLoad(tReader, sReadSheet) then
      put xlReadRowCount(tReader, sReadSheet) into tRows
      put xlReadColumnCount(tReader, sReadSheet) into tColumns
      -- a window onto the sheet, not the sheet: enough to look around in
      put xlReadGrid(tReader, sReadSheet, 1, 1, min(tRows, 200), min(tColumns, 26)) into tGrid
      -- a row number in front of each line; a line break inside a cell
      -- arrives as a vertical tab, shown here as a space
      replace numToChar(11) with space in tGrid
      put 0 into tRow
      repeat for each line tLine in tGrid
         add 1 to tRow
         put tRow & tab & tLine & return after tOut
      end repeat
      delete the last char of tOut
   end if
   put tOut into field "rd:grid"
   put xdFileName(pPath) & ": sheet " & sReadSheet & " of " & tCount & ", " & tRows & " rows x " & tColumns \
         & " columns. Merged: " & xdOrNone(xlReadMerged(tReader, sReadSheet)) & ". Dates count from " \
         & xdEpoch(xlReadUses1904(tReader)) & "." into field "rd:file"
   set the foregroundColor of field "rd:file" to kUiInkSoft
   put "Click a row of the cells above, on the cell you want." into field "rd:cell"
   xlReadClose tReader
end xdReadShow

function xdFileName pPath
   set the itemDelimiter to "/"
   return the last item of pPath
end xdFileName

function xdOrNone pText
   if pText is empty then
      return "none"
   end if
   replace return with ", " in pText
   return pText
end xdOrNone

function xdEpoch pIs1904
   if pIs1904 then
      return "1904"
   end if
   return "1900"
end xdEpoch

-- Which cell was clicked: the row is the clicked line; the column is found
-- by counting the tabs in front of the clicked character (the first tab
-- follows the row number).
command xdReadCell
   local tRow, tColumn, tChunk, tFirst, tLine, tBefore, tReader, tOut, tKind
   set the defaultStack to the short name of this stack
   if sReadPath is empty then
      exit xdReadCell
   end if
   put the hilitedLine of field "rd:grid" into tRow
   if tRow is not an integer or tRow < 1 then
      exit xdReadCell
   end if
   put 1 into tColumn
   put the clickCharChunk into tChunk
   if word 1 of tChunk is "char" and word 2 of tChunk is an integer then
      put word 2 of tChunk into tFirst
      put line tRow of field "rd:grid" into tLine
      -- chars of the field before this line: every earlier line and its return
      if tRow > 1 then
         subtract the number of chars of (line 1 to (tRow - 1) of field "rd:grid") + 1 from tFirst
      end if
      put char 1 to tFirst of tLine into tBefore
      set the itemDelimiter to tab
      put max(1, the number of items of (tBefore & "x") - 1) into tColumn
      set the itemDelimiter to comma
   end if
   put xlReadOpen(sReadPath) into tReader
   if tReader is 0 then
      put "The file can no longer be opened: " & xlLastError() into field "rd:cell"
      exit xdReadCell
   end if
   get xlReadLoad(tReader, sReadSheet)
   put xlReadCellKind(tReader, sReadSheet, tRow, tColumn) into tKind
   put "Cell " & xlCellName(tRow, tColumn) & " (row " & tRow & ", column " & tColumn & ", " & xlColumnName(tColumn) & ")" & return into tOut
   put "kind:     " & tKind & return after tOut
   put "shown:    " & xlReadCell(tReader, sReadSheet, tRow, tColumn) & return after tOut
   put "stored:   " & xlReadCellValue(tReader, sReadSheet, tRow, tColumn) & return after tOut
   put "formula:  " & xlReadCellFormula(tReader, sReadSheet, tRow, tColumn) & return after tOut
   put "format:   " & xlReadCellFormat(tReader, sReadSheet, tRow, tColumn) after tOut
   if tKind is "date" then
      put return & "as text:  " & xlSerialToDate(xlReadCellNumber(tReader, sReadSheet, tRow, tColumn)) after tOut
   end if
   xlReadClose tReader
   put tOut into field "rd:cell"
end xdReadCell

-- ==========================================================================
-- About: every check, in one click. The same code is what a headless run
-- calls (xdCheckAll), so the window and the tests cannot drift apart.
-- ==========================================================================

on xdRunChecks
   local tReport
   set the defaultStack to the short name of this stack
   put xdCheckAll() into tReport
   put tReport into field "about:log"
   if sCkFail is 0 then
      put sCkPass && "checks passed, none failed." into field "about:sum"
      set the foregroundColor of field "about:sum" to kUiOk
      uiStatus "Every check passed.", "ok"
   else
      put sCkPass && "passed," && sCkFail && "FAILED. The failing lines begin with FAIL." into field "about:sum"
      set the foregroundColor of field "about:sum" to kUiBad
      uiStatus sCkFail && "check(s) failed.", "bad"
   end if
end xdRunChecks

private command xdCk pOk, pLabel, pDetail
   if pOk is true then
      add 1 to sCkPass
      put "PASS  " & pLabel & return after sCkLog
   else
      add 1 to sCkFail
      put "FAIL  " & pLabel & "  [" & pDetail & "]" & return after sCkLog
   end if
end xdCk

-- Returns the transcript; its last line is "SUMMARY <passed> <failed>".
function xdCheckAll
   local tProblem, tReader, tSheet, tNames, tIndex, tError, tWide, tBook, tPath, tGot
   put 0 into sCkPass
   put 0 into sCkFail
   put empty into sCkLog
   try
      put "Library: " & xlLibraryVersion() & return after sCkLog
      xdCk xlABIVersion() is 1, "the library is at the ABI this binding wants", xlABIVersion()
      xdCk xlCellName(3, 2) is "B3" and xlColumnName(28) is "AB" and xlCellRow("B3") is 3 and xlCellColumn("AB12") is 28, \
            "cell names both ways", xlCellName(3, 2) && xlColumnName(28)
      xdCk xlRangeName(1, 1, 3, 2) is "A1:B3" and xlRangeFormula("My Sheet", 2, 1, 7, 1) is "='My Sheet'!$A$2:$A$7", \
            "range names, with a sheet name that needs quotes", xlRangeFormula("My Sheet", 2, 1, 7, 1)
      xdCk xlSerialToDate(xlDateToSerial(2026, 11, 20, 14, 30, 0)) is "2026-11-20 14:30:00", \
            "a date to its serial and back", xlSerialToDate(xlDateToSerial(2026, 11, 20, 14, 30, 0))
      xdCk xlSerialToSeconds(xlSecondsToSerial(1700000000)) is 1700000000, "seconds to a serial and back", \
            xlSerialToSeconds(xlSecondsToSerial(1700000000))

      -- the complete workbook: every builder, as the window's defaults or
      -- as it is set now
      put xdBuildBook("all") into tProblem
      xdCk tProblem is empty, "the complete workbook is written and no call was refused", tProblem
      xdCk there is a file sLastPath and byte 1 to 2 of URL ("binfile:" & sLastPath) is "PK", "the file is there and is a zip", sLastPath
      xdCk xlWorkbookCount() is 0, "no workbook is left open after the close", xlWorkbookCount()

      put xlReadOpen(sLastPath) into tReader
      xdCk tReader > 0 and xlReadIsValid(tReader), "the reader opens it", xlLastError()
      repeat with tIndex = 1 to xlReadSheetCount(tReader)
         put xlReadSheetName(tReader, tIndex) & comma after tNames
      end repeat
      xdCk tNames begins with "Table,Formats,Formulas,Charts," and "Page," is in tNames, "the sheets, in the order they were added", tNames

      put xlReadSheetNumber(tReader, "Table") into tSheet
      xdCk xlReadLoad(tReader, tSheet), "Table loads", xlLastError()
      xdCk xlReadRowCount(tReader, tSheet) >= 1 and xlReadCell(tReader, tSheet, 1, 1) is xdFirstCell(xdTableText()), \
            "its first cell is the first cell typed", xlReadCell(tReader, tSheet, 1, 1)

      put xlReadSheetNumber(tReader, "Formats") into tSheet
      xdCk xlReadLoad(tReader, tSheet), "Formats loads", xlLastError()
      xdCk xlReadMerged(tReader, tSheet) is "A1:E1", "the merged title", xlReadMerged(tReader, tSheet)
      xdCk xlReadCellFormat(tReader, tSheet, 4, 3) is "#,##0.00" and xlReadCellNumber(tReader, tSheet, 4, 3) is 89.5, \
            "a price and its number format", xlReadCellFormat(tReader, tSheet, 4, 3) && xlReadCell(tReader, tSheet, 4, 3)
      xdCk xlReadCellFormat(tReader, tSheet, 4, 4) is "0%", "a percentage format", xlReadCellFormat(tReader, tSheet, 4, 4)
      xdCk xlReadCellKind(tReader, tSheet, 4, 5) is "date" and xlReadCell(tReader, tSheet, 4, 5) is "2026-01-14", \
            "a date reads as a date", xlReadCell(tReader, tSheet, 4, 5)
      xdCk xlReadCellFormula(tReader, tSheet, 8, 3) begins with "=SUMPRODUCT(" and xlReadCellNumber(tReader, tSheet, 8, 3) is 5865.14, \
            "a formula and the result stored with it", xlReadCellFormula(tReader, tSheet, 8, 3) && xlReadCell(tReader, tSheet, 8, 3)

      put xlReadSheetNumber(tReader, "Formulas") into tSheet
      xdCk xlReadLoad(tReader, tSheet), "Formulas loads", xlLastError()
      xdCk xlReadCellFormula(tReader, tSheet, 2, 3) begins with "=SUM(A2:A", "the SUM formula", xlReadCellFormula(tReader, tSheet, 2, 3)
      xdCk xlReadCell(tReader, tSheet, 2, 5) is "true" and xlReadCell(tReader, tSheet, 3, 5) is "false" \
            and xlReadCellKind(tReader, tSheet, 2, 5) is "boolean", "true and false", xlReadCell(tReader, tSheet, 2, 5)
      xdCk xlReadCell(tReader, tSheet, 5, 5) is "2026-11-20 14:30:00", "a date and time", xlReadCell(tReader, tSheet, 5, 5)
      xdCk xlReadCell(tReader, tSheet, 2, 7) is "Your link", "the text of a link", xlReadCell(tReader, tSheet, 2, 7)
      put "caf" & numToCodepoint(233) && numToCodepoint(9731) && numToCodepoint(128512) into tWide
      xdCk xlReadCell(tReader, tSheet, 12, 1) is tWide, "text outside ASCII comes back the same", \
            the number of chars of xlReadCell(tReader, tSheet, 12, 1)
      xdCk xlReadCell(tReader, tSheet, 13, 1) is "two" & numToChar(10) & "lines", "a line break inside a cell", \
            the number of chars of xlReadCell(tReader, tSheet, 13, 1)

      put xlReadSheetNumber(tReader, "Charts") into tSheet
      xdCk xlReadLoad(tReader, tSheet) and xlReadCellNumber(tReader, tSheet, 4, 3) is 131.25, "the figures under the chart", \
            xlReadCell(tReader, tSheet, 4, 3)
      put xlReadSheetNumber(tReader, "Page") into tSheet
      xdCk xlReadLoad(tReader, tSheet) and xlReadRowCount(tReader, tSheet) is 61, "the sixty-row page sheet", xlReadRowCount(tReader, tSheet)
      xdCk xlReadCellFormula(tReader, tSheet, 61, 6) is "=B61*(1+C61)", "its last formula", xlReadCellFormula(tReader, tSheet, 61, 6)
      xdCk xlReadUses1904(tReader) is false, "dates count from 1900", xlReadUses1904(tReader)
      xdCk xlReadCell(tReader, 99, 1, 1) is empty and xlReadCell(tReader, tSheet, 0, 0) is empty, "a read outside the file is empty, not an error", \
            xlReadCell(tReader, 99, 1, 1)
      xlReadClose tReader
      xdCk xlReadIsValid(tReader) is false and xlReadCount() is 0, "the reader is closed", xlReadCount()

      -- every chart kind is accepted and an unknown one is not
      put xdTempFile("xlsxt-demo-check.xlsx") into tPath
      put xlWorkbookNew(tPath) into tBook
      put empty into tGot
      repeat for each item tIndex in kXdChartKinds
         if xlWorkbookAddChart(tBook, tIndex) is 0 then
            put tIndex & comma after tGot
         end if
      end repeat
      xdCk tGot is empty, "every chart kind is made", tGot
      xdCk xlWorkbookAddChart(tBook, "hologram") is 0 and xlLastError() is not empty, "an unknown chart kind is refused in words", xlLastError()
      put xlWorkbookAddSheet(tBook, "A") into tSheet
      xdCk xlWorkbookAddSheet(tBook, "a") is 0, "a second sheet of the same name is refused", xlLastError()
      xlSheetWriteNumber tSheet, 0, 1, 5, 0
      xlSheetWriteLink tSheet, 1, 1, "just words", empty, 0
      -- four so far: the chart kind, the sheet name, row 0 and the link
      xdCk xlWorkbookErrorCount(tBook) is 4 and xlWorkbookFirstError(tBook) is not empty, "a workbook counts what it refused", \
            xlWorkbookErrorCount(tBook)
      xlWorkbookDiscard tBook
      xdCk there is no file tPath and xlWorkbookCount() is 0, "a discarded workbook writes nothing", xlWorkbookCount()
      xlSheetWriteNumber tSheet, 1, 1, 5, 0
      xdCk xlLastError() is not empty, "a handle of a closed workbook is refused, not a fault", "no error"

      put "this is not a workbook" into URL ("binfile:" & tPath)
      xdCk xlReadOpen(tPath) is 0 and xlLastError() is not empty, "a file that is no workbook is refused in words", xlLastError()
      delete file tPath
      xdCk xlReadOpen(tPath) is 0, "a missing file does not open", xlLastError()
   catch tError
      xdCk false, "the checks ran to their end", line 1 of tError
   end try
   put "SUMMARY" && sCkPass && sCkFail after sCkLog
   return sCkLog
end xdCheckAll

-- The first cell of a table of tabs and returns.
function xdFirstCell pTable
   set the itemDelimiter to tab
   return item 1 of line 1 of pTable
end xdFirstCell
