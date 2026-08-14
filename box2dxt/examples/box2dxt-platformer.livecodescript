-- =====================================================================
-- box2dxt-platformer.livecodescript  /  Game Kit Phases 1+2+3+4 showcase
--
-- A SEVEN-LEVEL collect-them-all platformer (each level its own
-- scrolling world in a 1024px viewport) that exercises everything
-- built so far: the Kit's PLAYER CONTROLLER (b2kPlayerAttach drives
-- movement, jumping, grounding, state and animations - this file holds
-- no movement code of its own), atlas spritesheets with named
-- animations and scaling, the camera (follow + bounds + shake),
-- synthesized sound, the full Wave 1 toy box, the Wave 3 + Wave 6
-- bestiaries (bats, mimics, piranhas, the ghost, kickable shells,
-- crushers, a frog, a barnacle, a spider), the kit's JOINT + dynamics
-- systems (a sagging rope bridge, a rolling boulder, an exploding
-- barrel), and variety walkers (mouse, worm, ladybug, fire slime).
-- Collect EVERY coin on a level (the goal
-- flag turns GOLD), touch the flag, and the next level builds; level
-- 7's flag is the win. Anything without sheet art falls back to plain
-- graphics, so all seven levels run even with no asset folder (the coin
-- totals count themselves as each level builds).
--
-- HOW TO RUN
--   1. In OXT, make a new stack. Put this whole file into the STACK script.
--   2. Make sure the box2dxt extension is loaded. Close and reopen.
--   3. First run asks for the repo's Spritesheets folder (remembered in a
--      stack property; Shift+Reset re-asks; Cancel = placeholder shapes).
--
-- CONTROLS  arrows or A/D run / SPACE / UP / W jumps (tap = hop, hold =
--           full) / jump AGAIN in mid-air = DOUBLE JUMP / jump off a wall
--           you are sliding = WALL JUMP / SHIFT or X = DASH (a flat zip) /
--           DOWN/S ducks (brakes to a stop in place) - and DOWN+JUMP
--           on a one-way deck (bridge, clouds) DROPS THROUGH it / UP/DOWN
--           at the L2 ladder CLIMBS (JUMP lets go) / ride the moving LIFTS
--           (they carry you) / the MOUSE DRAGS the crate (chained weights
--           are NOT draggable) / R restarts the CURRENT level / ESC pauses
--           / M mutes the synthesized sound
--
-- THE SEVEN LEVELS (every beat holds a coin; the flag advances):
--   LEVEL 1  GREEN HILLS (8640px) - movement + the toys: the
--            SPRINGBOARD mid-meadow (sky coin above; a 42px hop for
--            non-bouncers), the BONK ROW (headbutt ?-boxes, SMASH bricks
--            into debris), the one-way BRIDGE over a spike slime, the
--            slope MOUND, one-way CLOUDS with the fly, the bee, the
--            SPIKE PIT, a fast MOUSE, a hopping FROG, a coin on the open
--            meadow run, a flying ladybug - then the rope-bridge finale,
--            the crusher alley, and the hilltop SWIM POOL to the flag.
--   LEVEL 2  THE WORKS (5952px) - the machines: drag the
--            CRATE onto the yellow BUTTON to open the gate (coin in
--            the gateway), the Wave 2 LADDER up to its bonus ledge,
--            the red CHECKPOINT, the saw LEVER (STAND at it to power
--            the sweeping saw down - running past never flips it),
--            both SAWS, a crawling WORM, a lurking BARNACLE, the THWOMP
--            ALLEY (chained weights: ride the second one's head to the
--            top coin; grab the YELLOW KEY between them), a breather
--            cloud with its bee,
--            the Wave 5 LIFT BAY (its signature: RIDE the moving deck
--            across the grinder for a mid-bay coin - platform-carry),
--            then the crusher alley and the WALLED DOOR - a stone
--            curtain to the ceiling, so the stone steps, the coins and
--            the FLAG behind it are reachable ONLY through the door.
--   LEVEL 3  FROZEN CITADEL (6592px) - everything at once,
--            on ICE (~15% acceleration: momentum rules): the Wave 5
--            WALL-JUMP SHAFT (its signature: climb two ice pillars to a
--            top coin - or double-jump the slot), a ladybug, spring
--            over the first spiked pit, a bonk row, the first sweeping
--            saw, a second spiked pit, a checkpoint, a thwomp guarding
--            the RED key, the glacier run (a SECOND always-on saw under
--            a snow cloud) with a ROLLING BOULDER that slides the ice
--            head-on (leap it), the blue crusher alley, the red walled
--            door, snow steps, the final flag.
--   LEVEL 4  HAUNTED HOLLOW (6656px) - WAVE 3's bestiary in
--            the purple biome: a MIMIC field (grass blocks that do
--            not belong - they wake and lunge), the SNAIL (stomp it
--            into a SHELL, kick the shell, bowl the slime down the
--            path), two BATS roosting under a stone bar (they drop
--            and swoop), a pit, a long FOUR-burrow PIRANHA row (they
--            will not rise under your feet), the shy GHOST that drifts
--            closer while you face away, a SPIDER that drops from an
--            overhang, two faced CRUSHERS around a
--            LAVA strip crossed by a COLLAPSING BRIDGE (cross the
--            crumbling planks fast, or double-jump it), a smouldering FIRE
--            SLIME, the POWDER KEG bay (an explosive barrel + woodpile,
--            scattered by b2kExplode), the red crusher alley (its
--            signature gauntlet), purple steps, the flag.
--   LEVEL 5  SCORCHED DUNES (6400px) - WAVE 7's DESERT biome, run LONG (the
--            length + variety pass): THREE acts across three THORN PITS. ACT 1 -
--            a sand DUNE to crest, a sand slime, a hopping FROG, PIT1, a two-
--            cloud HOP, a snail, a lurking BARNACLE. ACT 2 - a darting FLY, a
--            second dune a sand BOULDER rolls down at you, a high SAND CLOUD
--            route, a FIRE slime, a second frog. ACT 3 - a treasure MIMIC, a
--            second fly, a final cloud route, a homeward snail, and sand steps
--            to the summit flag. ~24 coins, three checkpoints.
--   LEVEL 6  CAVERN DEPTHS (6400px) - the asset-expansion DIRT biome, run DEEP
--            (the length + variety pass): THREE acts across three pits. ACT 1 -
--            the WALL-JUMP SHAFT of floating dirt columns (slot coin + bonus
--            GEM), a spike GAP, a DIRT-RAMP mound, a one-way DIRT CLOUD, a slime,
--            a hopping BLOCK SLIME, a snail, a leftward CONVEYOR. ACT 2 - the
--            CRUSHER GALLERY: two BATS roosting on a dirt overhang, two faced
--            dirt crushers, a wider spike chasm. ACT 3 - the DEEP RUN: a dropping
--            SPIDER, a stalking GHOST, a floor BARNACLE, a cave PLANT, a spiked
--            chasm a LIFT ferries, a rightward speed CONVEYOR + a second block
--            slime, a FIRE slime, a treasure MIMIC and a finale crusher to the
--            flag. ~24 coins, three checkpoints.
--   LEVEL 7  STONE KEEP (a VERTICAL TOWER, ~2300px tall) - the asset-expansion
--            STONE/CASTLE biome, CLIMBED not crossed: you JUMP UP one-way stone
--            ledges that zig-zag to the top of the keep, and the camera SCROLLS
--            UP with you (the only level that scrolls vertically). The length +
--            variety pass makes it a BLADE-AND-WARDEN GAUNTLET: SIXTEEN ledges,
--            FIVE sweeping spinners guarding the gaps + a stationary half-blade,
--            and three WARDENS holding the wide "fight" ledges (a slime, a hopping
--            frog, a SPIKE slime you dodge). ~22 coins up the climb, two bonus
--            GEMs (mid + summit), the flag atop the keep (the win); torchlit walls
--            and windows. (Multi-key/switch PUZZLES are the remaining slice 3.)
--
-- WHAT TO VERIFY (the Phase 3 + level-rebuild OXT pass)
--   1. Feel: a TAPPED jump is clearly shorter than a HELD one; jumping
--      still fires ~90ms after running off a ledge (coyote); pressing
--      jump just before touchdown fires on landing (buffer).
--   2. SOLID GROUND EVERYWHERE (the chain ghost-rule fix): the mound
--      walks up the left ramp, across, down the right with no
--      fall-through at any edge; the bridge deck and BOTH clouds are
--      solid out to their visible ends; the LEVEL EDGES are hard stops
--      (thick slabs - no creeping past the first/last screen).
--   3. NO EVENT EVER MISSES (per-step harvest fix): every coin touch
--      collects, every stomp registers - even on heavy frames. The
--      PRESSURE PLATE is now POLLED, not event-counted: pressed exactly
--      while something physically sits on it (a crate that settles and
--      falls ASLEEP still holds it; ~0.2s release grace - no flapping,
--      no chime spam). Things shoved into the PIT are DESTROYED below
--      the kill floor, never fall forever; losing the crate closes the
--      gate.
--   4. STOMPS SQUASH (judged by the controller's land/fall state, not
--      post-impact velocity): land on a normal slime = squash + bounce;
--      its sides hurt; the SPIKE slime hurts from every side.
--   5. Thwomps: underside kills while falling/rising; the resting head
--      is a platform (it rests STATIC - a chained weight can NOT be
--      dragged or shoved by the player); it rises and re-arms in place.
--   6. HUD "lands" rises by exactly 1 per touchdown; stand still 2+ min
--      (never ASLEEP); hurt/win cut control then respawn restores it.
--   7. Camera follows smoothly over each level's full width; build time
--      per level stays tolerable; ms/frame stays ~16-18.
--   8. SOUND (Phase 5 audio, all b2kToneMake - zero asset files): cues
--      for jump, land, coin, stomp, hurt, checkpoint, gate, win. M
--      mutes/unmutes; an engine with no audio stays SILENT, no errors
--      (the HUD would show the b2kSoundStatus reason).
--   9. Reset and stack-reopen leave no ghosts (R resets, ESC pauses).
--  10. WAVE 1 toys (all verdicts POLLED geometry + windows, no contact
--      events on statics): the springboard relaunches whenever your
--      feet rest in its band (b2kPlayerJump, so no ground-snap swallow)
--      and reaches the sky coin; each ?-box pays exactly ONE coin then
--      shows its empty face; bricks shatter into chunks that the kill
--      floor sweeps (no debris ghosts after the bounce); the gate
--      button shows pressed/idle switch art in step with the polled
--      plate; STANDING at the lever (not running past) powers the
--      sweeping saw down (ghosted, spin stopped, harmless) and a second
--      stand powers it back up; the key rides the hero's shoulder, the
--      WALL-DOOR opens on approach (no pressing-in needed; the passage
--      body is parked off-world then disabled, the lock dissolves into
--      the wall) and STAYS open through respawns; the hero walks
--      through IN FRONT of the open door art (scenery builds before
--      him) and the passage coin pays on the way; the wall runs to the
--      ceiling, so NO route - thwomp-ride arcs included - reaches the
--      steps or the flag without the door; the crate wears the
--      empty-box face but still drags; spike tips show in the pit; the
--      steps past the door are STONE biome.
--  11. WIN-STATE CLARITY: collecting a level's LAST coin turns its goal
--      flag GOLD with a banner + chime; touching the flag short of the
--      total BUZZES and banners how many coins remain (throttled; the
--      HUD repeats the hint). On the walled-door levels the last coins
--      live behind the door, so the GOLD moment lands in sight of the
--      flag. The red checkpoint flag only marks respawn - never a win.
--  12. THE LEVEL FLOW: flag on L1/L2 banners "LEVEL N CLEAR!" and the
--      next level builds ~1.2s later (outside the physics frame); R
--      restarts only the CURRENT level; the final dialog shows TOTAL
--      time and falls across all four; Play again is a fresh L1 run.
--      The boundaries audit rides pfBounds: every level gets thick
--      INVISIBLE side slabs PLUS edge wall segments PLUS the matching
--      camera clamp, all hugging the level CONTENT (just past the spawn,
--      just past the flag) - check you stop right by the start / the flag
--      and the view never scrolls out onto bare floor past either end.
--  13. WAVE 2 player actions (the Kit's controller, harness v10):
--      DUCK: DOWN anywhere on the ground brakes to a crouch (the duck
--      pose; hitbox unchanged this wave - you cannot duck under saws).
--      DROP-THROUGH: DOWN+JUMP on the L1 bridge drops to the low road
--      (mind the spike slime) and off both cloud rests; same on L2's
--      breather cloud; solid ground just ducks. The deck is SOLID
--      again immediately after (land back on it).
--      CLIMB: the L2 ladder (right of the gate) climbs to a bonus
--      ledge + coin; UP grabs it, JUMP lets go with a normal jump,
--      climbing down to the floor steps off.
--      KNOCKBACK SPLIT: contact damage (slime sides, spike slime, saw
--      brushes, spike tips, thwomp undersides, the fly) now POPS the
--      hero away with a hit pose + ~1s of mercy (HUD counts "hits") -
--      he NO LONGER teleports to the checkpoint; only lethal FALLS
--      (pits, leaving the world) respawn ("falls" counts those).
--  14. WAVE 3 bestiary (LEVEL 4; all polled, zero Kit changes):
--      SNAIL: stomp = shell (not a kill); ANY touch of the parked
--      shell kicks it sliding at 520px/s AWAY from you; it bowls over
--      the slime (and any walker it reaches), REVERSES off walls, and
--      its sides hurt - stomp it again to park it. The kick sound is
--      new. MIMICS: the two grass blocks sit dead still until you are
--      ~90px away, then wake (jump face) and lunge in hops; one stomp
--      each. BATS: roost under the stone bar, drop when you walk
--      near, swoop to head height and bob; one stomp each. PIRANHAS:
--      rise from the two burrow holes on a cycle, bite, sink - and
--      refuse to rise while you stand over a mouth; unkillable (skip
--      or time them). GHOST: drifts toward you ONLY while you face
--      away; turn around and it freezes in its shy pose; untouchable
--      - it is the level's pressure, not a kill. CRUSHERS: the L4
--      thwomps wear the block FACES (idle/fall/rest swap with state).
--      If a spook's left/right facing looks mirrored, report it (the
--      sheet's native facing is unverifiable statically).
--      No enemies.png in the folder? The four spook makers skip
--      SILENTLY and L4 still completes (snail/crushers/lava remain).
--  15. THE SHOWCASE MECHANISMS (the kit's JOINT + dynamics systems, all
--      example-side, zero Kit change; verdicts are POLLED, so a hit can
--      never be outrun). L1 ROPE BRIDGE: the planks SAG under you and
--      spring back; cross by walking (a moving body needs no carry); a
--      slip into the chasm respawns you at the new CHECKPOINT on the
--      brink (a quick retry, never a whole-level replay). L3 BOULDER (a
--      sprite-faced stone): it slides the icy flat head-on, JUMPING lifts
--      you clear (it passes through you and is judged by a poll); it
--      recycles forever, never reaching the kill floor. L4 POWDER KEG:
--      coming near lights the fuse, then
--      b2kExplode scatters the woodpile and knocks you if you lingered;
--      retreat on the telegraph. NEW SPECIES (slime FAMILY, native foes
--      art): a fast MOUSE (L1), a slow WORM (L2), a LADYBUG (L1/L3), a
--      FIRE SLIME by the lava (L4, spike-type - hurts every side). The
--      HUD now shows "awake N/M" bodies (watch it fall as things sleep).
--  16. WAVE 5 MOVES (the Kit controller's new abilities, on everywhere;
--      each level leans on one new beat - all example-side, zero Kit
--      change). DOUBLE JUMP: a second jump fires in mid-air (clears the
--      taller beats). WALL JUMP: hug a wall while airborne to slow the
--      fall, then jump to launch up-and-away. DASH (SHIFT or X): a flat
--      horizontal burst on a cooldown. DUCK: DOWN brakes to a stop in place.
--      PLATFORM CARRY: a grounded hero on a moving lift inherits its
--      velocity. The signature beats: L1 has a coin on the open meadow run;
--      L2 LIFT BAY (jump the
--      pedestal, RIDE the deck across the grinder for the mid-bay coin,
--      step off the far pedestal - a fall onto the grinder is a recoverable
--      knockback; the ~200px gap is also double-jumpable); L3 WALL-JUMP
--      SHAFT (climb the two floating ice pillars to the top coin - a
--      straight double-jump up the slot also reaches it, so it is never
--      trick-only; walk under the pillars unobstructed). PLATFORM CARRY is
--      demoed by the L2 lift bay above; L4's lava crossing is now the Wave 4
--      COLLAPSING BRIDGE (item 17), not a lift. EVERY new-move coin is also
--      reachable WITHOUT the trick (the double-jump is universal), so no
--      level can dead-end. FEEL is unverifiable statically - tune the Wave 5
--      knobs in OXT and confirm: the L2 lift carries you (stand still and
--      drift with the deck), DOWN brakes a running hero to a stop in place
--      (no hitbox reshape this build), and the L3 slot is climbable by
--      wall-jumps AND a plain double-jump.
--  17. PHASE E LAVA SERPENT (L4, over a WIDENED lava pit - this replaced the old
--      collapsing bridge, which never read right). The pit is now a 512px chasm
--      (2944..3456, up from a cramped 192px strip) crossed in TWO ~160px hops over
--      a middle STEPPING-STONE (deck y490), with a single faced CRUSHER guarding
--      the approach. A rearing LAVA SERPENT (snakeLava art, bodiless) rises OUT of
--      the lava, arcs ACROSS it and sinks back in, PEAKING at the stepping-stone -
--      so it contests the very rock you must land on (time your hops between its
--      rises). A slip onto the lava OR a brush with the serpent's head is a
--      recoverable knockback (pfOuch) back to a bank, never a kill. VERIFY in OXT:
--      the serpent reads as rising from / sinking into the lava (its lower body
--      hidden by the lava tiles), its head reaches the stepping-stone deck at the
--      peak, each hop is clearable by a running/double jump, and the mid-stone
--      coin is grabbable between rises; tune gLSerpPer (the crossing period) in
--      pfMakeSerpent to taste. (L6 reuses the same serpent as a GOO-pool snake.)
--  18. WAVE 6 BESTIARY II (frog / barnacle / spider - all example-side, no Kit
--      change, no harness bump). FROG (L1 far meadow, ~x4660): a native-art
--      HOPPER that crouches then LEAPS at you when near; STOMP it from above (it
--      rides the slime stomp path), its side touch knocks back. Confirm it hops
--      toward you, stays in its band (never springs into a pit), and squashes on
--      a clean stomp. BARNACLE (L2, ~x3460, between the third-bay snail and the
--      chained crusher): a clam that lurks shut, OPENS as a telegraph, then SNAPS
--      a brief hurt-window and cools down - a watchful run clears it, a jump
--      always clears it. Confirm the open-before-bite warning and that jumping
--      over is safe. SPIDER (L4, ~x4416, under a small purple overhang on the run
--      to the chained crusher): OPTIONAL (Family C art) - it crawls the bar and
--      DROPS as you pass under, then climbs back; grab the 4440 coin while you
--      dodge. Confirm it drops on approach, hurts on contact, climbs back, and
--      that a MISSING spooks sheet simply omits it + its overhang (the level
--      still completes). Art FACING polarity (frog/spider flip) is statically
--      unverifiable - flag any mirrored sprite for a one-line flip fix.
--  19. WAVE 7 DESERT BIOME - LEVEL 5 "SCORCHED DUNES" (the first 5th level; the
--      win now needs gLevel>=5). A new SAND level, laid out GENEROUSLY (every
--      beat 250px+ of clear air, audited before building - the answer to Wave
--      6's crowding). VERIFY: the sand DUNE (ramp slope) walks up/across/down
--      with no fall-through (the chain ghost-rule); the THORN PIT (2000..2256,
--      four spikes) is a running/double-jump leap and a slip burns + respawns at the checkpoint (1900, at
--      the brink); BOTH sand clouds are solid to their visible ends; the
--      bestiary II reads with ROOM here (frog ~1500, barnacle ~3300 - no
--      crowding; no spider, which needs a ceiling the open desert lacks); the
--      sand STEPS + flag finale plays; the HUD/help/splash now say "of 6"
--      and L5's flag ADVANCES to level 6 (the win moved to L6 - see item 20).
--      New biome: confirm the sand art reads with no missing-frame fallbacks.
--      THE LENGTH + VARIETY PASS (now ~6400px / ~24 coins / three checkpoints):
--      ACT 2 adds a darting FLY, a second dune a sand BOULDER rolls DOWN at you
--      (it re-parks at 4160 so the bank you land on stays safe - confirm it does
--      not trap you), a high SAND CLOUD route, a FIRE slime (no stomp) and a 2nd
--      frog; ACT 3 adds a treasure MIMIC, a 2nd fly, a final cloud route and a
--      homeward snail. Confirm the boulder is dodgeable on the climb, the fire
--      slime cannot be stomped, and the three thorn pits (PIT1 2000, PIT2 3840,
--      PIT3 5376) each have a working brink/far-bank checkpoint.
--  20. ASSET-EXPANSION PHASE B, SLICE 1 - LEVEL 6 "CAVERN DEPTHS" (the DIRT
--      biome: terrain_dirt_*, previously unused; the win now needs gLevel>=6).
--      VERIFY on a full asset folder: (a) the BACKDROP is the dark cave (not
--      blank) - pfBuildCaveBackdrop draws it; no border line shows on the two
--      panels; (b) the dirt ground/ramps/cloud/cliff-corners read with NO
--      missing-frame fallbacks; (c) the spike rows sit FLUSH between the carved
--      pit lips - no bare gap at the left edge, no spike overhanging the ground
--      on the right (the horizontal fix; check the L1/L3/L5 pits too, it changed
--      those); (d) wall TORCHES flicker and
--      light the gloom; CHAINS/STALACTITES hang from the top WITHOUT clipping
--      the hero, and orientation looks right (gotcha 26 - flip if not); the rock/
--      mushrooms/bush sit clear; (e) the WALL-JUMP SHAFT slot coin is reachable
--      by wall-jump AND a straight double-jump (never trick-only), and the bonus
--      GEM above the shaft is reachable (lower it if not); (f) the dirt MOUND
--      walks up/across/down with no fall-through; the DIRT CLOUD is solid to its
--      ends and DOWN+JUMP drops through it; the spike GAP is a clean leap; the
--      slime, the snail, and the BLOCK SLIME (slice 2) all patrol solid ground -
--      the block slime HOPS its band (jump frame airborne, squish idle settled,
--      no apex-flicker) and stomps to slime_block_rest; (g) the CONVEYOR BELT
--      (slice 3) carries you LEFT when grounded on it - you walk slower toward
--      the goal and faster back, you can still power across, and jumping over it
--      is unaffected; the tread art faces the push direction (flip - OXT-verify
--      it reads). (h) THE LENGTH + VARIETY PASS (now ~6400px / ~24 coins): ACT 2
--      is a CRUSHER GALLERY - two BATS roost on a dirt overhang (split bands, no
--      mid-air collision), two faced crushers to dash between, a wider PIT2; ACT
--      3 is the DEEP RUN - a SPIDER drops from its overhang as you pass, a GHOST
--      stalks the stretch, a floor BARNACLE telegraphs, a cave PLANT snaps, a
--      LIFT ferries the spiked PIT3 (or double-jump it), a rightward speed belt +
--      a second block slime, a FIRE slime (no stomp), a treasure MIMIC and a
--      finale crusher to the flag. Confirm spacing reads (not cramped), every
--      enemy patrols solid ground, and a missing enemies.png degrades the spooks
--      (bat/spider/ghost/mimic/plant) SILENTLY with the level still completable.
--      L6's flag now ADVANCES to L7 (the win moved to L7).
--  21. ASSET-EXPANSION PHASE C, SLICE 1 - LEVEL 7 "STONE KEEP" - a VERTICAL
--      TOWER you CLIMB (the win now needs gLevel>=7). *** THE BIG OXT ITEM: the
--      camera must SCROLL UP smoothly as the hero climbs *** - this is the only
--      level that scrolls vertically (pfBoundsV opens gCamTopY/gCamBotY; every
--      other level pins y=320). If the vertical scroll is wrong, that is where
--      to look (the per-frame camera in b2kFrame + pfBoundsV). ALSO VERIFY: (a)
--      the hero spawns at the BOTTOM and the view starts there; (b) the one-way
--      stone LEDGES are solid from above and you JUMP UP THROUGH them from below
--      (drop-through still works); (c) the zig-zag is climbable jump-to-jump (or
--      with a double-jump) and the side WALLS keep you in the tower; (d) falling
--      drops you to a lower ledge / the floor, never off the world or to a
--      respawn (the kill plane is off); (e) all 22 coins are grabbable up the
--      climb, BOTH bonus GEMs (mid-climb + the summit double-jump) are reachable,
--      the flag is atop the keep; (f) the backdrop is the dark stone keep and the
--      chrome (HUD/help/buttons/level-picker) stays put while the world scrolls;
--      (g) the tower is CENTRED and the stone SIDE-WALLS fill the viewport margins
--      each side - no dead backdrop, and the taller wall still builds fast; (h)
--      THE LENGTH + VARIETY PASS (now ~2300px / SIXTEEN ledges / ~22 coins): FIVE
--      sweeping SPINNERS guard the gaps (stand SAFE on the lower ledge, time the
--      jump - a mistime is knockback, never lethal), a stationary HALF-BLADE sits
--      on the final ledge (land clear, hop over), and three WARDENS hold the wide
--      ledges - a slime to STOMP, a hopping FROG, and a SPIKE slime to DODGE (no
--      stomp on the spikes). Confirm the walkers rest on their one-way ledges and
--      patrol without falling off; the spike-slime leap to L14 is fair; spinner
--      timing reads (tune pPerX if frantic); a missing enemies.png leaves the
--      spinner spots safe but KEEPS the native slimes/frog (still a climb). The
--      win screen says ALL SEVEN LEVELS CLEAR. (Multi-key/switch puzzles: slice 3.)
-- =====================================================================

local gStarted, gHero, gHeroSpr, gHudLast, gHurtLock
-- Phase G: the chosen hero SKIN (beige/green/pink/purple/yellow). One word; the
-- hero anim defs and the creation frame interpolate it, so a rebuild re-skins the
-- whole character (pfLoadSheets runs in pfStartGame). gHudPortrait = the bottom-
-- left avatar (hud_player_<skin>) showing the choice. Persists across the run.
local gHeroSkin, gHudPortrait
local gCoins, gCoinsTotal, gAssetsOK, gLoadNote, gWon
-- GEM bonus pickups (separate from the coin/flag gate): collect them for a
-- bonus tally shown in the HUD + the win screen; the flag never depends on them.
-- gGems/gGemsTotal are per-level; gGemsBank/gGemsAllTotal carry the run total.
local gGems, gGemsTotal, gGemsBank, gGemsAllTotal
-- Phase F collectibles. COIN SCORE: bronze/silver/gold coins are worth 1/2/3;
-- the flag still gates on the coin COUNT (gCoins/gCoinsTotal, unchanged), so this
-- is a pure bonus tally (gScore/gScoreTotal per level, banked across the run and
-- shown on the win screen). The hidden STAR: one hard-to-reach challenge pickup
-- per level (gStars/gStarsTotal are 0/1 per level), its own dim->lit HUD slot and
-- a win-screen line, mirroring the gem banking exactly.
local gScore, gScoreTotal, gScoreBank, gScoreAllTotal
local gStars, gStarsTotal, gStarsBank, gStarsAllTotal
local gHudStar, gHudStarLast
-- the PARALLAX backdrop: a per-biome scene tiled across 3 card panels that drift
-- slower than the 1:1 foreground (depth). gBgLastHS gates the per-frame redraw.
local gBgPanel, gBgLastHS
-- Phase F: the ART HUD - screen-fixed hud_* sprites that replace the bottom text
-- readout. Built card-fixed (before b2kCamOn, like the backdrop) from a 2nd "hud"
-- view of the tiles atlas at HUD scale; digit FRAMES swap ON CHANGE only (the
-- 4Hz/write-on-change rule, far cheaper than the per-frame field relayout it
-- replaces). gHudOK = the art HUD is active (false = no hud_* art -> the text
-- field stays as the fallback, so the demo never ships blank). gHudCoinD = the two
-- collected-count digit sprites; gHudCoinLast caches the last value drawn.
local gHudOK, gHudCoinIcon, gHudCoinD, gHudCoinTot, gHudCoinLast, gHudTotLast
local gHudKey, gHudKeysLast
local gHudGemIcon, gHudGemD, gHudGemLast, gHudGemTotLast
-- Phase F health: gHearts = the live pip count (reset to kHearts each level);
-- gHudHeart = the five heart icon sprites along the bottom-left; gHudHeartLast
-- caches the last count drawn so pfUpdateHearts only redraws on change (4Hz rule).
local gHearts, gHudHeart, gHudHeartLast
-- Phase F: with the art HUD on, the old bottom text readout becomes a DEBUG
-- overlay (the dev stats) toggled with the ` key. gShowDebug is its on/off state.
local gShowDebug
-- Polish pass: the boot title screen + the full-screen transition card that
-- COVERS each level teardown/rebuild (no visible construction). gAtTitle is
-- true while the title is up (SPACE starts); gCardFade is the fade-out ramp
-- (0 = opaque ... 100 = clear); gCardGen invalidates a stale fade send when a
-- newer cover supersedes it; gTitleHeroSpr is the title's live hero preview;
-- gCardArt is the CR-list of per-level illustrated-card art controls (long ids)
-- that fade/raise/hide as a set alongside the tint base + title text.
local gAtTitle, gCardFade, gCardGen, gTitleHeroSpr, gCardArt
local gGate, gGateSprA, gGateSprB, gPlateHoldMS, gPlateLook, gCamOK
local gIntroPan, gRunStart, gFalls, gWinLock, gFlagHint, gWinSecs
local gOuches   -- Wave 2: contact hits (knockbacks) - falls stay falls
local gBuilding, gLands, gPrevState, gHudNextMS, gGateVel, gAirMS
-- the five-level game: which level, its width/name, and the banked
-- totals carried across level clears for the final win screen
local gLevel, gLevelW, gLevelName, gTotalFalls, gSecsBank
local gEdgeL, gEdgeR   -- the playable L/R edges (content-hugging); set by pfBounds
local gCamTopY, gCamBotY, gKillPlaneY   -- camera Y clamp + kill plane; pfBounds pins gCamTopY=gCamBotY=320 (no vertical scroll), pfBoundsV opens them for the climbing levels
local gPlateX, gGateUpY, gGateDownY, gDoorX, gDoorWord, gCheckX
-- enemy/trap tables, indexed 1..N (see pfMakeSlime/pfMakeThwomp/pfAddMover)
local gSlimeN, gSlimeB, gSlimeSpr, gSlimeKind, gSlimeDir
local gSlimeMin, gSlimeMax, gSlimeGoneAt
local gSlimeDeadX, gSlimeDeadY   -- Phase D: the squash point, so the defeated art POPS up as it fades
local gSlimeT          -- Wave 3: per-row timer (mimic hop cooldowns)
local gBlockN, gBlockB, gBlockSpr, gBlockState, gBlockT, gBlockX
local gMovN, gMovSpr, gMovX, gMovY, gMovAX, gMovPX, gMovAY, gMovPY
local gMovHurtW, gMovHurtH, gMovFlip
local gConvN, gConvL, gConvR, gConvY, gConvDir   -- Phase B: conveyor-belt zones
-- Wave 3 (bestiary I): the piranha burrows, the ghost, the spooks sheet
local gPlantN, gPlantSpr, gPlantX, gPlantState, gPlantT
local gGhostSpr, gGhostX, gGhostY, gGhostShy
local gSpooksOK        -- enemies.png loaded (ghost/bat/piranha/mimic art)
local gCheckSpr, gCheckpointOn, gRespawnX, gRespawnY
-- Wave 1 (the iconic-feel base): springboard, bonk row, lever, key+door
local gToysOK, gSpringSpr, gSpringX, gSpringMS, gSpringBackMS
local gBonkN, gBonkHost, gBonkSpr, gBonkKind, gBonkUsed, gBonkX
local gBonkMS, gPlateSpr
-- the per-frame hero snapshot (read ONCE in b2kFrame; every tick
-- shares it - each b2kPosition/b2kPlayerState is an FFI round-trip)
local gHeroPX, gHeroPY, gHeroState, gJumpMS
local gHeroHalfH        -- the hero capsule's half-height (head reach for bonks)
local gDebrisNext, gDebrisUntil
local gLeverSpr, gLeverX, gLeverArmed, gSawOn, gSawMov, gSawSpr
-- MULTI-KEY doors (Phase C slice 3): a level may now plant SEVERAL coloured
-- key+door pairs. gKeysHeld is the comma-list of colours the hero is carrying
-- (Phase F: shown as hud_key_* icons in the art HUD, which appear on pickup and
-- vanish when a door consumes the key - this retired the ride-along key sprite).
-- The rest are per-door arrays indexed 1..gDoorN (gDoorX/gDoorWord were single
-- globals - one door per level).
local gKeysHeld, gDoorN, gDoorOpen, gLockSpr, gDoorSprT, gDoorSprB, gDoorHostNm
-- LATCHING switch-gates (Phase C slice 3, part 2): a floor/ledge switch that,
-- once pressed, opens its coloured gate FOR GOOD (the kinematic gate rises out
-- of the way and rests). Indexed 1..gSwN; gSwDone[i] = open AND settled (idles
-- in one compare thereafter).
local gSwN, gSwX, gSwWord, gSwOpen, gSwDone, gSwGate, gSwSpr, gSwGateSprA, gSwGateSprB, gSwGateVel
local gDebrisB, gDebrisSpr, gCrateB, gCrateSpr
-- Phase D juice: a small pool of DUST motes flung from a stomped foe (the
-- debris pattern - pooled bodies parked off-world, flung on the event, re-parked
-- by pfTickDust - so nothing is created mid-game). Built every level.
local gDustB, gDustUntil, gDustNext
local gBlockChainA, gBlockChainB, gBlockFace
local gGoalSpr, gNoticeUntil, gFlagNoteMS
-- Polish pass (the showcase round): three classic mechanisms riding the
-- Kit's JOINT + dynamics subsystems (all example-side, zero Kit change).
-- The ROPE BRIDGE is a row of plank bodies hinged end-to-end and pinned
-- to the world; the ROLLING BOULDER is a dynamic ball (a sprite-faced
-- stone) re-parked on a cycle so it never nears the kill floor; the
-- EXPLOSIVE BARREL fires b2kExplode to scatter a woodpile of crates.
-- Per-critter speed + squash frame let the slime FAMILY carry the new
-- walker species (mouse, worm, ladybug, fire slime) with no new tables.
-- gSlimeFlip is the per-row facing polarity (gotcha 26): the snail's
-- sheet art faces the OPPOSITE way to the slimes', so it flips inverted.
local gSlimeSpeed, gSlimeFlat, gSlimeFlip
local gBoulderN, gBoulderB, gBoulderSpr, gBoulderHomeX, gBoulderHomeY
local gBoulderResetX, gBoulderT, gBoulderHurtR, gBoulderGrace, gBoulderVX
local gBarrelN, gBarrelB, gBarrelSpr, gBarrelX, gBarrelY, gBarrelState, gBarrelT
-- Wave 5 showcase: the moving-platform LIFT (platform-carry). A KINEMATIC
-- box driven by VELOCITY (carry reads b2BodyVX, so a position-driven body
-- would report zero velocity and never carry its rider). pfTickLift flips
-- each lift's vx at its min/max endpoints (write-on-change only - a resting
-- lift must keep moving, so it ASSERTS velocity, but only at the turns).
-- gLiftVX caches the last-written vx so the tick never re-sets an unchanged
-- velocity (gotcha 17). Indexed 1..gLiftN.
local gLiftN, gLift, gLiftMin, gLiftMax, gLiftSpeed, gLiftVX
-- Phase E: the rearing SERPENT (L4 lava, L6 goo). A bodiless snake sprite that
-- rises out of a hazard pool, arcs across it and sinks back in, peaking high so it
-- CONTESTS the crossing (gotcha 16: a proximity-poll hurt, the saw rule - you TIME
-- it, you never stomp it). gLSerpL/R = the pool lips it travels between;
-- gLSerpSurfY = the surface it emerges from; gLSerpPeakY = the head's height at the
-- centre peak; gLSerpVis caches its shown/hidden state so the visibility flip is
-- write-on-change. Single-instance (one serpent per level), reset on each build.
local gLSerpSpr, gLSerpL, gLSerpR, gLSerpSurfY, gLSerpPeakY, gLSerpPer
local gLSerpHalfH, gLSerpVis
-- Wave 6 (bestiary II), all example-side: the FROG joins the slime family
-- (gFrogAir, indexed by slime row, tracks its mid-hop pose so the crouch frame
-- is set once on landing, not every frame). The BARNACLE is a bodiless timed
-- bite-cycle (the piranha pattern held still); the SPIDER is a bodiless
-- ceiling-crawler that drops on the hero (the ghost/mover pattern). Indexed 1..N.
local gFrogAir
local gBarnN, gBarnSpr, gBarnX, gBarnY, gBarnState, gBarnT
local gSpiderN, gSpiderSpr, gSpiderX, gSpiderY, gSpiderHangY, gSpiderDropTo
local gSpiderMinX, gSpiderMaxX, gSpiderDir, gSpiderState

constant kMoveSpeed = 280
constant kJumpSpeed = 430
constant kPfUIVersion = "11"   -- Polish: transition card + boot title screen + recomposed win card
-- Phase F health: the forgiving five-heart buffer. A contact hit (pfOuch) costs
-- ONE pip with a mercy window between hits; emptying the row routes to the
-- respawn (pfHurt), which REFILLS it - so the hero never hard-fails on contact,
-- it just loses ground back to the checkpoint. Declared up here so its first use
-- (pfStartGame/pfBuildHud) is lexically AFTER it (gotcha 29: a constant
-- referenced before its declaration resolves to nothing and silently zeroes).
constant kHearts = 5
-- The playable box hugs the level CONTENT, not the raw world width. The hero
-- spawns at x 120 and each goal flag sits near the right end, so the side
-- walls sit just past the spawn (kPfEdgeL) and just past the flag
-- (goal + kPfEndCap) - no empty walk-off room before the start or after the
-- finish. The INVISIBLE side slabs stop you near the spawn / the flag; an
-- always-on per-frame clamp and a direct camera-scroll backstop hold the box
-- even where OXT will not collide an off-card slab or apply b2kCamBounds.
-- kPfEdgeL eased back to 64 (92 jammed the hero against the screen edge).
constant kPfEdgeL = 64
constant kPfEndCap = 40
-- Flags/checkpoints are 64px frames whose pole base lands on the frame bottom,
-- so a flag CENTRED at surface-32 rests its base on the floor line (verified
-- against the atlas: zero footroom). On the user's engine the flags still read
-- as "floating" a few px above the surface (a scrolled-group vertical quirk in
-- how a sprite created mid-scroll lands), so every flag/checkpoint is PLANTED
-- this many px deeper -- the base sits slightly INTO the ground, never hovering.
-- This is the single knob: bump it if a flag still floats in an OXT pass.
-- The real float turned out to be a cast-creation scroll-shift (flags were
-- BORN while the camera was scrolled), now fixed by building the cast at
-- scroll 0 (see pfStartGame's ORDER LAW). So this no longer fights an offset -
-- 8px is just a subtle plant so the pole base reads as rooted, not balanced.
constant kFlagPlantPx = 8
constant kHeroSheetB64 = "iVBORw0KGgoAAAANSUhEUgAAAYAAAAEACAYAAAC6d6FnAAAI/ElEQVR42u3dPVLjShgFUJlyxCJwTOqVQEDORojYCDkBrMSpY7EIUl4knixjj9vqH7V0TtVUYaZLvhZPffUZ3tA0AAAAAAAAAAAAAAAAAAAAAAAAAABAHquxB3h7ufsZe4zn16+VLwVAJQUQY+OfQhEosLKcf6ioAIYX7NPDdnSI989d9gtagdWfWxFAxgLoX7QxNv5zRZDqYlZgZTfQuZx/WFQBpN78c5SAAiu7gc7h/MPiCiDX5p/yQlZg886uBCDcTcjiHJt/iufJWWD948d8mybHa6g5e+rXAIssgO4iyrX5Dy/kmBexAiu7gdZ6/sEEUCkFVvZ55nT+YVEFUOridRHbQAETQJWbp03U+QcFgA0UmKx1rAPdbj8OHn/vHqOuB2CCBTDczLvPndrUQ9fnoMDKcv6hwgIYXoibzf3vx227P7owQ9eX2HwUmPMPS3AT88Ltb+bd4/6a0PUlNp/N5v73z6mNJmR9yQ001nrnHxTA7N92UGAfzj8oABQYoAAAUABDw2+6te3+6HF/Teh6ACY8Afy1qXd//trMQ9enpMDKcv6h8gL468I89blr1+fehBSY8w9LsE51Icden3oTCvm5+ND1ObP3N/VTG2jIeucfFMDi3o5QYM4/KAAUGDBLfgwUQAEAoAAAUAAAKAAAFAAACgAABQCAAgBAAQCgAACoowCeX79WTdM075+7IuG65+1yhJJf/jH5wQQAwDILoNRdXKy7N/nld5lDhAkg10Wc6nnklx8ILID+XVTqi6t//Fh3b/LLD4yYAHJcxCkvXvnlBw4FXyRvL3c/5/7+6WE7ekRPefHKLz9wZQFcchHHulMstQnJLz8sgR8DBVio6L8U/pI7sJR3gPLLD5gAAFAAACgAABQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAksop5sBi/q/WS3wmbivzyyy//kvKvphK85BdCfvnll3+J+Vcxgz89bEcHf//cZftCyC+//PIvOf8qRvgYwc+9kBRfBPnll1/+pee/mWL44XFjj0jyyy+//PJfUQA5wqf8Isgvv/zyyz9iAsgRPmdDyi+//PIvMX9QAXQtkiv88EWMbWH55ZdffvkjTAAA1O3iAijVXrFaWH755Zdf/sP8JgAAEwAAS7JOcdDb7cfB4+/dY9T1qckvv/zyLyH/Terwpz537frcJ19++eWXf6751ynDbzb3vx+37f6omULX5z758ssvv/xzzn+TI3z3uL8mdH3Jky+//PLLP8f8vgkMsFAKAEABAKAArjD8hkPb7o8e99eErk9Nfvnll39p+dexX0T/Gw/9UH+FCV2f44sgv/zyy7+U/DcpXsQln7t2fe4mll9++eWfa/51rhcRc32JL4L88ssv/9zy+yYwwEIpAAAFAIACAEABAKAAAFAAACgAABQAAAoAAAUAgAIAoL4CeH79WjVN07x/7ooE7Z63yxFKfvnll1/+w/wmAAATwHRbbGz7yi+//PLLf5z/ZuxBc4Wv5bjyyy+//LXkDy6AfoukfhH9449tX/nll19++SNMADleRIqTL7/88ssv//9GvbC3l7ufc3//9LAdPaLEPvnyyy+//PJHKIBLXkSspiz1RZBffvnln2t+PwYKsFDrlAe/pIFSNqD88ssvv/yFCoDpyzHmgv9+FzgB+A8Q59/5Y7rn3/cAABZKAQAAAAAAAAAAAAAAAABM3CT+OWj/OzpARQWQ4l/RUwQAEy6A4cZ/yW+t+Zfhb7XJWQQmGEABBG6WMTb+c0WQelM1wQAKYCKbf64SmNsEA5C0AHJt/qlLYE4TDMBYQf8cdI7NP9Xz5Cix/nGn/KvmAC4qgG4jy7X5DzfTGBtpzglGCQCznABqV/MEA5C1AErd/cecAuYwwQCYAABQAFO++zcFADVYxzrQ7fbj4PH37jHqegAmOAEMN/NTn7t2PQATnACGG/dmc//7cdvuj+7sQ9fnYoIBTACRNv/ucX9N6PpSm78JBjABLMBcJhiArBPAnDf/miYYAAUAQJ4CGL7d0bb7o8f9NaHrAUhn9PcAvnePB2979Df1vzbz0PUATHAC+NdGH2t9KiYYwASQqARirk9ZAiYYwASwULVOMACTmADmWAI1TDAAJgAAFAAACgAABQCAAgBAAQAoAAAUAAAKAAAFAIACAEABAKAAAFAAACgAABQAAAoAgCkXwPPr16ppmub9c1ckXPe8XY5QtecHMAEAkL8ASt1Fx7p7rj0/wCQmgFybaKrnqT0/QPYC6N/Fpt7c+sePdfdce36AohNAjk005eZZe36A2II3qbeXu59L1j09bM9ukJdu1rHVnh+gWAGEbqTX3qWnVnt+gLGu/jHQlG/R5FB7foCx1jk32BR33fIDZJ4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJZgNfYAby93P2OP8fz6tfKlAKikAGJs/IoAoKICGG78Tw/b0SHeP3fFisAEAyiAwM0yxsZ/rghSb6omGEABTGTzz1UCc5tgAJIWQK7NP3UJzGmCARjrJmRxjs0/1fPkKLH+cVO8xQSQtQC6jSzX5j/cTGNspDknGCUAzHICqF3NEwxA1gIodfcfcwqYwwQDYAIAQAFM+e7fFADUYB3rQLfbj4PH37vHqOsBmOAEMNzMT33u2vUATHACGG7cm83978dtuz+6sw9dn4sJBjABRNr8u8f9NaHrS23+JhjABLAAc5lgALJOAHPe/GuaYAAUAAB5CmD4dkfb7o8e99eErgcgndHfA/jePR687dHf1P/azEPXAzDBCeBfG32s9amYYAATQKISiLk+ZQmYYAATwELVOsEATGICmGMJ1DDBAJgAAFAAACgAABQAAAoAAAUAoAAAUAAALLwAnl+/Vk3TNO+fuyLhuuftcoSqPT+ACQCA/AVQ6i461t1z7fkBJjEB5NpEUz1P7fkBshdA/y429ebWP36su+fa8wMUnQBybKIpN8/a8wPEdvEm9fZy93Pq754etlE2zXOb9li15weILcrvA6j9PW/v2QNL5MdAAUwA1xvzVse5t2ZyqT0/gAkAAAUAgAIAQAEA0PkPK875jF7ESN4AAAAASUVORK5CYII="

-- =====================================================================
-- Lifecycle
-- =====================================================================
on openCard
   -- Load the five Kenney atlases ONCE, not every level: persisted sheets
   -- survive b2kTeardown (like sounds), so a level rebuild reuses them
   -- instead of re-decoding/re-parsing/re-slicing. They also ride along in
   -- a SAVED stack, so a reopened stack skips the disk import entirely
   -- (Shift+Reset purges the cache to re-pick the art folder).
   b2kSheetPersist true
   if the uPfUIVersionTag of this stack is not kPfUIVersion then buildPfUI
   if gStarted is true then
      b2kStart                 -- a run already in progress (e.g. a reopened stack): resume it
   else
      put 1 into gLevel
      pfResetRun
      pfShowTitle              -- a fresh open boots to the title screen; SPACE starts level 1
   end if
   pass openCard
end openCard

on closeCard
   b2kStop
   pass closeCard
end closeCard

-- =====================================================================
-- Chrome (version-tagged; rebuilds when a newer example is pasted in)
-- =====================================================================
command buildPfUI
   local tC
   -- clear EVERY chrome control this handler creates before rebuilding, so a
   -- kPfUIVersion bump never leaves a duplicate behind (the splash/win/pause
   -- overlays were previously omitted here, which would have duplicated them).
   set the itemDelimiter to comma
   repeat for each item tC in "pfTitle,pfHelp,pfHud,pfSplash,pfWinText,pfPauseText,pfCardText"
      if there is a field tC then delete field tC
   end repeat
   repeat for each item tC in "pfWinShade,pfPauseShade,pfCardShade"
      if there is a graphic tC then delete graphic tC
   end repeat
   repeat for each item tC in "pfbtn_pause,pfbtn_reset,pfbtn_level,pfbtn_again"
      if there is a button tC then delete button tC
   end repeat
   set the width of this stack to 1024
   set the height of this stack to 640
   set the loc of this stack to the screenLoc
   try
      set the title of this stack to "Box2Dxt - Platformer Demo"
   catch tErr
   end try
   create field "pfTitle"
   set the rect of it to 20, 8, 838, 30
   set the lockText of it to true
   set the traversalOn of it to false
   set the textSize of it to 14
   set the text of it to "Box2Dxt platformer - a scrolling Game Kit showcase (input + sprites + player + camera + joints)"
   -- LEVEL PICKER (top-right): a DEV/TEST convenience - jump straight to any
   -- level instead of replaying the ones already approved (menuPick ->
   -- pfJumpToLevel). UPDATE this menu list when a level is added.
   create button "pfbtn_level"
   set the style of it to "menu"
   set the menuMode of it to "option"
   set the rect of it to 846, 6, 1004, 32
   set the traversalOn of it to false
   set the text of it to "1  Green Hills" & cr & "2  The Works" & cr & "3  Frozen Citadel" & cr & "4  Haunted Hollow" & cr & "5  Scorched Dunes" & cr & "6  Cavern Depths" & cr & "7  Stone Keep"
   set the menuHistory of it to 1
   create field "pfHelp"
   set the rect of it to 20, 34, 1004, 92
   set the lockText of it to true
   set the traversalOn of it to false
   set the textSize of it to 11
   create field "pfHud"
   set the rect of it to 20, 584, 760, 612
   set the lockText of it to true
   set the traversalOn of it to false
   set the textSize of it to 11
   create button "pfbtn_pause"
   set the rect of it to 800, 582, 884, 610
   set the label of it to "Pause"
   set the traversalOn of it to false
   create button "pfbtn_reset"
   set the rect of it to 900, 582, 984, 610
   set the label of it to "Reset"
   set the traversalOn of it to false
   -- intro splash (shown during the opening pan)
   create field "pfSplash"
   set the rect of it to 112, 220, 912, 330
   set the lockText of it to true
   set the traversalOn of it to false
   set the textAlign of it to "center"
   set the textSize of it to 26
   set the textStyle of it to "bold"
   set the opaque of it to false
   set the showBorder of it to false
   set the text of it to "B O X 2 D X T" & cr & "a physics platformer demo  -  arrows/WASD run, SPACE jumps"
   set the visible of it to false
   -- the win card (hidden until all coins + the flag): the final-run summary,
   -- composed in the level-card visual language - a centred panel, deeper and
   -- more opaque than before so the stats read as a finished payoff screen
   create graphic "pfWinShade"
   set the style of it to "roundrect"
   set the rect of it to 212, 116, 812, 512
   set the filled of it to true
   set the backgroundColor of it to "22,28,48"
   set the blendLevel of it to 10
   set the visible of it to false
   create field "pfWinText"
   set the rect of it to 236, 146, 788, 452
   set the lockText of it to true
   set the traversalOn of it to false
   set the textAlign of it to "center"
   set the textSize of it to 16
   set the textColor of it to "255,250,235"
   set the opaque of it to false
   set the showBorder of it to false
   set the visible of it to false
   create button "pfbtn_again"
   set the rect of it to 452, 468, 572, 500
   set the label of it to "Play again"
   set the traversalOn of it to false
   set the visible of it to false
   -- the PAUSE overlay (Phase F): the controls reference, now that the top help
   -- bar is retired. Shown by pfTogglePause on ESC / the pause button.
   create graphic "pfPauseShade"
   set the style of it to "roundrect"
   set the rect of it to 152, 150, 872, 500
   set the filled of it to true
   set the backgroundColor of it to "24,28,40"
   set the blendLevel of it to 16
   set the visible of it to false
   create field "pfPauseText"
   set the rect of it to 172, 176, 852, 484
   set the lockText of it to true
   set the traversalOn of it to false
   set the textAlign of it to "center"
   set the textSize of it to 17
   set the textColor of it to "248,249,240"
   set the opaque of it to false
   set the showBorder of it to false
   set the text of it to "P A U S E D" & cr & cr & "Arrows / A-D  -  run          SPACE  -  jump" & cr & "jump again in mid-air = DOUBLE  /  off a wall = WALL-JUMP" & cr & "SHIFT / X  -  dash          DOWN  -  duck (DOWN+JUMP drops through)" & cr & "UP / DOWN  -  climb ladders          MOUSE  -  drag the crate" & cr & "Pick your hero on the TITLE screen  (1 - 5 there)" & cr & cr & "ESC  resume       R  restart       M  mute       `  debug overlay"
   set the visible of it to false
   -- ===== the TRANSITION CARD: a full-screen opaque overlay that COVERS each
   -- level teardown + rebuild (no visible construction), and doubles as the boot
   -- title screen and the biome-tinted "LEVEL n" cards. Card-level chrome - NOT
   -- named pf_* (so pfWipeStage leaves it) and NOT in the camera group (so it
   -- never scrolls); raised above everything while covering, then faded out to
   -- reveal the positioned level. Built ONCE here; shown by pfCardShow, hidden by
   -- the pfCardReveal fade ramp. =====
   create graphic "pfCardShade"
   set the style of it to "rectangle"
   set the rect of it to 0, 0, 1024, 640
   set the filled of it to true
   set the backgroundColor of it to "26,30,44"
   set the blendLevel of it to 0
   set the visible of it to false
   create field "pfCardText"
   set the rect of it to 32, 40, 992, 600
   set the lockText of it to true
   set the traversalOn of it to false
   set the textAlign of it to "center"
   set the textSize of it to 22
   set the textStyle of it to "bold"
   set the textColor of it to "245,246,236"
   set the opaque of it to false
   set the showBorder of it to false
   set the visible of it to false
   set the uPfUIVersionTag of this stack to kPfUIVersion
end buildPfUI

-- =====================================================================
-- Transition card + boot title screen (the polish pass)
--
-- ONE full-screen opaque overlay (pfCardShade + pfCardText, built once in
-- buildPfUI) does three jobs: it COVERS every level teardown/rebuild so the
-- player never sees construction, it is the biome-tinted "LEVEL n" card held
-- briefly then faded out, and it is the boot TITLE screen (with a live hero
-- preview + the 1-5 chooser). The card is card-level chrome raised above the
-- camera viewport, exactly like the pause overlay, so it never scrolls.
-- =====================================================================

-- Zero the whole-run banks (everything the win screen sums). gLevel is set by
-- the caller. Centralised so a fresh run from anywhere - the title, Play again,
-- the dev picker - can never leave a stale coin-score / star bank behind (the
-- picker + Play again previously zeroed only some of them).
command pfResetRun
   put 0 into gTotalFalls
   put 0 into gSecsBank
   put 0 into gGemsBank
   put 0 into gGemsAllTotal
   put 0 into gScoreBank
   put 0 into gScoreAllTotal
   put 0 into gStarsBank
   put 0 into gStarsAllTotal
end pfResetRun

-- The biome NAME for a level, independent of the build (the card is composed
-- before the scene builder sets gLevelName).
function pfLevelTitle pN
   local tNm
   set the itemDelimiter to comma
   put item pN of "Green Hills,The Works,Frozen Citadel,Haunted Hollow,Scorched Dunes,Cavern Depths,Stone Keep" into tNm
   if tNm is empty then put "Level" into tNm
   return tNm
end pfLevelTitle

-- A one-line flavour per biome for the level card.
function pfLevelFlavour pN
   switch pN
      case 1
         return "Sun on the green hills - find your feet."
      case 2
         return "Gears, lifts and locked doors in the works."
      case 3
         return "Mind the ice in the frozen citadel."
      case 4
         return "Something stirs in the haunted hollow."
      case 5
         return "Heat shimmers over the scorched dunes."
      case 6
         return "Deep dark in the cavern depths."
      case 7
         return "Climb the stone keep to the very top."
      default
         return ""
   end switch
end pfLevelFlavour

-- The card tint per biome (deeper than the parallax backdrop so the card reads
-- as a composed panel). One line each - tune in OXT.
function pfLevelTint pN
   switch pN
      case 1
         return "120,186,104"
      case 2
         return "150,168,128"
      case 3
         return "176,206,232"
      case 4
         return "168,138,196"
      case 5
         return "226,196,138"
      case 6
         return "34,38,50"
      case 7
         return "48,52,66"
      default
         return "120,186,104"
   end switch
end pfLevelTint

-- The dark biomes (cavern, stone keep) need LIGHT card text; the bright ones
-- keep dark text. Mirrors the existing splash/notice rule, carried to the cards.
function pfLevelLight pN
   return (pN is 6 or pN is 7)
end pfLevelLight

-- A hero skin word ("green") as a display name ("Green").
function pfHeroName pSkin
   if pSkin is empty then return "Beige"
   return toUpper(char 1 of pSkin) & (char 2 to -1 of pSkin)
end pfHeroName

-- The composed text for a LEVEL card (shown in the upper band while that level
-- builds behind it; the illustrated cast row sits below it - see pfCardArtBuildLevel).
function pfLevelCardText
   local tMsg
   put "LEVEL  " & gLevel & "   of   7" & cr & cr & pfLevelTitle(gLevel) & cr & cr & pfLevelFlavour(gLevel) & cr & cr & "Collect every coin, then reach the flag" into tMsg
   return tMsg
end pfLevelCardText

-- The biome BACKDROP frame for a level's card (the same Kenney bg art the level
-- itself uses). L6/L7 build their backdrops procedurally - no frame - so the
-- card falls back to its solid biome tint there.
function pfLevelBgFrame pN
   switch pN
      case 1
      case 2
         return "background_color_hills"
      case 3
         return "background_fade_hills"
      case 4
         return "background_color_mushrooms"
      case 5
         return "background_color_desert"
      default
         return ""
   end switch
end pfLevelBgFrame

-- A representative FOE frame per biome for the card's cast row (all on the
-- always-loaded "foes" sheet - no optional-sheet dependency). A missing frame
-- just drops that one cast slot (pfCardCastMember no-ops).
function pfLevelFoeFrame pN
   switch pN
      case 2
         return "bee_a"
      case 3
         return "snail_walk_a"
      case 5
         return "ladybug_walk_a"
      case 6
         return "mouse_walk_a"
      case 7
         return "saw_a"
      default
         return "slime_normal_walk_a"
   end switch
end pfLevelFoeFrame

-- Darken an "r,g,b" toward black by pFactor (0..1) - for the card's ground band.
function pfShade pRGB, pFactor
   local tR, tG, tB
   set the itemDelimiter to comma
   put round((item 1 of pRGB) * pFactor) into tR
   put round((item 2 of pRGB) * pFactor) into tG
   put round((item 3 of pRGB) * pFactor) into tB
   return tR & comma & tG & comma & tB
end pfShade

-- The composed text for the boot TITLE card. The hero chooser highlights the
-- current pick; the live hero sprite (pfTitleHero) floats over the blank band
-- between the title and the chooser.
function pfTitleCardText
   local tMsg, tWord, tNames, tOne
   set the itemDelimiter to comma
   put empty into tNames
   repeat for each item tWord in "beige,green,pink,purple,yellow"
      put pfHeroName(tWord) into tOne
      if tWord is gHeroSkin then put "[" & toUpper(tOne) & "]" into tOne
      if tNames is empty then
         put tOne into tNames
      else
         put tNames & "     " & tOne into tNames
      end if
   end repeat
   put "B O X 2 D X T" & cr & "a Box2D physics platformer demo" & cr & cr & cr & cr & cr & cr & cr & "Choose your hero    ( 1 - 5 )" & cr & tNames & cr & cr & cr & "Press   SPACE   to start" & cr & cr & "Arrows / WASD  move      ESC  controls      M  mute" into tMsg
   return tMsg
end pfTitleCardText

-- ===== ILLUSTRATED-CARD ART (the per-level scene behind the title text) =====
-- The biome backdrop, a dimming scrim, a ground band, and a CAST ROW of real
-- game sprites (hero + a biome foe + a coin + the goal flag). All card-level
-- controls named pfCard* (so pfWipeStage leaves them) and tracked in gCardArt so
-- they fade/raise/hide as a set. EVERY piece is optional - on a missing sheet or
-- a failed slice it is simply skipped, and the always-present opaque pfCardShade
-- tint base guarantees the cover still hides the build. =====

-- Remember an art control so the fade/raise/hide handlers see it.
command pfCardAddArt pCtrl
   if pCtrl is empty then exit pfCardAddArt
   put pCtrl & cr after gCardArt
end pfCardAddArt

-- Drop every per-level art control and reset the list. Called before each cover,
-- and at the title. Deletes BY NAME (a proper type-checked existence test); the
-- names are fixed, so this clears every art control whether or not gCardArt is in
-- sync, and avoids referencing a possibly-stale long id.
command pfCardArtClear
   local tC
   set the itemDelimiter to comma
   repeat for each item tC in "pfCardBgA,pfCardBgB,pfCardScrim,pfCardGround,pfCardCastHero,pfCardCastFoe,pfCardCastCoin,pfCardCastFlag"
      if there is an image tC then delete image tC
      if there is a graphic tC then delete graphic tC
   end repeat
   put empty into gCardArt
end pfCardArtClear

-- Clone a sliced atlas frame onto the CARD as a plain (camera-free) image named
-- pName, hidden and at native sliced size. Uses the proven throwaway-sprite path
-- (pfTextureSlab): the sprite carries the frame as its icon, which we clone. The
-- throwaway is created in whatever camera group is live, then removed; the clone
-- is a card control. Returns pName, or empty on any failure.
function pfCardArtImage pSheet, pFrame, pName
   local tSpr, tImg
   if gAssetsOK is not true then return empty
   if not b2kSheetHasFrame(pSheet, pFrame) then return empty
   b2kSpriteNew pSheet, pFrame, -4000, -4000
   put the result into tSpr
   if tSpr is empty then return empty
   put the icon of tSpr into tImg
   if tImg is empty or there is no image id tImg then
      b2kSpriteRemove tSpr
      return empty
   end if
   if there is an image pName then delete image pName
   clone image id tImg
   set the name of the last image to pName
   set the visible of the last image to false
   -- NB: lockLoc is set by the CALLER, AFTER it sets the rect - an image only
   -- scales its content to a custom rect when the rect is set while lockLoc is
   -- still false, then locked (the order pfTextureSlab uses). Locking first here
   -- left the backdrop stuck at its natural ~640px instead of filling the card.
   b2kSpriteRemove tSpr
   return pName
end pfCardArtImage

-- One cast-row figure: clone pFrame, scale the clone to target height pH (aspect
-- kept), stand it centred at x pCX with its feet on pFeetY, and track it. No
-- b2kSheetScale juggling - the clone is resized directly, so the game's sheet
-- scales are never touched.
command pfCardCastMember pSheet, pFrame, pName, pCX, pFeetY, pH
   local tNW, tNH, tW
   if pfCardArtImage(pSheet, pFrame, pName) is empty then exit pfCardCastMember
   put the width of image pName into tNW
   put the height of image pName into tNH
   if tNH < 1 then
      delete image pName
      exit pfCardCastMember
   end if
   put max(1, round(tNW * pH / tNH)) into tW
   set the rect of image pName to pCX - (tW div 2), pFeetY - pH, pCX + (tW div 2), pFeetY
   set the lockLoc of image pName to true   -- freeze the scaled size (rect set first, see pfCardArtImage)
   set the uCardBaseBlend of image pName to 0
   pfCardAddArt the long id of image pName
end pfCardCastMember

-- Build the illustrated scene for gLevel into gCardArt (hidden; pfCardShow shows
-- it under the cover lock). The uCardBaseBlend property holds each layer's RESTING
-- blendLevel so the fade ramp can add progress on top without flattening the
-- scrim/ground translucency.
command pfCardArtBuildLevel
   local tBg, tGY, tBW, tBH, tBgH, tBgTop
   if gAssetsOK is not true then exit pfCardArtBuildLevel   -- placeholder mode: tint card only
   put 480 into tGY                                         -- the ground line the cast stands on
   -- the biome backdrop (L1-L5): ONE panel scaled to COVER the 1024 card width with
   -- its aspect KEPT (the overflow below the 640 card height is simply cropped by
   -- the window). A single image has no join, so there is no seam to misalign - the
   -- earlier two-panel stretch mismatched in its overlap. The card's ground band
   -- hides the cropped-off foreground.
   put pfLevelBgFrame(gLevel) into tBg
   if tBg is not empty and b2kSheetHasFrame("bg", tBg) then
      if pfCardArtImage("bg", tBg, "pfCardBgA") is not empty then
         put the width of image "pfCardBgA" into tBW    -- natural sliced size (~640x640 at bg scale 2.5)
         put the height of image "pfCardBgA" into tBH
         if tBW < 1 then put 640 into tBW
         if tBH < 1 then put 640 into tBH
         put max(640, round(1024 * tBH / tBW)) into tBgH   -- aspect-scaled to fill the 1024 width (>= card height)
         put (640 - tBgH) div 2 into tBgTop                -- centre the vertical crop (show the focal middle, not just the sky)
         set the rect of image "pfCardBgA" to 0, tBgTop, 1024, tBgTop + tBgH
         set the lockLoc of image "pfCardBgA" to true      -- freeze the scaled size (rect set first, see pfCardArtImage)
         set the uCardBaseBlend of image "pfCardBgA" to 0
         pfCardAddArt the long id of image "pfCardBgA"
         -- a dark scrim so the title text reads over the busy backdrop (rests at 42)
         create graphic "pfCardScrim"
         set the style of graphic "pfCardScrim" to "rectangle"
         set the rect of graphic "pfCardScrim" to 0, 0, 1024, 640
         set the filled of graphic "pfCardScrim" to true
         set the backgroundColor of graphic "pfCardScrim" to "14,16,26"
         set the blendLevel of graphic "pfCardScrim" to 42
         set the uCardBaseBlend of graphic "pfCardScrim" to 42
         set the visible of graphic "pfCardScrim" to false   -- hidden until pfCardShow reveals the whole cover at once
         pfCardAddArt the long id of graphic "pfCardScrim"
      end if
   end if
   -- a ground band the cast stands on (a darker shade of the biome tint)
   create graphic "pfCardGround"
   set the style of graphic "pfCardGround" to "rectangle"
   set the rect of graphic "pfCardGround" to 0, tGY, 1024, 640
   set the filled of graphic "pfCardGround" to true
   set the backgroundColor of graphic "pfCardGround" to pfShade(pfLevelTint(gLevel), 0.45)
   set the blendLevel of graphic "pfCardGround" to 6
   set the uCardBaseBlend of graphic "pfCardGround" to 6
   set the visible of graphic "pfCardGround" to false   -- hidden until pfCardShow reveals the whole cover at once
   pfCardAddArt the long id of graphic "pfCardGround"
   -- THE CAST: real game art previewing this world (each figure optional)
   pfCardCastMember "chars", ("character_" & gHeroSkin & "_idle"), "pfCardCastHero", 336, tGY + 8, 96
   pfCardCastMember "foes", pfLevelFoeFrame(gLevel), "pfCardCastFoe", 492, tGY + 8, 64
   pfCardCastMember "tiles", "coin_gold", "pfCardCastCoin", 606, tGY + 4, 40
   pfCardCastMember "tiles", "flag_yellow_a", "pfCardCastFlag", 706, tGY + 8, 96
end pfCardArtBuildLevel

-- Raise the whole card stack to the very top, in z-order: tint base, then the
-- art (in build order: backdrop, scrim, ground, cast), then the title text on
-- top. Each "set the layer ... to tTop" lands at the top, pushing the previous
-- one down, so the LAST raised (the text) ends up frontmost.
command pfCardRaise
   local tTop, tC
   put the number of controls of this card into tTop
   if there is a graphic "pfCardShade" then set the layer of graphic "pfCardShade" to tTop
   repeat for each line tC in gCardArt
      if tC is not empty then set the layer of tC to tTop
   end repeat
   if there is a field "pfCardText" then set the layer of field "pfCardText" to tTop
end pfCardRaise

-- COVER the screen with the card NOW: compose its colour + text, raise the whole
-- stack above every other control, make it opaque, and force ONE repaint so it is
-- on screen BEFORE the teardown/build that follows paints underneath it. pLight
-- true = light text (for the dark tints).
command pfCardShow pText, pTint, pLight
   local tC
   add 1 to gCardGen                       -- invalidate any in-flight fade ramp
   if there is no graphic "pfCardShade" then exit pfCardShow
   set the backgroundColor of graphic "pfCardShade" to pTint
   set the blendLevel of graphic "pfCardShade" to 0
   if there is a field "pfCardText" then
      set the text of field "pfCardText" to pText
      set the blendLevel of field "pfCardText" to 0
      if pLight is true then
         set the textColor of field "pfCardText" to "245,246,236"
      else
         set the textColor of field "pfCardText" to "28,30,42"
      end if
   end if
   pfCardRaise
   lock screen
   set the visible of graphic "pfCardShade" to true
   repeat for each line tC in gCardArt
      if tC is not empty then set the visible of tC to true
   end repeat
   if there is a field "pfCardText" then set the visible of field "pfCardText" to true
   unlock screen                           -- flush: the cover is on screen now
end pfCardShow

-- Cover for the CURRENT level (called at the very top of pfStartGame, before the
-- teardown): build the illustrated biome scene, then cover with it. The title
-- text sits in the upper band, the cast row below it.
command pfCardCover
   pfCardArtClear
   pfCardArtBuildLevel
   if there is a field "pfCardText" then set the rect of field "pfCardText" to 40, 70, 984, 410
   pfCardShow pfLevelCardText(), pfLevelTint(gLevel), pfLevelLight(gLevel)
end pfCardCover

-- REVEAL the built level: hold the opaque card briefly (a "ready" beat), then
-- fade it out. Decoupled from the frame loop via a self-send so it cannot trip
-- the frame-loop intro code (which a past pan rework broke - gotcha 11).
command pfCardReveal
   add 1 to gCardGen
   put 0 into gCardFade
   send ("pfCardFadeStep" && gCardGen) to me in 620 milliseconds
end pfCardReveal

-- One step of the fade-out ramp (0 = opaque ... 100 = clear), across the tint
-- base, the title text, and every illustrated-art layer. Each layer fades from
-- its RESTING blend (uCardBaseBlend: 0 for opaque pieces, 42/6 for scrim/ground) up to
-- 100, so the scrim's dimming holds through the fade instead of flashing opaque.
-- pGen guards against a stale ramp left when a newer cover superseded this one.
command pfCardFadeStep pGen
   local tC
   if pGen is not gCardGen then exit pfCardFadeStep
   if there is no graphic "pfCardShade" then exit pfCardFadeStep
   add 12 to gCardFade
   if gCardFade >= 100 then
      set the visible of graphic "pfCardShade" to false
      if there is a field "pfCardText" then set the visible of field "pfCardText" to false
      repeat for each line tC in gCardArt
         if tC is not empty then set the visible of tC to false
      end repeat
      set the blendLevel of graphic "pfCardShade" to 0   -- reset for the next cover
      exit pfCardFadeStep
   end if
   set the blendLevel of graphic "pfCardShade" to gCardFade
   if there is a field "pfCardText" then set the blendLevel of field "pfCardText" to gCardFade
   repeat for each line tC in gCardArt
      if tC is not empty then set the blendLevel of tC to min(100, (the uCardBaseBlend of tC) + gCardFade)
   end repeat
   send ("pfCardFadeStep" && gCardGen) to me in 45 milliseconds
end pfCardFadeStep

-- The boot TITLE screen: load the art once (so the hero preview can show),
-- compose the title card, cover with it (held until SPACE), and place the live
-- hero preview on top. Re-callable (a hero pick recomposes it).
command pfShowTitle
   put true into gAtTitle
   put false into gStarted
   b2kStop                                  -- no game loop while the title is up
   if there is no graphic "pfCardShade" then buildPfUI
   if gHeroSkin is empty then put "beige" into gHeroSkin
   -- load the atlases ONCE (prompts for the folder the first time, then cached +
   -- persisted into the game); skip the reload once the chars sheet is present
   if not b2kSheetHasFrame("chars", "character_beige_idle") then put pfLoadSheets() into gAssetsOK
   pfCardArtClear                           -- the title has no level scene (just the hero preview)
   if there is a field "pfCardText" then set the rect of field "pfCardText" to 32, 40, 992, 600
   pfCardShow pfTitleCardText(), "26,30,44", true
   pfTitleHero                              -- the live hero preview, above the card
end pfShowTitle

-- The title's live hero preview: a single idle frame of the chosen skin, floating
-- over the card. A Kit sprite created with the camera OFF is a plain card control
-- (screen-fixed); b2kTeardown sweeps it when the level builds. Degrades silently
-- to text-only when the art is missing.
command pfTitleHero
   local tFrame
   if gTitleHeroSpr is not empty then
      b2kSpriteRemove gTitleHeroSpr
      put empty into gTitleHeroSpr
   end if
   if gAssetsOK is not true then exit pfTitleHero
   put "character_" & gHeroSkin & "_idle" into tFrame
   if not b2kSheetHasFrame("chars", tFrame) then exit pfTitleHero
   b2kSheetScale "chars", 0.9               -- pfStartGame resets this to 0.75 for play
   b2kSpriteNew "chars", tFrame, 512, 214
   put the result into gTitleHeroSpr
   if gTitleHeroSpr is empty then exit pfTitleHero
   lock screen
   set the layer of gTitleHeroSpr to the number of controls of this card
   unlock screen
end pfTitleHero

-- 1-5 at the title: re-skin and recompose the title (no level to rebuild yet).
command pfTitlePickHero pN
   local tSkin
   set the itemDelimiter to comma
   put item pN of "beige,green,pink,purple,yellow" into tSkin
   if tSkin is empty or tSkin is gHeroSkin then exit pfTitlePickHero
   put tSkin into gHeroSkin
   pfShowTitle                              -- recompose with the new hero highlighted
end pfTitlePickHero

-- SPACE at the title: drop the preview, start a fresh run at level 1. The card
-- stays covering (pfStartGame recomposes it to the LEVEL 1 card, then fades).
command pfStartFromTitle
   put false into gAtTitle
   if gTitleHeroSpr is not empty then
      b2kSpriteRemove gTitleHeroSpr
      put empty into gTitleHeroSpr
   end if
   put 1 into gLevel
   pfResetRun
   put true into gStarted
   pfStartGame
end pfStartFromTitle

-- =====================================================================
-- Assets: the Kenney atlases, or the embedded placeholder when missing
-- =====================================================================
function pfLoadSheets
   local tFolder, tN, tHero
   put empty into gLoadNote
   put the uSpriteSheetFolderPath of this stack into tFolder
   if tFolder is empty or there is no file (tFolder & "/spritesheet-characters-default.png") then
      answer folder "Locate the repo's Spritesheets folder (Cancel = built-in placeholder art):"
      put it into tFolder
      if tFolder is empty or the result is "cancel" then
         put "no folder chosen" into gLoadNote
         return false
      end if
      if there is no file (tFolder & "/spritesheet-characters-default.png") then
         put "spritesheet-characters-default.png is not inside: " & tFolder into gLoadNote
         return false
      end if
      set the uSpriteSheetFolderPath of this stack to tFolder
   end if
   b2kSheetLoadAtlas "chars", tFolder & "/spritesheet-characters-default.png"
   put the result into tN
   if tN < 1 then
      put "characters atlas gave 0 frames (png or xml unreadable) in: " & tFolder into gLoadNote
      return false
   end if
   b2kSheetLoadAtlas "foes", tFolder & "/spritesheet-enemies-default.png"
   put the result into tN
   if tN < 1 then put "enemies atlas gave 0 frames. " after gLoadNote
   b2kSheetLoadAtlas "tiles", tFolder & "/spritesheet-tiles-default.png"
   put the result into tN
   if tN < 1 then put "tiles atlas gave 0 frames. " after gLoadNote
   -- Phase F: a SECOND view of the tiles atlas as "hud", scaled down for the
   -- screen-chrome hud_* sprites (the 64px hud_ cells -> ~38px HUD elements). The
   -- atlas decodes once (sheets persist across rebuilds); only the hud_* frames
   -- the HUD actually uses ever get sliced, so the extra cost is negligible.
   b2kSheetLoadAtlas "hud", tFolder & "/spritesheet-tiles-default.png"
   if the result >= 1 then b2kSheetScale "hud", 0.6
   b2kSheetLoadAtlas "bg", tFolder & "/spritesheet-backgrounds-default.png"
   put the result into tN
   if tN < 1 then put "backgrounds atlas gave 0 frames. " after gLoadNote
   b2kSheetScale "bg", 2.5   -- 256px panels -> 640px (full card height)
   -- Wave 3: the SPOOKS (ghost/bat/piranha/grassBlock) live on the
   -- Family C enemies.png - a ~70px-grid sheet in a 64px-grid level,
   -- normalised per the mixed-grids law (frame names keep their .png
   -- suffix on this sheet). Optional: missing = those makers skip.
   b2kSheetLoadAtlas "spooks", tFolder & "/enemies.png"
   put the result into tN
   if tN >= 1 then
      b2kSheetScale "spooks", 0.9
      b2kAnimDef "spooks", "batfly", "bat_fly.png,bat.png", 8, true
      b2kAnimDef "spooks", "spiderwalk", "spider_walk1.png,spider_walk2.png", 8, true   -- Wave 6
      b2kAnimDef "spooks", "spin", "spinner.png,spinner_spin.png", 12, true             -- Phase C: the keep's blade
      b2kAnimDef "spooks", "spinhalf", "spinnerHalf.png,spinnerHalf_spin.png", 12, true -- wall-mounted half-blade
      b2kAnimDef "spooks", "slimegreen", "slimeGreen.png,slimeGreen_walk.png", 4, true  -- Phase D: a GREEN slime skin
      b2kAnimDef "spooks", "slimeblue", "slimeBlue.png,slimeBlue_blue.png", 4, true     -- ...and a BLUE one
      b2kAnimDef "spooks", "snakewalk", "snake.png,snake_walk.png", 5, true             -- Phase E: the SLITHER crawl
      b2kAnimDef "spooks", "snakelava", "snakeLava.png,snakeLava_ani.png", 5, true
      b2kAnimDef "spooks", "snakeslime", "snakeSlime.png,snakeSlime_ani.png", 5, true
   end if
   -- the HERO (Phase G: gHeroSkin picks the colour word - beige/green/pink/purple/
   -- yellow - so the whole character re-skins on a rebuild). tHero = the frame
   -- prefix; the numeric placeholder defs below (no atlas) stay skin-agnostic.
   if gHeroSkin is empty then put "beige" into gHeroSkin
   put "character_" & gHeroSkin & "_" into tHero
   b2kAnimDef "chars", "idle", (tHero & "idle"), 2, true
   b2kAnimDef "chars", "walk", (tHero & "walk_a," & tHero & "walk_b"), 6, true
   b2kAnimDef "chars", "jump", (tHero & "jump"), 1, true
   b2kAnimDef "chars", "hit", (tHero & "hit"), 2, false
   -- Wave 2 poses: the default characters sheet HAS duck and climb
   -- frames for the hero (the design doc guessed it did not).
   -- "hurtpose" LOOPS on purpose: the Kit's knockback drives it, and a
   -- non-looping anim would fire b2kSpriteOnFinish -> pfHurtDone (the
   -- RESPAWN) mid-knockback. The respawn path keeps the one-shot "hit".
   b2kAnimDef "chars", "duck", (tHero & "duck"), 1, true
   b2kAnimDef "chars", "climb", (tHero & "climb_a," & tHero & "climb_b"), 6, true
   b2kAnimDef "chars", "hurtpose", (tHero & "hit"), 2, true
   b2kAnimDef "foes", "buzz", "bee_a,bee_b", 8, true
   b2kAnimDef "foes", "sawspin", "saw_a,saw_b", 10, true
   b2kAnimDef "foes", "slimewalk", "slime_normal_walk_a,slime_normal_walk_b", 4, true
   b2kAnimDef "foes", "spikewalk", "slime_spike_walk_a,slime_spike_walk_b", 4, true
   b2kAnimDef "foes", "blockidle", "slime_block_walk_a,slime_block_walk_b", 4, true   -- the block slime's settled squish between hops (Phase B)
   b2kAnimDef "foes", "snailwalk", "snail_walk_a,snail_walk_b", 4, true
   -- the showcase round's new walker species (all native 64px foes art,
   -- so no sheet/scale juggling; they ride the slime FAMILY as new kinds)
   b2kAnimDef "foes", "mousewalk", "mouse_walk_a,mouse_walk_b", 9, true
   b2kAnimDef "foes", "wormwalk", "worm_normal_move_a,worm_normal_move_b", 4, true
   b2kAnimDef "foes", "wormring", "worm_ring_move_a,worm_ring_move_b", 4, true   -- Phase D: a second worm skin
   b2kAnimDef "foes", "ladywalk", "ladybug_walk_a,ladybug_walk_b", 7, true
   b2kAnimDef "foes", "firewalk", "slime_fire_walk_a,slime_fire_walk_b", 5, true
   -- aquatic foes for the swim pools (native 64px foes art, previously unused)
   b2kAnimDef "foes", "fishblue", "fish_blue_swim_a,fish_blue_swim_b", 6, true
   b2kAnimDef "foes", "fishyellow", "fish_yellow_swim_a,fish_yellow_swim_b", 6, true
   b2kAnimDef "foes", "ladyflit", "ladybug_fly,ladybug_walk_a", 10, true
   b2kAnimDef "tiles", "spin", "coin_gold,coin_gold_side", 4, true
   b2kAnimDef "tiles", "spinsilver", "coin_silver,coin_silver_side", 4, true   -- Phase F coin tiers
   b2kAnimDef "tiles", "spinbronze", "coin_bronze,coin_bronze_side", 4, true
   b2kAnimDef "tiles", "starspin", "star", 1, true                             -- the hidden star (single frame)
   b2kAnimDef "tiles", "wave", "flag_blue_a,flag_blue_b", 4, true
   b2kAnimDef "tiles", "wavegold", "flag_yellow_a,flag_yellow_b", 4, true
   b2kAnimDef "tiles", "coinpop", "coin_gold_side,coin_gold,coin_gold_side", 14, false
   b2kAnimDef "tiles", "coinpopsilver", "coin_silver_side,coin_silver,coin_silver_side", 14, false   -- tier-matched pickup pops
   b2kAnimDef "tiles", "coinpopbronze", "coin_bronze_side,coin_bronze,coin_bronze_side", 14, false
   b2kAnimDef "tiles", "checkwave", "flag_red_a,flag_red_b", 4, true
   b2kAnimDef "tiles", "torch", "torch_on_a,torch_on_b", 5, true   -- flickering wall torch (cavern ambiance, L6)
   b2kAnimDef "foes", "flit", "fly_a,fly_b", 10, true
   b2kAnimDef "chars", "win", (tHero & "duck," & tHero & "idle"), 3, true
   return true
end pfLoadSheets

-- Every sound is SYNTHESIZED (b2kToneMake): zero asset files. Sounds
-- survive b2kTeardown (Kit policy), so after the first build a reset
-- skips the synthesis entirely. Short and plucky on purpose - the
-- engine plays one clip at a time, so a new cue cuts the previous.
command pfMakeSounds
   -- guard on the NEWEST cue, so a stack upgraded in place re-synthesizes
   if b2kSoundIsLoaded("gem") then exit pfMakeSounds   -- already built
   b2kToneMake "jump", "392,587", 40, 55
   b2kToneMake "coin", "1319,1760", 36, 45
   b2kToneMake "stomp", "165,110", 40, 70
   b2kToneMake "hurt", "220,156,110", 55, 65
   b2kToneMake "land", "98", 26, 40, "sine"
   b2kToneMake "check", "659,880", 50, 50, "sine"
   b2kToneMake "gate", "294,392", 40, 35, "sine"
   b2kToneMake "win", "523,659,784,1047", 110, 65
   -- Wave 1 cues
   b2kToneMake "spring", "262,392,587", 36, 55
   b2kToneMake "smash", "147,98,73", 40, 65
   b2kToneMake "key", "988,1319", 45, 45, "sine"
   b2kToneMake "unlock", "392,523,659", 55, 50, "sine"
   b2kToneMake "lever", "294,220", 30, 45
   b2kToneMake "deny", "196,147", 60, 55
   -- Wave 3 cue: the shell kick
   b2kToneMake "kick", "330,494", 32, 60
   -- the showcase round's mechanism cues
   b2kToneMake "creak", "175,147", 34, 35, "sine"   -- a foot on the bridge
   b2kToneMake "rumble", "73,87,65", 60, 55, "sine"  -- the boulder lets go
   b2kToneMake "boom", "131,98,73,55", 80, 70          -- the barrel blast
   -- Wave 6 cue: the barnacle's snap
   b2kToneMake "bite", "147,98", 28, 60
   -- Wave 8 cue: the gem pickup (a sparkly ascending chime - the NEWEST cue, the guard keys on it)
   b2kToneMake "gem", "1047,1568,2093", 70, 50, "sine"
end pfMakeSounds

command pfEmbedPlaceholder
   if there is no image "pf_sheetsrc" then
      create image "pf_sheetsrc"
      set the visible of it to false
      set the text of image "pf_sheetsrc" to base64Decode(kHeroSheetB64)
      set the lockLoc of it to true   -- AFTER the content, so it auto-sized
   end if
   b2kSheetFromImage "chars", the long id of image "pf_sheetsrc", 48, 64
   b2kAnimDef "chars", "idle", "1-4", 4, true
   b2kAnimDef "chars", "walk", "9-16", 10, true
   b2kAnimDef "chars", "jump", "17", 1, true
   b2kAnimDef "chars", "hit", "19", 2, false
   b2kAnimDef "chars", "hurtpose", "19", 2, true   -- looping twin (knockback)
   b2kAnimDef "chars", "win", "1-4", 6, true
end pfEmbedPlaceholder

-- =====================================================================
-- Wave 8: the PARALLAX backdrop (per-biome scene, drifting for depth)
-- =====================================================================
-- Pick a biome scene for the level and tile it across 3 card panels that
-- pfTickParallax drifts + wraps. All bg scenes are OPAQUE, so this is a single
-- drifting layer (a fade layer behind would be hidden); the depth comes from
-- the slower-than-foreground drift. No art = no backdrop (the card shows), as
-- before. Built before b2kCamOn so the panels stay on the card, not in the
-- scrolling camera group.
command pfBuildBackdrop
   local tFrame, i, tRef
   put empty into gBgPanel
   put 0 into gBgLastHS
   if gLevel is 6 then
      pfBuildCaveBackdrop   -- the cavern gets a built dark backdrop, not a flat "solid_" frame
      exit pfBuildBackdrop
   end if
   if gLevel is 7 then
      pfBuildStoneBackdrop   -- the stone keep, like the cavern, has no outdoor scene
      exit pfBuildBackdrop
   end if
   switch gLevel
      case 3
         put "background_fade_hills" into tFrame      -- pale + cold for the frozen citadel
         break
      case 4
         put "background_color_mushrooms" into tFrame  -- purple/spooky for the haunted hollow
         break
      case 5
         put "background_color_desert" into tFrame    -- the scorched dunes
         break
      default
         put "background_color_hills" into tFrame     -- green hills / the works
   end switch
   if gAssetsOK is not true or not b2kSheetHasFrame("bg", tFrame) then exit pfBuildBackdrop
   repeat with i = 1 to 3
      b2kSpriteNew "bg", tFrame, (i - 1) * 640 + 320, 320
      put the result into tRef
      if tRef is empty then next repeat
      set the layer of tRef to i
      -- OVERLAP the 640px panels by ~2px each side. Adjacent panels meet
      -- EXACTLY at the 640 boundary, so sub-pixel rounding leaves a 1px gap and
      -- the card's white shows through as a hairline seam. A 4px-wider panel,
      -- recentred, always overlaps its neighbour (opaque over opaque, no seam);
      -- the spacing and the 640 wrap modulus are unchanged, so the wrap stays
      -- seamless. (Panels are 256px bg frames at b2kSheetScale 2.5 = 640px.)
      set the width of tRef to (the width of tRef) + 4
      set the loc of tRef to ((i - 1) * 640 + 320) & ",320"
      put tRef into gBgPanel[i]
   end repeat
end pfBuildBackdrop

-- Phase F: build the ART HUD - screen-fixed hud_* sprites that replace the bottom
-- text readout. Created HERE (before b2kCamOn, like the backdrop) so they live on
-- the CARD and never scroll. Rebuilt each level (b2kTeardown cleared the old Kit
-- sprites). When the hud_* art is missing it no-ops and gHudOK stays false, so the
-- text field readout remains the fallback (the demo never ships blank). Increment
-- 1: just the coin counter (an icon + two collected-count digits, top-left), to
-- prove the card-fixed sprite + digit path on OXT before the rest is layered on.
command pfBuildHud
   local tK, tI
   put false into gHudOK
   put empty into gHudCoinLast
   put empty into gHudTotLast
   put empty into gHudKeysLast
   put empty into gHudGemLast
   put empty into gHudGemTotLast
   put empty into gHudHeartLast
   put empty into gHudStarLast
   put empty into gHudPortrait   -- Phase G avatar; teardown cleared last build's sprite
   if gAssetsOK is not true or not b2kSheetHasFrame("hud", "hud_coin") then exit pfBuildHud
   b2kSpriteNew "hud", "hud_coin", 40, 20
   put the result into gHudCoinIcon
   if gHudCoinIcon is empty then exit pfBuildHud
   put pfHudDigit(74, 20) into gHudCoinD[1]
   put pfHudDigit(98, 20) into gHudCoinD[2]
   -- the "/" between the collected count and the total (the hud_character_* set
   -- has no slash glyph, so draw a tiny card line; pfWipeStage clears it each build)
   create graphic "pf_hudslash"
   set the style of graphic "pf_hudslash" to "line"
   set the points of graphic "pf_hudslash" to "112,31" & cr & "120,9"
   set the lineSize of graphic "pf_hudslash" to 2
   set the foregroundColor of graphic "pf_hudslash" to "215,215,215"
   put pfHudDigit(134, 20) into gHudCoinTot[1]
   put pfHudDigit(158, 20) into gHudCoinTot[2]
   -- the KEY icons (one slot per colour): created hidden, then shown + packed
   -- left-aligned by pfUpdateHud as the hero collects them - and hidden again the
   -- moment a door consumes one. This replaced the ride-along key-on-shoulder sprite.
   set the itemDelimiter to comma
   repeat for each item tK in "blue,green,red,yellow"
      if b2kSheetHasFrame("hud", "hud_key_" & tK) then
         b2kSpriteNew "hud", "hud_key_" & tK, 200, 20
         put the result into gHudKey[tK]
         if gHudKey[tK] is not empty then set the visible of gHudKey[tK] to false
      end if
   end repeat
   -- the GEM counter (a bonus tally): an icon + collected-count digits, created
   -- hidden and revealed by pfUpdateHud only on levels that actually have gems.
   if b2kSheetHasFrame("hud", "gem_blue") then
      b2kSpriteNew "hud", "gem_blue", 205, 20
      put the result into gHudGemIcon
      if gHudGemIcon is not empty then set the visible of gHudGemIcon to false
      put pfHudDigit(239, 20) into gHudGemD[1]
      put pfHudDigit(263, 20) into gHudGemD[2]
      if gHudGemD[1] is not empty then set the visible of gHudGemD[1] to false
      if gHudGemD[2] is not empty then set the visible of gHudGemD[2] to false
   end if
   -- Phase G: the HERO PORTRAIT (avatar) anchors the bottom-left status corner -
   -- the chosen skin's hud_player_<skin> face, with the heart row to its right.
   -- Rebuilt each level, so it always shows the current gHeroSkin (chosen at the title).
   if b2kSheetHasFrame("hud", "hud_player_" & gHeroSkin) then
      b2kSpriteNew "hud", "hud_player_" & gHeroSkin, 44, 620
      put the result into gHudPortrait
   end if
   -- the HEARTS (health): five hud_heart icons in the DIRT band at the very
   -- bottom-left, BELOW the grass line (per the OXT pass - at y560 they sat up in
   -- the play area among the world props; y620 drops them into the dirt strip,
   -- clear of the scene). They build FULL; pfUpdateHearts swaps a slot to
   -- hud_heart_empty as contact damage drains the buffer, and a respawn refills
   -- it. Like the coin/gem digits these are card sprites (built before b2kCamOn)
   -- so they never scroll; pfChromeFront raises them above the viewport. Shifted
   -- right of the portrait (Phase G).
   if b2kSheetHasFrame("hud", "hud_heart") then
      repeat with tI = 1 to kHearts
         b2kSpriteNew "hud", "hud_heart", 96 + (tI - 1) * 36, 620
         put the result into gHudHeart[tI]
      end repeat
   end if
   -- the hidden STAR slot (top-right, just left of the level picker): built DIM,
   -- lit BRIGHT the instant the level's star is collected (the pickup + pfUpdateHud).
   -- One per level - a single icon, not a counter. pfUpdateHud hides it on any
   -- level that planted no star.
   if b2kSheetHasFrame("hud", "star") then
      b2kSpriteNew "hud", "star", 806, 22
      put the result into gHudStar
      if gHudStar is not empty then set the blendLevel of gHudStar to 62
   end if
   put true into gHudOK
   -- the art HUD + the splash/pause overlay own the screen chrome now: retire the
   -- demo TITLE and the top CONTROLS bar, and turn the bottom readout into the
   -- DEBUG overlay (hidden unless toggled with `). pfHelp is RE-SHOWN below only if
   -- the camera is unavailable, where it carries the diagnostic.
   if there is a field "pfTitle" then set the visible of field "pfTitle" to false
   if there is a field "pfHelp" then set the visible of field "pfHelp" to false
   if there is a field "pfHud" then set the visible of field "pfHud" to (gShowDebug is true)
end pfBuildHud

-- One HUD digit sprite (hud_character_0..9) at a fixed screen point, from the
-- scaled "hud" sheet. A plain card sprite (built before b2kCamOn = never scrolls).
function pfHudDigit pX, pY
   b2kSpriteNew "hud", "hud_character_0", pX, pY
   return the result
end pfHudDigit

-- Draw a 0..99 value across two digit slots, right-aligned, hiding the leading
-- slot below 10. Frames swap only when called; the caller gates on change.
command pfHudSetNum2 pD1, pD2, pValue
   if pValue < 0 then put 0 into pValue
   if pValue > 99 then put 99 into pValue
   if pD2 is not empty then
      b2kSpriteSetFrame pD2, "hud_character_" & (pValue mod 10)
      set the visible of pD2 to true   -- the ones digit always shows (matters for slots built hidden, e.g. gems)
   end if
   if pD1 is empty then exit pfHudSetNum2
   if pValue < 10 then
      set the visible of pD1 to false
   else
      b2kSpriteSetFrame pD1, "hud_character_" & (pValue div 10)
      set the visible of pD1 to true
   end if
end pfHudSetNum2

-- Refresh the art HUD (called at 4 Hz). Cheap: each element redraws only when its
-- own value changes. O(1) out when the art HUD is not active (the text fallback).
command pfUpdateHud
   local tSlot, k, tKeyBase
   if gHudOK is not true then exit pfUpdateHud
   -- coins collected + total (each on its own change; the total settles once at
   -- build, the collected count ticks as you grab coins)
   if gCoins is not gHudCoinLast then
      put gCoins into gHudCoinLast
      pfHudSetNum2 gHudCoinD[1], gHudCoinD[2], gCoins
   end if
   if gCoinsTotal is not gHudTotLast then
      put gCoinsTotal into gHudTotLast
      pfHudSetNum2 gHudCoinTot[1], gHudCoinTot[2], gCoinsTotal
   end if
   -- gems (a bonus tally): the counter shows only on levels that planted gems
   if gGems is not gHudGemLast or gGemsTotal is not gHudGemTotLast then
      put gGems into gHudGemLast
      put gGemsTotal into gHudGemTotLast
      if gGemsTotal > 0 then
         if gHudGemIcon is not empty then set the visible of gHudGemIcon to true
         pfHudSetNum2 gHudGemD[1], gHudGemD[2], gGems
      else
         if gHudGemIcon is not empty then set the visible of gHudGemIcon to false
         if gHudGemD[1] is not empty then set the visible of gHudGemD[1] to false
         if gHudGemD[2] is not empty then set the visible of gHudGemD[2] to false
      end if
   end if
   -- keys (on change): pack the carried set left-aligned in pickup order after the
   -- coin (and, where present, gem) counters; hide the rest. gKeysHeld drops a
   -- colour the instant a door consumes it, so the icon goes.
   if gKeysHeld is not gHudKeysLast then
      put gKeysHeld into gHudKeysLast
      set the itemDelimiter to comma
      if gGemsTotal > 0 then put 305 into tKeyBase else put 200 into tKeyBase
      repeat for each item k in "blue,green,red,yellow"
         if gHudKey[k] is not empty then set the visible of gHudKey[k] to false
      end repeat
      put 0 into tSlot
      repeat for each item k in gKeysHeld
         if gHudKey[k] is not empty then
            set the loc of gHudKey[k] to (tKeyBase + tSlot * 36) & comma & 20
            set the visible of gHudKey[k] to true
            add 1 to tSlot
         end if
      end repeat
   end if
   -- the hidden STAR slot: hidden on levels without one; else dim until found and
   -- bright once collected (the pickup also lights it instantly). On change only.
   if gStars is not gHudStarLast then
      put gStars into gHudStarLast
      if gHudStar is not empty then
         if gStarsTotal is 0 then
            set the visible of gHudStar to false
         else
            set the visible of gHudStar to true
            if gStars > 0 then
               set the blendLevel of gHudStar to 0
            else
               set the blendLevel of gHudStar to 62
            end if
         end if
      end if
   end if
   pfUpdateHearts
end pfUpdateHud

-- Refresh the heart row (from pfUpdateHud at 4Hz, on change only). Slots 1..gHearts
-- show hud_heart; the rest go hud_heart_empty so the buffer size always reads.
command pfUpdateHearts
   local tI
   if gHudOK is not true then exit pfUpdateHearts
   if gHearts is gHudHeartLast then exit pfUpdateHearts
   put gHearts into gHudHeartLast
   repeat with tI = 1 to kHearts
      if gHudHeart[tI] is empty then next repeat
      if tI <= gHearts then
         b2kSpriteSetFrame gHudHeart[tI], "hud_heart"
      else
         b2kSpriteSetFrame gHudHeart[tI], "hud_heart_empty"
      end if
   end repeat
end pfUpdateHearts

-- The CAVERN (L6) has no outdoor SCENE in the bg atlas, and Kenney's flat
-- "background_solid_*" frames read as a near-blank wash (the "no background"
-- report), so build a guaranteed-visible dark UNDERGROUND void from two card
-- graphics: deep earth, a touch warmer through the play band as if lit from
-- the floor torches. NOT parallax-drifted (a flat fill gains nothing from
-- drift) - the cave's depth comes from the scrolling ceiling/torches/decor in
-- pfL6Scene. gBgPanel stays empty so pfTickParallax no-ops. The graphics are
-- pf_* (pfWipeStage clears them next build) and sit at the back layers, behind
-- the camera viewport built right after.
command pfBuildCaveBackdrop
   create graphic "pf_bgcave1"
   set the style of graphic "pf_bgcave1" to "rectangle"
   set the showBorder of graphic "pf_bgcave1" to false
   set the filled of graphic "pf_bgcave1" to true
   set the backgroundColor of graphic "pf_bgcave1" to "36,28,21"
   set the rect of graphic "pf_bgcave1" to 0, 0, 1064, 640
   set the layer of graphic "pf_bgcave1" to 1
   create graphic "pf_bgcave2"
   set the style of graphic "pf_bgcave2" to "rectangle"
   set the showBorder of graphic "pf_bgcave2" to false
   set the filled of graphic "pf_bgcave2" to true
   set the backgroundColor of graphic "pf_bgcave2" to "54,42,32"
   set the rect of graphic "pf_bgcave2" to 0, 388, 1064, 584
   set the layer of graphic "pf_bgcave2" to 2
end pfBuildCaveBackdrop

-- The STONE KEEP (L7) interior, like the cavern, has no outdoor scene in the bg
-- atlas, so build a dark stone backdrop (cooler gray-blue than the cave's
-- brown) from two card graphics. Not parallax-drifted - the depth comes from
-- the scrolling stonework + torches in pfL7Scene. Reuses the pf_bgcave* names
-- (one level's backdrop exists at a time; pfWipeStage clears them each build).
command pfBuildStoneBackdrop
   create graphic "pf_bgcave1"
   set the style of graphic "pf_bgcave1" to "rectangle"
   set the showBorder of graphic "pf_bgcave1" to false
   set the filled of graphic "pf_bgcave1" to true
   set the backgroundColor of graphic "pf_bgcave1" to "40,42,52"
   set the rect of graphic "pf_bgcave1" to 0, 0, 1064, 640
   set the layer of graphic "pf_bgcave1" to 1
   create graphic "pf_bgcave2"
   set the style of graphic "pf_bgcave2" to "rectangle"
   set the showBorder of graphic "pf_bgcave2" to false
   set the filled of graphic "pf_bgcave2" to true
   set the backgroundColor of graphic "pf_bgcave2" to "58,61,74"
   set the rect of graphic "pf_bgcave2" to 0, 388, 1064, 584
   set the layer of graphic "pf_bgcave2" to 2
end pfBuildStoneBackdrop

-- Drift the backdrop slower than the 1:1 foreground (parallax depth) and wrap
-- it seamlessly (the bg scenes tile at the 640px panel width). Gated on the
-- scroll changing, so a still camera costs one compare. 0.3 = the drift rate.
command pfTickParallax
   local i, tHS, tShift
   if gBgPanel[1] is empty or gCamOK is not true then exit pfTickParallax
   put the hScroll of b2kCamGroup() into tHS
   if tHS is gBgLastHS then exit pfTickParallax   -- camera still: no redraw
   put tHS into gBgLastHS
   put - (round(tHS * 0.3) mod 640) into tShift   -- 0.3x the foreground; wrap every panel width (rounded so the loc lands on a whole pixel -> no sub-pixel shimmer at the panel overlaps)
   repeat with i = 1 to 3
      if gBgPanel[i] is not empty then set the loc of gBgPanel[i] to ((i - 1) * 640 + tShift + 320) & ",320"
   end repeat
end pfTickParallax

-- =====================================================================
-- World build / reset
-- =====================================================================
command pfStartGame
   local tRef, tW, tH, tDY, tX, tS
   if gBuilding is true then exit pfStartGame   -- ignore R-mash mid-rebuild
   put true into gBuilding
   -- COVER FIRST: raise the opaque biome card over everything BEFORE the teardown,
   -- so the player never sees the old level clear or the new one assemble. The
   -- whole build below paints behind it; pfCardReveal fades it out at the end.
   pfCardCover
   if the shiftKey is down then
      set the uSpriteSheetFolderPath of this stack to empty
      b2kSheetsWipe   -- drop the cached sheets so a re-picked folder loads fresh
   end if
   try
      b2kClear                  -- spawned bodies (confetti, the crate) go
   catch tErr                   -- while the world still exists
   end try
   b2kTeardown                  -- clears the world + camera; cached sheets survive (persist)
   pfWipeStage
   put false into gHurtLock
   put false into gWon
   put false into gWinLock
   put false into gFlagHint
   put false into gCheckpointOn
   put 120 into gRespawnX
   put 480 into gRespawnY
   put empty into gWinSecs
   put 0 into gFalls
   put 0 into gOuches
   put 0 into gLands
   put kHearts into gHearts   -- a fresh, forgiving five-heart buffer each level
   put 0 into gHudNextMS
   put empty into gGateVel
   put 0 into gAirMS
   put the milliseconds into gRunStart
   put 0 into gCoins
   put 0 into gGems       -- gem bonus tally (gGemsTotal counts itself as gems build, like coins)
   put 0 into gGemsTotal
   put 0 into gScore      -- Phase F coin-tier bonus score (gScoreTotal self-counts as coins build)
   put 0 into gScoreTotal
   put 0 into gStars      -- the hidden star (gStarsTotal self-counts as the star builds)
   put 0 into gStarsTotal
   if there is a graphic "pfWinShade" then set the visible of graphic "pfWinShade" to false
   if there is a field "pfWinText" then set the visible of field "pfWinText" to false
   if there is a button "pfbtn_again" then set the visible of button "pfbtn_again" to false
   -- a fresh build is never paused: clear the pause overlay + reset the button
   if there is a graphic "pfPauseShade" then set the visible of graphic "pfPauseShade" to false
   if there is a field "pfPauseText" then set the visible of field "pfPauseText" to false
   if there is a button "pfbtn_pause" then set the label of button "pfbtn_pause" to "Pause"
   -- (the intro splash is retired: the transition card now shows the level title
   -- while the world builds behind it. The pfSplash field stays, reused by
   -- pfNotice for the centre banners; it is just no longer shown at level start.)
   put 0 into gPlateHoldMS
   put empty into gPlateLook
   -- per-level machine refs: a rebuilt level must never tick a deleted
   -- control's stale long id from the previous one
   put empty into gGate
   put empty into gGateSprA
   put empty into gGateSprB
   put empty into gPlateX
   put empty into gDoorX
   put empty into gDoorWord
   put empty into gCheckX
   put empty into gLevelName
   put 2880 into gLevelW
   put 64 into gEdgeL    -- pfBounds overrides both per level (belt-and-braces defaults)
   put 2880 into gEdgeR
   put 320 into gCamTopY
   put 320 into gCamBotY
   put 780 into gKillPlaneY
   -- the indexed enemy/trap tables start the run empty
   put 0 into gSlimeN
   put empty into gSlimeB
   put empty into gSlimeSpr
   put empty into gSlimeKind
   put empty into gSlimeDir
   put empty into gSlimeMin
   put empty into gSlimeMax
   put empty into gSlimeGoneAt
   put empty into gSlimeDeadX
   put empty into gSlimeDeadY
   put empty into gSlimeT
   put empty into gFrogAir   -- Wave 6: the frog's per-row hop-pose flag
   -- Wave 3 tables start the run empty
   put 0 into gPlantN
   put empty into gPlantSpr
   put empty into gPlantX
   put empty into gPlantState
   put empty into gPlantT
   put empty into gGhostSpr
   put 0 into gGhostX
   put 0 into gGhostY
   put true into gGhostShy
   -- Wave 6 (bestiary II) tables start the run empty
   put 0 into gBarnN
   put empty into gBarnSpr
   put empty into gBarnX
   put empty into gBarnY
   put empty into gBarnState
   put empty into gBarnT
   put 0 into gSpiderN
   put empty into gSpiderSpr
   put empty into gSpiderX
   put empty into gSpiderY
   put empty into gSpiderHangY
   put empty into gSpiderDropTo
   put empty into gSpiderMinX
   put empty into gSpiderMaxX
   put empty into gSpiderDir
   put empty into gSpiderState
   put 0 into gBlockN
   put empty into gBlockB
   put empty into gBlockSpr
   put empty into gBlockState
   put empty into gBlockT
   put empty into gBlockX
   put 0 into gMovN
   put empty into gMovSpr
   put empty into gMovX
   put empty into gMovY
   put empty into gMovAX
   put empty into gMovPX
   put empty into gMovAY
   put empty into gMovPY
   put empty into gMovHurtW
   put empty into gMovHurtH
   put empty into gMovFlip
   put 0 into gConvN
   put empty into gConvL
   put empty into gConvR
   put empty into gConvY
   put empty into gConvDir
   put empty into gPrevState
   -- Wave 1 state starts the run empty/idle
   put false into gToysOK
   put empty into gSpringSpr
   put 0 into gSpringMS
   put 0 into gSpringBackMS
   put 0 into gBonkN
   put empty into gBonkHost
   put empty into gBonkSpr
   put empty into gBonkKind
   put empty into gBonkUsed
   put empty into gBonkX
   put 0 into gBonkMS
   put empty into gPlateSpr
   put empty into gLeverSpr
   put true into gLeverArmed
   put true into gSawOn
   put empty into gSawMov
   put empty into gSawSpr
   put 0 into gDoorN
   put empty into gKeysHeld
   put empty into gDoorOpen
   put empty into gLockSpr
   put empty into gDoorSprT
   put empty into gDoorSprB
   put empty into gDoorHostNm
   put 0 into gSwN
   put empty into gSwX
   put empty into gSwWord
   put empty into gSwOpen
   put empty into gSwDone
   put empty into gSwGate
   put empty into gSwSpr
   put empty into gSwGateSprA
   put empty into gSwGateSprB
   put empty into gSwGateVel
   put 0 into gDebrisNext
   put empty into gDebrisB
   put empty into gDebrisSpr
   put empty into gDebrisUntil
   put 0 into gDustNext
   put empty into gDustB
   put empty into gDustUntil
   put 0 into gHeroPX
   put 0 into gHeroPY
   put empty into gHeroState
   put 0 into gJumpMS
   put empty into gCrateB
   put empty into gCrateSpr
   put empty into gBlockChainA
   put empty into gBlockChainB
   put empty into gBlockFace
   put empty into gGoalSpr
   put 0 into gNoticeUntil
   put 0 into gFlagNoteMS
   -- the showcase round's mechanism tables start the run empty/idle
   put 0 into gBoulderN
   put empty into gBoulderB
   put empty into gBoulderSpr
   put empty into gBoulderHomeX
   put empty into gBoulderHomeY
   put empty into gBoulderResetX
   put empty into gBoulderT
   put empty into gBoulderHurtR
   put empty into gBoulderGrace
   put empty into gBoulderVX
   put 0 into gBarrelN
   put empty into gBarrelB
   put empty into gBarrelSpr
   put empty into gBarrelX
   put empty into gBarrelY
   put empty into gBarrelState
   put empty into gBarrelT
   -- the serpent starts empty (only the L4 lava / L6 goo pools build one)
   put empty into gLSerpSpr
   put false into gLSerpVis
   -- the Wave 5 moving-platform lifts start the run empty/idle
   put 0 into gLiftN
   put empty into gLift
   put empty into gLiftMin
   put empty into gLiftMax
   put empty into gLiftSpeed
   put empty into gLiftVX
   -- per-critter speed + squash frame + facing polarity (slime columns)
   put empty into gSlimeSpeed
   put empty into gSlimeFlat
   put empty into gSlimeFlip
   b2kSetup
   b2kSetScale 60
   pfMakeSounds
   if gHeroSkin is empty then put "beige" into gHeroSkin   -- Phase G: the chosen skin persists; default once
   put pfLoadSheets() into gAssetsOK
   if gAssetsOK is not true then pfEmbedPlaceholder
   -- Wave 1 toys need the tiles atlas (spring/box/brick/lever/key/door
   -- art); without it each level builds its frozen plain-shape fallback
   put (gAssetsOK is true and b2kSheetHasFrame("tiles", "spring_out")) into gToysOK
   -- Wave 3 spooks need enemies.png (ghost/bat/piranha/mimic); without
   -- it those four makers skip silently - L4 stays completable
   put (gAssetsOK is true and b2kSheetHasFrame("spooks", "ghost.png")) into gSpooksOK
   -- the coin total COUNTS ITSELF: pfMakeCoin and every "?-box" add one
   -- as they are built, so totals can never drift from the layout
   put 0 into gCoinsTotal
   lock screen
   -- ===== far backdrop: a per-biome scene that PARALLAX-drifts behind the
   -- foreground (slower than the 1:1 scroll, for depth). Built BEFORE b2kCamOn
   -- so the panels live on the CARD (not the scrolling camera group); the
   -- parallax tick in b2kFrame drifts + wraps them. =====
   pfBuildBackdrop
   pfBuildHud   -- Phase F: the screen-fixed art HUD (before b2kCamOn, like the backdrop, so it does not scroll)
   -- ===== the camera: everything Kit-made from here lives in the view ====
   b2kCamOn
   put (b2kCamIsOn() and b2kCamStatus() is empty) into gCamOK
   -- regular-platformer camera: the hero is LOCKED to screen centre and
   -- the world scrolls 1:1; the bounds are set per level by pfBounds.
   -- ORDER LAW (gotcha #12, learned the hard way): NEVER b2kCamGoto
   -- before the bounds exist - an unbounded goto scrolls the empty
   -- viewport (120 centred = scroll -392), and every control built
   -- after that lands SCROLL-SHIFTED. So build the WHOLE world at scroll
   -- 0 - scenery, the hero, AND the cast (coins/flags/checkpoints) - and
   -- b2kCamGoto exactly ONCE, after the cast (below). A goto BEFORE the
   -- cast left create-once cast sprites scroll-shifted on the user's engine
   -- (coins off-centre in the pond, flag/checkpoint POLES drifting off their
   -- step). Bound bodies re-sync every frame, so the hero was always fine;
   -- static pickups never re-sync, so they must be BORN at scroll 0.
   b2kCamDeadzone 0, 0
   -- ===== LEVEL SCENERY (terrain, machines, Wave 1 toys) =====
   -- Built BEFORE the hero so every piece of it layers BEHIND him (he
   -- must walk in front of doors and levers, never vanish). Each level
   -- is a builder pair: ...Scene here, ...Cast after the hero exists.
   switch gLevel
      case 2
         pfL2Scene
         break
      case 3
         pfL3Scene
         break
      case 4
         pfL4Scene
         break
      case 5
         pfL5Scene
         break
      case 6
         pfL6Scene
         break
      case 7
         pfL7Scene
         break
      default
         put 1 into gLevel
         pfL1Scene
   end switch
   -- (the camera goto is DEFERRED to after the cast - see the ORDER LAW above -
   -- so coins/flags/checkpoints are born at scroll 0, on their marks)
   -- ===== the hero ====
   if gAssetsOK is true then
      b2kSheetScale "chars", 0.75
      put 48 into tW
      -- the 128px character frame is bottom-aligned with headroom, so an
      -- 88px hitbox topped out ABOVE the visible head -- heads "missed"
      -- bricks by that headroom. 76 matches the art; tDY keeps the FEET on
      -- the ground (sprite half = 128*0.75/2 = 48 vs hitbox half tH/2).
      -- If the head still gaps under bricks, lower tH a touch; if it sinks
      -- INTO them, raise it. tDY + gHeroHalfH follow automatically.
      put 76 into tH
      put (tH div 2) - 48 into tDY
   else
      put 36 into tW
      put 60 into tH
      put -2 into tDY
   end if
   put tH / 2 into gHeroHalfH   -- bonks reach the brick at the real head
   create graphic "pf_heroBody"
   set the style of it to "rectangle"
   set the rect of it to gRespawnX - tW div 2, gRespawnY - tH div 2, gRespawnX + tW div 2, gRespawnY + tH div 2
   set the visible of it to false
   put the long id of graphic "pf_heroBody" into gHero
   if gAssetsOK is true then
      b2kSpriteNew "chars", ("character_" & gHeroSkin & "_idle"), gRespawnX, gRespawnY
   else
      b2kSpriteNew "chars", 1, gRespawnX, gRespawnY
   end if
   put the result into gHeroSpr
   b2kSpriteBind gHeroSpr, gHero, 0, tDY
   b2kSpriteOnFinish gHeroSpr, "pfHurtDone"
   -- Phase 3: the Kit's controller owns movement, grounding, jump feel
   -- (coyote/buffer/jump-cut), state and anims. Attaching adds the
   -- capsule + fixed rotation + sleep-off + low friction in one call;
   -- the bound sprite above is auto-discovered as the art to animate.
   b2kPlayerAttach gHero
   -- duck/climb map when the atlas loaded them (placeholder art has
   -- neither: empty slots fall back to idle/jump inside the Kit). The
   -- knockback pose is the LOOPING "hurtpose" -- never the one-shot
   -- "hit", whose finish message means RESPAWN in this game
   if gAssetsOK is true and b2kSheetHasFrame("chars", ("character_" & gHeroSkin & "_duck")) then
      b2kPlayerAnims "idle", "walk", "jump", "jump", "", "duck", "climb", "hurtpose"
   else
      b2kPlayerAnims "idle", "walk", "jump", "jump", "", "", "", "hurtpose"
   end if
   b2kPlayerSet "moveSpeed", kMoveSpeed
   b2kPlayerSet "jumpSpeed", kJumpSpeed
   -- Wave 4 swim feel: heavier than the Kit defaults. swimGravity (the
   -- sink between strokes) is well up so the water feels weighty; swimJump
   -- (the stroke) is the ONLY thing that sets the escape height, so it is
   -- trimmed back -- you must swim to the bank and stroke to climb out, not
   -- bob straight up. All four are live; tune to taste in OXT.
   b2kPlayerSet "swimSpeed", 165
   b2kPlayerSet "swimJump", 300
   b2kPlayerSet "swimGravity", 0.6
   b2kPlayerSet "swimMaxFall", 200
   -- Wave 5 moves, on for the whole showcase (each beat below leans on one;
   -- all stay live everywhere). The Kit falls the wall-slide pose back to
   -- the fall/jump frame and the dash pose to the run frame -- the beige
   -- hero has no dedicated wall/dash art -- so they read correctly. Tune in
   -- OXT to taste: these are first-pass feel numbers.
   b2kPlayerSet "airJumps", 1         -- DOUBLE JUMP (a second jump in mid-air)
   b2kPlayerSet "wallJumpX", 240      -- WALL JUMP: launch away from a wall...
   b2kPlayerSet "wallJumpY", 430      -- ...and up (matches the ground jump)
   b2kPlayerSet "wallSlideMax", 120   -- ...after a slowed slide down it
   b2kPlayerSet "dashSpeed", 560      -- DASH (SHIFT or X): a flat GROUND zip
   b2kPlayerSet "dashMs", 150
   b2kPlayerSet "dashCooldownMs", 420
   b2kPlayerSet "airDash", 0          -- no mid-air dash: DASH only fires while grounded
   b2kPlayerSet "duckScale", 1        -- DOWN brakes to a stop in place (no hitbox reshape)
   b2kPlayerSet "platformCarry", 1    -- ride the moving platforms (the L2 lift bay)
   put 75 into gIntroPan   -- a splash beat (~1.2 s), then control
   pfMakeDustPool   -- Phase D: the stomp dust-poof pool (every level; needs gHero)
   -- ===== LEVEL CAST (coins, enemies, checkpoint, the goal flag) =====
   switch gLevel
      case 2
         pfL2Cast
         break
      case 3
         pfL3Cast
         break
      case 4
         pfL4Cast
         break
      case 5
         pfL5Cast
         break
      case 6
         pfL6Cast
         break
      case 7
         pfL7Cast
         break
      default
         pfL1Cast
   end switch
   -- NOW frame the spawn (clamped to the content box, no void at the left).
   -- Deferred to HERE so the whole world - scenery, hero AND cast - was built
   -- at scroll 0; no create-once pickup is scroll-shifted. Per-frame tracking
   -- takes over in b2kFrame once the intro beat ends.
   b2kCamGoto gEdgeL + 512, gCamBotY   -- gCamBotY=320 (horizontal) or the tower's bottom (vertical)
   -- help + the level banner on the splash (visible through the intro
   -- beat); gCoinsTotal counted itself during the build above
   if gAssetsOK is true and gLoadNote is empty then
      set the text of field "pfHelp" to "Arrows/A-D run, SPACE jumps - press it again in mid-air to DOUBLE JUMP, or off a wall to WALL-JUMP. SHIFT or X = DASH." & cr & "DOWN ducks to a stop (DOWN+JUMP drops through bridges/clouds); UP/DOWN climbs ladders. R restarts, ESC pauses, M mutes, MOUSE drags the crate." & cr & "LEVEL " & gLevel & " of 7: " & gLevelName & ". Collect ALL " & gCoinsTotal & " coins - the flag turns GOLD - then touch the flag. Seven levels to win."
   else
      if gAssetsOK is true then
         set the text of field "pfHelp" to "KENNEY CHARACTERS LOADED, but: " & gLoadNote & cr & "Missing atlases fall back to plain shapes." & cr & "Shift+Reset re-asks for the Spritesheets folder."
      else
         set the text of field "pfHelp" to "PLACEHOLDER ART - the atlas load failed: " & gLoadNote & cr & "Press Shift+Reset to pick the Spritesheets folder again (it must contain the" & cr & "spritesheet-*-default.png and .xml files)."
      end if
   end if
   if there is a field "pfSplash" then
      -- the pfSplash field is now only the CENTRE-BANNER surface (pfNotice sets
      -- its text just before showing it - the level title moved to the transition
      -- card). Prime its colour per biome so those banners read against the scene:
      -- the cavern + stone keep need LIGHT text; the bright biomes keep dark.
      if gLevel is 6 or gLevel is 7 then
         set the textColor of field "pfSplash" to "245,246,236"
      else
         set the textColor of field "pfSplash" to "28,30,42"
      end if
   end if
   -- ===== camera-dead fallback: clamp play to the visible screen ====
   if gCamOK is not true then
      b2kWall 1010, 0, 1010, 640
      put empty into tRef
      if gAssetsOK is true and b2kSheetHasFrame("tiles", "flag_blue_a") then
         b2kSpriteNew "tiles", "flag_blue_a", 950, 544 + kFlagPlantPx   -- plant the pole base (see kFlagPlantPx)
         put the result into tRef
         if tRef is not empty then
            set the uPfGoalFlag of tRef to true
            b2kSpritePlay tRef, "wave"
            b2kAddSensor tRef, "ball"
            put tRef into gGoalSpr
         end if
      end if
      if tRef is empty then
         create graphic "pf_flagnear"
         set the style of it to "rectangle"
         set the rect of it to 934, 512, 966, 576
         set the filled of it to true
         set the backgroundColor of it to "70,110,230"
         put the long id of graphic "pf_flagnear" into tRef
         set the uPfGoalFlag of tRef to true
         b2kAddSensor tRef, "box"
      end if
      set the text of field "pfHelp" to "CAMERA UNAVAILABLE on this engine (" & b2kCamStatus() & ") - the level is clamped" & cr & "to this screen and the flag moved here so it stays completable. Everything else works." & cr & "Please report the quoted reason."
      -- this diagnostic matters, so override the art-HUD retirement of pfHelp
      if there is a field "pfHelp" then set the visible of field "pfHelp" to true
   end if
   -- diagnostics: prove world membership at a glance (line 3 of the help)
   if gCamOK is true and gHeroSpr is not empty then
      put "diag: hero-sprite in [" & the short name of the owner of gHeroSpr & "]" into tS
      if gGateSprA is not empty then
         put "   gate-tile in [" & the short name of the owner of gGateSprA & "]" after tS
      end if
      put tS & "   grouped-loc semantics: " & b2kCamLocSemantics() into line 3 of field "pfHelp"
   end if
   -- ===== input + events ====
   b2kInputOn
   b2kBindAction "jump", "space,up,w"
   b2kFrameTarget the long id of me
   b2kContactTarget the long id of me
   pfChromeFront
   unlock screen
   put empty into gHudLast
   put true into gStarted
   put false into gBuilding
   if there is a button "pfbtn_level" then set the menuHistory of button "pfbtn_level" to gLevel
   b2kStart
   -- the level is built and framed behind the opaque card: hold it a beat, then
   -- fade the card out to reveal it (control engages as the gIntroPan beat ends)
   pfCardReveal
end pfStartGame

-- An invisible static physics slab (shown grey only in fallback mode).
command pfSlab pName, pL, pT, pR, pB
   create graphic pName
   set the style of it to "rectangle"
   set the rect of it to pL, pT, pR, pB
   set the filled of it to true
   set the backgroundColor of it to "100,105,115"
   set the visible of it to false
   b2kAddStatic the long id of graphic pName
end pfSlab

-- Skin a STATIC slab with sheet art instead of a flat colour: a COPY of the
-- frame image stretched to the slab's exact rect, so the collision size never
-- changes. The texture is a pf_* image (pfWipeStage clears it next build), laid
-- in at build time only -- the camera scroll is 0 then, so the slab's rect reads
-- as world coords and the adopt preserves the position. No assets or a missing
-- frame: this no-ops and the slab keeps its colour (the placeholder fallback).
command pfTextureSlab pSlab, pFrame
   local tSpr, tImg, tName
   if gAssetsOK is not true then exit pfTextureSlab
   if there is no graphic pSlab then exit pfTextureSlab
   if not b2kSheetHasFrame("tiles", pFrame) then exit pfTextureSlab
   b2kSpriteNew "tiles", pFrame, -3000, -3000   -- a throwaway sprite carries the sliced frame as its icon
   put the result into tSpr
   if tSpr is empty then exit pfTextureSlab
   put the icon of tSpr into tImg
   if tImg is empty or there is no image id tImg then
      b2kSpriteRemove tSpr
      exit pfTextureSlab
   end if
   put "pf_tex_" & (the short name of graphic pSlab) into tName
   if there is an image tName then delete image tName
   lock screen
   clone image id tImg
   set the name of the last image to tName
   set the rect of image tName to the rect of graphic pSlab   -- stretch to fit
   set the visible of image tName to true   -- the sliced frame source is hidden; the copy shows
   set the lockLoc of image tName to true
   b2kSpriteRemove tSpr
   set the visible of graphic pSlab to false   -- the texture stands in for the flat fill
   b2kCamAdopt the long id of image tName
   unlock screen
end pfTextureSlab

command pfShowSlabs pFlag
   local tC
   set the itemDelimiter to comma
   repeat for each item tC in "pf_ground1,pf_ground2,pf_ground3,pf_plat1,pf_plat2,pf_plat3"
      if there is a graphic tC then
         set the visible of graphic tC to pFlag
         if pFlag is true then b2kCamAdopt the long id of graphic tC
      end if
   end repeat
end pfShowSlabs

-- One 64px tile sprite by its top-left corner (sprites centre on x,y).
-- pFlip true mirrors the tile (ramps ascending the other way).
command pfTile pFrame, pX, pY, pFlip
   local tRef
   b2kSpriteNew "tiles", pFrame, pX + 32, pY + 32
   if pFlip is true then
      put the result into tRef
      if tRef is not empty then b2kSpriteFlipH tRef, true
   end if
end pfTile

-- A flickering wall TORCH (2-frame torch_on_a/b), centred at pX,pY - pure
-- cavern ambiance, no body, no gate (not audited as decor). No torch art: a
-- small warm glow oval stands in so the cave still reads as lit.
command pfMakeTorch pX, pY
   local tRef
   put empty into tRef
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "torch_on_a") then
      b2kSpriteNew "tiles", "torch_on_a", pX, pY
      put the result into tRef
      if tRef is not empty then b2kSpritePlay tRef, "torch"
   end if
   if tRef is empty then
      create graphic ("pf_torch" & pX & "_" & pY)
      set the style of it to "oval"
      set the filled of it to true
      set the backgroundColor of it to "255,170,70"
      set the rect of it to pX - 9, pY - 13, pX + 9, pY + 13
      put the long id of it into tRef
      b2kCamAdopt tRef
   end if
end pfMakeTorch

-- Register a bodiless patroller: the sprite glides on sine paths each
-- frame (b2kSpriteMoveTo, camera-correct), flips to face its travel, and
-- hurts by plain proximity when given a hurt box - no physics involved.
command pfAddMover pSpr, pX, pY, pAmpX, pPerX, pAmpY, pPerY, pHurtW, pHurtH, pFaceTravel
   add 1 to gMovN
   put pSpr into gMovSpr[gMovN]
   put pX into gMovX[gMovN]
   put pY into gMovY[gMovN]
   put pAmpX into gMovAX[gMovN]
   put max(1, pPerX) into gMovPX[gMovN]
   put pAmpY into gMovAY[gMovN]
   put max(1, pPerY) into gMovPY[gMovN]
   put pHurtW into gMovHurtW[gMovN]
   put pHurtH into gMovHurtH[gMovN]
   put (pFaceTravel is true) into gMovFlip[gMovN]
end pfAddMover

-- A SPINNING-BLADE hazard (asset-expansion Phase C, the keep's hazard): a
-- bodiless spooks-sheet sprite that spins in place (animation, not body
-- rotation - gotcha 23) and SWEEPS a horizontal sine path, hurting by plain
-- proximity like the saw. It is an UNKILLABLE hazard - the "saw rule": you
-- TIME it, you never stomp it (knockback via pfOuch in pfTickMovers, never a
-- respawn). pAmpX/pPerX set the sweep (amp 0 = a blade fixed in place); pHalf
-- selects the wall-mounted HALF-blade (spinnerHalf) over the full disc. The
-- art is OPTIONAL (enemies.png / gSpooksOK): absent, the maker no-ops and the
-- spot is simply safe (the climb never depends on a hazard being present).
command pfMakeSpinner pX, pY, pAmpX, pPerX, pHalf
   local tRef, tFrame, tAnim, tHurtH
   if gSpooksOK is not true then exit pfMakeSpinner
   if pHalf is true then
      put "spinnerHalf.png" into tFrame
      put "spinhalf" into tAnim
      put 15 into tHurtH        -- the half-blade is flat (63x31): a short hurt box
   else
      put "spinner.png" into tFrame
      put "spin" into tAnim
      put 28 into tHurtH        -- the full disc (~57px after the 0.9 scale): hurt ~ the blade
   end if
   if not b2kSheetHasFrame("spooks", tFrame) then exit pfMakeSpinner
   b2kSpriteNew "spooks", tFrame, pX, pY
   put the result into tRef
   if tRef is empty then exit pfMakeSpinner
   b2kSpritePlay tRef, tAnim
   -- a spinning disc is symmetric: no facing flip (pFaceTravel false)
   pfAddMover tRef, pX, pY, pAmpX, pPerX, 0, 1, 28, tHurtH, false
end pfMakeSpinner

-- A COIN. The flag gates on COUNT (every coin), so each coin still adds 1 to
-- gCoinsTotal. Phase F adds a TIER (bronze/silver/gold = 1/2/3) feeding a bonus
-- SCORE (gScore/gScoreTotal): auto-assigned by height (higher = harder to reach
-- = worth more) unless an explicit pTier is passed. The tier picks the art, the
-- spin anim and the fallback colour; the score total counts itself as coins build.
command pfMakeCoin pX, pY, pTier
   local tRef, tVal, tAnim, tColor
   add 1 to gCoinsTotal   -- the total counts itself as the level builds (the flag gate)
   if pTier is empty then
      if pY <= 360 then put "gold" into pTier         -- a high bonus coin
      else if pY > 520 then put "bronze" into pTier   -- a ground-level coin
      else put "silver" into pTier                    -- the main jump-grab band
   end if
   switch pTier
      case "gold"
         put 3 into tVal
         put "spin" into tAnim
         put "240,200,70" into tColor
         break
      case "bronze"
         put 1 into tVal
         put "spinbronze" into tAnim
         put "205,135,80" into tColor
         break
      default            -- silver (and any unexpected tier)
         put "silver" into pTier
         put 2 into tVal
         put "spinsilver" into tAnim
         put "200,205,215" into tColor
   end switch
   add tVal to gScoreTotal   -- the bonus score counts itself as coins build
   put empty into tRef
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "coin_" & pTier) then
      b2kSpriteNew "tiles", "coin_" & pTier, pX, pY
      put the result into tRef
      if tRef is not empty then b2kSpritePlay tRef, tAnim
   end if
   if tRef is empty then
      create graphic ("pf_coin" & pX)
      set the style of it to "oval"
      set the rect of it to pX - 16, pY - 16, pX + 16, pY + 16
      set the filled of it to true
      set the backgroundColor of it to tColor
      put the long id of it into tRef
      b2kCamAdopt tRef
   end if
   set the uPfCoinFlag of tRef to true
   set the uPfCoinVal of tRef to tVal
   b2kAddSensor tRef, "ball"
end pfMakeCoin

-- A GEM: a bonus pickup that does NOT count toward the coin/flag gate - a pure
-- skill-reward tally (gGems/gGemsTotal, shown in the HUD + win screen). pColour
-- is blue/green/red/yellow (gem_* tiles art); no-art falls back to a small jewel.
command pfMakeGem pX, pY, pColour
   local tRef
   add 1 to gGemsTotal   -- the total counts itself as the level builds (like coins)
   put empty into tRef
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "gem_" & pColour) then
      b2kSpriteNew "tiles", "gem_" & pColour, pX, pY
      put the result into tRef
   end if
   if tRef is empty then
      create graphic ("pf_gem" & pX)
      set the style of it to "oval"   -- a simple jewel when the gem_* art is missing
      set the rect of it to pX - 13, pY - 16, pX + 13, pY + 16
      set the filled of it to true
      set the backgroundColor of it to "120,210,235"
      put the long id of it into tRef
      b2kCamAdopt tRef
   end if
   set the uPfGemFlag of tRef to true
   b2kAddSensor tRef, "ball"
end pfMakeGem

-- The hidden STAR: one per level, a hard-to-reach CHALLENGE pickup (like the gems
-- but rarer - one per level), banked to the win screen and lighting its own HUD
-- slot. A bonus only: it NEVER gates the flag, so it can sit on the hardest route
-- without locking progress. pX,pY is the star's centre; place it ON or just above
-- a surface the player provably reaches (a ledge/cloud/ladder top), never at a
-- bare max-jump apex.
command pfMakeStar pX, pY
   local tRef
   add 1 to gStarsTotal
   put empty into tRef
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "star") then
      b2kSpriteNew "tiles", "star", pX, pY
      put the result into tRef
      if tRef is not empty then b2kSpritePlay tRef, "starspin"
   end if
   if tRef is empty then
      create graphic ("pf_star" & pX)
      set the style of it to "oval"   -- a simple bead when the star art is missing
      set the rect of it to pX - 14, pY - 14, pX + 14, pY + 14
      set the filled of it to true
      set the backgroundColor of it to "245,210,70"
      put the long id of it into tRef
      b2kCamAdopt tRef
   end if
   set the uPfStarFlag of tRef to true
   b2kAddSensor tRef, "ball"
end pfMakeStar

-- A patrolling slime: an invisible dynamic body, art bound on top.
-- pKind "normal" stomps flat; "spike" hurts from EVERY side. pTopY is the
-- surface it stands on; it walks pMinX..pMaxX.
command pfMakeSlime pIdx, pKind, pX, pMinX, pMaxX, pTopY
   local tName, tBody, tSpr, tFrame
   put "pf_slimeBody" & pIdx into tName
   create graphic tName
   set the style of it to "rectangle"
   set the rect of it to pX - 24, pTopY - 36, pX + 24, pTopY
   set the filled of it to true
   if pKind is "spike" then
      set the backgroundColor of it to "200,80,80"
   else
      set the backgroundColor of it to "110,190,90"
   end if
   set the visible of it to false
   put the long id of graphic tName into tBody
   b2kAddBox tBody
   b2kSetFixedRotation tBody, true
   b2kSetFriction tBody, 0.1
   put empty into tSpr
   put "slime_" & pKind & "_walk_a" into tFrame
   if gAssetsOK is true and b2kSheetHasFrame("foes", tFrame) then
      b2kSpriteNew "foes", tFrame, pX, pTopY - 32
      put the result into tSpr
      if tSpr is not empty then
         b2kSpriteBind tSpr, tBody, 0, -6
         if pKind is "spike" then
            b2kSpritePlay tSpr, "spikewalk"
         else
            b2kSpritePlay tSpr, "slimewalk"
         end if
      end if
   end if
   if tSpr is empty then set the visible of graphic tName to true
   if the visible of graphic tName is true then b2kCamAdopt tBody
   if pIdx > gSlimeN then put pIdx into gSlimeN
   put tBody into gSlimeB[pIdx]
   put tSpr into gSlimeSpr[pIdx]
   put pKind into gSlimeKind[pIdx]
   put 60 into gSlimeDir[pIdx]
   put 60 into gSlimeSpeed[pIdx]
   put "slime_" & pKind & "_flat" into gSlimeFlat[pIdx]
   put false into gSlimeFlip[pIdx]
   put pMinX into gSlimeMin[pIdx]
   put pMaxX into gSlimeMax[pIdx]
   put empty into gSlimeGoneAt[pIdx]
end pfMakeSlime

-- The showcase round's variety walkers: mouse (fast), worm (slow),
-- ladybug, fire slime - all native 64px foes art. They JOIN the slime
-- family as ordinary patrollers (pKind "normal" = stompable, "spike" =
-- hurts from every side) so the existing contact verdict, b2kFell
-- cleanup and per-frame steering all carry them for free. pFlat is the
-- squash frame (empty = the sheet has none, so the critter just drops
-- and fades - a safe no-op, never wrong art). pHalfW/pFullH size the
-- (invisible) collision box; pDY offsets the bound art.
command pfMakeCritter pIdx, pKind, pX, pMinX, pMaxX, pTopY, pSpeed, pFrame, pAnim, pFlat, pHalfW, pFullH, pColor, pDY, pSheet, pFaceFlip
   local tName, tBody, tSpr
   if pSheet is empty then put "foes" into pSheet   -- Phase D: default native foes; "spooks" for the .png slime skins
   put "pf_slimeBody" & pIdx into tName
   create graphic tName
   set the style of it to "rectangle"
   set the rect of it to pX - pHalfW, pTopY - pFullH, pX + pHalfW, pTopY
   set the filled of it to true
   set the backgroundColor of it to pColor
   set the visible of it to false
   put the long id of graphic tName into tBody
   b2kAddBox tBody
   b2kSetFixedRotation tBody, true
   b2kSetFriction tBody, 0.1
   put empty into tSpr
   if gAssetsOK is true and b2kSheetHasFrame(pSheet, pFrame) then
      b2kSpriteNew pSheet, pFrame, pX, pTopY - pFullH div 2
      put the result into tSpr
      if tSpr is not empty then
         b2kSpriteBind tSpr, tBody, 0, pDY
         b2kSpritePlay tSpr, pAnim
      end if
   end if
   if tSpr is empty then set the visible of graphic tName to true
   if the visible of graphic tName is true then b2kCamAdopt tBody
   if pIdx > gSlimeN then put pIdx into gSlimeN
   put tBody into gSlimeB[pIdx]
   put tSpr into gSlimeSpr[pIdx]
   put pKind into gSlimeKind[pIdx]
   put pSpeed into gSlimeDir[pIdx]
   put pSpeed into gSlimeSpeed[pIdx]
   put pFlat into gSlimeFlat[pIdx]
   -- facing polarity (gotcha 26): most foes art faces RIGHT (flip false), but some
   -- sheets (the ground ladybug) face LEFT like the snail - pass pFaceFlip true to
   -- invert. The flying ladybug/bee/fish (pfAddMover) carry their own correction.
   put (pFaceFlip is true) into gSlimeFlip[pIdx]
   put pMinX into gSlimeMin[pIdx]
   put pMaxX into gSlimeMax[pIdx]
   put empty into gSlimeGoneAt[pIdx]
end pfMakeCritter

-- Phase E: a SNAKE - the SLITHER movement type. It joins the slime family as
-- kind "snake" (stompable on top, hurts on a side touch, like a slime) but
-- gets its own tick: it crawls the floor and AUTO-REVERSES at a pit edge or a
-- wall (pfTickSlimes "snake" case), so you place it without hand-tuning a band -
-- pMinX/pMaxX are just the outer safety bound. This is the LOW (snake.png)
-- crawler; the taller snakeLava/snakeSlime art rears up and is the rising
-- SERPENT (pfMakeSerpent). Spook-sheet art, so it SELF-GATES on gSpooksOK.
command pfMakeSnake pIdx, pX, pMinX, pMaxX, pTopY
   if gSpooksOK is not true then exit pfMakeSnake
   pfMakeCritter pIdx, "snake", pX, pMinX, pMaxX, pTopY, 46, "snake.png", "snakewalk", "snake_dead.png", 28, 24, "150,170,90", 3, "spooks"
end pfMakeSnake

-- A thwomp (falling-block trap) perched at pX. Walking beneath wakes it
-- (static -> dynamic) and it slams down. Only its UNDERSIDE is dangerous -
-- the head is a platform: hop on while it RESTS (static: a weight on a
-- chain is not the player's to drag or shove) and ride the slow
-- kinematic rise back UP to perch height. pFaced true = the Wave 3
-- CRUSHER look: it wears the block_idle/fall/rest FACES (the art that
-- was this machine's fallback all along) instead of the chained weight.
-- pTileFace (optional) overrides BOTH with a plain tiles sprite (e.g.
-- "block_green" for the grass-biome crusher rows) - a solid block that
-- drops, no mood-face swaps.
command pfMakeThwomp pIdx, pX, pFaced, pTileFace
   local tName, tBody
   put "pf_blockBody" & pIdx into tName
   create graphic tName
   set the style of it to "rectangle"
   set the rect of it to pX - 30, 170, pX + 30, 230
   set the filled of it to true
   set the backgroundColor of it to "120,120,135"
   set the visible of it to false
   put the long id of graphic tName into tBody
   b2kAddBox tBody, false                   -- starts STATIC (armed)
   put empty into gBlockSpr[pIdx]
   put empty into gBlockChainA[pIdx]
   put empty into gBlockChainB[pIdx]
   put false into gBlockFace[pIdx]
   if pTileFace is not empty and gAssetsOK is true and b2kSheetHasFrame("tiles", pTileFace) then
      -- a plain tile block (block_green for the green crusher rows): it
      -- drops and rises with no mood-face swap (gBlockFace stays false)
      b2kSpriteNew "tiles", pTileFace, pX, 200
      put the result into gBlockSpr[pIdx]
   else if pFaced is true and gAssetsOK is true and b2kSheetHasFrame("foes", "block_idle") then
      b2kSpriteNew "foes", "block_idle", pX, 200
      put the result into gBlockSpr[pIdx]
      put true into gBlockFace[pIdx]   -- pfTickThwomps swaps the moods
   else
      if gAssetsOK is true and b2kSheetHasFrame("tiles", "weight") \
            and b2kSheetHasFrame("tiles", "chain") then
         -- Wave 1: the REAL thwomp look - a weight on a chain. The chain
         -- tiles (44..172) reach the block's perch top (170) and STAY put
         -- while the weight falls; re-arming re-seats them under it
         -- (pfTickThwomps), defensive against any future sideways drift.
         b2kSpriteNew "tiles", "chain", pX, 76
         put the result into gBlockChainA[pIdx]
         b2kSpriteNew "tiles", "chain", pX, 140
         put the result into gBlockChainB[pIdx]
         b2kSpriteNew "tiles", "weight", pX, 200
         put the result into gBlockSpr[pIdx]
      else
         if gAssetsOK is true and b2kSheetHasFrame("foes", "block_idle") then
            b2kSpriteNew "foes", "block_idle", pX, 200
            put the result into gBlockSpr[pIdx]
            put true into gBlockFace[pIdx]   -- this art has state faces
         end if
      end if
   end if
   if gBlockSpr[pIdx] is not empty then b2kSpriteBind gBlockSpr[pIdx], tBody, 0, 0
   if gBlockSpr[pIdx] is empty then set the visible of graphic tName to true
   if the visible of graphic tName is true then b2kCamAdopt tBody
   if pIdx > gBlockN then put pIdx into gBlockN
   put tBody into gBlockB[pIdx]
   put pX into gBlockX[pIdx]   -- perch x cached: an armed block never moves
   put "armed" into gBlockState[pIdx]
   put 0 into gBlockT[pIdx]
end pfMakeThwomp

-- The checkpoint flag at pX: touch it once and respawns restart there
-- (the off flag hoists red). MULTI-CHECKPOINT SAFE: each flag carries its
-- OWN respawn x (uPfCheckX) and a one-shot guard (uPfCheckDone), so a level
-- may plant several and each banks/raises independently (the single gCheck*
-- globals only ever tracked ONE - three in L6 made all but the last dead).
command pfMakeCheckpoint pX
   local tRef
   put empty into gCheckSpr
   put pX into gCheckX
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "flag_off") then
      b2kSpriteNew "tiles", "flag_off", pX, 544 + kFlagPlantPx   -- plant the pole base on the floor (see kFlagPlantPx)
      put the result into tRef
      if tRef is not empty then
         set the uPfCheckFlag of tRef to true
         set the uPfCheckX of tRef to pX        -- THIS flag's own respawn x
         set the uPfCheckDone of tRef to false  -- raised + banked only on first touch
         put tRef into gCheckSpr
         b2kAddSensor tRef, "ball"
      end if
   end if
end pfMakeCheckpoint

-- =====================================================================
-- Wave 3 builders: the bestiary. Three of the six join the slime
-- FAMILY (same tables, same contact verdicts, same b2kFell cleanup) as
-- new KINDS - snail/shell, bat, mimic; the piranha and the ghost are
-- bodiless sprites with their own small ticks; the faced crusher is
-- pfMakeThwomp's pFaced flag. Spook art is OPTIONAL (gSpooksOK): the
-- snail and the crusher are native foes-sheet art and always build.
-- =====================================================================

-- A snail: patrols like a slime, but a stomp SHELLS it instead of
-- killing it - then any touch KICKS the shell into a slide that bowls
-- over every ground foe it reaches (the verdicts live in b2kContact).
command pfMakeSnail pIdx, pX, pMinX, pMaxX
   local tName, tBody, tSpr
   put "pf_slimeBody" & pIdx into tName
   create graphic tName
   set the style of it to "rectangle"
   set the rect of it to pX - 24, 544, pX + 24, 576
   set the filled of it to true
   set the backgroundColor of it to "210,170,90"
   set the visible of it to false
   put the long id of graphic tName into tBody
   b2kAddBox tBody
   b2kSetFixedRotation tBody, true
   b2kSetFriction tBody, 0.1
   put empty into tSpr
   if gAssetsOK is true and b2kSheetHasFrame("foes", "snail_walk_a") then
      b2kSpriteNew "foes", "snail_walk_a", pX, 560
      put the result into tSpr
      if tSpr is not empty then
         b2kSpriteBind tSpr, tBody, 0, -4
         b2kSpritePlay tSpr, "snailwalk"
      end if
   end if
   if tSpr is empty then set the visible of graphic tName to true
   if the visible of graphic tName is true then b2kCamAdopt tBody
   if pIdx > gSlimeN then put pIdx into gSlimeN
   put tBody into gSlimeB[pIdx]
   put tSpr into gSlimeSpr[pIdx]
   put "snail" into gSlimeKind[pIdx]
   put 60 into gSlimeDir[pIdx]
   put 60 into gSlimeSpeed[pIdx]
   put empty into gSlimeFlat[pIdx]   -- the switch picks snail_shell
   put true into gSlimeFlip[pIdx]    -- the snail sheet art faces LEFT
   put pMinX into gSlimeMin[pIdx]
   put pMaxX into gSlimeMax[pIdx]
   put empty into gSlimeGoneAt[pIdx]
   put 0 into gSlimeT[pIdx]
end pfMakeSnail

-- A bat: hangs STATIC under an overhang until the hero walks near,
-- then drops into a fast sine-bobbing patrol at head height
-- (dynamic, gravity scale 0 - a flying body, so stomps just work).
command pfMakeBat pIdx, pX, pHangY, pMinX, pMaxX
   local tName, tBody, tSpr
   if gSpooksOK is not true then exit pfMakeBat
   put "pf_slimeBody" & pIdx into tName
   create graphic tName
   set the style of it to "rectangle"
   set the rect of it to pX - 20, pHangY - 14, pX + 20, pHangY + 14
   set the filled of it to true
   set the backgroundColor of it to "90,70,120"
   set the visible of it to false
   put the long id of graphic tName into tBody
   b2kAddBox tBody, false           -- parked static: hanging
   b2kSetFixedRotation tBody, true
   b2kSetFriction tBody, 0.1
   put empty into tSpr
   b2kSpriteNew "spooks", "bat_hang.png", pX, pHangY
   put the result into tSpr
   if tSpr is not empty then b2kSpriteBind tSpr, tBody, 0, 0
   if tSpr is empty then
      set the visible of graphic tName to true
      b2kCamAdopt tBody
   end if
   if pIdx > gSlimeN then put pIdx into gSlimeN
   put tBody into gSlimeB[pIdx]
   put tSpr into gSlimeSpr[pIdx]
   put "bat" into gSlimeKind[pIdx]
   put 90 into gSlimeDir[pIdx]
   put 90 into gSlimeSpeed[pIdx]
   put empty into gSlimeFlat[pIdx]   -- the switch picks bat_hit.png
   put false into gSlimeFlip[pIdx]
   put pMinX into gSlimeMin[pIdx]
   put pMaxX into gSlimeMax[pIdx]
   put empty into gSlimeGoneAt[pIdx]
   put 0 into gSlimeT[pIdx]
end pfMakeBat

-- A mimic: a GRASS block sitting in the purple biome - wrong on
-- purpose, that is the tell - dead still until the hero comes close,
-- then it wakes and lunges in short hops.
command pfMakeMimic pIdx, pX
   local tName, tBody, tSpr
   if gSpooksOK is not true then exit pfMakeMimic
   put "pf_slimeBody" & pIdx into tName
   create graphic tName
   set the style of it to "rectangle"
   set the rect of it to pX - 28, 520, pX + 28, 576
   set the filled of it to true
   set the backgroundColor of it to "120,180,90"
   set the visible of it to false
   put the long id of graphic tName into tBody
   b2kAddBox tBody, false           -- parked static: just scenery... so far
   b2kSetFixedRotation tBody, true
   b2kSetFriction tBody, 0.4
   put empty into tSpr
   b2kSpriteNew "spooks", "grassBlock.png", pX, 545
   put the result into tSpr
   if tSpr is not empty then b2kSpriteBind tSpr, tBody, 0, -3
   if tSpr is empty then
      set the visible of graphic tName to true
      b2kCamAdopt tBody
   end if
   if pIdx > gSlimeN then put pIdx into gSlimeN
   put tBody into gSlimeB[pIdx]
   put tSpr into gSlimeSpr[pIdx]
   put "mimic" into gSlimeKind[pIdx]
   put 0 into gSlimeDir[pIdx]
   put 0 into gSlimeSpeed[pIdx]
   put empty into gSlimeFlat[pIdx]   -- the switch picks grassBlock_hit.png
   put false into gSlimeFlip[pIdx]
   put pX into gSlimeMin[pIdx]
   put pX into gSlimeMax[pIdx]
   put empty into gSlimeGoneAt[pIdx]
   put 0 into gSlimeT[pIdx]
end pfMakeMimic

-- Wave 6 (bestiary II): a FROG - a grounded HOPPER (the lunger). It rests in
-- a crouch, then leaps toward the hero whenever it has settled and he is within
-- range. It JOINS the slime family (a new "frog" kind in pfTickSlimes), so the
-- existing stomp verdict, knockback and b2kFell cleanup carry it for free:
-- stomp it from above, its side touch hurts. Native foes art (so it is NOT
-- optional). pMinX/pMaxX bound its hops so it can never spring into a pit.
command pfMakeFrog pIdx, pX, pMinX, pMaxX, pTopY
   local tName, tBody, tSpr
   put "pf_slimeBody" & pIdx into tName
   create graphic tName
   set the style of it to "rectangle"
   set the rect of it to pX - 22, pTopY - 36, pX + 22, pTopY
   set the filled of it to true
   set the backgroundColor of it to "120,175,75"
   set the visible of it to false
   put the long id of graphic tName into tBody
   b2kAddBox tBody
   b2kSetFixedRotation tBody, true
   b2kSetFriction tBody, 0.3
   put empty into tSpr
   if gAssetsOK is true and b2kSheetHasFrame("foes", "frog_idle") then
      b2kSpriteNew "foes", "frog_idle", pX, pTopY - 32
      put the result into tSpr
      if tSpr is not empty then b2kSpriteBind tSpr, tBody, 0, -14
   end if
   if tSpr is empty then set the visible of graphic tName to true
   if the visible of graphic tName is true then b2kCamAdopt tBody
   if pIdx > gSlimeN then put pIdx into gSlimeN
   put tBody into gSlimeB[pIdx]
   put tSpr into gSlimeSpr[pIdx]
   put "frog" into gSlimeKind[pIdx]
   put 0 into gSlimeDir[pIdx]
   put 0 into gSlimeSpeed[pIdx]
   put empty into gSlimeFlat[pIdx]    -- no squashed frame: it drops and fades
   put true into gSlimeFlip[pIdx]     -- the frog sheet art faces LEFT (like the snail, gotcha 26)
   put pMinX into gSlimeMin[pIdx]
   put pMaxX into gSlimeMax[pIdx]
   put empty into gSlimeGoneAt[pIdx]
   put the milliseconds + 600 + random(500) into gSlimeT[pIdx]
   put false into gFrogAir[pIdx]
end pfMakeFrog

-- A BLOCK SLIME (asset-expansion Phase B): a hopping CUBE that arcs back and
-- forth across its band (slime_block_* foes art, previously unused). A
-- slime-family kind "block" - stompable via the CLASSIC path (a stomp squashes
-- it to slime_block_rest, a side touch knocks back), so it needs no b2kContact
-- case. The _jump frame shows on the hop, the squish idle (walk_a/b) when
-- settled. Reuses gFrogAir as its airborne flag (per-index, like the frog).
command pfMakeBlockSlime pIdx, pX, pMinX, pMaxX, pTopY
   local tName, tBody, tSpr
   put "pf_slimeBody" & pIdx into tName
   create graphic tName
   set the style of it to "rectangle"
   set the rect of it to pX - 24, pTopY - 44, pX + 24, pTopY
   set the filled of it to true
   set the backgroundColor of it to "150,120,200"   -- a purple cube (no-art fallback)
   set the visible of it to false
   put the long id of graphic tName into tBody
   b2kAddBox tBody
   b2kSetFixedRotation tBody, true
   b2kSetFriction tBody, 0.4
   put empty into tSpr
   if gAssetsOK is true and b2kSheetHasFrame("foes", "slime_block_rest") then
      b2kSpriteNew "foes", "slime_block_rest", pX, pTopY - 28
      put the result into tSpr
      if tSpr is not empty then
         b2kSpriteBind tSpr, tBody, 0, -8
         b2kSpritePlay tSpr, "blockidle"
      end if
   end if
   if tSpr is empty then set the visible of graphic tName to true
   if the visible of graphic tName is true then b2kCamAdopt tBody
   if pIdx > gSlimeN then put pIdx into gSlimeN
   put tBody into gSlimeB[pIdx]
   put tSpr into gSlimeSpr[pIdx]
   put "block" into gSlimeKind[pIdx]
   put 100 into gSlimeSpeed[pIdx]
   put 100 into gSlimeDir[pIdx]
   put "slime_block_rest" into gSlimeFlat[pIdx]   -- the defeat pose (the only static cube frame)
   put false into gSlimeFlip[pIdx]
   put pMinX into gSlimeMin[pIdx]
   put pMaxX into gSlimeMax[pIdx]
   put empty into gSlimeGoneAt[pIdx]
   put the milliseconds + 500 + random(400) into gSlimeT[pIdx]
   put false into gFrogAir[pIdx]
end pfMakeBlockSlime

-- A CONVEYOR BELT (asset-expansion Phase B): a polled surface ZONE that carries
-- the GROUNDED hero along pDir (+1 right, -1 left) ON TOP of his own walking, so
-- you can power against it. No body - the level's ground slab still owns the
-- collision; this only adds vx in pfTickConveyor. The belt art is the (single-
-- frame, unanimated) conveyor tile, flipped to face pDir. Per the plan this is
-- the example-side polled version (no Kit "surface velocity" feature).
command pfMakeConveyor pL, pR, pDir
   local tX
   add 1 to gConvN
   put pL into gConvL[gConvN]
   put pR into gConvR[gConvN]
   put 576 into gConvY[gConvN]
   put pDir into gConvDir[gConvN]
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "conveyor") then
      put pL into tX
      repeat while tX <= pR - 64
         pfTile "conveyor", tX, 576, (pDir < 0)   -- flip the tread to face pDir; the single frame has no scroll animation, so the flip is the only direction cue (OXT-verify it reads)
         add 64 to tX
      end repeat
   end if
end pfMakeConveyor

-- Carry the grounded hero along any belt he stands on (his input vx PLUS the
-- belt). One compare when no belts exist; uses the per-frame hero snapshot (no
-- extra position FFI). b2kSetVelocity wakes the hero - already awake under the
-- controller, so it is free. The y test (hero at/below the belt line) keeps a
-- hero on a HIGHER platform over the same x off the belt.
command pfTickConveyor
   local i, tV
   if gConvN is 0 or gConvN is empty then exit pfTickConveyor
   if not b2kPlayerOnGround() then exit pfTickConveyor
   set the itemDelimiter to comma
   repeat with i = 1 to gConvN
      if gHeroPX >= gConvL[i] and gHeroPX <= gConvR[i] and gHeroPY > gConvY[i] - 80 then
         put b2kVelocity(gHero) into tV   -- the controller's input-driven vx,vy this frame
         b2kSetVelocity gHero, (item 1 of tV) + gConvDir[i] * 130, item 2 of tV
         exit repeat   -- one belt at a time
      end if
   end repeat
end pfTickConveyor

-- A piranha burrow at pX: the plant is a bodiless sprite pfTickPlants
-- raises and sinks; its dark mouth-hole is drawn by the SCENE (so it
-- layers under every later sprite). Unkillable, like the saws.
command pfMakePlant pIdx, pX
   local tSpr
   if gSpooksOK is not true then exit pfMakePlant
   b2kSpriteNew "spooks", "piranha.png", pX, 606
   put the result into tSpr
   if tSpr is empty then exit pfMakePlant
   set the visible of tSpr to false       -- starts swallowed
   if pIdx > gPlantN then put pIdx into gPlantN
   put tSpr into gPlantSpr[pIdx]
   put pX into gPlantX[pIdx]
   put "down" into gPlantState[pIdx]
   put the milliseconds + 800 + random(600) into gPlantT[pIdx]
end pfMakePlant

-- THE ghost (one per level): bodiless, drifts through terrain, chases
-- only while the hero faces away - eye contact freezes it shy.
command pfMakeGhost pX, pY
   local tSpr
   if gSpooksOK is not true then exit pfMakeGhost
   b2kSpriteNew "spooks", "ghost_normal.png", pX, pY
   put the result into tSpr
   if tSpr is empty then exit pfMakeGhost
   put tSpr into gGhostSpr
   put pX into gGhostX
   put pY into gGhostY
   put true into gGhostShy
end pfMakeGhost

-- Wave 6 (bestiary II): a BARNACLE - a stationary clam (the lurker). It sits
-- SHUT until the hero nears, TELEGRAPHS by opening, then SNAPS a brief
-- hurt-window and cools down. Bodiless (the piranha's timed cycle held still),
-- unkillable like the saws - you time it or jump it. pY is the surface it sits
-- on (place at 544 to rest a clam on a 576 floor: the art opens upward). Native
-- foes art; the no-art fallback is a static rect that still snaps (gBarnSpr
-- stays empty there, so the tick skips the frame swaps, like the slimes).
command pfMakeBarnacle pIdx, pX, pY
   local tSpr
   put empty into tSpr
   if gAssetsOK is true and b2kSheetHasFrame("foes", "barnacle_attack_rest") then
      b2kSpriteNew "foes", "barnacle_attack_rest", pX, pY
      put the result into tSpr
   end if
   if tSpr is empty then
      create graphic ("pf_barn" & pIdx)
      set the style of it to "rectangle"
      set the rect of it to pX - 22, pY - 10, pX + 22, pY + 32
      set the filled of it to true
      set the backgroundColor of it to "150,95,120"
      b2kCamAdopt the long id of graphic ("pf_barn" & pIdx)
   end if
   if pIdx > gBarnN then put pIdx into gBarnN
   put tSpr into gBarnSpr[pIdx]
   put pX into gBarnX[pIdx]
   put pY into gBarnY[pIdx]
   put "shut" into gBarnState[pIdx]
   put the milliseconds + 600 into gBarnT[pIdx]
end pfMakeBarnacle

-- Wave 6 (bestiary II): a SPIDER - a ceiling-crawler under an overhang. It
-- creeps along the bar, and when the hero passes BENEATH it DROPS on its
-- thread, hurts on contact, then hauls back up and resumes the crawl. Bodiless
-- (the ghost/mover pattern - b2kSpriteMoveTo is scroll-correct, no physics to
-- fight the controller). Family C art, so it is OPTIONAL: a missing spooks
-- sheet skips it silently (gotcha 25), and the SCENE only draws its overhang
-- when gSpooksOK, so the level stays completable without it.
command pfMakeSpider pIdx, pX, pMinX, pMaxX, pHangY
   local tSpr
   if gSpooksOK is not true then exit pfMakeSpider
   b2kSpriteNew "spooks", "spider.png", pX, pHangY
   put the result into tSpr
   if tSpr is empty then exit pfMakeSpider
   b2kSpritePlay tSpr, "spiderwalk"
   if pIdx > gSpiderN then put pIdx into gSpiderN
   put tSpr into gSpiderSpr[pIdx]
   put pX into gSpiderX[pIdx]
   put pHangY into gSpiderY[pIdx]
   put pHangY into gSpiderHangY[pIdx]
   put pHangY + 174 into gSpiderDropTo[pIdx]   -- drops to ~head height, then climbs
   put pMinX into gSpiderMinX[pIdx]
   put pMaxX into gSpiderMaxX[pIdx]
   put 60 into gSpiderDir[pIdx]
   put "patrol" into gSpiderState[pIdx]
end pfMakeSpider

-- A lava strip ON the path (the haunted ground hazard): lava art over
-- a knockback sensor that rises above the floor line, so wading in -
-- not just falling in - burns. The Wave 2 split holds: surface
-- hazards knock back; only pits respawn.
command pfMakeLava pL, pR, pSensorTop
   local tRef, tX
   -- the hurt sensor's TOP: y548 (default) sits ABOVE the floor so it catches a
   -- walker crossing surface lava (L2's grinder bay). A BRIDGED lava PIT (L4)
   -- passes a LOWER top so a hero on the bank-level bridge is clear, but a fall
   -- through a collapsed plank still drops into it.
   if pSensorTop is empty then put 548 into pSensorTop
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "lava_top") then
      put pL into tX
      repeat while tX <= pR - 64
         pfTile "lava_top", tX, 576
         add 64 to tX
      end repeat
   else
      create graphic ("pf_lava" & pL)
      set the style of it to "rectangle"
      set the rect of it to pL, 600, pR, 640
      set the filled of it to true
      set the backgroundColor of it to "235,120,40"
      b2kCamAdopt the long id of graphic ("pf_lava" & pL)
   end if
   create graphic ("pf_lavasens" & pL)
   set the style of it to "rectangle"
   set the rect of it to pL + 6, pSensorTop, pR - 6, 640
   set the visible of it to false
   put the long id of graphic ("pf_lavasens" & pL) into tRef
   set the uPfHazardFlag of tRef to true
   b2kAddSensor tRef, "box"
end pfMakeLava

-- Phase E: a TOXIC GOO POOL - the slime-biome twin of pfMakeLava and the home of
-- the snakeSlime SERPENT (L6's cavern). A green goo rect filling the pit (the y576
-- row, so it occludes a serpent's submerged lower body exactly as the lava tiles
-- do) over a knockback hurt sensor, plus a bright surface line. Like the lava,
-- wading in knocks back (pfOuch via uPfHazardFlag) - it is not a respawn pit. A
-- plain rect (the tiles sheet has no goo frame), so no gAssetsOK branch is needed.
-- pSensorTop defaults to y596 (a hero on the bank is clear, a slip into the goo
-- burns). Create the serpent BEFORE this so the goo draws OVER its lower body.
command pfMakeSlimePool pL, pR, pSensorTop
   local tRef
   if pSensorTop is empty then put 596 into pSensorTop
   create graphic ("pf_goo" & pL)
   set the style of it to "rectangle"
   set the rect of it to pL, 576, pR, 640
   set the filled of it to true
   set the backgroundColor of it to "96,176,72"      -- toxic green goo
   b2kCamAdopt the long id of graphic ("pf_goo" & pL)
   create graphic ("pf_gooSurf" & pL)
   set the style of it to "line"
   set the points of it to pL & comma & 578 & cr & pR & comma & 578
   set the lineSize of it to 3
   set the foregroundColor of it to "168,228,128"    -- a brighter goo surface line
   b2kCamAdopt the long id of graphic ("pf_gooSurf" & pL)
   create graphic ("pf_goosens" & pL)
   set the style of it to "rectangle"
   set the rect of it to pL + 6, pSensorTop, pR - 6, 640
   set the visible of it to false
   put the long id of graphic ("pf_goosens" & pL) into tRef
   set the uPfHazardFlag of tRef to true
   b2kAddSensor tRef, "box"
end pfMakeSlimePool

-- Wave 4: a SWIM basin. Registers the Kit swim zone (the controller polls
-- it -- buoyant gravity, capped sink, UP/DOWN swim, SPACE strokes up) and
-- draws the water as a blue rect with a bright surface line. The caller
-- places the banks + floor slabs: the 640-tall world clamps the camera at
-- y640, so a swim pool cannot be a pit BELOW the ground -- it is a RAISED
-- basin between two banks (a hilltop pool). Coins layer on top (cast).
command pfMakeWater pL, pTop, pR, pBot
   b2kPlayerAddWater pL, pTop, pR, pBot
   create graphic ("pf_water" & pL)
   set the style of it to "rectangle"
   set the rect of it to pL, pTop, pR, pBot
   set the filled of it to true
   set the backgroundColor of it to "92,150,205"
   set the foregroundColor of it to "60,110,170"
   b2kCamAdopt the long id of graphic ("pf_water" & pL)
   create graphic ("pf_surf" & pL)
   set the style of it to "line"
   set the points of it to pL & comma & pTop & cr & pR & comma & pTop
   set the lineSize of it to 3
   set the foregroundColor of it to "165,210,245"
   b2kCamAdopt the long id of graphic ("pf_surf" & pL)
end pfMakeWater

-- =====================================================================
-- Wave 1 builders: springboard, bonk row, lever, key + locked door.
-- The pattern everywhere: an invisible static HOST graphic (named pf_*,
-- wiped with the stage) carries the physics; an atlas sprite carries the
-- face. Placement comes from MEASURED art (all cells 64px; spring alpha
-- tops at cell y+20, switch at y+24, spike tips at y+30).
-- =====================================================================

-- A springboard at centre pCX on the main ground line. It is solid (you
-- can land on it), but pfTickSpring relaunches you the moment your feet
-- rest in its band - a springboard is not a place to stand.
command pfMakeSpring pCX
   create graphic "pf_springHost"
   set the style of it to "rectangle"
   set the rect of it to pCX - 26, 534, pCX + 26, 576
   set the visible of it to false
   b2kAddStatic the long id of graphic "pf_springHost"
   b2kSpriteNew "tiles", "spring", pCX, 544
   put the result into gSpringSpr
   put pCX into gSpringX
end pfMakeSpring

-- One bonk tile (centre pCX; the row hangs at y 384..448, low enough to
-- headbutt from the ground, too high to stand on from it). "box" pays a
-- coin once and shows its empty face; "brick" shatters into debris.
command pfMakeBonk pKind, pCX
   local tName, tFrame
   add 1 to gBonkN
   put "pf_bonk" & gBonkN into tName
   create graphic tName
   set the style of it to "rectangle"
   set the rect of it to pCX - 32, 384, pCX + 32, 448
   set the visible of it to false
   b2kAddStatic the long id of graphic tName
   put the long id of graphic tName into gBonkHost[gBonkN]
   if pKind is "box" then
      put "block_coin" into tFrame
      add 1 to gCoinsTotal   -- a ?-box pays one coin when headbutted
      add 1 to gScoreTotal   -- ...worth 1 toward the bonus score (matches pfGainCoin's default)
   else
      put "bricks_brown" into tFrame
      -- PRE-WARM the debris frame: icon slicing is lazy and costs
      -- ~250ms per new frame - paid here at build, never as a mid-game
      -- hitch on the first smash (which also made the debris seem to
      -- pop in far from the brick: physics had outrun the freeze)
      b2kSheetEnsureIcon "tiles", "brick_brown"
   end if
   b2kSpriteNew "tiles", tFrame, pCX, 416
   put the result into gBonkSpr[gBonkN]
   put pKind into gBonkKind[gBonkN]
   put false into gBonkUsed[gBonkN]
   put pCX into gBonkX[gBonkN]
end pfMakeBonk

-- The saw power lever (centre pCX on the ground line). STANDING at it
-- toggles the SWEEPING saw (pfTickLever - running past never flips it):
-- powered down the saw stops spinning, fades and stops hurting - the
-- timid player's way past the gauntlet.
command pfMakeLever pCX
   b2kSpriteNew "tiles", "lever_right", pCX, 544
   put the result into gLeverSpr
   put pCX into gLeverX
end pfMakeLever

-- The key (a one-shot SENSOR at pKeyX,pKeyY - place it at walking
-- height somewhere dangerous) and the WALLED DOOR at pWallX: a stone
-- curtain from the ceiling to the door's lintel with a locked
-- two-tile door at its foot, in pColour (yellow/red/green/blue art
-- exists). The wall exists because a free-standing column was
-- BYPASSABLE - a thwomp-ride arc sailed clean over it and the flag
-- ended the game with the door never used. Everything past the wall
-- is reachable ONLY through the door: the gate is structural, and the
-- level reads "find the key" at a glance. The unlock is a proximity
-- POLL; only the door's 128px passage ever clears - the wall stays.
-- A coloured KEY + the locked DOOR it opens. Now MULTI-INSTANCE (Phase C slice
-- 3): each call appends door #gDoorN, so a level may plant several pairs (the
-- key tags itself with uPfKeyWord = its colour). The key is a sensor pickup,
-- the door a solid stone wall + a panel host that drops away once you reach it
-- carrying the matching key (pfTickDoors). Single-door levels (L2/L3) just plant
-- one and behave exactly as before.
command pfMakeKeyDoor pKeyX, pKeyY, pWallX, pColour
   local tRef, tY, tCX, tI, tWall, tHost
   add 1 to gDoorN
   put gDoorN into tI
   put pWallX + 32 into tCX
   put tCX into gDoorX[tI]
   put pColour into gDoorWord[tI]
   put false into gDoorOpen[tI]
   put ("pf_doorWall" & tI) into tWall
   put ("pf_doorHost" & tI) into tHost
   put tHost into gDoorHostNm[tI]
   b2kSpriteNew "tiles", "key_" & pColour, pKeyX, pKeyY
   put the result into tRef
   if tRef is not empty then
      set the uPfKeyFlag of tRef to true
      set the uPfKeyWord of tRef to pColour   -- which coloured door this key opens
      b2kAddSensor tRef, "ball"
   end if
   create graphic tWall
   set the style of it to "rectangle"
   set the rect of it to pWallX, 0, pWallX + 64, 448
   set the visible of it to false
   b2kAddStatic the long id of graphic tWall
   put 0 into tY
   repeat while tY <= 320
      pfTile "terrain_stone_block_center", pWallX, tY
      add 64 to tY
   end repeat
   b2kSpriteNew "tiles", "lock_" & pColour, tCX, 416
   put the result into gLockSpr[tI]
   create graphic tHost
   set the style of it to "rectangle"
   set the rect of it to pWallX, 448, pWallX + 64, 576
   set the visible of it to false
   b2kAddStatic the long id of graphic tHost
   b2kSpriteNew "tiles", "door_closed_top", tCX, 480
   put the result into gDoorSprT[tI]
   b2kSpriteNew "tiles", "door_closed", tCX, 544
   put the result into gDoorSprB[tI]
end pfMakeKeyDoor

-- The PLAYABLE box, belt AND braces: thick slabs (the solver's clean
-- stop) PLUS two-sided wall segments at the exact edges (a second
-- fence even for a creeping capsule), the segment ceiling, the kill
-- floor, and the camera clamped to the same box. One helper, every
-- level - boundary bugs get fixed in exactly one place.
-- pLeft/pRight are the CONTENT edges (just past the spawn, just past the
-- flag), NOT the raw world width: the walls hug the level so there is no
-- empty walk-off room before the start or after the goal.
command pfBounds pLeft, pRight
   put pLeft into gEdgeL
   put pRight into gEdgeR
   put pRight into gLevelW   -- kept in step for any legacy reader
   -- ON-CARD positive coords ONLY. OXT can refuse to collide a static slab
   -- whose rect sits far off the card (negative x/y) - which is why the old
   -- -164..-600 wall let the hero walk clean through. The left wall runs from
   -- x 0 to the edge; the right from the edge out; both floor-to-ceiling
   -- (y 0..640). The ceiling + kill floor close the box top and bottom.
   pfSlab "pf_wallL", 0, 0, pLeft, 640
   pfSlab "pf_wallR", pRight, 0, pRight + 256, 640
   b2kWall pLeft, 0, pLeft, 640
   b2kWall pRight, 0, pRight, 640
   b2kWall pLeft, 0, pRight, 0
   b2kKillFloor 820
   -- the camera clamps to the SAME tight box, so the INVISIBLE side slabs
   -- stop you right at the content and the view never scrolls out onto bare
   -- floor past either end (no visible wall needed - the tight stop + clamp do it)
   b2kCamBounds pLeft, 0, pRight, 640
   put 320 into gCamTopY    -- horizontal: the camera Y is pinned (the world is exactly one viewport tall)
   put 320 into gCamBotY
   put 780 into gKillPlaneY
end pfBounds

-- Dress a vertical level's side MARGIN as a solid stone WALL so the gap beside
-- the (narrower-than-viewport) play column reads as the keep's wall, not dead
-- backdrop. pX1..pX2 is the margin span in world px, pTop..pBottom its height;
-- it is stone-tiled (terrain_stone_block_center, matching the floor/ledges) at
-- 64px, lowest layer so torches/coins/ledges draw in front. No stone art: the
-- flat collider slab pSlab is made visible (and camera-adopted) as the fallback.
command pfDressWall pSlab, pX1, pX2, pTop, pBottom
   local tX, tY
   if pX2 - pX1 < 1 then exit pfDressWall                  -- a zero-width margin (column == viewport): nothing to fill
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_stone_block_center") then
      put pX1 into tX
      repeat while tX <= pX2 - 64
         put pTop into tY
         repeat while tY <= pBottom - 64
            pfTile "terrain_stone_block_center", tX, tY
            add 64 to tY
         end repeat
         add 64 to tX
      end repeat
   else if there is a graphic pSlab then
      set the backgroundColor of graphic pSlab to "70,73,86"   -- lit stone, lighter than the backdrop
      set the visible of graphic pSlab to true
      b2kCamAdopt the long id of graphic pSlab
   end if
end pfDressWall

-- VERTICAL bounds (the CLIMBING levels): a TALL world (pTop..pBottom), walls
-- around the full box + a ceiling, and the camera scrolls VERTICALLY between
-- gCamTopY..gCamBotY as the hero climbs. The kill plane sits well BELOW the
-- bottom floor: the climb is contained (a missed jump drops you onto a lower
-- platform or the floor, never off the world), so there is no respawn-on-fall.
-- Coords stay POSITIVE (the off-card collision worry was NEGATIVE coords; a
-- tall positive world collides the same way the horizontal walls do).
command pfBoundsV pLeft, pRight, pTop, pBottom
   local tCx
   put pLeft into gEdgeL
   put pRight into gEdgeR
   put pRight into gLevelW
   pfSlab "pf_wallL", 0, pTop, pLeft, pBottom        -- POSITIVE coords only (x 0..pLeft), like pfBounds
   pfSlab "pf_wallR", pRight, pTop, pRight + 256, pBottom
   b2kWall pLeft, pTop, pLeft, pBottom
   b2kWall pRight, pTop, pRight, pBottom
   b2kWall pLeft, pTop, pRight, pTop       -- the ceiling
   b2kKillFloor pBottom + 300              -- below the floor slab; the climb never reaches it
   -- the play column (pLeft..pRight) is NARROWER than the 1024 viewport, so the
   -- camera's X bounds are a viewport-wide range CENTRED on the column (a bound
   -- of just pLeft..pRight would left-align the tower with dead space on the
   -- right). The leftover margin EACH side is then DRESSED as the keep's stone
   -- side-walls (the collider slabs made visible / stone-tiled) so the shaft
   -- reads enclosed, edge to edge - no dead backdrop. The Y bounds stay the
   -- full world height (that is what the vertical scroll rides).
   put (pLeft + pRight) / 2 into tCx
   b2kCamBounds tCx - 512, pTop, tCx + 512, pBottom
   pfDressWall "pf_wallL", tCx - 512, pLeft, pTop, pBottom      -- fill the LEFT margin
   pfDressWall "pf_wallR", pRight, tCx + 512, pTop, pBottom     -- fill the RIGHT margin
   put pTop + 320 into gCamTopY            -- a 640-tall viewport sliding inside the tall world
   put pBottom - 320 into gCamBotY
   put pBottom + 300 into gKillPlaneY      -- the explicit kill check is effectively off (contained)
end pfBoundsV

-- The button-and-gate machine: a polled pressure plate at pPlateX
-- (pfTickGate reads gPlateX) drives a kinematic gate whose left edge
-- is pGateL. The gateway coin is made FIRST so the closed gate hides
-- it. The plate is a pure region - pressed = b2kOverlapMoving poll.
command pfMakeGate pPlateX, pGateL
   local tCX
   put pGateL + 32 into tCX
   pfMakeCoin tCX, 540
   put pPlateX into gPlateX
   create graphic "pf_plate"
   set the style of it to "rectangle"
   set the rect of it to pPlateX - 28, 560, pPlateX + 28, 576
   set the filled of it to true
   set the backgroundColor of it to "220,180,60"
   b2kCamAdopt the long id of graphic "pf_plate"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "switch_yellow") then
      set the visible of graphic "pf_plate" to false
      b2kSpriteNew "tiles", "switch_yellow", pPlateX, 544
      put the result into gPlateSpr
   end if
   create graphic "pf_gate"
   set the style of it to "rectangle"
   set the rect of it to pGateL, 448, pGateL + 64, 576
   set the filled of it to true
   set the backgroundColor of it to "190,70,70"
   put the long id of graphic "pf_gate" into gGate
   b2kAddBox gGate
   b2kSetKinematic gGate
   put empty into gGateSprA
   put empty into gGateSprB
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "block_red") then
      set the visible of graphic "pf_gate" to false
      b2kSpriteNew "tiles", "block_red", tCX, 480
      put the result into gGateSprA
      if gGateSprA is not empty then b2kSpriteBind gGateSprA, gGate, 0, -32
      b2kSpriteNew "tiles", "block_red", tCX, 544
      put the result into gGateSprB
      if gGateSprB is not empty then
         b2kSpriteBind gGateSprB, gGate, 0, 32
      end if
   else
      b2kCamAdopt gGate
   end if
end pfMakeGate

-- A LATCHING SWITCH + the coloured GATE it opens (Phase C slice 3, part 2): step
-- on the switch (switch_<colour>) ONCE and the kinematic gate (block_<colour> at
-- pGateL) rises out of the way FOR GOOD - unlike pfMakeGate's momentary pad. A
-- puzzle element: the switch can sit off the direct line so you must find it.
-- pSwitchY is the switch's surface (default the ground at 448 of a cloud / 544 of
-- a floor); the poll band sits just above it. Multi-instance (own table).
command pfMakeSwitchGate pSwitchX, pColour, pGateL, pSwitchY
   local tI, tCX
   if pSwitchY is empty then put 448 into pSwitchY
   add 1 to gSwN
   put gSwN into tI
   put pGateL + 32 into tCX
   put pSwitchX into gSwX[tI]
   put pColour into gSwWord[tI]
   put false into gSwOpen[tI]
   put false into gSwDone[tI]
   put empty into gSwGateVel[tI]
   -- the SWITCH plate, flush on its surface
   create graphic ("pf_swPlate" & tI)
   set the style of it to "rectangle"
   set the rect of it to pSwitchX - 28, pSwitchY - 16, pSwitchX + 28, pSwitchY
   set the filled of it to true
   set the backgroundColor of it to "120,124,150"
   b2kCamAdopt the long id of graphic ("pf_swPlate" & tI)
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "switch_" & pColour) then
      set the visible of graphic ("pf_swPlate" & tI) to false
      b2kSpriteNew "tiles", "switch_" & pColour, pSwitchX, pSwitchY - 28
      put the result into gSwSpr[tI]
   end if
   -- the GATE it opens: a kinematic barrier, raised (closed) until pressed
   create graphic ("pf_swGate" & tI)
   set the style of it to "rectangle"
   set the rect of it to pGateL, 448, pGateL + 64, 576
   set the filled of it to true
   set the backgroundColor of it to "120,124,150"
   put the long id of graphic ("pf_swGate" & tI) into gSwGate[tI]
   b2kAddBox gSwGate[tI]
   b2kSetKinematic gSwGate[tI]
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "block_" & pColour) then
      set the visible of graphic ("pf_swGate" & tI) to false
      b2kSpriteNew "tiles", "block_" & pColour, tCX, 480
      put the result into gSwGateSprA[tI]
      if gSwGateSprA[tI] is not empty then b2kSpriteBind gSwGateSprA[tI], gSwGate[tI], 0, -32
      b2kSpriteNew "tiles", "block_" & pColour, tCX, 544
      put the result into gSwGateSprB[tI]
      if gSwGateSprB[tI] is not empty then
         b2kSpriteBind gSwGateSprB[tI], gSwGate[tI], 0, 32
      end if
   else
      b2kCamAdopt gSwGate[tI]
   end if
end pfMakeSwitchGate

-- A spike pit between pL and pR (the level's ground slabs leave the
-- gap). Spike alpha is the BOTTOM 34px of the cell (measured), so
-- cells at y=576 put the tips at 606, base flush with the floor; the
-- hurt sensor (592+) fires before the art is even reached.
command pfMakeSpikes pL, pR
   local tRef, tX
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "spikes") then
      put pL into tX
      repeat while tX <= pR - 64
         pfTile "spikes", tX, 546   -- HORIZONTAL alignment: pfTile treats (x,y) as the tile's TOP-LEFT (it centres at x+32, like all the ground tiling), so the row must use top-lefts pL, pL+64, ... pR-64 to land FLUSH from pL to pR. The old pL+32..pR-32 range shifted every spike 32px RIGHT - a bare gap at the LEFT pit edge and the last spike OVERHANGING the ground on the RIGHT (the reported misalignment). VERTICAL: the spike pixels are the bottom 34px of the 64px frame, so y546 puts the tips at the ground line (576).
         add 64 to tX
      end repeat
   else
      create graphic ("pf_spikes" & pL)
      set the style of it to "rectangle"
      set the rect of it to pL, 576, pR, 612
      set the filled of it to true
      set the backgroundColor of it to "200,60,60"
      b2kCamAdopt the long id of graphic ("pf_spikes" & pL)
   end if
   create graphic ("pf_spikesens" & pL)
   set the style of it to "rectangle"
   set the rect of it to pL, 592, pR, 644
   set the visible of it to false
   put the long id of graphic ("pf_spikesens" & pL) into tRef
   set the uPfHazardFlag of tRef to true
   b2kAddSensor tRef, "box"
end pfMakeSpikes

-- The goal flag: BLUE while coins remain, GOLD (pfGainCoin) when the
-- level is sweepable - touch it then to clear the level (or win, on
-- level four).
command pfMakeGoal pX, pY
   local tRef
   add kFlagPlantPx to pY   -- plant the flag base on its surface (see kFlagPlantPx); shifts both the sprite and the no-art fallback
   put empty into tRef
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "flag_blue_a") then
      b2kSpriteNew "tiles", "flag_blue_a", pX, pY
      put the result into tRef
      if tRef is not empty then
         set the uPfGoalFlag of tRef to true
         b2kSpritePlay tRef, "wave"
         b2kAddSensor tRef, "ball"
         put tRef into gGoalSpr
      end if
   end if
   if tRef is empty then
      create graphic "pf_flag"
      set the style of it to "rectangle"
      set the rect of it to pX - 16, pY - 32, pX + 16, pY + 32
      set the filled of it to true
      set the backgroundColor of it to "70,110,230"
      put the long id of graphic "pf_flag" into tRef
      set the uPfGoalFlag of tRef to true
      b2kCamAdopt tRef
      b2kAddSensor tRef, "box"
   end if
end pfMakeGoal

-- =====================================================================
-- The showcase mechanisms (the kit's JOINT + dynamics subsystems, which
-- the demo had never touched). All four are HAZARDS the player TIMES or
-- AVOIDS - never rides - so none needs the platform-carry the controller
-- gains in a later wave. Verdicts are POLLED geometry (the doctrine), so
-- a post-step contact read can never be outrun. Bodies clean up with the
-- world (b2kTeardown) and the spawned ones with b2kClear.
-- =====================================================================

-- A sagging ROPE BRIDGE: pPlanks dynamic plank bodies hinged end-to-end,
-- the first and last pinned to the world at the posts (pL / pR), so the
-- span dips under the hero's weight and springs back. Spawned boxes are
-- camera-grouped and rotate as polygons, so each plank tilts true; the
-- Kit syncs them - no per-frame tick. The hero WALKS across (a moving
-- body needs no carry), so the controller's vx-assert never fights it.
-- Hang it over a real gap: dawdle and you sag, and a slip is a fall.
command pfMakeBridge pL, pR, pY, pPlanks
   local i, tPW, tCx, tSeam, tRef, tPrev
   put (pR - pL) / pPlanks into tPW
   put empty into tPrev
   repeat with i = 1 to pPlanks
      put pL + (i - 0.5) * tPW into tCx
      b2kSpawnBox tCx, pY, round(tPW) - 2, 14, "150,112,62"
      put the result into tRef
      if tRef is empty then next repeat
      b2kSetDensity tRef, 2.2             -- heavy enough to feel like a deck
      b2kSetFriction tRef, 0.9
      put pL + (i - 1) * tPW into tSeam
      if tPrev is empty then
         b2kHinge tRef, empty, pL, pY     -- pin the near post
      else
         b2kHinge tPrev, tRef, tSeam, pY  -- the chain seam between planks
      end if
      put tRef into tPrev
   end repeat
   if tPrev is not empty then b2kHinge tPrev, empty, pR, pY   -- the far post
end pfMakeBridge

-- Phase E: a rearing SERPENT - a tall snake that rises out of a hazard pool
-- (LAVA on L4, toxic GOO on L6), arcs ACROSS it on a sine path and sinks back
-- in, peaking high so it CONTESTS the crossing (the L4 stepping-stone, the L6
-- jump arc). Bodiless: a pure sprite that pfTickSerpent drives along the arc
-- (rise at the lips, peak over the centre) and hides while submerged - the pool's
-- surface (lava tiles / goo rect) occludes its lower body, so it must be created
-- BEFORE the pool. Unkillable, like the saws (gotcha 16: a proximity-poll
-- knockback, never a stomp). pFrame/pAnim pick the skin (snakeLava / snakeSlime),
-- both spook-sheet art, so it SELF-GATES on gSpooksOK - absent, the maker no-ops
-- and the pit is simply a hazard gap (the crossing never depends on the serpent).
-- pL/pR are the pool lips; pSurfY the surface it emerges from; pPeakY the head's
-- height at the centre peak.
command pfMakeSerpent pL, pR, pSurfY, pPeakY, pFrame, pAnim
   local tRef
   if gSpooksOK is not true then exit pfMakeSerpent
   if not b2kSheetHasFrame("spooks", pFrame) then exit pfMakeSerpent
   b2kSpriteNew "spooks", pFrame, (pL + pR) / 2, pSurfY
   put the result into tRef
   if tRef is empty then exit pfMakeSerpent
   b2kSpritePlay tRef, pAnim
   set the visible of tRef to false   -- starts submerged (the tick shows it as it rises)
   put tRef into gLSerpSpr
   put pL into gLSerpL
   put pR into gLSerpR
   put pSurfY into gLSerpSurfY
   put pPeakY into gLSerpPeakY
   put 4200 into gLSerpPer           -- one full lip-to-lip crossing; slow enough to read + time
   put 66 into gLSerpHalfH           -- snakeLava/Slime is 147px * the 0.9 spooks scale ~= 132 tall; head at the sprite TOP, so half ~= 66
   put false into gLSerpVis
end pfMakeSerpent

-- A ROLLING BOULDER: a dynamic ball released across the ground (a flat
-- icy SLIDE on level 3, signed pVX) toward the hero, who must outrun or
-- leap it. It STARTS parked (static) and is released on a cycle by
-- pfTickBoulder, which also re-parks it the instant it rolls past
-- pResetX - so it never reaches the kill floor and never needs a respawn. It passes THROUGH the hero
-- (b2kNoCollide); the hit is a POLL (a solid shove would fight the
-- controller's velocity assert and ground-snap him mid-air).
command pfMakeBoulder pX, pY, pResetX, pVX
   local tRef, tIdx
   if pVX is empty then put 70 into pVX
   add 1 to gBoulderN
   put gBoulderN into tIdx
   b2kSpawnBall pX, pY, 54, "122,120,130"
   put the result into tRef
   if tRef is empty then exit pfMakeBoulder
   b2kSetDensity tRef, 3.0
   b2kSetFriction tRef, 0.18         -- low grip: it COASTS far on the ice
   b2kSetBounce tRef, 0.08
   b2kNoCollide tRef, gHero
   b2kSetStatic tRef                  -- parked until the timer releases it
   put tRef into gBoulderB[tIdx]
   put empty into gBoulderSpr[tIdx]
   -- sprite-only: a stone FACE over the (now invisible) ball. A boulder is
   -- round, so it needs no rotation - the sprite reads right at any spin,
   -- and a bound sprite tracks the body through roll and re-park alike.
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "rock") then
      set the visible of tRef to false
      b2kSpriteNew "tiles", "rock", pX, pY
      put the result into gBoulderSpr[tIdx]
      if gBoulderSpr[tIdx] is not empty then b2kSpriteBind gBoulderSpr[tIdx], tRef
   end if
   put pX into gBoulderHomeX[tIdx]
   put pY into gBoulderHomeY[tIdx]
   put pResetX into gBoulderResetX[tIdx]
   put pVX into gBoulderVX[tIdx]       -- signed: a flat icy SLIDE, or a ramp roll
   put the milliseconds + 2200 into gBoulderT[tIdx]   -- first run after the splash
   put 40 into gBoulderHurtR[tIdx]
   put the milliseconds + 2400 into gBoulderGrace[tIdx]
end pfMakeBoulder

-- An EXPLOSIVE BARREL: a bomb face over an invisible static host. The
-- hero coming near lights the fuse; a beat later b2kExplode (Box2D's
-- native, shape-aware radial blast) scatters every nearby DYNAMIC body -
-- a woodpile of loose crates flies - and knocks the hero back if he
-- lingered in range. One-shot: the barrel parks off-world and the face
-- flashes out. Trigger-and-retreat, the classic powder keg.
command pfMakeBarrel pX, pY
   local tName, tRef, tIdx
   add 1 to gBarrelN
   put gBarrelN into tIdx
   put "pf_barrel" & tIdx into tName
   create graphic tName
   set the style of it to "rectangle"
   set the rect of it to pX - 22, pY - 26, pX + 22, pY + 26
   set the filled of it to true
   set the backgroundColor of it to "70,55,48"
   set the visible of it to false
   b2kAddStatic the long id of graphic tName
   put the long id of graphic tName into tRef
   put empty into gBarrelSpr[tIdx]
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "bomb") then
      b2kSpriteNew "tiles", "bomb", pX, pY
      put the result into gBarrelSpr[tIdx]
   else
      set the visible of graphic tName to true
      b2kCamAdopt tRef
   end if
   put tRef into gBarrelB[tIdx]
   put pX into gBarrelX[tIdx]
   put pY into gBarrelY[tIdx]
   put "idle" into gBarrelState[tIdx]
   put 0 into gBarrelT[tIdx]
end pfMakeBarrel

-- A loose WOODEN CRATE (the L2 gate-crate pattern): an invisible
-- fixed-rotation spawned box wearing the block_empty sprite - the same
-- crate face the ?-boxes and the gate crate use. Fixed rotation means a
-- blast sends it SLIDING, not tumbling, so the bound sprite tracks it
-- without the sprite-cannot-rotate problem (gotcha 23). Cleaned up with
-- the world (b2kClear/b2kTeardown).
command pfMakeWoodCrate pX, pY
   local tRef, tSpr
   b2kSpawnBox pX, pY, 44, 44, "150,112,62"
   put the result into tRef
   if tRef is empty then exit pfMakeWoodCrate
   b2kSetFriction tRef, 0.5
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "block_empty") then
      set the visible of tRef to false
      b2kSetFixedRotation tRef, true
      b2kSpriteNew "tiles", "block_empty", pX, pY
      put the result into tSpr
      if tSpr is not empty then b2kSpriteBind tSpr, tRef
   end if
end pfMakeWoodCrate

-- A moving-platform LIFT (the Wave 5 platform-carry showcase): a KINEMATIC
-- box at (pX,pY) that patrols horizontally pMinX..pMaxX at pSpeed px/sec. A
-- grounded player standing on it INHERITS its velocity (b2kPlayerSet
-- "platformCarry" is on for the whole showcase), so it ferries the hero
-- across the hazard below. It MUST move by VELOCITY, not by repositioning:
-- the carry reads the body's vx, and a position-driven kinematic reports
-- zero velocity (no carry). Sleep is disabled so it never naps at a turn.
-- A kinematic box is a graphic (no rotation, gotcha 23), so a plain visible
-- slab reads fine - the metal-deck colour suits a machine bay. Wiped with
-- the world (b2kTeardown/b2kClear) like every spawned body.
command pfMakeLift pX, pY, pW, pH, pMinX, pMaxX, pSpeed
   local tRef, tIdx
   b2kSpawnBox pX, pY, pW, pH, "120,128,140"
   put the result into tRef
   if tRef is empty then exit pfMakeLift
   add 1 to gLiftN
   put gLiftN into tIdx
   b2kSetKinematic tRef
   b2kSetSleepEnabled tRef, false   -- a lift that naps at a turn would strand its rider
   b2kSetVelocity tRef, pSpeed, 0   -- initial drift toward pMaxX (signed pSpeed)
   put tRef into gLift[tIdx]
   put pMinX into gLiftMin[tIdx]
   put pMaxX into gLiftMax[tIdx]
   put pSpeed into gLiftSpeed[tIdx]
   put pSpeed into gLiftVX[tIdx]    -- the last vx written (write-on-change cache)
end pfMakeLift

-- =====================================================================
-- LEVEL 1 - "GREEN HILLS" (8640px). Movement and the Wave 1 toys:
-- springboard + sky coin, the bonk row, the one-way bridge over the
-- spike slime, the slope mound, two one-way clouds, the spike pit, a
-- skittering MOUSE and a flying ladybug, then the showcase finale: a
-- sagging ROPE BRIDGE (hinged planks) over a real chasm, the crusher
-- alley and the hilltop swim pool to the flag.
-- =====================================================================
command pfL1Scene
   local tX
   put "GREEN HILLS" into gLevelName
   pfBounds kPfEdgeL, 8520 + kPfEndCap          -- right edge hugs the goal flag (8520); the hilltop pool + meadow are well inside
   pfSlab "pf_ground1", 0, 576, 2560, 640
   pfSlab "pf_ground2", 2752, 576, 3968, 640
   pfSlab "pf_ground3", 4288, 576, 7552, 640   -- the far meadow, the gauntlet, the homeward run + the GREEN CRUSHER alley
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_block_top") then
      put 0 into tX
      repeat while tX <= 2496
         if tX >= 1376 and tX <= 1696 then
            -- under the mound: plain centre, so the hill reads as one mass
            pfTile "terrain_grass_block_center", tX, 576
         else
            pfTile "terrain_grass_block_top", tX, 576
         end if
         add 64 to tX
      end repeat
      put 2752 into tX
      repeat while tX <= 3904
         pfTile "terrain_grass_block_top", tX, 576
         add 64 to tX
      end repeat
      put 4288 into tX
      repeat while tX <= 7488
         pfTile "terrain_grass_block_top", tX, 576
         add 64 to tX
      end repeat
      pfShowSlabs false
   else
      pfShowSlabs true
   end if
   -- the post-pit meadow (the level's second act): a one-way cloud rest
   -- over the long run home (chain ghost-padded a tile past the art)
   b2kSmoothGround "3392,448" & cr & "3328,448" & cr & "3136,448" & cr & "3072,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_cloud_left") then
      pfTile "terrain_grass_cloud_left", 3136, 448
      pfTile "terrain_grass_cloud_middle", 3200, 448
      pfTile "terrain_grass_cloud_right", 3264, 448
   else
      create graphic "pf_cloudledgeC"
      set the style of it to "line"
      set the points of it to "3136,448" & cr & "3328,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "70,190,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeC"
   end if
   -- (a low CRAWL overhang once sat here for the Wave 5 crawl move; DOWN is now
   -- a simple in-place brake, so the overhang is gone and its coin -- cast on
   -- the open run below -- is grabbed just by running past it)
   pfMakeSpikes 2560, 2752
   -- the one-way bridge (GHOST RULE: the chain runs one tile past the
   -- deck on each side - 688..1072 under art 752..1008)
   b2kSmoothGround "1072,440" & cr & "1008,440" & cr & "752,440" & cr & "688,440"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "bridge") then
      put 752 into tX
      repeat while tX <= 944
         pfTile "bridge", tX, 424
         add 64 to tX
      end repeat
   else
      create graphic "pf_ledge"
      set the style of it to "line"
      set the points of it to "752,440" & cr & "1008,440"
      set the lineSize of it to 4
      set the foregroundColor of it to "70,190,110"
      b2kCamAdopt the long id of graphic "pf_ledge"
   end if
   -- the slope mound (26.6-degree ramps): six chain points, the outer
   -- two are non-colliding ghost anchors; ramps mirrored on the ascent.
   -- Spacing pass: the mound and the cloud steps each get clear air
   -- (the steps used to start at the mound's very foot).
   b2kSmoothGround "1824,576" & cr & "1760,576" & cr & "1632,512" & cr & "1504,512" & cr & "1376,576" & cr & "1312,576"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_ramp_long_a") then
      pfTile "terrain_grass_ramp_long_b", 1376, 512, true
      pfTile "terrain_grass_ramp_long_a", 1440, 512, true
      pfTile "terrain_grass_block_top", 1504, 512
      pfTile "terrain_grass_block_top", 1568, 512
      pfTile "terrain_grass_ramp_long_a", 1632, 512
      pfTile "terrain_grass_ramp_long_b", 1696, 512
   else
      create graphic "pf_mound"
      set the style of it to "polygon"
      set the points of it to "1376,576" & cr & "1504,512" & cr & "1632,512" & cr & "1760,576" & cr & "1376,576"
      set the filled of it to true
      set the backgroundColor of it to "90,170,90"
      b2kCamAdopt the long id of graphic "pf_mound"
   end if
   -- the cloud steps (one-way chains, ghost-padded past the art)
   b2kSmoothGround "2208,448" & cr & "2144,448" & cr & "1952,448" & cr & "1888,448"
   b2kSmoothGround "2496,320" & cr & "2432,320" & cr & "2240,320" & cr & "2176,320"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_cloud_left") then
      pfTile "terrain_grass_cloud_left", 1952, 448
      pfTile "terrain_grass_cloud_middle", 2016, 448
      pfTile "terrain_grass_cloud_right", 2080, 448
      pfTile "terrain_grass_cloud_left", 2240, 320
      pfTile "terrain_grass_cloud_middle", 2304, 320
      pfTile "terrain_grass_cloud_right", 2368, 320
   else
      create graphic "pf_cloudledgeA"
      set the style of it to "line"
      set the points of it to "1952,448" & cr & "2144,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "70,190,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeA"
      create graphic "pf_cloudledgeB"
      set the style of it to "line"
      set the points of it to "2240,320" & cr & "2432,320"
      set the lineSize of it to 4
      set the foregroundColor of it to "70,190,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeB"
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "bush") then
      -- decor stays CLEAR of the interactive beats (the bonk row used
      -- to sit right on top of the fences); more of it now, for variety
      pfTile "bush", 168, 512
      pfTile "fence", 640, 512
      pfTile "fence_broken", 704, 512
      pfTile "mushroom_brown", 1008, 512   -- clear of the meadow slime's patrol (was 1056, on its beat)
      pfTile "mushroom_red", 2752, 512      -- just left of the 2nd-act slime (was 2816, on its spawn)
      pfTile "bush", 2936, 512              -- in the gap before the mouse (was 3008, on its run)
      pfTile "mushroom_brown", 4860, 512    -- past the meadow frog (was 4600, on its beat)
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "sign") then
      pfTile "sign", 96, 512        -- a way-marker by the spawn
   end if
   -- the showcase FINALE: a sagging ROPE BRIDGE over a real chasm
   -- (3968..4288, the kill floor below) - the only way to the far meadow
   -- and the flag. Fence posts mark the anchors; the planks dip as you
   -- cross and spring back. Pure spawned-box physics, so it builds even
   -- without the atlas (it is the level's one mandatory crossing).
   pfMakeBridge 3968, 4288, 576, 6
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "fence") then
      pfTile "fence", 3904, 512
      pfTile "fence", 4288, 512
   end if
   -- the far-meadow GAUNTLET (the level's third act): a one-way cloud
   -- (ghost-padded a tile past the art each side - jump up for its coin,
   -- DOWN+JUMP to drop off) over a run of two slimes and a darting fly
   b2kSmoothGround "4992,448" & cr & "4928,448" & cr & "4736,448" & cr & "4672,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_cloud_left") then
      pfTile "terrain_grass_cloud_left", 4736, 448
      pfTile "terrain_grass_cloud_middle", 4800, 448
      pfTile "terrain_grass_cloud_right", 4864, 448
   else
      create graphic "pf_cloudledgeE"
      set the style of it to "line"
      set the points of it to "4736,448" & cr & "4928,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "70,190,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeE"
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "bush") then
      pfTile "bush", 5160, 512
      pfTile "mushroom_red", 5560, 512
      pfTile "bush", 5980, 512
      pfTile "mushroom_brown", 6200, 512
   end if
   -- the HOMEWARD RUN (a fourth act): a chained thwomp + a snail (in the
   -- cast) under a final one-way cloud (ghost-padded a tile past the art)
   b2kSmoothGround "6296,448" & cr & "6232,448" & cr & "6040,448" & cr & "5976,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_cloud_left") then
      pfTile "terrain_grass_cloud_left", 6040, 448
      pfTile "terrain_grass_cloud_middle", 6104, 448
      pfTile "terrain_grass_cloud_right", 6168, 448
   else
      create graphic "pf_cloudledgeG"
      set the style of it to "line"
      set the points of it to "6040,448" & cr & "6232,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "70,190,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeG"
   end if
   -- the GREEN CRUSHER ALLEY (the showcase gauntlet): a row of green-block
   -- thwomps (in the cast) you run beneath, then a two-cloud HOP to the
   -- flag. Both clouds ghost-padded a tile past the art each side.
   b2kSmoothGround "7312,448" & cr & "7248,448" & cr & "7056,448" & cr & "6992,448"
   b2kSmoothGround "7532,448" & cr & "7468,448" & cr & "7276,448" & cr & "7212,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_cloud_left") then
      pfTile "terrain_grass_cloud_left", 7056, 448
      pfTile "terrain_grass_cloud_middle", 7120, 448
      pfTile "terrain_grass_cloud_right", 7184, 448
      pfTile "terrain_grass_cloud_left", 7276, 448
      pfTile "terrain_grass_cloud_middle", 7340, 448
      pfTile "terrain_grass_cloud_right", 7404, 448
   else
      create graphic "pf_cloudledgeI"
      set the style of it to "line"
      set the points of it to "7056,448" & cr & "7468,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "70,190,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeI"
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "bush") then
      pfTile "bush", 6320, 512
      pfTile "mushroom_red", 7488, 512
   end if
   if gToysOK is true then
      -- the spring mid-meadow: bouncing happens in open air, well away
      -- from the left corner (flush-to-wall put the bounce against the
      -- window edge; mid-meadow it is a 42px hop for non-bouncers)
      pfMakeSpring 240
      pfMakeBonk "brick", 384
      pfMakeBonk "box", 448
      pfMakeBonk "brick", 512
      pfMakeBonk "box", 576
   end if
   -- ===== the Wave 4 HILLTOP POOL (past the crusher alley, before the
   -- flag): a RAISED swim basin between two earth banks. Hop up onto the
   -- left bank (a 96px step), DIVE in, swim DOWN for the coins, then stroke
   -- up + hold-right to HOP out the far bank and on to the flag. Banks are
   -- visible earth slabs; the floor hides under the water rect. =====
   pfSlab "pf_pondL", 7552, 480, 7760, 640
   pfSlab "pf_pondR", 8160, 480, 8368, 640
   -- a KILL FLOOR under the water (no solid bottom): the basin has no floor to
   -- rest on, so sinking out the bottom RESPAWNS - the swim has stakes, you must
   -- stroke up and out. The sensor sits just below the water line (640), clear of
   -- the underwater coins above it (b2kSensorEnter routes uPfKillFlag to pfHurt).
   create graphic "pf_pondkill"
   set the rect of it to 7760, 644, 8160, 676
   set the visible of it to false
   set the uPfKillFlag of graphic "pf_pondkill" to true
   b2kAddSensor the long id of graphic "pf_pondkill", "box"
   pfSlab "pf_ground4", 8368, 576, 8640, 640
   set the backgroundColor of graphic "pf_pondL" to "150,120,82"
   set the backgroundColor of graphic "pf_pondR" to "150,120,82"
   set the visible of graphic "pf_pondL" to true
   set the visible of graphic "pf_pondR" to true
   b2kCamAdopt the long id of graphic "pf_pondL"
   b2kCamAdopt the long id of graphic "pf_pondR"
   pfTextureSlab "pf_pondL", "terrain_stone_block_center"   -- sheet art instead of the flat banks
   pfTextureSlab "pf_pondR", "terrain_stone_block_center"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_block_top") then
      -- grass the bank tops + the far-bank flag approach so the pool reads
      -- as a basin set into the hill (the floor stays under the water)
      put 7552 into tX
      repeat while tX <= 7696
         pfTile "terrain_grass_block_top", tX, 480
         add 64 to tX
      end repeat
      put 8160 into tX
      repeat while tX <= 8304
         pfTile "terrain_grass_block_top", tX, 480
         add 64 to tX
      end repeat
      put 8368 into tX
      repeat while tX <= 8576
         pfTile "terrain_grass_block_top", tX, 576
         add 64 to tX
      end repeat
   else
      set the visible of graphic "pf_ground4" to true
      b2kCamAdopt the long id of graphic "pf_ground4"
   end if
   pfMakeWater 7760, 480, 8160, 640
end pfL1Scene

command pfL1Cast
   local tRef
   pfMakeCoin 360, 496      -- on the path, under the bonk row
   pfMakeCoin 880, 396      -- on the bridge deck (the high road)
   pfMakeCoin 1130, 500     -- the meadow slime's beat
   pfMakeCoin 1568, 460     -- on the mound plateau
   pfMakeGem 1568, 400, "yellow"   -- BONUS gem above the mound (double-jump for it)
   pfMakeStar 2400, 264   -- hidden STAR: ON the highest cloud (top y320, art 2240-2432), the peak of the cloud-hop sequence
   pfMakeCoin 2336, 264     -- on the high cloud (mind the fly)
   pfMakeCoin 2656, 440     -- mid-air over the spike pit: grab it mid-jump
   pfMakeCoin 2876, 500     -- the second act's slime beat
   pfMakeCoin 3076, 500     -- the skittering mouse's beat
   pfMakeCoin 3232, 392     -- on the rest cloud
   pfMakeCoin 3460, 500     -- on the open run (was the crawl-tunnel reward); grab it running past
   pfMakeCoin 3616, 500     -- the last meadow slime's beat
   pfMakeCoin 4128, 510     -- mid-bridge: grab it as the planks dip
   pfMakeCoin 4456, 500     -- the far meadow's ladybug beat
   pfMakeCoin 4660, 500     -- the meadow frog's beat (Wave 6)
   pfMakeCoin 4832, 392     -- up on the gauntlet's one-way cloud
   pfMakeCoin 5040, 500     -- the first gauntlet slime's beat
   pfMakeCoin 5232, 500     -- under the darting fly
   pfMakeCoin 5360, 500     -- the last gauntlet slime's beat
   pfMakeCoin 5700, 500     -- beneath the chained thwomp: grab it as you dash under
   pfMakeCoin 5900, 500     -- the homeward snail's beat (shell it, kick it)
   pfMakeCoin 6136, 392     -- up on the homeward-run cloud
   pfMakeCoin 6530, 500     -- threading the GREEN CRUSHER alley: grab between drops
   pfMakeCoin 6710, 500     -- ...and between the next pair of crushers
   pfMakeCoin 6890, 500     -- ...and the last gap
   pfMakeCoin 7120, 392     -- up on the first hop cloud
   pfMakeCoin 7340, 392     -- up on the second hop cloud, by the flag
   if gToysOK is true then pfMakeCoin 240, 230   -- the sky coin (spring up)
   -- the bee tours the mound (harmless); the fly guards the cloud coin;
   -- a flying LADYBUG patrols the second-act meadow (new aerial variety)
   if gAssetsOK is true and b2kSheetHasFrame("foes", "bee_a") then
      b2kSpriteNew "foes", "bee_a", 1448, 300
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "buzz"
         pfAddMover tRef, 1448, 300, 90, 900, 26, 430, 0, 0, true
      end if
   end if
   if gAssetsOK is true and b2kSheetHasFrame("foes", "fly_a") then
      b2kSpriteNew "foes", "fly_a", 2186, 390
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "flit"
         pfAddMover tRef, 2186, 390, 70, 700, 60, 450, 36, 44, true
      end if
   end if
   if gAssetsOK is true and b2kSheetHasFrame("foes", "ladybug_fly") then
      b2kSpriteNew "foes", "ladybug_fly", 3420, 420
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "ladyflit"
         pfAddMover tRef, 3420, 420, 110, 820, 24, 470, 34, 38, true
      end if
   end if
   pfMakeSlime 1, "spike", 880, 760, 1000, 576
   pfMakeSlime 2, "normal", 1130, 1080, 1180, 576
   -- Phase E: a SNAKE slithers the open meadow stretch past the slimes (auto-
   -- reverses at its band ends; clear of the pit at 2560). The showcase level gets
   -- the slither type too. Optional spooks art - absent, the stretch is just open.
   pfMakeSnake 11, 2050, 1700, 2300, 576
   if gSpooksOK is true then   -- Phase D: a GREEN slime variant (optional spooks art; a normal slime without it)
      pfMakeCritter 3, "normal", 2876, 2816, 2936, 576, 52, "slimeGreen.png", "slimegreen", "slimeGreen_squashed.png", 22, 36, "120,200,90", 4, "spooks"
   else
      pfMakeSlime 3, "normal", 2876, 2816, 2936, 576
   end if
   pfMakeSlime 4, "normal", 3616, 3556, 3676, 576
   -- NEW variety walkers (native foes art, stomp like any slime): a FAST
   -- mouse skitters the second act; a LADYBUG ambles the far meadow
   pfMakeCritter 5, "normal", 3076, 3000, 3160, 576, 120, "mouse_walk_a", "mousewalk", empty, 20, 30, "150,140,150", -4
   pfMakeCritter 6, "normal", 4456, 4360, 4540, 576, 72, "ladybug_walk_a", "ladywalk", empty, 22, 30, "200,70,70", -4, empty, true   -- ladybug art faces LEFT: pFaceFlip true
   -- Wave 6 (bestiary II): a meadow FROG hops at you in the far-meadow clearing
   -- (between the ladybug and the gauntlet cloud). Stomp it; do not stand by it.
   pfMakeFrog 10, 4660, 4600, 4780, 576
   -- the far-meadow gauntlet's two slimes (the cloud is above them) and a
   -- darting fly between - a classic run of stomps on the way to the flag
   if gSpooksOK is true then   -- Phase D: a BLUE slime variant
      pfMakeCritter 7, "normal", 5040, 4980, 5100, 576, 52, "slimeBlue.png", "slimeblue", "slimeBlue_squashed.png", 22, 36, "90,150,220", 4, "spooks"
   else
      pfMakeSlime 7, "normal", 5040, 4980, 5100, 576
   end if
   pfMakeSlime 8, "normal", 5360, 5300, 5420, 576
   if gAssetsOK is true and b2kSheetHasFrame("foes", "fly_a") then
      b2kSpriteNew "foes", "fly_a", 5232, 452
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "flit"
         pfAddMover tRef, 5232, 452, 80, 720, 30, 480, 34, 40, true
      end if
   end if
   -- the HOMEWARD RUN: the classic chained-weight THWOMP returns (dash
   -- under it for the coin), and a SNAIL to shell-and-kick
   pfMakeThwomp 1, 5700
   pfMakeSnail 9, 5900, 5840, 5960
   -- the GREEN CRUSHER ALLEY (the grass biome's marquee gauntlet): a row
   -- of four green-block thwomps you time your run beneath - each drops as
   -- you near it, so keep moving and snatch the coins in the gaps. They
   -- rest STATIC then rise + re-arm, never blocking the alley for good.
   pfMakeThwomp 2, 6440, false, "block_green"
   pfMakeThwomp 3, 6620, false, "block_green"
   pfMakeThwomp 4, 6800, false, "block_green"
   pfMakeThwomp 5, 6980, false, "block_green"
   -- a CHECKPOINT just before the rope bridge: a slip into the chasm is
   -- then a quick retry at the brink, never a replay of the whole level
   pfMakeCheckpoint 3856
   if gToysOK is true then pfMakeDebrisPool   -- this level has bricks
   -- Wave 4: the hilltop pool's coins are UNDERWATER, so the gate can only
   -- be cleared by diving and swimming for them (then stroke out + on)
   pfMakeCoin 7880, 556     -- the underwater coins, grouped CENTRALLY in the basin (water 7760..8160, centre 7960): dive for them
   pfMakeCoin 7960, 576     -- the deepest (raised from 588 for a safe margin above the new kill floor at ~644)
   pfMakeCoin 8040, 556
   -- FISH patrol the pool (native foes art): bodiless movers that hurt by
   -- proximity (pfOuch knockback, recoverable) - time the dive between them.
   -- Two depths/periods so the gap shifts; both stay inside the water (7760..8160).
   if gAssetsOK is true and b2kSheetHasFrame("foes", "fish_blue_swim_a") then
      b2kSpriteNew "foes", "fish_blue_swim_a", 7960, 532
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "fishblue"
         pfAddMover tRef, 7960, 532, 120, 2000, 14, 700, 30, 26, true
      end if
   end if
   if gAssetsOK is true and b2kSheetHasFrame("foes", "fish_yellow_swim_a") then
      b2kSpriteNew "foes", "fish_yellow_swim_a", 7960, 596
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "fishyellow"
         pfAddMover tRef, 7960, 596, 120, 2500, 12, 800, 30, 26, true
      end if
   end if
   pfMakeGoal 8520, 544
end pfL1Cast

-- =====================================================================
-- LEVEL 2 - "THE WORKS" (5952px). The machines: crate + button gate,
-- the Wave 2 ladder to its bonus ledge, the stand-to-flip saw lever,
-- both saws, a crawling WORM, chained thwomps, a breather cloud with its
-- bee, a SECOND machine bay (another chained crusher + an always-on
-- sweeping saw), the Wave 5 LIFT BAY (the signature: ride the moving deck
-- over a grinder), then the crusher alley, the yellow key and the walled
-- door, stone steps to the flag. Spaced so every machine is its own beat
-- (round-6: cramped reads as "what IS all this?").
-- =====================================================================
command pfL2Scene
   local tX, tRef
   put "THE WORKS" into gLevelName
   pfBounds kPfEdgeL, 6272 + kPfEndCap   -- the stone VAULT finale gives the two-key gates room (flag at 6272)
   pfSlab "pf_ground1", 0, 576, 6384, 640
   pfSlab "pf_plat1", 6016, 512, 6208, 576
   pfSlab "pf_plat2", 6208, 448, 6336, 576
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_block_top") then
      put 0 into tX
      repeat while tX <= 6320
         if tX >= 5344 then
            -- the VAULT finale plays in STONE, entered through the first (yellow) gate
            pfTile "terrain_stone_block_top", tX, 576
         else
            pfTile "terrain_grass_block_top", tX, 576
         end if
         add 64 to tX
      end repeat
      pfTile "terrain_stone_block_top_left", 6016, 512
      pfTile "terrain_stone_block_top", 6080, 512
      pfTile "terrain_stone_block_top_right", 6144, 512
      pfTile "terrain_stone_block_top", 6208, 448
      pfTile "terrain_stone_block_top", 6272, 448
      pfTile "terrain_stone_block_center", 6208, 512
      pfTile "terrain_stone_block_center", 6272, 512
      pfShowSlabs false
   else
      pfShowSlabs true
   end if
   -- the breather between the alley and the wall: a one-way cloud rest
   -- (chain ghost-padded a tile past the art on each side)
   b2kSmoothGround "2370,448" & cr & "2306,448" & cr & "2114,448" & cr & "2050,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_cloud_left") then
      pfTile "terrain_grass_cloud_left", 2114, 448
      pfTile "terrain_grass_cloud_middle", 2178, 448
      pfTile "terrain_grass_cloud_right", 2242, 448
   else
      create graphic "pf_cloudledgeA"
      set the style of it to "line"
      set the points of it to "2114,448" & cr & "2306,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "70,190,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeA"
   end if
   -- WAVE 2: the bonus ledge, a clear beat of its own past the gate
   -- (round 6 had it tangled with the checkpoint and the lever). The
   -- ledge is a one-way chain (ghost-padded a tile past the stone art
   -- each side), so you can also DOWN+JUMP off it; the ladder is a
   -- pure polled ZONE -- no physics body, the climb is the Kit
   -- controller's. The zone tops out 40px above the deck so climbing
   -- out steps you onto it, and it starts at the floor so DOWN while
   -- falling past grabs it.
   b2kSmoothGround "960,352" & cr & "896,352" & cr & "704,352" & cr & "640,352"
   b2kPlayerAddLadder 824, 312, 864, 570
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "ladder_middle") then
      pfTile "terrain_stone_block_top_left", 704, 352
      pfTile "terrain_stone_block_top", 768, 352
      pfTile "terrain_stone_block_top_right", 832, 352
      pfTile "ladder_top", 812, 352
      pfTile "ladder_middle", 812, 416
      pfTile "ladder_middle", 812, 480
      pfTile "ladder_bottom", 812, 544
   else
      create graphic "pf_bonusledge"
      set the style of it to "line"
      set the points of it to "704,352" & cr & "896,352"
      set the lineSize of it to 4
      set the foregroundColor of it to "180,170,150"
      b2kCamAdopt the long id of graphic "pf_bonusledge"
      create graphic "pf_ladderline"
      set the style of it to "line"
      set the points of it to "844,352" & cr & "844,576"
      set the lineSize of it to 6
      set the foregroundColor of it to "170,120,60"
      b2kCamAdopt the long id of graphic "pf_ladderline"
   end if
   pfMakeGate 400, 500
   -- the crate that holds the plate down (drag or push it). It wears
   -- the empty-box face - the same box the ?-row turns into - over an
   -- invisible spawned body; fixed rotation (bound art does not spin).
   b2kSpawnBox 240, 520, 56, 56, "orange"
   put the result into tRef
   if tRef is not empty then
      b2kSetFriction tRef, 0.6
      put tRef into gCrateB
      if gAssetsOK is true and b2kSheetHasFrame("tiles", "block_empty") then
         set the visible of tRef to false
         b2kSetFixedRotation tRef, true
         b2kSpriteNew "tiles", "block_empty", 240, 520
         put the result into gCrateSpr
         if gCrateSpr is not empty then b2kSpriteBind gCrateSpr, tRef
      end if
   end if
   -- decor along the run into the second machine bay (the chained
   -- crusher + the always-on sweeping saw are built in the CAST)
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "bush") then
      pfTile "sign", 2300, 512        -- moved LEFT off the checkpoint: at 2400 the sign (2368..2432) overlapped the flag at 2450 (flag 2418..2482); 2300 clears it by ~86px and sits just right of the breather cloud's art (~2274)
      pfTile "bush", 2828, 512        -- between the relocated slime's sweep (..2824) and the left lift pedestal (2920); clear of both (was 2720, now inside that slime's patrol)
   end if
   -- ===== THE LIFT BAY (level 2's signature finale - the Wave 5 PLATFORM-
   -- CARRY showcase). A GRINDER strip runs along the floor; two boarding
   -- pedestals flank it. The moving LIFT (built in the cast) shuttles the
   -- pedestal tops, so you jump up onto the left pedestal, RIDE the deck
   -- across the grinder (its velocity carries you - stand still and you
   -- drift with it), grab the mid-bay coin, and step off the right pedestal.
   -- The grinder hurts (pfOuch knockback, recoverable) so the floor route is
   -- blocked; but a running DOUBLE JUMP also clears the ~200px, so the bay is
   -- never a dead end. Built as scenery (behind the hero). =====
   pfSlab "pf_liftpedL", 2920, 489, 3010, 576
   pfSlab "pf_liftpedR", 3210, 489, 3300, 576
   set the backgroundColor of graphic "pf_liftpedL" to "96,104,118"
   set the backgroundColor of graphic "pf_liftpedR" to "96,104,118"
   set the visible of graphic "pf_liftpedL" to true
   set the visible of graphic "pf_liftpedR" to true
   b2kCamAdopt the long id of graphic "pf_liftpedL"
   b2kCamAdopt the long id of graphic "pf_liftpedR"
   pfTextureSlab "pf_liftpedL", "terrain_stone_block_center"   -- stone pedestals, not flat grey
   pfTextureSlab "pf_liftpedR", "terrain_stone_block_center"
   -- the bay's floor hazard, drawn as LAVA (sheet art, not a flat-red GRC):
   -- pfMakeLava lays the lava tiles + a hurt sensor whose top sits at the floor
   -- line (y548), so it catches a walker but never the deck/rider above at y~500
   pfMakeLava 3010, 3210
   -- the bay's moving deck: a kinematic platform shuttling 3020..3200 at
   -- 60px/s between the pedestals. A grounded hero on it inherits its
   -- velocity (platformCarry), so it ferries him over the grinder to the far
   -- pedestal. Built here in the SCENE (before the hero) so the deck layers
   -- BEHIND him - he rides ON it, drawn in front, never hidden by the deck.
   pfMakeLift 3020, 500, 96, 22, 3020, 3200, 60
   -- a THIRD machine run: a snail + another chained crusher (in the cast)
   -- under a one-way cloud (ghost-padded a tile past the art each side)
   b2kSmoothGround "3956,448" & cr & "3892,448" & cr & "3700,448" & cr & "3636,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_cloud_left") then
      pfTile "terrain_grass_cloud_left", 3700, 448
      pfTile "terrain_grass_cloud_middle", 3764, 448
      pfTile "terrain_grass_cloud_right", 3828, 448
   else
      create graphic "pf_cloudledgeH"
      set the style of it to "line"
      set the points of it to "3700,448" & cr & "3892,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "70,190,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeH"
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "bush") then
      pfTile "bush", 3488, 512   -- between the barnacle and the chained crusher (was 3400, on the barnacle's telegraph)
   end if
   -- the GREEN CRUSHER ALLEY (the works' marquee gauntlet): a row of green-
   -- block thwomps (in the cast) you run beneath, then a two-cloud HOP to the
   -- walled door. Both clouds ghost-padded a tile past the art each side.
   b2kSmoothGround "5096,448" & cr & "5032,448" & cr & "4840,448" & cr & "4776,448"
   b2kSmoothGround "5316,448" & cr & "5252,448" & cr & "5060,448" & cr & "4996,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_grass_cloud_left") then
      pfTile "terrain_grass_cloud_left", 4840, 448
      pfTile "terrain_grass_cloud_middle", 4904, 448
      pfTile "terrain_grass_cloud_right", 4968, 448
      pfTile "terrain_grass_cloud_left", 5060, 448
      pfTile "terrain_grass_cloud_middle", 5124, 448
      pfTile "terrain_grass_cloud_right", 5188, 448
   else
      create graphic "pf_cloudledgeJ"
      set the style of it to "line"
      set the points of it to "4840,448" & cr & "5252,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "70,190,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeJ"
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "bush") then
      pfTile "sign", 3980, 512        -- a way-marker into the crusher alley
      pfTile "bush", 5160, 512        -- last greenery before the stone vault (was 5400, now inside the stone finale)
   end if
   if gToysOK is true then
      pfMakeLever 1120        -- stand here to power the FIRST sweep saw down
      -- THE TWO-KEY LOCKGATE (Phase C slice 3): the works' exit is now a DOUBLE
      -- door - a YELLOW key early on the main run, a BLUE key up on the hop
      -- clouds, and BOTH gates stand between you and the flag (the HUD lists the
      -- keys you carry). Multi-instance pfMakeKeyDoor; each key opens its colour.
      -- THE VAULT'S TWO-KEY LOCKGATE (Phase C slice 3): the stone finale is
      -- entered through a YELLOW gate, then a corridor, then a BLUE gate before
      -- the flag - each its own beat, well clear of the steps (the HUD lists the
      -- keys you carry). Yellow key on the main run, blue key up on the hop clouds.
      pfMakeKeyDoor 1740, 500, 5344, "yellow"
      pfMakeKeyDoor 4904, 356, 5760, "blue"
      -- a GREEN SWITCH-GATE (slice 3 part 2): the green gate bars the way into
      -- the crusher alley until you climb to the third-bay cloud and press the
      -- switch up there (it latches open) - a "find the switch" beat. Skip it and
      -- the closed gate at 4060 sends you back to look for the cloud.
      pfMakeSwitchGate 3828, "green", 4000, 448
   end if
end pfL2Scene

command pfL2Cast
   local tRef
   pfMakeCoin 800, 296      -- on the LADDER's bonus ledge (Wave 2 climb)
   pfMakeGem 800, 236, "blue"   -- BONUS gem above the bonus ledge (climb + double-jump)
   pfMakeStar 720, 296   -- hidden STAR: ON the ladder-reached bonus ledge (top y352), left of the gem
   pfMakeCoin 1430, 448     -- above the sweeping saw: time the hop
   pfMakeCoin 1912, 96      -- ride the second thwomp's head up, then hop RIGHT for it. (Was 1840,64 - dead in the chain's column: the chain tiles at x1840 span y44..172, so a coin at y64 sat BEHIND the chain art. 1912 clears the chain's right edge (~1872) by 40px, still reachable from the rising weight's apex.)
   pfMakeCoin 1990, 500     -- the worm's beat, before the breather cloud
   pfMakeCoin 2210, 392     -- on the breather cloud (the bee patrols it)
   pfMakeCoin 2680, 500     -- past the second bay's chained crusher
   pfMakeCoin 2880, 448     -- above the second sweeping saw: time the hop
   pfMakeCoin 3110, 465     -- mid-LIFT-BAY: grab it as the deck carries you across the grinder
   pfMakeCoin 3350, 500     -- the third bay's snail; nudged PAST the right lift-pedestal edge (3210..3300) so the coin disc clears the stone
   pfMakeCoin 3600, 500     -- beneath the third chained crusher: grab it as you dash under
   pfMakeCoin 3796, 392     -- up on the third bay's one-way cloud
   pfMakeCoin 3950, 500     -- the fourth bay's snail (shell it, kick it)
   pfMakeCoin 4230, 500     -- threading the GREEN CRUSHER alley: grab between drops
   pfMakeCoin 4410, 500     -- ...and between the next pair of crushers
   pfMakeCoin 4590, 500     -- ...and the last gap
   pfMakeCoin 4904, 392     -- up on the first hop cloud
   pfMakeCoin 5124, 392     -- up on the second hop cloud, before the door
   pfMakeCoin 6080, 460     -- over the first stone step
   pfMakeCoin 6200, 420     -- on the climb to the flag (clear of the goal)
   -- length pass: a few more coins for the longer two-key finish (L2 -> ~24)
   pfMakeCoin 1130, 500     -- the early run, between the lever and the first saw
   pfMakeCoin 2360, 500     -- the open stretch before the checkpoint
   pfMakeCoin 4750, 500     -- the run out of the green crusher alley
   pfMakeCoin 5250, 392     -- on the second hop cloud, approaching the vault
   pfMakeCoin 5560, 500     -- in the vault corridor, between the two gates
   pfMakeCoin 5920, 500     -- past the blue gate, on the run to the steps
   if gToysOK is true then pfMakeCoin 5440, 500   -- just PAST the yellow gate (still gated by it), clear of the closed-door face
   -- the bee patrols the breather cloud
   if gAssetsOK is true and b2kSheetHasFrame("foes", "bee_a") then
      b2kSpriteNew "foes", "bee_a", 2210, 310
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "buzz"
         pfAddMover tRef, 2210, 310, 80, 850, 24, 400, 0, 0, true
      end if
   end if
   put empty into tRef
   if gAssetsOK is true and b2kSheetHasFrame("foes", "saw_a") then
      b2kSpriteNew "foes", "saw_a", 1240, 544
      put the result into tRef
      if tRef is not empty then
         set the uPfHazardFlag of tRef to true
         b2kSpritePlay tRef, "sawspin"
         b2kAddSensor tRef, "ball"
      end if
   end if
   if tRef is empty then
      create graphic "pf_saw"
      set the style of it to "oval"
      set the rect of it to 1216, 520, 1264, 568
      set the filled of it to true
      set the backgroundColor of it to "210,60,60"
      put the long id of graphic "pf_saw" into tRef
      set the uPfHazardFlag of tRef to true
      b2kCamAdopt tRef
      b2kAddSensor tRef, "ball"
   end if
   -- its restless twin SWEEPS the ground: a bodiless mover the lever
   -- can power down
   if gAssetsOK is true and b2kSheetHasFrame("foes", "saw_a") then
      b2kSpriteNew "foes", "saw_a", 1430, 548
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "sawspin"
         pfAddMover tRef, 1430, 548, 96, 1100, 0, 1, 38, 42, false
         put gMovN into gSawMov
         put tRef into gSawSpr
      end if
   end if
   pfMakeSlime 1, "normal", 2750, 2700, 2800, 576   -- guards the coin past the 2nd-bay crusher. (Was 4374, patrolling 4324..4460 INSIDE the green crusher alley: its sweep overlapped crushers 6@4320 and 7@4500 and it stuck to them. Crusher alleys are walker-free by convention - snails guard the APPROACH, never the gaps. The open 2590..2920 stretch gives it a real 100px patrol, 86px clear of the chained crusher at 2560.)
   -- a slow WORM crawls the run before the breather cloud (new variety;
   -- native foes art, stomps like any walker)
   pfMakeCritter 2, "normal", 1990, 1920, 2060, 576, 38, "worm_ring_move_a", "wormring", empty, 22, 26, "210,150,120", -2   -- Phase D: the second (ring) worm skin
   -- the THIRD bay's snail (snails liberally now) and a third chained crusher
   pfMakeSnail 3, 3300, 3240, 3360
   pfMakeThwomp 1, 1640
   pfMakeThwomp 2, 1840
   pfMakeThwomp 3, 2560        -- the second bay's chained crusher
   pfMakeThwomp 4, 3600        -- the third bay's chained crusher
   -- Wave 6 (bestiary II): a BARNACLE clam-trap lurks on the floor in the clear
   -- pocket between the third bay's snail and the chained crusher. It opens
   -- (telegraph) before it snaps, so a watchful run clears it; jump it if late.
   pfMakeBarnacle 1, 3460, 544
   -- a SECOND sweeping saw, ALWAYS on (the lever powers only the first):
   -- a bodiless mover hurting by proximity, sweeping the second bay floor
   if gAssetsOK is true and b2kSheetHasFrame("foes", "saw_a") then
      b2kSpriteNew "foes", "saw_a", 2880, 548
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "sawspin"
         pfAddMover tRef, 2880, 548, 92, 1050, 0, 1, 38, 42, false
      end if
   end if
   -- the GREEN CRUSHER ALLEY (the works' marquee gauntlet): a row of four
   -- green-block thwomps you time your run beneath - each drops as you near
   -- it, so keep moving and snatch the coins in the gaps. They rest STATIC
   -- then rise + re-arm, never blocking the alley for good. The GREEN
   -- SWITCH-GATE (above) now guards the approach - the redundant fourth-bay
   -- snail was retired to give that gate clear air on both sides.
   pfMakeThwomp 5, 4140, false, "block_green"
   pfMakeThwomp 6, 4320, false, "block_green"
   pfMakeThwomp 7, 4500, false, "block_green"
   pfMakeThwomp 8, 4680, false, "block_green"
   pfMakeCheckpoint 2450   -- clear flat ground past the breather cloud (was 1000, right beside the floating bonus ledge's open span - it read as "a flag over a pit"); clear of both sweeping saws too
   pfMakeGoal 6272, 416
end pfL2Cast

-- =====================================================================
-- LEVEL 3 - "FROZEN CITADEL" (6592px). Everything at once, on ICE:
-- snow ground with quarter-strength player acceleration (momentum!), the
-- Wave 5 WALL-JUMP SHAFT (climb two ice pillars to a top coin, or
-- double-jump the slot), a ladybug, the spring arcs over the first spiked
-- pit, a bonk row, the sweeping saw, a second spiked pit, a thwomp
-- guarding the RED key, then the GLACIER RUN where a ROLLING BOULDER
-- slides the ice head-on (leap it!), the blue crusher alley, the red
-- walled door, snow steps to the flag.
-- =====================================================================
command pfL3Scene
   local tX
   put "FROZEN CITADEL (icy!)" into gLevelName
   pfBounds kPfEdgeL, 6200 + kPfEndCap   -- right edge hugs the goal flag (6200); was 6592 = ~390px of dead ground past the flag
   pfSlab "pf_ground1", 0, 576, 768, 640
   pfSlab "pf_ground2", 960, 576, 1792, 640
   pfSlab "pf_ground3", 1984, 576, 6592, 640
   pfSlab "pf_plat1", 5920, 512, 6112, 576
   pfSlab "pf_plat2", 6112, 448, 6240, 576
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_snow_block_top") then
      put 0 into tX
      repeat while tX <= 704
         pfTile "terrain_snow_block_top", tX, 576
         add 64 to tX
      end repeat
      put 960 into tX
      repeat while tX <= 1728
         pfTile "terrain_snow_block_top", tX, 576
         add 64 to tX
      end repeat
      put 1984 into tX
      repeat while tX <= 6528
         pfTile "terrain_snow_block_top", tX, 576
         add 64 to tX
      end repeat
      pfTile "terrain_snow_block_top_left", 5920, 512
      pfTile "terrain_snow_block_top", 5984, 512
      pfTile "terrain_snow_block_top_right", 6048, 512
      pfTile "terrain_snow_block_top", 6112, 448
      pfTile "terrain_snow_block_top", 6176, 448
      pfTile "terrain_snow_block_center", 6112, 512
      pfTile "terrain_snow_block_center", 6176, 512
      pfShowSlabs false
   else
      pfShowSlabs true
   end if
   pfMakeSpikes 768, 960
   pfMakeSpikes 1792, 1984
   -- ===== THE WALL-JUMP SHAFT (level 3's signature vertical beat - the
   -- Wave 5 WALL-SLIDE + WALL-JUMP). Two FLOATING ICE COLUMNS frame a slot
   -- over the opening run: hug one, jump to launch up-and-away, alternate
   -- column to column to climb to the COIN dead-centre in the slot. The
   -- columns float (bottoms at y448), so the hero walks UNDER them at ground
   -- level unobstructed - the main path is never blocked. The slot coin sits
   -- where a straight DOUBLE JUMP up the gap also reaches it, so a player who
   -- has not mastered wall-jumps is never locked out (no dead end, never
   -- trick-only). Built from real 64px ICE BLOCKS (was a stretched thin slab;
   -- it reads crisp now), and the COIN is built HERE in the SCENE with the
   -- columns so it lands exactly between them (a cast-built coin can drift
   -- relative to the scene-built columns). Built on ground1, before the pit. =====
   pfSlab "pf_wjShaftL", 256, 256, 320, 448
   pfSlab "pf_wjShaftR", 408, 256, 472, 448
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_snow_block_top") then
      pfTile "terrain_snow_block_top", 256, 256
      pfTile "terrain_snow_block_center", 256, 320
      pfTile "terrain_snow_block_center", 256, 384
      pfTile "terrain_snow_block_top", 408, 256
      pfTile "terrain_snow_block_center", 408, 320
      pfTile "terrain_snow_block_center", 408, 384
   else
      set the backgroundColor of graphic "pf_wjShaftL" to "150,180,210"
      set the backgroundColor of graphic "pf_wjShaftR" to "150,180,210"
      set the visible of graphic "pf_wjShaftL" to true
      set the visible of graphic "pf_wjShaftR" to true
      b2kCamAdopt the long id of graphic "pf_wjShaftL"
      b2kCamAdopt the long id of graphic "pf_wjShaftR"
   end if
   pfMakeCoin 364, 340   -- the slot coin, dead-centre between the columns (slot 320..408, centre 364): wall-jump up (or double-jump). Built in the SCENE so it aligns with the columns.
   -- the glacier run (the level's second act): a snow cloud rest above
   -- the second sweeping saw's stretch
   b2kSmoothGround "3008,448" & cr & "2944,448" & cr & "2752,448" & cr & "2688,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_snow_cloud_left") then
      pfTile "terrain_snow_cloud_left", 2752, 448
      pfTile "terrain_snow_cloud_middle", 2816, 448
      pfTile "terrain_snow_cloud_right", 2880, 448
   else
      create graphic "pf_cloudledgeD"
      set the style of it to "line"
      set the points of it to "2752,448" & cr & "2944,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "200,220,240"
      b2kCamAdopt the long id of graphic "pf_cloudledgeD"
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "sign") then
      pfTile "sign", 3008, 512        -- a way-marker into the boulder run
   end if
   -- past the boulder run, a one-way SNOW CLOUD over a final glacier slime
   -- (ghost-padded a tile past the art each side; jump up for its coin)
   b2kSmoothGround "3956,448" & cr & "3892,448" & cr & "3700,448" & cr & "3636,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_snow_cloud_left") then
      pfTile "terrain_snow_cloud_left", 3700, 448
      pfTile "terrain_snow_cloud_middle", 3764, 448
      pfTile "terrain_snow_cloud_right", 3828, 448
   else
      create graphic "pf_cloudledgeF"
      set the style of it to "line"
      set the points of it to "3700,448" & cr & "3892,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "200,220,240"
      b2kCamAdopt the long id of graphic "pf_cloudledgeF"
   end if
   -- the BLUE CRUSHER ALLEY (the citadel's marquee gauntlet): a row of ice-
   -- block thwomps (in the cast) you run beneath, then a two-cloud HOP to the
   -- red door. Both clouds ghost-padded a tile past the art each side.
   b2kSmoothGround "5516,448" & cr & "5452,448" & cr & "5260,448" & cr & "5196,448"
   b2kSmoothGround "5736,448" & cr & "5672,448" & cr & "5480,448" & cr & "5416,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_snow_cloud_left") then
      pfTile "terrain_snow_cloud_left", 5260, 448
      pfTile "terrain_snow_cloud_middle", 5324, 448
      pfTile "terrain_snow_cloud_right", 5388, 448
      pfTile "terrain_snow_cloud_left", 5480, 448
      pfTile "terrain_snow_cloud_middle", 5544, 448
      pfTile "terrain_snow_cloud_right", 5608, 448
   else
      create graphic "pf_cloudledgeK"
      set the style of it to "line"
      set the points of it to "5260,448" & cr & "5672,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "200,220,240"
      b2kCamAdopt the long id of graphic "pf_cloudledgeK"
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "sign") then
      pfTile "sign", 4440, 512        -- a way-marker into the crusher alley
   end if
   if gToysOK is true then
      pfMakeSpring 700        -- arcs you clean over the first pit
      pfMakeBonk "brick", 1232
      pfMakeBonk "box", 1296
      pfMakeBonk "brick", 1360
      pfMakeBonk "box", 1424
      pfMakeKeyDoor 2268, 500, 5760, "red"
   end if
end pfL3Scene

command pfL3Cast
   local tRef
   -- ICE: starts and stops at ~15% strength - a full-speed stop slides
   -- about 300px, and every jump carries its momentum (knobs reset
   -- with each rebuild, so only this level skates)
   b2kPlayerSet "accel", 260
   b2kPlayerSet "airAccel", 480
   -- (the WALL-JUMP SHAFT's slot coin is built in pfL3Scene with the columns, so it stays centred between them)
   pfMakeCoin 1100, 500     -- the ladybug's beat, after the spring landing
   pfMakeGem 364, 288, "green"   -- BONUS gem atop the WALL-JUMP SHAFT (reward the full climb)
   pfMakeStar 2784, 392   -- hidden STAR: ON the snow cloud (top y448, art 2752-2944) in the glacier run
   pfMakeCoin 1300, 500     -- under the bonk row
   pfMakeCoin 1640, 448     -- above the first sweeping saw
   pfMakeCoin 1888, 440     -- mid-air over the second pit
   pfMakeCoin 2113, 500     -- the snow slime's beat
   pfMakeCoin 2608, 448     -- above the SECOND sweeping saw (no lever here)
   pfMakeCoin 2848, 392     -- on the snow cloud
   pfMakeCoin 3250, 500     -- in the boulder run: snatch it between slides
   pfMakeCoin 3640, 500     -- the final glacier slime's beat
   pfMakeCoin 3796, 392     -- up on the second snow cloud
   pfMakeCoin 4040, 500     -- the glacier snail's beat (shell it, kick it)
   pfMakeCoin 4280, 500     -- beneath the chained thwomp: grab it as you dash under
   pfMakeCoin 4420, 500     -- the citadel snail's beat (shell it, kick it)
   pfMakeCoin 4650, 500     -- threading the BLUE CRUSHER alley: grab between drops
   pfMakeCoin 4830, 500     -- ...and between the next pair of crushers
   pfMakeCoin 5010, 500     -- ...and the last gap
   pfMakeCoin 5324, 392     -- up on the first hop cloud
   pfMakeCoin 5544, 392     -- up on the second hop cloud, before the door
   pfMakeCoin 6050, 448     -- over the first snow step
   pfMakeCoin 6145, 392     -- over the top step, by the flag
   if gToysOK is true then
      pfMakeCoin 864, 300   -- over the first pit: ride the spring's arc
      pfMakeCoin 5856, 500  -- just PAST the red door (still gated by it), clear of the closed-door face (was 5808 on the door tile)
   end if
   if gAssetsOK is true and b2kSheetHasFrame("foes", "saw_a") then
      b2kSpriteNew "foes", "saw_a", 1640, 548
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "sawspin"
         pfAddMover tRef, 1640, 548, 96, 1100, 0, 1, 38, 42, false
         put gMovN into gSawMov
         put tRef into gSawSpr
      end if
   end if
   -- the glacier run's saw: always on (the lever stayed in level 2)
   if gAssetsOK is true and b2kSheetHasFrame("foes", "saw_a") then
      b2kSpriteNew "foes", "saw_a", 2608, 548
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "sawspin"
         pfAddMover tRef, 2608, 548, 96, 1000, 0, 1, 38, 42, false
      end if
   end if
   pfMakeSlime 1, "normal", 2113, 2078, 2118, 576   -- right limit pulled IN off the crusher: at 2148 its right edge (2172) all but touched the crusher body (left 2178 - a 6px gap) and the two stuck together; 2118 -> far edge 2142 clears the crusher by 36px (the slime body is 48px wide). Coin stays at 2113, inside the band.
   -- a LADYBUG ambles the early ice (new variety; native foes art)
   pfMakeCritter 2, "normal", 1100, 1010, 1180, 576, 64, "ladybug_walk_a", "ladywalk", empty, 22, 30, "200,70,70", -4, empty, true   -- ladybug art faces LEFT: pFaceFlip true
   pfMakeThwomp 1, 2208     -- it guards the red key
   -- the glacier's ROLLING ICE BOULDER: it slides the icy flat HEAD-ON at
   -- the climbing hero, who must leap it (jumping lifts him clear of the
   -- poll). It passes through him (b2kNoCollide) and SLIDES ALL THE WAY
   -- off-screen left (reset line 2300, well past the run and below the
   -- camera's left edge) before a fresh one comes from the source - no
   -- teleport-in-place. Built in the CAST so the hero exists.
   pfMakeBoulder 3450, 549, 2300, -320
   -- a final glacier slime under the second snow cloud, clear to the right
   -- of the boulder's home so the parked stone never jostles it
   pfMakeSlime 3, "normal", 3640, 3580, 3700, 576
   -- the citadel's final stretch: a SNAIL and the classic chained THWOMP
   -- back, guarding the run to the red door
   pfMakeSnail 4, 4040, 3980, 4100
   pfMakeThwomp 2, 4280
   -- the BLUE CRUSHER ALLEY (the citadel's marquee gauntlet): a row of four
   -- ice-block thwomps you time your run beneath - each drops as you near it,
   -- so keep moving and snatch the coins in the gaps. A glacier SNAIL guards
   -- the approach (snails liberally).
   pfMakeSnail 5, 4420, 4390, 4450
   pfMakeThwomp 3, 4560, false, "block_blue"
   pfMakeThwomp 4, 4740, false, "block_blue"
   pfMakeThwomp 5, 4920, false, "block_blue"
   pfMakeThwomp 6, 5100, false, "block_blue"
   -- Phase E: a SNAKE slithers the second ice platform, auto-turning at the
   -- right spike pit (the new slither movement; clear of the ladybug's band).
   pfMakeSnake 6, 1450, 1250, 1792, 576
   pfMakeCheckpoint 2048
   if gToysOK is true then pfMakeDebrisPool   -- this level has bricks
   pfMakeGoal 6200, 416
end pfL3Cast

-- =====================================================================
-- LEVEL 4 - "HAUNTED HOLLOW" (6656px). Wave 3's bestiary in the purple
-- biome: a MIMIC field (grass blocks that do not belong), the SNAIL
-- whose kicked shell bowls a slime over, the BAT overhang, a pit, a long
-- FOUR-burrow PIRANHA row, the GHOST stalking the back half, a faced
-- CRUSHER guarding a WIDE lava pit crossed in two hops over a middle
-- stepping-stone that a rearing LAVA SERPENT contests at its peak, a
-- smouldering FIRE SLIME, then the POWDER KEG bay (an explosive barrel + woodpile,
-- scattered by b2kExplode), the red crusher alley (the signature
-- gauntlet), purple steps to the flag. Every beat spaced per the
-- layout law (~100px+ of clear air).
-- =====================================================================
command pfL4Scene
   local tX, tH, tHi
   put "HAUNTED HOLLOW (spooky!)" into gLevelName
   pfBounds kPfEdgeL, 6524 + kPfEndCap   -- right edge hugs the goal flag (6524)
   pfSlab "pf_ground1", 0, 576, 1856, 640
   -- the ground BREAKS at a WIDE lava pit (2944..3456, 512px): two bank slabs
   -- with a middle STEPPING-STONE (pf_lavastep), so the crossing is TWO ~160px
   -- hops, not one - and the lava serpent rears up to the stone at its peak.
   pfSlab "pf_ground2", 2048, 576, 2944, 640
   pfSlab "pf_ground3", 3456, 576, 6656, 640
   pfSlab "pf_lavastep", 3104, 490, 3296, 554   -- the mid-lava stepping-stone (deck y490 = the serpent's peak)
   pfSlab "pf_plat1", 6240, 512, 6432, 576
   pfSlab "pf_plat2", 6432, 448, 6560, 576
   -- the bat overhang: a stone bar the bats roost under
   pfSlab "pf_batbar", 1472, 256, 1856, 320
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_purple_block_top") then
      put 0 into tX
      repeat while tX <= 1792
         pfTile "terrain_purple_block_top", tX, 576
         add 64 to tX
      end repeat
      put 2048 into tX
      repeat while tX <= 6592
         if tX >= 2944 and tX < 3456 then next repeat   -- leave the WIDE LAVA PIT open
         pfTile "terrain_purple_block_top", tX, 576
         add 64 to tX
      end repeat
      -- the mid-lava stepping-stone, tiled to match its slab (deck y490): L/M/R
      pfTile "terrain_purple_block_top_left", 3104, 490
      pfTile "terrain_purple_block_top", 3168, 490
      pfTile "terrain_purple_block_top_right", 3232, 490
      pfTile "terrain_purple_block_top_left", 6240, 512
      pfTile "terrain_purple_block_top", 6304, 512
      pfTile "terrain_purple_block_top_right", 6368, 512
      pfTile "terrain_purple_block_top", 6432, 448
      pfTile "terrain_purple_block_top", 6496, 448
      pfTile "terrain_purple_block_center", 6432, 512
      pfTile "terrain_purple_block_center", 6496, 512
      pfTile "terrain_purple_horizontal_left", 1472, 256
      pfTile "terrain_purple_horizontal_middle", 1536, 256
      pfTile "terrain_purple_horizontal_middle", 1600, 256
      pfTile "terrain_purple_horizontal_middle", 1664, 256
      pfTile "terrain_purple_horizontal_middle", 1728, 256
      pfTile "terrain_purple_horizontal_right", 1792, 256
      pfShowSlabs false
   else
      pfShowSlabs true
   end if
   -- the FOUR piranha burrow mouths (the row is twice as long now), drawn
   -- by the SCENE so every later sprite (the plants included) layers above
   set the itemDelimiter to comma
   put 0 into tHi
   repeat for each item tH in "2340,2490,2640,2790"
      add 1 to tHi
      create graphic ("pf_hole" & tHi)
      set the style of it to "oval"
      set the rect of it to tH - 24, 566, tH + 24, 590
      set the filled of it to true
      set the backgroundColor of it to "30,24,40"
      b2kCamAdopt the long id of graphic ("pf_hole" & tHi)
   end repeat
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "grass_purple") then
      pfTile "grass_purple", 320, 512
      pfTile "grass_purple", 1100, 512
      pfTile "grass_purple", 2240, 512
   end if   -- (the 2920 tuft was removed: it now sat at the widened lava lip; a 3960 tuft went earlier - it hid the 4000 coin)
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "sign") then
      pfTile "sign", 2860, 512        -- a way-marker past the piranha row, before the lava pit
   end if
   -- the LAVA SERPENT is created BEFORE pfMakeLava so the lava tiles (the y576
   -- row) draw OVER its lower body - it reads as rising OUT of the lava. It rears
   -- to the stepping-stone deck (y490) at its peak over the pit centre (x3200),
   -- CONTESTING the stone: time your two hops between its rises. Bodiless, the
   -- saw rule (gotcha 16) - a recoverable proximity knockback, never a stomp.
   pfMakeSerpent 2944, 3456, 596, 490, "snakeLava.png", "snakelava"
   -- the WIDE lava pit (2944..3456, 512px - a real widening from the old 192px
   -- bridge strip) with a low hurt-top (y596) so a hero ON the banks / the
   -- stepping-stone is clear, but a slip INTO the lava burns. Crossed in TWO
   -- ~160px hops (near bank -> stepping-stone -> far bank): a confident running
   -- jump, a double-jump as insurance (the L2 lift bay's ~200px reach). The single
   -- faced CRUSHER (3040) guards the approach - the far-bank twin was retired to
   -- de-cram the pit. A slip onto the lava is a knockback (pfOuch) back to a bank.
   pfMakeLava 2944, 3456, 596
   -- the POWDER KEG bay (scenery, so it layers behind the hero): an
   -- explosive barrel ringed by a small PYRAMID of crates. Coming near lights
   -- the fuse and b2kExplode (the kit's native radial blast, dark in the
   -- demo until now) scatters the pile and clears the barrel.
   pfMakeBarrel 3732, 550
   -- the pyramid: a four-crate base flanking the barrel, a crate bridging each
   -- outer pair, and one capping the barrel (dynamic + fixed-rotation, so it holds)
   pfMakeWoodCrate 3644, 554
   pfMakeWoodCrate 3688, 554
   pfMakeWoodCrate 3776, 554
   pfMakeWoodCrate 3820, 554
   pfMakeWoodCrate 3666, 510
   pfMakeWoodCrate 3798, 510
   pfMakeWoodCrate 3732, 502
   -- the RED CRUSHER ALLEY (the hollow's marquee gauntlet): a row of danger-
   -- block thwomps (in the cast) you run beneath, then a two-cloud HOP to the
   -- purple steps. Both clouds ghost-padded a tile past the art each side.
   b2kSmoothGround "5956,448" & cr & "5892,448" & cr & "5700,448" & cr & "5636,448"
   b2kSmoothGround "6176,448" & cr & "6112,448" & cr & "5920,448" & cr & "5856,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_purple_cloud_left") then
      pfTile "terrain_purple_cloud_left", 5700, 448
      pfTile "terrain_purple_cloud_middle", 5764, 448
      pfTile "terrain_purple_cloud_right", 5828, 448
      pfTile "terrain_purple_cloud_left", 5920, 448
      pfTile "terrain_purple_cloud_middle", 5984, 448
      pfTile "terrain_purple_cloud_right", 6048, 448
   else
      create graphic "pf_cloudledgeL"
      set the style of it to "line"
      set the points of it to "5700,448" & cr & "6112,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "150,110,190"
      b2kCamAdopt the long id of graphic "pf_cloudledgeL"
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "sign") then
      pfTile "sign", 4900, 512        -- a way-marker into the crusher alley
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "grass_purple") then
      pfTile "grass_purple", 5640, 512
   end if
   -- Wave 6 (bestiary II): the SPIDER's overhang - a short purple bar over the
   -- run up to the chained crusher. Drawn ONLY when the spooks sheet is present
   -- (the spider that hangs from it is optional art). Visual only and at y256,
   -- out of jump reach, so it never blocks the ground beneath it.
   if gSpooksOK is true and gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_purple_horizontal_left") then
      pfTile "terrain_purple_horizontal_left", 4352, 256
      pfTile "terrain_purple_horizontal_right", 4416, 256
   end if
end pfL4Scene

command pfL4Cast
   local tRef
   pfMakeCoin 544, 470      -- between the two things that are not grass
   pfMakeCoin 980, 500      -- the snail's beat (shell it, kick it)
   pfMakeCoin 1255, 500     -- the slime its shell can bowl over
   pfMakeCoin 1664, 500     -- under the bat roost - they drop
   pfMakeCoin 1952, 430     -- mid-air over the pit
   pfMakeCoin 2415, 480     -- threading the FOUR-burrow piranha row: time
   pfMakeGem 2415, 408, "red"   -- BONUS gem high over the piranha row (a risky double-jump grab)
   pfMakeStar 3140, 434   -- hidden STAR: ON the mid-lava stepping-stone (top y490, span 3104-3296) - grab it mid-crossing, between serpent rises
   pfMakeCoin 2565, 480     -- the bites and snatch a coin between each pair
   pfMakeCoin 2715, 480
   pfMakeCoin 3200, 450     -- up on the mid-lava STEPPING-STONE: grab it between the serpent's rises
   pfMakeCoin 3540, 500     -- the fire slime's beat, fresh from the lava on the far bank
   pfMakeCoin 3892, 500     -- past the powder keg (the lure: mind the blast)
   pfMakeCoin 4000, 500     -- the second snail's beat (shell it, kick it!)
   pfMakeCoin 4220, 500     -- the slime its bowled shell can flatten
   pfMakeCoin 4440, 500     -- on the run up to the chained crusher
   pfMakeCoin 4600, 500     -- beneath the chained crusher: grab it as you dash under
   pfMakeCoin 4780, 500     -- past the crusher, into the red alley
   pfMakeCoin 5090, 500     -- threading the RED CRUSHER alley: grab between drops
   pfMakeCoin 5270, 500     -- ...and between the next pair of crushers
   pfMakeCoin 5450, 500     -- ...and the last gap
   pfMakeCoin 5764, 392     -- up on the first hop cloud
   pfMakeCoin 5984, 392     -- up on the second hop cloud, by the steps
   pfMakeCoin 6336, 448     -- over the first purple step
   pfMakeCoin 6464, 392     -- over the top step, by the flag
   pfMakeSnail 1, 980, 880, 1080
   pfMakeSlime 2, "normal", 1255, 1180, 1330, 576
   -- split patrol bands: two flying BODIES sharing one band would
   -- collide mid-bar and fight their velocity asserts (jitter)
   pfMakeBat 3, 1568, 344, 1490, 1650
   pfMakeBat 4, 1728, 344, 1690, 1840
   pfMakeMimic 5, 448
   pfMakeMimic 6, 640
   -- the piranha row, twice as long now: FOUR burrows cycling on their
   -- own staggered timers (the ghost stalks this whole stretch)
   pfMakePlant 1, 2340
   pfMakePlant 2, 2490
   pfMakePlant 3, 2640
   pfMakePlant 4, 2790
   pfMakeGhost 2240, 360
   pfMakeThwomp 1, 3040, true   -- the faced CRUSHER guards the lava-pit approach (the far-bank twin was retired to de-cram the widened pit)
   -- a FIRE SLIME smoulders in the bay between the lava and the powder keg
   -- (spike-type: it hurts from every side - you do not stomp a slime on fire).
   -- Its band stops at 3560 (right edge ~3584) so it never wades into the crate
   -- pyramid at 3644 (the earlier 3600 band jammed its body against the crates).
   pfMakeCritter 7, "spike", 3522, 3484, 3560, 576, 52, "slime_fire_walk_a", "firewalk", "slime_fire_flat", 24, 36, "230,120,60", -6
   -- a final BOWLING LANE past the keg: a second snail to shell + kick,
   -- and a slime its sliding shell flattens - the haunted level escalates
   pfMakeSnail 8, 4000, 3940, 4060
   pfMakeSlime 9, "normal", 4220, 4160, 4280, 576
   -- the haunted FINALE: the classic chained-weight THWOMP comes back among
   -- the faced crushers. (Trimmed from four snails to two for the showcase
   -- pass - the bowling-lane snail above is plenty; the alley reads cleaner.)
   pfMakeThwomp 3, 4600
   -- Wave 6 (bestiary II): a SPIDER crawls the overhang over the run to the
   -- chained crusher and DROPS as you pass under it (grab the 4440 coin while
   -- you dodge). Optional (Family C art); a missing spooks sheet skips it.
   pfMakeSpider 1, 4416, 4368, 4464, 336
   -- the RED CRUSHER ALLEY (the hollow's marquee gauntlet): a row of four
   -- danger-block thwomps you time your run beneath - each drops as you near
   -- it, so keep moving and snatch the coins in the gaps. The haunted level's
   -- last test before the flag.
   pfMakeThwomp 4, 5000, false, "block_red"
   pfMakeThwomp 5, 5180, false, "block_red"
   pfMakeThwomp 6, 5360, false, "block_red"
   pfMakeThwomp 7, 5540, false, "block_red"
   -- Phase E: a plain SNAKE slithers the lava-pit APPROACH, auto-reversing at the
   -- entry pit (2048) and the lava lip (2944) - the floor-probe slither, so it
   -- never falls in. The rearing LAVA SERPENT over the pit itself is bodiless and
   -- built in the SCENE (it must live under the lava tiles).
   pfMakeSnake 10, 2500, 2048, 2944, 576
   pfMakeCheckpoint 2160
   pfMakeGoal 6524, 416
end pfL4Cast

-- =====================================================================
-- LEVEL 5 - "SCORCHED DUNES" (Wave 7, the DESERT biome): sand ground with a
-- DUNE (sand-ramp slope), a THORN PIT to leap, a two-cloud HOP, then the Wave
-- 6 bestiary given ROOM - a frog in the open, a barnacle clam - and sand steps
-- to the flag. (No spider here: a ceiling-crawler needs a ceiling, and a sand
-- bar floating in the open desert sky read as a glitch - the spider stays in
-- L4's cave.) GENEROUSLY spaced: the layout was audited before building, so
-- every beat gets 250px+ of clear air (the answer to Wave 6's crowding).
-- =====================================================================
command pfL5Scene
   local tX
   put "SCORCHED DUNES (hot!)" into gLevelName
   -- the dunes run LONG now (the asset-expansion length + variety pass): THREE
   -- acts across ~6300px and three THORN PITS - the entry dune, a BOULDER dune
   -- with a fire-slime run, then the deep desert past the treasure mimic to the
   -- summit flag. FOUR sand floors with three spiked chasms between them.
   pfBounds kPfEdgeL, 6400
   pfSlab "pf_ground1", 0, 576, 2000, 640
   pfSlab "pf_ground2", 2256, 576, 3840, 640
   pfSlab "pf_ground3", 4096, 576, 5376, 640
   pfSlab "pf_ground4", 5568, 576, 6400, 640
   pfSlab "pf_plat1", 6080, 512, 6272, 576
   pfSlab "pf_plat2", 6272, 448, 6400, 576
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_sand_block_top") then
      put 0 into tX
      repeat while tX <= 1936
         if tX >= 864 and tX <= 1184 then
            pfTile "terrain_sand_block_center", tX, 576   -- under the first dune: one mass
         else
            pfTile "terrain_sand_block_top", tX, 576
         end if
         add 64 to tX
      end repeat
      put 2256 into tX
      repeat while tX <= 3776
         pfTile "terrain_sand_block_top", tX, 576
         add 64 to tX
      end repeat
      put 4096 into tX
      repeat while tX <= 5312
         if tX >= 4352 and tX <= 4672 then
            pfTile "terrain_sand_block_center", tX, 576   -- under the second (boulder) dune
         else
            pfTile "terrain_sand_block_top", tX, 576
         end if
         add 64 to tX
      end repeat
      put 5568 into tX
      repeat while tX <= 6016
         pfTile "terrain_sand_block_top", tX, 576
         add 64 to tX
      end repeat
      pfTile "terrain_sand_block_top_left", 6080, 512
      pfTile "terrain_sand_block_top", 6144, 512
      pfTile "terrain_sand_block_top_right", 6208, 512
      pfTile "terrain_sand_block_top", 6272, 448
      pfTile "terrain_sand_block_top", 6336, 448
      pfTile "terrain_sand_block_center", 6272, 512
      pfTile "terrain_sand_block_center", 6336, 512
      pfShowSlabs false
   else
      pfShowSlabs true
   end if
   -- the DUNE (26.6-degree sand ramps; the L1 mound recipe in sand): six chain
   -- points, the outer two non-colliding ghost anchors; ramps mirrored
   b2kSmoothGround "1312,576" & cr & "1248,576" & cr & "1120,512" & cr & "992,512" & cr & "864,576" & cr & "800,576"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_sand_ramp_long_a") then
      pfTile "terrain_sand_ramp_long_b", 864, 512, true
      pfTile "terrain_sand_ramp_long_a", 928, 512, true
      pfTile "terrain_sand_block_top", 992, 512
      pfTile "terrain_sand_block_top", 1056, 512
      pfTile "terrain_sand_ramp_long_a", 1120, 512
      pfTile "terrain_sand_ramp_long_b", 1184, 512
   else
      create graphic "pf_dune"
      set the style of it to "polygon"
      set the points of it to "864,576" & cr & "992,512" & cr & "1120,512" & cr & "1248,576" & cr & "864,576"
      set the filled of it to true
      set the backgroundColor of it to "200,170,110"
      b2kCamAdopt the long id of graphic "pf_dune"
   end if
   -- PIT1 - the THORN PIT (leap it; a slip burns then drops to the kill floor):
   -- 256px (FOUR spikes), spike tips flush with the floor line. The checkpoint
   -- at the brink (1900) makes a slip a quick retry.
   pfMakeSpikes 2000, 2256
   -- the two-cloud HOP (one-way sand clouds, each ghost-padded a tile past the
   -- art each side): jump up for the coins, DOWN+JUMP to drop off
   b2kSmoothGround "2640,448" & cr & "2576,448" & cr & "2384,448" & cr & "2320,448"
   b2kSmoothGround "2944,448" & cr & "2880,448" & cr & "2688,448" & cr & "2624,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_sand_cloud_left") then
      pfTile "terrain_sand_cloud_left", 2384, 448
      pfTile "terrain_sand_cloud_middle", 2448, 448
      pfTile "terrain_sand_cloud_right", 2512, 448
      pfTile "terrain_sand_cloud_left", 2688, 448
      pfTile "terrain_sand_cloud_middle", 2752, 448
      pfTile "terrain_sand_cloud_right", 2816, 448
   else
      create graphic "pf_cloudledgeM"
      set the style of it to "line"
      set the points of it to "2384,448" & cr & "2576,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "200,170,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeM"
      create graphic "pf_cloudledgeN"
      set the style of it to "line"
      set the points of it to "2688,448" & cr & "2880,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "200,170,110"
      b2kCamAdopt the long id of graphic "pf_cloudledgeN"
   end if
   -- ===== ACT 2/3 terrain (the length + variety pass) =====
   -- PIT2 - a second THORN chasm (256px, four spikes) onto the boulder bank.
   pfMakeSpikes 3840, 4096
   -- the SECOND DUNE - a sand mound a BOULDER rolls DOWN at you (crest 4480..4608,
   -- mirror the Act 1 recipe). The boulder lives in the cast; it rolls to 4160
   -- and re-parks, so the far bank you land on stays safe.
   b2kSmoothGround "4800,576" & cr & "4736,576" & cr & "4608,512" & cr & "4480,512" & cr & "4352,576" & cr & "4288,576"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_sand_ramp_long_a") then
      pfTile "terrain_sand_ramp_long_b", 4352, 512, true
      pfTile "terrain_sand_ramp_long_a", 4416, 512, true
      pfTile "terrain_sand_block_top", 4480, 512
      pfTile "terrain_sand_block_top", 4544, 512
      pfTile "terrain_sand_ramp_long_a", 4608, 512
      pfTile "terrain_sand_ramp_long_b", 4672, 512
   end if
   -- a one-way SAND CLOUD high route over the fire-slime run (solid 4928..5120),
   -- and a final one on G4 (solid 5696..5888) - both ghost-padded a tile each side.
   b2kSmoothGround "5184,448" & cr & "5120,448" & cr & "4928,448" & cr & "4864,448"
   b2kSmoothGround "5952,448" & cr & "5888,448" & cr & "5696,448" & cr & "5632,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_sand_cloud_left") then
      pfTile "terrain_sand_cloud_left", 4928, 448
      pfTile "terrain_sand_cloud_middle", 4992, 448
      pfTile "terrain_sand_cloud_right", 5056, 448
      pfTile "terrain_sand_cloud_left", 5696, 448
      pfTile "terrain_sand_cloud_middle", 5760, 448
      pfTile "terrain_sand_cloud_right", 5824, 448
   end if
   -- PIT3 - the last THORN chasm (192px, three spikes) before the summit run.
   pfMakeSpikes 5376, 5568
   -- desert decor, placed clear of every beat (cacti, a rock, the way-markers)
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "cactus") then
      pfTile "sign", 160, 512
      pfTile "cactus", 320, 512
      pfTile "cactus", 1700, 512
      pfTile "cactus", 2300, 512
      pfTile "rock", 3520, 512
      pfTile "cactus", 4760, 512
      pfTile "rock", 6020, 512
   end if
end pfL5Scene

command pfL5Cast
   local tRef
   -- ACT 1 coins (the entry dune + the thorn pit + the cloud hop)
   pfMakeCoin 480, 500      -- the opening run
   pfMakeCoin 680, 500      -- the sand slime's beat
   pfMakeCoin 1056, 460     -- atop the dune (jump it as you crest)
   pfMakeCoin 1500, 500     -- the desert frog's beat (stomp it; do not stand by it)
   pfMakeCoin 2128, 440     -- mid-air over PIT1: leap it
   pfMakeCoin 2480, 392     -- on the first sand cloud
   pfMakeCoin 2784, 392     -- on the second sand cloud
   pfMakeCoin 3000, 500     -- the snail's beat (shell it, kick it)
   pfMakeCoin 3260, 500     -- past the barnacle, on the run to PIT2
   -- ACT 2 coins (the boulder dune + the fire-slime run)
   pfMakeCoin 3520, 500     -- the open run to PIT2
   pfMakeCoin 3968, 440     -- mid-air over PIT2: leap it
   pfMakeCoin 4160, 500     -- landing on the boulder bank
   pfMakeCoin 4280, 500     -- approaching the dune (mind the boulder rolling down)
   pfMakeCoin 4544, 452     -- atop the boulder dune (grab it as you crest)
   pfMakeCoin 4720, 500     -- down the far side of the dune
   pfMakeCoin 5024, 408     -- on the sand cloud (the high route over the fire slime)
   pfMakeCoin 5240, 500     -- the second frog's beat
   -- ACT 3 coins (the deep desert + the summit)
   pfMakeCoin 5472, 440     -- mid-air over PIT3: leap it
   pfMakeCoin 5700, 500     -- the treasure mimic's beat (chest, or not?)
   pfMakeCoin 5792, 408     -- on the final sand cloud (the high route)
   pfMakeCoin 5888, 408     -- ...and along it
   pfMakeCoin 5980, 500     -- the homeward snail's beat
   pfMakeCoin 6160, 460     -- over the first sand step
   pfMakeCoin 6240, 460     -- on the climb to the summit (clear of the flag)
   pfMakeGem 1056, 400, "blue"   -- BONUS gem above the dune crest (double-jump for it)
   pfMakeStar 4960, 392   -- hidden STAR: ON the act-2 sand cloud (top y448, art 4928-5120), deep in the dunes
   -- ACT 1 cast
   pfMakeSlime 1, "normal", 680, 620, 760, 576
   pfMakeFrog 2, 1500, 1420, 1620, 576
   -- Phase E: a SAND SNAKE slithers the open dune stretch before the snail (auto-
   -- reverses at its band ends; clear of the snail at 2940). Optional spooks art.
   pfMakeSnake 8, 2550, 2350, 2850, 576
   pfMakeSnail 3, 3000, 2940, 3060
   pfMakeBarnacle 1, 3300, 544
   -- ACT 2 cast: a desert FLY, a BOULDER rolling the dune, a FIRE slime, a 2nd frog
   if gAssetsOK is true and b2kSheetHasFrame("foes", "fly_a") then
      b2kSpriteNew "foes", "fly_a", 4700, 380
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "flit"
         pfAddMover tRef, 4700, 380, 80, 720, 50, 450, 36, 44, true
      end if
   end if
   pfMakeBoulder 4544, 458, 4160, -90    -- a sand BOULDER rolls down the dune at you, re-parks at 4160
   pfMakeCritter 4, "spike", 5000, 4940, 5060, 576, 52, "slime_fire_walk_a", "firewalk", "slime_fire_flat", 24, 36, "230,120,60", -6   -- a FIRE slime (scorched!): no stomp
   pfMakeFrog 5, 5240, 5160, 5320, 576
   -- ACT 3 cast: a treasure MIMIC, a 2nd fly, a homeward snail
   pfMakeMimic 6, 5700
   if gAssetsOK is true and b2kSheetHasFrame("foes", "fly_a") then
      b2kSpriteNew "foes", "fly_a", 5850, 380
      put the result into tRef
      if tRef is not empty then
         b2kSpritePlay tRef, "flit"
         pfAddMover tRef, 5850, 380, 90, 760, 40, 470, 36, 44, true
      end if
   end if
   pfMakeSnail 7, 5980, 5920, 6040
   pfMakeCheckpoint 1900    -- at the brink of PIT1: a slip is a retry, not a replay
   pfMakeCheckpoint 4160    -- past PIT2, on the boulder bank
   pfMakeCheckpoint 5632    -- past PIT3, before the summit run
   pfMakeGoal 6336, 416
end pfL5Cast


-- =====================================================================
-- LEVEL 6 - "CAVERN DEPTHS" (asset-expansion Phase B, the DIRT biome):
-- the underground level. The whole terrain_dirt_* tile set was UNUSED
-- before this - block tops, carved cliff CORNERS on the goal steps,
-- DIRT RAMPS for the mound, a one-way DIRT CLOUD, and a WALL-JUMP SHAFT
-- of floating dirt columns. Backdrop is the (also unused) dark
-- background_solid_dirt. Built on proven L3/L5 recipes (chains ghost-
-- padded a tile past the art each side; goal-step corners; pits a 64px
-- multiple). Slice 1 reuses the existing slime/snail cast; the block
-- slime and the conveyor (Phase B's headline mechanics) land in the
-- next slices.
-- =====================================================================
command pfL6Scene
   local tX
   put "CAVERN DEPTHS (deep!)" into gLevelName
   -- the cavern runs DEEP now (the asset-expansion LENGTH + variety pass): THREE
   -- acts across ~6300px - the entry shaft, a CRUSHER GALLERY under bat-hung
   -- overhangs, then the DEEP RUN past a dropping spider, a stalking ghost and a
   -- rolling boulder to the flag. FOUR floors with three pits between them: PIT1
   -- spikes (1088..1280), PIT2 spikes (3520..3776), PIT3 a spiked chasm a lift
   -- ferries (4736..4928). Every pit is still double-jumpable (the lift is flair).
   pfBounds kPfEdgeL, 6400
   pfSlab "pf_ground1", 0, 576, 1088, 640
   pfSlab "pf_ground2", 1280, 576, 3520, 640
   pfSlab "pf_ground3", 3776, 576, 4736, 640
   pfSlab "pf_ground4", 4928, 576, 6400, 640
   pfSlab "pf_plat1", 6016, 512, 6208, 576
   pfSlab "pf_plat2", 6208, 448, 6400, 576
   -- the DIRT biome's tiling: block tops across every floor (block_center under
   -- the ramp mound's mass), carved CLIFF CORNERS at the pit edges, finished
   -- steps at the goal climb. terrain_dirt_* was entirely unused before L6.
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_dirt_block_top") then
      put 0 into tX
      repeat while tX <= 960
         pfTile "terrain_dirt_block_top", tX, 576
         add 64 to tX
      end repeat
      pfTile "terrain_dirt_block_top_right", 1024, 576   -- carved LEFT lip of PIT1
      pfTile "terrain_dirt_block_top_left", 1280, 576    -- carved RIGHT lip of PIT1
      put 1344 into tX
      repeat while tX <= 3392
         if tX >= 1408 and tX <= 1792 then
            pfTile "terrain_dirt_block_center", tX, 576   -- under the dirt mound: one mass
         else
            pfTile "terrain_dirt_block_top", tX, 576
         end if
         add 64 to tX
      end repeat
      pfTile "terrain_dirt_block_top_right", 3456, 576   -- carved LEFT lip of PIT2
      pfTile "terrain_dirt_block_top_left", 3776, 576    -- carved RIGHT lip of PIT2
      put 3840 into tX
      repeat while tX <= 4608
         pfTile "terrain_dirt_block_top", tX, 576
         add 64 to tX
      end repeat
      pfTile "terrain_dirt_block_top_right", 4672, 576   -- carved LEFT lip of PIT3
      pfTile "terrain_dirt_block_top_left", 4928, 576    -- carved RIGHT lip of PIT3
      put 4992 into tX
      repeat while tX <= 5952
         pfTile "terrain_dirt_block_top", tX, 576
         add 64 to tX
      end repeat
      pfTile "terrain_dirt_block_top_left", 6016, 512    -- the goal climb's finished steps
      pfTile "terrain_dirt_block_top", 6080, 512
      pfTile "terrain_dirt_block_top_right", 6144, 512
      pfTile "terrain_dirt_block_top", 6208, 448
      pfTile "terrain_dirt_block_top", 6272, 448
      pfTile "terrain_dirt_block_top", 6336, 448
      pfTile "terrain_dirt_block_center", 6208, 512
      pfTile "terrain_dirt_block_center", 6272, 512
      pfTile "terrain_dirt_block_center", 6336, 512
      pfShowSlabs false
   else
      pfShowSlabs true
   end if
   -- the WALL-JUMP SHAFT (a cave beat; the dirt biome's vertical walls): two
   -- FLOATING dirt columns frame a slot over the entry run - wall-jump up it
   -- (or double-jump the slot) for the slot coin. The columns float (bottoms
   -- at y448) so the main path runs UNDER them, never blocked - the L3 ice-
   -- shaft recipe in dirt. The slot coin is built HERE in the SCENE so it
   -- lands dead-centre between the columns (a cast coin can drift relative to
   -- the scene-built columns).
   pfSlab "pf_wjShaftL", 320, 256, 384, 448
   pfSlab "pf_wjShaftR", 472, 256, 536, 448
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_dirt_block_top") then
      pfTile "terrain_dirt_block_top", 320, 256
      pfTile "terrain_dirt_block_center", 320, 320
      pfTile "terrain_dirt_block_center", 320, 384
      pfTile "terrain_dirt_block_top", 472, 256
      pfTile "terrain_dirt_block_center", 472, 320
      pfTile "terrain_dirt_block_center", 472, 384
   else
      set the backgroundColor of graphic "pf_wjShaftL" to "120,90,60"
      set the backgroundColor of graphic "pf_wjShaftR" to "120,90,60"
      set the visible of graphic "pf_wjShaftL" to true
      set the visible of graphic "pf_wjShaftR" to true
      b2kCamAdopt the long id of graphic "pf_wjShaftL"
      b2kCamAdopt the long id of graphic "pf_wjShaftR"
   end if
   pfMakeCoin 428, 340   -- the slot coin, dead-centre between the columns (slot 384..472, centre 428): wall-jump up, or double-jump. Built in the SCENE so it aligns with the columns.
   -- PIT1 - the CAVERN GAP: spikes seated FLUSH at the pit edge (192px = three
   -- spikes); leap it - the checkpoint sits just past it.
   pfMakeSpikes 1088, 1280
   -- a DIRT RAMP mound (the dirt biome's slopes): up the left ramp, across the
   -- crest, down the right. The six-point chain's outer two points are ghost
   -- anchors (chain ghost rule); the ramps are mirrored.
   b2kSmoothGround "1856,576" & cr & "1792,576" & cr & "1664,512" & cr & "1536,512" & cr & "1408,576" & cr & "1344,576"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_dirt_ramp_long_a") then
      pfTile "terrain_dirt_ramp_long_b", 1408, 512, true
      pfTile "terrain_dirt_ramp_long_a", 1472, 512, true
      pfTile "terrain_dirt_block_top", 1536, 512
      pfTile "terrain_dirt_block_top", 1600, 512
      pfTile "terrain_dirt_ramp_long_a", 1664, 512
      pfTile "terrain_dirt_ramp_long_b", 1728, 512
   end if
   -- a one-way DIRT CLOUD (drop through with DOWN+JUMP) for the high bonus
   -- route; ghost-padded a tile past the art each side (solid span 1984..2176).
   b2kSmoothGround "2240,448" & cr & "2176,448" & cr & "1984,448" & cr & "1920,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_dirt_cloud_left") then
      pfTile "terrain_dirt_cloud_left", 1984, 448
      pfTile "terrain_dirt_cloud_middle", 2048, 448
      pfTile "terrain_dirt_cloud_right", 2112, 448
   else
      create graphic "pf_cloudledgeP"
      set the style of it to "line"
      set the points of it to "1984,448" & cr & "2176,448"
      set the lineSize of it to 4
      set the foregroundColor of it to "150,120,90"
      b2kCamAdopt the long id of graphic "pf_cloudledgeP"
   end if
   -- a CONVEYOR BELT on the lower run (pushes LEFT, back toward the cloud): a
   -- treadmill you must power across to reach the block slime - the cavern's
   -- mechanic (Phase B, slice 3). Grid-aligned, on solid ground2.
   pfMakeConveyor 2176, 2368, -1
   -- ===== ACT 2/3 terrain (the asset-expansion LENGTH pass) =====
   -- PIT2 - the GOO PIT (Phase E): a 256px toxic-goo chasm past the crusher
   -- gallery where a rearing snakeSlime SERPENT rises out of the goo, arcs across
   -- and sinks back in. The serpent is created BEFORE pfMakeSlimePool so the goo
   -- draws over its submerged body (it reads as rising OUT of the goo). It peaks at
   -- y460 over the centre (x3648) - so time your double-jump for when it has sunk;
   -- a mistimed leap is a knockback (pfOuch) to the near bank, and a slip into the
   -- goo burns the same. Self-gates on gSpooksOK: absent the spooks sheet the goo
   -- pit is just a plain double-jump gap (still completable).
   pfMakeSerpent 3520, 3776, 596, 460, "snakeSlime.png", "snakeslime"
   pfMakeSlimePool 3520, 3776, 596
   -- a one-way DIRT CLOUD high route on G3 (solid span 4416..4608), and a
   -- second on G4 (solid 5568..5760) - both ghost-padded a tile each side.
   b2kSmoothGround "4672,448" & cr & "4608,448" & cr & "4416,448" & cr & "4352,448"
   b2kSmoothGround "5824,448" & cr & "5760,448" & cr & "5568,448" & cr & "5504,448"
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_dirt_cloud_left") then
      pfTile "terrain_dirt_cloud_left", 4416, 448
      pfTile "terrain_dirt_cloud_middle", 4480, 448
      pfTile "terrain_dirt_cloud_right", 4544, 448
      pfTile "terrain_dirt_cloud_left", 5568, 448
      pfTile "terrain_dirt_cloud_middle", 5632, 448
      pfTile "terrain_dirt_cloud_right", 5696, 448
   end if
   -- PIT3 - a spiked chasm a horizontal LIFT ferries across (ride it, or just
   -- double-jump the 192px gap - the lift is variety, never a gate).
   pfMakeSpikes 4736, 4928
   pfMakeLift 4736, 544, 112, 24, 4720, 4944, 70
   -- a SECOND CONVEYOR on the deep run, pushing RIGHT (+1) this time: it speeds
   -- you along - control the slide so it does not carry you into the next beat.
   pfMakeConveyor 5056, 5248, 1
   -- CAVE DRESSING: flickering wall TORCHES light the gloom; bat-roost + spider
   -- OVERHANGS (dirt ledges the cave-flyers hang under, drawn only with the
   -- spooks sheet since those creatures are optional); CHAINS and STALACTITES
   -- hang from the unseen roof; ground decor breaks up the floor, all clear of
   -- the beats. (Overhang/stalactite hang orientation: OXT-verify, gotcha 26.)
   pfMakeTorch 352, 300     -- the wall-jump shaft's left column
   pfMakeTorch 504, 300     -- ...and its right column
   pfMakeTorch 900, 452     -- the entry cave
   pfMakeTorch 1360, 452    -- past the spike gap
   pfMakeTorch 2360, 452    -- the lower run
   pfMakeTorch 3216, 452    -- the crusher gallery
   pfMakeTorch 4080, 452    -- the deep run (the spider's reach)
   pfMakeTorch 5024, 452    -- past the lift chasm
   pfMakeTorch 6112, 388    -- the goal climb
   if gSpooksOK is true and gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_dirt_horizontal_overhang_left") then
      pfTile "terrain_dirt_horizontal_overhang_left", 2816, 256    -- the BAT ROOST (Act 2)
      pfTile "terrain_dirt_horizontal_middle", 2880, 256
      pfTile "terrain_dirt_horizontal_middle", 2944, 256
      pfTile "terrain_dirt_horizontal_middle", 3008, 256
      pfTile "terrain_dirt_horizontal_overhang_right", 3072, 256
      pfTile "terrain_dirt_horizontal_overhang_left", 3904, 256    -- the SPIDER's overhang (Act 3)
      pfTile "terrain_dirt_horizontal_middle", 3968, 256
      pfTile "terrain_dirt_horizontal_overhang_right", 4032, 256
      pfTile "terrain_dirt_horizontal_overhang_left", 5504, 256    -- a SECOND bat roost (Act 3)
      pfTile "terrain_dirt_horizontal_middle", 5568, 256
      pfTile "terrain_dirt_horizontal_overhang_right", 5632, 256
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "chain") then
      pfTile "chain", 700, 96
      pfTile "chain", 1640, 96
      pfTile "chain", 2520, 96
      pfTile "chain", 3360, 96
      pfTile "chain", 4240, 96
      pfTile "chain", 5360, 96
      pfTile "chain", 6080, 96
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_dirt_vertical_bottom") then
      pfTile "terrain_dirt_vertical_bottom", 1120, 96    -- a stalactite over the spike gap
      pfTile "terrain_dirt_vertical_bottom", 2000, 96    -- ...and over the cloud route
      pfTile "terrain_dirt_vertical_bottom", 3616, 96    -- ...over PIT2
      pfTile "terrain_dirt_vertical_bottom", 4816, 96    -- ...over the lift chasm
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "rock") then
      pfTile "rock", 970, 512
      pfTile "rock", 3824, 512    -- just past PIT2, clear of the deep-run beats
   end if
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "mushroom_brown") then
      pfTile "mushroom_brown", 1336, 512
      pfTile "mushroom_red", 2320, 512
      pfTile "bush", 2680, 512
      pfTile "mushroom_brown", 4256, 512    -- in the gap between the ghost run and the barnacle
   end if
end pfL6Scene

command pfL6Cast
   -- ACT 1 coins (the entry shaft + the first depths)
   pfMakeCoin 240, 500      -- the opening cave run
   pfMakeCoin 760, 500      -- before the gap (the first slime's beat)
   pfMakeCoin 1184, 452     -- mid-air over PIT1: leap it
   pfMakeCoin 1568, 468     -- atop the dirt mound crest
   pfMakeCoin 2048, 408     -- on the one-way dirt cloud (the high route)
   pfMakeCoin 2200, 500     -- past the snail, on the lower run
   pfMakeCoin 2560, 500     -- the block slime's beat (grab it between hops)
   -- ACT 2 coins (the crusher gallery, under the bat roost)
   pfMakeCoin 2880, 440     -- under the BATS (duck the swoop)
   pfMakeCoin 3088, 500     -- into the crusher gallery
   pfMakeCoin 3304, 500     -- threading the two crushers: grab it between drops
   pfMakeCoin 3648, 452     -- mid-air over the GOO PIT: grab it as you leap, timed for when the serpent has sunk
   -- ACT 3 coins (the deep run + the descent to the flag)
   pfMakeCoin 3968, 470     -- under the dropping SPIDER (grab it as you dodge)
   pfMakeCoin 4180, 500     -- the ghost-stalked run
   pfMakeCoin 4512, 408     -- on the G3 dirt cloud (the high route)
   pfMakeCoin 4640, 500     -- the cave plant's beat (time the snap)
   pfMakeCoin 4832, 452     -- mid-air over PIT3 (ride the lift, or leap it)
   pfMakeCoin 5120, 500     -- on the speed CONVEYOR (it carries you right)
   pfMakeCoin 5440, 500     -- the fire slime's beat (do NOT stomp a slime on fire)
   pfMakeCoin 5632, 408     -- on the G4 dirt cloud (the high route)
   pfMakeCoin 5808, 500     -- by the treasure MIMIC (is it a chest, or not?)
   pfMakeCoin 5984, 500     -- the final crusher's gap: grab it as you dash under
   pfMakeCoin 6112, 476     -- on the first goal step
   pfMakeCoin 6256, 412     -- on the climb to the flag
   pfMakeGem 428, 204, "green"   -- BONUS gem ABOVE the wall-jump shaft: master the wall-jump to reach it (OXT: confirm it is reachable; lower it a touch if not)
   pfMakeStar 4448, 392   -- hidden STAR: ON the act-3 dirt cloud (top y448, art 4416-4608), deep in the cavern
   -- ACT 1 cast: the meadow-cave roster
   pfMakeSlime 1, "normal", 760, 640, 900, 576
   pfMakeBlockSlime 2, 2560, 2440, 2680, 576   -- the cavern's hopping CUBE (Phase B; stomp it or time the hops)
   pfMakeSnail 3, 2050, 1980, 2120
   -- ACT 2 cast: the BAT ROOST + the CRUSHER GALLERY (split bat bands so two
   -- flying bodies never share a path and fight their velocity asserts; gotcha 18)
   pfMakeBat 4, 2900, 300, 2840, 2960
   pfMakeBat 5, 3060, 300, 3000, 3120
   pfMakeThwomp 1, 3216, true    -- a faced dirt CRUSHER
   pfMakeThwomp 2, 3392, true    -- ...and its twin (time the dash between them)
   -- ACT 3 cast: the DEEP RUN's bestiary - a dropping spider, a stalking ghost,
   -- a floor barnacle, a cave plant, a treasure mimic, a fire slime + a finale crusher
   pfMakeSpider 1, 3968, 3904, 4032, 336    -- crawls the overhang, DROPS as you pass under
   pfMakeGhost 4180, 360                    -- stalks the whole deep run
   pfMakeBarnacle 1, 4400, 544              -- a clam-trap on the floor (it telegraphs)
   pfMakeBat 6, 4544, 320, 4448, 4640       -- a lone bat by the G3 cloud
   pfMakePlant 1, 4640                       -- a carnivorous cave plant (burrow-and-snap)
   pfMakeBlockSlime 7, 5184, 5056, 5312, 576   -- a second hopping cube on the speed belt
   pfMakeCritter 8, "spike", 5440, 5360, 5520, 576, 52, "slime_fire_walk_a", "firewalk", "slime_fire_flat", 24, 36, "230,120,60", -6   -- a FIRE slime (hurts from every side)
   pfMakeMimic 9, 5808                       -- a treasure MIMIC (lunges when you near)
   pfMakeThwomp 3, 5984                       -- the finale's chained crusher before the flag
   pfMakeCheckpoint 1900    -- past PIT1, before the depths
   pfMakeCheckpoint 3840    -- past PIT2, entering the deep run
   pfMakeCheckpoint 5008    -- past PIT3, before the descent
   pfMakeGoal 6336, 416
end pfL6Cast


-- =====================================================================
-- A one-way stone LEDGE for the vertical climb: a b2kSmoothGround chain (solid
-- from ABOVE, pass up THROUGH from below), ghost-padded a tile each side, then
-- skinned with stone_cloud tiles (a line in the no-art fallback). pL..pR is the
-- SOLID span at height pY.
command pfMakeLedge pL, pR, pY
   local tX, tPts
   put (pR + 64) & "," & pY & cr & pR & "," & pY & cr & pL & "," & pY & cr & (pL - 64) & "," & pY into tPts
   b2kSmoothGround tPts
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_stone_cloud_left") then
      pfTile "terrain_stone_cloud_left", pL, pY
      put pL + 64 into tX
      repeat while tX <= pR - 128
         pfTile "terrain_stone_cloud_middle", tX, pY
         add 64 to tX
      end repeat
      pfTile "terrain_stone_cloud_right", pR - 64, pY
   else
      create graphic ("pf_ledge" & pL & "_" & pY)
      set the style of it to "line"
      set the points of it to pL & "," & pY & cr & pR & "," & pY
      set the lineSize of it to 4
      set the foregroundColor of it to "150,154,170"
      b2kCamAdopt the long id of graphic ("pf_ledge" & pL & "_" & pY)
   end if
end pfMakeLedge

-- =====================================================================
-- LEVEL 7 - "STONE KEEP" (asset-expansion Phase C, slice 1): a VERTICAL
-- TOWER you CLIMB, not a level you cross. The terrain_stone_* set (unused
-- before this) builds a tall keep; the camera SCROLLS UP as the hero
-- jumps from one one-way stone ledge to the next (pfBoundsV opens the
-- vertical camera; L1-L6 are untouched). A pure climb for slice 1; the
-- SPINNER (slice 2) and the multi-key / switch PUZZLES (slice 3) are the
-- keep's hazards, landing next. NOTE: the vertical camera scroll is the
-- one thing that needs an OXT eye (every other level only scrolls
-- horizontally) - if it is janky, that is where to look.
-- =====================================================================
command pfL7Scene
   local tX
   put "STONE KEEP (the climb!)" into gLevelName
   put 160 into gRespawnX      -- the hero starts at the BOTTOM of the TALL keep
   put 2164 into gRespawnY
   pfBoundsV 64, 960, 0, 2304   -- a TALL keep (~2300px): the camera scrolls UP the whole climb
   pfSlab "pf_ground1", 64, 2240, 960, 2304   -- the bottom floor (solid)
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "terrain_stone_block_top") then
      put 64 into tX
      repeat while tX <= 896
         pfTile "terrain_stone_block_top", tX, 2240
         add 64 to tX
      end repeat
      pfShowSlabs false
   else
      pfShowSlabs true
   end if
   -- THE CLIMB: SIXTEEN one-way stone ledges zig-zag up to the keep's top, each
   -- ~128px above the last and staggered side to side. The WIDE ledges (320..704)
   -- are the "fight" landings - a warden or a blade waits there; the side walls
   -- (pfBoundsV) keep you in the shaft. Jump (or double-jump) up through each.
   pfMakeLedge 256, 448, 2112
   pfMakeLedge 576, 768, 1984
   pfMakeLedge 320, 704, 1856
   pfMakeLedge 256, 448, 1728
   pfMakeLedge 576, 768, 1600
   pfMakeLedge 256, 448, 1472
   pfMakeLedge 320, 704, 1344
   pfMakeLedge 576, 768, 1216
   pfMakeLedge 256, 448, 1088
   pfMakeLedge 576, 768, 960
   pfMakeLedge 256, 448, 832
   pfMakeLedge 576, 768, 704
   pfMakeLedge 320, 704, 576
   pfMakeLedge 576, 768, 448
   pfMakeLedge 384, 640, 320
   pfMakeLedge 320, 704, 192      -- the KEEP TOP (the goal ledge; wide, to land + reach the flag)
   -- TOWER DRESSING: torches climb both walls; windows in the stonework.
   pfMakeTorch 96, 2120
   pfMakeTorch 928, 1944
   pfMakeTorch 96, 1768
   pfMakeTorch 928, 1592
   pfMakeTorch 96, 1416
   pfMakeTorch 928, 1080
   pfMakeTorch 96, 744
   pfMakeTorch 928, 440
   pfMakeTorch 96, 264
   if gAssetsOK is true and b2kSheetHasFrame("tiles", "window") then
      pfTile "window", 0, 2040      -- centred IN the left wall column (origin 0)
      pfTile "window", 960, 1640     -- ...the right column (origin 960)
      pfTile "window", 0, 1140
      pfTile "window", 960, 740
      pfTile "window", 0, 340
   end if
end pfL7Scene

command pfL7Cast
   -- coins up the climb: one near each ledge, plus gap bonuses to double-jump for
   pfMakeCoin 512, 2176     -- just above the start floor
   pfMakeCoin 352, 2064     -- ledge 1
   pfMakeCoin 672, 1936     -- ledge 2
   pfMakeCoin 512, 1808     -- the wide ledge (grab it past the slime)
   pfMakeCoin 352, 1680     -- ledge 4
   pfMakeCoin 672, 1552     -- ledge 5
   pfMakeCoin 352, 1424     -- ledge 6
   pfMakeCoin 400, 1296     -- the wide ledge (off-centre, past the frog)
   pfMakeCoin 672, 1168     -- ledge 8
   pfMakeCoin 352, 1040     -- ledge 9
   pfMakeCoin 672, 912      -- ledge 10
   pfMakeCoin 352, 784      -- ledge 11
   pfMakeCoin 672, 656      -- ledge 12
   pfMakeCoin 512, 528      -- the wide ledge (past the spike slime)
   pfMakeCoin 672, 400      -- ledge 14
   pfMakeCoin 420, 272      -- ledge 15 (off-centre, clear of the blade)
   pfMakeCoin 448, 144      -- on the keep top
   pfMakeCoin 512, 1730     -- a gap bonus (double-jump between ledges)
   pfMakeCoin 512, 1450     -- a gap bonus
   pfMakeCoin 512, 1100     -- a gap bonus
   pfMakeCoin 512, 850      -- a gap bonus
   pfMakeCoin 512, 600      -- a gap bonus
   pfMakeGem 544, 80, "blue"      -- BONUS gem: the summit, a double-jump above the keep top
   pfMakeGem 512, 1180, "green"   -- BONUS gem: a mid-climb gap reward
   pfMakeStar 420, 776   -- hidden STAR: ON the mid-upper climb ledge (pfMakeLedge 256,448,832), right end - clear of the ledge's coin (352,784) and both gems
   -- THE BLADE GAUNTLET: FIVE sweeping spinners guard the climb gaps (stand SAFE
   -- on the lower ledge, read the blade, jump when it has swept clear), and ONE
   -- stationary HALF-BLADE sits on the final ledge (land clear of it, hop over).
   -- The saw rule: time them, never stomp; a mistime is knockback, never lethal.
   pfMakeSpinner 512, 2010, 320, 1300, false   -- gap L1->L2
   pfMakeSpinner 512, 1626, 320, 1200, false   -- gap L4->L5
   pfMakeSpinner 512, 1242, 300, 1100, false   -- gap L7->L8
   pfMakeSpinner 512, 858, 300, 1050, false    -- gap L10->L11
   pfMakeSpinner 512, 474, 280, 1000, false    -- gap L13->L14 (tightest, near the top)
   pfMakeSpinner 512, 296, 0, 1, true          -- a stationary half-blade on the final ledge (y320)
   -- THE KEEP'S WARDENS: walkers hold the wide "fight" ledges - a slime to stomp,
   -- a hopping FROG, and a SPIKE slime you must dodge (no stomp on the spikes).
   pfMakeSlime 1, "normal", 560, 460, 680, 1856
   pfMakeFrog 2, 560, 460, 640, 1344
   pfMakeSlime 3, "spike", 560, 460, 680, 576
   pfMakeGoal 544, 160      -- the flag, atop the keep
end pfL7Cast


-- Every coin (sensor pickup or ?-box payout) lands here. The moment the
-- LAST one arrives, the goal flag turns GOLD and a banner + chime send
-- you to it - the win gate is a state you can SEE, never a surprise
-- delivered only at the flag.
command pfGainCoin pVal
   add 1 to gCoins
   if pVal is empty then put 1 into pVal   -- the ?-box payout passes nothing -> worth 1
   add pVal to gScore                       -- the bonus tier score (count gate is unchanged)
   b2kSound "coin"
   if gCoins >= gCoinsTotal then
      if gGoalSpr is not empty and b2kSheetHasFrame("tiles", "flag_yellow_a") then
         b2kSpritePlay gGoalSpr, "wavegold"
      end if
      pfNotice "ALL " & gCoinsTotal & " COINS - the flag is GOLD, go touch it to WIN!", 2800
      b2kSound "check"
   end if
end pfGainCoin

-- A big centre-screen banner on the splash field; b2kFrame hides it
-- when its time is up (no send-in timers to leak across resets).
command pfNotice pText, pMS
   if there is no field "pfSplash" then exit pfNotice
   set the text of field "pfSplash" to pText
   set the visible of field "pfSplash" to true
   put the milliseconds + pMS into gNoticeUntil
end pfNotice

-- Phase F: toggle the bottom DEBUG overlay (the old text readout: state/ms/awake/
-- view/audio + the run stats) with the ` key. Only meaningful when the art HUD is
-- on; without hud_ art the field is the always-on readout fallback.
command pfToggleDebug
   if gHudOK is not true then exit pfToggleDebug
   put (gShowDebug is not true) into gShowDebug
   if there is a field "pfHud" then set the visible of field "pfHud" to gShowDebug
end pfToggleDebug

command pfChromeFront
   local tN, tC, tI
   put the number of controls of this card into tN
   set the itemDelimiter to comma
   -- Phase F: the art HUD sprites are card-level (built before b2kCamOn), so they
   -- ride below the camera viewport until raised here like the rest of the chrome.
   if gHudOK is true then
      if gHudCoinIcon is not empty then set the layer of gHudCoinIcon to tN
      if gHudCoinD[1] is not empty then set the layer of gHudCoinD[1] to tN
      if gHudCoinD[2] is not empty then set the layer of gHudCoinD[2] to tN
      if gHudCoinTot[1] is not empty then set the layer of gHudCoinTot[1] to tN
      if gHudCoinTot[2] is not empty then set the layer of gHudCoinTot[2] to tN
      if there is a graphic "pf_hudslash" then set the layer of graphic "pf_hudslash" to tN
      if gHudGemIcon is not empty then set the layer of gHudGemIcon to tN
      if gHudGemD[1] is not empty then set the layer of gHudGemD[1] to tN
      if gHudGemD[2] is not empty then set the layer of gHudGemD[2] to tN
      repeat for each item tC in "blue,green,red,yellow"
         if gHudKey[tC] is not empty then set the layer of gHudKey[tC] to tN
      end repeat
      repeat with tI = 1 to kHearts
         if gHudHeart[tI] is not empty then set the layer of gHudHeart[tI] to tN
      end repeat
      if gHudStar is not empty then set the layer of gHudStar to tN
      if gHudPortrait is not empty then set the layer of gHudPortrait to tN
   end if
   repeat for each item tC in "pfTitle,pfHelp,pfHud,pfSplash,pfWinText"
      if there is a field tC then set the layer of field tC to tN
   end repeat
   if there is a graphic "pfWinShade" then set the layer of graphic "pfWinShade" to tN - 1
   repeat for each item tC in "pfbtn_pause,pfbtn_reset,pfbtn_again,pfbtn_level"
      if there is a button tC then set the layer of button tC to tN
   end repeat
   -- the transition card (tint base + illustrated art + title text) sits ABOVE all
   -- other chrome while it is covering: the build created controls over it, so
   -- re-raise the whole stack here to keep it on top until the reveal fade hides
   -- it. Skipped when hidden (e.g. on the win screen).
   if there is a graphic "pfCardShade" and the visible of graphic "pfCardShade" is true then pfCardRaise
end pfChromeFront

command pfWipeStage
   local tAgain, i, tName
   put true into tAgain
   repeat while tAgain
      put false into tAgain
      repeat with i = 1 to the number of controls of this card
         put the short name of control i of this card into tName
         if char 1 to 3 of tName is "pf_" then
            delete control i of this card
            put true into tAgain
            exit repeat
         end if
      end repeat
   end repeat
end pfWipeStage

-- =====================================================================
-- The game tick
-- =====================================================================
on b2kFrame
   local tHud, tPos, tHS, tCamX, tCamY
   if gHero is empty then exit b2kFrame
   -- THE HERO SNAPSHOT, once per frame: position and controller state
   -- feed the kill plane, edge failsafe, sound cues and every pf tick
   -- below (one FFI/string round-trip instead of eight)
   set the itemDelimiter to comma
   put b2kPosition(gHero) into tPos
   put item 1 of tPos into gHeroPX
   put item 2 of tPos into gHeroPY
   put b2kPlayerState() into gHeroState
   if gHeroState is "jump" then put the milliseconds into gJumpMS
   if gIntroPan > 0 then
      -- no camera pan (cut for reliability): just a splash beat over the
      -- spawn, then the follow engages and the run clock starts
      subtract 1 from gIntroPan
      if gIntroPan is 0 then
         if there is a field "pfSplash" then set the visible of field "pfSplash" to false
         put the milliseconds into gRunStart
      end if
   end if
   -- kill plane: anything that slips every other check still respawns.
   -- Plus the EDGE FAILSAFE: a solver squeeze must never leave the hero
   -- beyond a wall (with the thick slabs it should never fire; when it
   -- does not, it costs two compares)
   if gHurtLock is not true and gHeroPY > gKillPlaneY then pfHurt   -- the kill plane = respawn (off, far below, on a contained vertical climb)
   -- the EDGE CLAMP runs ALWAYS now (containment is non-negotiable): a hard
   -- per-frame snap so a knockback, a dash, or a wall that failed to collide
   -- can never leave the box - b2kMoveTo teleports the body back inside.
   if gHeroPX < gEdgeL + 16 then b2kMoveTo gHero, gEdgeL + 28, gHeroPY
   if gHeroPX > gEdgeR - 16 then b2kMoveTo gHero, gEdgeR - 28, gHeroPY
   -- CAMERA: track the hero through the Kit's OWN goto (a cut each frame = a
   -- 1:1 follow), but clamp the CENTRE to the content box ourselves. This is
   -- the alignment fix: a raw "set the hScroll" write (the old backstop) left
   -- the scroll out of step with the Kit's scroll-compensation, so coins and
   -- flags drew offset at the edges. b2kCamGoto keeps them in sync; we just
   -- pre-clamp the point (b2kCamBounds did not hold on the user's engine).
   if gIntroPan is 0 and gCamOK is true then
      if gEdgeR - gEdgeL <= 1024 then
         put (gEdgeL + gEdgeR) / 2 into tCamX   -- a world no wider than the viewport (the tower): centre it, no horizontal scroll
      else
         put gHeroPX into tCamX
         if tCamX < gEdgeL + 512 then put gEdgeL + 512 into tCamX
         if tCamX > gEdgeR - 512 then put gEdgeR - 512 into tCamX
      end if
      put gHeroPY into tCamY    -- follow vertically too; gCamTopY=gCamBotY=320 pins it on horizontal levels
      if tCamY < gCamTopY then put gCamTopY into tCamY
      if tCamY > gCamBotY then put gCamBotY into tCamY
      b2kCamGoto tCamX, tCamY
   end if
   -- centre-screen banners (pfNotice) expire here
   if gNoticeUntil > 0 and the milliseconds > gNoticeUntil then
      put 0 into gNoticeUntil
      if there is a field "pfSplash" then set the visible of field "pfSplash" to false
   end if
   -- the Kit's player controller moved/animated the hero before this
   -- handler ran; the example reads its one-tick land state and the
   -- jump transition for the sound cues
   if gHeroState is "land" then
      add 1 to gLands
      b2kSound "land"
   end if
   if gHeroState is "jump" and gPrevState is not "jump" and gHurtLock is not true then
      b2kSound "jump"   -- also chirps on the slime-stomp bounce: earned
   end if
   if gHeroState is "jump" or gHeroState is "fall" then
      put the milliseconds into gAirMS   -- "was airborne recently", for the stomp window
   end if
   put gHeroState into gPrevState
   pfTickGate
   pfTickSwitchGates
   pfTickSlimes
   pfTickThwomps
   pfTickMovers
   pfTickSpring
   pfTickBonks
   pfTickDebris
   pfTickDust
   pfTickLever
   pfTickDoors
   pfTickPlants
   pfTickGhost
   pfTickBarnacles   -- Wave 6 (bestiary II)
   pfTickSpiders     -- Wave 6 (bestiary II)
   pfTickBoulder
   pfTickLift
   pfTickConveyor    -- Phase B: belts carry the grounded hero
   pfTickSerpent     -- Phase E: the L4 lava / L6 goo serpent's rise-cross-sink arc
   pfTickBarrel
   pfTickParallax   -- Wave 8: drift the biome backdrop for depth
   -- HUD at 4 Hz, not 60: the ms readout changes every frame, so an
   -- unthrottled HUD re-sets the field text (= engine relayout+redraw)
   -- on EVERY frame -- the single biggest avoidable per-frame cost here
   local tSecs
   if the milliseconds < gHudNextMS then exit b2kFrame
   put the milliseconds + 250 into gHudNextMS
   pfUpdateHud   -- Phase F: refresh the art HUD (coins/gems/keys) on change
   -- with the art HUD on, the bottom field is the DEBUG overlay - skip building it
   -- unless the ` toggle is up. With no hud_ art it stays the full text fallback.
   if gHudOK is true and gShowDebug is not true then exit b2kFrame
   if gWinSecs is not empty then
      put gWinSecs into tSecs
   else
      put (the milliseconds - gRunStart) div 1000 into tSecs
   end if
   put "L" & gLevel & "   " & gCoins & "/" & gCoinsTotal & "   " & format("%d:%02d", tSecs div 60, tSecs mod 60) & "   HP " & gHearts & "/" & kHearts & "   falls " & gFalls & "   hits " & gOuches & "   lands " & gLands & "   |   " & gHeroState & "/" & b2kSpriteAnim(gHeroSpr) & "   " & round(b2kFrameMS() * 10) / 10 & " ms   awake " & b2kAwakeBodyCount() & "/" & b2kBodyCount() into tHud
   if gGemsTotal > 0 then put "   gems " & gGems & "/" & gGemsTotal after tHud
   if gStarsTotal > 0 then put "   star " & gStars & "/" & gStarsTotal after tHud
   put "   score " & gScore & "/" & gScoreTotal after tHud
   if gKeysHeld is not empty then put "   [KEYS " & gKeysHeld & "]" after tHud
   if gCamOK is true then
      put the hScroll of b2kCamGroup() into tHS   -- read the scroll once
      put "   |   view " & tHS & "-" & (tHS + 1024) after tHud
   end if
   if not b2kIsAwake(gHero) then put "   [ASLEEP?!]" after tHud   -- must never show
   if b2kSoundStatus() is not empty then put "   [audio: " & b2kSoundStatus() & "]" after tHud
   if b2kSoundMuted() then put "   [muted]" after tHud
   -- the flag hints belong to the TEXT-readout fallback; with the art HUD on they
   -- already reach the player as centre-screen pfNotice banners (the flag's "find
   -- N more coins" / pfGainCoin's "ALL COINS" / the win screen), so they are not
   -- echoed into the debug overlay.
   if gHudOK is not true then
      if gWon is true then
         put "WINNER!   " before tHud
      else
         if gFlagHint is true and gCoins < gCoinsTotal then
            put "Find ALL the coins, then return to the flag!   " before tHud
         end if
         if gCoins >= gCoinsTotal then put "All coins - to the FLAG!   " before tHud
      end if
   end if
   if tHud is not gHudLast then
      put tHud into gHudLast
      set the text of field "pfHud" to tHud
   end if
end b2kFrame

-- (The Phase 1/2 hand-rolled hero tick and ground probe lived here.
-- b2kPlayerAttach + b2kPlayerAnims now do all of it inside the Kit --
-- with accel, coyote time, jump buffering and a real slope test the
-- hand-rolled version never had.)

-- The kinematic gate chases its open/closed height; the plate's colour
-- tracks its state. Anything on the plate (the hero OR the crate) holds
-- it. Pressed = any tracked body overlapping the pad region, POLLED
-- (stateless, sleep-proof); a short release debounce keeps a settling
-- crate's micro-bounces from flapping the gate.
command pfTickGate
   local tTarget, tY, tLook, tVel, tOn
   if gGate is empty then exit pfTickGate
   set the itemDelimiter to comma
   -- b2kOverlapMoving, not b2kOverlap: the pad region sits on the floor
   -- and the broadphase's fattened boxes make the GROUND SLAB overlap it
   -- permanently - the plate read pressed from frame one. Moving bodies
   -- only (hero, crate - awake or asleep) is what "pressed" means.
   put (b2kOverlapMoving(gPlateX - 26, 552, gPlateX + 26, 576) is not empty) into tOn
   if tOn then put the milliseconds + 200 into gPlateHoldMS
   if tOn or the milliseconds < gPlateHoldMS then
      put 342 into tTarget
      put "down" into tLook
   else
      put 512 into tTarget
      put "up" into tLook
   end if
   if tLook is not gPlateLook then
      if gPlateLook is not empty then b2kSound "gate"   -- not on the build tick
      put tLook into gPlateLook
      -- Wave 1 button art tracks the polled state; the coloured rect
      -- below is the frozen no-asset fallback (hidden when art loaded)
      if gPlateSpr is not empty then
         if tLook is "down" then
            b2kSpriteSetFrame gPlateSpr, "switch_yellow_pressed"
         else
            b2kSpriteSetFrame gPlateSpr, "switch_yellow"
         end if
      end if
      if there is a graphic "pf_plate" then
         if tLook is "down" then
            set the backgroundColor of graphic "pf_plate" to "140,110,30"
         else
            set the backgroundColor of graphic "pf_plate" to "220,180,60"
         end if
      end if
   end if
   put item 2 of b2kPosition(gGate) into tY
   -- write the kinematic's velocity only when it CHANGES (one less FFI
   -- round-trip per frame while the gate idles, which is most frames)
   if abs(tY - tTarget) <= 6 then
      put 0 into tVel
   else
      if tTarget < tY then
         put -160 into tVel
      else
         put 160 into tVel
      end if
   end if
   if tVel is not gGateVel then
      put tVel into gGateVel
      b2kSetVelocity gGate, 0, tVel
   end if
end pfTickGate

-- Every LATCHING switch-gate, polled. A still-closed switch polls its pad each
-- frame (b2kOverlapMoving - moving bodies only, so the ground slab never reads
-- as "pressed"); once pressed it latches OPEN and the kinematic gate rises to
-- y342 and rests. After it settles, gSwDone short-circuits to one compare/frame.
command pfTickSwitchGates
   local i, tOn, tY, tTarget, tVel
   if gSwN is 0 or gSwN is empty then exit pfTickSwitchGates
   set the itemDelimiter to comma   -- item 2 of b2kPosition is the gate's y
   repeat with i = 1 to gSwN
      if gSwDone[i] is true then next repeat
      if gSwGate[i] is empty then next repeat
      if gSwOpen[i] is not true then
         put (b2kOverlapMoving(gSwX[i] - 30, 420, gSwX[i] + 30, 452) is not empty) into tOn
         if tOn then
            put true into gSwOpen[i]
            b2kSound "gate"
            b2kCamShake 2, 120
            if gSwSpr[i] is not empty then b2kSpriteSetFrame gSwSpr[i], "switch_" & gSwWord[i] & "_pressed"
            if there is a graphic ("pf_swPlate" & i) then set the backgroundColor of graphic ("pf_swPlate" & i) to "90,92,112"
         end if
      end if
      -- drive the gate toward its target (open=342 raised, closed=512); the
      -- velocity is written only on change, and gSwDone freezes it once open
      if gSwOpen[i] is true then
         put 342 into tTarget
      else
         put 512 into tTarget
      end if
      put item 2 of b2kPosition(gSwGate[i]) into tY
      if abs(tY - tTarget) <= 6 then
         put 0 into tVel
      else
         if tTarget < tY then
            put -160 into tVel
         else
            put 160 into tVel
         end if
      end if
      if tVel is not gSwGateVel[i] then
         put tVel into gSwGateVel[i]
         b2kSetVelocity gSwGate[i], 0, tVel
      end if
      if gSwOpen[i] is true and tVel is 0 then put true into gSwDone[i]
   end repeat
end pfTickSwitchGates

-- The slime-FAMILY tick: the classic patrollers plus the Wave 3 kinds.
-- One position read per live row; each kind costs a couple of compares
-- plus its own steering. Kind chains: snail -> shell -> shellslide <->
-- shell; bat -> batfly; mimic -> mimiclive. (The stomp/kick/hurt
-- VERDICTS live in b2kContact - this tick is pure steering.)
command pfTickSlimes
   local i, j, tX, tY, tPos, tBody, tVX, tMS, tVel, tEl, tInv
   set the itemDelimiter to comma
   put the milliseconds into tMS
   repeat with i = 1 to gSlimeN
      if gSlimeGoneAt[i] is not empty then
         if tMS > gSlimeGoneAt[i] then
            if gSlimeSpr[i] is not empty then
               set the blendLevel of gSlimeSpr[i] to 0   -- clear the fade before the sprite is freed/reused
               b2kSpriteRemove gSlimeSpr[i]
            end if
            put empty into gSlimeSpr[i]
            if there is a graphic ("pf_slimeBody" & i) then delete graphic ("pf_slimeBody" & i)
            put empty into gSlimeGoneAt[i]
         else
            -- Phase D juice: the defeated art FADES out (blendLevel 0 -> ~96) AND
            -- POPS up on an ease-out arc (~50px) over its ~700ms linger, instead
            -- of blinking off. Short window; only a stomped foe or two at once.
            if gSlimeSpr[i] is not empty then
               put (tMS - gSlimeGoneAt[i] + 700) into tEl   -- 0..700 ms elapsed
               set the blendLevel of gSlimeSpr[i] to min(96, round(tEl / 7))
               if gSlimeDeadY[i] is not empty then
                  put 1 - tEl / 700 into tInv
                  b2kSpriteMoveTo gSlimeSpr[i], gSlimeDeadX[i], gSlimeDeadY[i] - 50 * (1 - tInv * tInv)
               end if
            end if
         end if
         next repeat
      end if
      put gSlimeB[i] into tBody
      if tBody is empty then next repeat
      put b2kPosition(tBody) into tPos
      if tPos is empty then next repeat
      put item 1 of tPos into tX
      put item 2 of tPos into tY
      switch gSlimeKind[i]
         case "shell"
            -- a parked shell needs NO per-frame work: the transitions
            -- already wrote velocity 0, and a per-frame b2kSetVelocity
            -- would WAKE it every tick (the Kit wakes on velocity
            -- writes by design) - a sleeping shell costs the solver
            -- nothing. The case must exist, or the default branch
            -- would hand it patrol velocity.
            break
         case "shellslide"
            -- the bowling ball: a per-frame velocity ASSERT (the
            -- player-controller pattern) keeps the slide at speed; a
            -- wall hit shows as collapsed vx -> reverse, keep rolling
            put b2kVelocity(tBody) into tVel   -- read once, reuse for the vy pass-through
            put item 1 of tVel into tVX
            if gSlimeDir[i] > 0 and tVX < 60 then put -520 into gSlimeDir[i]
            if gSlimeDir[i] < 0 and tVX > -60 then put 520 into gSlimeDir[i]
            b2kSetVelocity tBody, gSlimeDir[i], item 2 of tVel
            if gSlimeSpr[i] is not empty then b2kSpriteFlipH gSlimeSpr[i], ((gSlimeDir[i] < 0) is not gSlimeFlip[i])
            -- bowl over any ground foe it reaches (shells are immune
            -- to each other; this loop only runs while one slides)
            repeat with j = 1 to gSlimeN
               if j is i then next repeat
               if gSlimeB[j] is empty then next repeat
               if gSlimeKind[j] is "shell" or gSlimeKind[j] is "shellslide" then next repeat
               put b2kPosition(gSlimeB[j]) into tPos
               if tPos is empty then next repeat
               if abs(item 1 of tPos - tX) < 44 and abs(item 2 of tPos - tY) < 44 then
                  pfSquashSlime j
               end if
            end repeat
            break
         case "bat"
            -- hanging: one proximity compare arms the drop
            if abs(gHeroPX - tX) < 150 and gHeroPY > tY then
               put "batfly" into gSlimeKind[i]
               b2kSetDynamic tBody
               b2kSetGravityScale tBody, 0   -- a flying body
               if gSlimeSpr[i] is not empty then b2kSpritePlay gSlimeSpr[i], "batfly"
            end if
            break
         case "batfly"
            -- patrol + a proportional swoop to head height + sine bob
            if tX <= gSlimeMin[i] then put 90 into gSlimeDir[i]
            if tX >= gSlimeMax[i] then put -90 into gSlimeDir[i]
            b2kSetVelocity tBody, gSlimeDir[i], (450 - tY) * 1.5 + 40 * sin(tMS / 300)
            if gSlimeSpr[i] is not empty then b2kSpriteFlipH gSlimeSpr[i], ((gSlimeDir[i] < 0) is not gSlimeFlip[i])
            break
         case "mimic"
            -- disguised and DEAD STILL until the hero is close; the
            -- wake is the tell (grass has no business in this biome).
            -- 110px = ~0.4s of warning even at full sprint.
            if abs(gHeroPX - tX) < 110 and abs(gHeroPY - tY) < 160 then
               put "mimiclive" into gSlimeKind[i]
               b2kSetDynamic tBody
               if gSlimeSpr[i] is not empty then b2kSpriteSetFrame gSlimeSpr[i], "grassBlock_jump.png"
               put tMS + 350 into gSlimeT[i]   -- first hop after a beat
            end if
            break
         case "mimiclive"
            -- short lunges at the hero whenever it has settled
            if tMS > gSlimeT[i] and abs(item 2 of b2kVelocity(tBody)) < 8 then
               if gHeroPX < tX then
                  put -170 into gSlimeDir[i]
               else
                  put 170 into gSlimeDir[i]
               end if
               b2kSetVelocity tBody, gSlimeDir[i], -330
               put tMS + 900 + random(400) into gSlimeT[i]
               if gSlimeSpr[i] is not empty then b2kSpriteFlipH gSlimeSpr[i], ((gSlimeDir[i] < 0) is not gSlimeFlip[i])
            end if
            break
         case "frog"
            -- Wave 6: a grounded HOPPER (the lunger). Crouches, then leaps
            -- toward the hero when settled and he is within range. Stompable
            -- via the classic-slime path (no contact case needed); its side
            -- touch knocks back. One velocity read per live frog - it is
            -- always active (unlike the mimic, which only wakes when neared).
            put item 2 of b2kVelocity(tBody) into tVX
            if gFrogAir[i] is true then
               -- mid-hop: the instant it settles, drop to the idle crouch
               if abs(tVX) < 8 then
                  put false into gFrogAir[i]
                  if gSlimeSpr[i] is not empty then b2kSpriteSetFrame gSlimeSpr[i], "frog_idle"
               end if
            else if tMS > gSlimeT[i] and abs(tVX) < 8 then
               -- crouched and re-armed: leap at the hero if he is near, but
               -- never hop past this frog's band, so it can never spring into
               -- a pit or off its ledge (0 = a frustrated hop in place)
               if abs(gHeroPX - tX) < 300 then
                  put 0 into gSlimeDir[i]
                  if gHeroPX < tX - 8 and tX > gSlimeMin[i] then put -150 into gSlimeDir[i]
                  if gHeroPX > tX + 8 and tX < gSlimeMax[i] then put 150 into gSlimeDir[i]
                  b2kSetVelocity tBody, gSlimeDir[i], -300
                  put tMS + 1100 + random(500) into gSlimeT[i]
                  put true into gFrogAir[i]
                  if gSlimeSpr[i] is not empty then
                     b2kSpriteFlipH gSlimeSpr[i], ((gSlimeDir[i] < 0) is not gSlimeFlip[i])
                     b2kSpriteSetFrame gSlimeSpr[i], "frog_jump"
                  end if
               end if
            end if
            break
         case "block"
            -- Phase B: a HOPPING cube that arcs back and forth across its band
            -- (jump frame in the air, the squish idle when settled), reversing
            -- at the band edges. Always active; one velocity read per live
            -- block-slime. Stomp/knockback live on the classic path (b2kContact).
            put item 2 of b2kVelocity(tBody) into tVX   -- vy, reusing tVX like the frog
            if gFrogAir[i] is true then
               if abs(tVX) < 8 then
                  put false into gFrogAir[i]   -- landed: settle into the squish idle
                  if gSlimeSpr[i] is not empty then b2kSpritePlay gSlimeSpr[i], "blockidle"
               end if
            else if tMS > gSlimeT[i] and abs(tVX) < 8 then
               if tX <= gSlimeMin[i] then put gSlimeSpeed[i] into gSlimeDir[i]
               if tX >= gSlimeMax[i] then put -gSlimeSpeed[i] into gSlimeDir[i]
               b2kSetVelocity tBody, gSlimeDir[i], -320
               put tMS + 650 + random(350) into gSlimeT[i]
               put true into gFrogAir[i]
               if gSlimeSpr[i] is not empty then
                  b2kSpriteFlipH gSlimeSpr[i], ((gSlimeDir[i] < 0) is not gSlimeFlip[i])
                  b2kSpriteSetFrame gSlimeSpr[i], "slime_block_jump"
               end if
            end if
            break
         case "snake"
            -- Phase E SLITHER: crawl the floor, auto-reversing at a PIT EDGE as
            -- well as the patrol bound (which also stops it at a wall). One
            -- floor-probe AHEAD-and-BELOW the body per frame - it sits past the
            -- snake's own box, so empty = a ledge ahead, flip around. Gravity
            -- keeps vy, so it hugs the floor.
            if gSlimeDir[i] is 0 then put gSlimeSpeed[i] into gSlimeDir[i]
            if gSlimeDir[i] >= 0 then put tX + 40 into tEl
            if gSlimeDir[i] < 0 then put tX - 40 into tEl
            if tEl <= gSlimeMin[i] or tEl >= gSlimeMax[i] \
                  or b2kOverlap(tEl - 8, tY + 18, tEl + 8, tY + 50) is empty then
               put - gSlimeDir[i] into gSlimeDir[i]
            end if
            b2kSetVelocity tBody, gSlimeDir[i], item 2 of b2kVelocity(tBody)
            if gSlimeSpr[i] is not empty then b2kSpriteFlipH gSlimeSpr[i], ((gSlimeDir[i] < 0) is not gSlimeFlip[i])
            break
         default
            -- the classic patroller (normal/spike slimes, walking snails,
            -- and the showcase mice/worms/ladybugs - speed per row now,
            -- so a mouse skitters and a worm crawls on the same branch)
            if tX <= gSlimeMin[i] then put gSlimeSpeed[i] into gSlimeDir[i]
            if tX >= gSlimeMax[i] then put -gSlimeSpeed[i] into gSlimeDir[i]
            b2kSetVelocity tBody, gSlimeDir[i], item 2 of b2kVelocity(tBody)
            if gSlimeSpr[i] is not empty then b2kSpriteFlipH gSlimeSpr[i], ((gSlimeDir[i] < 0) is not gSlimeFlip[i])
      end switch
   end repeat
end pfTickSlimes

-- The piranha burrows: a pure sprite cycle, no body. down (hidden,
-- with the classic mercy - it will not rise while the hero stands
-- over the mouth) -> rise -> up (the bite = the hurt box) -> sink.
command pfTickPlants
   local i, tMS, tP
   if gPlantN is 0 or gPlantN is empty then exit pfTickPlants
   put the milliseconds into tMS
   repeat with i = 1 to gPlantN
      if gPlantSpr[i] is empty then next repeat
      switch gPlantState[i]
         case "down"
            if tMS > gPlantT[i] and abs(gHeroPX - gPlantX[i]) > 52 then
               put "rise" into gPlantState[i]
               put tMS + 450 into gPlantT[i]
               set the visible of gPlantSpr[i] to true
            end if
            break
         case "rise"
            put 1 - (gPlantT[i] - tMS) / 450 into tP
            if tP > 1 then put 1 into tP
            b2kSpriteMoveTo gPlantSpr[i], gPlantX[i], 606 - 56 * tP
            if tMS >= gPlantT[i] then
               put "up" into gPlantState[i]
               put tMS + 1200 into gPlantT[i]
            end if
            break
         case "up"
            if gHurtLock is not true then
               if abs(gHeroPX - gPlantX[i]) < 34 and gHeroPY > 460 and gHeroPY < 600 then
                  pfOuch gPlantX[i]
               end if
            end if
            if tMS >= gPlantT[i] then
               put "sink" into gPlantState[i]
               put tMS + 450 into gPlantT[i]
            end if
            break
         case "sink"
            put (gPlantT[i] - tMS) / 450 into tP
            if tP < 0 then put 0 into tP
            b2kSpriteMoveTo gPlantSpr[i], gPlantX[i], 606 - 56 * tP
            if tMS >= gPlantT[i] then
               put "down" into gPlantState[i]
               put tMS + 1400 + random(500) into gPlantT[i]
               set the visible of gPlantSpr[i] to false
            end if
            break
      end switch
   end repeat
end pfTickPlants

-- The ghost: bodiless, drifts through everything, chases at ~80px/s
-- ONLY while the hero faces away - eye contact freezes it in the shy
-- pose. One sprite and a handful of compares; the haunt is cheap.
command pfTickGhost
   local tDX, tDY, tLen, tWatched, tDT
   if gGhostSpr is empty then exit pfTickGhost
   if (gGhostX - gHeroPX >= 0 and b2kPlayerFacing() is 1) \
         or (gGhostX - gHeroPX < 0 and b2kPlayerFacing() is -1) then
      put true into tWatched
   else
      put false into tWatched
   end if
   if tWatched is not gGhostShy then
      put tWatched into gGhostShy
      if tWatched is true then
         b2kSpriteSetFrame gGhostSpr, "ghost_normal.png"
      else
         b2kSpriteSetFrame gGhostSpr, "ghost.png"
      end if
   end if
   if tWatched is not true then
      put b2kFrameMS() / 1000 into tDT
      if tDT > 0.05 then put 0.05 into tDT
      put gHeroPX - gGhostX into tDX
      put (gHeroPY - 12) - gGhostY into tDY
      put sqrt(tDX * tDX + tDY * tDY) into tLen
      if tLen > 10 then
         put gGhostX + tDX / tLen * 80 * tDT into gGhostX
         put gGhostY + tDY / tLen * 80 * tDT into gGhostY
         if gGhostY < 220 then put 220 into gGhostY
         if gGhostY > 540 then put 540 into gGhostY
         b2kSpriteFlipH gGhostSpr, (tDX < 0)
         b2kSpriteMoveTo gGhostSpr, gGhostX, gGhostY
      end if
   end if
   if gHurtLock is not true then
      if abs(gHeroPX - gGhostX) < 30 and abs(gHeroPY - gGhostY) < 44 then pfOuch gGhostX
   end if
end pfTickGhost

-- Wave 6: the BARNACLES - stationary clams that lurk, telegraph, then snap.
-- A timed bite cycle armed by proximity (shut -> open warning -> bite window
-- -> cooldown). The hurt window is the "bite" state only, and only when the
-- hero is close AND at the clam's level, so jumping over it is always safe.
command pfTickBarnacles
   local i, tMS, tDX
   if gBarnN is 0 or gBarnN is empty then exit pfTickBarnacles
   put the milliseconds into tMS
   repeat with i = 1 to gBarnN
      put abs(gHeroPX - gBarnX[i]) into tDX
      switch gBarnState[i]
         case "shut"
            -- lurks closed; the hero nearing (cooldown up) arms a bite, but it
            -- TELEGRAPHS by opening first - the warning beat is the mercy
            if tDX < 120 and tMS > gBarnT[i] then
               put "open" into gBarnState[i]
               put tMS + 360 into gBarnT[i]
               if gBarnSpr[i] is not empty then b2kSpriteSetFrame gBarnSpr[i], "barnacle_attack_a"
            end if
            break
         case "open"
            if tMS >= gBarnT[i] then
               put "bite" into gBarnState[i]
               put tMS + 240 into gBarnT[i]
               if gBarnSpr[i] is not empty then b2kSpriteSetFrame gBarnSpr[i], "barnacle_attack_b"
               b2kSound "bite"
            end if
            break
         case "bite"
            if gHurtLock is not true and tDX < 40 and abs(gHeroPY - gBarnY[i]) < 46 then pfOuch gBarnX[i]
            if tMS >= gBarnT[i] then
               put "shut" into gBarnState[i]
               put tMS + 900 into gBarnT[i]   -- a cooldown before it can re-arm
               if gBarnSpr[i] is not empty then b2kSpriteSetFrame gBarnSpr[i], "barnacle_attack_rest"
            end if
            break
      end switch
   end repeat
end pfTickBarnacles

-- Wave 6: the SPIDERS - ceiling-crawlers that drop on the hero passing under
-- and climb back. Bodiless: a per-frame b2kSpriteMoveTo (scroll-correct) walks
-- the sprite; dt comes from b2kFrameMS like the ghost. The drop hurts on
-- contact; reaching the bottom flips it to climb, reaching the top to patrol.
command pfTickSpiders
   local i, tDT
   if gSpiderN is 0 or gSpiderN is empty then exit pfTickSpiders
   put b2kFrameMS() / 1000 into tDT
   if tDT > 0.05 then put 0.05 into tDT
   repeat with i = 1 to gSpiderN
      if gSpiderSpr[i] is empty then next repeat
      switch gSpiderState[i]
         case "patrol"
            -- creep along the underside of the overhang, facing travel
            put gSpiderX[i] + gSpiderDir[i] * tDT into gSpiderX[i]
            if gSpiderX[i] <= gSpiderMinX[i] then put abs(gSpiderDir[i]) into gSpiderDir[i]
            if gSpiderX[i] >= gSpiderMaxX[i] then put -abs(gSpiderDir[i]) into gSpiderDir[i]
            b2kSpriteMoveTo gSpiderSpr[i], gSpiderX[i], gSpiderHangY[i]
            b2kSpriteFlipH gSpiderSpr[i], (gSpiderDir[i] < 0)
            -- the hero passing beneath (close in x, below the bar) drops it
            if abs(gHeroPX - gSpiderX[i]) < 44 and gHeroPY > gSpiderHangY[i] + 20 then put "drop" into gSpiderState[i]
            break
         case "drop"
            put gSpiderY[i] + 380 * tDT into gSpiderY[i]
            if gSpiderY[i] >= gSpiderDropTo[i] then
               put gSpiderDropTo[i] into gSpiderY[i]
               put "climb" into gSpiderState[i]
            end if
            b2kSpriteMoveTo gSpiderSpr[i], gSpiderX[i], gSpiderY[i]
            if gHurtLock is not true and abs(gHeroPX - gSpiderX[i]) < 26 and abs(gHeroPY - gSpiderY[i]) < 40 then pfOuch gSpiderX[i]
            break
         case "climb"
            put gSpiderY[i] - 240 * tDT into gSpiderY[i]
            if gSpiderY[i] <= gSpiderHangY[i] then
               put gSpiderHangY[i] into gSpiderY[i]
               put "patrol" into gSpiderState[i]
            end if
            b2kSpriteMoveTo gSpiderSpr[i], gSpiderX[i], gSpiderY[i]
            break
      end switch
   end repeat
end pfTickSpiders

-- Each thwomp's life cycle (only the underside kills; the head is a
-- platform). A chained weight is never the player's to move: it rests
-- STATIC (unpushable, and b2kGrab only takes dynamics) and mouseDown
-- filters the brief dynamic fall out of the grab. The kinematic rise
-- still carries whoever rides the head.
command pfTickThwomps
   local i, tHX, tHY, tBX, tBY, tPos, tBody
   set the itemDelimiter to comma
   put gHeroPX into tHX
   put gHeroPY into tHY
   repeat with i = 1 to gBlockN
      put gBlockB[i] into tBody
      if tBody is empty then next repeat
      if gBlockState[i] is "armed" then
         -- a STATIC block resting at a fixed perch (x cached, y always 200):
         -- trigger on the cached x + the hero snapshot, NO per-frame FFI.
         -- Only the 0-1 blocks actually in motion below pay b2kPosition.
         if abs(tHX - gBlockX[i]) < 42 and tHY > 200 then
            put "falling" into gBlockState[i]
            b2kSetDynamic tBody
            b2kSetGravityScale tBody, 1.8   -- slam, not float
            -- (face swaps only exist on the block_* fallback art; the
            -- chained weight is one frame and the chain stays behind)
            if gBlockFace[i] is true then b2kSpriteSetFrame gBlockSpr[i], "block_fall"
         end if
         next repeat
      end if
      put b2kPosition(tBody) into tPos
      if tPos is empty then next repeat
      put item 1 of tPos into tBX
      put item 2 of tPos into tBY
      switch gBlockState[i]
         case "falling"
            pfBlockUndersideCheck tHX, tHY, tBX, tBY
            if abs(item 2 of b2kVelocity(tBody)) < 4 and tBY > 320 then
               put "down" into gBlockState[i]
               put the milliseconds into gBlockT[i]
               -- rest STATIC: a weight on a chain is not the player's to
               -- shove around (and b2kGrab only takes dynamics, so a
               -- static rest is un-draggable by construction)
               b2kSetStatic tBody
               if gBlockFace[i] is true then b2kSpriteSetFrame gBlockSpr[i], "block_rest"
            end if
            break
         case "down"
            -- a generous rest: time enough to climb onto the head
            if the milliseconds - gBlockT[i] > 2600 then
               put "rising" into gBlockState[i]
               b2kSetKinematic tBody         -- carries whoever rides its head
               b2kSetVelocity tBody, 0, -55
               if gBlockFace[i] is true then b2kSpriteSetFrame gBlockSpr[i], "block_idle"
            end if
            break
         case "rising"
            pfBlockUndersideCheck tHX, tHY, tBX, tBY
            if tBY <= 202 then
               -- re-arm WHERE IT IS, never teleport-home (a teleport
               -- read as vanishing + reappearing)
               put "armed" into gBlockState[i]
               b2kSetStatic tBody
               b2kMoveTo tBody, tBX, 200
               b2kSpriteMoveTo tBody, tBX, 200   -- statics are not body-synced
               put tBX into gBlockX[i]   -- keep the cached perch honest after any drift
               -- re-seat the chain under the weight (defensive: the rise
               -- is vertical, but any drift would betray the chain)
               if gBlockChainA[i] is not empty then b2kSpriteMoveTo gBlockChainA[i], tBX, 76
               if gBlockChainB[i] is not empty then b2kSpriteMoveTo gBlockChainB[i], tBX, 140
            end if
            break
      end switch
   end repeat
end pfTickThwomps

-- Bodiless patrollers (bee, fly, the sweeping saw): sine paths, facing,
-- and proximity hurt - pure geometry, no physics.
command pfTickMovers
   local i, tHX, tHY, tMX, tMY, tMS
   if gMovN is 0 or gMovN is empty then exit pfTickMovers
   set the itemDelimiter to comma
   put the milliseconds into tMS   -- one clock read for the whole pass
   put gHeroPX into tHX
   put gHeroPY into tHY
   repeat with i = 1 to gMovN
      if gMovSpr[i] is empty then next repeat
      -- the lever can power the sweeping saw down: parked, no hurt box
      if i is gSawMov and gSawOn is not true then next repeat
      put gMovX[i] + gMovAX[i] * sin(tMS / gMovPX[i]) into tMX
      put gMovY[i] + gMovAY[i] * sin(tMS / gMovPY[i]) into tMY
      b2kSpriteMoveTo gMovSpr[i], tMX, tMY
      if gMovFlip[i] is true and gMovAX[i] > 0 then
         -- FACE TRAVEL. Position is X + A*sin(t/P), so the x-velocity sign is
         -- cos(t/P): cos>0 = moving RIGHT. Every facing mover here is foes-sheet
         -- flyer art (bee/fly/fish/ladybug) which - like the snail (gotcha 26) -
         -- is drawn facing LEFT, so it must show UNFLIPPED when moving left and
         -- MIRROR when moving right: flip on cos>0. (Was cos<0, which assumed
         -- right-facing art and ran every flyer backwards.)
         b2kSpriteFlipH gMovSpr[i], (cos(tMS / gMovPX[i]) > 0)
      end if
      if gMovHurtW[i] > 0 and gHurtLock is not true then
         -- a brush with a mover (saw, fly) knocks back, never respawns
         if abs(tHX - tMX) < gMovHurtW[i] and abs(tHY - tMY) < gMovHurtH[i] then pfOuch tMX
      end if
   end repeat
end pfTickMovers

-- Dangerous only from below: the hero must be under the block's bottom
-- edge and horizontally within it. A crush knocks back (Wave 2) -- the
-- pop throws him clear of the slam.
command pfBlockUndersideCheck pHX, pHY, pBX, pBY
   if abs(pHX - pBX) < 46 and pHY > pBY + 26 and pHY < pBY + 96 then pfOuch pBX
end pfBlockUndersideCheck

-- =====================================================================
-- Wave 1 ticks. All POLLED geometry plus windows (the doctrine: position
-- verdicts never hang off instantaneous contact reads), and each one
-- exits in O(1) when its piece is absent or locked out.
-- =====================================================================

-- Feet in the spring's band = launch, every 420ms while you stay there.
-- b2kPlayerJump is the ONLY correct boost: a raw upward set-velocity on
-- a grounded player is treated as solver rebound and ground-snapped to
-- zero (the landing-hop fix); the API jump is exempt by design.
command pfTickSpring
   local tBottom
   if gSpringSpr is empty or gHurtLock is true then exit pfTickSpring
   put gHeroPY + 44 into tBottom
   if abs(gHeroPX - gSpringX) < 28 and tBottom >= 524 and \
         tBottom <= 560 and the milliseconds > gSpringMS then
      put the milliseconds + 420 into gSpringMS
      b2kPlayerJump 620   -- ~320px apex: comfortably reaches the sky coin
      b2kSound "spring"
      b2kSpriteSetFrame gSpringSpr, "spring_out"
      put the milliseconds + 260 into gSpringBackMS
   end if
   if gSpringBackMS > 0 and the milliseconds > gSpringBackMS then
      b2kSpriteSetFrame gSpringSpr, "spring"
      put 0 into gSpringBackMS
   end if
end pfTickSpring

-- Headbutting the row from below. The hero's HEAD must be in a tile's
-- bottom band while RISING - judged from the controller's jump state
-- with a 160ms window, because the solver has already zeroed vy on the
-- very frame the head meets the tile (the stomp lesson, applied
-- upward; every rise here IS a jump - springs and stomp bounces go
-- through b2kPlayerJump). Nearest unspent tile only, one bonk per
-- 220ms, so a jump between two tiles never pays twice.
command pfTickBonks
   local i, tHX, tHead, tBest, tBestDX, tDX, tSpr
   if gBonkN is 0 or gBonkN is empty then exit pfTickBonks
   if gHurtLock is true then exit pfTickBonks
   put gHeroPX into tHX
   put gHeroPY - gHeroHalfH into tHead   -- the real capsule top (head)
   if tHead < 440 or tHead > 468 then exit pfTickBonks
   if the milliseconds < gBonkMS then exit pfTickBonks
   if gHeroState is not "jump" and (gJumpMS is 0 or gJumpMS is empty or the milliseconds - gJumpMS > 160) then exit pfTickBonks
   set the itemDelimiter to comma
   put 0 into tBest
   put 9999 into tBestDX
   repeat with i = 1 to gBonkN
      if gBonkUsed[i] is true then next repeat
      if gBonkHost[i] is empty then next repeat
      put abs(tHX - gBonkX[i]) into tDX
      if tDX < 40 and tDX < tBestDX then
         put i into tBest
         put tDX into tBestDX
      end if
   end repeat
   if tBest is 0 then exit pfTickBonks
   put the milliseconds + 220 into gBonkMS
   if gBonkKind[tBest] is "box" then
      put true into gBonkUsed[tBest]
      pfGainCoin
      if gBonkSpr[tBest] is not empty then b2kSpriteSetFrame gBonkSpr[tBest], "block_empty"
      b2kCamShake 2, 90
      -- the payout pops above the box (the same one-shot as a pickup)
      b2kSpriteNew "tiles", "coin_gold_side", gBonkX[tBest], 352
      put the result into tSpr
      if tSpr is not empty then
         b2kSpriteOnFinish tSpr, "pfPopDone"
         b2kSpritePlay tSpr, "coinpop"
      end if
   else
      pfSmashBrick tBest
   end if
end pfTickBonks

-- Six brick chunks built ONCE per level (cast phase, so the hero
-- exists for the no-collide pairing): invisible spawned balls wearing
-- brick_brown art, parked STATIC far left of the world. A smash only
-- MOVES them: creating controls mid-game under accelerated rendering
-- is a guaranteed hitch (the spike's dynamic-layer stall in
-- miniature), and that frozen frame let physics outrun the debris -
-- "the chunks never showed up". Build once, write on change.
command pfMakeDebrisPool
   local i, tRef, tSpr
   put 0 into gDebrisNext
   repeat with i = 1 to 6
      put empty into gDebrisB[i]
      put empty into gDebrisSpr[i]
      put 0 into gDebrisUntil[i]
      b2kSpawnBall -700 + i * 20, 300, 14, "orange"
      put the result into tRef
      if tRef is empty then next repeat
      set the visible of tRef to false
      b2kNoCollide tRef, gHero
      b2kSetStatic tRef
      put tRef into gDebrisB[i]
      b2kSpriteNew "tiles", "brick_brown", -700 + i * 20, 300
      put the result into tSpr
      if tSpr is not empty then
         b2kSpriteBind tSpr, tRef
         put tSpr into gDebrisSpr[i]
      end if
   end repeat
end pfMakeDebrisPool

-- A brick shatters: host body and face go, three POOLED chunks fling
-- out of it. Nothing is created here - see pfMakeDebrisPool.
command pfSmashBrick pWhich
   local i, tHost, tSlot, tX, tDX, tVX
   put gBonkHost[pWhich] into tHost
   put true into gBonkUsed[pWhich]
   b2kSound "smash"
   b2kCamShake 3, 120
   if gBonkSpr[pWhich] is not empty then b2kSpriteRemove gBonkSpr[pWhich]
   put empty into gBonkSpr[pWhich]
   if tHost is not empty then b2kRemove tHost
   if there is a graphic ("pf_bonk" & pWhich) then delete graphic ("pf_bonk" & pWhich)
   put empty into gBonkHost[pWhich]
   put gBonkX[pWhich] into tX
   set the itemDelimiter to comma
   repeat with i = 1 to 3
      put item i of "-16,16,0" into tDX
      put item i of "-150,150,20" into tVX
      add 1 to gDebrisNext
      if gDebrisNext > 6 then put 1 into gDebrisNext
      put gDebrisNext into tSlot
      if gDebrisB[tSlot] is empty then next repeat
      b2kSetDynamic gDebrisB[tSlot]
      b2kMoveTo gDebrisB[tSlot], tX + tDX, 408 + (i mod 2) * 8
      b2kSetVelocity gDebrisB[tSlot], tVX, -280 - i * 20
      put the milliseconds + 1200 into gDebrisUntil[tSlot]
   end repeat
end pfSmashBrick

-- Flown chunks re-park ~0.5s before the kill floor would eat them: a
-- destroyed pool slot cannot be refilled without a mid-game create.
-- Six array reads per frame while nothing is flying.
command pfTickDebris
   local i
   repeat with i = 1 to 6
      if gDebrisUntil[i] is 0 or gDebrisUntil[i] is empty then next repeat
      if the milliseconds < gDebrisUntil[i] then next repeat
      put 0 into gDebrisUntil[i]
      if gDebrisB[i] is empty then next repeat
      b2kSetStatic gDebrisB[i]
      b2kMoveTo gDebrisB[i], -700 + i * 20, 300
      b2kSpriteMoveTo gDebrisB[i], -700 + i * 20, 300
   end repeat
end pfTickDebris

-- Phase D: the DUST-POOF pool. Eight tiny pale balls parked off-world; a stomp
-- flings four of them out of the foe (pfDustBurst), and pfTickDust re-parks them
-- ~0.5s later. The balls ARE the art (no sprite), so a dust mote is just a small
-- light circle arcing up out of the squash - the classic stomp poof, no new
-- frames. Bodies (not graphics), so b2kMoveTo handles the camera scroll for free.
command pfMakeDustPool
   local i, tRef
   put 0 into gDustNext
   repeat with i = 1 to 8
      put empty into gDustB[i]
      put 0 into gDustUntil[i]
      b2kSpawnBall -800 + i * 18, 300, 6, "238,234,216"
      put the result into tRef
      if tRef is empty then next repeat
      b2kNoCollide tRef, gHero
      b2kSetStatic tRef
      put tRef into gDustB[i]
   end repeat
end pfMakeDustPool

-- Fling four pooled dust motes out of (pX,pY) - call it the moment a foe is
-- squashed. Nothing is created here; see pfMakeDustPool.
command pfDustBurst pX, pY
   local i, tSlot, tDX, tVX
   if gDustNext is empty then exit pfDustBurst   -- no pool on this build
   set the itemDelimiter to comma
   repeat with i = 1 to 4
      put item i of "-14,14,-6,6" into tDX
      put item i of "-130,130,-55,55" into tVX
      add 1 to gDustNext
      if gDustNext > 8 then put 1 into gDustNext
      put gDustNext into tSlot
      if gDustB[tSlot] is empty then next repeat
      b2kSetDynamic gDustB[tSlot]
      b2kMoveTo gDustB[tSlot], pX + tDX, pY - 8
      b2kSetVelocity gDustB[tSlot], tVX, -210 - i * 22
      put the milliseconds + 500 into gDustUntil[tSlot]
   end repeat
end pfDustBurst

-- Flung motes re-park ~0.5s out (before the kill floor eats them). Eight array
-- reads per frame while none are flying.
command pfTickDust
   local i
   repeat with i = 1 to 8
      if gDustUntil[i] is 0 or gDustUntil[i] is empty then next repeat
      if the milliseconds < gDustUntil[i] then next repeat
      put 0 into gDustUntil[i]
      if gDustB[i] is empty then next repeat
      b2kSetStatic gDustB[i]
      b2kMoveTo gDustB[i], -800 + i * 18, 300
   end repeat
end pfTickDust

-- The lever: STOP at it (grounded in its band, near-zero vx) to toggle
-- the sweeping saw's power - running through never flips it, so the
-- main path stays accident-free. A leave-the-band latch re-arms it; no
-- timer, no strobing. Powered down the saw stops spinning, fades and
-- stops hurting; the handle mirrors the state (right = on, left = off).
command pfTickLever
   if gLeverSpr is empty or gHurtLock is true then exit pfTickLever
   set the itemDelimiter to comma
   if abs(gHeroPX - gLeverX) >= 30 or abs(gHeroPY - 532) >= 50 then
      put true into gLeverArmed   -- left the band: ready for the next flip
      exit pfTickLever
   end if
   if gLeverArmed is not true then exit pfTickLever
   if abs(item 1 of b2kVelocity(gHero)) < 40 and b2kPlayerOnGround() then
      put false into gLeverArmed
      put (gSawOn is not true) into gSawOn
      b2kSound "lever"
      if gSawOn is true then
         b2kSpriteSetFrame gLeverSpr, "lever_right"
      else
         b2kSpriteSetFrame gLeverSpr, "lever_left"
      end if
      if gSawSpr is not empty then
         if gSawOn is true then
            set the blendLevel of gSawSpr to 0
            b2kSpritePlay gSawSpr, "sawspin"
         else
            b2kSpriteStop gSawSpr
            set the blendLevel of gSawSpr to 55
         end if
      end if
   end if
end pfTickLever

-- The locked door: holding the key and approaching the door swings it
-- open FOR GOOD (one-shot world state - respawns walk back through).
-- The trigger fires ~20px before the hero physically touches the face,
-- so no pressing-into-the-door is ever needed. Clearing the passage
-- body PARKS it 2000px above the world first (b2kMoveTo - the thwomp
-- re-arm path, proven on every install) and only then tries
-- b2kDisable in its own try (a missing newer binding must not kill
-- the park); nothing is deleted inside the frame loop. Only the 128px
-- passage clears - the wall above is permanent, and the lock tile
-- dissolves into plain stone so the wall stays visually whole.
-- Every coloured door, polled: at the wall you reach (within 80px, jumped up
-- to the lintel) the matching KEY opens it - each colour independent, and the
-- key is CONSUMED so it opens exactly its own door. Keyless = a throttled
-- "LOCKED, find the <colour> key" note (shared with the flag deny throttle).
command pfTickDoors
   local i, tWord, k, tNew
   if gDoorN is 0 or gDoorN is empty then exit pfTickDoors
   set the itemDelimiter to comma
   repeat with i = 1 to gDoorN
      if gDoorOpen[i] is true then next repeat
      if gDoorSprB[i] is empty then next repeat
      if abs(gHeroPX - gDoorX[i]) >= 80 or gHeroPY <= 360 then next repeat
      put gDoorWord[i] into tWord
      if tWord is not among the items of gKeysHeld then
         if the milliseconds > gFlagNoteMS then
            put the milliseconds + 2600 into gFlagNoteMS
            b2kSound "deny"
            pfNotice "LOCKED - find the " & tWord & " KEY, back along the way", 2400
         end if
         next repeat
      end if
      -- UNLOCK door i and consume its key from the held set
      put true into gDoorOpen[i]
      put empty into tNew
      repeat for each item k in gKeysHeld
         if k is not tWord then
            if tNew is empty then put k into tNew else put tNew & "," & k into tNew
         end if
      end repeat
      put tNew into gKeysHeld
      b2kSound "unlock"
      b2kCamShake 3, 150
      -- the lock dissolves into the wall (removing it would punch a
      -- see-through hole in front of the still-solid wall host)
      if gLockSpr[i] is not empty then b2kSpriteSetFrame gLockSpr[i], "terrain_stone_block_center"
      -- the key was just dropped from gKeysHeld above, so its hud_key_* icon
      -- vanishes on the next pfUpdateHud (the old ride-along sprite is gone)
      if gDoorSprT[i] is not empty then b2kSpriteSetFrame gDoorSprT[i], "door_open_top"
      b2kSpriteSetFrame gDoorSprB[i], "door_open"
      if there is a graphic gDoorHostNm[i] then
         b2kMoveTo the long id of graphic gDoorHostNm[i], gDoorX[i], -2000
         try
            b2kDisable the long id of graphic gDoorHostNm[i]
         catch tErr
         end try
      end if
   end repeat
end pfTickDoors

-- The boulder cycle: parked static at the top, released on a timer with a
-- nudge + rumble, re-parked the moment it rolls past the reset line (so it
-- never reaches the kill floor). The hit is a POLL - it rolls THROUGH the
-- hero (b2kNoCollide), since a solid shove would fight the controller. One
-- position read per live boulder; O(1) out when none exist or while parked.
command pfTickBoulder
   local i, tPos, tX, tY, tMS
   if gBoulderN is 0 or gBoulderN is empty then exit pfTickBoulder
   set the itemDelimiter to comma
   put the milliseconds into tMS
   repeat with i = 1 to gBoulderN
      if gBoulderB[i] is empty then next repeat
      if gBoulderT[i] > 0 then
         if tMS < gBoulderT[i] then next repeat
         put 0 into gBoulderT[i]
         b2kSetDynamic gBoulderB[i]
         b2kSetVelocity gBoulderB[i], gBoulderVX[i], 0   -- shove it off (signed)
         put tMS + 250 into gBoulderGrace[i]
         b2kSound "rumble"
         next repeat
      end if
      put b2kPosition(gBoulderB[i]) into tPos
      if tPos is empty then next repeat
      put item 1 of tPos into tX
      put item 2 of tPos into tY
      -- past the reset line in the ROLL DIRECTION (or fell): re-park + recycle
      if (gBoulderVX[i] > 0 and tX > gBoulderResetX[i]) \
            or (gBoulderVX[i] < 0 and tX < gBoulderResetX[i]) or tY > 700 then
         b2kSetStatic gBoulderB[i]
         b2kMoveTo gBoulderB[i], gBoulderHomeX[i], gBoulderHomeY[i]
         -- a STATIC body is not sprite-synced (the thwomp re-arm lesson),
         -- so re-place the bound stone face by hand back at the top
         if gBoulderSpr[i] is not empty then b2kSpriteMoveTo gBoulderSpr[i], gBoulderHomeX[i], gBoulderHomeY[i]
         put tMS + 1500 into gBoulderT[i]
         next repeat
      end if
      if gHurtLock is not true and tMS > gBoulderGrace[i] then
         if abs(gHeroPX - tX) < gBoulderHurtR[i] and abs(gHeroPY - tY) < 46 then pfOuch tX
      end if
   end repeat
end pfTickBoulder

-- Patrol the moving-platform lifts: bounce each off its min/max endpoints.
-- WRITE-ON-CHANGE only - a lift must keep moving (so it asserts velocity),
-- but re-setting an unchanged vx every frame is the parked-shell mistake
-- (gotcha 17: a needless wake + 2 FFI per frame). The rider inherits the
-- velocity automatically (platformCarry), so there is no per-rider work
-- here. One clock-free pass: endpoints are positions, no time math needed.
command pfTickLift
   local i, tPos, tX, tV
   if gLiftN is 0 or gLiftN is empty then exit pfTickLift
   set the itemDelimiter to comma
   repeat with i = 1 to gLiftN
      if gLift[i] is empty then next repeat
      put b2kPosition(gLift[i]) into tPos
      if tPos is empty then next repeat
      put item 1 of tPos into tX
      put gLiftVX[i] into tV
      -- past an endpoint while still heading that way: reverse the drift
      if tV > 0 and tX >= gLiftMax[i] then put - gLiftSpeed[i] into tV
      if tV < 0 and tX <= gLiftMin[i] then put gLiftSpeed[i] into tV
      if tV is not gLiftVX[i] then
         b2kSetVelocity gLift[i], tV, 0   -- the ONLY per-lift write, at the turn
         put tV into gLiftVX[i]
      end if
   end repeat
end pfTickLift

-- The serpent's arc (Phase E): a sine EMERGENCE (0 at the lips, 1 over the centre)
-- drives both how far it has risen and where along the pool it sits, so one
-- parameter traces a rise-cross-sink path lip to lip; it loops, and the reset
-- lands while submerged (hidden), so the teleport back to the left lip never
-- shows. The pool surface (the y576 row) occludes its lower body as it rises; we
-- ALSO hide it outright while its head is below the surface so the no-tile
-- fallback never shows a snake floating in the gap. Proximity HURT (the saw rule,
-- gotcha 16) fires only while emerged - a recoverable knockback, never a respawn.
-- O(1) out when no serpent exists (every non-serpent level).
command pfTickSerpent
   local tP, tEm, tX, tHeadY, tCy, tMS
   if gLSerpSpr is empty then exit pfTickSerpent
   put the milliseconds into tMS
   put (tMS mod gLSerpPer) / gLSerpPer into tP
   put sin(3.14159265 * tP) into tEm                    -- 0 at the lips, 1 at the centre peak (literal pi: kPI is declared later in the script, and a forward constant ref leaves it unresolved on OXT - which pinned tEm at 0 and kept the serpent submerged forever)
   put gLSerpL + (gLSerpR - gLSerpL) * tP into tX
   put gLSerpSurfY - (gLSerpSurfY - gLSerpPeakY) * tEm into tHeadY
   if tHeadY >= gLSerpSurfY - 6 then
      -- submerged (head at/below the pool surface): hide it; the loop reset lands here
      if gLSerpVis then
         set the visible of gLSerpSpr to false
         put false into gLSerpVis
      end if
      exit pfTickSerpent
   end if
   if not gLSerpVis then
      set the visible of gLSerpSpr to true
      put true into gLSerpVis
   end if
   put tHeadY + gLSerpHalfH into tCy                     -- head at the sprite top, so centre = head + half-height
   b2kSpriteMoveTo gLSerpSpr, tX, tCy
   -- proximity HURT (the saw rule): the head's strike zone. Mistime the crossing
   -- and the rearing head bounces you back to the near bank (pfOuch), not a kill.
   if gHurtLock is not true and abs(gHeroPX - tX) < 34 and abs(gHeroPY - tHeadY) < 84 then pfOuch tX
end pfTickSerpent

-- The powder keg: idle until the hero is near, then the fuse lights
-- (bomb_active); a beat later b2kExplode scatters the woodpile, knocks the
-- hero if he lingered, and the barrel parks off-world (the door-clear
-- pattern: move first, disable behind a try). One-shot; O(1) when idle.
command pfTickBarrel
   local i, tMS
   if gBarrelN is 0 or gBarrelN is empty then exit pfTickBarrel
   put the milliseconds into tMS
   repeat with i = 1 to gBarrelN
      switch gBarrelState[i]
         case "idle"
            if abs(gHeroPX - gBarrelX[i]) < 92 and abs(gHeroPY - gBarrelY[i]) < 120 then
               put "lit" into gBarrelState[i]
               put tMS + 850 into gBarrelT[i]
               if gBarrelSpr[i] is not empty then b2kSpriteSetFrame gBarrelSpr[i], "bomb_active"
            end if
            break
         case "lit"
            if tMS >= gBarrelT[i] then
               put "boom" into gBarrelState[i]
               b2kSound "boom"
               b2kCamShake 8, 320
               b2kExplode gBarrelX[i], gBarrelY[i], 152, 1300
               if gHurtLock is not true and abs(gHeroPX - gBarrelX[i]) < 112 \
                     and abs(gHeroPY - gBarrelY[i]) < 130 then pfOuch gBarrelX[i]
               if gBarrelSpr[i] is not empty then b2kSpriteSetFrame gBarrelSpr[i], "fireball"
               if gBarrelB[i] is not empty then
                  b2kMoveTo gBarrelB[i], gBarrelX[i], -2200
                  try
                     b2kDisable gBarrelB[i]
                  catch tErr
                  end try
               end if
               put tMS + 240 into gBarrelT[i]
            end if
            break
         case "boom"
            if tMS >= gBarrelT[i] then
               put "gone" into gBarrelState[i]
               if gBarrelSpr[i] is not empty then b2kSpriteRemove gBarrelSpr[i]
               put empty into gBarrelSpr[i]
            end if
            break
      end switch
   end repeat
end pfTickBarrel

-- =====================================================================
-- Events: sensors (coins, hazards, goal) and contacts (the slimes);
-- the pressure plate is POLLED in pfTickGate, not event-counted
-- =====================================================================
on b2kSensorEnter pSensorCtrl, pVisitorCtrl
   local tPopAt, tWord, tCoinVal, tPopFrame, tPopAnim
   if pSensorCtrl is empty then exit b2kSensorEnter
   if pVisitorCtrl is not gHero then exit b2kSensorEnter
   if the uPfKeyFlag of pSensorCtrl is true then
      put the uPfKeyWord of pSensorCtrl into tWord
      if tWord is empty then put "yellow" into tWord
      set the itemDelimiter to comma
      if tWord is not among the items of gKeysHeld then
         if gKeysHeld is empty then
            put tWord into gKeysHeld
         else
            put gKeysHeld & "," & tWord into gKeysHeld
         end if
         b2kSound "key"
         b2kSpriteRemove pSensorCtrl
         -- the carried key now shows as a hud_key_* icon in the art HUD
         -- (pfUpdateHud reads gKeysHeld), which retired the ride-along sprite.
      end if
      exit b2kSensorEnter
   end if
   if the uPfGemFlag of pSensorCtrl is true then
      add 1 to gGems
      b2kSound "gem"
      b2kSpriteRemove pSensorCtrl
      try
         delete pSensorCtrl   -- fallback diamond is not Kit-spawned
      catch tErr
      end try
      exit b2kSensorEnter
   end if
   if the uPfStarFlag of pSensorCtrl is true then
      add 1 to gStars
      b2kSound "gem"   -- a celebratory pickup chime (shares the gem tone for now)
      if gHudStar is not empty then set the blendLevel of gHudStar to 0   -- light the HUD slot at once
      b2kSpriteRemove pSensorCtrl
      try
         delete pSensorCtrl   -- fallback bead is not Kit-spawned
      catch tErr
      end try
      pfNotice "STAR found - the hidden collectible!", 1900
      exit b2kSensorEnter
   end if
   if the uPfCoinFlag of pSensorCtrl is true then
      put the uPfCoinVal of pSensorCtrl into tCoinVal   -- the tier value, before removal
      pfGainCoin tCoinVal
      put b2kPosition(pSensorCtrl) into tPopAt   -- world px, from its body
      b2kSpriteRemove pSensorCtrl
      try
         delete pSensorCtrl         -- fallback oval is not Kit-spawned
      catch tErr
      end try
      -- the pickup POP matches the coin's tier (most coins are silver/bronze now,
      -- so a gold pop on every grab would jar)
      put "coin_gold_side" into tPopFrame
      put "coinpop" into tPopAnim
      if tCoinVal is 2 then
         put "coin_silver_side" into tPopFrame
         put "coinpopsilver" into tPopAnim
      else if tCoinVal is 1 then
         put "coin_bronze_side" into tPopFrame
         put "coinpopbronze" into tPopAnim
      end if
      if tPopAt is not empty and b2kSheetHasFrame("tiles", tPopFrame) then
         set the itemDelimiter to comma
         b2kSpriteNew "tiles", tPopFrame, item 1 of tPopAt, item 2 of tPopAt
         put the result into tPopAt   -- capture: the next command clears it
         if tPopAt is not empty then
            b2kSpriteOnFinish tPopAt, "pfPopDone"
            b2kSpritePlay tPopAt, tPopAnim
         end if
      end if
      exit b2kSensorEnter
   end if
   if the uPfCheckFlag of pSensorCtrl is true then
      -- activate the FLAG YOU TOUCHED (not a single global), raise it once, and
      -- only ever ADVANCE the respawn point - so an earlier flag re-touched on a
      -- knockback can never drag the respawn backward. (The bug this fixes: with
      -- the old single gCheck* globals, three checkpoints in L6 meant touching
      -- any flag banked the LAST one's x and raised the LAST flag, so the first
      -- never lit and a later one stood pre-raised.)
      if the uPfCheckDone of pSensorCtrl is not true then
         set the uPfCheckDone of pSensorCtrl to true
         put true into gCheckpointOn
         if the uPfCheckX of pSensorCtrl > gRespawnX then
            put the uPfCheckX of pSensorCtrl into gRespawnX
            put 470 into gRespawnY
         end if
         b2kSpritePlay pSensorCtrl, "checkwave"
         b2kSound "check"
         b2kCamShake 3, 180
      end if
      exit b2kSensorEnter
   end if
   if the uPfHazardFlag of pSensorCtrl is true then
      -- spikes/saw sensors: knockback away from the hazard's centre
      -- (a wide spike strip pops you back toward the side you entered)
      set the itemDelimiter to comma
      pfOuch item 1 of b2kPosition(pSensorCtrl)
   end if
   if the uPfKillFlag of pSensorCtrl is true then
      pfHurt   -- the kill floor under the water: sinking out the bottom respawns
      exit b2kSensorEnter
   end if
   if the uPfGoalFlag of pSensorCtrl is true then
      -- camera-dead fallback clamps play to one screen, so most coins are
      -- out of reach there: the near flag advances unconditionally instead
      if gCoins >= gCoinsTotal or gCamOK is not true then
         if gLevel >= 7 then
            pfWin
         else
            pfLevelClear
         end if
      else
         -- short of the total: the flag BUZZES and banners the count,
         -- throttled so standing on it does not spam (the HUD line
         -- repeats the hint until the count is full)
         put true into gFlagHint
         if the milliseconds > gFlagNoteMS then
            put the milliseconds + 2600 into gFlagNoteMS
            b2kSound "deny"
            pfNotice "Locked: " & (gCoinsTotal - gCoins) & " more coin(s) to find - then return to this flag", 2400
         end if
      end if
   end if
end b2kSensorEnter

-- Something fell past the kill floor and the Kit is about to remove it
-- (body destroyed; Kit-spawned controls deleted). Clean up OUR
-- companions: a slime's or thwomp's bound art and its table slot. Do
-- not delete the body control here - the Kit is mid-removal.
on b2kFell pCtrl
   local i
   repeat with i = 1 to gSlimeN
      if gSlimeB[i] is not empty and pCtrl is gSlimeB[i] then
         if gSlimeSpr[i] is not empty then b2kSpriteRemove gSlimeSpr[i]
         put empty into gSlimeSpr[i]
         put empty into gSlimeB[i]
         put empty into gSlimeGoneAt[i]
         exit b2kFell
      end if
   end repeat
   repeat with i = 1 to gBlockN
      if gBlockB[i] is not empty and pCtrl is gBlockB[i] then
         if gBlockSpr[i] is not empty then b2kSpriteRemove gBlockSpr[i]
         if gBlockChainA[i] is not empty then b2kSpriteRemove gBlockChainA[i]
         if gBlockChainB[i] is not empty then b2kSpriteRemove gBlockChainB[i]
         put empty into gBlockSpr[i]
         put empty into gBlockChainA[i]
         put empty into gBlockChainB[i]
         put empty into gBlockB[i]
         exit b2kFell
      end if
   end repeat
   -- the crate lost to the pit: the Kit removes the spawned box; we
   -- sweep the bound box face (losing the crate closes the gate, as ever)
   if gCrateB is not empty and pCtrl is gCrateB then
      if gCrateSpr is not empty then b2kSpriteRemove gCrateSpr
      put empty into gCrateSpr
      put empty into gCrateB
      exit b2kFell
   end if
   -- brick debris dying at the kill floor: the Kit removes the spawned
   -- ball; we sweep the brick art bound to it
   repeat with i = 1 to 6
      if gDebrisB[i] is not empty and pCtrl is gDebrisB[i] then
         if gDebrisSpr[i] is not empty then b2kSpriteRemove gDebrisSpr[i]
         put empty into gDebrisSpr[i]
         put empty into gDebrisB[i]
         exit b2kFell
      end if
   end repeat
end b2kFell

-- Hero vs slime: falling onto a NORMAL one squashes it (and bounces you);
-- anything else - sides, undersides, or any touch of a SPIKE slime - hurts.
-- "Falling onto" is judged by the PLAYER CONTROLLER's state, not by the
-- hero's velocity: contacts dispatch AFTER the physics step, when the
-- solver has already absorbed the impact (velocity reads near zero on a
-- clean stomp). At dispatch time b2kPlayerState() is this frame's state
-- and gPrevState is last frame's - a stomp shows up as land/fall in one
-- of them. The raw velocity stays as a belt-and-braces fallback.
on b2kContact pA, pB
   local i, tWhich, tFoe, tState, tStomp, tAbove, tKind, tFX
   if gHurtLock is true then exit b2kContact
   put empty into tWhich
   repeat with i = 1 to gSlimeN
      if gSlimeB[i] is empty then next repeat
      if (pA is gHero and pB is gSlimeB[i]) or (pB is gHero and pA is gSlimeB[i]) then
         put i into tWhich
         exit repeat
      end if
   end repeat
   if tWhich is empty then exit b2kContact
   put gSlimeB[tWhich] into tFoe
   set the itemDelimiter to comma
   -- "falling onto" = airborne within the last quarter second. A dynamic
   -- slime SINKS under the hero, so the probe grounds a few frames before
   -- the contact event arrives - by then the instantaneous state has left
   -- land/fall. A window cannot be outrun; walking in sideways still
   -- hurts (no recent airtime).
   put b2kPlayerState() into tState
   put (tState is "land" or tState is "fall" \
         or gPrevState is "land" or gPrevState is "fall" \
         or (gAirMS > 0 and the milliseconds - gAirMS < 250) \
         or (item 2 of b2kVelocity(gHero)) > 40) into tStomp
   put ((item 2 of b2kPosition(gHero)) < (item 2 of b2kPosition(tFoe)) - 16) into tAbove
   put item 1 of b2kPosition(tFoe) into tFX
   put gSlimeKind[tWhich] into tKind
   -- ===== the Wave 3 kinds own their verdicts =====
   if tKind is "snail" then
      -- a stomp SHELLS the snail (it does not die); a side touch hurts
      if tStomp and tAbove then
         put "shell" into gSlimeKind[tWhich]
         put 0 into gSlimeDir[tWhich]
         b2kSetVelocity tFoe, 0, item 2 of b2kVelocity(tFoe)
         if gSlimeSpr[tWhich] is not empty then
            b2kSpriteStop gSlimeSpr[tWhich]
            b2kSpriteSetFrame gSlimeSpr[tWhich], "snail_shell"
         end if
         b2kSound "stomp"
         b2kPlayerJump 260
      else
         pfOuch tFX
      end if
      exit b2kContact
   end if
   if tKind is "shell" then
      -- ANY touch of a parked shell KICKS it away from the hero (a
      -- stomp-kick also bounces him, stomp-style); resting shells are
      -- otherwise harmless
      if gHeroPX < tFX then
         put 520 into gSlimeDir[tWhich]
      else
         put -520 into gSlimeDir[tWhich]
      end if
      put "shellslide" into gSlimeKind[tWhich]
      b2kSetVelocity tFoe, gSlimeDir[tWhich], 0
      b2kSound "kick"
      if tStomp and tAbove then b2kPlayerJump 260
      exit b2kContact
   end if
   if tKind is "shellslide" then
      -- stomping a sliding shell STOPS it; its sides hurt
      if tStomp and tAbove then
         put "shell" into gSlimeKind[tWhich]
         put 0 into gSlimeDir[tWhich]
         b2kSetVelocity tFoe, 0, item 2 of b2kVelocity(tFoe)
         b2kSound "stomp"
         b2kPlayerJump 260
      else
         pfOuch tFX
      end if
      exit b2kContact
   end if
   if tKind is "bat" or tKind is "batfly" or tKind is "mimic" or tKind is "mimiclive" then
      -- one-stomp critters; their touch knocks back like everything
      if tStomp and tAbove then
         pfSquashSlime tWhich
         b2kPlayerJump 260
      else
         pfOuch tFX
      end if
      exit b2kContact
   end if
   -- ===== the classic slimes =====
   if tKind is not "spike" and tStomp and tAbove then
      pfSquashSlime tWhich
      b2kPlayerJump 260   -- the API jump: exempt from the ground-snap
                          -- (a raw upward set-velocity on a grounded
                          -- player is treated as solver rebound)
   else
      -- contact damage = knockback away from the slime (Wave 2 split)
      pfOuch tFX
   end if
end b2kContact

-- The slime-family death: pick the kind's death pose, freeze the art,
-- drop the body, sweep the remains a moment later (pfTickSlimes).
-- Wave 3 kinds die too - bats and mimics to their spook hit frames, a
-- bowled snail leaves its shell behind. (A frame a sheet lacks is a
-- safe no-op inside the Kit: the art simply keeps its last pose.)
command pfSquashSlime pWhich
   local tFlat, tPos
   if gSlimeB[pWhich] is empty then exit pfSquashSlime
   b2kSound "stomp"
   set the itemDelimiter to comma
   put b2kPosition(gSlimeB[pWhich]) into tPos   -- the squash point, for the dust poof
   switch gSlimeKind[pWhich]
      case "bat"
      case "batfly"
         put "bat_dead.png" into tFlat       -- Phase D: a proper DEAD pose, not the _hit flash
         break
      case "mimic"
      case "mimiclive"
         put "grassBlock_dead.png" into tFlat
         break
      case "snail"
      case "shell"
      case "shellslide"
         put "snail_shell" into tFlat
         break
      default
         -- the per-row squash frame: a slime's "_flat", or EMPTY for the
         -- showcase critters whose sheet has no squashed pose (they just
         -- drop and fade - never the wrong art)
         put gSlimeFlat[pWhich] into tFlat
   end switch
   if gSlimeSpr[pWhich] is not empty then
      b2kSpriteStop gSlimeSpr[pWhich]
      if tFlat is not empty then b2kSpriteSetFrame gSlimeSpr[pWhich], tFlat
      b2kSpriteUnbind gSlimeSpr[pWhich]
   end if
   if tPos is not empty then pfDustBurst (item 1 of tPos), (item 2 of tPos)   -- Phase D: a dust POOF at the squash
   b2kRemove gSlimeB[pWhich]      -- body gone; the death art lingers a moment
   put empty into gSlimeB[pWhich]
   put the milliseconds + 700 into gSlimeGoneAt[pWhich]
   if tPos is not empty then     -- Phase D: remember the squash point so it POPS up as it fades
      put item 1 of tPos into gSlimeDeadX[pWhich]
      put item 2 of tPos into gSlimeDeadY[pWhich]
   else
      put empty into gSlimeDeadY[pWhich]
   end if
end pfSquashSlime

-- The RESPAWN path -- Wave 2 reserves it for LETHAL hits (pits, the
-- kill plane). Contact damage goes through pfOuch instead.
command pfHurt
   if gHurtLock is true or gWinLock is true then exit pfHurt
   put true into gHurtLock
   add 1 to gFalls
   put kHearts into gHearts   -- a respawn restores the full buffer (the forgiving model)
   b2kSound "hurt"
   b2kCamShake 7, 280
   -- the controller must not steer or re-anim during the hit pose; it
   -- keeps observing (state stays fresh) and resumes in pfHurtDone.
   -- (The explicit control call also cancels any Kit knockback in
   -- flight -- a knockback that ends in a pit hands over cleanly.)
   b2kPlayerControl false
   set the itemDelimiter to comma
   b2kSetVelocity gHero, 0, item 2 of b2kVelocity(gHero)
   b2kSpritePlay gHeroSpr, "hit", true   -- non-loop; OnFinish respawns
end pfHurt

-- Contact damage -> the Kit's knockback standard (Wave 2): an away-pop
-- off pFromX, the hurt pose, a short control-off window, then a mercy
-- window. The Kit no-ops repeat hurts inside the window; the gate here
-- just keeps the sound/shake from spamming alongside.
command pfOuch pFromX
   if gHurtLock is true or gWinLock is true then exit pfOuch
   if b2kPlayerHurtIs() then exit pfOuch
   add 1 to gOuches
   -- Phase F health: each contact hit spends one heart. The mercy window
   -- (b2kPlayerHurtIs, above) means you can lose at most one pip per hit, so
   -- the five-heart buffer can't drain in a single frame of overlap. Empty the
   -- row and the hit becomes LETHAL: hand off to pfHurt, which respawns at the
   -- checkpoint and REFILLS the hearts (pfHurt does its own sound/shake).
   subtract 1 from gHearts
   if gHearts <= 0 then
      put 0 into gHearts
      pfHurt
      exit pfOuch
   end if
   b2kSound "hurt"
   b2kCamShake 5, 200
   b2kPlayerHurt pFromX
end pfOuch

-- All coins + the flag on levels 1-2: bank the stats, banner the clear,
-- and rebuild the NEXT level outside this frame (sensor dispatch runs
-- mid-loop; rebuilding the world from inside it is the micro-game
-- lesson - defer with a send).
command pfLevelClear
   if gWinLock is true then exit pfLevelClear
   put true into gWinLock
   b2kSound "win"
   b2kPlayerControl false
   set the itemDelimiter to comma
   b2kSetVelocity gHero, 0, item 2 of b2kVelocity(gHero)
   b2kSpritePlay gHeroSpr, "win", true
   b2kCamShake 4, 300
   add gFalls to gTotalFalls
   add (the milliseconds - gRunStart) div 1000 to gSecsBank
   add gGems to gGemsBank
   add gGemsTotal to gGemsAllTotal
   add gScore to gScoreBank
   add gScoreTotal to gScoreAllTotal
   add gStars to gStarsBank
   add gStarsTotal to gStarsAllTotal
   pfNotice "LEVEL " & gLevel & " CLEAR!", 1400
   send pfNextLevel to me in 1200 milliseconds
end pfLevelClear

-- Fires from pfLevelClear's send. If an R-restart beat us here the
-- rebuild already reset gWinLock - a stale advance must then no-op.
command pfNextLevel
   if gWinLock is not true then exit pfNextLevel
   add 1 to gLevel
   pfStartGame
end pfNextLevel

-- All coins + the flag on level 3: the celebration dialogue.
command pfWin
   local tSecs, tMsg
   if gWinLock is true then exit pfWin
   put true into gWinLock
   put true into gWon
   -- the win dialogue owns the screen: any banner yields immediately
   put 0 into gNoticeUntil
   if there is a field "pfSplash" then set the visible of field "pfSplash" to false
   -- the banked clears plus this level = the whole run
   put gSecsBank + (the milliseconds - gRunStart) div 1000 into tSecs
   put tSecs into gWinSecs
   add gFalls to gTotalFalls
   add gGems to gGemsBank
   add gGemsTotal to gGemsAllTotal
   add gScore to gScoreBank
   add gScoreTotal to gScoreAllTotal
   add gStars to gStarsBank
   add gStarsTotal to gStarsAllTotal
   b2kSound "win"
   b2kPlayerControl false   -- the win dance owns the art from here
   set the itemDelimiter to comma
   b2kSetVelocity gHero, 0, item 2 of b2kVelocity(gHero)
   b2kSpritePlay gHeroSpr, "win", true
   b2kCamShake 5, 400
   -- physics confetti: a burst of little balls around the hero (he is
   -- standing at the flag, wherever this level put it)
   local i, tC, tHX, tHY
   put item 1 of b2kPosition(gHero) into tHX
   put item 2 of b2kPosition(gHero) into tHY
   repeat with i = 1 to 12
      put item ((i mod 5) + 1) of "gold,orange,red,purple,white" into tC
      b2kSpawnBall tHX + random(81) - 41, tHY - 120 + random(41) - 21, 10 + random(8), tC
      put the result into tC
      if tC is not empty then b2kPush tC, random(361) - 180, 0 - (180 + random(220))
   end repeat
   -- the final-run payoff, composed like a level card: a title header, the chosen
   -- hero, then every banked stat, the flawless callout, and the replay prompt
   put "Y O U   W I N" & cr & "all seven levels clear" & cr & cr & cr into tMsg
   put "Hero   -   " & pfHeroName(gHeroSkin) & cr & cr after tMsg
   put "Time  " & format("%d:%02d", tSecs div 60, tSecs mod 60) & "          Falls  " & gTotalFalls & cr & cr after tMsg
   if gGemsAllTotal > 0 then put "Gems   " & gGemsBank & " / " & gGemsAllTotal & cr after tMsg
   if gStarsAllTotal > 0 then put "Stars   " & gStarsBank & " / " & gStarsAllTotal & cr after tMsg
   if gScoreAllTotal > 0 then put "Coin score   " & gScoreBank & " / " & gScoreAllTotal & cr after tMsg
   put cr after tMsg
   if gTotalFalls is 0 then put "A FLAWLESS RUN - not a single tumble." & cr & cr after tMsg
   put "Press  Play again  for a fresh run from level 1." after tMsg
   set the text of field "pfWinText" to tMsg
   set the visible of graphic "pfWinShade" to true
   set the visible of field "pfWinText" to true
   set the visible of button "pfbtn_again" to true
   pfChromeFront
end pfWin

-- The coin-pickup pop finished: remove the one-shot effect sprite.
on pfPopDone pSprite, pAnim
   b2kSpriteRemove pSprite
end pfPopDone

command pfTogglePause
   local tTop
   if b2kIsRunning() then
      b2kPause
      set the label of button "pfbtn_pause" to "Resume"
      -- show the controls overlay, raised to the very top (above the HUD + world)
      if there is a graphic "pfPauseShade" then
         put the number of controls of this card into tTop
         set the layer of graphic "pfPauseShade" to tTop
         set the layer of field "pfPauseText" to tTop
         set the visible of graphic "pfPauseShade" to true
         set the visible of field "pfPauseText" to true
      end if
   else
      b2kResume
      set the label of button "pfbtn_pause" to "Pause"
      if there is a graphic "pfPauseShade" then
         set the visible of graphic "pfPauseShade" to false
         set the visible of field "pfPauseText" to false
      end if
   end if
end pfTogglePause

on pfHurtDone pSprite, pAnim
   -- ONLY the respawn flow's one-shot "hit" may land here: any other
   -- non-looping anim finishing on the hero (a stray pose) must not
   -- teleport him to the checkpoint
   if gHurtLock is not true then exit pfHurtDone
   b2kMoveTo gHero, gRespawnX, gRespawnY
   b2kSetVelocity gHero, 0, 0
   put false into gHurtLock
   b2kPlayerControl true   -- re-asserts the state anim over the hit pose
end pfHurtDone

-- =====================================================================
-- Mouse: buttons by name; everything else is a camera-corrected grab
-- =====================================================================
on mouseDown
   local tName, tHit
   if gAtTitle is true then exit mouseDown   -- the title card owns the screen; no world to grab
   put the short name of the target into tName
   if char 1 to 6 of tName is "pfbtn_" then exit mouseDown
   -- chained weights are not draggable (resting they are static, which
   -- b2kGrab already refuses; this also keeps a FALLING weight from
   -- being dangled off the mouse). The crate is the intended drag.
   put b2kControlAt(b2kCamMouseX(), b2kCamMouseY()) into tHit
   if tHit contains "pf_blockBody" then exit mouseDown
   get b2kGrab(b2kCamMouseX(), b2kCamMouseY())
end mouseDown

on mouseUp
   local tName
   put the short name of the target into tName
   switch tName
      case "pfbtn_reset"
         pfStartGame
         break
      case "pfbtn_pause"
         pfTogglePause
         break
      case "pfbtn_again"
         -- a fresh run: back to level 1, every banked total cleared
         put 1 into gLevel
         pfResetRun
         pfStartGame
         break
      default
         b2kRelease
   end switch
end mouseUp

-- The LEVEL PICKER (the top-right option menu): jump straight to the chosen
-- level. A DEV/TEST convenience so the levels already approved need not be
-- replayed after every update; NOT part of the normal coin-gated progression.
on menuPick pWhich
   local tLv
   if the short name of the target is "pfbtn_level" then
      put word 1 of pWhich into tLv
      if tLv is an integer and tLv >= 1 then pfJumpToLevel tLv
   end if
   pass menuPick
end menuPick

-- Rebuild straight to pLevel with a FRESH run state (banks zeroed, like starting
-- there). pfStartGame hides the win dialogue + clears the win latches itself, so
-- jumping works from play, pause, or the win screen.
command pfJumpToLevel pLevel
   if gBuilding is true then exit pfJumpToLevel
   put pLevel into gLevel
   pfResetRun
   put true into gStarted
   pfStartGame
end pfJumpToLevel

on mouseRelease
   b2kRelease
end mouseRelease

-- R restarts, ESC pauses/resumes, M mutes. These are message-path events
-- (not the Kit's polled input) so they also work WHILE PAUSED, when the
-- sampler is not running.
on rawKeyDown pKeyCode
   -- the boot TITLE screen owns the keyboard: SPACE / RETURN start a fresh run,
   -- 1-5 pick the hero (preview only - no level to rebuild yet), M still mutes;
   -- every other key is swallowed (there is no game running behind the card).
   if gAtTitle is true then
      if pKeyCode is 32 or pKeyCode is 65293 then
         pfStartFromTitle
      else if pKeyCode >= 49 and pKeyCode <= 53 then
         pfTitlePickHero (pKeyCode - 48)
      else if pKeyCode is 109 or pKeyCode is 77 then
         b2kSoundMute (not b2kSoundMuted())
      end if
      exit rawKeyDown
   end if
   if pKeyCode is 65307 then
      pfTogglePause
      exit rawKeyDown
   end if
   if pKeyCode is 114 or pKeyCode is 82 then
      pfStartGame
      exit rawKeyDown
   end if
   if pKeyCode is 109 or pKeyCode is 77 then
      b2kSoundMute (not b2kSoundMuted())
      exit rawKeyDown
   end if
   if pKeyCode is 96 then   -- the ` (backquote) key toggles the dev debug overlay
      pfToggleDebug
      exit rawKeyDown
   end if
   -- (hero select moved to the title screen, so an in-level number press can no
   -- longer accidentally restart the level - see pfShowTitle / pfTitlePickHero)
   pass rawKeyDown
end rawKeyDown

-- (Phase G's in-level pfPickHero was retired in the polish pass: hero select
-- moved to the boot title screen - pfTitlePickHero - so a stray number press
-- can no longer restart the level you are on.)

-- =====================================================================
-- The Kit (embedded verbatim; regenerated by tools/sync-embedded-kit.py -
-- do not edit between the sentinels)
-- =====================================================================
-- >>> BEGIN EMBEDDED KIT >>>
-- =====================================================================
-- box2dxt-kit.livecodescript   /   "Box2Dxt Kit"  (b2k...)
--
-- A friendly, pure-xTalk toolkit over the box2dxt extension. You work in
-- PIXELS, SCREEN coordinates and DEGREES; the kit converts to Box2D's
-- metres / radians / y-up for you, runs the world, and moves your controls.
-- Runs in OpenXTalk (OXT); compatible with LiveCode 9.6.3+.
-- Requires the box2dxt extension loaded (put b2Version() should return 4).
--
-- =====================  60-SECOND START  =============================
--   on openCard
--      b2kQuickStart            -- world + gravity + walls around the card + go
--      b2kSpawnBall 200,80, 50               -- create + drop a ball
--      b2kSpawnBox 260,80, 60,40, "orange"   -- (read `the result` for the ref)
--      b2kContactTarget the long id of me    -- (optional) collision messages
--   end openCard
--   on mouseDown ; get b2kGrab(the mouseH,the mouseV) ; end mouseDown
--   on mouseUp   ; b2kRelease ; end mouseUp
--   on closeCard ; b2kStop ; end closeCard
--
-- =====================  CHEAT SHEET  ================================
-- WORLD   b2kSetup [gx,gy] / b2kQuickStart [gy] / b2kStart / b2kStop /
--         b2kTeardown / b2kAddWalls / b2kWall x1,y1,x2,y2 / b2kClear /
--         b2kPause / b2kResume / b2kIsRunning() / b2kKillFloor y
--         (movers below y are removed; "b2kFell ctrl" precedes each)
-- CONFIG  b2kSetScale px / b2kSetOrigin x,y / b2kSetGravity gx,gy /
--         b2kSetSubsteps n / b2kContactTarget obj / b2kFrameTarget obj /
--         b2kEnableSleeping flag / b2kEnableContinuous flag
-- ATTACH  b2kAddBox ctrl[,dyn] / b2kAddBall ctrl[,dyn] / b2kAddCapsule ctrl[,dyn]
--         b2kAddPolygon ctrl[,dyn] / b2kAddStatic ctrl / b2kAddGround [screenY]
-- SPAWN   b2kSpawnBox x,y,w,h[,color] / b2kSpawnBall x,y,diam[,color] /
--         b2kSpawnCapsule x,y,len,thick[,color]                       (-> control)
-- MATERIAL b2kSetBounce ctrl,0..1 / b2kSetFriction ctrl,0..1 / b2kSetDensity ctrl,d
-- BODY    b2kSetBullet ctrl,flag / b2kSetFixedRotation ctrl,flag /
--         b2kSetGravityScale ctrl,s / b2kSetDamping ctrl,lin[,ang] / b2kWake ctrl /
--         b2kSetType ctrl,name / b2kSetStatic/Dynamic/Kinematic ctrl /
--         b2kEnable/Disable ctrl / b2kSetSleepEnabled ctrl,flag
-- ACT     b2kPush ctrl,dvx,dvy / b2kImpulse ctrl,ix,iy / b2kForce ctrl,fx,fy /
--         b2kSetVelocity ctrl,vx,vy / b2kSpin ctrl,deg/s / b2kSpinBy ctrl,deg/s /
--         b2kTorque ctrl,t / b2kAngularImpulse ctrl,imp / b2kMoveTo ctrl,x,y[,deg] /
--         b2kExplode x,y[,radius][,power] / b2kRemove ctrl
-- GET     b2kBodyOf(ctrl) / b2kPosition(ctrl) / b2kWorldCenter(ctrl) / b2kVelocity(ctrl) /
--         b2kSpeed(ctrl) / b2kAngle(ctrl) / b2kMass(ctrl) / b2kBodyType(ctrl) /
--         b2kGravityScale(ctrl) / b2kDamping(ctrl) / b2kIsAwake(ctrl) / b2kControlAt(x,y) /
--         b2kControlContains(ctrl,x,y) / b2kBodyCount() / b2kAwakeCount() /
--         b2kToWorldX/Y(px) / b2kToScreenX/Y(m) /
--         b2kRayHit(x1,y1,x2,y2) + b2kRayHitX/Y() / b2kRayHitNormalX/Y() / b2kRayDist()
-- JOINTS  b2kHinge ctrlA,ctrlB,x,y / b2kWeld ctrlA,ctrlB / b2kRope ctrlA,ctrlB[,len]
--         b2kSlider ctrlA,ctrlB,axisDeg / b2kWheel chassis,wheel,x,y[,axisDeg]
--         b2kMotor j,degPerSec[,maxTorque] / b2kSliderMotor j,pxPerSec[,maxForce] /
--         b2kWheelMotor j,degPerSec[,maxTorque] / b2kRemoveJoint j
-- JOINT+  b2kHingeLimit j,loDeg,hiDeg / b2kHingeAngle(j) / b2kSliderLimit j,loPx,hiPx /
--         b2kSliderPos(j) / b2kRopeRange j,minPx,maxPx / b2kRopeLength(j) /
--         b2kSpring j,hz[,damp] / b2kWeldSpring j,hz[,damp] / b2kWheelSpring j,hz[,damp]
-- DRAG    b2kGrab(x,y) -> control / b2kRelease
-- INPUT   b2kInputOn/Off / b2kKeyIsDown(k) / b2kKeyPressed/Released(k) /
--         b2kInputInject keys / b2kInputInjectOff (scripted keys: tests/replays) /
--         b2kKeysHeld() / b2kBindAction name,keys / b2kActionIsDown/Pressed/
--         Released(name) / b2kBindAxis name,negKeys,posKeys / b2kAxis(name) /
--         b2kFrameMS()   (poll-based: arm b2kInputOn, read from on b2kFrame)
-- SPRITE  b2kSheetLoad name,path,fw,fh[,n,margin,gap] / b2kSheetLoadAtlas name,png[,xml] /
--         b2kSheetFromImage name,img,fw,fh[,n,margin,gap] / b2kSheetFrames(name) /
--         b2kSheetAddFrame sheet,frame,x,y,w,h (no-XML packed sheets; fw/fh 0 = no grid) /
--         b2kSheetFrameNames(name) / b2kSheetHasFrame(name,frame) /
--         b2kSheetScale name,factor / b2kSheetFrameSize(name,frame) /
--         b2kAnimDef sheet,anim,frames,fps[,loop] / b2kSpriteNew sheet[,frame,x,y] /
--         b2kSpriteFromGIF path[,x,y] / b2kSpritePlay spr,anim[,restart] /
--         b2kSpriteStop spr / b2kSpriteSetFrame spr,f / b2kSpriteFlipH spr,flag /
--         b2kSpriteFPS spr,fps / b2kSpriteOnFinish spr,msg /
--         b2kSpriteBind spr,bodyCtrl[,dx,dy] / b2kSpriteRemove spr
-- PLAYER  b2kPlayerMake x,y,w,h[,sheet] / b2kPlayerAttach ctrl /
--         b2kPlayerAnims idle,run,jump,fall[,land,duck,climb,hurt,swim] /
--         b2kPlayerSet key,value / b2kPlayerGet(key) / b2kPlayerOnGround() /
--         b2kPlayerState() (idle|run|jump|fall|land|duck|climb|hurt|swim) /
--         b2kPlayerFacing() / b2kPlayerJump [speed] / b2kPlayerControl flag /
--         b2kPlayerAddLadder x1,y1,x2,y2 / b2kPlayerAddWater x1,y1,x2,y2 /
--         b2kPlayerHurt [fromX] /
--         b2kPlayerHurtIs() (true through knockback + mercy window) /
--         b2kPlayer() / b2kPlayerSprite() / b2kPlayerRemove
--         (drives axes "moveX"/"moveY" + action "jump"; rebind to remap.
--         DOWN ducks / DOWN+JUMP on a one-way chain drops through /
--         UP/DOWN in a ladder zone climbs / JUMP exits a climb /
--         in a water zone UP/DOWN swim, JUMP strokes (repeatable))
-- CAMERA  b2kCamOn [rect] / b2kCamOff / b2kCamFollow ctrl[,lerp] / b2kCamUnfollow /
--         b2kCamDeadzone w,h / b2kCamBounds x1,y1,x2,y2 / b2kCamGoto x,y /
--         b2kCamPos() / b2kCamShake amp,ms / b2kCamMouseX/Y() / b2kCamGroup() /
--         b2kCamAdopt ctrl   (world px == control locs; spawns auto-join the view)
-- AUDIO   b2kSoundLoad name,path / b2kToneMake name,freqs,msPerNote[,vol,shape] /
--         b2kSound name / b2kSoundLoop name / b2kSoundStop / b2kSoundMute flag /
--         b2kSoundMuted() / b2kSoundVolume pct / b2kSoundIsLoaded(name) /
--         b2kSoundStatus()  (audioClips: one at a time; b2kToneMake = no asset files)
-- EVENTS  on b2kContact pCtrlA,pCtrlB / on b2kEndContact pCtrlA,pCtrlB
--         (long ids; empty for walls/ground) / on b2kFrame  (once per frame)
--         poll instead: b2kContactCount()+b2kContactA/B(i) / b2kEndContactCount()+...
-- SENSOR  b2kAddSensor ctrl[,shape] / on b2kSensorEnter pSensor,pVisitor /
--         on b2kSensorExit pSensor,pVisitor / b2kSensorCount()+EnterSensor/Visitor(i)
-- FILTER  b2kDefineLayer name / b2kSetCategory ctrl,layers / b2kSetMask ctrl,layers /
--         b2kSetCollisionGroup ctrl,n / b2kNoCollide ctrlA,ctrlB
-- TERRAIN b2kChain pointList[,loop] / b2kSmoothGround pointList  (>=4 screen
--         points; chains carry the reserved "oneway" layer, bit 2^31)
-- QUERY+  b2kOverlap x1,y1,x2,y2 / b2kOverlapMoving x1,y1,x2,y2 (presence:
--         statics filtered out) / b2kOverlapCircle x,y,r / b2kRayHitAll x1,y1,x2,y2
-- MOTOR   b2kMotorTo mover,ref,dxPx,dyPx,deg[,maxF,maxT] / b2kExplode (native blast)
-- TUNE    b2kSetRestitutionThreshold px/s / b2kSetContactTuning hz,damp,pushPx /
--         b2kSetJointTuning hz,damp / b2kSetMaxSpeed px/s / b2kEnableWarmStarting f /
--         b2kProfile() / b2kAwakeBodyCount()
--
-- Tips: pass controls by reference (the long id of ... is safest). Keep moving
-- objects a sensible on-screen size (default scale 40 px/m, so ~4-400 px).
-- Graphic boxes/polygons and dynamic images rotate; buttons/fields/etc follow
-- position upright (their rotation is locked so the sim matches the render).
-- =====================================================================

local sWorld, sRunning, sPaused, sGen
local sScale, sOriginX, sOriginY
local sAccum, sLast, sSub
local sBody          -- ctrlRef     -> body handle
local sCtrl          -- body handle -> ctrlRef
local sShapeH        -- ctrlRef     -> shape handle (for material edits)
local sRender        -- ctrlRef     -> "poly" | "ball" | "image" | "loc"
local sVerts         -- ctrlRef     -> local polygon verts (metres) for "poly"
local sRad           -- ctrlRef     -> radius (metres) for "ball"
local sImgAngle      -- ctrlRef     -> last applied angle (deg) for "image"
local sStatic        -- ctrlRef     -> true for bodies that never move
local sSpawned       -- ctrlRef     -> true if the kit created the control
local sSensor        -- ctrlRef     -> true for sensor (non-solid trigger) bodies
local sLayers        -- collision-layer name -> bit value
local sNextBit       -- next free collision-layer bit
local sDragJoint, sDragAnchor, sDragging
local sContactObj    -- object that receives b2kContact messages
local sFrameObj      -- object that receives an on b2kFrame message each frame
local sRayX, sRayY   -- last b2kRayHit point (screen pixels)
local sRayNX, sRayNY -- last b2kRayHit surface normal (screen-oriented)
local sRayDist       -- last b2kRayHit distance from the ray start (pixels)
local sRayBodyH      -- last b2kRayHit BODY HANDLE (already fetched for the
                     -- control lookup; stashed so the player's ground probe
                     -- can classify the hit with zero extra FFI calls)
local sOneWayBody    -- body handle -> true for one-way chain bodies (b2kChain)
local sNeedFullSync  -- true when a script-side transform/type edit bypassed move events
local sEvtCN, sEvtCA, sEvtCB -- begin-contacts buffered THIS FRAME (body handles)
local sEvtEN, sEvtEA, sEvtEB -- end-contacts buffered this frame
local sEvtSN, sEvtSS, sEvtSV -- sensor enters this frame (sensor, visitor)
local sEvtXN, sEvtXS, sEvtXV -- sensor exits this frame
local sKillY         -- kill floor: screen y below which dynamic bodies are removed
local sDrawKey       -- ctrlRef -> last rendered pixel/angle key; avoids redundant redraws
local sInputOn       -- true while the per-frame keyboard sample is armed
local sInjectOn      -- true = the sample comes from sInjectKeys, not the keyboard
local sInjectKeys    -- injected keycode list (tests, replays, cutscene ghosts)
local sKeysNow       -- comma-wrapped keycode set held this frame (",65361,32,")
local sKeysPrev      -- last frame's set; pressed/released edges are the diff
local sKeyActions    -- action name -> bound key list ("jump" -> "space,up,w")
local sAxisNeg       -- axis name -> negative-direction key list
local sAxisPos       -- axis name -> positive-direction key list
local sKeyActionsC   -- action name -> RESOLVED keycode list (bind-time cache)
local sAxisNegC      -- axis name -> resolved negative keycodes
local sAxisPosC      -- axis name -> resolved positive keycodes
local sFrameMS       -- real elapsed ms folded into the last frame (b2kFrameMS)
local sSheetSrc      -- sheet -> long id of its hidden source image
local sSheetOwned    -- sheet -> true when the Kit created the source image
local sSheetRegion   -- sheet -> frame key -> "x,y,w,h" region (source px)
local sSheetKeys     -- sheet -> CR list of frame keys, definition order
local sSheetIcon     -- sheet -> frame key -> sliced frame image id (lazy)
local sSheetFlip     -- sheet -> frame key -> mirrored image id (lazy)
local sSheetData     -- sheet -> cached source imageData (freed on teardown)
local sSheetAlpha    -- sheet -> cached source alphaData
local sSheetScale    -- sheet -> display scale factor (default 1; engine-resampled at slice time)
local sSheetPath     -- sheet -> its source path/ref (the idempotent-reload + reuse key)
local sSheetKeep     -- true = sheets survive b2kTeardown (b2kSheetPersist); assets, like sounds
local sAnimList      -- "sheet|anim" -> CR list of frame keys
local sAnimFPS       -- "sheet|anim" -> frames per second
local sAnimLoop      -- "sheet|anim" -> true/false
local sSprRefs       -- CR list of every live sprite control
local sSprLive       -- ...the subset the tick must service (bound/playing)
local sSprLiveDirty  -- true -> rebuild sSprLive from sSprRefs next tick
local sSprSheet, sSprKind, sSprAnim, sSprStep, sSprNextMS
local sSprFPS, sSprFPSOver, sSprFlip, sSprMsg, sSprFrameKey, sSprIconNow
local sSprBind, sSprBindDX, sSprBindDY, sSprLastLoc
local sCamGroup      -- viewport group long id while the camera is on
local sCamFollow     -- control the camera tracks (empty = manual)
local sCamLerp       -- follow smoothing 0..1 (1 = snap)
local sCamDZW, sCamDZH -- deadzone box in px (0 = always centre)
local sCamB1X, sCamB1Y, sCamB2X, sCamB2Y -- world bounds (sCamB1X empty = none)
local sCamX, sCamY   -- current view centre (world px)
local sCamShakeAmp, sCamShakeEnd
local sCamLastH, sCamLastV -- last written scroll (skip redundant sets)
local sCamNote       -- empty = healthy; else why the camera is degraded
local sCamLocVisual  -- true when this engine reports grouped locs SCROLL-ADJUSTED
local sCamCurH, sCamCurV -- the scroll actually applied this frame (cached)
local sInCam         -- ctrlRef -> true when the Kit placed it inside the viewport
local sPlayRef       -- the player's control (empty = no player controller)
local sPlayArt       -- the sprite whose anims the controller drives
local sPlayTune      -- tuning key -> value (b2kPlayerSet; defaults fill gaps)
local sPlayAnims     -- state -> animation name (idle/run/jump/fall/land/duck/climb/hurt)
local sPlayState     -- idle | run | jump | fall | land | duck | climb | hurt
                     -- (land lasts one tick; a drop-through renders as fall)
local sPlayFacing    -- 1 right / -1 left (last horizontal intent)
local sPlayGrounded  -- this frame's ray-probe verdict
local sPlayGroundMS  -- when last grounded (the coyote window)
local sPlayPressMS   -- when jump was last pressed (the buffer window)
local sPlayJumping   -- a controller jump is still ascending (cut-eligible)
local sPlayControl   -- false = observe only: no velocity or anim writes
local sPlayOwnBody   -- true when the controller created the body
local sPlayHalfW, sPlayHalfH -- capsule half-extents in px (probe geometry)
local sPlayAnimNow   -- last animation written (redundancy suppression)
local sPlayFlipNow   -- last flip written
local sPlayHoldMS    -- suppress anim switches until then (land flourish)
-- hot-path caches (b2kPlayerTuneCache): the tick runs every frame, so
-- the knobs resolve at SET time, not per use
local sPlayMoveSpd, sPlayAccelG, sPlayAccelA, sPlayJumpSpd, sPlayJumpCut
local sPlayCoyote, sPlayBuffer, sPlayMaxFall, sPlayCosSlope
local sPlayDropMS, sPlayClimbSpd                       -- Wave 2 caches...
local sPlayHurtPopX, sPlayHurtPopY, sPlayHurtMS, sPlayInvulnMS
local sPlayProbeOffs -- the 3 probe x-offsets, precomputed at attach
local sPlayReach     -- probe ray length (halfH + 4), precomputed
local sPlayAir       -- consecutive airborne ticks (landing hysteresis)
local sPlayNormX     -- surface normal X at the grounded probe hit (slope test)
local sPlayPX, sPlayPY -- the probe's screen-px body centre, stashed for the
                     -- ladder zone test and b2kPlayerHurt (no second FFI read)
local sPlayOnOneWay  -- this frame's ground is a one-way chain (drop eligible)
local sPlayDropUntil -- sim-clock end of the drop-through window (0 = inactive)
local sPlayDropHard  -- hard restore deadline (4x dropMs): a drop that lands on
                     -- a parked solid under the chain must not stay intangible
local sPlayDropLineY -- surface y the drop started through; the mask is only
                     -- restored once the capsule's TOP clears it (a straddling
                     -- restore would snap the player back on top: chain contacts
                     -- are one-sided, judged by the centroid)
local sPlayDropSeen  -- the probe skipped a one-way hit this frame (still inside)
local sPlayDropMask  -- the player's mask to restore when the window closes
local sPlayClimb     -- true while in the climb state (gravity scale parked at 0)
local sPlayGravSave  -- the body's gravity scale to restore on climb exit
local sPlayLadN      -- registered ladder zones (flat numeric arrays: the
local sPlayLadL, sPlayLadT, sPlayLadR, sPlayLadB -- ...in-zone test is pure compares)
-- Wave 4: water zones + the swim state (a buoyant parallel to the climb)
local sPlaySwim      -- true while submerged in a water zone (gravity scaled down)
local sPlaySwimGravSave -- the body's gravity scale to restore on swim exit
local sPlaySwimSpd, sPlaySwimJump, sPlaySwimGrav, sPlaySwimMaxFall -- swim tune caches
local sPlayWatN      -- registered water zones (flat numeric arrays, like ladders)
local sPlayWatL, sPlayWatT, sPlayWatR, sPlayWatB
local sPlayHurt      -- true while knockback owns the controller
local sPlayHurtEnd   -- sim-clock when hurtMs has elapsed
local sPlayHurtHalf  -- sim-clock when half of hurtMs has elapsed (landings
                     -- only count from here; restore = LATER of the two)
local sPlayHurtLand  -- sim-clock of the first landing after the half mark (0 = none)
local sPlayInvulnUntil -- sim-clock end of the post-hurt mercy window
local sPlayClock     -- the player's SIM-TIME clock: summed frame ms.
                     -- Wall-clock would shrink the coyote/buffer windows
                     -- on slow machines (90ms = fewer frames); sim time
                     -- keeps them frame-coherent everywhere and makes
                     -- hand-stepped tests deterministic.
-- Wave 5 actions: double-jump, wall-slide/jump, dash, duck capsule reshape,
-- moving-platform carry. Each is OPT-IN through a knob whose default leaves
-- the pre-Wave-5 controller byte-for-byte unchanged, and each idle path
-- costs ONE compare per frame (the wall side-probe casts only while the
-- system is on AND airborne; carry reads a velocity only while grounded).
local sPlayAirJumps     -- extra mid-air jumps allowed (airJumps knob; 0 = none)
local sPlayAirJumpsLeft -- air jumps remaining (reset to sPlayAirJumps on ground)
local sPlayWallOn       -- the wall system is armed (wallJumpX or wallSlideMax > 0)
local sPlayWallJumpX, sPlayWallJumpY, sPlayWallSlideMax -- wall tune caches
local sPlayWall         -- airborne wall touch: -1 wall on left, 1 on right, 0 none
local sPlayWallSliding  -- true while actively wall-sliding (drives state + anim)
local sPlayWallLockUntil -- sim-clock through which a wall-jump owns vx (no air steer)
local sPlayDashSpd, sPlayDashMS, sPlayDashCool -- dash tune caches
local sPlayAirDash      -- true = dash allowed in mid-air (airDash knob; false = grounded only)
local sPlayDash         -- true while a dash is in flight (gravity parked at 0)
local sPlayDashEnd      -- sim-clock the dash ends
local sPlayDashReady    -- sim-clock the next dash may start (the cooldown gate)
local sPlayDashDir      -- dash direction (the facing captured at dash start)
local sPlayDashGravSave -- the body's gravity scale to restore when the dash ends
local sPlayDuckScale    -- ducked capsule height as a fraction of standing (1 = no reshape)
local sPlayDucked       -- true while the capsule is shrunk for a crawl
local sPlayStandH       -- the full standing capsule height in px (for the duck reshape)
local sPlayCarry        -- true = inherit a moving platform's velocity (platformCarry knob)
local sPlayGroundBody   -- the body handle under the grounding ray (carry reads its velocity)
local sPlayInLad, sPlayInWat -- this frame's ladder/water zone membership (exposed by getters)
local sSndClip       -- sound name -> audioClip short name ("b2ksnd_...")
local sSndMute       -- true = swallow play calls (a user preference; survives teardown)
local sSndDead       -- true after a play failure: degrade to silence, never errors
local sSndNote       -- empty = healthy; else why audio is degraded

constant kPI = 3.14159265358979

-- =====================================================================
-- World / lifecycle
-- =====================================================================
command b2kSetup pGravityX, pGravityY
   b2kEnsureNativeLib
   b2kTeardown
   if pGravityX is empty then put 0 into pGravityX
   if pGravityY is empty then put -10 into pGravityY
   put b2NewWorld(pGravityX, pGravityY, true, true) into sWorld
   put b2NewStaticBody(sWorld, 0, 0) into sDragAnchor
   put 40 into sScale
   put (the width of this card) div 2 into sOriginX
   put (the height of this card) - 40 into sOriginY
   put 4 into sSub
   b2kResetTables
   put empty into sLayers
   put 1 into sNextBit
   put 0 into sDragJoint
   put false into sDragging
   put false into sRunning
   put false into sPaused
   put false into sNeedFullSync
   put empty into sKillY
   b2kEventsReset
end b2kSetup

-- Point the engine at the native library so the c:box2dxt> foreign bindings
-- resolve on EVERY platform and IDE -- including OXT Lite, whose stripped IDE
-- does not auto-scan an extension's code/ folder. the revLibraryMapping is the
-- exact name->path table the engine consults when loading a foreign-handler
-- library (engine resolver MCEngineLoadLibrary); seeding it ourselves means no
-- /usr/lib, no LD_LIBRARY_PATH, no sudo, no code/ packaging, on Linux/macOS/
-- Windows alike. The library ships next to the stack under its bare name
-- (box2dxt.{so,dll,dylib}); if it is there we map it, otherwise we leave the
-- engine's own search untouched (so the historical "beside the engine" path on
-- Win/macOS still works). Raw b2* callers that do not use the Kit can set the
-- same mapping themselves before their first b2 call.
command b2kEnsureNativeLib
   local tStackFile, tDir, tName, tPath, tOldDelim
   put the effective filename of this stack into tStackFile
   if tStackFile is empty then exit b2kEnsureNativeLib
   switch the platform
      case "Win32"
         put "box2dxt.dll" into tName
         break
      case "MacOS"
         put "box2dxt.dylib" into tName
         break
      default
         put "box2dxt.so" into tName   -- Linux and friends
         break
   end switch
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to slash
   put item 1 to -2 of tStackFile into tDir
   set the itemDelimiter to tOldDelim
   put tDir & slash & tName into tPath
   if there is a file tPath then
      set the revLibraryMapping["box2dxt"] to tPath
   end if
end b2kEnsureNativeLib

command b2kResetTables
   put empty into sBody
   put empty into sCtrl
   put empty into sShapeH
   put empty into sRender
   put empty into sVerts
   put empty into sRad
   put empty into sImgAngle
   put empty into sDrawKey
   put empty into sStatic
   put false into sNeedFullSync
   put empty into sSpawned
   put empty into sSensor
   put empty into sInCam
   put empty into sOneWayBody
end b2kResetTables

command b2kTeardown
   put false into sRunning
   put the milliseconds & random(9999) into sGen
   if sWorld is not empty then b2DestroyWorld sWorld
   put empty into sWorld
   b2kPlayerForget true   -- full: a teardown wipes the tuning too
   if sSheetKeep is true then
      -- sheets are ASSETS that SURVIVE teardown (b2kSheetPersist), exactly
      -- like sounds: clear only the sprite INSTANCES + dead viewports and
      -- keep the sheet cache, so a level rebuild reuses it instead of
      -- re-decoding/re-parsing/re-slicing (the costliest thing the Kit does).
      b2kSpritesClear
      b2kSpriteSweepOrphans true
      put empty into sSheetData    -- the imageData cache re-derives lazily;
      put empty into sSheetAlpha   -- free it like the full wipe would
   else
      b2kSheetsWipe   -- sprites first: their stored long ids include the group
   end if
   -- sounds deliberately SURVIVE teardown: clips are tiny (KBs) and
   -- deterministic, and re-synthesis cost a fifth of a second on every
   -- reset. b2kSoundsWipe purges them when you really want them gone.
   b2kCamOff       -- ...then dissolve the viewport (survivors go to the card)
   b2kResetTables
   put 0 into sDragJoint
   put false into sDragging
end b2kTeardown

-- One-liner: world with gravity, walls around the card, loop running.
command b2kQuickStart pGravityY
   b2kSetup 0, pGravityY
   b2kAddWalls
   b2kStart
end b2kQuickStart

command b2kStart
   if sWorld is empty then b2kSetup
   put true into sRunning
   put false into sPaused
   put 0 into sAccum
   put the milliseconds into sLast
   put the milliseconds & "_" & random(1000000) into sGen
   send ("b2kStep " & sGen) to me in 16 milliseconds
end b2kStart

command b2kStop
   put false into sRunning
   put the milliseconds & random(9999) into sGen
end b2kStop

command b2kPause
   put true into sPaused
end b2kPause

command b2kResume
   put false into sPaused
   put the milliseconds into sLast
end b2kResume

function b2kIsRunning
   return (sRunning is true) and (sPaused is not true)
end b2kIsRunning

-- Static, invisible walls along the four card edges.
command b2kAddWalls
   local tL, tR, tT, tB
   put b2kToWorldX(0) into tL
   put b2kToWorldX(the width of this card) into tR
   put b2kToWorldY(0) into tT
   put b2kToWorldY(the height of this card) into tB
   b2kEdge tL, tB, tR, tB
   b2kEdge tL, tT, tR, tT
   b2kEdge tL, tB, tL, tT
   b2kEdge tR, tB, tR, tT
end b2kAddWalls

command b2kEdge pWx1, pWy1, pWx2, pWy2
   local tBody
   if sWorld is empty then exit b2kEdge   -- no world yet: a wall is a quiet no-op
   put b2NewStaticBody(sWorld, 0, 0) into tBody
   get b2AddSegment(tBody, pWx1, pWy1, pWx2, pWy2, 0.6, 0.1)
end b2kEdge

-- A wide invisible ground line at screen height pScreenY (default: near bottom).
command b2kAddGround pScreenY
   local tBody, tWy
   if sWorld is empty then exit b2kAddGround
   if pScreenY is empty then put (the height of this card) - 40 into pScreenY
   put b2kToWorldY(pScreenY) into tWy
   put b2NewStaticBody(sWorld, 0, tWy) into tBody
   get b2AddSegment(tBody, -500, 0, 500, 0, 0.7, 0.1)
end b2kAddGround

-- A static collision segment between two SCREEN points - custom walls, ramps,
-- ledges and floors. Like the card-edge walls it is invisible (draw your own
-- graphic to match) and lives for the world's lifetime; it isn't tracked as a
-- body, so b2kClear leaves it in place.
-- Destroy any moving Kit body whose centre falls below this SCREEN y
-- (empty = off). Crates shoved into pits, enemies knocked off the level:
-- gone instead of falling forever. The PLAYER's body is exempt (the game
-- owns its respawn). Each removal first sends "b2kFell <ctrl>" to the
-- frame target so the game can clean up companions (bound sprites, table
-- slots) -- do not delete the control inside that handler; the Kit is
-- mid-removal (Kit-spawned controls are deleted for you).
command b2kKillFloor pScreenY
   put pScreenY into sKillY
end b2kKillFloor

command b2kWall pX1, pY1, pX2, pY2
   b2kEdge b2kToWorldX(pX1), b2kToWorldY(pY1), b2kToWorldX(pX2), b2kToWorldY(pY2)
end b2kWall

-- Remove every dynamic body (b2kRemove deletes kit-spawned controls; attached
-- controls are just detached). Sprites are Kit-created controls, so they go
-- too; loaded sheets stay (they are assets, not world state).
command b2kClear
   local tRef, tList, d
   b2kSpritesClear
   b2kPlayerForget false   -- the player is world state; its tuning is config
   put empty into tList
   repeat for each key tRef in sBody
      if sStatic[tRef] is not true then put tRef & cr after tList
   end repeat
   repeat for each line d in tList
      if d is not empty then b2kRemove d
   end repeat
end b2kClear

-- =====================================================================
-- Configuration
-- =====================================================================
function b2kNumberOr pValue, pDefault
   if pValue is empty then return pDefault
   if pValue is not a number then return pDefault
   return pValue
end b2kNumberOr

function b2kClamp pValue, pLo, pHi
   local tValue
   put b2kNumberOr(pValue, pLo) into tValue
   if tValue < pLo then put pLo into tValue
   if tValue > pHi then put pHi into tValue
   return tValue
end b2kClamp

command b2kSetScale pPixelsPerMetre
   put b2kClamp(pPixelsPerMetre, 1, 10000) into sScale
end b2kSetScale

command b2kSetOrigin pScreenX, pScreenY
   put b2kNumberOr(pScreenX, sOriginX) into sOriginX
   put b2kNumberOr(pScreenY, sOriginY) into sOriginY
end b2kSetOrigin

command b2kSetGravity pGx, pGy
   put b2kNumberOr(pGx, 0) into pGx
   put b2kNumberOr(pGy, -10) into pGy
   if sWorld is not empty then b2SetGravity sWorld, pGx, pGy
end b2kSetGravity

command b2kSetSubsteps pN
   put round(b2kClamp(pN, 1, 64)) into sSub
end b2kSetSubsteps

-- World toggles: island sleeping (saves CPU) and continuous collision (CCD,
-- stops fast bodies tunnelling through thin walls).
command b2kEnableSleeping pFlag
   if sWorld is not empty then b2EnableSleeping sWorld, (pFlag is true)
end b2kEnableSleeping

command b2kEnableContinuous pFlag
   if sWorld is not empty then b2EnableContinuous sWorld, (pFlag is true)
end b2kEnableContinuous

command b2kContactTarget pObject
   put pObject into sContactObj
end b2kContactTarget

-- Object that receives an `on b2kFrame` message once per simulated frame (after
-- bodies are synced). Use it for per-frame logic: motors, custom drawing, input.
command b2kFrameTarget pObject
   put pObject into sFrameObj
end b2kFrameTarget

function b2kWorld
   return sWorld
end b2kWorld

-- Sanity check from kit-only code: returns the native shim's ABI version (4),
-- i.e. that the box2dxt extension and its native library are loaded and in sync.
function b2kVersion
   return b2Version()
end b2kVersion

-- =====================================================================
-- Coordinate conversion (sim Y up; screen Y down)
-- =====================================================================
function b2kToScreenX pWx
   return sOriginX + pWx * sScale
end b2kToScreenX

function b2kToScreenY pWy
   return sOriginY - pWy * sScale
end b2kToScreenY

function b2kToWorldX pSx
   if sScale is empty or sScale = 0 then return 0   -- before b2kSetup: stay safe
   return (pSx - sOriginX) / sScale
end b2kToWorldX

function b2kToWorldY pSy
   if sScale is empty or sScale = 0 then return 0
   return (sOriginY - pSy) / sScale
end b2kToWorldY

-- =====================================================================
-- Attaching existing controls (pDynamic defaults to true)
-- =====================================================================
command b2kAddBox pControl, pDynamic
   local tRef, tType, tFixed, tBody, tHw, tHh, tWx, tWy, tGraphic, tImage
   if sWorld is empty then return 0   -- attach needs a world (b2kSetup first)
   put the long id of pControl into tRef
   put (pDynamic is not false) into pDynamic
   if pDynamic then put 2 into tType
   else put 0 into tType
   put ((the width of pControl) / 2) / sScale into tHw
   put ((the height of pControl) / 2) / sScale into tHh
   if tHw <= 0 or tHh <= 0 then return 0
   put b2kToWorldX(item 1 of the loc of pControl) into tWx
   put b2kToWorldY(item 2 of the loc of pControl) into tWy
   put (word 1 of tRef is "graphic") into tGraphic
   put (word 1 of tRef is "image") into tImage
   -- Graphics rotate as polygons; dynamic images rotate via `the angle`. Other
   -- control types (button, field, ...) can't be shown rotated, so we lock
   -- their rotation to keep the simulation consistent with the upright render.
   if tGraphic or (tImage and pDynamic) then put false into tFixed
   else put true into tFixed
   put b2NewBody(sWorld, tType, tWx, tWy, 0, false, tFixed) into tBody
   b2ShapeDefEnableSensorEvents true   -- so sensors can detect this shape
   put b2AddBox(tBody, tHw, tHh, 1.0, 0.4, 0.2) into sShapeH[tRef]
   b2kRegister tRef, tBody, (not pDynamic)
   if tGraphic and pDynamic then
      set the style of pControl to "polygon"
      put "poly" into sRender[tRef]
      put ("-" & tHw) & "," & ("-" & tHh) & cr & tHw & "," & ("-" & tHh) & cr \
            & tHw & "," & tHh & cr & ("-" & tHw) & "," & tHh into sVerts[tRef]
   else if tImage and pDynamic then
      put "image" into sRender[tRef]
   else
      put "loc" into sRender[tRef]
   end if
   -- Draw the new body NOW. The style switch above left a "poly" graphic with
   -- no points (invisible), and the move-event sync can't help: a world that
   -- isn't stepping emits no move events, so a part spawned while the loop is
   -- stopped would stay invisible until the first Run. Attach = visible.
   b2kDrawBody tRef, tWx, tWy, 0
   return tBody
end b2kAddBox

command b2kAddBall pControl, pDynamic
   local tRef, tType, tBody, tRad, tWx, tWy
   if sWorld is empty then return 0
   put the long id of pControl into tRef
   put (pDynamic is not false) into pDynamic
   if pDynamic then put 2 into tType
   else put 0 into tType
   put ((the width of pControl) / 2) / sScale into tRad
   if tRad <= 0 then return 0
   put b2kToWorldX(item 1 of the loc of pControl) into tWx
   put b2kToWorldY(item 2 of the loc of pControl) into tWy
   put b2NewBody(sWorld, tType, tWx, tWy, 0, false, false) into tBody
   b2ShapeDefEnableSensorEvents true   -- so sensors can detect this shape
   put b2AddCircle(tBody, 0, 0, tRad, 1.0, 0.4, 0.4) into sShapeH[tRef]
   b2kRegister tRef, tBody, (not pDynamic)
   if word 1 of tRef is "graphic" then put "ball" into sRender[tRef]
   else if word 1 of tRef is "image" then put "image" into sRender[tRef]
   else put "loc" into sRender[tRef]
   put tRad into sRad[tRef]
   b2kDrawBody tRef, tWx, tWy, 0   -- visible at attach, even with the loop stopped
   return tBody
end b2kAddBall

-- Capsule ("pill"): the long side of the control's rect is the capsule axis,
-- the short side its diameter. Graphics render as a rounded outline (and rotate);
-- images rotate via `the angle`; other controls follow position upright.
command b2kAddCapsule pControl, pDynamic
   local tRef, tType, tFixed, tBody, tWx, tWy, tWm, tHm, tR, tL, tHoriz, tGraphic, tImage
   if sWorld is empty then return 0
   put the long id of pControl into tRef
   put (pDynamic is not false) into pDynamic
   if pDynamic then put 2 into tType
   else put 0 into tType
   put (the width of pControl) / sScale into tWm
   put (the height of pControl) / sScale into tHm
   if tWm <= 0 or tHm <= 0 then return 0
   put (tWm >= tHm) into tHoriz
   if tHoriz then
      put tHm / 2 into tR
      put max(0, tWm / 2 - tR) into tL
   else
      put tWm / 2 into tR
      put max(0, tHm / 2 - tR) into tL
   end if
   put b2kToWorldX(item 1 of the loc of pControl) into tWx
   put b2kToWorldY(item 2 of the loc of pControl) into tWy
   put (word 1 of tRef is "graphic") into tGraphic
   put (word 1 of tRef is "image") into tImage
   if tGraphic or (tImage and pDynamic) then put false into tFixed
   else put true into tFixed
   put b2NewBody(sWorld, tType, tWx, tWy, 0, false, tFixed) into tBody
   b2ShapeDefEnableSensorEvents true   -- so sensors can detect this shape
   if tHoriz then
      put b2AddCapsule(tBody, - tL, 0, tL, 0, tR, 1.0, 0.4, 0.2) into sShapeH[tRef]
   else
      put b2AddCapsule(tBody, 0, - tL, 0, tL, tR, 1.0, 0.4, 0.2) into sShapeH[tRef]
   end if
   b2kRegister tRef, tBody, (not pDynamic)
   if tGraphic and pDynamic then
      set the style of pControl to "polygon"
      put "poly" into sRender[tRef]
      put b2kCapsuleVerts(tL, tR, tHoriz) into sVerts[tRef]
   else if tImage and pDynamic then
      put "image" into sRender[tRef]
   else
      put "loc" into sRender[tRef]
   end if
   -- Same as b2kAddBox: the freshly point-less "poly" graphic must be drawn
   -- here, because a stopped world never emits the move event that would.
   b2kDrawBody tRef, tWx, tWy, 0
   return tBody
end b2kAddCapsule

-- Build a body from a polygon graphic's own points (<= 8 vertices, convex).
command b2kAddPolygon pControl, pDynamic
   local tRef, tType, tBody, tCx, tCy, tWx, tWy, tPoints, p, tLocal, lx, ly, tCount
   if sWorld is empty then return 0
   put the long id of pControl into tRef
   put (pDynamic is not false) into pDynamic
   if pDynamic then put 2 into tType
   else put 0 into tType
   put item 1 of the loc of pControl into tCx
   put item 2 of the loc of pControl into tCy
   put b2kToWorldX(tCx) into tWx
   put b2kToWorldY(tCy) into tWy
   put b2NewBody(sWorld, tType, tWx, tWy, 0, false, false) into tBody
   b2PolyBegin
   put empty into tLocal
   put 0 into tCount
   repeat for each line p in the points of pControl
      if p is empty then next repeat
      if tCount >= 8 then next repeat
      put (item 1 of p - tCx) / sScale into lx
      put - ((item 2 of p - tCy) / sScale) into ly
      b2PolyAddPoint lx, ly
      put lx & "," & ly & cr after tLocal
      add 1 to tCount
   end repeat
   if tCount < 3 then
      b2DestroyBody tBody
      return 0
   end if
   b2ShapeDefEnableSensorEvents true   -- so sensors can detect this shape
   put b2AddPolygon(tBody, 1.0, 0.4, 0.2) into sShapeH[tRef]
   b2kRegister tRef, tBody, (not pDynamic)
   put "poly" into sRender[tRef]
   put tLocal into sVerts[tRef]
   b2kDrawBody tRef, tWx, tWy, 0   -- visible at attach, even with the loop stopped
   return tBody
end b2kAddPolygon

command b2kAddStatic pControl
   b2kAddBox pControl, false
end b2kAddStatic

command b2kRegister pRef, pBody, pIsStatic
   put pBody into sBody[pRef]
   put pRef into sCtrl[pBody]
   put (pIsStatic is true) into sStatic[pRef]
end b2kRegister

-- =====================================================================
-- Spawning new controls (create + attach in one call). Returns control ref.
-- =====================================================================
command b2kSpawnBox pScreenX, pScreenY, pW, pH, pColor
   local tName, tRef
   if sWorld is empty then return empty   -- spawn needs a world (b2kSetup first)
   if pW is empty then put 40 into pW
   put b2kClamp(pW, 1, 10000) into pW
   if pH is empty then put pW into pH
   put b2kClamp(pH, 1, 10000) into pH
   put b2kNumberOr(pScreenX, sOriginX) into pScreenX
   put b2kNumberOr(pScreenY, sOriginY) into pScreenY
   put "b2kspawn_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create graphic (tName)
   else
      create graphic (tName) in group "b2kcam_view"
   end if
   put the long id of graphic (tName) into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   set the style of tRef to "rectangle"
   set the filled of tRef to true
   set the foregroundColor of tRef to "20,20,24"
   if pColor is not empty then
      try
         set the backgroundColor of tRef to pColor
      catch tErr
         -- an unknown colour name (CSS names like "teal" are not LC/X11
         -- names) must not abort the spawn and orphan the control
      end try
   end if
   set the width of tRef to pW
   set the height of tRef to pH
   set the loc of tRef to round(pScreenX - b2kCamShiftX(tRef)) & "," & round(pScreenY - b2kCamShiftY(tRef))
   b2kAddBox tRef
   put true into sSpawned[tRef]
   return tRef
end b2kSpawnBox

command b2kSpawnBall pScreenX, pScreenY, pDiameter, pColor
   local tName, tRef
   if sWorld is empty then return empty
   if pDiameter is empty then put 40 into pDiameter
   put b2kClamp(pDiameter, 1, 10000) into pDiameter
   put b2kNumberOr(pScreenX, sOriginX) into pScreenX
   put b2kNumberOr(pScreenY, sOriginY) into pScreenY
   put "b2kspawn_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create graphic (tName)
   else
      create graphic (tName) in group "b2kcam_view"
   end if
   put the long id of graphic (tName) into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   set the style of tRef to "oval"
   set the filled of tRef to true
   set the foregroundColor of tRef to "20,20,24"
   if pColor is not empty then
      try
         set the backgroundColor of tRef to pColor
      catch tErr
         -- an unknown colour name (CSS names like "teal" are not LC/X11
         -- names) must not abort the spawn and orphan the control
      end try
   end if
   set the width of tRef to pDiameter
   set the height of tRef to pDiameter
   set the loc of tRef to round(pScreenX - b2kCamShiftX(tRef)) & "," & round(pScreenY - b2kCamShiftY(tRef))
   b2kAddBall tRef
   put true into sSpawned[tRef]
   return tRef
end b2kSpawnBall

-- Create a pill-shaped graphic and attach a capsule body. pLength is along the
-- pill's long axis, pThickness across it; horizontal if pLength >= pThickness.
command b2kSpawnCapsule pScreenX, pScreenY, pLength, pThickness, pColor
   local tName, tRef
   if sWorld is empty then return empty
   if pLength is empty then put 80 into pLength
   if pThickness is empty then put 40 into pThickness
   put b2kClamp(pLength, 1, 10000) into pLength
   put b2kClamp(pThickness, 1, 10000) into pThickness
   put b2kNumberOr(pScreenX, sOriginX) into pScreenX
   put b2kNumberOr(pScreenY, sOriginY) into pScreenY
   put "b2kspawn_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create graphic (tName)
   else
      create graphic (tName) in group "b2kcam_view"
   end if
   put the long id of graphic (tName) into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   set the style of tRef to "polygon"
   set the filled of tRef to true
   set the foregroundColor of tRef to "20,20,24"
   if pColor is not empty then
      try
         set the backgroundColor of tRef to pColor
      catch tErr
         -- an unknown colour name (CSS names like "teal" are not LC/X11
         -- names) must not abort the spawn and orphan the control
      end try
   end if
   if pLength >= pThickness then
      set the width of tRef to pLength
      set the height of tRef to pThickness
   else
      set the width of tRef to pThickness
      set the height of tRef to pLength
   end if
   set the loc of tRef to round(pScreenX - b2kCamShiftX(tRef)) & "," & round(pScreenY - b2kCamShiftY(tRef))
   b2kAddCapsule tRef
   put true into sSpawned[tRef]
   return tRef
end b2kSpawnCapsule

-- =====================================================================
-- Materials & body properties
-- =====================================================================
command b2kSetBounce pControl, pRestitution
   local s
   put sShapeH[the long id of pControl] into s
   put b2kClamp(pRestitution, 0, 2) into pRestitution
   if s is not empty then b2SetShapeRestitution s, pRestitution
end b2kSetBounce

command b2kSetFriction pControl, pFriction
   local s
   put sShapeH[the long id of pControl] into s
   put b2kClamp(pFriction, 0, 10) into pFriction
   if s is not empty then b2SetShapeFriction s, pFriction
end b2kSetFriction

command b2kSetDensity pControl, pDensity
   local s
   put sShapeH[the long id of pControl] into s
   put b2kClamp(pDensity, 0, 10000) into pDensity
   if s is not empty then b2SetShapeDensity s, pDensity
end b2kSetDensity

-- Re-fit a body's collision shape to the control's CURRENT size, in place on the
-- SAME body so any joints stay valid. pShape is "box" | "ball" | "capsule" | "poly".
-- Resize the control's graphic first, then re-apply materials afterwards.
command b2kReshape pControl, pShape
   local tRef, tBody, tOld, tHw, tHh, tWm, tHm, tR, tL, tHoriz, tCx, tCy, p, lx, ly, tCount, tNewVerts
   local tWx, tWy, tWa
   put the long id of pControl into tRef
   if sBody[tRef] is empty then exit b2kReshape
   put sBody[tRef] into tBody
   -- Build the new shape first and drop the old one only afterwards, so the body
   -- is never momentarily shapeless and a rejected shape leaves the original
   -- intact (any joints on the body stay valid throughout).
   put sShapeH[tRef] into tOld
   put empty into sShapeH[tRef]
   b2ShapeDefEnableSensorEvents true   -- keep the reshaped body detectable by sensors
   if sSensor[tRef] is true then b2ShapeDefSensor true   -- a sensor stays a sensor after reshaping
   switch pShape
      case "ball"
         put ((the width of pControl) / 2) / sScale into tR
         if tR <= 0 then
            put tOld into sShapeH[tRef]
            b2ShapeDefReset   -- drop the pending one-shot flags set above
            exit b2kReshape
         end if
         put b2AddCircle(tBody, 0, 0, tR, 1.0, 0.4, 0.4) into sShapeH[tRef]
         put tR into sRad[tRef]
         break
      case "capsule"
         put (the width of pControl) / sScale into tWm
         put (the height of pControl) / sScale into tHm
         if tWm <= 0 or tHm <= 0 then
            put tOld into sShapeH[tRef]
            b2ShapeDefReset   -- drop the pending one-shot flags set above
            exit b2kReshape
         end if
         put (tWm >= tHm) into tHoriz
         if tHoriz then
            put tHm / 2 into tR
            put max(0, tWm / 2 - tR) into tL
            put b2AddCapsule(tBody, - tL, 0, tL, 0, tR, 1.0, 0.4, 0.2) into sShapeH[tRef]
         else
            put tWm / 2 into tR
            put max(0, tHm / 2 - tR) into tL
            put b2AddCapsule(tBody, 0, - tL, 0, tL, tR, 1.0, 0.4, 0.2) into sShapeH[tRef]
         end if
         put b2kCapsuleVerts(tL, tR, tHoriz) into sVerts[tRef]
         break
      case "poly"
         put item 1 of the loc of pControl into tCx
         put item 2 of the loc of pControl into tCy
         b2PolyBegin
         put empty into tNewVerts
         put 0 into tCount
         repeat for each line p in the points of pControl
            if p is empty then next repeat
            if tCount >= 8 then next repeat
            put (item 1 of p - tCx) / sScale into lx
            put - ((item 2 of p - tCy) / sScale) into ly
            b2PolyAddPoint lx, ly
            put lx & "," & ly & cr after tNewVerts
            add 1 to tCount
         end repeat
         if tCount < 3 then           -- degenerate outline: keep the existing shape
            put tOld into sShapeH[tRef]
            b2ShapeDefReset   -- drop the pending one-shot flags set above
            exit b2kReshape
         end if
         put b2AddPolygon(tBody, 1.0, 0.4, 0.2) into sShapeH[tRef]
         put tNewVerts into sVerts[tRef]
         break
      default
         put ((the width of pControl) / 2) / sScale into tHw
         put ((the height of pControl) / 2) / sScale into tHh
         if tHw <= 0 or tHh <= 0 then
            put tOld into sShapeH[tRef]
            b2ShapeDefReset   -- drop the pending one-shot flags set above
            exit b2kReshape
         end if
         put b2AddBox(tBody, tHw, tHh, 1.0, 0.4, 0.2) into sShapeH[tRef]
         if sRender[tRef] is "poly" then
            put ("-" & tHw) & "," & ("-" & tHh) & cr & tHw & "," & ("-" & tHh) & cr \
                  & tHw & "," & tHh & cr & ("-" & tHw) & "," & tHh into sVerts[tRef]
         end if
   end switch
   if tOld is not empty then b2DestroyShape tOld   -- now safe to release the old shape
   -- The size/outline changed but the body need not have moved, so the move-event
   -- sync would skip it (an at-rest body produces no move event). Bust the
   -- pose-keyed draw cache and redraw at the body's current pose right now so the
   -- new shape is visible immediately, awake or asleep.
   delete variable sDrawKey[tRef]
   put b2BodyX(tBody) into tWx
   put b2BodyY(tBody) into tWy
   if sRender[tRef] is "poly" or sRender[tRef] is "image" then put b2BodyAngle(tBody) into tWa
   else put 0 into tWa
   lock screen
   b2kDrawBody tRef, tWx, tWy, tWa
   unlock screen
end b2kReshape

-- Every body-targeting wrapper resolves the control's body first and quietly
-- no-ops when there is none (unregistered, removed, or pre-setup): the kit's
-- contract is that a missing body is never a script error.
command b2kSetBullet pControl, pFlag
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetBullet
   b2SetBullet b, (pFlag is true)
end b2kSetBullet

command b2kSetFixedRotation pControl, pFlag
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetFixedRotation
   b2SetFixedRotation b, (pFlag is true)
end b2kSetFixedRotation

command b2kSetGravityScale pControl, pScale
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetGravityScale
   b2SetGravityScale b, pScale
end b2kSetGravityScale

command b2kSetDamping pControl, pLinear, pAngular
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetDamping
   if pLinear is not empty then b2SetLinearDamping b, pLinear
   if pAngular is not empty then b2SetAngularDamping b, pAngular
end b2kSetDamping

command b2kWake pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kWake
   b2SetAwake b, true
end b2kWake

-- Send a body to sleep (it stops simulating until something wakes it).
command b2kSleep pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSleep
   b2SetAwake b, false
end b2kSleep

-- Allow or forbid THIS body ever falling asleep (vs b2kEnableSleeping,
-- which switches the whole world). The player controller forbids it: a
-- character must respond to input even after standing still for minutes.
command b2kSetSleepEnabled pControl, pFlag
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetSleepEnabled
   b2EnableSleep b, (pFlag is true)
   if pFlag is not true then b2SetAwake b, true
end b2kSetSleepEnabled

-- Below this speed (pixels/sec) a body may fall asleep. Lower = stays awake
-- longer; higher = sleeps sooner (saves CPU).
command b2kSetSleepThreshold pControl, pPxPerSec
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetSleepThreshold
   b2SetSleepThreshold b, pPxPerSec / sScale
end b2kSetSleepThreshold

-- =====================================================================
-- Acting on bodies   (velocities/kicks are in PIXELS/sec, screen-oriented)
-- =====================================================================
command b2kSetVelocity pControl, pVxPx, pVyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSetVelocity
   b2SetVelocity b, pVxPx / sScale, - pVyPx / sScale
   -- setting a velocity means "move": wake the body. Raw SetVelocity
   -- does NOT wake (why b2kPush always called SetAwake) - a SLEEPING
   -- kinematic (a parked gate) given one cached write stayed frozen,
   -- which read as "the pressure plate is flaky".
   b2SetAwake b, true
end b2kSetVelocity

command b2kPush pControl, pDvxPx, pDvyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kPush
   b2SetVelocity b, b2BodyVX(b) + pDvxPx / sScale, b2BodyVY(b) - pDvyPx / sScale
   b2SetAwake b, true
end b2kPush

command b2kSpin pControl, pDegPerSec
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSpin
   b2SetAngularVelocity b, pDegPerSec * kPI / 180
end b2kSpin

-- Add to the current spin (vs b2kSpin which sets it absolutely).
command b2kSpinBy pControl, pDegPerSec
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kSpinBy
   b2SetAngularVelocity b, b2BodyAngularVelocity(b) + pDegPerSec * kPI / 180
   b2SetAwake b, true
end b2kSpinBy

-- Continuous, screen-oriented force (thrusters, wind). Apply each frame for a
-- sustained effect; b2kPush is the one-shot impulse equivalent.
command b2kForce pControl, pFxPx, pFyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kForce
   b2ApplyForce b, pFxPx / sScale, - pFyPx / sScale, true
end b2kForce

-- A one-shot impulse (a sharp kick), screen-oriented. Mass-aware: heavier bodies
-- move less. b2kPush changes velocity directly; this is the impulse equivalent.
command b2kImpulse pControl, pIxPx, pIyPx
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kImpulse
   b2ApplyImpulse b, pIxPx / sScale, - pIyPx / sScale, true
end b2kImpulse

-- A continuous turning force (same units as motor torque). Positive turns one way,
-- negative the other. Apply each frame for a sustained twist; pairs with b2kForce.
command b2kTorque pControl, pTorque
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kTorque
   b2ApplyTorque b, pTorque, true
end b2kTorque

-- A one-shot twist (a sharp angular kick), mass-aware: bodies with more
-- rotational inertia turn less. b2kSpinBy sets the spin directly; this is the
-- impulse equivalent, and the angular partner of b2kImpulse.
command b2kAngularImpulse pControl, pImpulse
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kAngularImpulse
   b2ApplyAngularImpulse b, pImpulse, true
end b2kAngularImpulse

-- Change a body's type at runtime: "static", "kinematic", or "dynamic".
command b2kSetType pControl, pType
   local tRef, tCode
   put the long id of pControl into tRef
   if sBody[tRef] is empty then exit b2kSetType
   switch pType
      case "static"
         put 0 into tCode
         break
      case "kinematic"
         put 1 into tCode
         break
      default
         put 2 into tCode
   end switch
   b2SetBodyType sBody[tRef], tCode
   put (tCode is 0) into sStatic[tRef]   -- only true statics are skipped by sync
   if tCode is not 0 then b2SetAwake sBody[tRef], true
   put true into sNeedFullSync
end b2kSetType

command b2kSetStatic pControl
   b2kSetType pControl, "static"
end b2kSetStatic

command b2kSetDynamic pControl
   b2kSetType pControl, "dynamic"
end b2kSetDynamic

command b2kSetKinematic pControl
   b2kSetType pControl, "kinematic"
end b2kSetKinematic

-- Temporarily take a body out of / put it back into the simulation.
command b2kDisable pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kDisable
   b2DisableBody b
end b2kDisable

command b2kEnable pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then exit b2kEnable
   b2EnableBody b
   put true into sNeedFullSync
end b2kEnable

command b2kMoveTo pControl, pScreenX, pScreenY, pAngleDeg
   local tRef, tWx, tWy, tWa
   if pAngleDeg is empty then put 0 into pAngleDeg
   put the long id of pControl into tRef
   if sBody[tRef] is empty then exit b2kMoveTo
   put b2kToWorldX(pScreenX) into tWx
   put b2kToWorldY(pScreenY) into tWy
   put pAngleDeg * kPI / 180 into tWa
   b2SetTransform sBody[tRef], tWx, tWy, tWa
   b2kDrawBody tRef, tWx, tWy, tWa
end b2kMoveTo

command b2kRemove pControl
   local tRef, tBody, tWasSpawned
   put the long id of pControl into tRef
   put sBody[tRef] into tBody
   if tBody is not empty and tBody > 0 then
      b2DestroyBody tBody
      delete variable sCtrl[tBody]
   end if
   put (sSpawned[tRef] is true) into tWasSpawned
   delete variable sBody[tRef]
   delete variable sShapeH[tRef]
   delete variable sRender[tRef]
   delete variable sVerts[tRef]
   delete variable sRad[tRef]
   delete variable sImgAngle[tRef]
   delete variable sStatic[tRef]
   delete variable sSpawned[tRef]
   delete variable sSensor[tRef]
   delete variable sInCam[tRef]
   -- If the kit created this control (b2kSpawn...), delete it too, so removing
   -- a body never leaves a dead graphic behind. Attached controls are left alone.
   if tWasSpawned then
      try
         delete tRef
      end try
   end if
end b2kRemove

-- A radial "blast" that kicks nearby dynamic bodies outward. Uses Box2D's native
-- b2World_Explode: it's shape-perimeter aware (so a wide plank catches more blast
-- than a small ball) and affects EVERY dynamic body in range, not just kit ones.
-- pPowerPx is the impulse per unit length of facing surface; pRadiusPx the reach.
command b2kExplode pScreenX, pScreenY, pRadiusPx, pPowerPx
   if pRadiusPx is empty then put 180 into pRadiusPx
   if pPowerPx is empty then put 900 into pPowerPx
   if sWorld is empty then exit b2kExplode
   b2WorldExplode sWorld, b2kToWorldX(pScreenX), b2kToWorldY(pScreenY), \
         pRadiusPx / sScale, (pRadiusPx / sScale) * 0.5, pPowerPx / sScale
end b2kExplode

-- The original velocity-based blast (pre-v3): kicks only kit-tracked dynamic
-- bodies, ignoring their size. Kept for callers that relied on the old feel.
command b2kExplodeLegacy pScreenX, pScreenY, pRadiusPx, pPowerPx
   local cx, cy, tRadM, tRef, b, dx, dy, d, f
   if pRadiusPx is empty then put 180 into pRadiusPx
   if pPowerPx is empty then put 900 into pPowerPx
   put b2kToWorldX(pScreenX) into cx
   put b2kToWorldY(pScreenY) into cy
   put pRadiusPx / sScale into tRadM
   repeat for each key tRef in sBody
      if sStatic[tRef] is true then next repeat
      put sBody[tRef] into b
      put b2BodyX(b) - cx into dx
      put b2BodyY(b) - cy into dy
      put sqrt(dx * dx + dy * dy) into d
      if d > 0.02 and d < tRadM then
         put (1 - d / tRadM) * (pPowerPx / sScale) into f
         b2SetVelocity b, b2BodyVX(b) + dx / d * f, b2BodyVY(b) + dy / d * f
         b2SetAwake b, true
      end if
   end repeat
end b2kExplodeLegacy

-- =====================================================================
-- Getters
-- =====================================================================
function b2kBodyOf pControl
   return sBody[the long id of pControl]
end b2kBodyOf

-- A body's position in SCREEN pixels as "x,y" (the position partner of
-- b2kVelocity). Controls already follow their body, but this reads the exact,
-- sub-pixel centre - handy for aiming, distance checks, or mixing with b2...
function b2kPosition pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return b2kToScreenX(b2BodyX(b)) & "," & b2kToScreenY(b2BodyY(b))
end b2kPosition

-- A body's centre of mass in SCREEN pixels as "x,y". Differs from b2kPosition
-- for off-centre or compound shapes; it's the true pivot for spin and torque.
function b2kWorldCenter pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return b2kToScreenX(b2BodyWorldCenterX(b)) & "," & b2kToScreenY(b2BodyWorldCenterY(b))
end b2kWorldCenter

function b2kVelocity pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return (b2BodyVX(b) * sScale) & "," & (- b2BodyVY(b) * sScale)
end b2kVelocity

function b2kSpeed pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return sqrt((b2BodyVX(b) * sScale) ^ 2 + (b2BodyVY(b) * sScale) ^ 2)
end b2kSpeed

function b2kAngle pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyAngle(b) * 180 / kPI
end b2kAngle

function b2kIsAwake pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return false
   return b2BodyIsAwake(b)
end b2kIsAwake

-- Current rotation speed in DEGREES/sec (the getter for b2kSpin / b2kSpinBy).
function b2kSpinRate pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyAngularVelocity(b) * 180 / kPI
end b2kSpinRate

function b2kIsBullet pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return false
   return b2BodyIsBullet(b)
end b2kIsBullet

function b2kIsEnabled pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return false
   return b2BodyIsEnabled(b)
end b2kIsEnabled

function b2kMass pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyMass(b)
end b2kMass

-- The body's per-body gravity multiplier (the getter for b2kSetGravityScale).
function b2kGravityScale pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return 0
   return b2BodyGravityScale(b)
end b2kGravityScale

-- The body's drag as "linear,angular" (the getter for b2kSetDamping).
function b2kDamping pControl
   local b
   put sBody[the long id of pControl] into b
   if b is empty then return "0,0"
   return b2BodyLinearDamping(b) & "," & b2BodyAngularDamping(b)
end b2kDamping

-- Body type as a word: "static", "kinematic", or "dynamic" (mirrors b2kSetType).
function b2kBodyType pControl
   local b, tCode
   put sBody[the long id of pControl] into b
   if b is empty then return "static"
   put b2BodyType(b) into tCode
   if tCode is 1 then return "kinematic"
   if tCode is 2 then return "dynamic"
   return "static"
end b2kBodyType

-- How many bodies the kit is currently tracking.
function b2kBodyCount
   return the number of lines of the keys of sBody
end b2kBodyCount

-- How many dynamic bodies are currently awake (i.e. actively simulating).
function b2kAwakeCount
   local tRef, tCount
   put 0 into tCount
   repeat for each key tRef in sBody
      if sStatic[tRef] is not true and b2BodyIsAwake(sBody[tRef]) then add 1 to tCount
   end repeat
   return tCount
end b2kAwakeCount

-- Which attached control sits at a screen point (empty if none).
function b2kControlAt pScreenX, pScreenY
   if sWorld is empty then return empty
   return sCtrl[b2BodyAtPoint(sWorld, b2kToWorldX(pScreenX), b2kToWorldY(pScreenY))]
end b2kControlAt

-- True if SCREEN point (x,y) is inside this control's actual collision shape -
-- rotation- and shape-aware, unlike a bounding-box test. b2kControlAt searches
-- every body; this tests one control you already have (e.g. a precise click hit).
function b2kControlContains pControl, pScreenX, pScreenY
   local tRef
   put the long id of pControl into tRef
   if sShapeH[tRef] is empty then return false
   return b2ShapeTestPoint(sShapeH[tRef], b2kToWorldX(pScreenX), b2kToWorldY(pScreenY))
end b2kControlContains

-- Cast a ray between two screen points; returns the control hit (or empty).
-- Then b2kRayHitX() / b2kRayHitY() give the hit point in screen pixels.
function b2kRayHit pX1, pY1, pX2, pY2
   local dx, dy
   if sWorld is not empty and \
         b2CastRayClosest(sWorld, b2kToWorldX(pX1), b2kToWorldY(pY1), b2kToWorldX(pX2), b2kToWorldY(pY2)) then
      put round(b2kToScreenX(b2RayX())) into sRayX
      put round(b2kToScreenY(b2RayY())) into sRayY
      put b2RayNormalX() into sRayNX        -- surface normal, screen-oriented
      put - b2RayNormalY() into sRayNY
      put pX2 - pX1 into dx
      put pY2 - pY1 into dy
      put b2RayFraction() * sqrt(dx * dx + dy * dy) into sRayDist
      -- the handle is fetched for the control lookup anyway; stashing it
      -- lets the player's probe classify the ground (one-way chain or
      -- solid) without a single extra FFI call
      put b2RayBody() into sRayBodyH
      return sCtrl[sRayBodyH]
   end if
   put empty into sRayX
   put empty into sRayY
   put empty into sRayNX
   put empty into sRayNY
   put empty into sRayDist
   put empty into sRayBodyH
   return empty
end b2kRayHit

function b2kRayHitX
   return sRayX
end b2kRayHitX

function b2kRayHitY
   return sRayY
end b2kRayHitY

-- Surface normal (a unit direction, screen-oriented) at the last ray hit.
function b2kRayHitNormalX
   return sRayNX
end b2kRayHitNormalX

function b2kRayHitNormalY
   return sRayNY
end b2kRayHitNormalY

-- Distance in pixels from the ray's start to the last hit point.
function b2kRayDist
   return sRayDist
end b2kRayDist

-- ---- contacts, polling style ----------------------------------------
-- The kit also SENDS `on b2kContact` / `on b2kEndContact` to your
-- b2kContactTarget. These functions instead let you POLL the same snapshot
-- (e.g. from `on b2kFrame`) without registering a target. The snapshot
-- covers EVERY fixed step the frame ran (nothing lost on a 2-step frame,
-- nothing repeated on a 0-step one); indices are 1-based. Each accessor
-- returns the touching control's long id (empty for a wall, the ground,
-- or any body the kit isn't tracking).
function b2kContactCount
   if sEvtCN is empty then return 0
   return sEvtCN
end b2kContactCount

function b2kContactA pIndex
   return sCtrl[sEvtCA[pIndex]]
end b2kContactA

function b2kContactB pIndex
   return sCtrl[sEvtCB[pIndex]]
end b2kContactB

function b2kEndContactCount
   if sEvtEN is empty then return 0
   return sEvtEN
end b2kEndContactCount

function b2kEndContactA pIndex
   return sCtrl[sEvtEA[pIndex]]
end b2kEndContactA

function b2kEndContactB pIndex
   return sCtrl[sEvtEB[pIndex]]
end b2kEndContactB

-- =====================================================================
-- Joints (return a joint handle; pass it to b2kMotor / b2kRemoveJoint)
-- =====================================================================
-- Revolute pivot at screen point (x,y). If ctrlB is empty, pins ctrlA to the
-- world at that point (great for pendulums and swinging doors).
command b2kHinge pCtrlA, pCtrlB, pScreenX, pScreenY
   local bA, bB, wx, wy, aA, aB, j
   put sBody[the long id of pCtrlA] into bA
   if bA is empty or sWorld is empty then return 0
   if pCtrlB is not empty and sBody[the long id of pCtrlB] is empty then return 0
   put b2kToWorldX(pScreenX) into wx
   put b2kToWorldY(pScreenY) into wy
   put b2kLocalAnchor(bA, wx, wy) into aA
   if pCtrlB is empty then
      put sDragAnchor into bB
      put wx & "," & wy into aB
   else
      put sBody[the long id of pCtrlB] into bB
      put b2kLocalAnchor(bB, wx, wy) into aB
   end if
   put b2RevoluteJoint(sWorld, bA, bB, item 1 of aA, item 2 of aA, item 1 of aB, item 2 of aB, false) into j
   return j
end b2kHinge

command b2kWeld pCtrlA, pCtrlB
   local bA, bB, wx, wy, aA, refA, j
   put sBody[the long id of pCtrlA] into bA
   put sBody[the long id of pCtrlB] into bB
   if bA is empty or bB is empty or sWorld is empty then return 0
   put b2BodyX(bB) into wx
   put b2BodyY(bB) into wy
   put b2kLocalAnchor(bA, wx, wy) into aA
   put b2BodyAngle(bB) - b2BodyAngle(bA) into refA
   put b2WeldJoint(sWorld, bA, bB, item 1 of aA, item 2 of aA, 0, 0, refA, false) into j
   return j
end b2kWeld

-- Distance link. pLengthPx defaults to the current distance between centres.
command b2kRope pCtrlA, pCtrlB, pLengthPx
   local bA, bB, tLen, dx, dy, j
   put sBody[the long id of pCtrlA] into bA
   put sBody[the long id of pCtrlB] into bB
   if bA is empty or bB is empty or sWorld is empty then return 0
   if pLengthPx is empty then
      put b2BodyX(bB) - b2BodyX(bA) into dx
      put b2BodyY(bB) - b2BodyY(bA) into dy
      put sqrt(dx * dx + dy * dy) into tLen
   else
      put pLengthPx / sScale into tLen
   end if
   put b2DistanceJoint(sWorld, bA, bB, 0, 0, 0, 0, tLen, false) into j
   return j
end b2kRope

command b2kMotor pJoint, pDegPerSec, pMaxTorque
   if pJoint is empty or pJoint <= 0 then exit b2kMotor
   if pMaxTorque is empty then put 1000 into pMaxTorque
   b2RevoluteEnableMotor pJoint, true, pDegPerSec * kPI / 180, pMaxTorque
end b2kMotor

-- Optional revolute (hinge) limits/readout. Angles are in DEGREES.
command b2kHingeLimit pJoint, pLowerDeg, pUpperDeg
   if pJoint is empty or pJoint <= 0 then exit b2kHingeLimit
   b2RevoluteEnableLimit pJoint, true, pLowerDeg * kPI / 180, pUpperDeg * kPI / 180
end b2kHingeLimit

function b2kHingeAngle pJoint
   if pJoint is empty or pJoint <= 0 then return 0
   return b2RevoluteAngle(pJoint) * 180 / kPI
end b2kHingeAngle

-- Rope (distance) extras: read length, set a min/max range, make it springy.
function b2kRopeLength pJoint
   if pJoint is empty or pJoint <= 0 then return 0
   return b2DistanceLength(pJoint) * sScale
end b2kRopeLength

-- Set a rope (distance) joint's exact rest length, in pixels.
command b2kRopeSetLength pJoint, pLengthPx
   if pJoint is empty or pJoint <= 0 then exit b2kRopeSetLength
   b2DistanceSetLength pJoint, pLengthPx / sScale
end b2kRopeSetLength

command b2kRopeRange pJoint, pMinPx, pMaxPx
   if pJoint is empty or pJoint <= 0 then exit b2kRopeRange
   b2DistanceSetLengthRange pJoint, pMinPx / sScale, pMaxPx / sScale
end b2kRopeRange

command b2kSpring pJoint, pHertz, pDamping
   if pJoint is empty or pJoint <= 0 then exit b2kSpring
   if pDamping is empty then put 0.5 into pDamping
   b2DistanceEnableSpring pJoint, true, pHertz, pDamping
end b2kSpring

-- Make a weld springy (0 hertz = rigid again).
command b2kWeldSpring pJoint, pHertz, pDamping
   if pJoint is empty or pJoint <= 0 then exit b2kWeldSpring
   if pDamping is empty then put 0.5 into pDamping
   b2WeldSetStiffness pJoint, pHertz, pDamping, pHertz, pDamping
end b2kWeldSpring

-- Slider (prismatic): constrain pCtrlA to slide along an axis relative to
-- pCtrlB (or the world if empty). pAxisDeg is the on-screen slide direction
-- (0 = horizontal, 90 = vertical; default vertical). Drive it with b2kSliderMotor.
command b2kSlider pCtrlA, pCtrlB, pAxisDeg
   local bMover, bFixed, wax, way, ca, sa, lax, lay, anchX, anchY, aFix, aMov, refA, fixAng, j
   put sBody[the long id of pCtrlA] into bMover
   if pCtrlB is empty then put sDragAnchor into bFixed
   else put sBody[the long id of pCtrlB] into bFixed
   if bMover is empty or bFixed is empty or sWorld is empty then return 0
   if pAxisDeg is empty then put 90 into pAxisDeg
   put cos(pAxisDeg * kPI / 180) into wax
   put - sin(pAxisDeg * kPI / 180) into way
   put b2BodyAngle(bFixed) into fixAng
   put cos(- fixAng) into ca
   put sin(- fixAng) into sa
   put wax * ca - way * sa into lax
   put wax * sa + way * ca into lay
   put b2BodyX(bMover) into anchX
   put b2BodyY(bMover) into anchY
   put b2kLocalAnchor(bFixed, anchX, anchY) into aFix
   put b2kLocalAnchor(bMover, anchX, anchY) into aMov
   put b2BodyAngle(bMover) - fixAng into refA
   put b2PrismaticJoint(sWorld, bFixed, bMover, item 1 of aFix, item 2 of aFix, \
         item 1 of aMov, item 2 of aMov, lax, lay, refA, false) into j
   return j
end b2kSlider

command b2kSliderMotor pJoint, pPxPerSec, pMaxForce
   if pJoint is empty or pJoint <= 0 then exit b2kSliderMotor
   if pMaxForce is empty then put 1000 into pMaxForce
   b2PrismaticEnableMotor pJoint, true, pPxPerSec / sScale, pMaxForce
end b2kSliderMotor

command b2kSliderLimit pJoint, pLowerPx, pUpperPx
   if pJoint is empty or pJoint <= 0 then exit b2kSliderLimit
   b2PrismaticEnableLimit pJoint, true, pLowerPx / sScale, pUpperPx / sScale
end b2kSliderLimit

function b2kSliderPos pJoint
   if pJoint is empty or pJoint <= 0 then return 0
   return b2PrismaticTranslation(pJoint) * sScale
end b2kSliderPos

-- Wheel: a sprung sliding axis + free spin (vehicle wheels). pChassis carries
-- pWheel; anchor defaults to the wheel's centre, suspension axis to world "up".
-- Drive with b2kWheelMotor, tune ride with b2kWheelSpring.
command b2kWheel pChassis, pWheel, pScreenX, pScreenY, pAxisDeg
   local bA, bB, anchX, anchY, aA, aB, wax, way, ca, sa, lax, lay, angA, j
   put sBody[the long id of pChassis] into bA
   put sBody[the long id of pWheel] into bB
   if bA is empty or bB is empty or sWorld is empty then return 0
   if pScreenX is empty then
      put b2BodyX(bB) into anchX
      put b2BodyY(bB) into anchY
   else
      put b2kToWorldX(pScreenX) into anchX
      put b2kToWorldY(pScreenY) into anchY
   end if
   if pAxisDeg is empty then
      put 0 into wax
      put 1 into way
   else
      put cos(pAxisDeg * kPI / 180) into wax
      put - sin(pAxisDeg * kPI / 180) into way
   end if
   put b2BodyAngle(bA) into angA
   put cos(- angA) into ca
   put sin(- angA) into sa
   put wax * ca - way * sa into lax
   put wax * sa + way * ca into lay
   put b2kLocalAnchor(bA, anchX, anchY) into aA
   put b2kLocalAnchor(bB, anchX, anchY) into aB
   put b2WheelJoint(sWorld, bA, bB, item 1 of aA, item 2 of aA, \
         item 1 of aB, item 2 of aB, lax, lay, false) into j
   return j
end b2kWheel

command b2kWheelMotor pJoint, pDegPerSec, pMaxTorque
   if pJoint is empty or pJoint <= 0 then exit b2kWheelMotor
   if pMaxTorque is empty then put 1000 into pMaxTorque
   b2WheelEnableMotor pJoint, true, pDegPerSec * kPI / 180, pMaxTorque
end b2kWheelMotor

command b2kWheelSpring pJoint, pHertz, pDamping
   if pJoint is empty or pJoint <= 0 then exit b2kWheelSpring
   if pHertz is empty then put 4 into pHertz
   if pDamping is empty then put 0.7 into pDamping
   b2WheelEnableSpring pJoint, true, pHertz, pDamping
end b2kWheelSpring

-- OFF switches: the b2k... joint wrappers above only ever turn a feature ON, so
-- these let callers disable a motor or limit again (free swing / unbounded slide).
command b2kMotorOff pJoint
   if pJoint is not empty and pJoint > 0 then b2RevoluteEnableMotor pJoint, false, 0, 0
end b2kMotorOff

command b2kHingeLimitOff pJoint
   if pJoint is not empty and pJoint > 0 then b2RevoluteEnableLimit pJoint, false, 0, 0
end b2kHingeLimitOff

command b2kSliderMotorOff pJoint
   if pJoint is not empty and pJoint > 0 then b2PrismaticEnableMotor pJoint, false, 0, 0
end b2kSliderMotorOff

command b2kSliderLimitOff pJoint
   if pJoint is not empty and pJoint > 0 then b2PrismaticEnableLimit pJoint, false, 0, 0
end b2kSliderLimitOff

command b2kWheelMotorOff pJoint
   if pJoint is not empty and pJoint > 0 then b2WheelEnableMotor pJoint, false, 0, 0
end b2kWheelMotorOff

command b2kRemoveJoint pJoint
   if pJoint is not empty and pJoint > 0 then b2DestroyJoint pJoint
end b2kRemoveJoint

function b2kLocalAnchor pBody, pWx, pWy
   local bcx, bcy, ba, dx, dy, c, s
   put b2BodyX(pBody) into bcx
   put b2BodyY(pBody) into bcy
   put b2BodyAngle(pBody) into ba
   put pWx - bcx into dx
   put pWy - bcy into dy
   put cos(- ba) into c
   put sin(- ba) into s
   return (dx * c - dy * s) & "," & (dx * s + dy * c)
end b2kLocalAnchor

-- =====================================================================
-- Sensors (non-solid trigger zones)
-- =====================================================================
-- Attach a SENSOR fixture to a control: it reports overlaps but never blocks.
-- Static by default (a fixed trigger zone); pShape is "box" (default), "ball" or
-- "capsule". While the loop runs, overlaps are delivered to your b2kContactTarget
-- as `on b2kSensorEnter pSensorCtrl, pVisitorCtrl` / `on b2kSensorExit ...`. The
-- kit enables sensor events on every body it creates, so sensors detect them.
command b2kAddSensor pControl, pShape
   local tRef
   if sWorld is empty then return 0
   put the long id of pControl into tRef
   b2ShapeDefSensor true
   b2ShapeDefEnableSensorEvents true
   switch pShape
      case "ball"
         b2kAddBall pControl, false
         break
      case "capsule"
         b2kAddCapsule pControl, false
         break
      default
         b2kAddBox pControl, false
   end switch
   if sBody[tRef] is empty then
      -- the attach bailed (zero-sized control): clear the pending one-shot
      -- sensor flags so they cannot leak onto the next shape someone creates
      b2ShapeDefReset
      return 0
   end if
   put true into sSensor[tRef]
   return sBody[tRef]
end b2kAddSensor

-- Flip a control's collision between solid and SENSOR (a non-solid trigger that
-- reports overlaps but never blocks). The flag lives on the shape, so rebuild the
-- shape afterwards with b2kReshape - it re-applies the sensor state from here.
command b2kSetSensor pControl, pFlag
   put (pFlag is true) into sSensor[the long id of pControl]
end b2kSetSensor

-- Polling alternative to the on b2kSensorEnter/Exit messages (read in on b2kFrame).
-- Counts/indices are 1-based; each returns a control (empty for untracked bodies).
function b2kSensorCount
   if sEvtSN is empty then return 0
   return sEvtSN
end b2kSensorCount
function b2kSensorEnterSensor pIndex
   return sCtrl[sEvtSS[pIndex]]
end b2kSensorEnterSensor
function b2kSensorEnterVisitor pIndex
   return sCtrl[sEvtSV[pIndex]]
end b2kSensorEnterVisitor
function b2kSensorExitCount
   if sEvtXN is empty then return 0
   return sEvtXN
end b2kSensorExitCount
function b2kSensorExitSensor pIndex
   return sCtrl[sEvtXS[pIndex]]
end b2kSensorExitSensor
function b2kSensorExitVisitor pIndex
   return sCtrl[sEvtXV[pIndex]]
end b2kSensorExitVisitor

-- =====================================================================
-- Collision filtering (named layers; up to 32)
-- =====================================================================
-- Define (or fetch) a named collision layer, returning its bit value. Then
-- b2kSetCategory / b2kSetMask take a comma- or space-separated list of layer
-- names (or raw numbers). Two shapes collide only if EACH one's category appears
-- in the other's mask (and no shared negative group forbids it).
command b2kDefineLayer pName
   if sLayers[pName] is not empty then return sLayers[pName]
   if sNextBit is empty or sNextBit < 1 then put 1 into sNextBit
   -- xTalk's bitOr is 32-bit, so a wrapped layer would get a category of 0
   -- (= collides with nothing). Refuse instead of corrupting filters. The
   -- TOP bit (2^31) is the Kit's reserved "oneway" chain layer, so user
   -- layers stop at 2^30: 31 nameable layers.
   if sNextBit > 1073741824 then return 0
   put sNextBit into sLayers[pName]
   put sNextBit * 2 into sNextBit
   return sLayers[pName]
end b2kDefineLayer

function b2kLayerBits pLayerList
   local tBits, tL
   put 0 into tBits
   replace comma with space in pLayerList
   repeat for each word tL in pLayerList
      if tL is empty then next repeat
      if tL is "oneway" then
         -- the reserved chain layer (bit 2^31): nameable in masks so a
         -- body can opt in/out of one-way terrain explicitly
         put tBits bitOr 2147483648 into tBits
         next repeat
      end if
      if tL is a number then
         put tBits bitOr (tL) into tBits
      else
         -- b2kDefineLayer is a COMMAND: OXT cannot call commands with
         -- function syntax, so invoke it as a statement and read the result
         b2kDefineLayer tL
         put tBits bitOr (the result) into tBits
      end if
   end repeat
   return tBits
end b2kLayerBits

command b2kSetCategory pControl, pLayerList
   local s
   put sShapeH[the long id of pControl] into s
   if s is empty then exit b2kSetCategory
   b2SetShapeFilter s, b2kLayerBits(pLayerList), b2ShapeFilterMask(s), b2ShapeFilterGroup(s)
end b2kSetCategory

command b2kSetMask pControl, pLayerList
   local s
   put sShapeH[the long id of pControl] into s
   if s is empty then exit b2kSetMask
   -- a named-layer mask means OBJECT rules, not "fall through the
   -- terrain": the reserved chain bit rides along automatically, so
   -- custom-masked bodies still stand on b2kChain ground. To really
   -- pass through chains use raw b2SetShapeFilter (the player's
   -- drop-through window does exactly that, internally).
   b2SetShapeFilter s, b2ShapeFilterCategory(s), b2kLayerBits(pLayerList) bitOr 2147483648, b2ShapeFilterGroup(s)
end b2kSetMask

-- Group index: bodies sharing a NEGATIVE group never collide; a POSITIVE group
-- always collide. Overrides category/mask. 0 (default) = use category/mask.
command b2kSetCollisionGroup pControl, pGroup
   local s
   put sShapeH[the long id of pControl] into s
   if s is empty then exit b2kSetCollisionGroup
   b2SetShapeFilter s, b2ShapeFilterCategory(s), b2ShapeFilterMask(s), pGroup
end b2kSetCollisionGroup

-- =====================================================================
-- Chains (smooth terrain) and world queries
-- =====================================================================
-- A smooth static chain (ground/terrain) from a list of SCREEN points ("x,y" per
-- line). Unlike joined box/segment edges it has no inner corners for fast bodies
-- to catch on. Needs >= 4 points; pLoop true closes it. Invisible (draw a matching
-- graphic). Returns a chain handle (b2DestroyChain to remove).
-- THE GHOST RULE (open chains): Box2D uses the FIRST and LAST segments as
-- ghost anchors only -- N points collide as N-3 segments. Run the chain one
-- segment PAST the surface you need on each side (over solid ground the
-- ghost tails can simply continue flat). A chain whose endpoints sit AT the
-- platform edges has non-solid ends -- bodies fall straight through them.
command b2kChain pPoints, pLoop
   local tBody, p, tChain
   if sWorld is empty then return 0
   set the itemDelimiter to comma   -- points are "x,y" (gotcha 5)
   put b2NewStaticBody(sWorld, 0, 0) into tBody
   b2ChainBegin
   repeat for each line p in pPoints
      if p is empty then next repeat
      b2ChainAddPoint b2kToWorldX(item 1 of p), b2kToWorldY(item 2 of p)
   end repeat
   -- every Kit chain carries the reserved ONE-WAY category (bit 2^31,
   -- the "oneway" layer) with an all-bits mask: nothing collides any
   -- differently, but the player's drop-through window can now stop
   -- colliding with chains ALONE by masking out that single bit.
   b2ShapeDefFilter 2147483648, 4294967295, 0
   put b2CreateChain(tBody, (pLoop is true), 0.6, 0.1) into tChain
   if tChain > 0 then put true into sOneWayBody[tBody]
   return tChain
end b2kChain

command b2kSmoothGround pPoints
   -- statement call + the result: OXT cannot call commands function-style.
   -- Mind b2kChain's GHOST RULE: the outer two points anchor, not collide.
   b2kChain pPoints, false
   return the result
end b2kSmoothGround

-- Attach a smooth static chain to a CONTROL, from a list of SCREEN points
-- ("x,y" per line) - the control's own outline. Unlike b2kChain (which makes an
-- untracked world body), this registers the body against the control like
-- b2kAddBox/Ball/Polygon, so it selects (b2kControlAt), drags (b2kMoveTo) and
-- removes (b2kRemove) as a normal static part. The points are taken relative to
-- the control's centre, so moving the control moves the terrain with it. pLoop
-- true closes the outline into a solid blob; false leaves a one-sided ground
-- line. Great for smooth, rolling, concave terrain a fast body won't catch on.
command b2kAddChain pControl, pPoints, pLoop
   local tRef, tCx, tCy, tBody, p, lx, ly
   if sWorld is empty then return 0
   set the itemDelimiter to comma   -- locs and points are "x,y" (gotcha 5)
   put the long id of pControl into tRef
   put item 1 of the loc of pControl into tCx
   put item 2 of the loc of pControl into tCy
   put b2NewStaticBody(sWorld, b2kToWorldX(tCx), b2kToWorldY(tCy)) into tBody
   b2ChainBegin
   repeat for each line p in pPoints
      if p is empty then next repeat
      put (item 1 of p - tCx) / sScale into lx          -- local to the control's centre
      put - ((item 2 of p - tCy) / sScale) into ly
      b2ChainAddPoint lx, ly
   end repeat
   get b2CreateChain(tBody, (pLoop is true), 0.6, 0.1)
   b2kRegister tRef, tBody, true                        -- static, kit-tracked
   put "loc" into sRender[tRef]                          -- static: registered but never synced
   return tBody
end b2kAddChain

-- Controls whose body overlaps a screen RECT (newline-separated long ids).
-- NOTE: this asks the BROADPHASE, whose boxes are fattened (~0.1m = a few
-- px) -- a region touching the floor reports the floor. For presence
-- checks (plates, buttons) use b2kOverlapMoving.
function b2kOverlap pX1, pY1, pX2, pY2
   if sWorld is empty then return empty
   return b2kQueryToControls(b2OverlapAABB(sWorld, b2kToWorldX(pX1), b2kToWorldY(pY1), b2kToWorldX(pX2), b2kToWorldY(pY2)))
end b2kOverlap

-- Controls of MOVING (non-static) bodies overlapping a screen RECT --
-- THE presence poll for pressure plates and buttons. A pad region must
-- sit on its floor, and the broadphase's fattened boxes make the floor
-- itself overlap it forever; filtering statics asks what a plate means:
-- "is some THING on me?" (Dynamic and kinematic bodies count; sleeping
-- ones still register.)
function b2kOverlapMoving pX1, pY1, pX2, pY2
   local tLine, tOut
   put empty into tOut
   repeat for each line tLine in b2kOverlap(pX1, pY1, pX2, pY2)
      if tLine is empty then next repeat
      if sStatic[tLine] is true then next repeat
      put tLine & cr after tOut
   end repeat
   return tOut
end b2kOverlapMoving

-- Controls whose body overlaps a screen circle.
function b2kOverlapCircle pX, pY, pRadiusPx
   if sWorld is empty then return empty
   return b2kQueryToControls(b2OverlapCircle(sWorld, b2kToWorldX(pX), b2kToWorldY(pY), pRadiusPx / sScale))
end b2kOverlapCircle

-- Every control a ray crosses, nearest-first (vs b2kRayHit's single closest).
function b2kRayHitAll pX1, pY1, pX2, pY2
   if sWorld is empty then return empty
   return b2kQueryToControls(b2RayCastAll(sWorld, b2kToWorldX(pX1), b2kToWorldY(pY1), b2kToWorldX(pX2), b2kToWorldY(pY2)))
end b2kRayHitAll

-- Shared: turn the current query result (count) into a newline list of controls.
function b2kQueryToControls pCount
   local i, c, tList
   put empty into tList
   repeat with i = 1 to pCount
      put sCtrl[b2QueryBody(i)] into c
      if c is not empty then put c & cr after tList
   end repeat
   return tList
end b2kQueryToControls

-- =====================================================================
-- Motor & filter joints
-- =====================================================================
-- Drive pMover toward a target pose relative to pRef (a moving anchor; empty =
-- the world). Offsets are in screen pixels / degrees from pRef's centre. Great for
-- followers, lifts and character motion. Returns a joint handle (b2kRemoveJoint).
command b2kMotorTo pMover, pRef, pOffsetXPx, pOffsetYPx, pAngleDeg, pMaxForce, pMaxTorque
   local bMover, bRef
   put sBody[the long id of pMover] into bMover
   if pRef is empty then put sDragAnchor into bRef
   else put sBody[the long id of pRef] into bRef
   if bMover is empty or bRef is empty or sWorld is empty then return 0
   if pAngleDeg is empty then put 0 into pAngleDeg
   if pMaxForce is empty then put 1000 into pMaxForce
   if pMaxTorque is empty then put 1000 into pMaxTorque
   return b2MotorJoint(sWorld, bRef, bMover, pOffsetXPx / sScale, - pOffsetYPx / sScale, \
         pAngleDeg * kPI / 180, pMaxForce, pMaxTorque, 0.3, false)
end b2kMotorTo

-- Stop two specific controls from colliding with each other (without changing how
-- either collides with anything else). Returns a joint handle (b2kRemoveJoint).
command b2kNoCollide pCtrlA, pCtrlB
   local bA, bB
   put sBody[the long id of pCtrlA] into bA
   put sBody[the long id of pCtrlB] into bB
   if bA is empty or bB is empty or sWorld is empty then return 0
   return b2FilterJoint(sWorld, bA, bB)
end b2kNoCollide

-- =====================================================================
-- World tuning (advanced) + perf readout
-- =====================================================================
-- Below this approach speed (px/sec) collisions stop bouncing, even if bouncy.
command b2kSetRestitutionThreshold pPxPerSec
   if sWorld is not empty then b2SetRestitutionThreshold sWorld, pPxPerSec / sScale
end b2kSetRestitutionThreshold

-- Contact softness: stiffness (hertz), damping ratio, max separation-fix speed (px/sec).
command b2kSetContactTuning pHertz, pDamping, pPushPx
   if sWorld is not empty then b2SetContactTuning sWorld, pHertz, pDamping, pPushPx / sScale
end b2kSetContactTuning

command b2kSetJointTuning pHertz, pDamping
   if sWorld is not empty then b2SetJointTuning sWorld, pHertz, pDamping
end b2kSetJointTuning

-- Clamp how fast any body can move (px/sec) - stops runaway speeds.
command b2kSetMaxSpeed pPxPerSec
   if sWorld is not empty then b2SetMaximumLinearSpeed sWorld, pPxPerSec / sScale
end b2kSetMaxSpeed

command b2kEnableWarmStarting pFlag
   if sWorld is not empty then b2EnableWarmStarting sWorld, (pFlag is true)
end b2kEnableWarmStarting

-- A quick perf readout in milliseconds: "totalStep,collide,solve" for the last step.
function b2kProfile
   if sWorld is empty then return empty
   b2WorldProfileUpdate sWorld
   return b2WorldProfileStep() & "," & b2WorldProfileCollide() & "," & b2WorldProfileSolve()
end b2kProfile

-- How many dynamic bodies are awake right now (native count, vs b2kAwakeCount).
function b2kAwakeBodyCount
   if sWorld is empty then return 0
   return b2AwakeBodyCount(sWorld)
end b2kAwakeBodyCount

-- =====================================================================
-- Dragging: call b2kGrab from mouseDown and b2kRelease from mouseUp.
-- =====================================================================
function b2kGrab pScreenX, pScreenY
   local tWx, tWy, tBody
   if sWorld is empty then return empty   -- grab before setup: nothing to hit
   put b2kToWorldX(pScreenX) into tWx
   put b2kToWorldY(pScreenY) into tWy
   put b2BodyAtPoint(sWorld, tWx, tWy) into tBody
   if tBody > 0 and b2BodyType(tBody) is 2 then
      b2SetAwake tBody, true
      put b2MouseJoint(sWorld, sDragAnchor, tBody, tWx, tWy, 6, 0.7, 4000) into sDragJoint
      put true into sDragging
      return sCtrl[tBody]
   end if
   return empty
end b2kGrab

command b2kRelease
   if sDragJoint is not empty and sDragJoint > 0 then b2DestroyJoint sDragJoint
   put 0 into sDragJoint
   put false into sDragging
end b2kRelease

-- =====================================================================
-- Input (keyboard): poll-and-diff held keys, once per frame
-- =====================================================================
-- Model: one `the keysDown` sample per frame (taken inside the loop, just
-- before b2kFrame dispatches), diffed against the previous frame's sample.
-- Held = in the current set; pressed/released = the diff. This sidesteps
-- every event-path problem at once: OS auto-repeat (Win32 re-sends
-- rawKeyDown with no paired ups), focus stealing by fields/buttons, and
-- frontscript plumbing. Letter keys bind BOTH keysym cases ("w" = 119 and
-- 87) because the reported code shifts with the Shift key.
command b2kInputOn
   put true into sInputOn
   put comma into sKeysNow
   put comma into sKeysPrev
   -- starter bindings; rebind freely (these only fill empty slots)
   if sKeyActions["jump"] is empty then b2kBindAction "jump", "space"
   if sKeyActions["dash"] is empty then b2kBindAction "dash", "shift,x"
   if sAxisNeg["moveX"] is empty then b2kBindAxis "moveX", "left,a", "right,d"
   if sAxisNeg["moveY"] is empty then b2kBindAxis "moveY", "up,w", "down,s"
end b2kInputOn

command b2kInputOff
   put false into sInputOn
   put comma into sKeysNow
   put comma into sKeysPrev
end b2kInputOff

function b2kInputIsOn
   return (sInputOn is true)
end b2kInputIsOn

-- Internal, called by the loop each frame while armed. The sets are stored
-- comma-wrapped (",65361,32,") so membership is one `contains` test.
command b2kInputTick
   if sInputOn is not true then exit b2kInputTick
   put sKeysNow into sKeysPrev
   if sInjectOn is true then
      put comma & sInjectKeys & comma into sKeysNow
   else
      put comma & the keysDown & comma into sKeysNow
   end if
end b2kInputTick

-- Replace the keyboard with a SCRIPTED key set (friendly names or codes;
-- empty = nothing held) until b2kInputInjectOff. Deterministic input for
-- the self-test harness, input replays, and cutscene "ghost" players --
-- edges fall out of the normal frame diff exactly as with real keys.
command b2kInputInject pKeys
   put true into sInjectOn
   put b2kKeyListCodes(pKeys) into sInjectKeys
end b2kInputInject

command b2kInputInjectOff
   put false into sInjectOn
   put empty into sInjectKeys
end b2kInputInjectOff

-- A friendly key name (or raw keycode) -> the keycode candidates it matches,
-- comma-separated. Numbers >= 32 pass through as raw keycodes; single
-- characters resolve to their code (letters to both cases, per the
-- Shift-keysym behaviour the Phase 0 spike confirmed).
function b2kKeyCodes pKey
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
end b2kKeyCodes

-- The reverse map, for readouts: a keycode -> its friendly name (or itself).
function b2kKeyName pCode
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
end b2kKeyName

-- True when any of pKey's candidate codes is in the given set.
function b2kKeyInSet pSet, pKey
   local tC
   if pSet is empty or pSet is comma then return false
   repeat for each item tC in b2kKeyCodes(pKey)
      if pSet contains (comma & tC & comma) then return true
   end repeat
   return false
end b2kKeyInSet

function b2kKeyIsDown pKey
   return b2kKeyInSet(sKeysNow, pKey)
end b2kKeyIsDown

-- Edge queries: true only on the single frame the state changed.
function b2kKeyPressed pKey
   return b2kKeyInSet(sKeysNow, pKey) and not b2kKeyInSet(sKeysPrev, pKey)
end b2kKeyPressed

function b2kKeyReleased pKey
   return b2kKeyInSet(sKeysPrev, pKey) and not b2kKeyInSet(sKeysNow, pKey)
end b2kKeyReleased

-- Everything held right now, as friendly names (debug HUDs).
function b2kKeysHeld
   local tOut, tC
   put empty into tOut
   repeat for each item tC in char 2 to -2 of sKeysNow
      put b2kKeyName(tC) & space after tOut
   end repeat
   return word 1 to -1 of tOut
end b2kKeysHeld

-- Actions: a named set of keys ("jump" = "space,up,w"). Any bound key
-- counts; the action's edges treat the whole set as one logical key.
-- The name->keycode resolution happens ONCE, at bind time (the cached
-- code list is what the per-frame queries scan) -- these run inside the
-- player tick and game code every frame, so they must stay cheap.
command b2kBindAction pName, pKeyList
   put pKeyList into sKeyActions[pName]
   put b2kKeyListCodes(pKeyList) into sKeyActionsC[pName]
end b2kBindAction

-- Internal: a friendly key list -> every matching keycode, comma list.
function b2kKeyListCodes pKeyList
   local tK, tOut
   put empty into tOut
   set the itemDelimiter to comma
   repeat for each item tK in pKeyList
      if tOut is empty then
         put b2kKeyCodes(word 1 of tK) into tOut
      else
         put comma & b2kKeyCodes(word 1 of tK) after tOut
      end if
   end repeat
   return tOut
end b2kKeyListCodes

-- Internal: is any of these (pre-resolved) keycodes in the given set?
function b2kCodesInSet pSet, pCodes
   local tC
   if pSet is empty or pSet is comma then return false
   repeat for each item tC in pCodes
      if pSet contains (comma & tC & comma) then return true
   end repeat
   return false
end b2kCodesInSet

function b2kActionIsDown pName
   return b2kCodesInSet(sKeysNow, sKeyActionsC[pName])
end b2kActionIsDown

function b2kActionPressed pName
   if not b2kCodesInSet(sKeysNow, sKeyActionsC[pName]) then return false
   return not b2kCodesInSet(sKeysPrev, sKeyActionsC[pName])
end b2kActionPressed

function b2kActionReleased pName
   if not b2kCodesInSet(sKeysPrev, sKeyActionsC[pName]) then return false
   return not b2kCodesInSet(sKeysNow, sKeyActionsC[pName])
end b2kActionReleased

-- Axes: -1 / 0 / +1 from two key sets ("moveX" defaults to left,a / right,d).
-- Both directions held = 0, which is what character movement wants.
command b2kBindAxis pName, pNegKeys, pPosKeys
   put pNegKeys into sAxisNeg[pName]
   put pPosKeys into sAxisPos[pName]
   put b2kKeyListCodes(pNegKeys) into sAxisNegC[pName]
   put b2kKeyListCodes(pPosKeys) into sAxisPosC[pName]
end b2kBindAxis

function b2kAxis pName
   local tNeg, tPos
   put b2kCodesInSet(sKeysNow, sAxisNegC[pName]) into tNeg
   put b2kCodesInSet(sKeysNow, sAxisPosC[pName]) into tPos
   if tPos and not tNeg then return 1
   if tNeg and not tPos then return -1
   return 0
end b2kAxis

-- Real elapsed ms folded into the last frame -- drive animations and user
-- timers from this, not the step count (a frame may run 0..n fixed steps).
function b2kFrameMS
   if sFrameMS is empty then return 0
   return sFrameMS
end b2kFrameMS

-- =====================================================================
-- Sprites: sheets, atlases, named animations (icon-button backend)
-- =====================================================================
-- Model (decided by the Phase 0 spike, S12): a sheet registers named or
-- numbered frame REGIONS of one hidden source image; each region is sliced
-- into its own hidden image LAZILY, on first use. A sprite is a transparent
-- BUTTON whose icon is the current frame's image -- a frame switch is one
-- property set, and every sprite of a sheet shares the same frame images.
-- Mirrored (left-facing) frames are flip-clones, also made lazily.
-- Sheets persist until b2kTeardown (unless b2kSheetPersist is on; see below);
-- sprites are Kit-created controls, so b2kClear removes them like everything
-- else the Kit spawned.

-- Loaded sheets are ASSETS, not world state. By default b2kTeardown wipes
-- them (a full reset), but a multi-LEVEL game reloads the same atlases every
-- rebuild -- the costliest thing the Kit does (decode each PNG, parse each
-- XML, re-slice every frame). Turn this ON and sheets SURVIVE b2kTeardown,
-- exactly like synthesized sounds do, so they load ONCE per session: a level
-- rebuild reuses them (an identical b2kSheetLoad/LoadAtlas is then a no-op),
-- and re-warmed frames are already sliced. The Kit's source images are named
-- deterministically (b2ksheet_<name>) and tagged with their file path, so a
-- SAVED stack carries them: on reopen the load reuses the in-stack image
-- (skipping the expensive decode) instead of re-importing from disk. Call
-- b2kSheetsWipe to force a clean reload (e.g. after the user picks a new
-- asset folder). OFF by default, so single-shot examples are unchanged.
command b2kSheetPersist pFlag
   put (pFlag is not false) into sSheetKeep
end b2kSheetPersist

function b2kSheetPersists
   return (sSheetKeep is true)
end b2kSheetPersists

-- Register an image FILE as a uniform grid of pFW x pFH frames, numbered
-- 1..N left-to-right, top-to-bottom. Reports the frame count. Sheets that
-- are not edge-to-edge take pMargin (outer border px) and pSpacing (gap
-- between cells px). Pass pFW/pFH 0 (or empty) to register the image with
-- NO grid and name regions yourself with b2kSheetAddFrame -- the path for
-- packed sheets that have no Kenney-style XML.
command b2kSheetLoad pName, pPath, pFW, pFH, pCount, pMargin, pSpacing
   local tRef, tSig
   put pPath & "|" & pFW & "|" & pFH & "|" & pCount & "|" & pMargin & "|" & pSpacing into tSig
   if sSheetKeep is true and sSheetKeys[pName] is not empty and sSheetPath[pName] is tSig then
      return the number of lines of sSheetKeys[pName]   -- already loaded (same file+grid): reuse it
   end if
   put b2kSheetSourceFromFile(pName, pPath) into tRef
   if tRef is empty then return 0
   b2kSheetGridRegions pName, pFW, pFH, pCount, pMargin, pSpacing
   put tSig into sSheetPath[pName]
   return the number of lines of sSheetKeys[pName]
end b2kSheetLoad

-- Register an image already in the stack (e.g. base64-embedded art) as a
-- grid sheet. The image is used in place and never deleted by the Kit.
-- Same grid arguments as b2kSheetLoad (margin/spacing; 0x0 = no grid).
command b2kSheetFromImage pName, pImgRef, pFW, pFH, pCount, pMargin, pSpacing
   local tRef, tSig
   put the long id of pImgRef into tRef
   put tRef & "|" & pFW & "|" & pFH & "|" & pCount & "|" & pMargin & "|" & pSpacing into tSig
   if sSheetKeep is true and sSheetKeys[pName] is not empty and sSheetPath[pName] is tSig then
      return the number of lines of sSheetKeys[pName]   -- already loaded (same image+grid): reuse it
   end if
   b2kSheetForget pName
   put tRef into sSheetSrc[pName]
   put false into sSheetOwned[pName]
   b2kSheetGridRegions pName, pFW, pFH, pCount, pMargin, pSpacing
   put tSig into sSheetPath[pName]
   return the number of lines of sSheetKeys[pName]
end b2kSheetFromImage

-- Name one region of a loaded sheet yourself: the no-XML path for packed
-- sheets in any layout. Load the source first (b2kSheetLoad/FromImage with
-- frame size 0 for no grid), then add each frame by name; regions may be
-- any size and position and can also be added on top of a grid or atlas.
-- Redefining a name re-bakes its slice on next use.
command b2kSheetAddFrame pSheet, pFrame, pX, pY, pW, pH
   local tId
   if sSheetSrc[pSheet] is empty then exit b2kSheetAddFrame
   if pFrame is empty then exit b2kSheetAddFrame
   if pX is not a number or pY is not a number then exit b2kSheetAddFrame
   if pW is not a number or pH is not a number then exit b2kSheetAddFrame
   if pW < 1 or pH < 1 then exit b2kSheetAddFrame
   if sSheetRegion[pSheet][pFrame] is empty then
      if sSheetKeys[pSheet] is empty then
         put pFrame into sSheetKeys[pSheet]
      else
         put cr & pFrame after sSheetKeys[pSheet]
      end if
   else
      -- redefined: drop any stale slices so the new region re-bakes lazily
      put sSheetIcon[pSheet][pFrame] into tId
      if tId is not empty then
         try
            delete image id tId
         catch tErr
         end try
      end if
      delete variable sSheetIcon[pSheet][pFrame]
      put sSheetFlip[pSheet][pFrame] into tId
      if tId is not empty then
         try
            delete image id tId
         catch tErr
         end try
      end if
      delete variable sSheetFlip[pSheet][pFrame]
   end if
   put round(pX) & comma & round(pY) & comma & round(pW) & comma & round(pH) into sSheetRegion[pSheet][pFrame]
end b2kSheetAddFrame

-- Register a packed atlas: a PNG plus the TextureAtlas XML that names its
-- regions (<SubTexture name=".." x=".." y=".." width=".." height=".."/> --
-- the Kenney pack format, like Spritesheets/ in this repo). Frames are
-- addressed BY NAME. pXmlPath defaults to the png path with ".xml".
command b2kSheetLoadAtlas pName, pPngPath, pXmlPath
   local tRef, tXml, tLine, tNm, tX, tY, tW, tH, tSig
   if pXmlPath is empty then
      put pPngPath into pXmlPath
      set the itemDelimiter to "."
      put "xml" into item -1 of pXmlPath
   end if
   put pPngPath & "|" & pXmlPath into tSig
   if sSheetKeep is true and sSheetKeys[pName] is not empty and sSheetPath[pName] is tSig then
      return the number of lines of sSheetKeys[pName]   -- already loaded (same png+xml): reuse it
   end if
   put URL ("file:" & pXmlPath) into tXml
   if tXml is empty then put URL ("binfile:" & pXmlPath) into tXml
   if tXml is empty then return 0
   put b2kSheetSourceFromFile(pName, pPngPath) into tRef
   if tRef is empty then return 0
   set the itemDelimiter to comma
   repeat for each line tLine in tXml
      if tLine contains "<SubTexture" then
         put b2kXmlAttr(tLine, "name") into tNm
         put b2kXmlAttr(tLine, "x") into tX
         put b2kXmlAttr(tLine, "y") into tY
         put b2kXmlAttr(tLine, "width") into tW
         put b2kXmlAttr(tLine, "height") into tH
         if tNm is empty or tX is not a number or tY is not a number then next repeat
         if tW is not a number or tH is not a number then next repeat
         put tX & comma & tY & comma & tW & comma & tH into sSheetRegion[pName][tNm]
         put tNm & cr after sSheetKeys[pName]
      end if
   end repeat
   if the last char of sSheetKeys[pName] is cr then delete the last char of sSheetKeys[pName]
   put tSig into sSheetPath[pName]
   return the number of lines of sSheetKeys[pName]
end b2kSheetLoadAtlas

function b2kSheetFrames pName
   return the number of lines of sSheetKeys[pName]
end b2kSheetFrames

function b2kSheetHasFrame pName, pFrame
   return (sSheetRegion[pName][pFrame] is not empty)
end b2kSheetHasFrame

-- Every frame key of a sheet, one per line, in definition order --
-- introspect an atlas you didn't make ("what is this frame called?").
function b2kSheetFrameNames pName
   return sSheetKeys[pName]
end b2kSheetFrameNames

-- Display scale for a sheet's frames (default 1). Frames slice lazily, so
-- set this right after loading the sheet, BEFORE creating sprites or anims:
-- already-sliced frames are dropped and re-bake at the new scale, but live
-- sprites keep their button rects. The engine does the resampling, so any
-- frame size displays at any sprite size.
command b2kSheetScale pName, pScale
   local tKey, tId
   put b2kClamp(pScale, 0.05, 8) into pScale
   if b2kNumberOr(sSheetScale[pName], 1) is pScale then exit b2kSheetScale
   put pScale into sSheetScale[pName]
   repeat for each key tKey in sSheetIcon[pName]
      put sSheetIcon[pName][tKey] into tId
      if tId is not empty then
         try
            delete image id tId
         catch tErr
         end try
      end if
   end repeat
   repeat for each key tKey in sSheetFlip[pName]
      put sSheetFlip[pName][tKey] into tId
      if tId is not empty then
         try
            delete image id tId
         catch tErr
         end try
      end if
   end repeat
   delete variable sSheetIcon[pName]
   delete variable sSheetFlip[pName]
end b2kSheetScale

-- A frame's DISPLAY size as "w,h" (its region size times the sheet scale) --
-- lay out tiles and platforms from this instead of hard-coding pixels.
function b2kSheetFrameSize pName, pFrame
   local tRegion, tScale
   put sSheetRegion[pName][pFrame] into tRegion
   if tRegion is empty then return empty
   set the itemDelimiter to comma
   put b2kNumberOr(sSheetScale[pName], 1) into tScale
   return max(1, round((item 3 of tRegion) * tScale)) & comma & max(1, round((item 4 of tRegion) * tScale))
end b2kSheetFrameSize

-- Define a named animation: pFrames is a comma list of frame names and/or
-- 1-based indices, with numeric ranges ("1-8") expanded. pLoop defaults true.
command b2kAnimDef pSheet, pAnim, pFrames, pFPS, pLoop
   local tKey, tList, tItem, tA, tB, i
   put pSheet & "|" & pAnim into tKey
   put empty into tList
   set the itemDelimiter to comma
   repeat for each item tItem in pFrames
      put word 1 to -1 of tItem into tItem
      if tItem contains "-" and tItem is not a number then
         set the itemDelimiter to "-"
         put item 1 of tItem into tA
         put item 2 of tItem into tB
         set the itemDelimiter to comma
         if tA is a number and tB is a number then
            repeat with i = tA to tB
               put i & cr after tList
            end repeat
            next repeat
         end if
      end if
      put tItem & cr after tList
   end repeat
   if the last char of tList is cr then delete the last char of tList
   put tList into sAnimList[tKey]
   put b2kClamp(pFPS, 0.1, 120) into sAnimFPS[tKey]
   put (pLoop is not false) into sAnimLoop[tKey]
end b2kAnimDef

-- Create a sprite: a transparent button showing pFrame (default: the sheet's
-- first frame), centred on pX,pY and sized to the frame. Reports the control.
-- It is an ordinary Kit control: pass it to b2kAddCapsule/b2kAddBox for a
-- body (buttons render position-only with rotation locked), or bind it to
-- another control's body with b2kSpriteBind.
command b2kSpriteNew pSheet, pFrame, pX, pY
   local tName, tRef, tKey, tRegion, tW, tH
   if sSheetKeys[pSheet] is empty then return empty
   put pFrame into tKey
   if tKey is empty then put line 1 of sSheetKeys[pSheet] into tKey
   put b2kSheetFrameSize(pSheet, tKey) into tRegion   -- "w,h" at display scale
   if tRegion is empty then return empty
   set the itemDelimiter to comma
   put item 1 of tRegion into tW
   put item 2 of tRegion into tH
   put b2kNumberOr(pX, (the width of this card) div 2) into pX
   put b2kNumberOr(pY, (the height of this card) div 2) into pY
   put "b2kspr_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create button tName
   else
      create button tName in group "b2kcam_view"
   end if
   put the long id of button tName into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   set the style of tRef to "transparent"
   set the showName of tRef to false
   set the traversalOn of tRef to false
   set the autoHilite of tRef to false
   subtract b2kCamShiftX(tRef) from pX   -- creation while scrolled: place in
   subtract b2kCamShiftY(tRef) from pY   -- world coords on visual engines too
   set the rect of tRef to round(pX - tW / 2), round(pY - tH / 2), round(pX + tW / 2), round(pY + tH / 2)
   if sCamGroup is empty then
      -- dynamic layers composite in STACK coordinates: inside a scrolled
      -- viewport they ignore the group scroll and draw unscrolled, so a
      -- camera sprite must stay a plain group child
      try
         set the layerMode of tRef to "dynamic"
      catch tErr
      end try
   end if
   put pSheet into sSprSheet[tRef]
   put "sheet" into sSprKind[tRef]
   put false into sSprFlip[tRef]
   put true into sSpawned[tRef]
   put tRef & cr after sSprRefs
   b2kSpriteShowFrame tRef, tKey
   return tRef
end b2kSpriteNew

-- A sprite backed by an animated GIF file: the engine plays it; the Kit's
-- play/stop/frame calls drive repeatCount/currentFrame instead of icons.
command b2kSpriteFromGIF pPath, pX, pY
   local tName, tRef, tData
   put URL ("binfile:" & pPath) into tData   -- content-load, like the sheets
   if tData is empty then return empty
   put "b2kspr_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create image tName
   else
      create image tName in group "b2kcam_view"
   end if
   put the long id of image tName into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   try
      set the text of tRef to tData
   catch tErr
   end try
   set the lockLoc of tRef to true
   if the width of tRef < 1 then
      try
         delete tRef
      catch tErr
      end try
      return empty
   end if
   put b2kNumberOr(pX, (the width of this card) div 2) into pX
   put b2kNumberOr(pY, (the height of this card) div 2) into pY
   set the loc of tRef to round(pX - b2kCamShiftX(tRef)) & comma & round(pY - b2kCamShiftY(tRef))
   if sCamGroup is empty then
      try
         set the layerMode of tRef to "dynamic"   -- see b2kSpriteNew note
      catch tErr
      end try
   end if
   try
      set the repeatCount of tRef to -1
   catch tErr
   end try
   put "gif" into sSprKind[tRef]
   put true into sSpawned[tRef]
   put tRef & cr after sSprRefs
   return tRef
end b2kSpriteFromGIF

-- Start a named animation; a no-op if it is already playing (so calling it
-- every frame from a state machine is free) unless pRestart forces frame 1.
command b2kSpritePlay pCtrl, pAnim, pRestart
   local tRef, tKey
   put the long id of pCtrl into tRef
   if sSprKind[tRef] is "gif" then
      try
         set the repeatCount of tRef to -1
      catch tErr
      end try
      exit b2kSpritePlay
   end if
   if sSprSheet[tRef] is empty then exit b2kSpritePlay
   put sSprSheet[tRef] & "|" & pAnim into tKey
   if sAnimList[tKey] is empty then exit b2kSpritePlay
   if sSprAnim[tRef] is pAnim and pRestart is not true then exit b2kSpritePlay
   put pAnim into sSprAnim[tRef]
   put true into sSprLiveDirty   -- it now needs per-frame service
   put 1 into sSprStep[tRef]
   if sSprFPSOver[tRef] is not empty then
      put sSprFPSOver[tRef] into sSprFPS[tRef]
   else
      put sAnimFPS[tKey] into sSprFPS[tRef]
   end if
   if sSprFPS[tRef] is empty or sSprFPS[tRef] <= 0 then put 8 into sSprFPS[tRef]
   put the milliseconds + (1000 / sSprFPS[tRef]) into sSprNextMS[tRef]
   b2kSpriteShowFrame tRef, line 1 of sAnimList[tKey]
end b2kSpritePlay

command b2kSpriteStop pCtrl
   local tRef
   put the long id of pCtrl into tRef
   if sSprKind[tRef] is "gif" then
      try
         set the repeatCount of tRef to 0
      catch tErr
      end try
      exit b2kSpriteStop
   end if
   put empty into sSprAnim[tRef]
   put true into sSprLiveDirty
end b2kSpriteStop

function b2kSpriteAnim pCtrl
   try
      return sSprAnim[the long id of pCtrl]
   catch tErr
      return empty   -- a removed control is a stale ref, not an error
   end try
end b2kSpriteAnim

-- Show one frame by name/index (stops any running animation first).
command b2kSpriteSetFrame pCtrl, pFrame
   local tRef
   put the long id of pCtrl into tRef
   if sSprKind[tRef] is "gif" then
      try
         set the repeatCount of tRef to 0
         set the currentFrame of tRef to pFrame
      catch tErr
      end try
      exit b2kSpriteSetFrame
   end if
   put empty into sSprAnim[tRef]
   put true into sSprLiveDirty
   b2kSpriteShowFrame tRef, pFrame
end b2kSpriteSetFrame

function b2kSpriteFrame pCtrl
   try
      return sSprFrameKey[the long id of pCtrl]
   catch tErr
      return empty
   end try
end b2kSpriteFrame

-- Per-sprite speed override (empty = use each animation's own fps).
command b2kSpriteFPS pCtrl, pFPS
   local tRef
   put the long id of pCtrl into tRef
   put pFPS into sSprFPSOver[tRef]
   if pFPS is a number and pFPS > 0 then put pFPS into sSprFPS[tRef]
end b2kSpriteFPS

-- Face left (true) or right (false). The mirrored frame image is created
-- the first time it is needed, by flip-cloning the sliced frame.
command b2kSpriteFlipH pCtrl, pFlag
   local tRef
   put the long id of pCtrl into tRef
   if sSprSheet[tRef] is empty then exit b2kSpriteFlipH
   put (pFlag is true) into pFlag
   if sSprFlip[tRef] is pFlag then exit b2kSpriteFlipH
   put pFlag into sSprFlip[tRef]
   if sSprFrameKey[tRef] is not empty then b2kSpriteShowFrame tRef, sSprFrameKey[tRef]
end b2kSpriteFlipH

function b2kSpriteFlipped pCtrl
   try
      return (sSprFlip[the long id of pCtrl] is true)
   catch tErr
      return false
   end try
end b2kSpriteFlipped

-- When a NON-looping animation finishes, send pMessage to the frame target
-- with the sprite and the animation name (attack/death/effect chaining).
command b2kSpriteOnFinish pCtrl, pMessage
   put pMessage into sSprMsg[the long id of pCtrl]
end b2kSpriteOnFinish

-- Pin this sprite to another control's position each frame (offset in px) --
-- the standard pattern for "art bigger than the collision shape": give an
-- invisible control the body, bind the sprite to it.
command b2kSpriteBind pCtrl, pBodyCtrl, pDX, pDY
   local tRef
   put the long id of pCtrl into tRef
   put the long id of pBodyCtrl into sSprBind[tRef]
   put b2kNumberOr(pDX, 0) into sSprBindDX[tRef]
   put b2kNumberOr(pDY, 0) into sSprBindDY[tRef]
   put true into sSprLiveDirty   -- it now needs per-frame service
end b2kSpriteBind

command b2kSpriteUnbind pCtrl
   delete variable sSprBind[the long id of pCtrl]
   put true into sSprLiveDirty
end b2kSpriteUnbind

-- Remove a sprite (and its body, if it has one).
command b2kSpriteRemove pCtrl
   local tRef
   try
      put the long id of pCtrl into tRef
   catch tErr
      put pCtrl into tRef   -- stale path (group gone): still clear the registry
   end try
   if sBody[tRef] is not empty then
      try
         b2kRemove tRef       -- destroys the body and deletes the control
      catch tErr
      end try
   else
      try
         delete tRef
      catch tErr
      end try
   end if
   b2kSpriteForget tRef
end b2kSpriteRemove

-- Internal: drop a sprite's registry entries (the control is already gone).
command b2kSpriteForget pRef
   local tLn
   delete variable sSprSheet[pRef]
   delete variable sSprKind[pRef]
   delete variable sSprAnim[pRef]
   delete variable sSprStep[pRef]
   delete variable sSprNextMS[pRef]
   delete variable sSprFPS[pRef]
   delete variable sSprFPSOver[pRef]
   delete variable sSprFlip[pRef]
   delete variable sSprMsg[pRef]
   delete variable sSprBind[pRef]
   delete variable sSprBindDX[pRef]
   delete variable sSprBindDY[pRef]
   delete variable sSprFrameKey[pRef]
   delete variable sSprIconNow[pRef]
   delete variable sSprLastLoc[pRef]
   delete variable sInCam[pRef]
   set the wholeMatches to true
   put lineOffset(pRef, sSprRefs) into tLn
   if tLn > 0 then delete line tLn of sSprRefs
   put true into sSprLiveDirty
end b2kSpriteForget

-- Internal: remove every live sprite (b2kClear / b2kTeardown path).
command b2kSpritesClear
   local tRef, tList
   put sSprRefs into tList
   repeat for each line tRef in tList
      if tRef is not empty then b2kSpriteRemove tRef
   end repeat
   put empty into sSprRefs
   put empty into sSprLive
   put false into sSprLiveDirty
end b2kSpritesClear

-- Internal: forget one sheet -- its regions, anims, sliced/mirrored frame
-- images, and (if the Kit loaded it) the hidden source image.
command b2kSheetForget pName
   local tKey, tId
   if sSheetSrc[pName] is empty and sSheetKeys[pName] is empty then exit b2kSheetForget
   repeat for each key tKey in sSheetIcon[pName]
      put sSheetIcon[pName][tKey] into tId
      if tId is not empty then
         try
            delete image id tId
         catch tErr
         end try
      end if
   end repeat
   repeat for each key tKey in sSheetFlip[pName]
      put sSheetFlip[pName][tKey] into tId
      if tId is not empty and tId is not sSheetIcon[pName][tKey] then
         try
            delete image id tId
         catch tErr
         end try
      end if
   end repeat
   if sSheetOwned[pName] is not false and sSheetSrc[pName] is not empty then
      try
         delete sSheetSrc[pName]
      catch tErr
      end try
   end if
   delete variable sSheetSrc[pName]
   delete variable sSheetOwned[pName]
   delete variable sSheetRegion[pName]
   delete variable sSheetKeys[pName]
   delete variable sSheetIcon[pName]
   delete variable sSheetFlip[pName]
   delete variable sSheetData[pName]
   delete variable sSheetAlpha[pName]
   delete variable sSheetScale[pName]
   delete variable sSheetPath[pName]
   repeat for each key tKey in sAnimList
      if char 1 to (the number of chars of pName) + 1 of tKey is pName & "|" then
         delete variable sAnimList[tKey]
         delete variable sAnimFPS[tKey]
         delete variable sAnimLoop[tKey]
      end if
   end repeat
end b2kSheetForget

-- Internal: every sheet + every sprite (b2kTeardown path).
command b2kSheetsWipe
   local tName
   b2kSpritesClear
   repeat for each key tName in sSheetSrc
      b2kSheetForget tName
   end repeat
   put empty into sSheetSrc
   put empty into sSheetRegion
   put empty into sSheetKeys
   put empty into sSheetIcon
   put empty into sSheetFlip
   put empty into sSheetData
   put empty into sSheetAlpha
   put empty into sSheetScale
   put empty into sSheetPath
   put empty into sAnimList
   put empty into sAnimFPS
   put empty into sAnimLoop
   b2kSpriteSweepOrphans
end b2kSheetsWipe

-- Internal: delete Kit-generated sprite/sheet controls left over from a
-- PREVIOUS session. Script-locals reset when a stack reopens (or a new
-- script is pasted in), but the controls persist -- registry cleanup can't
-- see them, so a reopened stack would show ghost sprites frozen on their
-- last frame. Swept by name prefix on every teardown.
command b2kSpriteSweepOrphans pKeepAssets
   local tAgain, i, tName, tHit
   put true into tAgain
   repeat while tAgain
      put false into tAgain
      repeat with i = 1 to the number of controls of this card
         put the short name of control i of this card into tName
         if char 1 to 7 of tName is "b2kcam_" then
            -- a dead session's viewport: free the children, then the shell
            try
               ungroup control i of this card
            catch tErr
               delete control i of this card
            end try
            put true into tAgain
            exit repeat
         end if
         put false into tHit
         if char 1 to 7 of tName is "b2kspr_" then put true into tHit
         -- sheet ASSET images (sources + sliced frames + flips) are KEPT
         -- when persisting (b2kSheetPersist); only sprite instances + dead
         -- viewports go, so the sheet cache survives the teardown
         if pKeepAssets is not true then
            if char 1 to 6 of tName is "b2kfr_" then put true into tHit
            if char 1 to 6 of tName is "b2kfl_" then put true into tHit
            if char 1 to 9 of tName is "b2ksheet_" then put true into tHit
         end if
         if tHit then
            delete control i of this card
            put true into tAgain
            exit repeat
         end if
      end repeat
   end repeat
end b2kSpriteSweepOrphans

-- ---- sprite internals ------------------------------------------------

-- Internal: load an image file into a hidden, Kit-owned source image.
-- The bytes are loaded as CONTENT (binfile -> set the text), not as a
-- filename reference: referenced images size and load lazily for hidden
-- controls, which broke the slicer's stride; content images adopt their
-- pixel size immediately -- the exact path b2kSheetFromImage users (and
-- the platformer's embedded placeholder) already exercise successfully.
-- lockLoc only AFTER the content, so the control has auto-sized first.
function b2kSheetSourceFromFile pName, pPath
   local tImg, tData
   put "b2ksheet_" & pName into tImg
   -- REUSE: a source image already decoded for this exact file -- earlier
   -- this session, or carried inside a SAVED stack (b2kSheetPersist) -- is
   -- the cache. Adopt it in place and skip the costly binfile decode.
   if sSheetKeep is true and there is an image tImg \
         and the uB2kSrcPath of image tImg is pPath and the width of image tImg >= 2 then
      set the lockLoc of image tImg to true
      put the long id of image tImg into sSheetSrc[pName]
      put true into sSheetOwned[pName]
      return sSheetSrc[pName]
   end if
   b2kSheetForget pName
   if there is no file pPath then return empty
   put URL ("binfile:" & pPath) into tData
   if tData is empty then return empty
   if there is an image tImg then delete image tImg
   create image tImg
   set the visible of it to false
   try
      set the text of image tImg to tData
   catch tErr
      delete image tImg
      return empty
   end try
   if the width of image tImg < 2 then
      delete image tImg
      return empty
   end if
   set the lockLoc of image tImg to true
   set the uB2kSrcPath of image tImg to pPath   -- the cache key for next time
   put the long id of image tImg into sSheetSrc[pName]
   put true into sSheetOwned[pName]
   return sSheetSrc[pName]
end b2kSheetSourceFromFile

-- Internal: register grid regions over the current source image. Margin =
-- outer border (left AND top, assumed symmetric), spacing = gap between
-- cells; both default 0 (edge-to-edge, the common case). A frame size of
-- 0/empty registers NO grid -- the caller names regions with
-- b2kSheetAddFrame instead.
command b2kSheetGridRegions pName, pFW, pFH, pCount, pMargin, pSpacing
   local tCols, tRows, tMax, i, tC, tR
   if sSheetSrc[pName] is empty then exit b2kSheetGridRegions
   if b2kNumberOr(pFW, 0) < 1 or b2kNumberOr(pFH, 0) < 1 then exit b2kSheetGridRegions
   put b2kClamp(pFW, 1, 4096) into pFW
   put b2kClamp(pFH, 1, 4096) into pFH
   put round(b2kClamp(pMargin, 0, 2048)) into pMargin
   put round(b2kClamp(pSpacing, 0, 2048)) into pSpacing
   put ((the width of sSheetSrc[pName]) - 2 * pMargin + pSpacing) div (pFW + pSpacing) into tCols
   put ((the height of sSheetSrc[pName]) - 2 * pMargin + pSpacing) div (pFH + pSpacing) into tRows
   if tCols < 1 or tRows < 1 then exit b2kSheetGridRegions
   put tCols * tRows into tMax
   if pCount is a number and pCount > 0 and pCount < tMax then put pCount into tMax
   repeat with i = 1 to tMax
      put (i - 1) mod tCols into tC
      put (i - 1) div tCols into tR
      put (pMargin + tC * (pFW + pSpacing)) & comma & (pMargin + tR * (pFH + pSpacing)) & comma & pFW & comma & pFH into sSheetRegion[pName][i]
      put i & cr after sSheetKeys[pName]
   end repeat
   if the last char of sSheetKeys[pName] is cr then delete the last char of sSheetKeys[pName]
end b2kSheetGridRegions

-- Internal: one attribute value out of an XML tag line (attr="value").
function b2kXmlAttr pLine, pAttr
   local tFrom, tLen
   put offset(pAttr & "=" & quote, pLine) into tFrom
   if tFrom is 0 then return empty
   add the number of chars of pAttr + 2 to tFrom
   put offset(quote, pLine, tFrom - 1) into tLen
   if tLen is 0 then return empty
   return char tFrom to tFrom + tLen - 2 of pLine
end b2kXmlAttr

-- Internal: make sure a frame's sliced image exists (lazy, cached). The
-- source pixels are fetched once per sheet and kept until teardown.
-- Internal: the 1-based position of a frame key in its sheet's key list --
-- a STABLE id (load order is deterministic) used to name sliced frames so a
-- SAVED stack can find and reuse them (b2kSheetPersist), never duplicating.
function b2kSheetKeyIndex pSheet, pKey
   local i, tK
   put 0 into i
   repeat for each line tK in sSheetKeys[pSheet]
      add 1 to i
      if tK is pKey then return i
   end repeat
   return 0
end b2kSheetKeyIndex

-- Internal: a slice's provenance stamp. A saved frame image is only safe to
-- reuse if it was baked from the CURRENT source (sSheetPath already encodes
-- the file/image + grid/xml args) at the CURRENT scale. Stamped onto each
-- slice as uB2kSig and re-checked on reuse, so a reopened stack that reuses a
-- sheet NAME for different art, or changes a sheet's scale, re-slices instead
-- of adopting stale pixels (the name alone is not a safe identity).
function b2kSheetSliceSig pSheet
   return sSheetPath[pSheet] & "|" & b2kNumberOr(sSheetScale[pSheet], 1)
end b2kSheetSliceSig

command b2kSheetEnsureIcon pSheet, pKey
   local tRegion, tX, tY, tW, tH, tSW, tRowPx, tFD, tFA, y, tName, tScale, tW2, tH2
   if sSheetIcon[pSheet][pKey] is not empty then exit b2kSheetEnsureIcon
   put sSheetRegion[pSheet][pKey] into tRegion
   if tRegion is empty then exit b2kSheetEnsureIcon
   -- Frame image name. Persisting: a DETERMINISTIC name (b2kfr_<sheet>_<n>)
   -- lets a slice carried in a SAVED stack be found and reused -- but only if
   -- its uB2kSig still matches (baked from the current source at the current
   -- scale), so a reused sheet name or a changed scale re-slices rather than
   -- show stale pixels. Off the persist path: a fresh unique name (no key
   -- scan; the slice is wiped on teardown anyway), exactly as before.
   if sSheetKeep is true then
      put "b2kfr_" & pSheet & "_" & b2kSheetKeyIndex(pSheet, pKey) into tName
      if there is an image tName and the uB2kSig of image tName is b2kSheetSliceSig(pSheet) then
         put the id of image tName into sSheetIcon[pSheet][pKey]
         exit b2kSheetEnsureIcon
      end if
   else
      put "b2kfr_" & the milliseconds & "_" & random(1000000) into tName
   end if
   if sSheetData[pSheet] is empty then
      put the imageData of sSheetSrc[pSheet] into sSheetData[pSheet]
      put the alphaData of sSheetSrc[pSheet] into sSheetAlpha[pSheet]
   end if
   set the itemDelimiter to comma
   put item 1 of tRegion into tX
   put item 2 of tRegion into tY
   put item 3 of tRegion into tW
   put item 4 of tRegion into tH
   put the width of sSheetSrc[pSheet] into tSW
   -- refuse to slice from inconsistent pixels: a stride mismatch must yield
   -- an empty (invisible) frame, never garbage on screen
   if the number of bytes in sSheetData[pSheet] is not tSW * (the height of sSheetSrc[pSheet]) * 4 then exit b2kSheetEnsureIcon
   if tX + tW > tSW then exit b2kSheetEnsureIcon
   put empty into tFD
   put empty into tFA
   repeat with y = 0 to tH - 1
      put (tY + y) * tSW + tX into tRowPx
      put byte (tRowPx * 4 + 1) to (tRowPx * 4 + tW * 4) of sSheetData[pSheet] after tFD
      put byte (tRowPx + 1) to (tRowPx + tW) of sSheetAlpha[pSheet] after tFA
   end repeat
   if the number of bytes in tFD is not tW * tH * 4 then exit b2kSheetEnsureIcon
   if the number of bytes in tFA is not tW * tH then
      put empty into tFA   -- no usable alpha: ship the frame fully opaque
   end if
   if there is an image tName then delete image tName   -- never duplicate a deterministic slice
   create image tName
   set the visible of it to false
   set the lockLoc of it to true
   set the width of it to tW
   set the height of it to tH
   set the imageData of image tName to tFD
   if tFA is not empty then set the alphaData of image tName to tFA
   -- sheet scale: resize the control (the engine resamples the render),
   -- then bake that render back in as the frame's real pixels
   put b2kNumberOr(sSheetScale[pSheet], 1) into tScale
   if tScale is not 1 then
      put max(1, round(tW * tScale)) into tW2
      put max(1, round(tH * tScale)) into tH2
      set the width of image tName to tW2
      set the height of image tName to tH2
      put the imageData of image tName into tFD
      put the alphaData of image tName into tFA
      set the imageData of image tName to tFD
      if tFA is not empty then set the alphaData of image tName to tFA
   end if
   if sSheetKeep is true then set the uB2kSig of image tName to b2kSheetSliceSig(pSheet)
   put the id of image tName into sSheetIcon[pSheet][pKey]
end b2kSheetEnsureIcon

-- Internal: the mirrored copy of a frame (falls back to the unmirrored
-- frame if this engine's flip throws, so facing left never errors).
command b2kSheetEnsureFlip pSheet, pKey
   local tName
   if sSheetFlip[pSheet][pKey] is not empty then exit b2kSheetEnsureFlip
   if sSheetKeep is true then
      put "b2kfl_" & pSheet & "_" & b2kSheetKeyIndex(pSheet, pKey) into tName
      if there is an image tName and the uB2kSig of image tName is b2kSheetSliceSig(pSheet) then
         put the id of image tName into sSheetFlip[pSheet][pKey]   -- reuse a saved flip
         exit b2kSheetEnsureFlip
      end if
   else
      put "b2kfl_" & the milliseconds & "_" & random(1000000) into tName
   end if
   b2kSheetEnsureIcon pSheet, pKey
   if sSheetIcon[pSheet][pKey] is empty then exit b2kSheetEnsureFlip
   try
      if there is an image tName then delete image tName
      clone image id sSheetIcon[pSheet][pKey]
      set the name of it to tName
      set the visible of it to false
      flip image tName horizontal
      if sSheetKeep is true then set the uB2kSig of image tName to b2kSheetSliceSig(pSheet)
      put the id of image tName into sSheetFlip[pSheet][pKey]
   catch tErr
      put sSheetIcon[pSheet][pKey] into sSheetFlip[pSheet][pKey]
   end try
end b2kSheetEnsureFlip

-- Internal: point a sprite's icon at a frame, honouring its facing. Skips
-- the property set when the icon is already right (the sDrawKey idea).
command b2kSpriteShowFrame pRef, pKey
   local tSheet, tIcon
   put sSprSheet[pRef] into tSheet
   if tSheet is empty then exit b2kSpriteShowFrame
   if sSprFlip[pRef] is true then
      b2kSheetEnsureFlip tSheet, pKey
      put sSheetFlip[tSheet][pKey] into tIcon
   else
      b2kSheetEnsureIcon tSheet, pKey
      put sSheetIcon[tSheet][pKey] into tIcon
   end if
   if tIcon is empty then exit b2kSpriteShowFrame
   put pKey into sSprFrameKey[pRef]
   if sSprIconNow[pRef] is tIcon then exit b2kSpriteShowFrame
   set the icon of pRef to tIcon
   put tIcon into sSprIconNow[pRef]
end b2kSpriteShowFrame

-- Internal: per-frame service -- bound sprites follow their body's control,
-- playing animations advance on wall-clock time. Vanished controls are
-- forgotten, like the body sync does.
command b2kSpritesTick
   local tNow, tRef, tDead, tSheet, tAnim, tAKey, tList, tStep, tN, tLoc, tBX, tBY
   if sSprRefs is empty then exit b2kSpritesTick
   -- the tick walks only the LIVE subset (bound and/or playing); the
   -- list rebuilds lazily when membership changed. Tile-heavy scenes
   -- are ~90% inert sprites, and per-frame cost must not scale with
   -- them (a platformer level: ~100 tiles skipped, ~25 live serviced).
   if sSprLiveDirty is true then
      put empty into sSprLive
      repeat for each line tRef in sSprRefs
         if tRef is empty then next repeat
         if sSprBind[tRef] is not empty or sSprAnim[tRef] is not empty then
            put tRef & cr after sSprLive
         end if
      end repeat
      put false into sSprLiveDirty
   end if
   if sSprLive is empty then exit b2kSpritesTick
   put the milliseconds into tNow
   put empty into tDead
   set the itemDelimiter to comma
   repeat for each line tRef in sSprLive
      if tRef is empty then next repeat
      -- still-inert guard: membership changed mid-frame retires next tick
      if sSprBind[tRef] is empty and sSprAnim[tRef] is empty then next repeat
      try
         if sSprBind[tRef] is not empty then
            put the loc of sSprBind[tRef] into tLoc
            put (item 1 of tLoc) + b2kCamShiftX(sSprBind[tRef]) + sSprBindDX[tRef] into tBX
            put (item 2 of tLoc) + b2kCamShiftY(sSprBind[tRef]) + sSprBindDY[tRef] into tBY
            put tBX & comma & tBY into tLoc
            if sSprLastLoc[tRef] is not tLoc then
               set the loc of tRef to (tBX - b2kCamShiftX(tRef)) & comma & (tBY - b2kCamShiftY(tRef))
               put tLoc into sSprLastLoc[tRef]
            end if
         end if
         if sSprKind[tRef] is "sheet" and sSprAnim[tRef] is not empty then
            if tNow >= sSprNextMS[tRef] then
               put sSprSheet[tRef] into tSheet
               put sSprAnim[tRef] into tAnim
               put tSheet & "|" & tAnim into tAKey
               put sAnimList[tAKey] into tList
               put the number of lines of tList into tN
               put sSprStep[tRef] + 1 into tStep
               if tStep > tN then
                  if sAnimLoop[tAKey] is false then
                     put empty into sSprAnim[tRef]
                     put true into sSprLiveDirty   -- (if also unbound) retire it
                     if sSprMsg[tRef] is not empty and sFrameObj is not empty then
                        dispatch sSprMsg[tRef] to sFrameObj with tRef, tAnim
                     end if
                     next repeat
                  end if
                  put 1 into tStep
               end if
               put tStep into sSprStep[tRef]
               add (1000 / sSprFPS[tRef]) to sSprNextMS[tRef]
               if sSprNextMS[tRef] < tNow then put tNow + (1000 / sSprFPS[tRef]) into sSprNextMS[tRef]
               b2kSpriteShowFrame tRef, (line tStep of tList)
            end if
         end if
      catch tErr
         put tRef & cr after tDead   -- control vanished; clean up below
      end try
   end repeat
   repeat for each line tRef in tDead
      if tRef is not empty then b2kSpriteForget tRef
   end repeat
end b2kSpritesTick

-- =====================================================================
-- Player: a platformer character controller (input -> motion + anims)
-- =====================================================================
-- ONE keyboard-driven player (spec section 6): a vertical capsule with
-- fixed rotation, sleep disabled and low friction, steered by a per-frame
-- tick that reads the Input module's axes "moveX"/"moveY" and action
-- "jump" (rebind those names to remap the controls). Horizontal motion is
-- velocity-driven -- vx is accelerated toward axis * moveSpeed, so
-- stopping needs no friction and walls can't glue the character.
-- Grounding is decided by short downward rays whose surface normal must
-- point sufficiently up, which makes walkable-slope vs wall one cosine
-- compare. The feel features platformers expect are built in: coyote
-- time, jump buffering, release jump-cut (tap = hop, hold = full jump),
-- a terminal fall speed, and a one-tick "land" state for dust and sound.
-- Wave 2 actions: DOWN ducks (brake to a stop; the hitbox keeps its
-- size this wave); DOWN+JUMP on a ONE-WAY CHAIN drops through it (a
-- dropMs window without chain collision); UP (or DOWN in the air) in a
-- b2kPlayerAddLadder zone climbs (gravity 0, velocity-driven, JUMP
-- exits); b2kPlayerHurt is the contact-damage knockback standard.
-- With b2kPlayerAnims set, the controller drives b2kSpritePlay/FlipH on
-- the player's art -- the player control itself when it IS a sprite, or
-- the first sprite b2kSpriteBind-pinned to it (the invisible-body
-- pattern). Tuning lives in b2kPlayerSet/Get; b2kClear keeps it (it is
-- config, like input bindings); b2kTeardown and b2kPlayerRemove wipe it.

-- One call: an invisible capsule host (or a visible capsule graphic when
-- no sheet is given), the body, the controller, input armed. With pSheet,
-- a sprite showing the sheet's first frame is created and bound on top --
-- so the collision size (pW x pH) is independent of the art size.
-- Reports the player control (give that to b2kCamFollow, sensors, etc).
command b2kPlayerMake pX, pY, pW, pH, pSheet
   local tName, tRef, tArt
   if sWorld is empty then return empty
   if pW is empty then put 32 into pW
   if pH is empty then put 48 into pH
   put b2kClamp(pW, 4, 10000) into pW
   put b2kClamp(pH, 4, 10000) into pH
   put b2kNumberOr(pX, sOriginX) into pX
   put b2kNumberOr(pY, sOriginY) into pY
   put "b2kspawn_" & the milliseconds & "_" & random(1000000) into tName
   if sCamGroup is empty then
      create graphic (tName)
   else
      create graphic (tName) in group "b2kcam_view"
   end if
   put the long id of graphic (tName) into tRef
   if sCamGroup is not empty then put true into sInCam[tRef]
   set the style of tRef to "rectangle"
   set the filled of tRef to true
   set the foregroundColor of tRef to "20,20,24"
   set the backgroundColor of tRef to "70,130,220"
   set the width of tRef to pW
   set the height of tRef to pH
   set the loc of tRef to round(pX - b2kCamShiftX(tRef)) & "," & round(pY - b2kCamShiftY(tRef))
   put true into sSpawned[tRef]
   if pSheet is not empty and sSheetKeys[pSheet] is not empty then
      set the visible of tRef to false       -- the graphic is only the body host
      b2kSpriteNew pSheet, empty, pX, pY
      put the result into tArt
      if tArt is not empty then
         b2kSpriteBind tArt, tRef
      else
         set the visible of tRef to true     -- sprite failed: stay visible
      end if
   end if
   b2kPlayerAttach tRef   -- adds the capsule (tall rect -> vertical pill)
   return tRef
end b2kPlayerMake

-- Adopt an existing control (or sprite) as the player. A capsule body is
-- added if it has none -- then the controller also sets its material (low
-- friction); a body you made yourself is left exactly as you tuned it.
command b2kPlayerAttach pCtrl
   local tRef
   if sWorld is empty then exit b2kPlayerAttach
   put the long id of pCtrl into tRef
   put false into sPlayOwnBody
   if sBody[tRef] is empty then
      b2kAddCapsule tRef
      if sBody[tRef] is empty then exit b2kPlayerAttach   -- zero-sized control
      put true into sPlayOwnBody
      b2kSetFriction tRef, 0.08   -- low: walls must not glue the capsule
      b2kSetBounce tRef, 0        -- characters land DEAD: the default 0.2
                                  -- restitution rebounded every landing
                                  -- (~13px hop = double land ticks/sounds)
   end if
   put tRef into sPlayRef
   b2kSetFixedRotation tRef, true
   b2kSetSleepEnabled tRef, false   -- a player must always respond
   put (the width of tRef) / 2 into sPlayHalfW
   put (the height of tRef) / 2 into sPlayHalfH
   put (the height of tRef) into sPlayStandH   -- full height, for the duck reshape
   put "idle" into sPlayState
   put 1 into sPlayFacing
   put false into sPlayGrounded
   put 0 into sPlayGroundMS
   put 0 into sPlayPressMS
   put false into sPlayJumping
   put true into sPlayControl
   put 0 into sPlayHoldMS
   put 0 into sPlayClock
   put 0 into sPlayAir
   put empty into sPlayAnimNow
   put empty into sPlayFlipNow
   -- Wave 2 state starts clean (ladder ZONES survive an attach: they are
   -- world geometry, registered before or after the player exists)
   put 0 into sPlayPX
   put 0 into sPlayPY
   put false into sPlayOnOneWay
   put 0 into sPlayDropUntil
   put 0 into sPlayDropHard
   put empty into sPlayDropMask
   put false into sPlayClimb
   put empty into sPlayGravSave
   put false into sPlaySwim
   put empty into sPlaySwimGravSave
   put false into sPlayHurt
   put 0 into sPlayHurtEnd
   put 0 into sPlayHurtHalf
   put 0 into sPlayHurtLand
   put 0 into sPlayInvulnUntil
   -- Wave 5 state starts clean (the knobs decide whether each is reachable)
   put 0 into sPlayAirJumpsLeft
   put 0 into sPlayWall
   put false into sPlayWallSliding
   put 0 into sPlayWallLockUntil
   put false into sPlayDash
   put 0 into sPlayDashEnd
   put 0 into sPlayDashReady
   put 0 into sPlayDashDir
   put empty into sPlayDashGravSave
   put false into sPlayDucked
   put empty into sPlayGroundBody
   put false into sPlayInLad
   put false into sPlayInWat
   if sPlayLadN is empty then put 0 into sPlayLadN
   b2kPlayerTuneCache   -- bake the knobs + probe geometry for the tick
   b2kPlayerResolveArt
   b2kInputOn   -- arms the sampler; starter bindings fill empty slots only
end b2kPlayerAttach

-- Internal: which control's animations the controller drives -- the
-- player itself when it is a sprite, else the first sprite bound to it.
command b2kPlayerResolveArt
   local tRef
   put empty into sPlayArt
   if sPlayRef is empty then exit b2kPlayerResolveArt
   if sSprSheet[sPlayRef] is not empty then
      put sPlayRef into sPlayArt
      exit b2kPlayerResolveArt
   end if
   repeat for each line tRef in sSprRefs
      if sSprBind[tRef] is sPlayRef then
         put tRef into sPlayArt
         exit b2kPlayerResolveArt
      end if
   end repeat
end b2kPlayerResolveArt

-- Tuning knobs (pixels, px/s, ms, degrees). Keys: moveSpeed, accel,
-- airAccel, jumpSpeed, jumpCut, coyoteMs, bufferMs, maxFall, maxSlopeDeg,
-- dropMs (drop-through window), climbSpeed (ladder px/s), swimSpeed/
-- swimJump (water px/s + stroke), swimGravity/swimMaxFall (buoyancy),
-- hurtPopX/hurtPopY (knockback launch px/s), hurtMs (control-off span),
-- invulnMs (post-hurt mercy). Wave 5, all OPT-IN (default = off): airJumps
-- (extra mid-air jumps; 1 = double-jump), wallJumpX/wallJumpY (wall-jump
-- launch px/s) + wallSlideMax (capped slide fall px/s), dashSpeed/dashMs/
-- dashCooldownMs (the dash; bind the "dash" action), duckScale (ducked
-- capsule height as a fraction of standing, <1 to crawl), platformCarry
-- (1 = ride moving platforms). Settable any time, before or after the
-- player exists; unknown keys are stored verbatim for your own use.
command b2kPlayerSet pKey, pValue
   put pValue into sPlayTune[toLower(pKey)]
   b2kPlayerTuneCache
end b2kPlayerSet

-- Internal: resolve the knobs into flat locals ONCE per change -- the
-- tick reads these every frame and must not pay name lookups for them.
command b2kPlayerTuneCache
   put b2kPlayerGet("moveSpeed") into sPlayMoveSpd
   put b2kPlayerGet("accel") into sPlayAccelG
   put b2kPlayerGet("airAccel") into sPlayAccelA
   put b2kPlayerGet("jumpSpeed") into sPlayJumpSpd
   put b2kPlayerGet("jumpCut") into sPlayJumpCut
   put b2kPlayerGet("coyoteMs") into sPlayCoyote
   put b2kPlayerGet("bufferMs") into sPlayBuffer
   put b2kPlayerGet("maxFall") into sPlayMaxFall
   put b2kPlayerGet("dropMs") into sPlayDropMS
   put b2kPlayerGet("climbSpeed") into sPlayClimbSpd
   put b2kPlayerGet("swimSpeed") into sPlaySwimSpd
   put b2kPlayerGet("swimJump") into sPlaySwimJump
   put b2kPlayerGet("swimGravity") into sPlaySwimGrav
   put b2kPlayerGet("swimMaxFall") into sPlaySwimMaxFall
   put b2kPlayerGet("hurtPopX") into sPlayHurtPopX
   put b2kPlayerGet("hurtPopY") into sPlayHurtPopY
   put b2kPlayerGet("hurtMs") into sPlayHurtMS
   put b2kPlayerGet("invulnMs") into sPlayInvulnMS
   -- Wave 5 knob caches + the one-compare gates the tick reads
   put b2kPlayerGet("airJumps") into sPlayAirJumps
   put b2kPlayerGet("wallJumpX") into sPlayWallJumpX
   put b2kPlayerGet("wallJumpY") into sPlayWallJumpY
   put b2kPlayerGet("wallSlideMax") into sPlayWallSlideMax
   put (sPlayWallJumpX > 0 or sPlayWallSlideMax > 0) into sPlayWallOn
   put b2kPlayerGet("dashSpeed") into sPlayDashSpd
   put b2kPlayerGet("dashMs") into sPlayDashMS
   put b2kPlayerGet("dashCooldownMs") into sPlayDashCool
   put (b2kPlayerGet("airDash") is not 0) into sPlayAirDash
   put b2kPlayerGet("duckScale") into sPlayDuckScale
   put (b2kPlayerGet("platformCarry") is not 0) into sPlayCarry
   put cos(b2kPlayerGet("maxSlopeDeg") * kPI / 180) into sPlayCosSlope
   if sPlayHalfW is not empty and sPlayHalfW > 0 then
      put sPlayHalfH + 4 into sPlayReach
      put (0 - max(2, sPlayHalfW * 0.6)) & comma & 0 & comma & max(2, sPlayHalfW * 0.6) into sPlayProbeOffs
   end if
end b2kPlayerTuneCache

function b2kPlayerGet pKey
   local tDef
   put toLower(pKey) into pKey
   put b2kPlayerDefault(pKey) into tDef
   if sPlayTune[pKey] is empty then return tDef
   -- known keys are numeric: a garbage value must not break the tick
   if tDef is not empty then return b2kNumberOr(sPlayTune[pKey], tDef)
   return sPlayTune[pKey]
end b2kPlayerGet

-- Internal: the defaults (spec section 6 -- a 32x48 px player, scale 40).
function b2kPlayerDefault pKey
   switch pKey
      case "movespeed"
         return 220
      case "accel"
         return 1800
      case "airaccel"
         return 1100
      case "jumpspeed"
         return 460
      case "jumpcut"
         return 0.45
      case "coyotems"
         return 90
      case "bufferms"
         return 110
      case "maxfall"
         return 900
      case "maxslopedeg"
         return 50
      case "dropms"
         return 260
      case "climbspeed"
         return 160
      case "swimspeed"
         return 150
      case "swimjump"
         return 300
      case "swimgravity"
         return 0.35
      case "swimmaxfall"
         return 150
      case "hurtpopx"
         return 220
      case "hurtpopy"
         return 320
      case "hurtms"
         return 700
      case "invulnms"
         return 900
      -- Wave 5 (all OPT-IN: these defaults disable the feature, so an
      -- untouched controller behaves exactly as it did before Wave 5)
      case "airjumps"
         return 0          -- extra mid-air jumps (1 = double-jump)
      case "walljumpx"
         return 0          -- away-from-wall launch px/s (0 = wall system off)
      case "walljumpy"
         return 0          -- up launch off a wall (0 = fall back to jumpSpeed)
      case "wallslidemax"
         return 0          -- capped fall px/s while hugging a wall (0 = no slide)
      case "dashspeed"
         return 0          -- dash px/s (0 = dash off)
      case "dashms"
         return 160        -- dash duration
      case "dashcooldownms"
         return 500        -- minimum gap between dashes
      case "airdash"
         return 1          -- 1 = dash works mid-air too; 0 = dash only when grounded
      case "duckscale"
         return 1          -- ducked capsule height / standing height (1 = no reshape)
      case "platformcarry"
         return 0          -- 1 = inherit a moving platform's velocity (opt-in: it
                           -- costs 2 reads/grounded-frame and changes how a player
                           -- rides any kinematic body), 0 = off
   end switch
   return empty
end b2kPlayerDefault

-- Map the controller's states to the art's animations (empty leaves that
-- state alone; pFall defaults to pJump). pLand is an optional non-looping
-- touch-down flourish: the controller holds it for its own duration, then
-- idle/run resume. NOTE: a finishing land animation dispatches the art's
-- b2kSpriteOnFinish message like any non-looping animation would.
-- Wave 2 slots (all optional, so old five-argument calls keep working):
-- pDuck falls back to the idle pose, pClimb and pHurt to the jump pose;
-- the Wave 4 pSwim falls back to the fall pose -- sheets without those
-- frames still read correctly. Wave 5 slots: pWall (wall-slide) falls back
-- to the fall pose, pDash falls back to the run pose.
command b2kPlayerAnims pIdle, pRun, pJump, pFall, pLand, pDuck, pClimb, pHurt, pSwim, pWall, pDash
   put pIdle into sPlayAnims["idle"]
   put pRun into sPlayAnims["run"]
   put pJump into sPlayAnims["jump"]
   if pFall is empty then
      put pJump into sPlayAnims["fall"]
   else
      put pFall into sPlayAnims["fall"]
   end if
   put pLand into sPlayAnims["land"]
   if pDuck is empty then
      put pIdle into sPlayAnims["duck"]
   else
      put pDuck into sPlayAnims["duck"]
   end if
   if pClimb is empty then
      put pJump into sPlayAnims["climb"]
   else
      put pClimb into sPlayAnims["climb"]
   end if
   if pHurt is empty then
      put pJump into sPlayAnims["hurt"]
   else
      put pHurt into sPlayAnims["hurt"]
   end if
   if pSwim is empty then
      put sPlayAnims["fall"] into sPlayAnims["swim"]
   else
      put pSwim into sPlayAnims["swim"]
   end if
   if pWall is empty then
      put sPlayAnims["fall"] into sPlayAnims["wallslide"]
   else
      put pWall into sPlayAnims["wallslide"]
   end if
   if pDash is empty then
      put sPlayAnims["run"] into sPlayAnims["dash"]
   else
      put pDash into sPlayAnims["dash"]
   end if
   put empty into sPlayAnimNow   -- re-assert on the next tick
   if sPlayArt is empty then b2kPlayerResolveArt
end b2kPlayerAnims

function b2kPlayer
   return sPlayRef
end b2kPlayer

-- The art control the controller animates (empty = none resolved yet).
function b2kPlayerSprite
   return sPlayArt
end b2kPlayerSprite

-- Grounded this frame (post-tick; false on the frame a jump launches).
function b2kPlayerOnGround
   return (sPlayGrounded is true)
end b2kPlayerOnGround

-- idle | run | jump | fall | duck | climb | hurt | swim | wallslide | dash,
-- plus "land" for exactly one frame on touch-down from jump/fall (dust
-- puffs, landing sounds). A drop-through renders as "fall". The Wave 5
-- states (wallslide, dash) only appear when their knobs are enabled.
-- Empty = no player.
function b2kPlayerState
   return sPlayState
end b2kPlayerState

function b2kPlayerFacing
   if sPlayFacing is -1 then return -1
   return 1
end b2kPlayerFacing

-- The capsule's CURRENT half-extents in px (the half-height drops while
-- the player is in a reshaped duck/crawl). Head-reach logic should read
-- these live rather than bake a constant (gotcha 28: a hitbox taller than
-- the visible art bumps things the head never touches).
function b2kPlayerHalfH
   return b2kNumberOr(sPlayHalfH, 0)
end b2kPlayerHalfH

function b2kPlayerHalfW
   return b2kNumberOr(sPlayHalfW, 0)
end b2kPlayerHalfW

-- This frame's ladder / water zone membership (the controller computes
-- these every tick anyway -- read them for "press UP to climb" prompts,
-- splash effects, breath meters, without recomputing the rects yourself).
function b2kPlayerInLadder
   return (sPlayInLad is true)
end b2kPlayerInLadder

function b2kPlayerInWater
   return (sPlayInWat is true)
end b2kPlayerInWater

-- Programmatic jump (springs, double-jump powerups): the same launch as a
-- pressed jump but WITHOUT the grounded/coyote gate -- the caller decides
-- when it is allowed. Uses the jumpSpeed knob unless given a speed.
command b2kPlayerJump pSpeed
   local tVel
   if sPlayRef is empty or sBody[sPlayRef] is empty then exit b2kPlayerJump
   if pSpeed is empty then put b2kPlayerGet("jumpSpeed") into pSpeed
   set the itemDelimiter to comma
   put b2kVelocity(sPlayRef) into tVel
   b2kSetVelocity sPlayRef, item 1 of tVel, 0 - pSpeed
   put true into sPlayJumping
   put 0 into sPlayGroundMS   -- consume coyote: no free second jump
   put 0 into sPlayPressMS    -- ...and any buffered press
end b2kPlayerJump

-- Register a ladder ZONE (screen-px rect, any corner order). While the
-- player's centre is inside one, UP enters the climb state (DOWN too,
-- when airborne -- walk off a platform and grab); gravity parks at 0,
-- y runs at climbSpeed off the moveY axis (0 = hang), x at half speed.
-- JUMP exits with a normal jump; leaving the zone (or climbing down
-- onto ground) restores gravity. Zones are pure polled geometry -- no
-- physics objects -- and are WORLD state: b2kClear wipes them.
-- TIP: run the zone a little above a platform at the ladder's top, so
-- walking off that edge while holding DOWN grabs the ladder.
command b2kPlayerAddLadder pX1, pY1, pX2, pY2
   if pX1 is not a number or pY1 is not a number \
         or pX2 is not a number or pY2 is not a number then exit b2kPlayerAddLadder
   if sPlayLadN is empty then put 0 into sPlayLadN
   add 1 to sPlayLadN
   put min(pX1, pX2) into sPlayLadL[sPlayLadN]
   put max(pX1, pX2) into sPlayLadR[sPlayLadN]
   put min(pY1, pY2) into sPlayLadT[sPlayLadN]
   put max(pY1, pY2) into sPlayLadB[sPlayLadN]
end b2kPlayerAddLadder

-- Register a water ZONE (screen-px rect, any corner order). While the
-- player's centre is inside one, the controller SWIMS: gravity drops to
-- swimGravity (buoyant), the sink caps at swimMaxFall, UP/DOWN swim at
-- swimSpeed, and JUMP is a repeatable upward STROKE (swimJump) -- no
-- ground needed. Leaving the zone restores gravity. Pure polled geometry,
-- WORLD state (b2kClear wipes them), exactly like the ladder zones.
-- TIP: top the zone a little ABOVE the water's surface tiles, so the dive
-- in and the surface-out break the water where the surface art sits.
command b2kPlayerAddWater pX1, pY1, pX2, pY2
   if pX1 is not a number or pY1 is not a number \
         or pX2 is not a number or pY2 is not a number then exit b2kPlayerAddWater
   if sPlayWatN is empty then put 0 into sPlayWatN
   add 1 to sPlayWatN
   put min(pX1, pX2) into sPlayWatL[sPlayWatN]
   put max(pX1, pX2) into sPlayWatR[sPlayWatN]
   put min(pY1, pY2) into sPlayWatT[sPlayWatN]
   put max(pY1, pY2) into sPlayWatB[sPlayWatN]
end b2kPlayerAddWater

-- The knockback standard (spec section 9.4): control off, an away-pop
-- (the sign of pFromX vs the player picks the direction; no/empty
-- pFromX pops away from the facing), the hurt anim, control restored
-- after hurtMs OR the first landing after half of it -- whichever is
-- LATER -- then an invulnMs mercy window during which this command
-- no-ops and b2kPlayerHurtIs() stays true (skip your hazard checks).
-- Games keep their respawn flow for LETHAL hits (pits, kill planes):
-- contact damage knocks back, falling dies -- the Wave 2 split.
command b2kPlayerHurt pFromX
   local tDir
   if sPlayRef is empty or sBody[sPlayRef] is empty then exit b2kPlayerHurt
   if b2kPlayerHurtIs() then exit b2kPlayerHurt          -- mercy window
   if sPlayControl is not true then exit b2kPlayerHurt   -- a cutscene owns the body
   if sPlayClimb is true then b2kPlayerClimbEnd sBody[sPlayRef]
   if sPlaySwim is true then b2kPlayerSwimEnd sBody[sPlayRef]
   if sPlayDash is true then b2kPlayerDashEnd sBody[sPlayRef]
   if pFromX is a number then
      if pFromX > sPlayPX then
         put -1 into tDir
      else
         put 1 into tDir
      end if
   else
      put 0 - sPlayFacing into tDir   -- pop back off whatever was ahead
   end if
   -- the pop rides the jump flag, like b2kPlayerJump: a raw upward
   -- set-velocity on a grounded player reads as solver rebound and gets
   -- ground-snapped to zero (gotcha 16)
   b2kSetVelocity sPlayRef, tDir * sPlayHurtPopX, 0 - sPlayHurtPopY
   put true into sPlayJumping
   put true into sPlayHurt
   put 0 into sPlayHurtLand
   put sPlayClock + sPlayHurtMS into sPlayHurtEnd
   put sPlayClock + sPlayHurtMS / 2 into sPlayHurtHalf
   put false into sPlayGrounded
   put 0 into sPlayGroundMS   -- no coyote freebie off a knockback
   put 0 into sPlayPressMS
   put "hurt" into sPlayState
   put empty into sPlayAnimNow   -- assert the hurt anim this tick
end b2kPlayerHurt

-- True through the knockback AND the mercy window that follows it: the
-- one gate a game's hazard checks need (poll it before calling
-- b2kPlayerHurt -- though a hurt inside the window already no-ops).
function b2kPlayerHurtIs
   if sPlayHurt is true then return true
   if sPlayInvulnUntil is not empty and sPlayInvulnUntil > 0 and sPlayClock < sPlayInvulnUntil then return true
   return false
end b2kPlayerHurtIs

-- false = the controller only OBSERVES: ground/state/facing stay fresh
-- but it writes neither velocity nor animations (the maxFall clamp stays
-- live -- it is the character's terminal velocity). For cutscenes,
-- hit poses, scripted deaths; physics and the Kit run on.
command b2kPlayerControl pFlag
   put (pFlag is not false) into sPlayControl
   -- an EXPLICIT control call overrides a knockback in flight: the game
   -- is taking the body (cutscene, respawn). No mercy window is granted
   -- -- the game owns what happens next.
   if sPlayHurt is true then
      put false into sPlayHurt
      put 0 into sPlayHurtLand
   end if
   -- a dash parks gravity at 0 and is ended only by its own tick, which
   -- stops running when control goes off -- so end it here or the parked
   -- gravity (and the held vy) leak into the cutscene.
   if sPlayControl is not true and sPlayDash is true \
         and sPlayRef is not empty and sBody[sPlayRef] is not empty then
      b2kPlayerDashEnd sBody[sPlayRef]
   end if
   -- returning control must re-assert the state anim over any manual pose
   if sPlayControl then put empty into sPlayAnimNow
end b2kPlayerControl

-- Teleport the player to a screen-px point and reset it to a clean
-- standing idle: velocity zeroed; the jump/hurt/dash/climb/swim/drop/duck
-- state cleared; the air and air-jump budgets refreshed. This is the
-- respawn most games hand-roll (b2kMoveTo + b2kSetVelocity + clearing a
-- pile of flags) in one call. Tuning and zones are kept (world/config
-- state). Empty pX/pY reuse the current centre (an in-place reset).
command b2kPlayerRespawn pX, pY
   local tB
   if sPlayRef is empty or sBody[sPlayRef] is empty then exit b2kPlayerRespawn
   put sBody[sPlayRef] into tB
   if sPlayClimb is true then b2kPlayerClimbEnd tB
   if sPlaySwim is true then b2kPlayerSwimEnd tB
   if sPlayDash is true then b2kPlayerDashEnd tB
   if sPlayDropUntil is not empty and sPlayDropUntil > 0 then b2kPlayerDropRestore
   if sPlayDucked is true then b2kPlayerStandUp
   put b2kNumberOr(pX, sPlayPX) into pX
   put b2kNumberOr(pY, sPlayPY) into pY
   b2kMoveTo sPlayRef, pX, pY
   b2kSetVelocity sPlayRef, 0, 0
   put true into sPlayControl
   put false into sPlayJumping
   put false into sPlayHurt
   put 0 into sPlayHurtLand
   put 0 into sPlayInvulnUntil
   put false into sPlayGrounded
   put 0 into sPlayAir
   put 0 into sPlayWallLockUntil
   put false into sPlayWallSliding
   put sPlayAirJumps into sPlayAirJumpsLeft
   put "idle" into sPlayState
   put empty into sPlayAnimNow   -- re-assert the idle pose next tick
end b2kPlayerRespawn

-- Tear down the controller, tuning included. The body and sprite remain
-- yours: remove them with b2kRemove / b2kSpriteRemove as usual.
command b2kPlayerRemove
   b2kPlayerForget true
end b2kPlayerRemove

-- Internal: drop controller state. b2kClear passes false (tuning is
-- config and survives, like input bindings); teardown/remove pass true.
-- Ladder zones are WORLD state, so they go either way; a mid-climb or
-- mid-drop body gets its gravity scale and collision mask back first.
command b2kPlayerForget pFull
   if sPlayClimb is true and sPlayRef is not empty and sBody[sPlayRef] is not empty then
      b2kPlayerClimbEnd sBody[sPlayRef]
   end if
   if sPlaySwim is true and sPlayRef is not empty and sBody[sPlayRef] is not empty then
      b2kPlayerSwimEnd sBody[sPlayRef]
   end if
   if sPlayDash is true and sPlayRef is not empty and sBody[sPlayRef] is not empty then
      b2kPlayerDashEnd sBody[sPlayRef]
   end if
   if sPlayDropUntil is not empty and sPlayDropUntil > 0 then b2kPlayerDropRestore
   put empty into sPlayRef
   put empty into sPlayArt
   put empty into sPlayAnims
   put empty into sPlayState
   put false into sPlayGrounded
   put false into sPlayJumping
   put true into sPlayControl
   put 1 into sPlayFacing
   put 0 into sPlayGroundMS
   put 0 into sPlayPressMS
   put 0 into sPlayHoldMS
   put 0 into sPlayClock
   put 0 into sPlayAir
   put empty into sPlayAnimNow
   put empty into sPlayFlipNow
   put false into sPlayOnOneWay
   put 0 into sPlayDropUntil
   put 0 into sPlayDropHard
   put empty into sPlayDropMask
   put false into sPlayClimb
   put empty into sPlayGravSave
   put false into sPlaySwim
   put empty into sPlaySwimGravSave
   put false into sPlayHurt
   put 0 into sPlayHurtEnd
   put 0 into sPlayHurtHalf
   put 0 into sPlayHurtLand
   put 0 into sPlayInvulnUntil
   -- Wave 5 state (the body keeps any reshaped duck size -- it is yours
   -- now; b2kClear removes it, teardown removes everything)
   put 0 into sPlayAirJumpsLeft
   put 0 into sPlayWall
   put false into sPlayWallSliding
   put 0 into sPlayWallLockUntil
   put false into sPlayDash
   put 0 into sPlayDashEnd
   put 0 into sPlayDashReady
   put 0 into sPlayDashDir
   put empty into sPlayDashGravSave
   put false into sPlayDucked
   put empty into sPlayGroundBody
   put false into sPlayInLad
   put false into sPlayInWat
   put 0 into sPlayLadN
   put empty into sPlayLadL
   put empty into sPlayLadT
   put empty into sPlayLadR
   put empty into sPlayLadB
   put 0 into sPlayWatN
   put empty into sPlayWatL
   put empty into sPlayWatT
   put empty into sPlayWatR
   put empty into sPlayWatB
   if pFull is true then put empty into sPlayTune
end b2kPlayerForget

-- Internal: 3 short rays cast down from the capsule's bottom; ground is
-- any hit whose surface normal points up within maxSlopeDeg. The rays
-- start inside our own capsule, which Box2D structurally never reports
-- (Phase 0, S7) -- self-hits are impossible. Sets the grounded flag and
-- refreshes the coyote clock. While OUR jump is still ascending the
-- probe is skipped outright: it would otherwise re-ground on the launch
-- frame and report phantom landings while rising THROUGH a one-way
-- chain (the bridge route). Plain upward motion is NOT skipped -- running
-- up a slope moves the capsule upward while genuinely grounded.
command b2kPlayerProbe pBody, pVY
   local tX, tY, tOff
   put false into sPlayGrounded
   put false into sPlayOnOneWay
   put false into sPlayDropSeen
   put empty into sPlayGroundBody
   set the itemDelimiter to comma
   -- raw reads with the caller's body handle: the probe runs every
   -- frame, so it skips the ref->body lookup and the "x,y" string pack.
   -- The centre is stashed even when the rays are skipped -- the tick's
   -- ladder zone test and b2kPlayerHurt read it.
   put b2kToScreenX(b2BodyX(pBody)) into tX
   put b2kToScreenY(b2BodyY(pBody)) into tY
   put tX into sPlayPX
   put tY into sPlayPY
   if sPlayJumping is true and pVY < 0 then exit b2kPlayerProbe
   repeat for each item tOff in sPlayProbeOffs
      get b2kRayHit(tX + tOff, tY, tX + tOff, tY + sPlayReach)
      if sRayNY is not empty and sRayNY <= 0 - sPlayCosSlope then
         if sOneWayBody[sRayBodyH] is true then
            -- mid-drop, a one-way chain is NOT ground (or the controller
            -- would re-ground on the very platform it is leaving -- the
            -- phantom-ground lesson in reverse); remember the sighting:
            -- the window's restore logic waits for the capsule to clear
            if sPlayDropUntil > 0 then
               put true into sPlayDropSeen
               next repeat
            end if
            put true into sPlayOnOneWay   -- standing on a chain: drop eligible
         end if
         put true into sPlayGrounded
         put sRayBodyH into sPlayGroundBody  -- the platform under us (carry)
         put sRayNX into sPlayNormX          -- flat vs slope, for ground-snap
         put sPlayClock into sPlayGroundMS   -- the sim clock, not wall time
         exit b2kPlayerProbe
      end if
   end repeat
end b2kPlayerProbe

-- Internal: enter the climb -- gravity parks at 0 (the body's own scale
-- is saved and restored, so a game-tuned floatiness survives a ladder).
command b2kPlayerClimbStart pBody
   if sPlayClimb is true then exit b2kPlayerClimbStart
   put b2BodyGravityScale(pBody) into sPlayGravSave
   b2SetGravityScale pBody, 0
   put true into sPlayClimb
   put false into sPlayJumping
end b2kPlayerClimbStart

command b2kPlayerClimbEnd pBody
   if sPlayClimb is not true then exit b2kPlayerClimbEnd
   b2SetGravityScale pBody, b2kNumberOr(sPlayGravSave, 1)
   put empty into sPlayGravSave
   put false into sPlayClimb
end b2kPlayerClimbEnd

-- Internal: enter the swim -- gravity drops to swimGravity (buoyant; the
-- body's own scale is saved and restored, like the climb). Mutually
-- exclusive with the climb: the tick only ever starts one of them.
command b2kPlayerSwimStart pBody
   if sPlaySwim is true then exit b2kPlayerSwimStart
   put b2BodyGravityScale(pBody) into sPlaySwimGravSave
   b2SetGravityScale pBody, b2kNumberOr(sPlaySwimGrav, 0.35)
   put true into sPlaySwim
   put false into sPlayJumping
end b2kPlayerSwimStart

command b2kPlayerSwimEnd pBody
   if sPlaySwim is not true then exit b2kPlayerSwimEnd
   b2SetGravityScale pBody, b2kNumberOr(sPlaySwimGravSave, 1)
   put empty into sPlaySwimGravSave
   put false into sPlaySwim
end b2kPlayerSwimEnd

-- Internal: open the drop-through window -- take the reserved one-way
-- bit out of the player's mask so chains (alone) stop colliding.
command b2kPlayerDropStart
   local tS, tM
   put sShapeH[sPlayRef] into tS
   if tS is empty then exit b2kPlayerDropStart
   put b2ShapeFilterMask(tS) into tM
   -- Box2D's default mask reads back as 2^64-1, which neither xTalk's
   -- 32-bit bit ops nor the shim's 2^53 guard can round-trip: clamp to
   -- "all 32 kit bits" -- identical behaviour, every category this Kit
   -- can mint lives below 2^32
   if tM > 4294967295 then put 4294967295 into tM
   put tM into sPlayDropMask
   b2SetShapeFilter tS, b2ShapeFilterCategory(tS), tM bitAnd (bitNot 2147483648), b2ShapeFilterGroup(tS)
   put sPlayClock + sPlayDropMS into sPlayDropUntil
   put sPlayClock + sPlayDropMS * 4 into sPlayDropHard
   put sRayY into sPlayDropLineY   -- the grounding ray's hit = the surface line
end b2kPlayerDropStart

command b2kPlayerDropRestore
   local tS
   put 0 into sPlayDropUntil
   put 0 into sPlayDropHard
   put sShapeH[sPlayRef] into tS
   if tS is empty or sPlayDropMask is empty then exit b2kPlayerDropRestore
   b2SetShapeFilter tS, b2ShapeFilterCategory(tS), sPlayDropMask, b2ShapeFilterGroup(tS)
   put empty into sPlayDropMask
end b2kPlayerDropRestore

-- Internal (Wave 5): enter the dash -- gravity parks at 0 (saved/restored
-- like the climb) so the burst is a flat horizontal zip; the tick holds vx
-- at dashSpeed for dashMs, then b2kPlayerDashEnd restores gravity. The
-- cooldown (dashReady) gates the next start.
command b2kPlayerDashStart pBody
   if sPlayDash is true then exit b2kPlayerDashStart
   put b2BodyGravityScale(pBody) into sPlayDashGravSave
   b2SetGravityScale pBody, 0
   put true into sPlayDash
   put sPlayFacing into sPlayDashDir
   put sPlayClock + sPlayDashMS into sPlayDashEnd
   put sPlayClock + sPlayDashMS + sPlayDashCool into sPlayDashReady
   put false into sPlayJumping
end b2kPlayerDashStart

command b2kPlayerDashEnd pBody
   if sPlayDash is not true then exit b2kPlayerDashEnd
   b2SetGravityScale pBody, b2kNumberOr(sPlayDashGravSave, 1)
   put empty into sPlayDashGravSave
   put false into sPlayDash
end b2kPlayerDashEnd

-- Internal (Wave 5): a single horizontal ray toward the input/facing side.
-- A near-vertical hit within a capsule-width is a wall -> sPlayWall = the
-- side (-1 left, 1 right; 0 = none). Runs only while the wall system is on
-- AND the player is airborne, so the steady-state budget is untouched.
command b2kPlayerWallProbe pBody, pAxis
   local tDir
   put 0 into sPlayWall
   if pAxis is 0 then
      put sPlayFacing into tDir
   else
      put pAxis into tDir
   end if
   set the itemDelimiter to comma
   get b2kRayHit(sPlayPX, sPlayPY, sPlayPX + tDir * (sPlayHalfW + 4), sPlayPY)
   if sRayNX is not empty and abs(sRayNX) > 0.7 and abs(sRayNY) < 0.6 then
      put tDir into sPlayWall
   end if
end b2kPlayerWallProbe

-- Internal (Wave 5): enter/leave the reshaped crawl (only when duckScale
-- < 1). Entering shrinks the capsule FEET-ANCHORED (drop the centre by
-- half the height lost so the feet stay planted); standing waits for
-- headroom (a ray up from the crouched top), so a low ceiling keeps you
-- crawling. b2kReshape resets the material, so friction/bounce are re-set.
command b2kPlayerDuckSet pWantDuck
   local tNewH, tShift, tNeed
   if sPlayRef is empty then exit b2kPlayerDuckSet
   if pWantDuck is true then
      if sPlayDucked is true or sPlayDuckScale >= 1 then exit b2kPlayerDuckSet
      put max(8, round(sPlayStandH * sPlayDuckScale)) into tNewH
      put (sPlayStandH - tNewH) / 2 into tShift
      set the height of sPlayRef to tNewH
      b2kMoveTo sPlayRef, sPlayPX, sPlayPY + tShift
      b2kReshape sPlayRef, "capsule"
      b2kSetFriction sPlayRef, 0.08
      b2kSetBounce sPlayRef, 0
      put tNewH / 2 into sPlayHalfH
      put true into sPlayDucked
      b2kPlayerTuneCache   -- the probe reach follows the new (shorter) capsule
   else
      if sPlayDucked is not true then exit b2kPlayerDuckSet
      put sPlayStandH - (the height of sPlayRef) into tNeed
      set the itemDelimiter to comma
      get b2kRayHit(sPlayPX, sPlayPY - sPlayHalfH, sPlayPX, sPlayPY - sPlayHalfH - tNeed - 2)
      if sRayNY is not empty then exit b2kPlayerDuckSet   -- a ceiling: stay crawling
      b2kPlayerStandUp
   end if
end b2kPlayerDuckSet

-- Internal (Wave 5): restore the capsule to standing height, feet planted.
-- Used by the duck exit (with headroom) and by b2kPlayerRespawn (forced).
command b2kPlayerStandUp
   local tShift
   if sPlayDucked is not true or sPlayRef is empty then exit b2kPlayerStandUp
   put (sPlayStandH - (the height of sPlayRef)) / 2 into tShift
   set the height of sPlayRef to sPlayStandH
   b2kMoveTo sPlayRef, sPlayPX, sPlayPY - tShift
   b2kReshape sPlayRef, "capsule"
   b2kSetFriction sPlayRef, 0.08
   b2kSetBounce sPlayRef, 0
   put sPlayStandH / 2 into sPlayHalfH
   put false into sPlayDucked
   b2kPlayerTuneCache
end b2kPlayerStandUp

-- Internal: the per-frame controller. Loop order: input -> PLAYER ->
-- sprites -> camera, so it reads this frame's edges and the sprite tick
-- applies the anim it picks. Exits in one compare when unused. The
-- Wave 2 paths (drop window, ladders, hurt) each cost ONE compare per
-- frame while idle -- the tick's steady-state budget is unchanged.
command b2kPlayerTick
   local tNow, tDT, tB, tVX, tVY, tAxis, tAxisY, tTarget, tAcc, tStep
   local tPrevState, tWrite, tInZone, tDuck, tClimbJump, i, tInWater
   local tOnLift, tPVX, tPVY   -- Wave 5: platform-carry scratch
   if sPlayRef is empty then exit b2kPlayerTick
   put sBody[sPlayRef] into tB
   if tB is empty then exit b2kPlayerTick
   -- the controller's clock is SIM time: the coyote/buffer windows must
   -- mean the same number of frames on every machine (and stand still
   -- while paused/hand-stepped) -- wall-clock would not
   put sPlayClock + b2kClamp(sFrameMS, 0, 100) into sPlayClock
   put sPlayClock into tNow
   -- present velocity, screen-oriented px/s (positive vy = falling).
   -- Raw reads with the cached handle: this runs every frame, so skip
   -- the wrapper's ref lookup and "vx,vy" string round-trip (same math
   -- as b2kVelocity -- mind the y flip, gotcha 9).
   set the itemDelimiter to comma
   put b2BodyVX(tB) * sScale into tVX
   put 0 - (b2BodyVY(tB) * sScale) into tVY
   b2kPlayerProbe tB, tVY
   -- a touch of ground refills the air-jump budget (Wave 5; idle when
   -- airJumps is 0, the default)
   if sPlayGrounded is true then put sPlayAirJumps into sPlayAirJumpsLeft
   -- the drop window's bookkeeping runs UNGATED (a hurt or control-off
   -- mid-drop must never strand the mask without its one-way bit). The
   -- mask returns when the clock has run AND the capsule has cleared the
   -- line it dropped through -- a straddling restore would snap it back
   -- on top (chain contacts are one-sided, judged by the centroid) --
   -- with a hard 4x deadline for drops that land on something below.
   if sPlayDropUntil > 0 and tNow >= sPlayDropUntil then
      if (sPlayDropSeen is not true and sPlayPY - sPlayHalfH > sPlayDropLineY + 2) \
            or tNow >= sPlayDropHard then
         b2kPlayerDropRestore
      end if
   end if
   -- the hurt window runs its own clock: control comes back at hurtMs
   -- OR the first landing after half of it, whichever is LATER, and the
   -- mercy window starts then
   if sPlayHurt is true then
      if sPlayHurtLand is 0 and sPlayGrounded is true and tNow >= sPlayHurtHalf then
         put tNow into sPlayHurtLand
      end if
      if tNow >= sPlayHurtEnd and sPlayHurtLand > 0 then
         put false into sPlayHurt
         put tNow + sPlayInvulnMS into sPlayInvulnUntil
         put empty into sPlayAnimNow   -- re-assert the state anim
      end if
   end if
   put false into tWrite
   put false into tDuck
   put false into tOnLift
   if sPlayControl is true and sPlayHurt is not true then
      put sFrameMS / 1000 into tDT
      if tDT <= 0 then put 1 / 60 into tDT
      if tDT > 0.05 then put 0.05 into tDT
      put b2kAxis("moveX") into tAxis
      put b2kAxis("moveY") into tAxisY
      if tAxis is not 0 then
         if tAxis < 0 then
            put -1 into sPlayFacing
         else
            put 1 into sPlayFacing
         end if
      end if
      -- ladder + water presence: pure numeric compares on the probe's
      -- stashed centre; zero zones of a kind = one compare and out
      put false into tInZone
      if sPlayLadN > 0 then
         repeat with i = 1 to sPlayLadN
            if sPlayPX >= sPlayLadL[i] and sPlayPX <= sPlayLadR[i] \
                  and sPlayPY >= sPlayLadT[i] and sPlayPY <= sPlayLadB[i] then
               put true into tInZone
               exit repeat
            end if
         end repeat
      end if
      put false into tInWater
      if sPlayWatN > 0 then
         repeat with i = 1 to sPlayWatN
            if sPlayPX >= sPlayWatL[i] and sPlayPX <= sPlayWatR[i] \
                  and sPlayPY >= sPlayWatT[i] and sPlayPY <= sPlayWatB[i] then
               put true into tInWater
               exit repeat
            end if
         end repeat
      end if
      put tInZone into sPlayInLad   -- exposed by b2kPlayerInLadder/InWater
      put tInWater into sPlayInWat
      -- DASH (Wave 5): a flat horizontal burst that overrides normal
      -- movement for dashMs, then hands back. Idle in one compare when
      -- dashSpeed is 0; yields to climb/swim (it ends on entering either).
      if sPlayDash is true then
         if tNow >= sPlayDashEnd or tInWater is true or tInZone is true then
            b2kPlayerDashEnd tB
         else
            put sPlayDashDir into sPlayFacing   -- face the dash, not late input
            put sPlayDashDir * sPlayDashSpd into tVX
            put 0 into tVY
            put true into tWrite
         end if
      end if
      if sPlayDash is not true and sPlayDashSpd > 0 and tNow >= sPlayDashReady \
            and (sPlayAirDash is true or sPlayGrounded is true) \
            and sPlayClimb is not true and sPlaySwim is not true \
            and tInZone is not true and tInWater is not true \
            and b2kActionPressed("dash") then
         b2kPlayerDashStart tB
         put sPlayDashDir * sPlayDashSpd into tVX
         put 0 into tVY
         put true into tWrite
      end if
      -- everything below (climb/swim entry + the three movement modes) is
      -- suspended while a dash owns the body
      if sPlayDash is not true then
      if sPlayClimb is not true and sPlaySwim is not true and tInZone is true then
         -- enter: UP any time in-zone; DOWN only while AIRBORNE (a
         -- grounded DOWN is a duck -- or a drop-through on a chain)
         if tAxisY is -1 or (tAxisY is 1 and sPlayGrounded is not true) then
            b2kPlayerClimbStart tB
         end if
      end if
      if sPlaySwim is not true and sPlayClimb is not true and tInWater is true then
         b2kPlayerSwimStart tB   -- submerged: buoyant gravity, stroke to rise
      end if
      if sPlayClimb is true then
         if b2kActionPressed("jump") then
            -- JUMP exits with a normal jump. The same press edge is
            -- still "pressed" when the walk branch runs below this
            -- tick: tClimbJump keeps it from re-arming the buffer
            -- (one press must never pay for two jumps)
            b2kPlayerClimbEnd tB
            put 0 - sPlayJumpSpd into tVY
            put true into sPlayJumping
            put false into sPlayGrounded
            put 0 into sPlayGroundMS
            put 0 into sPlayPressMS
            put true into tClimbJump
            put true into tWrite
         else
            if tInZone is not true or (sPlayGrounded is true and tAxisY is 1) then
               -- slid out of the zone, or climbed down onto ground:
               -- gravity returns and (same tick) normal control resumes
               b2kPlayerClimbEnd tB
            else
               -- the climb drive: y runs at climbSpeed off the moveY
               -- axis (0 = hang), x at half speed, gravity parked at 0
               put tAxisY * sPlayClimbSpd into tVY
               put tAxis * sPlayMoveSpd / 2 into tTarget
               put sPlayAccelG * tDT into tStep
               if tVX < tTarget then
                  put min(tTarget, tVX + tStep) into tVX
               else
                  put max(tTarget, tVX - tStep) into tVX
               end if
               put true into tWrite
            end if
         end if
      end if
      if sPlaySwim is true then
         if tInWater is not true then
            b2kPlayerSwimEnd tB   -- surfaced / left the pool: gravity returns
         else
            -- horizontal: ease vx toward axis * swimSpeed (sluggish -- the
            -- air-accel rate gives the underwater drag)
            put tAxis * sPlaySwimSpd into tTarget
            put sPlayAccelA * tDT into tStep
            if tVX < tTarget then
               put min(tTarget, tVX + tStep) into tVX
            else
               put max(tTarget, tVX - tStep) into tVX
            end if
            -- vertical: a JUMP press is a repeatable upward STROKE (no
            -- ground gate -- the spec's water jump); else UP/DOWN swim at
            -- swimSpeed; else the reduced gravity sinks you, capped low
            if b2kActionPressed("jump") then
               put 0 - sPlaySwimJump into tVY
            else
               if tAxisY is not 0 then
                  put tAxisY * sPlaySwimSpd into tVY
               end if
            end if
            put true into tWrite
         end if
      end if
      if sPlayClimb is not true and sPlaySwim is not true then
         -- horizontal: accelerate vx toward axis * moveSpeed (air = airAccel)
         put tAxis * sPlayMoveSpd into tTarget
         -- DUCK: down on the ground. With duckScale < 1 the capsule
         -- reshapes to a CRAWL (slow movement, shorter hitbox -- so you
         -- can slip under a low gap); otherwise the Wave 2 duck brakes to
         -- a stop with the hitbox unchanged.
         if tAxisY is 1 and sPlayGrounded is true then
            put true into tDuck
            if sPlayDuckScale < 1 then
               b2kPlayerDuckSet true
               put tAxis * sPlayMoveSpd * 0.5 into tTarget   -- crawl, not brake
            else
               put 0 into tTarget
            end if
         end if
         if tDuck is not true and sPlayDucked is true then b2kPlayerDuckSet false
         -- PLATFORM CARRY (Wave 5): inherit the ground body's velocity so a
         -- moving platform carries you (static ground reads 0 -> no effect).
         -- A vertical lift's carry exempts the ground-snap below.
         if sPlayCarry is true and sPlayGrounded is true and sPlayGroundBody is not empty then
            put b2BodyVX(sPlayGroundBody) * sScale into tPVX
            put 0 - (b2BodyVY(sPlayGroundBody) * sScale) into tPVY
            add tPVX to tTarget
            if tPVY is not 0 and sPlayJumping is not true then
               put tPVY into tVY
               put true into tOnLift
            end if
         end if
         if sPlayGrounded then
            put sPlayAccelG into tAcc
         else
            put sPlayAccelA into tAcc
         end if
         -- a wall-jump owns vx briefly (sPlayWallLockUntil): skip the air
         -- steer so the away-launch carries clear before control resumes
         if tNow >= sPlayWallLockUntil then
            put tAcc * tDT into tStep
            if tVX < tTarget then
               put min(tTarget, tVX + tStep) into tVX
            else
               put max(tTarget, tVX - tStep) into tVX
            end if
         end if
         put true into tWrite
         if tClimbJump is not true and b2kActionPressed("jump") then put tNow into sPlayPressMS
         -- WALL slide (Wave 5; airborne only, one ray when the system is
         -- armed): hugging a wall while falling caps the fall at wallSlideMax
         put false into sPlayWallSliding
         if sPlayWallOn is true and sPlayGrounded is not true then
            b2kPlayerWallProbe tB, tAxis
            if sPlayWall is not 0 and tAxis is sPlayWall and tVY > 0 and sPlayWallSlideMax > 0 then
               if tVY > sPlayWallSlideMax then put sPlayWallSlideMax into tVY
               put true into sPlayWallSliding
            end if
         end if
         if tDuck is true then
            -- a press while crouched: on a ONE-WAY CHAIN it drops
            -- through (dropMs of no chain collision); on solid ground
            -- nothing -- and nothing later either, so the buffer is
            -- eaten (a crouch-press must not launch on release)
            if sPlayPressMS > 0 and tNow - sPlayPressMS <= sPlayBuffer then
               if sPlayOnOneWay is true and sPlayDropUntil is 0 then
                  b2kPlayerDropStart
                  put false into sPlayGrounded   -- falling from this frame on
                  put 0 into sPlayGroundMS       -- no coyote out of a drop
               end if
               put 0 into sPlayPressMS
            end if
         else
            -- a buffered press, in priority: WALL-JUMP > ground/coyote
            -- jump > air-jump (the double-jump). The wall and air branches
            -- idle (their knobs are 0) unless the game enables them.
            if sPlayPressMS > 0 and tNow - sPlayPressMS <= sPlayBuffer then
               if sPlayWallOn is true and sPlayWall is not 0 \
                     and sPlayGrounded is not true and sPlayWallJumpX > 0 then
                  -- WALL-JUMP: up + away from the wall, with a brief steer
                  -- lock so the launch carries before air control resumes
                  put sPlayWallJumpY into tStep
                  if tStep <= 0 then put sPlayJumpSpd into tStep
                  put 0 - tStep into tVY
                  put (0 - sPlayWall) * sPlayWallJumpX into tVX
                  put 0 - sPlayWall into sPlayFacing
                  put true into sPlayJumping
                  put tNow + 180 into sPlayWallLockUntil
                  put 0 into sPlayPressMS
               else
                  if sPlayGrounded or (sPlayGroundMS > 0 and tNow - sPlayGroundMS <= sPlayCoyote) then
                     put 0 - sPlayJumpSpd into tVY
                     put true into sPlayJumping
                     put false into sPlayGrounded   -- airborne from this frame on
                     put 0 into sPlayGroundMS       -- consume coyote
                     put 0 into sPlayPressMS        -- consume the buffer
                  else
                     if sPlayAirJumps > 0 and sPlayAirJumpsLeft > 0 then
                        -- DOUBLE / AIR JUMP: airborne, no ground or coyote
                        put 0 - sPlayJumpSpd into tVY
                        put true into sPlayJumping
                        subtract 1 from sPlayAirJumpsLeft
                        put 0 into sPlayPressMS
                     end if
                  end if
               end if
            end if
         end if
         -- jump-cut: releasing while still rising from OUR jump shortens it
         if sPlayJumping and tVY < 0 and b2kActionReleased("jump") then
            put tVY * sPlayJumpCut into tVY
            put false into sPlayJumping
         end if
      end if
      end if
   end if
   if sPlayJumping and tVY >= 0 then put false into sPlayJumping   -- apex
   -- terminal velocity: the low swimMaxFall is the buoyant sink cap while
   -- submerged; the normal maxFall (the character's terminal velocity) else
   if sPlaySwim is true then
      if tVY > sPlaySwimMaxFall then
         put sPlaySwimMaxFall into tVY
         put true into tWrite
      end if
   else
      if tVY > sPlayMaxFall then
         put sPlayMaxFall into tVY
         put true into tWrite
      end if
   end if
   -- GROUND-SNAP: grounded on FLAT ground, drifting upward, and we did
   -- not jump = the contact solver's push-out rebound after a hard
   -- landing (a ~7px hop: phantom airtime, double land ticks - measured
   -- by the self-test at vy 61 up). Kill it at the source. Slopes are
   -- exempt (|normalX| >= 0.1): running uphill is real upward motion.
   -- Climbs are exempt too: rising up a ladder from its grounded base
   -- is exactly the motion this guard exists to kill. External boosts
   -- must use b2kPlayerJump, which sets the jump flag (b2kPlayerHurt's
   -- pop rides the same flag).
   if sPlayGrounded and sPlayJumping is not true and sPlayClimb is not true \
         and sPlaySwim is not true and tOnLift is not true and tVY < 0 and abs(sPlayNormX) < 0.1 then
      put 0 into tVY
      put true into tWrite
   end if
   if tWrite then b2SetVelocity tB, tVX / sScale, 0 - (tVY / sScale)
   -- the state machine (land = exactly one tick on touch-down), with
   -- LANDING HYSTERESIS: the contact solver's push-out (and chain seams)
   -- can blip the 4px probe off for a tick around an impact -- without
   -- hysteresis that read as a second micro-fall and a second land tick
   -- (double land sounds; the self-test caught it). A touchdown counts
   -- as "land" only after a real airborne stretch (3+ ticks), and a
   -- single ungrounded blip does not even show as airborne -- unless it
   -- is OUR jump, which must read as "jump" on its launch frame.
   -- Hurt and climb OWN the state outright; a knockback's landing shows
   -- no "land" tick (the hit pose holds through the touchdown).
   put sPlayState into tPrevState
   if sPlayHurt is true then
      put "hurt" into sPlayState
      if sPlayGrounded is true then
         put 0 into sPlayAir
      else
         add 1 to sPlayAir
      end if
   else
      if sPlayClimb is true then
         put "climb" into sPlayState
         put 0 into sPlayAir
      else
         if sPlayGrounded is true then
            if (tPrevState is "jump" or tPrevState is "fall") and sPlayAir >= 3 then
               put "land" into sPlayState
            else
               if tDuck is true then
                  put "duck" into sPlayState
               else
                  if abs(tVX) < 8 then
                     put "idle" into sPlayState
                  else
                     put "run" into sPlayState
                  end if
               end if
            end if
            put 0 into sPlayAir
         else
            add 1 to sPlayAir
            if sPlayWallSliding is true then
               put "wallslide" into sPlayState   -- Wave 5: clinging a wall
            else
               if sPlayJumping is true or sPlayAir >= 2 then
                  if tVY < 0 then
                     put "jump" into sPlayState
                  else
                     put "fall" into sPlayState
                  end if
               end if
            end if
         end if
      end if
   end if
   -- swim OWNS the state while submerged: the machine above ran the
   -- grounded/airborne branch (sPlayClimb is false underwater), so override
   -- to "swim" and keep the air counter clear -- surfacing must never read
   -- as a long fall plus a phantom land tick.
   if sPlaySwim is true and sPlayHurt is not true then
      put "swim" into sPlayState
      put 0 into sPlayAir
   end if
   -- a dash OWNS the state outright (it yields to swim/climb, so it can
   -- never be underwater -- this safely overrides last)
   if sPlayDash is true then
      put "dash" into sPlayState
      put 0 into sPlayAir
   end if
   -- animations: only while controlling (manual poses own the art when
   -- control is off), and never let a vanished art control abort the
   -- frame -- the loop's ticks share one try block
   if sPlayControl is not true then exit b2kPlayerTick
   if sPlayAnims["idle"] is empty and sPlayAnims["run"] is empty then exit b2kPlayerTick
   try
      if sPlayArt is empty then b2kPlayerResolveArt
      if sPlayArt is not empty then b2kPlayerShowState tNow, tVX
   catch tErr
      put empty into sPlayArt   -- art gone; re-resolve next tick
   end try
end b2kPlayerTick

-- Internal: drive the art's animation and facing from the current state.
command b2kPlayerShowState pNow, pVX
   local tWant, tAnim, tAKey, tFPS, tFlip
   put sPlayState into tWant
   if pNow < sPlayHoldMS and tWant is not "jump" and tWant is not "fall" \
         and tWant is not "hurt" and tWant is not "climb" and tWant is not "swim" \
         and tWant is not "wallslide" and tWant is not "dash" then
      put empty into tAnim   -- mid land-flourish: leave it playing
   else
      if tWant is "land" and sPlayAnims["land"] is empty then
         -- no flourish mapped: land straight into idle or run, by speed
         if abs(pVX) < 8 then
            put "idle" into tWant
         else
            put "run" into tWant
         end if
      end if
      put sPlayAnims[tWant] into tAnim
   end if
   if tAnim is not empty and tAnim is not sPlayAnimNow then
      b2kSpritePlay sPlayArt, tAnim, (tWant is "land")
      put tAnim into sPlayAnimNow
      if tWant is "land" then
         -- hold the flourish for its own length (frames / fps)
         put sSprSheet[sPlayArt] & "|" & tAnim into tAKey
         put sAnimFPS[tAKey] into tFPS
         if tFPS is empty or tFPS <= 0 then put 8 into tFPS
         put pNow + (the number of lines of sAnimList[tAKey]) * 1000 / tFPS into sPlayHoldMS
      else
         put 0 into sPlayHoldMS
      end if
   end if
   put (sPlayFacing < 0) into tFlip
   if tFlip is not sPlayFlipNow then
      b2kSpriteFlipH sPlayArt, tFlip
      put tFlip into sPlayFlipNow
   end if
end b2kPlayerShowState

-- =====================================================================
-- Camera: a clipped viewport group the loop scrolls (proven in spike S9)
-- =====================================================================
-- While the camera is on, Kit-created controls (spawns and sprites) are
-- placed INSIDE the viewport group; their locs stay WORLD pixels, because
-- contents of a scrolled group keep their coordinates -- the body sync and
-- all physics math are untouched, the scroll is pure presentation. Chrome
-- stays on the card; anything behind the (transparent) group reads as an
-- infinite-distance parallax backdrop. Map mouse points with
-- b2kCamMouseX/Y. Level coordinates should start at 0,0: an invisible
-- anchor pins the group's content origin there, so scroll == view corner.
command b2kCamOn pRect
   local tG
   if sCamGroup is not empty then exit b2kCamOn
   put empty into sCamNote
   if pRect is empty then put the rect of this card into pRect
   try
      create group "b2kcam_view"
   catch tErr
      put "create group failed: " & tErr into sCamNote
      exit b2kCamOn
   end try
   put the long id of group "b2kcam_view" into tG
   try
      set the margins of tG to 0
      set the showBorder of tG to false
      set the hScrollbar of tG to false
      set the vScrollbar of tG to false
      create graphic "b2kcam_anchor" in group "b2kcam_view"
      set the rect of it to 0, 0, 1, 1
      set the visible of it to false
      set the lockLoc of tG to true
      set the rect of tG to pRect
   catch tErr
      put "viewport setup failed: " & tErr into sCamNote
      try
         delete group "b2kcam_view"
      catch tErr
      end try
      exit b2kCamOn
   end try
   try
      set the unboundedHScroll of tG to true
      set the unboundedVScroll of tG to true
   catch tErr
   end try
   -- NOTE: deliberately NOT layerMode "scrolling". The compositor caches
   -- that mode's content as one surface; past common GPU surface limits
   -- (~2048px) the cached world freezes while dynamic-layer sprites keep
   -- moving -- the player "runs off" a stopped picture. Plain rendering
   -- pans correctly at any level size.
   put tG into sCamGroup
   set the itemDelimiter to comma
   put ((item 1 of pRect) + (item 3 of pRect)) / 2 into sCamX
   put ((item 2 of pRect) + (item 4 of pRect)) / 2 into sCamY
   put 0.15 into sCamLerp
   put 0 into sCamDZW
   put 0 into sCamDZH
   put empty into sCamFollow
   put empty into sCamB1X
   put 0 into sCamShakeAmp
   put empty into sCamLastH
   put empty into sCamLastV
   -- self-test: prove the scroll property actually pans this group. The
   -- anchor is stretched first so content exceeds the view (engines clamp
   -- scroll to content bounds), then restored; failure is reported via
   -- b2kCamStatus instead of letting the player walk out of a frozen view.
   try
      set the rect of graphic "b2kcam_anchor" to 0, 0, 4000, 2000
      set the hScroll of sCamGroup to 7
      if the hScroll of sCamGroup is not 7 then
         put "group scroll is ineffective on this engine" into sCamNote
      end if
      set the hScroll of sCamGroup to 0
      set the rect of graphic "b2kcam_anchor" to 0, 0, 1, 1
   catch tErr
      put "setting the group scroll failed: " & tErr into sCamNote
   end try
   -- probe the engine's coordinate semantics for grouped controls: place a
   -- probe at x=100, scroll by 50, and read the loc back. Engines that
   -- report 50 give SCROLL-ADJUSTED (visual) locs -- every per-frame
   -- position write into the group must then subtract the live scroll, or
   -- the write cancels the pan and the control "outruns" the world.
   put false into sCamLocVisual
   try
      set the rect of graphic "b2kcam_anchor" to 0, 0, 4000, 2000
      create graphic "b2kcam_probe" in group "b2kcam_view"
      set the rect of it to 96, 96, 104, 104
      set the visible of it to false
      set the hScroll of sCamGroup to 50
      put ((item 1 of the loc of graphic "b2kcam_probe") is 50) into sCamLocVisual
      set the hScroll of sCamGroup to 0
      delete graphic "b2kcam_probe"
      set the rect of graphic "b2kcam_anchor" to 0, 0, 1, 1
   catch tErr
      put false into sCamLocVisual
   end try
   put 0 into sCamCurH
   put 0 into sCamCurV
   put empty into sInCam
   b2kCamApply
end b2kCamOn

-- Dissolve the viewport: children return to the card with their world locs.
command b2kCamOff
   if sCamGroup is empty then exit b2kCamOff
   try
      ungroup group "b2kcam_view"
   catch tErr
   end try
   if there is a graphic "b2kcam_anchor" then delete graphic "b2kcam_anchor"
   put empty into sCamGroup
   put false into sCamLocVisual
   put 0 into sCamCurH
   put 0 into sCamCurV
   put empty into sInCam
end b2kCamOff

function b2kCamIsOn
   return (sCamGroup is not empty)
end b2kCamIsOn

-- The viewport group's reference (empty when the camera is off) -- create
-- your own level controls inside it: create graphic "x" in b2kCamGroup().
function b2kCamGroup
   return sCamGroup
end b2kCamGroup

-- Move an existing control (IDE-designed levels) into the viewport.
command b2kCamAdopt pCtrl
   if sCamGroup is empty then exit b2kCamAdopt
   try
      relayer pCtrl to front of group "b2kcam_view"
   catch tErr
      -- no script relayer on this engine: the control stays on the card.
      -- Physics is unaffected; only its drawing will not scroll.
   end try
   -- mark AFTER the move: a long id embeds the group path, so the key
   -- must be the post-relayer id or the camera's write-compensation
   -- (b2kCamShiftX/Y) never recognises adopted controls
   try
      put true into sInCam[the long id of pCtrl]
   catch tErr
   end try
end b2kCamAdopt

command b2kCamFollow pCtrl, pLerp
   put the long id of pCtrl into sCamFollow
   if pLerp is a number then put b2kClamp(pLerp, 0.01, 1) into sCamLerp
end b2kCamFollow

command b2kCamUnfollow
   put empty into sCamFollow
end b2kCamUnfollow

-- Follow only once the target leaves a centre box (0 = always centre).
command b2kCamDeadzone pW, pH
   put b2kNumberOr(pW, 0) into sCamDZW
   put b2kNumberOr(pH, 0) into sCamDZH
end b2kCamDeadzone

command b2kCamBounds pX1, pY1, pX2, pY2
   put pX1 into sCamB1X
   put pY1 into sCamB1Y
   put pX2 into sCamB2X
   put pY2 into sCamB2Y
   -- stretch the invisible anchor across the whole level: the group's
   -- scrollable content then always spans the bounds, so the engine can
   -- never clamp the scroll short (works with or without unbounded scroll)
   if sCamGroup is not empty then
      try
         set the rect of graphic "b2kcam_anchor" to pX1, pY1, pX2, pY2
      catch tErr
      end try
   end if
end b2kCamBounds

command b2kCamGoto pX, pY
   put b2kNumberOr(pX, sCamX) into sCamX
   put b2kNumberOr(pY, sCamY) into sCamY
   b2kCamApply
end b2kCamGoto

function b2kCamPos
   return round(sCamX) & comma & round(sCamY)
end b2kCamPos

-- A decaying random view offset on top of the follow (impacts, blasts).
command b2kCamShake pAmpPx, pMs
   put b2kClamp(pAmpPx, 0, 200) into sCamShakeAmp
   put the milliseconds + b2kClamp(pMs, 0, 5000) into sCamShakeEnd
end b2kCamShake

-- The mouse in WORLD pixels (camera-aware) -- use these for b2kGrab,
-- spawning at the pointer, click-picking, instead of the mouseH/V.
function b2kCamMouseX
   if sCamGroup is empty then return the mouseH
   set the itemDelimiter to comma
   return the mouseH - (item 1 of the rect of sCamGroup) + the hScroll of sCamGroup
end b2kCamMouseX

function b2kCamMouseY
   if sCamGroup is empty then return the mouseV
   set the itemDelimiter to comma
   return the mouseV - (item 2 of the rect of sCamGroup) + the vScroll of sCamGroup
end b2kCamMouseY

-- Health: empty = camera fine (or simply off); otherwise the reason the
-- camera could not run properly (create-group/scroll failures). Check it
-- after b2kCamOn and degrade your level gracefully.
function b2kCamStatus
   return sCamNote
end b2kCamStatus

-- "visual" when this engine reports/sets grouped locs scroll-adjusted,
-- else "content". Diagnostic; the Kit compensates automatically.
function b2kCamLocSemantics
   if sCamLocVisual is true then return "visual"
   return "content"
end b2kCamLocSemantics

-- Internal: the scroll to subtract when WRITING a position into the
-- viewport on a visual-semantics engine (0 otherwise / outside it).
function b2kCamShiftX pRef
   if sCamLocVisual is not true then return 0
   if sInCam[pRef] is not true then return 0
   return sCamCurH
end b2kCamShiftX

function b2kCamShiftY pRef
   if sCamLocVisual is not true then return 0
   if sInCam[pRef] is not true then return 0
   return sCamCurV
end b2kCamShiftY

-- Move ANY sprite/control to a WORLD position, camera-correct (use this
-- instead of `set the loc` for things you animate by hand, like a patrol
-- path -- outside a camera it is a plain loc set).
command b2kSpriteMoveTo pCtrl, pX, pY
   local tRef
   put the long id of pCtrl into tRef
   set the loc of tRef to round(pX - b2kCamShiftX(tRef)) & comma & round(pY - b2kCamShiftY(tRef))
end b2kSpriteMoveTo

-- Internal, called by the loop each frame: chase the followed control. The
-- follow eases, but the target is GUARANTEED on screen: if it would leave
-- the view (fast falls, teleports, lerp lag), the camera snaps to it.
command b2kCamTick
   local tLoc, tTX, tTY, tHalfW, tHalfH
   if sCamGroup is empty then exit b2kCamTick
   if sCamFollow is not empty then
      try
         set the itemDelimiter to comma
         put the loc of sCamFollow into tLoc
         put (item 1 of tLoc) + b2kCamShiftX(sCamFollow) into tTX
         put (item 2 of tLoc) + b2kCamShiftY(sCamFollow) into tTY
         if abs(tTX - sCamX) > sCamDZW / 2 then
            put sCamX + sCamLerp * (tTX - sCamX) into sCamX
         end if
         if abs(tTY - sCamY) > sCamDZH / 2 then
            put sCamY + sCamLerp * (tTY - sCamY) into sCamY
         end if
         -- the never-offscreen guarantee (32 px inside the view edges)
         put ((item 3 of the rect of sCamGroup) - (item 1 of the rect of sCamGroup)) / 2 into tHalfW
         put ((item 4 of the rect of sCamGroup) - (item 2 of the rect of sCamGroup)) / 2 into tHalfH
         if abs(tTX - sCamX) > tHalfW - 32 then put tTX into sCamX
         if abs(tTY - sCamY) > tHalfH - 32 then put tTY into sCamY
      catch tErr
         put empty into sCamFollow   -- target vanished
      end try
   end if
   b2kCamApply
   -- reality check: prove the target is inside the view using the ACTUAL
   -- scroll properties (not internal state). If anything desynced them --
   -- an engine quirk, a missed write -- force the scroll directly.
   if sCamFollow is not empty then
      try
         set the itemDelimiter to comma
         put the loc of sCamFollow into tLoc
         put (item 1 of tLoc) + b2kCamShiftX(sCamFollow) - (the hScroll of sCamGroup) into tTX
         put ((item 3 of the rect of sCamGroup) - (item 1 of the rect of sCamGroup)) into tHalfW
         if tTX < 48 or tTX > tHalfW - 48 then
            set the hScroll of sCamGroup to round((item 1 of tLoc) - tHalfW / 2)
            put the hScroll of sCamGroup into sCamLastH
            put item 1 of tLoc into sCamX
         end if
      catch tErr
      end try
   end if
end b2kCamTick

-- Internal: clamp to bounds, add shake, write the scroll (skip when same).
command b2kCamApply
   local tVW, tVH, tHalfW, tHalfH, tX, tY, tH, tV, tNow
   if sCamGroup is empty then exit b2kCamApply
   set the itemDelimiter to comma
   put (item 3 of the rect of sCamGroup) - (item 1 of the rect of sCamGroup) into tVW
   put (item 4 of the rect of sCamGroup) - (item 2 of the rect of sCamGroup) into tVH
   put tVW / 2 into tHalfW
   put tVH / 2 into tHalfH
   put sCamX into tX
   put sCamY into tY
   if sCamB1X is not empty then
      if tX > sCamB2X - tHalfW then put sCamB2X - tHalfW into tX
      if tX < sCamB1X + tHalfW then put sCamB1X + tHalfW into tX
      if tY > sCamB2Y - tHalfH then put sCamB2Y - tHalfH into tY
      if tY < sCamB1Y + tHalfH then put sCamB1Y + tHalfH into tY
   end if
   -- write the clamped centre back: the follow math must ease against the
   -- view that is actually shown, or the camera lags invisibly at the
   -- bounds and the player outruns a scroll that has not started yet
   put tX into sCamX
   put tY into sCamY
   if sCamShakeAmp > 0 then
      put the milliseconds into tNow
      if tNow >= sCamShakeEnd then
         put 0 into sCamShakeAmp
      else
         put tX + (random(sCamShakeAmp * 2 + 1) - sCamShakeAmp - 1) into tX
         put tY + (random(sCamShakeAmp * 2 + 1) - sCamShakeAmp - 1) into tY
      end if
   end if
   put round(tX - tHalfW) into tH   -- content origin pinned at 0,0
   put round(tY - tHalfH) into tV
   if tH is not sCamLastH then
      set the hScroll of sCamGroup to tH
      put tH into sCamLastH
   end if
   if tV is not sCamLastV then
      set the vScroll of sCamGroup to tV
      put tV into sCamLastV
   end if
   put tH into sCamCurH
   put tV into sCamCurV
end b2kCamApply

-- =====================================================================
-- Audio: named sounds over audioClips + a script-side tone synthesizer
-- =====================================================================
-- Model: a sound is an AUDIOCLIP imported into the stack -- the one LC
-- sound path with no external media-layer dependency -- and plays by
-- name (`play audioClip`). The engine plays ONE clip at a time; a new
-- play cuts the previous. That is the classic LC limit, and it suits
-- short retro SFX (document it, don't fight it). b2kToneMake SYNTHESIZES
-- a clip in pure script (8-bit mono WAV at 22050 Hz, square or sine, a
-- comma list of note frequencies, per-note decay so notes never click),
-- so a self-contained example ships sound with ZERO asset files. Sounds
-- are assets that SURVIVE b2kTeardown -- clips are tiny and resets must
-- stay snappy; names are stable, so re-making replaces rather than
-- accumulates, and b2kSoundsWipe purges everything (it also sweeps
-- b2ksnd_ clips a dead session left in the stack). Failures degrade to
-- silence, never to errors: the first play that throws trips a
-- dead-flag and b2kSoundStatus() says why. The mute is a user
-- preference. There is no per-frame tick -- audio is purely
-- event-driven.

-- Import a WAV/AIFF/AU file as a named sound (replaces any same name).
command b2kSoundLoad pName, pPath
   local tClip, tCount
   if pName is empty then exit b2kSoundLoad
   if there is no file pPath then
      put "no such file: " & pPath into sSndNote
      exit b2kSoundLoad
   end if
   put "b2ksnd_" & pName into tClip
   try
      if there is an audioClip tClip then delete audioClip tClip
      put the number of audioClips of this stack into tCount
      import audioClip from file pPath
      if the number of audioClips of this stack > tCount then
         set the name of audioClip (tCount + 1) of this stack to tClip
         put tClip into sSndClip[pName]
      end if
   catch tErr
      put "import failed: " & tErr into sSndNote
   end try
end b2kSoundLoad

-- Synthesize a named sound: pFreqs is a comma list of note frequencies
-- in Hz (0 = a rest), each pMsPerNote long; pVolPct 0-100 (default 60);
-- pShape "square" (default -- retro/plucky) or "sine" (soft). About
-- 22 KB per second of audio, built once -- keep SFX short.
--   b2kToneMake "coin", "1319,1760", 36          -- a two-note blip
--   b2kToneMake "win", "523,659,784,1047", 110   -- a little fanfare
command b2kToneMake pName, pFreqs, pMsPerNote, pVolPct, pShape
   local tClip, tData, tPath, tCount, tF
   if pName is empty then exit b2kToneMake
   put "b2ksnd_" & pName into tClip
   put b2kClamp(pMsPerNote, 5, 2000) into pMsPerNote
   put b2kClamp(b2kNumberOr(pVolPct, 60), 0, 100) into pVolPct
   put empty into tData
   set the itemDelimiter to comma
   repeat for each item tF in pFreqs
      put b2kToneBytes(b2kNumberOr(word 1 of tF, 440), pMsPerNote, pVolPct, pShape) after tData
   end repeat
   if tData is empty then exit b2kToneMake
   put specialFolderPath("temporary") & "/b2ktone_" & the milliseconds & "_" & random(99999) & ".wav" into tPath
   put b2kWavWrap(tData) into URL ("binfile:" & tPath)
   try
      if there is an audioClip tClip then delete audioClip tClip
      put the number of audioClips of this stack into tCount
      import audioClip from file tPath
      if the number of audioClips of this stack > tCount then
         set the name of audioClip (tCount + 1) of this stack to tClip
         put tClip into sSndClip[pName]
      end if
   catch tErr
      put "import failed: " & tErr into sSndNote
   end try
   try
      delete file tPath
   catch tErr
   end try
end b2kToneMake

-- Internal: pMs of one note as 8-bit unsigned mono PCM at 22050 Hz,
-- with a linear decay across the note (clickless and plucky).
function b2kToneBytes pFreq, pMs, pVolPct, pShape
   local tRate, tN, tOut, i, tPhase, tStep, tAmp, tEnv, tS
   put 22050 into tRate
   put round(tRate * pMs / 1000) into tN
   if tN < 1 then return empty
   put pVolPct * 1.27 into tAmp   -- 0-100 -> 0-127 sample amplitude
   put pFreq / tRate into tStep
   put 0 into tPhase
   put empty into tOut
   repeat with i = 0 to tN - 1
      put tAmp * (1 - i / tN) into tEnv
      if pFreq <= 0 then
         put 0 into tS   -- a rest
      else
         if pShape is "sine" then
            put tEnv * sin(tPhase * 2 * kPI) into tS
         else
            if tPhase mod 1 < 0.5 then
               put tEnv into tS
            else
               put 0 - tEnv into tS
            end if
         end if
      end if
      put numToByte(round(128 + tS)) after tOut
      add tStep to tPhase
   end repeat
   return tOut
end b2kToneBytes

-- Internal: wrap raw 8-bit mono 22050 Hz samples in a WAV container.
function b2kWavWrap pData
   local tLen
   put the number of bytes in pData into tLen
   return "RIFF" & b2kLE32(36 + tLen) & "WAVE" & "fmt " & b2kLE32(16) \
         & b2kLE16(1) & b2kLE16(1) & b2kLE32(22050) & b2kLE32(22050) \
         & b2kLE16(1) & b2kLE16(8) & "data" & b2kLE32(tLen) & pData
end b2kWavWrap

-- Internal: little-endian byte packers (hand-rolled: no binaryEncode
-- format-letter portability worries).
function b2kLE16 pN
   return numToByte(pN mod 256) & numToByte(pN div 256 mod 256)
end b2kLE16

function b2kLE32 pN
   return numToByte(pN mod 256) & numToByte(pN div 256 mod 256) & numToByte(pN div 65536 mod 256) & numToByte(pN div 16777216 mod 256)
end b2kLE32

-- Play a named sound (cuts whatever is playing -- the audioClip model).
command b2kSound pName
   local tClip
   if sSndMute is true or sSndDead is true then exit b2kSound
   put sSndClip[pName] into tClip
   if tClip is empty then exit b2kSound
   try
      play audioClip tClip
   catch tErr
      put true into sSndDead   -- this engine can't play: silence, no spam
      put "play failed: " & tErr into sSndNote
   end try
end b2kSound

-- Loop a named sound until b2kSoundStop / the next play (ambience).
command b2kSoundLoop pName
   local tClip
   if sSndMute is true or sSndDead is true then exit b2kSoundLoop
   put sSndClip[pName] into tClip
   if tClip is empty then exit b2kSoundLoop
   try
      play audioClip tClip looping
   catch tErr
      put true into sSndDead
      put "play failed: " & tErr into sSndNote
   end try
end b2kSoundLoop

command b2kSoundStop
   try
      play stop
   catch tErr
   end try
end b2kSoundStop

-- Mute is a preference: it survives b2kTeardown and stack resets are up
-- to the caller (store it in a custom property if you want it saved).
command b2kSoundMute pFlag
   put (pFlag is true) into sSndMute
   if sSndMute then b2kSoundStop
end b2kSoundMute

function b2kSoundMuted
   return (sSndMute is true)
end b2kSoundMuted

-- The engine-GLOBAL output volume (the playLoudness, 0-100): it affects
-- every stack's audio, so games should expose it, not hardcode it.
command b2kSoundVolume pPct
   try
      set the playLoudness to round(b2kClamp(pPct, 0, 100))
   catch tErr
      put "volume failed: " & tErr into sSndNote
   end try
end b2kSoundVolume

function b2kSoundIsLoaded pName
   return (sSndClip[pName] is not empty)
end b2kSoundIsLoaded

-- Empty = healthy; otherwise the most recent reason audio degraded
-- (missing file, import failure, play failure). Plays never throw.
function b2kSoundStatus
   return sSndNote
end b2kSoundStatus

-- Internal: delete every Kit-made audioClip ("b2ksnd_" prefix -- catches
-- a dead session's leftovers too) and reset the registry. The dead-flag
-- resets (a fresh world may retry); the mute preference survives.
command b2kSoundsWipe
   local i, tName
   try
      play stop
   catch tErr
   end try
   repeat with i = the number of audioClips of this stack down to 1
      put the short name of audioClip i of this stack into tName
      if char 1 to 7 of tName is "b2ksnd_" then
         try
            delete audioClip i of this stack
         catch tErr
         end try
      end if
   end repeat
   put empty into sSndClip
   put false into sSndDead
   put empty into sSndNote
end b2kSoundsWipe

-- =====================================================================
-- The loop  (fixed timestep, generation-guarded; one screen lock per frame)
-- =====================================================================
-- The whole frame -- body sync, contact/sensor dispatch and the app's own
-- b2kFrame drawing -- runs inside a single lock screen / unlock screen so it
-- composites in ONE redraw (no tearing between bodies and the joints/HUD a user
-- draws on top). The try/catch guarantees the unlock even if a user handler
-- throws, so a faulty event handler can never leave the screen frozen.
on b2kStep pGen
   local tNow, tElapsed, tFixed, tNext
   if not sRunning then exit b2kStep
   if pGen is not sGen then exit b2kStep
   if sPaused is not true then
      put the milliseconds into tNow
      put (tNow - sLast) / 1000 into tElapsed
      put tNow into sLast
      add tElapsed to sAccum
      if sAccum > 0.20 then put 0.20 into sAccum
      put tElapsed * 1000 into sFrameMS
      put 1 / 60 into tFixed
      -- events are HARVESTED per fixed step into frame buffers: Box2D
      -- only exposes the LAST step's events, so a 2-step frame would
      -- lose the first step's pickups/stomps, and a 0-step frame would
      -- re-read (duplicate!) the previous step's. The buffers make the
      -- frame's event view exact either way.
      b2kEventsReset
      repeat while sAccum >= tFixed
         b2Step sWorld, tFixed, sSub
         b2kHarvestEvents
         subtract tFixed from sAccum
      end repeat
      if sDragging then
         -- camera-aware: b2kCamMouseX/Y fall back to the raw mouse when off
         b2MouseSetTarget sDragJoint, b2kToWorldX(b2kCamMouseX()), b2kToWorldY(b2kCamMouseY())
      end if
      lock screen
      try
         b2kSyncBodies         -- lock-free; this frame's single lock is held here
         b2kInputTick          -- keyboard sample, so b2kFrame sees this frame's edges
         b2kPlayerTick         -- reads the fresh edges, steers, picks the anim
         b2kSpritesTick        -- bound sprites follow bodies; animations advance
         b2kCamTick            -- viewport chases its target over the fresh locs
         b2kDispatchContacts
         b2kDispatchSensors
         if sFrameObj is not empty then dispatch "b2kFrame" to sFrameObj
      catch tErr               -- a user handler error must never freeze the screen
      end try
      unlock screen
   end if
   -- Pace the next step against what this frame consumed instead of a flat
   -- 16 ms scheduled AFTER the work: the flat delay made the real rate
   -- "timer cadence (~16.5 ms) plus frame cost", measured at ~50 fps under
   -- load in the Phase 0 spike. Clamp to 1..16 so a heavy frame reschedules
   -- immediately and an idle one never busy-loops.
   -- Reschedule with pGen (OUR generation), never the live sGen: if a user
   -- handler inside this frame tore the world down and restarted it (a
   -- level change from a sensor event), sGen is already the NEW loop's --
   -- rescheduling with it would clone the loop and double-step forever.
   -- With pGen, this stale instance's next tick fails the guard and dies.
   if sPaused is true then
      send ("b2kStep " & pGen) to me in 16 milliseconds
   else
      put 16 - (the milliseconds - tNow) into tNext
      if tNext < 1 then put 1 into tNext
      if tNext > 16 then put 16 into tNext
      send ("b2kStep " & pGen) to me in tNext milliseconds
   end if
end b2kStep

-- Advance exactly one fixed step, even while paused (drives a Step button).
command b2kStepOnce
   if not sRunning then exit b2kStepOnce
   b2kEventsReset
   b2Step sWorld, (1 / 60), sSub
   b2kHarvestEvents
   put 1000 / 60 into sFrameMS   -- a hand-stepped frame is one fixed step long
   if sDragging then
      b2MouseSetTarget sDragJoint, b2kToWorldX(b2kCamMouseX()), b2kToWorldY(b2kCamMouseY())
   end if
   lock screen
   try
      b2kSyncBodies
      b2kInputTick
      b2kPlayerTick
      b2kSpritesTick
      b2kCamTick
      b2kDispatchContacts
      b2kDispatchSensors
      if sFrameObj is not empty then dispatch "b2kFrame" to sFrameObj
   catch tErr
   end try
   unlock screen
end b2kStepOnce

-- Public, standalone-safe sync: locks the screen and always unlocks, even if a
-- draw throws. This is the "the loop is stopped, redraw by hand" entry point
-- (editors and build modes call it after spawning or moving things), so it must
-- FULL-SCAN: the move-event fast path only reports bodies a b2Step moved, and a
-- stopped world steps never - relying on it here would draw nothing at all.
-- The running loop instead holds one lock across the whole frame and calls the
-- lock-free, move-event-driven b2kSyncBodies directly.
command b2kSync
   lock screen
   try
      b2kSyncAllBodies
   catch tErr
   end try
   unlock screen
end b2kSync

command b2kSyncAll
   lock screen
   try
      b2kSyncAllBodies
   catch tErr
   end try
   unlock screen
end b2kSyncAll

-- Lock-free body sync (the caller owns the screen lock). Fast path: Box2D already
-- gives us the bodies that moved during the last step, so we use that event list
-- instead of scanning every tracked control and calling body-is-awake/x/y/angle
-- across the FFI for each one.
command b2kSyncBodies
   if sNeedFullSync is true then
      b2kSyncAllBodies
      put false into sNeedFullSync
      exit b2kSyncBodies
   end if

   local tN, i, tBody, tRef, tWx, tWy, tWa, tDead, tFell
   put empty into tDead
   put empty into tFell
   put b2BodiesUpdate(sWorld) into tN
   if tN <= 0 then exit b2kSyncBodies

   repeat with i = 1 to tN
      put b2BodyMoveBody(i) into tBody
      if tBody <= 0 then next repeat
      put sCtrl[tBody] into tRef
      if tRef is empty then next repeat
      if sStatic[tRef] is true then next repeat
      try
         put b2BodyMoveX(i) into tWx
         put b2BodyMoveY(i) into tWy
         -- the kill floor: a mover that fell below the line is queued for
         -- removal instead of drawn (the player is the game's to respawn).
         -- Zero extra scanning: falling bodies are, by definition, moving.
         if sKillY is not empty and tRef is not sPlayRef and b2kToScreenY(tWy) > sKillY then
            put tRef & cr after tFell
            next repeat
         end if
         if sRender[tRef] is "poly" or sRender[tRef] is "image" then
            put b2BodyMoveAngle(i) into tWa
         else
            put 0 into tWa
         end if
         b2kDrawBody tRef, tWx, tWy, tWa
      catch tErr
         put tRef & cr after tDead   -- control vanished; clean up below
      end try
   end repeat
   b2kPruneDeadRefs tDead
   repeat for each line tRef in tFell
      if tRef is empty then next repeat
      if sFrameObj is not empty then dispatch "b2kFell" to sFrameObj with tRef
      b2kRemove tRef
   end repeat
end b2kSyncBodies

-- Lock-free full scan (the caller owns the screen lock). Comprehensive fallback
-- for script-side edits that do not come from a Box2D step event (for example
-- changing a body type while paused).
command b2kSyncAllBodies
   local tRef, tBody, tWx, tWy, tWa, tDead
   put empty into tDead
   repeat for each key tRef in sBody
      if sStatic[tRef] is true then next repeat
      put sBody[tRef] into tBody
      if b2BodyIsAwake(tBody) is false then next repeat   -- asleep = at rest, skip redraw
      try
         put b2BodyX(tBody) into tWx
         put b2BodyY(tBody) into tWy
         if sRender[tRef] is "poly" or sRender[tRef] is "image" then
            put b2BodyAngle(tBody) into tWa
         else
            put 0 into tWa
         end if
         b2kDrawBody tRef, tWx, tWy, tWa
      catch tErr
         put tRef & cr after tDead   -- control vanished; clean up below
      end try
   end repeat
   b2kPruneDeadRefs tDead
end b2kSyncAllBodies

command b2kPruneDeadRefs pDead
   local d, tBody
   repeat for each line d in pDead
      if d is not empty then
         put sBody[d] into tBody
         if tBody is not empty then
            b2DestroyBody tBody
            delete variable sCtrl[tBody]
         end if
         -- drop every parallel entry, exactly like b2kRemove, so a vanished
         -- control leaves no stale state behind
         delete variable sBody[d]
         delete variable sShapeH[d]
         delete variable sRender[d]
         delete variable sVerts[d]
         delete variable sRad[d]
         delete variable sImgAngle[d]
         delete variable sStatic[d]
         delete variable sSpawned[d]
         delete variable sSensor[d]
         delete variable sDrawKey[d]
         delete variable sInCam[d]
      end if
   end repeat
end b2kPruneDeadRefs

command b2kDrawBody pRef, pWx, pWy, pWa
   local tSx, tSy, tKey
   switch sRender[pRef]
      case "poly"
         b2kDrawPoly pRef, pWx, pWy, pWa
         break
      case "ball"
         b2kDrawBall pRef, pWx, pWy
         break
      case "image"
         b2kDrawImage pRef, pWx, pWy, pWa
         break
      default
         put round(b2kToScreenX(pWx)) into tSx
         put round(b2kToScreenY(pWy)) into tSy
         put tSx & "," & tSy into tKey
         if sDrawKey[pRef] is tKey then exit b2kDrawBody
         set the loc of pRef to (tSx - b2kCamShiftX(pRef)) & "," & (tSy - b2kCamShiftY(pRef))
         put tKey into sDrawKey[pRef]
   end switch
end b2kDrawBody

command b2kDrawPoly pRef, pWx, pWy, pWa
   local c, s, p, pt, tPts, tFirst, tKey
   put round(b2kToScreenX(pWx)) & "," & round(b2kToScreenY(pWy)) & "," & round(pWa * 1800 / kPI) into tKey
   if sDrawKey[pRef] is tKey then exit b2kDrawPoly
   put cos(pWa) into c
   put sin(pWa) into s
   put empty into tPts
   put empty into tFirst
   local tOffX, tOffY
   put b2kCamShiftX(pRef) into tOffX
   put b2kCamShiftY(pRef) into tOffY
   repeat for each line p in sVerts[pRef]
      put b2kCorner(pWx, pWy, item 1 of p, item 2 of p, c, s) into pt
      if tOffX is not 0 or tOffY is not 0 then
         put ((item 1 of pt) - tOffX) & "," & ((item 2 of pt) - tOffY) into pt
      end if
      if tFirst is empty then put pt into tFirst
      put pt & cr after tPts
   end repeat
   put tFirst after tPts
   set the points of pRef to tPts
   put tKey into sDrawKey[pRef]
end b2kDrawPoly

command b2kDrawBall pRef, pWx, pWy
   local tRp, tSx, tSy, tKey
   put sRad[pRef] * sScale into tRp
   put round(b2kToScreenX(pWx)) into tSx
   put round(b2kToScreenY(pWy)) into tSy
   put tSx & "," & tSy & "," & round(tRp) into tKey
   if sDrawKey[pRef] is tKey then exit b2kDrawBall
   subtract b2kCamShiftX(pRef) from tSx
   subtract b2kCamShiftY(pRef) from tSy
   set the rect of pRef to round(tSx - tRp), round(tSy - tRp), round(tSx + tRp), round(tSy + tRp)
   put tKey into sDrawKey[pRef]
end b2kDrawBall

-- Position + rotate an image control to follow its body. The body angle is in
-- radians, CCW-positive in the sim's y-up frame; with this kit's y-flip that is
-- also a CCW screen rotation, which matches `the angle` (CCW-positive). We keep
-- the image at its design size and skip redundant re-rotations (each set of the
-- angle resamples the image, but always from the original, so there's no drift).
command b2kDrawImage pRef, pWx, pWy, pWa
   local tDeg, tSx, tSy, tKey
   put ((round(pWa * 180 / kPI) mod 360) + 360) mod 360 into tDeg
   put round(b2kToScreenX(pWx)) into tSx
   put round(b2kToScreenY(pWy)) into tSy
   put tSx & "," & tSy & "," & tDeg into tKey
   if sDrawKey[pRef] is tKey then exit b2kDrawImage
   if sImgAngle[pRef] is not tDeg then
      set the angle of pRef to tDeg
      put tDeg into sImgAngle[pRef]
   end if
   set the loc of pRef to (tSx - b2kCamShiftX(pRef)) & "," & (tSy - b2kCamShiftY(pRef))
   put tKey into sDrawKey[pRef]
end b2kDrawImage

function b2kCorner pWx, pWy, pLx, pLy, c, s
   local rx, ry
   put pLx * c - pLy * s into rx
   put pLx * s + pLy * c into ry
   return round(b2kToScreenX(pWx + rx)) & "," & round(b2kToScreenY(pWy + ry))
end b2kCorner

-- Local-space outline (metres) approximating a capsule of half-length pL and
-- radius pR: two half-circle caps joined by straight edges. Built along local X
-- and transposed to local Y when the capsule is vertical. Used only to draw the
-- graphic; the collision shape is a true Box2D capsule.
function b2kCapsuleVerts pL, pR, pHoriz
   local tV, i, a, lx, ly
   local n
   put 8 into n
   put empty into tV
   repeat with i = 0 to n               -- right cap: -90 -> +90 degrees
      put (-90 + 180 * i / n) * kPI / 180 into a
      put pL + pR * cos(a) into lx
      put pR * sin(a) into ly
      if pHoriz then put lx & "," & ly & cr after tV
      else put ly & "," & lx & cr after tV
   end repeat
   repeat with i = 0 to n               -- left cap: +90 -> +270 degrees
      put (90 + 180 * i / n) * kPI / 180 into a
      put - pL + pR * cos(a) into lx
      put pR * sin(a) into ly
      if pHoriz then put lx & "," & ly & cr after tV
      else put ly & "," & lx & cr after tV
   end repeat
   return tV
end b2kCapsuleVerts

-- Internal: zero the frame's event buffers (the loop calls this before
-- it steps; the buffers then accumulate one harvest per fixed step).
command b2kEventsReset
   put 0 into sEvtCN
   put 0 into sEvtEN
   put 0 into sEvtSN
   put 0 into sEvtXN
end b2kEventsReset

-- Internal: pull THIS step's Box2D events into the frame buffers. Box2D
-- keeps only the latest step's events, so this must run after every
-- b2Step -- the dispatchers and pollers then see the whole frame.
command b2kHarvestEvents
   local tN, i
   put b2ContactsUpdate(sWorld) into tN
   repeat with i = 1 to tN
      add 1 to sEvtCN
      put b2ContactBeginBodyA(i) into sEvtCA[sEvtCN]
      put b2ContactBeginBodyB(i) into sEvtCB[sEvtCN]
   end repeat
   repeat with i = 1 to b2ContactEndCount()
      add 1 to sEvtEN
      put b2ContactEndBodyA(i) into sEvtEA[sEvtEN]
      put b2ContactEndBodyB(i) into sEvtEB[sEvtEN]
   end repeat
   put b2SensorsUpdate(sWorld) into tN
   repeat with i = 1 to tN
      add 1 to sEvtSN
      put b2ShapeBody(b2SensorBeginSensorShape(i)) into sEvtSS[sEvtSN]
      put b2ShapeBody(b2SensorBeginVisitorShape(i)) into sEvtSV[sEvtSN]
   end repeat
   repeat with i = 1 to b2SensorEndCount()
      add 1 to sEvtXN
      put b2ShapeBody(b2SensorEndSensorShape(i)) into sEvtXS[sEvtXN]
      put b2ShapeBody(b2SensorEndVisitorShape(i)) into sEvtXV[sEvtXN]
   end repeat
end b2kHarvestEvents

command b2kDispatchContacts
   local i, tA, tB
   if sContactObj is empty then exit b2kDispatchContacts
   repeat with i = 1 to sEvtCN
      put sCtrl[sEvtCA[i]] into tA
      put sCtrl[sEvtCB[i]] into tB
      dispatch "b2kContact" to sContactObj with tA, tB
   end repeat
   repeat with i = 1 to sEvtEN
      put sCtrl[sEvtEA[i]] into tA
      put sCtrl[sEvtEB[i]] into tB
      dispatch "b2kEndContact" to sContactObj with tA, tB
   end repeat
end b2kDispatchContacts

-- Deliver the frame's buffered sensor begin/end overlaps (if a target is
-- set) as on b2kSensorEnter / on b2kSensorExit, in step order.
command b2kDispatchSensors
   local i, tS, tV
   if sContactObj is empty then exit b2kDispatchSensors
   repeat with i = 1 to sEvtSN
      put sCtrl[sEvtSS[i]] into tS
      put sCtrl[sEvtSV[i]] into tV
      dispatch "b2kSensorEnter" to sContactObj with tS, tV
   end repeat
   repeat with i = 1 to sEvtXN
      put sCtrl[sEvtXS[i]] into tS
      put sCtrl[sEvtXV[i]] into tV
      dispatch "b2kSensorExit" to sContactObj with tS, tV
   end repeat
end b2kDispatchSensors
-- <<< END EMBEDDED KIT <<<
