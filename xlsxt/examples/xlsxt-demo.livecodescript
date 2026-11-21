script "xlsxtDemo"

-- xlsxt-demo.livecodescript - Spreadsheet Studio, the xlsxt showcase stack.
--
-- It opens playing. A tour of four short scenes writes real Excel files and
-- reads them back while you watch: a sheet fills itself cell by cell and is
-- given its colours, money format, frozen heading and a chart; formulas,
-- today's date and a true-or-false cell are written with their answers; all
-- fifteen kinds of chart the library makes are drawn and written into one
-- file; and ten thousand cells are written and read back a few rows at a
-- time, timed. Each scene ends by reading the file it wrote and saying
-- whether every cell came back the same. A button plays any one scene
-- again, and one plays all four.
--
-- The other tabs are the workbench: a whole table in one call; fonts,
-- colours, borders and number formats; formulas, dates, links, notes and
-- drop-down lists; charts of every kind; page setup, protection and a
-- picture; the reader, which opens any .xlsx and shows its sheets and
-- cells; and About, which runs every check in one click.
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
-- this demo: docs/OXT-ENGINE-NOTES.md 5.5. Without the extension the window
-- still opens and the scenes still play; each says that nothing was written.
--
-- Conventions: rows, columns and sheets count from 1. A call that is given
-- something it cannot use does nothing and returns 0 or empty; it never
-- throws, and xlLastError() says why. A workbook counts its own refusals,
-- so the builders here write freely and ask once before closing.
--
-- HONESTY (the suite convention): see the footer line this stack paints,
-- which is kept true to what has run.
--
-- THE LOOK. The suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical), builds the controls; xdDress then gives them
-- OXT-Beyond's dark look. Every field, label and tick box is given its own
-- text colour, and every entry field and list its own background, so no
-- system theme, light or dark, can leave words white on white (engine note
-- 5.16). Push buttons are drawn by this stack (a rounded shape behind a
-- transparent button), so they look the same under every theme.
--
-- SMOOTH. The scenes run on a timer, one frame at a time, each frame under
-- `lock screen`. Nothing waits: long work is done a few rows a frame, with
-- a bar that shows how far it has got, and the window answers clicks all
-- the while. Leaving the Showcase tab stops the scene and closes its files.

-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kXdUiVersion = "xlsxt-beyond-1"
constant kXdWidth = 960
constant kXdHeight = 640
-- The header band: OXT-Beyond's name, the demo's, what it does, who made it.
constant kXdBandH = 50
-- The tabs, in order: key, then the label on its button.
constant kXdTabs = "show,tbl,sty,fx,ch,pg,rd,about"
constant kXdTabLabels = "Showcase,Table,Formats,Formulas,Charts,Page,Read,About"
-- The tabs whose workbook the action row makes.
constant kXdMakers = "tbl,sty,fx,ch,pg"
-- The tabs are laid out for a header 16 points shorter than this one, then
-- moved down by that much in one pass (xdShiftDown).
constant kXdDown = 16
-- The chart kinds xlWorkbookAddChart takes, as the Charts tab lists them.
constant kXdChartKinds = "column,column stacked,column percent,bar,bar stacked,line,area,area stacked,pie,doughnut,scatter,scatter lines,scatter smooth,radar,radar markers"
-- A 40 x 40 PNG (a small green grid), for the picture the Page tab places:
-- carried as text so the demo stays one paste-and-run file.
constant kXdPicture = "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAIAAAADnC86AAAAS0lEQVR42u3UMQ0AIAxFQaxgBkP4wAducAQY6NiQkCOfqcNtr9TenqzcP9eIlnQFg8HfwM/KteOXdAWDwd/AygUGg5VLucBgAcndAfsIXhyXnhvJAAAAAElFTkSuQmCC"

-- OXT-Beyond's dark look. Each colour is named where it is used, so a
-- system theme never chooses one.
constant kXdStage = "15,17,23"         -- the window
constant kXdBand = "22,26,35"          -- the header band
constant kXdPanel = "25,29,39"         -- the card behind a tab
constant kXdWell = "17,20,28"          -- entry fields, lists, logs, the chart
constant kXdLine = "52,60,76"          -- hairlines and borders
constant kXdInk = "232,236,242"        -- words
constant kXdSoft = "168,176,190"       -- explanations
constant kXdMuted = "122,131,146"      -- small print
constant kXdSelect = "176,104,48"      -- the chosen line of a list (light or dark words read on it)
constant kXdHeadRow = "62,44,30"       -- a sheet's heading row, in the showcase
constant kXdAccent = "255,140,60"      -- OXT-Beyond orange
constant kXdAccentOver = "255,162,96"
constant kXdAccentDown = "226,116,38"
constant kXdAccentInk = "26,20,14"     -- words on the orange
constant kXdButton = "38,44,58"
constant kXdButtonOver = "52,60,78"
constant kXdButtonDown = "30,35,47"
constant kXdButtonEdge = "76,86,106"
constant kXdOk = "102,212,140"
constant kXdBad = "242,118,108"
constant kXdWarn = "236,192,96"
constant kXdSecond = "86,180,233"      -- a chart's second series
-- The slices of a pie, in turn ("|" between colours).
constant kXdSlices = "255,140,60|86,180,233|102,212,140|236,192,96|190,128,232|242,118,108"

-- The showcase: its scenes, in the order the tour plays them.
constant kXdScenes = "sheet,formulas,charts,many"
constant kXdSceneLabels = "A sheet fills itself,Formulas and dates,Every kind of chart,Ten thousand cells"
-- One frame of a scene, in milliseconds: 20 a second, which makes each
-- scene five to ten seconds long.
constant kXdFrameMs = 50
-- The pause between two scenes of the tour.
constant kXdRestMs = 2200
-- The lines the showcase's sheet shows: the column letters, then 13 rows.
constant kXdGridLines = 14
-- Graphics kept for the chart the showcase draws. They are made with the
-- window and reused, so a frame creates and deletes nothing.
constant kXdPool = 12

local sTab          -- active tab key, one of kXdTabs
local sLastPath     -- the workbook the last Make or scene wrote (a temporary file)
local sLastWhat     -- which builder made it: a tab key, "all" or a scene
local sReadPath     -- the file the Read tab is showing
local sReadSheet    -- the sheet of it that is shown, from 1
local sCkPass       -- About: passing checks
local sCkFail       -- About: failing checks
local sCkLog        -- About: the running transcript
local sPressed      -- the painted button the mouse went down on
local sShowGen      -- counts the showcase's starts and stops: a frame of an older run ends itself
local sShowScene    -- the scene playing, an item of kXdScenes, or empty
local sShowStep     -- the frame of the scene playing, from 1
local sShowTour     -- true while the scenes play one after another
local sShowState    -- the scene's working values: its cells, workbook, reader, timings

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
   xdShowTab "show"
   -- straight into motion: the tour starts with the window
   xdShowPlay item 1 of kXdScenes, true
end preOpenStack

on closeStack
   -- The showcase is the one thing that keeps a workbook or a reader open
   -- between handlers, for the length of a scene; stopping it closes both
   -- and cancels its next frame. Every builder closes what it opens on the
   -- same click, error paths included, and the Read tab opens its reader
   -- per repaint.
   xdShowStop
end closeStack

-- ==========================================================================
-- UI construction. Every generated control is named "prefix:role"; the
-- prefix is its tab, or "ui" for the tab bar, "hd" for the header, "act"
-- for the action row and "pool" for the graphics the showcase draws with,
-- so one loop shows a tab and one handler routes a click.
-- ==========================================================================

on xdBuildUI
   local tIndex, tKey, tLeft
   -- Version-guarded rebuild: a saved stack keeps its controls, so only a
   -- kit or layout bump (kXdUiVersion) rebuilds them.
   if the uXdUiVersion of this stack is kXdUiVersion and there is a button "ui:show" then
      exit xdBuildUI
   end if
   xdShowStop
   xdClearUI
   lock screen
   -- 960 x 640 is held by tools/check-stack-size.py (every window fits 720p).
   uiChrome "Spreadsheet Studio - xlsxt", kXdWidth, kXdHeight, kXdBandH
   xdHeader
   if xdLoaded() then
      xdStatus "Ready (" & xlLibraryVersion() & ").", "ok"
   else
      xdStatus "xlsxt is NOT loaded: install org.openxtalk.library.xlsxt and reopen. The scenes still play;" \
            & " nothing is written.", "bad"
   end if

   put 0 into tIndex
   repeat for each item tKey in kXdTabs
      add 1 to tIndex
      put 16 + (tIndex - 1) * 116 into tLeft
      xdButton "ui:" & tKey, item tIndex of kXdTabLabels, tLeft & ",78," & (tLeft + 110) & ",104", "tab"
   end repeat

   -- The card is created BEFORE the tab content so it sits behind it.
   uiPanel "ui:panel", "16,112,944,574"
   uiFooter \
         "Backed by libxlsxwriter, zlib and Expat through the xlsxt C shim; every scene and every Make writes a" \
         & " real .xlsx and reads it back. This window has run on OXT-Beyond's Linux engine; on Windows, macOS" \
         & " and in a browser it is verified statically; needs an OXT pass. No file it wrote has been opened" \
         & " in Excel on the record.", \
         "16,582,944,636"
   set the foregroundColor of field "uiFooter" to kXdMuted

   -- The tabs, laid out for the shorter header and moved down below.
   xdBuildShow
   xdBuildTable
   xdBuildFormats
   xdBuildFormulas
   xdBuildCharts
   xdBuildPage
   xdBuildRead
   xdBuildAbout

   -- The action row, shared by the five tabs that make a workbook.
   xdButton "act:make", "Make this workbook", "32,506,196,532", "fill"
   xdButton "act:all", "Make one with everything", "204,506,400,532", "plain"
   xdButton "act:save", "Save the .xlsx...", "408,506,552,532", "plain"
   uiLabel "act:result", "Nothing made yet. Pick a tab and click Make this workbook.", "32,535,928,554", 11
   set the foregroundColor of field "act:result" to kXdSoft

   xdShiftDown
   xdDress
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

-- The header: OXT-Beyond's name over the demo's on the left, what the demo
-- does and who made it on the right, and an orange rule under the band.
private command xdHeader
   set the backgroundColor of this card to kXdStage
   set the backgroundColor of graphic "uiBand" to kXdBand
   xdHeaderLabel "hd:brand", "OXT-BEYOND", "10,3,410,37", 10, kXdAccent, "bold", "left"
   -- the demo's name goes in the field the kit made for the window's title
   put "Spreadsheet Studio" into field "uiTitle"
   set the textSize of field "uiTitle" to 20
   set the textStyle of field "uiTitle" to "bold"
   set the foregroundColor of field "uiTitle" to kXdInk
   set the rect of field "uiTitle" to "10,14,610,56"
   xdHeaderLabel "hd:what", "Real Excel workbooks, written and read back by the xlsxt extension.", \
         "380,5,950,45", 12, kXdSoft, "plain", "right"
   xdHeaderLabel "hd:by", "by Seth Morrow", "380,24,950,60", 11, kXdSoft, "italic", "right"
   uiGfx "hd:rule", "0," & kXdBandH & "," & kXdWidth & "," & (kXdBandH + 2)
   set the style of graphic "hd:rule" to "rectangle"
   set the filled of graphic "hd:rule" to true
   set the lineSize of graphic "hd:rule" to 0
   set the backgroundColor of graphic "hd:rule" to kXdAccent
end xdHeader

-- One line of the header, at a rect that puts its letters where they go.
-- The field keeps the engine's own margins: with margins of 0, a small
-- size draws its letters above the field's top, and the window cut the
-- tops off them (the Linux engine, 2026-11-21). With them, the letters of
-- 10 to 20 point start 3 to 7 points below the top and 6 in from the side.
private command xdHeaderLabel pName, pText, pRect, pSize, pColor, pStyle, pAlign
   uiLabel pName, pText, pRect, pSize
   set the textStyle of field pName to pStyle
   set the textAlign of field pName to pAlign
   set the foregroundColor of field pName to pColor
