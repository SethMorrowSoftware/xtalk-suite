# Expansion Prep — the asset dump & the content phase

> **ARCHIVED / HISTORICAL.** This was the pre-implementation *intake plan* for the
> asset pack and the Wave 0–8 content phases. Those waves shipped (the demo grew
> to seven levels); the as-built record is
> [`../../CHANGELOG.md`](../../CHANGELOG.md) + [`../../plan.md`](../../plan.md), and
> the content roadmap is [`../asset-expansion-plan.md`](../asset-expansion-plan.md).
> Kept for history only.

The Game Kit is **done and verified** (plan.md Phases 0–5, Win32). This
document is the intake plan for what comes next: a large Kenney spritesheet
pack, new **enemy types**, and new **player actions** — and the working rules
that keep the expansion as reliable as the engine underneath it.

| | |
|---|---|
| Baseline | Kit + games user-verified; self-test harness **v22, ~180 assertions across 37 test handlers, all pass** (current; Waves 1–7 all closed) |
| Assets | **LANDED (2026-06-11)** — Kenney's iconic platformer family, ~900 frames; Wave 0 catalogue below |
| Wave 1 | **COMPLETE — user-verified 2026-06-12** (the iconic-feel base; shipped as a three-level platformer, since grown to **five levels**; see §7) |
| Wave 2 | **COMPLETE — user-verified 2026-06-13** (player actions I; see §9) |
| Wave 3 | **COMPLETE — statically verified 2026-06-13** (bestiary I + HAUNTED HOLLOW; see §10) |
| Showcase polish | **COMPLETE — statically verified 2026-06-13** (pre-Wave-4: longer/re-spaced levels, the kit's first JOINT mechanics — rope bridge + boulder + barrel; a prototyped wrecking ball was cut as un-sprite-able — and four variety species; all example-side, zero Kit change, no harness bump) |
| Wave 4 | **COMPLETE — SWIM user play-tested in the platformer 2026-06-14** (see §11). The Kit gained `b2kPlayerAddWater` + a buoyant `swim` mode/state/anim; the platformer's L1 GREEN HILLS gained a **HILLTOP POOL** (a raised-bank basin — the swim showcase, where it's tested), tuned heavier and with the hero hitbox fixed to match the art (gotcha 28), all per the user's OXT pass. DONE: swim zones, lava (platformer L4), the collapsing bridge (now L4's lava crossing). |
| Wave 5 | **COMPLETE** (player actions II: double-jump `airJumps`, wall-slide/jump, dash, duck capsule-reshape, moving-platform carry — all opt-in Kit knobs, defaults unchanged; see §12). Enabled + showcased in the platformer; the **micro-game was retired here** (focus is the platformer). |
| Wave 6 | **COMPLETE — statically verified, merged** (bestiary II: frog hopper, barnacle lurking clam, spider ceiling-dropper — woven into L1/L2/L4). |
| Wave 7 | **COMPLETE — statically verified, merged** (the desert biome: **L5 SCORCHED DUNES** — the platformer's fifth level, sand/desert). |
| Wave 8 | **NOT STARTED** — builder cross-pollination (animated sprite parts + the player-as-a-part in the Contraption Builder); the only remaining roadmap item. |
| Next | Wave 8: the builder cross-pollination. |
| Companions | [plan.md](../../plan.md) (history/decision log) · [game-engine-spec.md](game-engine-spec.md) (module design) |

---

## 1. The asset dump: how to deliver it

- **Where:** new sheets go in `Spritesheets/` next to the existing four
  (characters / enemies / tiles / backgrounds, `-default` 1x and `-double` 2x).
- **Format:** PNG + Kenney **TextureAtlas XML** pairs load directly
  (`b2kSheetLoadAtlas`). Plain grids load with `b2kSheetLoad … fw, fh
  [,count, margin, spacing]`. Anything else (packed, no XML) loads with frame
  size 0 + `b2kSheetAddFrame` per region — **every layout is loadable**, so
  don't filter the pack; send everything that might be useful.
- **Licensing:** keep it CC0/Kenney-style; note the source pack names in the
  commit message.
- **Size note:** the repo carries the PNGs; the games load only the sheets
  they name, and frames slice lazily — a big pack costs disk, not runtime.

## 2. Wave 0 — the catalogue (intake COMPLETE, 2026-06-11)

The upload is Kenney's **iconic platformer family** — three compatible art
sets, ~900 usable frames. Inventory by sheet (names dumped from the XMLs;
all load with `b2kSheetLoadAtlas`):

### Family C — the 70px "classic" set (PRIMARY: richest gameplay art)

| Sheet | Frames | Contents |
|---|---|---|
| `tiles_sheet` | 172 | **Six terrain biomes** — grass, dirt, sand, snow, stone, castle — each a full autotile kit: `Mid/Left/Right/Center`, cliffs, **`Half*` thin platforms (one-ways!)**, **`Hill*` slopes**, ledges. Plus: ?-boxes (coin/item/explosive + used/disabled), brick walls, two bridges, **doors** (open/closed, 2 tiles), fences, **ladders** (`ladder_mid/top`), **liquids** (lava + water, surface + body tiles), **locks ×4 colours**, **ropes** (attached/horizontal/vertical), signs (incl. exit), hills (decor), torches, windows |
| `items_sheet` | 59 | **Buttons ×4 colours with `_pressed` art** (our polled plates, finally with faces), **lever switches** (`switchLeft/Mid/Right`), **springboards** (up/down), keys ×4, gems ×4, coins ×3 metals, star, **bomb + flash**, **fireball**, flags ×4 colours (incl. hanging), weight (+`weightChained` — thwomp art!), **brick particles** (debris for breakables), clouds/plants/decor |
| `enemies` | 100 | **25 species, most with `_dead`/`_hit` states**: barnacle (bite), **bat (fly + hang!)**, bee, fish ×2, fly, frog (leap), **ghost** (the Boo!), **grassBlock (disguised mimic!)**, ladybug, mouse, **piranha (`_down` — the pipe plant!)**, slime/slimeBlock/slimeBlue/slimeGreen (squashed states), snail (+shell), **snake / snakeLava / snakeSlime** (pit dwellers), spider (2-frame walk), **spinner + spinnerHalf** (spinning blades), worm |
| `enemies_sheet` | 18 | Simple set: **blocker (body/mad/sad) and poker (mad/sad) — crusher blocks with moods**, fish, fly, slime, snail (+upside-down shell) |
| `player_sheet` | 48 | **p1/p2/p3** characters, 66×92: `stand, duck, hurt, jump, front`, **11-frame walks** (the smoothest art in the repo) |
| `hud_sheet` | 33 | Digits 0–9, `x`, coin/gem/key icons (+disabled), **hearts (full/half/empty — a health system)**, player portraits |

### Family B — the 128px "deluxe" set (alternate biomes + the aliens)

| Sheet | Frames | Contents |
|---|---|---|
| `spritesheet_ground` | 108 | Six biomes again — incl. **planet** (alien world!) — same autotile grammar at 128px (`Hill_left/right`, `Half_*`, corners, cliffs) |
| `spritesheet_tiles` | 72 | 128px interactables: boxes, bricks, bridges, doors, ladders, **liquids**, levers, locks, mushrooms, signs, spikes, **spring/sprung**, switches ×4 (+pressed), torches, water/lava tops, weights |
| `spritesheet_enemies` | 57 | Redux species incl. **saw + sawHalf**, slime ×4 colours, worms ×2, fish ×3 (`fishBlue_fall`!), barnacle/bee/fly/frog/ladybug/mouse/snail |
| `spritesheet_players` / `aliens` / `alien<Colour>` ×5 | 55/55/11 | **Five alien colourways**, 66×92, with `stand, walk1/2, jump, duck, hurt, front` **and `climb1/2` + `swim1/2`** — ladder and water gameplay art |
| `spritesheet_items` | 24 | Coins/gems/keys/star + flag poles with `_down` states |
| `spritesheet_hud` / `spritesheet` | 36/98 | 128px HUD + a mixed sampler |
| `spritesheet_complete` | 355 | ⚠ **orphan** — references `sprites.png`, which is not in the upload. No loss (it's the union of the others); ignore or upload its PNG later |

### Decisions out of Wave 0

- **World grid = 70px (Family C primary).** It has the most gameplay art
  (buttons, springboards, levers, ladders, liquids, locks, ropes, doors,
  bridges, the 25-species enemy sheet, p1–p3). Family B serves as alternate
  biomes (planet!) and the **alien player skins** — their 66×92 frames match
  p1–p3, so aliens drop onto the 70px grid directly; B's 128px tiles join via
  `b2kSheetScale` when a level wants those biomes.
- **Sprite-only graphics from now on (policy).** No new plain LC graphics
  ("native GRCs") for visible game art — every new visual is a sheet frame
  (buttons replace coloured rects, weightChained replaces the grey thwomp,
  spikes/springs/doors all have art). Plain graphics remain only as
  *invisible physics hosts* (slabs, body proxies) and inside the existing
  no-asset fallbacks, which are frozen — not extended.
- **Measure before placing** stands: every Hill/slope tile gets its surface
  profile read from the pixels before a chain is fitted under it.

## 3. Player actions roadmap (expanded by the art)

Everything from the original roadmap, plus what the new frames unlock.
Each action: Kit change + tuning keys + **self-test assertions + harness
bump** + a place in a game.

| Action | Art | Design sketch | Keys |
|---|---|---|---|
| **Drop-through** | `*Half*` one-way tiles | brief collision-mask window; chains already one-sided | `dropMs` |
| **Wall-slide + wall-jump** | reuse jump/hurt poses | side probes (the ground-probe pattern, horizontal); capped slide fall; away-launch with input lockout | `slideFall, wallJumpX/Y, wallLockMs` |
| **Dash** | walk frames at high fps | fixed-speed burst, gravity off during, cooldown | `dashSpeed, dashMs, dashCooldownMs` |
| **Double jump** | jump frame | `airJumps` counter refilled on ground | `airJumps` |
| **Platform carry** | — | probe hit on kinematic ⇒ add its velocity to target vx | (automatic) |
| **CLIMB (new)** | `ladder_mid/top` + alien `climb1/2` | ladder zones = polled regions (`b2kOverlapMoving` doctrine); in-zone + up/down ⇒ gravity scale 0, velocity-driven y, climb anim; jump exits | `climbSpeed` |
| **SWIM (new)** | `liquidWater*` + alien `swim1/2` | water zones: gravity scale ~0.3, damping up, capped fall, jump = stroke (`b2kPlayerJump` repeatable in water), swim anim | `swimSpeed, swimJump` |
| **DUCK (new)** | `*_duck` frames | down ⇒ duck state + anim; optional hitbox shrink later (capsule reshape is a Kit call away) | — |
| **HURT knockback (new)** | `*_hurt` | standardise the hurt arc: control-off + `b2kPlayerJump`-style pop + invulnerability window | `hurtMs` |
| **Springboards (new)** | `springboardUp/Down`, `spring/sprung` | sensor/contact ⇒ `b2kPlayerJump kSpringSpeed` + art swap — the canonical use of the API jump | per-spring speed |

## 4. Enemy archetype roadmap (the full bestiary)

All on existing Kit mechanisms (patrol tables, movers, thwomp lifecycle,
rays, sensors, polls). Names = actual frame sets. Each lands with art,
anims, a maker/table entry, contact rules, **and a banner/self-test check**.

| Archetype | Species (art) | Behaviour |
|---|---|---|
| **Walker** (stompable) | slime ×4, worm ×2, mouse, ladybug | patrol; stomp = squash (`_squashed`/`_dead` art), side = hurt |
| **Spiked walker** | spinner, spinnerHalf, poker | patrol; **never stompable** (the spike-slime rule) |
| **Shelled** | snail (+`snail_shell`, upside-down) | stomp ⇒ shell (safe, static-ish); second hit ⇒ **kicked shell**: fast slider that kills other enemies and the player alike |
| **Flier (sine)** | bee, fly, ladybug_fly | the mover table (bodiless proximity) |
| **Ceiling ambusher** | **bat** (`bat_hang` → `bat_fly`) | hangs static; player passes under ⇒ drop + swoop (mover with a trigger) |
| **Ghost (the Boo)** | ghost (`ghost_normal/dead`) | chases ONLY while the player faces away (`b2kPlayerFacing()` vs relative x); freezes + fades when watched |
| **Mimic** | **grassBlock** | disguised as terrain; wakes when approached (the thwomp arming pattern, sideways) |
| **Pipe plant** | **piranha (`piranha_down`)** | emerges/retreats on a timer from pits/pipes; suppressed while the player stands close (the classic) |
| **Pit dweller** | snakeLava, snakeSlime, fish ×3 | periodic leaps out of liquid (mover, vertical, liquid-synced); `fishBlue_fall` for the arc-top flip |
| **Lunger** | frog (`frog_leap`), barnacle (`barnacle_bite`) | frog: timed hops toward the player; barnacle: static bite window (lurker pattern) |
| **Chaser** | mouse/spider | patrol until `b2kRayHit` line-of-sight, then accelerate |
| **Crusher** | blocker/poker (mad/sad!), weight + `weightChained` | the thwomp lifecycle with REAL art — face swaps mad/sad with state |
| **Saw** | saw, sawHalf (B) | static sensor + the sweeping mover (both shipped patterns) |
| **Spider** | spider walk1/2 | ceiling walker: patrol upside-down, drop on proximity, climb back (rope art available) |

Promotion rule stands: when the second game needs a pattern, it graduates
to Kit API (`b2kFoe…`).

## 5. Terrain, traps & interactables roadmap

- **Biomes:** grass / dirt / sand / snow / stone / castle (70px) + planet
  (128px). Levels declare a biome; the tile verbs take it as a parameter —
  one interpreter, seven skins. **Snow = low-friction ground** (ice physics
  via `b2kSetFriction` on its slabs) — terrain that plays differently.
- **Slopes:** `*Hill*` tiles per biome — measured, then chain-fitted (the
  mound recipe, now with proper art per biome).
- **One-ways:** `*Half*` thin platforms over ghost-padded one-sided chains.
- **Liquids:** water = swim zones; **lava = instant hurt** (polled region) with
  `liquidLavaTop` surface animation (two frames). Bubbling pits for snakes.
- **Ladders:** climb zones + `ladder_mid/top` columns.
- **Bridges & ropes:** plank bridges (`bridgeA/B`, `bridgeLogs`) — including a
  **collapsing bridge** trap (planks drop on a timer after touch; kill floor
  cleans up); rope tiles for spider/climb decor.
- **?-Boxes:** `boxCoin/boxItem/boxExplosive` + disabled/used states — **hit
  from below** (the underside-contact pattern inverted) pops a coin/powerup;
  explosive boxes chain into `bomb + bombFlash + particles`.
- **Breakable bricks:** brick tiles + `particleBrick*` debris (spawned balls
  with kill-floor cleanup) — stomp-from-below demolition.
- **Switch family:** polled **buttons** ×4 colours (pressed art), **levers**
  (left/mid/right = a 2-state toggle with a real handle), **key + lock ×4
  colours** (carry key, unlock matching lock tile), **doors** (open/closed art;
  the micro-game's exit gets a face), springboards, signs, torches (lit
  states), weights on chains.
- **Checkpoints/goals:** flag families in 4 colours, hanging variants, pole
  `_down` states for raise animations.
- **HUD:** sprite digits (`hud_0-9`, `hud_x`), hearts (full/half/empty),
  key/gem/coin icons — the text-field HUD becomes sprite-based (and cheaper
  than field relayouts).

## 6. Rules of engagement (updated)

1. Kit edits only in the source Kit → sync → static gates — every time.
2. **Every Kit change adds/extends a self-test assertion and bumps
   `kStHarnessV`.** The user runs the harness before playing.
3. Doctrine: events for one-shots; **`b2kOverlapMoving` polls for
   presence**; windows for verdicts; sim-time for feel; ghost-pad chains;
   thick slabs for driven edges; both targets set in every game;
   **measure art before placing it; sprite-only visuals** (plain graphics
   only as invisible physics hosts).
4. Perf budget: ~25 *live* sprites near the ceiling; tiles are free
   (inert); HUDs throttled; build once, write on change.
5. Docs ride along; plan.md decision log records every call.
6. Statically verified → user OXT pass → next wave.

## 7. The waves (expanded)

1. **Wave 1 — the iconic-feel base:** springboards, ?-boxes (coin pop),
   breakable bricks + debris, buttons/levers with art, key+lock+door; the
   platformer re-skinned sprite-only (real thwomp art, spike tiles, biome
   ground). *The "it looks like the classics now" wave.*
   **COMPLETE — user-verified 2026-06-12.** Shipped as a **three-level
   platformer** (a historical milestone — the platformer has since grown
   to **five levels** through Waves 3 and 7): L1 GREEN HILLS (movement +
   the toys: springboard, bonk row, one-way bridge, mound, clouds, spike
   pit), L2 THE WORKS (button gate, saw lever, thwomps, yellow key + the
   walled door), L3 FROZEN CITADEL (everything on ICE, snow biome, a
   second saw, red key + door). Springboards, ?-boxes paying coins,
   POOLED brick debris,
   button art on the polled plate, stand-to-flip lever, chained-weight
   thwomps (static at rest, **not player-movable**), walled doors whose
   gates are STRUCTURAL (floor-to-ceiling; the flag and last coins
   behind them, so wins provably pass through), GOLD-flag win-state
   clarity, self-counting coin totals, one-helper world bounds, and a
   one-snapshot-per-frame hot path. Harness **v9** (door-clearing
   assertions) user-confirmed all-pass. The wave's laws, all earned in
   OXT rounds, live in plan.md: gates must be structural; scenery
   first, actors after; never goto before camera bounds; no
   sub-capsule slots between statics; pool mid-game effects; park
   before disable.
   All POLLED geometry + windows (no static-contact events); **zero Kit
   changes, so no harness bump**. Art note: Wave 1 ships in the
   platformer's native 64px family (it has the full switch/spring/
   key/door set, style-matched); Family C debuts with content built FOR
   its 70px grid (Waves 2-3).
2. **Wave 2 — player actions I: COMPLETE (user-verified 2026-06-13).**
   Drop-through, climb (ladders), duck, the hurt-knockback standard;
   alien skins in the micro-game. Harness **v10 all-pass on the
   user's machine** — the wave's exit criterion. One OXT round of
   feedback: the new beats CRAMPED the levels (the L2 ladder landed
   on the checkpoint and lever) — answered with a spacing pass
   (L1 3968px / L2 3072px / L3 3776px; micro L2 1664px) and a new
   LAYOUT LAW: every interactive beat gets ~100px of clear air.
   Design in §9; as-built record in plan.md's decision log. The §9
   ABI question resolved to NO ABI CHANGE (the shim's pending
   shape-def filter already covers chain creation).
3. **Wave 3 — bestiary I (COMPLETE):** shelled (kickable!), ghost, bat,
   mimic, pipe plant, crusher-with-faces — into the platformer's L4
   "HAUNTED HOLLOW".
4. **Wave 4 — liquids (COMPLETE):** swim zones (the platformer's hilltop
   pool) + lava (L4) + the collapsing bridge (now L4's lava crossing).
   As-built record in §11.
5. **Wave 5 — player actions II (COMPLETE):** wall-slide/jump, dash,
   double-jump powerup (boxItem delivers it), platform carry. The
   micro-game was retired here.
6. **Wave 6 — bestiary II + promotion (COMPLETE):** frog hopper,
   barnacle lurking clam, spider ceiling-dropper — woven into L1/L2/L4;
   the `b2kFoe…` promotion decision deferred (no second consumer yet —
   the micro-game retired).
7. **Wave 7 — the desert biome (COMPLETE):** the platformer's fifth
   level, **L5 SCORCHED DUNES** (sand/desert) — the "iconic platformer"
   demonstration piece.
8. **Wave 8 — builder cross-pollination (NOT STARTED — the only
   remaining roadmap item):** sprite parts + the player as placeable
   kinds in the contraption builder.

## 8. Open questions / risks

- **macOS/Linux (R1):** unverified; the self-test is the acceptance suite.
- **`b2kScene*` promotion:** did NOT land — the platformer reached five
  levels (through Wave 7) keeping its scenes example-side, so the format
  was never promoted to Kit API. Revisit only if a second game needs it.
- **`spritesheet_complete.xml`** is an orphan (its `sprites.png` wasn't
  uploaded) — no content loss; upload the PNG later or delete the XML.
- **Mixed grids:** 70px (C) vs 128px (B) — normalised per level via
  `b2kSheetScale`; never mix raw grids inside one level.
- **Sheet memory:** prefer `-default`/70px sources + scale; the `-double`
  and 128px sets are alternates, not defaults.

## 9. Wave 2 design — player actions I (prepared 2026-06-12)

Four controller abilities plus the alien skins. **This wave edits the
Kit's player module** — the first Kit-touching wave of the content
phase — so every change lands with self-test assertions and a
`kStHarnessV` bump (v9 → v10), and the platformer + micro-game are the
two consumers that prove the API. One PR: Kit + sync + harness +
games + docs, statically verified, then the OXT rounds.

### 9.1 Drop-through (one-way platforms, downward)

- **Input:** DOWN+JUMP while grounded **on a one-way chain** (plain
  DOWN means duck, §9.3). On solid ground, DOWN+JUMP just ducks.
- **Mechanic:** a `dropMs` (~260ms) collision window between the
  player and one-way chains, per the original sketch. Chains gain a
  reserved Kit collision category ("the one-way bit"); the window
  drops that bit from the player's mask, then restores it.
- **Kit surface:** `dropMs` tuning key; internal state `drop`
  (renders as `fall`). `b2kChain`/`b2kSmoothGround` tag their chains
  with the reserved bit.
- **RESOLVED (2026-06-12): no ABI change needed.** `b2lc_chain_create`
  already honors the pending shape-def filter (`b2ShapeDefFilter` →
  `s_sd` → `cd.filter`), so the Kit tags chains at creation through
  the existing surface. The reserved bit is 2³¹ (nameable as the
  `oneway` layer; `b2kDefineLayer` now stops at 2³⁰ = 31 user layers,
  and `b2kSetMask` ORs the bit in automatically). One subtlety found
  in the build: the window's restore must wait until the capsule has
  CLEARED the deck (one-sided chain contacts judge by centroid — a
  timer-only restore snaps a straddling player back on top); a 4×
  hard deadline covers drops blocked by something below.
- **Grounding interplay:** during the window the ground probe must
  ignore one-way chains too, or the controller re-grounds mid-drop
  (the phantom-ground lesson from Phase 3, in reverse).
- **Where it lands:** L1's bridge (drop to the low road - mind the
  spike slime) and clouds; L2's breather cloud.
- **Harness:** stand on a chain platform, inject down+jump, assert
  the player's y passes below the chain within `dropMs` frames, and
  that the chain is solid again after (land on it from above).

### 9.2 Climb (ladders)

- **Mechanic:** ladder ZONES are rectangles registered with the
  controller (`b2kPlayerAddLadder x1,y1,x2,y2`; cleared by
  `b2kClear` like world state). In-zone + UP/DOWN enters state
  `climb`: gravity scale 0, velocity-driven y at `climbSpeed`
  (~160 px/s), x movement allowed at half speed. JUMP exits with a
  normal jump; leaving the zone restores gravity. Presence is a
  POLLED point-in-rect test in the tick (doctrine: presence = polls),
  zero physics objects.
- **Kit surface:** `b2kPlayerAddLadder`, `climbSpeed` key, `climb`
  anim slot in `b2kPlayerAnims` (optional: falls back to the jump
  pose). CORRECTION (build finding): the beige hero HAS climb frames
  (`character_beige_climb_a/b` in the default chars sheet) - the
  platformer climbs fully-frame'd; the aliens remain the micro-game's
  showcase.
- **Art:** `ladder_bottom/middle/top` (old tiles sheet, 64px) as pure
  decor tiles over the zone; alien `climb1/2` for skins that have it.
- **Where it lands:** L2 - a ladder up to a new bonus ledge above the
  gate area (one coin); the micro-game's level 2 exit approach.
- **Harness:** zone + hand-stepped UP: assert state `climb`, y
  decreasing, gravity restored on exit; jump-exit produces a jump.

### 9.3 Duck

- **Mechanic:** DOWN while grounded (and not on a chain) enters
  `duck`: target vx 0 at normal decel, duck anim. No hitbox change in
  this wave (capsule reshape is Wave 5 - say so in the guide so
  nobody expects to duck under saws yet).
- **Kit surface:** `duck` anim slot; state `duck`; no new keys.
- **Art:** `character_beige_duck` (already in the chars sheet);
  alien `_duck`.
- **Harness:** inject down on flat ground: state `duck`, vx decays to
  0, anim key reported; releasing down returns to idle.

### 9.4 Hurt-knockback standard

- **Mechanic:** `b2kPlayerHurt pFromX` - control off, an away-pop
  (sign of pFromX picks the direction; `hurtPopX` ~220 / `hurtPopY`
  ~320 via the jump-style velocity set, exempt from ground-snap),
  `hurt` anim, control restored after `hurtMs` (~700) **or** first
  landing after half that, whichever is later; then an invulnerability
  window (`invulnMs` ~900) during which `b2kPlayerHurt` no-ops and
  `b2kPlayerHurtIs()` returns true (the game skips hazard checks).
- **Game split (design decision):** contact damage (slimes' sides,
  saws, spikes brushed) = KNOCKBACK in place; lethal falls (pits,
  kill plane) = the existing respawn. The platformer's `pfHurt`
  becomes the respawn path only; knockback replaces it for contacts.
  The micro-game adopts the same split - two consumers, per the
  promotion rule.
- **Harness:** call `b2kPlayerHurt`, assert control off + away
  velocity + `b2kPlayerHurtIs()`; step past `hurtMs`, assert control
  restored; assert a second hurt inside `invulnMs` is a no-op.

### 9.5 Alien skins in the micro-game

- **Philosophy guard:** the micro-game stays ZERO-ASSET. Skins are an
  OPTIONAL upgrade: if the Spritesheets folder is known (same
  stack-property dance as the platformer), the start screen offers
  p-beige + five aliens; otherwise the embedded base64 hero loads as
  always, silently.
- **Mechanics bonus:** aliens carry `climb1/2` and `_duck` frames -
  the micro-game's skin picker is where Wave 2's anims show fully.
- **Frames (B family, 66x92):** `stand, walk1/2, jump, duck, hurt,
  front, climb1/2, swim1/2` per colour (swim waits for Wave 4).

### 9.6 Exit criteria

1. Harness v10 all-pass on the user's machine (every new state and
   window asserted, self-diagnosing messages).
