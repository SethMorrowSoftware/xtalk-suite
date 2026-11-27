-- =====================================================================
-- box3dxt-orb-island.livecodescript  /  Orb Island
--
-- A 3D game on the b3k Kit: walk a floating island 60 metres square, find
-- the 26 golden orbs on its three levels, and do not fall into the sea. A sweeper arm
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
-- lanterns, clouds. The player (who idles, walks and jumps with his own
-- animations, squashes as he lands, leans into a run and kicks up dust),
-- the flags, platforms, gate, clouds, stands of trees, grass tufts, round
-- isles, lift pads and vault walls are Kenney's CC0 models, from his
-- Platformer, City Builder and FPS kits (box3dxt/examples/models/), carried in this file
-- between the GAME MODELS markers by box3dxt/tools/build-game-models.py.
--
-- Version 1.2 (2026-11-26) is four times the island of 1.1, which was
-- 30 metres square with eight orbs; 1.1's eight are A to H, moved out
-- with the island.
--
-- Version 1.4 (2026-11-27) makes the island TALLER: one island, three
-- levels in height. The shore is 1.2's sixteen orbs; the terraces, 9 m
-- up in the north, are two grass terraces joined by a bridge of slabs,
-- a turning plank and crumbling planks, with a flying enemy patrolling
-- it, a second jump pad, a coin block and a feather that gives a double
-- jump (reached by a stair of slabs in the west or a lift in the east);
-- the summit, 17 m up, is a round isle with a fountain and a second
-- enemy, reached by a climb of slabs and a lift. Ten more orbs (Q to Z),
-- a flag on each upper level, the HUD naming the level you are on and
-- each level's orbs, and music: a new tune each session, composed by
-- audioxt in an offline engine (N turns it off).
--
-- WHY THIS EXAMPLE EXISTS: it is the Kit's showcase, the 3D sibling of
-- box2dxt's games. Every system the Kit has carries part of the game:
--   * the world and the loop: b3kSetup, b3kSetStepMode, b3kStart, b3kPause,
--     b3kKillFloor
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
--     and b3kSetRotation (stands of trees, stones, crystals)
--   * kinematic things: b3kSetSpin (the windmill's sails, the beacon, the
--     turning platform), b3kGlideTo (the plate and the gate)
--   * models: b3kSetLook draws a model in place of a thing's shape (the
--     flags, platforms, gate, clouds, trees, grass, isles, lifts, walls);
--     b3kAddLookPart and b3kPoseLookPart draw the player in six parts and
--     play his animations on them; b3kSetLookPose squashes and leans him,
--     bobs the orbs and spreads the shadow
--   * rays: b3kRayHit finds the ground under the player for his shadow
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
--           M turns the sound off and on / N the music / P pauses /
--           R restarts
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
--      camera a little and counts it ("Orbs 1 / 26"); the last shows the
--      banner with the time. The HUD names the level you are on and how
--      many of each level's orbs are found.
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
--   7. X, C, V, M, N, P, R and the seven buttons do what they say; V says
--      render3dxt is not loaded when it is not, M that audioxt is not.
--   8. A real gamepad: the stick walks, A jumps, the pad rumbles on an orb.
--   9. Sound: the sea, the chimes climbing, the blast, the splash, the
--      fanfare, the island's tune (a different one each launch; N stops
--      it); in a web page from the first click or key press.
--  11. The levels: the west stair and the east lift reach the terraces,
--      the bridge's planks crumble and turn, the flying enemies knock
--      you back, the feather lets you jump again in the air, and the
--      climb and the summit lift reach the summit.
--  10. Every label is readable in the light and the dark appearance (each
--      control sets its own colours).
--
-- STATUS: the game's build and its rules ran on the headless Linux server
-- engine (box3dxt/tests/engine-demo.lc, OXT-Beyond 9.7.1): with box3dxt
-- alone, with no extension, and on 2026-11-26 with render3dxt, gamepadxt
-- (a virtual pad) and audioxt (its silent device) as well. In a web Stack
-- Player (web-2026.11.22, headless Chromium, 2026-11-26) version 1.2
-- built at its size, walked to an orb, found gamepadxt and audioxt, and
-- drew 30 pictures a second with the models, the animated character and
-- the trees where 1.1 drew 36 on the same machine.
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
constant kOiUIVersion = "4"
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
-- the four stretches of sea, which a shadow falls on (oiSea names them)
constant kOiSeaNames = "sea north,sea south,sea west,sea east"
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
-- the three levels: a player above kOiTier2Y metres is on the terraces,
-- above kOiTier3Y on the summit
constant kOiTier2Y = 7.5
constant kOiTier3Y = 15.5
constant kOiTierNames = "the shore,the terraces,the summit"
-- the music: an eighth note at 100 beats a minute, eight bars round, made at
-- 22050 samples a second in one channel (a quarter of a CD's data)
constant kOiMusicRate = 22050
constant kOiMusicStep = 0.3
constant kOiMusicVolume = 0.32
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
local sOiHudEvery     -- milliseconds between HUD writes: 250, or 1000 on the web
local sOiBobHalf      -- which half of the orbs bobs this frame, 0 or 1
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
local sOiPauseGen     -- counts pauses: the paused pad poll of an old one stops
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
local sOiAnim         -- [anim] -> frames, length; [anim,frame,part] -> pose
local sOiParts        -- the character's parts, one a line
local sOiAct          -- the animation playing: idle, walk or jump
local sOiActT         -- seconds into it
local sOiBlendFrom    -- [part] -> the pose the last animation left
local sOiBlend        -- 0 to 1: how far the new animation has taken over
local sOiSquash       -- the look's squash (below 0) or stretch (above)
local sOiSquashV      -- how fast it springs back
local sOiLean         -- degrees the character leans into its run
local sOiAir          -- true while the player is off the ground
local sOiFallV        -- the player's last upward speed (m/s)
local sOiStepAt       -- the walk's time at the last footstep
local sOiShadow       -- the blob shadow under the player
local sOiDust         -- [puff] -> "vx,vz,born ms"
local sOiDustAt       -- the clock time of the last running puff
local sOiOrbPhase     -- [orb] -> its bob's phase
-- version 1.4's three levels: the shore, the terraces (9 m) and the summit
local sOiOrbTier      -- [orb] -> its level, 1 to 3
local sOiTierCount    -- [level] -> how many orbs it has
local sOiTierFound    -- [level] -> how many of them are found
local sOiTierBest     -- the highest level the player has reached this run
local sOiUpLift       -- the lift from the tower's top to the east terrace
local sOiUpWait       -- the clock time at which it moves again
local sOiTopLift      -- the lift up to the summit
local sOiTopWait      -- the clock time at which it moves again
local sOiPad2         -- the jump pad on the floating platform
local sOiFeather      -- the feather (a sensor): a double jump once touched
local sOiEnemy        -- [enemy] -> "x,y,z;x,y,z;seconds": its two ends
local sOiEnemyWait    -- [enemy] -> the clock time it sets off again
local sOiEnemyAt      -- [enemy] -> 1 or 2, the end it last set off for
local sOiHitAt        -- the clock time an enemy may knock the player again
-- the music (audioxt): a tune composed at the start, played round
local sOiMusic        -- the tune's sound, 0 for none
local sOiMusicOff     -- true when N has turned the music off
local sOiMusicSecs    -- the tune's length in seconds
local sOiMusicMs      -- milliseconds the composing took (for the test)

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
   put 250 into sOiHudEvery
   put 0 into sOiBobHalf
   if oiOnWeb() then put 1000 into sOiHudEvery
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
   put "idle" into sOiAct
   put 0 into sOiActT
   put empty into sOiBlendFrom
   put 1 into sOiBlend
   put 0 into sOiSquash
   put 0 into sOiSquashV
   put 0 into sOiLean
   put false into sOiAir
   put 0 into sOiFallV
   put 0 into sOiStepAt
   put empty into sOiShadow
   put empty into sOiDust
   put 0 into sOiDustAt
   put empty into sOiOrbPhase
   put empty into sOiOrbTier
   put empty into sOiTierCount
   put empty into sOiTierFound
   put 1 into sOiTierBest
   put empty into sOiUpLift
   put 0 into sOiUpWait
   put empty into sOiTopLift
   put 0 into sOiTopWait
   put empty into sOiPad2
   put empty into sOiFeather
   put empty into sOiEnemy
   put empty into sOiEnemyWait
   put empty into sOiEnemyAt
   put 0 into sOiHitAt
   if there is a field "oiBanner" then hide field "oiBanner"
   b3kSetup
   -- each frame's time spent in equal steps: at a frame rate that is not a
   -- sixtieth's multiple (a web page's 26, a 144 Hz screen) whole steps
   -- made the island lurch, two steps one frame and three the next
   b3kSetStepMode "smooth"
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
   -- character, fitted to the capsule's 1.6 m, in six parts that his own
   -- idle, walk and jump animations move (render3dxt; box3dxt's renderer
   -- draws the capsule)
   oiHeroMake
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
   if not oiSoundOn() then
      oiSoundStart
   else
      oiSoundRebase
   end if
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
   oiLook sOiLift, "lift"

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
   oiStatic "cylinder", 0, 3.5, -19, 0.4, 3.4, "132,190,98"
   oiLook the result, "roundtop"

   oiBuildCorners
   oiBuildSkyIsle
   oiBuildTrees
   oiBuildVault
   oiBuildEastIslet
   oiBuildTerraces
   oiBuildSummit
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
   -- the terraces, 9 m up (version 1.4): Q on the west terrace, R over a
   -- crumbling plank of the bridge, S on the east terrace, T on the west
   -- stair, U on the coin block, V in the air over the second jump pad
   oiOrb "Q", -19, 9.8, -22
   oiOrb "R", -2.6, 9.8, -22.2
   oiOrb "S", 16.5, 9.8, -27
   oiOrb "T", -27.4, 6.8, -15
   oiOrb "U", 11, 11.1, -21
   oiOrb "V", 0.8, 9.6, -19.5
   -- the summit, 16.7 m up: W over the fountain (the feather's double
   -- jump reaches it), X on the coin block of the climb, Y at the edge, Z
   -- high over the summit's coin block
   oiOrb "W", -3.4, 19, -37
   oiOrb "X", 3.4, 12, -32.4
   oiOrb "Y", 0.2, 17.6, -39.6
   oiOrb "Z", -7.5, 19.7, -38

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

-- A rock hanging under something: the Kit's cone has its BASE at pY and
-- its point pHeight above, so turned over it hangs from pY down. (Version
-- 1.2's first trees and rocks were placed as if pY were the middle, and
-- floated apart; 2026-11-26.)
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
   oiStatic "cone", -16, 6.95, 16, 1.2, 1.6, "170,70,60"
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
      b3kSpawnCone item 1 of tCrystal, -0.15, item 2 of tCrystal, tH, 0.5 * tH, "150,226,240"
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
      oiRock tX, tY - 0.24, 6 - 0.6 * tI, 2.2, 1.4
   end repeat
   oiStatic "box", -45, 1.2, 4.5, 3, 2.4, 3, "136,128,120"
   oiRock -45, 0.01, 4.5, 4, 3
end oiBuildCorners

-- The floating isle in the north, over the sea, and the sky lift that
-- carries the player out to it: from a dock at the island's north edge
-- (its top at y 0.4) up to the isle's south edge (its top at y 4.5).
command oiBuildSkyIsle
   local tBeam, tIsle
   -- round, like the rock it sits on: Kenney's large grass platform
   oiStatic "cylinder", 0, 4, -43, 1, 12, "132,190,98"
   put the result into tIsle
   b3kName tIsle, "sky isle"
   oiLook tIsle, "isle"
   oiRock 0, 3.51, -43, 6, 12
   b3kAddPlatform 0, 0.2, -27.5, 2.6, 0.4, 2.6, "230,150,60"
   put the result into sOiSkyLift
   b3kName sOiSkyLift, "sky lift"
   oiLook sOiSkyLift, "lift"
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

-- Stands of trees round the island, Kenney's City Builder clumps: each is
-- one static cylinder (what the player bumps into) wearing a clump of four
-- or five trees, turned so no two stands look alike. Version 1.2's first
-- trees were a trunk and two cones, three things a tree and stiff to look
-- at (2026-11-26). Then grass tufts, which only show: a sensor is passed
-- through.
command oiBuildTrees
   local tTree, tS, tH, tKind, tThing, tTuft
   repeat for each line tTree in "-9,25,1,trees,20" & return & "-12,9,1.1,grove,75" & return & "9,10,0.9,grove,140" & return & \
         "12,23,1,trees,200" & return & "-24,25,1.2,trees,260" & return & "-26,-6,1,grove,310" & return & \
         "25,7,1.1,trees,35" & return & "26,-7,0.9,grove,100" & return & "-6,-26,1,trees,165" & return & \
         "15,-26,1,grove,230" & return & "-26,11,0.9,trees,290" & return & "-25,-15,1,trees,345" & return & \
         "28,18,1,grove,50" & return & "-28,0,1.1,trees,120" & return & "28,-16,0.9,grove,185" & return & \
         "-14,-28,0.9,trees,250" & return & "20,15,0.9,grove,320"
      put item 3 of tTree into tS
      put item 4 of tTree into tKind
      if tKind is "trees" then put 4.2 * tS into tH
      else put 3.4 * tS into tH
      oiStatic "cylinder", item 1 of tTree, tH / 2, item 2 of tTree, tH, 2.2 * tS, "64,128,70"
      put the result into tThing
      oiFix tThing, 0, item 5 of tTree, 0
      oiLook tThing, tKind, tS
   end repeat
   repeat for each line tTuft in oiTufts()
      oiTuft item 1 of tTuft, item 2 of tTuft, item 3 of tTuft
   end repeat
end oiBuildTrees

-- where the tufts grow: x, z, turn; in twos and threes by the trees
function oiTufts
   local tList
   put empty into tList
   put "-7.5,23.4,0" & return after tList
   put "-10.6,26.8,47" & return after tList
   put "-13.8,10.5,94" & return after tList
   put "-10.2,7.6,141" & return after tList
   put "7.4,11.6,188" & return after tList
   put "10.5,8.6,235" & return after tList
   put "13.7,21.4,282" & return after tList
   put "10.4,24.6,329" & return after tList
   put "-22.4,23.3,16" & return after tList
   put "-25.6,27.1,63" & return after tList
   put "-27.6,-4.4,110" & return after tList
   put "-24.4,-7.8,157" & return after tList
   put "23.5,8.8,204" & return after tList
   put "26.8,5.4,251" & return after tList
   put "24.4,-8.4,298" & return after tList
   put "-4.4,-24.6,345" & return after tList
   put "-7.6,-27.6,32" & return after tList
   put "13.5,-24.4,79" & return after tList
   put "-27.4,12.6,126" & return after tList
   put "-23.4,-13.4,173" & return after tList
   put "-26.6,-16.6,220" & return after tList
   put "3.4,24.8,267" & return after tList
   put "-3.6,8.2,314" & return after tList
   put "6.2,-8.8,1" & return after tList
   return tList
end oiTufts