end xdHeaderLabel

-- A push button this stack draws: a rounded shape, then a transparent
-- button on it that carries the words and takes the clicks. pKind is
-- "fill" (the orange of the main action), "plain" or "tab"; a tab or a
-- scene that is on (its uXdOn) is orange too, so on and off never look
-- alike.
command xdButton pName, pLabel, pRect, pKind
   uiGfx (pName & "Bg"), pRect
   set the roundRadius of graphic (pName & "Bg") to 8
   set the filled of graphic (pName & "Bg") to true
   uiButton pName, pLabel, pRect
   set the style of button pName to "transparent"
   set the opaque of button pName to false
   set the showBorder of button pName to false
   set the threeD of button pName to false
   set the shadow of button pName to false
   set the hiliteBorder of button pName to false
   set the autoHilite of button pName to false
   set the traversalOn of button pName to false
   set the textSize of button pName to 12
   set the textStyle of button pName to "bold"
   set the uXdKind of button pName to pKind
   xdPaint pName, "rest"
end xdButton

-- Paints a drawn button for a state: "rest", "over" (the pointer is on
-- it) or "down" (pressed).
command xdPaint pName, pState
   local tBack, tInk, tEdge
   set the defaultStack to the short name of this stack
   if there is no button pName or there is no graphic (pName & "Bg") then
      exit xdPaint
   end if
   if the uXdKind of button pName is "fill" or the uXdOn of button pName is true then
      put kXdAccentInk into tInk
      put empty into tEdge
      if pState is "over" then
         put kXdAccentOver into tBack
      else if pState is "down" then
         put kXdAccentDown into tBack
      else
         put kXdAccent into tBack
      end if
   else
      put kXdInk into tInk
      put kXdButtonEdge into tEdge
      if pState is "over" then
         put kXdButtonOver into tBack
      else if pState is "down" then
         put kXdButtonDown into tBack
      else
         put kXdButton into tBack
      end if
   end if
   set the backgroundColor of graphic (pName & "Bg") to tBack
   if tEdge is empty then
      set the lineSize of graphic (pName & "Bg") to 0
   else
      set the lineSize of graphic (pName & "Bg") to 1
      set the foregroundColor of graphic (pName & "Bg") to tEdge
   end if
   set the foregroundColor of button pName to tInk
end xdPaint

-- Moves each tab's controls, and the action row, down by kXdDown: the tabs
-- were laid out for a header that much shorter.
private command xdShiftDown
   local tI, tName, tPrefix
   repeat with tI = 1 to the number of controls of this card
      put the short name of control tI of this card into tName
      if tName contains ":" then
         put char 1 to (offset(":", tName) - 1) of tName into tPrefix
         if tPrefix is "act" or tPrefix is among the items of kXdTabs then
            set the top of control tI of this card to (the top of control tI of this card) + kXdDown
         end if
      end if
   end repeat
end xdShiftDown

-- SAY EVERY COLOUR. The kit paints a light card and leaves the text colour
-- of its entry fields, lists and tick boxes to the system theme; a dark
-- theme's is white (engine note 5.16). Here each field this window made
-- gets OXT-Beyond's colours: an entry field, list or log a dark well with
-- light words and an orange-brown chosen line, a caption the light, soft
-- or muted ink that matches the kit colour it was given. Each tick box
-- names its ink too. The drive (tests/demo-drive.livecodescript) fails a
-- window that leaves one to the theme.
private command xdDress
   local tI, tColor, tError
   set the backgroundColor of this card to kXdStage
   repeat with tI = 1 to the number of fields of this card
      if the opaque of field tI of this card then
         set the backgroundColor of field tI of this card to kXdWell
         set the borderColor of field tI of this card to kXdLine
         set the foregroundColor of field tI of this card to kXdInk
         set the hiliteColor of field tI of this card to kXdSelect
      else
         put the foregroundColor of field tI of this card into tColor
         if tColor is kUiInkSoft then
            set the foregroundColor of field tI of this card to kXdSoft
         else if tColor is kUiMuted then
            set the foregroundColor of field tI of this card to kXdMuted
         else if tColor is empty or tColor is kUiInk then
            set the foregroundColor of field tI of this card to kXdInk
         end if
      end if
   end repeat
   repeat with tI = 1 to the number of buttons of this card
      if the style of button tI of this card is "checkbox" then
         set the foregroundColor of button tI of this card to kXdInk
      end if
   end repeat
   -- the card behind the tabs: dark, a hairline, and no shadow
   set the backgroundColor of graphic "ui:panel" to kXdPanel
   set the foregroundColor of graphic "ui:panel" to kXdLine
   set the borderColor of graphic "ui:panel" to kXdLine
   try
      set the dropShadow of graphic "ui:panel" to empty
   catch tError
   end try
end xdDress

-- The status line, in the dark look's colours (the kit's are for a light
-- page).
command xdStatus pText, pKind
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      exit xdStatus
   end if
   uiStatus pText, pKind
   if pKind is "ok" then
      set the foregroundColor of field "uiStatus" to kXdOk
   else if pKind is "bad" then
      set the foregroundColor of field "uiStatus" to kXdBad
   else if pKind is "warn" then
      set the foregroundColor of field "uiStatus" to kXdWarn
   else
      set the foregroundColor of field "uiStatus" to kXdSoft
   end if
end xdStatus

-- Whether the xlsxt library answers. Everything that writes or reads asks
-- this first; the rest of the window works without it.
function xdLoaded
   local tError
   try
      get xlLibraryVersion()
   catch tError
      return false
   end try
   return true
end xdLoaded

-- A tab's heading and its paragraph of explanation, at the same place on
-- every tab.
private command xdHeading pTab, pTitle, pWords
   uiWrap pTab & ":h", pTitle, "32,106,928,130", 15
   set the textStyle of field (pTab & ":h") to "bold"
   set the foregroundColor of field (pTab & ":h") to kXdInk
   uiWrap pTab & ":exp", pWords, "32,132,928,176", 11
   set the foregroundColor of field (pTab & ":exp") to kXdSoft
end xdHeading

-- A checkbox that starts ticked or not. The kit's checkboxes are driven
-- from script (autoHilite off), so a click flips them in mouseUp.
private command xdCheck pName, pLabel, pRect, pOn
   uiCheckbox pName, pLabel, pRect
   -- a tick box is its tick and its words: no button frame around them
   set the showBorder of button pName to false
   set the shadow of button pName to false
   set the opaque of button pName to false
   set the hiliteBorder of button pName to false
   set the threeD of button pName to false
   set the foregroundColor of button pName to kXdInk
   set the hilite of button pName to pOn
end xdCheck

-- The Showcase: the sheet a scene writes, drawn as text on the left; the
-- chart it adds, drawn with graphics on the right, and under it the calls
-- the scene just made; a bar for how far it has got; a line for what it
-- found; and a button for each scene.
on xdBuildShow
   local tI, tLeft
   xdHeading "show", "Scene 1 of 4: " & item 1 of kXdSceneLabels, xdSceneWords(item 1 of kXdScenes)
   uiArea "show:grid", "32,184,560,448"
   set the vScrollbar of field "show:grid" to false
   set the dontWrap of field "show:grid" to true
   set the textSize of field "show:grid" to 12
   set the fixedLineHeight of field "show:grid" to true
   set the textHeight of field "show:grid" to 18
   set the hGrid of field "show:grid" to true
   set the vGrid of field "show:grid" to true
   uiGfx "show:chart", "576,184,928,392"
   set the roundRadius of graphic "show:chart" to 10
   set the filled of graphic "show:chart" to true
   set the backgroundColor of graphic "show:chart" to kXdWell
   set the lineSize of graphic "show:chart" to 1
   set the foregroundColor of graphic "show:chart" to kXdLine
   uiLabel "show:ctitle", empty, "586,190,918,208", 11
   set the textStyle of field "show:ctitle" to "bold"
   set the foregroundColor of field "show:ctitle" to kXdInk
   -- the pool, on the well: bars, slices and dots, then two lines, then
   -- the axis and a doughnut's hole on top of them
   repeat with tI = 1 to kXdPool
      xdPoolMake "pool:g" & tI
   end repeat
   xdPoolMake "pool:p1"
   xdPoolMake "pool:p2"
   xdPoolMake "pool:axis"
   xdPoolMake "pool:hole"
   uiLabel "show:story", empty, "576,398,928,448", 10
   set the textFont of field "show:story" to uiMonoFont()
   set the dontWrap of field "show:story" to true
   set the foregroundColor of field "show:story" to kXdSoft
   uiGfx "show:track", "32,456,928,462"
   set the style of graphic "show:track" to "rectangle"
   set the filled of graphic "show:track" to true
   set the lineSize of graphic "show:track" to 0
   set the backgroundColor of graphic "show:track" to kXdLine
   xdPoolMake "pool:bar"
   uiLabel "show:count", "Starting...", "32,466,928,486", 12
   set the foregroundColor of field "show:count" to kXdInk
   xdButton "show:all", "Play all four", "32,498,152,530", "plain"
   repeat with tI = 1 to the number of items of kXdSceneLabels
      put 160 + (tI - 1) * 194 into tLeft
      xdButton "show:s" & tI, item tI of kXdSceneLabels, tLeft & ",498," & (tLeft + 186) & ",530", "plain"
   end repeat
end xdBuildShow

-- One graphic of the pool: made hidden, somewhere inside the window; each
-- drawing gives it a shape, a place and colours.
private command xdPoolMake pName
   uiGfx pName, "40,40,41,41"
   set the visible of graphic pName to false
   set the uXdLit of graphic pName to false
end xdPoolMake

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
   xdButton "rd:open", "Open an .xlsx file...", "32,184,200,212", "plain"
   xdButton "rd:last", "Show the last one made", "208,184,388,212", "plain"
   uiWrap "rd:file", "No file open.", "400,188,928,208", 11
   set the foregroundColor of field "rd:file" to kXdSoft
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
   xdButton "about:run", "Run every check", "32,184,200,212", "fill"
   uiWrap "about:sum", "Not run yet.", "212,188,928,208", 11
   uiArea "about:log", "32,222,928,548"
end xdBuildAbout

-- ==========================================================================
-- Tabs.
-- ==========================================================================

on xdShowTab pKey
   local tI, tName, tShown, tKey, tPrefix
   if pKey is not among the items of kXdTabs then
      exit xdShowTab
   end if
   -- leaving the Showcase stops its scene and closes what the scene had open
   if pKey is not "show" and sShowScene is not empty then
      xdShowStop
      xdShowSay "Stopped when you left this tab. Click a scene to play it again.", "run"
   end if
   put pKey into sTab
   lock screen
   repeat with tI = 1 to the number of controls of this card
      put the short name of control tI of this card into tName
      if tName contains ":" then
         put char 1 to (offset(":", tName) - 1) of tName into tPrefix
         if tPrefix is "ui" or tPrefix is "hd" then
            put true into tShown
         else if tPrefix is "act" then
            -- the action row belongs to the tabs that make a workbook
            put (pKey is among the items of kXdMakers) into tShown
         else if tPrefix is "pool" then
            -- a graphic of the showcase's chart shows only while it is drawn
            put (pKey is "show" and the uXdLit of control tI of this card is true) into tShown
         else
            put (tPrefix is pKey) into tShown
         end if
         set the visible of control tI of this card to tShown
      end if
   end repeat
   repeat for each item tKey in kXdTabs
      set the uXdOn of button ("ui:" & tKey) to (tKey is pKey)
      xdPaint "ui:" & tKey, "rest"
   end repeat
   unlock screen
   if pKey is "rd" and sReadPath is empty and sLastPath is not empty then
      xdReadShow sLastPath, 1
   end if