2. Platformer: drop-through on the L1 bridge, the L2 ladder ledge,
   duck everywhere, knockback-vs-respawn split live in all three
   levels.
3. Micro-game: skin picker (with folder) + knockback split; still
   runs asset-free.
4. Docs ride along: kit-reference (new handlers/keys), kit-guide
   (climb/drop/hurt patterns + the duck caveat), CHANGELOG, plan.md
   decision log.
5. No regression: Wave 1's three levels still complete start to
   finish.

## 10. Wave 3 design — bestiary I (prepared 2026-06-13)

Six enemy archetypes and the **haunted level** they debut in. This wave
is **all example-side** — every verdict is a poll or rides the existing
slime/thwomp/mover machinery, and the Kit is untouched, so per rule 2
there is **no harness bump** (v10 stays the baseline). The platformer
grows a fourth level; "three levels to win" copy flips to four.

### 10.1 The sheet: "spooks" (enemies.png, Family C)

`enemies.png/.xml` carries the species the 64px foes sheet lacks:
**ghost** (51x73; `ghost` moving + `ghost_normal` shy + hit/dead),
**bat** (`bat_hang` 38x48 + `bat_fly` 88x37 + `bat` + hit/dead),
**piranha** (45x60, up + `piranha_down` + hit/dead), **grassBlock**
(71x70 + `_jump` + hit/dead — the terrain MIMIC). Frame names carry
their `.png` suffix (same as aliens.xml). It is a ~70px-family sheet in
a 64px-family level, so it loads as sheet `spooks` with
`b2kSheetScale 0.9` — the documented mixed-grid normalisation; raw
grids never mix. The **snail** (kickable shell) and the **crusher
faces** (`block_idle/fall/rest`) already live on the native 64px foes
sheet — no import, no scaling. If `enemies.png` is missing (an older
folder), the spook-kind makers skip silently; the level stays
completable (no coin or gate depends on a spook).

