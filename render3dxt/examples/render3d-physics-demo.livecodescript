script "RenderThreeDDemo"
-- render3d-physics-demo.livecodescript - render3dxt drawing a box3dxt
-- simulation, one paste-and-run file.
--
-- WHAT THIS IS. A window with one picture in it. box3dxt (Box3D) simulates
-- crates, balls and a faceted gem falling onto a floor; render3dxt draws
-- them, textured and lit, into an ordinary image control sixty times a
-- second. Drag the picture to walk the camera round the scene, turn the
-- wheel to come closer, click a thing to kick it, and use the buttons to
-- drop more.
--
-- WHAT TO LOOK AT AS A TEMPLATE. rdFrame is the whole join between the two
-- extensions, and it is five lines:
--
--    set the imageData of image "rdView" to r3SceneFrame(sScene)   -- rdShow
--    b3WorldStep sWorld, 1/60, 4
--    get b3WorldUpdateMoves(sWorld)
--    get r3SceneApplyMoves(sScene, b3MovesText())
--    get r3SceneRenderBegin(sScene, kRdViewW, kRdViewH)
--
-- The engine runs script on one thread, so the frame never waits for a
-- picture: it shows the one begun a frame ago and begins the next, which
-- render3dxt draws on its own threads while the engine redraws the window
-- and waits for the timer. Physics steps by the clock, so a slow machine
-- shows fewer pictures and never a slower fall; and when nothing has moved
-- and nothing was touched, no picture is drawn at all.
--
-- A node is tagged with its body's handle (rdAddThing), so one call carries
-- a whole physics step to the picture, and a click on the picture leads back
-- to a body (rdKick: r3ScenePick, r3NodeTag, b3BodyApplyImpulse). Both
-- extensions use the same world: y up, metres, a rotation as a quaternion.
--
-- HOW TO USE. Install the render3dxt and box3dxt extensions. Paste this
-- into a new stack's script, then close and reopen the stack: the window
-- builds itself. Opening this file directly does not build it
-- (docs/OXT-ENGINE-NOTES.md 5.5). Without one of the extensions the window
-- still opens and its status line says which is missing.
--
-- HONESTY (the suite convention): this script has run on OXT-Beyond's
-- headless Linux server engine (tests/engine-demo.lc, 2026-11-20): the
-- window's controls were built, the boot self-check came back green, frames
-- ran on the timer, the picture reached the image, and a drop, a kick, the
-- toggles, Reset and the close were driven by message. One desktop engine
-- has opened it (OXT-Beyond 0.2.8-dp.2 on Linux, 2026-11-20): the picture
-- was seen, a real pointer dragged the camera, kicked a thing and pressed
-- every button, and it showed 57 pictures a second with nine things. On
-- Windows and macOS its look, the mouse and its speed are verified
-- statically; needs an OXT pass.
--
-- THE LOOK. This stack adopts the suite UI kit v2 verbatim (the marked
-- block below); the kit block is never edited here - a look change edits
-- tools/ui-kit.livecodescript and re-carries. The picture is the one
-- control the kit does not build: an image, created in rdBuild. The
-- buttons are painted by this stack (rdButton) and the log, the small print
-- and the footer say their own colours, because what is left to the system
-- comes out white on white under a dark theme (Windows, 2026-11-20). The
-- look as rebuilt that day (the buttons, the sky, the wheel, the corner's
-- pictures-a-second) is verified statically; needs an OXT pass.


-- ==========================================================================
-- Demo constants and state.
-- ==========================================================================

-- Bumped whenever the generated UI changes so a saved stack rebuilds.
constant kRdUiVersion = "render3d-kit2-3"
constant kRdWinW = 980
constant kRdWinH = 620
-- The picture: 4 by 3, and small enough that a frame with smooth edges
-- (four samples a pixel) stays inside a sixtieth of a second on an
-- ordinary machine.
constant kRdViewW = 624
constant kRdStepMs = 16.6667 -- one physics step: a sixtieth of a second
constant kRdViewH = 468
constant kRdViewLeft = 16
constant kRdViewTop = 64
-- At most this many falling things: the oldest goes when a new one comes.
constant kRdMaxThings = 60
-- What the camera looks at, and how far away it stands.
constant kRdTarget = "0,1.2,0"
constant kRdDistance = 10.5 -- the camera's first distance from kRdTarget, metres
constant kRdNear = 4.5       -- and how near and how far the wheel takes it
constant kRdFar = 26
-- The look of this stack's own buttons, which are painted here and not by
-- the system (rdButton says why). Three shades each: at rest, under the
-- pointer, pressed.
constant kRdFill = "44,90,160"
constant kRdFillOver = "58,108,186"
constant kRdFillDown = "30,68,126"
constant kRdLine = "255,255,255"
constant kRdLineOver = "234,240,250"
constant kRdLineDown = "214,225,244"
constant kRdOn = "224,234,250"
constant kRdEdge = "164,184,218"
constant kRdQuiet = "90,98,110"   -- small print: darker than the kit's muted grey
constant kRdConsole = "28,34,46"  -- the log: a dark page with light words
constant kRdConsoleInk = "214,222,236"
constant kRdButtons = "rdCrate,rdBall,rdGem,rdRain,rdReset,rdPause,rdSmooth,rdTextures,rdTurn"