-- A tuft of grass (Kenney's, CC0): a sensor that shows, at pX, pZ, turned
-- pTurn degrees
command oiTuft pX, pZ, pTurn
   local tTuft
   b3kAddSensorBox pX, 0.275, pZ, 0.9, 0.55, 0.9
   put the result into tTuft
   if tTuft is empty then exit oiTuft
   b3kSetVisible tTuft, true
   b3kSetColor tTuft, "96,170,92"
   b3kSetRotation tTuft, 0, pTurn, 0
   b3kName tTuft, "tuft"
   oiLook tTuft, "tuft"
end oiTuft

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
   put sOiOrbCount * 0.9 into sOiOrbPhase[tOrb]
   add 1 to sOiOrbCount
   put oiTierAt(pY) into sOiOrbTier[tOrb]
   add 1 to sOiTierCount[sOiOrbTier[tOrb]]
   if sOiTierFound[sOiOrbTier[tOrb]] is empty then put 0 into sOiTierFound[sOiOrbTier[tOrb]]
end oiOrb

-- the level a height is on: 1 the shore, 2 the terraces, 3 the summit
function oiTierAt pY
   if pY > kOiTier3Y then return 3
   if pY > kOiTier2Y then return 2
   return 1
end oiTierAt

-- the level the player is on now
function oiTier
   if b3kPlayer() is empty then return 1
   return oiTierAt(b3kY(b3kPlayer()))
end oiTier

-- the name of a level, "the shore" ...
function oiTierName pTier
   set the itemDelimiter to comma
   return item max(1, min(3, pTier)) of kOiTierNames
end oiTierName

-- found and to find on a level: "found,count"
function oiTierOrbs pTier
   return b3kNum(sOiTierFound[pTier], 0) & comma & b3kNum(sOiTierCount[pTier], 0)
end oiTierOrbs

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

command oiLook pThing, pName, pScale
   if pThing is empty then exit oiLook
   if pScale is empty then put 1 into pScale
   b3kSetLook pThing, oiModel(pName & ".obj"), oiModel(pName & ".mtl"), pScale
end oiLook

-- =====================================================================
-- The character: Kenney's in six parts, his animations played on them,
-- and the squash, stretch and lean that make a jump and a run read; a
-- blob shadow under it, and dust where it lands and runs
-- =====================================================================
command oiHeroMake
   local tPlayer, tPart
   put b3kPlayer() into tPlayer
   if tPlayer is empty then exit oiHeroMake
   put oiModel("character.parts") into sOiParts
   repeat for each line tPart in sOiParts
      b3kAddLookPart tPlayer, tPart, oiModel("character-" & tPart & ".obj"), oiModel("character-" & tPart & ".mtl")
   end repeat
   if sOiAnim is not an array then oiAnimLoad
   oiHeroPose 0
   oiShadowMake
end oiHeroMake

-- "anim NAME FRAMES LENGTH" then "FRAME PART x,y,z,rx,ry,rz,sx,sy,sz"
command oiAnimLoad
   local tLine, tName
   put empty into sOiAnim
   repeat for each line tLine in oiModel("character.anim")
      if word 1 of tLine is "anim" then
         put word 2 of tLine into tName
         put word 3 of tLine into sOiAnim[tName & ",frames"]
         put word 4 of tLine into sOiAnim[tName & ",length"]
      else if tName is not empty and the number of words of tLine is 3 then
         put word 3 of tLine into sOiAnim[tName & comma & word 1 of tLine & comma & word 2 of tLine]
      end if
   end repeat
end oiAnimLoad

-- one part's pose at pT seconds into an animation: the frames either side,
-- mixed
function oiAnimPose pAnim, pPart, pT
   local tFrames, tLen, tF, tI, tA, tB, tOut, k
   put sOiAnim[pAnim & ",frames"] into tFrames
   put sOiAnim[pAnim & ",length"] into tLen
   if tFrames is empty then return empty
   put max(0, min(1, pT / max(0.001, tLen))) * (tFrames - 1) into tF
   put trunc(tF) into tI
   put tF - tI into tF
   put sOiAnim[pAnim & comma & min(tFrames, tI + 1) & comma & pPart] into tA
   put sOiAnim[pAnim & comma & min(tFrames, tI + 2) & comma & pPart] into tB
   return oiMix(tA, tB, tF)
end oiAnimPose

-- two lists of numbers mixed: pF 0 is pA, 1 is pB
function oiMix pA, pB, pF
   local tOut, k
   if pB is empty or pF <= 0 then return pA
   if pA is empty then return pB
   set the itemDelimiter to comma
   put empty into tOut
   repeat with k = 1 to the number of items of pA
      put item k of pA + (item k of pB - item k of pA) * pF & comma after tOut
   end repeat
   delete the last char of tOut
   return tOut
end oiMix

command oiTickHero pMs
   local tPlayer, tVel, tSpeed, tDt, tWant, tGround, tRate, tLen, tHalf
   put b3kPlayer() into tPlayer
   if tPlayer is empty or not b3kIsThing(tPlayer) then exit oiTickHero
   put pMs / 1000 into tDt
   set the itemDelimiter to comma
   put b3kVelocity(tPlayer) into tVel
   put sqrt(item 1 of tVel ^ 2 + item 3 of tVel ^ 2) into tSpeed
   put b3kPlayerOnGround() into tGround
   -- which animation: in the air the jump, else a walk or standing still
   if not tGround then
      put "jump" into tWant
   else if tSpeed > 0.8 then
      put "walk" into tWant
   else
      put "idle" into tWant
   end if
   -- the landing: a squash as deep as the fall was fast, and dust
   if tGround and sOiAir is true then
      if sOiFallV < -2.5 then
         subtract min(0.32, -sOiFallV * 0.035) from sOiSquash
         oiDustBurst b3kX(tPlayer), b3kY(tPlayer) - 0.75, b3kZ(tPlayer), 6
         oiSound "land"
      end if
   end if
   -- the take-off: a stretch
   if not tGround and sOiAir is not true and item 2 of tVel > 2 then
      add 0.18 to sOiSquash
   end if
   put not tGround into sOiAir
   put item 2 of tVel into sOiFallV
   if tWant is not sOiAct then
      oiHeroBlendFrom
      put tWant into sOiAct
      put 0 into sOiActT
      put 0 into sOiBlend
   end if
   -- the walk keeps pace with the feet
   put 1 into tRate
   if sOiAct is "walk" then put max(0.7, tSpeed / 4) into tRate
   add tDt * tRate to sOiActT
   put b3kNum(sOiAnim[sOiAct & ",length"], 1) into tLen
   if sOiAct is "jump" then
      put min(sOiActT, tLen) into sOiActT
   else if sOiActT > tLen then
      put sOiActT mod tLen into sOiActT
   end if
   -- footsteps: twice a walk cycle
   if sOiAct is "walk" then
      put tLen / 2 into tHalf
      if trunc(sOiActT / tHalf) is not trunc(sOiStepAt / tHalf) then
         oiSound "step"
         if tSpeed > 4 and sOiClockMS - sOiDustAt > 180 then
            put sOiClockMS into sOiDustAt
            oiDustBurst b3kX(tPlayer), b3kY(tPlayer) - 0.75, b3kZ(tPlayer), 1
         end if
      end if
   end if
   put sOiActT into sOiStepAt
   put min(1, sOiBlend + tDt / 0.12) into sOiBlend
   -- the squash springs back (a stiff, damped spring) and the air stretches
   -- with the upward speed
   add (-260 * sOiSquash - 16 * sOiSquashV) * tDt to sOiSquashV
   add sOiSquashV * tDt to sOiSquash
   put max(-0.4, min(0.4, sOiSquash)) into sOiSquash
   -- the lean into a run, eased
   if tGround then
      add (min(14, tSpeed * 1.8) - sOiLean) * min(1, tDt * 10) to sOiLean
   else
      add (0 - sOiLean) * min(1, tDt * 6) to sOiLean
   end if
   oiHeroPose item 2 of tVel
   oiShadowTick
end oiTickHero

-- the pose the last animation left, for the next to take over from
command oiHeroBlendFrom
   local tPart
   repeat for each line tPart in sOiParts
      put oiMix(sOiBlendFrom[tPart], oiAnimPose(sOiAct, tPart, sOiActT), sOiBlend) into sOiBlendFrom[tPart]
   end repeat
end oiHeroBlendFrom

command oiHeroPose pVy
   local tPlayer, tPart, tPose, tSy, tSx, tAir
   put b3kPlayer() into tPlayer
   if tPlayer is empty then exit oiHeroPose
   repeat for each line tPart in sOiParts
      put oiMix(sOiBlendFrom[tPart], oiAnimPose(sOiAct, tPart, sOiActT), sOiBlend) into tPose
      if tPose is empty then next repeat
      set the itemDelimiter to comma
      b3kPoseLookPart tPlayer, tPart, item 1 of tPose, item 2 of tPose, item 3 of tPose, item 4 of tPose, item 5 of tPose, item 6 of tPose, \
            item 7 of tPose, item 8 of tPose, item 9 of tPose
   end repeat
   -- the whole look: stretched in the air, squashed on landing, the volume
   -- kept (wider when shorter), the feet kept on the ground, leaning in
   put 0 into tAir
   if sOiAir is true then put max(-0.1, min(0.14, b3kNum(pVy, 0) * 0.02)) into tAir
   put 1 + sOiSquash + tAir into tSy
   put 1 / sqrt(max(0.3, tSy)) into tSx
   b3kSetLookPose tPlayer, 0, 0.8 * (tSy - 1), 0, sOiLean, 0, 0, tSx, tSy, tSx
end oiHeroPose

-- The blob shadow: a dark disc on whatever is under the player, smaller
-- the higher it jumps. A sensor (nothing stands on it) the ray passes.
command oiShadowMake
   local tObj, tI, tA
   b3kAddSensorBox 0, -20, 0, 0.9, 0.02, 0.9
   put the result into sOiShadow
   if sOiShadow is empty then exit oiShadowMake
   b3kSetVisible sOiShadow, true
   b3kSetColor sOiShadow, "70,92,58"
   b3kName sOiShadow, "shadow"
   put "mtllib model.mtl" & return & "v 0 0 0" & return & "vn 0 1 0" & return into tObj
   repeat with tI = 0 to 15
      put tI * 2 * pi / 16 into tA
      put "v " & format("%.3f", 0.5 * cos(tA)) && "0" && format("%.3f", 0.5 * sin(tA)) & return after tObj
   end repeat
   put "usemtl shade" & return after tObj
   repeat with tI = 0 to 15
      -- counter-clockwise seen from above: the centre, then two rim points
      put "f 1//1 " & ((tI + 1) mod 16) + 2 & "//1 " & tI + 2 & "//1" & return after tObj
   end repeat
   b3kSetLook sOiShadow, tObj, "newmtl shade" & return & "Kd 0.2 0.26 0.17" & return
end oiShadowMake

command oiShadowTick
   local tPlayer, tHit, tY, tH, tS, tTries
   if sOiShadow is empty or not b3kIsThing(sOiShadow) then exit oiShadowTick
   put b3kPlayer() into tPlayer
   -- from inside the player's own shape, which a ray starting in it never
   -- meets: a ray from its feet started just under the grass when it
   -- stood on it, and met the sea (2026-11-26)
   put b3kRayHit(b3kX(tPlayer), b3kY(tPlayer) - 0.5, b3kZ(tPlayer), 0, -12, 0) into tHit
   -- a ray meets sensors too: the shadow itself (which then climbed its
   -- own top, frame by frame), dust and tufts; look on past them, to the
   -- first solid thing or the sea
   set the itemDelimiter to comma
   put 0 into tTries
   repeat while tHit is not empty and tTries < 4 and b3kKind(tHit) is "sensor" and b3kNameOf(tHit) is not among the items of kOiSeaNames
      add 1 to tTries
      put item 2 of b3kHitPoint() - 0.01 into tY
      put b3kRayHit(b3kX(tPlayer), tY, b3kZ(tPlayer), 0, -12, 0) into tHit
   end repeat
   if tHit is empty or tHit is tPlayer or b3kKind(tHit) is "sensor" and b3kNameOf(tHit) is not among the items of kOiSeaNames then
      b3kSetVisible sOiShadow, false
      exit oiShadowTick
   end if
   set the itemDelimiter to comma
   put item 2 of b3kHitPoint() into tY
   put b3kY(tPlayer) - 0.8 - tY into tH
   put max(0.35, 1 - tH * 0.12) into tS
   if not b3kIsVisible(sOiShadow) then b3kSetVisible sOiShadow, true
   b3kMoveTo sOiShadow, b3kX(tPlayer), tY + 0.03, b3kZ(tPlayer)
   b3kSetLookPose sOiShadow, 0, 0, 0, 0, 0, 0, tS, 1, tS
end oiShadowTick

-- Dust: small pale balls that drift out, shrink and are gone in 0.45 s.
-- Sensors, so nothing trips on them; at most fourteen at once.
command oiDustBurst pX, pY, pZ, pCount
   local tI, tA, tPuff
   repeat with tI = 1 to pCount
      if the number of lines of the keys of sOiDust >= 14 then exit repeat
      b3kAddSensorBall pX, pY + 0.1, pZ, 0.32
      put the result into tPuff
      if tPuff is empty then exit repeat
      b3kSetVisible tPuff, true
      b3kSetColor tPuff, "238,230,214"
      b3kSetGlow tPuff, "60,56,50"
      put random(360) * pi / 180 into tA
      put 1.6 * cos(tA) & comma & 1.6 * sin(tA) & comma & sOiClockMS into sOiDust[tPuff]
   end repeat
end oiDustBurst

command oiTickDust pMs
   local tPuff, tAge, tS, tD
   set the itemDelimiter to comma
   repeat for each key tPuff in sOiDust
      put sOiDust[tPuff] into tD
      put sOiClockMS - item 3 of tD into tAge
      if tAge > 450 or not b3kIsThing(tPuff) then
         if b3kIsThing(tPuff) then b3kRemove tPuff
         delete variable sOiDust[tPuff]
         next repeat
      end if
      b3kMoveTo tPuff, b3kX(tPuff) + item 1 of tD * pMs / 1000, b3kY(tPuff) + 0.6 * pMs / 1000, b3kZ(tPuff) + item 2 of tD * pMs / 1000
      put 1.3 - tAge / 450 into tS
      b3kSetLookPose tPuff, 0, 0, 0, 0, 0, 0, tS, tS, tS
   end repeat
end oiTickDust

-- the orbs bob, each a little after the last
-- Half the orbs a frame, in turn: a bob moves an orb about a hundredth of
-- a metre a frame, so each is posed every other frame and no step shows,
-- and the posing (script, in a web page) costs half
command oiTickOrbBob
   local tOrb, tT, tI
   put sOiClockMS / 1000 into tT
   put 1 - sOiBobHalf into sOiBobHalf
   put 0 into tI
   repeat for each key tOrb in sOiOrb
      add 1 to tI
      if tI mod 2 is sOiBobHalf then
         b3kSetLookPose tOrb, 0, 0.12 * sin(tT * 2.6 + sOiOrbPhase[tOrb]), 0
      end if
   end repeat
end oiTickOrbBob

function oiHeroAct
   return sOiAct
end oiHeroAct

function oiDustCount
   return the number of lines of the keys of sOiDust
end oiDustCount

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
   -- the walls wear Kenney's FPS kit wall (CC0)
   oiStatic "box", 23.5, 1.6, -26, 0.6, 3.2, 5.6, "150,128,112"
   oiLook the result, "wall-z"
   oiStatic "box", 28.5, 1.6, -26, 0.6, 3.2, 5.6, "150,128,112"
   oiLook the result, "wall-z"
   oiStatic "box", 26, 1.6, -28.5, 5.6, 3.2, 0.6, "150,128,112"
   oiLook the result, "wall-x"
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
   oiStatic "cylinder", 49.5, -0.5, 0, 1, 7, "132,190,98"
   put the result into tIsle
   b3kName tIsle, "east islet"
   oiLook tIsle, "isle", 7 / 12
   oiRock 49.5, -0.99, 0, 3, 6
   oiFlag "east islet", 51.5, 0, -2.2
end oiBuildEastIslet

-- =====================================================================
-- The two upper levels (version 1.4, 2026-11-27): one island, three
-- levels in height. The terraces are two of Kenney's large grass
-- platforms 9 m up, over the north-west and the north-east, joined by a
-- bridge of planks across the north; the summit is a round isle 16.7 m up
-- in the north with a fountain on it. The ways up:
--   * the west stair: slabs climbing from the west ledge (3 m) round the
--     island's edge to the west terrace, one of them crumbling;
--   * the upper lift: from the tower's top (5 m) to the east terrace;
--   * the second jump pad, on the floating platform: up past orb V to the
--     bridge;
--   * the climb: from the east terrace a slab, a coin block and a slab to
--     the summit lift.
-- A flying enemy patrols the bridge and another the summit; touched, it
-- knocks the player back. The feather on the west terrace gives a double
-- jump, which the summit's fountain and its highest orb want.
-- =====================================================================
command oiBuildTerraces
   local tTurn
   oiTerrace "west terrace", -18, 9, -20
   oiTerrace "east terrace", 14, 9, -24
   -- the west stair: each top a metre above the last, a short jump on;
   -- the fourth crumbles. From the west ledge (top 3 m at -18, -3.6).
   oiSlab -21.8, 4, -7.4
   oiSlab -25.4, 5, -11
   oiSlab -27.4, 6, -15
   oiCrumbleSpot 4, -26.6, 6.75, -19.2
   oiSlab -25.5, 8, -23
   -- the upper lift, on the tower's north face (z -16): from just above
   -- the tower's top (5 m) to the east terrace's (9 m), whose south edge
   -- is 0.2 m beyond it
   b3kAddPlatform 18.5, 5, -17.5, 2.6, 0.4, 2.6, "70,180,190"
   put the result into sOiUpLift
   b3kName sOiUpLift, "upper lift"
   oiLook sOiUpLift, "lift"
   -- the bridge across the north, from the west terrace's east edge (x -13)
   -- to the east terrace's west edge (x 9): a plank, a turning platform,
   -- two crumbling planks and a plank, a jump apart
   oiSlab -10.4, 9, -21
   b3kAddPlatform -6.4, 8.7, -21.6, 3, 0.6, 3, "200,170,110"
   put the result into tTurn
   b3kName tTurn, "bridge turner"
   b3kSetSpin tTurn, 0, -40, 0
   oiLook tTurn, "platform"
   oiCrumbleSpot 5, -2.6, 8.75, -22.2
   oiCrumbleSpot 6, 0.8, 8.75, -22.8
   oiSlab 6.2, 9, -23.6
   -- the second jump pad, on the floating platform (top 3.7 m)
   b3kAddSensorBox 0.8, 3.8, -19.5, 1, 0.2, 1
   put the result into sOiPad2
   b3kName sOiPad2, "high jump pad"
   b3kSetVisible sOiPad2, true
   b3kSetColor sOiPad2, "90,200,110"
   b3kSetGlow sOiPad2, "20,90,30"
   -- a coin block on the east terrace, orb U on top
   oiBlock 11, 9.7, -21
   -- the feather, at the top of the west stair
   b3kAddSensorBall -21, 9.9, -23.5, 0.8
   put the result into sOiFeather
   if sOiFeather is not empty then
      b3kSetVisible sOiFeather, true
      b3kSetColor sOiFeather, "150,230,255"
      b3kSetGlow sOiFeather, "40,120,170"
      b3kName sOiFeather, "feather"
   end if
   oiEnemyMake "bridge", -9, 10.3, -21.4, 5, 10.3, -23.4, 6
   oiFlag "west terrace", -15, 9, -17
   oiFlag "east terrace", 17, 9, -21
   repeat for each line tTurn in "-21,-17,40" & return & "-14.5,-23.5,150" & return & "11,-27.5,260" & return & "18,-27,20"
      oiSprig item 1 of tTurn, 9, item 2 of tTurn, item 3 of tTurn
   end repeat
end oiBuildTerraces

command oiBuildSummit
   local tIsle, tTuft
   -- the climb from the east terrace's north-west corner (9, -29)
   oiSlab 6.6, 10.1, -31
   oiBlock 3.4, 10.6, -32.4
   oiSlab 0.2, 11.9, -31
   -- the summit lift: from beside the last slab (its top 12.2 m) to the
   -- summit's (16.7 m), 0.5 m from the isle's edge
   b3kAddPlatform -3.4, 12, -30.2, 2.6, 0.4, 2.6, "230,150,60"
   put the result into sOiTopLift
   b3kName sOiTopLift, "summit lift"
   oiLook sOiTopLift, "lift"
   -- the summit: a round isle 10 m across on a hanging rock
   oiStatic "cylinder", -3.4, 16.2, -37, 1, 10, "132,190,98"
   put the result into tIsle
   b3kName tIsle, "summit"
   oiLook tIsle, "isle", 10 / 12
   oiRock -3.4, 15.71, -37, 5, 9
   -- the fountain, 1.6 m high: a double jump stands on it
   oiStatic "box", -3.4, 17.5, -37, 4.4, 1.6, 4.4, "170,176,190"
   b3kName the result, "fountain"
   oiLook the result, "fountain"
   b3kAddLamp -3.4, 19, -37, "255,214,140", 10, 1.8
   oiBlock -7.5, 17.4, -38
   oiEnemyMake "summit", -6.6, 17.5, -34.2, -0.2, 17.5, -34.2, 5
   oiFlag "summit", -0.4, 16.7, -33.6
   repeat for each line tTuft in "-6.5,-40.5,30" & return & "-1,-41,120" & return & "0.8,-35.5,210" & return & "-7.4,-35.4,300"
      oiSprig item 1 of tTuft, 16.7, item 2 of tTuft, item 3 of tTuft
   end repeat
end oiBuildSummit

-- A terrace: Kenney's large grass platform on a box 10 m square and 1.2 m
-- thick, its top at pTop, a rock hanging under it
command oiTerrace pName, pX, pTop, pZ
   oiStatic "box", pX, pTop - 0.6, pZ, 10, 1.2, 10, "132,190,98"
   b3kName the result, pName
   oiLook the result, "terrace"
   oiRock pX, pTop - 1.19, pZ, 5, 7
end oiTerrace

-- A slab to jump on: Kenney's large platform on a box 3.2 m square and
-- 0.5 m thick, its top at pTop
command oiSlab pX, pTop, pZ
   oiStatic "box", pX, pTop - 0.25, pZ, 3.2, 0.5, 3.2, "196,170,130"
   oiLook the result, "slab"
end oiSlab

-- A coin block, 1.4 m a side, centred at pY
command oiBlock pX, pY, pZ
   oiStatic "box", pX, pY, pZ, 1.4, 1.4, 1.4, "240,190,60"
   b3kName the result, "coin block"
   oiLook the result, "coinblock"
end oiBlock

-- A small tuft (Kenney's grass-small) on a level whose top is pTop
command oiSprig pX, pTop, pZ, pTurn
   local tTuft
   b3kAddSensorBox pX, pTop + 0.225, pZ, 0.7, 0.45, 0.7
   put the result into tTuft
   if tTuft is empty then exit oiSprig
   b3kSetVisible tTuft, true
   b3kSetColor tTuft, "96,170,92"
   b3kSetRotation tTuft, 0, pTurn, 0
   b3kName tTuft, "sprig"
   oiLook tTuft, "sprig"
end oiSprig

-- A flying enemy (Kenney's, CC0): a kinematic box that glides between
-- two ends, turned to face its way, resting a moment at each end
command oiEnemyMake pName, pX1, pY1, pZ1, pX2, pY2, pZ2, pSecs
   local tEnemy
   b3kAddPlatform pX1, pY1, pZ1, 1.2, 1, 1.2, "200,90,190"
   put the result into tEnemy
   if tEnemy is empty then exit oiEnemyMake
   b3kName tEnemy, "enemy " & pName
   oiLook tEnemy, "enemy"
   put pX1 & comma & pY1 & comma & pZ1 & ";" & pX2 & comma & pY2 & comma & pZ2 & ";" & pSecs into sOiEnemy[tEnemy]
   put 0 into sOiEnemyWait[tEnemy]
   put 1 into sOiEnemyAt[tEnemy]
end oiEnemyMake

-- The two new lifts, as the tower's: a rest at each end, then a glide
command oiTickUpLifts
   if sOiUpLift is not empty and b3kIsThing(sOiUpLift) then
      if not b3kIsGliding(sOiUpLift) and sOiClockMS >= sOiUpWait then
         if b3kY(sOiUpLift) < 7 then
            b3kGlideTo sOiUpLift, 18.5, 8.8, -17.5, 3
         else
            b3kGlideTo sOiUpLift, 18.5, 5, -17.5, 3
         end if
         put sOiClockMS + 4500 into sOiUpWait
      end if
   end if
   if sOiTopLift is not empty and b3kIsThing(sOiTopLift) then
      if not b3kIsGliding(sOiTopLift) and sOiClockMS >= sOiTopWait then
         if b3kY(sOiTopLift) < 14 then
            b3kGlideTo sOiTopLift, -3.4, 16.5, -30.2, 4
         else
            b3kGlideTo sOiTopLift, -3.4, 12, -30.2, 4
         end if
         put sOiClockMS + 6000 into sOiTopWait
      end if
   end if
end oiTickUpLifts

-- The enemies fly to and fro; one within reach of the player knocks it
-- back and up, away from itself, once in 0.9 s at most
command oiTickEnemies
   local tEnemy, tEnds, tTo, tFrom, tPlayer, tDx, tDy, tDz, tD
   put b3kPlayer() into tPlayer
   set the itemDelimiter to comma
   repeat for each key tEnemy in sOiEnemy
      if not b3kIsThing(tEnemy) then
         delete variable sOiEnemy[tEnemy]
         next repeat
      end if
      if not b3kIsGliding(tEnemy) and sOiClockMS >= sOiEnemyWait[tEnemy] then
         put sOiEnemy[tEnemy] into tEnds
         set the itemDelimiter to ";"
         put 3 - sOiEnemyAt[tEnemy] into sOiEnemyAt[tEnemy]
         put item sOiEnemyAt[tEnemy] of tEnds into tTo
         put item 3 - sOiEnemyAt[tEnemy] of tEnds into tFrom
         get item 3 of tEnds
         set the itemDelimiter to comma
         -- it faces its way: Kenney's enemy looks down +z
         b3kSetRotation tEnemy, 0, atan2(item 1 of tTo - item 1 of tFrom, item 3 of tTo - item 3 of tFrom) * 180 / pi, 0
         b3kGlideTo tEnemy, item 1 of tTo, item 2 of tTo, item 3 of tTo, it
         put sOiClockMS + 1000 * it + 800 into sOiEnemyWait[tEnemy]
      end if
      if tPlayer is empty or sOiClockMS < sOiHitAt then next repeat
      put b3kX(tPlayer) - b3kX(tEnemy) into tDx
      put b3kY(tPlayer) - b3kY(tEnemy) into tDy
      put b3kZ(tPlayer) - b3kZ(tEnemy) into tDz
      if abs(tDy) > 1.4 or abs(tDx) > 1.4 or abs(tDz) > 1.4 then next repeat
      put sqrt(tDx * tDx + tDz * tDz) into tD
      if tD > 1.3 then next repeat
      if tD < 0.01 then
         put 1 into tDx
         put 0 into tDz
         put 1 into tD
      end if
      b3kSetVelocity tPlayer, 7 * tDx / tD, 5.5, 7 * tDz / tD
      put sOiClockMS + 900 into sOiHitAt
      b3kCamShake 0.12, 200
      oiRumble 0.5, 0.3, 160
      oiSound "ouch"
      uiStatus "Ouch! The flying enemy knocks you back.", "warn"
   end repeat
end oiTickEnemies

-- A new level reached is announced, once a run each
command oiTickTier
   local tTier
   put oiTier() into tTier
   if tTier <= sOiTierBest then exit oiTickTier
   put tTier into sOiTierBest
   oiSound "tier"
   oiSparks b3kX(b3kPlayer()), b3kY(b3kPlayer()) + 1, b3kZ(b3kPlayer())
   if tTier is 2 then
      uiStatus "Level 2: the terraces. " & item 2 of oiTierOrbs(2) & " orbs up here; the summit is higher still.", "ok"
   else
      uiStatus "Level 3: the summit! " & item 2 of oiTierOrbs(3) & " orbs at the top of the island.", "ok"
   end if
end oiTickTier

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
   oiTickUpLifts
   oiTickEnemies
   oiTickHero tMs
   oiTickDust tMs
   oiTickOrbBob
   oiTickBall
   oiTickCrumble
   oiTickPlate
   oiTickGlow
   oiTickSparks
   oiTickJump
   oiSoundTick
   -- in a web page a write to the side panel costs a frame's worth of
   -- drawing (12 ms in headless Chromium, 2026-11-26), and four of those a
   -- second were the hitches, and the gaps in the sound: there, once a second
   if sOiClockMS - sOiHudAt >= sOiHudEvery then
      oiTickTier
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
   if pSensor is sOiPad2 then
      -- 12 m/s: 7 m up, past orb V, to the bridge overhead
      b3kPlayerJump 12
      oiSound "pad"
      exit b3kSensorEnter
   end if
   if pSensor is sOiFeather then
      oiSparks b3kX(pSensor), b3kY(pSensor), b3kZ(pSensor)
      b3kRemove pSensor
      put empty into sOiFeather
      b3kPlayerSet "airJumps", 1
      oiSound "feather"
      uiStatus "The feather! Jump again in the air for a double jump.", "ok"
      exit b3kSensorEnter
   end if
   if sOiOrb[pSensor] is not empty then
      oiSparks b3kX(pSensor), b3kY(pSensor), b3kZ(pSensor)
      delete variable sOiOrb[pSensor]
      add 1 to sOiTierFound[b3kNum(sOiOrbTier[pSensor], 1)]
      delete variable sOiOrbTier[pSensor]
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
      case "n"
         oiToggleMusic
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
      case "oiMusic"
         oiToggleMusic
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
      add 1 to sOiPauseGen
      if sOiPadOn is true then send ("oiPadPausedPoll " & sOiPauseGen) to me in 50 milliseconds
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
   -- a worn stick rests a little off centre: past gamepadxt's 0.15 that
   -- walked the player away on its own
   gpSetDeadZone 0.24
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
   local tStick, tX, tY, tLook
   if sOiPadOn is not true then exit oiPadTick
   oiPadEvents
   -- a pad let go of (unplugged, asleep, its batteries flat) while its
   -- stick was pushed must let go of the player too: until 2026-11-26 the
   -- last push stayed, and the player ran on by itself
   if sOiPadNow is 0 or b3kPlayer() is empty then
      if sOiPadSteer is true then
         b3kPlayerSteer empty, empty
         put false into sOiPadSteer
      end if
      exit oiPadTick
   end if
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

-- the pad's queued events: plugged in, unplugged, a button pressed
command oiPadEvents
   local tEvent
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
end oiPadEvents

-- While the Kit is paused it sends no b3kFrame, so oiPadTick stops; this
-- reads the pad on its own timer instead, so Start resumes and Back starts
-- again (before 2026-11-26 a pad that paused could not resume). One poll
-- runs at a time: pGen is the pause it belongs to, and it ends when that
-- pause does.
command oiPadPausedPoll pGen
   set the defaultStack to the short name of this stack
   if pGen is not sOiPauseGen then exit oiPadPausedPoll
   if sOiPadOn is not true or b3kWorld() is empty then exit oiPadPausedPoll
   if not b3kIsPaused() then exit oiPadPausedPoll
   oiPadEvents
   if pGen is sOiPauseGen and b3kIsPaused() then
      send ("oiPadPausedPoll " & pGen) to me in 50 milliseconds
   end if
end oiPadPausedPoll

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
   oiMusicMake
   oiSoundLabel
end oiSoundStart

-- ---------------------------------------------------------------------
-- The island's music, composed afresh each session
-- ---------------------------------------------------------------------
-- A little tune in C on a steel-drum-ish voice, over a sine bass, soft
-- chord stabs and a shaker: eight bars of eight steps (kOiMusicStep
-- seconds each), chords C F G F C F G C. The notes are not stored: they
-- are drawn at random from the C pentatonic scale, walking a step or
-- two at a time and landing on a chord tone at the start of each half
-- bar, so every session hums a different tune that still sounds like
-- the island. audioxt does the work twice: an OFFLINE engine
-- (auEngineCreateOffline) plays the voices into samples step by step,
-- nothing heard, and the samples become one looping sound on the live
-- engine (auSoundFromPCM). Mono at kOiMusicRate hertz keeps it small:
-- about 19 seconds is 850 KB. Composing takes a moment once, at start;
-- after that the music costs the frame nothing.
command oiMusicMake
   local tEngine, tData, tErr, tT0
   put 0 into sOiMusic
   put 0 into sOiMusicSecs
   if not oiSoundOn() then exit oiMusicMake
   put the milliseconds into tT0
   try
      put auEngineCreateOffline(kOiMusicRate, 1) into tEngine
   catch tErr
      put 0 into tEngine
   end try
   if tEngine is not an integer or tEngine <= 0 then exit oiMusicMake
   put oiMusicCompose(tEngine) into tData
   auEngineFree tEngine
   if tData is empty then exit oiMusicMake
   put auSoundFromPCM(sOiAudio, tData, "s16", kOiMusicRate, 1) into sOiMusic
   if sOiMusic is not an integer or sOiMusic <= 0 then
      put 0 into sOiMusic
      exit oiMusicMake
   end if
   put the number of bytes in tData / (2 * kOiMusicRate) into sOiMusicSecs
   auSoundSetVolume sOiMusic, kOiMusicVolume
   auSoundSetLooping sOiMusic, true
   if sOiMusicOff is not true then auSoundStart sOiMusic
   put the milliseconds - tT0 into sOiMusicMs
end oiMusicMake

-- the tune's samples, s16 mono: each step starts its notes, then the
-- offline engine renders that step; a voice is freed once it has ended
function oiMusicCompose pEngine
   local tData, tFrames, tBar, tStep, tRoot, tChord, tNote, tPos, tLast
   local tRhythm, tLive, tKeep, tLine, tNow, tLen
   set the itemDelimiter to comma
   put round(kOiMusicStep * kOiMusicRate) into tFrames
   -- C pentatonic from middle C up, as MIDI notes; tPos walks it
   put "60,62,64,67,69,72,74,76,79,81" into tNote
   put 6 into tPos
   repeat with tBar = 1 to 8
      -- C F G F C F G C: the root as a MIDI note, and the chord's tones
      put item tBar of "48,53,55,53,48,53,55,48" into tRoot
      put item tBar of "0 4 7,0 4 9,2 7 11,0 4 9,0 4 7,0 4 9,2 7 11,0 4 7" into tChord
      -- where the melody plays this bar: one of four rhythms, the last
      -- bar held on its first note so the loop breathes before it turns
      put any item of "10101110,10111010,11011010,10100110" into tRhythm
      if tBar is 8 then put "10000000" into tRhythm
      repeat with tStep = 0 to 7
         put auEngineTime(pEngine) into tNow
         -- the bass: the root on 1 and 5, the fifth on 4 and 8
         if tStep is 0 or tStep is 4 then
            oiMusicVoice pEngine, "sine", tRoot, 0.26, 2 * kOiMusicStep, tNow, tLive
         else if tStep is 3 or tStep is 7 then
            oiMusicVoice pEngine, "sine", tRoot + 7, 0.2, kOiMusicStep, tNow, tLive
         end if
         -- the chord: three soft triangles on the off beats
         if tStep is 2 or tStep is 6 then
            repeat for each word tLine in tChord
               oiMusicVoice pEngine, "triangle", 60 + (tLine mod 12), 0.06, 0.9 * kOiMusicStep, tNow, tLive
            end repeat
         end if
         -- the melody
         if char tStep + 1 of tRhythm is "1" and not (tBar is 8 and tStep is 7) then
            if tStep is 0 or tStep is 4 then
               -- a strong beat: move to the nearest chord tone
               put oiMusicNearest(tNote, tPos, tChord) into tPos
            else
               put max(1, min(10, tPos + any item of "-2,-1,-1,1,1,2")) into tPos
            end if
            put item tPos of tNote into tLine
            put kOiMusicStep into tLen
            if char tStep + 2 of tRhythm is "0" then put 2 * kOiMusicStep into tLen
            if tBar is 8 then
               put item 1 of tNote into tLine
               put 6 * kOiMusicStep into tLen
            end if
            oiMusicVoice pEngine, "sine", tLine, 0.17, tLen, tNow, tLive
            oiMusicVoice pEngine, "triangle", tLine + 12, 0.05, 0.6 * tLen, tNow, tLive
         end if
         -- the shaker, louder off the beat; quiet in the last bar's tail
         if not (tBar is 8 and tStep >= 4) then
            if tStep mod 2 is 1 then
               oiMusicVoice pEngine, "white", 0, 0.035, 0.07, tNow, tLive
            else
               oiMusicVoice pEngine, "white", 0, 0.015, 0.05, tNow, tLive
            end if
         end if
         put auEngineRender(pEngine, tFrames, "s16") after tData
         -- the voices that have ended are given back
         put auEngineTime(pEngine) into tNow
         put empty into tKeep
         repeat for each line tLine in tLive
            if item 2 of tLine <= tNow then
               auSoundFree item 1 of tLine
            else
               put tLine & return after tKeep
            end if
         end repeat
         put tKeep into tLive
      end repeat
   end repeat
   repeat for each line tLine in tLive
      auSoundFree item 1 of tLine
   end repeat
   return tData
end oiMusicCompose

-- one note of the tune: MIDI note pNote (0 for the noise), fading from
-- pLevel to silence over pFor seconds; pLive collects it to be freed
command oiMusicVoice pEngine, pShape, pNote, pLevel, pFor, pNow, @pLive
   local tSound
   if pShape is "white" then
      put auSoundNoise(pEngine, "white", pLevel) into tSound
   else
      put auSoundTone(pEngine, pShape, 440 * 2 ^ ((pNote - 69) / 12), pLevel) into tSound
   end if
   if tSound is not an integer or tSound <= 0 then exit oiMusicVoice
   auSoundFade tSound, 1, 0, pFor
   auSoundStart tSound
   auSoundStopAt tSound, pNow + pFor
   put tSound & comma & (pNow + pFor) & return after pLive
end oiMusicVoice

-- the place in pScale, nearest pPos, of a note in the chord pChord
-- (pitch classes, as words)
function oiMusicNearest pScale, pPos, pChord
   local tD, tP
   set the itemDelimiter to comma
   repeat with tD = 0 to 9
      repeat for each item tP in (pPos - tD) & comma & (pPos + tD)
         if tP < 1 or tP > 10 then next repeat
         if (item tP of pScale) mod 12 is among the words of pChord then return tP
      end repeat
   end repeat
   return pPos
end oiMusicNearest

-- N: the music off or on again (the sound itself is M's)
command oiToggleMusic
   if not oiSoundOn() then
      uiStatus "No music: load the audioxt extension for the island's tune.", "warn"
      exit oiToggleMusic
   end if
   put sOiMusicOff is not true into sOiMusicOff
   if sOiMusic > 0 then
      if sOiMusicOff then
         auSoundStop sOiMusic
      else
         auSoundStart sOiMusic
      end if
   end if
   if sOiMusicOff then
      uiStatus "Music off. N plays it again.", "ok"
   else
      uiStatus "Music on.", "ok"
   end if
   oiSoundLabel
   oiHud
end oiToggleMusic

-- true while the tune plays
function oiMusicOn
   return oiSoundOn() and sOiMusic is an integer and sOiMusic > 0 and sOiMusicOff is not true
end oiMusicOn

-- the tune's length in seconds, and how long composing it took (the test
-- reads them)
function oiMusicSecs
   return b3kNum(sOiMusicSecs, 0)
end oiMusicSecs

function oiMusicMs
   return b3kNum(sOiMusicMs, 0)
end oiMusicMs

-- the tune's sound, 0 for none
function oiMusicSound
   return b3kNum(sOiMusic, 0)
end oiMusicSound

-- a new run sets the game clock back to 0: the last run's one-shot sounds
-- are freed now (their deadlines are on the old clock, which the new one
-- would take minutes to reach) and the sea swells again from 0
command oiSoundRebase
   local tLine
   repeat for each line tLine in sOiVoices
      if item 1 of tLine is an integer then auSoundFree item 1 of tLine
   end repeat
   put empty into sOiVoices
   put 0 into sOiSeaAt
end oiSoundRebase

command oiSoundStop
   if sOiAudio is an integer and sOiAudio > 0 then auEngineFree sOiAudio
   put 0 into sOiAudio
   put 0 into sOiSea
   put 0 into sOiMusic
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
   if there is no button "oiMusic" then exit oiSoundLabel
   if oiMusicOn() then
      set the label of button "oiMusic" to "Music: on (N)"
   else
      set the label of button "oiMusic" to "Music: off (N)"
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
         -- sixteen notes climb; the terraces' and the summit's orbs climb them again
         put item ((max(1, sOiFound) - 1) mod 16) + 1 of kOiChime into tNote
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
      case "step"
         oiVoice "white", 0, 0.035, 0, 0.04
         break
      case "land"
         oiVoice "sine", 90, 0.22, 0, 0.1
         oiVoice "white", 0, 0.08, 0, 0.08
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
      case "feather"
         repeat with tI = 0 to 4
            oiVoice "sine", 784 * (1.122 ^ tI), 0.12, 0.06 * tI, 0.25
         end repeat
         break
      case "ouch"
         oiVoice "square", 220, 0.08, 0, 0.12
         oiVoice "square", 165, 0.08, 0.1, 0.18
         break
      case "tier"
         set the itemDelimiter to comma
         put 0 into tI
         repeat for each item tNote in "392,523.25,659.25,783.99"
            oiVoice "triangle", tNote, 0.14, tI * 0.09, 0.4
            add 1 to tI
         end repeat
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
   local tScore, tTime, tLevel, tStats, tSound, tT, tLvl, tOrbs
   put sOiClockMS into sOiHudAt
   if there is no field "oiScore" then exit oiHud
   put "Orbs  " & sOiFound & " / " & sOiOrbCount into tScore
   -- tenths where the panel is written four times a second, whole seconds
   -- where it is written once
   if sOiHudEvery >= 1000 then
      put "Time  " & trunc(sOiPlayMS / 1000) & " s      Falls  " & sOiFalls into tTime
   else
      put "Time  " & format("%.1f", sOiPlayMS / 1000) & " s      Falls  " & sOiFalls into tTime
   end if
   -- the level the player is on, and the orbs found on each of the three
   put oiTier() into tT
   put "On level " & tT & ", " & oiTierName(tT) & return into tLevel
   repeat with tLvl = 1 to 3
      put oiTierOrbs(tLvl) into tOrbs
      if tLvl > 1 then put "     " after tLevel
      put word 2 of oiTierName(tLvl) & "  " & item 1 of tOrbs & " / " & item 2 of tOrbs after tLevel
   end repeat
   put "none (audioxt not loaded)" into tSound
   if oiSoundOn() then
      put "on" into tSound
      if sOiMuted is true then put "off (M)" into tSound
      if oiMusicOn() then
         put ", music on (N)" after tSound
      else
         put ", music off (N)" after tSound
      end if
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
   if tLevel is not sOiHudText["level"] and there is a field "oiLevel" then
      put tLevel into field "oiLevel"
      put tLevel into sOiHudText["level"]
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
   uiLabel "oiScore", "Orbs  0 / 0", tL & ",82," & tR & ",106", 20
   set the textStyle of field "oiScore" to "bold"
   uiLabel "oiTime", "Time  0.0 s", tL & ",106," & tR & ",122", 11
   set the foregroundColor of field "oiTime" to kUiInkSoft
   -- the three levels: the one the player is on, and each one's orbs
   -- a fixed rect, two lines of 14 px under a 6 px margin: uiWrap would
   -- fit it to the one line it starts with and cut the second off, and
   -- with no top margin the first line's tops are cut
   uiLabel "oiLevel", "On level 1, the shore" & return & "shore  0 / 0", tL & ",122," & tR & ",158", 11
   set the margins of field "oiLevel" to "8,6,8,0"
   set the fixedLineHeight of field "oiLevel" to true
   set the textHeight of field "oiLevel" to 14
   set the foregroundColor of field "oiLevel" to kUiInkSoft
   uiSection "oiSecPlay", "2  Play", tL & ",158," & tR & ",178"
   oiButton "oiRestart", "Restart (R)", tL & ",180,940,204", true
   oiButton "oiPause", "Pause (P)", "948,180," & tR & ",204", false
   oiButton "oiBlast", "Blast (X)", tL & ",210,940,234", false
   oiButton "oiCrates", "Drop crates (C)", "948,210," & tR & ",234", false
   oiButton "oiRender", "Renderer (V)", tL & ",240," & tR & ",264", false
   oiButton "oiSound", "Sound (M)", tL & ",270,940,294", false
   oiButton "oiMusic", "Music (N)", "948,270," & tR & ",294", false
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
         "X blast, C crates, V renderer, M sound," & return & "N music, P pause, R restart" & return & \
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
         "26 orbs on three levels of an island 60 metres square; gamepadxt and audioxt are used when they are loaded.", \
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
      case "trees.obj"
         put "H4sIAAAAAAAC/2VaSZIkuQ28zyvyA1nNffmOpJGZzLpHB7X0fhGAO8DIulQEHSAIgAjSyaxfv3/+/NffXr/+/Y8/f379+v3zj/+90teu508er/w1RjtI/qplvN7pK1UB58oOQs8g7elq7FvGPn/7rPK+p2FpBDa3Yn1NM5e+ZjO12qqr5W3m5uaguRbTyjm0FDsWwrcyl0KrNjp3Gt3V3OFbEY6o2gllFVrrIzvkPQlKCD4EgzgOuyJdzjuH4qiOYVgiM8IveUIrYm3L58HVhg1Q2gy9bOb61GBHaaexmqUzjS7giSZ/7VtNkQ8t62pqda0r1mrerbaodyzAl9ZzgD0jf31E9z2bZn6M5UP3tg3LI3pvrR8HdVocGyt8tN7H14BatlhG5F4qbFiA7SqOOa06drsdH+MGdWjDjul5FcOoBuayLhARrqveGpKG/JjFbB/SKj0UT/bv7Koik7s9YRbf+6jbBKY9pSV5kCCmDlLkCz3p6fuhC/ipCwOuO5okp22Ndfdl6L5U6y4GrhouHPdahoW1aeEoV4yW5uVCSnBil3KZ6POBFltoiMIEvIAJ+Rz7Ba8KL9qc4cUo3dA6a0Q3C0y0mm8vUn7AdINw1pWDlmcx79bIgbaGsFdegaaZH4mDYU9cun2b/co80uaZR8yAEbMEJJ4N+WaPm2nRh2s+ess3Cl1HzQJ0YeG8rPYqX1leS4df+Sz4wPIahs1Vw2ahszVF7wnNPlZoDual1uWauaMWqvspKxAV" after tData
         put "d6RqlHmrMoEPVfSHqnnv40/qGoroHbWogHpUFoFXgdf+CheYFgPhAsFyZpv5Y3WWMR1jeZdInie0RFdd2Y7Zavtq1k1928qWkq1N6n/NxUEqGobermndpXlWohOo7Z6ZhZ5tIwa6bSUrmjmxqkVUbSjbskzTpv7kRr9AaNaKqUvpUj1lYGi3zdJ0bajz0lalszqloRvoQ9lNDEtBPfscU5AQQLW9zzKQrqjCJsOSCAL1EDJYxsJHHaiP72BrV2I6E1vmlYOSMV37Uk1M163ZLbGlLy7rB5yYw2Pdqk5Xw5pvVQM/Vc0AVdO80zqrpaDbyogtZCSjVNm4F9DdbWuXDzAstI2CHW2HD2liP5jpNtxmfcCifMOwYR6bjeMb6gKOd/sW6mx3eRRYKI+5HKz8ChKFSFJ9wHDD4GOsX6WTB8th7UBLwsy3Pq/xEngsEke7HcnAMsLMpX7nHsrMPaIG6lEb/8rNNt/G8hlWus02trFuZaCfyrBB5aXrTWvXYn1WI6srqM5tjBQlpKhwMRwiWqcB+TAGv4ztPgintTBgEBboAlDoGhomoEwTsj2/rz52MLh96GCnqUVg/ApGr5fNMR4oHCDawoCUqtHWXEqAY2N9HDWGSqB6yBaMMlvlVq1j3enGhE1YRaRAEWnJygyqdmggucPIiTl1toALhCZB686Y0L2fmMopNas7rI19BYYVf24fW5hRQb2Goh0MTuhlhWLCOe18XKaX8blISZZwcXGh6leGCoshXWl/" after tData
         put "amKYgmLavYfNwRrtV30QtHBYIK1crnMq4brREcM61nNjIzY2sRZ53JivVkuEnQyTI5vrAWtrhF4DjTinBqsd2SVSJTkr3QbVc1eaD9R0HYUF03UL9QJn7Tdo/R2UXUtPLHokK1hV16GRMRaJUE01dM+extPJpWtn4LCAGNZT11Doyvd4+ZA6jk1+7hW0TjCq0T0KYRKwcE7jtCvzuB+6hn7qmgXX7WVytFM4XNexSJsPuRDNlw9jzgdqowE9o9UadkdHdvYIcJHaTTtkyFYpR5dB1XxN0JoPXTj2oWsWoHtcsNAEldIkmnUJXVo2POOlGpo8AJRRQjNzbnoojv0cyMLygaCLDFC3thZWF4px1CsDrTTW7XTVzC9n2gWBqaY2HygqqXmoOwzwVFSt8M3A4OdUZg/V2R6qZtVVR633l9MeKUQdIYV5XyncqLiaI6xU7Hoky3HznCT1xm+vcd/s6KVCLnZd00amoqxiuJ8KPV5RnJp1DGOk3qOrEXh5xiVTbR3jhl7jwedsL28uYwGW+zLj7KBYW9oI5cR6yOtWro1JXvfNh11CvhEobdQoiVs5dRaVXDnFXkWmssxEs1NGA1u+vu/ayFNaaFby31xv3UaCmNe64IwvW74WN8Hbz5T3rVqakwpXTQ1bh9SaHhnlYyHdu0ng7iQa0zU3Lud6mg+eQfbTH/0nKFWO/p3984PU2fht0yf5lnjl0ua18fAORPaoohMv4XZe8CyiolqoWmO9XPwqJHzfIPxk" after tData
         put "vUYYqJmq/TKbM83eG0+RleUv+85fSa8SpS0zrU0ZVZt6xtaPrrGDHs7Ky+4n/noF8g5oy2phhDOj38lVUhqJ9im+pKR1WRdtR1P9eodj2v3N/uf1qMNShqo5/fbRr8H1Js1OHb2bQUJE3hHtm+GmF0Y5SuqdrDyqWs3bDWNl6wHNNnjE07RC9dNgzJaCxlSe3S7ZEQ4xWg85x0KjzbALqFsf8yQ0QoG+0JV3+EJX4P+bAbx97DcHN2ff9BbOhq/CFi0GhIt2mxyz+pgeb45BWCjTrGLMQ0wSfs6w+COvk7Or1xEWn0PLZgO+UONNlfDmDih7uit9NjsNMTbPpA+u/r6vGVKP33Q5yrzHuHboRNXtKESmoLFaPU/Nvx5CfcU3BtPDcuWu5fn8dOfnV8EvyD99uO4W1NnwlWNyyDd+9bH1AN4TeRN6R5CMUc/i5pxXh1VTj2+fs8NvoXB2sgeAEiv8qju+n1WjejBfrNLilYC0FC4W9KR4p32tTKhcKtGbN91BBG+E8I7B7zXLysn8hbv0Vn8VsDY+yVKvFNEvTTWXj958QrDIEHkHpBSphqfv8OPOvZjLVyTR7Cgc+uVpZ8LqRwYx4jWg/vJjVd6YrsKaaPuReSsdM45FKa2rkHSDQTtJG27qdYL9LrkvMaZS7dkanbijWLpne7htF18MZTYa7YQG0jGxbKgPb3pEL950I+zSLMJ4M47w0wOPgd8cmVr3bvSlJByrx3pudo+0df/+rt0UlfPIVezs" after tData
         put "167pdsZVXdfKmkYs/FgSQS1LudfoNK41mVpUImI3db6tCtSeGxPUqOVKl84shDgJmgJDuPIWt+0FQ6031TDfwDjlhALRFQ4d873q2ZD5j//+589fv3++/p7++Ocr//iRX+XHj/Kq588B9F3Rdv6IxmnMVz74OfQcpSmYtUxy9JZg/cePje7jvLotxWE9z2M0vfb5m195yeOgaJpM/4rq6XJO50X/ii/w7rQgyuWJ4jGA2ovD+wPe9liE1wOehJtGKmi1sAVEU2UlSSOikNgjNGtC1C0t6G7hZsaLpsncqOVYwtdJOYi9W+oxHeUYPqeVcsYq6VXEkqYfbUiXtA5cZS7qqx5DZ8OpXR4Cow2p9BUHrBthMxlGKKW2WXu14345bmd5iM/WhtRGCrgd+KwIoY02OmVpie1s8AnvrA2mJNrWhrQmaYm2wM2lhNmGdMlDopxWZniwKNCGtIwP2CpJPDG433CtT9jaGqXB+YYrjWC2zDP4KdrW5lxyitspl7OcdwlvvLrkoB8YbUqLtAQWa/vVj62WXn3LQ2C0TTqkr9i2bt4pfRgxaWirtdc4c3sOoqPL48BoQ2ojBTwEnpc22ugksBSEvbzmCe/QXlOSL8bakHbpJJ6MA/fkUsLsDWmRh9i2aZh4cElBG1IJ/gFrWz1R2F4I9/kBW7kMTrG9EO40gtkyz+CnDGltziWneJ666fk1T3iH3c0uD4HRhnTI48BL2vO1RLpeS7Qlg2xDKtqyvq3jWd+0tZa0" after tData
         put "wjalHHIdz0Z6rePZOW3vJA+BrQ3p1IfAFvxs9uAnhTakq33AePC7tBfCOz9ha6snCtsL4cV8W7gKj4JUiDbakBZpXeFoMq4orU3pRKpgZCI1DB5tSMO25d9mC3Mn2tbm7HDSttTNa8vK+9rb9lW0VJJTws6dpu4SaekeljY2b7ZNmhM2NdlTNixl2eq2G6YMo2XdgM9mlbptbLIT2nbnCDUqt/NkH8PGPpt8dghg503rU4Cnb/eZW7pL+qfEEDhmkvYhqS5JRma6beqaHcUBUD64JXuMRbf6CB6AyzP2ezeNpORIChGOFYNg7pJO9uSMJpthCDmjJeu2kEvR7TiXiv0hEGo0bOC5bN3Bs2yNch0uG6juyo64RsHujt4hMeu3NWpEH7N7nkO38yxbmm7zgVAjuQeQNNvUrz6OQEN2QqUBeDsaVXd4aGofINSQDbqab1V31dBwCRHXaNiILbfFNPTpJUaEGqV8k6A8nQTgLSRlf5Pgu6hOSe3tkrg1zrJ5S+/VGhCvA68QoSdDcn1iH6fOhdwMyzURaixpK9UX4imE9lidQvG7PFVChBpDnmptmTVKzPptzTW8j9k9JPpUxjkPZdkUZ1daDYQaNu4tkV32HHvuPkTYVySaA3s7khP7ytTUPkCoIVv8Mt9EUi4NlzhCDVlRbE4xc4NPP30QoUYb3yQ4tziNwFtIev2UdNTd8AoZ+Snpbo2zbN7Se+0DxOvAK0QIzjpfyZTYT3UJPVpab0RcQ45O+mXJ" after tData
         put "HrjkhHQ09lkpZOtcmmsiriHLqa4usgXuHFZls975Hsc13APZL7ec5I638nOYbOjbPCBCDX1qH2RnJjz9CyZCjZW+Sfj09QD0JCTzmwRzu3y21/iQ+PxYNkyyG7OlEiLUWNJ+RNosO5EDIq5RmVFam8jO8uw4wvFiHMyYzTJnXSVAfE59treMeJAtuUhy8u36ojLHqCSOW7dOkR6YTwjKE5L6HphrNRotSSZT/lnWNt1+XlSo57/AXCspokJ7DftUv8e8tNyhklQolwSKnZOb0py0VOgYtbKa2A+hkgU5VhrP0DOiY6EVPaF3h3LFScy1YOuaEvp4pf2CqDMZh2rp1QlqdvsX4IhpmJVbAgQJLT4Tt2R9kyw8/VbI3kLitK/Y9YrEuzDBesNiyQiMWiUmXY/aMil6npccFw/5wlwr+wTIfrxD/wCFaQyIOj1sbqvZUgcqqjYvJMdCa3plhzesi7q8VhwLre+uwpibVxkxV/IwqrEV86pAtbifJTTKNwkvU/zmDW8h8XuWkKCvX+LhLSTVrWEKr5Rhmp9pdK0rx4ufhBfNVSvEXAuJ9etUsSGXUnJR1+TCs9qtXn8Jr5E7wKGGTq+md4e56z1eFvuqoqeA0Cyqop5OdLAb2+ZW2F19GToorOhnYT2T+CCOCCY83a7JStFLs6J3a8XawrM7pAKL9oCaXciJ4Sbayy7/tt5JFalgYbmnLTmuCVIxYm1hKbXo5V8tuKA7Y9EWjZicI/uQwleqXfLUpVc+" after tData
         put "VW+GhraF1bQMqdywHO1WoGbXSXrxcrRb06ur1vVGpUnyhGGdttDCNiAV2Nqyv7dlV1cL10tnLNhyIybnyD6k7K+92pm+2Z1JxUVAP4UhUzP09qBLlLK4jqp3D6PpwX+INtWEd/VLu6maXiMMdOLNUHNbNCJb4ultLsCWwOhd1CHzS0+acnzSg2fTc3/lcfUUrSy3w865Q8+3E9WYrKh1b1BiAE2t00ePhfIfVqLWE5cbLSyGJf0Uh7lCg4rDQhrmWrU6z1pQOOzJv5XI4lLsoLgM0SvsTg09WHUtOujikKmjyEd/qtSOt9uOUVquWQt124G3JmqoBIhUeC12vK2Fx04Z2a2GtQRdeBIeSKENHEBmsgPJsMNLASKXApUaKpH7gUZdHHw0m0P6DDtyzWnUfuo4UsCC6CFsUUOtAZHKX8mOXCvxKCQju1W3ZjrhSXggVbo6qOIAce+kmet4INdfaxlFXZoduUfbHUR3GKnc1ge6SmPn3Udu6kRXyepiXz+8jLAa1uR+Tq1k89GsqgewMhd8VF+1j24Vheyvkg+WIK3zYPoyjEadF12lgRmlyukh1Aut7OySrE7vm4p+BaeDsT/92chMBEdst4mrJzvo56Napq4OZYvA3WZMuinpmGdb0u3pfJHYB4dTmCxsSDfJadzhvOgWpXobW678MKUblP1UZb9/pMsEtILCnKGq7voZu7F+zjGUUin5p/lrzJaAhdumpWPSGvwIs9zSC/db3ddlxedWPW21wWJj" after tData
         put "mzk2Zdu38Yvo8Vr1bYOOTZmbu/ScFy2QwTCObubY2LstwGJwme4StbzYdVFWn6i1bbhFUhFwI9xueD1RbWqwihqfYBwMAIyC/KKQQYBRgF/IgtfxW56o2S5vnfhj4yYnMD5xMQjjF3qVJXVBRgGpw9abI/uQ4DLGL6yvpBSMAvxikEGAUYBfCCfI+CVKGAX4RSUNMUYBTmB8IhgE+YUwBCkBMApKCbM3+AWH5FjGL6xv7PLkF/IzRAuqQH5RsJ2DUYATGHHADz3DaYgxhOAE5BfS92InHJlDglGQX0xSnKlls62kJmuKbUj7E7a2jmxwe8AseXshvNITtrYGrzC4DaPycIxqGNHJsjjelIVUZ+ATJ7dxrrP4lTu5AdfZn9SEZMc+mYsw0QMMTW6zYS+TddmnbL2W6duX6Ag19qfEEPiwnHpdkuLftb2FJLVPiSGWFawFRrsYaoTovIs8bDnLIu8iD2v4QoN3kYd152zgXWRMxrpulkUeJiu+LgPBu8jDXOJWyMPcA+dd4GFmQ9dy8C7nYcVZFnkXeZgwpsprZdUF+7G+vAwXlkXGZKzrwbLAw+QkMTXVzruoERJYcU/CAzJA8DCzcbMf8jD5pXWNm0s5D1vkOORdZEzGrfyC9uJsxqBuxkQeJl/hfrA59yQ8AO9yHladG9oyoX3lOb1EHYGG/tr7kGx8JNsLfqcPiX9Y9haSOT4lhlh2TEJO6BF7pKSEThJJsW76d5FEvaSYfn8oDM9JIjhfXEuW" after tData
         put "YHi0/2R4ThL1Z8n6YJVBEofTv6CEbsJ7Xk5m0tzwNiihsy29ZexPnuYMT+0r0XBKGCSxB/3zDiSJd08ncSSJ8MLv8JT+cXAQQqec5Kp0Z7mrKzRq/SYhf/I+9haSur9JNsZz0uWsi5JgaUxgENgrk6SrHjuy5rxVJ9l+QDwz1Apf9ALVhI65Vguhpq1RKC96zdbCbLu1WgiVQHd2kBe9mFO/A3OtHkJ1aLDDoLc6j4G51gyhZuHMrf37jbyoi/afccRCq4RQR1gUyi2UhrLC7Lq0rKcK7WezzQ7yosHpWSYw16oh1P/sS+igL1lfVOiYa/UQTsxUX3zZPmWBUWskFw5OmQnPyyg+ZYFRy3qqcFTMlHWQl+ZTFphrZRd2Tpl1GPRWpyww14rJ1h8v66nqMfgy9UWFjrnWCqH+82ShUP5xT/NYwmy5tZYL9f+6amUHeSn6okLHqGUmajjU2KHRW/uvQsdcK4dQQq4na7qJ6Yu6qOkLzLVGCHWEkzXdfPRFHdL0BUYt5cMQqtlJ4WTPGWbnrTVcaEYWnVwcSD8Hx0KrmvD/peXX7RxNAAA=" after tData
         break
      case "trees.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0DM0MQWSpqbmQNLE2JArDyptCJE2MgISZsaGIFkzc7isEVTW0gRImoNkTQ2M4LLGEFlzC5AuU5D5xoYWXAAfHp4QeQAAAA==" after tData
         break
      case "grove.obj"
         put "H4sIAAAAAAAC/21aSZIkuQ28zyvyA9nFffnOSCMzmXWPDhrp/SIAdxCRpUtn0OEEQZBBB6P6118/f/7z99evf/39j58/fv3187f/vt75R29LflIar/Rjz2ZoXVV+8nodRs0PUKgBhYND9f7px9rd+68HZL2B9ZLlpy3BWq2G1pkvcxS6nP1yey+G5rwuN6f+8KDDuwNQFQTzzCm71xP+BlpSu2MdZ0DvDI6tY6zpY6UfZe4HVcFPpvV3am4hgtEGZtBDZtLCFMpdgSSJf6A6mINz5+u2l2loG+WiM9HBUG7NVQbbhdwaEp7mg4vAPrjmwblzOXootmEOOqS5q204UOsO1NGArtIvtRUuTqD2WR5j2cwaNye4yAK5292eKTh1hin4XtypOjUnRNBSvxHsNR8ottJiDma7DjL38ip3rMElWy1fap0PquUbVA/288XZNW4lRhDcJh9rl5vZIRtU3hTbn1syuKdieU4drwm97BZBJRJDZyNa7zN0Cb3b6hG0YYg1neWoGtVQrJ/gyNvdHK6ZL2/ojjidcwdRctFjZxuZvUEUkMzza6mEy44Jtov1XBVcN5qJhJ3W9dfmpWHcJ88CBK3vMMSeNpM1PJbjYxULZnjnUVeAbFxibfTQd2cQg8OWt41yjg/ZJlNc1pYVHCOkYfcH07p/MKU7mdlPcvPZOfoUfhYsdc4mEHuy1BZ9IUEsNp9ha4BhZo3DICAMM+YjlXQ54FJe4oFl7ddlKxsBbScuG7qHCXZk" after tData
         put "sof0EEtr3jGGbbyVwxh9IRG5hGBaJMIjiTOAN8IwaaYs55Axm15pO4TD88OWMMkrezRwV+reMunQf3t7kA395MKFk2ubDmf54cmiW2A1O8BBbqao8NGrH4SBvDMUYowVPHdXdRuwrMd4IBvaqeup1OB4QWtPmoPjs+tAPut4yRVoPksYohjjAWM8oumouLuY1PZRd5j1WJCatEdIEc90kC35zkXINhwi9nQa17O5R5j0HBvoOf/v7LxCKcMWQB3PChGbyO7OtvI5wM52WJ04251cF7prHYSDAJYx7zxqB1r3DuS04bbXQJ6Zwj8it+TgwoOACyNflGR7E23mrWM52grrnNG/rxnyMAY2bF4xD7lEtsNPtjtx9sxhwJZQCK4aXsma4KL0GWbdvBLsM8zP4daC58QS84h02EM4+vKUKjItzd7IHVplh0dtVlNd6kUj1x0Y9YxR9gUzZFsK+rNp7AU13tBTDby+oPm5OS8bdM4g8qTk9TFuOBxEmESdupaPPDvPzuswDxO6PYfTrCQZswaall0G3iEMlbqyetRUtFJu7wFNSnWSt2p23nVIYokTYYiSsDtpZmwPD3zviiQuH6awrx35Ir1U54rrlK1XXhd0Zl7e24noPfckqMfSvqh1D2jbMfKMZZijOVeqGPN7KrCYkLaQkBy46/ZHBLe/Mh1dqAWjz4K6b0dsWurSivG3blsh9R5HSvtyPQMP7p0VuPZic2duyHqNL1XbC9VsDQ7mGBf1EIjWhweW" after tData
         put "bDHZbVL32r0RJxynK9tZ/tL7KvVxGHYeM8+l3PzSuVy4wxU7dejPskypxPLG2Zc7HJW04n3LwM5L7VbTC4tUS2PnXAegxaDZMd8KOWeUa7UEMFkdnnLx+W68kmndAQq6jhgI8zJqPPZ5ZZtpWv+312FSryALOkfMefZwXG8WVrvUKKDFL6jL3U5evKG8mtOJWqTU6HYlFKY1x5cTlyys2MdZ0a7TNrGDWujNi00qYQNmnALFtuXjeJVTjrMvCbXu412Z8rb9eYBXUm1e2pJ7/QEkC2jLBeyVpXFALZLlgeykH1z0Wi5I1r7mSw5qbUrsfyJ3h4yKkMNl+pTIFdJub/ZDBO9Mq/HfDOK6pVfM4c1J3CjfCPMO++a4STMR6PZWb3hQHbJyqHPuu/qhcrMHHmkSA5GxY9Kqfr+De7oKntjvzY7p5QHKJ46YgZRjhmaBdf+fvHsa+81jZcdmS78eGyPfxWSHfIeNacXqw6phePBxlXJYaOwnQjoTjtjdXIM5bDe4sOz2yHlkVy+cSGUNoccl/ljPR4joygHo7noLy4fYRabxZUX7dMvNGujgI8l97U89LeiiwWnHAngfvBaFPsv0OSzumnXn0Jg0jeUdgmmTGfKtzMEtHL1VWqfGTtte5oJolk2woVmuS+zJFqLjuIOrNz3exV3hI5fhu2px8HV3cMOitkubGLK4f+aM7mOifR/Sk0zc1h+JxvvTYoyWU6a03e2ziG3b7+y1u3mp3F61eooQXfOd6k40" after tData
         put "lhvK6nfoFaakawVO69YFwVvLR20IA2YG8Uhud48rbEZLW8WRap95daF4rNg3E003ctscyHE/2jzhiL3e7Pa+zt/Be7u0x8toVeFs4f3XOpmI3af6Pf7fFyOU2cR7nr1LigeRYPGo02rwvpzosuI7bm5XeEkM8deI0OPV8o4tnJUghXXkgPsuPMbbv/3n33/8+uvn62/pt3+88tdXfpWvr/Kq558D6LOi7fxzAMFf/eurvsb55wD6rGixLjl9fZ1Lzel0yrKDDcGspZZ1Hg8kP9ZZjfSkMFzng+RzqJ/mKXXzlJbAaMO6pHXhItG2VynyIzOwNjuRbXYGyzC1BZN1ZFJsdGYBLbN0xCU2ndL5V1xgTqdlFu10QWvq7BW1B4fHBzzsh47tgXAhXLrOYEgWy7RZoWUWZL9WnUBtmpXKKbBt1rKRrCoPYL1awk6wJmyVHqZshdZkLVuxdbQWLN12CUey1WkDuUYb1o8AtK/5Ea/WMgti0t+pA8pPR1bYNmv9gCuWjBm3B8IaSoStU+Fi2gPh5k50I9vMdQE8D7AwN8M2m60OV0xbMFXuw3ametSyn1mcS1TP8iO7ydq0yluomywbTV7N/epNfgRGG9ZEJyeoc7724+Qc9CNJS2Br0yrvpb7zw2D42oTRhpVDjgMfkRgy+/Nuy2suk2QbVuk0A3yctvSaSX4EtjatZJudAd64rQ2r9b0ZtBBuqtCmtSLAbq+YzCpb2u3tRdusoz9ha2tODN4RHu0Dtl0z" after tData
         put "6NseCE/Cs9p0miZ2dsySbVi5OivrdFbRVC1Oh22zzokMrqmzNtprLeSEbVgznXTdN7voSu+EJUab1opdhSGnrd1uWAa0af2IxHrDl/hGG5F4gEtztG0ZdkWq0IZ1fcK2SJPLYA+EV/mArdPkEtsD4e1ObL8jB7YoNye0eqqabWwsmq+ltWnljt1n1qc62Gc6/Vi3tARG26w5JWmqgB1//dQe6Yzaj7AlYXS1ECEjS1sFRp42uaddpK19iJDR3duJ5Nwzs+iP/CkjN/lVb0CcIWdaeURwpjqO9IoWDxVYIs74Fpt5oVe1AHGGR01ppGS67l4EjPTNYojm1/bNeuAa4dNgHTffd3twXCdpQ9gieYJsCR8ZI+HmUjPkm8BXH8sOM9KnRQGSIfWAJKdUpssRMhrTZZzz2y2MMji8I2QUeqvJIhBtkpBrQWgXAaP4NO3pejXmYxwyPIKKzVqxMapvZ0fIWNwytLRs2RGltewQ8b7exzhhXnc+QMgwHzHXFS/JzagjZPhrU1AJFpSA5ZZzRMCo89NSsQWrF4w1f1jGNwt2YfVxanlamlukWpK/80jZIX9OaVPaaiFChlQwmjcRPfnvAaL169TDXRiaA0fAEHFdWr2L9J3LHbingk3SVgsQZ1T3dmKR/0Ajwih/AR5FfrXoB+KMLr+PCE4uztU3S82wllqAkPE9NvNCrzoOETI8amh2hmhnrwguAkb/ZulYWy8b8XQtvX2zoG/zHdLm0zKut2UrxyzZSsa8" after tData
         put "OeNmdFh2fLXvPgBChuVR+yArUrFIlmZm3og4ozBvxjm/1SKZjRE4QkZyb8siEH2UqFdibESc4TOd2L3udbuFCBkewcKuXdghy/e1I2QM7h23bMuOKL5lh4gzvI9xbtRhPkDIMB8x1wtvy80oEWf4+zPx1s+KX1aWFwFj9U/L4nV1u2U/Lat9s2AnLh9npadlm4UfH+SsPfusydW/y0eAZt8a5PQ8k5Gbtk7eGjJuIVbEk344sOt81lxso4j6dnTgx4DBLpdtND17B0iisxKLBiFRSXfxul6iCXnbxWzzznvusodV7EJc9LYhd6yiN71i176i99aqbXQyK2+++yVvW7H7YNEcwKl06sH30jYDUqvA6K1jXSdymNSkN7Ka7X6WcEWs/TXkp+n1pwobbb0HrQDLnQq3O9y49HY3lSZnQsvoxPta8U7ONprsNrEqSSKZFpkFZHHKjpAtcS44srbNiuKGS0g7dxOplbteDJpMXl6RNrXSbkvr7qYVWdY2OpmVl5BTWwm8tfxuEiCdinSn63sPbSMgswqM3jrWdWIFrGwwqSNQofXGwrmfLZyk9pgoX60ElSorofxDUT/0lJDtqwj6GoOFs/iX7T66FobD6nO4l4pd/ovBHUb2/hghRGXoMOYEAwdn+llioi5bVqeNydpxnphlA45tFc+wGgiI1D4zR4t8hZmFXqzCmlZVbuNKXTYr+7Jym+32DX3AlW8rs5GpsW1EixgtevUm44heihfo2FxeZxz/sslX" after tData
         put "htrbx0U5bRp0EjXQ0nFkywvCvsZgnSH+5RWR/z0n+rmsnqF/OV3SY5xliMeoDLXQy7JIrje5RO5s+rWL6dnO1Nh9uLJhdzVl2HbiARGN2P1hkQgGvZgSbd0g8jYIV/RrT/alwu0V+t4+4MpteC8yNbaJaBGjRe+KIKurYqCysO0AtvPfdEHo/EhcqAwbB72qAY75aWpCLTBlkF2R+5UPKkPD2Q8toDKQrUOrLnB8iAFPYpHRFc5tSIMcyPqB0sSA0lB5+EMMIA3OtuMc0mAj4eOtiIENYVJAYRkGD3MyGMmgVUeOcLYfsu3B4fkBT/Nd6KQ84AQYyYBIeU4gS5iV5UAOf8gSRGri8IcMUaTkY1Hn18TlIjWhN5Al6k2HxFGWTKRkq7V8tQwiZWokmgBZgkiRTVkykfJIKEvQBBGWGhQEIiW+tJgwWaJIZcgQZQki5WwIi4mUjYRPeyJLNoSJEiSumCAWG1KXAW1a9xO2tjpR2B4c7k/Y2jpLc5IiPLl9kAzIpecEAolZWQ5UpqiPFCO5Q9eHgFHz5B6u5wb10fWyuxqSC70MfSht0Esblx/MVA4xnskjVbfAIr+ZU78IGLl+s9jLpt7MYk/Xkvc3y8Z4zb21D0txC/LlYn7zlpAVzNiypONQvanmm3ro6k01Fy1N/P6iikw131Rkqrer+WRN4OoNNZeDZ9ao/K7mjVpN9XY19z6u3lDzGxvV25WyyO9DXanmophaLVC9Xc2razXVm2p++0B3qeY2" after tData
         put "Lr9+qHpjPNNu1gSyYn3gl++HI2SM/M2S8et9xvqwzG+WiXF8h9hTsPhOZL5Yady8sbLgjC1LqtWsLFhpqHbHOsIrDdH5xju0VgusNCarBVYWXi101iteWaDSkKNrz1iVsNKwekJveqwsWGl4H68sUGkgNlYYdk+UKM9c5cO7/kosWlc4QsZwi/7196ROPwLrw9YHNToGVpFXkkapKlKmMbNnvm5zZA0a4aRYgPagA+kiEAusSmORs+IcfOeh8EGNVY2OOatdo7qVOmrwQUPUP6tfzFnrGtVtp7GzZ79ue2S1a1Qng0EODqRlxcWcla9RMzlPJZf4oEb9a6xjl1WuUd2u89D4oCFqzXIxZ41rVLebxs2e+7rdkVWuUf8/QkKQ+qB/805qdIwsDRtGyaT+R4fFBzXqNrkYWVrf4r88qNuzTfSzsz5UfVCjY85qbjS3lcbKnvW6rZGVrlGdNAbZOJD91wzHnDXN+D9K/W6qAj0AAA==" after tData
         break
      case "grove.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0DM0MQWSpqbmQNLE2JArDyptCJE2MgISZsaGIFkzc7isEVTW0gRImoNkTQ2M4LLGEFlzC5AuU5D5xoYWXAAfHp4QeQAAAA==" after tData
         break
      case "tuft.obj"
         put "H4sIAAAAAAAC/21WW3LbMAz87yl0AUci+JB0nbbpTGeS9qNpz98FsCAZyT+2sHgtlqDs94+3t59fl/ff31/fXt4/3r78Wx7bS9rTgk8p+JScAG4vmxzqkr2qq1ZGlnpFEVrLJd0ip/yc50Zba/gs+XCwSJt8wshWRvoWRfMhEyq7o5IsdjvbVMCJbptFkr14RDlnbE6WXJ80EjmekBIpT/j3CsnU8OlnJIvOTuFyumgUYs4S6Uz5lurQXH+eWJ6N7KAyj+PW+FwMzNJnUzQ5m1TSJ9RA0CLFKX+AyDquybos7dpHwfPCaCSLr8Nux5E8OVU/lpQNPUeoMqnVZZhDt/P0DCGlfZons32aR+fkpXbJU/W55RyaB9bDXPpLXAf1Yc837gq348ZI4SLX8YleJh2VP41qlS9T/dKHZptgWDsUw7cNaRrue4RdsSeZ6nPlqlUZHbQhoL1DNmOyXAfxbTLafK0wrjpli95ndnlk6oMWLxZbi0dBKODnDDFxyuvlR/VgMZHoZOdMsRw/osCUhUWx1FWLuxT3pGeFY7z7dIGYZv00eu2TBOaD9AHtIFv7zOqTpAwbUb3avBVsOvVUgQ9//8/VfXHbPk3tL7tjWqZiYpyUz/Ky5RVi9i60O9iXcO8ihhLZznif5Iqgx5OoGbtTfTzj8biP+bjP9LgP9bhM8PfPK35zl2/blx9LWte0yLrKktc1A6jrWh0lYM+GtnVtAPZ13ZdjXY/lXNcTgD0bmjYEW1nNSrTN" after tData
         put "p6Bb4UNXTAEYjfA2SgVfZUlolarCtOlF86TdgQJE53Qab410yzyCHrKNqoIvmdLDphc5+P0EjK5YKEEYfkYFhEUZh00vBsVvMOBTmyxZe51LxjxZW9IOL9jhDwNgFRL6ohdOP6NW1pZh04tOWcf2hyWDQm4MUpg2vWCSlWBBNl7G9BaVYIoObxRxFeIA4lR4HO5zfUblArqlLAXeovTCphc1ShusC3jhp23Qo01vjzZpKDNlG7KG6F1t2pQ11PZhWZSEFKZNrxEYh0BvVztsem24sTy22H2n3eI6xpb6vvHW2B7GHaKHl8a3vadHTde1L0HsRsC+In22sOmNaL2GcX5xqG65xy5Sv/W6knbh7WKrTACU5ZKQjN8gxbWEW+7B7OkYoCAG/3ZE6ygx2lEgot0fSrAVrfBZps4GrvjvFqtx8hrTprcgN6vCBWll6xtzuZj0etK43ZEU0WHTi04ljQvh74bxmgqb3rgnHN1k6i8ftyhKqMFRvA+7Kgu3wxsTxuWgHtdo6mETDPXo7UVi3Xz5+tuO5+SvUj9tf+bpxrHGtfB94+34D3bITYe8DQAA" after tData
         break
      case "tuft.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0DMyNwSSZhZGQNLEkisPKmsIkTU2Acmam5oDSVMjUy4AKc8msj0AAAA=" after tData
         break
      case "isle.obj"
         put "H4sIAAAAAAAC/3VWS5IlJwzczym4AK9BfKrqOrbHERPRbS889vktKSUeUDWbbpQpUkLSo/j6+fn547fw9fcf3z9fXz8/v/0XIr3o6iGmVw7t1WphLInZ2Kxu5NDhm3oHWV/XeTFWX1QLXHSpEFPw0g0MqTK8NB5D5XXmE166XDdG3znpRw8wqcUHueh68UkwPinGx+1PcRis8EtiWeWSZjUREz5XOHqJ51JGr2V8KFN8qObTXmtTBH8PaD2NaOpD0x96Gx96FB8abpjlQ35ACWEx29Q3nASng0N6n91aBTap2Ve1UcF30BHzUc7V7hJ3BUSMq3u8+2+juGTNUM4jkfZKV3aHnK4FcoSLex3Bh+86FsgRdfaEWGGBHEkj4/w23Yp3/3iPE+/5xYfY8SHp+HDauNTjL5kcyvL31LplwdLbbmq/yjWgcgFq712UNyi+sbEz+tb45Bh/5dk8ioVY7Dn56NnHx9zufmkC2uY0ad2OztaRsfsYTieAiyB0kfa6nGKKs6erRHSG8bBIuILHGCFuGkNi3bjtS7rTQ8U87YjblnGce5Ii8e8/3/kLFX5P3/4M9fz4KDWUhn9d/jFstrH1MhgLh1syuOVZZHiDHyLHqm2bat28D7DkIevs3Yp70+xd++ZdAO/eHayHBO/erbl3nb3rDlv6fROxCp5+ynOG27HBdsrd27rhFcTC4bbD1g1vAxYO99Gd+Ryh1BWGHXo2uOcF9jZg4XApG4wa9LJm0q2lQ6TM3sVr" after tData
         put "At69e928jxV27/ooYt4Vx/FJz+zACH/7Pz4osC4xoGtFWUo8pECBq1IDi2gGslZUGsAAV7aFzHn2kHlnE1m1QLBiF4gDHCGz6hkybz8FgwWGdQ/BOMwFC4xgsMBw1EswVs8JEQMlMQRV07jLkpFogeRQfFaSf3JQ2CA1EQbliL77rQlbuY4aECeWyTIiqRSN1J2zPIkD5BKId+Ya6BBLYLONPcUSCamWeaGK4msmuOYKklbTJmg7GNK14UXSb97iIn+799QsMFIQiYKFncZcJIzZxhY7K+o4juH5u21stmIXnTDNyPITELZyhOnj3XRJ3/hv1n+YLzZBnQt2wpEMxMJQUZ9R2Fo+8r5M8IpiC3k0LAytK1hBDYHJSYcLObQJldLOKGwt9AyTaRSHywIfCvtvWYonN0g+UHSMdD580E9n5a7Kp31w8qVTTkm/cSTD7jZYGbzLfoD8djCNIe22sZJStnub9Bahou0ljKFYoOSupmKXtsBStQofG0WqTsq9SfrjkM3N4lhU8TYbrFxy1N4icgUSBpe6XYlsO+va8sGiA9nqiNJhc0uDO+0o8j2lE8WxSuHuYNM4aeH5doXgQM00EvJ2q3BqOIGdRzRgO0t+EPnRJ70cCn6IJdllwbax+rmWImGhV0ohc7KLmm1j9eFA/gAqg3XYbWPlc6Lt0uEx21i7i9k2FoMl3jqBlrBNp90cbBuL9Md4l/dTyF9I1/rMcpY2mLYXUlngusF1e/O0Be4b3NdXjD9f" after tData
         put "+vqK8XdKX58UBtvLYjwpHKb1cePPF1qfFA6X9XHjj4YyPxL+B0tbbz2NEQAA" after tData
         break
      case "isle.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0DMzMgeSJiYg0sKSKw8qawiRNTE0A5JG5oZA0tzUHC5tBJE2NbIEksZmpiDNRghpY4i0sQVImyXICFMTUy4APHUw4noAAAA=" after tData
         break
      case "roundtop.obj"
         put "H4sIAAAAAAAC/3VWS7LcNgzc+xS8AJ9F8Cddx4lTlarnZBEn5w8+DYqk5M0M0Q00QBDD4Y+fn59/fgs//v79++fHj5+fX/4L8fhoNcnXUUL6qD0xeIhNYma3lO0WUM/mDiUVxtIHHTS8eK0Yc+amEQqxPNw0rWLHSa7GyzUy3qF3hninuPXii2B0xfgmGV814y/iXzIJmrFDM7tvzoqbyJVbmh6963Nno7c2vjUtvjT3Lfi4U3R1ecl6jBg77LdxeJ54fDm3+DYGAJECmCXxtD2Ns7QN+UH2MPXW6dH+I1jyviqObt6Jp1peJYfiQ+SpcXjZfQmIz4htTJfaGWop3MNRCrlDvfoC3UjSCVBhXi6QI+rsTqywQAMZFbe5j2bFp3985onP+uJL7vhSdHzZbVz68ZeOlQ5cz9LjLNhx25faH+UcUDkNanlA1DYo3tiIjB4a3xzjrzwvz4IUiz0XH736+Frb0++YgGtzmrQeWxcrIToByKcBF5nQRXrWWQPE2ctVIjrDeFgkXMFzjBQPjSGxBm5xh0Z6qpimiLiFjO08ixSJf//5zv9i4bfjyx+hnF+/5hJyta8mXwzDBlsuwLZwuB6Aa5pFhrfxQ6Sv2ggqZfPuxpKnLLN3ze5Ns3dpm3c2ePduxnpK4927Vvcus3fZYZTfNhF08PRdnjNc+wZjl7s3TsM7aAuH6w7jNPwYbOFwG6cz7yPkssJmh5YAt7TAfgy2cDjnDbYetLxW0nCkQyTP3tl7Yrx7" after tData
         put "t7J59xV27/IqAu9i2/FJT+zASArsRIF1iQFdK8pS4iENCtyVElhEK5C1onIADHBna0hcZwuJI6vIqmUEKzaBOEEPiVXPkDj8FMwsY1i3C8ZpLrOMEcwsYzjrJRirp8MyBjrEEFRNcBeKkWyBZFO8V5Iv2ajZRmohDMoWPfrWNFu5Zj0gLiwRKiLpFI3SnUOdxAlSDsSR/MyiLpbAsMGeYomEdAte1kXxhWlcdQUpq+oh6HEwpGvgWcqvfsRZPpufKSxjpCGSxRbYDVwkDWywGXu1Po5teP1ug01odtYJ04pQn4BmK0c2fRxNl5wbfyb9svli06hzwU5zJIC2ACrqM2q2to/8XCZ4RS2EPJstgJYVLEYNgclJh8tqqBMqrZ1Rs7XRM0zQyA7nBe4K+29Zmic3SOrWdBvp1H3QT2flrkon/nDSpVNOh/7HkQy728bK4F34AVJyjSHtNlgpKeHeJr1FKOvxko2hWEbJXU0Zl7bA0rViPhhFKk7KvUn645DgijzIKt6wjZVLjuotIlcg2eBSw5XItrOuLX9Y1K1aHVHqmFsa3ImtyP8pndYcdMruDjbByRGet6sJDhQmSJPHrcKl2Q6wH9Ew21nyjciP/tDLIdsPMR+4LNgGq3/X0iRb6JWSCU64qNkGqw8H8gdQHqzDboOVvxM9Lh0e2GBxF7MN1gZLvHUCUTCmEzcH22Ct/DHe+X4K+QvpWp9ZztIG0/ZCygtcNrhsb566wG2D2/qK8edLW18x/k5p" after tData
         put "65MCMF4W40nhMK2PG3++0PqkcDivjxt/NOT5kfA/3ZSsDbERAAA=" after tData
         break
      case "roundtop.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0DMzMgeSJiYg0sKSKw8qawiRNTE0A5JG5oZA0tzUHC5tBJE2NbIEksZmpiDNRghpY4i0sQVImyXICFMTUy4APHUw4noAAAA=" after tData
         break
      case "lift.obj"
         put "H4sIAAAAAAAC/3VXS7Iktw3czyl4Ab7H/+c6tuUIRcxIC8s+vwkgQYLVpVUVEgmASIJd7F9//fz5+z/crz//9dvPr19//fzxPxe/svPhK9S6XmPqDMVeCEzyylCKWaFQhZVqP6HJgOErtmKwvBEtECQ0SWKpmUy2A2kkIf6F5d9pzwb8S03/2oL/XK9/Ecm/tepfddJ0/vR/Qv2R6fTh3xQIcwIzyxM15/xQ+Er2EepfYr1p7WMp/q2K//vwRx3/uiD/2Yx/1ca/KeFflLVb783e7+3zj/078OcOet3Ce+725uyB8maiPsH34M8qb0t/X+RbP+Fr1i0HGw9QMf/K9H9D7aFucHQFaSto43qLBhHWwTg02cAaikI5CdTiCR2zWx7Am5ksrwxdSNEK5ay35WjBZCGOxII1thct0LrWzGchLXTLA3gzk+WV1javzviUoOb52e0GJTjZ0Ny03VqVlUyFYWkAL2K6aVGhCAHOMopuoi52AxKG7DtwqnJlKmQ2otRieQBvZrK8YYpk5Y2oPSQVfcTT/wF3Yzu0H9FTAyuZ9fVueWjuZibLa2m3iy3sZsHtApOFWjL9o2bSXU0ZFdcEnbZGsTyANzNt3qJlc7YbT9N6TumfIJ4mhZQHUIKTDR0H6SD1YSukQ1PsIqab1hXqsQlrmnS9DQMmC0mo8jQ4xM3L8jPY7Y9b79XwFLyYafP+oCqRd44PLiD6lcXOVWXx72/lCYoC0V7zQ0z6LHJFMWPcASMDqrvS" after tData
         put "QFBsHERftz/I+WE/Q/zL6vxLNf9Yn38s0L807t/adCvLs7A3lXcW/5bGax7bizf9x0PcC/8EX4PXl3AvjXvzpjlu3pvuWVmv0n7an8299fbW2rP6S/GGrZiPrUBzXcymomQzBCY72E2za7YOQtu9ZtsbLTdxxqHq0I8yHYSCnmTqahIzFanfUb9LNmVzMm+yDUgp8R4JvGbw0nyIz62RdHRO3fZdR0onmCwE7Swc5pW49f7vf35b/3LcP8OPf7tUv7/XDSJleSR6EAwb3vaAmzyKwuWC+wNm25UJWF4UzgFwDSbpB1torsY7twYpW/ybvduZlv0Bp3sl6SqZ4wNGiQxYXjacHjBy13uBWMnustr2zgLrSpKrq6vZ3Fyt9CAYNryNHgQvRdfnoI71GK5OsgiGLd4WyFpwW7XydG3VKsG1TA+CYcNLlSbBq3aJrq1a69LUOlkEw4Z3kEXw4D6atNNUKrXFW3VO5GUH1QcsM9h0d+RF4aqjKS8bLoZNzUOqgeZhq3cryArvdnaXYsMr6h8FRegjldrwdmyDiLP1bSoVbHj3NqwkJbu+FliK65EeC4atXorNBFNYdX0toTTXabnUjtrwUklad6e+uutUcrhOuUgTtcU7qBKte1Dt6caqVYMblIu6VBveQhbBci677F3X+YatXh0Iedmw7qW8KDziA5Yp6uGGxWZNNryaV6kKmldbvEdBVni3s7sUG15R3yjIQh+pYKs3YxtEHNVXhDt6q1e3YawkNbqx" after tData
         put "Fri+IqPTg2DY8A56ELzC1oVtriXU4mYka8Gw1Uslad1zLWl9lieVbG5SLtJEbXipEq17Uu3uJtUablIu6lJt8cZApWjh/LZ2YMqmTj3HsNU9dCbk5YT1Gxeb1y5pkoXHUPa44GbYJIDIJXIccdW7VWSVd8O7U7HhlR0wKkYRd8sFW7wivcpCekHkAblgb7duRgyRJzSGxEMXQ8bUHUQZBdMbg0xeDDLWMXTM3kGUMXAQYpg8pjEGnsMYIyZwI5uRMOAx8sFYTxnaGCsOykGU0TDm/Mb7jP2Oep4Pooy6PfXhGdszbk/MHx6dt/T0CCK6HQ+ro4q2rY4iyjhaZ9mF3enRAIgyZL+s1rIvVlFFNkN/vKGg2Z+yFVVEGbJzeq+jiaYsjgbSEYdG/Pt7CLoKyXH9/p5sOIrnBkj1FUbyrNbpSHHHsIllUFye5LOrX2ERGDe8cKEJd7V4o/Fx88QxP8nprBgOLqEHzY/LaLryaop0l9s32nbB/U5dMFFK7hd5z2S07H0XVfa4b5e4ViqsuXO84PTIPR+XznSxy83Wu2e92UIzcLXwOZbxglWS2K8k7QHjOO7cy07r2DSZKB4sus2v3GlwkiTLTzSLsPPgIIklNsETNJY98V2UxrrQVS7zqGUax0L3rAISz1oumNJFU6/AelDox5yadUuf5OhKSNtG74xSdcpMwIpv7KIPN70zutbQcZTiOockc3T8+8OpYcNLwkU5iR0kTkVMscTDdBNOEq4fCNpq5sKG" after tData
         put "V7Nm2ofBEsbpMs0LKwtbvGXlTkH3YXVIHSVXVvnEIsKGl3okESUbaMhFbNjwchAEXPtT+UEU+vmBCV9TtBm032AXalLUkFgvi4otC6q6sg1nzZxtNCt4wVhc0CTBwqT/gYNug+h7tkW9uluiIfeUA/RFj2TDS9PJ20JDHbd3w7Dhpb8he3TFgg9CZwwwT7QOe5aIKh8B+prpZ4I/DQDke8CfhoHvBH798W1oOMn4GsAZ8AGR447DL8f5HG89/JMszCbRcPgVxnHH4Zcg1SbL4Y/yTcNhx+GWgPNToEef4378HyiHDjnlHQAA" after tData
         break
      case "lift.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0DMyNUWQFmZceVBpQ5C0IVDQwtAISBqbI6SMYFJmRiYgXUZwGWOYjLkRyDxjAzMuAP5Ttv1vAAAA" after tData
         break
      case "wall-x.obj"
         put "H4sIAAAAAAAC/31YSbIluQ3b+xR5gXylebiO7XaEI6rthds+v0US0JD5qjelRwCCqIFS/vr9j58///nX6/d///23n5/f//j5l/9dt/uE0i//ya5c7hMH5D7epYEwnhIBQq4GlRQ3jft03ygJVRFxfCtSAuA/MfpN4D8hleseTUjTZYKxrX4lxqUz75b7CfmPz5bQvbxyL4R2zUjpplENu0Ka2Og8nRYsaS1tr3HTmmHo5YHd4aN9t+UEwkEOsLwhrBCx4uN7CIDlG/RE1rLpCO9ERPf2es/qme1SPUTHjL5OaOX5tvmuuE/JY42/LN1rRb4t5betCZ8U6o769EQJ3t+191fxe9feZ+C9YM81/bKFr715bemXHbUUnxku7DmZrxN/SP3H1SxhG6UywOTtamiaSBnXDJUThPLsDqV2H3Vd/C/BfaAx3/y2LPk59ljxaoWdN8uBSkdZnZJ2LdD81QFaOoTefo0+Rguuf/EF+sghRtvduhukoKArZZcCNemjP6RmINfqL8F9pHFt2mLvnhPch3efVGU2Nddt+6NAfaiXLG6qoydkPDhj875j+wjj2OT08CO2DzuSTZZzdbohc35xvAuyFW4/9hOm+mFCNU16qn8Cn0OO9GJ9e0/4mUm3U5FcPbyb5hdcPMSGUvuwoJh5xJ7/BD4HHIfLTv3pPeEjETmJQfYVB4p16wUsre9KA6k8ulPJ3Y/lV+Ax0FiFVJ+eBI/RwycnXAZyYJzr67KXOhQsHBiEANHb" after tData
         put "hO6J3fK5FZ/DbOjmKWiIj9EneJvDmFLX7F0s6x6Wg6Rr7/jIGkotUXOglg4LHWAtz8E2cLkOsL8SAPivy4nK61ehhDKJE/kGlImwzxupB/IGLLr3gfPC0OeNfOn2hlJT/1b3+N6AUWED8HvkkRV+7ODpN9DLbZp79rx3+b30NzpIa7/mD8lfg0/nyoVuccGMd/o7ez/om/z9FNxPxUg2mKFf27QNp+z9oHe7U3D/SvEUKP/f//w2/vi5/ub+8o8rtR8/Qr6K0yZVaQbM2NjcAWfhy5WyNlnYIiaIwRbAahKMDeYdqA5k1STAe+QoQ0pTpEGCIwYrmShc/OhWrxJG064SpREYMdgkjcAyZJ+wJNg3E7BTLXwy09FI3klgxGA9YfQesuiu0qQRGDHYOWTXIavTPKtH3ojJBmRSo/UGnB4mxi510szUdDQZCTI2Vvum5S2ykWctyJsxWA5Zqw3ZLO/OvBEb2xwyad56Aw6nCdilDpagZna1yAQRg+U2sHfUPFtC3ozBcsiWbciiebaKvBmDbcykW2+Du3uYgKVa+WSm6eo8EIzBchvQW2Qjzx6QN2KyHLLLdPzVZXrh6rIpUiSMwcqmeYHlsMUJyxmMmwnYqW6WYLaGB4IxWG4Dew9ZTJd3TlrBDSDNMb3zOqh3QVMdzzhyXwgVCQl5l9VkMeXlRsXqY3Wo/trygCyECj8ZulRMpmEyC6FiZdAtA+8se+85HyJTEZibj3Ahk15uUGx9rD7VX1senIVA" after tData
         put "4fpk6JIte184n4lQMTPwMtM8Wpl7Ga1kVJQhAkWQ+cm174PMuW6MZF13Nyq2PgFZWxmPb7SZNREq5s5NF8l6/MkeJOumDBEqZgZBZtpHO+aexkdCqNIqQ4QKmV9XZmQwvl0mE53EhxsVs090yNrK28d5qiZCxdw5uoh2vMc+BmnVDchUWAZ8mjWX8dRdskTXmLsAshiGAsjyWyZ51Q2Q39dIW3dhKMeqjZ5jToNtC8v6rzyzsliSh0+XpDG+/iQ7L/0Rkw3SCCwJlCsOXx+vKMPK2WIMVrzlYBmP3vAS2GKyCSZeH3p9/mX29tprZEwFZvYWGrVAUyaAJgFlyYlU4EaSKELjonx7tIVqeDWOZWGWwfqVJVc5KIjBmpPAwWRSBfHKUsoyW8ZgPU3kCDmFpRG1g4nExsoQCtsPwj6dsMUXxQcoZ2FHoxlxuB2Uo7KjGl4Eyw5qISzUQj3KetR2kOPHHeQE0qHkUPFwjeEBw34uWbIFFtbbEmmlIAYbsR3RSjnbC5JZ4ojJFsLlgHmN2Q/CkfdeblvvtxpD9tMbneZlYzzV+g2tteR39RO2eGUCGCYxP2D7DgjMBHcAVmxeDYyN1ddKbzb7uidcTtjWH315zj1ZPZRhXoL6wSOXmTy08mb++FEmNLa5GiHuVS+zpv8Kv0B5kHwwTg6f19sm4C6KuIsYg+VdZPwlF7rcggVTZwyWt6K8A+OGsd7wEhgx2Mb7p+sFkZxWfmLlIyYbcH0kKxCRSTMrBDHK" after tData
         put "p7MW+g4n1rP9IBzcCVusy2Zw2UyXCWNUvAfs/Q7309o87U9AhesOe6oP59QeYmNDPuGQT3XfQj0lll3Y4UCx/ZhwPmFYh/CAzStwD3AaUtejPA8JY2M9/8y1HxPuJ6xb49GX2+5nJ8c/ofHmOL290nxMEBtrJ0nU9p2V7RZIvBwYG5tY7vaDcKgnjG+dwCvQfkzYP2C7Ueann2XKpbHJraUCa7PQj2V7dq0UPN94wFYaYDFLkRlr1bbUVnYLRgzW24cGL57I/7xwdjs7u1gdb2s3WZ7cYmei2IkpVDMGyxNTrXe1Oqx82BiD5bGrduyaFVijCWKyLOZm1dOsDjpNEJOd1WJPbEeJOboAIM0M9U84FaKuXZsMESrSvBhwr/A7Yn5ILISKWa6e9evRTjciU+EmgxspdHy2rOIHMhWW9f8BFufX/g8gAAA=" after tData
         break
      case "wall-x.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0LOwNAGSRpYgwsSYKw8qawiRNTUwA5FGpkDSzNAILm0EkTY2NwaRlkZA0sTCDC5tDJG2NAPpM7YA22BizgUAU80sinsAAAA=" after tData
         break
      case "wall-z.obj"
         put "H4sIAAAAAAAC/3VYR7LlNgzc+xS6gN4wh+s4Vblqxl44nN9EaDBIf/MpdDdAMADS+z/++f79j5+vH3/9+tv3z49/vv/03+U+8fKf7Mp4CqUbUq7bfbxLDIRcGTol7lNSFEWocOq+7VFGcANSepH4T4zewgwzhMRDgiNJ2hNTXYnxwNynZUr0XjLzH5+bYDZv7mUiKb2J3KeGGUknGGw0mSZ3YqLrNR4YRerF9pXyv8JHPRUh3YlB9S6KEyl+nbIY8hVweMlhH8FXNwVe3WaSp+SpOCc655kx7h0qO3A/RLZj98uW3XO2e4t1vwW733wJ9GkBU6gyzQu6i1+1i/QlqffVHIvB5t7btXlk/VAd+3m/bjql+r6q1x14LOoJDix5rtPKK3Y1z00ZbaV07hOtrChrF1QisHaJsKG5+JfZDF3ijm14pjBB8c8D9J/a0qqMhVbXalxBURoo7qI09xUMvT0nMnCNGVx/zm6guHPPi3HbPVcKNbmwgSw0TJxFaN4TpK56zDIhizca5r694lqXkxgW3Wn3SXWuZRxskQ1ZMRXGvjirzpxXsC8HZt59OVoFx4XJ6Zwb4G1LrK4NMnHu9zwIx+3eXgyCinaiepKsnRFWtKf6MttEZ9yRWayPHFZUIiRHB9Bd37TBRTqpPV2Rtj1bUU7/iY4b0fNjrhWdYceVaumRwYry6aSWac9TWBIbhdekcv2GqnaiHEG1M8JExypiecy2ojPu2IZ1zy2CoOMGuy71x60uJ7k4" after tData
         put "LnQpwLX/KahSQ90iFX/+vIpfo9tkBIf4CDzhNQkquUgll3q/lgguc3GO8KuSQVEe7qK01davsHWagfVyBAS2zPwnXTI+lPHnMD9+B+6JTKBsyBtQHz6M3MfE9+qTd+ReoSOb+yXjNraSr5QKdtuzQZX15/V4xsMNVL1vuLsLCW+y27zvp8eNzSVvPNzYzM45eJiFzdAX9j7oG/x9Cu6vFKdgmUHXkcIx43pMU3B/pTgFy9Gv9Mr++/dv48fP9Yv76fcrtW/fQr6K4yFVGgYMW9jcFc7ElytlHjKxhYKorWxRmIMEYYPEDlAHsBwkaGxfeUoaCg2a4LCVpUwYLn641auEMbSrRBoIVlvZRAPBNGU3mBLsSxBlTU18kqBjoLwTwWor6wGr95BFd5VGA8FqK2tTdp6yOs6zes1bbbBBM6lRvBVORxBhpzpxZhx0DFkThC0s+6YZm2Qjz1o0b9jKYspaZcomeXfkrbawzWkmzYu3wmEPouxUB0mQM7taRIJqK4tjgHfkPFvSvGEriylblikL59mq5g1b2YZMungL3N0RRFmomU8SNF0dFwK2sjgG9SbZyLMHzVttsJiy03L81Wl54ep0KFQksJWlQ/ME02WLBtMdjEsQZU3dJMEsAy4EbGVxDPAesjg+uZyjkXABQGNO7zxP6l3gVMfrXHOfCBRJE/Iuc5DJlEc0KKaP1CHH5xEXZCJQeGMQpepimi5mIlDMDLpk4J1k7z3WA8QUAbn5qFHApEc0VSw+" after tData
         put "Up8cn0dcnImownVjECVL9r5gPYZAYRl4WmkeI619/NLxlFFhBogqAq2P2r4PtOa6MJR1XaNBsfgEzVrKeHyoWdZAoLCTsyiU9fjqD5R1YwYIFJZBoJWOH4ZhrD2NF32oNDIDBApaX2dmZDC+XIyJjuwtGhTmE51mLeXto90qQ6Cwk0MU0qZxU2KgkaMpYgrJAK9mzmW86i7aomusnQDaDEEVyPRMi7zqAtDzNdLmUxjKsWvDc6xpsG1imf/Sa5Y2i/IYn/6Uhs8XZefJX22wgQaCKYFyxRHXxyvStHS3YCtLseliCa/eGotgscEmDeL5Rc+vf1q9vO3ZEqYqJuHFFGqCokwKikQpSY6kBDeQQNUULtK3R5som1fDXGJmmqxfmXKli6K2shKJ4CAyqoJ4ZSplWi1sZT2C0BVyDNNAaqdByBaWpmBYHgD7tMNiXxBvIN2FFY0SCNOtIF2VFWXzAlhWkAthomLyVeartoKYP64gFpA2JaaKW9QYDljD25Yl2WBivWwRV4raykY9jiilnOUNklHiaoMtgMsGo43JA+CIvpfb4v1U65R9j61O1myEh5q/obmW/Ko+YbFnJgprkJgPWL4DAjLRHqA7Zq0BtrD8tuLOJl/3gMsOy/6rL+65B8uXMlgT5A8eamb0oqV35rdvxaBxzFUIil65mTX+S/wE6YXkg3B0+Tx3m6C9KGovgq0sepHwFzV06oJFlw5bWXRFeg+MDiPeGotgtZVt6D+dG0RyXPkJla82" after tData
         put "2KDtI0mBkIwGqxC1tXw6aqGvcEI9ywPg4HZYbN42gcsSdAaBrRXvFfZ+hfseWmLKT0CG6wp7qLfIqR1iYUPe4ZB3dV9MviWSXVjhALE8GJx3WEOHcMASK+AM9DakzlfZLglsYT1+5sqDwX2H+Wi8+uLYvTk5/ITWd47j7pXsZaK2sHKTSC3fWVm6QEJzgC1sQrnLA+BQd1i/dQJaoDwY7A9YOop9+kmm2BpZ3NwqZWUV/LEsr10pBY93vMJSGsrqKkkmrFTbVEvZTVhtZb18aKDxRPzzwkl3dtJYHbq1MxY3t8idKHJjCtSwlcWNqeJdpQ4rXmywlcW1q3LtmhRYQxC1waKYm1RPkzroCKI2WKsWecV2LTGHKAqARob8E46FWteuGQMEimSNQfsKviPsQ2IiUFi5etSv19GiATGFM0Y7Uuj62TKLXxFTSNb/A+YMx2oPIAAA" after tData
         break
      case "wall-z.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0LOwNAGSRpYgwsSYKw8qawiRNTUwA5FGpkDSzNAILm0EkTY2NwaRlkZA0sTCDC5tDJG2NAPpM7YA22BizgUAU80sinsAAAA=" after tData
         break
      case "terrace.obj"
         put "H4sIAAAAAAAC/3VXS5LtJgyd9yrYAG3zh+0kealKVXcyyEvWH6QjYcBkco2OhCTEkXz9/fPr649fzPdfv/34+vz++fXxr4mf9a7G3p/O93X0gbHkG2EZS4aySwr5DKj0PbqzrwcGK0XIPxD13verq+6Voa4arvqGgcEKiD2Z2aPdOzP7TsSezm7fR7CHetjDKeyhSJM7O/l7zmGPWe+2sl8rM8LY5zJGiva5s5GinXI8gu/d9hRmKZl9bvQIHo5zPPlzM3a7mgU7VuJV3JkOITsgd9GLvwsjXbNxcvK9b7PvfXOiuy97Nnt5s4eg9p2sPZ3oDqM4fblAitiDlT2axRTlSpQhwY2u6OsdZKv0tqg5Ps2Z42rVgwC4+yF2v4ylTZ5sKMPZhiKJzQgkMuKIaNXHnP4A0w5MwScjleF5Cm41+pSgTZuftAaanTxtMHkRMO1JL0Uf2dk9PfuKZfda2D1d+w70ysXuZ7KnYtlTdeyx+PZ/avC6/p1oJ3qmfctChgNfNkptLNxZe6L23jZbg/zZvfFEjeTXFSCZB2LkBvdixJsoFydI6Tv4IQaNRZchYqZG3ilIGXGaIJm3NBbtW14i2C2EfXu0h8ztOxX7PrJ9H1Dj2ykBTtBqhn3ZDfbAdoqsYewhjn0q+TI7uTvsnEtgn6r6YTbO+8KOO7m+dirwCrzOvxXoNloOvjdajcVNWl1Y9/HP3z/6/zrz6/3xu0nXFY27rmRy/+kArxmN/Uct6nVVBXjNaOur" after tData
         put "DtDDuPu6GuvICQvAu8NGkL8u1/MI/eGMi/QgWGTRJnoQTLsGeq8uoBumPUyvp+9GrhrvSOqwyKqlrZQZndKErgu3CYEeHRSZdU7KwAma0B+9ZX2jB1lCFi2Sp2ANsATTHFSGFnvJSU89eBO6WQgmeJIIFlm0mSSCA5IV7YBFFu0tR8FBxakUgaxFFm3SkLQ70mX2X/IsF94lUYUNzXikFZVHERQLun91DpYMGxPqilY82upA/MZbYCwG7BR2C+xX13i4YexnY6/Gzs3WMazWMDMxKhwXWI8Y0wLn1TecmqhVgl6tXdusUYJYV2vXNrjO8DilOFFYE8RC4RBXGDKzusM6JYixqXDnZdA+VaE9FiaRuz40KEPqnUR+ssk3PxI5z9R6JBeTArUvo9Qj2bOIAKwjD+SxwlGFY25e3mRyxqOIi+LZrKBxyrDmfKBNgCm7go5hXxlOKLsSuZ9yY23R0VAcnEJbtHFKgdPKnV10PFTH/VWRUA3SfSxnUxGyasiK47CvApiOUzNPDew2tcowQZChVbiiVO3Gw8nhW+QBzSO4VQzuVmjAiUYxXFILrCoYfi1houPCWtOhfvOhK66bQ6VBE6qK8kPYEmRCKz/AlqyjX/khbHFSFfBDyMLsmAjIZHkcCz9Qguzmiy+DLVVpIvwQtji9SvBD2MLWSbmWB1ua8EH5IXy4ZRqrLGwZsPADbKm3+FZ+CFui5K38ELZEZabwA8dhJ3zxwg/hg1OuQRa2IAG95zrY4pUm" after tData
         put "IAgokeR1DglkCcII8EPI4iWzwRDmS8uaGe5b+dLyQpQwDfK6vTfqNO+f+a6w214SbYbH2FdYhrBaxxXW0ZfuZe7v1piIya2+ZdN4SyS3WGsmMvDF+gXv75QwO3neKWGSp5dHWeC8wXl+S2jlo3SXa9w5DlPYNekkkkWbFc4LXDa44FEFzoALrLNaqyzaqHBcYM0EiwFrJhWxKnxRiwAWGdpSVrjIJk0QC4WpRRhukGmg0eNWWGTR1g2Gr9Y2mGVwv+Na+qRjMGKyRUyrqGMwDq2yBIsBK9VyWGAlTxYZnZKVPCpDW+4VhoyhNcNgc9FMKuQKqlUNqbJo1TcWA84bDGIW/ftSkVnDqdr46wZZtRoSiwGPf5ZpgfNC+oxvmv4f/rr6v+quo3/JtGa0e6SXAD1Mv+jMKqIhrRntqRb5pOlfco4IGYwjUvBfJ5FFS7wM+EYqYsSuyBISNGw+bade6BOTOJX16yMNrXpl1hsPcgchnoii0+7CQtCygiC0147DQlBXVtSJsfYhFgMe1vNu5D3D2OS1hbBQ2NXJ2t/8ueQdf0X5Wz6uSBZtt/ZePtp84DP5yJ9DPsoZSRZtL45P8jnoM5/KFz6Fr3JKX1RLX0m+DcLwXvEkhfYJOuERNmhMOJtygPZJzeEEHFzOIyX1dWg5FSmS90oFFOGhhmrBGCV7eV5G+o5q64tOtei0/wAhTWis7BkAAA==" after tData
         break
      case "terrace.mtl"
         put "H4sIAAAAAAAC/03OvQ2EMAyG4T5TMAHCf/lghhsD6IAK6da/GEfmirzNo9i+9u95H8M6lc82TCODskLl6kqhBmmt7YHmRA6stng9MyNVQonNBwhalVM1VP2X+dJKL1og1AHwvYtIcu0nE7/9W4zO8pz1DFdY+QGZoCWF8QAAAA==" after tData
         break
      case "slab.obj"
         put "H4sIAAAAAAAC/3VZSZLluA3d1yl0AWYSnHmdttsRjqhqL1z2+U2MBPXpTX7x4QHExEHKX79//vznH8+vf/39z59fv37//PHfB77aE+JXbGM9lp4IqrEjmCo/M5abYSUBY0vLlNfAwMWL1WHNEJ1imdhT5MZYT9vchlQVkXBhhSvt4lv4dCRc4g+3GMItK+EWR7jl6rAZnFEXTbj5/uaahfaqSnBlMUfDrt92NDhP7+jFQLjO5dMXdnFv2C2mW/i7RuEo0gu7Z+MzxWdvlMoZKq1vrEmCKnx2qZ/jUznctL3bnzbD/6V+Wg1XB8LN/XCPM5ey1dfgBSoWrsxwo8avWedmQk4MzvpoayRqDcPiCbK2U4av2LdyzDLLcCWPbXpivDEPIuTuMIZ6dm6X6cETy93PzBPXbS8VrjgUx0uQPDHemI4Yv0YCn8VBYJ/Ond49Fg9QtA/l4ZWbzFKrnyV7YrwxX8SxsVkZ8/FJBYYLT6HpVqLqdmcvAffDyM0bnJ4Yb0xHpLbSABdBdi8Y0mLLUIcDiwcoyoduNN1ZZdsF82aBKR3EeGMexFiaYVkxgO11yQd4YqXtWVQbklnsulCjNe0Cx8GLN+LB23tUgipYlUh0lW4sniAoT3SXo80wGFUD2RtJovbaxHhjnsSSzSJMweZWjnxwGXhiJe9ZQPoGbJLYpPR76WIthufFG9HxsDh7khjbKxH4ON4xezBbfKY8dtsMScOY03kInhdvxJNXrdlnkRyOUbayEUcx" after tData
         put "4ks5Htqzus4ugoFbK5aH6rv4ZG4irinXJKOdZwNup+N1CmxMVL0m9GZQy6+tfWETPC1eeAdt7EZPclDUfeCC0hg7oOHWl6jGsVcNH8qrM91aaI4VLzTPSnEHtc4zCcot3+qh6DFR9Zqp7wmEVJz54Unxg3WQxoZAXK27clFp1QocT83oVWHsLSByYlNKzlr2tHjhGe0v6mzsQSozdIZaQYg2i1aERZdTOnfw2Eaor2LSjzAmDdHJv4hlClMUoNtMU5SgkdKcOAyf42OO8JokXEyGi/fh4k24BB4uYaoPwTlBTgb1cj0uwnvu4Ca3icJtprAz+km8Wbzp+lQEl15HtLg/wbsy5Tq4ZJ/ARx5eiYqPpoVrGOGdT9aKODTZ0VJafRyJklkhtaDEV4Vw65GrDHvOdpPkb3CXVQkeFyzGKw5NsaZsMhactSFxV80oGQhqAQsljs9X28qS6zxsWqXsmt6lWdhN82WLQgjNGjJbIf7z7z9//f75/C3++MdT4vd3Lk8e/NPxZ8EyFmmBFwzMngpPD5f0ghP/KLuccBG4Rmf0k020p8JpW5RKViNwsNUTliv7A355IrAYKfUFV/7RVPGDwe0FN/4Z6iAaqU9F2+2pqNQQlrFIUakijEb6U1F7PBVj7gjLmKUNoxoLbhj8fNoKp8SnZfxBWMYixZkmwmvuAk9bc5X0tI4jhGUs0oEjhLnyjfPbNN86ZmnVnPCDKdUXzKkiv8lI9HDVDPKDwcWzh6VqSPAyVqll" after tData
         put "kDJs4ViUPBYpZ39nkBO9U6VjkXYpAyfH8ts0VTIWqZVhGVlbdF8Orjt7B/xZsIxViroZYVSrT18urJeaju5iODoWKU6JfneMqz8dpxxPR1uYEx2zdOBM6PfAuecz1lw1PgNtYZQ6FmnBEcK8DDrXruu6lLFKtSH4wWCtJT8oPOAFcxf1eMI8ppwYvILXVBUJXscs3RmkDFs4FiWPRcrZdxmkRO9UyVilWcrAydH8cuJ2vlWqZZBNSfeqeW54KtUoR6VGHo1ac3RpTR2LdEh/D27NyW0/QVpTxipNskhmpg6ehTp0VmlNHYu0SdtPWi3P5EaeU9aOjlkKMUrf09OKZHILTF31Mlbx0Pj5Yav1E+cx+05mkoeHbqj8YHDz7KHpmrpF6liklkXKsgVskfJYpFwBl0Xg5Fq6ZMzSoZu1JMiSrDuqjE2sxVj38NU+mFhsq7R+M/6SRBFlYKMBSZZ2zet3OVMxpx3HJFFEGQPHJFkerrcJgOXAeuUEQKsYnyHGwHkrSdCXvn5x5rF+0SpFaYgycN5BkiZ1lnqDrv6NKKOapJ4SyB8S7aphkvGSFJOUlyR5HcqOZrRZdhRRxs515ipYpDsHgiiD6+VzzXXxGVXEGFUrxxl09SmWUUWUsSvXaS8EGLS9rfdf2d82IowUZZ+EBLTHQUq0gULSXW4jytAtF1KlDRFSox0PUpe9biPKGLKVQpq080KOtD1CBtmSDTGGbqj0hBVLUvWkm4QhxrCu4icnsT5I5SWZ" after tData
         put "b0nSjhxvCUh3peglmB3LaNLsGCKMnWuuh4vUcqCIMrheR66zVGFnVBFlgFaOM7irwRn29TGGVS5n9joX9iBX9cAQZTSNB18Y0AN8McBI8VouHigiDHyV4OzgawJ6iy8A6Aneq9kDQ5RRNFK8XWN28DqNXuPtmvNmiDKGRlqkYvJaAvaSsBFh2GuPPDldq7a8Cm1J/ZBoR5a3JGvfNS+h7GhGh2ZHEWPsXFeugkW6cyCIMrhePtdcF59RQ5TRtXKcQVeNZhlVRBm7cnwHg8q3Wah6vTXEGHo/gyrdW2WVVL3kbkQZes+FyhcxqHzTgqp3rI0Io+kVDhrf+KBJxze9Cm5EGXrnpSesmLyx0DxcOUWMYV1V80ti1ZY3GZM0+JBIR9b4lsgtEex+KNlwGbVd2RBhuFzzdXdHunMgiDJqtMpprvkO7DKqiDHsxOAM7mo028kNUQZXTr9F4MmKVh88yh7sOLyWfX8PRheZqrxcmDR48Mzjw+P7G9Y5vSYCNIs/tM/xGFkbxY0Ylu6yAP3BDRvoxRnnxC0yxwfXX0YuLdpluLB9mgYNi+4kKZOQjQXMD67AnB5a6Jh4tmZSgxPR2AFRUnZ55PVYXxP4swiL8gvlJsn1ROvrY47cpLdxvH46jnzX2eh4fd/p3q7tifrtqJ4fifTrUD2/Bk3/ecfugPIVSMjJmhyOj0H5ZKf3B5tywPbBph5wO23r5xz7jtM8G+aL3c/vOMKG+YKHh/dNFw7Yjo7q4X1uVDd+" after tData
         put "5OqrC4Wuk6ttnuXnarQlw77GZ0KXDjLw51kuNxLhqyk+E7o87LKUYCmtOGBtGUsONLeMRYoNmnkldiGRKWTyiCVEd+q4aNYGsYTAOxOPRapW8Xc+eItZP/QXQR6KrChaHNpPsLOoKlodCv1EQchN4XbAxvba7LeHWQkvYgwPD8Nw7BRpq0irXoAjhGUs0sVOtPhXDlOmmFKhHSMViRHHIl3JSVV2stQoqtQpijQkShyzFLeZNK1hSFcsSaLx3zwokz5iBZ2TjTkfWLpdA46AJpd4JKU4Fim5IklKSVuBk7BbQ6XcMdrsmX2vfAjgOafHBB0NAvB5QEfDkHNCdn85G4ru3XwaiDDKASIbOh8N6DV0KcfaueloAD6O5CiQg4FPAKknHhRixwzIUSBbf9I9XsZyMEQ5bfQokIOBnPnxP6vFyTuBKAAA" after tData
         break
      case "slab.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0DMyNUWQFmZceVBpQ5C0IVDQwtAISBqbI6SMYFJmRiYgXUZwGWOYjLkRyDxjAzMuAP5Ttv1vAAAA" after tData
         break
      case "enemy.obj"
         put "H4sIAAAAAAAC/41bW9IdqQ1+n1WcDWA3l4ZmO0lmqlJlJw+ZZP1Bd0Hrd1Ku+k/zSQghhBAX//zzx4+//+Xz859/+/3Ht59//vjtP5/rWy3jk65vV+lYeBAsE8HaHwD77TnrU9+cV8uOs/QGYNuq5/EAeNe8VUfG2RyWe0XGaxM515/ruX3dDrWuex6NrL+lHvIW36zKlyLG9AXnW8UUGiiFFkqhNVJojhT2PYVGToFJUjiaKbIUsI4MP/0C1nK3ral+ozHnDhLrw6ztKoJCKb/lAvzMU7BndjLi9sAYxXvaDkaNhW3F6kb9DS0T2uAr9RktV1NNrVMwtPDTdysKvDOLiL415wUvsHUn4OitF6usXF9ZDTUbOKkG/u8uePd4i02h3N1ibwlbz1Lci91k74nKE2oPWjsY6BB2LWwpHjGeDauj8zknmYLPBpZ2GpwwN14m8nB5BWW4l/LG6OfnUT2FLaVIavJijxE82or6GRkk7nrcSuscoE+HkLDt/fdr7KUjg36iGVgObPcEXTC8y/0CPGfO3k76oqH60AqALscel9E38zUddqOoC83GGMR9xIphOMy5eq6BjpvRRkcLqPtW05AUKZcieSlSJb11SVHXUtS3FKsTaV0bLYQea4jVa8MottCqyljptLQ6iJoo3RnromW+Vo/dFBS8xm++FDO+G0mBMinqXIp6l6LuYdtUGpSWVNbcgVcPQOJMX7HSZO7EevP8/T/Qa4y3AAUHuhg7Qms8GBjGB672" after tData
         put "19U95wDVrms6rKORBaPKgL0qU/qgrZThGDdQmm5NBu6lUAp1T5Ge6Uuxbw1S2IEU98CaAhdo99t4pcy3mfMsQfuK+paM1StFUs9uHbybBilUIWorbMqPtO9q2HxglfRLAV8YwHkVTjSIXI2zcR0rRO/RdwN43gNl3sNdGF2RwfWWBRCYQvSL+kFToVZhB8K++obWd82nSgJGWPqiNpmfOfepwpwyp1+MEd9W2Y+9VX+NfQhu9WEZp/SCwq8kl60H6F2+TseBFVdKx8mZcM7P0ZIx7jnzzrln+DdmGVc/Kp+Ysu16a9YiTWzJ1QG+auOqQd0c5IOjVUHNFA50rFbfOAmDcBFhrvKTyaE9I2NlzJjzDQKrU3PevEjF4Lubh1IOfQmoNW+shrqezhZoxcFrB6klOhA4wNzud/XNUNxOhFEzkj9vbSvo2z5Aavuoju0I5ttWjBa9jAkS60NHHeV2h0KUcO1s9/MV232wvTDXQntLa0HNlt8tKPbUt3ZglVM9mQx7b5+vGe+T8QX6ZlrE2IJmjlnDGdratBA6MwXDvKE8bQ6UeGMJmbLZlk+xDjSpL9BXT1EUS2F0SmFQTmF4S1EgTFEUTUG0TVFUTlFQT2H4T+FKk8L1I8ULUIqXixRO1RTO1RSGlBTGlBTGpBRGixQH/xSuHimOtimM4SmO9ykOuCkO2SlcXVK4jKVwgUhRlEtR2E3R6pbCRSOFS0EKg3SKFtIUxfgUrZopXAtTuEClKHqnKKqkKCal" after tData
         put "MCilKPilKHSmMMimMCamMHymMPqmIO6nYHlI0WKQotUgBctXihamFC1qKVjVUrRIpmhdS1+FzijOpzBMpzikpzBSpzCop3itSOHC8g9YwvDgnraFjNDmJHuItnwH18GEPCBtUJkiJcoXloxtY1WrdVZ619mqpDdTCrl2fVLQsRT0LAWKp0Dz9DZBOnqTAuuuf1l4cULg4dRdGSsYUSbUKmVTBy+/hmCjMIb0U2CKJCYnUqu72tpMknZi7N1K1EikYtC9wApBh2OF4RycfqUH0/7OzmB3YJ9iFKo5H5a+SYLKXhxhbzlQn+oVV7SSCDEZv1bQ6eclpUCU9N51/q1zOhTkfku3vcFEnRDaWgr03cWexv2kVd0c9HR4mhubbxfI9DYfESRtbnM6oYhKm9tEsySaJK858hKXTJ73wrOJd5/eHY86Gcie/fMeUsbMq75G0uZ6u+fhQJ4OLZAiHx48E+A89xfQ4eCvCXg2BIakuwn8ZIt8ibgAuyOwD8DG8d7MoA1JAVd6szmuFLClSFx6t2oQTgaeFDitLOTIjNbyVsQJ6HAXqgrHHVTE+L7R9aArJVdk0VIsEiqUmjyZLqemCaNk+nFlX8R7KOWG1Awj/JTi5Nsb8edNWjrEpbP5dHT56Ew62k9H79LZvXQYJznT/ftfv//888fnr9dvf3za8/17XhvN/Az4uNcHIveiKWZMEz+ANi/47Osjf//ey/otCCBNIOWpACCpEkmbI17fmvGYJrN9/16yl+ha" after tData
         put "U4yY2oSfRSnXkv309QvM+VofFT+QppgwNfiVanB7UK5bPhp+IBG0zGV9gHZr31KuiQgSFROufCECxIxim1ZYCOrQsKZiyjVMbGVdlehqWgXh4q5hzRtNUvKg36uJbfJkysWUcVIurlMuoZTroGSl5J2SlUItmgalnHVyPilSh5BQmrSndfJNPkqjhx+POKt8euI04jyJaF0i8qevWZVYOhh6kslyfshCCxEzEiZcBd3pkb7ncnmi1TRMuQZ+ILGQuzKkTEhTTJge8elS2ZVL4Y881KcVM67HiNAPsHUFDdf6Xiq2iETFjKsggsQiFW5Sh7mRJpDydFV1shJ1yEdRbWp5EbsRMRIsk9cqHzhqaPL6CKZctxHZOyvPFxDKPZSONelqs+4rZlzW/SbtNNGmmTY4RxFTLqeNWKB1+TALtPIijp2ISrJ9m5lcIeUZYvLWqduNu980GDSZHLQGLKe8sRPoqLd2YvLHbT1sD6t3N/m4Vc+b5/HNM/y+tUFth334aA97oDw39+CuJKfL75DlofRGy4NgwoQ0WmHWx8Qlp/QuS07p9wYJD5KEWyXeSmobtGlycxS6B9vUt6aacHPMBLSBY7hWlYGetyoOHEJcVUbdMeVCYueWhjQ5LCiO50W0oDjmSXwuJfKnJ2YjggVK58bh44FxL0PbLEMx5cKa+Lm8CDMB+PBd0X6KEZgLiJMdYwz6ZR3UBKV7vdTtH/bCh91+6mqiSD0pggjHM07KvL6U1s46z9gpQ11z" after tData
         put "1INiGjAy7xel7BpAAsWUwRN0ZvmoOlPntWPKhUQYqMqK5Fp49GtWL3GYcomeRNSxnkpURzAR5iVT4sojMZsc7ZGuwBiDsjjWXd1A/UY9iZiw2sO2oeymXprVTFwkF5I5LgILVqpX2SDlkWqgG0qiD7WafHqiszeHdxIPkfHR/LJeXYj3zqVilz4krWTVUGs6TLmQOLjbD/9KklwvjtM1Z/m4tMFcBSs7l8ikvnH4r7mpBfjTE28zD40hMaGmkqiQfIOUR2UCDUWVrNyqqsOUC4nSIK8cNesYY+JlkPJINRTJTqMJL1KwV0VGmqo9KhKMVZpYbarVrD3RBblW8JR9Ga2QqyVYPtYPxPT1Q9F1faxVAvQBd1w/A9VZH49yY130NGKDsDAd97JUvT51NbumLKQ8OCfpQ+Elq8IKA6lRbR9In+r9gdSkdoMhv6iDqbCfXG3VqU1gy9YkU2FJb2Cpe9Vug9v6QBbSsEkqM5WacJowt8JUFqp2h2xCvWbToO9hWSyG9jTue7Hd1WAuC3WZ5qbAB+OhTR42Yao22VeT99BKws1lpt4LvrtTkC2o3eEyU8Ww7CekGesJelNZqIu7ATdkok2Ghd0DfRLLTKVBAiE4TOoQqABwU5mpkCq2Zs7GFiNZZkGmmmGxu+rm6t+sMFFV774+7inORn4B3aEyU80H0Y9ET1VQykwV/5baOCwmhMtMpUHCRA3TukrZHQx4l7nTi1IvOdOAAZl9/RacPRmN2DfKg31gDqRM" after tData
         put "tEGG3s1n/WY2ToaRKY9RiBMpHb0jQ2dXHzNlyGD/jCn2ahpT5NUgpuMX1SIuqwYZKhrFuCe6xlZL9JLa1JVdIPP4aqw8Q8KDjSkkPIXdRBFIp5cbOYogylF5cmZIRteYsbE30zIiHJBW4LBaHR6O0djHFFEOlWZqi/XN6gIpDxkSFZ8YBI1FKYIIB2wKME6qt9AAiVKohCDM4XVAx3Gu9nI+4bChIIu4ulpHEOGAxBoDFtvKVIGEtFWvnHCY2uLkNGoyimgeRoQDEkQMAhmypHY5n6wcvxQRDjIg6oa6mIdDltloMjEiHOb71DM3EXUCqk7MYbrRULkJ2DlaKiIcpoHMMfFk0t77ts5C8npJEGA+4f6yfmC72NciAoEInBJa6StswQ51fGDn2B+DYe/UJ1MXDH0f1wf2GiN/YJQGyB5L9qjahMiGXo+m3FgX4EUf9wcy+rGaWLIHysYPgWGDMB7eqd/XB2bTmLjLvcEYUmYq7OdA9gP5e8YD6HZ/wEBP4VNrKDMVRgH8AEz7rLUHLFw+sBXvEBC4zFTYGzzYJOSEN9dmWcDNZaJ2mPWg96DtxqAksUu+ymWmdtlawsblWSvV+rmXEDjQxsWQykyF0/QHZaPhRUHYjj3TusNUHUseBhoWHg0YYi7zIOEQghA0PJuOHQBgKgtVOi9CeEh1LKnMVPI5EyL2FcNKmak4VguGTeVc6QV4+Rq0VarQHS4zVTvPTZKN2GLQJJVFIdGEbSRufro9W1BMxULg" after tData
         put "9OguPCgwOlRmKmxCZzY/oUE0h+AyU1VBbpINa/amsigkhiX/V9OITbjMVJobIASnhQyxwlJmqow8T26yKIsE2VSWqa9zHm3Gg8iuB01SmakaODi+iBfplKKyRB/tPE1uUUg04bJQsRcAc8TgSYL2tSklYQYdwHFTKNAww2WhihAaVAlwGma4zFSKe9BLCq4M63QVNg69wi3uQ8NAkcwGjanqVTwMFKR4EkCTVGaqDgOfLfHRz5TTUikztR8wnepOOW2iD4WfA56uCYCnq/3Jel6Sr8xI4d+qFEGEoymlHZRbKfdB6S/KeEkbXsr6fZRCSme+1cp6c6SIchSllINSTwoh61c1yO2g3C8K65a1P/TlKONF4X7l50V5+HcqZe4UvaVTCt/WZT204C9HURsUWr9yafwrB+uGCEdXykLmSoZg8zZXsgJ7u4mpviLCcUNZpM2VRMJ2cMJ+CBJPTIYEUY4O5a2OSDVpgjCHk/Zwy52lVtVNEOGY2g6d6qNU+LVdnCDK8chxf+Ez2MKntUXvVxURDj2LLc9B6S8KX8cUOydmZPC9p85pRcZ1UnjmGkVvUcftEeHQ9BJsS0uRHNjobp6Xdt5D69ZaypQ66f6c9u+S1OnpiRwRcBN6UkDJkVSS8xBacOWYhPbjFihJhdeJklRSblqs+VxBd/Oce8hRhh580OkJL7+krt+aQNtjSpqOFEGEo/PKkjElnJb+29ZEEeaAUXhoA5Jx8dKtCWaXxW9nlEO3qTCmz3Bb" after tData
         put "E93aKiIcD69j/CXbmG1LJwhzwLqKy5ZSqId+2y2IcFgdWIyn29e6jY4gwjE4/bNNEVOsjvIyB9kedUM7yRZr/Upeoohw2BaVrG4ctufWOsJh0grmfLoVpqMBv31WjpvTQkN4K0wj6LfPwsHSZDbSaxs8Ox/8tkWeuiCFD6L5+cwjj3Qee1KzMLmsyHazI58i/JFHNUQsL2Kzy2s+wpb3QPJAiBNavBGUy85CCJ5Vdnle0OXio9vDmt5eRLsv7vISp1/yYdf+97NjCzEi3wjrBTH2a6h1b3klQ+989OWPCbj4aI+uQu71gYpiRcWE6eqyMvDDH36Ykrs+DtLHKoAZFzaIx8Is33M5omLKVU0dXiX01Y+uRop0/xoH64yDcr0ovH5oVmLIPCn2hKbKc5lub2nq66HNbW9pKpsZrTRoKV0fWFExYRq6ADcm2XMbe2VjmHI9KtRerIhatak2ihmXe/QiT0/spYq5sT090Wcmjz3skOcl8tzkeT8zkZabaaOYcbk3KPV8SXIVe4QhM8KelJiq+tqjn4+p9IGFPv+47fbfHnvINe1td5v62MOef1w2UeW1h7z+sNtuvNm7KTWhD/fEQd8/6BMH4sLMKL/eItjrrafumHIJEZzpefgXpWOgwrgGNySMCZPclgM7P3IU1SWvIuWlO/q6ESG7rZfbe0+R+/xpN9OC9Bfl2il20/9MjwgHUrQv2juwHZ5SItv6VEy5NqI+BnA19epfazKXDYBd4OuVvnt+wVfx" after tData
         put "cjWPV2BtvzXXe3R9YOKvz+WqfL8E1xtyjTEstim23ZBzUOObcbkpF8pxQ25X8hib3fW2Xnjvd9J6Ya3OyTWbYtuFNT995BtnuYFGSt0vnPUKWqr5C2e9graaTS+c7apbVkPM/Rb0gdY/cPQPS/pKRz6wrn0guYFkGr4RhdMVGBLgBqJUwW9Eb6qCPYNcbf1ASrV+6BKHykwFbfDQaYn9YA86NoYJCZaQgjfolFRRPaIZTGWh3iYVUieeF7pdpjL9vXeQN+q6g+8OLTsoL1V1iVyNPtxR7iZZDgSyXN3LU5mIYwf5REDR4dC6g5zh1G0vN/hEG9vjJDLjfL7GniEeqeKeIT57Nog19dmsZIPTMj1MwPCF3pAPe3hmCd4VZHrXnsNtmV7P1ANJ4zit096S1nQk77orh/UOEh61hOvGwzTtjkCOR56PlHvyM0XpKHSASX2D9lRYeiL1JTH9w9ilk8yjvZz2zkL20HJ8KBtx3qbL0TtvzIUqsGzMeceNJ5S29+dtul7RCBtv04VbNua845arDt6YyzYdFbLdvDztkJsb2ZjzNl1P5HljTtt0vdCRjTlv0+WkNUMaNuBU6cZT3wx3/JOuG/HLUQafE2dInwZcEDa87Mqg6aTb2InH6plSH5i2mW+8Mr5kvSC2dDzpzqBRp7tsZHK1wD54wm61Ol3DcW1si1uHIe/Na6FypAssxfdKed7KE6IsSGJIWSpfGOgOXii2s1ZEOLSOWFROJMyyijAH7W+3Onwi" after tData
         put "YRRBdJwaH/OzGW03bicFijCHjYUiOlw2TDoWwmMGEjfS4xHdxAsiHDRc3qjqguZ6jAiH1VEdyGbiF1iJEWMxeUySowyrJIhy6BGDuBUdyfgjIEHU8RrfZqhr66GKHn8IIhymgTi/HGnRUY0/BlMOnRWigUxEOzoTRDlMNxxH0ckfnQkiHDbF5IhONDDdVCfmIGe353iXpDiYGkEsguuR1Q5+IwoBD74RhXwRjQsXXVRCAl5QIAMRMLzjkMICx2Ui4qkzFZmIOwrLLDDRm7Ta0//9oDJTgXsyt2YnzSUnUvy4/b4rf+wg27N9cjlgviHR4yjSltp3SnOZqYW14/RIlNa+VJfPaEblip+5g7zlsf9Z5FD7v0PFlT98yfNftRRzxvpaAAA=" after tData
         break
      case "enemy.mtl"
         put "H4sIAAAAAAAC/03QvRHDIAwF4J4pPEFOoF9myBhxusRV7rJ+eIaAC17Bd0ISx/P7/ry2B6X7vtFNVJGOVNN0DM6dgwGlILhOLV3b1Urjydy5ZmnJOcCyWDqroE6dW1rYZO3MbpgMp8pEA+Z26QQulzrvdUboZ+dQftkoBlc86QV7hefJdcw8uxbx9Rv0bxt07uScfhZAy/tJAQAA" after tData
         break
      case "fountain.obj"
         put "H4sIAAAAAAAC/3VWW7LlNAz8n1VkA77jt5PtAEMVVffCBwPrx1K3/EjCzznpbkmW5Yf89fPz849fjq+/fvvx+fH18/Pbv4eLH/Fw/uM8+kfHA7obBnR33Yhaws3lnXl6gekhczVKwZ10xoaPcLVhKmYGVFkJZ4x7je/eB3DvI8RcZsDhqewjNWH93WxMy4hndquZe0Rz76N2Q98U+xyJbkmXGDZD0oshXYdh/9iGHowY+kcwi7Xn8hjBBlhKAOLV7XWER2qPzN5n+V6kWVL1fpTeYi4zuG2A1e/ptlq5bQMwjfsO2A0/Woj7fio+LRugozs7yMWsR1kZI9yro3sfxL0kE6566GWgnxs1mdgaGE2B5p0c0JB7CeieEd0essN0yRLgZPdvzqGUYz3BZtB5Tevp9PBZbNwS+YX1k9D4f0qxNYp8yTe+SAUhTVPJTaqXGUvVwoINuv/Bi71kd+Ga2IiJTxJMwazPBRt0j3juHtDdIkoRZH3EoDQyJwgbQZcU2dxsd1NT3RLqTnmDDHhdslfaKCeQFMgKRn0Q7x7UvaHrWqAz7PYR/vn7R++sx6/+2+9HOL9/T0f08huu/ts5IlUyOf0nVzy4Eqav2ZXFN7SNa+ob1zEYIZALkytp45L+ZsaLM17Mm11WLq52anGUQruFi2nl4Fsqfcvia1xdfHUMq2SQSvYZNc0q6vybcL0q2RRyMvPzCEEV0cWuRytUZCZFuD7OBaSjXeLbM66mGNdR6Ee0iqQG4pwk" after tData
         put "DZMkJ7EsCmNVrQkQFpDaSdNLo5EcpsQqJo+hUpBsFEERThEV5pmSzIRcxhyJoJhdkSqoxZF6bqdwQFASfYGa1DGdqCMRFPM9lbtkDbLHGgBRafDVqVPRmgw7KOabg3JJfHOkLxCUuNkFrS45ICg5YYyMpfIobWD9AaHlbPUnW3QXsNZAJpmpqkeuUl/ZeVJZIiiF3uCa1NfsgKDkhmrrv26oEzp33kkln6i2VsQUckRQEivWowcdMWi8MDlB2LpcAbNTfdipBfbmtJvWrEGgksyuTjvjiBDVcww/uZQ3DuMGcm3JJW1c0t+LXJi+yXzTQHc7cJFcXDiOkfRGzHoXZd5j5PDLOzWVaZd2O70xU9zspjV3VqIiZ0U5P+0GBy8ovCs1LsfIceP0N7GHAMWycefkzFfjcox4bnbTetiBy+w/uS3cud7bctRajxmzNrDYtFfFkw2vY6pVkPaAXpt4HVUuCI+OIMfNMFW5J+UkwQ0tLTCkNc5gapXrRTLBB5pdpJFYA1OtcpkLjQ8bEkZLglBHJq3XMVZOD53RWnPHVDFZ63T+aHIbFfRCoQ1DxZwXWoNOa2KqGGJUXgeXc9JnIMe1z1dOgNLEUKscujxp4KPKaZBLCB+DlqNSF1rxUeXUSOXxMWg5jrLY+GC1FmtiqjZfC8ISj0yIqVrlMa+xfLaRbLGhYnLLLBlrbA0uNlUbkrvThhibFNhULeRcJ5vOKBWwqWNVsSesVLYMxLZj1GnZX1i0uZGIGQtB" after tData
         put "bA9oH5AGV+SHLVdPvR5Y3iR4NsrPOYh8aDOpfD1JA9IudKIxoT/Kz4kuh7ag13fg5QsEIa6UIn1ABT6kBpc3Tu/yUMiVhWOf4lsQrz92eyK8CwPz17cgXn8XWyYeifosNEqnibefCvONiFdh5dMPD0E+/Yo9HYj1QUHW1qGghuFAn2HT0ZnID2eti6TLlflGkazx4MI88IjQlxrTk0x0MbLk9h8+2w3V3BMAAA==" after tData
         break
      case "fountain.mtl"
         put "H4sIAAAAAAAC/0XNvQ2AIBCG4Z4pmMAccL8zOIbaKZWJ68sJweYteC4f9Xiu+4wbhHWPsFCRVlZuVdNQB6fBnLyKrQJ5cu7M4iyWWw1tcuksVHyWzFl4MnZGfydf4PRP00DwPzHjd6PhBVVfJMa4AAAA" after tData
         break
      case "coinblock.obj"
         put "H4sIAAAAAAAC/41cWZLgOG79n1PkBdClhdquY3smwhE99ofHPr+J5T1QImrs6IhOCQCxEQQBKLP+/o8///z3f/n5+3/+21///OPv//jzL//zI8sf53L/9P8fj74c6+XQ/tCh1xt2bwPlvSVUHDxCV1urTF48SdnFfuWXoj48R5YvjgKWL42o6KCR5HqVLR/jC9tL00H3Ef7P3FlYLrPpM1epNZXaVKlsld86a9Ks8v4/cf4LNMdCue3Vrpf+gNzjVHw7X5YMwAom9eKQ4sB3EH5g7QSMPlSY/B44upssi238QiFJCrslbSxWj4Z/KL+ElZRa9YKl/Eajr48KV1Yurzy5/NGu3QVZ+Dld2/Zpr9vt4b6PsKDbW67dN5Pbjnsg3F1IW0ZCt2q/Ryn7sQ2r73HxS8NY/NImPPiW3J59Yhhq7/c6wNy8tzYgfDuisEVhX9C2/0xLbz1ls4yPLurCyoOFDz4uUPcV3is8/1XDA232XeG6z4a7UVNcfMPnq79UGytV7Em13VJFn5RBINWeSbnlUgWMVIdEqhMhZfhLFdZShaGUp0LKQJTqVEmx31LFolRRIEU0ShUaUu/nFAlSxJAUp0WqoyHVQZAixqUISymOhxSBKeXJOu/Qz5Udsm5sT+czAu8zTMjV6sKJUJV2s5JQBbsWY3LHdg/qxNpjm1R8rw1tuHiUzPti4Nh3aNBmb7Parg3NG6400g2W0GE3jszHizKtbjjdby9KqY9UfpTSGTJ74x7Xpy+l" after tData
         put "3AiZduIlf/CmVO6UMgxkDph2Dkd/8KnMUXjz5OxTYFZx+YkiP9lzVH5Cw09D+8bkJ8Z94St+XLV2zWq8w8eXvg5CgMb49gM9BeM3uN+mp/77FInz9n69Jl8Jd94xRRROQTDZL5MDhgviHSyz1+Xr9lHyJ/y/7pNqt2WKioy9KvTSYXmvSFHjyFiDDFlornJydd4rUtUJMlcYUtUmUlRh37UfbfJekap2kqLckbnskqLgkapik7yU5o2WKhal2n6polHKoJBqD6UMAakCSKpDI9UJkfI4SBXmUoWllKdEysCU6pS9qzOpCsmxocqiTepScuAw1HJSl11SFm5SV35SVr4zi49uQ0UrdZ0qZU0pZaUrdVUpdbEsVdEmVWH59XEtbdKsOInym6MznzupDq1UqUrKtCRlDpIquUiVC6RKTVJlA6kTWxEGZdyWoVFGbR0u5Z7WYVEGVnnEyrNUH5ryGJTBWp+jOlR/dxLn0ljK8l3KilmqAl7KOlqqwleqqlmqkluqRkPKpkLKDkKq1kCqSl6qxkKqWl6qtkTKGlnKcl7K0lnKgl7qilrK4lfq8lnK+lvK/kPKXkPqvkLKbkHKyl7qfkPq2l7KlkWKElqq8l6qwlqKAl+qaluKElmK4lqKslyKBkSqbkOq3kKKtkGKSl+KjkOKWl/KZmVbD8Vsuy4Oscthft6eLWAFSIqlnWy3fVuvg6DVQmdt68B/ptp8hxezNci+K/vzufr6Z9CiWvmlc7KRyoneNKsa" after tData
         put "8tL0u0rmZTKtc898fPoFuRdGJ8gMcr9/3P4F0Z/LfU0+dhgugAIov19eEo50/xcEYkeXEZY+G8nkSze65KPICHxHy8feYvUMnRSSiqeUakpl4/eEpPzxLCXtGMcv6BtYrv+dqDHqXvK/yytYoVGt0CwlvuspyLUYYCajy3uD5Aszbq+VumG+fQOsrb5Rb7IP1eJX0hY105W7Oi7UzfOdfK/8LPQ9TqqCfcFrVnVmXvH+qFn4dPZV4arZLYXby83RozywigvaD3gB/G7QTPiFXb+FSLVwBr5d7cC3s6FfSfl2VQIn80qexXKp1n92cmBZaflVcoZNRwTA1w6C5SvQguUEm0/iIEjekirplfDfsfwcmVRpAr6Ev3OqFNWJVFWMjBfze/H7PpCi+JCiuJGq/JC55JGqJJGi6JGixJGiDJGiDpG5EJG57JG57pGp8JGiXpG5qpGiYpG5rpGiZpG5spGqaJGiuJG6aJGywJG5IpFvWTHQyf8DVlz2UlUQUlcLUlYwUtU6UhYhUhcxUhY8UtRaUpVLUlZgUpVvUtYbUpYmUhYSUlUSUhdHUldSUhUeUpUyUhY9UhddUlZdUhZTI3SqVqSqaqSofqSqkqSoYmQuWaSqiaQoWqQolKSoZKQqlaSqjGQuXmSuXmQqX6QolqSolmQul2Suc6SohmSudKSoh2SudaSoiKSoYKSudaSsi6SqoKSsZaQoemQujaSqoKQqEqSoOqQsMaSqeaSsjqSqW6QseqQukKSq" after tData
         put "z6SssKQu26Qs+6SuVaQubKQuQ6SsQ6QsraSswuR3RUtRCklVNElZsklVs0lRiP2HBY21teZ0wlZd93giuAN2GJ3PqY+EiQEH2GrOeOwYYa1n49PmFF+5g1iIeHN7MRt4CZgNelC5QQ/Jtdewdk26L9lkqkn9Ci0dR6NGO+Vr6MRNKt2kMkwqy6R2y1eb2cOlg78bWOxzsaXzjha295+WSi4TCtX9ZCasAEm58iJVQj6Ah5D1SZD8FiYDMJbKyF6+oCepfGFqKmnQd+Fg4ovqQ1QwLzWdmUmpxtcbX4dNLi28tfzhqdSqz9u3Vd9txOMEJ0/z8RB/6B1wn6Gc/j624qGsXTEDS42bnxcTZdFs0d1ykcyrPrLfoj5MDJGKTUKNMg37aqk/QwVTZzC/rwp5z3CSY9EJhwTJ5YI28gwp4Oi/P36kIrcbcbSPFq8l8l5jUmQQ02JjGrV6KfX8fNQ+fwazoCTtHvdDPpEBHsP+yDc4JDfBdkxyy+D2ZIt9Si6+r8KNrZSZhctXmEyMft7aSSH752PjpK8UWyTvQJF5y+QbKfLdRKn34bt18t1sqQJXiliVT3DKJ/TkEzYyxaq84kaK6O7/rREI4LIq1GEBIkSTY8PXKeTgB7dqAl7vkQUZvO93Z/ni6PfMSD++vhX4rP5I/2q3mJ0MfGsdr8Z3u7MfhtXrNVT+Y73Gd0nAh92H/EvND6VJ/333W36QT8B//9df//6PP3/+dfnL336O69evHiXH3X/cP8fT" after tData
         put "fzwdfK6/fp3rz7n1H9vPufcfu4KP/nAQe/Yfp4KX/rDEe/BScOd9XhRB3v3hfH6uvuhafq7O61oV7LL8PUVeHXxt4OWLFLwb06uZ3tcRvK/LNLtu5/UEk3s1vQN7b6H3dZre/h68lHp3WSECvO/D9L5P0/u+Qu+Q5e+DyNv0Dl6+SMGPMX0W0/tZg/ezm2ZPM17PEUyey/QG9g69n8309vfgpeDHZYUI8F6X1RRfl800X5c9VA9xAUix69JM+WAYCw1xGO91OU3/dbko5DEd13VxnusKZutuRiRFCzPW5TY7AgKutuYIyZBHOevlxqy3G7M+YUxKNsiowbaYOeTqaw2j0bb3n2ph6z/VE4dhOu3VaTfduW7ppvtrGmyd/70mxd659wyrGHXbCQi4Kmbvcu59kEc5e3/qaXXd+9pb13au92XcQrJDRg32jrnv5OprDXM5//12e/YHctrq2rbNubYd3Nrh9pDihD1tcXscAq6GuUIy5KWcx+05FrfnWGEPJDtk1ODY3B5w9bWG2Z3/0dye44AczSqqrWYb4/qAm2YntQcUmljcnuN0exwCrrZmD8mQRzma8tQeTW5qjyYitweSHfLS4HZ7wNXXGuZx/pbHuj2W7UyOZhvVVrOQctW049w0a6k9pLhhj+XGExBwNcwTkiGPcjQVqj2a9NQeTVBuDyQ7ZNTgbm4PuPpaw6h3+mnU/Pb006hZ8LHTqFno6bSanZ5uqaajxzTQbNY7k6To3B879Zoznw0Q" after tData
         put "cLU1Xc7zDPIoR1Nkz3D94dYHXf3ogx18CnfQoMW2LApqyTrWG27Vx6M/bPpw9oddHy5DHvr49IeuXU86/UFVWFdDqqB1H6g0K/UEZ8imsJsw8lekZqueoEbhKVNTaM98/UFZrMpC+a+PsYUeAXsptCpyWwb+wcKQl3lz03z4KM0TXt00T/W92TSDdQdumq/cb5r1+u4lxRm7t2mW7bsXEHA1zGUuTnkp5/Hd2/bFd2/bV+wehQdo1GLffPfIOtYbbncpmhXVKs2fLk2zleqsecwYP+CnuU+tAoXmKrdKc61a5RBwtTV7iIY8ymlHWKWJ06xqF62C8AC9tLjDKrCO9YZ7XIrmRrVKs6hL05ylOms2U8aau5yfZkC1ihQ3rNKMq1Y5BFwN84RoyKOccw2rzi2sOndaBeEBGrU4W1gF1rHecEcE+3nGSTsvRv35xBm6lojwa2VgX3uctKRqPGnnHSctYORvK484CSk8ZV5XnDTNqXbSrocnLfV44qQNCt1LnDTyDxaGxKG+kVHuPN03csWNk3znAb6RUUj1ZEa5kVEeZJQ7M8qDE5/CU+aDjPIgozyZUajHg4wyKPQgo5D/kxnFs7HC7rDTU6/K3D2zPf1hc/67pThju1vC7HYOVCfs3D1Z34SRvyEv6EHhg8zH7dw953YWnggfQ0KPgL0UWje3k/zBgv2TkqFx8h7HG6FsZtAoaX3bhrYq2iiCvXFCG2XY7M2i9dGYPtXJ0TihjbL+SMHROIVkw2b/" after tData
         put "BF5gEu/orqi3qwAwmEAzF+kiBnCIhN4wL8C0Mlq44E1zooWLbusMTdDCRcu2BBO8e0NHMFq4aOjW0CSYoglrIRItXDR0d3gQLVw0dEcYH50ceIEJ3gNLvUOFaP/ABGAX6SISDJHQG/1qgGll2BG8oUk0k+j7ttAEzWQ0j2cwwXu0lgRHMxmt5QVNgik6wSVkZjOJ5rKFF9lNorlcwwXoKoNl8iIguk4a4LoAnpyIcNkuaeiLw3DYAFMDTIthE9inbehu0X3eoRF7TPayWzBLSHS7iWF3i253D73In33pCQ3Y3Ua36x2sYdDdotu94F50ueRKboCQgvZAJ3bI5EZt0W8v4eTEQAPaQ9uBSR+EhZRD3dh5ozO2Hnrsf9mJa5ezvHpzdOLEsPOOTtwpxk6fPbP2MN6bo/NGJ27dtWHQeaMTN4qxAydXciMEFGkPpgPo3smNmNDA5Y0Y+iLtge3ApA9gIeSkpZgKRNfu/f3Ym3MG0MCNEEwJEhNTAU4JDuhG/tHPa13rGmAqwCnBBl9zKgBNHngH0wFyJTdAOD9Ie0InYsiN2oYGLu+FgQa0h7YDkz7AxAJy0lJMLDBROKEbJxaYTyzgRkhMMBLDiQUmGCt0A3/OGho04MQCE4wbvubEAhOMA97B5IJcyY0QUKQ90AlTD3IjJjRweSOGGtAeTm+ASR/AQsihbpimcNqxQTdOUzA7OcGNEExXEoNpCqYrF3UDf8xBFmjAaQqmKw2+5jQF05UV3sFUBVyT" after tData
         put "GyGYu6Q9oRMwyY2Y0MDlvaZE8AXtoe3ApA9gIeSkpZj0YBJjM5tx2MK5jvaY52sWFJOfxHDSg8mPUYyTJY5nrIHzYRAnPTH7wTDHkBz1YPbjRK+ZD5kn0wANNDQslBtGRmSZinMMZWJfKChC2+gHYNIfbu0gihoOwyhOiLz9ew2Bcjxl3ef2HllxPJXIHEahmQyq1yQsx0fWM/nIisMojqe8NzQkh1EcTznVayqV/JNtwkg12MkZGgdbyTaRUCiEv5DpqsFOOobIwUO0nTIHJ2B2FrMtn4KN4ytOylrsckIwS0tMzM44SzsiZpJ/DLy2m4HB2VlO0zach2F4BnUengdO0cg8mQKUk7Y0LJRLVLKk4lDFxb5QUIS20Q/ApD8w3qOowWzM9zB/O6Eg53uY5i3gR0jM+xLD+R7mfSu0A38O5RpVyPkeJ343PZ8DPkz8DrqJkz4yT6YEkSYNg3IcFCZL4qCKix1RVIS2ce4JTPoD1lJUaogZJGeEGxTkDBITxxP8CMFMMjGYQWImeVE78MfgcKEKOYPkVLLR8zmExFRypZs4jQTzgSlBnFimYaEcUQNL4qCKi33NWeEX2kY/AJP+gLUUNZjNMSlnlzdzI8eTORLdmMQShsHpgMwxKQenO3MjReVg82T6yzEpBqcxBzUkx6QcnF5M1pyXJv9kS1hSpZ1UMkeuyTYt4CR34R2QSCqUdqZjiBw8BNtTZmqbQ11OWvPGyqEux7x5tSSMY95E5lAXV9edNxZF" after tData
         put "5Rg2L6Uc6nLMmzdzDnU55s0rlNPd5J9sE0aqwU7OojkgTraJhEJ33sxpHl012EnHEDl4iLZT5uAEjqBjLowx8mv0m+PmBrYDjEPpARkj6GEofVDbFIWhsdcRNqjmCDqH0ht2ZRhBU7MH7uMseuB/p52A5cR6sBNKJjLZpgVQKIS/kVSIdg6OIXLwEAfmlBnaYnJuZFo5rdvaH/Z42OxsrS9kwPrDlsgTsBUPO5HbPiFbIreJ7VEgDzycBduGhzuR94R8iNSaY922/nDjwZDmhISBqi1E+mP3clvjwcltCwhLqi2R0LbBTue/Jtt1pErfOuyAkv3BLv7tMG0JI9VF5GaPZ0ea+y64z0ItYSbqfiEJI5XVTptFcDxGSOyMhJthojBSaW3SIYrUq3Xdj9iV/YyQ2F1bwEilXyw7xFYeWKAG7xfJDam2721A6t3dH4wtYWAxIA94yINJqZ50AmB23ZspiSSMVB5y7gQodJ7QdqHMhNGmRBJGKvsU6nZeLfb4xK7bleebTWTA+sOdyA2wCw9PIp8v0q9UR95ftnbnfJAB6w/bzDa49YeM27tNyINIu5L05NmtaQ8Hj2DCSHUmEnnoufCQqSZhpMqE8UDbB3Y6/yPZHiNV+tZg+x1K9odmiXq3SABsoNqJtK+/+9MXqPvaEu5rmu0TZk5u64gkjFTNvpO21VbuscBCojWSM0w6jFTNrs+mxXGz+7DdsSvtiZBorm3ASNXshmyPrVxjgW3jsZDcFFLb25XI" after tData
         put "ZvfQYaYkbAV/ItsaHvJgUjttihFOIOwMUxJJGKk85NwJZyjUti20teh2mYTdsCmRhJGq2fl3O/clAmBDJFiXbJudyID1h0ak5Q6D7Xg4cuUxIc9EtontVSAvPNwF2zMeGuMWjyNyTaTflj/tWPCw4ggmLKm2REYeaseOB6aaAUaqlkhoe8DO9lAhwpIqfWuwfhuHkvpw4loeYKBytQ1pl2tP482uiZ6Mw32XrSQs7q0RSRip7OqwNI5HhMRB8gyTY6CyxtquyOaXwhq7sjEk7NgTRqqTdzYeYxu3i+SGPPwWTKS1ZXbRDTCwGJAnPOTB1Kns92/CCYRtYcqAJIxUHnLmhA0K+QVzRXS7zIRBoQFJGKn8GjI77zP2+Mau36zeBuQdD8+SyAbkA+RK5LNOyC2Ry8R2n5EB6w9tZhvc+kPG7XNOyAvIY/Hbsj+ceLhwBAcYqe5ERh46lgcPTDUDDFQrE8axhrbBbQf/nWwVRqqVvg3YCiX7w8rid4CRiu1Bs8u1p/HDrglNxuY+y9QDDPdWIgkj1eFXx2Mrj1hgIaEX3ZN3GWCkOqzitSvysEtBL1fbFb2RLCT8cgWMVMfGOxuPsY16qQW5IdeoE4A8rPj1iy5hO/gTeWzhIQ8mtdN6gnACYXeYkkjCSOUhF04IhY69hbYW3S6TsAc2JZIwUh12/rud6EStW9rOqfG7it7uQSuVbep2fVfu67xyZxO2zSt3tKl79rD7PiGzsNy3iW2FbLNCiSTbo0DS" after tData
         put "lOx+PS03NH4NXWHLlrGNVFsi2fixPTS257tlNFc9LyRhpHK3POkhXWBpYiG5rQSMVH7lWU0Vj0MfF+Sv3o5UfkO2d29HqgF5R4d27tGSRs9mFSBgpPL6yR1vOW8bqAZkwkhlmvnwwC6znTBS2UrCSOUPtnKNpvcEck9k9IAD1ZatcS4gi5tNdcLAYkDe29S+7UWHduAhm817n1ZexUq2jHexks1mdqL380U+2Yne95dthXyWQqF7YrsWK2HKkz2sX6oNjV+L3s4PEmAD1Q3k0NKxybMYet6Nn2XBbUQSRip3S9voIVtgaXMnua0MGKncG81iKB6zGwP5q0MDlTu5Xa8OLfu4AdnQez1x90XnZU1YwEjl3m7uPrvgjpHqzk4UMFLZkKT5rphvT8JIZbUjYaTyB9P2ihs9YKSylTt62AttcDa4XJAsWrbGhO1oD4lEyzU2Yc/cZ0V71R+GlvH5rmx7sZINUZtXNrSMLfvJdkzI7Cdbm9hWyLNQqE1srwJJU7ITPeK6iiasoUNr2b61kaolkk0YW7UbF0DCLO/3q2NEEkYqd8uSHupI+4DYryuQ20rASOVXpIVJPA49VZC/+yxQ+bV8vvssUg3IBR3UEe1h9E/WEAFGKve2HQd38z5SJTJhpDpx6cRObYSRylYSRqoLF10EwEoYqWzlg04UVHu2qbkAyJvT44EtWAzIp02t1FF0SxcesvF7jmnlU6xkW7MUKx8g1+x51gm5JXKZ2M5IwEaFhpVkuxcr" after tData
         put "dzy0RMZ1Fa1UQ5/VsglrI9WSSLZSbLgaLoABdvrVMSAJSyq/F9NDtuDy6wrkthIwUpk3mrepWyDRGYF87JZI5U72yzW7JfZUA/KMPsiqJm3yoguytmZFMwiqZWHj55fwOawckAkj1YZLx3eqX1eAkcpWEkaqnRfdE1ckYKSylQf6SVzLTzabWDCwyBlwwg60aoFEh9b4icO+FaKtWbNzSRipzvlbYSKzt1uvCZkz+vV5c3ut5MfFROYXPxvzaenNz1PDV6mEkYrpavfR4k4YqaitwUj1sGjnZ6yAkYqmGIyfxPJLGL9KuR8f2HS+vkolVSK5gMgjm7AD7dsaFxfIbSVgpLKLy5uweBw+bK28LIePXaDyiWV7fexKqgHJD08o2q/h29Iyfeza5u9ZiczO5donZH54uo43t/fKa0Lyq1SzUVQ7xk8oPDUDjFR5Um38pbXjhYMXVNTWYKQ6WJLyg0zASEVTFJZU/FozfDlZohe4sv/ILyekGpCxgMi2Zouxojm5Ii2D3FYGjFTN07JdlvGYH19A/vogA6rmU7Xr9UEmqQYkitkNJemWVWfCSHXP31wSmXX59kyfcvLjyL6+ub1W8iNNftPJLyc+PNiHMf8w3U8YqDZmk4bhAWCkSm33gWpnkho+GkR6azmwGGCkyi8KnO67HxfY1F7T/aRKJBcQeWUBfaH09jHSQ3JbCRipLs6Y8Dh8IAjy90cDUPmxP18fDZIqkfk5AAXXnTP6hJGqFd8FiMyq8z4m" after tData
         put "ZA7w7+vN7b3ymZA53ffW+BxH0ZxADzBSMZscaI0BIxW1VVhSMUnlYDtgpKIpBiMVp945gfav17ApakdOoEmVSCwg8tiyPNxQWNpOaaoJclu5ozxESbo9WR5igoIhNshfg21QHX4on9dgO8ffgURlZO749asXT79+HT/6F3X253n6a1s//utkP15z29+L6QPBdursDw76w+MMlJX95vevX5v+4nb/ob8z3H/4v8bg751qawO4B8Omv9fXf+gvr/36tS8J1oqyH3fHqlEqJ1RxklTNcMnXHmgNzfD3wLoyaYY2tb2EdAvsFrB3YPvatiR1MFG5g8DAgUWYHZy0J4z7xSWFUyjQ8HSSYe0Xi+09sFrRHVYZ2wNtojH+HljtZduVLvWtC8/aH8HZO7BwlC/jfhtL+0NMew+sDgb8cu9O2D2Ecg/9zTEajJZrtZA9GF5kEO/AIrx8mQdpxKc9B1xbcfs+qwOY44QtziVtCyxNNha+m7FfVvbYu7MHXzMBsfiJTcPF5uvU5ziCJMM13oE1VwzUHtyundXK/u7YYIKzagTdHC3Cw3iww3tgO7uYtOtD2JIbgPfAdlv8t3sC3KXuQ6jHO7CgRjh3jTU3MarjPbDqS5979YcjNjsDEu+B7bz9UugidSYZWILj3bHc4hCJYIcmeA9s/3FYOtV/KwCuC09n+AJrjkzqCB8d6B17BhuwYOJ4hLDrmQEPLDYb4WY+Co/Z1MjfHevet2tADcCxYwLAe2DNkYwY+0ux" after tData
         put "Htw/mkV+1Cb99wJ+/bp+9O8Tf/SPBOwvUPWW+LEGSf/Gs/84B7DelVdg9S/tdaXd32SgjF2E3rH+G+KdfNM/Leg/+vHpPDb/t1H0AWAt5axu87WOc7EDreIgyEPRTGJo2Vtg1DaAdI2t1r/T12eDBoUrisBjcMR7YOkKVxSB5x7JMA0sgyMcF2BS492xdImrGe6in/zd1TZfp87Yl88+BTYMDgY44gjneA8sOcd2+tke0oe/B1Y3PsPT9tzPFiIgMOrmXGzRxiD2N8cEP1uK8AW/ePfAQkxFgCI5fJIFwhfujhiLQ8dQi3dg7QAndSRQguMdYWxus7+uVd+HCjh0f8N7YOPE/C9kEKvWpIgAAA==" after tData
         break
      case "coinblock.mtl"
         put "H4sIAAAAAAAC/0XOsRGAIAwF0J4pmMAjhIRkBsdQO6XyzvUFwVDkF/+RC+V4rvv0W3Dr7sOSpUYiqokgrgyFrgqNibU9CpNjZyG1VDDFsRx1JqFxGpeZLIXmNjWGWnKdaDX/dUb8PmuSfxGITTK7F3X0fhblAAAA" after tData
         break
      case "sprig.obj"
         put "H4sIAAAAAAAC/31US3LdMAzb5xS6gN/TX/Z12iYznXlJF01z/pIgJMuxk41tAhQFQrRe3x+P3z/c659fz4/b6/vj6cMt/hbS5vwtxqJBCs3QVAQMGxJyucgc6JQ5Voc16KsXjZWpKUuuLxk5IV6gqVxVCEkrSNIW9Bmj6vABWEKGX8GszMvbGUx+Oy32pfRt5Jk3A2ud9va+zDVDU7Vxo3ifk7bv4xAvr5zPRbXLc1ET/11Ns8nUgytubKR2nLCaD9anC1QO8unjDWcpj7Uppsf5ph9FtYgD8hWPWRdJS89CcX3O1ZC3fJ14kTelWQMg2kasouGg/bb1M7ZMYF/c1yLtsHJHlh2CkfMqArMGDPyWsCmTVn1Ykz3rhH2xcEHWceER61OyYSp2EZ+hagv1sErHMBk2jq31PKzXf6FZ+YxaGW0TqlCPcyrUqoISZpA5kJhQrY25sOLKtDJKHWVdqDqJWi5ULReylm90Xcladl059kefmUtkPNex7DMEVcGKx8NhBKiIx7SrLFv67++zXMvup396ceV+31y934N3TZ5BIItArPIZBVIqgchKhCKYctUiYwTb5N1c8PJaXQjy2gRlTDLe71F3VjoGkPKnCil3yIvR2UJyiib5KKzoQpaosoTGZEVLbAorv44NlIUM4ZNnTHZXF6THJFtKW0lb6TFZEZS0a/DV2DYJVH7tzRg7CUTRSTdjsthi0s0tZoFalO2AFThKnAO7ngRaTDaKnXkWaB6AVbvBZ8Zk" after tData
         put "e3YZxsKK6RjIDr9pBo3FTpPf3LkfA8bMRQnl19MpUxkWGRVkmlKw2ZTZAldtBLWqspETaVwfGz+UDUcZG2ueTI5SGUauO5r6CB76EEc5vn2oGdLtYbMdEse320mXachh1D3X7uIYk8U2u7ZeqUvmRqbYSE2W/uSuoqvDT8adlWnLbXeUPiubIVr5lfHuNFfjZthrMDQOF8hewS6KUdduEZYFNy4knI0gTvtxsiNGVL+BajkBBC+KVkV1c8FXfAMdN5imj0sNgeFacNxpWNuvLxQ1fYr3ZWbgKMXQKMFGLRrJpRBk0oCP3syk/VQYK8eW+4mYR+wSbVuX44h4kurQMF0DEixHx7W5sdRM5Nmqa/8B7TEZCbYLAAA=" after tData
         break
      case "sprig.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0DMytwCSZpYmQNLE0oQrDyptCJE2NrEEkuZmhkDS1MiSCwDTlrHYPgAAAA==" after tData
         break
      case "character-antenna.obj"
         put "H4sIAAAAAAAC/31WSZLcOAy8+xX8AFqiRLJK35kZd8REdM8cvLzfWBIgJbH64hIysSRAkO3Pnx8f//6VPv//5/vH2+fPj2+/E61vay1pfctlh8HoCM6wcKQXnkWZh3m649cgsDmkRi7VvhXL6yH/tod9j36GbWNsyXXALBbYKbbsbayxlfA7Y1bDMJqJoZlqmkmkVzlvxWmmnObSex269u3geWgsk6bV6aZeKtFUFA2qelM0nRRNR0XXFk7FprXGMx6bndafzIW+TPBiBMM+kR/ylp+ns1Jwb+U8gHClqe+tFBKwx9Ar4g2kKfoi/l5pqmkqf9boWGYqaCb95niJttHD83xL4Hk6o9Fx5ncKphvqY7vlpFlSB/9La8pplQ+GbMsO/VTuCwQA3ZA1ETJyDeUOfScQX/XpbE0/4aV6mrT/2AK6IFUmfA6TtKfcj82jcgmEThBNFNBEKE1k0TzftSrdxdJMbeSnU5emjU59mjYaxHlRGqp6idHPldAgJZqg2VRoNhYaZF+rTIr0Axx6m5a9D4FeBc9ir+dzqIisz/PRMYXojNEMvMbCMhadHT3UMJqB09hrhZmQieBJXz39TMVE7dntCrXu1o6OnaCJ191piKMzRmfwJTZAv3585//hpb/Xb+/pWJZHyuuyPFPOy3IE1JaFF0EZxvKDzZryk39ayuzCS/qeNqb5LXRYnQQuy7Jtaav8s6eNU/Gj+J529t6eaec625H2bVl2kWC8e+9s7eoNN0661+6N" after tData
         put "WggSrT0FuJ7Z5JkNVjKb7ayq6t5lX5aSOwzbWVa1y5Qql64PG1ofk1qgKjfE97a72kgrV6/aCWywSOHiMEKfHWywNhQRxx/8Z9dZh2GDLZykFD9ZGzCqS0GzlYtydsJYhdNeGBGztCYDhitMkJXV1E2ctXWvWLnj8uwKwIYw7JxNHPOXls0GW/mnSsuNo9sa66LLI7nNBmsDESVa23eu8RG3LHMzG2ysojUQl8C33yUYG0ps3LH9ehQ9N9goiTXHlpnOvnV+CWwZ/eLmPobCAWWFu8CwwXLxIsULFy9RPMbgNlg+1CKHWrjD8vAxVM5Vjj40Z32PK9euOcYQWw8bLFeqOkv9wLSG1YANlpXU1mHro18+2B7k3o35evja91nCBqvN9hEDDm93M9bmKUp0Cji31FhAE92wwcZK2yidjQvoNthIwmH1GddFH4R+t5zVQQ7edl3sNPrlctaS+MZIlcwOme8X58k5ZS6eFdaPgLlmluls3BH/xdg4aOPniNlNbwjPcuMHhzvY+BXmKpsU35nfeV05187vECfZNYny7r3zz94Gb2b3B4LE22oV7mB/DiUtGjottut2JVeBaoMVGDZYba4vEuA4bLfBujdmhAsQo3LbWDuA7o0LEDBsn7ceisxEh+Or0ZfUbLAxWLcxyIBhGxvN4+T9cvkiwQZrY++j8nWJPTEbbHijpA0DRyresMFGEoNxXcIbNthYaWyC3e/hCTHb90S3RpTY8vlF9cvltbCaXhKriafP" after tData
         put "Ln1/KMHGxqIkLkU8q7CdDSV6HpDQn1XYYGPt8WSjZChxgWB1I+M+y2FL7SSHkmSVJEK+FS0GyB+PJNWS/F2XNuRbUTkXCylJXtEkIhnQb0XlZXYPjUOIfiuKEMmt3ppZGpJvRR+Wg3+axDUJaZajGdoE+ANL6U7IfRQAAA==" after tData
         break
      case "character-antenna.mtl"
         put "H4sIAAAAAAAC/8tLLc8tyVFINuDyTlEw0DO2NAOSRqamQNLcxJArDyptCJE2sQBJGxtZAkkLuKQRRNLUAqTCAERamFrCZY0hskbGhgjS1JQLANxWs795AAAA" after tData
         break
      case "character-arm-left.obj"
         put "H4sIAAAAAAAC/32UW3LeIAyF37sKNkACyBi8nbbJTGeS9qFp118dXWz8Q/NiOJ8uCAR+/3h7+/E1vP/6/vL29P7x9uVvSE+08yflyt/ci6PI7Mhg6ZjcLnS5eWhqMyy1TsFg8yIc/VhMauSO8fIc6AW3q6K4pHfIrNYle1hoThmmfGFZ4t0tOuS9zZ6AKxaX4Q8wruLjcqX4WYLFYul46MadDfGTZ/zMNS5942qt+JBhpiV30dbrEYs04815hdcpLPOUeAmTHu5iMaM/edL4VsgAKXNM2G+rYuiH6a6OVXQKMaunZIiaRy2n4cBC1F1iJkzdkMJnPoE5wnPQl4xLffO3NU77QscL3HUcd0+bfPEX6PuNdTCqd4bTp3aPxYvuA1ukW3pNC/w3f1wsEKeCZ7gO7k3TPiwcp5Vnxzh4/vn9wn/08C19eQ2Fnp/zFsrGQw2lQgGbNusOBVxVHzw0swKbVislKMaUedLPXGcS1WalgoEx5yiiSsicqCCBKDEgqFiwoZxGJEpKADPVRyajMbJYQi2HFWElASfdUONht+0BI0MKtOvQMDDesupDhq0YRljJioscViEkMa1W8ZYzRLZq2qzwBj6kTkpSIGWrhKppOVr+W7y6dqvEDkuK21WJabNq0Hk5sAqOI0gPyI5QThoU58YAMYHTbIHXwjZkLpTPmdSjIq4ipGqOqrQpOE6PEWAubQTJvOauPseQRXHm+a5LNxTXUG3T8pvSrgBFS11SIQOZC826n8yh" after tData
         put "3fOyoZ+Lm8XWwo1I4oEBwcmis5wYf7MMWiqk2sggjXA3iO26DLkbNam2JtCbJD3J18MhGh+OWvwx5X5df386fu/tFaCaw+4i33t/BShEbpfde3sF3e65Tk58PGB7FckfS7rh7Njuvb0C4N3eJ6XzFeDClnP36CB2x11nwxEye6F8U2qx1ovNm+iNVaWW3WK1pdbf6o3dBi0RivvYL2+tUett3m8dwxvJyM6twPGSdClLI1W7Fa2hC/u/yJvh2qzubdHaSmsszlG15/Ylcx3uSb/dE2El3dj1Ux1+WIDt6phps6Ku0u02EJmWOkj+eqrNqrFD2xWf3qbdqrfhH9yCNbaqDAAA" after tData
         break
      case "character-arm-left.mtl"
         put "H4sIAAAAAAAC/0XMsQ2AMAxE0T5TZALkxBc5noExIB2kQmJ9SIxM85t3ut7u8zriRmHdIy1SxFshoX+cjLnibQaPEbNzNq4TrErZmY2h44LnhuAKU034ixIerHuuGJoAAAA=" after tData
         break
      case "character-arm-right.obj"
         put "H4sIAAAAAAAC/3VUW5LcIAz831NwAWYBGYyvk2SnKlWzyUce549aEg/b5GdwtxpJoGY+f79e37+4z5/fPl6Pz9+vt7/OhwcV/IbowiPW1DmmjgwuHHfdxHVd3xv2O5lyvmcEeU/J22/9hJ3uyq135Cd2SP1Se5Ey3NNZatxSuNBdyzCk/B/2ljMVGtKZXHF+uf2sFM3tlMb6pdavxTdtSFVi16HMdL+r4yZdkrZ/JV2kPFOXvXwbUZDdFJVOQpnVAJMU0I4/afG7r6RZvH4qBeWVizqSS3W9T5A/gHeGDotgAfgKLtrHY8uiqIfCqhuyQtkyUllCIwhdHKljfAqpW7lG+/DtCxrZOeEB/RL7E0FV6ZZggQf0JzxO/yC8KZLbr2WiqlCUZ5U8sbrPKpkw7eeN1327uySXZ3lNdMrj7yJ/z+QXTfnFcfy9Lb9o3i+O7Udvf3598D+4+xreni7R+3vcXNp4yS5lLKANW7RgmeidlzKpDVu0Apk6OQr4BZmYMySRGJWT1bhDqWMwKD6oIinjRAlwMSulxV3iED8wbQxlcZAqWv4vIDR6gJYPO5+dFkkUW1Q3QY0awVHRZccC+hC8RV2S0fJxSOVUJBfJhUMdZTdFaZCSJSGSK+VhoQTJzRq2KOeiMtSadKIVW1QbAC3ZrJZVtqkBW1QqdW9AgHO7JHesl8sbsmPd5viWcVHyLTIjuHJxkWe8y1TRlCIJ7DMDgMSDIdnMBXemagu3XfItrCXGiIMr8os5" after tData
         put "h968mIqG+brR8jBMSmaYNDhqnLlHvYQcES0195iXEha7XvjB3FGbLcqEzSTDLUZv4WKiMHnJfMvuMS8JLZ2Ye8xLqEz99GSnJxfZD1VOLZwijXBz6D1yG4ciFzkp7GJII5vq9JaRiZckl/3UtZHQC6sfnd4ajVuLUgQLEsbeMqwTcek8F9w2Wx13LbNQ3KKoSZNaJ9VHZLhFWxKzgVgi2l+MrI3LJy6fDKIN6Lht+EipuLXb+mojwXhTm8yzYYuir4Qzy7hzn3Ifr2GNokRCSd3WN0nKkcSipm43m3VOSV8phqEE4e0S5kr6jknZrRObPndW5PZfIKzlkHeqntHnC06RRqq6SZ1zTJ4YHqGTnWjykSRRqRkm6hLEN8+OLSrmevsHYaVaoaUMAAA=" after tData
         break
      case "character-arm-right.mtl"
         put "H4sIAAAAAAAC/0XNsQ2AMAxE0T5TZAKU5OzEmYExgA5SIbE+GCPT/ObZurFdx7nHJYV5jWlq3LxCLYyPszGEnhaCHgHOxVgqvD2TM4wZCqhdj5Cdybi//JX/bTYmZv1ORbcl3JC3n2q5AAAA" after tData
         break
      case "character-leg-left.obj"
         put "H4sIAAAAAAAC/3VTSZIbMQy7zyv0AVmiepO+M4lTlSo7OYwn7w8JUksvvrREkIQA0n6+Ho/fn+759+f9cXu+Hh//XLzFbXJej3ijWADyKSCtiwQ5jWAsSdvGdpqlMlFm0F+SeiWopdrvL1l7J0pHUfv2q7pds+/dJikV6qi/ht8w9Pd9F2Dyrf/oahygfzesC15/TbxD+2IGD+cdHNAzwR++zJt8ZANbVqSgiT9TMUBKSEqSNU1omvmjNP7Mw5DsVYpbfODxkkNJMd5dxyFbq30vh8sV363VHLFzG17xo7C9Y382GB2nR1utna+S+v6689/K/YgfvxyFQC6FkNwUwsQA7kDnEGap2DhY3RLC4vi6MYS74ZT5EDBxU+K3mYDnRqtE0q6xZVM6wEmb+HGS1/VS4TTVaoMnhaPBemnwbLCoRLSaSMbEDAozyAntCJFpLmBNIUZqoxpuTmVEygJfRTALJWWDU3obE+T0aVquMsq0aMEKOqOcBjFr2xpVlasYtI0UqcXWbI0UoUeFqxOSk9qC2sgtXiBBlQjMlFTa5IUOqnSsmmxojedBknkq1UUzkDgJ7RDHI8j1d6guoq1HtauPWmVazQk/R/iJmnbLNli1Vydoqm8buBufClayphYjEsYsVfxFPmuThJqDzlwH32E6wIjFDtA8gpA0oMq/AvwPTU5bdhQHAAA=" after tData
         break
      case "character-leg-left.mtl"
         put "H4sIAAAAAAAC/0XKsQ2AMAwF0T5TZAKU+JvYmYExgA5SIbE+toyguebd2O/zOvJa0rLlMjUSK7NXexqv1tCZuxXqiF8plBtcq0VUP0UolK3E/giQHo/GjgF5AAAA" after tData
         break
      case "character-leg-right.obj"
         put "H4sIAAAAAAAC/3VTS5LdMAjcv1PoAh4J+SP5OpNMqlL1XrLIJOcPNCDLtmZji6ZpGmS/Pp/Pn+/h9fv7x/Pt9fl8/AtTeqO047WtgZ81K5rK7C9QTty054DciUuLKGSqjLZKYFr/leiIOTA17D5sftKcbu3zTgc6jeEvFMRBA92B2bL6tpUBdxqTe+5Q4DatlB+r7jTvN9hTpxH3l8Q7OPyYd0OWwtEimy7VSQKRQNnrZrAWfqgUIzUkfu0WDmQujEvre5t7FxeZDhXMuuFZGueK3cvkU1I5n/EEpMDG+kxLXMIwCfHvnw/+rcK39PgRKEYKOcYc5hhnBnAGusS4MLDFuIUaYw17jDsDOAOlxLzUihAhI8IaIWNKKMysvYbMOImYhsg0NWIJWtGuI+KgoNAFYsvFJuAWVNs8SFhXNwIM7Y5STRlRFmBCkLGmmbcrvTN8ZRjU2LKieYJJi1iPZKN6cFg6K9vgWdnV4drRYCcfNyaeVuxP1uqbFrPUTLa2Fq9Ypu5U4MKHzbtLN9r8BnPC8PYl2DXQ3hYvoEa4foN8ZSbsihZbFpo+RvaGmIV5pfNr00gZrs/8W7bB5t+aokhUdQKIu6469mlW24N+wJpb7aNI/SAnx9iH9C5aU1So6RfPOrr2IOx1KELxB7D0IF1QfcFZefwH81fwORoHAAA=" after tData
         break
      case "character-leg-right.mtl"
         put "H4sIAAAAAAAC/0XKsQ2AMAwF0T5TZAKU+JvYmYExgA5SIbE+toyguebd2O/zOvJa0rLlMjUSK7NXexqv1tCZuxXqiF8plBtcq0VUP0UolK3E/giQHo/GjgF5AAAA" after tData
         break
      case "character-torso.obj"
         put "H4sIAAAAAAAC/31Xa67eJhD9n1V4AyQGm4e30zaRKiXtj6Zdf+dxZgDDja508ZwzzBvs78fP79///O348fcfX79//vHz+6f/jvPzlehfiZH+31cRKD0spVoYq1dXSyUtavkZ1VJu9D/WNmCxZv4fy7i33Yzla8BEId55NCdqdfIqHsqTFw81l7e1mqqrhZ1e2Cuu4YVdWcKmLmFXhLCrQtikHHZlDZtChE3nwq46rFh483lzNvQ8uNEujn6h9UCLHgCGQbUbDIvFSe/pjjd+gjn6ANy4WbxsQ3xntyvBLuEPIlaQatyD8zy4eWFsiugCfenCgk3oxqyKvn9OcTJqmthumh18YzplU31+EfwQ+2oy7GxOdVq2TwmFbfBTmZZjh0MyXT0ztnrfJbRzsu2Pj3lbjw2wubutXkuBGQvvKWzrPBs2hd12h65tztzsJuxshsHo0rG2Hp0xw00h9jnvPGid+XoNW/Q9ph9hS4AA5+4DnOuoJuf2476fZ+xDcD0jk6Ow93Q+fBdnfYm0qt5PcXHfCzbr6d5RL+wUwweaq+uw9x0vzvGSd5Njt2DXjEnzcx2xJFia7J2P2CtjLkX0znHvKe/gS9+bHvWiGD7QXN2EXTxhl2DYZRg2Kf4l3wqSPL9TMxC5I+St61DW/bPWS0l05PNDZVIPsG8qpB+wte96b1r3TFvCqhS2WnM8YZNY2GQWNoGHTeRhLUF4ZRM21aW/aLpyKRU2ki9gKfF/+bhJaQqnNDl+ZjcB" after tData
         put "E/5tMOwshsGkbx92u5tgfvbY6mXnZBfiJr1NFTYJ7wOu+EyqVtD49P9PAVgGsDxWFN35NFifLPHm0Zxiqx3ejw+1QeySGek2fh3gEN9oKWxMWfZD8mvM4RUg8ra0x4JZOFto8rSJdzb7Lu4RaHsf0PfA69mYZjvxRTjNiCFhGpv3EJqpMI3N7pTsDslyRhZzodsbp/DtYs1pTXyX5Ma2/EJ6txRYn6qPkTCN3jx50sj3QBvkyIHmdQPD5P4Ceg34cgAnR//+85V+qx+/n5++HSl/+UK1SYWW60iVlpvhRg/5SA8t5bhOWirBV6SH5tqyl7Whlmh5Bu3ry5frPK6blnhcpH2xtj44TLaui2Hyfd3HRZ7pNXqRSfpAcvgmo1cFS/BNvq7HXYjn7hJspnDvRnCm3XeFr+Om5RaXKoNVF0Mk0HZYZWM9Ha2JZo3SMKyyVUzq2bUzqdGQOgzZWCpNjlxY6Ye7fNUErLss5JI+NmyTaUMGmwnOZQgQFfR0IIO1wmJONDLEyXGrbCxp36x9k5Hb2oLxYNsqg9UmsRFpkw+EBMDaKoO9KYv77sOGiqmtXkGwvbCSro+5zzcCVtbjLvSQHxs2nQtOR2WwfQZljixOD9BksDbftlva0o1ABqtN4gBpG32hclt4qbzg7JTk7CmwnWeemJuqdTU7AF4dk8FShLdok7k7WaiegclgKdRb8qVQ7+Ksw5CV9aJpUY9MIeSzj7TJYMlFTr19FqDHrTLYTAFmDjCT75zd" after tData
         put "iI20yWDNdiEjudkB0Er342IsuSzsslCkxdrZrxDIxkppum27QqQG/cIx2+5SnNjYebNNBivhs0tpkx+A13EBqwH1o6g1QsUYhgxWqu8Tk3pDGlmtTy+xyWDJeePqNJJbRPOPRlYbGzEZrJWhUZmaD5KHChlso1CbuCTfLdsgqa0+dmC1pKxNLlu1Znv7IINttLeJtkTqns2lyWBtpB9y8pxWYh3C3hCwD7WvcUPUCeattw8y2Icq+MSeJZrt6UAGq+H39llAFglksNqrwaV0y5r9zWVlPRJNwEfaLgXIYLVJPjFyk/EldB2FLyE6EXw3cb6FYqZvrkL5lnpUvptahyvFSF8hyhJcKYp6HpVipA/eSj4rD1Il2/VyF2a7kq96u7bsZZh4+slXyQX9OKxku4pteTC4USSVI+HdTdVo4bhagTbDyrJLhSUkG9LebJXBepYIUANGnJw8ZIQvybERCcnGTkvTh9RYOwBmBMl6liqD1W50GGPngwTZNrm25mFNejcNWXo6CiPAHrfKtskCxNgheR9Sk8FaTTAQGDsd8D6kNi4+JxIpDrIN6TeTwfqwYSatvn7hqGwT6+no1WcBWSSQjZUsGMaU4cKR89uvJxtNKfugrReljyZkY82IHlU7FH4JQwarZ4Wz1AMJ2K8+U8NxVW07z5zBQ84THfhbF/40kusBMthicFW56fIYDFnZeJ7A4xmBJKyXM4aYxu3M/WLywmSsxZnyYurCWGzNmfZinoV5dI3nm1GE" after tData
         put "1mhMjC8mLQwyjl4DfRoYrYG1h4eA9tIXNsEHfxnzLU/X+MHdPPj658bzs6A8P/z1yNpM2hZ5FjTrlkhrvI5IW+nncyQ+CgwZbOOFx5PMHpFKEYs4Y02VhEmUcGS/usG4DqtsbO5WOWVdkhdYZf2fZxCt9Z6XAU0zqPVM1hx+iA2JIk2vcrGSSan5PcgDTcdHngXltz8/C8oNbtI9OlkqCSHjIQpKkM3I55WbHCNkJRmFCJLMx9QjTczSbyeeD/mhDhksaz/Q9mzvIVkTD5/cFAdZLCg8qh0+swZjLv1oarTqfwgaMtiE6FBuC1pz+R+6u0I+NSAAAA==" after tData
         break
      case "character-torso.mtl"
         put "H4sIAAAAAAAC/0XOuQ2AMAxA0T5TZALk+EicGRgD6CAVEuuTC1P4N0+WXY7nuk+/gVt3DwvXQcm1icWViWGgBK0lSbWKpjhUgf8mNabBuS/PcjbmwYgW+lEahvYNSjsN0Sh+pNC/SuReXqdYJswAAAA=" after tData
         break
      case "character.parts"
         put "H4sIAAAAAAAC/0vMK0nNy0vkSizK1c1JTSsBM4oy0zNKuHJS0yFCIAZEqCS/qDifCwC53+18NAAAAA==" after tData
         break
      case "character.anim"
         put "H4sIAAAAAAAC/81a7Y7duA3936eYB7g2RIr6epxBN7tNm2SL7BR9/ZKUfceSLUu6+VMEGGcAnbF0TJGHH+8/vn5/++vj/ePr39/ozazwN3j79uWP5duX3z/k14iPxazOJHkYdA+j/0D+bUt/fv3jHx9vS3/xx58///rzzdyuef/5fX83WS9r0Ln20ue7t8XWthb/+Pjy48c7v50XebpahOMHx5mD48DBcfzgOHNwHDm4HT+4nTm4HTi4HT+4nTm4HTk4jR+cZg5OAwen8YPTzMFp5ODvcuu//vbtyxsCv9770L/24Gbu/VIsv6Zjcd2rrw9D8bHY1ZH+tPaxEK0xQccTbFjYsBlaIwuuBAAGy43hBDE4R0zLMyy8ST/oHSjI+ch7fcjf4CNSCB1vsZGzYzO0Rp7IMYn/vluBZrzH4cB2jh/b5odNYsyJkJMzqiXZ1QThx67WYcep5OPatIMztoYWBEFmiIQhXjThZg5HpjmGWp6Gd51w0NsQXyjk5V4ecgqC1SfbcT4bQWHHKrRGFvzoSUzkl3p+HDbnJvhxc/y4Nj9IxRZu+JEjUlKWjNy2tPrgCmCTHrdjFVojL+gJSk843n4/QY+fo8e36MHVFTtosyMWAGuKJA+H/D4b2ItQAW3FLvHlGZyxNbQgyCpEAloodhcm+Alz/IQWP1B+onBHkJ6RMk8GxA+5FX0ooE2CYAdnbA29IIhdzxJL644TDMU5hmKboeKOxzuG5GfKD5fEgvh2Wlcgm+on" after tData
         put "7eCMraEXBJESVLjHNEFQmiMotQgyZZBId3owyoNI949BGOL74lIBbTIUdnDG1tALtSgmm8oQC2ZGH5pJgWjaJBVagxfesJT1G+Y4HET38RosoU2WnuCMraFXmjoKS4VQgykVPSujhzLogRSaeSlXd1KLYvl1crFAsYkZzQyTohlw1FjwdWPB140Fh41lRjnDpHQGO+h3wL7ueMC+7nnADrueGf0MkwIaaDCAAb0cwYBeD2FAozEMZmQ0TOpocINKCNzrUgjc61oI3KgYghk9DZOCGgYVNfyCpIZf0NQwKqphRlXDpKyGMJiWQXg1L4PwcmIGYTQzgxlhDZPKGuJgbg/x5eQe4svZPcTR9B5m1DVMymtIgzUiSK8XiSC9XiWCNFomwhmJjZMSG02bp0DlLm542qqMWlO1cgOJWAdhib2vNjI4Y0/QK5qi0IRFMXRGY+OkxsahWjW+XqzG16vVOFSu1tL+f9+//esNSDdn/987egu5mZ7ecfVrTT1i1bDJU3BrpG5jTwAaAli8ngAHDii4g8xOSW04WXdfyN9yENzUo81/iR+WtCp/W8g3GSy/sXempMrKp4dgwV2X8lN42hquMVK9y6u8xPLZ+Rf5FMS/YbcnaKPuDNgdntYfKTP+ENcML5Q9cZZwV9sHl08NGp8A5dBWfDjEFVgZNkr7+lXQ5kCVfb14eo5WTDIjXTxX9lfDF8zk/opYAEp6gjHU27zKUawRO0MkDSeYqNtPtHouZOouAAfWLMWj" after tData
         put "/xbT4e/tbKveH54xR1hD9d6gfgpUVbOuQdcq+CsKNtMOGreibNexJTFjjA3+XPJn4rwkNJjpTttlk79WbtXdMCeBFXXHptMB2JnjGHwGNJkTG6XV+dRqBJyIYyEkWpOPIPaGnqnwrVZASVyWj1bjQoCHQP25FVDTxrsFNrjk64369iUVT8hcE5/OdDoD2y1FNoYLRPOeOhfyw7V6BCHf03wKUCZiVDOFGFWrA4ZWj6C4qJKiuOze+ZYzf4w1T9fmC+qsXlW3O+sFAhu2r7ca2jHBxyJ6hLtwAFAvboQCTpHVRSUD9x2DLRKAfkUxfk4a5cM7TX5v+wUGn0JWQNn3orZ00zP7CwVZcIgF8qGAPxH4eqOdFOdkNd0sZ7mA9HVE7OiIPZWN6t2SRpKh/sGOzdAa2ah2opJ63z8gyvef3f/JJV0nOcQBSGzQXXi9Is3ZTVz4F9tip+TxvpOwyQR5QQDO4ThDAfVfIYbbNgIm+VQcKIAeWb2L57Ln/sFmUWT0EPz/i61ddhFs/uIoereOeo1OgqRX4uguAmvZS7DB7kxlryWxC+77CQDZAp1UUAIfn32WEC6RDkKznZBrpA+tBjp2++kRWJ2DBMho6KKVsLl6SkoYyk8Xbb3DK/EO+dZappr4tkuw7HUV0DuNqBL2LiAHynBzCbxUAyQLo4TN/sKWF+arwX4RORKHh5gVKmMRYrPXsF8P4RqYLdFkkZ1PEM70ceo6rGpjLijPpIFYYn61xyvRj5A/EGs9" after tData
         put "DPowvRYEBlUhzPJyBTmamYmfnLHCCGz10GxEuN28ttIbux4Sa1FJxm/6jG7nPkR27CLWNRvn+MbH93oh+F4m5y/aEGxoElGcz6yphPUx1bu8lP1bJOGbA5bzCzr3L053M4kzNZL8XEEKTfF09aglbyuOZRNLN90JOFRt5MMK0DtRFf7gvaGl/9Xg5FZjiPxix9/LijKNF52Jp6bQM+l0Fcv+q41OzBLC1DAhjEwTAk3l2TSXaI/PFP7zP9///Qae9+Auyw4kmim33ZAlYErd2gNZ3JtPVqKQGyhATA0WkkYzdnv8k8VStxjxWahR5JKhS419bbDwyE9Ud92tTRz4Ib5uYWDyWHJGFyYGDDn1kByZL49wZMenCzNwUeRSQ5v1PgihM2B45MnxYbrliCNNke88DswpS7KCdnTOUBM7dcDq/AA5v7NjU4Zxhy6wOc4KfMFUVKZ8tJ1BwyNTyG9O3SLEgSpWV8HBwGRz3bih+76NVa1gMl1m9YnGpg3dDl3MxlcFbvZtqDdweOAJWIT4fsnhyBOn6NisOZRtwOJO33ZLdXkmKrK8iSv4ztThBsQduGTkUkKvGoDa/7OdqcMjR25N0XXrCweOHJu4ca36QtlSlnrH4PihNoXBSFBPKPreubHZQ0w7csnQpcJetd2dcBmS74wfHomiyp2FLlG+dGhhcJIjdAc5LD9AFSBH0sEJxDzEIcglQ5cK2xji4JvZnUEsaZLiaq+OUNKUCjUQ2zypyh6rJUhKJhkg" after tData
         put "m8amC8bqCDtuycClRF7JJ3FfsEbsFhKKWwexX0c4kCTB1LbqCHckpS5JRhWBlhzRhLFZxB24ZORSQVs0ce5uqDeNeORJUu/YryMcmcLTqOHgAJXp3zvySpXkX5jS4ERi2KFLxi41uHXz+Jv3ZhKPXCV2e7FfQTiGO5amRResOZp48uW384m7MxcvJd0YzEWYoVHFtEOXjF1qcMOdg693iF0VJaWqbvXgyJc4N9+sHtzog9sZxk0gOKtOPXBGm5wdm2DcJIKz2aurxC/B1yKBbcun3gzjkSzJkWy/aHCU56lSFu1RxnpayHZVJ2kARKkY6aW8H2MsVCflCCj+qAY3VCer+NKyevpcSmCpXyg4kuWrWnp7nrFOZm5LBls2Q2Jaeh9hdSH2ygdFOkP280bW6EY+k1YytjfSWKbI0uMwvbHGMkcOKZaQJmHOw+hoI2mDzsYsHLRahh57g42f80MZu2TwckJfpcpONDsa6M023tZc/HzRxQ9VXfyrZRf/K3UXP1J4+R8qR2En9D4AAA==" after tData
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
--         b3kSetSubsteps n / b3kSetStepMode fixed|smooth / b3kStepMode() /
--         b3kKillFloor y / b3kWorld() / b3kEnsureNativeLib
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
--         b3kSetLook thing,objTextOrPath[,mtlText,scale] /
--         b3kAddLookPart thing,part,objTextOrPath[,mtlText,scale] /
--         b3kPoseLookPart thing,part,x,y,z[,rx,ry,rz,sx,sy,sz] /
--         b3kSetLookPose thing,x,y,z[,rx,ry,rz,sx,sy,sz]
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
-- the step mode (empty or "fixed", or "smooth") and how far the smooth
-- steps have taken the simulation clock from sFrames whole sixtieths
local sStepMode, sSimDrift
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
-- a look's moving parts (b3kAddLookPart) and poses (b3kPoseLookPart,
-- b3kSetLookPose): [thing][part] -> source, materials, scale, mesh key,
-- node, pose; [thing] -> the whole look's pose; [thing] -> true when posed
local sPartSrc, sPartMtl, sPartScale, sPartKey, sPartNode, sPartPose
local sPose, sPosed
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
   put 0 into sSimDrift
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
Summary: Choose how the running loop divides a frame's time into physics steps.

pMode: "fixed" (the default) or "smooth".

Example:
b3kSetStepMode "smooth"

Description:
"fixed" steps a sixtieth of a second at a time and carries what is left of
a frame over to the next one, so a frame runs a whole number of steps: at 26
pictures a second some frames run two and some three, and what moves seems
to speed up and slow down. "smooth" uses up each frame's time in equal
steps no longer than a sixtieth (38 ms as three of 12.7 ms), so things move
as far as the time that passed. <b3kStepOnce> always takes one sixtieth, in
either mode. The mode is kept until it is set again.

References: b3kStepMode (handler), b3kStart (handler), b3kStepOnce (handler)
*/
command b3kSetStepMode pMode
   if pMode is "smooth" then
      put "smooth" into sStepMode
   else
      put "fixed" into sStepMode
   end if
end b3kSetStepMode

/**
Summary: The step mode set by <b3kSetStepMode>.

Returns: "fixed" or "smooth".

Example:
put b3kStepMode() into field "Mode"

References: b3kSetStepMode (handler)
*/
function b3kStepMode
   if sStepMode is "smooth" then return "smooth"
   return "fixed"
end b3kStepMode

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
   put empty into sPartSrc
   put empty into sPartMtl
   put empty into sPartScale
   put empty into sPartKey
   put empty into sPartNode
   put empty into sPartPose
   put empty into sPose
   put empty into sPosed
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
   local tN, tDt
   b3kInputTick
   b3kPlayerTick
   b3kGlideTick
   put empty into sEvents
   if sStepMode is "smooth" then
      -- the frame's whole time, in as few equal steps as keep each no
      -- longer than a sixtieth (the accumulator is capped above, so no
      -- more than kB3kMaxSteps)
      if sAccum >= 1 then
         put trunc(sAccum / kB3kStepMs) into tN
         if tN * kB3kStepMs < sAccum then add 1 to tN
         put sAccum / tN into tDt
         repeat tN times
            b3kWorldStep tDt
         end repeat
         put 0 into sAccum
      end if
   else
      repeat while sAccum >= kB3kStepMs
         b3kWorldStep
         subtract kB3kStepMs from sAccum
      end repeat
   end if
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

-- the simulation clock in milliseconds: whole sixtieths, and what smooth
-- steps added or took away (0 in the fixed mode, so the same number as ever)
private function b3kSimMs
   return sFrames * kB3kStepMs + b3kNum(sSimDrift, 0)
end b3kSimMs

-- one physics step, its events harvested and its moves carried to the
-- picture. Box3D keeps only the LAST step's events and moves, so they are
-- read after every step, not once a frame.
private command b3kWorldStep pDtMs
   local tCount, i, tA, tB
   if pDtMs is empty then
      b3WorldStep sWorld, kB3kStepS, sSub
   else
      -- a smooth step (b3kSetStepMode): its own length, and the clock
      -- told how far it differs from a sixtieth
      b3WorldStep sWorld, pDtMs / 1000, sSub
      add pDtMs - kB3kStepMs to sSimDrift
   end if
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
   put empty into sPartNode
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
      b3kPosedSyncAll
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
   if sPosed[pThing] is true then b3kPoseSync pThing
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
      b3kPosedSyncAll
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
   -- a thing with parts (b3kAddLookPart) and no look draws its parts alone
   if sPartSrc[pThing] is an array and sLookKey[pThing] is empty then
      b3kPartsMake pThing
      exit b3kVisualMake
   end if
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
   if sPartSrc[pThing] is an array then b3kPartsMake pThing
   if sPosed[pThing] is true then b3kPoseSync pThing
end b3kVisualMake

-- a thing's parts as nodes of their own, untagged (the moves of a step
-- leave them alone: b3kPoseSync places them), listed in sNode as well so
-- visibility and removal reach them
private command b3kPartsMake pThing
   local tPart, tKey, tNode
   repeat for each key tPart in sPartSrc[pThing]
      if sPartNode[pThing][tPart] is not empty then next repeat
      put sPartKey[pThing][tPart] into tKey
      if sMeshes[tKey] is empty then
         if sPartSrc[pThing][tPart] contains return then
            get r3MeshParseObj(sPartSrc[pThing][tPart], sPartMtl[pThing][tPart])
         else
            get r3MeshLoadObj(sPartSrc[pThing][tPart])
         end if
         if it is a number and it > 0 then put it into sMeshes[tKey]
      end if
      if sMeshes[tKey] is empty then next repeat
      put r3NodeCreate(sScene, sMeshes[tKey]) into tNode
      if tNode is not a number or tNode <= 0 then next repeat
      put tNode into sPartNode[pThing][tPart]
      if sNode[pThing] is empty then
         put tNode into sNode[pThing]
      else
         put comma & tNode after sNode[pThing]
      end if
      if sVisible[pThing] is false or b3BodyIsEnabled(pThing) is false then r3NodeSetVisible tNode, false
   end repeat
   put true into sPosed[pThing]
   b3kPoseSync pThing
end b3kPartsMake

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
   -- a look (b3kSetLook) and parts (b3kAddLookPart) wear their models' own
   -- materials
   if sLookKey[pThing] is not empty or sPartSrc[pThing] is an array then
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
         (b3kSimMs() + 1000 * max(0.02, b3kNum(pSeconds, 1))) into sGlide[pThing]
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
      put (item 4 of tG - b3kSimMs()) / 1000 into tLeft
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
   -- a new picture: the old nodes and any mesh they alone owned go first
   b3kVisualRemake pThing
end b3kSetLook

/**
Summary: Give a thing's look a moving part, such as a leg or an arm (render3dxt only).

pThing: The thing.

pPart: The part's name, any word.

pSource: The part's model: OBJ text, or the full path of a .obj file. Its origin is the point it turns about (a hip, a shoulder); empty takes the part away.

pMaterials: The text of the part's material (.mtl) file, for OBJ text; empty leaves it white.

pScale: A size multiplier; empty means 1.

Example:
b3kAddLookPart tHero, "leg left", tLegObj, tLegMtl

Description:
Parts are drawn with the thing, and turn and move with it; place and
turn each one inside the thing with <b3kPoseLookPart>. A thing with parts
and no <b3kSetLook> draws its parts instead of its shape. Parts change
only the picture: the thing collides as its shape. Things that share a part's
model share one copy of it. box3dxt's renderer draws the shape.

References: b3kPoseLookPart (handler), b3kSetLookPose (handler), b3kSetLook (handler)
*/
command b3kAddLookPart pThing, pPart, pSource, pMaterials, pScale
   local tNode
   if sKind[pThing] is empty or pPart is empty then exit b3kAddLookPart
   -- the old node, if the part was there
   put sPartNode[pThing][pPart] into tNode
   if tNode is not empty then
      if sScene is not empty then r3NodeDestroy tNode
      delete variable sPartNode[pThing][pPart]
      put b3kItemOut(sNode[pThing], tNode) into sNode[pThing]
   end if
   if pSource is empty then
      delete variable sPartSrc[pThing][pPart]
      delete variable sPartMtl[pThing][pPart]
      delete variable sPartScale[pThing][pPart]
      delete variable sPartKey[pThing][pPart]
      delete variable sPartPose[pThing][pPart]
      if sPartSrc[pThing] is not an array then
         -- no parts left: the shape (or the look) is drawn as before
         delete variable sPartSrc[pThing]
         b3kVisualRemake pThing
      end if
      put true into sStale
      exit b3kAddLookPart
   end if
   put pSource into sPartSrc[pThing][pPart]
   put pMaterials into sPartMtl[pThing][pPart]
   put max(0.0001, b3kNum(pScale, 1)) into sPartScale[pThing][pPart]
   put "look:" & base64Encode(md5Digest(pSource & numToChar(1) & pMaterials)) into sPartKey[pThing][pPart]
   put true into sPosed[pThing]
   -- the first part takes the place of the shape's picture
   if the number of lines of the keys of sPartSrc[pThing] is 1 and sLookKey[pThing] is empty then
      b3kVisualRemake pThing
   else if sScene is not empty and sNode[pThing] is not empty then
      b3kPartsMake pThing
   end if
   put true into sStale
end b3kAddLookPart

/**
Summary: Place and turn one part of a thing's look.

pThing: The thing.

pPart: The part's name, from <b3kAddLookPart>.

pX: Where the part's origin sits, in metres across the thing (its own x); empty means 0.

pY: Up the thing; empty means 0.

pZ: Along the thing, forward being +z; empty means 0.

pRx: Degrees about the thing's x (a leg swinging forward and back); empty means 0.

pRy: Degrees about its y (turning); empty means 0.

pRz: Degrees about its z (an arm raised sideways); empty means 0.

pSx: A stretch across; empty means 1.

pSy: A stretch up; empty means 1.

pSz: A stretch along; empty means 1.

Example:
b3kPoseLookPart tHero, "leg left", 0.15, -0.5, 0, 30 * sin(tPhase)

Description:
The turn is made about x, then y, then z. Call it as often as the part
moves, every frame for a walk: it only remembers the pose, and the parts
are placed once when the picture is drawn.

References: b3kAddLookPart (handler), b3kSetLookPose (handler)
*/
command b3kPoseLookPart pThing, pPart, pX, pY, pZ, pRx, pRy, pRz, pSx, pSy, pSz
   if sPartSrc[pThing][pPart] is empty then exit b3kPoseLookPart
   put b3kPoseText(pX, pY, pZ, pRx, pRy, pRz, pSx, pSy, pSz) into sPartPose[pThing][pPart]
   put true into sStale
end b3kPoseLookPart

/**
Summary: Move, turn and stretch a thing's whole look within it (render3dxt only).

pThing: The thing.

pX: Metres across the thing; empty means 0.

pY: Metres up it; empty means 0.

pZ: Metres along it; empty means 0.

pRx: Degrees about its x (a lean forward); empty means 0.

pRy: Degrees about its y; empty means 0.

pRz: Degrees about its z (a lean to the side); empty means 0.

pSx: A stretch across; empty means 1.

pSy: A stretch up (below 1 squashes); empty means 1.

pSz: A stretch along; empty means 1.

Example:
b3kSetLookPose b3kPlayer(), 0, -0.1, 0, 0, 0, 0, 1.2, 0.8, 1.2

Description:
For bounce and character: a squash on landing, a stretch in a jump, a
lean into a run, a bob when still. The look and its parts move together;
the thing collides as before. With no pose given, or every value empty,
the look sits as it was made.

References: b3kSetLook (handler), b3kPoseLookPart (handler)
*/
command b3kSetLookPose pThing, pX, pY, pZ, pRx, pRy, pRz, pSx, pSy, pSz
   if sKind[pThing] is empty then exit b3kSetLookPose
   put b3kPoseText(pX, pY, pZ, pRx, pRy, pRz, pSx, pSy, pSz) into sPose[pThing]
   put true into sPosed[pThing]
   put true into sStale
end b3kSetLookPose

-- "x,y,z,qx,qy,qz,qw,sx,sy,sz" from a place, degrees and stretches
private function b3kPoseText pX, pY, pZ, pRx, pRy, pRz, pSx, pSy, pSz
   return b3kNum(pX, 0) & comma & b3kNum(pY, 0) & comma & b3kNum(pZ, 0) & comma & \
         b3kQuatEuler(b3kNum(pRx, 0), b3kNum(pRy, 0), b3kNum(pRz, 0)) & comma & \
         b3kNum(pSx, 1) & comma & b3kNum(pSy, 1) & comma & b3kNum(pSz, 1)
end b3kPoseText

-- a turn about x, then y, then z (degrees) as a quaternion "x,y,z,w"
private function b3kQuatEuler pRx, pRy, pRz
   local tCr, tSr, tCp, tSp, tCy, tSy
   put cos(pRx * pi / 360) into tCr
   put sin(pRx * pi / 360) into tSr
   put cos(pRy * pi / 360) into tCp
   put sin(pRy * pi / 360) into tSp
   put cos(pRz * pi / 360) into tCy
   put sin(pRz * pi / 360) into tSy
   return (tSr * tCp * tCy - tCr * tSp * tSy) & comma & (tCr * tSp * tCy + tSr * tCp * tSy) & comma & \
         (tCr * tCp * tSy - tSr * tSp * tCy) & comma & (tCr * tCp * tCy + tSr * tSp * tSy)
end b3kQuatEuler

-- the product of two quaternions "x,y,z,w": pA turned by pB first
private function b3kQuatMul pA, pB
   local tAx, tAy, tAz, tAw, tBx, tBy, tBz, tBw
   set the itemDelimiter to comma
   put item 1 of pA into tAx
   put item 2 of pA into tAy
   put item 3 of pA into tAz
   put item 4 of pA into tAw
   put item 1 of pB into tBx
   put item 2 of pB into tBy
   put item 3 of pB into tBz
   put item 4 of pB into tBw
   return (tAw * tBx + tAx * tBw + tAy * tBz - tAz * tBy) & comma & (tAw * tBy - tAx * tBz + tAy * tBw + tAz * tBx) & comma & \
         (tAw * tBz + tAx * tBy - tAy * tBx + tAz * tBw) & comma & (tAw * tBw - tAx * tBx - tAy * tBy - tAz * tBz)
end b3kQuatMul

-- the point "x,y,z" turned by the quaternion pQ
private function b3kQuatTurn pQ, pX, pY, pZ
   local tQX, tQY, tQZ, tQW, tTX, tTY, tTZ
   set the itemDelimiter to comma
   put item 1 of pQ into tQX
   put item 2 of pQ into tQY
   put item 3 of pQ into tQZ
   put item 4 of pQ into tQW
   -- t = 2 (q x v); v' = v + w t + q x t
   put 2 * (tQY * pZ - tQZ * pY) into tTX
   put 2 * (tQZ * pX - tQX * pZ) into tTY
   put 2 * (tQX * pY - tQY * pX) into tTZ
   return (pX + tQW * tTX + tQY * tTZ - tQZ * tTY) & comma & (pY + tQW * tTY + tQZ * tTX - tQX * tTZ) & comma & \
         (pZ + tQW * tTZ + tQX * tTY - tQY * tTX)
end b3kQuatTurn

-- a list without one item
private function b3kItemOut pList, pItem
   local tItem, tOut
   put empty into tOut
   repeat for each item tItem in pList
      if tItem is not pItem then put tItem & comma after tOut
   end repeat
   delete the last char of tOut
   return tOut
end b3kItemOut

-- a thing's picture made again: its nodes go, then b3kVisualMake
private command b3kVisualRemake pThing
   local tHandle
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
   delete variable sPartNode[pThing]
   b3kVisualMake pThing
   put true into sStale
end b3kVisualRemake

-- every posed thing placed, once a picture: the moves of the steps put a
-- tagged node at its body, and a part's node is untagged; a pose changed
-- by the game a dozen times a frame is placed once, here
private command b3kPosedSyncAll
   local tThing
   repeat for each key tThing in sPosed
      b3kPoseSync tThing
   end repeat
end b3kPosedSyncAll

-- a posed thing's nodes placed: the body, then the whole look's pose,
-- then each part's own
private command b3kPoseSync pThing
   local tXf, tBq, tRoot, tRq, tRs, tP, tQ, tNode, tPart, tPose, tAt, tLook, tParts, tScale
   if sRenderer is not "render3dxt" or sScene is empty or sNode[pThing] is empty then exit b3kPoseSync
   put b3BodyTransform(pThing) into tXf
   if tXf is empty then exit b3kPoseSync
   set the itemDelimiter to comma
   put item 4 to 7 of tXf into tBq
   put sPose[pThing] into tRoot
   if tRoot is empty then put "0,0,0,0,0,0,1,1,1,1" into tRoot
   put item 4 to 7 of tRoot into tRq
   put item 8 to 10 of tRoot into tRs
   -- the look's own node (not a part): the root pose alone
   put empty into tParts
   repeat for each key tPart in sPartNode[pThing]
      put sPartNode[pThing][tPart] & comma after tParts
   end repeat
   put b3kNum(sLookScale[pThing], b3kNum(sScale[pThing], 1)) into tScale
   put b3kQuatTurn(tBq, item 1 of tRoot, item 2 of tRoot, item 3 of tRoot) into tP
   put b3kQuatMul(tBq, tRq) into tQ
   repeat for each item tNode in sNode[pThing]
      if (comma & tParts) contains (comma & tNode & comma) then next repeat
      r3NodeSetTransform tNode, item 1 of tXf + item 1 of tP, item 2 of tXf + item 2 of tP, item 3 of tXf + item 3 of tP, \
            item 1 of tQ, item 2 of tQ, item 3 of tQ, item 4 of tQ
      if sLookKey[pThing] is not empty or sPose[pThing] is not empty then
         r3NodeSetScale tNode, tScale * item 1 of tRs, tScale * item 2 of tRs, tScale * item 3 of tRs
      end if
   end repeat
   -- each part: its place stretched and turned by the root pose, then the
   -- body's turn; its turn the body's, the root's and its own
   repeat for each key tPart in sPartNode[pThing]
      put sPartNode[pThing][tPart] into tNode
      put sPartPose[pThing][tPart] into tPose
      if tPose is empty then put "0,0,0,0,0,0,1,1,1,1" into tPose
      put b3kQuatTurn(tRq, item 1 of tPose * item 1 of tRs, item 2 of tPose * item 2 of tRs, item 3 of tPose * item 3 of tRs) into tAt
      put b3kQuatTurn(tBq, item 1 of tRoot + item 1 of tAt, item 2 of tRoot + item 2 of tAt, item 3 of tRoot + item 3 of tAt) into tP
      put b3kQuatMul(b3kQuatMul(tBq, tRq), item 4 to 7 of tPose) into tQ
      r3NodeSetTransform tNode, item 1 of tXf + item 1 of tP, item 2 of tXf + item 2 of tP, item 3 of tXf + item 3 of tP, \
            item 1 of tQ, item 2 of tQ, item 3 of tQ, item 4 of tQ
      put sPartScale[pThing][tPart] into tScale
      r3NodeSetScale tNode, tScale * item 8 of tPose * item 1 of tRs, tScale * item 9 of tPose * item 2 of tRs, tScale * item 10 of tPose * item 3 of tRs
   end repeat
end b3kPoseSync

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
   delete variable sPartSrc[pThing]
   delete variable sPartMtl[pThing]
   delete variable sPartScale[pThing]
   delete variable sPartKey[pThing]
   delete variable sPartNode[pThing]
   delete variable sPartPose[pThing]
   delete variable sPose[pThing]
   delete variable sPosed[pThing]
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
   put b3kSimMs() into sPlayJumpAt
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
   put b3kSimMs() into tNow
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