end xdShowTab

-- ==========================================================================
-- Clicks and the pointer: a control's short name is "prefix:role".
-- ==========================================================================

on mouseUp
   local tName, tPrefix, tRole
   put the short name of the target into tName
   if tName contains ":" then
      put char 1 to (offset(":", tName) - 1) of tName into tPrefix
      put char (offset(":", tName) + 1) to -1 of tName into tRole
      if tPrefix is "ui" then
         if tRole is among the items of kXdTabs then
            xdShowTab tRole
         end if
      else if word 1 of the target is "button" and the style of the target is "checkbox" then
         set the hilite of the target to not the hilite of the target
      else if tPrefix is "act" then
         xdAction tRole
      else if tPrefix is "show" then
         xdShowClick tRole
      else if tPrefix is "rd" then
         xdReadClick tRole
      else if tName is "about:run" then
         xdRunChecks
      end if
      xdPressEnd
   else
      xdPressEnd
      pass mouseUp
   end if
end mouseUp

-- The pointer over a drawn button lightens it and a press darkens it: the
-- feedback a system button gives, which these paint themselves.
on mouseEnter
   if word 1 of the target is "button" and the style of the target is "transparent" then
      xdPaint the short name of the target, "over"
   end if
   pass mouseEnter
end mouseEnter

on mouseLeave
   if word 1 of the target is "button" and the style of the target is "transparent" then
      xdPaint the short name of the target, "rest"
   end if
   pass mouseLeave
end mouseLeave

on mouseDown
   if word 1 of the target is "button" and the style of the target is "transparent" then
      put the short name of the target into sPressed
      xdPaint sPressed, "down"
   end if
   pass mouseDown
end mouseDown

-- The button came up somewhere else: the press ends, and nothing is done.
on mouseRelease
   xdPressEnd
   pass mouseRelease
end mouseRelease

command xdPressEnd
   local tWas
   put sPressed into tWas
   put empty into sPressed
   if tWas is empty then
      exit xdPressEnd
   end if
   set the defaultStack to the short name of this stack
   if there is a button tWas and the mouseLoc is within the rect of button tWas then
      xdPaint tWas, "over"
   else
      xdPaint tWas, "rest"
   end if
end xdPressEnd

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
         set the foregroundColor of field "act:result" to kXdBad
      else if pKind is "ok" then
         set the foregroundColor of field "act:result" to kXdOk
      else
         set the foregroundColor of field "act:result" to kXdSoft
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
      xdStatus "Not made.", "bad"
      exit xdMake
   end if
   put xdSummary(sLastPath) into tSummary
   if tProblem is not empty then
      xdResult tProblem, "bad"
   else
      xdResult "Made and read back: " & tSummary, "ok"
   end if
   xdStatus "Workbook written to " & sLastPath, "ok"
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
         put "Nothing has been made yet: play a scene, or use Make this workbook on another tab." into field "rd:file"
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
      set the foregroundColor of field "rd:file" to kXdBad
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
   set the foregroundColor of field "rd:file" to kXdSoft
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
      set the foregroundColor of field "about:sum" to kXdOk
      xdStatus "Every check passed.", "ok"
   else
      put sCkPass && "passed," && sCkFail && "FAILED. The failing lines begin with FAIL." into field "about:sum"
      set the foregroundColor of field "about:sum" to kXdBad
      xdStatus sCkFail && "check(s) failed.", "bad"
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

-- ==========================================================================
-- The Showcase: four scenes of a few seconds each, played one frame at a
-- time on a timer. A scene is a function of its frame number that answers
-- true while it has more to show. Every frame is drawn under lock screen;
-- nothing waits, so the window answers clicks throughout. A scene that
-- writes a file reads it back at the end and says what it found.
-- ==========================================================================

function xdSceneWords pScene
   switch pScene
      case "sheet"
         return "Twelve months of sales are typed into a sheet, one cell at a time. Then the library writes" \
               & " them in three calls, colours the heading row, gives the money its format, freezes the" \
               & " heading, puts a chart beside the figures and closes the file. Last, the reader opens the" \
               & " file and every row is checked against what was typed."
      case "formulas"
         return "A formula is written as text, and Excel works it out when the file opens;" \
               & " xlSheetWriteFormulaValue also stores the answer, so a program that does not calculate" \
               & " still sees it. Today's date is a number with a date format, and true and false are cells" \
               & " of their own kind. The reader checks every formula, answer and kind."
      case "charts"
         return "xlWorkbookAddChart makes fifteen kinds of chart. Each is drawn here as it is added to one" \
               & " workbook, from the same six months of figures; Excel draws the real ones when it opens the" \
               & " file. At the end the file is checked for all fifteen charts, and its figures are read back."
      case "many"
         return "Ten thousand numbers, a hundred rows of a hundred, written two rows at a time with" \
               & " xlSheetWriteGrid and read back two rows at a time with xlReadGrid, so the window keeps" \
               & " moving while it works. The times are the time spent inside the library."
   end switch
   return empty
end xdSceneWords

private command xdShowClick pRole
   if pRole is "all" then
      xdShowPlay item 1 of kXdScenes, true
   else if pRole begins with "s" and char 2 to -1 of pRole is an integer then
      xdShowPlay item (char 2 to -1 of pRole) of kXdScenes, false
   end if
end xdShowClick

-- Starts a scene; pTour true plays the ones after it too.
command xdShowPlay pScene, pTour
   xdShowStop
   if pScene is not among the items of kXdScenes then
      exit xdShowPlay
   end if
   put pScene into sShowScene
   put 0 into sShowStep
   put (pTour is true) into sShowTour
   put empty into sShowState
   xdShowLight pScene
   send ("xdShowFrame" && sShowGen) to me in 20 milliseconds
end xdShowPlay

-- Stops whatever plays: a frame still on its way finds the count moved on
-- and ends itself, and the scene's workbook and reader are closed.
command xdShowStop
   local tLine
   add 1 to sShowGen
   put empty into sShowScene
   put false into sShowTour
   xdShowRelease
   repeat for each line tLine in the pendingMessages
      if word 1 of item 3 of tLine is among the words of "xdShowFrame xdShowNext xdShowTourEnd" then
         cancel item 1 of tLine
      end if
   end repeat
   xdShowLight empty
end xdShowStop

-- Closes what a scene has open. A workbook a scene did not finish is
-- discarded, so no half-written file is left behind.
command xdShowRelease
   local tError
   if sShowState["book"] is an integer and sShowState["book"] > 0 then
      try
         xlWorkbookDiscard sShowState["book"]
      catch tError
      end try
   end if
   if sShowState["reader"] is an integer and sShowState["reader"] > 0 then
      try
         xlReadClose sShowState["reader"]
      catch tError
      end try
   end if
   put empty into sShowState["book"]
   put empty into sShowState["reader"]
end xdShowRelease

-- The button of the scene playing is orange, and Play all four while the
-- tour plays; the others are not.
private command xdShowLight pScene
   local tI
   set the defaultStack to the short name of this stack
   if there is a button "show:all" then
      set the uXdOn of button "show:all" to (pScene is not empty and sShowTour is true)
      xdPaint "show:all", "rest"
   end if
   repeat with tI = 1 to the number of items of kXdScenes
      if there is a button ("show:s" & tI) then
         set the uXdOn of button ("show:s" & tI) to (item tI of kXdScenes is pScene)
         xdPaint "show:s" & tI, "rest"
      end if
   end repeat
end xdShowLight

-- One frame. It arrives by `send ... in`, so it pins the stack first: an
-- unqualified control resolves against the defaultStack (engine note 5.3).
on xdShowFrame pGen
   local tMore, tError
   if pGen is not sShowGen or sShowScene is empty then
      exit xdShowFrame
   end if
   set the defaultStack to the short name of this stack
   if there is no field "show:count" then
      exit xdShowFrame
   end if
   add 1 to sShowStep
   put false into tMore
   lock screen
   try
      switch sShowScene
         case "sheet"
            put xdSceneSheet(sShowStep) into tMore
            break
         case "formulas"
            put xdSceneFormulas(sShowStep) into tMore
            break
         case "charts"
            put xdSceneCharts(sShowStep) into tMore
            break
         case "many"
            put xdSceneMany(sShowStep) into tMore
            break
      end switch
   catch tError
      put false into tMore
      xdShowFail "The scene stopped: " & line 1 of tError
   end try
   unlock screen
   if pGen is not sShowGen then
      exit xdShowFrame
   end if
   if tMore is true then
      send ("xdShowFrame" && pGen) to me in xdFrameMs() milliseconds
   else
      xdShowEnded pGen
   end if
end xdShowFrame

-- A scene has ended: on the tour the next one follows after a pause, and
-- after the last the heading says the tour is over.
private command xdShowEnded pGen
   local tAt
   put xdSceneNumber(sShowScene) into tAt
   put empty into sShowScene
   xdShowRelease
   xdShowLight empty
   if sShowTour is not true then
      exit xdShowEnded
   end if
   if tAt > 0 and tAt < the number of items of kXdScenes then
      send ("xdShowNext" && pGen & comma & (tAt + 1)) to me in xdRestMs() milliseconds
   else
      send ("xdShowTourEnd" && pGen) to me in xdRestMs() milliseconds
   end if
end xdShowEnded

on xdShowNext pGen, pAt
   if pGen is not sShowGen or sShowTour is not true then
      exit xdShowNext
   end if
   set the defaultStack to the short name of this stack
   if there is no field "show:count" then
      exit xdShowNext
   end if
   xdShowPlay item pAt of kXdScenes, true
end xdShowNext

on xdShowTourEnd pGen
   if pGen is not sShowGen then
      exit xdShowTourEnd
   end if
   set the defaultStack to the short name of this stack
   put false into sShowTour
   if there is no field "show:h" then
      exit xdShowTourEnd
   end if
   put "That was the tour" into field "show:h"
   xdShowWords "Play any scene again with its button, or all four. The tabs above are the workbench: each" \
         & " makes a workbook of its own and reads it back, the Read tab opens any .xlsx (the last file a" \
         & " scene wrote is waiting there), and About runs every check in one click."
end xdShowTourEnd

private function xdSceneNumber pScene
   local tI
   repeat with tI = 1 to the number of items of kXdScenes
      if item tI of kXdScenes is pScene then
         return tI
      end if
   end repeat
   return 0
end xdSceneNumber

-- The frame time and the pause between scenes. A drive sets the stack's
-- uXdFast to play the scenes as fast as the engine goes.
function xdFrameMs
   if the uXdFast of this stack is true then
      return 1
   end if
   return kXdFrameMs
end xdFrameMs

function xdRestMs
   if the uXdFast of this stack is true then
      return 1
   end if
   return kXdRestMs
end xdRestMs

-- ---- what every scene shares ---------------------------------------------

-- The start of a scene: its sheet's size, column stops and letters, and a
-- clean slate.
private command xdShowBegin pRows, pColumns, pStops, pLetters
   local tAt
   put xdLoaded() into sShowState["live"]
   put pRows into sShowState["rows"]
   put pColumns into sShowState["cols"]
   put pStops into sShowState["stops"]
   put pLetters into sShowState["letters"]
   put 1 into sShowState["top"]
   put 0 into sShowState["same"]
   put 0 into sShowState["differ"]
   set the uXdShowDone of this stack to empty
   put xdSceneNumber(sShowScene) into tAt
   put "Scene " & tAt & " of " & (the number of items of kXdScenes) & ": " & (item tAt of kXdSceneLabels) \
         into field "show:h"
   xdShowWords xdSceneWords(sShowScene)
   put empty into field "show:story"
   put empty into field "show:ctitle"
   xdShowChart "none", empty, empty, 0
   xdShowBar 0
   xdShowGrid
   if sShowState["live"] then
      xlSetTempFolder the temporary folder
   end if