local sRdHaveRender          -- capability flags from the boot probe
local sRdHavePhysics
local sRdWorld               -- the box3dxt world, or empty
local sRdScene               -- the render3dxt scene, or empty
local sRdFloorBody
local sRdThings              -- one line a falling thing: "body,node"
local sRdMeshes              -- array: crate, ball, gem, floor -> mesh handle
local sRdMaterials           -- comma list of material handles this stack made
local sRdTextures            -- comma list of texture handles this stack made
local sRdCrateMats           -- comma list: the materials crates take in turn
local sRdBallMats            -- comma list: the materials balls take in turn
local sRdTexOfMat            -- array: material -> the texture it wears when Textures is on
local sRdDropCount           -- how many things have been dropped (picks colours and places)
local sRdRunning             -- true while the frame timer should keep going
local sRdPaused
local sRdFrameMsg            -- the id of the pending rdFrame message
local sRdFrames              -- frames drawn since the stack opened
local sRdBegun               -- true while a picture begun last frame waits to be shown
local sRdStale               -- true when the scene has changed since the last picture was begun
local sRdClock               -- the milliseconds at the last frame
local sRdOwed                -- simulated time the physics still owes the clock, milliseconds
local sRdYaw, sRdPitch       -- the camera's place on its orbit, radians
local sRdDragging            -- true between a mouseDown on the picture and its end
local sRdDragX, sRdDragY     -- where the mouse was at the last drag step
local sRdDragMoved           -- how far the mouse has gone since mouseDown, pixels
local sRdSmooth, sRdTextured -- the toggles' state (script-managed)
local sRdTurning             -- true while the camera walks slowly round by itself
local sRdDistance            -- the camera's distance from kRdTarget, metres
local sRdShown               -- pictures shown since the stats were last written
local sRdStatsAt             -- the milliseconds when they were
local sRdPressed             -- the button the mouse went down on, or empty

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
   -- SAY THE TEXT COLOUR. Left unset it is the system theme's, and a dark
   -- theme's is white: white words on the white this builder paints (seen on
   -- Windows, 2026-11-20, in a log and under two checkboxes).
   set the foregroundColor of field pName to kUiInk
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
   -- and its words, for uiInput's reason: never the theme's
   set the foregroundColor of field pName to kUiInk
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
   -- its label sits on the adopter's card, which the kit paints white: the
   -- theme's text colour (white, under a dark theme) must not reach it
   set the foregroundColor of button pName to kUiInk
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
   local tName, tMissing, tC, tFound
   set the defaultStack to the short name of this stack
   repeat for each item tName in pList
      -- ALL FOUR CONTROL TYPES. The kit builds fields (uiLabel/uiWrap/uiCap/
      -- uiSection/uiInput/uiArea/uiTable), buttons (uiButton/uiCheckbox) AND
      -- GRAPHICS (uiGfx/uiPanel/uiPill). The first version of this asked only
      -- about fields and buttons, so every uiPill a demo builds - the Tor
      -- pills in both Quick Shares, for one - reported as a missing control on
      -- a stack where it exists.
      --
      -- AND IMAGES (2026-08-31), for the same reason one step further out. A
      -- demo may build a control the KIT does not: coinxt's wallet paints a
      -- QR into an image, which is the only way a BMP this family builds
      -- becomes something a phone can read. Registered and built, it reported
      -- as missing - found by coinxt/tools/check-wallet-boot.py, which boots
      -- the stack headlessly, so this one cost no engine time. The lesson is
      -- the one this block already carries twice: the list of types a demo
      -- can build is not the list of types the KIT builds.
      --
      -- AND EVERY CARD (2026-08-29). Unqualified `there is a field X` answers
      -- for the CURRENT card only (engine notes 5.6) - OBSERVED when
      -- riptide's five-card boot reported all 63 off-card controls missing
      -- from a stack where every one existed. A single-card demo walks its
      -- one card here, exactly the old behaviour.
      put false into tFound
      repeat with tC = 1 to the number of cards of this stack
         if there is a field tName of card tC \
               or there is a button tName of card tC \
               or there is a graphic tName of card tC \
               or there is an image tName of card tC then
            put true into tFound
            exit repeat
         end if
      end repeat
      if not tFound then
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

-- ==========================================================================
-- Lifecycle. The self-check runs LAST in openStack: it reads state rdStart
-- establishes.
-- ==========================================================================

on openStack
   rdBuild
   rdStart
   rdScRun
end openStack

on closeStack
   rdStop
end closeStack

on mouseUp
   switch the short name of the target
      case "rdView"
         rdDragEnd true
         break
      case "rdCrate"
         rdDrop "crate"
         break
      case "rdBall"
         rdDrop "ball"
         break
      case "rdGem"
         rdDrop "gem"
         break
      case "rdRain"
         rdRain
         break
      case "rdReset"
         rdReset
         break
      case "rdPause"
         rdTogglePause
         break
      case "rdSmooth"
         rdSetSmooth (sRdSmooth is not true)
         break
      case "rdTextures"
         rdSetTextured (sRdTextured is not true)
         break
      case "rdTurn"
         rdSetTurning (sRdTurning is not true)
         break
      default
         rdPressEnd
         pass mouseUp
   end switch
   rdPressEnd
end mouseUp

-- The pointer over one of this stack's buttons lightens it, and a press
-- darkens it: the feedback a system button gives, which these paint
-- themselves.
on mouseEnter
   if the short name of the target is among the items of kRdButtons then
      rdPaintButton the short name of the target, "over"
   end if
   pass mouseEnter
end mouseEnter

on mouseLeave
   if the short name of the target is among the items of kRdButtons then
      rdPaintButton the short name of the target, "rest"
   end if
   pass mouseLeave
end mouseLeave

command rdPressEnd
   local tWas
   put sRdPressed into tWas
   put empty into sRdPressed
   if tWas is empty then
      exit rdPressEnd
   end if
   set the defaultStack to the short name of this stack
   if there is a button tWas and the mouseLoc is within the rect of button tWas then
      rdPaintButton tWas, "over"
   else
      rdPaintButton tWas, "rest"
   end if
end rdPressEnd

-- The wheel over the picture brings the camera closer or takes it away. A
-- turn of the wheel reaches a stack as a rawKeyDown: 65309 away from the
-- hand, 65308 towards it.
on rawKeyDown pKey
   if pKey is not 65309 and pKey is not 65308 then
      pass rawKeyDown
   end if
   if there is no image "rdView" or the mouseLoc is not within the rect of image "rdView" then
      pass rawKeyDown
   end if
   if pKey is 65309 then
      rdZoom -1
   else
      rdZoom 1
   end if
end rawKeyDown

-- The picture is dragged to orbit and clicked to kick; which of the two a
-- press was is decided when it ends, by how far the mouse went.
on mouseDown
   if the short name of the target is among the items of kRdButtons then
      put the short name of the target into sRdPressed
      rdPaintButton sRdPressed, "down"
   end if
   if the short name of the target is not "rdView" then
      pass mouseDown
   end if
   put true into sRdDragging
   put the mouseH into sRdDragX
   put the mouseV into sRdDragY
   put 0 into sRdDragMoved
end mouseDown

on mouseMove pX, pY
   if sRdDragging is not true then
      pass mouseMove
   end if
   rdOrbitBy pX - sRdDragX, pY - sRdDragY
   add abs(pX - sRdDragX) + abs(pY - sRdDragY) to sRdDragMoved
   put pX into sRdDragX
   put pY into sRdDragY