### 10.2 The archetypes

All six reuse proven pipelines. The slime FAMILY (bodies, contact
stomp-vs-ouch, `b2kFell` cleanup) absorbs three of them as new KINDS;
the thwomp absorbs one; two are bodiless sprites.

1. **Shelled — the snail (kickable!).** A slime-family patroller
   (anim `snailwalk`). STOMP does not kill: the snail becomes a
   **shell** (`snail_shell` frame, patrol stops). ANY hero touch of a
   resting shell KICKS it away from him (a 520 px/s velocity assert
   per frame while sliding, the player-controller pattern); a wall
   hit reverses it (poll: actual vx sign vs intent = the bounce).
   A SLIDING shell is a bowling ball: any ground foe it overlaps dies
   (+200), and it HURTS the hero on side contact (knockback) — stomp
   a sliding shell to stop it. Kind chain: `snail -> shell ->
   shellslide <-> shell`.
2. **Ghost.** Bodiless sprite (it drifts through terrain — that is
   the point). Chases the hero at ~80 px/s ONLY while unwatched;
   the moment the hero FACES it (`b2kPlayerFacing` vs relative x) it
   freezes in the shy pose (`ghost_normal`). Proximity touch =
   knockback. Unkillable — the level's ambient dread, one per level.
3. **Bat.** Slime-family kind with **gravity scale 0** once woken: it
   hangs (`bat_hang`, body parked static) under an overhang until the
   hero comes within ~150px, then drops into a fast sine-bobbing
   patrol (`batfly` anim, velocity-driven vx + sine vy). Stompable
   (one hit, `bat_hit` then gone); touch = knockback.
