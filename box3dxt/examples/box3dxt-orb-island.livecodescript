-- =====================================================================
-- box3dxt-orb-island.livecodescript  /  Orb Island
--
-- A 3D game on the b3k Kit: walk a floating island 60 metres square, find
-- the sixteen golden orbs, and do not fall into the sea. A sweeper arm
-- turns in the middle, a wrecking ball swings under its gantry in the
-- north-west, a lift rides up a tower, a ramp climbs to a plateau, stairs
-- climb to a ledge, and a green jump pad throws you up to a floating
-- platform. Further out: a windmill on a round hill whose sails sweep the
-- grass, a circle of standing stones round a violet altar, a garden of
-- glowing crystals, a row of dominoes, stepping stones out over the sea
-- to a rock, and a sky lift that carries you to a floating isle with a
-- beacon. In the north-east a vault holds an orb behind a gate that a
-- pressure plate opens (push the heavy crate onto it); out east,
-- crumbling and turning platforms cross the sea to an islet; checkpoint
-- flags catch a fall. Crates and balls are there to be kicked, blasted
-- and knocked into the sea. It is late afternoon: a low warm sun,
-- lanterns, clouds. The player, flags, platforms, gate and clouds are
-- Kenney's CC0 models (box3dxt/examples/models/), carried in this file
-- between the GAME MODELS markers by box3dxt/tools/build-game-models.py.
--
-- Version 1.2 (2026-11-26) is four times the island of 1.1, which was
-- 30 metres square with eight orbs; 1.1's eight are A to H, moved out
-- with the island.
--
-- WHY THIS EXAMPLE EXISTS: it is the Kit's showcase, the 3D sibling of
-- box2dxt's games. Every system the Kit has carries part of the game:
--   * the world and the loop: b3kSetup, b3kStart, b3kPause, b3kKillFloor
--   * the view and both renderers: b3kViewMake, b3kUseRenderer (V swaps
--     render3dxt and box3dxt's own renderer when both are loaded)
--   * the look: b3kSetLight with a coloured sun, b3kSetFog, b3kSetGlow
--     (the orbs pulse, the crystals and the beacon shine), b3kAddLamp
--     (lanterns, the altar, the crystals, the beacon)
--   * the camera: b3kCamFollow (from b3kPlayerMake), b3kCamMouseOrbit,
--     b3kCamShake
--   * scenery: b3kAddGround, b3kAddStaticBox, b3kAddRamp, b3kAddPlatform
--     with b3kGlideTo (the lift and the sky lift), b3kAddStaticModel (the
--     hill, made here as OBJ text), b3kSpawn... with b3kSetType "static"
--     and b3kSetRotation (trees, stones, crystals)
--   * kinematic things: b3kSetSpin (the windmill's sails, the beacon, the
--     turning platform), b3kGlideTo (the plate and the gate)
--   * models: b3kSetLook draws a model in place of a thing's shape (the
--     player, the flags, the platforms, the gate, the clouds)
--   * joints: a motor-driven hinge (the sweeper), a rope (the wrecking
--     ball), b3kNoCollide (the arm passes through its hub)
--   * sensors: the orbs, the jump pad, the sea, the flags, the plate and
--     the crumbling platforms (b3kSensorEnter and b3kSensorExit)
--   * the player controller: b3kPlayerMake, b3kPlayerJump, b3kPlayerSteer
--     (the gamepad's stick), b3kPlayerRespawn (on b3kFell)
--   * picking: a click kicks what b3kThingAt finds, unless the press was a
--     camera drag (b3kCamDragged)
-- Two other suite extensions join in when they are loaded, and the game
-- runs without them: gamepadxt (a game controller walks, looks, jumps,
-- blasts; it rumbles when you find an orb) and audioxt (a sea that swells,
-- a chime a note higher for each orb, jumps, blasts, a splash, a fanfare:
-- tones and noise made on the spot, so there are no sound files).
-- The game's own code is short: everything below the EMBEDDED KIT line is
-- the Kit, carried verbatim from box3dxt/src/box3dxt-kit.livecodescript by
-- box3dxt/tools/sync-embedded-kit.py. Never edit it here.
--
-- HOW TO RUN
--   1. Load the box3dxt extension (and render3dxt too, if you have it, for
--      the lit, glowing look; gamepadxt and audioxt if you have them).
--   2. Open this file from start-here, or make a new stack, put this whole
--      file into its STACK script, then close and reopen the stack.
--   3. Play. Restart (R) starts a new run at any time.
--
-- CONTROLS  WASD or the arrow keys walk (forward is away from the camera)
--           / Space jumps / Q and E turn the camera / drag the view to
--           look around / click a crate or ball to kick it / X blasts what
--           is in front of you / C drops crates / V swaps the renderer /
--           M turns the sound off and on / P pauses / R restarts
-- GAMEPAD   left stick walks / right stick or the shoulders turn the
--           camera / A (south) jumps / X (west) blasts / Y (north) drops
--           crates / B (east) swaps the renderer / Start pauses / Back
--           restarts
--
-- WHAT TO VERIFY (OXT pass)
--   1. Paste and play: the window builds at 1104 x 640 with the island in
--      the view, the status line green, the sky peach and the orbs gold.
--   2. Walking: WASD and the arrows move the player relative to the camera;
--      Space jumps; Q and E turn the view; the camera follows smoothly.
--   3. The orbs: touching one removes it in a burst of sparks, shakes the
--      camera a little and counts it ("Orbs 1 / 16"); the sixteenth shows
--      the banner with the time.
--   4. The toys: the sweeper turns and pushes you; the lift carries you up
--      the tower; the jump pad throws you onto the floating platform; the
--      wrecking ball swings and knocks you; the windmill's sails sweep
--      you off the hill; the sky lift carries you to the floating isle;
--      the dominoes fall; the stepping stones can be jumped; the heavy
--      crate pushed onto the plate opens the vault; the crumbling
--      platforms shake and fall and come back; a flag touched is where a
--      fall puts you back.
--   5. Falling into the sea puts you back at the start and counts a fall;
--      a crate knocked off the edge is gone.
--   6. Mouse: dragging the view turns the camera and does NOT kick; a click
--      on a crate or ball kicks it away from the camera. Untick "Drag the
--      view to look around" and a drag does nothing.
--   7. X, C, V, M, P, R and the six buttons do what they say; V says
--      render3dxt is not loaded when it is not, M that audioxt is not.
--   8. A real gamepad: the stick walks, A jumps, the pad rumbles on an orb.
--   9. Sound: the sea, the chimes climbing, the blast, the splash, the
--      fanfare; in a web page from the first click or key press.
--  10. Every label is readable in the light and the dark appearance (each
--      control sets its own colours).
--
-- STATUS: the game's build and its rules ran on the headless Linux server
-- engine (box3dxt/tests/engine-demo.lc, OXT-Beyond 9.7.1): with box3dxt
-- alone, with no extension, and on 2026-11-26 with render3dxt, gamepadxt
-- (a virtual pad) and audioxt (its silent device) as well. In a web Stack
-- Player (web-2026.11.22, headless Chromium, 2026-11-26) version 1.2
-- built at its size, walked to an orb, found gamepadxt and audioxt, and
-- drew 32 pictures a second with the models where 1.1 drew 37 to 40 on
-- the same machine.
-- A real gamepad, the sound heard, a desktop IDE and the feel: verified
-- statically; needs an OXT pass.
-- =====================================================================

-- The suite's UI kit, carried verbatim (master tools/ui-kit.livecodescript,
-- held by the suite's tools/check-ui-kit-drift.py): the page, the title
-- band, the status line, the panels and the footer. Above the game code,
-- because a constant must be declared before its first use.
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
   -- The page ground has NO text colour, on purpose: every control on the
   -- card inherits one, and a native push button's face is the theme's -
   -- dark in the dark appearance - so kUiInk here would put dark words on
   -- it. Each builder below that puts words on a colour of the kit's sets
   -- their colour itself (tools/check-ui-kit-text-colour.py holds that).
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

-- =====================================================================
-- THE GAME. Script locals are sOi*, handlers oi*: none of them is a name
-- the Kit (below) or the UI kit (above) uses.
-- =====================================================================
-- bump when the built chrome changes, so a newer paste rebuilds it once
constant kOiUIVersion = "3"
-- the view, in card pixels: 768 x 456, five by three
constant kOiViewL = 16
constant kOiViewT = 58
constant kOiViewW = 768
constant kOiViewH = 456
-- where the player starts, and starts again after a fall: the south of
-- the island, looking north up the lantern path
constant kOiStartX = 0
constant kOiStartY = 1
constant kOiStartZ = 22
-- the island is 60 metres square (four times the 30 of version 1.1)
constant kOiIsland = 60
-- the camera's starting orbit round the player: behind it, looking north
constant kOiCamPitch = 17
constant kOiCamDist = 10
-- late afternoon: a warm sun low in the west, a peach sky, cool shade
constant kOiSky = "238,196,160"
constant kOiSea = "44,118,178"
constant kOiSun = "255,222,170"
constant kOiShade = "92,96,124"
constant kOiOrbColor = "240,190,40"
-- the orbs' glow pulses through these, one step every 250 ms
constant kOiOrbGlow = "90,60,0;140,96,0;190,130,10;140,96,0"
-- C drops no more things once the world holds this many more than the
-- island was built with
constant kOiMoreThings = 60
-- the notes of the orb chime, one a found orb, climbing a pentatonic scale
constant kOiChime = "523.25,587.33,659.25,783.99,880,1046.5,1174.66,1318.51,1567.98,1760,2093,2349.32,2637.02,3135.96,3520,4186.01"

local sOiOrb          -- [orb sensor] -> its letter, while it waits to be found
local sOiOrbCount     -- how many orbs the level has
local sOiFound        -- how many the player has found this run
local sOiFalls        -- falls off the island this run
local sOiPlayMS       -- milliseconds of play this run: the score's clock,
                      -- which stops at the last orb (pauses excluded)
local sOiClockMS      -- milliseconds since the run began, never stopped:
                      -- the toys' and the HUD's clock (pauses excluded)
local sOiDone         -- true once every orb is found
local sOiBest         -- the best time this session, in seconds
local sOiPad          -- the jump pad (a sensor)
local sOiLift         -- the tower's lift (a kinematic platform)
local sOiLiftWait     -- the clock time at which the lift moves again
local sOiSkyLift      -- the sky lift out to the floating isle
local sOiSkyWait      -- the clock time at which the sky lift moves again
local sOiBall         -- the wrecking ball
local sOiHudAt        -- the clock time of the last HUD write
local sOiHudText      -- what the HUD fields hold, to write only on change
local sOiBaseThings   -- how many things the island was built with
local sOiGlowStep     -- which step of kOiOrbGlow the orbs show
local sOiGlowAt       -- the clock time of the last glow step
local sOiSpark        -- [spark thing] -> the clock time it goes
local sOiWasGround    -- the player stood on something last frame
-- the gamepad (gamepadxt, when it is loaded)
local sOiPadOn        -- true once gpStart worked
local sOiPadNow       -- the pad in use, 0 for none
local sOiPadSteer     -- true while the stick steers the player
-- the sound (audioxt, when it is loaded)
local sOiAudio        -- the audio engine, 0 for none
local sOiAudioDevice  -- the device oiSoundStart opens: 0 the default
local sOiMuted        -- true when M has turned the sound off
local sOiSea          -- the sea's hiss, a looping noise
local sOiSeaAt        -- the clock time the sea's swell turns next
local sOiSeaUp        -- true while the swell rises
local sOiVoices       -- one line a sound to free: "handle,clock ms"
local sOiPlayed       -- the sounds played this run, by name (for the test)
local sOiModels       -- [name.obj / name.mtl] -> the model text, unpacked once
local sOiCheck        -- "x,y,z": where a fall puts the player back
local sOiFlag         -- [flag sensor] -> "x,y,z" of the checkpoint it sets
local sOiFlagGot      -- [flag sensor] -> true once the player has touched it
local sOiCrumble      -- [spot] -> "x,y,z" of a crumbling platform's home
local sOiCrumbleThing -- [spot] -> the platform now there, empty while gone
local sOiCrumbleOf    -- [sensor above a spot] -> the spot
local sOiCrumbleAt    -- [spot] -> the clock time it falls, while it shakes
local sOiCrumbleBack  -- [spot] -> the clock time it comes back, once fallen
local sOiPlate        -- the pressure plate (a kinematic platform)
local sOiPlateSensor  -- the sensor just above it
local sOiPlateOn      -- [thing] -> true while it presses the plate
local sOiPlateDown    -- true while the plate is pressed down
local sOiGate         -- the vault's gate (a kinematic platform)
local sOiGateShutAt   -- the clock time the gate shuts, once nothing presses

-- =====================================================================
-- Lifecycle
-- =====================================================================
on openStack
   oiBuildUI
   oiPadStart
   oiNewGame
   pass openStack
end openStack

on closeStack
   b3kTeardown
   oiSoundStop
   oiPadStop
   pass closeStack
end closeStack

-- A new run: a fresh world, the island, the player, the camera, go. Safe
-- at any time, from a button, a key or openStack: b3kSetup tears down the
-- old world first, and the old loop dies at its next tick.
command oiNewGame
   local tLook
   set the defaultStack to the short name of this stack
   put empty into sOiOrb
   put 0 into sOiOrbCount
   put 0 into sOiFound
   put 0 into sOiFalls
   put 0 into sOiPlayMS
   put 0 into sOiClockMS
   put false into sOiDone
   put empty into sOiPad
   put empty into sOiLift
   put 0 into sOiLiftWait
   put empty into sOiSkyLift
   put 0 into sOiSkyWait
   put empty into sOiBall
   put 0 into sOiHudAt
   put empty into sOiHudText
   put 1 into sOiGlowStep
   put 0 into sOiGlowAt
   put empty into sOiSpark
   put true into sOiWasGround
   put false into sOiPadSteer
   put empty into sOiPlayed
   put kOiStartX & comma & kOiStartY & comma & kOiStartZ into sOiCheck
   put empty into sOiFlag
   put empty into sOiFlagGot
   put empty into sOiCrumble
   put empty into sOiCrumbleThing
   put empty into sOiCrumbleOf
   put empty into sOiCrumbleAt
   put empty into sOiCrumbleBack
   put empty into sOiPlate
   put empty into sOiPlateSensor
   put empty into sOiPlateOn
   put false into sOiPlateDown
   put empty into sOiGate
   put 0 into sOiGateShutAt
   if there is a field "oiBanner" then hide field "oiBanner"
   b3kSetup
   if b3kWorld() is empty then
      uiStatus "Nothing can run: " & b3kLastError() & ". Load the box3dxt extension, then press Restart.", "bad"
      oiHud
      exit oiNewGame
   end if
   b3kViewMake kOiViewL, kOiViewT, kOiViewW, kOiViewH
   b3kSetBackground kOiSky
   -- the fog starts past the middle of the island and swallows the far
   -- sea: it hides the sea's edge and keeps the far side soft
   b3kSetFog kOiSky, 36, 84
   b3kSetLight 0.62, -0.62, -0.48, kOiSun
   b3kSetAmbient kOiShade
   -- In a web page render3dxt draws on ONE thread, inside the frame: with
   -- smooth edges (each pixel the average of 2 x 2 samples, the Kit's
   -- default) that was 57 ms of every frame and the game ran at 14
   -- pictures a second in the gallery's player (2026-11-22). Single
   -- samples cost 15 ms. A desktop draws on every core in the background
   -- and keeps the smooth edges.
   if oiOnWeb() then b3kSetSmooth 1
   oiBuildIsland
   put b3kThingCount() into sOiBaseThings
   b3kPlayerMake kOiStartX, kOiStartY, kOiStartZ, "capsule", "61,110,200"
   -- the player collides as the Kit's capsule and looks like Kenney's
   -- character, fitted to the capsule's 1.6 m (render3dxt; box3dxt's
   -- renderer draws the capsule)
   oiLook b3kPlayer(), "character"
   -- a little quicker than the Kit's 5 m/s: the island is four times as big
   b3kPlayerSet "moveSpeed", 6.5
   -- the orbit's target given too: the camera starts ON the player, where
   -- following alone would swoop in from the middle of the island
   b3kCamOrbit 0, kOiCamPitch, kOiCamDist, kOiStartX, kOiStartY + 0.8, kOiStartZ
   -- two steps, not one `and`: the engine may evaluate both sides of an
   -- `and` (suite engine note 2.5), and the hilite of a missing button throws
   put true into tLook
   if there is a button "oiLook" then put the hilite of button "oiLook" into tLook
   b3kCamMouseOrbit tLook
   -- below the sea: a fall into the sea is a fall
   b3kKillFloor -6
   b3kStart
   oiRendererLabel
   if there is a button "oiPause" then set the label of button "oiPause" to "Pause (P)"
   -- one audio engine for the session, made at the first run: in a web
   -- page the browser unlocks sound once, and a new engine is not unlocked
   if not oiSoundOn() then oiSoundStart
   oiSoundLabel
   oiHud
   uiStatus "Find the " & sOiOrbCount & " golden orbs. " & oiRendererWords(), "ok"
end oiNewGame

-- =====================================================================
-- The island, in metres: y up, the start in the south (+z), the camera
-- looking north (-z). Every piece is placed by hand; the comments give
-- the arithmetic where two pieces must meet. Version 1.1's island, 30
-- metres square, is the middle of this one, spread out; the corners,
-- the sea, the sky and the floating isle are new.
-- =====================================================================
command oiBuildIsland
   local tHub, tArm, tJoint, tHook, tThing, tI, tA
   -- the south: the start, a crate pyramid and two balls to kick and blast,
   -- and a lantern path north to the plaza
   oiCrate 4.1, 0.425, 18
   oiCrate 5, 0.425, 18
   oiCrate 5.9, 0.425, 18
   oiCrate 4.55, 1.275, 18
   oiCrate 5.45, 1.275, 18
   oiCrate 5, 2.125, 18
   b3kSpawnBall -4, 0.5, 19, 1, "235,90,80"
   put the result into tThing
   b3kSetBounce tThing, 0.6
   b3kSpawnBall -5, 0.4, 17.5, 0.8, "90,150,235"
   put the result into tThing
   b3kSetBounce tThing, 0.6
   oiLantern -2.6, 12, true
   oiLantern 2.6, 12, false
   oiLantern -2.6, 5, false
   oiLantern 2.6, 5, true

   -- the middle: a 9 metre arm turning round a hub, low enough to jump.
   -- The hub is a step to stand on (1 m), the arm passes through it
   -- (b3kNoCollide), and a strong motor keeps it turning at 45 degrees a
   -- second whatever it pushes. Four stones mark the plaza's corners.
   b3kSpawnCylinder 0, 0.5, 0, 1, 1.8, "120,124,136"
   put the result into tHub
   b3kSetType tHub, "static"
   b3kName tHub, "hub"
   b3kSpawnBox 0, 0.45, 0, 9, 0.5, 0.4, "220,70,60"
   put the result into tArm
   b3kName tArm, "arm"
   b3kNoCollide tArm, tHub
   b3kHinge tArm, empty, 0, 0.45, 0, 0, 1, 0
   put the result into tJoint
   b3kMotor tJoint, 45, 800
   repeat for each item tA in "45,135,225,315"
      oiStatic "cylinder", 6.5 * sin(tA * pi / 180), 0.6, 6.5 * cos(tA * pi / 180), 1.2, 0.9, "176,170,160"
   end repeat

   -- the east: a plateau 2 m high and a 20 degree ramp up to it from the
   -- south. The ramp's far top edge must meet the plateau's top (y 2) at
   -- its south face (z 1): with length 5.5 and thickness 0.3 that puts
   -- the ramp's centre at y 0.92, z 3.58.
   b3kAddStaticBox 18.5, 1, -2, 6, 2, 6, "206,180,132"
   b3kAddRamp 18.5, 0.92, 3.58, 3, 0.3, 5.5, 20

   -- the north-east: a tower 5 m high and its lift, 0.3 m from its west
   -- face (x 16.5); the lift rides from the ground to just above the top
   b3kAddStaticBox 18.5, 2.5, -14, 4, 5, 4, "180,156,134"
   b3kAddPlatform 14.9, 0.2, -14, 2.6, 0.4, 2.6, "70,180,190"
   put the result into sOiLift
   b3kName sOiLift, "lift"

   -- the west: five steps of half a metre up to a ledge 3 m high
   put 1 into tI
   repeat while tI <= 5
      b3kAddStaticBox -18, 0.25 * tI, 5 - 1.2 * tI, 2.4, 0.5 * tI, 1.2, "156,164,184"
      add 1 to tI
   end repeat
   b3kAddStaticBox -18, 1.5, -3.6, 2.4, 3, 4, "156,164,184"

   -- the north-west: a wrecking ball on a 4.5 m rope from a hook 5.2 m
   -- up, let go 60 degrees out, so it skims the grass at the bottom; the
   -- hook hangs from a gantry
   b3kAddStaticBox -12, 5.2, -14, 0.4, 0.4, 0.4, "80,82,92"
   put the result into tHook
   oiStatic "box", -12, 5.55, -14, 0.4, 0.3, 7, "96,98,110"
   oiStatic "box", -12, 2.7, -17.4, 0.4, 5.4, 0.4, "96,98,110"
   oiStatic "box", -12, 2.7, -10.6, 0.4, 5.4, 0.4, "96,98,110"
   b3kSpawnBall -8.1, 2.95, -14, 1.2, "64,66,76"
   put the result into sOiBall
   b3kName sOiBall, "wrecking ball"
   b3kSetDensity sOiBall, 4
   b3kRope tHook, sOiBall, 4.5

   -- the north: a jump pad, and the floating platform it reaches. The pad
   -- is a sensor (the player passes into it); b3kSensorEnter throws.
   b3kAddSensorBox 0, 0.1, -16, 1.6, 0.2, 1.6
   put the result into sOiPad
   b3kName sOiPad, "jump pad"
   b3kSetVisible sOiPad, true
   b3kSetColor sOiPad, "90,200,110"
   b3kSetGlow sOiPad, "20,90,30"
   b3kAddStaticBox 0, 3.5, -19, 3, 0.4, 3, "206,180,132"

   oiBuildCorners
   oiBuildSkyIsle
   oiBuildTrees
   oiBuildVault
   oiBuildEastIslet
   oiFlag "west rock", -46.1, 2.4, 3.4
   oiFlag "sky isle", -3.5, 4.5, -39

   -- sixteen orbs, from the easy one on the lantern path to the floating
   -- isle: A to H are version 1.1's eight, moved out with the island
   oiOrb "A", 0, 0.8, 16.5
   oiOrb "B", -6.5, 0.8, 19.5
   oiOrb "C", 0, 1.75, 0
   oiOrb "D", 19.5, 2.8, -3
   oiOrb "E", 19, 5.8, -14.5
   oiOrb "F", -12, 0.8, -14
   oiOrb "G", -18, 3.8, -4.5
   oiOrb "H", 0, 4.4, -19
   oiOrb "I", 50.5, 0.8, 1.5
   oiOrb "J", -16, 2.6, 19.5
   oiOrb "K", 8, 0.8, -24.5
   oiOrb "L", 3, 5.3, -40
   oiOrb "M", 4, 5.3, -46.5
   oiOrb "N", -45, 3.2, 4.5
   oiOrb "O", -20, 1.6, -22
   -- P waits in the vault, behind the gate the pressure plate opens
   oiOrb "P", 26, 0.8, -26

   -- LAST, the grass and the sea: render3dxt draws in the order things were
   -- made, and a pixel of grass already hidden by a tree or a stone is then
   -- refused by its depth alone, never textured or fogged. Made first, the
   -- grass under everything was drawn in full and drawn over (in a web
   -- page, on one thread, the difference shows; 2026-11-26).
   -- 60 by 60 metres of grass, its top at y = 0; no walls: the sea is
   -- the danger
   b3kAddGround kOiIsland, 0, "132,190,98", "110,166,84"
   oiSeaAndSky
end oiBuildIsland

-- The sea all round and the clouds. The sea is four sensors (a fall
-- passes through it to the kill floor below) round the island, made
-- after the grass: drawn first, every pixel of sea under the grass was
-- drawn and then drawn over, and in a web page, where render3dxt draws on
-- one thread, that was about a tenth of every frame (measured on the
-- server engine with one thread, 2026-11-26). Rock under the island was
-- dropped for the same reason. The sea ends 40 m out, where the fog has
-- all but swallowed it: beyond, the sky colour is cleared, not drawn.
command oiSeaAndSky
   local tCloud
   -- each strip reaches 12 m in under the grass: a look past the shore
   -- from above meets the sea under the island's edge, and strips that
   -- stopped at the shore left the sky colour showing there (2026-11-26).
   -- Made after the grass, the part under it costs a depth test only
   oiSea "north", 0, -54, 140, 72
   oiSea "south", 0, 54, 140, 72
   oiSea "west", -44, 0, 52, 60
   oiSea "east", 44, 0, 52, 60
   -- clouds: white balls that glow a little, so their shade stays light
   repeat for each line tCloud in "-22,17,-12" & return & "16,19,10" & return & "6,16,-36" & return & "-30,18,22"
      oiCloud item 1 of tCloud, item 2 of tCloud, item 3 of tCloud
   end repeat
end oiSeaAndSky

-- one stretch of sea, 4 m below the grass
command oiSea pName, pX, pZ, pW, pD
   local tSea
   b3kAddSensorBox pX, -4, pZ, pW, 0.2, pD
   put the result into tSea
   if tSea is empty then exit oiSea
   b3kSetVisible tSea, true
   b3kSetColor tSea, kOiSea
   b3kSetGlow tSea, "12,36,60"
   b3kName tSea, "sea " & pName
end oiSea

command oiRock pX, pY, pZ, pHeight, pDiameter
   b3kSpawnCone pX, pY, pZ, pHeight, pDiameter, "112,96,84"
   oiFix the result, 180, 0, 0
end oiRock

-- A cloud: a sensor (nothing stands on it) that looks like Kenney's
-- cloud; box3dxt's renderer shows its box in white.
command oiCloud pX, pY, pZ
   local tCloud
   b3kAddSensorBox pX, pY, pZ, 7, 3.2, 5
   put the result into tCloud
   if tCloud is empty then exit oiCloud
   b3kSetVisible tCloud, true
   b3kSetColor tCloud, "250,246,242"
   oiLook tCloud, "cloud"
end oiCloud

-- The four corners and the far west: dominoes, a windmill hill, a stone
-- circle, a crystal garden and stepping stones out over the sea.
command oiBuildCorners
   local tI, tA, tThing, tX, tY, tH, tCrystal
   -- the south-east: sixteen dominoes in a row; walk into the first
   put 0 into tI
   repeat while tI < 16
      if tI mod 2 is 0 then
         b3kSpawnBox 11 + 0.85 * tI, 0.7, 26, 0.2, 1.4, 0.7, "236,232,220"
         put the result into tThing
      else
         b3kSpawnBox 11 + 0.85 * tI, 0.7, 26, 0.2, 1.4, 0.7, "40,44,56"
         put the result into tThing
      end if
      if tI is 0 then b3kName tThing, "first domino"
      add 1 to tI
   end repeat

   -- the south-west: a round hill, 3 m high, and a windmill on top whose
   -- sails sweep down to just above the grass (kinematic: they turn at a
   -- set speed and no push slows them)
   b3kAddStaticModel -16, 0, 16, oiHillObj(8, 3, 7, 20), 1, "118,176,90"
   b3kName the result, "hill"
   oiStatic "cylinder", -16, 4.9, 16, 4.2, 1.1, "236,226,206"
   oiStatic "cone", -16, 7.5, 16, 1.2, 1.6, "170,70,60"
   repeat for each item tA in "0,90"
      b3kSpawnBox -16, 6.4, 16.8, 6, 0.45, 0.12, "246,240,228"
      put the result into tThing
      b3kSetType tThing, "kinematic"
      b3kSetRotation tThing, 0, 0, tA
      b3kSetSpin tThing, 0, 0, 70
      b3kName tThing, "sail " & tA
   end repeat

   -- the north-west corner: a circle of eight standing stones round a
   -- glowing altar, lit violet
   repeat with tI = 0 to 7
      put tI * 45 into tA
      oiStatic "box", -20 + 4.2 * sin(tA * pi / 180), 1.3, -22 + 4.2 * cos(tA * pi / 180), 1.2, 2.6, 0.7, "150,152,160"
      oiFix the result, 0, tA, 0
   end repeat
   oiStatic "cylinder", -20, 0.3, -22, 0.6, 1.4, "120,96,170"
   b3kSetGlow the result, "70,40,120"
   b3kAddLamp -20, 2.4, -22, "190,140,255", 9, 1.6

   -- the north, west of the tower: a garden of crystals that glow cyan
   repeat for each line tCrystal in "6,-24,3.2,0,10" & return & "9.6,-25.5,2.4,14,-8" & return & "7,-27.4,2,-12,20" & return & \
         "10.4,-23,1.6,0,-22" & return & "5,-22.6,1.8,16,0" & return & "11,-27,2.8,-6,0" & return & "4.4,-26.6,1.4,0,24"
      put item 3 of tCrystal into tH
      b3kSpawnCone item 1 of tCrystal, tH / 2, item 2 of tCrystal, tH, 0.5 * tH, "150,226,240"
      put the result into tThing
      oiFix tThing, item 4 of tCrystal, 0, item 5 of tCrystal
      b3kSetGlow tThing, "30,110,140"
   end repeat
   b3kAddLamp 7.5, 1.6, -25, "120,230,255", 7, 1.8

   -- the far north-east: a stack of crates to climb by the tower
   oiStatic "box", 26, 0.5, -21, 1, 1, 1, "176,124,74"

   -- the west, past the edge (x -30): stepping stones over the sea to a
   -- rock. Each top is 0.6 m above the last and 1.4 m on: a run and a
   -- jump each.
   repeat with tI = 0 to 3
      put -32.5 - 3 * tI into tX
      put 0.6 * tI - 0.25 into tY
      oiStatic "box", tX, tY, 6 - 0.6 * tI, 1.6, 0.5, 1.6, "150,150,156"
      oiRock tX, tY - 1.4, 6 - 0.6 * tI, 2.2, 1.4
   end repeat
   oiStatic "box", -45, 1.2, 4.5, 3, 2.4, 3, "136,128,120"
   oiRock -45, -1.5, 4.5, 4, 3
end oiBuildCorners

-- The floating isle in the north, over the sea, and the sky lift that
-- carries the player out to it: from a dock at the island's north edge
-- (its top at y 0.4) up to the isle's south edge (its top at y 4.5).
command oiBuildSkyIsle
   local tBeam, tIsle
   b3kAddStaticBox 0, 4, -43, 12, 1, 12, "132,190,98"
   put the result into tIsle
   b3kSetChecker tIsle, "132,190,98", "110,166,84", 12
   oiRock 0, -1.5, -43, 10, 12
   b3kAddPlatform 0, 0.2, -27.5, 2.6, 0.4, 2.6, "230,150,60"
   put the result into sOiSkyLift
   b3kName sOiSkyLift, "sky lift"
   -- the beacon: a white tower, a glowing lamp and a beam that sweeps
   oiStatic "cylinder", -3, 7, -46, 5, 1.4, "240,236,226"
   oiStatic "cylinder", -3, 8.2, -46, 0.5, 1.5, "200,60,52"
   oiStatic "ball", -3, 9.9, -46, 1.4, "255,236,170"
   b3kSetGlow the result, "255,200,90"
   b3kSpawnBox -3, 9.9, -46, 10, 0.22, 0.22, "255,240,190"
   put the result into tBeam
   b3kSetType tBeam, "kinematic"
   b3kSetGlow tBeam, "255,210,120"
   b3kSetSpin tBeam, 0, 60, 0
   b3kName tBeam, "beacon beam"
   b3kAddLamp -3, 9.9, -46, "255,210,140", 14, 2
end oiBuildSkyIsle

-- Trees round the island: a trunk and two cones of leaves.
command oiBuildTrees
   local tTree, tS
   repeat for each line tTree in "-9,25,1" & return & "-12,9,1.2" & return & "9,10,0.9" & return & "12,23,1.1" & return & \
         "-24,25,1.3" & return & "-26,-6,1" & return & "25,7,1.2" & return & "26,-7,0.9" & return & \
         "-6,-26,1.1" & return & "15,-26,1" & return & "-26,11,0.9" & return & "-25,-15,1"
      put item 3 of tTree into tS
      oiStatic "cylinder", item 1 of tTree, 0.8 * tS, item 2 of tTree, 1.6 * tS, 0.42 * tS, "120,84,56"
      oiStatic "cone", item 1 of tTree, 2.5 * tS, item 2 of tTree, 2.4 * tS, 2.6 * tS, "64,128,70"
      oiStatic "cone", item 1 of tTree, 3.6 * tS, item 2 of tTree, 1.8 * tS, 1.8 * tS, "78,148,80"
   end repeat
end oiBuildTrees

-- A lantern post; pLamp hangs one of the Kit's lamps in it as well (a
-- world holds seven, so not every post has one).
command oiLantern pX, pZ, pLamp
   oiStatic "cylinder", pX, 1.1, pZ, 2.2, 0.16, "60,58,66"
   oiStatic "ball", pX, 2.35, pZ, 0.45, "255,226,150"
   b3kSetGlow the result, "255,170,60"
   if pLamp is true then b3kAddLamp pX, 2.35, pZ, "255,190,110", 7, 1.6
end oiLantern

-- Static scenery of any shape: a thing spawned, then fixed in place. The
-- thing is left in the result.
command oiStatic pKind, pX, pY, pZ, pA, pB, pC, pColor
   local tThing
   switch pKind
      case "cylinder"
         b3kSpawnCylinder pX, pY, pZ, pA, pB, pC
         break
      case "cone"
         b3kSpawnCone pX, pY, pZ, pA, pB, pC
         break
      case "ball"
         b3kSpawnBall pX, pY, pZ, pA, pB
         break
      default
         b3kSpawnBox pX, pY, pZ, pA, pB, pC, pColor
   end switch
   put the result into tThing
   if tThing is not empty then b3kSetType tThing, "static"
   return tThing
end oiStatic

-- a thing made static and turned (degrees); the thing is left in the result
command oiFix pThing, pRx, pRy, pRz
   if pThing is empty then return empty
   b3kSetType pThing, "static"
   b3kSetRotation pThing, pRx, pRy, pRz
   return pThing
end oiFix

-- A round hill as Wavefront OBJ text: pRings rings of pSegments points
-- round a top, its height falling as a cosine from pHeight at the middle
-- to 0 at radius pRadius. Each triangle's corners run counter-clockwise
-- seen from above, so its front faces up and the player stands on it
-- (a mesh is one-sided, box3dxt's CLAUDE.md).
function oiHillObj pRadius, pHeight, pRings, pSegments
   local tObj, tR, tS, tRad, tA, tY, tA0, tA1, tB0, tB1, tTop
   put "v 0 " & pHeight & " 0" & return into tObj
   repeat with tR = 1 to pRings
      put pRadius * tR / pRings into tRad
      put pHeight * (0.5 + 0.5 * cos(pi * tR / pRings)) into tY
      repeat with tS = 0 to pSegments - 1
         put 2 * pi * tS / pSegments into tA
         put "v " & format("%.4f", tRad * cos(tA)) && format("%.4f", tY) && format("%.4f", tRad * sin(tA)) & return after tObj
      end repeat
   end repeat
   -- the top: a fan from vertex 1 to ring 1 (vertices 2 .. pSegments + 1)
   repeat with tS = 0 to pSegments - 1
      put 2 + tS into tA0
      put 2 + ((tS + 1) mod pSegments) into tA1
      put "f 1 " & tA1 && tA0 & return after tObj
   end repeat
   -- each band between ring tR and ring tR + 1: two triangles a segment
   repeat with tR = 1 to pRings - 1
      put 2 + (tR - 1) * pSegments into tTop
      repeat with tS = 0 to pSegments - 1
         put tTop + tS into tA0
         put tTop + ((tS + 1) mod pSegments) into tA1
         put tA0 + pSegments into tB0
         put tA1 + pSegments into tB1
         put "f " & tA0 && tA1 && tB1 & return after tObj
         put "f " & tA0 && tB1 && tB0 & return after tObj
      end repeat
   end repeat
   return tObj
end oiHillObj

command oiCrate pX, pY, pZ
   b3kSpawnBox pX, pY, pZ, 0.85, 0.85, 0.85, "176,124,74"
end oiCrate

-- An orb is a sensor ball the player passes into, made visible, gold and
-- glowing.
command oiOrb pLetter, pX, pY, pZ
   local tOrb
   b3kAddSensorBall pX, pY, pZ, 0.7
   put the result into tOrb
   if tOrb is empty then exit oiOrb
   b3kSetVisible tOrb, true
   b3kSetColor tOrb, kOiOrbColor
   b3kSetGlow tOrb, oiGlowStep(1)
   b3kName tOrb, "orb " & pLetter
   put pLetter into sOiOrb[tOrb]
   add 1 to sOiOrbCount
end oiOrb

-- step pStep of the orbs' pulse, as "r,g,b"
function oiGlowStep pStep
   set the itemDelimiter to ";"
   get item pStep of kOiOrbGlow
   set the itemDelimiter to comma
   return it
end oiGlowStep

-- =====================================================================
-- Kenney's models (CC0, see box3dxt/examples/models/README.md), carried
-- in this script by tools/build-game-models.py: each thing still
-- collides as its own simple shape and only LOOKS like the model
-- =====================================================================
function oiModel pName
   if sOiModels[pName] is empty then
      put oiModelData(pName) into sOiModels[pName]
      if sOiModels[pName] is not empty then
         put decompress(base64Decode(sOiModels[pName])) into sOiModels[pName]
      end if
   end if
   return sOiModels[pName]
end oiModel

command oiLook pThing, pName
   if pThing is empty then exit oiLook
   b3kSetLook pThing, oiModel(pName & ".obj"), oiModel(pName & ".mtl")
end oiLook

-- =====================================================================
-- Platformer pieces: a pressure plate and the vault it opens, crumbling
-- and turning platforms out to an islet, and checkpoint flags
-- =====================================================================

-- The north-east vault: three walls 3.2 m high round orb P and a gate on
-- the south. The gate sinks into the ground while something presses the
-- plate, 7 m away, and rises again under a second after nothing does:
-- too soon for the player to run from the plate, so the heavy crate must
-- be pushed (or kicked, or blasted) onto it.
command oiBuildVault
   local tCrate
   oiStatic "box", 23.5, 1.6, -26, 0.6, 3.2, 5.6, "150,128,112"
   oiStatic "box", 28.5, 1.6, -26, 0.6, 3.2, 5.6, "150,128,112"
   oiStatic "box", 26, 1.6, -28.5, 5.6, 3.2, 0.6, "150,128,112"
   b3kAddPlatform 26, 1.6, -23.5, 5, 3.2, 0.6, "170,96,70"
   put the result into sOiGate
   b3kName sOiGate, "gate"
   oiLook sOiGate, "gate"
   b3kAddPlatform 22, 0.12, -17, 2.2, 0.24, 2.2, "220,200,90"
   put the result into sOiPlate
   b3kName sOiPlate, "plate"
   oiLook sOiPlate, "plate"
   b3kAddSensorBox 22, 0.6, -17, 1.8, 0.8, 1.8
   put the result into sOiPlateSensor
   b3kSpawnBox 19.5, 0.6, -19.5, 1.2, 1.2, 1.2, "150,104,60"
   put the result into tCrate
   b3kName tCrate, "heavy crate"
   b3kSetDensity tCrate, 0.6
end oiBuildVault

-- Out east, over the sea: three crumbling platforms and one that turns,
-- 1.2 m apart, to a small islet with orb I and a checkpoint. A crumbling
-- platform shakes for 0.6 s once stood on, falls, and is back 4.5 s later.
command oiBuildEastIslet
   local tTurn, tIsle
   oiCrumbleSpot 1, 32, -0.25, 0
   b3kAddPlatform 36, -0.3, 0, 3, 0.6, 3, "200,170,110"
   put the result into tTurn
   b3kName tTurn, "turning platform"
   b3kSetSpin tTurn, 0, 32, 0
   oiLook tTurn, "platform"
   oiCrumbleSpot 2, 40, -0.25, 0
   oiCrumbleSpot 3, 43.6, -0.25, 0
   b3kAddStaticBox 49.5, -0.5, 0, 7, 1, 7, "132,190,98"
   put the result into tIsle
   b3kName tIsle, "east islet"
   b3kSetChecker tIsle, "132,190,98", "110,166,84", 7
   oiRock 49.5, -2.6, 0, 4.2, 6
   oiFlag "east islet", 51.5, 0, -2.2
end oiBuildEastIslet

command oiCrumbleSpot pSpot, pX, pY, pZ
   local tSensor
   put pX & comma & pY & comma & pZ into sOiCrumble[pSpot]
   oiCrumbleMake pSpot
   -- the sensor stays when the platform falls: it only arms the platform
   b3kAddSensorBox pX, pY + 0.5, pZ, 2.2, 0.5, 2.2
   put the result into tSensor
   if tSensor is not empty then put pSpot into sOiCrumbleOf[tSensor]
end oiCrumbleSpot

command oiCrumbleMake pSpot
   local tHome, tThing
   put sOiCrumble[pSpot] into tHome
   set the itemDelimiter to comma
   b3kAddStaticBox item 1 of tHome, item 2 of tHome, item 3 of tHome, 2.4, 0.5, 2.4, "196,150,96"
   put the result into tThing
   put tThing into sOiCrumbleThing[pSpot]
   b3kName tThing, "crumble " & pSpot
   oiLook tThing, "crumble"
   put empty into sOiCrumbleAt[pSpot]
   put empty into sOiCrumbleBack[pSpot]
end oiCrumbleMake

command oiTickCrumble
   local tSpot, tThing, tHome
   repeat for each key tSpot in sOiCrumble
      put sOiCrumbleThing[tSpot] into tThing
      if sOiCrumbleAt[tSpot] is not empty then
         if not b3kIsThing(tThing) then
            put empty into sOiCrumbleAt[tSpot]
         else if sOiClockMS >= sOiCrumbleAt[tSpot] then
            -- it lets go: a falling body the sea's kill floor removes
            b3kSetRotation tThing, 0, 0, 0
            b3kSetType tThing, "dynamic"
            -- scenery is made weightless; a weightless moving body never moves
            b3kSetDensity tThing, 1
            b3kPush tThing, 0, -1, 0
            put empty into sOiCrumbleAt[tSpot]
            put sOiClockMS + 4500 into sOiCrumbleBack[tSpot]
         else
            -- the shake: a few degrees this way and that
            b3kSetRotation tThing, random(7) - 4, 0, random(7) - 4
         end if
      else if sOiCrumbleBack[tSpot] is not empty and sOiClockMS >= sOiCrumbleBack[tSpot] then
         if b3kIsThing(tThing) then b3kRemove tThing
         oiCrumbleMake tSpot
      end if
   end repeat
end oiTickCrumble

-- The plate: down while anything presses it, the gate sinking with it.
command oiTickPlate
   local tPressed, tThing
   if sOiPlate is empty or not b3kIsThing(sOiPlate) then exit oiTickPlate
   put false into tPressed
   repeat for each key tThing in sOiPlateOn
      if b3kIsThing(tThing) then
         put true into tPressed
      else
         delete variable sOiPlateOn[tThing]
      end if
   end repeat
   if tPressed then
      put 0 into sOiGateShutAt
      if sOiPlateDown is not true then
         put true into sOiPlateDown
         b3kGlideTo sOiPlate, 22, 0.02, -17, 0.15
         b3kGlideTo sOiGate, 26, -1.75, -23.5, 0.9
         oiSound "plate"
         uiStatus "Click! Something in the north-east rumbles open.", "ok"
      end if
   else if sOiPlateDown is true then
      if sOiGateShutAt is 0 then put sOiClockMS + 800 into sOiGateShutAt
      if sOiClockMS >= sOiGateShutAt then
         put false into sOiPlateDown
         put 0 into sOiGateShutAt
         b3kGlideTo sOiPlate, 22, 0.12, -17, 0.15
         b3kGlideTo sOiGate, 26, 1.6, -23.5, 0.9
         oiSound "gate"
      end if
   end if
end oiTickPlate

function oiPlateIsDown
   return (sOiPlateDown is true)
end oiPlateIsDown

-- A checkpoint: Kenney's flag on a sensor. Touched, it is where a fall
-- puts the player back, until another is touched or the run restarts.
command oiFlag pName, pX, pTop, pZ
   local tFlag
   b3kAddSensorBox pX, pTop + 1.2, pZ, 1.4, 2.4, 1.4
   put the result into tFlag
   if tFlag is empty then exit oiFlag
   b3kSetVisible tFlag, true
   b3kSetColor tFlag, "230,70,60"
   b3kName tFlag, "flag " & pName
   oiLook tFlag, "flag"
   put pX & comma & (pTop + 1) & comma & pZ into sOiFlag[tFlag]
end oiFlag

function oiCheckpoint
   return sOiCheck
end oiCheckpoint

-- =====================================================================
-- The Kit's messages
-- =====================================================================
on b3kFrame
   local tMs
   -- a frame after a long stall (a dialog, a drag of the window) counts as
   -- a tenth of a second at most
   put min(100, b3kFrameMS()) into tMs
   add tMs to sOiClockMS
   if sOiDone is not true then
      add tMs to sOiPlayMS
   end if
   oiPadTick
   oiTickLift
   oiTickSkyLift
   oiTickBall
   oiTickCrumble
   oiTickPlate
   oiTickGlow
   oiTickSparks
   oiTickJump
   oiSoundTick
   if sOiClockMS - sOiHudAt >= 250 then
      oiHud
   end if
end b3kFrame

on b3kSensorEnter pSensor, pVisitor
   if pVisitor is empty then exit b3kSensorEnter
   -- the plate counts anything that moves: the player, a crate, a ball
   if pSensor is sOiPlateSensor then
      if b3kType(pVisitor) is "dynamic" then put true into sOiPlateOn[pVisitor]
      exit b3kSensorEnter
   end if
   if pVisitor is not b3kPlayer() then
      exit b3kSensorEnter
   end if
   if sOiCrumbleOf[pSensor] is not empty then
      oiCrumbleArm sOiCrumbleOf[pSensor]
      exit b3kSensorEnter
   end if
   if sOiFlag[pSensor] is not empty then
      if sOiCheck is not sOiFlag[pSensor] then
         put sOiFlag[pSensor] into sOiCheck
         put true into sOiFlagGot[pSensor]
         oiSparks b3kX(pSensor), b3kY(pSensor) + 1, b3kZ(pSensor)
         oiSound "check"
         uiStatus "Checkpoint: a fall now brings you back here.", "ok"
      end if
      exit b3kSensorEnter
   end if
   if pSensor is sOiPad then
      b3kPlayerJump 10.5
      oiSound "pad"
      exit b3kSensorEnter
   end if
   if sOiOrb[pSensor] is not empty then
      oiSparks b3kX(pSensor), b3kY(pSensor), b3kZ(pSensor)
      delete variable sOiOrb[pSensor]
      b3kRemove pSensor
      add 1 to sOiFound
      b3kCamShake 0.06, 120
      oiRumble 0.35, 0.5, 140
      oiHud
      if sOiFound >= sOiOrbCount then
         oiWin
      else
         oiSound "orb"
         uiStatus "Orb found: " & sOiFound & " of " & sOiOrbCount & ".", "ok"
      end if
   end if
end b3kSensorEnter

on b3kSensorExit pSensor, pVisitor
   if pSensor is not empty and pSensor is sOiPlateSensor then
      delete variable sOiPlateOn[pVisitor]
   end if
end b3kSensorExit

command oiCrumbleArm pSpot
   if sOiCrumbleAt[pSpot] is not empty or sOiCrumbleBack[pSpot] is not empty then exit oiCrumbleArm
   if not b3kIsThing(sOiCrumbleThing[pSpot]) then exit oiCrumbleArm
   put sOiClockMS + 600 into sOiCrumbleAt[pSpot]
   oiSound "creak"
end oiCrumbleArm

-- The Kit reports the player below the kill floor and leaves it to us; a
-- crate or a ball that falls is removed by the Kit itself.
on b3kFell pThing
   if pThing is not empty and pThing is b3kPlayer() then
      add 1 to sOiFalls
      oiSound "splash"
      oiRumble 0.6, 0.2, 260
      set the itemDelimiter to comma
      b3kPlayerRespawn item 1 of sOiCheck, item 2 of sOiCheck, item 3 of sOiCheck
      b3kCamOrbit b3kCamYaw(), b3kCamPitch(), b3kCamDistance(), item 1 of sOiCheck, item 2 of sOiCheck + 0.8, item 3 of sOiCheck
      put true into sOiWasGround
      oiHud
      if sOiCheck is (kOiStartX & comma & kOiStartY & comma & kOiStartZ) then
         uiStatus "Into the sea! Back to the start (falls: " & sOiFalls & ").", "warn"
      else
         uiStatus "Into the sea! Back to the checkpoint (falls: " & sOiFalls & ").", "warn"
      end if
   end if
end b3kFell

-- The lift waits a second and a half at each end, then glides for three.
command oiTickLift
   if sOiLift is empty or not b3kIsThing(sOiLift) then exit oiTickLift
   -- the clock that never stops: on the score's clock the lift froze once
   -- the last orb was found (the engine test caught it)
   if b3kIsGliding(sOiLift) or sOiClockMS < sOiLiftWait then exit oiTickLift
   if b3kY(sOiLift) < 2.5 then
      b3kGlideTo sOiLift, 14.9, 4.95, -14, 3
   else
      b3kGlideTo sOiLift, 14.9, 0.2, -14, 3
   end if
   put sOiClockMS + 4500 into sOiLiftWait
end oiTickLift

-- The sky lift waits two seconds at each end, then glides for five, out
-- over the sea and up to the isle's edge, or back.
command oiTickSkyLift
   if sOiSkyLift is empty or not b3kIsThing(sOiSkyLift) then exit oiTickSkyLift
   if b3kIsGliding(sOiSkyLift) or sOiClockMS < sOiSkyWait then exit oiTickSkyLift
   if b3kZ(sOiSkyLift) > -31 then
      b3kGlideTo sOiSkyLift, 0, 4.3, -35.7, 5
   else
      b3kGlideTo sOiSkyLift, 0, 0.2, -27.5, 5
   end if
   put sOiClockMS + 7000 into sOiSkyWait
end oiTickSkyLift

-- A rope loses a little energy each swing; when the ball has all but
-- stopped near the bottom, give it a push to keep the hazard alive.
command oiTickBall
   if sOiBall is empty or not b3kIsThing(sOiBall) then exit oiTickBall
   if b3kSpeed(sOiBall) < 0.4 and b3kY(sOiBall) < 1.2 then
      b3kPush sOiBall, 4, 0, 0
   end if
end oiTickBall

-- The orbs' glow pulses: one step of kOiOrbGlow every 250 ms. Each step
-- is a material render3dxt keeps, so a step is a swap, not a new one.
command oiTickGlow
   local tOrb, tGlow
   if sOiClockMS - sOiGlowAt < 250 then exit oiTickGlow
   put sOiClockMS into sOiGlowAt
   put (sOiGlowStep mod 4) + 1 into sOiGlowStep
   put oiGlowStep(sOiGlowStep) into tGlow
   repeat for each key tOrb in sOiOrb
      b3kSetGlow tOrb, tGlow
   end repeat
end oiTickGlow

-- A found orb bursts into eight glowing sparks that fly out and are gone
-- in a second and a half. They are things like any other, so they bounce.
command oiSparks pX, pY, pZ
   local tI, tA, tSpark
   repeat with tI = 0 to 7
      put tI * 45 into tA
      b3kSpawnBall pX + 0.3 * sin(tA * pi / 180), pY + 0.2, pZ + 0.3 * cos(tA * pi / 180), 0.16, kOiOrbColor
      put the result into tSpark
      if tSpark is empty then next repeat
      b3kSetGlow tSpark, "255,180,40"
      b3kSetBounce tSpark, 0.7
      b3kPush tSpark, 3.2 * sin(tA * pi / 180), 4 + (tI mod 3), 3.2 * cos(tA * pi / 180)
      put sOiClockMS + 1500 into sOiSpark[tSpark]
   end repeat
end oiSparks

command oiTickSparks
   local tSpark
   repeat for each key tSpark in sOiSpark
      if sOiClockMS >= sOiSpark[tSpark] then
         b3kRemove tSpark
         delete variable sOiSpark[tSpark]
      end if
   end repeat
end oiTickSparks

-- A jump, by key or pad, is heard: the player left the ground going up.
command oiTickJump
   local tGround, tVy
   if b3kPlayer() is empty then exit oiTickJump
   put b3kPlayerOnGround() into tGround
   if sOiWasGround is true and tGround is false then
      put item 2 of b3kVelocity(b3kPlayer()) into tVy
      if tVy > 3 and tVy < 9 then oiSound "jump"
   end if
   put tGround into sOiWasGround
end oiTickJump

-- =====================================================================
-- Things the player does
-- =====================================================================
on keyDown pKey
   switch toLower(pKey)
      case "r"
         oiNewGame
         break
      case "p"
         oiTogglePause
         break
      case "x"
         oiBlast
         break
      case "c"
         oiDropCrates
         break
      case "v"
         oiNextRenderer
         break
      case "m"
         oiToggleSound
         break
      default
         pass keyDown
   end switch
end keyDown

on mouseUp pButton
   switch the short name of the target
      case "oiRestart"
         oiNewGame
         break
      case "oiPause"
         oiTogglePause
         break
      case "oiBlast"
         oiBlast
         break
      case "oiCrates"
         oiDropCrates
         break
      case "oiRender"
         oiNextRenderer
         break
      case "oiSound"
         oiToggleSound
         break
      case "oiLook"
         oiToggleLook
         break
      case "b3kView"
         if pButton is 1 then oiKick the mouseH, the mouseV
         break
      default
         pass mouseUp
   end switch
end mouseUp

-- A click on the view kicks the crate or ball under the mouse away from
-- the camera; a press that dragged the camera round is not a click.
command oiKick pH, pV
   local tThing, tP, tE, tDx, tDz, tLen
   if b3kWorld() is empty or b3kCamDragged() then exit oiKick
   put b3kThingAt(pH, pV) into tThing
   if tThing is empty or tThing is b3kPlayer() then exit oiKick
   if b3kType(tThing) is not "dynamic" then exit oiKick
   put b3kPosition(tThing) into tP
   put b3kCamEye() into tE
   put (item 1 of tP) - (item 1 of tE) into tDx
   put (item 3 of tP) - (item 3 of tE) into tDz
   put sqrt(tDx * tDx + tDz * tDz) into tLen
   if tLen < 0.001 then exit oiKick
   b3kPush tThing, 6 * tDx / tLen, 3, 6 * tDz / tLen
   oiSound "kick"
end oiKick

-- X: a blast two and a half metres in front of the player.
command oiBlast
   local tP, tYaw
   if b3kPlayer() is empty or not b3kIsRunning() then exit oiBlast
   put b3kPosition(b3kPlayer()) into tP
   put b3kPlayerFacing() * pi / 180 into tYaw
   b3kExplode (item 1 of tP) + 2.5 * sin(tYaw), (item 2 of tP) - 0.5, (item 3 of tP) + 2.5 * cos(tYaw), 3.5, 9
   b3kCamShake 0.25, 300
   oiSound "blast"
   oiRumble 1, 0.8, 320
end oiBlast

-- C: five things fall from the sky a little ahead of the player.
command oiDropCrates
   local tP, tYaw, tCx, tCz, tI
   if b3kPlayer() is empty or not b3kIsRunning() then exit oiDropCrates
   if b3kThingCount() >= oiMaxThings() then
      uiStatus "That is plenty for one island: blast some into the sea first.", "warn"
      exit oiDropCrates
   end if
   put b3kPosition(b3kPlayer()) into tP
   put b3kPlayerFacing() * pi / 180 into tYaw
   put (item 1 of tP) + 3 * sin(tYaw) into tCx
   put (item 3 of tP) + 3 * cos(tYaw) into tCz
   put 1 into tI
   repeat while tI <= 5
      oiDropOne tCx + (random(41) - 21) / 10, (item 2 of tP) + 4 + tI, tCz + (random(41) - 21) / 10, tI
      add 1 to tI
   end repeat
   oiSound "drop"
end oiDropCrates

-- the most things C lets the world hold
function oiMaxThings
   return sOiBaseThings + kOiMoreThings
end oiMaxThings

command oiDropOne pX, pY, pZ, pKind
   switch pKind
      case 1
         b3kSpawnBall pX, pY, pZ, 0.7
         break
      case 2
         b3kSpawnCylinder pX, pY, pZ, 0.7, 0.6
         break
      case 3
         b3kSpawnCapsule pX, pY, pZ, 0.9, 0.4
         break
      default
         b3kSpawnBox pX, pY, pZ, 0.6, 0.6, 0.6
   end switch
end oiDropOne

command oiTogglePause
   if b3kWorld() is empty then exit oiTogglePause
   if b3kIsPaused() then
      b3kResume
      set the label of button "oiPause" to "Pause (P)"
      uiStatus "Playing on.", "ok"
   else
      b3kPause
      set the label of button "oiPause" to "Resume (P)"
      uiStatus "Paused. P or Resume plays on; dragging the view still turns the camera.", "warn"
   end if
end oiTogglePause

command oiToggleLook
   set the hilite of button "oiLook" to not the hilite of button "oiLook"
   b3kCamMouseOrbit the hilite of button "oiLook"
end oiToggleLook

command oiNextRenderer
   if b3kWorld() is empty then exit oiNextRenderer
   if not b3kHasRender3d() then
      uiStatus "render3dxt is not loaded, so box3dxt's own renderer draws: solid colours, one light.", "warn"
      exit oiNextRenderer
   end if
   if b3kRenderer() is "render3dxt" then
      b3kUseRenderer "box3dxt"
   else
      b3kUseRenderer "render3dxt"
   end if
   oiRendererLabel
   oiHud
   uiStatus oiRendererWords(), "ok"
end oiNextRenderer

command oiRendererLabel
   if there is no button "oiRender" then exit oiRendererLabel
   if b3kRenderer() is empty then
      set the label of button "oiRender" to "Renderer: none (V)"
   else
      set the label of button "oiRender" to "Renderer: " & b3kRenderer() & " (V)"
   end if
end oiRendererLabel

function oiRendererWords
   if b3kRenderer() is "render3dxt" then
      if oiOnWeb() then return "render3dxt draws: textured, lit and glowing."
      return "render3dxt draws: textured, lit and glowing, smooth edges."
   end if
   if b3kRenderer() is "box3dxt" then
      if b3kHasRender3d() then
         return "box3dxt's own renderer draws (V for render3dxt)."
      end if
      return "box3dxt's own renderer draws; load render3dxt for the lit, glowing look."
   end if
   return "Nothing draws (" & b3kRenderer() & ")."
end oiRendererWords

-- true in a web page (the Stack Player), where the engine says HTML5
function oiOnWeb
   return the platform is "HTML5"
end oiOnWeb

command oiWin
   local tSecs
   put true into sOiDone
   put format("%.1f", sOiPlayMS / 1000) into tSecs
   if sOiBest is not a number or tSecs < sOiBest then
      put tSecs into sOiBest
   end if
   oiSound "win"
   oiRumble 0.8, 1, 600
   if there is a field "oiBanner" then
      put "All " & sOiOrbCount & " orbs in " & tSecs & " s!" & return & \
            "Best this session: " & sOiBest & " s.  R plays again." into field "oiBanner"
      show field "oiBanner"
   end if
   oiHud
   uiStatus "Every orb found in " & tSecs & " seconds. Restart (R) for another run.", "ok"
end oiWin

-- =====================================================================
-- The gamepad, through gamepadxt when it is loaded. Nothing here throws
-- without it: oiPadStart asks once, inside a try, and every other
-- handler does nothing unless that worked.
--   left stick walks (forward is away from the camera), right stick and
--   the shoulders turn the camera, A (south) jumps, X (west) blasts,
--   Y (north) drops crates, B (east) swaps the renderer, Start pauses,
--   Back restarts.
-- =====================================================================
command oiPadStart
   local tOk, tErr
   put false into sOiPadOn
   put 0 into sOiPadNow
   try
      put gpStart() into tOk
   catch tErr
      put false into tOk
   end try
   if tOk is not true then exit oiPadStart
   put true into sOiPadOn
   oiPadPick
end oiPadStart

command oiPadStop
   local tErr
   if sOiPadOn is not true then exit oiPadStop
   put false into sOiPadOn
   put 0 into sOiPadNow
   try
      gpStop
   catch tErr
   end try
end oiPadStop

-- true once gamepadxt has started
function oiPadOn
   return sOiPadOn is true
end oiPadOn

-- the pad in use: the first one connected, coloured gold where it can be
command oiPadPick
   local tPad
   put 0 into sOiPadNow
   if sOiPadOn is not true then exit oiPadPick
   put line 1 of gpPads() into tPad
   if tPad is not an integer or tPad <= 0 then exit oiPadPick
   put tPad into sOiPadNow
   get gpPadSetLED(sOiPadNow, 240, 190, 40)
end oiPadPick

-- one frame of the pad: what happened since the last frame, then what is
-- held. A pad steers only while its stick is pushed, and gives the keys
-- back when let go.
command oiPadTick
   local tEvent, tStick, tX, tY, tLook
   if sOiPadOn is not true then exit oiPadTick
   get gpPoll()
   repeat for each line tEvent in gpEvents()
      switch item 1 of tEvent
         case "connected"
         case "disconnected"
            oiPadPick
            oiHud
            break
         case "button"
            if item 2 of tEvent is sOiPadNow and item 4 of tEvent is "down" then oiPadButton item 3 of tEvent
            break
      end switch
   end repeat
   if sOiPadNow is 0 or b3kPlayer() is empty then exit oiPadTick
   put gpPadStick(sOiPadNow, "left") into tStick
   put item 1 of tStick into tX
   put item 2 of tStick into tY
   if tX is a number and tY is a number and abs(tX) + abs(tY) > 0 then
      b3kPlayerSteer tX, 0 - tY
      put true into sOiPadSteer
   else if sOiPadSteer is true then
      b3kPlayerSteer empty, empty
      put false into sOiPadSteer
   end if
   put item 1 of gpPadStick(sOiPadNow, "right") into tLook
   if tLook is not a number then put 0 into tLook
   if gpPadButton(sOiPadNow, "leftshoulder") then subtract 1 from tLook
   if gpPadButton(sOiPadNow, "rightshoulder") then add 1 to tLook
   if tLook is not 0 then b3kCamOrbitBy 3 * tLook, 0
end oiPadTick

command oiPadButton pButton
   switch pButton
      case "south"
         if b3kPlayer() is not empty and b3kPlayerOnGround() then b3kPlayerJump
         break
      case "west"
         oiBlast
         break
      case "north"
         oiDropCrates
         break
      case "east"
         oiNextRenderer
         break
      case "start"
         oiTogglePause
         break
      case "back"
         oiNewGame
         break
   end switch
end oiPadButton

-- shake the pad, where it can: pLow and pHigh 0 to 1, for pMs
command oiRumble pLow, pHigh, pMs
   if sOiPadOn is not true or sOiPadNow is 0 then exit oiRumble
   get gpPadRumble(sOiPadNow, pLow, pHigh, pMs)
end oiRumble

-- the pad's name for the HUD
function oiPadWords
   if sOiPadOn is not true then return "not loaded"
   if sOiPadNow is 0 then return "none connected"
   return gpPadName(sOiPadNow)
end oiPadWords

-- =====================================================================
-- Sound, through audioxt when it is loaded: tones and noise made on the
-- spot, so the game needs no sound files. A sea that swells, a chime a
-- note higher for each orb, a jump, a spring, a kick, a blast, a splash
-- and a fanfare. Nothing here throws without audioxt: oiSoundStart asks
-- once, inside a try. In a web page the browser lets sound start at the
-- first click or key press, which is its rule.
-- =====================================================================
command oiSoundStart pDevice
   local tEngine, tErr
   if pDevice is an integer then put pDevice into sOiAudioDevice
   if sOiAudioDevice is not an integer then put 0 into sOiAudioDevice
   oiSoundStop
   try
      put auEngineCreate(sOiAudioDevice, 0, 2) into tEngine
   catch tErr
      put 0 into tEngine
   end try
   if tEngine is not an integer or tEngine <= 0 then
      put 0 into sOiAudio
      exit oiSoundStart
   end if
   put tEngine into sOiAudio
   put empty into sOiVoices
   if sOiMuted is true then auEngineSetVolume sOiAudio, 0
   -- the sea: soft pink noise that swells and falls every four seconds
   put auSoundNoise(sOiAudio, "pink", 0.05) into sOiSea
   if sOiSea > 0 then
      auSoundSetLooping sOiSea, true
      auSoundStart sOiSea
   end if
   put 0 into sOiSeaAt
   put true into sOiSeaUp
   oiSoundLabel
end oiSoundStart

command oiSoundStop
   if sOiAudio is an integer and sOiAudio > 0 then auEngineFree sOiAudio
   put 0 into sOiAudio
   put 0 into sOiSea
   put empty into sOiVoices
   oiSoundLabel
end oiSoundStop

-- true while an audio engine plays
function oiSoundOn
   return sOiAudio is an integer and sOiAudio > 0
end oiSoundOn

-- the sounds played this run, one name a line (the test reads it)
function oiSoundsPlayed
   return sOiPlayed
end oiSoundsPlayed

-- how many voices wait to be freed (the test reads it)
function oiSoundVoices
   return the number of lines of sOiVoices
end oiSoundVoices

command oiToggleSound
   if not oiSoundOn() then
      uiStatus "No sound: load the audioxt extension for the sea, the chimes and the blasts.", "warn"
      exit oiToggleSound
   end if
   put sOiMuted is not true into sOiMuted
   if sOiMuted then
      auEngineSetVolume sOiAudio, 0
      uiStatus "Sound off. M turns it on.", "ok"
   else
      auEngineSetVolume sOiAudio, 1
      uiStatus "Sound on.", "ok"
   end if
   oiSoundLabel
end oiToggleSound

command oiSoundLabel
   if there is no button "oiSound" then exit oiSoundLabel
   if not oiSoundOn() then
      set the label of button "oiSound" to "Sound: none (M)"
   else if sOiMuted is true then
      set the label of button "oiSound" to "Sound: off (M)"
   else
      set the label of button "oiSound" to "Sound: on (M)"
   end if
end oiSoundLabel

-- each frame: the sea's swell, and the finished sounds given back
command oiSoundTick
   local tLine, tKeep
   if not oiSoundOn() then exit oiSoundTick
   if sOiClockMS >= sOiSeaAt and sOiSea > 0 then
      if sOiSeaUp then
         auSoundFade sOiSea, 0.35, 1, 4
      else
         auSoundFade sOiSea, 1, 0.35, 4
      end if
      put not sOiSeaUp into sOiSeaUp
      put sOiClockMS + 4000 into sOiSeaAt
   end if
   if sOiVoices is empty then exit oiSoundTick
   repeat for each line tLine in sOiVoices
      if sOiClockMS >= item 2 of tLine then
         auSoundFree item 1 of tLine
      else
         put tLine & return after tKeep
      end if
   end repeat
   put tKeep into sOiVoices
end oiSoundTick

-- one voice: a tone or a noise that starts pAt seconds from now, lasts
-- pFor seconds and fades out over its last part; freed when it is done
command oiVoice pKind, pHertz, pLevel, pAt, pFor
   local tSound, tNow
   if pKind is "white" or pKind is "pink" then
      put auSoundNoise(sOiAudio, pKind, pLevel) into tSound
   else
      put auSoundTone(sOiAudio, pKind, pHertz, pLevel) into tSound
   end if
   if tSound is not an integer or tSound <= 0 then exit oiVoice
   put auEngineTime(sOiAudio) into tNow
   if pAt > 0 then
      auSoundStartAt tSound, tNow + pAt
   else
      auSoundStart tSound
      auSoundFade tSound, 1, 0, pFor
   end if
   auSoundStopAt tSound, tNow + pAt + pFor
   put tSound & comma & round(sOiClockMS + 1000 * (pAt + pFor) + 500) & return after sOiVoices
end oiVoice

command oiSound pName
   local tNote, tI
   put pName & return after sOiPlayed
   if not oiSoundOn() then exit oiSound
   switch pName
      case "orb"
         set the itemDelimiter to comma
         put item max(1, min(16, sOiFound)) of kOiChime into tNote
         oiVoice "sine", tNote, 0.22, 0, 0.45
         oiVoice "triangle", tNote * 1.5, 0.1, 0.07, 0.4
         break
      case "jump"
         oiVoice "triangle", 330, 0.12, 0, 0.12
         oiVoice "triangle", 495, 0.08, 0.05, 0.1
         break
      case "pad"
         repeat with tI = 0 to 3
            oiVoice "sine", 262 * (1.26 ^ tI), 0.16, 0.05 * tI, 0.12
         end repeat
         break
      case "kick"
         oiVoice "white", 0, 0.18, 0, 0.07
         oiVoice "sine", 110, 0.25, 0, 0.12
         break
      case "drop"
         oiVoice "sine", 880, 0.08, 0, 0.1
         oiVoice "sine", 660, 0.08, 0.08, 0.12
         break
      case "blast"
         oiVoice "white", 0, 0.45, 0, 0.6
         oiVoice "sine", 55, 0.5, 0, 0.5
         break
      case "splash"
         oiVoice "pink", 0, 0.5, 0, 0.9
         oiVoice "white", 0, 0.12, 0, 0.35
         break
      case "creak"
         oiVoice "triangle", 98, 0.16, 0, 0.25
         oiVoice "white", 0, 0.06, 0.05, 0.3
         break
      case "check"
         oiVoice "triangle", 659.25, 0.16, 0, 0.18
         oiVoice "triangle", 987.77, 0.16, 0.1, 0.35
         break
      case "plate"
         oiVoice "sine", 220, 0.25, 0, 0.08
         oiVoice "pink", 0, 0.2, 0.05, 1
         oiVoice "sine", 55, 0.3, 0.05, 1
         break
      case "gate"
         oiVoice "pink", 0, 0.16, 0, 0.9
         oiVoice "sine", 70, 0.22, 0, 0.9
         break
      case "win"
         set the itemDelimiter to comma
         put 0 into tI
         repeat for each item tNote in "523.25,659.25,783.99,1046.5"
            oiVoice "triangle", tNote, 0.2, tI * 0.13, 0.5
            oiVoice "sine", tNote / 2, 0.12, tI * 0.13, 0.5
            add 1 to tI
         end repeat
         oiVoice "sine", 1046.5, 0.18, 0.6, 1.2
         break
   end switch
end oiSound

-- The HUD: written four times a second at most, and a field only when its
-- text changed (a field write is the costliest thing a frame can do).
command oiHud
   local tScore, tTime, tStats, tSound
   put sOiClockMS into sOiHudAt
   if there is no field "oiScore" then exit oiHud
   put "Orbs  " & sOiFound & " / " & sOiOrbCount into tScore
   put "Time  " & format("%.1f", sOiPlayMS / 1000) & " s      Falls  " & sOiFalls into tTime
   put "none (audioxt not loaded)" into tSound
   if oiSoundOn() then
      put "on" into tSound
      if sOiMuted is true then put "off (M)" into tSound
   end if
   put b3kStats() into tStats
   put "renderer  " & item 4 of tStats & "   lamps  " & the number of lines of b3kLamps() & return & \
         "pictures a second  " & item 1 of tStats & return & \
         "things  " & item 2 of tStats & "   awake  " & item 3 of tStats & return & \
         "gamepad  " & oiPadWords() & return & "sound  " & tSound into tStats
   if tScore is not sOiHudText["score"] then
      put tScore into field "oiScore"
      put tScore into sOiHudText["score"]
   end if
   if tTime is not sOiHudText["time"] then
      put tTime into field "oiTime"
      put tTime into sOiHudText["time"]
   end if
   if tStats is not sOiHudText["stats"] then
      put tStats into field "oiStats"
      put tStats into sOiHudText["stats"]
   end if
end oiHud

-- =====================================================================
-- The window (built once; rebuilt when kOiUIVersion changes)
-- =====================================================================
command oiBuildUI
   local tL, tR
   if the uOiUIVersion of this stack is kOiUIVersion and there is a field "oiScore" then
      exit oiBuildUI
   end if
   lock screen
   uiChrome "Box3Dxt Kit - Orb Island", 1104, 640
   -- the view sits on a card of its own; the Kit makes the image
   uiPanel "oiViewCard", (kOiViewL - 6) & comma & (kOiViewT - 6) & comma & \
         (kOiViewL + kOiViewW + 6) & comma & (kOiViewT + kOiViewH + 6)
   -- no soft shadow under the view: the view is drawn sixty times a
   -- second, and the engine redrew the shadow beneath it every time
   -- (in the web player that cost about 10 ms of every frame,
   -- 2026-11-22). The hairline still sets the card off the page.
   set the dropShadow of graphic "oiViewCard" to empty
   b3kViewMake kOiViewL, kOiViewT, kOiViewW, kOiViewH
   -- the side panel
   put 816 into tL
   put 1072 into tR
   uiPanel "oiSide", "800,52,1088,600"
   uiSection "oiSecScore", "1  Orbs", tL & ",64," & tR & ",84"
   uiLabel "oiScore", "Orbs  0 / 0", tL & ",92," & tR & ",124", 22
   set the textStyle of field "oiScore" to "bold"
   uiLabel "oiTime", "Time  0.0 s", tL & ",126," & tR & ",146", 13
   set the foregroundColor of field "oiTime" to kUiInkSoft
   uiSection "oiSecPlay", "2  Play", tL & ",154," & tR & ",174"
   oiButton "oiRestart", "Restart (R)", tL & ",180,940,204", true
   oiButton "oiPause", "Pause (P)", "948,180," & tR & ",204", false
   oiButton "oiBlast", "Blast (X)", tL & ",210,940,234", false
   oiButton "oiCrates", "Drop crates (C)", "948,210," & tR & ",234", false
   oiButton "oiRender", "Renderer (V)", tL & ",240," & tR & ",264", false
   oiButton "oiSound", "Sound (M)", tL & ",270," & tR & ",294", false
   uiCheckbox "oiLook", "Drag the view to look around", tL & ",300," & tR & ",320"
   -- made as a push button first, so it would keep a push button's frame
   set the showBorder of button "oiLook" to false
   set the threeD of button "oiLook" to false
   set the foregroundColor of button "oiLook" to kUiInk
   set the textSize of button "oiLook" to 11
   set the hilite of button "oiLook" to true
   uiSection "oiSecKeys", "3  Keys and gamepad", tL & ",326," & tR & ",346"
   uiWrap "oiKeys", "WASD or arrows: walk; Space: jump" & return & \
         "Q and E, or drag the view: turn the camera" & return & \
         "Click a crate or ball: kick it" & return & \
         "X blast, C crates, V renderer, M sound," & return & "P pause, R restart" & return & \
         "Gamepad: left stick walks, right stick looks," & return & \
         "A jumps, X blasts, Y crates, Start pauses", tL & ",352," & tR & ",466", 11
   uiSection "oiSecKit", "4  Under the hood", tL & ",470," & tR & ",490"
   uiArea "oiStats", tL & ",494," & tR & ",590"
   set the foregroundColor of field "oiStats" to kUiInk
   set the vScrollbar of field "oiStats" to false
   -- the win banner, over the middle of the view, hidden until it is won
   uiLabel "oiBanner", empty, (kOiViewL + 144) & comma & (kOiViewT + 168) & comma & \
         (kOiViewL + kOiViewW - 144) & comma & (kOiViewT + 288), 20
   set the opaque of field "oiBanner" to true
   set the backgroundColor of field "oiBanner" to kUiInk
   set the foregroundColor of field "oiBanner" to "255,214,92"
   set the textAlign of field "oiBanner" to "center"
   set the textStyle of field "oiBanner" to "bold"
   set the margins of field "oiBanner" to "8,24,8,8"
   hide field "oiBanner"
   uiFooter "Orb Island: a demo of the b3k Kit, carried below its game code from box3dxt/src/box3dxt-kit.livecodescript. " & \
         "Sixteen orbs on an island 60 metres square; gamepadxt and audioxt are used when they are loaded.", \
         "16,524,784,600"
   set the uOiUIVersion of this stack to kOiUIVersion
   set the loc of this stack to the screenLoc
   unlock screen
end oiBuildUI

-- A flat button that sets its own colours, so it reads the same in the
-- light and the dark appearance (a native button in the dark appearance
-- draws light words, which a light page cannot show). The style is
-- riptide's raBtn, seen on OXT-Beyond.
command oiButton pName, pLabel, pRect, pPrimary
   uiButton pName, pLabel, pRect
   set the style of button pName to "roundRect"
   set the opaque of button pName to true
   set the showBorder of button pName to false
   set the borderWidth of button pName to 0
   set the threeD of button pName to false
   set the textSize of button pName to 12
   if pPrimary is true then
      set the backgroundColor of button pName to kUiAccent
      set the foregroundColor of button pName to kUiAccentText
      set the hiliteColor of button pName to "31,64,116"
      set the textStyle of button pName to "bold"
   else
      set the backgroundColor of button pName to "226,232,240"
      set the foregroundColor of button pName to kUiInk
      set the hiliteColor of button pName to "203,210,222"
      set the textStyle of button pName to empty
   end if
end oiButton

-- BEGIN GAME MODELS: generated by box3dxt/tools/build-game-models.py from
-- box3dxt/examples/models/ (Kenney, kenney.nl, CC0); rerun the tool, never edit here.
-- oiModelData(name) is a model's OBJ text ("<name>.obj") or its materials
-- ("<name>.mtl"), gzipped and base64ed: oiModel unpacks them.
private function oiModelData pName
   local tData
   put empty into tData
   switch pName
      case "character.obj"
         put "H4sIAAAAAAAC/4VcW7blqA39zyjOBOhrwMb2dJJ0r5W1qpKPdDL+oMeWhK1b+alrth5IIBCI0/3zzx8//vHXz89//f33H7/9/PPHX/772X5rx/Ep22/H1WZju3YB70rgOPfZqMdYwK0S535G8TH/TM67M1i3+61zOzuBfexBXMFVp4or52rSKq69r5xBfP6p/YisV8SU80r4ntLe+/yz3VdEr4jBo2XotKN1lMKAvOWvtJ8wGXDnNerXuwsXLOncljQMSjrlJZ3zks5aSUOhpPNW0qEraYiUdERLPnklm+eSBUTJY6fkU1WyuSp5qJQsVkq6Jkoa6iWZ3vLN/D4jo6QB1BuHDP271xrDrPVOoC6xyUfYfj4Yad7OwNcOdq33GsB6ynzcPUpfPDL9GAGsw102lRe1Wq1R+GAnruPRy9PEOlj0MraS8ZWcMbGwpMNTsvEp6WCUdDRK5nnJRrhk41GSeSzZIHlA7oOc6n0Ny2MG12yMY0GVdyhvv00Dtep4KabWdb80L9x3MCPrkP7UOwbkA836y7vLTU6dTscnHYjvXFBUl6QY+9oO9tEWbsAPbihh7lz1/NtHUPHweFFsvNhvlDegPg5BrYP/34sQJ4nakupdR+2tYXGt5F6sg/Zerrqw1i1uBRMbUtfSnvI5c8lWn8vNwLGCrwF/z62pfAS+gbZG7sgZV+pDvqRdlVRtiXofc/joLPM0G5Lc+bQXmnzZqZ8hgf07RvD32MtGBeNic3AZT1EZg8FS" after tData
         put "R4y6X4DPxfPoqOQ9zfMCnwQ4aNXMtp0cdeN4gE9GEn4wloyzfMf67r18033tVY5Nsf+6C3iuIC+WerQINgGvEUHZ0KtkXfg0uhgRxbeDd4cqqdisf7OW73iTvkpqVkl9Lamz5Rtvz/uUk0M4lCnW9yPcZyLjAxNGk973Nzj01BKlFXt0I9KLPcim+xEvQwF18Us35ZU1oC/WlkHvbup6E7skB9TlyhfAXIGz4lwuHT5YZWMHawADa1Dw0iq7zENes9ajq5U1yL+7qsuEwqsFxO49stlbwMApy/jJ+karzCnQYFVAsbVKaNUVrTqE2KaUF7O2oFX/vPXysn2yvkGemIrk7F0BLOnyKdlCK+mSLNniLdkKKtn6K+kCLOn6LelqK/lyK/mCLekyLPkCK+kKK+liKvnCK9lyLsmyL/kSK+kaK/nSLenaLemKLPmSLPnyK+lSLfkKKvkSKvlqKfnSKumSLemSL+nuUNKdoOTrsOSLtuTrs+QLtKQrtKRLtKRrtHy3SLdj5z1Iz/y3JnmA87tdD8wYyzecezivDxSYfgnOz3qswgFiP+QeGauXE+uP0ieg+w7Qed4BE0nFFtEr6uetRLkWTDqI9aLFjpLZWxLryjcKXx2XzOaSGW198DFoHaeQ8Ny+WCXzjp+1s2c9za1Zinpw5s169Fed79F/0lHaT5zS4GTW9Wswyq+Ec79j5NgmoFVWmxsGz3aujhvrGyXeV2SognrWOEciL2BJ0W/k3z2lNqXmZ47G" after tData
         put "bmjMnvYolkAlF9U5ky7WBaFWY72+GDO+RTjMuEu/wiXBgvA/6RLB9xbq+LwE4VIWX6VvBcQngpsgXaqJFMyMlLeeCd2zRczWfujh0gGz3Kp3kXhQwV2cXcr5/O9pPE/sLca9lGjY6nF5O7h9Jjm6ZeLzU0mzQ86fJDV0dE/JezVCcqB6cD2Y5AmFSNKunIpZP1gqpxkWdamn0FtmESlvppJyrfaUxLGSeFYSw0tieXkPQXl4U5LRpVkBr0z74N1Qscaxfx8x3sSccX1CxJxNMaY/FZZMYwkqTTxIWzchCjPs3UvWSWZi4l4yConDucFnlZg+MaD19n/voeAI4MBS0dVw65pdNZFwVCfYWw/Ji1wLTW9Biev4tYHBvqipJKrgfXD+bXN5GKh+w+04YDAnhZaeEntXtY/BLXqOWsNcVsQS0Y322CUygJQlWJ6hB1VlCZZsbWRL47UyXuqK64ux9+zi7dPb8czJRPc9Pu+JVMxj6XukLAG3xhtP3zOMATlSDbEw/QX0iObXanvq53hCCj44di7wXhJsx22xp7HuaZBzo2dJxrC3lqpfhIZ8Z5Ka/tL2wq+qjZ60PT1/1naJHvbdkvM1FozfN/uxYvzUdq6yB9cIHUvUpVyvDr7VX5IOysvgN5gLX1I0enZcXj2/GcvK+QiQR3yUZ4CUR0iUd8Q8nUtMTjxLnHiP8Xtu3lPznoZklpOgyeYqm5YktvJxfU9AHoJ6/+BPXZPfIuHcsyJ0//HTtEMLUhKu" after tData
         put "8mYLXCVhK5m68u5VoP/8+/eff/74/G37yx+f+vVVP+3rq33611efAH8zun997cRxzsb4HF9fx2d+nhPib8XrNf8Q2KZQmwe9qWBeHeqgFolLW6mtPeAmQrPzSr3LB+DWwa1wF3hTWD4M3hUmK7k11MiJkTPMeLHyyuLcZIp5wa4JNBEIisPmKQ2RaGG/bsK0SSQdOFGvw8Tm+GgqDRpptOrBU+Aa6a9CUyshh8gOsqbpXGhLSVDYN5rBLhOrM6stocBGluaWUIhPxkr0mkLx7GAv9yEmalMVq8p9E1/YcuMc7AxjXd3ZT54NsXy/ZHzQFJr1ziYJKJ2avFprc8OTz9pUl/Y+A6QPjrkd4YO2UEnvAh8idGpoygdg6ly4FT4FRnzLh8EXIvaYX/e097jn3zm+g0ZrXDwV8hloFAEyx1PN3NPbmNIX/b3JXVZ4zjG9Z4icO0GTdk4DLw6gk7locKbmi6JjKrxklJgpSF3z466rFPFckGYztPtrjtDVVzOgyLxQPYtnzvV2QCFjYkHDwMQDEcXuqfu+IwXDd3OgbHEcb9K3Hc4j08Ek6nWzkYiDBcRHxsfRIPCY8X3jLWH4nMuwLX6BFMLAIPC4mPUmHmGKWKMizhICS2k3hepWg1jf2Os7TClPMQ+IcSN6rLOb9sbt9DDy6NFIdcWmsFeyaOsYvhhYpod8vzC5lqhI8zRlrmzKLzfzzGmcbZq6e5o+5vbcq8w3GT54r6X9hub0nn/HzEmUdC5SJiyT" after tData
         put "gUNk7vXbVHpeLDMkRObMTWj+rWQtRSq09CYDI/2yDIfV9bknZdTPNZuHKDslBKbbU1mDUiaha9EfTRDPXK3rg5ouQa9jwuoumRL1UU0hCk1bnReRevG+Nnu6TkaYaJhxXYww8VSM53te48BFRMeMi1N6YyINfOtRf1ALzLh47TXO/yeprZti9HGyfpZ0DFysq7rahXi2hNgg6WoNo73kSdTPQLxd7c2u7OaB+cTEhhGieWzVxoyJpLbN8LovfDDXwceaLljbKj52EFXJAPHUWWm8Mg1zLpaUyaYe+maYcbFaJu7qUz/UlT7M2n0zTOdzrzbZhDmX6FoMUoForWHBbFHBByqNq9YkdObHjRgKGLj49FLvhcg7QuuLpGPG1TBlrR463k1npdVus1L7k8h9PoiKzY8jIUJ/9cnmlTvDBB6YT0wE5lwHYqjx/kCHzn3DR0Votr0DO/AxVuJx68AMqOANI2DGxYfWtkiyQcdYiIYZF/d5sJ/ag87Acam1x2mzwhi41ArLAbxqKG7nNsv/8lxRGGlTaJxkZK9c4PqAuf25FL0iyHMTUNE/FOyCsofz9AletIXaAMsH4H484EP+wDj5ALw/4F3/7ApTktzbh04ce/9QCt1pyZ3T0n1e1ea07ONzzp53GmI6GOyXcbMswcJGqXi/nZtS9LF9rrk0jpnQJvdB3PJh8NR10LqhJX3sH9pkj+NDO+YxAjyVHqdSA8zSSiVY20pFl7CbLVPzCda2UtlngnkUTMnD" after tData
         put "EqU+lcBZ81LaoPLQEDffL5mN/uC6oG2lnjjp10G5eobPQNIah+UNx8A0kPwHL/65T9LBqfJNmpc5x79j4Dp56VdIUlodu/61K7gh4LhBOetD5k255e9pN/eTd5buQsIaOzIWPg7LzX7ochpd/2IxOKIcp61hGRbz0vxmMwxTJhnLxcKTh3xf7JDjAZUGBj6YXW7nFCFVHKG/HCoVrjECjsMox4NyGeVSSlPKrZTGR7y5m28DCf70bEEGzjXa6ERYd6qdNP5gQWDQEGhV6yC8580453QmWc8h8NQ3SUs02/kiCTSBwQDTWuSOCg0Bh1vReRwabcL8t2I8Dr6qzzvBIXtIO7B0nTQa7yPKwpcN2QEbL6dBlw1sgo2CYm4MgYQdr1HgHHSnrLyLNT7+nXL3lb2z6a7YTi4ryN1LuFyMN0EhKTftBPu9SFn3Jq7uLCqdK0iqAwoZEwsaBibsf4bQWY84jNI5YG6M7DKMMrDOYRTryMYsjBUg8Ij7nN1oJ72dxSk2mTJ66Jtv2YoYS+hL5jWGSRIeyuPj1Pl6FEguhc7o9O2xFWOKcgfPDQ8oayPeLUwzTzsPhYYE3wh7CI2+zRE4R4hUC1C+oF0hCnms2DZMHYJQphAHoY4qJXWGiizdiaVqq8U+uWxr4VLqeryvVCvQWslV2weX7aQSycf6+XFb5ZXU8QxKWVWIhqK9B5O0pnmjioljz4aiI8qNvEej6ublNm3frEWKinTOqtwTqm4NZrHKnftHZVQL" after tData
         put "kXQyu60Iqi0pggLjaqFqNpVoX1GnXMU/dBecAU7Xp8GlAWmDiru3VgzocjjDgupRgwsW2lYqyghalADVYG0rlQOWJ3j2OW6vi1C56VwqJcbBVQOm7BxasBPmaxtkL61YEcRU0TiMpXtweCe35GNaLydVJGgNcJQAAYeVVqxqwUP0ofsjl660bWQesdCHLl+r+GjbO7CurcrCDsAUVqWIcaBEo9UcMUanmGBtC9VrSjoBXr6R0YwFHeNA2abxc8DcBfglYMfFkK8IDikPrzbZ5fm1gfYGxeYHHxp4N3IMXKqKk/PQ1HvL39aQguXLKRXHGDGAXhdaxceGE5OV7LBfSj027nBWLdQSK9NQm8WWqdXGuGeiWItCKtM6R53VVlFnZJ1SFHOeF8mKxmL0YohWhDufyLZ9KSSbIU7TFNf53La5l7FebCVlpzk/dvlgihZcO0XvjHoUTFlMIFMZaCgYe71Z7Q0ZEJZHmhd4rT4sY8Fyxq8J0mkoFVuJN8yP1YrNl2AniryIB4zFUofGS4eHkVaLvXwcwsjqxaLaNCJX0lRxmuQ8SJVoPHlKwtz0KUnSpKRMcGla1KTJJ2GCNU0q1WBJk0iaLIS+FVwyteRGUeaPeJIe6bp/hQyo+fHSrjQjgmqwZkTNj4daoClRMq4qlhyId7pbbZCcKDSxxMRVKZIgsp1em3E/1jZyo+3hEkF6vZds5td9UFEF0As9UpEdXw0A3bOdJBXc/HHE07bnHGQuLZtgMxaFYf82" after tData
         put "Oic4coDTpJVIcOrTtlKf6QElkqqnOm0jeeAooGc8eGcZ2dzVKo4Pg2Qr1H6s6AOjkd5gvKZAFGHs+KBtI+PIr6cNmAs70VYqCj8mLncKL/FIG+SQbf1Gbnd0vobLLw1OLQBwmYN+YsClD3bcMWW6rEqgXFF50GmYcV2u1EoAVhQ4vRYwVgwqmHht8bKPy3+koBxwWjnAygAqI5zIylIGQF3g0tOUkC69+F9yd5YDAhDjuBYKFw5QSmAprnl5F1ZJsL70em+nCasA8PnAMONqduawG32Ph4iFoscKOYDEAwfF7EoBYkcSl8EJhLfOCgvlKGKYc51+TtHziZ1Xbj2dhfMJDixd17KfTuy4gvUTDgVyXNFUGx9+/SSy6d5jWd+u6aduY+C1o4pRcGHH9Tx2pBd2VEbMunAswTnl0p0FJhiLk/yUgZOB+B+fx52n6f5ut3zc+o1ipwg/hhx6HseV3Ck2RJoRgrAJ4TBit3czz27rsg/qaDJFbut2e39Prt7A1bNQA/CpNW1205dQCTJWBMLwyqjiJMLbjT1d6wWt45Djb9d4y244Dturs75l177jRGVvyPacXXFIs2uZPWfrUzSL4QEbqk0jLjV4ecaz8vL2jDdtPkBsy+3KHrW12/g4brcgGQUm4RlbVUeNcuPzd231n3fY/nwjvo/3G7FxhQfka3s+5oY3Yn/DtVddfmvb7e2U33DxqssqmryA2hvuiX3cXwb1MxLrixheepsT24vor5H2huuvunwG" after tData
         put "retLL6nobSH6A689+ZL9/TSD+hW5nOgPnzs+3FrD/O00vICeT8lIvJ/Po20YsY0nsTtRn27nR5cpw/MuEw0zrh3z2TiKW7X3VHthZaJhxjUw2f7Y6s+vzR9WtxWzd9j1SdaIe0Lc14dbJsozqhp0NHtqNVcIMy6WPHwQ9tMeW+2pldUaBi72aZ7msW3xfkFJ/aKr0M4Xv0pTd/GqoMR80W9kTr72VaoZ8A+jnHLzj8iUgzfBje9qlX/fSL/nafrboUo/irxb6M/6ocLivLe7zKa/cav0G7+bNpXBd/VKd5Rb+uGvQLn0V2CshU6QTU+SFW+7hoDD3pjVyrgN+85oGJh8GGC4uAIHeICAwLWuv19TQ32b1jGMO7fz+I5vCjEiPhKKgEPmMVJsT4/7NjATdzH4iUl+TTs4gr+gqOXulCHgMMORH2yMLHMAMQ4fPQ0vTxw3qgyOWQxa7IkLlguXfGMYmDyYEfg2MTE72/xhdbjLehAwY91GMw0s7ClTNJA9pR8oRzlm0X7oDxtdTI8YYSE4BB7XqLnYV6UfVoAYiyxYHg/dIowUjh3Ojn3ExC4+sNOvhHhnvJC92UrHjIu3yGslWoL2vGyYcwVJaNMsb3mfcyQw79MNOs/nEUPPFcsRw4ktIT5+cmbpvjfP3mJt70teVkwt6/LDLsWMC7piug8qTLI18Wp+yMDMjwN+Bsy4BobPMU+zIbsCc0lX60cAHAqaH2tafxLDT6WceCcHBVirudqyN/cJzH1y" after tData
         put "VzxH8oX28jT4R8TAxa7IUx3n6qPGHBxSr2Hg4s4PuU2LkkDUjha1xgVJ5GWOw71KHWHXusLeUWkwBBz2M4ZdqxL70L+nUYCAw+oWu1zdpyH6F8/2hhhHM0p7UPqTIsj8a7Yd+4NyvChq2zGMMh6U80U59e/1omgd5riNcq+UsT0pA3UfG4NRHxR7Udn14WbXH4Xt9rZjiHIcVtRhhG6lNMj0/9hpNF5VbrmGGRerlAso6xz00wkK1EEv/PwSzovDMOfiH9qNVdL0u1rHjCuobbB2g/7TrQXmXN36PPR3KIf+6OTY7b+QAAIO+eERIp8L2PSbpPqhDuYpnQX4VZwkjg+rGh+KCN4Z0FYq/SqK/0sflT4ENiXaVmpXJVQSmDss/bhg3pioetEZ1rZSB/0hJdzJhx4z+lADiFvbSp0DyvcqEQPVYW0rtQfdM86G/kFUa1upttxGbH8G1pr+mknhY3vAEsr2cyX6mIlDvFafbUJuH0vMC80YBQ8tvXZpW6kESxtU+sUczSotsXmhlbZSCda2UGmVdYoTWna9alupBEsb1NkTZ0H1gEpV/f5QFYd/ZKxtUIn7Vm4fBtvUAMsGZvsJYNkzTnCfke1jO4nCulvYZqEGiwluN9pK3WCgzoTaLe78D9LOUVPsXQAA" after tData
         break
      case "character.mtl"
         put "H4sIAAAAAAAC/03OvRHCMAyG4d5TZALO1ifrZwbGADpIxR3rE0WgpHmbx5K8Pj6v93O59Xa9L/0ipFuZo+Zt/elI1alVYy2mZBhvJUY8AoqRPNn3RzGMYzenssQYRsyalc5Um7PqXYol2YGjMoo1mahyOmyB+z2KtTit9T9Zj+9C0b7aRdMeKQEAAA==" after tData
         break
      case "flag.obj"
         put "H4sIAAAAAAAC/41WS5IlJwzczym4AN3FH65jexzhiG574bHPb6RMFdSrmg5vHkUqSSQhwfv88fHxxy/u86/fvn+8ff74+Pav88fbUZMLb1E+S8oTu0D56K8QWP6nNP+g5i88/z/AtUvrMvQQZKixQXS0k1prJfUG/mx5GHntVOF7KGVjljwe0DTyg2oK9cnXE37S8D/dcHMttXyPLLZ7CoD5p8D8k6TkutjZzOWHgvM0j5aVlYsCJ4OALjtZWCbuZROb4J13pHHfEyAXg4rFL3oplDsP4HGSckhbAOd8btIWZyzs5I07r/R6453YMeS3i3s1L2zySlyY1k1wZxXOr9Hrmr+FWFd69kaZ5RBRDmNvPGMSlOWLaZ1yQc+metjKf6Vwci9teXJRCP7FsVUeOLK6g9iLx243BUAy9+vjVnIX5jVXZO65WsxLroz5lOrrRq/5ezgV/xiTf3TVP3rgv0jALalfncolV/4xL/6xiPxjuvzTEf4pjeUO+QhSy0B8sK9plQ+/GcWs2JToEoJmb0S1PkEjnlDqV2ghts6W+UfoJuXvWgJ17ctofg51/y2bQzL127xjvvgX4EGP9jAudkz9wwYv+0eY99hXwhiSewnxEnPChnvS3TXh7pUN/X/+/j7/Hbhfj2+/u1jf32cpxDKH4mKXQWD56IA7SG3C6Zgfw8WhQ4oyCDw/4qHwHIQUD8JCS6qdMrX1owPuXGvwpBV1KKlfAsPB1GA1BxVuYDdKCgy/ld1JsnDm" after tData
         put "6gCHDvP7gMMB7vddZLIlnOCykMKE9SMCjtzJ4EkTkeSyhJMEjpgnDHmHM9iZkgJnzBMGJQk8A5iXQ55RxuJyl0FgcaG5Iqu7K6IlnhRZPVyJagVpwnXCSRcnV+c+6gZmsFRidWEitTCduVqA6UhMNlmYztQfxWSv4Nr0Mh3QlXOGu66JNWKhZIA0xnCyEbNrQbUgKWysZn4oYnUtBCtolndjNelHY0GzvAUeW2GwTKQQwlbQLG+BWdBxawaKCBvNgPIWNgua5Z32Aq6ntRnMrmCPFGu8ts1XXbOgWd6I2YLv1sSIQtgoaCvvc0tqkz2sJFnQKG+s3eo6bOVt2tF6BOUt7HQpd6vrUnDYVU+1NJ5qGXrY9cCpyiI5NNhdjWoFSeqraSHVquVez3KXnOiaoNxAhWCWQqwsrF2wht8KTEdisuXCKlS5BxxwLWoBCyNKVTCYVlDuFpPNO2JobGGuZn4oYnUtpzI3mf9ap2Z3YWpJwJjBMJeLjI4uzOQPmAXDDJZZXoO84ILGJpjEwRkszIGOxMYODcWZFR0JdUJ9QbZQ9nZRWu2AU1KxnKpNPThsj+CinFF0UbbX3sacVt1VUhOldRITwdzohAZ1QGo1SqSZC+FiNvejWbHJxtbV1BI257SeInSZ8VgkNqcVkdi5ilzTm1OvWdye+q1oByCLkiYsqVzimSazGHYsLIYLFpRnWFhYzBcs668+Aeajdi3blc3beUWzwq15o7Un2xXNi7UCs13ZvN3eLjxI" after tData
         put "6nVhCjiDhdHpSEyaZWE6c40Pl47Eat2ximeOWWXDsXnh3NaebN7ER4rtSusJW7uyeZEYy5w+2HzA+Zw3u9jwgNtzHrk5H3B7zjNvEntI+ayG61PIZxWS68+APasmkrVHm956mbceZ7AcxI4NyzumMxXUGzNv2LFjOtNYbI/pNZ9z5GP9wbHnHImxzFW0wWxJ+RGmtMH7e5a+yAJkdE5xQX6mtmjO7yrrqgBLrWFxhGSCmgqpZIaaCqlkhpoKqWTa1Tq4wemdmBAk7kxNnAD/AcFLPeWQEwAA" after tData
         break
      case "flag.mtl"
         put "H4sIAAAAAAAC/0XOsQ3DMAxE0V5TeIJAFo8iNYPHiN0lrgJkfUuiQDa/eTiQ9/X//j7bO6fj3PKL0XpJe5Raupfupqg0dO8RVddiWiasMjuTsbB4FeIMY1KMHcYFIXJm41rGDpjreKya6tTVUDFtuUQpLutioagiPVkum1UTAQAA" after tData
         break
      case "platform.obj"
         put "H4sIAAAAAAAC/3VXS5LdNgzczyl4Ab3HP6nrJHGqUjVjL+L4/EYTAAlKymZENBp/Sg/z9fPz858/3NePv759vr5+fn78ckd4peIO/0o4+s7QQHyPLrziBTkmpHbLLMfi/CvmIgKj0ZiWRVygYU7romEnEneEgZvNs+97Eo/J3uI91h1nBvdqnsreeGqqAX2fzU9Cu0K3cdxH9jSM2NMk0Zm7oNiC/if5O/FejyY687wBTxXfBviU57XFCwgl3C7LxELvi9ilEaS9hLwim+XxaHrcbRd0i/ro7yHle2H+dSqJjhvA8nFjHA+U2soi5dAZbRnhRruLPy0mzImyfdqsi68Ta0mws5o4vlmmojs3bcx85plRicKrYVnXnCyaNoytNXe1b2m67BKmGl4t2fDUeGOmjZdKtDVK7Fj7ZIZoMY2jKNunzdr3WU3Q/sRuBhtLtUxBL9y0mESss71xvH5Et5cg54Uli7ChxuWvEPHizLo2IfZmOnZanta8MZPyvo92n4MxbBTq3KiR1hU7LCi2xpSM+ClAqAycGu88GQjVAipfDa4eH+yHgQkwDGwGZWXeugSZNTc1u0LPhrfW3Bv41KunVpXx5a6dz8yamELHA2Yy08RW/ib9HTgezC7Nus3iIUX6SDpvJjUH5QTnjKHoc8JtyDGzXWc7LSZmdtMkhcbzVfZwdhhvXS7IbNBwcKiHgyvytxvJ7jzEqduK115AEqPpZZgdSpw38r9/v9G+5v70H3+7+n5XV97v" after tData
         put "4jqdCBjn9H43d9IfAvBw8f3uLnj6S0ggKVA+4f0+XcgQgCaI8MIaQOQshMmfTCIF+mFv9IguekiA/QjCyokmchtPF+mRvEsZD8Dj4ELlCCMQYDJLSY1ShQTX5wjFsgQmGEFSRoX0NwxhoWXp4KEZMCo1WZQpQLtBU9s9pPMRzt5oDRyMdrk2AQBWy51p5Gi4bAg0GZQpQLNF08VxMf4XOYRlA7RalDmA2wZXhfsGt0vEbgKjG8HCIe9slkUrV2bBqV7gsjsRWbSJYX1FwqpAuzDrLSZ1U1gxsulZ2OB8gaUCnT4fJpwubNYWf2FzBUVDsl5v1sykhI09b4A3Tu9wvGTirZN8YcvNm5dZ7rzCfYflTssboZ2PqzAJPuvVZM5LvUimuIKm0TcNcxgfNJFFiwEUwAjXXEHw7gp84WunMmsrQuKTVxHkdJUiZ+9qwgOwyKJFJHz3KsXOwVWKRQtxbZAAiyzaDgkw1195LlVbrLK86/qG8GEaaU/4MOFygflSlrzDLHNPJtxnq7oUL7JqZwdHh2c5s0qWRcvdXx3kRq9WqSzaJmPg5sz+Vm2VyKKdYyAnOblGCebsWsCDYJFVC1v8GDSYFdcohVxdQ7ooR2XRIiTybqiruYaQ3TX4Qk9UZm1HJOTdEZt+BSlW8a7DF6pUWbQZEmDuf+ORNn1dRFatXoiWLNzDBebr0nSWfJiwvqEtbrA3bCpeW5WleJVZuzo4OjzLmVWyLFruvungaPRqlciqTTIGbo72" after tData
         put "lxu3+q1aHoN+K8ZPPP2mY02JWF4AjPNAUQ2vOoF+uwEVF7GToESRWYkdJiA5rBuhu4iV5RxbRkQWIquWKoi48lQC/ePCLl0EeWwXLLNy+DeOgablQWXRdkiAqU5aFEcpUsU4C45dKWZZeyKtbVRLrC6BgypUZi2WoDj2t1GOS3hDeTtLY3cSmbVcKgKOekZXuRZQIYgC/ZP1LzR1wl01Tlk7Y3GFkqlUD7bIoh15S3dSHCnhAZdRpgGZtUlhPkw47jDLI0F2EiycrjA/ojqJcYOrwnWDzx1m2alrS3JZwTEcHSwPbl0A0cq89dpnXdfHEk/lFh5NY1SAsbqPJT7xQi97uyzliVd13tvHCl/5HwElyA5fZcOWrV13+FNWaZXHDh/5/wTd2WWDR/KnXD/yKBs8k9aiLxv8ZOvOLhv80H78BtWt+LF8FgAA" after tData
         break
      case "platform.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEwVDDQszA0ApLG5mZceVApQ5CUgZ4RWAJKGpnDpY2g0uaGcNLYEC5rDDPXzMgErBEuYwKTMTcyBekxMOMCAAWUj+6NAAAA" after tData
         break
      case "crumble.obj"
         put "H4sIAAAAAAAC/3VXSZIlJwzd+xRcgKpkhuvYbkc4otpeuO3zG+lJJFNvKtHTgIbHh/r+4+vrz1/N979///b18f3H1y//Gft8tOrp4xP9LTUR6j6e5kh+knk+agk7aAc6B5j9QzYIymtYdhf152Cv6YvOtiPAMO0JaKpLVrI9sJvzdZtrRrfcbzv/rB1j72uJ125sluotOfaevgPqzYb3Bb1N7Trf68w6GMIUMoj7ABX7STmn4bXEOXNN/IZdWnEd9TXpcwYT1peh7CSbwRyHYY6ChXJwbIdmV3vztRfnGdv3vcW75Xyp7fnIKQ2zvl4xhezNzl4M+4Q4FZew5Gn4wbUiuZHRipHV4SZAbSw7H4DwEvU0Rfy6OYB56ymIMm2KopDf0nvjcFh7K8GelW52q+8cbS/NnrXZozi7V2cv5dlLffYsUCB7yd0eidpzS3v2xh6529uOZ172rNHeGmhvDbPXkdhrS+wxc3vjpD2ZYE822xup7EE9ezDcHny1l+Njd5bby0mw22n5i924D4l/6Z1TkOtJ7J93zM6gek/OpUv4CuAygKZ7tgZghGFA5d1hj3jxZ4dpA3ZYMxi51yibuLdwurNgeIB356NBt0beenZvWSr8t2ENu4EpZC/YlJ0mN1cxFbFD9uK6Ne6YyyXNTirzTFMbQzOKsw2tOLRCqBzQv/986+9H89vzyx8mhc/PkEyK+CT6EFw/P30zmbTBZE9Sh7Pr8jO0CrN3NqmwFkYEN3iTtkgsCkJy" after tData
         put "xc4VW1aCE8wyPhSrdLh4zqx0bTMlS35sVaGsgClG6TF75zlURoxMcN/R9cQaa2FEsOOYUPIGBBaE7CUWU7oHJVG7ZTYVqdTuT1FZ7Cg2q7pZRR0cpwDmED1H8TW1B6cqOLxqBGuUXTDueT4/q2k9OSqMv6Zxr0zzUm57eOuW8XGSQUMLK5XrAVMGrULGBtASzDNHrITYaVDE6XTTYMoYAbghXMCsJ+YIU4pyAdxQpmRJVbihTHkkVeGGMIXhqlMvgylVKQJuCFGczBHUEKKw7WBZHkRpQgWlhnDhoc9LHCHKQMENEKVqcsoOUCVKl5QdwpWojBR2oJKqdQs9QAgnNGMJVOGdO6bswCgbJR90lEIasVE65EGWwVOhB3oKcrz8U7KM0EIPIUtZWEJ+ibLMlH4BkXnNaEUhgSpgQCx4zagcM89FERAA8NqjGhTjeBTO81xcwKxVhC7KmGhbmHAuZMcCcKGJSzx4jaC+Kos2C01c4a64ijOqR0hlaP0jPVOYZ+UlfxZEMyxD4EPjAx+SEOXQqCzaKj+30EtWkiOFhixa+L6xw8NH7A0CWbVZji8WUpoYUWyRRVukcCogRBpT/+tYeNH06qR1A/RqGmYUJoTWCQ1ljRDaFY7PpJ1gN2nf0NMGWvSwHWlEP9nCkdAwoTAhNM5o2AKnKf5r7NzrQ2ieUdgQXBY4K1wXuGw71mljOTYv7OJqDVm0QpkXDnmD0xpEZNEGwPrTEN4KtAuj3jSlPhWWJnnqmVvg" after tData
         put "uMFSgU4fiwGHzRra9GzWqCDpltArs0YmyS3WgwHPFPSE/ZbJMweJm7Uwb5BZOK9wXWHh9DgRWp5fq9QU2lylzinq687jReZxVfMvO2TR0qNvgT0+YYMDPhqE72HP9y7BRWCVRavWWAw4KZwWOAvMbyzPlyd9NEGVoS1lhYs4VYXrDNN1C5gXuP7kLeX1OvRDq1tiMeCwwpD5eu6wdj7peyfikRTxOor6aIpDq2NPdYGVJKnNcNaxZ8AZTll/EVSGtjwrDJkfPgsM6hela5VfMBzZqodSZdFqbCwGnDcYJ7tolU3uD8BNya2yaId1XWDtCRYK85NoIj2/CfpVRpezpzdHwCPEA+3lRDxkXL+yCErG08OA/ESGkh4WrsiN7fplT++Ixjey54scsmp7Np7/AelfLyGNJ2O+VCFDyfGnwISGN4LKoqXLnWvoZfuIUqQKXgtOzw8f5RHg+xus1+KzCWRDVagMLd39vsoDw/fnCDUTT6ZAOagMLUqlDbke7ipqwRMwqIL6J28yVzQIujoFhXbshQolU6merEUWLect3ekHzuPXxOvPiMrQBoWxGLBfYcicIIK4GQ47jI/XIN4vsP5yYTHgtsKQjYaejYz+UmI4OlgM7iWAaGXe/wOBd0EfQhoAAA==" after tData
         break
      case "crumble.mtl"
         put "H4sIAAAAAAAC/03Ouw2AMAxF0T5TMAGKf7EzA2MAHVAhsT4xRoEitznyU4712s9tmHOaliGPotRa2lOwdLwIgUWq12OoXTG0WgtjC4p0pEAE/Pq75WD2TQFfB+wogcoOqv6rStS5BNtzRyw+XS3di4UFt9IAAAA=" after tData
         break
      case "cloud.obj"
         put "H4sIAAAAAAAC/4VXSRLkNBC88wp/QI0t798BhggiZuDA8n5qyaySZQ2c2rVnrXZ/++vr199+mr798cuXr59vf3394Z+pfpZp+RxTWT67kdsu9L5syrnXNVSMVYUs9XPORyqduzMffsrY0ZUsj/ZdTxFOyfJAqDblaaSeS+da4pdBJuWZSmpRqUTESCWsmvzDiqivZPWcLMoAe3ln+Ij/8jyKP0rkjXtQkjKoSTYlIUY3H4YtSnatPsfoOUVHW513Ul1OT5XyjFEG47RM8+c+5CEL2zB6uvQG62eHwpIMo8vSa5RexekB+dDvPb5CBqbSgy6vtBqVl8byqZc+rcfRdtWZ1UMvOzhs0vpZl0pfQVOn7VPjZxBt4Lr0vq1/hB12fTzzVEYoSw+zvHGWDuiVhfOImP4W/ADWQKtBGoPwH6j6AyAsgCpNhs1uvZCWd8SE1Sm1MbMVo/LVZ4lzWV84E1IfrHEUHa7dzGWyvco19U57vDFf2aHe79vNy6gMhqSMpquMRqe8039V/3eBMAt21ZtPp5dVcW3KUuemYqzVWGYlD3VTnl2C5Qbv6aoMfdUDo6rqYI1c9SHNe3kgrea4NTT3pfe/mJtXSuWVUyhSrzBqk1NYPovhSJoMAgmBlBG6MkqjDJJ94hi4H6AYZDTG/65Q+U6J2KsGKpv8LFqLlc3MXvY2nUnJOXmPyaPZfYX7UGU4cfOt1sq+aHebarDenDIy867VU0GdyTNWefLKiPmw/Q6nMxwEGOMA" after tData
         put "2vJOqQwSf6q9tNTzYTU8Y271gB12Yw5Y7lr40yZmQ19PA2vwjsVZh2k5frAGvkYhX/7LIICOq9pW/+YAaxB0N0cvuGWAtwwAlx7xahpNWEuiPLMYghupETBjlv8B1+gFOGIrTbJN6V6AyzBsoGs68QqbzRkUM+G+YAzQNsAS18AXO980nnPUJD7QYgfS+xs7xy8b0vse+emtymh6ymj0ymimyrsUfTv+/vOL/C2efp5/+HVa5h9/XOZpWeRHviWq/NSGvcrPCqmyN3nYgm1Kyt7lQY7xIT/yyXLKz6nsSx6uYJuSsm95uINtSsKu4q3OU5VYAr0KkqpIqsSq61QlslzzKk7q3rDFiRzrKiGrhqziTb9VJES9307MGkbKRiwYUZvIvAZu29TEpaG9C3ufp0OcSB8OiXzcwgYN6Sk/p5bK5dMpkc9lOsXJqU5AQ+q2yjYzdifYoCmNpoENX+HEabbYeqdseZBpYi+ts+rEaUjdVrMU+b4FbpOmb0qZDurtyNA79Q0aUo7PKW2RlcNwee9y2CCNkLvQ+x4ATZrpQOqAVFtC7pWl8m5kYSmVUp1WKol93jG4MbFOQ3qJ7TU32jbv0yUALpsTpymlEx+YWKHYHWTt0kzeQ14ivTasjLBJQxpILAHWN4aNtEujDZdM8HWQ7TVIJ5BeksWlK+UPXMAoFWhKuZe0FrXrapyAhlTSuSwdS2DaxHrbkZywSbv0lp97znVdZqudDP6sIz3bYSKPK23HJANj8wMP" after tData
         put "aUh5EC6xvpYYyFnrN9ccUch9yCysbot8QAKq9zwTC3nkQMzTJlA2mRL5ORUR6JAzI7NxHFAGCkXldMgfBdG5mjdeSM9UM3c65XE6WV0486vYhg+NJgpFOLi0AZ3Iuabe+gwfuJLjGptUbtN12sTFVmP5uGWgIWWhc/148iM9HB2X+hFXPOYPagFC9Z0DebzTHFawUx8cyB1Wvuy4/AxLGtKYVl/vmIUYAXAot/1oXqUx/XSUO+IaWC2++bV3m3RxW1jAvtyUit3WrOQmCWwH4CgbNKTSzE2buUnU7ebLbxdf+5KvSkp5eHaJLV83eInEcpGGVCLtWrpDnBwz3jXTKUqnAgQNabyGPXa8WE2ar2FI47WAMh8C4dhzN0FD6jnn+h1Cy6dVbCVoSs1WkVgCxBkvKNKQMh04wessfIOm1EqjuK1NeW5y/ILjGrf83OrfH3CX2vUBh3Lh3w3bO5wDCJpGoS1474Wr7Fc/lx/SW2xvnRZ/iNXiywE0pTaQ6Ruvbp+lfNEzsofkvFspJMNJ124Sv1Y0sZy0npNWkxratUmPkjZB+K4hUW5qqNAcCWOVxNd5WkWwLtMq3NXYGmKdVgmxbtMqLlat1ioO1yOMQtvk0yqh5dN9Ff+rRqdTib3eqb2J9TY7LE2hcYBw5kdLoiqQKfLUdAk9eppitZ/TLtF3jQ7aZMh+l989liZ2iUvk0kOow9ZA3B/Vq+UynQClIGEJBQVZhxDHmsYmg54j866hYd5B5x9CHFsu" after tData
         put "K9m2KWkOaWiDjSOT2jg6kFot8ty5da42aEpF+zgjWatHVgC0yXTWlGVZY/fz0IGG1CuSpeEZjIOBw+fSCKeto4tIA7TJsAz2bOMNhj0bV4dF4Qiu84jus82gIc11xDj5WYtDRRrDxXZ7YBt8FgWUS2KBnIkasnxO0dyAaPWlElflukRTQEPqG5mHzNXyxJN2qRspDl9VJB0bS9qll6C+7JvHHvjaC4CgIfXDpZ2QIHfFLW0ONmhIxei2ivjO3+L0lkWVyLdmCZoXwc5RIsFJzZBOUxpOtP03XwXxKcBXA6QGKE8hAPrxynQoJW4W1raZy+gUJNanrLWjyqKC5tG0RJVtAXhps2FOU2pgsqgcFX6+gGbJo9Z+idkCy7/JEHc6EneA+JCKlx1pl3qf8o3BopINmu8TC6HadrqDHesBGlJqYxjwCRAvUn4SYHSYDhYETrD8oCjzrfkX2Rlm32khAAA=" after tData
         break
      case "cloud.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0DM3M4STFibmXHlQaUOItIWJMZy0NDCCSxtBpC2NzRGkmSEXAGsAAYtdAAAA" after tData
         break
      case "plate.obj"
         put "H4sIAAAAAAAC/3VXSZLkNgy8zyv4AXVxJ/WdsccRjugeHzz2+40kABJU0ZeSkEjslIT6+vX5+ed39/XX7z8+P75+fX77113+477xGyJ+2x0Bho8Ayafk/EfvD+hSzNgaU58Lif7uIjCz92lOrhZzgZY67YPGFsSmw5Ag72Zn/4dMjim/xzx3YEY9VXWsfyOqrSZHXVzTuG+2fQffB3Sa42k+hOVgvOXAxAkq9n+FvDMPxdmcJeUDdGrBYbDHhJ99Nwjd5vw8ShZsJkRT65zfDtQT2myvo/F1sDbYW+Sjx1Peh/r8R62LVusOCXIdWNeRlu+yeMk3Rssog3ufWrKgUhVlB0JV+zTKEzALmFNb9vHulqpedy47WNQaJ5i9nMwcjH3W2TAqVAXZXqnqoKRVQE5qX29D7Zap4E4Ve2HG0m2pEincdTGVyqA63R1o/WLvy4oUonQqBlNU0BPLVEV3rjiQ0+nzihQav0BsS1MsC5OJCsSmGqTJm8Z304+bj6yv2XYuWaaiG1XHQcyfo/X8UPD7rytYBzhqCk/ssqBaG2McO74KECoDeEn9lM+cZ4UFVH4aPD0e7IeBCTAMbAZh5V4kiDeFF839HTwbvzXo1MhTz84tS8yrfM+8iSl0HTCTnSZnq1hFvEHXwfTRuLe5HNKkD6/zZmpzaE5wNC0ORZ/TbkOOme0625XIYszspkkKjWet7OHsMt66HBa2v8TBpR4ursiH5+mUvkCcuq147QUkMZpehtmlxHk6" after tData
         put "//n7B+2B7jf/7Q9XX6/qyutVXKc7AsZ9er2au+mHAFxcfL3oo+vpl5BAUqB8wut1u5AhAE0Q4YU1gMgZjU/5k0mkQFtDo0t00UMC7EcQVk40kdt4u0iX5F3KuAAeNy5UjjACASYzWkjEKFVIcH2PUCxLYIIRJGVUSL9hCAstSwcPzYBRqcmiTAHaDZra7iHdRzh7ozVwMNrl2gQAWC13ppGj4bIh0GRQpgDNFk0Px8X4X+QQlg3QalHmAG4bXBXuG9weEbsJjG4EC4e8s1kWrRyZBaf6gMvuRGTRJob1EQmrAu3CrLeY1E1hxcimZ2GD8wOWCnT6fDPh9GCztvgHmysoGpL1erJmJiVs7HkCvHH6DsdHJt46yQ+2nLx5mOXMK9x3WM60PBHa+bgKk+CzXk3mftSLZIoraBq90zCH8UITWbQYQAGMcM0VBO+uwBfediqztiIkXnkVQW5XKXL2riZcAIssWkTCe69SbPr7UilWjq42SIBFFm2HBJjrrzyXqi1WWZ51fUL4ZhppT/hmwuUB86EseYdZ5p5MuM9WdSleZNXODo4Oz3JmlSyLlru/OsiNXq1SWbRNxsDNmf2t2iqRRTvHQE5yco0SpP8oLeBCsMiqhS0+Bg1mxTVKIVfXkC7KUVm0CIm8G+pqriFkdw2+0BOVWdsRCXl3xKavIMUq3nX4QpUqizZDAsz9bzzSpo+LyKrVA9GShXt4wHxcms6SbyasT2iLG+wNm4rXVmUpXmXWrg6ODs9y" after tData
         put "ZpUsi5a7bzo4Gr1aJbJqk4yBm6P95catfquWx6DvivGJp2861pSI5QXAuB8oquFVJ9C3G1BxETsJShSZldhhApLDuhG6i1hZ7rFlRGQhsmqpgogjTyXEKC5dBHlsFyyzcvg3joGm5UFl0XZIgKlOWhRHKVLFuBccu1LMsvZEWtuollhdAgdVqMxaLEFx7G+jHJfwhPJ2lsbuJDJruVQEHPWMrnItoEIQBfon619o6oS7apyydsbiCiVTqR5skUU78pbupDhSwgUuo0wDMmuTwnwz4bjDLI8E2UmwcHrCfInqJMYNrgrXDb53mGWnri3JZQXHcHSwPLh1AEQr89Zjn3VdH0s8lVt4NI1RAcbqPpb4xAu97O2ylCde1XlvHyt85T8CSpAdvsqGLVu77vC3rNIqjx0+8v8E3dllg0fytxw/8igbPJPWoi8b/GTrzi4b/NB++w8P2LLc1BYAAA==" after tData
         break
      case "plate.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEwVDDQszA0ApLG5mZceVApQ5CUgZ4RWAJKGpnDpY2g0uaGcNLYEC5rDDPXzMgErBEuYwKTMTcyBekxMOMCAAWUj+6NAAAA" after tData
         break
      case "gate.obj"
         put "H4sIAAAAAAAC/4VXSZLkNgy8zyv0AVZx0/Yd2zMRjui2Dx77/caSAMWl7UtL2BMEmKr+/Pnx8fsv2+efv33/eH3+/Pj2zxbyK+9bfMWL/uTzocmV/hRVuCweo8OUYhmQXpUVMe1Nc7Ci7ggxjzp4TDlKHzDD1iJdb5r12Ytr+kJhnbkrPVaasi4rj4cQpqbDdC6BSp47P9o84ivlplKM7vYYJHTP3hDatedutZt4n1+AhX4r8hcFRReGkhIaJk9VlhFH6Fs13dRXeA5tqPEAGBZthGev87xDvxJ5dUI9rIdT6M5oAGqbEfqpG6jHbrjquVMN+tPleTGnhgdMTdH5DKdpPtP6hv5+IbC7tfWBccj9RflhJIs+pl7/83weNNMf9v9gbve573+xTPPKzdu1uKrzhV7c3cU9nW/zfHFXd211KRfXb7rgEwfMF37e+PlazFdgul7TDZyu24oGFnSxJob8dfawKri6zYvLNH2VBkVYfT5Y84fQmmDmk7wzVLHIX/KFQo878TndB+tGnznNV0ESEzxIYkIXJDGhBcGp+ViW1IdYxLOBkIYuw6NNBxgeoUO18FX+J4Kh3CrzGkF/HmHRflgdUhQqOa28wE0nA7RzzfSncvLbFaHXaMYuKuqlOn3sY+IwlA7rSqIIz0qSJXSVJEsYK4c0oAtdU6FLHRa5w4wgjPXCovswn1FYn0iYCg7owwJqJNsW9c1fIgISv5tKU6jq77++02/j7df47ceW3u+05fc7b+X9" after tData
         put "LqSo73fd9vd73473+2APMqSyJTKkuiUy0ReE1De93FuOFBu3THlyYrW6SQLOTSp9V33zkzxaHpXl3fTibkrBxCANn2g5LymAQKp4epXU0vehLq2AyehSumL1RepryyTneyuUqfBxlZNezq2QlWZWyFrYu1I0jaUyuLpVql4ZWqXS9dgqBdVzqxRUL1arm0ajEudW2ZKYN5CgpAJib8iwjkgkGrlYDRlWwdXU1pUlgWxBAp+9pS8vaWcCGdZW8pYh8Qy2PemI9yxLsxcdWcW0jiqHf+yyI8eBFTuo8LEdjGI7bp22+bCoJVgpEkyeVQFouMBgT5FgsZRaXeOQhbFChjVjMRSddYe+kFBNUwZtw6qJBJMeBGnPWwZzRZn9lbBA1yWDuG6Z9R0xnzvJid9ZlvMuGMRdZd3uXdbtPrBASKrRiGVvlc1q3shtJTPWzWRUdiQSZjhdbbJaFRCrpS9P4rhRUq0KqJ2JlTA1ZLNKz05pPHcy3HLpQQB86CyJPvEceRMSQUwX6IT5JDm5qAV8A2KgqZ2NHVQCobCjeJKWKBwMZqQGPlNb5nmXVp2drJC8Q6/u7CdwFRd4TDGq3oFrYmcxJ2lAVKsjFfhgx8Z4KouNj4pVVDIfznaUtewP6lGrM5KRCw8qPjgGsloL3xg5agJTs1ONcYzJsFKSwkky1aYfMeAYpx5jJLUWCir5gVvcHpQJGbgliNVSxLsUAK1Ls3rzUsSbdapHe2ptXaJ5fAH8TCDDKs0yYVyy" after tData
         put "JeARIxcT1bgfWKGjyJ4rnRiPgGvEdNqq77cslXLfaSsDYlSb8yOYOPEWNM4T0ZhwxxbBCVxuvpARUnSRrAp35LUgwXRh47U/B+LfAhRXq2PQHu0bceoNQaNq8n4vXRLjICMfYx21nidW6NIlAe2dFdOHDGtjxyrrarTnfAf6Vuu5Y5mN7LNMHwz2w2RYzwMrZG5gdfOGDKuW4NxSxHFeWGbrQ62tHfQhh9HagWxnYBdFD8fh20fKAMOquI2QnW4IyWW8kmgDUgR7PSiZh304jwoV8m0W2nIS4y8nfwckoYVIwpZCbIOnroMhUEktQ7BxqXGwybBaVmsCjG1rZjKsEuSUK7FSlfOqpBajZlCZcRQZs5CREIrTC8+HOaDwICvIqbGl8QpPKDV6gaxJEcslVYZ1zG1cavxnMqwGECU1Grk4CWRYjRahtmYtifG4Wp3O7WOAZq1LyLB6SeUGZ4oT4zL6BBdGzAU8lXkRjK1OnZ0yR6NROEkkfFirshq9GrhRRLUxBIhqcwrTagDmdGWyWhtepXYgNGjmpZ8ElAMyO4iRYGE1xGeR01RqeHCVXGe/3BeWw2inyM44+xjHgjhsruami6aVWK0yrJ5bXzyXJwFDq9WJGrhRcmQ2s3oSUDGa9S7hBhovWCVjZAAytcmw9oQnv+4iTXFP233JI8XITyZWVtDPtpjlefP/BMJ8oqBfs6c+WM+JRK7IV5Goeq1qKZOXTLGglhexmgXFUMRqplhRzcp41dpV2xFb" after tData
         put "b8nJD2b+GyBYVqvAJL0FHp47omoEnOg448OjiuVfLPgwncwbAAA=" after tData
         break
      case "gate.mtl"
         put "H4sIAAAAAAAC/z3OOxKAIAwE0J5TeAInJOTDGTyG2imVM15fIkyabR7spp3v/VzLDmk7FlgVsWeB0hPVUpucBxvVngz+iJiCcXDNrsJeEUbD2HoI2D9SQ8tQEfL0dkMN5fn3H2T0YqEcLPPo4ruq4icQpQ+WlnR81AAAAA==" after tData
         break
   end switch
   return tData
end oiModelData
-- END GAME MODELS

-- =====================================================================
-- THE b3k KIT, carried verbatim from src/box3dxt-kit.livecodescript by
-- tools/sync-embedded-kit.py. Never edit between the two lines below:
-- edit the Kit and run the tool.
-- =====================================================================
-- >>> BEGIN EMBEDDED KIT >>>
-- =====================================================================
-- box3dxt-kit.livecodescript   /   "Box3Dxt Kit"  (b3k...)
--
-- A friendly, pure-xTalk game toolkit over the box3dxt extension: the
-- 3D sibling of box2dxt's b2k Kit. You work in METRES and DEGREES with y
-- pointing up; the Kit runs the world on a fixed 1/60 s step, draws it
-- into one image control, moves the camera, reads the keyboard, steers a
-- player and sends your script messages when things touch.
-- Runs in OpenXTalk (OXT) and OXT-Beyond; compatible with LiveCode 9.6.3+.
--
-- TWO RENDERERS, ONE KIT. When the render3dxt extension is loaded the
-- Kit draws with it (textured, lit, smooth edges, drawn on the library's
-- own threads while your script runs). Without it the Kit draws with the
-- renderer inside box3dxt itself (solid colours, one light). Your game
-- code is the same either way; b3kRenderer() says which one is drawing.
-- The join between the two extensions is box3dxt's move list:
-- b3WorldUpdateMoves then r3SceneApplyMoves, once per physics step.
--
-- Requires the box3dxt extension loaded (b3ABIVersion() 2 or later for
-- its own renderer). render3dxt is optional.
--
-- =====================  60-SECOND START  =============================
--   on openCard
--      b3kQuickStart                     -- world, view, ground, camera, go
--      b3kSpawnBox 0, 4, 0, 1, 1, 1, "orange"
--      b3kSpawnBall 0.3, 7, 0.2, 1, "blue"
--      put the result into tBall          -- a thing is its body's handle
--   end openCard
--   on mouseUp
--      get b3kThingAt(the mouseH, the mouseV)    -- what is under the mouse
--      if it is not empty then b3kPush it, 0, 6, 0
--   end mouseUp
--   on closeCard
--      b3kTeardown                       -- before the card goes
--   end closeCard
--
-- =====================  CHEAT SHEET  ================================
-- WORLD   b3kSetup [gx,gy,gz] / b3kQuickStart [gy] / b3kStart / b3kStop /
--         b3kPause / b3kResume / b3kStepOnce / b3kIsRunning() / b3kIsPaused() /
--         b3kClear / b3kTeardown / b3kSetGravity gx,gy,gz / b3kGravity() /
--         b3kSetSubsteps n / b3kKillFloor y / b3kWorld() / b3kEnsureNativeLib
-- TARGETS b3kFrameTarget obj / b3kContactTarget obj
-- VIEW    b3kViewMake l,t,w,h / b3kViewAttach img / b3kView() /
--         b3kUseRenderer "auto"|"render3dxt"|"box3dxt"|"none" / b3kRenderer() /
--         b3kSetBackground color / b3kSetLight dx,dy,dz[,color] / b3kSetAmbient color /
--         b3kSetFog color,near,far / b3kSetSmooth 1..4 / b3kSetRenderMode mode /
--         b3kDraw / b3kSync
-- CAMERA  b3kCamOrbit yaw,pitch,dist[,tx,ty,tz] / b3kCamOrbitBy dYaw,dPitch /
--         b3kCamLookAt ex,ey,ez,tx,ty,tz[,fov] / b3kCamZoom dist / b3kCamZoomBy f /
--         b3kCamSetFov deg / b3kCamFollow thing[,lerp,height] / b3kCamUnfollow /
--         b3kCamShake metres,ms / b3kCamMouseOrbit flag / b3kCamDragged() /
--         b3kCamEye() / b3kCamTarget() / b3kCamYaw() / b3kCamPitch() /
--         b3kCamDistance() / b3kCamText()
-- SPAWN   b3kSpawnBox x,y,z,w,h,d[,color] / b3kSpawnBall x,y,z,diam[,color] /
--         b3kSpawnCapsule x,y,z,len,diam[,color] / b3kSpawnCylinder x,y,z,h,diam[,color] /
--         b3kSpawnCone x,y,z,h,diam[,color] / b3kSpawnHull x,y,z,points[,color] /
--         b3kSpawnModel x,y,z,objTextOrPath[,scale,color]          (-> thing)
-- SCENERY b3kAddGround [size,y,colorA,colorB] / b3kAddWalls [height] /
--         b3kAddStaticBox x,y,z,w,h,d[,color] / b3kAddRamp x,y,z,w,h,d,tilt[,yaw,color] /
--         b3kAddStaticModel x,y,z,objTextOrPath[,scale,color] /
--         b3kAddPlatform x,y,z,w,h,d[,color] / b3kGlideTo thing,x,y,z,seconds /
--         b3kIsGliding(thing)
-- SENSOR  b3kAddSensorBox x,y,z,w,h,d / b3kAddSensorBall x,y,z,diam
-- LOOK    b3kSetColor thing,color / b3kColor(thing) / b3kSetChecker thing,a,b[,cells] /
--         b3kSetTexture thing,path / b3kSetVisible thing,flag / b3kIsVisible(thing) /
--         b3kSetGlow thing,color / b3kGlow(thing) /
--         b3kSetLook thing,objTextOrPath[,mtlText,scale]
-- LAMPS   b3kAddLamp x,y,z[,color,range,intensity] (-> lamp) / b3kMoveLamp lamp,x,y,z /
--         b3kRemoveLamp lamp / b3kLamps()
-- MATERIAL b3kSetBounce thing,0..1 / b3kSetFriction thing,f / b3kSetDensity thing,d
-- BODY    b3kSetType thing,"static"|"kinematic"|"dynamic" / b3kType(thing) /
--         b3kSetGravityScale thing,s / b3kSetDamping thing,lin[,ang] /
--         b3kSetBullet thing,flag / b3kKeepUpright thing,flag / b3kWake thing /
--         b3kEnable thing / b3kDisable thing
-- ACT     b3kPush thing,dvx,dvy,dvz / b3kImpulse thing,ix,iy,iz / b3kForce thing,fx,fy,fz /
--         b3kTorque thing,tx,ty,tz / b3kSetVelocity thing,vx,vy,vz /
--         b3kSetSpin thing,wx,wy,wz (deg/s) / b3kMoveTo thing,x,y,z /
--         b3kSetRotation thing,rx,ry,rz (deg) / b3kTurnTo thing,yaw /
--         b3kExplode x,y,z[,radius,power] / b3kRemove thing
-- GET     b3kPosition(thing) / b3kX(thing) / b3kY(thing) / b3kZ(thing) /
--         b3kVelocity(thing) / b3kSpeed(thing) / b3kRotation(thing) / b3kYaw(thing) /
--         b3kMass(thing) / b3kIsAwake(thing) / b3kKind(thing) / b3kIsThing(x) /
--         b3kThings() / b3kThingCount() / b3kDistance(a,b) / b3kShapeOf(thing) /
--         b3kName thing,name / b3kNameOf(thing) / b3kThingNamed(name)
-- PICK    b3kThingAt(cardX,cardY) / b3kPointAt(cardX,cardY) /
--         b3kGroundPoint(cardX,cardY[,y]) / b3kProject(x,y,z) /
--         b3kRayHit(ox,oy,oz,dx,dy,dz) + b3kHitPoint() / b3kHitNormal() /
--         b3kHitDistance() / b3kOverlapSphere(x,y,z,r)
-- JOINTS  b3kHinge a,b,x,y,z,ax,ay,az / b3kBallJoint a,b,x,y,z / b3kWeld a,b /
--         b3kRope a,b[,maxLen] / b3kSlider a,b,ax,ay,az / b3kMotor j,deg/s[,torque] /
--         b3kHingeLimit j,lo,hi / b3kHingeAngle(j) / b3kRemoveJoint j / b3kNoCollide a,b
-- INPUT   b3kInputOn / b3kInputOff / b3kInputIsOn() / b3kKeyIsDown(k) / b3kKeyPressed(k) /
--         b3kKeyReleased(k) / b3kKeysHeld() / b3kBindAction name,keys /
--         b3kActionIsDown(name) / b3kActionPressed(name) / b3kActionReleased(name) /
--         b3kBindAxis name,neg,pos / b3kAxis(name) / b3kInputInject keys /
--         b3kInputInjectOff
-- PLAYER  b3kPlayerMake x,y,z[,kind,color] / b3kPlayerAttach thing[,mode] /
--         b3kPlayerSet key,value / b3kPlayerGet(key) / b3kPlayer() /
--         b3kPlayerOnGround() / b3kPlayerFacing() / b3kPlayerJump [speed] /
--         b3kPlayerControl flag / b3kPlayerSteer x,y / b3kPlayerRespawn x,y,z /
--         b3kPlayerRemove
--         (moves on axes "moveX"/"moveY" relative to the camera, jumps on
--         action "jump"; axis "turn" (q/e) turns the camera)
-- EVENTS  on b3kFrame / on b3kContact pA,pB / on b3kEndContact pA,pB /
--         on b3kSensorEnter pSensor,pVisitor / on b3kSensorExit pSensor,pVisitor /
--         on b3kFell pThing    (poll instead: b3kEvents())
-- INFO    b3kVersion() / b3kHasPhysics() / b3kHasRender3d() / b3kLastError() /
--         b3kFrameError() / b3kFrameMS() / b3kStats()
--
-- Tips: a THING is its body's handle (a positive whole number), so raw
-- b3... calls take it as it is. Messages go to the card that is current at
-- b3kSetup (its script, then its stack's) unless b3kFrameTarget /
-- b3kContactTarget say otherwise. Keep moving things between about 0.1 and
-- 10 metres: Box3D is tuned for that range.
-- =====================================================================

constant kB3kVersion = "1"
-- one physics step: a sixtieth of a second, in milliseconds and seconds
constant kB3kStepMs = 16.6666666667
constant kB3kStepS = 0.0166666666667
-- the most steps one frame may run; a longer stall is forgiven, not caught up
constant kB3kMaxSteps = 4
-- every collision category bit the shim accepts (2^53 - 1), and the one bit
-- the player's shape wears so that its own ground probe can look past it
constant kB3kAllBits = 9007199254740991
constant kB3kPlayerBit = 1073741824
-- every bit but that one: the mask the ground sweep looks through
constant kB3kNoPlayerBits = 9007198180999167
-- colours handed out in turn when a spawn names none
constant kB3kPalette = "231,96,76;240,172,64;94,170,92;72,140,214;160,106,200;236,124,170;70,190,190;232,214,90"

-- the world and the loop
local sWorld, sAnchor, sRunning, sPaused, sGen
local sSub, sAccum, sLast, sFrameMS, sFrames, sFpsCount, sFpsStart, sFps
local sFrameObj, sFrameAuto, sContactObj, sKillY, sKillTick
local sLastError, sFrameError, sSpawnCount, sEvents
-- the things: every table is keyed by the thing (its body handle)
local sKind, sShape, sDims, sColor, sNode, sOwnMesh, sOwnMat, sOwnTex
local sChecker, sTexPath, sModel, sScale, sVisible, sSensorOf, sName, sThingOf
local sGeo, sOwnLook, sModelPath, sGlide, sHasOwn, sBorn, sBornCount
local sGround, sGroundSize, sGroundY
-- the view and the renderers
local sView, sViewW, sViewH, sRenderer, sWant, sStale, sBegun
local sScene, sSun, sMeshes, sMats
local sBg, sAmbient, sLight, sFog, sSmooth, sMode
-- the sun's colour, each thing's glow, and the lamps: sLamp[n] is
-- "x,y,z;r,g,b;intensity;range" and sLampR3[n] its render3dxt light
local sSunColor, sGlow, sLamp, sLampR3, sLampCount
-- a model drawn in place of a thing's own shape (b3kSetLook): its OBJ text
-- or file, its material text, its scale, and the key of its shared mesh
local sLook, sLookMtl, sLookScale, sLookKey
-- the camera: a target, an orbit round it and a lens
local sCamTarget, sCamYaw, sCamPitch, sCamDist, sCamFov
local sCamEye, sCamF, sCamR, sCamU, sCamLast
local sCamFollow, sCamLerp, sCamHeight
local sShakeAmp, sShakeUntil, sCamMouse, sDragOn, sDragLoc, sDragMoved
-- the last ray or pick
local sHitThing, sHitPoint, sHitNormal, sHitDist
-- the keyboard
local sInputOn, sKeysNow, sKeysPrev, sInjectOn, sInjectKeys
local sKeyActions, sKeyActionsC, sAxisNeg, sAxisPos, sAxisNegC, sAxisPosC
-- the player
local sPlayer, sPlayKind, sPlayCtl, sPlay, sPlayGround, sPlayGroundAt
local sPlayJumpAt, sPlayWantAt, sPlayFacing, sPlayHalf, sPlayRadius
local sPlayT, sPlayOn, sPlayCut, sPlayAirLeft, sPlaySteer, sPlayOld

/**
Title: Box3Dxt Kit
Author: Seth Morrow
Description:
A pure-script 3D game toolkit over the box3dxt extension (Box3D physics).
You work in metres and degrees with y pointing up; the Kit runs the world on
a fixed sixtieth-of-a-second step, draws it into one image control, moves
the camera, reads the keyboard, steers a player and sends your script
messages when things touch.

Start with <b3kQuickStart> (or <b3kSetup>, <b3kViewMake> and <b3kStart>),
make things with <b3kSpawnBox> and its siblings, and handle b3kFrame for
per-frame logic and b3kContact or b3kSensorEnter for touches. Commands
report through the result, so read it on the next line. When the
render3dxt extension is loaded the Kit draws with it (textured, lit,
smooth edges); otherwise it draws with the renderer inside box3dxt.

It needs the box3dxt extension loaded: b3kVersion() returns 1.

Tags: Physics, Games, 3D
*/

-- =====================================================================
-- Info and capability probes
-- =====================================================================

/**
Summary: The Kit's own version.

Returns: A whole number as text; it goes up when the Kit's calls change.

Example:
put "Box3Dxt Kit" && b3kVersion() into field "About"

References: b3kHasPhysics (handler), b3kHasRender3d (handler)
*/
function b3kVersion
   return kB3kVersion
end b3kVersion

/**
Summary: Report whether the box3dxt extension is loaded.

Returns: true when box3dxt answers; false otherwise.

Example:
if not b3kHasPhysics() then answer "Install the box3dxt extension first."

Description:
The Kit's first question. It asks the library its ABI number inside a
try, so a missing extension is an answer, not an error.

References: b3kHasRender3d (handler), b3kSetup (handler)
*/
function b3kHasPhysics
   local tAbi, tErr
   try
      put b3ABIVersion() into tAbi
   catch tErr
      return false
   end try
   return tAbi is a number and tAbi >= 1
end b3kHasPhysics

/**
Summary: Report whether the render3dxt extension is loaded.

Returns: true when render3dxt answers; false otherwise.

Example:
if b3kHasRender3d() then b3kSetSmooth 2

Description:
When it is, the Kit draws with it unless <b3kUseRenderer> says otherwise.

References: b3kUseRenderer (handler), b3kRenderer (handler)
*/
function b3kHasRender3d
   local tAbi, tErr
   try
      put r3ABIVersion() into tAbi
   catch tErr
      return false
   end try
   return tAbi is a number and tAbi >= 1
end b3kHasRender3d

-- box3dxt's own renderer arrived with its ABI 2.
private function b3kHasOwnRenderer
   local tAbi, tErr
   try
      put b3ABIVersion() into tAbi
   catch tErr
      return false
   end try
   return tAbi is a number and tAbi >= 2
end b3kHasOwnRenderer

/**
Summary: The reason the last Kit call that failed gave.

Returns: Text, or empty when nothing has failed.

Example:
b3kSetup
if b3kLastError() is not empty then answer b3kLastError()

References: b3kFrameError (handler)
*/
function b3kLastError
   return sLastError
end b3kLastError

/**
Summary: The error a frame last caught, if any.

Returns: The engine's error text, or empty.

Example:
if b3kFrameError() is not empty then put b3kFrameError() into field "Debug"

Description:
The loop runs your b3kFrame handler and the Kit's own frame work inside
one try, so that an error can never leave the screen locked. The error is
kept here instead of being lost: a frame that stopped half way says why.

References: b3kFrameTarget (handler), b3kLastError (handler)
*/
function b3kFrameError
   return sFrameError
end b3kFrameError

/**
Summary: The real time the last frame covered.

Returns: Milliseconds, or 0 before the first frame. A hand step counts as one 1/60 s step.

Example:
add b3kFrameMS() to tTimer

Description:
Drive game timers from this, not the frame count: a frame may run zero,
one or several fixed physics steps.

References: b3kFrameTarget (handler)
*/
function b3kFrameMS
   if sFrameMS is empty then return 0
   return sFrameMS
end b3kFrameMS

/**
Summary: How the Kit is doing, as one line.

Returns: Five items: pictures drawn in the last second, things, bodies awake, the renderer, and true when a frame has caught an error (see <b3kFrameError>).

Example:
put b3kStats() into field "Stats"

References: b3kFrameMS (handler), b3kRenderer (handler)
*/
function b3kStats
   local tAwake
   put 0 into tAwake
   if sWorld is not empty then put b3WorldAwakeBodyCount(sWorld) into tAwake
   return b3kNum(sFps, 0) & comma & b3kThingCount() & comma & tAwake & comma & b3kRenderer() & comma & (sFrameError is not empty)
end b3kStats

/**
Summary: The box3dxt world the Kit runs.

Returns: The world handle, or empty before <b3kSetup>.

Example:
put b3WorldContactCount(b3kWorld()) into tTouching

Description:
For raw b3... calls beside the Kit. A thing is its body's handle, so raw
body calls take a thing as it is.

References: b3kSetup (handler)
*/
function b3kWorld
   return sWorld
end b3kWorld

-- A number, or the default when the value is empty or not a number. Every
-- value the Kit hands a typed .lcb parameter goes through here first: an
-- empty value into "in pX as Number" is a hard runtime error (suite engine
-- note 6.4), not a zero.
private function b3kNum pValue, pDefault
   if pValue is a number then return pValue
   return pDefault
end b3kNum

-- a turn about x, then y, then z (degrees), as "qx,qy,qz,qw": the product
-- qz * qy * qx, written out. Computed here, with the engine's own sin and
-- cos, and not by b3QuatFromEuler: Box3D makes its quaternions with its own
-- fast cross-platform cosine and sine (b3ComputeCosSin), off by up to some
-- 0.2 degrees (measured on the engine, 2026-11-21), and a turn a game reads
-- back with b3kRotation should be the turn it asked for
private function b3kQuat pRx, pRy, pRz
   local tSa, tCa, tSb, tCb, tSc, tCc
   put sin(b3kNum(pRx, 0) * pi / 360) into tSa
   put cos(b3kNum(pRx, 0) * pi / 360) into tCa
   put sin(b3kNum(pRy, 0) * pi / 360) into tSb
   put cos(b3kNum(pRy, 0) * pi / 360) into tCb
   put sin(b3kNum(pRz, 0) * pi / 360) into tSc
   put cos(b3kNum(pRz, 0) * pi / 360) into tCc
   return (tCc * tCb * tSa - tSc * tCa * tSb) & comma & \
         (tCc * tCa * tSb + tSc * tCb * tSa) & comma & \
         (tCa * tCb * tSc - tCc * tSa * tSb) & comma & \
         (tCa * tCb * tCc + tSa * tSb * tSc)
end b3kQuat

-- =====================================================================
-- World & loop
-- =====================================================================

/**
Summary: Point the engine at libraries saved beside the stack.

Example:
b3kEnsureNativeLib

Description:
When box3dxt.dll, .dylib or .so (by platform) sits in the folder of the
saved stack, its revLibraryMapping is set to that file, so the extension
resolves with no install; render3dxt's library likewise. Otherwise the
engine's own search is left alone. An unsaved stack is a quiet no-op.
<b3kSetup> calls it for you.

References: b3kSetup (handler)
*/
command b3kEnsureNativeLib
   local tStackFile, tDir, tSuffix, tName, tOld
   put the effective filename of this stack into tStackFile
   if tStackFile is empty then exit b3kEnsureNativeLib
   switch the platform
      case "Win32"
         put ".dll" into tSuffix
         break
      case "MacOS"
         put ".dylib" into tSuffix
         break
      default
         put ".so" into tSuffix
   end switch
   put the itemDelimiter into tOld
   set the itemDelimiter to slash
   put item 1 to -2 of tStackFile into tDir
   set the itemDelimiter to tOld
   repeat for each item tName in "box3dxt,render3dxt"
      if there is a file (tDir & slash & tName & tSuffix) then
         set the revLibraryMapping[tName] to tDir & slash & tName & tSuffix
      end if
   end repeat
end b3kEnsureNativeLib

/**
Summary: Make a world with gravity, ready for things.

pGx: Gravity along x in m/s^2. Empty means 0.

pGy: Gravity along y; y points up, so empty means -10 (down).

pGz: Gravity along z. Empty means 0.

Example:
b3kSetup
b3kAddGround
b3kStart

Description:
Tears down any world the Kit already runs, makes a new one, picks the
renderer (<b3kUseRenderer>) and puts the camera at its starting place.
If box3dxt is not loaded nothing is made and <b3kLastError> says so;
the result says it too.

References: b3kQuickStart (handler), b3kStart (handler), b3kTeardown (handler)
*/
command b3kSetup pGx, pGy, pGz
   b3kEnsureNativeLib
   b3kTeardown
   put empty into sLastError
   put empty into sFrameError
   if not b3kHasPhysics() then
      put "the box3dxt extension is not loaded" into sLastError
      return sLastError
   end if
   put b3WorldCreate(b3kNum(pGx, 0), b3kNum(pGy, -10), b3kNum(pGz, 0), 1) into sWorld
   if sWorld is not a number or sWorld <= 0 then
      put "box3dxt made no world: " & b3LastError() into sLastError
      put empty into sWorld
      return sLastError
   end if
   -- a static body with no shape: the other end of a joint to "the world"
   put b3BodyCreate(sWorld, 0, 0, 0, 0) into sAnchor
   put 4 into sSub
   put false into sRunning
   put false into sPaused
   put 0 into sAccum
   put 0 into sSpawnCount
   put empty into sKillY
   put 0 into sKillTick
   put 0 into sFrames
   -- the messages' default home is the card current now: its script and
   -- its stack's script (where a pasted Kit sits) both hear them. "me" would
   -- be wrong for a Kit used as a library: the library itself, which holds
   -- no game code. A target the game named is kept.
   if sFrameObj is empty or sFrameAuto is true then
      put the long id of this card into sFrameObj
      put true into sFrameAuto
   end if
   put b3kHasOwnRenderer() into sHasOwn
   b3kCamReset
   b3kRendererPick
   return empty
end b3kSetup

/**
Summary: One call to a running scene: world, view, ground, camera, go.

pGy: Gravity along y; empty means -10.

Example:
b3kQuickStart
b3kSpawnBall 0, 5, 0, 1

Description:
<b3kSetup>, then a view filling the card if none is attached
(<b3kViewMake>), a 30 metre ground (<b3kAddGround>), the camera looking
at the middle, and <b3kStart>.

References: b3kSetup (handler), b3kViewMake (handler), b3kAddGround (handler)
*/
command b3kQuickStart pGy
   b3kSetup 0, pGy, 0
   if sWorld is empty then return sLastError
   if sView is empty or not exists(sView) then
      b3kViewMake 0, 0, the width of this card, the height of this card
   end if
   b3kAddGround 30
   b3kStart
   return empty
end b3kQuickStart

/**
Summary: Start the simulation loop.

Example:
b3kSetup
b3kAddGround
b3kStart

Description:
Steps the world at a fixed 1/60 s, carries each step to the picture,
delivers events and sends b3kFrame once a frame. Calls <b3kSetup> first
when there is no world. Starting again replaces a running loop.

References: b3kStop (handler), b3kPause (handler), b3kStepOnce (handler)
*/
command b3kStart
   if sWorld is empty then b3kSetup
   if sWorld is empty then exit b3kStart
   put true into sRunning
   put false into sPaused
   put 0 into sAccum
   put the milliseconds into sLast
   put the milliseconds into sFpsStart
   put 0 into sFpsCount
   put the milliseconds & "_" & random(1000000) into sGen
   put true into sStale
   b3kDraw
   send ("b3kStep " & sGen) to me in 16 milliseconds
end b3kStart

/**
Summary: Stop the simulation loop.

Example:
b3kStop

Description:
The world and its things stay; nothing steps until <b3kStart>.
<b3kTeardown> destroys the world as well.

References: b3kStart (handler), b3kTeardown (handler)
*/
command b3kStop
   put false into sRunning
   put the milliseconds & random(9999) into sGen
end b3kStop

/**
Summary: Freeze the simulation without stopping the loop.

Example:
b3kPause

Description:
While paused no physics step runs and no b3kFrame is sent, but the camera
still answers the mouse and the keys, and the picture is redrawn when it
moves. <b3kStepOnce> still advances one step.

References: b3kResume (handler), b3kIsPaused (handler)
*/
command b3kPause
   put true into sPaused
end b3kPause

/**
Summary: Resume after <b3kPause>.

Example:
b3kResume

References: b3kPause (handler)
*/
command b3kResume
   put false into sPaused
   put 0 into sAccum
   put the milliseconds into sLast
end b3kResume

/**
Summary: Report whether the loop is stepping.

Returns: true while started and not paused.

Example:
if b3kIsRunning() then b3kPause

References: b3kIsPaused (handler)
*/
function b3kIsRunning
   return sRunning is true and sPaused is not true
end b3kIsRunning

/**
Summary: Report whether the loop is paused.

Returns: true or false.

Example:
if b3kIsPaused() then b3kResume

References: b3kIsRunning (handler)
*/
function b3kIsPaused
   return sPaused is true
end b3kIsPaused

/**
Summary: Change gravity.

pGx: Along x, m/s^2.

pGy: Along y; -10 is earth-like.

pGz: Along z.

Example:
b3kSetGravity 0, -3, 0   -- the moon, more or less

References: b3kGravity (handler)
*/
command b3kSetGravity pGx, pGy, pGz
   if sWorld is empty then exit b3kSetGravity
   b3WorldSetGravity sWorld, b3kNum(pGx, 0), b3kNum(pGy, -10), b3kNum(pGz, 0)
end b3kSetGravity

/**
Summary: The world's gravity.

Returns: "x,y,z" in m/s^2, or empty with no world.

Example:
put item 2 of b3kGravity() into tDown

References: b3kSetGravity (handler)
*/
function b3kGravity
   if sWorld is empty then return empty
   return b3WorldGravity(sWorld)
end b3kGravity

/**
Summary: Set how many solver sub-steps each step takes.

pN: 1 to 8; the Kit starts at 4.

Example:
b3kSetSubsteps 8   -- tall stacks stand steadier

References: b3kSetup (handler)
*/
command b3kSetSubsteps pN
   put max(1, min(8, round(b3kNum(pN, 4)))) into sSub
end b3kSetSubsteps

/**
Summary: Choose the object that receives b3kFrame and b3kFell.

pObject: A reference to an object, such as the long id of this card;
empty puts the default back.

Example:
b3kFrameTarget the long id of this card

Description:
Until you name one, the target is the card that is current when
<b3kSetup> makes the world (each b3kSetup chooses again), so a handler in
that card's script or in its stack's script, where a pasted Kit sits,
hears the messages. A target you name is kept until you name another.
b3kFrame is sent once a frame, after the physics steps and before the
picture is drawn: read the keys and move things there.

References: b3kContactTarget (handler), b3kFrameError (handler)
*/
command b3kFrameTarget pObject
   if pObject is empty then
      put the long id of this card into sFrameObj
      put true into sFrameAuto
   else
      put pObject into sFrameObj
      put false into sFrameAuto
   end if
end b3kFrameTarget

/**
Summary: Choose the object that receives the touch and sensor messages.

pObject: A reference to an object; empty sends them to the frame target.

Example:
b3kContactTarget the long id of this card

Description:
Receives b3kContact and b3kEndContact (two things), b3kSensorEnter and
b3kSensorExit (the sensor, then the thing that came or went).

References: b3kFrameTarget (handler), b3kEvents (handler)
*/
command b3kContactTarget pObject
   put pObject into sContactObj
end b3kContactTarget

/**
Summary: Remove things that fall below a height.

pY: The height in metres; empty turns it off.

Example:
b3kKillFloor -10

Description:
A few times a second, every moving thing whose centre is below pY is sent
to the frame target as b3kFell, then removed. The player is reported and
NOT removed: your game decides where it starts again.

References: b3kRemove (handler), b3kPlayer (handler)
*/
command b3kKillFloor pY
   if pY is a number then
      put pY into sKillY
   else
      put empty into sKillY
   end if
end b3kKillFloor

/**
Summary: Remove every thing, keep the world.

Example:
b3kClear
b3kAddGround

Description:
Things, the ground, the player and every joint go; the world, its
gravity, the camera, the view and the loop stay.

References: b3kTeardown (handler), b3kRemove (handler)
*/
command b3kClear
   local tThing, tAll
   -- the keys first: b3kRemove deletes from the table being walked
   put the keys of sKind into tAll
   repeat for each line tThing in tAll
      b3kRemove tThing
   end repeat
   put the keys of sLamp into tAll
   repeat for each line tThing in tAll
      b3kRemoveLamp tThing
   end repeat
   b3kTablesReset
   put true into sStale
end b3kClear

/**
Summary: Stop the loop and destroy the world and everything the Kit made.

Example:
b3kTeardown    -- in closeCard, before the card goes

Description:
The world, every thing, the render3dxt scene with its meshes, materials
and textures, the player and the camera's follow all go. The view image
is kept (it is your control) and so are the key bindings.

References: b3kSetup (handler), b3kClear (handler)
*/
command b3kTeardown
   put false into sRunning
   put the milliseconds & random(9999) into sGen
   b3kSceneFree
   if sWorld is not empty then
      b3WorldDestroy sWorld
   end if
   put empty into sWorld
   put empty into sAnchor
   b3kTablesReset
   b3kPlayerForget true
   put empty into sRenderer
   put false into sBegun
end b3kTeardown

-- forgets every thing; destroys nothing (the world and scene go elsewhere)
private command b3kTablesReset
   put empty into sKind
   put empty into sBorn
   put 0 into sBornCount
   put empty into sShape
   put empty into sDims
   put empty into sColor
   put empty into sNode
   put empty into sOwnMesh
   put empty into sOwnMat
   put empty into sOwnTex
   put empty into sChecker
   put empty into sGlow
   put empty into sTexPath
   put empty into sModel
   put empty into sModelPath
   put empty into sLook
   put empty into sLookMtl
   put empty into sLookScale
   put empty into sLookKey
   put empty into sGeo
   put empty into sOwnLook
   put empty into sGlide
   put empty into sScale
   put empty into sVisible
   put empty into sSensorOf
   put empty into sName
   put empty into sThingOf
   put empty into sGround
   put empty into sPlayer
   put empty into sCamFollow
   put empty into sEvents
   -- the lamps go with the things (b3kClear destroys their render3dxt
   -- lights first; b3kTeardown's scene took them with it)
   put empty into sLamp
   put empty into sLampR3
   put 0 into sLampCount
end b3kTablesReset

-- =====================================================================
-- The loop: a fixed step, generation-guarded, one screen lock a frame
-- =====================================================================
-- b3kStep is sent, so it is public; everything it calls is the Kit's own.
-- It reschedules with ITS generation pGen, never the live sGen: a game that
-- tears its world down and starts again inside b3kFrame makes a new loop,
-- and this one must die at its next tick instead of running beside it.

-- ONE FRAME OF THE LOOP, the timer message b3kStart sends and that sends
-- itself on (pGen: the generation of the loop that sent it). Not API, so
-- no doc block: start the loop with b3kStart and step a paused world with
-- b3kStepOnce. It reads the keys, steers the player, runs the physics steps
-- the clock owes (at most four), removes fallen things, moves the camera,
-- delivers events, sends b3kFrame and draws. It is public only because a
-- `send` must reach it; tools/check-dictionary-docs.py exempts it by name.
on b3kStep pGen
   local tNow, tNext, tErr
   if sRunning is not true then exit b3kStep
   if pGen is not sGen then exit b3kStep
   put the milliseconds into tNow
   put tNow - sLast into sFrameMS
   put tNow into sLast
   lock screen
   try
      if sPaused is not true then
         add sFrameMS to sAccum
         if sAccum > kB3kMaxSteps * kB3kStepMs then put kB3kMaxSteps * kB3kStepMs into sAccum
         b3kFrameWork
      else
         b3kCamTick
         b3kFrameDraw
      end if
   catch tErr
      put tErr into sFrameError
   end try
   unlock screen
   -- pace the next frame against what this one cost: 1 to 16 ms
   put 16 - (the milliseconds - tNow) into tNext
   if tNext < 1 then put 1 into tNext
   if tNext > 16 then put 16 into tNext
   send ("b3kStep " & pGen) to me in tNext milliseconds
end b3kStep

-- the body of a frame; the caller holds the lock and the try
private command b3kFrameWork
   b3kInputTick
   b3kPlayerTick
   b3kGlideTick
   put empty into sEvents
   repeat while sAccum >= kB3kStepMs
      b3kWorldStep
      subtract kB3kStepMs from sAccum
   end repeat
   b3kKillTick
   b3kCamTick
   b3kDispatchEvents
   if sFrameObj is not empty then dispatch "b3kFrame" to sFrameObj
   b3kFrameDraw
end b3kFrameWork

/**
Summary: Advance exactly one 1/60 s step, even while paused.

Example:
b3kPause
b3kStepOnce

Description:
Runs one whole frame of one step: keys, player, physics, events,
b3kFrame and the picture. For a Step button and for tests. Needs a world;
the loop need not be running.

References: b3kPause (handler), b3kStart (handler)
*/
command b3kStepOnce
   local tErr
   if sWorld is empty then exit b3kStepOnce
   put kB3kStepMs into sFrameMS
   put kB3kStepMs into sAccum
   lock screen
   try
      b3kFrameWork
   catch tErr
      put tErr into sFrameError
   end try
   unlock screen
   put 0 into sAccum
end b3kStepOnce

-- one physics step, its events harvested and its moves carried to the
-- picture. Box3D keeps only the LAST step's events and moves, so they are
-- read after every step, not once a frame.
private command b3kWorldStep
   local tCount, i, tA, tB
   b3WorldStep sWorld, kB3kStepS, sSub
   -- the simulation clock: the player's coyote and buffer windows run on it
   add 1 to sFrames
   -- touches
   get b3WorldUpdateContactEvents(sWorld)
   put b3ContactBeginCount() into tCount
   repeat with i = 1 to tCount
      put b3ShapeBody(b3ContactBeginShapeA(i)) into tA
      put b3ShapeBody(b3ContactBeginShapeB(i)) into tB
      put "contact," & tA & comma & tB & return after sEvents
   end repeat
   put b3ContactEndCount() into tCount
   repeat with i = 1 to tCount
      put b3ShapeBody(b3ContactEndShapeA(i)) into tA
      put b3ShapeBody(b3ContactEndShapeB(i)) into tB
      put "endcontact," & tA & comma & tB & return after sEvents
   end repeat
   -- sensors
   get b3WorldUpdateSensorEvents(sWorld)
   put b3SensorBeginCount() into tCount
   repeat with i = 1 to tCount
      put b3ShapeBody(b3SensorBeginSensor(i)) into tA
      put b3ShapeBody(b3SensorBeginVisitor(i)) into tB
      put "sensorenter," & tA & comma & tB & return after sEvents
   end repeat
   put b3SensorEndCount() into tCount
   repeat with i = 1 to tCount
      put b3ShapeBody(b3SensorEndSensor(i)) into tA
      put b3ShapeBody(b3SensorEndVisitor(i)) into tB
      put "sensorexit," & tA & comma & tB & return after sEvents
   end repeat
   -- moves: the whole join between the two extensions
   if b3WorldUpdateMoves(sWorld) > 0 then
      if sRenderer is "render3dxt" then
         get r3SceneApplyMoves(sScene, b3MovesText())
      end if
      put true into sStale
   end if
end b3kWorldStep

/**
Summary: This frame's events, for polling instead of messages.

Returns: One line per event, "kind,a,b": kind is contact, endcontact, sensorenter or sensorexit; a and b are things (0 for a body the Kit did not make, or one already gone).

Example:
put b3kEvents() into tEvents
filter tEvents with "sensorenter,*"
put the number of lines of tEvents into tPickups

Description:
Read it from b3kFrame: it covers every physics step of the frame.

References: b3kContactTarget (handler)
*/
function b3kEvents
   return sEvents
end b3kEvents

-- the messages for this frame's events, after every step has run
private command b3kDispatchEvents
   local tTarget, tEvent, tA, tB
   if sEvents is empty then exit b3kDispatchEvents
   put sContactObj into tTarget
   if tTarget is empty then put sFrameObj into tTarget
   if tTarget is empty then exit b3kDispatchEvents
   set the itemDelimiter to comma
   repeat for each line tEvent in sEvents
      put item 2 of tEvent into tA
      put item 3 of tEvent into tB
      switch item 1 of tEvent
         case "contact"
            dispatch "b3kContact" to tTarget with tA, tB
            break
         case "endcontact"
            dispatch "b3kEndContact" to tTarget with tA, tB
            break
         case "sensorenter"
            dispatch "b3kSensorEnter" to tTarget with tA, tB
            break
         case "sensorexit"
            dispatch "b3kSensorExit" to tTarget with tA, tB
            break
      end switch
   end repeat
end b3kDispatchEvents

-- the kill floor, six times a second
private command b3kKillTick
   local tThing, tFell
   if sKillY is empty then exit b3kKillTick
   add 1 to sKillTick
   if sKillTick mod 10 is not 0 then exit b3kKillTick
   put empty into tFell
   repeat for each key tThing in sKind
      if b3BodyType(tThing) is 2 and b3BodyY(tThing) < sKillY then
         put tThing & return after tFell
      end if
   end repeat
   repeat for each line tThing in tFell
      if sFrameObj is not empty then dispatch "b3kFell" to sFrameObj with tThing
      if tThing is not sPlayer then b3kRemove tThing
   end repeat
end b3kKillTick

-- =====================================================================
-- The view and the two renderers
-- =====================================================================
-- The picture is drawn into ONE image control, the view. With render3dxt
-- the Kit keeps a scene: one node a thing, tagged with the thing's body
-- handle, so r3SceneApplyMoves(sScene, b3MovesText()) carries a whole
-- physics step to the picture in one call; the picture is begun in the
-- background (r3SceneRenderBegin) and shown on the next frame, so the
-- engine's one script thread never waits for it. Without render3dxt the
-- Kit asks box3dxt to draw its own world (b3RenderWorld), which reads the
-- bodies directly and needs no scene at all.

/**
Summary: Make an image to draw into and attach it as the view.

pLeft: Its left edge on the card, in pixels.

pTop: Its top edge.

pWidth: Its width, 16 to 2048 pixels.

pHeight: Its height, 16 to 2048 pixels.

Returns: (through the result) the image's long id.

Example:
b3kViewMake 0, 40, 640, 400

Description:
Makes an image named "b3kView" on the current card, or reuses the one
there, and hands it to <b3kViewAttach>. A smaller picture draws faster:
halve both sides and it costs a quarter as much.

References: b3kViewAttach (handler), b3kView (handler)
*/
command b3kViewMake pLeft, pTop, pWidth, pHeight
   local tW, tH
   put max(16, min(2048, round(b3kNum(pWidth, 640)))) into tW
   put max(16, min(2048, round(b3kNum(pHeight, 400)))) into tH
   if there is not an image "b3kView" then
      create image "b3kView"
   end if
   set the lockLoc of image "b3kView" to true
   set the rect of image "b3kView" to round(b3kNum(pLeft, 0)), round(b3kNum(pTop, 0)), \
         round(b3kNum(pLeft, 0)) + tW, round(b3kNum(pTop, 0)) + tH
   b3kViewAttach the long id of image "b3kView"
   return the long id of image "b3kView"
end b3kViewMake

/**
Summary: Draw into an image you made.

pImage: A reference to an image control (the long id is safest).

Example:
b3kViewAttach the long id of image "Game"

Description:
The picture takes the image's size, read again whenever the image is
resized. The image's own contents are replaced by the picture.

References: b3kViewMake (handler), b3kView (handler)
*/
command b3kViewAttach pImage
   if pImage is empty or not exists(pImage) then
      put "there is no such image: " & pImage into sLastError
      return sLastError
   end if
   put the long id of pImage into sView
   set the lockLoc of sView to true
   put the width of sView into sViewW
   put the height of sView into sViewH
   put true into sStale
   if sWorld is not empty then b3kDraw
   return empty
end b3kViewAttach

/**
Summary: The image the Kit draws into.

Returns: Its long id, or empty when there is none.

Example:
put the rect of b3kView() into tRect

References: b3kViewMake (handler), b3kViewAttach (handler)
*/
function b3kView
   if sView is not empty and not exists(sView) then put empty into sView
   return sView
end b3kView

/**
Summary: Choose who draws the picture.

pWhich: "auto" (the default), "render3dxt", "box3dxt" or "none".

Example:
b3kUseRenderer "box3dxt"   -- solid colours, even with render3dxt loaded

Description:
"auto" takes render3dxt when it is loaded and box3dxt's own renderer
otherwise. "none" runs the physics and draws nothing. Naming a renderer
that is not loaded falls back as "auto" would, and <b3kRenderer> says
what was chosen. It can change while things exist: their pictures are
remade.

References: b3kRenderer (handler), b3kHasRender3d (handler)
*/
command b3kUseRenderer pWhich
   put pWhich into sWant
   if sWorld is not empty then b3kRendererPick
end b3kUseRenderer

/**
Summary: Who is drawing the picture.

Returns: "render3dxt", "box3dxt" or "none"; empty before <b3kSetup>.

Example:
if b3kRenderer() is "box3dxt" then b3kSetRenderMode "outline"

References: b3kUseRenderer (handler)
*/
function b3kRenderer
   return sRenderer
end b3kRenderer

-- settles sRenderer from sWant and what is loaded, and builds or frees the
-- render3dxt scene to match
private command b3kRendererPick
   local tWant, tPick
   put sWant into tWant
   if tWant is empty then put "auto" into tWant
   put "none" into tPick
   if tWant is not "none" then
      if tWant is not "box3dxt" and b3kHasRender3d() then
         put "render3dxt" into tPick
      else if b3kHasOwnRenderer() then
         put "box3dxt" into tPick
      else if b3kHasRender3d() then
         put "render3dxt" into tPick
      end if
   end if
   if tPick is sRenderer then exit b3kRendererPick
   b3kSceneFree
   put tPick into sRenderer
   if tPick is "render3dxt" then b3kSceneMake
   b3kCamApply
   put true into sStale
end b3kRendererPick

-- the render3dxt scene and a node for every thing there already is
private command b3kSceneMake
   local tThing
   put r3SceneCreate() into sScene
   put empty into sMeshes
   put empty into sMats
   -- a new scene has no camera yet: make b3kCamApply hand it over
   put empty into sCamLast
   b3kSceneLook
   repeat for each key tThing in sKind
      b3kVisualMake tThing
   end repeat
   repeat for each key tThing in sLamp
      b3kLampMake tThing
   end repeat
end b3kSceneMake

-- the scene's background, ambient light, sun, fog and smoothing
private command b3kSceneLook
   if sRenderer is not "render3dxt" or sScene is empty then exit b3kSceneLook
   set the itemDelimiter to comma
   r3SceneSetBackground sScene, item 1 of sBg, item 2 of sBg, item 3 of sBg
   r3SceneSetAmbient sScene, item 1 of sAmbient, item 2 of sAmbient, item 3 of sAmbient
   -- THE SUN IS THE SCENE'S OWN LIGHT. A new render3dxt scene starts with
   -- one directional light (light 1, the one box3dxt's renderer starts
   -- with); a second one of the Kit's lit every surface twice, nearly
   -- white (seen in the example game's first frames, 2026-11-21). So the
   -- Kit takes light 1 and turns it, and makes one only if it is gone.
   -- Nested: a typed call never shares an expression with its guard
   -- (engine note 2.5).
   if sSun is not empty then
      if not r3LightIsValid(sSun) then put empty into sSun
   end if
   if sSun is empty then
      if r3SceneLightCount(sScene) >= 1 then put r3SceneLight(sScene, 1) into sSun
   end if
   if sSun is not empty then
      if not r3LightIsValid(sSun) then put empty into sSun
   end if
   if sSunColor is empty then put "255,248,236" into sSunColor
   if sSun is empty then
      put r3LightCreateDirectional(sScene, item 1 of sLight, item 2 of sLight, item 3 of sLight, \
            item 1 of sSunColor, item 2 of sSunColor, item 3 of sSunColor, 1) into sSun
   else
      r3LightSetDirection sSun, item 1 of sLight, item 2 of sLight, item 3 of sLight
      r3LightSetColor sSun, item 1 of sSunColor, item 2 of sSunColor, item 3 of sSunColor, 1
   end if
   if sFog is not empty then
      r3SceneSetFog sScene, item 1 of sFog, item 2 of sFog, item 3 of sFog, item 4 of sFog, item 5 of sFog
   end if
   r3SceneSetSupersample sScene, sSmooth
end b3kSceneLook

-- everything render3dxt holds for the Kit goes back: the scene (with its
-- nodes and lights), then the meshes, materials and textures
private command b3kSceneFree
   local tThing, tHandle
   if sScene is not empty then
      r3SceneDestroy sScene
      repeat for each element tHandle in sMeshes
         r3MeshDestroy tHandle
      end repeat
      repeat for each element tHandle in sMats
         r3MaterialDestroy tHandle
      end repeat
      repeat for each key tThing in sKind
         repeat for each item tHandle in sOwnMesh[tThing]
            r3MeshDestroy tHandle
         end repeat
         repeat for each item tHandle in sOwnMat[tThing]
            r3MaterialDestroy tHandle
         end repeat
         repeat for each item tHandle in sOwnTex[tThing]
            r3TextureDestroy tHandle
         end repeat
      end repeat
   end if
   put empty into sScene
   put empty into sSun
   put empty into sLampR3
   put empty into sMeshes
   put empty into sMats
   put empty into sNode
   put empty into sOwnMesh
   put empty into sOwnMat
   put empty into sOwnTex
   put false into sBegun
end b3kSceneFree

/**
Summary: Set the colour behind everything.

pColor: A colour name, "r,g,b" or "#rrggbb".

Example:
b3kSetBackground "20,24,36"

References: b3kSetLight (handler), b3kSetFog (handler)
*/
command b3kSetBackground pColor
   put b3kRGB(pColor, "26,30,44") into sBg
   b3kSceneLook
   put true into sStale
end b3kSetBackground

/**
Summary: Set the direction the sunlight travels.

pDx: The x of the direction.

pDy: The y of the direction; negative shines down.

pDz: The z of the direction.

pColor: The sunlight's colour (render3dxt only); empty keeps it as it
is. It starts a warm white, "255,248,236".

Example:
b3kSetLight -0.4, -1, -0.3
b3kSetLight -0.8, -0.5, -0.3, "255,196,140"   -- a low evening sun

Description:
Both renderers light from this direction; a surface facing away keeps a
dim shade, so nothing goes black. box3dxt's renderer lights in white.

References: b3kSetAmbient (handler)
*/
command b3kSetLight pDx, pDy, pDz, pColor
   if pColor is not empty then put b3kRGB(pColor, "255,248,236") into sSunColor
   if b3kNum(pDx, 0) = 0 and b3kNum(pDy, 0) = 0 and b3kNum(pDz, 0) = 0 then
      b3kSceneLook
      put true into sStale
      exit b3kSetLight
   end if
   put b3kNum(pDx, 0) & comma & b3kNum(pDy, -1) & comma & b3kNum(pDz, 0) into sLight
   b3kSceneLook
   put true into sStale
end b3kSetLight

/**
Summary: Set the light that reaches every surface (render3dxt only).

pColor: A colour name, "r,g,b" or "#rrggbb"; darker is moodier.

Example:
b3kSetAmbient "60,64,80"

References: b3kSetLight (handler)
*/
command b3kSetAmbient pColor
   put b3kRGB(pColor, "70,74,90") into sAmbient
   b3kSceneLook
   put true into sStale
end b3kSetAmbient

/**
Summary: Fade far things into a colour (render3dxt only).

pColor: The fog's colour; usually the background's.

pNear: Where the fog starts, in metres from the camera.

pFar: Where it is complete. Empty or 0 turns fog off.

Example:
b3kSetFog "26,30,44", 20, 60

References: b3kSetBackground (handler)
*/
command b3kSetFog pColor, pNear, pFar
   if b3kNum(pFar, 0) <= 0 then
      put empty into sFog
      if sScene is not empty then
         r3SceneSetFog sScene, 0, 0, 0, 0, 0
      end if
   else
      put b3kRGB(pColor, sBg) & comma & b3kNum(pNear, 10) & comma & pFar into sFog
   end if
   b3kSceneLook
   put true into sStale
end b3kSetFog

/**
Summary: Choose how smooth edges are (render3dxt only).

pN: 1 (fastest, jagged) to 4 (smoothest); the Kit starts at 2.

Example:
b3kSetSmooth 1   -- for a slow machine

References: b3kRenderer (handler)
*/
command b3kSetSmooth pN
   put max(1, min(4, round(b3kNum(pN, 2)))) into sSmooth
   b3kSceneLook
   put true into sStale
end b3kSetSmooth

/**
Summary: Choose how box3dxt's own renderer draws.

pMode: "solid" (the default), "wireframe" or "outline" (solid with edges).

Example:
b3kSetRenderMode "outline"

Description:
render3dxt always draws solid; this applies to box3dxt's renderer.

References: b3kUseRenderer (handler)
*/
command b3kSetRenderMode pMode
   switch pMode
      case "wireframe"
      case "wire"
         put 1 into sMode
         break
      case "outline"
      case "outlines"
         put 2 into sMode
         break
      default
         put 0 into sMode
   end switch
   put true into sStale
end b3kSetRenderMode

/**
Summary: Hang a lamp in the world: a light that shines from a point (render3dxt only).

pX: The x of the lamp.

pY: The y of the lamp.

pZ: The z of the lamp.

pColor: Its colour; empty is a warm "255,214,150".

pRange: How far its light reaches, in metres; empty means 8.

pIntensity: How bright, 0 to 4; empty means 1.

Returns: (through the result) the lamp, a whole number, or empty when there
is no world or the world already has seven lamps.

Example:
b3kAddLamp 0, 2.5, 0, "255,200,120", 6
put the result into tLamp

Description:
Things within the range are lit from the lamp as well as the sun, more
the nearer they are. Lighting is worked out at the corners of each shape,
so a lamp shows best on rounded things and small boxes; a big flat box
whose corners are all out of range is not lit by it. A world holds at most
seven lamps beside the sun. Lamps go with <b3kClear> and <b3kTeardown>,
and come back when the renderer changes. box3dxt's renderer has no lamps.

References: b3kMoveLamp (handler), b3kRemoveLamp (handler), b3kSetGlow (handler)
*/
command b3kAddLamp pX, pY, pZ, pColor, pRange, pIntensity
   local tId
   if sWorld is empty then return empty
   if the number of lines of the keys of sLamp >= 7 then
      put "a world holds at most seven lamps" into sLastError
      return empty
   end if
   add 1 to sLampCount
   put sLampCount into tId
   put b3kNum(pX, 0) & comma & b3kNum(pY, 0) & comma & b3kNum(pZ, 0) & ";" & \
         b3kRGB(pColor, "255,214,150") & ";" & max(0, min(4, b3kNum(pIntensity, 1))) & ";" & \
         max(0.1, min(1000, b3kNum(pRange, 8))) into sLamp[tId]
   b3kLampMake tId
   put true into sStale
   return tId
end b3kAddLamp

/**
Summary: Move a lamp.

pLamp: A lamp, from <b3kAddLamp>.

pX: The new x.

pY: The new y.

pZ: The new z.

Example:
b3kMoveLamp tLamp, b3kX(tTorch), b3kY(tTorch) + 0.5, b3kZ(tTorch)

Description:
A lamp that is not there is ignored.

References: b3kAddLamp (handler)
*/
command b3kMoveLamp pLamp, pX, pY, pZ
   local tSpec
   if pLamp is empty or sLamp[pLamp] is empty then exit b3kMoveLamp
   put sLamp[pLamp] into tSpec
   set the itemDelimiter to ";"
   put b3kNum(pX, 0) & comma & b3kNum(pY, 0) & comma & b3kNum(pZ, 0) into item 1 of tSpec
   put tSpec into sLamp[pLamp]
   set the itemDelimiter to comma
   if sLampR3[pLamp] is not empty then
      r3LightSetPosition sLampR3[pLamp], b3kNum(pX, 0), b3kNum(pY, 0), b3kNum(pZ, 0)
   end if
   put true into sStale
end b3kMoveLamp

/**
Summary: Take a lamp away.

pLamp: A lamp, from <b3kAddLamp>.

Example:
b3kRemoveLamp tLamp

Description:
Removing a lamp that is not there is harmless.

References: b3kAddLamp (handler), b3kLamps (handler)
*/
command b3kRemoveLamp pLamp
   if pLamp is empty or sLamp[pLamp] is empty then exit b3kRemoveLamp
   if sLampR3[pLamp] is not empty then r3LightDestroy sLampR3[pLamp]
   delete variable sLampR3[pLamp]
   delete variable sLamp[pLamp]
   put true into sStale
end b3kRemoveLamp

/**
Summary: The lamps there are.

Returns: One lamp a line, oldest first; empty if there are none.

Example:
put the number of lines of b3kLamps() into tCount

References: b3kAddLamp (handler)
*/
function b3kLamps
   local tKeys
   put the keys of sLamp into tKeys
   sort lines of tKeys numeric
   return tKeys
end b3kLamps

-- a lamp's render3dxt light, when render3dxt draws
private command b3kLampMake pLamp
   local tSpec, tPos, tRGB, tPower, tRange, tLight
   if sRenderer is not "render3dxt" or sScene is empty then exit b3kLampMake
   put sLamp[pLamp] into tSpec
   if tSpec is empty then exit b3kLampMake
   set the itemDelimiter to ";"
   put item 1 of tSpec into tPos
   put item 2 of tSpec into tRGB
   put item 3 of tSpec into tPower
   put item 4 of tSpec into tRange
   set the itemDelimiter to comma
   put r3LightCreatePoint(sScene, item 1 of tPos, item 2 of tPos, item 3 of tPos, \
         item 1 of tRGB, item 2 of tRGB, item 3 of tRGB, tPower, tRange) into tLight
   if tLight is a number and tLight > 0 then put tLight into sLampR3[pLamp]
end b3kLampMake

/**
Summary: Draw the picture now.

Example:
b3kMoveTo tCrate, 0, 3, 0
b3kDraw

Description:
The loop draws by itself whenever something moved; call this after
changing things while the loop is stopped or paused. It draws at once,
replacing any picture still being drawn in the background.

References: b3kSync (handler)
*/
command b3kDraw
   if sWorld is empty or sView is empty then exit b3kDraw
   if not b3kViewFits() then exit b3kDraw
   b3kCamApply
   put false into sStale
   put false into sBegun
   if sRenderer is "render3dxt" then
      b3kShow r3SceneRender(sScene, sViewW, sViewH)
   else if sRenderer is "box3dxt" then
      b3kOwnRender
   end if
end b3kDraw

/**
Summary: Put every thing's picture where its body is.

Example:
b3kPause
b3kMoveTo tCrate, 0, 2, 0
b3kSync

Description:
The loop does this by itself from the physics step's move list. After
moving things by hand in a stopped world, call it (it also draws).

References: b3kDraw (handler)
*/
command b3kSync
   local tThing
   if sRenderer is "render3dxt" then
      repeat for each key tThing in sKind
         b3kNodeSync tThing
      end repeat
   end if
   put true into sStale
   b3kDraw
end b3kSync

-- a thing's nodes to its body's place
private command b3kNodeSync pThing
   local tNode, tXf
   if sNode[pThing] is empty then exit b3kNodeSync
   put b3BodyTransform(pThing) into tXf
   if tXf is empty then exit b3kNodeSync
   repeat for each item tNode in sNode[pThing]
      r3NodeSetTransformText tNode, tXf
   end repeat
end b3kNodeSync

-- the frame's drawing: with render3dxt, show the picture begun last frame
-- and begin the next when anything changed; with box3dxt, draw now
private command b3kFrameDraw
   if sView is empty or sRenderer is "none" or sRenderer is empty then exit b3kFrameDraw
   if not b3kViewFits() then exit b3kFrameDraw
   if sRenderer is "render3dxt" then
      if sBegun is true then
         put false into sBegun
         b3kShow r3SceneFrame(sScene)
      end if
      if sStale is true then
         put false into sStale
         put (r3SceneRenderBegin(sScene, sViewW, sViewH) > 0) into sBegun
      end if
   else if sStale is true then
      put false into sStale
      b3kOwnRender
   end if
end b3kFrameDraw

-- box3dxt's renderer: one camera for the process, so it is set every time
private command b3kOwnRender
   set the itemDelimiter to comma
   b3RenderSetCamera item 1 of sCamEye, item 2 of sCamEye, item 3 of sCamEye, \
         item 1 of sCamTarget, item 2 of sCamTarget, item 3 of sCamTarget, sCamFov
   b3RenderSetBackground item 1 of sBg, item 2 of sBg, item 3 of sBg
   b3RenderSetLight item 1 of sLight, item 2 of sLight, item 3 of sLight
   if b3RenderWorld(sWorld, sViewW, sViewH, b3kNum(sMode, 0)) then
      b3kShow b3RenderPixels()
   end if
end b3kOwnRender

-- true when the view exists; a resized view is measured again and redrawn
private function b3kViewFits
   if sView is empty then return false
   if not exists(sView) then
      put empty into sView
      return false
   end if
   if the width of sView is not sViewW or the height of sView is not sViewH then
      put the width of sView into sViewW
      put the height of sView into sViewH
      put false into sBegun
      put true into sStale
      b3kCamApply
   end if
   return sViewW >= 1 and sViewH >= 1
end b3kViewFits

-- Hands a picture to the view. The engine compresses whatever is set as
-- imageData the way the paintCompression says, and a desktop engine starts
-- with "png": encoding a PNG of every frame cost more than drawing it
-- (render3dxt's demo measured 36.6 ms a frame against 6.5 with "rle" on
-- OXT-Beyond 0.2.8-dp.2). The property is global and the paint tools read
-- it, so it is changed for this one line and put back.
private command b3kShow pPicture
   local tWas
   if pPicture is empty then exit b3kShow
   if the number of bytes of pPicture is not sViewW * sViewH * 4 then exit b3kShow
   put the paintCompression into tWas
   set the paintCompression to "rle"
   set the imageData of sView to pPicture
   set the paintCompression to tWas
   add 1 to sFpsCount
   if the milliseconds - sFpsStart >= 1000 then
      put sFpsCount into sFps
      put 0 into sFpsCount
      put the milliseconds into sFpsStart
   end if
end b3kShow

-- =====================================================================
-- Colours
-- =====================================================================

-- "r,g,b" for a colour name, "r,g,b" or "#rrggbb"; pDefault when empty;
-- the next palette colour when pDefault is empty too
private function b3kRGB pColor, pDefault
   local tC
   if pColor is empty then
      if pDefault is not empty then return pDefault
      add 1 to sSpawnCount
      set the itemDelimiter to ";"
      put item ((sSpawnCount - 1) mod 8) + 1 of kB3kPalette into tC
      set the itemDelimiter to comma
      return tC
   end if
   set the itemDelimiter to comma
   if the number of items of pColor is 3 and item 1 of pColor is a number \
         and item 2 of pColor is a number and item 3 of pColor is a number then
      return max(0, min(255, round(item 1 of pColor))) & comma & \
            max(0, min(255, round(item 2 of pColor))) & comma & \
            max(0, min(255, round(item 3 of pColor)))
   end if
   if char 1 of pColor is "#" and the number of chars of pColor is 7 then
      return baseConvert(char 2 to 3 of pColor, 16, 10) & comma & \
            baseConvert(char 4 to 5 of pColor, 16, 10) & comma & \
            baseConvert(char 6 to 7 of pColor, 16, 10)
   end if
   switch toLower(word 1 to -1 of pColor)
      case "red"
         return "220,64,56"
      case "orange"
         return "240,150,50"
      case "yellow"
         return "240,210,70"
      case "green"
         return "80,170,90"
      case "lime"
         return "150,220,80"
      case "teal"
         return "50,160,160"
      case "cyan"
         return "80,200,220"
      case "blue"
         return "60,120,220"
      case "navy"
         return "40,60,130"
      case "purple"
         return "150,90,200"
      case "pink"
         return "240,130,180"
      case "brown"
         return "140,96,60"
      case "white"
         return "240,240,240"
      case "gray"
      case "grey"
         return "140,146,156"
      case "black"
         return "30,30,34"
      case "gold"
         return "230,180,40"
      case "silver"
         return "190,196,206"
   end switch
   if pDefault is not empty then return pDefault
   return "200,200,200"
end b3kRGB

-- =====================================================================
-- The camera
-- =====================================================================
-- One camera, kept as a TARGET it looks at, an ORBIT round it (yaw and
-- pitch in degrees, a distance in metres) and a lens (the vertical field
-- of view). The eye is worked out from those, so orbiting, zooming and
-- following are all one model. Both renderers take the camera as seven
-- numbers "ex,ey,ez,tx,ty,tz,fov", y up, and the Kit works out the same
-- projection in script (b3kProject, b3kThingAt), so picking needs no
-- picture and works with either renderer or none.

-- the camera's starting place: above and in front of the origin
private command b3kCamReset
   put "0,0,0" into sCamTarget
   put 30 into sCamYaw
   put 25 into sCamPitch
   put 16 into sCamDist
   put 50 into sCamFov
   put empty into sCamFollow
   put 0.15 into sCamLerp
   put 0.8 into sCamHeight
   put 0 into sShakeAmp
   put 0 into sShakeUntil
   put empty into sCamLast
   if sBg is empty then put "26,30,44" into sBg
   if sAmbient is empty then put "70,74,90" into sAmbient
   if sLight is empty then put "-0.45,-1,-0.35" into sLight
   if sSmooth is empty then put 2 into sSmooth
   if sMode is empty then put 0 into sMode
   b3kCamApply
end b3kCamReset

-- works out the eye and the view's axes, hands the camera to render3dxt,
-- and marks the picture stale when anything changed
private command b3kCamApply
   local tYaw, tPitch, tCp, tEx, tEy, tEz, tFx, tFy, tFz, tLen
   local tUx, tUy, tUz, tRx, tRy, tRz, tCam
   if sCamYaw is empty then exit b3kCamApply
   set the itemDelimiter to comma
   put sCamYaw * pi / 180 into tYaw
   put sCamPitch * pi / 180 into tPitch
   put cos(tPitch) into tCp
   put item 1 of sCamTarget + sCamDist * tCp * sin(tYaw) into tEx
   put item 2 of sCamTarget + sCamDist * sin(tPitch) into tEy
   put item 3 of sCamTarget + sCamDist * tCp * cos(tYaw) into tEz
   if sShakeAmp > 0 and the milliseconds < sShakeUntil then
      add sShakeAmp * (random(2001) - 1001) / 1000 to tEx
      add sShakeAmp * (random(2001) - 1001) / 1000 to tEy
      add sShakeAmp * (random(2001) - 1001) / 1000 to tEz
   end if
   put tEx & comma & tEy & comma & tEz into sCamEye
   -- forward, right = forward x up, up = right x forward; looking straight
   -- up or down, world -z stands in for up (the renderers' own rule)
   put item 1 of sCamTarget - tEx into tFx
   put item 2 of sCamTarget - tEy into tFy
   put item 3 of sCamTarget - tEz into tFz
   put sqrt(tFx * tFx + tFy * tFy + tFz * tFz) into tLen
   if tLen <= 0 then exit b3kCamApply
   divide tFx by tLen
   divide tFy by tLen
   divide tFz by tLen
   put 0 into tUx
   put 1 into tUy
   put 0 into tUz
   if abs(tFy) > 0.999 then
      put 0 into tUy
      put -1 into tUz
   end if
   put tFy * tUz - tFz * tUy into tRx
   put tFz * tUx - tFx * tUz into tRy
   put tFx * tUy - tFy * tUx into tRz
   put sqrt(tRx * tRx + tRy * tRy + tRz * tRz) into tLen
   divide tRx by tLen
   divide tRy by tLen
   divide tRz by tLen
   put tFx & comma & tFy & comma & tFz into sCamF
   put tRx & comma & tRy & comma & tRz into sCamR
   put (tRy * tFz - tRz * tFy) & comma & (tRz * tFx - tRx * tFz) & comma & (tRx * tFy - tRy * tFx) into sCamU
   put sCamEye & comma & sCamTarget & comma & sCamFov into tCam
   if tCam is sCamLast then exit b3kCamApply
   put tCam into sCamLast
   if sRenderer is "render3dxt" and sScene is not empty then
      r3SceneSetCamera sScene, tEx, tEy, tEz, item 1 of sCamTarget, item 2 of sCamTarget, item 3 of sCamTarget, sCamFov
   end if
   put true into sStale
end b3kCamApply

/**
Summary: Put the camera on an orbit round a point.

pYaw: Degrees round the vertical; 0 looks along -z from the +z side.

pPitch: Degrees above the horizon, -89 to 89.

pDistance: Metres from the point.

pTx: The x of the point it looks at; empty keeps the current one.

pTy: Its y.

pTz: Its z.

Example:
b3kCamOrbit 45, 30, 20, 0, 0, 0

References: b3kCamOrbitBy (handler), b3kCamLookAt (handler), b3kCamFollow (handler)
*/
command b3kCamOrbit pYaw, pPitch, pDistance, pTx, pTy, pTz
   put b3kNum(pYaw, sCamYaw) into sCamYaw
   put max(-89, min(89, b3kNum(pPitch, sCamPitch))) into sCamPitch
   put max(0.1, b3kNum(pDistance, sCamDist)) into sCamDist
   if pTx is a number and pTy is a number and pTz is a number then
      put pTx & comma & pTy & comma & pTz into sCamTarget
   end if
   b3kCamApply
end b3kCamOrbit

/**
Summary: Turn the camera round its point.

pDYaw: Degrees to add to the yaw.

pDPitch: Degrees to add to the pitch (kept within -89 to 89).

Example:
b3kCamOrbitBy 2, 0   -- a slow turn, once a frame

References: b3kCamOrbit (handler), b3kCamMouseOrbit (handler)
*/
command b3kCamOrbitBy pDYaw, pDPitch
   b3kCamOrbit sCamYaw + b3kNum(pDYaw, 0), sCamPitch + b3kNum(pDPitch, 0), sCamDist
end b3kCamOrbitBy

/**
Summary: Place the camera by an eye and a target.

pEx: The x of the eye.

pEy: The y of the eye.

pEz: The z of the eye.

pTx: The x of the point it looks at.

pTy: Its y.

pTz: Its z.

pFov: The vertical field of view in degrees; empty keeps the current one (the Kit starts at 50).

Example:
b3kCamLookAt 0, 12, 18, 0, 0, 0

Description:
The Kit turns it into an orbit round the target, so <b3kCamOrbitBy> and
<b3kCamZoomBy> carry on from here.

References: b3kCamOrbit (handler), b3kCamSetFov (handler)
*/
command b3kCamLookAt pEx, pEy, pEz, pTx, pTy, pTz, pFov
   local tDx, tDy, tDz, tDist
   put b3kNum(pEx, 0) - b3kNum(pTx, 0) into tDx
   put b3kNum(pEy, 0) - b3kNum(pTy, 0) into tDy
   put b3kNum(pEz, 0) - b3kNum(pTz, 0) into tDz
   put sqrt(tDx * tDx + tDy * tDy + tDz * tDz) into tDist
   if tDist < 0.001 then exit b3kCamLookAt
   put b3kNum(pTx, 0) & comma & b3kNum(pTy, 0) & comma & b3kNum(pTz, 0) into sCamTarget
   put tDist into sCamDist
   put max(-89, min(89, asin(tDy / tDist) * 180 / pi)) into sCamPitch
   put atan2(tDx, tDz) * 180 / pi into sCamYaw
   if pFov is a number then put max(5, min(150, pFov)) into sCamFov
   b3kCamApply
end b3kCamLookAt

/**
Summary: Set how far the camera stands from its point.

pDistance: Metres, 0.1 or more.

Example:
b3kCamZoom 8

References: b3kCamZoomBy (handler)
*/
command b3kCamZoom pDistance
   b3kCamOrbit sCamYaw, sCamPitch, b3kNum(pDistance, sCamDist)
end b3kCamZoom

/**
Summary: Move the camera nearer or farther by a factor.

pFactor: Below 1 comes nearer, above 1 goes farther.

Example:
b3kCamZoomBy 0.9

References: b3kCamZoom (handler)
*/
command b3kCamZoomBy pFactor
   b3kCamOrbit sCamYaw, sCamPitch, sCamDist * max(0.01, b3kNum(pFactor, 1))
end b3kCamZoomBy

/**
Summary: Set the camera's vertical field of view.

pDegrees: 5 to 150; 50 is a natural lens, small is a telephoto.

Example:
b3kCamSetFov 70

References: b3kCamLookAt (handler)
*/
command b3kCamSetFov pDegrees
   put max(5, min(150, b3kNum(pDegrees, 50))) into sCamFov
   b3kCamApply
end b3kCamSetFov

/**
Summary: Keep the camera on a thing as it moves.

pThing: The thing to follow.

pLerp: How quickly it catches up each frame, 0.01 to 1; empty means 0.15.

pHeight: Metres above the thing's centre to look at; empty means 0.8.

Example:
b3kPlayerMake 0, 1, 0
b3kCamFollow b3kPlayer()

Description:
The orbit (yaw, pitch, distance) stays yours: turn it with
<b3kCamOrbitBy>, the mouse (<b3kCamMouseOrbit>) or the "turn" axis.

References: b3kCamUnfollow (handler), b3kCamOrbit (handler)
*/
command b3kCamFollow pThing, pLerp, pHeight
   if sKind[pThing] is empty then exit b3kCamFollow
   put pThing into sCamFollow
   put max(0.01, min(1, b3kNum(pLerp, 0.15))) into sCamLerp
   put b3kNum(pHeight, 0.8) into sCamHeight
end b3kCamFollow

/**
Summary: Stop following.

Example:
b3kCamUnfollow

References: b3kCamFollow (handler)
*/
command b3kCamUnfollow
   put empty into sCamFollow
end b3kCamUnfollow

/**
Summary: Shake the camera for a moment.

pAmount: How far the eye jumps, in metres; 0.2 is a thump.

pMilliseconds: How long it lasts.

Example:
b3kCamShake 0.3, 250

References: b3kExplode (handler)
*/
command b3kCamShake pAmount, pMilliseconds
   put max(0, b3kNum(pAmount, 0.2)) into sShakeAmp
   put the milliseconds + max(0, b3kNum(pMilliseconds, 250)) into sShakeUntil
end b3kCamShake

/**
Summary: Let a drag on the view turn the camera.

pFlag: true to turn it on, false to turn it off.

Example:
b3kCamMouseOrbit true

Description:
While the mouse button is held after a press on the view, moving the
mouse sideways turns the camera round its point and up and down tilts
it. A click that did not move is still yours: in mouseUp, ask
<b3kCamDragged> whether the press was a drag before treating it as a click.

References: b3kCamDragged (handler), b3kCamOrbitBy (handler)
*/
command b3kCamMouseOrbit pFlag
   put (pFlag is true) into sCamMouse
end b3kCamMouseOrbit

/**
Summary: Report whether the last press on the view dragged the camera.

Returns: true when the mouse moved more than 4 pixels while held.

Example:
-- first thing in the view's mouseUp handler:
if b3kCamDragged() then exit mouseUp

References: b3kCamMouseOrbit (handler)
*/
function b3kCamDragged
   return b3kNum(sDragMoved, 0) > 4
end b3kCamDragged

-- once a frame: follow, the keyboard's turn, the mouse's drag, the shake
private command b3kCamTick
   local tPos, tK, tLoc, tDx, tDy, tTurn
   set the itemDelimiter to comma
   if sCamFollow is not empty then
      put b3BodyPosition(sCamFollow) into tPos
      if tPos is empty then
         put empty into sCamFollow
      else
         put 1 - (1 - sCamLerp) ^ (b3kNum(sFrameMS, kB3kStepMs) / kB3kStepMs) into tK
         put (item 1 of sCamTarget + (item 1 of tPos - item 1 of sCamTarget) * tK) & comma & \
               (item 2 of sCamTarget + (item 2 of tPos + sCamHeight - item 2 of sCamTarget) * tK) & comma & \
               (item 3 of sCamTarget + (item 3 of tPos - item 3 of sCamTarget) * tK) into sCamTarget
      end if
   end if
   if sInputOn is true and sAxisNegC["turn"] is not empty then
      put b3kAxis("turn") into tTurn
      if tTurn is not 0 then
         -- +1 (e) turns the view right: the yaw goes down (a higher yaw
         -- carries the eye round toward +x, turning the view left)
         subtract tTurn * 120 * b3kNum(sFrameMS, kB3kStepMs) / 1000 from sCamYaw
      end if
   end if
   if sCamMouse is true and sView is not empty then
      if the mouse is "down" then
         put the mouseLoc into tLoc
         if sDragOn is not true then
            if tLoc is within the rect of sView then
               put true into sDragOn
               put tLoc into sDragLoc
               put 0 into sDragMoved
            end if
         else
            put item 1 of tLoc - item 1 of sDragLoc into tDx
            put item 2 of tLoc - item 2 of sDragLoc into tDy
            add abs(tDx) + abs(tDy) to sDragMoved
            if sDragMoved > 4 then
               subtract tDx * 0.4 from sCamYaw
               put max(-89, min(89, sCamPitch + tDy * 0.3)) into sCamPitch
            end if
            put tLoc into sDragLoc
         end if
      else
         put false into sDragOn
      end if
   end if
   b3kCamApply
end b3kCamTick

/**
Summary: Where the camera's eye is.

Returns: "x,y,z" in metres.

Example:
put b3kCamEye() into tEye

References: b3kCamTarget (handler), b3kCamText (handler)
*/
function b3kCamEye
   return sCamEye
end b3kCamEye

/**
Summary: The point the camera looks at.

Returns: "x,y,z" in metres.

Example:
put b3kCamTarget() into tAim

References: b3kCamEye (handler)
*/
function b3kCamTarget
   return sCamTarget
end b3kCamTarget

/**
Summary: The camera's yaw round its point.

Returns: Degrees.

Example:
put b3kCamYaw() into tHeading

References: b3kCamOrbit (handler)
*/
function b3kCamYaw
   return sCamYaw
end b3kCamYaw

/**
Summary: The camera's pitch above the horizon.

Returns: Degrees, -89 to 89.

Example:
put b3kCamPitch() into tTilt

References: b3kCamOrbit (handler)
*/
function b3kCamPitch
   return sCamPitch
end b3kCamPitch

/**
Summary: How far the camera stands from its point.

Returns: Metres.

Example:
put b3kCamDistance() into tZoom

References: b3kCamZoom (handler)
*/
function b3kCamDistance
   return sCamDist
end b3kCamDistance

/**
Summary: The camera as the seven numbers both renderers take.

Returns: "ex,ey,ez,tx,ty,tz,fov".

Example:
r3SceneSetCameraText tMyOtherScene, b3kCamText()

References: b3kCamEye (handler)
*/
function b3kCamText
   return sCamEye & comma & sCamTarget & comma & sCamFov
end b3kCamText

-- =====================================================================
-- Picking: from the view to the world and back
-- =====================================================================

/**
Summary: Where a point of the world appears on the card.

pX: The x of the point, in metres.

pY: Its y.

pZ: Its z.

Returns: "h,v" card coordinates (they may lie off the view), or empty when the point is behind the camera or there is no view.

Example:
set the loc of field "Label" to b3kProject(b3kX(tCrate), b3kY(tCrate) + 1, b3kZ(tCrate))

References: b3kThingAt (handler), b3kGroundPoint (handler)
*/
function b3kProject pX, pY, pZ
   local tDx, tDy, tDz, tVx, tVy, tVz, tScale
   if b3kView() is empty then return empty
   b3kCamApply
   set the itemDelimiter to comma
   put b3kNum(pX, 0) - item 1 of sCamEye into tDx
   put b3kNum(pY, 0) - item 2 of sCamEye into tDy
   put b3kNum(pZ, 0) - item 3 of sCamEye into tDz
   put tDx * item 1 of sCamR + tDy * item 2 of sCamR + tDz * item 3 of sCamR into tVx
   put tDx * item 1 of sCamU + tDy * item 2 of sCamU + tDz * item 3 of sCamU into tVy
   put tDx * item 1 of sCamF + tDy * item 2 of sCamF + tDz * item 3 of sCamF into tVz
   if tVz < 0.05 then return empty
   put 0.5 * sViewH / tan(0.5 * sCamFov * pi / 180) into tScale
   return round(the left of sView + 0.5 * sViewW + tVx * tScale / tVz) & comma & \
         round(the top of sView + 0.5 * sViewH - tVy * tScale / tVz)
end b3kProject

-- the camera's ray through a card point: "ox,oy,oz,dx,dy,dz", d of length 1
private function b3kCamRay pH, pV
   local tPx, tPy, tScale, tVx, tVy, tDx, tDy, tDz, tLen
   if b3kView() is empty then return empty
   b3kCamApply
   set the itemDelimiter to comma
   put b3kNum(pH, 0) - the left of sView into tPx
   put b3kNum(pV, 0) - the top of sView into tPy
   put 0.5 * sViewH / tan(0.5 * sCamFov * pi / 180) into tScale
   put (tPx - 0.5 * sViewW) / tScale into tVx
   put -(tPy - 0.5 * sViewH) / tScale into tVy
   put item 1 of sCamF + item 1 of sCamR * tVx + item 1 of sCamU * tVy into tDx
   put item 2 of sCamF + item 2 of sCamR * tVx + item 2 of sCamU * tVy into tDy
   put item 3 of sCamF + item 3 of sCamR * tVx + item 3 of sCamU * tVy into tDz
   put sqrt(tDx * tDx + tDy * tDy + tDz * tDz) into tLen
   return sCamEye & comma & (tDx / tLen) & comma & (tDy / tLen) & comma & (tDz / tLen)
end b3kCamRay

/**
Summary: The thing under a point of the card.

pH: The horizontal card coordinate, such as the mouseH.

pV: The vertical card coordinate, such as the mouseV.

Returns: The thing, or empty when the ray from the camera through that point meets nothing within 500 metres.

Example:
-- in the view's mouseUp handler:
get b3kThingAt(the mouseH, the mouseV)
if it is not empty then b3kPush it, 0, 5, 0

Description:
A ray is cast through the world, so it needs no picture and works with
either renderer. Where it struck is <b3kHitPoint>; the ground counts as
a thing. Sensors are not seen.

References: b3kPointAt (handler), b3kRayHit (handler), b3kHitPoint (handler)
*/
function b3kThingAt pH, pV
   local tRay
   put b3kCamRay(pH, pV) into tRay
   if tRay is empty then return empty
   set the itemDelimiter to comma
   return b3kRayHit(item 1 of tRay, item 2 of tRay, item 3 of tRay, \
         item 4 of tRay * 500, item 5 of tRay * 500, item 6 of tRay * 500)
end b3kThingAt

/**
Summary: The point of the world under a point of the card.

pH: The horizontal card coordinate.

pV: The vertical card coordinate.

Returns: "x,y,z" where the camera's ray first meets something, or empty.

Example:
put b3kPointAt(the mouseH, the mouseV) into tWhere
if tWhere is not empty then b3kSpawnBall item 1 of tWhere, 5, item 3 of tWhere, 0.6

References: b3kThingAt (handler), b3kGroundPoint (handler)
*/
function b3kPointAt pH, pV
   get b3kThingAt(pH, pV)
   if sHitThing is empty then return empty
   return sHitPoint
end b3kPointAt

/**
Summary: Where the camera's ray through a card point meets a flat level.

pH: The horizontal card coordinate.

pV: The vertical card coordinate.

pY: The height of the level in metres; empty means 0.

Returns: "x,y,z", or empty when the ray runs parallel to the level or away from it.

Example:
put b3kGroundPoint(the mouseH, the mouseV) into tAim

Description:
Needs no body there: for aiming, placing things in an editor, or
click-to-move over open ground.

References: b3kPointAt (handler)
*/
function b3kGroundPoint pH, pV, pY
   local tRay, tLevel, tT
   put b3kCamRay(pH, pV) into tRay
   if tRay is empty then return empty
   set the itemDelimiter to comma
   put b3kNum(pY, 0) into tLevel
   if abs(item 5 of tRay) < 0.000001 then return empty
   put (tLevel - item 2 of tRay) / item 5 of tRay into tT
   if tT <= 0 then return empty
   return (item 1 of tRay + item 4 of tRay * tT) & comma & tLevel & comma & (item 3 of tRay + item 6 of tRay * tT)
end b3kGroundPoint

/**
Summary: Cast a ray and report the first thing it meets.

pOx: The x of the start, in metres.

pOy: Its y.

pOz: Its z.

pDx: The x of the travel: how far and which way, not just a direction.

pDy: Its y.

pDz: Its z.

Returns: The thing, or empty. <b3kHitPoint>, <b3kHitNormal> and <b3kHitDistance> say more.

Example:
-- is there ground within 2 m under the crate?
put b3kRayHit(b3kX(tCrate), b3kY(tCrate), b3kZ(tCrate), 0, -2, 0) into tBelow

Description:
A body the Kit did not make is reported as its body handle.

References: b3kThingAt (handler), b3kHitPoint (handler)
*/
function b3kRayHit pOx, pOy, pOz, pDx, pDy, pDz
   local tLen
   put empty into sHitThing
   put empty into sHitPoint
   put empty into sHitNormal
   put empty into sHitDist
   if sWorld is empty then return empty
   put b3kNum(pDx, 0) into pDx
   put b3kNum(pDy, 0) into pDy
   put b3kNum(pDz, 0) into pDz
   put sqrt(pDx * pDx + pDy * pDy + pDz * pDz) into tLen
   if tLen <= 0 then return empty
   if b3CastRayClosest(sWorld, b3kNum(pOx, 0), b3kNum(pOy, 0), b3kNum(pOz, 0), pDx, pDy, pDz) < 1 then
      return empty
   end if
   put b3HitBody(1) into sHitThing
   put b3HitPoint(1) into sHitPoint
   put b3HitNormal(1) into sHitNormal
   put b3HitFraction(1) * tLen into sHitDist
   return sHitThing
end b3kRayHit

/**
Summary: Where the last ray or pick struck.

Returns: "x,y,z", or empty when it struck nothing.

Example:
get b3kThingAt(the mouseH, the mouseV)
put b3kHitPoint() into tWhere

References: b3kRayHit (handler), b3kHitNormal (handler)
*/
function b3kHitPoint
   return sHitPoint
end b3kHitPoint

/**
Summary: Which way the surface faced where the last ray struck.

Returns: "x,y,z" of length 1, or empty.

Example:
if item 2 of b3kHitNormal() > 0.7 then put "floor" into tSurface

References: b3kRayHit (handler)
*/
function b3kHitNormal
   return sHitNormal
end b3kHitNormal

/**
Summary: How far the last ray travelled before it struck.

Returns: Metres, or empty.

Example:
if b3kHitDistance() < 1 then put "close" into tWarn

References: b3kRayHit (handler)
*/
function b3kHitDistance
   return sHitDist
end b3kHitDistance

/**
Summary: The things inside a sphere.

pX: The x of the centre.

pY: Its y.

pZ: Its z.

pRadius: The radius in metres.

Returns: One thing a line (each once), or empty.

Example:
put b3kOverlapSphere(0, 1, 0, 3) into tNear
if tNear is not empty then b3kPush line 1 of tNear, 0, 4, 0

Description:
Sensors and sleeping things are included.

References: b3kExplode (handler)
*/
function b3kOverlapSphere pX, pY, pZ, pRadius
   local tCount, i, tBody, tSeen, tOut
   if sWorld is empty then return empty
   put b3OverlapSphere(sWorld, b3kNum(pX, 0), b3kNum(pY, 0), b3kNum(pZ, 0), max(0.001, b3kNum(pRadius, 1))) into tCount
   put empty into tOut
   repeat with i = 1 to tCount
      put b3ShapeBody(b3ListItem(i)) into tBody
      if tBody > 0 and tSeen[tBody] is empty and tBody is not sAnchor then
         put true into tSeen[tBody]
         put tBody & return after tOut
      end if
   end repeat
   return char 1 to -2 of tOut
end b3kOverlapSphere

-- =====================================================================
-- Things: a body, one shape, and its picture
-- =====================================================================
-- A thing IS its body's handle. The Kit remembers its kind (what you
-- asked for: "box", "ground", "sensor"...), its geometry (what to draw:
-- box, ball, capsule, cylinder, the shape's own triangles, or a model)
-- with its sizes, and its look, so its picture can be made again when the
-- renderer changes. Every shape reports touches and is seen by sensors.

-- a new body, or empty (with the reason in sLastError)
private function b3kBodyNew pType, pX, pY, pZ
   local tBody
   if sWorld is empty then
      put "there is no world: call b3kSetup first" into sLastError
      return empty
   end if
   put b3BodyCreate(sWorld, pType, b3kNum(pX, 0), b3kNum(pY, 0), b3kNum(pZ, 0)) into tBody
   if tBody is not a number or tBody <= 0 then
      put "box3dxt made no body: " & b3LastError() into sLastError
      return empty
   end if
   return tBody
end b3kBodyNew

-- the options every Kit shape is made with: touches reported, seen by
-- sensors (a sensor reports nothing about a shape without sensor events)
private command b3kShapeOptions pSensor
   b3ShapeOptionsReset
   b3ShapeOptionsSetEvents true, false, true
   if pSensor is true then b3ShapeOptionsSetSensor true
end b3kShapeOptions

-- records a new thing and makes its picture; false (and the body gone)
-- when the shape was refused
private function b3kThingAdd pBody, pShape, pKind, pGeo, pDims, pColor
   local tRGB
   b3ShapeOptionsReset
   if pShape is not a number or pShape <= 0 then
      put "box3dxt refused the shape: " & b3LastError() into sLastError
      b3BodyDestroy pBody
      return false
   end if
   put pKind into sKind[pBody]
   add 1 to sBornCount
   put sBornCount into sBorn[pBody]
   put pGeo into sGeo[pBody]
   put pShape into sShape[pBody]
   put pDims into sDims[pBody]
   put b3kRGB(pColor, empty) into tRGB
   put tRGB into sColor[pBody]
   put true into sVisible[pBody]
   if sHasOwn is true then
      set the itemDelimiter to comma
      b3ShapeSetColor pShape, item 1 of tRGB, item 2 of tRGB, item 3 of tRGB
   end if
   put empty into sLastError
   put true into sStale
   return true
end b3kThingAdd

-- the picture of a thing, when render3dxt draws
private command b3kVisualMake pThing
   local tD, tKey, tMesh, tNode, tScale
   if sRenderer is not "render3dxt" or sScene is empty then exit b3kVisualMake
   if sNode[pThing] is not empty then exit b3kVisualMake
   set the itemDelimiter to comma
   put sDims[pThing] into tD
   put empty into tMesh
   -- a look (b3kSetLook) is drawn instead of the shape: one mesh for every
   -- thing that wears the same model, kept with the shapes' meshes
   if sLookKey[pThing] is not empty then
      put sLookKey[pThing] into tKey
      if sMeshes[tKey] is empty then
         if sLook[pThing] contains return then
            put r3MeshParseObj(sLook[pThing], sLookMtl[pThing]) into tMesh
         else
            put r3MeshLoadObj(sLook[pThing]) into tMesh
         end if
         if tMesh is a number and tMesh > 0 then put tMesh into sMeshes[tKey]
      end if
      put sMeshes[tKey] into tMesh
      if tMesh is a number and tMesh > 0 then
         put b3kNum(sLookScale[pThing], 1) into tScale
         put "look" into tD
      end if
   end if
   if tD is not "look" then
      switch sGeo[pThing]
         case "box"
            put "box:" & tD into tKey
            if sMeshes[tKey] is empty then put r3MeshBox(item 1 of tD, item 2 of tD, item 3 of tD) into sMeshes[tKey]
            put sMeshes[tKey] into tMesh
            break
         case "ball"
            put "ball:" & tD into tKey
            if sMeshes[tKey] is empty then put r3MeshSphere(item 1 of tD, 24, 12) into sMeshes[tKey]
            put sMeshes[tKey] into tMesh
            break
         case "capsule"
            put "capsule:" & tD into tKey
            if sMeshes[tKey] is empty then put r3MeshCapsule(item 1 of tD, item 2 of tD, 20, 6) into sMeshes[tKey]
            put sMeshes[tKey] into tMesh
            break
         case "cylinder"
            put "cylinder:" & tD into tKey
            if sMeshes[tKey] is empty then put r3MeshCylinder(item 1 of tD, item 2 of tD, 24) into sMeshes[tKey]
            put sMeshes[tKey] into tMesh
            break
         case "model"
            if sModelPath[pThing] is not empty then
               put r3MeshLoadObj(sModelPath[pThing]) into tMesh
            else
               put r3MeshParseObj(sModel[pThing], empty) into tMesh
            end if
            if tMesh is a number and tMesh > 0 then
               put tMesh into sOwnMesh[pThing]
               put b3kNum(sScale[pThing], 1) into tScale
            else
               put empty into tMesh
            end if
            break
      end switch
   end if
   -- a hull, a cone, a mesh, or a model that would not load: exactly the
   -- triangles box3dxt collides with
   if tMesh is not a number or tMesh <= 0 then
      put r3MeshFromTrianglesText(b3ShapeTrianglesText(sShape[pThing])) into tMesh
      if tMesh is not a number or tMesh <= 0 then exit b3kVisualMake
      put tMesh into sOwnMesh[pThing]
      put empty into tScale
   end if
   put r3NodeCreate(sScene, tMesh) into tNode
   if tNode is not a number or tNode <= 0 then exit b3kVisualMake
   put tNode into sNode[pThing]
   if tScale is a number and tScale is not 1 then r3NodeSetScale tNode, tScale, tScale, tScale
   r3NodeSetTransformText tNode, b3BodyTransform(pThing)
   r3NodeSetTag tNode, pThing
   b3kVisualLook pThing
   if sVisible[pThing] is false or b3BodyIsEnabled(pThing) is false then r3NodeSetVisible tNode, false
end b3kVisualMake

-- the node's material: a checker, a picture file, the model's own, or a
-- plain colour. A thing's old checker or texture material is freed first.
private command b3kVisualLook pThing
   local tMat, tHandle, tA, tB, tCells, tTex, tSize
   if sNode[pThing] is empty then exit b3kVisualLook
   repeat for each item tHandle in sOwnMat[pThing]
      r3MaterialDestroy tHandle
   end repeat
   repeat for each item tHandle in sOwnTex[pThing]
      r3TextureDestroy tHandle
   end repeat
   put empty into sOwnMat[pThing]
   put empty into sOwnTex[pThing]
   put empty into tMat
   -- a look (b3kSetLook) wears the model's own materials
   if sLookKey[pThing] is not empty then
      put true into sStale
      exit b3kVisualLook
   end if
   if sChecker[pThing] is not empty then
      set the itemDelimiter to ";"
      put item 1 of sChecker[pThing] into tA
      put item 2 of sChecker[pThing] into tB
      put item 3 of sChecker[pThing] into tCells
      set the itemDelimiter to comma
      put max(2, min(1024, tCells * 16)) into tSize
      put r3TextureChecker(tSize, tCells, item 1 of tA, item 2 of tA, item 3 of tA, item 1 of tB, item 2 of tB, item 3 of tB) into tTex
   else if sTexPath[pThing] is not empty then
      put r3TextureLoad(sTexPath[pThing]) into tTex
   end if
   if tTex is a number and tTex > 0 then
      if sChecker[pThing] is not empty then r3TextureSetSmooth tTex, false
      r3TextureSetRepeat tTex, true
      put tTex into sOwnTex[pThing]
      -- tMat was emptied above and r3MaterialSetTexture takes an Integer:
      -- a material that could not be made is never handed on (engine note 6.4)
      put r3MaterialCreate(255, 255, 255) into tMat
      if tMat is a number and tMat > 0 then
         r3MaterialSetTexture tMat, tTex
         put tMat into sOwnMat[pThing]
         if sGlow[pThing] is not empty then
            set the itemDelimiter to comma
            r3MaterialSetEmissive tMat, item 1 of sGlow[pThing], item 2 of sGlow[pThing], item 3 of sGlow[pThing]
         end if
      end if
   else if sOwnLook[pThing] is not true then
      put b3kColorMat(sColor[pThing], sGlow[pThing]) into tMat
   end if
   if tMat is a number and tMat > 0 then
      repeat for each item tHandle in sNode[pThing]
         r3NodeSetMaterial tHandle, tMat
      end repeat
   end if
   put true into sStale
end b3kVisualLook

-- one shared render3dxt material for each plain colour, and for each
-- colour and glow together ("r,g,b/r,g,b")
private function b3kColorMat pRGB, pGlow
   local tKey
   put pRGB into tKey
   if pGlow is not empty then put pRGB & "/" & pGlow into tKey
   if sMats[tKey] is empty then
      set the itemDelimiter to comma
      put r3MaterialCreate(item 1 of pRGB, item 2 of pRGB, item 3 of pRGB) into sMats[tKey]
      r3MaterialSetSpecular sMats[tKey], 0.25, 24
      if pGlow is not empty then
         r3MaterialSetEmissive sMats[tKey], item 1 of pGlow, item 2 of pGlow, item 3 of pGlow
      end if
   end if
   return sMats[tKey]
end b3kColorMat

/**
Summary: Make a box that falls and tumbles.

pX: The x of its centre, in metres.

pY: The y of its centre; y points up.

pZ: The z of its centre.

pW: Its width (along x) in metres; empty means 1.

pH: Its height (along y); empty means 1.

pD: Its depth (along z); empty means 1.

pColor: A colour name, "r,g,b" or "#rrggbb"; empty takes the next colour of the Kit's palette.

Returns: (through the result) the thing, or empty if it was refused (see <b3kLastError>).

Example:
b3kSpawnBox 0, 5, 0, 1, 1, 1, "orange"
put the result into tCrate

References: b3kSpawnBall (handler), b3kAddStaticBox (handler), b3kRemove (handler)
*/
command b3kSpawnBox pX, pY, pZ, pW, pH, pD, pColor
   local tBody, tHx, tHy, tHz
   put max(0.005, b3kNum(pW, 1)) / 2 into tHx
   put max(0.005, b3kNum(pH, 1)) / 2 into tHy
   put max(0.005, b3kNum(pD, 1)) / 2 into tHz
   put b3kBodyNew(2, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddBox(tBody, tHx, tHy, tHz, 1, 0.6, 0.1), "box", "box", tHx & comma & tHy & comma & tHz, pColor) then return empty
   b3kVisualMake tBody
   return tBody
end b3kSpawnBox

/**
Summary: Make a ball that falls and rolls.

pX: The x of its centre, in metres.

pY: The y of its centre.

pZ: The z of its centre.

pDiameter: Its diameter in metres; empty means 1.

pColor: A colour; empty takes the next palette colour.

Returns: (through the result) the thing, or empty if it was refused.

Example:
b3kSpawnBall 0, 6, 0, 0.8, "red"

References: b3kSpawnBox (handler)
*/
command b3kSpawnBall pX, pY, pZ, pDiameter, pColor
   local tBody, tR
   put max(0.005, b3kNum(pDiameter, 1)) / 2 into tR
   put b3kBodyNew(2, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddSphere(tBody, 0, 0, 0, tR, 1, 0.6, 0.25), "ball", "ball", tR, pColor) then return empty
   b3kVisualMake tBody
   return tBody
end b3kSpawnBall

/**
Summary: Make a capsule (a pill) standing along y.

pX: The x of its centre.

pY: The y of its centre.

pZ: The z of its centre.

pLength: Its whole length, end to end; empty means 1.6.

pDiameter: Its diameter; empty means 0.6.

pColor: A colour; empty takes the next palette colour.

Returns: (through the result) the thing, or empty if it was refused.

Example:
b3kSpawnCapsule 2, 3, 0, 1.8, 0.7

References: b3kPlayerMake (handler)
*/
command b3kSpawnCapsule pX, pY, pZ, pLength, pDiameter, pColor
   local tBody, tR, tHh
   put max(0.005, b3kNum(pDiameter, 0.6)) / 2 into tR
   put max(0.001, (b3kNum(pLength, 1.6) - 2 * tR) / 2) into tHh
   put b3kBodyNew(2, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddCapsule(tBody, 0, -tHh, 0, 0, tHh, 0, tR, 1, 0.6, 0.1), "capsule", "capsule", tR & comma & tHh, pColor) then return empty
   b3kVisualMake tBody
   return tBody
end b3kSpawnCapsule

/**
Summary: Make a cylinder standing along y.

pX: The x of its centre.

pY: The y of its centre.

pZ: The z of its centre.

pHeight: Its height; empty means 1.

pDiameter: Its diameter; empty means 1.

pColor: A colour; empty takes the next palette colour.

Returns: (through the result) the thing, or empty if it was refused.

Example:
b3kSpawnCylinder 0, 4, 0, 0.4, 1.2, "gold"   -- a coin

Description:
Box3D builds it as a 16-sided solid; render3dxt draws it round.

References: b3kSpawnCone (handler)
*/
command b3kSpawnCylinder pX, pY, pZ, pHeight, pDiameter, pColor
   local tBody, tR, tH
   put max(0.005, b3kNum(pDiameter, 1)) / 2 into tR
   put max(0.005, b3kNum(pHeight, 1)) into tH
   put b3kBodyNew(2, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddCylinder(tBody, tH, tR, 16, 1, 0.6, 0.1), "cylinder", "cylinder", tR & comma & tH / 2, pColor) then return empty
   b3kVisualMake tBody
   return tBody
end b3kSpawnCylinder

/**
Summary: Make a cone standing on its base along y.

pX: The x of its centre.

pY: The y of its centre.

pZ: The z of its centre.

pHeight: Its height; empty means 1.

pDiameter: The diameter of its base; empty means 1.

pColor: A colour; empty takes the next palette colour.

Returns: (through the result) the thing, or empty if it was refused.

Example:
b3kSpawnCone 0, 2, 0, 1.5, 1, "orange"   -- a traffic cone

References: b3kSpawnCylinder (handler)
*/
command b3kSpawnCone pX, pY, pZ, pHeight, pDiameter, pColor
   local tBody, tR, tH
   put max(0.005, b3kNum(pDiameter, 1)) / 2 into tR
   put max(0.005, b3kNum(pHeight, 1)) into tH
   put b3kBodyNew(2, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddCone(tBody, tH, tR, max(0.001, tR * 0.02), 16, 1, 0.6, 0.1), "cone", "tris", empty, pColor) then return empty
   b3kVisualMake tBody
   return tBody
end b3kSpawnCone

-- adds every point of a list to box3dxt's geometry: lines of "x,y,z", or
-- one long comma list read three numbers at a time; pScale multiplies
private function b3kPointsAdd pPoints, pScale
   local tFlat, tCount, i
   put pPoints into tFlat
   replace return with comma in tFlat
   replace ";" with comma in tFlat
   replace space with empty in tFlat
   set the itemDelimiter to comma
   put 0 into tCount
   repeat with i = 1 to the number of items of tFlat - 2
      if (i - 1) mod 3 is 0 and item i of tFlat is a number and item i + 1 of tFlat is a number and item i + 2 of tFlat is a number then
         if b3GeometryAddPoint(item i of tFlat * pScale, item i + 1 of tFlat * pScale, item i + 2 of tFlat * pScale) > 0 then add 1 to tCount
      end if
   end repeat
   return tCount
end b3kPointsAdd

/**
Summary: Make a solid from the tightest shape round some points.

pX: The x of its place; the points are around it.

pY: Its y.

pZ: Its z.

pPoints: The points, one "x,y,z" a line (or separated by semicolons, or one long comma list), relative to its place. At least 4, not all in one plane.

pColor: A colour; empty takes the next palette colour.

Returns: (through the result) the thing, or empty if it was refused.

Example:
-- an eight-sided gem
b3kSpawnHull 0, 4, 0, "0,0.7,0" & cr & "0,-0.7,0" & cr & "0.5,0,0" & cr & "-0.5,0,0" & cr & "0,0,0.5" & cr & "0,0,-0.5"

Description:
Box3D keeps at most 128 corners, so a rounded set of points is
simplified. Both renderers draw exactly the solid that collides.

References: b3kSpawnModel (handler)
*/
command b3kSpawnHull pX, pY, pZ, pPoints, pColor
   local tBody
   put b3kBodyNew(2, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3GeometryBegin
   if b3kPointsAdd(pPoints, 1) < 4 then
      b3BodyDestroy tBody
      put "a hull needs at least 4 points" into sLastError
      return empty
   end if
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddHull(tBody, 1, 0.6, 0.1), "hull", "tris", empty, pColor) then return empty
   b3kVisualMake tBody
   return tBody
end b3kSpawnHull

-- the text of an OBJ model, from its text or from a file path; empty and
-- sLastError when neither works
private function b3kObjText pSource
   if pSource contains (return & "v ") or char 1 to 2 of pSource is "v " then return pSource
   if there is a file pSource then return url ("file:" & pSource)
   put "not an OBJ model or a file: " & char 1 to 60 of pSource into sLastError
   return empty
end b3kObjText

-- the "v x y z" points of an OBJ text as "x,y,z" lines, scaled
private function b3kObjPoints pObj, pScale
   local tLine, tOut
   put empty into tOut
   repeat for each line tLine in pObj
      if word 1 of tLine is "v" and word 2 of tLine is a number and word 3 of tLine is a number and word 4 of tLine is a number then
         put word 2 of tLine * pScale & comma & word 3 of tLine * pScale & comma & word 4 of tLine * pScale & return after tOut
      end if
   end repeat
   return tOut
end b3kObjPoints

/**
Summary: Make a moving thing from a 3D model (Wavefront OBJ).

pX: The x of its place.

pY: Its y.

pZ: Its z.

pSource: The model: the full path of a .obj file, or the OBJ text itself.

pScale: A size multiplier; empty means 1.

pColor: A colour; empty keeps the model's own materials in render3dxt (and a light grey in box3dxt's picture).

Returns: (through the result) the thing, or empty if it was refused.

Example:
b3kSpawnModel 0, 3, 0, specialFolderPath("resources") & "/models/rock.obj", 0.5

Description:
It collides as the convex hull of the model's points (a moving body
cannot be hollow). render3dxt draws the model itself, with its materials
and textures; box3dxt's renderer draws the hull.

References: b3kAddStaticModel (handler), b3kSpawnHull (handler)
*/
command b3kSpawnModel pX, pY, pZ, pSource, pScale, pColor
   local tObj, tScale, tBody
   put b3kObjText(pSource) into tObj
   if tObj is empty then return empty
   put max(0.0001, b3kNum(pScale, 1)) into tScale
   put b3kBodyNew(2, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3GeometryBegin
   if b3kPointsAdd(b3kObjPoints(tObj, tScale), 1) < 4 then
      b3BodyDestroy tBody
      put "the model has fewer than 4 points" into sLastError
      return empty
   end if
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddHull(tBody, 1, 0.6, 0.1), "model", "model", empty, b3kRGB(pColor, "200,200,200")) then return empty
   b3kModelKeep tBody, pSource, tObj, tScale, pColor
   b3kVisualMake tBody
   return tBody
end b3kSpawnModel

-- remembers where a model's picture comes from
private command b3kModelKeep pThing, pSource, pObj, pScale, pColor
   if pSource is pObj then
      put pObj into sModel[pThing]
   else
      put pSource into sModelPath[pThing]
   end if
   put pScale into sScale[pThing]
   put (pColor is empty) into sOwnLook[pThing]
end b3kModelKeep

-- =====================================================================
-- Scenery: things that do not fall
-- =====================================================================

/**
Summary: Lay a square checkered ground.

pSize: Its width and depth in metres; empty means 30.

pY: The height of its top surface; empty means 0.

pColorA: The first checker colour; empty is a light grey.

pColorB: The second checker colour; empty is a blue grey.

Returns: (through the result) the ground thing.

Example:
b3kAddGround 40

Description:
A static box one metre thick whose top is at pY, checkered in one metre
squares by render3dxt (box3dxt's picture shows it in pColorB). There is
one ground: a second call replaces the first. <b3kAddWalls> fences it.

References: b3kAddWalls (handler), b3kKillFloor (handler)
*/
command b3kAddGround pSize, pY, pColorA, pColorB
   local tSize, tTop, tBody, tA, tB
   put max(1, min(2000, b3kNum(pSize, 30))) into tSize
   put b3kNum(pY, 0) into tTop
   if sGround is not empty then b3kRemove sGround
   put b3kBodyNew(0, 0, tTop - 0.5, 0) into tBody
   if tBody is empty then return empty
   put b3kRGB(pColorA, "214,218,226") into tA
   put b3kRGB(pColorB, "150,160,180") into tB
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddBox(tBody, tSize / 2, 0.5, tSize / 2, 0, 0.7, 0.1), "ground", "box", tSize / 2 & comma & 0.5 & comma & tSize / 2, tB) then return empty
   put tA & ";" & tB & ";" & max(1, min(64, round(tSize))) into sChecker[tBody]
   put tBody into sGround
   put tSize into sGroundSize
   put tTop into sGroundY
   b3kVisualMake tBody
   return tBody
end b3kAddGround

/**
Summary: Fence the ground with four walls.

pHeight: How tall they stand above the ground; empty means 1.

pColor: A colour; empty is a slate grey.

Returns: (through the result) the four wall things, one a line.

Example:
b3kAddGround 20
b3kAddWalls 1.5

References: b3kAddGround (handler)
*/
command b3kAddWalls pHeight, pColor
   local tH, tHalf, tY, tOut, tRGB
   if sGround is empty then
      put "there is no ground to fence: call b3kAddGround first" into sLastError
      return empty
   end if
   put max(0.1, b3kNum(pHeight, 1)) into tH
   put sGroundSize / 2 into tHalf
   put sGroundY + tH / 2 into tY
   put b3kRGB(pColor, "96,106,126") into tRGB
   b3kAddStaticBox tHalf + 0.25, tY, 0, 0.5, tH, sGroundSize + 1, tRGB
   put the result & return after tOut
   b3kAddStaticBox -tHalf - 0.25, tY, 0, 0.5, tH, sGroundSize + 1, tRGB
   put the result & return after tOut
   b3kAddStaticBox 0, tY, tHalf + 0.25, sGroundSize, tH, 0.5, tRGB
   put the result & return after tOut
   b3kAddStaticBox 0, tY, -tHalf - 0.25, sGroundSize, tH, 0.5, tRGB
   put the result after tOut
   return tOut
end b3kAddWalls

/**
Summary: Make a box that never moves: a wall, a step, a table.

pX: The x of its centre.

pY: The y of its centre.

pZ: The z of its centre.

pW: Its width; empty means 1.

pH: Its height; empty means 1.

pD: Its depth; empty means 1.

pColor: A colour; empty is a slate grey.

Returns: (through the result) the thing.

Example:
b3kAddStaticBox 0, 0.5, -4, 6, 1, 1   -- a low wall

References: b3kAddRamp (handler), b3kAddPlatform (handler)
*/
command b3kAddStaticBox pX, pY, pZ, pW, pH, pD, pColor
   local tBody, tHx, tHy, tHz
   put max(0.005, b3kNum(pW, 1)) / 2 into tHx
   put max(0.005, b3kNum(pH, 1)) / 2 into tHy
   put max(0.005, b3kNum(pD, 1)) / 2 into tHz
   put b3kBodyNew(0, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddBox(tBody, tHx, tHy, tHz, 0, 0.6, 0.1), "static", "box", tHx & comma & tHy & comma & tHz, b3kRGB(pColor, "96,106,126")) then return empty
   b3kVisualMake tBody
   return tBody
end b3kAddStaticBox

/**
Summary: Make a tilted static box: a ramp or a slide.

pX: The x of its centre.

pY: The y of its centre.

pZ: The z of its centre.

pW: Its width (across the slope).

pH: Its thickness.

pD: Its length (down the slope).

pTilt: Degrees it is tipped about its width; positive raises its far (-z) end.

pYaw: Degrees it is turned round the vertical afterwards; empty means 0.

pColor: A colour; empty is a sand colour.

Returns: (through the result) the thing.

Example:
b3kAddRamp 0, 1, 0, 3, 0.3, 6, 20

References: b3kAddStaticBox (handler)
*/
command b3kAddRamp pX, pY, pZ, pW, pH, pD, pTilt, pYaw, pColor
   local tBody, tHx, tHy, tHz, tQ
   put max(0.005, b3kNum(pW, 2)) / 2 into tHx
   put max(0.005, b3kNum(pH, 0.3)) / 2 into tHy
   put max(0.005, b3kNum(pD, 4)) / 2 into tHz
   if sWorld is empty then
      put "there is no world: call b3kSetup first" into sLastError
      return empty
   end if
   set the itemDelimiter to comma
   -- tilted about x, then turned about y
   put b3kQuat(pTilt, pYaw, 0) into tQ
   put b3BodyCreateRotated(sWorld, 0, b3kNum(pX, 0), b3kNum(pY, 0), b3kNum(pZ, 0), item 1 of tQ, item 2 of tQ, item 3 of tQ, item 4 of tQ) into tBody
   if tBody is not a number or tBody <= 0 then
      put "box3dxt made no body: " & b3LastError() into sLastError
      return empty
   end if
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddBox(tBody, tHx, tHy, tHz, 0, 0.6, 0.1), "ramp", "box", tHx & comma & tHy & comma & tHz, b3kRGB(pColor, "214,186,130")) then return empty
   b3kVisualMake tBody
   return tBody
end b3kAddRamp

/**
Summary: Make static scenery from a 3D model (Wavefront OBJ), hollows and all.

pX: The x of its place.

pY: Its y.

pZ: Its z.

pSource: The full path of a .obj file, or the OBJ text itself.

pScale: A size multiplier; empty means 1.

pColor: A colour; empty keeps the model's own materials in render3dxt.

Returns: (through the result) the thing, or empty if it was refused.

Example:
b3kAddStaticModel 0, 0, 0, tFolder & "/castle.obj"

Description:
It collides as the model's own triangles, so an arch can be walked
through and a bowl holds a ball. A triangle stops what meets its FRONT
(its corners counter-clockwise as you look at it), which is how
modelling programs write them.

References: b3kSpawnModel (handler)
*/
command b3kAddStaticModel pX, pY, pZ, pSource, pScale, pColor
   local tObj, tScale, tBody, tLine, tCount, tCorners, tWord, tI, tN, i
   put b3kObjText(pSource) into tObj
   if tObj is empty then return empty
   put max(0.0001, b3kNum(pScale, 1)) into tScale
   put b3kBodyNew(0, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3GeometryBegin
   put b3kPointsAdd(b3kObjPoints(tObj, tScale), 1) into tCount
   set the itemDelimiter to slash
   repeat for each line tLine in tObj
      if word 1 of tLine is not "f" then next repeat
      -- "f a b c d", each corner "v", "v/t", "v//n" or "v/t/n"; a
      -- negative index counts back from the points read so far
      put empty into tCorners
      repeat with tI = 2 to the number of words of tLine
         -- a word, then its first item: xTalk refuses `item of word` (a
         -- chunk names the larger part first: line, item, word, char)
         put word tI of tLine into tWord
         put item 1 of tWord into tWord
         if tWord is not an integer then next repeat
         if tWord < 0 then put tCount + 1 + tWord into tWord
         put tWord & comma after tCorners
      end repeat
      set the itemDelimiter to comma
      put the number of items of tCorners into tN
      repeat with i = 2 to tN - 1
         get b3GeometryAddTriangle(item 1 of tCorners, item i of tCorners, item i + 1 of tCorners)
      end repeat
      set the itemDelimiter to slash
   end repeat
   set the itemDelimiter to comma
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddMesh(tBody, 0.6, 0.1), "scenery", "model", empty, b3kRGB(pColor, "200,200,200")) then return empty
   b3kModelKeep tBody, pSource, tObj, tScale, pColor
   b3kVisualMake tBody
   return tBody
end b3kAddStaticModel

/**
Summary: Make a moving platform: a box that moves only as it is told.

pX: The x of its centre.

pY: The y of its centre.

pZ: The z of its centre.

pW: Its width; empty means 3.

pH: Its thickness; empty means 0.4.

pD: Its depth; empty means 3.

pColor: A colour; empty is a teal.

Returns: (through the result) the thing.

Example:
b3kAddPlatform 0, 1, 0, 3, 0.4, 3
put the result into tLift
b3kGlideTo tLift, 0, 4, 0, 2

Description:
A kinematic body: gravity and collisions do not move it, but it carries
and pushes what stands on it. Move it with <b3kGlideTo> or
<b3kSetVelocity>.

References: b3kGlideTo (handler), b3kSetType (handler)
*/
command b3kAddPlatform pX, pY, pZ, pW, pH, pD, pColor
   local tBody, tHx, tHy, tHz
   put max(0.005, b3kNum(pW, 3)) / 2 into tHx
   put max(0.005, b3kNum(pH, 0.4)) / 2 into tHy
   put max(0.005, b3kNum(pD, 3)) / 2 into tHz
   put b3kBodyNew(1, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3kShapeOptions false
   if not b3kThingAdd(tBody, b3ShapeAddBox(tBody, tHx, tHy, tHz, 0, 0.8, 0), "platform", "box", tHx & comma & tHy & comma & tHz, b3kRGB(pColor, "60,170,160")) then return empty
   b3kVisualMake tBody
   return tBody
end b3kAddPlatform

/**
Summary: Move a thing to a place over a time, by moving it.

pThing: The thing; a platform (<b3kAddPlatform>) is what this is for.

pX: The x to arrive at.

pY: The y to arrive at.

pZ: The z to arrive at.

pSeconds: How long the trip takes; empty means 1.

Example:
-- in your b3kFrame handler: a lift that rises and falls
if not b3kIsGliding(tLift) and b3kY(tLift) < 2 then b3kGlideTo tLift, 0, 4, 0, 2
if not b3kIsGliding(tLift) and b3kY(tLift) >= 2 then b3kGlideTo tLift, 0, 1, 0, 2

Description:
The thing is given the speed that brings it there in time, and is stopped
exactly there when the time is up, so what it carries rides along. It is
meant for kinematic things; a dynamic one is pushed the same way, but
gravity and collisions still act on it.

References: b3kIsGliding (handler), b3kAddPlatform (handler)
*/
command b3kGlideTo pThing, pX, pY, pZ, pSeconds
   if sKind[pThing] is empty then exit b3kGlideTo
   put b3kNum(pX, 0) & comma & b3kNum(pY, 0) & comma & b3kNum(pZ, 0) & comma & \
         (sFrames * kB3kStepMs + 1000 * max(0.02, b3kNum(pSeconds, 1))) into sGlide[pThing]
end b3kGlideTo

/**
Summary: Report whether a thing is still on its way to a <b3kGlideTo> place.

pThing: The thing.

Returns: true or false.

Example:
if not b3kIsGliding(tLift) then b3kGlideTo tLift, 0, 1, 0, 2

References: b3kGlideTo (handler)
*/
function b3kIsGliding pThing
   return sGlide[pThing] is not empty
end b3kIsGliding

-- once a frame, before the steps: each glider is given the velocity that
-- arrives on time; at the end it is put exactly there and stopped
private command b3kGlideTick
   local tThing, tG, tLeft, tQ, tDone
   if sGlide is empty then exit b3kGlideTick
   set the itemDelimiter to comma
   repeat for each key tThing in sGlide
      put sGlide[tThing] into tG
      -- the simulation clock, so a pause or a stalled frame does not
      -- shorten the trip
      put (item 4 of tG - sFrames * kB3kStepMs) / 1000 into tLeft
      if tLeft <= kB3kStepS or not b3BodyIsValid(tThing) then
         if b3BodyIsValid(tThing) then
            b3BodySetPosition tThing, item 1 of tG, item 2 of tG, item 3 of tG
            b3BodySetVelocity tThing, 0, 0, 0
            b3kNodeSync tThing
         end if
         put tThing & return after tDone
      else
         put b3BodyRotation(tThing) into tQ
         b3BodySetTargetTransform tThing, item 1 of tG, item 2 of tG, item 3 of tG, \
               item 1 of tQ, item 2 of tQ, item 3 of tQ, item 4 of tQ, tLeft, true
      end if
   end repeat
   repeat for each line tThing in tDone
      delete variable sGlide[tThing]
   end repeat
end b3kGlideTick

-- =====================================================================
-- Sensors: zones that notice what enters them
-- =====================================================================

/**
Summary: Make a box-shaped zone that reports what enters and leaves it.

pX: The x of its centre.

pY: The y of its centre.

pZ: The z of its centre.

pW: Its width; empty means 1.

pH: Its height; empty means 1.

pD: Its depth; empty means 1.

Returns: (through the result) the sensor thing.

Example:
b3kAddSensorBox 0, 1, -8, 2, 2, 2
put the result into tGoal
-- then, in your b3kSensorEnter pSensor, pVisitor handler:
if pSensor is tGoal and pVisitor is b3kPlayer() then answer "You made it!"

Description:
A sensor collides with nothing. render3dxt does not draw it (give it a
look with <b3kSetVisible>); box3dxt's renderer draws every shape, so
there it shows as a pale block. Messages go to <b3kContactTarget>.

References: b3kAddSensorBall (handler), b3kContactTarget (handler)
*/
command b3kAddSensorBox pX, pY, pZ, pW, pH, pD
   local tBody, tHx, tHy, tHz
   put max(0.005, b3kNum(pW, 1)) / 2 into tHx
   put max(0.005, b3kNum(pH, 1)) / 2 into tHy
   put max(0.005, b3kNum(pD, 1)) / 2 into tHz
   put b3kBodyNew(0, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3kShapeOptions true
   if not b3kThingAdd(tBody, b3ShapeAddBox(tBody, tHx, tHy, tHz, 0, 0, 0), "sensor", "box", tHx & comma & tHy & comma & tHz, "250,230,140") then return empty
   put true into sSensorOf[tBody]
   put false into sVisible[tBody]
   b3kVisualMake tBody
   return tBody
end b3kAddSensorBox

/**
Summary: Make a ball-shaped zone that reports what enters and leaves it.

pX: The x of its centre.

pY: The y of its centre.

pZ: The z of its centre.

pDiameter: Its diameter; empty means 1.

Returns: (through the result) the sensor thing.

Example:
b3kAddSensorBall 3, 1, 3, 1.2
put the result into tCoinZone

References: b3kAddSensorBox (handler)
*/
command b3kAddSensorBall pX, pY, pZ, pDiameter
   local tBody, tR
   put max(0.005, b3kNum(pDiameter, 1)) / 2 into tR
   put b3kBodyNew(0, pX, pY, pZ) into tBody
   if tBody is empty then return empty
   b3kShapeOptions true
   if not b3kThingAdd(tBody, b3ShapeAddSphere(tBody, 0, 0, 0, tR, 0, 0, 0), "sensor", "ball", tR, "250,230,140") then return empty
   put true into sSensorOf[tBody]
   put false into sVisible[tBody]
   b3kVisualMake tBody
   return tBody
end b3kAddSensorBall

-- =====================================================================
-- Look and material
-- =====================================================================

/**
Summary: Change a thing's colour.

pThing: The thing.

pColor: A colour name, "r,g,b" or "#rrggbb".

Example:
b3kSetColor tCrate, "red"

Description:
Replaces any checker or picture the thing wore.

References: b3kColor (handler), b3kSetChecker (handler)
*/
command b3kSetColor pThing, pColor
   local tRGB
   if sKind[pThing] is empty then exit b3kSetColor
   put b3kRGB(pColor, sColor[pThing]) into tRGB
   put tRGB into sColor[pThing]
   put empty into sChecker[pThing]
   put empty into sTexPath[pThing]
   put false into sOwnLook[pThing]
   if sHasOwn is true then
      set the itemDelimiter to comma
      b3ShapeSetColor sShape[pThing], item 1 of tRGB, item 2 of tRGB, item 3 of tRGB
   end if
   b3kVisualLook pThing
   put true into sStale
end b3kSetColor

/**
Summary: A thing's colour.

pThing: The thing.

Returns: "r,g,b", or empty for no thing.

Example:
put b3kColor(tCrate) into tWas

References: b3kSetColor (handler)
*/
function b3kColor pThing
   return sColor[pThing]
end b3kColor

/**
Summary: Make a thing glow with a light of its own (render3dxt only).

pThing: The thing.

pColor: The glow's colour, added to the thing's whatever the lights do;
empty or "0,0,0" turns it off.

Example:
b3kSetGlow tOrb, "160,110,0"      -- a gold that shines in the shade

Description:
A glow lights the thing itself, not what is near it: put a lamp beside it
with <b3kAddLamp> for that. It works with a colour, a checker or a picture.
box3dxt's renderer keeps the plain colour.

References: b3kGlow (handler), b3kAddLamp (handler), b3kSetColor (handler)
*/
command b3kSetGlow pThing, pColor
   if sKind[pThing] is empty then exit b3kSetGlow
   if pColor is empty then
      delete variable sGlow[pThing]
   else
      put b3kRGB(pColor, "0,0,0") into sGlow[pThing]
      if sGlow[pThing] is "0,0,0" then delete variable sGlow[pThing]
   end if
   b3kVisualLook pThing
   put true into sStale
end b3kSetGlow

/**
Summary: A thing's glow.

pThing: The thing.

Returns: "r,g,b", or empty for a thing that does not glow.

Example:
if b3kGlow(tOrb) is empty then b3kSetGlow tOrb, "120,90,0"

References: b3kSetGlow (handler)
*/
function b3kGlow pThing
   return sGlow[pThing]
end b3kGlow

/**
Summary: Give a thing a checkerboard look (render3dxt only).

pThing: The thing.

pColorA: The first colour.

pColorB: The second colour.

pCells: How many squares across each face; empty means 4.

Example:
b3kSetChecker tBall, "white", "red", 8

Description:
box3dxt's renderer shows the first colour.

References: b3kSetColor (handler), b3kSetTexture (handler)
*/
command b3kSetChecker pThing, pColorA, pColorB, pCells
   local tA
   if sKind[pThing] is empty then exit b3kSetChecker
   put b3kRGB(pColorA, "240,240,240") into tA
   put tA & ";" & b3kRGB(pColorB, "60,60,60") & ";" & max(1, min(64, round(b3kNum(pCells, 4)))) into sChecker[pThing]
   put empty into sTexPath[pThing]
   put tA into sColor[pThing]
   if sHasOwn is true then
      set the itemDelimiter to comma
      b3ShapeSetColor sShape[pThing], item 1 of tA, item 2 of tA, item 3 of tA
   end if
   b3kVisualLook pThing
end b3kSetChecker

/**
Summary: Wrap a picture file round a thing (render3dxt only).

pThing: The thing.

pPath: The full path of a PNG, JPEG, BMP or TGA file.

Example:
b3kSetTexture tCrate, specialFolderPath("resources") & "/crate.png"

Description:
Each face of a box shows the whole picture. box3dxt's renderer keeps
the thing's colour.

References: b3kSetChecker (handler)
*/
command b3kSetTexture pThing, pPath
   if sKind[pThing] is empty then exit b3kSetTexture
   put pPath into sTexPath[pThing]
   put empty into sChecker[pThing]
   b3kVisualLook pThing
end b3kSetTexture

/**
Summary: Draw a 3D model (Wavefront OBJ) in place of a thing's own shape (render3dxt only).

pThing: The thing.

pSource: The OBJ text itself, or the full path of a .obj file; empty puts the thing's own shape back.

pMaterials: The text of the model's material (.mtl) file, for OBJ text; empty leaves the model white. A path reads the materials and pictures its file names.

pScale: A size multiplier; empty means 1.

Example:
b3kSetLook tPlatform, tPlatformObj, tPlatformMtl

Description:
Only the picture changes: the thing still collides, falls and is
picked as its own shape, so a box can look like a carved platform and
a capsule like a character. The model's origin sits at the thing's
centre and turns with it. Things wearing the same model share one copy
of it. The model keeps its own colours: a colour, checker, picture or
glow set on the thing shows again when the look is taken off, and
box3dxt's renderer keeps drawing the shape in the thing's colour.

References: b3kSpawnModel (handler), b3kAddStaticModel (handler), b3kSetColor (handler)
*/
command b3kSetLook pThing, pSource, pMaterials, pScale
   local tHandle
   if sKind[pThing] is empty then exit b3kSetLook
   if pSource is empty then
      delete variable sLook[pThing]
      delete variable sLookMtl[pThing]
      delete variable sLookScale[pThing]
      delete variable sLookKey[pThing]
   else
      put pSource into sLook[pThing]
      put pMaterials into sLookMtl[pThing]
      put max(0.0001, b3kNum(pScale, 1)) into sLookScale[pThing]
      put "look:" & base64Encode(md5Digest(pSource & numToChar(1) & pMaterials)) into sLookKey[pThing]
   end if
   -- a new picture: the old node and any mesh it alone owned go first
   if sScene is not empty then
      repeat for each item tHandle in sNode[pThing]
         r3NodeDestroy tHandle
      end repeat
      repeat for each item tHandle in sOwnMesh[pThing]
         r3MeshDestroy tHandle
      end repeat
   end if
   put empty into sNode[pThing]
   put empty into sOwnMesh[pThing]
   b3kVisualMake pThing
   put true into sStale
end b3kSetLook

/**
Summary: Show or hide a thing's picture.

pThing: The thing.

pFlag: true to show it, false to hide it.

Example:
b3kSetVisible tGoalZone, true   -- see where the sensor is

Description:
Only the picture: a hidden thing still collides. Hiding is render3dxt's;
box3dxt's renderer draws every enabled body.

References: b3kIsVisible (handler), b3kDisable (handler)
*/
command b3kSetVisible pThing, pFlag
   local tNode
   if sKind[pThing] is empty then exit b3kSetVisible
   put (pFlag is not false) into sVisible[pThing]
   repeat for each item tNode in sNode[pThing]
      r3NodeSetVisible tNode, (sVisible[pThing] and b3BodyIsEnabled(pThing))
   end repeat
   put true into sStale
end b3kSetVisible

/**
Summary: Report whether a thing's picture is shown.

pThing: The thing.

Returns: true or false.

Example:
if not b3kIsVisible(tZone) then b3kSetVisible tZone, true

References: b3kSetVisible (handler)
*/
function b3kIsVisible pThing
   return sVisible[pThing] is true
end b3kIsVisible

/**
Summary: Set how bouncy a thing is.

pThing: The thing.

pValue: 0 (a thud) to 1 (bounces back as high).

Example:
b3kSetBounce tBall, 0.8

References: b3kSetFriction (handler)
*/
command b3kSetBounce pThing, pValue
   if sKind[pThing] is empty then exit b3kSetBounce
   b3ShapeSetRestitution sShape[pThing], max(0, min(1, b3kNum(pValue, 0.1)))
end b3kSetBounce

/**
Summary: Set how grippy a thing is.

pThing: The thing.

pValue: 0 (ice) and up; 0.6 is ordinary.

Example:
b3kSetFriction tPuck, 0.02

References: b3kSetBounce (handler)
*/
command b3kSetFriction pThing, pValue
   if sKind[pThing] is empty then exit b3kSetFriction
   b3ShapeSetFriction sShape[pThing], max(0, b3kNum(pValue, 0.6))
end b3kSetFriction

/**
Summary: Set how heavy a thing is for its size.

pThing: The thing.

pValue: Kilograms per cubic metre; the Kit's things start at 1.

Example:
b3kSetDensity tAnvil, 20

References: b3kMass (handler)
*/
command b3kSetDensity pThing, pValue
   if sKind[pThing] is empty then exit b3kSetDensity
   b3ShapeSetDensity sShape[pThing], max(0, b3kNum(pValue, 1)), true
end b3kSetDensity

-- =====================================================================
-- Body settings
-- =====================================================================

/**
Summary: Change how a thing moves.

pThing: The thing.

pType: "static" (never moves), "kinematic" (moves only as told) or "dynamic" (falls and collides).

Example:
b3kSetType tCrate, "static"   -- freeze it where it is

References: b3kType (handler)
*/
command b3kSetType pThing, pType
   local tN
   if sKind[pThing] is empty then exit b3kSetType
   switch pType
      case "static"
         put 0 into tN
         break
      case "kinematic"
         put 1 into tN
         break
      default
         put 2 into tN
   end switch
   b3BodySetType pThing, tN
   put true into sStale
end b3kSetType

/**
Summary: How a thing moves.

pThing: The thing.

Returns: "static", "kinematic" or "dynamic"; empty for no thing.

Example:
if b3kType(tHit) is "dynamic" then b3kPush tHit, 0, 3, 0

References: b3kSetType (handler)
*/
function b3kType pThing
   if sKind[pThing] is empty then return empty
   switch b3BodyType(pThing)
      case 0
         return "static"
      case 1
         return "kinematic"
      case 2
         return "dynamic"
   end switch
   return empty
end b3kType

/**
Summary: Scale how strongly gravity pulls one thing.

pThing: The thing.

pScale: 1 is normal, 0 floats, negative rises.

Example:
b3kSetGravityScale tBalloon, -0.2

References: b3kSetGravity (handler)
*/
command b3kSetGravityScale pThing, pScale
   if sKind[pThing] is empty then exit b3kSetGravityScale
   b3BodySetGravityScale pThing, b3kNum(pScale, 1)
end b3kSetGravityScale

/**
Summary: Slow a thing down over time, like air or water.

pThing: The thing.

pLinear: How quickly moving slows; 0 is none, 1 is heavy.

pAngular: How quickly spinning slows; empty leaves it alone.

Example:
b3kSetDamping tFeather, 2

References: b3kSetGravityScale (handler)
*/
command b3kSetDamping pThing, pLinear, pAngular
   if sKind[pThing] is empty then exit b3kSetDamping
   b3BodySetLinearDamping pThing, max(0, b3kNum(pLinear, 0))
   if pAngular is a number then b3BodySetAngularDamping pThing, max(0, pAngular)
end b3kSetDamping

/**
Summary: Make a fast thing check every step for what it might pass through.

pThing: The thing.

pFlag: true or false.

Example:
b3kSetBullet tShot, true

References: b3kSetDamping (handler)
*/
command b3kSetBullet pThing, pFlag
   if sKind[pThing] is empty then exit b3kSetBullet
   b3BodySetBullet pThing, (pFlag is true)
end b3kSetBullet

/**
Summary: Stop a thing from tipping over: it may move but not turn.

pThing: The thing.

pFlag: true keeps it upright; false lets it tumble again.

Example:
b3kKeepUpright tSnowman, true

References: b3kPlayerMake (handler)
*/
command b3kKeepUpright pThing, pFlag
   local tLock
   if sKind[pThing] is empty then exit b3kKeepUpright
   put (pFlag is not false) into tLock
   b3BodySetMotionLocks pThing, false, false, false, tLock, tLock, tLock
end b3kKeepUpright

/**
Summary: Wake a sleeping thing.

pThing: The thing.

Example:
b3kWake tCrate

Description:
Things at rest fall asleep to save time, and wake by themselves when
touched or pushed.

References: b3kIsAwake (handler)
*/
command b3kWake pThing
   if sKind[pThing] is empty then exit b3kWake
   b3BodySetAwake pThing, true
end b3kWake

/**
Summary: Take a thing out of the world for now, keeping it.

pThing: The thing.

Example:
b3kDisable tDoor

Description:
A disabled thing does not collide, move or show; <b3kEnable> brings it back where it was.

References: b3kEnable (handler)
*/
command b3kDisable pThing
   local tNode
   if sKind[pThing] is empty then exit b3kDisable
   b3BodyDisable pThing
   repeat for each item tNode in sNode[pThing]
      r3NodeSetVisible tNode, false
   end repeat
   put true into sStale
end b3kDisable

/**
Summary: Bring back a thing <b3kDisable> took out.

pThing: The thing.

Example:
b3kEnable tDoor

References: b3kDisable (handler)
*/
command b3kEnable pThing
   local tNode
   if sKind[pThing] is empty then exit b3kEnable
   b3BodyEnable pThing
   repeat for each item tNode in sNode[pThing]
      r3NodeSetVisible tNode, (sVisible[pThing] is true)
   end repeat
   put true into sStale
end b3kEnable

-- =====================================================================
-- Acting on things
-- =====================================================================

/**
Summary: Change a thing's speed at once, whatever it weighs.

pThing: The thing.

pDvx: Metres a second to add along x.

pDvy: Along y; positive is up.

pDvz: Along z.

Example:
b3kPush tBall, 0, 6, 0   -- a hop

Description:
The kick that suits any size: the impulse is the thing's mass times the
change. A kinematic thing has the change added to its velocity; a static
one does not move.

References: b3kImpulse (handler), b3kSetVelocity (handler)
*/
command b3kPush pThing, pDvx, pDvy, pDvz
   local tMass, tV
   if sKind[pThing] is empty then exit b3kPush
   put b3kNum(pDvx, 0) into pDvx
   put b3kNum(pDvy, 0) into pDvy
   put b3kNum(pDvz, 0) into pDvz
   switch b3BodyType(pThing)
      case 2
         put b3BodyMass(pThing) into tMass
         b3BodyApplyImpulseToCenter pThing, tMass * pDvx, tMass * pDvy, tMass * pDvz, true
         break
      case 1
         put b3BodyVelocity(pThing) into tV
         set the itemDelimiter to comma
         b3BodySetVelocity pThing, item 1 of tV + pDvx, item 2 of tV + pDvy, item 3 of tV + pDvz
         break
   end switch
end b3kPush

/**
Summary: Kick a thing at its centre.

pThing: The thing.

pIx: The impulse along x, in kilogram metres a second.

pIy: Along y.

pIz: Along z.

Example:
b3kImpulse tCrate, 0, 5, 0

Description:
A heavy thing moves less than a light one; <b3kPush> ignores weight.

References: b3kPush (handler), b3kForce (handler)
*/
command b3kImpulse pThing, pIx, pIy, pIz
   if sKind[pThing] is empty then exit b3kImpulse
   b3BodyApplyImpulseToCenter pThing, b3kNum(pIx, 0), b3kNum(pIy, 0), b3kNum(pIz, 0), true
end b3kImpulse

/**
Summary: Push a thing steadily: call it every frame it should act.

pThing: The thing.

pFx: The force along x, in newtons.

pFy: Along y.

pFz: Along z.

Example:
-- in your b3kFrame handler:
if b3kKeyIsDown("space") then b3kForce tRocket, 0, 30, 0

References: b3kImpulse (handler), b3kTorque (handler)
*/
command b3kForce pThing, pFx, pFy, pFz
   if sKind[pThing] is empty then exit b3kForce
   b3BodyApplyForceToCenter pThing, b3kNum(pFx, 0), b3kNum(pFy, 0), b3kNum(pFz, 0), true
end b3kForce

/**
Summary: Twist a thing steadily: call it every frame it should act.

pThing: The thing.

pTx: The torque about x, in newton metres.

pTy: About y.

pTz: About z.

Example:
b3kTorque tTop, 0, 2, 0

References: b3kSetSpin (handler)
*/
command b3kTorque pThing, pTx, pTy, pTz
   if sKind[pThing] is empty then exit b3kTorque
   b3BodyApplyTorque pThing, b3kNum(pTx, 0), b3kNum(pTy, 0), b3kNum(pTz, 0), true
end b3kTorque

/**
Summary: Set a thing's speed and direction.

pThing: The thing.

pVx: Metres a second along x.

pVy: Along y.

pVz: Along z.

Example:
b3kSetVelocity tPuck, 4, 0, -2

Description:
It wakes the thing: never set the velocity of something meant to rest every frame.

References: b3kPush (handler), b3kVelocity (handler)
*/
command b3kSetVelocity pThing, pVx, pVy, pVz
   if sKind[pThing] is empty then exit b3kSetVelocity
   b3BodySetVelocity pThing, b3kNum(pVx, 0), b3kNum(pVy, 0), b3kNum(pVz, 0)
end b3kSetVelocity

/**
Summary: Set how fast a thing turns.

pThing: The thing.

pWx: Degrees a second about x.

pWy: About y.

pWz: About z.

Example:
b3kSetSpin tCoin, 0, 180, 0

References: b3kTorque (handler)
*/
command b3kSetSpin pThing, pWx, pWy, pWz
   if sKind[pThing] is empty then exit b3kSetSpin
   b3BodySetAngularVelocity pThing, b3kNum(pWx, 0) * pi / 180, b3kNum(pWy, 0) * pi / 180, b3kNum(pWz, 0) * pi / 180
end b3kSetSpin

/**
Summary: Put a thing somewhere else at once, at rest.

pThing: The thing.

pX: The x of its new centre.

pY: Its y.

pZ: Its z.

Example:
b3kMoveTo b3kPlayer(), 0, 2, 0   -- back to the start

Description:
A teleport: its speed and spin are stopped and any <b3kGlideTo> is
dropped. Use <b3kGlideTo> to move a platform so that it carries things.

References: b3kGlideTo (handler), b3kSetRotation (handler)
*/
command b3kMoveTo pThing, pX, pY, pZ
   if sKind[pThing] is empty then exit b3kMoveTo
   delete variable sGlide[pThing]
   b3BodySetPosition pThing, b3kNum(pX, 0), b3kNum(pY, 0), b3kNum(pZ, 0)
   if b3BodyType(pThing) is not 0 then
      b3BodySetVelocity pThing, 0, 0, 0
      b3BodySetAngularVelocity pThing, 0, 0, 0
      b3BodySetAwake pThing, true
   end if
   b3kNodeSync pThing
   put true into sStale
end b3kMoveTo

/**
Summary: Turn a thing to a rotation given as three angles.

pThing: The thing.

pRx: Degrees about x.

pRy: Degrees about y.

pRz: Degrees about z.

Example:
b3kSetRotation tCrate, 0, 45, 0

References: b3kTurnTo (handler), b3kRotation (handler)
*/
command b3kSetRotation pThing, pRx, pRy, pRz
   local tQ
   if sKind[pThing] is empty then exit b3kSetRotation
   put b3kQuat(pRx, pRy, pRz) into tQ
   set the itemDelimiter to comma
   b3BodySetRotation pThing, item 1 of tQ, item 2 of tQ, item 3 of tQ, item 4 of tQ
   b3kNodeSync pThing
   put true into sStale
end b3kSetRotation

/**
Summary: Turn a thing to face a heading, upright.

pThing: The thing.

pYaw: Degrees round the vertical; 0 faces +z, 90 faces +x.

Example:
b3kTurnTo tGuard, b3kPlayerFacing()

References: b3kYaw (handler), b3kSetRotation (handler)
*/
command b3kTurnTo pThing, pYaw
   local tQ
   if sKind[pThing] is empty then exit b3kTurnTo
   put b3kQuat(0, pYaw, 0) into tQ
   set the itemDelimiter to comma
   b3BodySetRotation pThing, item 1 of tQ, item 2 of tQ, item 3 of tQ, item 4 of tQ
   b3kNodeSync pThing
   put true into sStale
end b3kTurnTo

/**
Summary: Blow things away from a point.

pX: The x of the blast.

pY: Its y.

pZ: Its z.

pRadius: How far it reaches at full strength, in metres; empty means 3.

pPower: How hard it pushes; empty means 6.

Example:
b3kExplode 0, 0.5, 0, 4, 10
b3kCamShake 0.3, 300

References: b3kOverlapSphere (handler), b3kCamShake (handler)
*/
command b3kExplode pX, pY, pZ, pRadius, pPower
   local tR
   if sWorld is empty then exit b3kExplode
   put max(0.01, b3kNum(pRadius, 3)) into tR
   b3WorldExplode sWorld, b3kNum(pX, 0), b3kNum(pY, 0), b3kNum(pZ, 0), tR, tR, b3kNum(pPower, 6)
end b3kExplode

/**
Summary: Remove a thing from the world and the picture.

pThing: The thing.

Example:
-- in your b3kSensorEnter pSensor, pVisitor handler:
if pSensor is tCoinZone then b3kRemove pSensor

Description:
Its joints go with it. A thing that is no longer there is ignored, so
removing twice is harmless.

References: b3kClear (handler)
*/
command b3kRemove pThing
   local tHandle
   if pThing is empty or sKind[pThing] is empty then exit b3kRemove
   if pThing is sPlayer then b3kPlayerForget false
   if pThing is sCamFollow then put empty into sCamFollow
   if pThing is sGround then put empty into sGround
   if sName[pThing] is not empty then delete variable sThingOf[sName[pThing]]
   if sScene is not empty then
      repeat for each item tHandle in sNode[pThing]
         r3NodeDestroy tHandle
      end repeat
      repeat for each item tHandle in sOwnMesh[pThing]
         r3MeshDestroy tHandle
      end repeat
      repeat for each item tHandle in sOwnMat[pThing]
         r3MaterialDestroy tHandle
      end repeat
      repeat for each item tHandle in sOwnTex[pThing]
         r3TextureDestroy tHandle
      end repeat
   end if
   b3BodyDestroy pThing
   delete variable sKind[pThing]
   delete variable sGeo[pThing]
   delete variable sShape[pThing]
   delete variable sDims[pThing]
   delete variable sColor[pThing]
   delete variable sNode[pThing]
   delete variable sOwnMesh[pThing]
   delete variable sOwnMat[pThing]
   delete variable sOwnTex[pThing]
   delete variable sChecker[pThing]
   delete variable sGlow[pThing]
   delete variable sTexPath[pThing]
   delete variable sModel[pThing]
   delete variable sModelPath[pThing]
   delete variable sLook[pThing]
   delete variable sLookMtl[pThing]
   delete variable sLookScale[pThing]
   delete variable sLookKey[pThing]
   delete variable sScale[pThing]
   delete variable sVisible[pThing]
   delete variable sSensorOf[pThing]
   delete variable sOwnLook[pThing]
   delete variable sGlide[pThing]
   delete variable sName[pThing]
   delete variable sBorn[pThing]
   put true into sStale
end b3kRemove

-- =====================================================================
-- Reading things
-- =====================================================================

/**
Summary: Where a thing is.

pThing: The thing.

Returns: "x,y,z" of its centre in metres; empty for no thing.

Example:
put b3kPosition(tBall) into tWhere

References: b3kX (handler), b3kMoveTo (handler)
*/
function b3kPosition pThing
   if sKind[pThing] is empty then return empty
   return b3BodyPosition(pThing)
end b3kPosition

/**
Summary: A thing's x.

pThing: The thing.

Returns: Metres; 0 for no thing.

Example:
if b3kX(tBall) > 10 then put "out" into tState

References: b3kPosition (handler)
*/
function b3kX pThing
   if sKind[pThing] is empty then return 0
   return b3BodyX(pThing)
end b3kX

/**
Summary: A thing's height.

pThing: The thing.

Returns: Metres; 0 for no thing.

Example:
if b3kY(b3kPlayer()) < -5 then b3kMoveTo b3kPlayer(), 0, 2, 0

References: b3kPosition (handler)
*/
function b3kY pThing
   if sKind[pThing] is empty then return 0
   return b3BodyY(pThing)
end b3kY

/**
Summary: A thing's z.

pThing: The thing.

Returns: Metres; 0 for no thing.

Example:
put b3kZ(tBall) into tDepth

References: b3kPosition (handler)
*/
function b3kZ pThing
   if sKind[pThing] is empty then return 0
   return b3BodyZ(pThing)
end b3kZ

/**
Summary: How a thing is moving.

pThing: The thing.

Returns: "vx,vy,vz" in metres a second; empty for no thing.

Example:
put item 2 of b3kVelocity(tBall) into tFalling

References: b3kSpeed (handler), b3kSetVelocity (handler)
*/
function b3kVelocity pThing
   if sKind[pThing] is empty then return empty
   return b3BodyVelocity(pThing)
end b3kVelocity

/**
Summary: How fast a thing is moving.

pThing: The thing.

Returns: Metres a second; 0 for no thing.

Example:
if b3kSpeed(tCar) > 20 then b3kSetDamping tCar, 0.5

References: b3kVelocity (handler)
*/
function b3kSpeed pThing
   if sKind[pThing] is empty then return 0
   return b3BodySpeed(pThing)
end b3kSpeed

/**
Summary: A thing's rotation, as the three angles b3kSetRotation takes.

pThing: The thing.

Returns: "rx,ry,rz" in degrees: turned about x first, then y, then z, as
<b3kSetRotation> turns it. Empty for no thing.

Example:
put b3kRotation(tCrate) into tTurn
b3kSetRotation tOther, item 1 of tTurn, item 2 of tTurn, item 3 of tTurn

Description:
ry runs from -90 to 90; rx and rz from -180 to 180. Standing straight up
or down (ry at 90 or -90) the x and z turns are the same turn, and it is
all given as rz.

References: b3kYaw (handler), b3kSetRotation (handler)
*/
function b3kRotation pThing
   local tQ, tX, tY, tZ, tW, tSin, tRx, tRy, tRz
   if sKind[pThing] is empty then return empty
   put b3BodyRotation(pThing) into tQ
   set the itemDelimiter to comma
   put item 1 of tQ into tX
   put item 2 of tQ into tY
   put item 3 of tQ into tZ
   put item 4 of tQ into tW
   -- b3kSetRotation turns by Rz * Ry * Rx (b3kQuat, the order
   -- b3QuatFromEuler uses too); this reads the three angles back out of
   -- that matrix
   put max(-1, min(1, 2 * (tW * tY - tX * tZ))) into tSin
   put asin(tSin) into tRy
   if abs(tSin) > 0.99999 then
      put 0 into tRx
      put atan2(2 * (tW * tZ - tX * tY), 1 - 2 * (tX * tX + tZ * tZ)) into tRz
   else
      put atan2(2 * (tY * tZ + tW * tX), 1 - 2 * (tX * tX + tY * tY)) into tRx
      put atan2(2 * (tX * tY + tW * tZ), 1 - 2 * (tY * tY + tZ * tZ)) into tRz
   end if
   return (tRx * 180 / pi) & comma & (tRy * 180 / pi) & comma & (tRz * 180 / pi)
end b3kRotation

/**
Summary: The heading a thing faces.

pThing: The thing.

Returns: Degrees round the vertical, -180 to 180; 0 faces +z, 90 faces +x.

Example:
put b3kYaw(tCar) into tHeading

References: b3kTurnTo (handler)
*/
function b3kYaw pThing
   local tQ, tF
   if sKind[pThing] is empty then return 0
   put b3BodyRotation(pThing) into tQ
   set the itemDelimiter to comma
   put b3QuatRotate(item 1 of tQ, item 2 of tQ, item 3 of tQ, item 4 of tQ, 0, 0, 1) into tF
   return atan2(item 1 of tF, item 3 of tF) * 180 / pi
end b3kYaw

/**
Summary: How heavy a thing is.

pThing: The thing.

Returns: Kilograms; 0 for a static thing or no thing.

Example:
put b3kMass(tCrate) into tKg

References: b3kSetDensity (handler)
*/
function b3kMass pThing
   if sKind[pThing] is empty then return 0
   return b3BodyMass(pThing)
end b3kMass

/**
Summary: Report whether a thing is awake (moving, or able to).

pThing: The thing.

Returns: true or false.

Example:
if not b3kIsAwake(tTower) then put "settled" into tState

References: b3kWake (handler)
*/
function b3kIsAwake pThing
   if sKind[pThing] is empty then return false
   return b3BodyIsAwake(pThing)
end b3kIsAwake

/**
Summary: What kind of thing a thing is.

pThing: The thing.

Returns: box, ball, capsule, cylinder, cone, hull, model, ground, static, ramp, scenery, platform or sensor; empty for no thing.

Example:
if b3kKind(tHit) is "ground" then put b3kHitPoint() into tTarget

References: b3kIsThing (handler)
*/
function b3kKind pThing
   if pThing is empty then return empty
   return sKind[pThing]
end b3kKind

/**
Summary: Report whether a value is a thing the Kit made and still has.

pValue: Anything.

Returns: true or false.

Example:
if b3kIsThing(tTarget) then b3kPush tTarget, 0, 3, 0

References: b3kKind (handler)
*/
function b3kIsThing pValue
   if pValue is empty then return false
   return sKind[pValue] is not empty
end b3kIsThing

/**
Summary: Every thing there is.

Returns: One thing a line, oldest first.

Example:
put line -1 of b3kThings() into tNewest

References: b3kThingCount (handler)
*/
function b3kThings
   local tKeys
   put the keys of sKind into tKeys
   -- by birth: a handle's number carries a generation tag, so it says
   -- nothing about which came first
   sort lines of tKeys numeric by sBorn[each]
   return tKeys
end b3kThings

/**
Summary: How many things there are.

Returns: A whole number.

Example:
put b3kThingCount() && "things" into field "Count"

References: b3kThings (handler)
*/
function b3kThingCount
   local tKeys
   put the keys of sKind into tKeys
   if tKeys is empty then return 0
   return the number of lines of tKeys
end b3kThingCount

/**
Summary: How far apart two things' centres are.

pThingA: One thing.

pThingB: The other.

Returns: Metres; empty when either is not a thing.

Example:
if b3kDistance(b3kPlayer(), tExit) < 1.5 then put "home" into tState

References: b3kPosition (handler)
*/
function b3kDistance pThingA, pThingB
   local tA, tB, tDx, tDy, tDz
   if sKind[pThingA] is empty or sKind[pThingB] is empty then return empty
   put b3BodyPosition(pThingA) into tA
   put b3BodyPosition(pThingB) into tB
   set the itemDelimiter to comma
   put item 1 of tA - item 1 of tB into tDx
   put item 2 of tA - item 2 of tB into tDy
   put item 3 of tA - item 3 of tB into tDz
   return sqrt(tDx * tDx + tDy * tDy + tDz * tDz)
end b3kDistance

/**
Summary: The box3dxt shape of a thing, for raw b3Shape... calls.

pThing: The thing.

Returns: The shape handle; empty for no thing.

Example:
b3ShapeSetRollingResistance b3kShapeOf(tBall), 0.05

References: b3kWorld (handler)
*/
function b3kShapeOf pThing
   if pThing is empty then return empty
   return sShape[pThing]
end b3kShapeOf

/**
Summary: Give a thing a name to find it by.

pThing: The thing.

pName: Any text; empty forgets its name.

Example:
b3kName tDoor, "door"
-- later
b3kRemove b3kThingNamed("door")

References: b3kThingNamed (handler), b3kNameOf (handler)
*/
command b3kName pThing, pName
   if sKind[pThing] is empty then exit b3kName
   if sName[pThing] is not empty then delete variable sThingOf[sName[pThing]]
   if pName is empty then
      delete variable sName[pThing]
   else
      if sThingOf[pName] is not empty then delete variable sName[sThingOf[pName]]
      put pName into sName[pThing]
      put pThing into sThingOf[pName]
   end if
end b3kName

/**
Summary: A thing's name.

pThing: The thing.

Returns: Its name, or empty.

Example:
put b3kNameOf(tHit) into field "Picked"

References: b3kName (handler)
*/
function b3kNameOf pThing
   if pThing is empty then return empty
   return sName[pThing]
end b3kNameOf

/**
Summary: The thing with a name.

pName: The name given by <b3kName>.

Returns: The thing, or empty.

Example:
b3kPush b3kThingNamed("ball"), 0, 5, 0

References: b3kName (handler)
*/
function b3kThingNamed pName
   if pName is empty then return empty
   return sThingOf[pName]
end b3kThingNamed


-- =====================================================================
-- Joints: hinges, balls, welds, ropes and sliders between two things
-- =====================================================================
-- A joint is Box3D's own handle (a positive whole number), reported through
-- the result like a thing. An empty second thing joins the first to the
-- world: the Kit's anchor, a static body with no shape, is the other end.
-- The anchor goes FIRST in that case, so a hinge's angle and a slider's
-- travel read the thing's own motion, not the world's against it.

-- "bodyA,bodyB" for a new joint, or empty when either end is not a thing
private function b3kJointPair pA, pB
   if sWorld is empty then return empty
   if sKind[pA] is empty then return empty
   if pB is empty then return sAnchor & comma & pA
   if sKind[pB] is empty then return empty
   if pB is pA then return empty
   return pA & comma & pB
end b3kJointPair

-- a live joint handle? Nested, never one expression: the handle goes to a
-- typed Integer parameter, and an empty one there is a hard error (engine
-- notes 2.5 and 6.4)
private function b3kJointOk pJoint
   if sWorld is empty then return false
   if pJoint is not an integer then return false
   if pJoint <= 0 or pJoint > 2147483647 then return false
   return b3JointIsValid(pJoint)
end b3kJointOk

-- a new joint's handle, or empty with b3kLastError saying why
private function b3kJointMade pJoint
   if pJoint is not a number or pJoint <= 0 then
      put "box3dxt refused the joint: " & b3LastError() into sLastError
      return empty
   end if
   put empty into sLastError
   return pJoint
end b3kJointMade

/**
Summary: Join two things with a hinge, or pin one to the world.

pA: The thing that turns.

pB: The other thing, or empty to pin pA to the world.

pX: The x of the hinge point; empty means the centre of pA.

pY: The y of the hinge point; empty means the centre of pA.

pZ: The z of the hinge point; empty means the centre of pA.

pAx: The x of the axis it turns about.

pAy: The y of the axis.

pAz: The z of the axis. An axis left empty or all zeros is 0, 0, 1: the
hinge then turns in the x-y plane, the way the starting camera looks.

Returns: (through the result) the joint, or empty when either thing is
missing or Box3D refused it (<b3kLastError> says why).

Example:
b3kSpawnBox 1, 3, 0, 2, 0.2, 1, "brown"
put the result into tDoor
b3kHinge tDoor, empty, 0, 3, 0, 0, 1, 0   -- a door turning about y at x = 0
put the result into tHinge
b3kHingeLimit tHinge, -90, 90

Description:
The two stay together at the point and turn only about the axis: a door,
a wheel on an axle, a see-saw, a pendulum. <b3kMotor> drives it,
<b3kHingeLimit> stops it, <b3kHingeAngle> reads it.

References: b3kMotor (handler), b3kHingeLimit (handler), b3kHingeAngle (handler), b3kRemoveJoint (handler)
*/
command b3kHinge pA, pB, pX, pY, pZ, pAx, pAy, pAz
   local tPair, tPos, tAx, tAy, tAz
   put b3kJointPair(pA, pB) into tPair
   if tPair is empty then return empty
   set the itemDelimiter to comma
   put b3BodyPosition(pA) into tPos
   put b3kNum(pAx, 0) into tAx
   put b3kNum(pAy, 0) into tAy
   put b3kNum(pAz, 0) into tAz
   if tAx = 0 and tAy = 0 and tAz = 0 then put 1 into tAz
   return b3kJointMade(b3JointRevolute(sWorld, item 1 of tPair, item 2 of tPair, \
         b3kNum(pX, item 1 of tPos), b3kNum(pY, item 2 of tPos), b3kNum(pZ, item 3 of tPos), \
         tAx, tAy, tAz, false))
end b3kHinge

/**
Summary: Join two things with a ball and socket, or hang one from the world.

pA: The thing that swings.

pB: The other thing, or empty to hang pA from the world.

pX: The x of the socket; empty means the centre of pA.

pY: The y of the socket; empty means the centre of pA.

pZ: The z of the socket; empty means the centre of pA.

Returns: (through the result) the joint, or empty when either thing is
missing or Box3D refused it.

Example:
b3kSpawnBall 0, 2, 0, 0.6, "red"
put the result into tBob
b3kBallJoint tBob, empty, 0, 5, 0   -- swings round a point 3 m above it

Description:
The two stay together at the point and turn freely about it, every way: a
shoulder, a chain link, a pendulum that can swing in a circle.

References: b3kHinge (handler), b3kRope (handler), b3kRemoveJoint (handler)
*/
command b3kBallJoint pA, pB, pX, pY, pZ
   local tPair, tPos
   put b3kJointPair(pA, pB) into tPair
   if tPair is empty then return empty
   set the itemDelimiter to comma
   put b3BodyPosition(pA) into tPos
   return b3kJointMade(b3JointSpherical(sWorld, item 1 of tPair, item 2 of tPair, \
         b3kNum(pX, item 1 of tPos), b3kNum(pY, item 2 of tPos), b3kNum(pZ, item 3 of tPos), \
         0, 1, 0, false))
end b3kBallJoint

/**
Summary: Glue two things together, or one to the world where it is.

pA: A thing.

pB: The thing to glue to it, or empty to fix pA in place.

Returns: (through the result) the joint, or empty when either thing is
missing or Box3D refused it.

Example:
b3kWeld tCart, tCrate

Description:
The two keep the places and turns they had when welded and move as one.
<b3kRemoveJoint> breaks the weld.

References: b3kRemoveJoint (handler), b3kHinge (handler)
*/
command b3kWeld pA, pB
   local tPair, tPos
   put b3kJointPair(pA, pB) into tPair
   if tPair is empty then return empty
   set the itemDelimiter to comma
   put b3BodyPosition(item 2 of tPair) into tPos
   return b3kJointMade(b3JointWeld(sWorld, item 1 of tPair, item 2 of tPair, \
         item 1 of tPos, item 2 of tPos, item 3 of tPos, false))
end b3kWeld

/**
Summary: Tie two things together with a rope from centre to centre.

pA: A thing.

pB: The other thing.

pLength: The rope's length in metres; empty means the distance between them now.

Returns: (through the result) the joint, or empty when either thing is
missing or Box3D refused it.

Example:
b3kAddStaticBox 0, 6, 0, 0.4, 0.4, 0.4
put the result into tHook
b3kSpawnBall 1, 4, 0, 0.5
put the result into tBob
b3kRope tHook, tBob, 3

Description:
A rope goes slack when the two come closer and stops them going further
apart than its length. To hang something from the world, tie it to a
static thing (<b3kAddStaticBox>).

References: b3kBallJoint (handler), b3kRemoveJoint (handler)
*/
command b3kRope pA, pB, pLength
   local tPA, tPB, tDx, tDy, tDz, tLen, tJ
   if pB is empty then return empty
   if b3kJointPair(pA, pB) is empty then return empty
   set the itemDelimiter to comma
   put b3BodyPosition(pA) into tPA
   put b3BodyPosition(pB) into tPB
   put item 1 of tPB - item 1 of tPA into tDx
   put item 2 of tPB - item 2 of tPA into tDy
   put item 3 of tPB - item 3 of tPA into tDz
   put max(0.05, b3kNum(pLength, sqrt(tDx * tDx + tDy * tDy + tDz * tDz))) into tLen
   put b3kJointMade(b3JointDistance(sWorld, pA, pB, item 1 of tPA, item 2 of tPA, item 3 of tPA, \
         item 1 of tPB, item 2 of tPB, item 3 of tPB, false)) into tJ
   if tJ is empty then return empty
   -- a spring of no stiffness and a length range: slack inside, taut at
   -- the top. Without the spring the joint holds the length both ways (a rod).
   b3DistanceSetLength tJ, tLen
   b3DistanceEnableSpring tJ, true
   b3DistanceSetSpringHertz tJ, 0
   b3DistanceSetLengthRange tJ, 0.05, tLen
   b3DistanceEnableLimit tJ, true
   return tJ
end b3kRope

/**
Summary: Let a thing slide along a line, against another thing or the world.

pA: The thing that slides.

pB: The other thing, or empty to slide pA against the world.

pAx: The x of the direction it slides.

pAy: The y of the direction.

pAz: The z of the direction. All empty or zero means straight up and down (0, 1, 0).

Returns: (through the result) the joint, or empty when either thing is
missing or Box3D refused it.

Example:
b3kSpawnBox 0, 1, 0, 2, 0.3, 2, "teal"
put the result into tLift
b3kSlider tLift, empty, 0, 1, 0
put the result into tRail
b3kHingeLimit tRail, 0, 4      -- metres, for a slider
b3kMotor tRail, 1, 500         -- one metre a second, upwards

Description:
The thing keeps its turn and moves only along the line through where it
is now: a lift, a piston, a drawer. <b3kMotor> drives it (metres a
second), <b3kHingeLimit> stops it (metres) and <b3kHingeAngle> reads how
far it has gone.

References: b3kMotor (handler), b3kHingeLimit (handler), b3kHingeAngle (handler)
*/
command b3kSlider pA, pB, pAx, pAy, pAz
   local tPair, tPos, tAx, tAy, tAz
   put b3kJointPair(pA, pB) into tPair
   if tPair is empty then return empty
   set the itemDelimiter to comma
   put b3BodyPosition(item 2 of tPair) into tPos
   put b3kNum(pAx, 0) into tAx
   put b3kNum(pAy, 0) into tAy
   put b3kNum(pAz, 0) into tAz
   if tAx = 0 and tAy = 0 and tAz = 0 then put 1 into tAy
   return b3kJointMade(b3JointPrismatic(sWorld, item 1 of tPair, item 2 of tPair, \
         item 1 of tPos, item 2 of tPos, item 3 of tPos, tAx, tAy, tAz, false))
end b3kSlider

/**
Summary: Drive a hinge or a slider at a steady speed, or stop driving it.

pJoint: A joint from <b3kHinge> or <b3kSlider>.

pSpeed: Degrees a second for a hinge, metres a second for a slider; empty
turns the motor off. 0 holds it still, as a brake.

pMax: The most torque (newton metres) or force (newtons) it may use;
empty means 100, plenty for the Kit's things (a 1 m box weighs 1 kg).

Example:
b3kMotor tWheel, 360          -- one turn a second
b3kMotor tWheel, empty        -- free again

Description:
The motor pushes as hard as it may to keep the speed, so a weak motor
stalls under a load and a strong one does not. Give it no more than the
job needs, because a limit is a little soft and a motor far stronger than
the thing it turns pushes it some way past the limit. Other joints
ignore it.

References: b3kHinge (handler), b3kSlider (handler), b3kHingeLimit (handler)
*/
command b3kMotor pJoint, pSpeed, pMax
   local tOn, tMax
   if not b3kJointOk(pJoint) then exit b3kMotor
   put (pSpeed is a number) into tOn
   put max(0, b3kNum(pMax, 100)) into tMax
   switch b3JointType(pJoint)
      case 5
         b3RevoluteEnableMotor pJoint, tOn
         if tOn then
            b3RevoluteSetMotorSpeed pJoint, pSpeed * pi / 180
            b3RevoluteSetMaxMotorTorque pJoint, tMax
         end if
         break
      case 4
         b3PrismaticEnableMotor pJoint, tOn
         if tOn then
            b3PrismaticSetMotorSpeed pJoint, pSpeed
            b3PrismaticSetMaxMotorForce pJoint, tMax
         end if
         break
   end switch
   b3JointWakeBodies pJoint
end b3kMotor

/**
Summary: Stop a hinge or a slider at two ends, or let it go free.

pJoint: A joint from <b3kHinge> or <b3kSlider>.

pLow: The lowest angle in degrees (hinge) or position in metres (slider).

pHigh: The highest. Both empty take the limit off.

Example:
b3kHingeLimit tDoor, -90, 90
b3kHingeLimit tLift, 0, 4

Description:
Angles and positions count from where the two were when the joint was
made. Swapped ends are put in order. Other joints ignore it.

References: b3kHingeAngle (handler), b3kMotor (handler)
*/
command b3kHingeLimit pJoint, pLow, pHigh
   local tOn, tLo, tHi
   if not b3kJointOk(pJoint) then exit b3kHingeLimit
   put (pLow is a number or pHigh is a number) into tOn
   put b3kNum(pLow, 0) into tLo
   put b3kNum(pHigh, 0) into tHi
   if tHi < tLo then
      put tLo into tHi
      put b3kNum(pHigh, 0) into tLo
   end if
   switch b3JointType(pJoint)
      case 5
         if tOn then b3RevoluteSetLimits pJoint, tLo * pi / 180, tHi * pi / 180
         b3RevoluteEnableLimit pJoint, tOn
         break
      case 4
         if tOn then b3PrismaticSetLimits pJoint, tLo, tHi
         b3PrismaticEnableLimit pJoint, tOn
         break
   end switch
   b3JointWakeBodies pJoint
end b3kHingeLimit

/**
Summary: How far a hinge has turned, or a slider has slid.

pJoint: A joint from <b3kHinge> or <b3kSlider>.

Returns: Degrees for a hinge, metres for a slider, counted from where the
two were when it was made; 0 for any other joint or no joint.

Example:
put round(b3kHingeAngle(tDoor)) into field "Door"

References: b3kHingeLimit (handler), b3kHinge (handler), b3kSlider (handler)
*/
function b3kHingeAngle pJoint
   if not b3kJointOk(pJoint) then return 0
   switch b3JointType(pJoint)
      case 5
         return b3RevoluteAngle(pJoint) * 180 / pi
      case 4
         return b3PrismaticTranslation(pJoint)
   end switch
   return 0
end b3kHingeAngle

/**
Summary: Take a joint away.

pJoint: A joint from any of the Kit's joint commands, or from <b3kNoCollide>.

Example:
b3kRemoveJoint tWeld

Description:
The two things are woken and go their own ways. A joint that is already
gone (its thing was removed, say) is ignored.

References: b3kHinge (handler), b3kWeld (handler)
*/
command b3kRemoveJoint pJoint
   if not b3kJointOk(pJoint) then exit b3kRemoveJoint
   b3JointDestroy pJoint, true
end b3kRemoveJoint

/**
Summary: Stop two things colliding with each other.

pA: A thing.

pB: Another thing.

Returns: (through the result) a joint that holds the rule; remove it with
<b3kRemoveJoint>. Empty when either thing is missing.

Example:
b3kNoCollide tCar, tDriver

Description:
Everything else still collides with both. Taking the rule away does not
push two things apart that already overlap: they meet again once one of
them moves away and back.

References: b3kRemoveJoint (handler)
*/
command b3kNoCollide pA, pB
   if pB is empty then return empty
   if b3kJointPair(pA, pB) is empty then return empty
   return b3kJointMade(b3JointFilter(sWorld, pA, pB))
end b3kNoCollide

-- =====================================================================
-- Input (keyboard): one sample of the keys held, once a frame
-- =====================================================================
-- The b2k Kit's model, proven there (box2dxt CLAUDE.md, spike S1 and S2):
-- one `the keysDown` sample per frame, compared with the frame before.
-- Held = in this frame's set; pressed and released = the difference. No key
-- messages are used at all, so auto-repeat, focus and frontscripts cannot
-- get in the way. Letters bind BOTH cases ("w" is 119 and 87): the code a
-- letter reports changes with the Shift key.

/**
Summary: Start reading the keyboard once a frame.

Example:
b3kInputOn
if b3kKeyIsDown("space") then put "jumping" into field "State"

Description:
Each frame the loop reads the keys held down and compares them with the
frame before, so the key, action and axis questions answer from b3kFrame.
It needs no focus and no key messages.

It also fills empty bindings: action "jump" (space), axis "moveX" (left, a
then right, d), axis "moveY" (down, s then up, w) and axis "turn" (q then
e), which turns the camera. Bindings you made are kept.
<b3kPlayerAttach> turns input on for you.

References: b3kInputOff (handler), b3kKeyIsDown (handler), b3kBindAction (handler), b3kAxis (handler)
*/
command b3kInputOn
   put true into sInputOn
   put comma into sKeysNow
   put comma into sKeysPrev
   if sKeyActions["jump"] is empty then b3kBindAction "jump", "space"
   if sAxisNeg["moveX"] is empty then b3kBindAxis "moveX", "left,a", "right,d"
   if sAxisNeg["moveY"] is empty then b3kBindAxis "moveY", "down,s", "up,w"
   if sAxisNeg["turn"] is empty then b3kBindAxis "turn", "q", "e"
end b3kInputOn

/**
Summary: Stop reading the keyboard.

Example:
b3kInputOff

Description:
Every key reads as up afterwards. Bindings are kept.

References: b3kInputOn (handler), b3kInputIsOn (handler)
*/
command b3kInputOff
   put false into sInputOn
   put comma into sKeysNow
   put comma into sKeysPrev
end b3kInputOff

/**
Summary: Report whether the keyboard is being read.

Returns: true or false.

Example:
if not b3kInputIsOn() then b3kInputOn

References: b3kInputOn (handler)
*/
function b3kInputIsOn
   return (sInputOn is true)
end b3kInputIsOn

-- once a frame, first thing: the sets are stored wrapped in commas
-- (",65361,32,") so a key is one `contains` test
private command b3kInputTick
   if sInputOn is not true then exit b3kInputTick
   put sKeysNow into sKeysPrev
   if sInjectOn is true then
      put comma & sInjectKeys & comma into sKeysNow
   else
      put comma & the keysDown & comma into sKeysNow
   end if
end b3kInputTick

/**
Summary: Hold keys from script instead of the keyboard.

pKeys: Key names or codes, separated by commas; empty holds none.

Example:
b3kInputInject "up,space"   -- forward and jump
b3kStepOnce

Description:
Until <b3kInputInjectOff>, each frame reads this set instead of the
keyboard, and pressed and released come from the usual comparison. For
tests, replays and characters your script plays.

References: b3kInputInjectOff (handler), b3kInputOn (handler)
*/
command b3kInputInject pKeys
   put true into sInjectOn
   put b3kKeyListCodes(pKeys) into sInjectKeys
end b3kInputInject

/**
Summary: Go back to the real keyboard.

Example:
b3kInputInjectOff

References: b3kInputInject (handler)
*/
command b3kInputInjectOff
   put false into sInjectOn
   put empty into sInjectKeys
end b3kInputInjectOff

-- a key name or code -> the codes it matches, separated by commas
private function b3kKeyCodes pKey
   local tLower, tUpper
   if pKey is a number and pKey >= 32 then return pKey
   switch pKey
      case "left"
         return 65361
      case "up"
         return 65362
      case "right"
         return 65363
      case "down"
         return 65364
      case "space"
         return 32
      case "return"
      case "enter"
         return "65293,65421"
      case "escape"
      case "esc"
         return 65307
      case "tab"
         return 65289
      case "shift"
         return "65505,65506"
      case "control"
      case "ctrl"
         return "65507,65508"
      case "alt"
      case "option"
         return "65513,65514"
      case "backspace"
         return 65288
      case "delete"
         return 65535
   end switch
   if the number of chars of pKey is 1 then
      put charToNum(toLower(pKey)) into tLower
      put charToNum(toUpper(pKey)) into tUpper
      if tLower >= 97 and tLower <= 122 then return tLower & comma & tUpper
      return charToNum(pKey)
   end if
   return 0
end b3kKeyCodes

-- a code -> its friendly name, for b3kKeysHeld
private function b3kKeyName pCode
   switch pCode
      case 65361
         return "left"
      case 65362
         return "up"
      case 65363
         return "right"
      case 65364
         return "down"
      case 32
         return "space"
      case 65293
      case 65421
         return "return"
      case 65307
         return "escape"
      case 65289
         return "tab"
      case 65505
      case 65506
         return "shift"
      case 65507
      case 65508
         return "control"
      case 65513
      case 65514
         return "alt"
      case 65288
         return "backspace"
      case 65535
         return "delete"
   end switch
   if pCode >= 97 and pCode <= 122 then return numToChar(pCode)
   if pCode >= 65 and pCode <= 90 then return numToChar(pCode + 32)
   if pCode >= 48 and pCode <= 57 then return numToChar(pCode)
   return pCode
end b3kKeyName

-- a list of key names -> every code they match; resolved once, at bind time
private function b3kKeyListCodes pKeyList
   local tKey, tOut
   put empty into tOut
   set the itemDelimiter to comma
   repeat for each item tKey in pKeyList
      if tOut is empty then
         put b3kKeyCodes(word 1 of tKey) into tOut
      else
         put comma & b3kKeyCodes(word 1 of tKey) after tOut
      end if
   end repeat
   return tOut
end b3kKeyListCodes

-- is any of these codes in a comma-wrapped set?
private function b3kCodesInSet pSet, pCodes
   local tCode
   if pSet is empty or pSet is comma then return false
   set the itemDelimiter to comma
   repeat for each item tCode in pCodes
      if pSet contains (comma & tCode & comma) then return true
   end repeat
   return false
end b3kCodesInSet

/**
Summary: Report whether a key is held this frame.

pKey: A key name (left, right, up, down, space, return, escape, tab,
shift, control, alt, backspace, delete), one character, or a key code.

Returns: true or false.

Example:
if b3kKeyIsDown("shift") then b3kPlayerSet "moveSpeed", 9

Description:
Needs <b3kInputOn>; ask it in b3kFrame.

References: b3kKeyPressed (handler), b3kKeyReleased (handler), b3kInputOn (handler)
*/
function b3kKeyIsDown pKey
   return b3kCodesInSet(sKeysNow, b3kKeyCodes(pKey))
end b3kKeyIsDown

/**
Summary: Report whether a key went down this frame.

pKey: A key name, one character, or a key code.

Returns: true only on the frame the key went down.

Example:
if b3kKeyPressed("r") then b3kPlayerRespawn 0, 2, 0

References: b3kKeyIsDown (handler), b3kKeyReleased (handler)
*/
function b3kKeyPressed pKey
   local tCodes
   put b3kKeyCodes(pKey) into tCodes
   if not b3kCodesInSet(sKeysNow, tCodes) then return false
   return not b3kCodesInSet(sKeysPrev, tCodes)
end b3kKeyPressed

/**
Summary: Report whether a key came up this frame.

pKey: A key name, one character, or a key code.

Returns: true only on the frame the key came up.

Example:
if b3kKeyReleased("space") then put false into tCharging

References: b3kKeyIsDown (handler), b3kKeyPressed (handler)
*/
function b3kKeyReleased pKey
   local tCodes
   put b3kKeyCodes(pKey) into tCodes
   if not b3kCodesInSet(sKeysPrev, tCodes) then return false
   return not b3kCodesInSet(sKeysNow, tCodes)
end b3kKeyReleased

/**
Summary: Every key held this frame, by name.

Returns: The names separated by spaces, or empty.

Example:
put b3kKeysHeld() into field "Keys"

References: b3kKeyIsDown (handler)
*/
function b3kKeysHeld
   local tOut, tCode
   put empty into tOut
   set the itemDelimiter to comma
   repeat for each item tCode in char 2 to -2 of sKeysNow
      put b3kKeyName(tCode) & space after tOut
   end repeat
   return word 1 to -1 of tOut
end b3kKeysHeld

/**
Summary: Name a set of keys as one action.

pName: The action's name, such as "fire".

pKeyList: Key names separated by commas, such as "x,control".

Example:
b3kBindAction "fire", "x,control"
if b3kActionPressed("fire") then b3kPush tCannonBall, 0, 0, -20

Description:
Any of the keys counts, and pressed and released treat the set as one
key. The names are turned into key codes once, here.

References: b3kActionIsDown (handler), b3kActionPressed (handler), b3kBindAxis (handler)
*/
command b3kBindAction pName, pKeyList
   put pKeyList into sKeyActions[pName]
   put b3kKeyListCodes(pKeyList) into sKeyActionsC[pName]
end b3kBindAction

/**
Summary: Report whether any key of an action is held.

pName: The action's name.

Returns: true or false; false for an action never bound.

Example:
if b3kActionIsDown("fire") then add b3kFrameMS() to tCharge

References: b3kBindAction (handler), b3kActionPressed (handler)
*/
function b3kActionIsDown pName
   return b3kCodesInSet(sKeysNow, sKeyActionsC[pName])
end b3kActionIsDown

/**
Summary: Report whether an action started this frame.

pName: The action's name.

Returns: true on the frame the first of its keys went down.

Example:
if b3kActionPressed("jump") then put "up!" into field "Log"

References: b3kBindAction (handler), b3kActionReleased (handler)
*/
function b3kActionPressed pName
   if not b3kCodesInSet(sKeysNow, sKeyActionsC[pName]) then return false
   return not b3kCodesInSet(sKeysPrev, sKeyActionsC[pName])
end b3kActionPressed

/**
Summary: Report whether an action ended this frame.

pName: The action's name.

Returns: true on the frame the last of its keys came up.

Example:
if b3kActionReleased("fire") then b3kPush tBall, 0, tCharge / 100, -10

References: b3kBindAction (handler), b3kActionPressed (handler)
*/
function b3kActionReleased pName
   if not b3kCodesInSet(sKeysPrev, sKeyActionsC[pName]) then return false
   return not b3kCodesInSet(sKeysNow, sKeyActionsC[pName])
end b3kActionReleased

/**
Summary: Make a -1, 0, +1 axis from two sets of keys.

pName: The axis's name, such as "moveX".

pNegKeys: The keys for -1, separated by commas.

pPosKeys: The keys for +1.

Example:
b3kBindAxis "moveY", "down,s", "up,w"

Description:
The player walks on "moveX" (sideways) and "moveY" (forward), and the
camera turns on "turn". Rebind them to change the keys.

References: b3kAxis (handler), b3kBindAction (handler)
*/
command b3kBindAxis pName, pNegKeys, pPosKeys
   put pNegKeys into sAxisNeg[pName]
   put pPosKeys into sAxisPos[pName]
   put b3kKeyListCodes(pNegKeys) into sAxisNegC[pName]
   put b3kKeyListCodes(pPosKeys) into sAxisPosC[pName]
end b3kBindAxis

/**
Summary: Read an axis.

pName: The axis's name.

Returns: -1, 0 or 1. Both ends held, or neither, is 0.

Example:
b3kSetSpin tTurret, 0, b3kAxis("aim") * 90, 0

References: b3kBindAxis (handler)
*/
function b3kAxis pName
   local tNeg, tPos
   put b3kCodesInSet(sKeysNow, sAxisNegC[pName]) into tNeg
   put b3kCodesInSet(sKeysNow, sAxisPosC[pName]) into tPos
   if tPos and not tNeg then return 1
   if tNeg and not tPos then return -1
   return 0
end b3kAxis

-- =====================================================================
-- The player: one character the keys steer, relative to the camera
-- =====================================================================
-- One player at a time (flat sPlay* locals, as in the b2k Kit). Each frame,
-- before the physics steps: a sphere is swept a little way down from inside
-- the feet to find the ground (the player's own shape wears kB3kPlayerBit
-- and the sweep's filter leaves that bit out, so the sweep cannot hit the
-- player); then the horizontal velocity is steered toward where the keys
-- point, seen from the camera, at most `accel` (or `airAccel`) m/s^2. Gravity
-- and the solver own the vertical, except a jump. Coyote time and the jump
-- buffer run on the SIMULATION clock (steps x 1/60 s), so a pause or a
-- stalled frame never eats them, and a hand-stepped test is exact.

/**
Summary: Make a player in one call: a thing the keys walk about.

pX: The x where it stands.

pY: The y of its centre.

pZ: The z where it stands.

pKind: "capsule" (1.6 m tall, the default), "ball" (a 0.8 m ball that
rolls) or "box" (0.7 by 1.4 by 0.7 m).

pColor: A colour; empty takes the next palette colour.

Returns: (through the result) the player's thing, or empty when there is
no world.

Example:
b3kQuickStart
b3kPlayerMake 0, 1, 0
put the result into tHero

Description:
It spawns the shape, makes it the player with <b3kPlayerAttach> and points
the camera at it with <b3kCamFollow>. Arrows or WASD walk, space jumps,
Q and E turn the camera; forward is away from the camera.

References: b3kPlayerAttach (handler), b3kPlayerSet (handler), b3kPlayer (handler)
*/
command b3kPlayerMake pX, pY, pZ, pKind, pColor
   local tThing
   if sWorld is empty then return empty
   switch pKind
      case "ball"
         b3kSpawnBall pX, pY, pZ, 0.8, pColor
         put the result into tThing
         break
      case "box"
         b3kSpawnBox pX, pY, pZ, 0.7, 1.4, 0.7, pColor
         put the result into tThing
         break
      default
         b3kSpawnCapsule pX, pY, pZ, 1.6, 0.6, pColor
         put the result into tThing
   end switch
   if tThing is empty then return empty
   b3kPlayerAttach tThing
   b3kCamFollow tThing
   return tThing
end b3kPlayerMake

/**
Summary: Make a thing you already have the player.

pThing: A moving (dynamic) thing.

pMode: "walk" keeps it upright and turns it to face where it goes; "roll"
leaves it free to roll. Empty means roll for a ball, walk for the rest.

Returns: (through the result) the thing, or empty when it is not a moving thing.

Example:
b3kSpawnCylinder 0, 1, 0, 1.2, 0.8, "gold"
put the result into tRobot
b3kPlayerAttach tRobot

Description:
The thing stops bouncing, never falls asleep and, walking, slides on
walls (friction 0.2) and cannot tip over. Input is turned on. There is
one player, so attaching another lets the first go, as <b3kPlayerRemove>
would.

References: b3kPlayerMake (handler), b3kPlayerRemove (handler), b3kPlayerSet (handler)
*/
command b3kPlayerAttach pThing, pMode
   local tShape, tD
   if sWorld is empty then return empty
   if sKind[pThing] is empty then return empty
   if b3BodyType(pThing) is not 2 then return empty
   if sPlayer is not empty and sPlayer is not pThing then b3kPlayerRelease
   if pMode is empty then
      if sGeo[pThing] is "ball" then
         put "roll" into pMode
      else
         put "walk" into pMode
      end if
   end if
   if pMode is not "roll" then put "walk" into pMode
   put sShape[pThing] into tShape
   if sPlayer is not pThing then
      put b3ShapeFriction(tShape) & comma & b3ShapeRestitution(tShape) into sPlayOld
   end if
   put pThing into sPlayer
   put pMode into sPlayKind
   -- the player's own category, so the ground sweep can look past it
   b3ShapeSetFilter tShape, kB3kPlayerBit, kB3kAllBits, 0
   b3ShapeSetRestitution tShape, 0
   if pMode is "walk" then
      b3ShapeSetFriction tShape, 0.2
      b3BodySetMotionLocks pThing, false, false, false, true, true, true
      b3BodySetAngularVelocity pThing, 0, 0, 0
   else
      b3BodySetMotionLocks pThing, false, false, false, false, false, false
   end if
   b3BodyEnableSleep pThing, false
   b3BodySetAwake pThing, true
   -- how far the feet are below the centre, and the sweep's radius
   set the itemDelimiter to comma
   put sDims[pThing] into tD
   switch sGeo[pThing]
      case "capsule"
         put item 1 of tD + item 2 of tD into sPlayHalf
         put item 1 of tD * 0.9 into sPlayRadius
         break
      case "ball"
         put item 1 of tD into sPlayHalf
         put item 1 of tD * 0.9 into sPlayRadius
         break
      case "cylinder"
         put item 2 of tD into sPlayHalf
         put item 1 of tD * 0.9 into sPlayRadius
         break
      case "box"
         put item 2 of tD into sPlayHalf
         put min(item 1 of tD, item 3 of tD) * 0.9 into sPlayRadius
         break
      default
         put b3BodyAABB(pThing) into tD
         put b3BodyY(pThing) - item 2 of tD into sPlayHalf
         put min(item 4 of tD - item 1 of tD, item 6 of tD - item 3 of tD) * 0.45 into sPlayRadius
   end switch
   put max(0.02, min(sPlayRadius, sPlayHalf * 0.9)) into sPlayRadius
   put b3kYaw(pThing) into sPlayFacing
   b3kPlayerForget false
   put pThing into sPlayer
   put true into sPlayCtl
   if sInputOn is not true then b3kInputOn
   b3kPlayerTune
   return pThing
end b3kPlayerAttach

-- let the player's thing go: its filter, sleep, turning and material back
private command b3kPlayerRelease
   local tShape
   if sPlayer is empty then exit b3kPlayerRelease
   if sKind[sPlayer] is not empty then
      put sShape[sPlayer] into tShape
      b3ShapeSetFilter tShape, kB3kAllBits, kB3kAllBits, 0
      if sPlayOld is not empty then
         set the itemDelimiter to comma
         b3ShapeSetFriction tShape, item 1 of sPlayOld
         b3ShapeSetRestitution tShape, item 2 of sPlayOld
      end if
      b3BodySetMotionLocks sPlayer, false, false, false, false, false, false
      b3BodyEnableSleep sPlayer, true
   end if
   put empty into sPlayOld
   b3kPlayerForget false
end b3kPlayerRelease

-- drop the controller's state; pFull drops the knobs too (b3kClear keeps
-- them, like key bindings; teardown and b3kPlayerRemove do not)
private command b3kPlayerForget pFull
   put empty into sPlayer
   put false into sPlayGround
   put empty into sPlayGroundAt
   put empty into sPlayJumpAt
   put empty into sPlayWantAt
   put empty into sPlayOn
   put true into sPlayCut
   put 0 into sPlayAirLeft
   put empty into sPlaySteer
   if pFull is true then
      put empty into sPlay
      b3kPlayerTune
   end if
end b3kPlayerForget

/**
Summary: Let the player go: the thing stays, the keys stop steering it.

Example:
b3kPlayerRemove

Description:
The thing gets back its material, its turning and its sleep, and the
knobs go back to their defaults. Remove the thing itself with <b3kRemove>.

References: b3kPlayerAttach (handler), b3kRemove (handler)
*/
command b3kPlayerRemove
   b3kPlayerRelease
   b3kPlayerForget true
end b3kPlayerRemove

/**
Summary: Set one of the player's knobs.

pKey: The knob (case does not matter): moveSpeed, accel, airAccel,
jumpSpeed, jumpCut, airJumps, coyoteMs, bufferMs, maxSlopeDeg, turnSpeed,
maxFall or carry. Any other name is kept for your own use.

pValue: The new value; empty puts the default back.

Example:
b3kPlayerSet "moveSpeed", 7
b3kPlayerSet "airJumps", 1     -- a double jump

Description:
The defaults: moveSpeed 5 (metres a second), accel 40 and airAccel 12
(m/s^2 toward the wanted speed, on the ground and in the air), jumpSpeed
5.5 (m/s up: about 1.5 m high), jumpCut 0.5 (rising speed kept when jump
is let go early; 1 = always full height), airJumps 0, coyoteMs 120 (a jump
still counts this long after walking off an edge), bufferMs 120 (a jump
pressed this long before landing still happens), maxSlopeDeg 50 (steeper
is a wall, not ground), turnSpeed 720 (degrees a second the player turns
to face its way), maxFall 40 (m/s) and carry 1 (ride moving platforms; 0
not). A change takes effect from the next frame. <b3kClear> keeps the
knobs; <b3kTeardown> and <b3kPlayerRemove> put the defaults back.

References: b3kPlayerGet (handler), b3kPlayerMake (handler)
*/
command b3kPlayerSet pKey, pValue
   put pValue into sPlay[toLower(pKey)]
   b3kPlayerTune
end b3kPlayerSet

/**
Summary: Read one of the player's knobs.

pKey: The knob's name (case does not matter).

Returns: Its value, or its default when it was never set. A knob of the
controller set to something not a number reads as its default.

Example:
put b3kPlayerGet("jumpSpeed") into tJump

References: b3kPlayerSet (handler)
*/
function b3kPlayerGet pKey
   local tDefault
   put toLower(pKey) into pKey
   put b3kPlayerDefault(pKey) into tDefault
   if sPlay[pKey] is empty then return tDefault
   if tDefault is empty then return sPlay[pKey]
   return b3kNum(sPlay[pKey], tDefault)
end b3kPlayerGet

-- the shipped defaults, for a 1.6 m player in metres and seconds
private function b3kPlayerDefault pKey
   switch pKey
      case "movespeed"
         return 5
      case "accel"
         return 40
      case "airaccel"
         return 12
      case "jumpspeed"
         return 5.5
      case "jumpcut"
         return 0.5
      case "airjumps"
         return 0
      case "coyotems"
         return 120
      case "bufferms"
         return 120
      case "maxslopedeg"
         return 50
      case "turnspeed"
         return 720
      case "maxfall"
         return 40
      case "carry"
         return 1
   end switch
   return empty
end b3kPlayerDefault

-- the knobs, resolved once per change: the tick reads them every frame
private command b3kPlayerTune
   local tKey
   repeat for each item tKey in "movespeed,accel,airaccel,jumpspeed,jumpcut,airjumps,coyotems,bufferms,turnspeed,maxfall,carry"
      put b3kPlayerGet(tKey) into sPlayT[tKey]
   end repeat
   put cos(b3kPlayerGet("maxSlopeDeg") * pi / 180) into sPlayT["cosslope"]
end b3kPlayerTune

/**
Summary: The player's thing.

Returns: The thing, or empty when there is no player.

Example:
-- in your b3kContact pA, pB handler:
if pA is b3kPlayer() or pB is b3kPlayer() then add 1 to tBumps

References: b3kPlayerMake (handler), b3kPlayerAttach (handler)
*/
function b3kPlayer
   return sPlayer
end b3kPlayer

/**
Summary: Report whether the player stands on something.

Returns: true when ground (anything no steeper than maxSlopeDeg) is
under its feet this frame.

Example:
if not b3kPlayerOnGround() then put "in the air" into field "State"

References: b3kPlayerJump (handler), b3kPlayerSet (handler)
*/
function b3kPlayerOnGround
   return (sPlayGround is true)
end b3kPlayerOnGround

/**
Summary: Which way the player faces.

Returns: Degrees round the vertical: 0 faces +z, 90 faces +x.

Example:
put b3kPlayerFacing() into tYaw

Description:
A walking player turns to face the way it goes; a rolling one keeps the
way it last went.

References: b3kYaw (handler), b3kPlayerMake (handler)
*/
function b3kPlayerFacing
   return b3kNum(sPlayFacing, 0)
end b3kPlayerFacing

/**
Summary: Make the player jump, whether or not it stands on anything.

pSpeed: The upward speed in m/s; empty means the jumpSpeed knob.

Example:
-- in your b3kSensorEnter pSensor, pVisitor handler: a spring pad
if pSensor is tSpring and pVisitor is b3kPlayer() then b3kPlayerJump 12

Description:
For springs, trampolines and power-ups: your script decides when it is
allowed. Letting go of jump does not cut it short.

References: b3kPlayerOnGround (handler), b3kPlayerSet (handler)
*/
command b3kPlayerJump pSpeed
   if sPlayer is empty then exit b3kPlayerJump
   if sKind[sPlayer] is empty then exit b3kPlayerJump
   b3kPlayerLaunch b3kNum(pSpeed, sPlayT["jumpspeed"])
   put true into sPlayCut
end b3kPlayerJump

-- the one way up: the speed, the jump's start for the ground sweep, and
-- the coyote window and any buffered press used up
private command b3kPlayerLaunch pSpeed
   local tV
   set the itemDelimiter to comma
   put b3BodyVelocity(sPlayer) into tV
   b3BodySetVelocity sPlayer, item 1 of tV, pSpeed, item 3 of tV
   put sFrames * kB3kStepMs into sPlayJumpAt
   put empty into sPlayGroundAt
   put empty into sPlayWantAt
   put false into sPlayGround
   put false into sPlayCut
end b3kPlayerLaunch

/**
Summary: Turn the keys' control of the player on or off.

pFlag: false to stop steering (for a cut scene); true to steer again.

Example:
b3kPlayerControl false
b3kGlideTo b3kPlayer(), 0, 1, -10, 3

Description:
While off, the player keeps its ground check and its fall limit but the
Kit writes nothing else to it.

References: b3kPlayerSteer (handler), b3kPlayerMake (handler)
*/
command b3kPlayerControl pFlag
   put (pFlag is not false) into sPlayCtl
end b3kPlayerControl

/**
Summary: Steer the player from script instead of the keys.

pX: Sideways, -1 (left) to 1 (right), as the camera sees it.

pY: Forward, -1 (toward the camera) to 1 (away). Both empty give the
keys back.

Example:
b3kPlayerSteer 0, 1           -- in a "forward" button's mouseDown
b3kPlayerSteer empty, empty   -- and in its mouseUp: the keys again

Description:
For on-screen buttons, touch screens and players your script drives. A
jump still comes from the jump action or <b3kPlayerJump>.

References: b3kPlayerControl (handler), b3kAxis (handler)
*/
command b3kPlayerSteer pX, pY
   if pX is empty and pY is empty then
      put empty into sPlaySteer
   else
      put max(-1, min(1, b3kNum(pX, 0))) & comma & max(-1, min(1, b3kNum(pY, 0))) into sPlaySteer
   end if
end b3kPlayerSteer

/**
Summary: Put the player somewhere, still, standing and ready.

pX: The new x; not a number keeps the current x.

pY: The new y of its centre; not a number keeps the current y.

pZ: The new z; not a number keeps the current z.

Example:
-- in your b3kFell pThing handler:
if pThing is b3kPlayer() then b3kPlayerRespawn 0, 2, 0

Description:
It stops, the jump in flight and any buffered jump are forgotten, the air
jumps are refilled and steering is on again.

References: b3kMoveTo (handler), b3kKillFloor (handler)
*/
command b3kPlayerRespawn pX, pY, pZ
   local tPos
   if sPlayer is empty then exit b3kPlayerRespawn
   if sKind[sPlayer] is empty then exit b3kPlayerRespawn
   set the itemDelimiter to comma
   put b3BodyPosition(sPlayer) into tPos
   b3kMoveTo sPlayer, b3kNum(pX, item 1 of tPos), b3kNum(pY, item 2 of tPos), b3kNum(pZ, item 3 of tPos)
   b3BodySetVelocity sPlayer, 0, 0, 0
   b3BodySetAngularVelocity sPlayer, 0, 0, 0
   put false into sPlayGround
   put empty into sPlayGroundAt
   put empty into sPlayJumpAt
   put empty into sPlayWantAt
   put true into sPlayCut
   put sPlayT["airjumps"] into sPlayAirLeft
   put true into sPlayCtl
end b3kPlayerRespawn

-- once a frame, before the physics steps
private command b3kPlayerTick
   local tNow, tV, tVx, tVy, tVz, tMx, tMy, tYaw, tDx, tDz, tLen
   local tTx, tTz, tC, tDt, tStep, tDvx, tDvz, tDvLen, tWant, tTurn, tQ, tPressed
   if sPlayer is empty then exit b3kPlayerTick
   if sKind[sPlayer] is empty then
      b3kPlayerForget false
      exit b3kPlayerTick
   end if
   put sFrames * kB3kStepMs into tNow
   set the itemDelimiter to comma
   put b3BodyVelocity(sPlayer) into tV
   put item 1 of tV into tVx
   put item 2 of tV into tVy
   put item 3 of tV into tVz
   b3kPlayerProbe tNow, tVy
   if sPlayGround is true then put sPlayT["airjumps"] into sPlayAirLeft
   put min(b3kNum(sFrameMS, kB3kStepMs), kB3kMaxSteps * kB3kStepMs) / 1000 into tDt
   if sPlayCtl is true then
      -- where the keys point, turned from the camera's view onto the ground:
      -- the camera's forward along the ground is (-sin yaw, -cos yaw), its
      -- right (cos yaw, -sin yaw)
      put 0 into tMx
      put 0 into tMy
      if sPlaySteer is not empty then
         put item 1 of sPlaySteer into tMx
         put item 2 of sPlaySteer into tMy
      else if sInputOn is true then
         put b3kAxis("moveX") into tMx
         put b3kAxis("moveY") into tMy
      end if
      put b3kNum(sCamYaw, 0) * pi / 180 into tYaw
      put tMx * cos(tYaw) - tMy * sin(tYaw) into tDx
      put 0 - tMx * sin(tYaw) - tMy * cos(tYaw) into tDz
      put sqrt(tDx * tDx + tDz * tDz) into tLen
      if tLen > 1 then
         divide tDx by tLen
         divide tDz by tLen
         put 1 into tLen
      end if
      put tDx * sPlayT["movespeed"] into tTx
      put tDz * sPlayT["movespeed"] into tTz
      -- riding: a moving platform's own speed is part of standing still
      if sPlayGround is true and sPlayT["carry"] is not 0 and sPlayOn is not empty then
         if b3BodyType(sPlayOn) is 1 then
            put b3BodyVelocity(sPlayOn) into tC
            add item 1 of tC to tTx
            add item 3 of tC to tTz
         end if
      end if
      -- steer the horizontal velocity toward the wanted one, no faster
      -- than the knob allows
      if sPlayGround is true then
         put sPlayT["accel"] * tDt into tStep
      else
         put sPlayT["airaccel"] * tDt into tStep
      end if
      put tTx - tVx into tDvx
      put tTz - tVz into tDvz
      put sqrt(tDvx * tDvx + tDvz * tDvz) into tDvLen
      if tDvLen > tStep and tDvLen > 0 then
         put tDvx * tStep / tDvLen into tDvx
         put tDvz * tStep / tDvLen into tDvz
      end if
      add tDvx to tVx
      add tDvz to tVz
      -- the jump: pressed now or buffered, from the ground or coyote time,
      -- or a fresh press spending an air jump
      put false into tPressed
      if sPlaySteer is empty and sInputOn is true then
         put b3kActionPressed("jump") into tPressed
      end if
      if tPressed then put tNow into sPlayWantAt
      if sPlayWantAt is not empty and tNow - sPlayWantAt <= sPlayT["bufferms"] then
         if sPlayGround is true then
            put sPlayT["jumpspeed"] into tVy
            b3kPlayerJumpState tNow
         else if sPlayGroundAt is not empty and tNow - sPlayGroundAt <= sPlayT["coyotems"] then
            put sPlayT["jumpspeed"] into tVy
            b3kPlayerJumpState tNow
         else if tPressed and sPlayAirLeft > 0 then
            subtract 1 from sPlayAirLeft
            put sPlayT["jumpspeed"] into tVy
            b3kPlayerJumpState tNow
         end if
      end if
      -- let go early, fall sooner
      if sPlayCut is not true then
         if tVy <= 0 then
            put true into sPlayCut
         else if not b3kActionIsDown("jump") then
            put tVy * sPlayT["jumpcut"] into tVy
            put true into sPlayCut
         end if
      end if
      -- face the way it goes, turning at most turnSpeed a second
      if tLen > 0.1 then
         put atan2(tDx, tDz) * 180 / pi into tWant
         put ((tWant - b3kNum(sPlayFacing, 0) + 540) mod 360) - 180 into tTurn
         put sPlayT["turnspeed"] * tDt into tStep
         if abs(tTurn) > tStep then
            if tTurn > 0 then
               put tStep into tTurn
            else
               put 0 - tStep into tTurn
            end if
         end if
         if tTurn is not 0 then
            put b3kNum(sPlayFacing, 0) + tTurn into sPlayFacing
            if sPlayFacing > 180 then subtract 360 from sPlayFacing
            if sPlayFacing <= -180 then add 360 to sPlayFacing
            if sPlayKind is "walk" then
               put b3kQuat(0, sPlayFacing, 0) into tQ
               b3BodySetRotation sPlayer, item 1 of tQ, item 2 of tQ, item 3 of tQ, item 4 of tQ
            end if
         end if
      end if
   end if
   if tVy < 0 - sPlayT["maxfall"] then put 0 - sPlayT["maxfall"] into tVy
   if sPlayCtl is true or tVy is not item 2 of tV then
      b3BodySetVelocity sPlayer, tVx, tVy, tVz
   end if
end b3kPlayerTick

-- the controller's own jump started now
private command b3kPlayerJumpState pNow
   put pNow into sPlayJumpAt
   put empty into sPlayGroundAt
   put empty into sPlayWantAt
   put false into sPlayGround
   put false into sPlayCut
end b3kPlayerJumpState

-- the ground under the feet: a sphere swept down from just inside them
private command b3kPlayerProbe pNow, pVy
   local tPos, tY, tCount, i, tBody, tNormal
   put false into sPlayGround
   put empty into sPlayOn
   -- the controller's own jump is still rising: the sweep would find the
   -- floor it just left and hand the jump back as coyote time
   if sPlayJumpAt is not empty and pNow - sPlayJumpAt < 250 and pVy > 0 then exit b3kPlayerProbe
   set the itemDelimiter to comma
   put b3BodyPosition(sPlayer) into tPos
   if tPos is empty then exit b3kPlayerProbe
   put item 2 of tPos - sPlayHalf + sPlayRadius + 0.02 into tY
   b3QuerySetFilter kB3kAllBits, kB3kNoPlayerBits
   put b3CastSphere(sWorld, item 1 of tPos, tY, item 3 of tPos, sPlayRadius, 0, -0.14, 0) into tCount
   b3QueryResetFilter
   repeat with i = 1 to tCount
      put b3HitBody(i) into tBody
      if tBody is sPlayer or sSensorOf[tBody] is true then next repeat
      put b3HitNormal(i) into tNormal
      if item 2 of tNormal >= sPlayT["cosslope"] then
         put true into sPlayGround
         put tBody into sPlayOn
         put pNow into sPlayGroundAt
         exit repeat
      end if
   end repeat
end b3kPlayerProbe
-- <<< END EMBEDDED KIT <<<