end mouseMove

-- The button came up outside the picture: the drag ends, and nothing is
-- kicked.
on mouseRelease
   rdPressEnd
   rdDragEnd false
end mouseRelease

command rdDragEnd pOverPicture
   local tWasDragging
   put (sRdDragging is true) into tWasDragging
   put false into sRdDragging
   if tWasDragging and pOverPicture and sRdDragMoved < 4 then
      set the defaultStack to the short name of this stack
      rdKick the mouseH - the left of image "rdView", the mouseV - the top of image "rdView"
   end if
end rdDragEnd

-- ==========================================================================
-- Build: the whole window, in script, kit look, inside the 720p budget.
-- ==========================================================================

command rdBuild
   if the uRdUiVersion of this stack is kRdUiVersion and there is a field "rdLog" then
      exit rdBuild
   end if
   lock screen
   rdClearGeneratedUI
   uiChrome "render3dxt + box3dxt: a simulation, drawn", kRdWinW, kRdWinH
   -- Panels first, for z-order (the kit rule). They start below the status
   -- line, which the kit ends at y 52.
   uiPanel "rdViewPanel", "10,58,646,538"
   uiPanel "rdSidePanel", "656,58,970,538"
   -- The picture. The kit builds no image, so this one is made here; its
   -- size is the picture's, exactly, because imageData is not scaled.
   rdImage "rdView", kRdViewLeft & comma & kRdViewTop & comma & (kRdViewLeft + kRdViewW) & comma & (kRdViewTop + kRdViewH)
   -- How fast it is going, where nobody can miss it: on the picture's corner.
   uiLabel "rdFps", empty, "24,72,176,100", 13
   set the textStyle of field "rdFps" to "bold"
   set the textAlign of field "rdFps" to "center"
   set the opaque of field "rdFps" to true
   set the backgroundColor of field "rdFps" to kRdConsole
   set the foregroundColor of field "rdFps" to "255,255,255"
   set the blendLevel of field "rdFps" to 18
   set the margins of field "rdFps" to "6,6,6,6"
   -- The side column.
   uiSection "rdDropCap", "Drop something", "668,68,958,86"
   rdButton "rdCrate", "A crate", "668,100,761,128", "fill"
   rdButton "rdBall", "A ball", "767,100,860,128", "fill"
   rdButton "rdGem", "A gem", "866,100,958,128", "fill"
   rdButton "rdRain", "Ten at once", "668,134,810,162", "fill"
   rdButton "rdReset", "Start again", "816,134,958,162", "line"
   uiSection "rdLookCap", "The picture", "668,176,958,194"
   rdButton "rdSmooth", "Smooth edges", "668,208,810,236", "line"
   rdButton "rdTextures", "Textures", "816,208,958,236", "line"
   rdButton "rdPause", "Pause", "668,242,810,270", "line"
   rdButton "rdTurn", "Turn slowly", "816,242,958,270", "line"
   uiCap "rdHelp", "Drag the picture to look round, turn the wheel to come closer, and click a thing to kick it.", "668,280,958,314"
   rdQuiet "rdHelp"
   uiSection "rdLogCap", "Boot self-check", "668,322,958,340"
   uiArea "rdLog", "668,354,958,528"
   -- the log is a dark page with light words, said outright: left to the
   -- system, its words are the theme's, and a dark theme's are white on the
   -- white the kit paints (seen on Windows, 2026-11-20)
   set the backgroundColor of field "rdLog" to kRdConsole
   set the foregroundColor of field "rdLog" to kRdConsoleInk
   set the borderColor of field "rdLog" to kRdConsole
   uiCap "rdStats", empty, "16,546,964,564"
   rdQuiet "rdStats"
   uiFooter "render3dxt draws, in an ordinary image, what box3dxt simulates. This stack reads and writes no file and uses no network; where it has run is at the top of its script.", "16,568,964,604"
   set the foregroundColor of field "uiFooter" to kRdQuiet
   set the uRdUiVersion of this stack to kRdUiVersion
   unlock screen
end rdBuild

-- Create-or-reuse a named image, as the kit's builders do for their kinds.
command rdImage pName, pRect
   if there is no image pName then
      create image
      set the name of the last image to pName
   end if
   set the lockLocation of image pName to true
   set the rect of image pName to pRect
end rdImage

-- Small print a person can read: the kit's captions are 10 point in a
-- pale grey, which on a real screen was too faint (Windows, 2026-11-20).
command rdQuiet pName
   set the textSize of field pName to 11
   set the foregroundColor of field pName to kRdQuiet
end rdQuiet

-- A button this stack paints itself: a rounded graphic (pName & "Bg") and,
-- over it, a transparent button that carries the label and takes the
-- clicks. A system button takes its colours from the system's theme, and
-- under a dark one it came out as a black slab on the kit's white panel,
-- with tick boxes whose words were white on white (Windows, 2026-11-20).
-- These say every colour they use, so they look the same anywhere. pKind
-- is "fill" (something happens: the accent, white words) or "line" (a
-- quieter one, and every toggle: white with an edge).
command rdButton pName, pLabel, pRect, pKind
   uiGfx (pName & "Bg"), pRect
   set the roundRadius of graphic (pName & "Bg") to 10
   set the filled of graphic (pName & "Bg") to true
   uiButton pName, pLabel, pRect
   set the style of button pName to "transparent"
   set the opaque of button pName to false
   set the showBorder of button pName to false
   set the threeD of button pName to false
   set the shadow of button pName to false
   set the autoHilite of button pName to false
   set the traversalOn of button pName to false
   set the textSize of button pName to 12
   set the textStyle of button pName to "bold"
   set the uRdKind of button pName to pKind
   rdPaintButton pName, "rest"
end rdButton