end xdShowBegin

-- The heading's paragraph, fitted to its height with its top kept.
private command xdShowWords pWords
   local tTop, tFH
   put the top of field "show:exp" into tTop
   put pWords into field "show:exp"
   put the formattedHeight of field "show:exp" into tFH
   if tFH > 0 then
      set the height of field "show:exp" to tFH
      set the top of field "show:exp" to tTop
   end if
end xdShowWords

-- The line under the bar: what the scene is doing, then what it found.
private command xdShowSay pText, pKind
   put pText into field "show:count"
   if pKind is "ok" then
      set the foregroundColor of field "show:count" to kXdOk
   else if pKind is "bad" then
      set the foregroundColor of field "show:count" to kXdBad
   else
      set the foregroundColor of field "show:count" to kXdInk
   end if
end xdShowSay

-- The calls a scene just made, the last three of them.
private command xdShowStory pLine
   local tText
   put field "show:story" into tText
   if tText is empty then
      put pLine into tText
   else
      put return & pLine after tText
   end if
   repeat while the number of lines of tText > 3
      delete line 1 of tText
   end repeat
   put tText into field "show:story"
end xdShowStory

private command xdShowBar pFraction
   local tTrack, tLeft, tRight
   put the rect of graphic "show:track" into tTrack
   put item 1 of tTrack into tLeft
   put tLeft + round(((item 3 of tTrack) - tLeft) * max(0, min(1, pFraction))) into tRight
   if tRight <= tLeft then
      xdPoolShow "pool:bar", false
      exit xdShowBar
   end if
   set the style of graphic "pool:bar" to "rectangle"
   set the filled of graphic "pool:bar" to true
   set the lineSize of graphic "pool:bar" to 0
   set the blendLevel of graphic "pool:bar" to 0
   set the backgroundColor of graphic "pool:bar" to kXdAccent
   set the rect of graphic "pool:bar" to tLeft & comma & (item 2 of tTrack) & comma & tRight & comma & (item 4 of tTrack)
   xdPoolShow "pool:bar", true
end xdShowBar

private command xdPoolShow pName, pOn
   set the uXdLit of graphic pName to (pOn is true)
   set the visible of graphic pName to (pOn is true and sTab is "show")
end xdPoolShow

-- How a scene ends: the line under the bar in green or red, and the
-- stack's uXdShowDone ("<scene> ok" or "<scene> bad") for a drive to read.
private command xdShowDone pOk, pWords
   if pOk is true then
      xdShowSay pWords, "ok"
      set the uXdShowDone of this stack to sShowScene && "ok"
   else
      xdShowSay pWords, "bad"
      set the uXdShowDone of this stack to sShowScene && "bad"
   end if
   xdShowBar 1
end xdShowDone

private command xdShowFail pWords
   xdShowRelease
   xdShowDone false, pWords
end xdShowFail

function xdShowPath pName
   return xdTempFile("xlsxt-show-" & pName & ".xlsx")
end xdShowPath

-- Closes the scene's workbook, which writes the file, and makes it the
-- last file made (the Read tab and Save then use it).
private function xdShowClose pPath
   local tBook, tRefused, tFirst
   put sShowState["book"] into tBook
   put xlWorkbookErrorCount(tBook) into tRefused
   put xlWorkbookFirstError(tBook) into tFirst
   put empty into sShowState["book"]
   if not xlWorkbookClose(tBook) then
      xdShowFail "The file could not be written: " & xlLastError()
      return false
   end if
   put pPath into sShowState["path"]
   put pPath into sLastPath
   put sShowScene into sLastWhat
   put empty into sReadPath
   if tRefused > 0 then
      xdShowFail "Written, but " & tRefused & " call(s) were refused. The first: " & tFirst
      return false
   end if
   xdShowStory "xlWorkbookClose(book): " & xdThousands(the number of bytes of URL ("binfile:" & pPath)) & " bytes"
   return true
end xdShowClose

-- The end of a scene that wrote and read: every row compared, or the plain
-- truth that the library was not there.
private command xdShowVerdict pCount, pWhat, pMore
   local tFile
   if sShowState["reader"] is an integer and sShowState["reader"] > 0 then
      xlReadClose sShowState["reader"]
   end if
   put empty into sShowState["reader"]
   if sShowState["live"] is not true then
      xdShowDone false, "xlsxt is not loaded, so nothing was written or read. Install the extension" \
            & " (org.openxtalk.library.xlsxt) and open this stack again."
      exit xdShowVerdict
   end if
   put xdFileName(sShowState["path"]) & ", " & xdThousands(the number of bytes of URL ("binfile:" & sShowState["path"])) \
         & " bytes" into tFile
   if sShowState["differ"] is 0 and sShowState["same"] is pCount then
      xdShowDone true, "Read back from " & tFile & ": all " & pCount && pWhat & " match" & pMore & "."
   else
      xdShowDone false, "Read back from " & tFile & ": " & (pCount - sShowState["same"]) & " of " & pCount \
            && pWhat & " are not what was written."
   end if
end xdShowVerdict

-- A row read back: its number turns green, or red.
private command xdShowMark pRow, pSame
   if pSame is true then
      put kXdOk into sShowState["mark"][pRow]
      add 1 to sShowState["same"]
   else
      put kXdBad into sShowState["mark"][pRow]
      add 1 to sShowState["differ"]
   end if
end xdShowMark

-- A cell typed: it shows in orange until the next one is typed.
private command xdShowType pRow, pColumn, pText
   xdShowUntype
   put pText into sShowState["c"][pRow][pColumn]
   put kXdAccent into sShowState["ink"][pRow][pColumn]
   put pRow & comma & pColumn into sShowState["typed"]
end xdShowType

private command xdShowUntype
   local tWas
   put sShowState["typed"] into tWas
   if tWas is not empty then
      put empty into sShowState["ink"][item 1 of tWas][item 2 of tWas]
   end if
   put empty into sShowState["typed"]
end xdShowUntype

-- The scene's sheet, drawn as text: the column letters, then each row
-- with its number in front. A row read back has its number in green (or
-- red); the heading row, once the scene has given it its format, is bold
-- and orange.
private command xdShowGrid
   local tText, tRow, tColumn, tTop, tLast, tLine, tMark, tInk
   put max(1, sShowState["top"]) into tTop
   put min(sShowState["rows"], tTop + kXdGridLines - 2) into tLast
   if sShowState["letters"] is not empty then
      put sShowState["letters"] into tText
   else
      repeat with tColumn = 1 to sShowState["cols"]
         put tab & numToChar(64 + tColumn) after tText
      end repeat
   end if
   repeat with tRow = tTop to tLast
      put return & tRow after tText
      repeat with tColumn = 1 to sShowState["cols"]
         put tab & sShowState["c"][tRow][tColumn] after tText
      end repeat
   end repeat
   set the tabStops of field "show:grid" to sShowState["stops"]
   put tText into field "show:grid"
   set the itemDelimiter to tab
   set the textColor of line 1 of field "show:grid" to kXdMuted
   put 1 into tLine
   repeat with tRow = tTop to tLast
      add 1 to tLine
      put sShowState["mark"][tRow] into tMark
      if tMark is empty then
         put kXdMuted into tMark
      end if
      set the textColor of item 1 of line tLine of field "show:grid" to tMark
      if tRow is sShowState["head"] then
         set the textStyle of line tLine of field "show:grid" to "bold"
         set the textColor of item 2 to -1 of line tLine of field "show:grid" to kXdAccent
      end if
      repeat with tColumn = 1 to sShowState["cols"]
         put sShowState["ink"][tRow][tColumn] into tInk
         if tInk is not empty then
            set the textColor of item (tColumn + 1) of line tLine of field "show:grid" to tInk
         end if
      end repeat
   end repeat
end xdShowGrid

-- ---- the chart, drawn with the pool ----------------------------------------

-- Draws a chart of kind pKind (a name xlWorkbookAddChart takes) in the
-- well, from the series pFirst and pSecond (comma lists; pSecond may be
-- empty), grown to pGrow of 100. "none" clears it. A graphic of the pool
-- that the kind does not use is hidden.
private command xdShowChart pKind, pFirst, pSecond, pGrow
   local tWell, tL, tT, tR, tB, tGrow, tI, tName
   put empty into sShowState["used"]
   put the rect of graphic "show:chart" into tWell
   put (item 1 of tWell) + 22 into tL
   put (item 2 of tWell) + 34 into tT
   put (item 3 of tWell) - 16 into tR
   put (item 4 of tWell) - 14 into tB
   put max(0, min(100, pGrow)) / 100 into tGrow
   if pKind is "pie" or pKind is "doughnut" then
      xdChartPie pKind, pFirst, tGrow, tL, tT, tR, tB
   else if pKind begins with "radar" then
      xdChartRadar pKind, pFirst, pSecond, tGrow, tL, tT, tR, tB
   else if pKind begins with "scatter" then
      xdChartAxis tL, tT, tR, tB
      xdChartScatter pKind, pFirst, pSecond, tGrow, tL, tT, tR, tB
   else if pKind begins with "bar" then
      xdChartAxis tL, tT, tR, tB
      xdChartBars pKind, pFirst, pSecond, tGrow, tL, tT, tR, tB
   else if pKind begins with "column" then
      xdChartAxis tL, tT, tR, tB
      xdChartColumns pKind, pFirst, pSecond, tGrow, tL, tT, tR, tB
   else if pKind is "line" or pKind begins with "area" then
      xdChartAxis tL, tT, tR, tB
      xdChartLines pKind, pFirst, pSecond, tGrow, tL, tT, tR, tB
   end if
   repeat with tI = 1 to kXdPool
      xdPoolShow "pool:g" & tI, (sShowState["used"]["pool:g" & tI] is true)
   end repeat
   repeat for each item tName in "pool:p1,pool:p2,pool:axis,pool:hole"
      xdPoolShow tName, (sShowState["used"][tName] is true)
   end repeat
end xdShowChart

private command xdChartAxis pL, pT, pR, pB
   xdPoolLine "pool:axis", xdPt(pL, pT) & return & xdPt(pL, pB) & return & xdPt(pR, pB), kXdLine, empty, 0
   set the lineSize of graphic "pool:axis" to 1
end xdChartAxis

-- Columns side by side ("column"), one on the other ("column stacked"), or
-- one on the other as shares of the whole ("column percent").
private command xdChartColumns pKind, pFirst, pSecond, pGrow, pL, pT, pR, pB
   local tN, tBand, tMax, tI, tA, tOther, tX, tHigh, tHigh2, tSum, tWide
   put the number of items of pFirst into tN
   put (pR - pL) / tN into tBand
   if pKind is "column" then
      put max(xdMaxOf(pFirst), xdMaxOf(pSecond)) into tMax
   else
      put xdMaxOfSums(pFirst, pSecond) into tMax
   end if
   repeat with tI = 1 to tN
      put item tI of pFirst into tA
      put item tI of pSecond into tOther
      if tOther is empty then
         put 0 into tOther
      end if
      put pL + (tI - 1) * tBand into tX
      if pKind is "column percent" then
         put tA + tOther into tSum
         if tSum <= 0 then
            put 1 into tSum
         end if
         put (pB - pT) * tA / tSum * pGrow into tHigh
         put (pB - pT) * tOther / tSum * pGrow into tHigh2
      else
         put (pB - pT) * tA / tMax * pGrow into tHigh
         put (pB - pT) * tOther / tMax * pGrow into tHigh2
      end if
      if pKind is "column" and pSecond is not empty then
         put tBand * 0.34 into tWide
         xdPoolBox "pool:g" & (2 * tI - 1), tX + tBand * 0.14, pB - tHigh, tX + tBand * 0.14 + tWide, pB, kXdAccent
         xdPoolBox "pool:g" & (2 * tI), tX + tBand * 0.52, pB - tHigh2, tX + tBand * 0.52 + tWide, pB, kXdSecond
      else if pKind is "column" then
         xdPoolBox "pool:g" & tI, tX + tBand * 0.18, pB - tHigh, tX + tBand * 0.82, pB, kXdAccent
      else
         xdPoolBox "pool:g" & (2 * tI - 1), tX + tBand * 0.2, pB - tHigh, tX + tBand * 0.8, pB, kXdAccent
         xdPoolBox "pool:g" & (2 * tI), tX + tBand * 0.2, pB - tHigh - tHigh2, tX + tBand * 0.8, pB - tHigh, kXdSecond
      end if
   end repeat