4. **Mimic — the grassBlock.** A GRASS block sitting in a PURPLE
   biome — wrong on purpose; haunted levels telegraph by wrongness.
   Parked static and frameless-still until the hero comes within
   ~90px, then it wakes (`grassBlock_jump`) and HOPS at him in short
   lunges (velocity bursts on a cooldown while settled). Stomp kills
   (+150); touch = knockback. Slime-family kind: `mimic ->
   mimiclive`.
5. **Pipe plant — the piranha.** No pipe art exists in any sheet, so
   it is a PIT LURKER: a bodiless sprite rising from a drawn burrow
   hole in the ground on a cycle (down ~1.6s, rise, bite ~1.2s,
   sink), with the classic mercy — it will NOT rise while the hero
   stands over the mouth (|dx| < 52). Hurt box only while risen.
   Unkillable (the saw rule). Pure sprite mover + state arrays.
6. **Crusher-with-faces.** The thwomp machine already had the face
   art as its no-weight fallback (`gBlockFace`); `pfMakeThwomp` gains
   a pFaced flag so L4's crushers WEAR the faces on purpose
   (idle/fall/rest swaps are already in pfTickThwomps). Same chained
   physics, same underside-knockback, same head-riding.

### 10.3 The haunted level — L4 "HAUNTED HOLLOW" (3712px)