-- Paints one of them for a state: "rest", "over" (the pointer is on it) or
-- "down" (pressed). A toggle that is on (its uRdOn) is tinted with the
-- accent, so on and off never look alike.
command rdPaintButton pName, pState
   local tBack, tInk, tEdge
   set the defaultStack to the short name of this stack
   if there is no button pName or there is no graphic (pName & "Bg") then
      exit rdPaintButton
   end if
   if the uRdKind of button pName is "fill" then
      put kUiAccentText into tInk
      put empty into tEdge
      switch pState
         case "over"
            put kRdFillOver into tBack
            break
         case "down"
            put kRdFillDown into tBack
            break
         default
            put kRdFill into tBack
      end switch
   else
      put kRdEdge into tEdge
      if the uRdOn of button pName is true then
         put kRdFill into tInk
         put kRdOn into tBack
         put kRdFill into tEdge
      else
         put kUiInk into tInk
         put kRdLine into tBack
      end if
      if pState is "over" and the uRdOn of button pName is not true then
         put kRdLineOver into tBack
      else if pState is "down" then
         put kRdLineDown into tBack
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
end rdPaintButton

-- Sets a toggle on or off: its look, and a word in its label, so that
-- nothing rests on a colour alone.
command rdShowToggle pName, pLabel, pOn
   set the defaultStack to the short name of this stack
   if there is no button pName then
      exit rdShowToggle
   end if
   set the uRdOn of button pName to (pOn is true)
   if pOn is true then
      set the label of button pName to pLabel & ": on"
   else
      set the label of button pName to pLabel & ": off"
   end if
   rdPaintButton pName, "rest"
end rdShowToggle

command rdClearGeneratedUI
   -- Rebuild-proof: drop every control on the card, then let rdBuild remake
   -- them.
   repeat while the number of controls of this card > 0
      delete control 1 of this card
   end repeat
end rdClearGeneratedUI

-- ==========================================================================
-- Start and stop.
-- ==========================================================================

-- True if pCall (a function call, as text) answers without throwing: an
-- extension that is not installed has no such handler.
function rdAnswers pCall
   local tValue, tError
   try
      do "put" && pCall && "into tValue"
   catch tError
      return false
   end try
   return tValue is not empty
end rdAnswers

command rdStart
   set the defaultStack to the short name of this stack
   put rdAnswers("r3LibraryVersion()") into sRdHaveRender
   put rdAnswers("b3LibraryVersion()") into sRdHavePhysics
   put false into sRdRunning
   put false into sRdPaused
   put false into sRdDragging
   put 0 into sRdFrames
   put false into sRdBegun
   put false into sRdStale
   put the milliseconds into sRdClock
   put 0 into sRdOwed
   put 0 into sRdShown
   put sRdClock into sRdStatsAt
   put empty into sRdPressed
   put kRdDistance into sRdDistance
   put empty into sRdFrameMsg
   set the label of button "rdPause" to "Pause"
   put empty into field "rdFps"
   rdShowToggle "rdSmooth", "Smooth edges", false
   rdShowToggle "rdTextures", "Textures", false
   rdShowToggle "rdTurn", "Turn slowly", false
   if sRdHaveRender is not true and sRdHavePhysics is not true then
      uiStatus "The render3dxt and box3dxt extensions are not installed: nothing can be drawn or simulated", "bad"
      exit rdStart
   end if
   if sRdHaveRender is not true then
      uiStatus "The render3dxt extension is not installed: nothing can be drawn", "bad"
      exit rdStart
   end if
   if sRdHavePhysics is not true then
      uiStatus "The box3dxt extension is not installed: nothing can be simulated", "bad"
      exit rdStart
   end if
   rdMakeScene
   rdSetSmooth true
   rdSetTextured true
   rdSetTurning true
   rdFirstThings
   rdDraw
   uiStatus "Running - " & r3LibraryVersion(), "ok"
   put true into sRdRunning
   send "rdFrame" to me in 16 milliseconds
   put the result into sRdFrameMsg
end rdStart

-- Everything this stack made is given back: the frame timer first, so no
-- frame runs against a world that is gone.
command rdStop
   local tHandle
   put false into sRdRunning
   if sRdFrameMsg is not empty then
      cancel sRdFrameMsg
      put empty into sRdFrameMsg
   end if
   if sRdHaveRender is true then
      if sRdScene is not empty then
         r3SceneDestroy sRdScene
      end if
      repeat for each element tHandle in sRdMeshes
         r3MeshDestroy tHandle
      end repeat
      repeat for each item tHandle in sRdMaterials
         r3MaterialDestroy tHandle
      end repeat
      repeat for each item tHandle in sRdTextures
         r3TextureDestroy tHandle
      end repeat
   end if
   if sRdHavePhysics is true and sRdWorld is not empty then
      b3WorldDestroy sRdWorld
   end if
   put empty into sRdScene
   put empty into sRdWorld
   put empty into sRdMeshes
   put empty into sRdMaterials
   put empty into sRdTextures
   put empty into sRdThings
end rdStop

-- ==========================================================================
-- The scene: a world for box3dxt and a picture of it for render3dxt.
-- ==========================================================================

-- A model as the TEXT of a Wavefront OBJ file: an eight-sided gem. A stack
-- that has a model file would call r3MeshLoadObj with its path instead;
-- from text, nothing is read from disk, so this demo stays one file.
function rdGemObj
   local tObj
   put "mtllib gem.mtl" & return & "usemtl gem" & return into tObj
   put "v 0 0.7 0" & return & "v 0 -0.7 0" & return after tObj
   put "v 0.5 0 0" & return & "v -0.5 0 0" & return after tObj
   put "v 0 0 0.5" & return & "v 0 0 -0.5" & return after tObj
   -- counter-clockwise seen from outside: four faces round the top point,
   -- four round the bottom
   put "f 1 3 6" & return & "f 1 6 4" & return & "f 1 4 5" & return & "f 1 5 3" & return after tObj
   put "f 2 6 3" & return & "f 2 4 6" & return & "f 2 5 4" & return & "f 2 3 5" & return after tObj
   return tObj
end rdGemObj

-- Its material file, as text: one material, a clear green.
function rdGemMtl
   return "newmtl gem" & return & "Kd 0.25 0.85 0.55" & return
end rdGemMtl

-- A checker texture and a material that wears it; both are remembered so
-- that rdStop can free them and the Textures box can take them off.
function rdCheckerMaterial pCells, pR1, pG1, pB1, pR2, pG2, pB2
   local tTexture, tMaterial
   put r3TextureChecker(64, pCells, pR1, pG1, pB1, pR2, pG2, pB2) into tTexture
   put r3MaterialCreate(255, 255, 255) into tMaterial
   put tTexture & comma after sRdTextures
   put tMaterial & comma after sRdMaterials
   put tTexture into sRdTexOfMat[tMaterial]
   return tMaterial
