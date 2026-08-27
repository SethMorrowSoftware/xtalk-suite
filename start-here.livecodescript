script "SuiteStartHere"

-- start-here.livecodescript - the suite's front door. Download the repo,
-- open THIS file in OpenXTalk (File > Open Stack), and you get a clickable
-- directory of every sample, demo and harness stack, listed by the relative
-- path it has in this repository. Click a path to read what it is and what
-- it needs; Open (or double-click) launches it in place.
--
-- HOW IT RESOLVES PATHS: a script-only stack opened from disk knows its own
-- file path (`the filename of this stack`), and this file lives at the
-- REPOSITORY ROOT - so every entry is simply root + the relative path shown.
-- Nothing is copied or installed; the stacks open from where the download
-- put them. If the status line reports missing files, the download is
-- incomplete or this file was moved out of the repo root.
--
-- WHAT OPENING DOES (the paste ritual, automated): a script-only file is
-- TEXT - on this engine, going to the file does not produce a built
-- window (maintainer-observed on OXT, 2026-08-14). What has worked on
-- every engine pass is the documented ritual: make a stack, set its
-- script, open it. So that is exactly what Open does: read the file,
-- CREATE an invisible host stack named by the file's own `script "..."`
-- line, SET its script (a compile error surfaces right here, with the
-- demo's name on it), GO to it so openStack builds the window, nudge
-- openStack once if the card arrived empty, then reveal the finished
-- window. There is nothing to wire up before that: a stack that needs a
-- script library CARRIES it, embedded verbatim by tools/sync-demo-embeds.py,
-- so not one registry row declares a helper today - and
-- tools/check-launcher-registry.py now refuses a row that names a helper its
-- own file embeds, so the field cannot quietly go stale again. The helper
-- mechanism stays anyway, because one demo is on record as unable to embed
-- its library (the reason is in that tool's NOT_EMBEDDED table, and it is a
-- behaviour change to a path with no engine pass, not an oversight) - a
-- helper named in a row gets the same treatment minus the window: created
-- invisibly, then `start using` BY NAME - nothing ever depends on loading a
-- stack FILE. Relaunching raises the running window; a closed one reopens
-- with its script refreshed from disk (never yanked under a running stack).
--
-- WHAT IT CANNOT DO FOR YOU: install the native extensions. Each entry
-- names what it needs (Tools > Extension Manager ids are in each member's
-- README); a demo opened without its extension fails CLOSED with a red
-- status line naming the missing piece - that is the family contract, not
-- a launcher bug.
--
-- WHY THE NUDGE IS SAFE: the openStack nudge fires only when the opened
-- card has ZERO controls - and an unbuilt stack has run nothing: no
-- timers to double-arm, no session to re-open. Every demo's build is
-- idempotent and version-guarded on top of that.
--
-- HONESTY (the suite convention): this launcher is verified statically
-- and needs an OXT pass - but its launch mechanism is no longer a bet:
-- create-stack + set-script + openStack is the exact ritual every
-- recorded engine pass has performed by hand.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here. Since
-- 2026-08-27 the launcher wears the full card look the demos wear - the
-- directory and the detail card are panels, the list groups by member,
-- and the two traits a reader needs before clicking (holds the torrent
-- session; self-contained) are pills instead of prose buried in a note.
--
-- THE TORRENT SESSION CARD (2026-08-27). The family's sharpest trap is
-- ONE torrent session per process: a second SESSION stack fails its
-- btStartSession while the first is open. Every session-holding stack in
-- this registry has a closeStack teardown that calls btStopSession (all
-- thirteen verified), so CLOSING the open one frees the session - which
-- is exactly what the card's button does: it finds the open
-- session-holding stacks by name and closes them, letting each run its
-- own teardown. What it cannot fix, and says so: a stack that CRASHED
-- past its teardown leaks the session inside the shim, and only an OXT
-- restart clears that (the .lcb exposes no session discovery on
-- purpose - handles are capabilities, not an enumerable table).
--
-- THE BOOT SELF-CHECK (2026-08-27): this stack is the fourteenth adopter
-- of tools/demo-selfcheck.livecodescript, so opening it produces a
-- citable record in the log (controls exist, the registry parses, the
-- files resolve, the session index built) instead of a human judgement.

-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kSlUiVersion = "start-here-2"

-- ---- script-local state (declared at top) ------------------------------------
local sLineEntry        -- array: list line number -> registry line ("" = header/spacer)
local sHeaderLines      -- comma list: list line numbers that are group headers
local sSelected         -- the currently shown registry line (empty = none)
local sSessName         -- array: SESSION relpath -> the stack name its file declares

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
-- ==== SUITE UI KIT v2 END ====

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   slBuild
   slSessIndex
   slProbe
   slSessRefresh
   -- the self-check runs LAST: it reads the state the lines above establish
   slScRun
end openStack

on mouseUp
   switch the short name of the target
      case "slList"
         slShowDetail the hilitedLine of field "slList"
         break
      case "slOpen"
         slOpenSelected
         break
      case "slCopyPath"
         slCopyPath
         break
      case "slHelp"
         slHelp
         break
      case "slSessClose"
         slCloseSessionStacks
         break
      default
         pass mouseUp
   end switch
end mouseUp

on mouseDoubleUp
   if the short name of the target is "slList" then
      slShowDetail the hilitedLine of field "slList"
      slOpenSelected
   else
      pass mouseDoubleUp
   end if
end mouseDoubleUp

-- ---- self-building UI (idempotent; rebuilds on a version bump) ----------------
command slBuild
   if the uSlUiVersion of this stack is kSlUiVersion and there is a field "slList" then
      exit slBuild
   end if
   slClearGeneratedUI
   lock screen
   uiChrome "xTalk Suite - start here", 1200, 640
   -- LEFT: the directory card - every runnable stack, grouped by member
   uiPanel "slListCard", "16,58,676,584"
   uiSection "slDirSec", "Every runnable stack, by repo path", "28,68,664,88"
   uiTable "slList", "28,100,664,544", empty
   uiCap "slListCap", "Group names are headers. Click a path for its card; double-click (or Open) launches it in place.", "28,552,664,578"
   -- RIGHT, TOP: what the selected stack is, wants, and how to launch it
   uiPanel "slCard", "692,58,1184,458"
   uiWrap "slName", "Click a stack on the left.", "708,72,1168,96", 14
   set the textStyle of field "slName" to "bold"
   -- the two traits worth knowing BEFORE clicking Open, as pills; built
   -- unconditionally (the boot self-check asserts every control exists),
   -- shown per selection
   uiPill "slPillSession", "holds the torrent session", "708,102,878,122", "wait"
   uiPill "slPillSelf", "self-contained", "888,102,996,122", "ok"
   slPillShow "slPillSession", false
   slPillShow "slPillSelf", false
   uiInput "slPath", "708,130,1088,154"
   set the lockText of field "slPath" to true
   set the traversalOn of field "slPath" to false
   set the backgroundColor of field "slPath" to kUiCodeBg
   set the borderColor of field "slPath" to kUiCodeLine
   set the dontWrap of field "slPath" to true
   uiButton "slCopyPath", "Copy", "1096,128,1168,156"
   uiCap "slNeedsCap", "Needs:", "708,164,1168,180"
   uiWrap "slNeeds", empty, "708,182,1168,240", 11
   uiWrap "slDesc", empty, "708,248,1168,330", 11
   uiWrap "slNote", empty, "708,338,1168,404", 11
   set the foregroundColor of field "slNote" to kUiWarn
   uiButton "slOpen", "Open this stack", "708,414,880,446"
   uiButton "slHelp", "Setup help", "896,414,1010,446"
   set the tooltip of button "slOpen" to "Launch the selected stack from where the download put it (double-clicking its path does the same)."
   set the tooltip of button "slHelp" to "The three-step setup, in plain language."
   set the tooltip of field "slPath" to "The file's location inside the downloaded folder - click Copy to copy it."
   -- RIGHT, BOTTOM: the one-torrent-session card + the boot/self-check log
   uiPanel "slSessCard", "692,470,1184,584"
   uiSection "slSessSec", "The one torrent session", "708,478,1168,498"
   uiArea "slLog", "708,506,1000,572"
   uiButton "slSessClose", "Close torrent stacks", "1012,506,1176,538"
   set the tooltip of button "slSessClose" to "Close every open session-holding stack; each runs its own teardown, freeing the session."
   uiCap "slSessCap", "Each closed stack runs its own teardown, freeing the session for the next launch.", "1012,544,1176,580"
   uiFooter \
         "ONE torrent session per process: the card above closes open" \
         & " session-holding stacks when the next launch needs the session;" \
         & " a stack that crashed past its teardown still needs an OXT" \
         & " restart. Extensions install via Tools > Extension Manager -" \
         & " each member's README has the id. This launcher is verified" \
         & " statically; needs an OXT pass.", \
         "16,598,1184,636"
   slFillList
   set the uSlUiVersion of this stack to kSlUiVersion
   unlock screen
end slBuild

-- Show or hide one pill (a uiPill is a graphic + a field pair).
command slPillShow pName, pOn
   if there is a graphic (pName & "Bg") then
      set the visible of graphic (pName & "Bg") to pOn
   end if
   if there is a field pName then
      set the visible of field pName to pOn
   end if
end slPillShow

command slClearGeneratedUI
   local tI
   lock screen
   repeat with tI = the number of fields of this card down to 1
      if the short name of field tI of this card begins with "sl" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      if the short name of button tI of this card begins with "sl" then
         delete button tI of this card
      end if
   end repeat
   repeat with tI = the number of graphics of this card down to 1
      if the short name of graphic tI of this card begins with "sl" then
         delete graphic tI of this card
      end if
   end repeat
   unlock screen
end slClearGeneratedUI

-- ---- the registry ------------------------------------------------------------
-- One line per runnable stack: relpath|helpers|needs|note|description.
-- Helpers are repo-relative files put in use BEFORE opening (comma list).
-- "SESSION" in the note marks the one-torrent-session-per-process stacks.
-- Kept by hand ON PURPOSE (a glob cannot write descriptions);
-- tools/check-launcher-registry.py fails the build when this list and the
-- tree disagree, so it cannot rot.
function slRegistry
   local tR
   put "sodiumxt/examples/sodium-demo.livecodescript||the sodiumxt extension (org.openxtalk.library.sodium)||A tabbed tour of the crypto surface: authenticated boxes, signatures, hashing, file crypto, deterministic identities from a passphrase, and key rollover." & return into tR
   put "coinxt/examples/coinxt-demo.livecodescript||the coinxt extension (org.openxtalk.library.coin); sodiumxt only for Generate new|This is a demo, not a wallet - never type a mnemonic that guards real funds. Self-contained: carries coinxt.|From a mnemonic to addresses to a SIGNED Bitcoin and Ethereum transaction, every step decoded on screen." & return after tR
   put "enetxt/examples/enet-lan-chat.livecodescript||the enetxt extension (org.openxtalk.library.enet)|Two machines on a LAN (or two stacks on one machine). Allow the engine through the HOST machine's firewall - inbound UDP 27099. Self-contained: carries enet-helpers.|Reliable-UDP LAN chat: one machine Hosts, everyone else Joins its ip. One broadcast relays every line." & return after tR
   put "enetxt/examples/enet-internet-chat.livecodescript||the enetxt extension (org.openxtalk.library.enet); the HOST additionally wants torrentxt (org.openxtalk.library.torrent) for the automatic router door|Two machines on DIFFERENT networks (a phone hotspot is the easy second one). The host clicks Host, waits for the invite to fill in, and sends it; the joiner pastes it. Self-contained: carries enet-helpers + torrent-helpers.|ENet across the REAL internet, provably: UPnP opens the host's UDP port, the invite carries the public ip, and the pill goes green only when the peer's address is public." & return after tR
   put "datachannelxt/examples/datachannel-loopback.livecodescript||the datachannelxt extension (org.openxtalk.library.datachannel)|Self-contained: carries datachannel-helpers.|Two WebRTC peers in ONE stack, signaling shuttled in script: the whole pipeline (offer/answer, ICE, DTLS, SCTP) with zero infrastructure." & return after tR
   put "datachannelxt/examples/datachannel-dht-chat.livecodescript||datachannelxt AND torrentxt extensions|Two machines, ideally on different networks. SESSION: uses the one torrent session. Self-contained: carries datachannel-helpers.|P2P chat where the BitTorrent DHT carries the WebRTC handshake - no server anywhere, then the chat rides the direct encrypted channel." & return after tR
   put "torrentxt/examples/torrent-client.livecodescript||the torrentxt extension (org.openxtalk.library.torrent)|SESSION: one torrent stack per OXT launch.|The full client: add magnets/files/URLs, seed, inspect, tune, save resume data - the whole bt* surface in one window." & return after tR
   put "torrentxt/examples/torrent-dht-channels.livecodescript||torrentxt; sodiumxt for the private-feed features; onionxt + a tor daemon for anonymous channels|SESSION: one torrent stack per OXT launch.|Serverless publish/subscribe: signed channel feeds over BEP44 mutable items, with content-addressed releases - or make a whole channel anonymous over Tor." & return after tR
   put "torrentxt/examples/torrent-quickshare.livecodescript||torrentxt; sodiumxt for passphrase locking; onionxt + a tor daemon for Private/Tor|SESSION: one torrent stack per OXT launch.|Send a file with a code, privately over Tor, or via a web link - the small sibling of the nocloud app." & return after tR
   put "torrentxt/examples/torrent-rp1-chat.livecodescript||the torrentxt extension|Two machines. SESSION: one torrent stack per OXT launch.|The rp1 transport test: a phantom swarm, a DHT rendezvous, and opaque bytes peer to peer - the channel Riptide rides." & return after tR
   put "onionxt/examples/onionxt-demo.livecodescript||a local tor daemon with ControlPort 9051 (or Tor Browser: 9151)|Self-contained: carries onionxt, onion-httpd and its own self-test.|Tor from xTalk: control-port status, anonymous dials, hosting v3 onion services, self-authenticating addresses." & return after tR
   put "onionxt/examples/onion-httpd/spike.livecodescript||a local tor daemon with ControlPort 9051|Self-contained: carries onionxt and onion-httpd.|The smallest onion site: pick a folder, get a .onion, serve it - three buttons." & return after tR
   put "riptide/examples/riptide-social.livecodescript||sodiumxt AND torrentxt; coinxt or sodiumxt ABI 7 for the onion spelling|Two machines to see propagation. SESSION: uses the one torrent session. Self-contained: carries riptide, onionxt and onion-httpd.|The capstone: one sealed identity, signed public feeds published and verified over the real DHT (phases 1-2)." & return after tR
   put "nocloud/src/nocloudquickshare.livecodescript||torrentxt; sodiumxt and onionxt optional (each feature fails closed without its piece)|SESSION: one torrent stack per OXT launch.|The SHIPPED app: No Cloud Quick Share - send any file to anyone, no server, no account, no size limit." & return after tR
   put "nostrxt/examples/nostrxt-demo.livecodescript||the coinxt extension for signing; sodiumxt for key generation; a relay you choose for the live legs|Self-contained: carries nostrxt, its relay layer and its self-test. ws:// mirrors the proven socket idioms; wss:// is engine-unproven.|Nostr from xTalk: generate an identity, sign and verify notes, decode NIP-19 entities, talk to a relay - inbound events verified before display." & return after tR
   put "box2dxt/examples/box2dxt-demo.livecodescript||the box2dxt extension (org.openxtalk.box2dxt)||The physics showcase: scenes for shapes, joints, forces, queries and the Kit's control-backed bodies." & return after tR
   put "box2dxt/examples/box2dxt-platformer.livecodescript||the box2dxt extension||A complete platformer on the b2k game Kit: sprites, input, camera, one-way platforms, hazards - a game, not a widget." & return after tR
   put "box2dxt/examples/box2dxt-slingshot.livecodescript||the box2dxt extension||Knock the towers down: projectile physics, star ratings, level progression." & return after tR
   put "box2dxt/examples/box2dxt-contraption-builder.livecodescript||the box2dxt extension||Build machines from parts (motors, ropes, magnets, thrusters...), then hit PLAY and watch the physics run them." & return after tR
   put "box2dxt/examples/box2dxt-spike-gamekit.livecodescript||the box2dxt extension||The game-Kit capability spike: timers, keyboard, sprites, rays, camera - one button per probe." & return after tR
   put "box2dxt/examples/box2dxt-selftest.livecodescript||the box2dxt extension||box2dxt's own harness: the b2* binding surface exercised end to end." & return after tR
   put "holde-em/src/holdem.livecodescript||nothing to play hotseat; box2dxt for card art, sodiumxt for the committed deal, + torrentxt for online tables|Save the stack next to holde-em/assets/ for the Kenney card art; a pasted stack falls back to drawn cards. SESSION when online.|Serverless Texas Hold'em: hotseat now, online tables over the DHT, signed hash-chained transcripts, an auditable committed shuffle - Riptide's sibling capstone." & return after tR
   put "tests/preflight.livecodescript||every extension you have (absent ones SKIP, not fail)|GENERATED from the C shims' ABI macros. Nothing to install first, no start-using step. It TAKES the one torrent session and gives it straight back, so run it BEFORE any SESSION stack in this OXT launch.|Answers the pass's first question - can this machine run it at all? - in the first minute: one table of LOADED/ABSENT rows, each extension's own ABI guard doing the checking." & return after tR
   put "tests/suite-selftest.livecodescript||every extension you have (absent ones SKIP, not fail)|SESSION: starts the one torrent session. GENERATED from the member harnesses.|The whole suite's self-test in one window: TEN folded harnesses - the seven extension members (nostrxt joined 2026-08-23) plus riptide, box2dxt and holde-em - over the core's own cross-member sections. The 2026-08-17 Windows pass ran 1,836 folded member checks with zero failures and 7 skips; the core's sections run on top of that. Copy-results button for the pass record." & return after tR
   put "tests/suite-closing-pass.livecodescript||varies by section (each says what it needs)|Two machines for sections B-E; a tor binary for F. SESSION.|The remaining runbook legs as a checklist: ENet chat, torrent resume-from-disk, rp1 chat, DHT-signalled WebRTC, live Tor." & return after tR
   put "enetxt/tests/enet-selftest.livecodescript||the enetxt extension||enetxt's own deep harness: the sync surface plus a live async loopback on this machine." & return after tR
   put "datachannelxt/tests/datachannel-selftest.livecodescript||the datachannelxt extension||datachannelxt's own deep harness: stale-handle surface plus a live in-process loopback." & return after tR
   put "torrentxt/tests/torrent-selftest.livecodescript||the torrentxt extension|SESSION: one torrent stack per OXT launch.|torrentxt's own deep harness: 101 checks over the whole bt* surface (2026-08-17 pass)." & return after tR
   put "coinxt/tests/coin-selftest.livecodescript||the coinxt extension|Self-contained: carries coinxt.|coinxt's own deep harness: every phase against the published vectors, 278 checks (2026-08-17 pass)." & return after tR
   return tR
end slRegistry

-- Fill the directory list: full repo-relative paths, mono, grouped under a
-- header line per member (the group name, upper-cased and muted). Header and
-- spacer lines map to no registry entry, so clicking one is a no-op.
command slFillList
   local tOldDelim, tLine, tRel, tGroup, tLastGroup, tLineNo, tText, tH
   put empty into sLineEntry
   put empty into sHeaderLines
   put empty into tText
   put 0 into tLineNo
   put the itemDelimiter into tOldDelim
   repeat for each line tLine in slRegistry()
      set the itemDelimiter to "|"
      put item 1 of tLine into tRel
      set the itemDelimiter to "/"
      put item 1 of tRel into tGroup
      set the itemDelimiter to tOldDelim
      if tGroup is not tLastGroup then
         if tLastGroup is not empty then
            put return after tText
            add 1 to tLineNo
         end if
         put toUpper(tGroup) & return after tText
         add 1 to tLineNo
         put tLineNo & comma after sHeaderLines
      end if
      put tGroup into tLastGroup
      put "  " & tRel & return after tText
      add 1 to tLineNo
      put tLine into sLineEntry[tLineNo]
   end repeat
   -- drop the trailing return so the list has no phantom last line
   if the last char of tText is return then
      delete the last char of tText
   end if
   put tText into field "slList"
   -- style the header lines in place: bold, muted, visually not-a-row
   if the last char of sHeaderLines is comma then
      delete the last char of sHeaderLines
   end if
   set the itemDelimiter to comma
   repeat for each item tH in sHeaderLines
      set the textStyle of line tH of field "slList" to "bold"
      set the foregroundColor of line tH of field "slList" to kUiMuted
   end repeat
   set the itemDelimiter to tOldDelim
end slFillList

-- ---- the probe: does the tree around this file look like the repo? -----------
command slProbe
   local tRoot, tOldDelim, tLine, tRel, tMissing, tCount
   put slRoot() into tRoot
   if tRoot is empty then
      uiStatus "Open this stack FROM THE REPO (File > Open Stack on start-here.livecodescript) so relative paths can resolve.", "bad"
      exit slProbe
   end if
   put 0 into tCount
   put empty into tMissing
   put the itemDelimiter into tOldDelim
   repeat for each line tLine in slRegistry()
      set the itemDelimiter to "|"
      put item 1 of tLine into tRel
      set the itemDelimiter to tOldDelim
      if there is a file (tRoot & "/" & tRel) then
         add 1 to tCount
      else
         put tRel & comma & space after tMissing
      end if
   end repeat
   if tMissing is empty then
      uiStatus tCount && "stacks found under" && tRoot & ". Click one; double-click (or Open) launches it.", "ok"
   else
      uiStatus "MISSING from the download:" && char 1 to -3 of tMissing && "- incomplete clone, or this file moved out of the repo root.", "bad"
   end if
end slProbe

-- The repo root is simply the folder this file lives in.
function slRoot
   local tOldDelim, tFile, tRoot
   put the filename of this stack into tFile
   if tFile is empty then
      return empty
   end if
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "/"
   put item 1 to -2 of tFile into tRoot
   set the itemDelimiter to tOldDelim
   return tRoot
end slRoot

-- ---- selection + detail ------------------------------------------------------
command slShowDetail pLine
   local tOldDelim, tEntry, tRel, tHelpers, tNeeds, tNote, tDesc
   if pLine is not a number or sLineEntry[pLine] is empty then
      exit slShowDetail
   end if
   put sLineEntry[pLine] into tEntry
   put tEntry into sSelected
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "|"
   put item 1 of tEntry into tRel
   put item 2 of tEntry into tHelpers
   put item 3 of tEntry into tNeeds
   put item 4 of tEntry into tNote
   put item 5 of tEntry into tDesc
   set the itemDelimiter to tOldDelim
   -- the name is the file's own basename; the path is the point, so it gets
   -- the code box and the Copy button
   uiWrap "slName", slBasename(tRel), "708,72,1168,96", 14
   set the textStyle of field "slName" to "bold"
   put tRel into field "slPath"
   -- the two trait pills: SESSION rows hold the one torrent session while
   -- open; "Self-contained" rows carry every script library they need
   slPillShow "slPillSession", (tNote contains "SESSION")
   slPillShow "slPillSelf", (tNote contains "Self-contained")
   -- helpers fold into the Needs line: every row is self-contained today
   -- (the embed pass), and the launcher-registry gate refuses a row naming
   -- a helper its file already carries - but the mechanism stays for the
   -- one recorded demo that cannot embed, so a non-empty field still shows
   if tHelpers is empty then
      put tNeeds into field "slNeeds"
   else
      put tNeeds & return & "Put in use first (the launcher does this): " \
            & tHelpers into field "slNeeds"
   end if
   put tDesc into field "slDesc"
   put tNote into field "slNote"
end slShowDetail

function slBasename pRel
   local tOldDelim, tName
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "/"
   put the last item of pRel into tName
   set the itemDelimiter to tOldDelim
   return tName
end slBasename

-- Plain-language setup, for someone who has never used the suite. An
-- answer dialog on purpose: it waits until read, and needs no layout.
command slHelp
   answer "GETTING SET UP, in three steps:" & return & return \
         & "1. You already did the hard part - this window opening means" \
         && "the download works." & return & return \
         & "2. Most stacks need one or two EXTENSIONS installed in" \
         && "OpenXTalk (Tools > Extension Manager). Click any stack in the" \
         && "list and its card says exactly which ones it needs; each" \
         && "member folder's README.md has the install walkthrough." \
         & return & return \
         & "3. Click a stack, then Open. If something is missing, the" \
         && "stack itself says so in red at the top - install what it" \
         && "names and reopen it. Nothing here can damage anything:" \
         && "every stack fails safe." titled "Setup help"
end slHelp

command slCopyPath
   local tErr
   if sSelected is empty then
      exit slCopyPath
   end if
   try
      set the clipboardData["text"] to the text of field "slPath"
      uiCopyFlash "slCopyPath"
   catch tErr
      -- clipboard unavailable; the path is on screen to copy by hand
   end try
end slCopyPath

-- ---- the one torrent session -------------------------------------------------
-- Build the SESSION index once per open: for every registry row whose note
-- carries the SESSION marker, the stack name its file's own `script "..."`
-- line declares. Names, not windows: the check against the openStacks is
-- done fresh at each use, so a stack the user closed by hand reads as
-- closed here too.
command slSessIndex
   local tOldDelim, tRoot, tLine, tRel, tNote, tFirst
   put empty into sSessName
   put slRoot() into tRoot
   if tRoot is empty then
      exit slSessIndex
   end if
   put the itemDelimiter into tOldDelim
   repeat for each line tLine in slRegistry()
      set the itemDelimiter to "|"
      put item 1 of tLine into tRel
      put item 4 of tLine into tNote
      set the itemDelimiter to tOldDelim
      if tNote contains "SESSION" and there is a file (tRoot & "/" & tRel) then
         put line 1 of url ("file:" & tRoot & "/" & tRel) into tFirst
         put slScriptName(tFirst, tRel) into sSessName[tRel]
      end if
   end repeat
end slSessIndex

-- The comma list of session-holding stacks that are OPEN right now.
function slSessOpenNames
   local tRel, tName, tOpen
   repeat for each line tRel in the keys of sSessName
      put sSessName[tRel] into tName
      if tName is not empty and there is a stack tName \
            and tName is among the lines of the openStacks then
         put tName & comma after tOpen
      end if
   end repeat
   if the last char of tOpen is comma then
      delete the last char of tOpen
   end if
   return tOpen
end slSessOpenNames

-- One line into the session/self-check log (the card's mono surface).
-- Pinned for the family reason: nothing here arrives from a timer today,
-- but the log is also the self-check's surface and the pin is one line.
command slSessLine pText
   set the defaultStack to the short name of this stack
   if there is no field "slLog" then
      exit slSessLine
   end if
   put pText & return after field "slLog"
   set the vscroll of field "slLog" to the formattedHeight of field "slLog"
end slSessLine

-- Re-read the live state and say it in the log, in one voice.
command slSessRefresh
   local tOpen
   if slRoot() is empty then
      slSessLine "[session] repo root unknown - open this stack from the repo first."
      exit slSessRefresh
   end if
   put slSessOpenNames() into tOpen
   if tOpen is empty then
      slSessLine "[session] free - no session-holding stack is open."
   else
      slSessLine "[session] held by:" && tOpen && "- close it (button on the right) before launching another SESSION stack."
   end if
end slSessRefresh

-- The button: close every open session-holding stack. Closing a stack
-- fires ITS closeStack, and every SESSION stack in this registry tears its
-- session down there (btStopSession; all thirteen verified 2026-08-27) -
-- so this frees the session without this launcher touching bt* at all.
-- The one case it cannot reach is a stack that CRASHED past its teardown:
-- the session leaks inside the shim, no public handler can find it, and
-- the honest advice is an OXT restart - so that is what the log says.
command slCloseSessionStacks
   local tOldDelim, tOpen, tName, tErr, tClosed
   put slSessOpenNames() into tOpen
   if tOpen is empty then
      slSessLine "[session] nothing to close - no session-holding stack is open."
      uiStatus "No session-holding stacks are open. If a launch still cannot start a session, restart OXT (a stack that crashed past its teardown leaks it).", "ok"
      exit slCloseSessionStacks
   end if
   -- one item per turn, with the delimiter re-pinned EVERY turn: `close
   -- stack` runs the closed demo's own teardown, and teardowns set the
   -- global itemDelimiter (family gotcha 7) - a `repeat for each item`
   -- spanning those calls would be chunking on whatever the last demo
   -- left behind
   put the itemDelimiter into tOldDelim
   repeat until tOpen is empty
      set the itemDelimiter to comma
      put item 1 of tOpen into tName
      delete item 1 of tOpen
      try
         close stack tName
         put tName & comma after tClosed
      catch tErr
         slSessLine "[session] could not close" && tName & ":" && tErr
      end try
   end repeat
   set the itemDelimiter to tOldDelim
   if the last char of tClosed is comma then
      delete the last char of tClosed
   end if
   if tClosed is not empty then
      slSessLine "[session] closed:" && tClosed && "- each ran its own teardown; the session is free."
      uiStatus "Closed" && tClosed & ". The torrent session is free for the next launch.", "ok"
   end if
   slSessRefresh
end slCloseSessionStacks

-- ---- launching ---------------------------------------------------------------
command slOpenSelected
   local tOldDelim, tRoot, tRel, tHelpers, tNote, tHelper, tErr, tFailed
   local tHelperName, tName, tHeld
   if sSelected is empty then
      uiStatus "Click a stack in the list first.", "warn"
      exit slOpenSelected
   end if
   put slRoot() into tRoot
   if tRoot is empty then
      uiStatus "Open this stack FROM THE REPO so relative paths can resolve.", "bad"
      exit slOpenSelected
   end if
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "|"
   put item 1 of sSelected into tRel
   put item 2 of sSelected into tHelpers
   put item 4 of sSelected into tNote
   set the itemDelimiter to tOldDelim
   if there is no file (tRoot & "/" & tRel) then
      uiStatus tRel && "is not in the download - see the missing list above.", "bad"
      exit slOpenSelected
   end if
   -- the one-session rule is the family's sharpest trap: warn at the moment
   -- it is about to be walked into, with the LIVE holder's name - measured
   -- from the openStacks, never from a sticky flag (the flag this replaces
   -- stayed "true" after the holder was closed, so it warned about a
   -- session that was already free)
   if tNote contains "SESSION" then
      put slSessOpenNames() into tHeld
      -- relaunching the holder itself is not a conflict
      if tHeld is not empty and tHeld is not sSessName[tRel] then
         uiStatus "The torrent session is held by" && tHeld & " - use Close" \
               && "torrent stacks (bottom right) first, or" && slBasename(tRel) \
               && "will fail its session start and say so in red.", "warn"
      end if
   end if
   -- helpers first, each named as it goes in use, so a failure points at
   -- the exact file rather than at the demo that later cannot find it.
   -- Same recipe as the demo itself, minus the window: prepared as a named
   -- in-memory stack, then put in use BY NAME.
   put empty into tFailed
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   repeat for each item tHelper in tHelpers
      if tFailed is empty then
         put slPrepareStack(tRoot & "/" & tHelper) into tHelperName
         if tHelperName is empty then
            put tHelper into tFailed
         else
            try
               start using stack tHelperName
            catch tErr
               put tHelper into tFailed
            end try
         end if
      end if
   end repeat
   set the itemDelimiter to tOldDelim
   if tFailed is not empty then
      -- slPrepareStack already painted the specific red status; this line
      -- only covers the start-using throw
      if tErr is not empty then
         uiStatus "Could not put" && tFailed && "in use:" && tErr, "bad"
      end if
      exit slOpenSelected
   end if
   -- now the stack itself: prepare, open (openStack builds the window),
   -- nudge once if the card arrived empty, then reveal the finished window
   put slPrepareStack(tRoot & "/" & tRel) into tName
   if tName is empty then
      exit slOpenSelected
   end if
   try
      go stack tName
   catch tErr
      uiStatus "Could not open" && tName & ":" && tErr, "bad"
      exit slOpenSelected
   end try
   if the number of controls of card 1 of stack tName is 0 then
      send "openStack" to stack tName
   end if
   set the visible of stack tName to true
   if tNote contains "SESSION" then
      uiStatus "Opened" && tName && "from" && tRel & ". It owns the one torrent session while open; its own status line takes it from here.", "ok"
   else
      uiStatus "Opened" && tName && "from" && tRel & ".", "ok"
   end if
   slSessRefresh
end slOpenSelected

-- The heart of the launcher: turn a script-only FILE into a live, named,
-- in-memory stack, the way every engine pass has done it by hand. Returns
-- the stack's name, or empty AFTER painting the red status itself.
function slPrepareStack pPath
   local tScript, tName, tErr
   if there is no file pPath then
      uiStatus pPath && "is missing from the download.", "bad"
      return empty
   end if
   put url ("file:" & pPath) into tScript
   if tScript is empty then
      uiStatus "Could not read" && pPath & ":" && the result, "bad"
      return empty
   end if
   put slScriptName(line 1 of tScript, pPath) into tName
   -- the `script "Name"` header is FILE metadata, not script: strip it
   -- before the text becomes a live stack script
   if line 1 of tScript begins with "script " then
      delete line 1 of tScript
   end if
   if there is a stack tName then
      -- already in memory from an earlier launch. If its window is open,
      -- leave it exactly alone (never yank a script under a running
      -- stack); if it is closed, refresh the script from disk so a
      -- freshly pulled repo is what reopens (the stale-in-memory-stack
      -- lesson the suite harness embed exists for).
      if tName is not among the lines of the openStacks then
         try
            set the script of stack tName to tScript
         catch tErr
            uiStatus "The script of" && tName && "did not compile:" && tErr, "bad"
            return empty
         end try
      end if
      return tName
   end if
   try
      create invisible stack tName
      set the script of stack tName to tScript
   catch tErr
      uiStatus "Could not prepare" && tName & ":" && tErr, "bad"
      if there is a stack tName then
         delete stack tName
      end if
      return empty
   end try
   return tName
end slPrepareStack

-- The stack's name comes from the file's own `script "Name"` first line;
-- the file's basename stands in if that line is ever missing or unquoted.
function slScriptName pLine1, pPath
   local tOldDelim, tName
   if pLine1 begins with "script " then
      put char 8 to -1 of pLine1 into tName
      replace quote with empty in tName
      put word 1 to -1 of tName into tName
      if tName is not empty then
         return tName
      end if
   end if
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "/"
   put the last item of pPath into tName
   set the itemDelimiter to tOldDelim
   replace ".livecodescript" with empty in tName
   return tName
end slScriptName


-- ---- the boot self-check (fourteenth adopter) ---------------------------------
-- The list is DERIVED, not hand-picked: tools/check-demo-control-lists.py
-- re-derives it from this source on every build and fails on any drift.
constant kSlScControls = "slCard,slCopyPath,slDesc,slDirSec,slHelp,slList,slListCap,slListCard,slLog,slName,slNeeds,slNeedsCap,slNote,slOpen,slPath,slPillSelf,slPillSession,slSessCap,slSessCard,slSessClose,slSessSec,uiFooter,uiStatus,uiTitle"

command slScRun
   local tOldDelim, tMissing, tLine, tRows, tGood, tRel, tNote
   local tSess, tNamed, tPresent, tAbsent
   scBegin "slLog"
   put scMissing(kSlScControls) into tMissing
   scAssert "all 24 controls this script names exist (missing: " \
         & scShow(tMissing) & ")", tMissing is empty
   -- the registry parses: five |-fields per row, no empties in the tree walk
   put 0 into tRows
   put 0 into tGood
   put the itemDelimiter into tOldDelim
   repeat for each line tLine in slRegistry()
      add 1 to tRows
      set the itemDelimiter to "|"
      if the number of items of tLine is 5 then
         add 1 to tGood
      end if
      set the itemDelimiter to tOldDelim
   end repeat
   scAssert "every registry row carries relpath|helpers|needs|note|description (" \
         & tGood & "/" & tRows & ")", (tGood is tRows and tRows > 0)
   scAssert "the directory list is built and mapped", \
         (the number of lines of the keys of sLineEntry is tRows)
   if slRoot() is empty then
      scSkip "every registry file resolves on disk", \
            "opened outside the repo - no filename to resolve against"
      scSkip "every SESSION row resolved its stack name", \
            "same reason - the index needs the repo root"
   else
      -- files present: absence is an incomplete DOWNLOAD (environment), so
      -- it skips with the count; the red status line above names the files
      put 0 into tPresent
      put 0 into tAbsent
      repeat for each line tLine in slRegistry()
         set the itemDelimiter to "|"
         put item 1 of tLine into tRel
         set the itemDelimiter to tOldDelim
         if there is a file (slRoot() & "/" & tRel) then
            add 1 to tPresent
         else
            add 1 to tAbsent
         end if
      end repeat
      if tAbsent is 0 then
         scAssert "every registry file resolves on disk (" & tPresent & "/" \
               & tRows & ")", true
      else
         scSkip "every registry file resolves on disk", \
               tAbsent & " missing - incomplete download; the status line names them"
      end if
      -- the session index: every SESSION row yielded a stack name, so the
      -- session card's close sweep can find what it needs to close
      put 0 into tSess
      put 0 into tNamed
      repeat for each line tLine in slRegistry()
         set the itemDelimiter to "|"
         put item 1 of tLine into tRel
         put item 4 of tLine into tNote
         set the itemDelimiter to tOldDelim
         if tNote contains "SESSION" then
            add 1 to tSess
            if sSessName[tRel] is not empty then
               add 1 to tNamed
            end if
         end if
      end repeat
      scAssert "every SESSION row resolved its stack name (" & tNamed & "/" \
            & tSess & ")", (tNamed is tSess and tSess > 0)
   end if
   scArmProbe
end slScRun

-- ==== DEMO SELF-CHECK v1 BEGIN (verbatim copy; master: tools/demo-selfcheck.livecodescript; gate: tools/check-demo-selfcheck-drift.py) ====
-- The sentinel is a CONSTANT so the probe compares against one spelling; a
-- literal repeated at the write and the read is a check that can pass while
-- disagreeing with itself.
constant kScProbe = "self-check: delayed write reached the status line"
local sScLines          -- the whole block, kept so a Copy button has something
local sScPassed, sScFailed, sScSkipped
local sScLogField       -- the adopting demo's own log field, set by scBegin

command scBegin pLogField
   put pLogField into sScLogField
   put empty into sScLines
   put 0 into sScPassed
   put 0 into sScFailed
   put 0 into sScSkipped
   scLine "== boot self-check (nothing is hosted, connected, or bound) =="
end scBegin

-- Each line is LOGGED as it is made, not accumulated and flushed at the end.
-- The first draft did both - a flush after the synchronous half and another
-- after the probe - which printed every synchronous line twice.
command scLine pText
   put pText & return after sScLines
   -- pin the stack: scFinish reaches here from a `send ... in` tick, and the
   -- field is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sScLogField is empty or there is no field sScLogField then
      exit scLine
   end if
   put pText & return after field sScLogField
   set the vscroll of field sScLogField to the formattedHeight of field sScLogField
end scLine

command scAssert pName, pOk
   if pOk then
      add 1 to sScPassed
      scLine "PASS  " & pName
   else
      add 1 to sScFailed
      scLine "FAIL  " & pName
   end if
end scAssert

-- SKIP, never FAIL, for an absent extension: a missing member is an
-- environment, and only a present-and-broken member is a defect.
command scSkip pName, pReason
   add 1 to sScSkipped
   scLine "SKIP  " & pName & " (" & pReason & ")"
end scSkip

-- An empty value prints as nothing, which reads as a missing check rather than
-- an answer of empty; every observed value in a self-check goes through here.
-- This is the playLoudness lesson (OXT-ENGINE-NOTES 5.4) as a helper: a check
-- that reports only its own name costs a whole engine pass to diagnose.
function scShow pValue
   if pValue is empty then
      return "empty"
   end if
   return pValue
end scShow

-- Returns the comma-list of control names in pList that do not exist, or empty.
-- The adopter passes EVERY control name its own script references, derived from
-- the source rather than hand-picked: a missing control is not cosmetic, it is
-- the "Chunk: error in object expression" class, and finding it at boot beats
-- finding it when somebody clicks.
function scMissing pList
   local tName, tMissing
   set the defaultStack to the short name of this stack
   repeat for each item tName in pList
      -- ALL THREE CONTROL TYPES. The kit builds fields (uiLabel/uiWrap/uiCap/
      -- uiSection/uiInput/uiArea/uiTable), buttons (uiButton/uiCheckbox) AND
      -- GRAPHICS (uiGfx/uiPanel/uiPill). The first version of this asked only
      -- about fields and buttons, so every uiPill a demo builds - the Tor
      -- pills in both Quick Shares, for one - reported as a missing control on
      -- a stack where it exists.
      if there is no field tName and there is no button tName \
            and there is no graphic tName then
         put tName & comma after tMissing
      end if
   end repeat
   if tMissing is empty then
      return empty
   end if
   return char 1 to -2 of tMissing
end scMissing

-- Call LAST in <pfx>ScRun. It arms the probe below; 400ms lands it before the
-- usual 800ms dashboard tick, so nothing races for the status line.
--
-- SAY THAT THE REPORT IS UNFINISHED, for the reason the suite harness carries a
-- RUN NOT FINISHED trailer: a report that simply stops reads exactly like a
-- report that ended, and the difference cost that harness a round trip on
-- 2026-08-19. One line is cheaper than the ambiguity.
command scArmProbe
   scLine "      ...one delayed-write check still to come; the count line " \
         & "below it is the end of the block"
   send "scTickProbe" to me in 400 milliseconds
end scArmProbe

-- THE ONE CHECK THAT NEEDS A TIMER.
--
-- OXT-ENGINE-NOTES 5.3 says an unqualified control reference inside a delayed
-- handler resolves against THE DEFAULTSTACK, not the stack whose script is
-- running - and that entry is classed DOCUMENTED, not OBSERVED, because this
-- tree has never actually watched the unpinned form fail. It also names the run
-- that would settle it: open a second stack in front and let a `send ... in`
-- handler write an unqualified field.
--
-- So this probe READS the defaultStack before pinning and PRINTS what it found.
-- On an ordinary run that line is context. On a run with another window in front
-- it is the measurement 5.3 is missing, taken for free and at no risk, because
-- the pin lands immediately afterwards and the write is verified.
command scTickProbe
   local tWas, tPrev, tPrevColor, tGot, tErr
   put the defaultStack into tWas
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      scSkip "a delayed handler writes the status line", "the chrome is not built"
      scFinish
      exit scTickProbe
   end if
   -- RESTORE THE COLOUR TOO, not just the text. uiStatus takes a KIND, and
   -- handing it back "ok" would repaint a "bad" line green - so a stack whose
   -- extension is missing would end this probe claiming to be fine.
   put field "uiStatus" into tPrev
   put the foregroundColor of field "uiStatus" into tPrevColor
   try
      uiStatus kScProbe, empty
      put field "uiStatus" into tGot
   catch tErr
      put "THREW:" && tErr into tGot
   end try
   uiStatus tPrev, empty
   set the foregroundColor of field "uiStatus" to tPrevColor
   scAssert "a delayed handler writes the status line " \
         & "(defaultStack on entry: " & scShow(tWas) & ")", (tGot is kScProbe)
   scFinish
end scTickProbe

command scFinish
   scLine "      " & sScPassed & " passed, " & sScFailed & " failed, " \
         & sScSkipped & " skipped - select this block and copy it into the " \
         & "OXT pass record"
   if sScFailed is 0 then
      scLine "      boot self-check GREEN (this is the single-machine claim; " \
            & "the live legs are the runbook's)"
      exit scFinish
   end if
   scLine "      boot self-check has FAILURES above - report them before " \
         & "running any live leg"
   -- ONLY ON FAILURE does this touch the status line, and the asymmetry is
   -- deliberate. Green, the demo's own "Ready ..." line is the more useful
   -- thing to be reading and the detail is in the log a few lines up. Red, the
   -- log may be on a tab nobody has clicked - so the one surface a person is
   -- certainly looking at has to say so. Fail loud, pass quiet.
   uiStatus "Boot self-check: " & sScFailed & " FAILED (see the log)", "bad"
end scFinish
-- ==== DEMO SELF-CHECK v1 END ====