Purple biome (`terrain_purple_*` + `grass_purple` decor — native 64px
tiles), **lava strips** as the new ground hazard (lava_top art over a
spike-pattern knockback sensor), one true pit, and the Wave 3 cast in
order: a MIMIC field (two grass blocks among purple bushes), the snail
+ a slime to bowl with its shell, the BAT overhang (two hangers under
a stone bar), the pit, a checkpoint, two PIRANHA burrows, the GHOST
stalking the whole second half, a faced-CRUSHER pair around a lava
strip, and purple steps to the flag. ~10 coins (self-counting), no
key/door (L2/L3 own that beat). Spacing per the new layout law:
every beat ~100px+ of clear air.

### 10.4 Game flow

`gLevel >= 4` wins; splash/help/win copy says FOUR; L1-L3 untouched
(beyond the spacing pass). L4 inherits default player knobs (no ice).
Knockback-vs-respawn split as everywhere: every Wave 3 touch is
knockback; only pits/kill-plane respawn.

### 10.5 Exit criteria

1. Harness v10 still all-pass (no Kit change = no bump — rule 2).
2. L4 completes start to finish with all coins; every archetype
   behaves: snail stomps to shell, shell kicks/bowls/reverses and can
   be stopped; ghost freezes when faced, drifts when not; bats drop
   and bob; mimics wake and lunge; piranhas cycle and show mercy;
   crushers wear their faces through the full cycle.