end rdCheckerMaterial

-- The sky's picture, as imageData: 4 pixels wide and 64 high, four bytes
-- a pixel with the first unused. Its top row is straight overhead and its
-- middle row is the horizon; below that it darkens again, for the depths
-- under the floor.
function rdSkyData
   local tData, tRow, tT, tR, tG, tB, tPixel
   repeat with tRow = 0 to 63
      if tRow < 32 then
         -- overhead to horizon, quickening as it comes down
         put (tRow / 31) ^ 3 into tT
         put 22 + (176 - 22) * tT into tR
         put 34 + (192 - 34) * tT into tG
         put 78 + (218 - 78) * tT into tB
      else
         put ((tRow - 32) / 31) ^ 0.6 into tT
         put 176 + (40 - 176) * tT into tR
         put 192 + (48 - 192) * tT into tG
         put 218 + (72 - 218) * tT into tB
      end if
      put numToByte(255) & numToByte(round(tR)) & numToByte(round(tG)) & numToByte(round(tB)) into tPixel
      put tPixel & tPixel & tPixel & tPixel after tData
   end repeat
   return tData
end rdSkyData

command rdMakeScene
   local tFloorMat, tNode, tMaterial, tGemMat, tTexture, tSkyMat
   -- the simulation: gravity down the y axis, one worker thread
   put b3WorldCreate(0, -10, 0, 1) into sRdWorld
   put b3BodyCreate(sRdWorld, 0, 0, -0.5, 0) into sRdFloorBody
   get b3ShapeAddBox(sRdFloorBody, 8, 0.5, 8, 0, 0.7, 0.1)

   -- the picture of it
   put r3SceneCreate() into sRdScene
   r3SceneSetBackground sRdScene, 26, 30, 44
   r3SceneSetAmbient sRdScene, 70, 74, 90
   -- the haze begins beyond everything that falls: it is there for the sky
   r3SceneSetFog sRdScene, 150, 170, 204, 70, 400
   r3SceneSetClip sRdScene, 0.05, 200
   get r3LightCreatePoint(sRdScene, -5, 6, 4, 255, 214, 170, 1.2, 30)
   put 0.6 into sRdYaw
   put 0.3 into sRdPitch
   rdAimCamera

   put empty into sRdMeshes
   put empty into sRdMaterials
   put empty into sRdTextures
   put empty into sRdTexOfMat
   put r3MeshBox(8, 0.5, 8) into sRdMeshes["floor"]
   put r3MeshSphere(1, 24, 16) into sRdMeshes["sky"]
   put r3MeshBox(0.5, 0.5, 0.5) into sRdMeshes["crate"]
   put r3MeshSphere(0.5, 28, 16) into sRdMeshes["ball"]
   put r3MeshParseObj(rdGemObj(), rdGemMtl()) into sRdMeshes["gem"]
   -- the gem keeps the material its own file gave it, shown as flat facets
   -- with a highlight
   put r3MeshSlotMaterial(sRdMeshes["gem"], 1) into tGemMat
   r3MaterialSetFlat tGemMat, true
   r3MaterialSetSpecular tGemMat, 0.9, 60

   -- the floor: a square a metre for each tile, in a picture big enough
   -- that the near tiles keep their edges
   put r3TextureChecker(256, 16, 222, 226, 234, 128, 138, 160) into tTexture
   put r3MaterialCreate(255, 255, 255) into tFloorMat
   put tTexture & comma after sRdTextures
   put tFloorMat & comma after sRdMaterials
   put tTexture into sRdTexOfMat[tFloorMat]
   put r3NodeCreate(sRdScene, sRdMeshes["floor"]) into tNode
   r3NodeSetMaterial tNode, tFloorMat
   r3NodeSetTransformText tNode, b3BodyTransform(sRdFloorBody)
   r3NodeSetTag tNode, sRdFloorBody

   -- the sky: the renderer clears to one colour, so the sky is a thing in
   -- the scene like any other: a great ball seen from inside, wearing a
   -- picture that runs from deep blue overhead to a pale horizon. It is
   -- unlit (no lamp reaches the sky) and tagged with nothing, so a click on
   -- it finds no body.
   put r3TextureFromImageData(rdSkyData(), 4, 64) into tTexture
   r3TextureSetRepeat tTexture, false
   put r3MaterialCreate(255, 255, 255) into tSkyMat
   r3MaterialSetTexture tSkyMat, tTexture
   r3MaterialSetUnlit tSkyMat, true
   r3MaterialSetDoubleSided tSkyMat, true
   put tTexture & comma after sRdTextures
   put tSkyMat & comma after sRdMaterials
   put r3NodeCreate(sRdScene, sRdMeshes["sky"]) into tNode
   r3NodeSetMaterial tNode, tSkyMat
   r3NodeSetScale tNode, 60, 60, 60

   put empty into sRdCrateMats
   put rdCheckerMaterial(2, 196, 148, 92, 150, 106, 60) & comma after sRdCrateMats
   put rdCheckerMaterial(2, 206, 96, 84, 160, 60, 54) & comma after sRdCrateMats
   put rdCheckerMaterial(2, 96, 150, 206, 60, 104, 160) & comma after sRdCrateMats
   put rdCheckerMaterial(4, 224, 196, 96, 170, 140, 50) & comma after sRdCrateMats
   put empty into sRdBallMats
   put rdCheckerMaterial(8, 240, 240, 240, 200, 60, 60) & comma after sRdBallMats
   put rdCheckerMaterial(8, 240, 240, 240, 60, 110, 200) & comma after sRdBallMats
   put rdCheckerMaterial(4, 250, 220, 90, 40, 40, 40) & comma after sRdBallMats
   repeat for each item tMaterial in sRdBallMats
      r3MaterialSetSpecular tMaterial, 0.6, 40
   end repeat
   put empty into sRdThings
   put 0 into sRdDropCount
end rdMakeScene

-- The camera stands on a sphere round kRdTarget; dragging moves it there.
command rdAimCamera
   local tX, tY, tZ
   put item 1 of kRdTarget + sRdDistance * cos(sRdPitch) * sin(sRdYaw) into tX
   put item 2 of kRdTarget + sRdDistance * sin(sRdPitch) into tY
   put item 3 of kRdTarget + sRdDistance * cos(sRdPitch) * cos(sRdYaw) into tZ
   r3SceneSetCamera sRdScene, tX, tY, tZ, item 1 of kRdTarget, item 2 of kRdTarget, item 3 of kRdTarget, 50