end xdChartColumns

-- Bars across, side by side ("bar") or end to end ("bar stacked").
private command xdChartBars pKind, pFirst, pSecond, pGrow, pL, pT, pR, pB
   local tN, tBand, tMax, tI, tA, tOther, tY, tLong, tLong2, tThick
   put the number of items of pFirst into tN
   put (pB - pT) / tN into tBand
   if pKind is "bar" then
      put max(xdMaxOf(pFirst), xdMaxOf(pSecond)) into tMax
   else
      put xdMaxOfSums(pFirst, pSecond) into tMax
   end if
   repeat with tI = 1 to tN
      put item tI of pFirst into tA
      put item tI of pSecond into tOther
      if tOther is empty then
         put 0 into tOther
      end if
      put pT + (tI - 1) * tBand into tY
      put (pR - pL) * tA / tMax * pGrow into tLong
      put (pR - pL) * tOther / tMax * pGrow into tLong2
      if pKind is "bar" and pSecond is not empty then
         put tBand * 0.34 into tThick
         xdPoolBox "pool:g" & (2 * tI - 1), pL, tY + tBand * 0.14, pL + tLong, tY + tBand * 0.14 + tThick, kXdAccent
         xdPoolBox "pool:g" & (2 * tI), pL, tY + tBand * 0.52, pL + tLong2, tY + tBand * 0.52 + tThick, kXdSecond
      else if pKind is "bar" then
         xdPoolBox "pool:g" & tI, pL, tY + tBand * 0.2, pL + tLong, tY + tBand * 0.8, kXdAccent
      else
         xdPoolBox "pool:g" & (2 * tI - 1), pL, tY + tBand * 0.2, pL + tLong, tY + tBand * 0.8, kXdAccent
         xdPoolBox "pool:g" & (2 * tI), pL + tLong, tY + tBand * 0.2, pL + tLong + tLong2, tY + tBand * 0.8, kXdSecond
      end if
   end repeat
end xdChartBars

-- Lines ("line"), shaded areas over each other ("area"), or the second
-- area on top of the first ("area stacked").
private command xdChartLines pKind, pFirst, pSecond, pGrow, pL, pT, pR, pB
   local tN, tBand, tMax, tI, tA, tOther, tX, tFirstLine, tSecondLine, tBack, tStart, tEnd
   put the number of items of pFirst into tN
   put (pR - pL) / tN into tBand
   if pKind is "area stacked" then
      put xdMaxOfSums(pFirst, pSecond) into tMax
   else
      put max(xdMaxOf(pFirst), xdMaxOf(pSecond)) into tMax
   end if
   repeat with tI = 1 to tN
      put item tI of pFirst into tA
      put item tI of pSecond into tOther
      if tOther is empty then
         put 0 into tOther
      end if
      if pKind is "area stacked" then
         put tA + tOther into tOther
      end if
      put pL + (tI - 0.5) * tBand into tX
      put xdPt(tX, pB - (pB - pT) * tA / tMax * pGrow) & return after tFirstLine
      put xdPt(tX, pB - (pB - pT) * tOther / tMax * pGrow) & return after tSecondLine
      put xdPt(tX, pB - (pB - pT) * tA / tMax * pGrow) & return before tBack
   end repeat
   delete the last char of tFirstLine
   delete the last char of tSecondLine
   put xdPt(pL + 0.5 * tBand, pB) into tStart
   put xdPt(pL + (tN - 0.5) * tBand, pB) into tEnd
   if pKind is "line" then
      xdPoolLine "pool:p1", tFirstLine, kXdAccent, empty, 0
      if pSecond is not empty then
         xdPoolLine "pool:p2", tSecondLine, kXdSecond, empty, 0
      end if
   else if pKind is "area" then
      xdPoolLine "pool:p1", tStart & return & tFirstLine & return & tEnd & return & tStart, kXdAccent, kXdAccent, 30
      if pSecond is not empty then
         xdPoolLine "pool:p2", tStart & return & tSecondLine & return & tEnd & return & tStart, kXdSecond, kXdSecond, 45
      end if
   else
      xdPoolLine "pool:p1", tStart & return & tFirstLine & return & tEnd & return & tStart, kXdAccent, kXdAccent, 15
      xdPoolLine "pool:p2", tSecondLine & return & tBack & line 1 of tSecondLine, kXdSecond, kXdSecond, 15
   end if
end xdChartLines

-- Points of the second series against the first ("scatter"), joined in
-- order across ("scatter lines"), or by a smooth curve ("scatter smooth").
private command xdChartScatter pKind, pFirst, pSecond, pGrow, pL, pT, pR, pB
   local tN, tLowX, tHighX, tLowY, tHighY, tI, tX, tY, tShown, tPoints
   put the number of items of pFirst into tN
   put xdMinOf(pFirst) into tLowX
   put max(xdMaxOf(pFirst), tLowX + 1) into tHighX
   put xdMinOf(pSecond) into tLowY
   put max(xdMaxOf(pSecond), tLowY + 1) into tHighY
   put round(tN * pGrow) into tShown
   repeat with tI = 1 to tShown
      put pL + 12 + (pR - pL - 24) * ((item tI of pFirst) - tLowX) / (tHighX - tLowX) into tX
      put pB - 12 - (pB - pT - 24) * ((item tI of pSecond) - tLowY) / (tHighY - tLowY) into tY
      xdPoolDot "pool:g" & tI, tX, tY, 5, kXdAccent
      put xdPt(tX, tY) & return after tPoints
   end repeat
   if pKind is "scatter" or tShown < 2 then
      exit xdChartScatter
   end if
   delete the last char of tPoints
   sort lines of tPoints numeric by item 1 of each
   if pKind is "scatter smooth" then
      put xdSmooth(tPoints) into tPoints
   end if
   xdPoolLine "pool:p1", tPoints, kXdSecond, empty, 0
end xdChartScatter

-- A web of the categories, and each series as a shape on it; "radar
-- markers" marks the first series' points.
private command xdChartRadar pKind, pFirst, pSecond, pGrow, pL, pT, pR, pB
   local tN, tCx, tCy, tRadius, tMax, tI, tAngle, tOuter, tInner, tFirstLine, tSecondLine, tReach, tX, tY
   put the number of items of pFirst into tN
   put (pL + pR) / 2 into tCx
   put (pT + pB) / 2 into tCy
   put min(pR - pL, pB - pT) / 2 - 4 into tRadius
   put max(xdMaxOf(pFirst), xdMaxOf(pSecond)) into tMax
   repeat with tI = 1 to tN
      put (-90 + (tI - 1) * 360 / tN) * pi / 180 into tAngle
      put xdPt(tCx + tRadius * cos(tAngle), tCy + tRadius * sin(tAngle)) & return after tOuter
      put xdPt(tCx + tRadius / 2 * cos(tAngle), tCy + tRadius / 2 * sin(tAngle)) & return after tInner
      put tRadius * (item tI of pFirst) / tMax * pGrow into tReach
      put tCx + tReach * cos(tAngle) into tX
      put tCy + tReach * sin(tAngle) into tY
      put xdPt(tX, tY) & return after tFirstLine
      if pKind is "radar markers" then
         xdPoolDot "pool:g" & (tI + 2), tX, tY, 4, kXdAccent
      end if
      if pSecond is not empty then
         put tRadius * (item tI of pSecond) / tMax * pGrow into tReach
         put xdPt(tCx + tReach * cos(tAngle), tCy + tReach * sin(tAngle)) & return after tSecondLine
      end if
   end repeat
   -- each shape closes on its first point
   put line 1 of tOuter after tOuter
   put line 1 of tInner after tInner
   put line 1 of tFirstLine after tFirstLine
   xdPoolLine "pool:g1", tOuter, kXdLine, empty, 0
   xdPoolLine "pool:g2", tInner, kXdLine, empty, 0
   set the lineSize of graphic "pool:g1" to 1
   set the lineSize of graphic "pool:g2" to 1
   xdPoolLine "pool:p1", tFirstLine, kXdAccent, kXdAccent, 55
   if tSecondLine is not empty then
      put line 1 of tSecondLine after tSecondLine
      xdPoolLine "pool:p2", tSecondLine, kXdSecond, kXdSecond, 55
   end if
end xdChartRadar

-- Slices from twelve o'clock, clockwise, as far as pGrow has got; a
-- doughnut has a hole in the middle.
private command xdChartPie pKind, pFirst, pGrow, pL, pT, pR, pB
   local tCx, tCy, tRadius, tSum, tValue, tI, tFrom, tSweep, tArc
   put (pL + pR) / 2 into tCx
   put (pT + pB) / 2 into tCy
   put min(pR - pL, pB - pT) / 2 - 2 into tRadius
   put 0 into tSum
   repeat for each item tValue in pFirst
      add tValue to tSum
   end repeat
   if tSum <= 0 then
      put 1 into tSum
   end if
   put 360 * pGrow into tSweep
   put 0 into tFrom
   repeat with tI = 1 to the number of items of pFirst
      put 360 * (item tI of pFirst) / tSum into tArc
      if tFrom + tArc > tSweep then
         put tSweep - tFrom into tArc
      end if
      if tArc >= 1 then
         xdPoolArc "pool:g" & tI, tCx - tRadius, tCy - tRadius, tCx + tRadius, tCy + tRadius, \
               xdSliceColor(tI), 90 - tFrom - tArc, tArc
      end if
      add 360 * (item tI of pFirst) / tSum to tFrom
   end repeat
   if pKind is "doughnut" then
      xdPoolDot "pool:hole", tCx, tCy, tRadius * 0.55, kXdWell
   end if
end xdChartPie

private command xdPoolBox pName, pL, pT, pR, pB, pColor
   if abs(pR - pL) < 1 or abs(pB - pT) < 1 then
      exit xdPoolBox
   end if
   set the style of graphic pName to "rectangle"
   set the filled of graphic pName to true
   set the lineSize of graphic pName to 0
   set the blendLevel of graphic pName to 0
   set the backgroundColor of graphic pName to pColor
   set the rect of graphic pName to xdRect(pL, pT, pR, pB)
   put true into sShowState["used"][pName]
end xdPoolBox

private command xdPoolArc pName, pL, pT, pR, pB, pColor, pStart, pArc
   set the style of graphic pName to "oval"
   set the filled of graphic pName to true
   set the lineSize of graphic pName to 2
   set the foregroundColor of graphic pName to kXdWell
   set the blendLevel of graphic pName to 0
   set the backgroundColor of graphic pName to pColor
   set the rect of graphic pName to xdRect(pL, pT, pR, pB)
   set the startAngle of graphic pName to (round(pStart) + 720) mod 360
   set the arcAngle of graphic pName to max(1, min(360, round(pArc)))
   put true into sShowState["used"][pName]
end xdPoolArc

private command xdPoolDot pName, pX, pY, pRadius, pColor
   set the style of graphic pName to "oval"
   set the filled of graphic pName to true
   set the lineSize of graphic pName to 0
   set the blendLevel of graphic pName to 0
   set the backgroundColor of graphic pName to pColor
   set the startAngle of graphic pName to 0
   set the arcAngle of graphic pName to 360
   set the rect of graphic pName to xdRect(pX - pRadius, pY - pRadius, pX + pRadius, pY + pRadius)
   put true into sShowState["used"][pName]
