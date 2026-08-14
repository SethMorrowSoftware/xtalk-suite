# Asset Expansion Plan — using the WHOLE spritesheet library

> **STATUS (frozen): Phases A–G shipped — the demo grew from 5 to SEVEN polished
> levels.** Forward feature development is now **stopped** for a polish pass (see
> [`platformer-polish-plan.md`](platformer-polish-plan.md)). The once-planned
> Phases **H** (Clocktown — *attempted and rolled back*), **I** (alien-swim) and
> **J** (stretch) are **not being pursued** and have been dropped from this plan;
> the assets they would have used are still catalogued in §1. The canonical
> history is [`../CHANGELOG.md`](../CHANGELOG.md) + [`../plan.md`](../plan.md).

The platformer demo now ships **seven polished levels** (it shipped five when this
roadmap was written). This document was the roadmap that grew it — an audit of
every `<SubTexture>` vs every frame-name the example references, then a plan to use
**more of the art** through new biomes, levels, enemies, mechanics, collectibles,
and heroes, without losing the reliability the engine and the layout audits give.

It is the **content** companion to
[`archive/expansion-prep.md`](archive/expansion-prep.md) (the Kit/Wave 0–8 intake,
now archived) and [`../plan.md`](../plan.md) (the as-built log).

| | |
|---|---|
| Goal | Every loadable spritesheet frame used by the demo (or a documented reason it isn't) |
| Current usage | chars **~8/45** · foes **~35/60** · tiles **~92/314** · bg **~5/14** · spooks **~13/100** (plus several whole sheets never loaded) |
| Kickoff (DONE) | **Phase A** — fish in the swim pool, gem bonus pickups, per-biome parallax backdrop (shipped; see the CHANGELOG) |
| Method | One biome/level per phase · ride the Kit (no new C/LCB unless forced) · every layout gated by `tools/audit-platformer.py` · OXT pass per phase |
| Verify | `tools/check-livecodescript.py` + `tools/audit-platformer.py` clean, then the user's OXT pass; bump the self-test only on **Kit** changes |

---

## 1. The unused-asset inventory

Grouped by where the value is. Frame names are the literal atlas names (the
`.png` suffix on the `spooks`/`enemies.png` sheet is part of the name).

### Backgrounds (`spritesheet-backgrounds-default`, 14 frames)
Used: `background_color_hills/_trees`, and now `background_color_desert`,
`background_color_mushrooms`, `background_fade_hills` (per-biome parallax).
**Unused:** `background_fade_trees/_desert/_mushrooms`, `background_solid_sky/
_grass/_sand/_dirt/_cloud`, `background_clouds`. All **opaque full scenes** — a
true multi-layer parallax needs transparent overlay art we don't have (see §5).

### Terrain (`spritesheet-tiles-default`, 314 frames)
The demo uses flat `_block_top*`/`_center` tops only. **Two whole biomes are
untouched** and every biome is missing its real terrain shapes:
- **`terrain_dirt_*` — 27 frames, entirely unused.** A complete brown/underground
  biome (block + 4 corners + 4 edges + center + cloud set + 3 long ramps + 2 short
  ramps + 3 verticals + overhangs).
- **`terrain_stone_*` — nearly all unused** (only the door-wall pieces are used). A
  full cave/castle biome.
- **Corner / edge / overhang / vertical / short-ramp pieces** are unused in *every*
  biome (grass/sand/snow/purple) — adding them turns flat shelves into cliffs,
  overhangs, pits with finished walls, and varied slopes.

### Items, pickups, hazards & decor (`tiles`)
- **Coin tiers:** `coin_bronze(_side)`, `coin_silver(_side)` (gold is used; gems now used).
- **Gems** `gem_blue/green/red/yellow` — **now used** (Phase A bonus pickups).
- **`star`, `heart`** — power-up / extra-life / health icons.
- **Hit-block variety:** `block_exclamation(_active)`, `block_coin_active`,
  `block_empty_warning`, and the whole `block_strong_*` set.
- **Multi-colour lock & key puzzles:** `switch_blue/green/red(_pressed)`,
  `key_blue/green`, `lock_blue/green` (only yellow/red are used).
- **Decor & ambiance:** `hill`, `hill_top(_smile)`, `grass`, `snow`, `window`,
  `torch_off/on_a/on_b` (animated wall light), `cloud1/2/3`.
- **Mechanic tiles:** `conveyor` (a conveyor belt), `bridge_logs`, `block_plank(s)`,
  `rope`/`rop_attached`, `ramp`, `block_spikes`, brick/diagonal variants.
- **Water/lava dressing:** `water`, `water_top(_low)`, `lava`, `lava_top_low`.
- **Flags:** `flag_green_a/b` (a third flag colour).

### HUD strip (`tiles`, 30 frames — entirely unused)
`hud_character_0`…`9`/`multiply`/`percent`, `hud_coin`, `hud_heart(_half/_empty)`,
`hud_key_blue/green/red/yellow`, `hud_player_*` and `hud_player_helmet_*` portraits.
An art-driven HUD that **replaces the LiveCode text fields outright** — the
`pfTitle`/`pfHelp` top bars and the `pfHud` bottom readout come out; live counts
become sprite digits + icons (see Phase F).

### Enemies (`spritesheet-enemies-default` "foes", 60 frames)
Used: slimes, snail, bat-via-spooks, saw, bee, fly, frog, mouse, worm, ladybug,
fire slime, and now **fish**. **Unused, native 64px (ride the slime family):**
- **Block slime** `slime_block_walk_a/b/_jump/_rest` (a hopping cube slime).
- **Worm "ring"** `worm_ring_move_a/b/_rest` (a second worm skin).
- **Idle/rest poses** for most species (`*_rest`) — for sleeping/telegraph beats.

### Spooks (`enemies.png`, Family C, 100 frames — 87 unused)
- **Snake family** `snake(.png)/_walk/_hit/_dead`, `snakeLava*`, `snakeSlime*` — a
  new **slither** movement type, including animated lava/slime snakes.
- **Spinner family** `spinner*`, `spinnerHalf*` — spinning-blade hazards.
- **Slime skins with squash/dead frames** `slimeBlue*`, `slimeGreen*`, `slime*`
  (`_squashed/_hit/_dead`) — the **defeat animations the demo currently lacks**.
- **`_hit`/`_dead` states** for bat/ghost/grassBlock/piranha/spider/bee/fly/frog/
  ladyBug/mouse/snail/worm/barnacle — proper stomp/defeat feedback everywhere.
- Alternate fish skins `fishGreen*`, `fishPink*`.

### Characters (`spritesheet-characters-default`, 45 frames — 37 unused)
**4 full alternate hero skins** `character_{green,pink,purple,yellow}_*` (each the
same 9-pose set) + `character_beige_front`. A one-word swap per the load comment →
a **character-select**.

### Whole sheets the demo never loads
- **`spritesheet.xml` (98) — a CITY/BUILDINGS set:** house walls/roofs (3 palettes),
  awnings, chimneys, `clock`, fences, doors, hanging shop signs, a big window
  library. A whole **town** theme.
- **`aliens.xml` + `alien*.xml` — an alternate hero family WITH SWIM frames**
  (`_swim1/2`, `_stand`, `_climb`, `_hurt`) that the Kenney `character_*` set lacks.
- **`items_sheet.xml` (59):** floor `button*`, `cloud1/2/3`, `plant(Purple)`,
  `springboardUp/Down`, `weightChained`, brick-debris `particle*` frames.
- **`enemies_sheet.xml` (18):** `blocker*`, `poker*` (spiked "poker" foes) — not in
  any loaded sheet.
- **`player_sheet.xml`**, **`spritesheet_*`/`*_sheet` packs**, the **`-double`** 2× sheets.

---

## 2. Strategy & principles

1. **One coherent slice per phase** — a biome usually ships as *backdrop + terrain
   set + 1–2 enemies + 1 mechanic + a level* so the art lands in context, not as a
   prop dump.
2. **Ride the Kit.** Almost everything below is example-side (new makers, new
   `pf*` ticks) reusing `b2kSpawn*`/`b2kAddSensor`/`b2kSpriteNew`/`pfAddMover`/the
   slime-family tables. **Only flag a Kit change when truly forced** (e.g. a new
   movement primitive); a Kit change means a `kStHarnessV` bump + `sync-embedded-kit`
   + the user's harness run.
3. **Audit-gated layout.** Extend `tools/audit-platformer.py` for each new maker
   (new enemy → parse its patrol; new biome → its slabs) so every level stays clean
   on buried/OOB/walk-off/overlap before the OXT pass.
4. **Honour the laws.** The layout law (~100px clear air/beat, widen before
   squeezing), the chain ghost rule, the single-threaded performance playbook
   (one snapshot/frame, 4 Hz HUD, build-once, write-on-change, raw handles in hot
   paths), and the OXT gotchas (no smart quotes, top-of-handler locals, scroll-0
   cast creation, etc.).
5. **Degrade gracefully.** Optional sheets gate their makers on a capability flag
   (the `gSpooksOK`/`gToysOK` pattern); a missing sheet omits its content and the
   level still completes.

---

## 3. The phased roadmap

Each phase is a shippable increment. Effort is rough (S/M/L); risk notes what
needs an OXT eye.

### Phase A — Swim life, gems & depth  ✅ DONE (kickoff)
- **Assets:** `fish_blue/yellow_swim_*`, `gem_*`, `background_{color_desert,
  color_mushrooms,fade_hills}`.
- **Shipped:** fish in the L1 pool; gem bonus pickups (HUD + win-screen tally);
  per-biome parallax backdrop.
- *OXT to confirm:* parallax tiling seam/feel; swim+fish balance.

### Phase B — Underground biome → **Level 6 "CAVERN DEPTHS"**  (M)
- **Slice 1 — DONE (statically verified; needs OXT):** the **dirt biome + Level 6
  skeleton** that completes start-to-finish. `terrain_dirt_*` (block tops,
  `block_center`, carved `block_top_left/right` corners, `ramp_long_a/b`, one-way
  `cloud_*`) over the `background_solid_dirt` backdrop; a wall-jump shaft of
  floating dirt columns, a spike gap, a dirt-ramp mound, a one-way-cloud bonus
  route, reused slimes + a snail, a bonus gem, dirt goal steps. Win moved to
  `gLevel >= 6`. Example-side; `audit-platformer.py` auto-discovers + clears L6.
- **Slice 2 — DONE (statically verified; needs OXT):** the **block slime**, a
  hopping cube (`slime_block_*`), a new slime-family kind `block` debuting in L6.
- **Slice 3 — DONE (statically verified; needs OXT):** the **conveyor belt**
  (`pfMakeConveyor`, a polled vx zone) in L6. Torches were pulled forward into
  slice 1's polish. **Phase B is complete** (pending the OXT pass).
- **Assets:** `terrain_dirt_*` (whole biome, slice 1), `background_solid_dirt`
  (slice 1), `torch_off/on_a/on_b` (slice 3), `conveyor` (slice 3),
  `slime_block_*` (block slime, slice 2).
- **New enemy:** **block slime** — a hopping cube (slime family, new `slimeblock`
  kind; `_jump` frame on the hop, `_rest` between).
- **New mechanic:** **conveyor belts** — a floor strip that pushes the grounded
  hero (a polled zone that adds vx). **Correction:** the `conveyor` tile is a
  **single frame** (no `_a/_b` pair), so the belt does **not** animate by frame-
  flip — drive it as a polled vx zone with a static tile (or fake-scroll the tile
  loc if motion is wanted). Only `torch_on_a/b` is a real 2-frame animation.
- **Ambiance:** wall **torches** (2-frame `torch_on_a/b` flicker) light the cavern;
  the dirt biome's corner/edge/vertical tiles make real tunnels & cliffs.
- **Level:** a descending cave run — conveyor sections, block-slime hops, a dark
  vertical shaft (wall-jump, **slice 1**), dirt ramps (**slice 1**). Backdrop is
  the dirt scene (**slice 1**).
- *Kit:* conveyor may want a tiny Kit helper (a "surface velocity" zone) — evaluate
  a polled example-side version first.

### Phase C — Castle/dungeon biome → **Level 7 "STONE KEEP"**  (M–L)
- **Slice 1 — DONE (statically verified; needs OXT):** Level 7 as a **VERTICAL
  climbing tower** on the `terrain_stone_*` set over the dark stone backdrop
  (`pfBuildStoneBackdrop`). A new **gated vertical-camera mode** (`pfBoundsV` +
  `gCamTopY/gCamBotY/gKillPlaneY`, spawn at `gRespawnX/Y`) scrolls the camera UP
  as the hero jumps one-way `pfMakeLedge` stone ledges to the flag atop the keep;
  8 coins + a summit gem. L1-L6 byte-for-byte unchanged. Win moved to
  `gLevel >= 7`. The audit skips the vertical level. **The vertical camera scroll
  is the OXT unknown.** (Earlier horizontal passes were redesigned after the user
  asked for a true vertical level.)
- **Slice 2 — DONE (pending OXT):** the **spinner** hazard. `pfMakeSpinner` (a
  bodiless `spooks`-sheet sprite spinning via animation + sweeping a sine path,
  proximity knockback like the saw — the saw-rule, you time it). L7 gets two
  sweeping blades across the L1->L2 and L4->L5 climb gaps, standing-safe on the
  adjacent ledges. `pHalf` provides the wall-mounted `spinnerHalf` for slice 3.
  Gated on `gSpooksOK` (no `enemies.png` = safe). **Blade timing is the OXT feel-pass.**
- **Slice 3 — DONE (pending OXT):** the **multi-key / switch puzzles**, woven into
  L2 "The Works" (L7 went vertical, so the puzzle wing lives in the machinery
  level - switches/gates/keys fit a factory). *Part 1:* `pfMakeKeyDoor` generalised
  to N coloured doors (a per-door table; the hero holds a `gKeysHeld` set, each key
  `uPfKeyWord`-tagged and consumed at its door) - deployed as a **two-key lockgate**
  (yellow + blue) ending L2, which also tops L2 to ~24 coins. *Part 2:*
  `pfMakeSwitchGate` - a **latching** floor switch (`switch_<colour>`) that opens
  its coloured kinematic gate (`block_<colour>`) for good - deployed as a **green
  switch-gate** barring the crusher alley until you find + press the switch on the
  third-bay cloud. Both gated on `gToysOK` (a missing tiles sheet = an open run).
- **Assets:** `terrain_stone_*` (full), `switch_{blue,green,red}(_pressed)`,
  `key_{blue,green}`, `lock_{blue,green}`, `spinner*`/`spinnerHalf*`,
  `block_strong_*`.
- **New enemy:** **spinner** — a spinning-blade hazard (sprite-faced sensor on a
  fixed or sweeping path; `spinnerHalf` for a wall-mounted half-blade).
- **New mechanic:** **multi-gate lock-and-key & switch puzzles** — generalise the
  existing yellow/red `pfMakeKeyDoor` to N colours, add floor **switches**
  (`switch_*`/`_pressed`, a polled plate like the L2 gate) that open coloured gates.
  A room that needs *two* keys / a switch sequence.
- **Level:** a fortress interior — strong `block_strong_*` ?-blocks, a key/switch
  puzzle wing, spinner gauntlets, stone cliffs/overhangs.

### Phase D — The defeat-animation & bestiary fill-in  (S–M)  — IN PROGRESS
- **Assets:** `*_squashed/_hit/_dead` across `spooks` and `foes` `_rest` poses;
  `worm_ring_*` (second worm skin); `slimeBlue*`/`slimeGreen*` skins.
- **Polish, every level:** play the proper **squash/dead** frame on a stomp (slimes,
  snail, snake, etc.) instead of just dropping the art; **rest/idle** poses for
  sleeping/telegraphing foes. Adds juice without new mechanics.
- *Pure example-side; no new levels.* Good "between big phases" polish.
- **Done (pending OXT):** the stomped foe now **fades out** over its linger
  (`blendLevel` ramp) instead of blinking off; the bat + mimic show a proper
  `_dead` pose (was a `_hit` flash); and a **dust-POOF** (four pooled `b2kSpawnBall`
  motes, the debris pattern) bursts from the squash. Slimes/snail/block already
  had `_flat`/`_shell`/`_rest` squash poses; telegraphing foes already idle on rest.
- **Done (round 2):** a defeat **POP** (the squashed art arcs up ~50px as it
  fades) and the **second skins** - a green + blue slime (`slimeGreen/Blue`,
  `spooks`, via `pfMakeCritter`'s new optional sheet param, `gSpooksOK`-gated) and
  the **ring worm** (`worm_ring`, native foes). Phase D essentially complete.

### Phase E — Snakes & the slither biome beat  (M)  — DONE (pending OXT)
- **Assets:** `snake(.png)/_walk/_hit/_dead`, `snakeLava*`, `snakeSlime*`.
- **New movement type:** **slither** — a ground crawler that hugs the floor and
  reverses at edges/walls (slime-family kind `snake`, animated `_walk`). The LOW
  `snake.png` is the crawler; the TALL rearing `snakeLava`/`snakeSlime` art is the
  rising **serpent** (a separate bodiless mover, not a floor crawler).
- Woven into L4 (lava), L6 (goo), and across the biomes (no dedicated level needed).
- **Done (pending OXT):**
  - The `snake` kind + slither tick (floor-probe edge/wall reversal) +
    `pfMakeSnake pIdx,pX,pMinX,pMaxX,pTopY` — the plain low crawler, `gSpooksOK`-
    gated, via `pfMakeCritter`'s sheet param. Deployed: L1 meadow, L3 ice, L4
    lava-approach, L5 desert — the slither type across four biomes.
  - **The serpent (`pfMakeSerpent`/`pfTickSerpent`, generic):** a rearing snake
    that rises out of a hazard pool, arcs across on a sine path and sinks back in,
    peaking high so it contests the crossing (a proximity-poll knockback, the saw
    rule). Created under the pool surface so its submerged body is occluded.
    Single-instance (one per level). Two homes:
    - **L4 lava** (`snakeLava`): the old collapsing bridge is gone; the pit is a
      512px chasm crossed in two hops over a middle stepping-stone the serpent
      peaks at.
    - **L6 goo** (`snakeSlime`): PIT2's spike chasm becomes a toxic **goo pool**
      (`pfMakeSlimePool`, the slime-biome twin of `pfMakeLava`); the serpent peaks
      at jump-arc height, so you time the double-jump for when it has sunk.
  - **Sprite grounding fix:** the spook skins fill their frames edge-to-edge (no
    transparent padding, measured), so their bind offset is the plain geometric
    `pFullH/2 - frameH*0.9/2`, not the FOES soft-bottom sink that floated them ~9px.
- **TODO (optional):** more snake placements if wanted; `audit-platformer.py` now
  tracks `pfMakeSlimePool` as a hazard but still ignores `pfMakeSnake`/`pfMakeSerpent`
  (harmless — the pools aren't gap-checked and the snakes self-reverse).

### Phase F — Collectibles & a health model  (M)
- **Assets:** `coin_bronze/silver(_side)`, `star`, `heart`, `hud_heart(_half/
  _empty)`, `hud_coin`, `hud_character_0-9/multiply`.
- **Coin tiers (SHIPPED).** Coins are bronze/silver/gold worth **1/2/3** toward a
  bonus `gScore`, auto-tiered by height (higher = worth more; `pfMakeCoin` takes an
  optional explicit tier). The flag still gates on the coin **count** (the
  collect-all clarity is preserved); the weighted score is banked and shown on the
  win screen.
- **A hidden `star` per level (SHIPPED).** One `pfMakeStar` challenge pickup per
  level, banked to the win screen with its own dim->lit HUD slot; it never gates
  the flag. Every star is placed **ON a proven-reachable standing surface** (a high
  cloud/ledge/stepping-stone), audit-checked for reachability + clearance, never a
  bare mid-air apex.
- **Health — a forgiving FIVE-heart buffer (SHIPPED).** The hero starts each level
  with 5 hearts (`hud_heart`/`hud_heart_empty`, a bottom-left row; `kHearts`). A
  contact hit (`pfOuch`) spends one pip *atop* the existing knockback + mercy window
  (so at most one pip per hit — the buffer can't drain in a frame of overlap);
  emptying the row makes that hit lethal and routes to the respawn (`pfHurt`), which
  REFILLS it. Falls / the kill-plane refill too, so the meter never hard-fails on
  contact — it *augments* the knockback model with a visible "you've been pushing
  your luck" gauge rather than replacing it. Shipped at **5** (forgiving), not the
  spec's 3.
- **Art HUD — retire the LiveCode text chrome (`hud_*`).** Today the demo frames
  the play area with LiveCode **fields**: `pfTitle` + `pfHelp` across the **top**
  and the live `pfHud` readout across the **bottom**. **Remove those persistent
  edge fields** and render every *in-game HUD need* from the unused `hud_*` sprite
  strip instead:
  - **Coins / gems / star:** `hud_coin` (+ a gem/star icon) followed by sprite
    digits `hud_character_0`…`9` (with `hud_multiply` / `hud_percent`) — e.g.
    `[coin] 12 / 30`. Built once, frames swapped **on change only** (the count
    changes rarely, so this is far cheaper than the per-frame field relayout it
    replaces — see the 4 Hz / write-on-change rule).
  - **Keys:** light a `hud_key_{blue,green,red,yellow}` icon as each key is taken
    (pairs with the Phase-C multi-key puzzles).
  - **Hearts (SHIPPED):** a `hud_heart`/`hud_heart_empty` row low at the bottom-left
    (`pfBuildHud` builds five, `pfUpdateHearts` redraws on change). The `_half` frame
    is unused — pips are integer.
  - **Hero portrait:** `hud_player_*` / `hud_player_helmet_*` (pairs with the
    Phase-G character select).
  - **Placement:** the `hud_*` sprites are screen chrome, not world objects — fixed
    positions on the card, **never** `b2kCamAdopt`-ed (the camera group scrolls; the
    HUD must not), built once at level start and parked/hidden when unused.
  - **Onboarding text loses its standing field:** fold the controls/level blurb
    (`pfHelp`) into the **transient centred splash** (`pfSplash` already exists as a
    non-edge overlay) and a Pause overlay — *that* field stays, since it is not
    top/bottom chrome and is the natural home for the load-failure / camera-unavailable
    diagnostics in the no-art fallback (where there are no HUD sprites to show).
  - **Buttons:** the `pfbtn_pause`/`pfbtn_reset` bottom buttons can stay functional
    or move into the Pause overlay; keyboard (ESC/R) already covers both.

### Phase G — Player identity: character select + portraits  (S–M)  — SHIPPED
- **Assets:** `character_{green,pink,purple,yellow}_*` (all carry the full 8-frame
  hero anim set), `hud_player_*` portraits.
- **Shipped:** press **1-5** to pick beige/green/pink/purple/yellow (`gHeroSkin`,
  the one-word swap the hero anim defs + creation frame interpolate; a rebuild
  re-skins cleanly). The choice persists across levels/restarts. A **HUD portrait**
  (`hud_player_<skin>`) anchors the bottom-left status corner beside the heart row;
  the splash + pause overlay carry the 1-5 hint. `hud_player_helmet_*` left unused
  (the plain portraits read cleaner at HUD scale). *OXT to confirm:* each skin
  animates cleanly across idle/walk/jump/duck/climb.

### Phases H–J — not pursued

The Village/**Clocktown** biome (H, the `spritesheet.xml` city set — *attempted and
rolled back*), the **alien swim-world** (I, the `aliens.xml` heroes with swim
frames), and the **stretch/quality** items (J — true multi-layer parallax, the
`-double` hi-DPI sheets, `items_sheet` particles/springboards) were scoped but are
**not being pursued** now that feature development is frozen. The assets each would
have used remain catalogued in §1 if work ever resumes.

---

## 4. Proposed level line-up (after expansion)

| # | Name | Biome / backdrop | Headline assets | Marquee beat |
|---|---|---|---|---|
| 1 | Green Hills | grass / hills | (built) + fish, gem | rope bridge, swim pool |
| 2 | The Works | grass / hills | (built) + gem | gate, lift bay, walled door |
| 3 | Frozen Citadel | snow / pale hills | (built) + gem | wall-jump shaft, boulder |
| 4 | Haunted Hollow | purple / mushrooms | (built) + gem, snakes | piranhas, ghost, collapse bridge |
| 5 | Scorched Dunes | sand / desert | (built) + gem | dune, thorn pit, bestiary II |
| **6** | **Cavern Depths** | **dirt / dirt** | dirt biome, conveyor, torches, block slime | conveyor descent + dark shaft |
| **7** | **Stone Keep** | **stone / cave** | stone biome, multi-key/switch, spinners | lock-and-key puzzle wing |

(6–7 are the shipped new content; the once-planned 8 "Clocktown" / 9 "Tidal Caves"
were not pursued — see Phases H–J above.)

---

## 5. Mechanic notes & gotchas to respect

- **Conveyor (Phase B):** prefer a polled example-side zone that adds vx to a
  grounded hero (read `b2kPlayerOnGround` + position, then `b2kPlayerSet`/a nudge)
  before reaching for a Kit "surface velocity" feature — keep the Kit untouched if
  possible.
- **Multi-key puzzles (Phase C):** `pfMakeKeyDoor` already parametrises colour;
  generalise to multiple simultaneous doors + polled **switches** (the L2 plate is
  the template). Mind gotcha 21 (filter-bit clamping) only if you gate by collision
  layers rather than scripted state.
- **Health/hearts (Phase F):** the current model is **knockback + mercy window**
  (contact) vs **respawn** (lethal falls). A heart model must keep that split
  coherent and not make the swim/fish/spinner gauntlets unfair. Prototype and
  OXT-test before committing.
- **True parallax (Phase J):** the loaded bg scenes are **100% opaque** (measured),
  so a fade layer behind is hidden — single-layer drift (shipped) is the ceiling
  until transparent overlay art exists.
- **New atlases (Phases H/I):** load with `b2kSheetLoadAtlas` behind a capability
  gate (`gCityOK`/`gAlienOK`), `b2kSheetScale` to normalise grid size (gotcha 24),
  and keep `.png`-suffixed frame names where the sheet uses them.
- **Scroll-0 creation:** every create-once pickup/flag is built before the camera
  `goto` (the root-cause fix) — new makers must keep that or be built in the scene.
- **Art HUD (Phase F):** the goal is to **delete the LiveCode edge fields**
  (`pfTitle`/`pfHelp` top, `pfHud` bottom) and rebuild the live readouts from
  `hud_*` sprites. Treat them as screen chrome: fixed card positions, **not**
  `b2kCamAdopt`-ed, built once, frames swapped on change only. Keep the centred
  `pfSplash` field as the text home for onboarding + the no-art / no-camera
  diagnostics (the fallback path has no HUD sprites to fall back on).

---

## 6. Asset-coverage (as-built)

Phases A–G shipped; the per-phase notes above and [`../CHANGELOG.md`](../CHANGELOG.md)
are the as-built coverage record. The original aspirational per-sheet checklist has
been dropped now that feature development is frozen — much of it shipped (coin tiers,
star, the heart HUD, character select, the dirt/stone biomes, snakes, spinners,
switch puzzles), and the remainder was tied to the unpursued Phases H–J.

---

## 7. Rules of engagement (carried from the project)

- **The embedded-Kit sync is law:** edit `src/box2dxt-kit.livecodescript`, then
  `python3 tools/sync-embedded-kit.py` and commit the re-synced examples in the
  same change. Most expansion work is example-side and won't touch the Kit.
- **Static gates before OXT:** `tools/check-livecodescript.py` (quotes, handler &
  control-structure balance, embedded-Kit drift) **and** `tools/audit-platformer.py`
  (geometry) must be clean. Extend the audit alongside each new maker.
- **Self-test:** bump `kStHarnessV` and add an assertion **only when the Kit
  changes**; example-only content does not bump it.
- **OXT is the truth for runtime/feel:** claim "verified statically; needs an OXT
  pass" and let the user confirm — never assert runtime behaviour we can't observe.
- **Branch/PR:** develop on the task branch, commit with clear messages, open a
  draft PR, keep `CHANGELOG.md` current per phase.

---

## 8. Open questions / risks

1. **Health model (F): DECIDED — a forgiving five-heart buffer LAYERED ON the
   knockback-mercy contract** (not a replacement). A contact hit costs one pip but
   still knocks back with mercy; the buffer only gates the *fifth* hit into a
   checkpoint respawn (which refills), so existing per-level difficulty is
   preserved and merely softened. Shipped at 5, not the spec's 3.
2. **Coin gate vs score: DECIDED — the flag still gates on the coin COUNT** (collect
   all coins to gild the flag, unchanged), and the bronze/silver/gold tiers feed a
   separate bonus `gScore` banked to the win screen. The collect-all clarity is
   preserved; the score is a pure skill-reward overlay.
3. **City/alien atlases (H/I):** different grids/styles — confirm they read at the
   64px world scale (`b2kSheetScale`) and that mixing styles per level looks
   intentional, not clashy.
4. **Conveyor/new primitives:** can they stay example-side (polled), or is a small
   Kit addition (with a harness bump) justified? Prefer example-side.
5. **True parallax art:** is transparent overlay art available/authorable, or does
   the single-layer drift stay the ceiling?
6. **Scope/order:** the table in §4 is a suggestion — confirm which biome/level to
   build next (Cavern Depths is the lowest-risk, highest-art-payoff first step).