end rdAimCamera

command rdOrbitBy pDx, pDy
   if sRdScene is empty then
      exit rdOrbitBy
   end if
   subtract pDx * 0.01 from sRdYaw
   add pDy * 0.01 to sRdPitch
   -- never under the floor, never straight overhead
   put max(0.05, min(1.45, sRdPitch)) into sRdPitch
   rdAimCamera
   if sRdPaused is true then
      rdDraw
   else
      put true into sRdStale
   end if
end rdOrbitBy

-- Where the camera is, as render3dxt's camera text ("ex,ey,ez,tx,ty,tz,fov"),
-- or empty when there is no scene: for a test, or a script that is curious.
function rdCamera
   if sRdScene is empty then
      return empty
   end if
   return r3SceneCamera(sRdScene)
end rdCamera

-- A step of the wheel: a tenth nearer (pSteps below zero) or further,
-- between kRdNear and kRdFar metres.
command rdZoom pSteps
   if sRdScene is empty or pSteps is not a number then
      exit rdZoom
   end if
   put max(kRdNear, min(kRdFar, sRdDistance * (1.1 ^ pSteps))) into sRdDistance
   rdAimCamera
   if sRdPaused is true then
      rdDraw
   else
      put true into sRdStale
   end if
end rdZoom

-- One falling thing: a body with a shape in the world, a node with a mesh
-- in the scene, and the body's handle as the node's tag, which is the
-- whole link between them.
command rdAddThing pKind, pX, pY, pZ
   local tBody, tNode, tMats
   if the number of lines of sRdThings >= kRdMaxThings then
      rdRemoveThing 1
   end if
   put b3BodyCreate(sRdWorld, 2, pX, pY, pZ) into tBody
   if tBody is 0 then
      exit rdAddThing
   end if
   switch pKind
      case "ball"
         get b3ShapeAddSphere(tBody, 0, 0, 0, 0.5, 1, 0.6, 0.45)
         put sRdBallMats into tMats
         break
      case "gem"
         -- the hull of the same six points the picture's model is made of
         b3GeometryBegin
         get b3GeometryAddPoint(0, 0.7, 0)
         get b3GeometryAddPoint(0, -0.7, 0)
         get b3GeometryAddPoint(0.5, 0, 0)
         get b3GeometryAddPoint(-0.5, 0, 0)
         get b3GeometryAddPoint(0, 0, 0.5)
         get b3GeometryAddPoint(0, 0, -0.5)
         get b3ShapeAddHull(tBody, 1, 0.5, 0.2)
         put empty into tMats
         break
      default
         put "crate" into pKind
         get b3ShapeAddBox(tBody, 0.5, 0.5, 0.5, 1, 0.6, 0.1)
         put sRdCrateMats into tMats
   end switch
   -- a little spin, so that the textures are seen to turn
   b3BodySetAngularVelocity tBody, (sRdDropCount mod 3) - 1, 0.5, ((sRdDropCount + 1) mod 3) - 1
   put r3NodeCreate(sRdScene, sRdMeshes[pKind]) into tNode
   if tMats is not empty then
      r3NodeSetMaterial tNode, item (sRdDropCount mod (the number of items of tMats)) + 1 of tMats
   end if
   r3NodeSetTransformText tNode, b3BodyTransform(tBody)
   r3NodeSetTag tNode, tBody
   put tBody & comma & tNode & return after sRdThings
   add 1 to sRdDropCount
end rdAddThing

command rdRemoveThing pLine
   local tThing
   put line pLine of sRdThings into tThing
   if tThing is empty then
      exit rdRemoveThing
   end if
   r3NodeDestroy item 2 of tThing
   b3BodyDestroy item 1 of tThing
   delete line pLine of sRdThings
end rdRemoveThing

-- What is there when the window opens: a small wall of crates, and ten
-- things on their way down to knock it over (sixteen in all).
command rdFirstThings
   local tRow, tColumn, tIndex
   repeat with tRow = 0 to 2
      repeat with tColumn = 0 to 2 - tRow
         rdAddThing "crate", (tColumn - (2 - tRow) / 2) * 1.05, 0.5 + tRow * 1.0, 0
      end repeat
   end repeat
   repeat with tIndex = 1 to 10
      rdAddThing item (tIndex mod 3) + 1 of "ball,gem,crate", ((tIndex * 7) mod 9) * 0.55 - 2.2, 4 + tIndex * 1.1, ((tIndex * 5) mod 7) * 0.5 - 1.5
   end repeat
end rdFirstThings

-- ==========================================================================
-- The frame: step the world, carry the step to the picture, draw.
-- ==========================================================================

on rdFrame
   local tStarted, tSpent, tSteps, tMoved
   -- pinned at the timer's entry: a delayed handler's unqualified controls
   -- resolve against the defaultStack (docs/OXT-ENGINE-NOTES.md 5.3)
   set the defaultStack to the short name of this stack
   put empty into sRdFrameMsg
   if sRdRunning is not true then
      exit rdFrame
   end if
   put the milliseconds into tStarted
   -- 1. the picture begun a frame ago was drawn while the engine did its
   -- own work: show it (r3SceneFrame waits if it is not quite finished)
   if sRdBegun is true then
      put false into sRdBegun
      rdShow r3SceneFrame(sRdScene)
      add 1 to sRdFrames
      add 1 to sRdShown
   end if
   -- twice a second, by the clock (a scene at rest shows no pictures to
   -- count by): what fell off the floor is removed and the numbers written
   if tStarted - sRdStatsAt >= 500 then
      rdSweepFallen
      rdShowStats tStarted
   end if
   -- 2. physics by the clock: as many sixtieths as have really gone by (at
   -- most four a frame; a longer stall is forgiven, not caught up)
   if sRdPaused is not true then
      add tStarted - sRdClock to sRdOwed
      put min(4, max(0, round(sRdOwed / kRdStepMs))) into tSteps
      subtract tSteps * kRdStepMs from sRdOwed
      if sRdOwed > kRdStepMs then
         put 0 into sRdOwed
      end if
      put 0 into tMoved
      repeat tSteps
         b3WorldStep sRdWorld, 1/60, 4
         get b3WorldUpdateMoves(sRdWorld)
         add r3SceneApplyMoves(sRdScene, b3MovesText()) to tMoved
      end repeat
      if tMoved > 0 then
         put true into sRdStale
      end if
      -- the camera's own slow walk round, by the clock too: a turn takes
      -- about a minute and a half. A hand on the picture stops it.
      if sRdTurning is true and sRdDragging is not true then
         add (tStarted - sRdClock) * 0.00007 to sRdYaw
         rdAimCamera
         put true into sRdStale
      end if
   end if
   put tStarted into sRdClock
   -- 3. begin the next picture, if anything in it would differ. The call
   -- returns once the scene is read; the pixels are drawn in the background
   if sRdStale is true then
      put false into sRdStale
      put (r3SceneRenderBegin(sRdScene, kRdViewW, kRdViewH) > 0) into sRdBegun
   end if
   -- sixty frames a second when a frame costs less than a sixtieth
   put the milliseconds - tStarted into tSpent
   send "rdFrame" to me in max(1, 16 - tSpent) milliseconds
   put the result into sRdFrameMsg