3. No regression: L1-L3 + micro-game still complete (spacing pass
   verified at the same time).
4. Docs ride along: CHANGELOG, plan.md decision log, this section.

## 11. Wave 4 — liquids (swim) — as built (2026-06-14)

The first new player-action since Wave 2, built as a faithful parallel to
the ladder/climb system and **user play-tested in the platformer**.

### 11.1 The swim feature (Kit)

- **`b2kPlayerAddWater x1,y1,x2,y2`** — a polled water zone (flat
  `sPlayWat*` arrays, parallel to `sPlayLad*`); world state, wiped by
  `b2kClear`/`b2kPlayerForget`, surviving an attach — exactly like ladders.
- **`swim` mode** — while the centre is in a zone: gravity scales to
  `swimGravity` (the body's own scale is saved and restored exactly once,
  like the climb), the sink caps at `swimMaxFall`, UP/DOWN drive vy at
  `swimSpeed`, and a JUMP press is a *repeatable* upward STROKE of
  `swimJump` (no grounded/coyote/buffer gate). The `swim` state overrides
  the grounded/airborne machine and clears `sPlayAir`, so surfacing is not
  a phantom land. A 9th `pSwim` arg on `b2kPlayerAnims` falls back to fall.
- **Mutual exclusion with climb** — both park gravity via *separate* saves,
  so the start gates check BOTH flags and two saves never fight. The tick
  costs ONE compare/frame when no water zones exist.