end xdPoolDot

-- A line through points (one "x,y" a line), and filled under it when pFill
-- names a colour; pBlend makes it see-through, 0 to 100.
private command xdPoolLine pName, pPoints, pColor, pFill, pBlend
   set the style of graphic pName to "polygon"
   set the lineSize of graphic pName to 2
   set the foregroundColor of graphic pName to pColor
   if pFill is empty then
      set the filled of graphic pName to false
   else
      set the filled of graphic pName to true
      set the backgroundColor of graphic pName to pFill
   end if
   set the blendLevel of graphic pName to pBlend
   set the points of graphic pName to pPoints
   put true into sShowState["used"][pName]
end xdPoolLine

private function xdRect pL, pT, pR, pB
   local tLeft, tTop, tRight, tBottom
   put round(min(pL, pR)) into tLeft
   put round(min(pT, pB)) into tTop
   put max(round(max(pL, pR)), tLeft + 1) into tRight
   put max(round(max(pT, pB)), tTop + 1) into tBottom
   return tLeft & comma & tTop & comma & tRight & comma & tBottom
end xdRect

private function xdPt pX, pY
   return round(pX) & comma & round(pY)
end xdPt

private function xdSliceColor pIndex
   set the itemDelimiter to "|"
   return item (((pIndex - 1) mod (the number of items of kXdSlices)) + 1) of kXdSlices
end xdSliceColor

private function xdMaxOf pList
   local tMax, tValue
   put 0 into tMax
   repeat for each item tValue in pList
      put max(tMax, tValue) into tMax
   end repeat
   if tMax <= 0 then
      return 1
   end if
   return tMax
end xdMaxOf

private function xdMinOf pList
   local tMin, tValue
   put item 1 of pList into tMin
   repeat for each item tValue in pList
      put min(tMin, tValue) into tMin
   end repeat
   if tMin is empty then
      return 0
   end if
   return tMin
end xdMinOf

private function xdMaxOfSums pFirst, pSecond
   local tMax, tI, tOther
   put 0 into tMax
   repeat with tI = 1 to the number of items of pFirst
      put item tI of pSecond into tOther
      if tOther is empty then
         put 0 into tOther
      end if
      put max(tMax, (item tI of pFirst) + tOther) into tMax
   end repeat
   if tMax <= 0 then
      return 1
   end if
   return tMax
end xdMaxOfSums

-- More points along a smooth curve (Catmull-Rom) through the given ones.
private function xdSmooth pPoints
   local tN, tI, tStep, tOut, tBefore, tFrom, tTo, tAfter, tT
   put the number of lines of pPoints into tN
   if tN < 3 then
      return pPoints
   end if
   repeat with tI = 1 to tN - 1
      put line max(1, tI - 1) of pPoints into tBefore
      put line tI of pPoints into tFrom
      put line tI + 1 of pPoints into tTo
      put line min(tN, tI + 2) of pPoints into tAfter
      repeat with tStep = 0 to 5
         put tStep / 6 into tT
         put xdPt(xdCatmull(item 1 of tBefore, item 1 of tFrom, item 1 of tTo, item 1 of tAfter, tT), \
               xdCatmull(item 2 of tBefore, item 2 of tFrom, item 2 of tTo, item 2 of tAfter, tT)) & return after tOut
      end repeat
   end repeat
   put line tN of pPoints after tOut
   return tOut
end xdSmooth

private function xdCatmull pBefore, pFrom, pTo, pAfter, pT
   return 0.5 * ((2 * pFrom) + (pTo - pBefore) * pT + (2 * pBefore - 5 * pFrom + 4 * pTo - pAfter) * pT * pT \
         + (3 * pFrom - pBefore - 3 * pTo + pAfter) * pT * pT * pT)
end xdCatmull

-- ---- numbers as people write them -------------------------------------------

function xdThousands pNumber
   local tWhole, tOut
   put round(pNumber) into tWhole
   repeat while the number of chars of tWhole > 3
      put "," & char -3 to -1 of tWhole before tOut
      delete char -3 to -1 of tWhole
   end repeat
   return tWhole & tOut
end xdThousands

function xdMoney pNumber
   local tFixed
   put format("%.2f", pNumber) into tFixed
   return "$" & xdThousands(char 1 to -4 of tFixed) & char -3 to -1 of tFixed
end xdMoney

-- A time the way a person reads it: milliseconds under a second.
function xdSeconds pMilliseconds
   if pMilliseconds < 1000 then
      return round(pMilliseconds) && "ms"
   end if
   return format("%.2f", pMilliseconds / 1000) && "s"
end xdSeconds

-- Today, as "yyyy-mm-dd", and as its three numbers.
function xdTodayItems
   local tNow
   put the seconds into tNow
   convert tNow to dateItems
   return item 1 of tNow & comma & item 2 of tNow & comma & item 3 of tNow
end xdTodayItems

function xdToday
   local tYMD
   put xdTodayItems() into tYMD
   return format("%04d-%02d-%02d", item 1 of tYMD, item 2 of tYMD, item 3 of tYMD)
end xdToday

-- The cell at pRow, pColumn of a table of tabs and returns.
function xdCellOf pTable, pRow, pColumn
   set the itemDelimiter to tab
   return item pColumn of line pRow of pTable
end xdCellOf

-- ---- scene 1: a sheet fills itself ------------------------------------------
--
-- Frames 2-53 type the 52 cells, 62 writes the file, 63-82 grow its chart,
-- 83 opens it with the reader, 84-109 check a row every second frame, and
-- 110 says what was found.

function xdSceneSheet pStep
   local tRow, tAt, tTable, tRevenue, tPath, tBook, tSheet, tHead, tMoney, tChart, tLeft, tRight, tGot, tSame
   local tColumn, tReader, tKept
   if pStep is 1 then
      xdShowBegin 13, 4, "40,150,230,330,440", empty
      put "January,February,March,April,May,June,July,August,September,October,November,December" \
            into sShowState["months"]
      put "12,7,15,9,14,11,16,13,10,18,17,21" into sShowState["units"]
      put "9.5,10.25,8.75,11,9.75,10.5,9.25,10,11.5,9,10.75,9.5" into sShowState["prices"]
      put "Month" & tab & "Units" & tab & "Price" & tab & "Revenue" into tTable
      repeat with tRow = 1 to 12
         put (item tRow of sShowState["units"]) * (item tRow of sShowState["prices"]) into tRevenue
         put tRevenue & comma after tLeft
         put return & item tRow of sShowState["months"] & tab & item tRow of sShowState["units"] & tab \
               & item tRow of sShowState["prices"] & tab & tRevenue after tTable
      end repeat
      delete the last char of tLeft
      put tLeft into sShowState["revenue"]
      put tTable into sShowState["table"]
      xdShowSay "Typing twelve months of sales...", "run"
      return true
   end if
   if pStep <= 53 then
      put pStep - 1 into tAt
      put ((tAt - 1) div 4) + 1 into tRow
      put ((tAt - 1) mod 4) + 1 into tColumn
      xdShowType tRow, tColumn, xdCellOf(sShowState["table"], tRow, tColumn)
      xdShowGrid
      xdShowBar tAt / 52 * 0.4
      return true
   end if
   if pStep is 54 then
      xdShowUntype
      xdShowGrid
      xdShowSay "Writing them takes three calls, then the look and a chart.", "run"
      return true
   end if
   if pStep < 62 then
      return true
   end if
   if pStep is 62 then
      -- the look the file gets, shown on the sheet here as well
      put 1 into sShowState["head"]
      repeat with tRow = 2 to 13
         put xdMoney(xdCellOf(sShowState["table"], tRow, 3)) into sShowState["c"][tRow][3]
         put xdMoney(xdCellOf(sShowState["table"], tRow, 4)) into sShowState["c"][tRow][4]
      end repeat
      xdShowGrid
      xdShowBar 0.5
      if sShowState["live"] is not true then
         xdShowStory "-- xlsxt is not loaded: nothing is written"
         return true
      end if
      put xdShowPath("sheet") into tPath
      put xlWorkbookNew(tPath) into tBook
      if tBook is 0 then
         xdShowFail "The workbook could not be started: " & xlLastError()
         return false
      end if
      put tBook into sShowState["book"]
      put xlWorkbookAddSheet(tBook, "Sales") into tSheet
      put xlWorkbookAddFormat(tBook) into tHead
      xlFormatSetBold tHead, true
      xlFormatSetFontColor tHead, "white"
      xlFormatSetBackgroundColor tHead, "#E8732C"
      xlFormatSetAlign tHead, "center"
      put xlWorkbookAddFormat(tBook) into tMoney
      xlFormatSetNumberFormat tMoney, "$#,##0.00"
      put empty into tLeft
      repeat with tRow = 1 to 12
         put item tRow of sShowState["months"] & tab & item tRow of sShowState["units"] & return after tLeft
         put item tRow of sShowState["prices"] & tab & item tRow of sShowState["revenue"] & return after tRight
      end repeat
      delete the last char of tLeft
      delete the last char of tRight
      put xlSheetWriteGrid(tSheet, 1, 1, line 1 of sShowState["table"], "text", tHead) into tGot
      put xlSheetWriteGrid(tSheet, 2, 1, tLeft, "numbers", 0) into tGot
      xdShowStory "xlSheetWriteGrid(sheet, 2, 1, months, ..) = " & tGot
      put xlSheetWriteGrid(tSheet, 2, 3, tRight, "numbers", tMoney) into tGot
      xdShowStory "xlSheetWriteGrid(sheet, 2, 3, money, ..) = " & tGot
      xlSheetFreeze tSheet, 1, 0
      xlSheetAutofilter tSheet, 1, 1, 13, 4
      xlSheetSetColumns tSheet, 1, 1, 13, 0
      xlSheetSetColumns tSheet, 2, 4, 11, 0
      put xlWorkbookAddChart(tBook, "column") into tChart
      get xlChartAddSeries(tChart, xlRangeFormula("Sales", 2, 1, 13, 1), xlRangeFormula("Sales", 2, 4, 13, 4))
      xlChartSeriesSetName tChart, 1, "Revenue"
      xlChartSeriesSetColor tChart, 1, "#E8732C"
      xlChartSetTitle tChart, "Revenue by month"
      xlChartSetLegend tChart, "none"
      xlSheetInsertChart tSheet, 2, 6, tChart, 1.2, 1.2
      return xdShowClose(tPath)
   end if
   if pStep <= 82 then
      if pStep is 63 then
         put "Revenue by month: a column chart at F2" into field "show:ctitle"
      end if
      xdShowChart "column", sShowState["revenue"], empty, (pStep - 62) * 5
      xdShowBar 0.5 + (pStep - 62) / 20 * 0.2
      return true
   end if
   if pStep is 83 then
      if sShowState["live"] is true then
         put xlReadOpen(sShowState["path"]) into tReader
         if tReader is 0 then
            xdShowFail "The reader refused the file: " & xlLastError()
            return false
         end if
         put tReader into sShowState["reader"]
         get xlReadLoad(tReader, 1)
         xdShowStory "xlReadOpen(file), then xlReadCell for each cell"
      end if
      xdShowSay "Reading the file back, row by row...", "run"
      return true
   end if
   if pStep <= 109 then
      if (pStep - 84) mod 2 is 0 and sShowState["live"] is true then
         put ((pStep - 84) div 2) + 1 into tRow
         put true into tSame
         repeat with tColumn = 1 to 4
            if xlReadCell(sShowState["reader"], 1, tRow, tColumn) is not xdCellOf(sShowState["table"], tRow, tColumn) then
               put false into tSame
            end if
         end repeat
         xdShowMark tRow, tSame
         xdShowGrid
      end if
      xdShowBar 0.7 + (pStep - 83) / 26 * 0.3
      return true
   end if
   put false into tKept
   if sShowState["live"] is true then
      put (xlReadCellFormat(sShowState["reader"], 1, 2, 3) is "$#,##0.00") into tKept
   end if
   if tKept then
      xdShowVerdict 13, "rows", ", and the money kept its format, $#,##0.00"
   else
      xdShowVerdict 13, "rows", empty
   end if
   return false