end rdFrame

-- A picture drawn and shown at once (the first one, and every change made
-- while paused). It replaces any picture still in the background.
command rdDraw
   set the defaultStack to the short name of this stack
   put false into sRdBegun
   put false into sRdStale
   rdShow r3SceneRender(sRdScene, kRdViewW, kRdViewH)
end rdDraw

-- Hands a picture to the image. The engine compresses whatever is set as
-- imageData the way the paintCompression says, and a desktop engine starts
-- with "png": encoding a PNG of every frame cost three times what drawing
-- the picture did (measured 2026-11-20 on OXT-Beyond 0.2.8-dp.2: 36.6 ms a
-- frame against 6.5 with "rle"). The property is global and the paint tools
-- read it, so it is changed for this one line and put back.
command rdShow pPicture
   local tWas
   if pPicture is empty then
      exit rdShow
   end if
   put the paintCompression into tWas
   set the paintCompression to "rle"
   set the imageData of image "rdView" to pPicture
   set the paintCompression to tWas
end rdShow

-- A thing that rolled off the floor falls for ever: twice a second, the
-- ones far below it are removed.
command rdSweepFallen
   local tLine
   repeat with tLine = the number of lines of sRdThings down to 1
      if item 2 of b3BodyPosition(item 1 of line tLine of sRdThings) < -20 then
         rdRemoveThing tLine
      end if
   end repeat
end rdSweepFallen

-- The numbers under the picture, and the two that matter most on its
-- corner: pictures shown a second since the last time, and what the last
-- one cost to draw.
command rdShowStats pNow
   local tStats, tSpan
   set the defaultStack to the short name of this stack
   put r3SceneStats(sRdScene) into tStats
   if pNow is not a number then
      put the milliseconds into pNow
   end if
   put pNow - sRdStatsAt into tSpan
   if sRdShown is 0 or tSpan <= 0 then
      -- nothing moved, so nothing was drawn: that is the design, not a stall
      put "at rest" into field "rdFps"
   else
      put round(sRdShown * 1000 / tSpan) && "fps   " & format("%.1f", item 3 of tStats) && "ms" into field "rdFps"
   end if
   put 0 into sRdShown
   put pNow into sRdStatsAt
   put the number of lines of sRdThings && "things," && item 1 of tStats && "triangles;" \
         && "the last picture took" && format("%.1f", item 3 of tStats) && "ms on" && r3ThreadCount() && "threads;" \
         && b3WorldAwakeBodyCount(sRdWorld) && "bodies awake" into field "rdStats"
end rdShowStats

-- ==========================================================================
-- The buttons and the mouse.
-- ==========================================================================

-- True when there is a scene to act on; says why not otherwise.
function rdReady
   if sRdScene is not empty and sRdWorld is not empty then
      return true
   end if
   uiStatus "Nothing to do that with: an extension is missing (see above)", "bad"
   return false
end rdReady

command rdDrop pKind
   if not rdReady() then
      exit rdDrop
   end if
   -- each drop a little to one side of the last, above the floor's middle
   rdAddThing pKind, ((sRdDropCount * 7) mod 9) * 0.5 - 2, 7 + (sRdDropCount mod 3), ((sRdDropCount * 5) mod 7) * 0.5 - 1.5
   if sRdPaused is true then
      rdDraw
   else
      put true into sRdStale
   end if
end rdDrop

command rdRain
   local tIndex
   if not rdReady() then
      exit rdRain
   end if
   repeat with tIndex = 1 to 10
      rdAddThing item (tIndex mod 3) + 1 of "crate,ball,gem", ((sRdDropCount * 7) mod 9) * 0.6 - 2.4, 6 + tIndex * 1.2, ((sRdDropCount * 5) mod 7) * 0.6 - 1.8
   end repeat
   if sRdPaused is true then
      rdDraw
   else
      put true into sRdStale
   end if
end rdRain

command rdReset
   if not rdReady() then
      exit rdReset
   end if
   repeat while sRdThings is not empty
      rdRemoveThing 1
   end repeat
   put 0 into sRdDropCount
   rdFirstThings
   rdDraw
end rdReset

command rdTogglePause
   set the defaultStack to the short name of this stack
   put (sRdPaused is not true) into sRdPaused
   if sRdPaused then
      set the label of button "rdPause" to "Go on"
   else
      set the label of button "rdPause" to "Pause"
   end if
end rdTogglePause

-- Smooth edges: every pixel is the average of four samples. Sharper to
-- look at, and four times the drawing.
command rdSetSmooth pOn
   set the defaultStack to the short name of this stack
   put (pOn is true) into sRdSmooth
   rdShowToggle "rdSmooth", "Smooth edges", sRdSmooth
   if sRdScene is empty then
      exit rdSetSmooth
   end if
   if sRdSmooth then
      r3SceneSetSupersample sRdScene, 2
   else
      r3SceneSetSupersample sRdScene, 1
   end if
   if sRdPaused is true then
      rdDraw
   else
      put true into sRdStale
   end if
end rdSetSmooth