- Knobs (`swimSpeed`/`swimJump`/`swimGravity`/`swimMaxFall`) cached in
  `b2kPlayerTuneCache`. Two Opus correctness reviews (the Kit change; the
  micro-game + harness) — no blockers.

### 11.2 The layout law: a swim pool is a RAISED basin

`b2kCamBounds` clamps the camera at the world's bottom edge, so a sub-ground
pit is off-screen. A swimmable pool is therefore a **raised basin between
two banks** (the platformer) or the whole ground raised (the micro-game):
hop in, dive for the underwater coins (which FORCE the swim via the
coin-gate), then stroke up + hold-forward to hop out the far bank.

### 11.3 Playtest tuning + the swimGravity/swimJump lesson

The pool felt too floaty (you could pop straight out), so it was made
heavier: `swimGravity` 0.6, `swimMaxFall` 200, `swimJump` 300. The lesson
worth keeping: **`swimGravity` sets only the between-stroke SINK; the
single-stroke escape height is `swimJump` ALONE** (the stroke writes
velocity directly, then full air-gravity governs the apex once you break the
surface). The lever for "harder to climb out" is `swimJump`, not gravity.

### 11.4 The brick head-bump fix (gotcha 28)

The pool work surfaced a pre-existing regression: the hero's 88px capsule
was taller than its ~76px visible character (128px frame headroom at a 0.75
down-scale), so the invisible "hat" hit bricks while the visible head sat
~12px low (the bonk still fired). Fixed by sizing the hitbox to the art
(`tH` 88→76, `tDY` derived to keep the feet planted) and reading the body's
real half-height (`gHeroHalfH`) in the bonk window — see gotcha 28.