end xdSceneSheet

-- ---- scene 2: formulas and dates ---------------------------------------------
--
-- Frames 2-17 type the budget and the labels, 18-57 work out the four
-- formulas (ten frames each), 58-69 the date and the true-or-false cell,
-- 70 writes the file, 71-86 grow its pie, 87 opens it and checks the
-- table, 88-99 check the rest a row every second frame, 100 the verdict.

function xdSceneFormulas pStep
   local tAt, tRow, tFrame, tSpec, tLine, tPath, tBook, tSheet, tHead, tMoney, tDate, tGot, tChart
   local tReader, tSame, tYMD, tI
   if pStep is 1 then
      xdShowBegin 12, 3, "36,190,330", empty
      put "Item" & tab & "Amount" & return & "Rent" & tab & "1200" & return & "Food" & tab & "452.5" \
            & return & "Transport" & tab & "121.5" & return & "Fun" & tab & "80" into sShowState["table"]
      -- each formula row: its label, the formula, and the answer stored with it
      put "Total|=SUM(B2:B5)|1854" & return & "Average|=AVERAGE(B2:B5)|463.5" & return \
            & "Largest|=MAX(B2:B5)|1200" & return & "Left of 2,500|=2500-B7|646" into sShowState["formulas"]
      put xdToday() into sShowState["today"]
      -- what is typed, in order: the table, then the labels of rows 7 to 12
      repeat with tRow = 1 to 5
         repeat with tI = 1 to 2
            put tRow & tab & tI & tab & xdCellOf(sShowState["table"], tRow, tI) & return after tLine
         end repeat
      end repeat
      set the itemDelimiter to "|"
      repeat with tRow = 1 to 4
         put (6 + tRow) & tab & 1 & tab & item 1 of line tRow of sShowState["formulas"] & return after tLine
      end repeat
      set the itemDelimiter to comma
      put "11" & tab & "1" & tab & "Today" & return & "12" & tab & "1" & tab & "Paid" after tLine
      put tLine into sShowState["queue"]
      xdShowSay "Typing a month's budget...", "run"
      return true
   end if
   if pStep <= 17 then
      put line (pStep - 1) of sShowState["queue"] into tLine
      xdShowType xdCellOf(tLine, 1, 1), xdCellOf(tLine, 1, 2), xdCellOf(tLine, 1, 3)
      xdShowGrid
      xdShowBar (pStep - 1) / 16 * 0.2
      return true
   end if
   if pStep <= 57 then
      put ((pStep - 18) div 10) + 1 into tAt
      put (pStep - 18) mod 10 into tFrame
      put 6 + tAt into tRow
      put line tAt of sShowState["formulas"] into tSpec
      set the itemDelimiter to "|"
      if tFrame is 0 then
         xdShowUntype
         put item 2 of tSpec into sShowState["c"][tRow][2]
         put kXdAccent into sShowState["ink"][tRow][2]
         xdShowSay "Working out " & item 2 of tSpec & "...", "run"
      else if tFrame is 6 then
         put xdMoney(item 3 of tSpec) into sShowState["c"][tRow][2]
         put empty into sShowState["ink"][tRow][2]
         put item 2 of tSpec into sShowState["c"][tRow][3]
         put kXdMuted into sShowState["ink"][tRow][3]
      end if
      set the itemDelimiter to comma
      xdShowGrid
      xdShowBar 0.2 + (pStep - 17) / 40 * 0.25
      return true
   end if
   if pStep <= 69 then
      if pStep <= 63 then
         put 11 into tRow
      else
         put 12 into tRow
      end if
      put (pStep - 58) mod 6 into tFrame
      if tFrame is 0 and tRow is 11 then
         put sShowState["today"] into sShowState["c"][11][2]
         put kXdAccent into sShowState["ink"][11][2]
         xdShowSay "Today, as a date...", "run"
      else if tFrame is 0 then
         put "TRUE" into sShowState["c"][12][2]
         put kXdAccent into sShowState["ink"][12][2]
         xdShowSay "And a cell that is true or false...", "run"
      else if tFrame is 3 then
         put empty into sShowState["ink"][tRow][2]
         put kXdMuted into sShowState["ink"][tRow][3]
         if tRow is 11 then
            put "a date: yyyy-mm-dd" into sShowState["c"][11][3]
         else
            put "true or false" into sShowState["c"][12][3]
         end if
      end if
      xdShowGrid
      xdShowBar 0.45 + (pStep - 57) / 12 * 0.05
      return true
   end if
   if pStep is 70 then
      put 1 into sShowState["head"]
      repeat with tRow = 2 to 5
         put xdMoney(xdCellOf(sShowState["table"], tRow, 2)) into sShowState["c"][tRow][2]
      end repeat
      xdShowGrid
      xdShowBar 0.5
      if sShowState["live"] is not true then
         xdShowStory "-- xlsxt is not loaded: nothing is written"
         return true
      end if
      put xdShowPath("formulas") into tPath
      put xlWorkbookNew(tPath) into tBook
      if tBook is 0 then
         xdShowFail "The workbook could not be started: " & xlLastError()
         return false
      end if
      put tBook into sShowState["book"]
      put xlWorkbookAddSheet(tBook, "Budget") into tSheet
      put xlWorkbookAddFormat(tBook) into tHead
      xlFormatSetBold tHead, true
      xlFormatSetFontColor tHead, "white"
      xlFormatSetBackgroundColor tHead, "#E8732C"
      put xlWorkbookAddFormat(tBook) into tMoney
      xlFormatSetNumberFormat tMoney, "$#,##0.00"
      put xlWorkbookAddFormat(tBook) into tDate
      xlFormatSetNumberFormat tDate, "yyyy-mm-dd"
      get xlSheetWriteGrid(tSheet, 1, 1, line 1 of sShowState["table"], "text", tHead)
      repeat with tRow = 2 to 5
         xlSheetWriteText tSheet, tRow, 1, xdCellOf(sShowState["table"], tRow, 1), 0
         xlSheetWriteNumber tSheet, tRow, 2, xdCellOf(sShowState["table"], tRow, 2), tMoney
      end repeat
      set the itemDelimiter to "|"
      repeat with tAt = 1 to 4
         put line tAt of sShowState["formulas"] into tSpec
         xlSheetWriteText tSheet, 6 + tAt, 1, item 1 of tSpec, 0
         xlSheetWriteFormulaValue tSheet, 6 + tAt, 2, item 2 of tSpec, item 3 of tSpec, tMoney
      end repeat
      set the itemDelimiter to comma
      xdShowStory "xlSheetWriteFormulaValue(.., " & quote & "=2500-B7" & quote & ", 646, ..)"
      put xdTodayItems() into tYMD
      xlSheetWriteText tSheet, 11, 1, "Today", 0
      xlSheetWriteDate tSheet, 11, 2, xlDateToSerial(item 1 of tYMD, item 2 of tYMD, item 3 of tYMD, 0, 0, 0), tDate
      xdShowStory "xlSheetWriteDate(sheet, 11, 2, today, date)"
      xlSheetWriteText tSheet, 12, 1, "Paid", 0
      xlSheetWriteBoolean tSheet, 12, 2, true, 0
      xlSheetSetColumns tSheet, 1, 1, 16, 0
      xlSheetSetColumns tSheet, 2, 2, 14, 0
      put xlWorkbookAddChart(tBook, "pie") into tChart
      get xlChartAddSeries(tChart, xlRangeFormula("Budget", 2, 1, 5, 1), xlRangeFormula("Budget", 2, 2, 5, 2))
      xlChartSetTitle tChart, "Where the money goes"
      xlSheetInsertChart tSheet, 2, 4, tChart, 1, 1
      return xdShowClose(tPath)
   end if
   if pStep <= 86 then
      if pStep is 71 then
         put "Where the money goes: a pie chart at D2" into field "show:ctitle"
      end if
      xdShowChart "pie", "1200,452.5,121.5,80", empty, (pStep - 70) * 6.25
      xdShowBar 0.5 + (pStep - 70) / 16 * 0.2
      return true
   end if
   if pStep is 87 then
      if sShowState["live"] is true then
         put xlReadOpen(sShowState["path"]) into tReader
         if tReader is 0 then
            xdShowFail "The reader refused the file: " & xlLastError()
            return false
         end if
         put tReader into sShowState["reader"]
         get xlReadLoad(tReader, 1)
         -- the table: its words and its numbers
         repeat with tRow = 1 to 5
            xdShowMark tRow, (xlReadCell(tReader, 1, tRow, 1) is xdCellOf(sShowState["table"], tRow, 1) \
                  and xlReadCell(tReader, 1, tRow, 2) is xdCellOf(sShowState["table"], tRow, 2))
         end repeat
         xdShowStory "xlReadCellFormula, xlReadCellNumber, xlReadCellKind"
      end if
      xdShowGrid
      xdShowSay "Reading the file back: each formula, its answer and each kind...", "run"
      return true
   end if
   if pStep <= 99 then
      if (pStep - 88) mod 2 is 0 and sShowState["live"] is true then
         put sShowState["reader"] into tReader
         put 7 + ((pStep - 88) div 2) into tRow
         if tRow <= 10 then
            put line (tRow - 6) of sShowState["formulas"] into tSpec
            set the itemDelimiter to "|"
            put (xlReadCellFormula(tReader, 1, tRow, 2) is item 2 of tSpec \
                  and xlReadCellNumber(tReader, 1, tRow, 2) is item 3 of tSpec) into tSame
            set the itemDelimiter to comma
         else if tRow is 11 then
            put (xlReadCellKind(tReader, 1, 11, 2) is "date" and xlReadCell(tReader, 1, 11, 2) is sShowState["today"]) into tSame
         else
            put (xlReadCellKind(tReader, 1, 12, 2) is "boolean" and xlReadCell(tReader, 1, 12, 2) is "true") into tSame
         end if
         xdShowMark tRow, tSame
         xdShowGrid
      end if
      xdShowBar 0.7 + (pStep - 87) / 12 * 0.3
      return true
   end if
   xdShowVerdict 11, "rows", ": the formulas with their answers, the date and the true-or-false cell"
   return false
end xdSceneFormulas

-- ---- scene 3: every kind of chart ---------------------------------------------
--
-- Frame 1 writes the figures; then each of the fifteen kinds has twelve
-- frames (2-181): it is added to the workbook on its first, and drawn
-- growing, then held. 182 closes the file, 183 checks it.