-- Textures off shows the same scene in plain lit colour: a material
-- without a texture draws its own colour.
command rdSetTextured pOn
   local tMaterial
   set the defaultStack to the short name of this stack
   put (pOn is true) into sRdTextured
   rdShowToggle "rdTextures", "Textures", sRdTextured
   if sRdScene is empty then
      exit rdSetTextured
   end if
   repeat for each key tMaterial in sRdTexOfMat
      if sRdTextured then
         r3MaterialSetTexture tMaterial, sRdTexOfMat[tMaterial]
         r3MaterialSetColor tMaterial, 255, 255, 255
      else
         r3MaterialSetTexture tMaterial, 0
         r3MaterialSetColor tMaterial, 170, 176, 190
      end if
   end repeat
   if sRdPaused is true then
      rdDraw
   else
      put true into sRdStale
   end if
end rdSetTextured

-- Turn slowly: the camera walks round the scene by itself, so every side
-- of it is seen without a hand. Off, a scene at rest costs nothing: no
-- picture is drawn until something moves.
command rdSetTurning pOn
   put (pOn is true) into sRdTurning
   rdShowToggle "rdTurn", "Turn slowly", sRdTurning
end rdSetTurning

-- A click on the picture: the node under it, the body that node is tagged
-- with, and a push at the very point that was clicked, away from the
-- camera and up.
command rdKick pPx, pPy
   local tNode, tBody, tHit, tRay
   if sRdScene is empty or sRdWorld is empty then
      exit rdKick
   end if
   put r3ScenePick(sRdScene, kRdViewW, kRdViewH, pPx, pPy) into tNode
   if tNode is 0 then
      exit rdKick
   end if
   put r3NodeTag(tNode) into tBody
   -- the sky has no body, and the floor's is not to be kicked
   if tBody is 0 or tBody is sRdFloorBody then
      exit rdKick
   end if
   put r3HitText() into tHit
   put r3SceneRay(sRdScene, kRdViewW, kRdViewH, pPx, pPy) into tRay
   if tHit is empty or tRay is empty then
      exit rdKick
   end if
   b3BodyApplyImpulse tBody, item 4 of tRay * 5, 4, item 6 of tRay * 5, item 1 of tHit, item 2 of tHit, item 3 of tHit, true
end rdKick

-- ==========================================================================
-- The boot self-check: what this stack can assert about itself without a
-- person. The control list is derived (tools/check-demo-control-lists.py).
-- ==========================================================================

constant kRdScControls = "rdDropCap,rdFps,rdHelp,rdLog,rdLogCap,rdLookCap,rdPause,rdSidePanel,rdStats,rdView,rdViewPanel,uiFooter,uiStatus,uiTitle"

-- Two comma lists of numbers, item for item, within a ten-thousandth.
function rdSameNumbers pA, pB
   local tIndex
   if pA is empty or the number of items of pA is not the number of items of pB then
      return false
   end if
   repeat with tIndex = 1 to the number of items of pA
      if item tIndex of pA is not a number or item tIndex of pB is not a number then
         return false
      end if
      if abs(item tIndex of pA - item tIndex of pB) > 0.0001 then
         return false
      end if
   end repeat
   return true
end rdSameNumbers

-- The controls whose colours are the system's to choose, which under a
-- dark theme means white words on a white panel: there should be none.
function rdThemed
   local tName, tList
   repeat for each item tName in kRdButtons
      if there is no button tName or there is no graphic (tName & "Bg") then
         put tName & "(missing)" & space after tList
      else if the foregroundColor of button tName is empty or the style of button tName is not "transparent" \
            or the backgroundColor of graphic (tName & "Bg") is empty then
         put tName & space after tList
      end if
   end repeat
   repeat for each item tName in "rdLog,rdFps,rdStats,rdHelp,uiFooter,uiStatus,uiTitle"
      if the foregroundColor of field tName is empty then
         put tName & space after tList
      end if
   end repeat
   if the backgroundColor of field "rdLog" is empty then
      put "rdLog(ground)" & space after tList
   end if
   return word 1 to -1 of tList
end rdThemed

command rdScRun
   local tMissing, tFirst, tSpot
   scBegin "rdLog"
   put scMissing(kRdScControls) into tMissing
   scAssert "all 14 controls this script names exist (missing: " & scShow(tMissing) & ")", tMissing is empty
   scAssert "the picture's image is the picture's size", the width of image "rdView" is kRdViewW and the height of image "rdView" is kRdViewH
   -- no control leaves its words or its ground to the system's theme
   scAssert "every button and the log say their own colours (" & scShow(rdThemed()) & ")", rdThemed() is empty
   if sRdHaveRender is true and sRdHavePhysics is true then
      scAssert "render3dxt answers at ABI 1 (" & scShow(r3ABIVersion()) & ")", r3ABIVersion() is 1
      scAssert "box3dxt answers (" & scShow(b3LibraryVersion()) & ")", b3LibraryVersion() is not empty
      scAssert "the first picture is width x height x 4 bytes (" & scShow(r3SceneFrameLength(sRdScene)) & ")", \
            r3SceneFrameLength(sRdScene) is kRdViewW * kRdViewH * 4
      scAssert "the image holds a picture of that size", the number of bytes of the imageData of image "rdView" is kRdViewW * kRdViewH * 4
      scAssert "one node for the floor, one for the sky and one for every body (" & scShow(r3SceneNodeCount(sRdScene)) & ")", \
            r3SceneNodeCount(sRdScene) is the number of lines of sRdThings + 2
      put item 1 of line 1 of sRdThings into tFirst
      scAssert "a body's transform is its node's transform", \
            rdSameNumbers(r3NodeTransform(r3SceneNodeByTag(sRdScene, tFirst)), b3BodyTransform(tFirst))
      put r3SceneProject(sRdScene, kRdViewW, kRdViewH, item 1 of kRdTarget, item 2 of kRdTarget, item 3 of kRdTarget) into tSpot
      scAssert "what the camera looks at is the middle of the picture (" & scShow(tSpot) & ")", \
            rdSameNumbers(item 1 to 2 of tSpot, (kRdViewW / 2) & comma & (kRdViewH / 2))
      scAssert "the gem's model came from text with its own material", \
            r3MeshTriangleCount(sRdMeshes["gem"]) is 8 and r3MeshSlotMaterial(sRdMeshes["gem"], 1) is not 0
   else
      scSkip "the scene, the picture and the join between the two", "render3dxt or box3dxt is not installed"
   end if
   scArmProbe
end rdScRun