### 11.5 Harness v12

- `stTestSwim` — dive / buoyant cap / repeatable stroke / swim-up /
  gravity-restored-on-exit, every value printed.
- `stTestSwimGrounded` — swim while resting on a submerged floor (the
  pool-floor case): still `swim`, a stroke lifts off with no grounded gate.
- `stTestSwimClear` — the level-rebuild path: `b2kClear` must wipe the zone,
  or the next level's player is born swimming where the old pool was.

### 11.6 Status / loose ends

- The platformer's L1 hilltop pool is the user-tested swim showcase; a
  `0`-key debug warp (delete-before-merge sentinel) reaches it fast.
- The micro-game's L3 "THE DEEP" (data verbs `water` + `fish`) is built but
  shows an example-side **white-world build issue** (set aside — the Kit
  swim is sound). To revisit: the L3 build path in `mgBuild` / the new verbs.
- The **collapsing-bridge** trap (the last named Wave 4 mechanic) is carried
  to the loose-ends list.

## 12. Wave 5 design — player actions II (prepared 2026-06-14)

The next wave: four moves that extend the controller. All are KIT changes
(harness bumps), each a parallel to an existing tick path — reuse the
start-gate discipline that keeps swim/climb from fighting.

### 12.1 Wall-slide / wall-jump

- **Detect:** a side probe (mirror the ground ray) reports a wall contact on
  the facing side while airborne and pressing toward it — a new `sPlayOnWall`
  (+ side), polled like grounding.
- **Slide:** while wall-pressed and falling, cap the descent at a new
  `wallSlideMax` (a velocity assert, like the swim sink).
- **Jump:** a JUMP press while sliding launches up-and-away (`wallJumpX`/
  `wallJumpY`), consuming the press, with a brief control-lock so the
  away-velocity is not instantly cancelled (the knockback hand-off pattern).
- **State `wallslide`** + a 10th `b2kPlayerAnims` slot (falls back to fall).

### 12.2 Dash

- A direction + a new "dash" action (bound like "jump") gives a fast
  horizontal burst (`dashSpeed`) for `dashMs`, then decays, gated by
  `dashCooldownMs`; air-dash optional (one per airtime). **State `dash`** —
  a velocity assert for its window (gotcha 17: it must keep moving). A dash
  into water/ladder yields to swim/climb (those modes win, as over walk).

### 12.3 Double-jump (powerup-delivered)

- The "?-box" (boxItem) delivers a double-jump charge. An airborne
  `b2kPlayerJump` gated on a charge count (`sPlayAirJumps`, reset on
  landing) — reuses the gate-free `b2kPlayerJump`, so it is mostly
  bookkeeping + the pickup. A pickup, not a permanent knob.

### 12.4 Duck capsule reshape (deferred from Wave 2 by design)

- Wave 2's duck brakes but keeps the hitbox; Wave 5 shrinks the capsule to
  crawl under low gaps. The hard part is gotcha 28's cousin — a
  **bottom-anchored** reshape (keep the FEET planted as the capsule
  shortens) — and restoring it only when a ceiling probe finds headroom.
  New `duckHeight` knob.

### 12.5 Harness plan

One self-diagnosing test per move: wall-slide caps the fall + wall-jump
launches away + leaves the state; dash bursts to `dashSpeed`, decays, and
respects the cooldown; double-jump fires once airborne and re-arms on
landing; duck-reshape shrinks the probed half-height and restores only under
headroom. Bump `kStHarnessV` per the rule.

### 12.6 Exit criteria

1. Harness all-pass (new states + the existing suite).
2. Each move feels right in the platformer (the test bed) and composes with
   swim/climb/duck/knockback without fighting (the start-gate discipline).
3. Docs ride along (CHANGELOG, plan.md, this section).
4. No regression: every existing level still completes.