function xdSceneCharts pStep
   local tRow, tTable, tPath, tBook, tSheet, tHead, tGot, tWhich, tFrame, tKind, tData, tFound, tI, tReader
   local tSame, tMonths
   if pStep is 1 then
      xdShowBegin 7, 3, "36,130,224", empty
      put "Jan,Feb,Mar,Apr,May,Jun" into tMonths
      put "12,7,15,9,14,11" into sShowState["north"]
      put "8,10,6,12,9,13" into sShowState["south"]
      put "Month" & tab & "North" & tab & "South" into tTable
      repeat with tRow = 1 to 6
         put return & item tRow of tMonths & tab & item tRow of sShowState["north"] & tab \
               & item tRow of sShowState["south"] after tTable
      end repeat
      put tTable into sShowState["table"]
      repeat with tRow = 1 to 7
         repeat with tI = 1 to 3
            put xdCellOf(tTable, tRow, tI) into sShowState["c"][tRow][tI]
         end repeat
      end repeat
      put 1 into sShowState["head"]
      xdShowGrid
      if sShowState["live"] is true then
         put xdShowPath("charts") into tPath
         put tPath into sShowState["path"]
         put xlWorkbookNew(tPath) into tBook
         if tBook is 0 then
            xdShowFail "The workbook could not be started: " & xlLastError()
            return false
         end if
         put tBook into sShowState["book"]
         put xlWorkbookAddSheet(tBook, "Charts") into tSheet
         put tSheet into sShowState["sheet"]
         put xlWorkbookAddFormat(tBook) into tHead
         xlFormatSetBold tHead, true
         get xlSheetWriteGrid(tSheet, 1, 1, line 1 of tTable, "text", tHead)
         put xlSheetWriteGrid(tSheet, 2, 1, line 2 to -1 of tTable, "numbers", 0) into tGot
         xdShowStory "xlSheetWriteGrid(sheet, 2, 1, figures, ..) = " & tGot
      else
         xdShowStory "-- xlsxt is not loaded: nothing is written"
      end if
      xdShowSay "Fifteen kinds of chart, all in one workbook...", "run"
      return true
   end if
   if pStep <= 181 then
      put ((pStep - 2) div 12) + 1 into tWhich
      put (pStep - 2) mod 12 into tFrame
      put item tWhich of kXdChartKinds into tKind
      if tFrame is 0 then
         put tKind & "   (" & tWhich & " of 15)" into field "show:ctitle"
         if sShowState["live"] is true then
            xdShowAddChart tKind, tWhich
         end if
      end if
      if tKind is "pie" or tKind is "doughnut" then
         xdShowChart tKind, sShowState["north"], empty, min(100, (tFrame + 1) * 12.5)
      else
         xdShowChart tKind, sShowState["north"], sShowState["south"], min(100, (tFrame + 1) * 12.5)
      end if
      xdShowBar (pStep - 1) / 180 * 0.85
      if pStep is 181 then
         xdShowSay "Closing the workbook: fifteen charts go into the file...", "run"
      end if
      return true
   end if
   if pStep is 182 then
      if sShowState["live"] is true then
         return xdShowClose(sShowState["path"])
      end if
      return true
   end if
   -- 183: the file holds every chart, and its figures read back the same
   if sShowState["live"] is true then
      put URL ("binfile:" & sShowState["path"]) into tData
      put 0 into tFound
      repeat with tI = 1 to 15
         if offset("xl/charts/chart" & tI & ".xml", tData) > 0 then
            add 1 to tFound
         end if
      end repeat
      put xlReadOpen(sShowState["path"]) into tReader
      if tReader is 0 then
         xdShowFail "The reader refused the file: " & xlLastError()
         return false
      end if
      put tReader into sShowState["reader"]
      get xlReadLoad(tReader, 1)
      put xlReadGrid(tReader, 1, 1, 1, 7, 3) into tGot
      repeat with tRow = 1 to 7
         put (line tRow of tGot is line tRow of sShowState["table"]) into tSame
         xdShowMark tRow, tSame
      end repeat
      xdShowGrid
      if tFound is 15 then
         xdShowVerdict 7, "rows", ", and all fifteen charts are in it (xl/charts/chart1.xml to chart15.xml)"
      else
         xdShowVerdict 7, "rows", empty
         xdShowDone false, "The file holds " & tFound & " of the fifteen charts."
      end if
   else
      xdShowVerdict 7, "rows", empty
   end if
   return false
end xdSceneCharts

-- One chart of the scene, made, given its series and placed on the sheet,
-- three to a row.
private command xdShowAddChart pKind, pWhich
   local tChart, tCats, tNorth, tSouth
   put xlRangeFormula("Charts", 2, 1, 7, 1) into tCats
   put xlRangeFormula("Charts", 2, 2, 7, 2) into tNorth
   put xlRangeFormula("Charts", 2, 3, 7, 3) into tSouth
   put xlWorkbookAddChart(sShowState["book"], pKind) into tChart
   if pKind begins with "scatter" then
      get xlChartAddSeries(tChart, tNorth, tSouth)
      xlChartSeriesSetName tChart, 1, "South against North"
      xlChartSeriesSetColor tChart, 1, kXdAccent
   else if pKind is "pie" or pKind is "doughnut" then
      get xlChartAddSeries(tChart, tCats, tNorth)
      xlChartSeriesSetName tChart, 1, "North"
   else
      get xlChartAddSeries(tChart, tCats, tNorth)
      xlChartSeriesSetName tChart, 1, "North"
      xlChartSeriesSetColor tChart, 1, kXdAccent
      get xlChartAddSeries(tChart, tCats, tSouth)
      xlChartSeriesSetName tChart, 2, "South"
      xlChartSeriesSetColor tChart, 2, kXdSecond
   end if
   xlChartSetTitle tChart, pKind
   xlSheetInsertChart sShowState["sheet"], 1 + ((pWhich - 1) div 3) * 16, 5 + ((pWhich - 1) mod 3) * 8, tChart, 1, 1
   xdShowStory "xlWorkbookAddChart(book, " & quote & pKind & quote & ")"
end xdShowAddChart

-- ---- scene 4: ten thousand cells ---------------------------------------------
--
-- Frame 1 makes the numbers; 2-51 write two rows of a hundred each; 52
-- closes the file; 53 opens it; 54-103 read two rows each and compare;
-- 104 says how long the library took and what it found.

function xdSceneMany pStep
   local tRow, tColumn, tLine, tPath, tBook, tGot, tStart, tReader, tSame, tFile
   if pStep is 1 then
      xdShowBegin 100, 7, "44,116,188,260,332,404,440", \
            tab & "A" & tab & "B" & tab & "C" & tab & "D" & tab & "E" & tab & "..." & tab & "CV"
      repeat with tRow = 1 to 100
         put empty into tLine
         repeat with tColumn = 1 to 100
            put tab & ((tRow * 7919 + tColumn * 104729) mod 100000) after tLine
         end repeat
         delete char 1 of tLine
         put tLine into sShowState["src"][tRow]
      end repeat
      put 0 into sShowState["writeMs"]
      put 0 into sShowState["readMs"]
      put 0 into sShowState["written"]
      if sShowState["live"] is true then
         put xdShowPath("many") into tPath
         put tPath into sShowState["path"]
         put xlWorkbookNew(tPath) into tBook
         if tBook is 0 then
            xdShowFail "The workbook could not be started: " & xlLastError()
            return false
         end if
         put tBook into sShowState["book"]
         put xlWorkbookAddSheet(tBook, "Ten thousand") into sShowState["sheet"]
      else
         xdShowStory "-- xlsxt is not loaded: nothing is written"
      end if
      xdShowSay "Writing ten thousand cells, two rows a frame...", "run"
      return true
   end if
   if pStep <= 51 then
      put (pStep - 2) * 2 + 1 into tRow
      if sShowState["live"] is true then
         put the milliseconds into tStart
         put xlSheetWriteGrid(sShowState["sheet"], tRow, 1, sShowState["src"][tRow] & return & sShowState["src"][tRow + 1], \
               "numbers", 0) into tGot
         add the milliseconds - tStart to sShowState["writeMs"]
         add tGot to sShowState["written"]
      end if
      xdShowManyRows tRow
      xdShowManyRows tRow + 1
      put max(1, tRow + 1 - (kXdGridLines - 2)) into sShowState["top"]
      xdShowGrid
      xdShowManyChart
      xdShowBar (tRow + 1) / 100 * 0.45
      xdShowSay "Writing: " & xdThousands((tRow + 1) * 100) & " of 10,000 cells", "run"
      if pStep is 51 then
         xdShowStory "xlSheetWriteGrid x 50 = " & xdThousands(sShowState["written"]) & " cells"
         xdShowSay "Closing: the library writes the sheet and zips the file...", "run"
      end if
      return true
   end if
   if pStep is 52 then
      if sShowState["live"] is true then
         put the milliseconds into tStart
         if not xdShowClose(sShowState["path"]) then
            return false
         end if
         add the milliseconds - tStart to sShowState["writeMs"]
      end if
      xdShowBar 0.5
      return true
   end if
   if pStep is 53 then
      if sShowState["live"] is true then
         put the milliseconds into tStart
         put xlReadOpen(sShowState["path"]) into tReader
         if tReader is 0 then
            xdShowFail "The reader refused the file: " & xlLastError()
            return false
         end if
         put tReader into sShowState["reader"]
         get xlReadLoad(tReader, 1)
         add the milliseconds - tStart to sShowState["readMs"]
         xdShowStory "xlReadOpen, xlReadLoad, then xlReadGrid x 50"
      end if
      xdShowSay "Reading them back, two rows a frame...", "run"
      return true
   end if
   if pStep <= 103 then
      put (pStep - 54) * 2 + 1 into tRow
      if sShowState["live"] is true then
         put the milliseconds into tStart
         put xlReadGrid(sShowState["reader"], 1, tRow, 1, tRow + 1, 100) into tGot
         add the milliseconds - tStart to sShowState["readMs"]
         put (line 1 of tGot is sShowState["src"][tRow]) into tSame
         xdShowMark tRow, tSame
         put (line 2 of tGot is sShowState["src"][tRow + 1]) into tSame
         xdShowMark tRow + 1, tSame
      end if
      put max(1, tRow + 1 - (kXdGridLines - 2)) into sShowState["top"]
      xdShowGrid
      xdShowManyChart
      xdShowBar 0.5 + (tRow + 1) / 100 * 0.5
      xdShowSay "Reading: " & xdThousands((tRow + 1) * 100) & " of 10,000 cells", "run"
      return true
   end if
   if sShowState["reader"] is an integer and sShowState["reader"] > 0 then
      xlReadClose sShowState["reader"]
   end if
   put empty into sShowState["reader"]
   if sShowState["live"] is not true then
      xdShowVerdict 100, "rows", empty
   else if sShowState["same"] is 100 and sShowState["written"] is 10000 then
      put xdFileName(sShowState["path"]) & ", " & xdThousands(the number of bytes of URL ("binfile:" & sShowState["path"])) \
            & " bytes" into tFile
      xdShowDone true, "10,000 cells written in " & xdSeconds(sShowState["writeMs"]) & " and read back in " \
            & xdSeconds(sShowState["readMs"]) & " (time inside the library), every one the same. " & tFile & "."
   else
      xdShowDone false, "Of 100 rows, " & sShowState["differ"] & " came back different; " \
            & xdThousands(sShowState["written"]) & " cells were written."
   end if
   return false
end xdSceneMany

-- Column A of the rows on the scene's sheet, drawn as an area that moves
-- as the rows go by.
private command xdShowManyChart
   local tRow, tValues, tLast
   put min(100, sShowState["top"] + kXdGridLines - 2) into tLast
   repeat with tRow = sShowState["top"] to tLast
      if sShowState["c"][tRow][1] is not empty then
         put sShowState["c"][tRow][1] & comma after tValues
      end if
   end repeat
   delete the last char of tValues
   if the number of items of tValues < 2 then
      exit xdShowManyChart
   end if
   put "Column A of rows " & sShowState["top"] & " to " & (sShowState["top"] + (the number of items of tValues) - 1) \
         into field "show:ctitle"
   xdShowChart "area", tValues, empty, 100
end xdShowManyChart

-- A row of the ten thousand on the scene's sheet: its first five cells,
-- then the hundredth (column CV).
private command xdShowManyRows pRow
   local tColumn
   repeat with tColumn = 1 to 5
      put xdCellOf(sShowState["src"][pRow], 1, tColumn) into sShowState["c"][pRow][tColumn]
   end repeat
   put "..." into sShowState["c"][pRow][6]
   put xdCellOf(sShowState["src"][pRow], 1, 100) into sShowState["c"][pRow][7]
end xdShowManyRows

