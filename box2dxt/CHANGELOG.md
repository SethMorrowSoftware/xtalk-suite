# Changelog

All notable changes to Box2Dxt are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The native shim's ABI is tracked separately by `b2Version()` (currently `4`).

## [Unreleased]

Nothing yet.

## [0.3.0] - 2026-06-22

### Added

- **Slingshot: a transition COVER between levels (carrying the platformer's transition-card lesson across).**
- **Platformer: ILLUSTRATED biome cards (real game art on the transition card).**
- **Platformer: TRANSITION CARD + boot TITLE screen + recomposed WIN card (the polish pass's headline - `docs/platformer-polish-plan.md` §2 / §2.4).**
- **Platformer: CHARACTER SELECT + a hero portrait (asset-expansion Phase G).**
- **Platformer: COLLECTIBLES - coin tiers + a hidden star per level (asset-expansion Phase F, completing it).**
- **Platformer: HEALTH - a forgiving five-heart buffer (asset-expansion Phase F).**
- **Platformer: the GOO SERPENT in a slime-pool beat + the serpent generalized (asset-expansion Phase E, continued).**
- **Platformer: the LAVA SERPENT + a widened L4 lava pit (asset-expansion Phase E).**
- **Platformer: SNAKES - the slither movement type (asset-expansion Phase E).**
- **Platformer: spook slime/snake sprites sit ON the ground (alignment fix).**
- **Platformer: defeat-animation juice (asset-expansion Phase D).**
- **Platformer: a stomp DUST-POOF** — four little pale motes arc out of a squashed foe.
- **Platformer: a defeat POP + second SKINS** — the squashed art pops up on an ease-out arc as it fades, and the bestiary gains green/blue slime variants and a ring worm.
- **Platformer: MULTI-KEY doors + a two-key puzzle in L2 (asset-expansion Phase C, slice 3 - part 1).**
- **Platformer: latching SWITCH-GATES + a switch puzzle in L2 (Phase C slice 3 - part 2).**
- **Platformer: LEVEL 7 "STONE KEEP" expanded to a blade-and-warden gauntlet (the length + variety pass, vertical edition).**
- **Platformer: LEVEL 5 "SCORCHED DUNES" expanded to a full three-act level (the length + variety pass, second of the audit).**
- **Platformer: multi-checkpoint activation fix.**
- **Platformer: LEVEL 6 "CAVERN DEPTHS" expanded to a full three-act level (the length + variety pass).**
- **Platformer: the SPINNER - a spinning-blade hazard (asset-expansion Phase C, slice 2).**
- **Platformer: a LEVEL PICKER (dev/test convenience).**
- **Platformer: LEVEL 7 "STONE KEEP" - a VERTICAL climbing tower (asset-expansion Phase C, slice 1).**
- **Platformer: the CONVEYOR BELT - a carried surface (asset-expansion Phase B, slice 3).**
- **Platformer: the BLOCK SLIME - a hopping cube (asset-expansion Phase B, slice 2).**
- **Platformer: LEVEL 6 "CAVERN DEPTHS" - the DIRT biome (asset-expansion Phase B, slice 1).**
- **Platformer: FISH in the swim pool.**
- **Platformer: GEM bonus pickups.**
- **Platformer: a PARALLAX biome backdrop.**
- **Platformer Wave 7 (biomes): a new desert Level 5, "Scorched Dunes."**
- **Platformer Wave 6 (bestiary II): frog, barnacle, and spider — woven into L1/L2/L4, all example-side (no Kit change, no harness bump).**
- **Kit: a persistent spritesheet cache (`b2kSheetPersist`) — load atlases once, not per level (statically verified + harness v14).**
- **Wave 5 (player actions II) — five new player-controller moves (statically verified + harness v13).**
- **Wave 4 (liquids) — SWIM, the Kit's first new player-action since Wave 2 (statically verified + harness v12; user play-tested in the platformer).**
- **The platformer's L1 GREEN HILLS gains a HILLTOP POOL** — the swim showcase, in the level the game is actually play-tested in.
- **The COLLAPSING BRIDGE — Wave 4's last named mechanic — is now built.**
- **Platformer SHOWCASE polish round (statically verified; awaiting the OXT pass).**
- **Wave 3 — bestiary I + HAUNTED HOLLOW (statically verified; awaiting the OXT pass).**
- **Wave 2 closed (user-verified 2026-06-13; harness v10 all-pass) + the level SPACING pass.**
- **New example: the SLINGSHOT** (`examples/box2dxt-slingshot.livecodescript`) — an angry-birds-style tower-knockdown game.
- **Wave 2 — player actions I (statically verified; awaiting the OXT pass).**
- **Wave 1 closed (user-verified 2026-06-12); Wave 2 designed.**
- **The platformer is now a THREE-LEVEL game** (user direction: "we need three distinct levels for this demo to show off all features").
- **Wave 1 — the iconic-feel base: the platformer learns the classics.**
- **Wave 0: the asset pack catalogued; the content roadmap expanded.**
- **`b2kOverlapMoving` — the presence poll done right (the plate's last stand).**
- **Documentation sweep + the expansion plan (the green-board close).**
- **The harness doubles its reach (engine-surprise insurance).**
- **The micro-game's actual bug: it never set `b2kContactTarget`.**
- **Self-test round 4: ground-snap + wake-on-SetVelocity.**
- **Self-test round 3: landing hysteresis.**
- **Self-test round 2: the player landed springy.**
- **First self-test run: two real Kit bugs found and fixed.**
- **The Kit self-test harness** — `examples/box2dxt-selftest.livecodescript`: one click in OXT, ~30 seconds, a PASS/FAIL report.
- **The pressure plate is polled, not counted.**
- **Frame-exact physics events (the "flaky collisions" root cause) + `b2kKillFloor`.**
- **Hot-path performance pass (engine-limitation aware).**
- **The micro-game (Game Kit Phase 5 exit artifact):** `examples/box2dxt-microgame.livecodescript` — a COMPLETE game in one pasteable file.
- **Kit Sound module (Game Kit Phase 5 begins).**
- **Sheets beyond the Kenney format: custom grids and hand-named regions.**
- **The platformer is now a collect-them-ALL puzzle platformer** on a rebuilt, half-again-longer level.
- **Kit Player module (Game Kit Phase 3 — the headline feature).**
- **Kit Camera module (Game Kit Phase 4, pulled forward).**
- **The platformer demo (release candidate).**
- **Camera hardening (from the demo's OXT runs).**
- **Kit Sprite module (Game Kit Phase 2).**
- **Kit Input module (Game Kit Phase 1).**
- **Paced simulation loop.**
- **`examples/box2dxt-platformer.livecodescript`** — Game Kit Phase 1's playable example.
- **Keyboard support in the contraption builder.**
- **Generation-tagged handles (C shim).**
- **ABI fail-fast in the LCB binding.**
- **A root `README.md`** — project overview, quick start, doc map, and build instructions on the repository landing page.
- **Showcase pass — every Kit capability is now reachable from the builder.**
- **Per-part collision filter (contraption builder).**
- **Per-part sensor toggle (contraption builder).**
- **Categorised Examples gallery.**
- **Enable/disable parts.**
- **Comprehensive part inspector.**
- **Three more example machines (contraption builder).**
- **Cannon example recipe (contraption builder).**
- **Draw-your-own terrain (contraption builder).**
- **World feel presets (contraption builder).**
- **Servo joint (contraption builder).**
- **Sensor trigger zones (contraption builder).**
- **Collision layers (contraption builder).**
- **Smooth, rolling hills (contraption builder + Kit).**
- **Full Box2D v3.1.0 live-object API.**
- **Kit completeness pass.**
- **Multiply tool.**
- **Drop-in vehicles.**
- **Scrolling tool palette.**
- **Ramp facing.**
- **Terrain objects in the Contraption Builder.**
- **"Terrain Run" example recipe** — a ball rolls down a ramp, over a hill and onto a platform, showing the new pieces in one click.
- **Continuous integration** (`.github/workflows/build.yml`).
- **Single-source Kit + drift check** (`tools/sync-embedded-kit.py`).
- **Contraption Builder overhaul — a polished, beginner-friendly sandbox.**
- **Rebuilt the demo on top of the Kit.**
- **Kit per-frame hook:** `b2kFrameTarget obj` delivers an `on b2kFrame` message once per simulated frame, for app logic, motors, input, and custom drawing.
- **Kit getter:** `b2kBodyCount()` returns how many bodies the Kit is tracking.
- **Kit additions:** `b2kWall x1, y1, x2, y2` builds a static collision segment between two screen points.
- **Kit shape resizing:** `b2kReshape ctrl, "box"|"ball"|"capsule"|"poly"` re-fits a body's collision shape to the control's current size in place on the same body.
- **Much broader Kit coverage of the engine.**
- **Rotating image support in the Kit.**
- `LICENSE` (MIT, with the bundled Box2D MIT notice).
- `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`.
- New documentation set under `docs/`: getting-started, building, api-reference, kit-reference, and architecture.
- This changelog.

### Changed

- **Input validation across the whole shim surface.**
- **Collision filter bits widened and made safe.**
- **Kit hardening: a missing body is never a script error.**
- **Sturdier bridges and more natural chains (contraption builder).**
- **Examples now embed the current Kit.**
- **ABI bumped 2 → 3** (`b2Version()` now returns `3`).
- **Slicker tool palette.**
- **Contraption joints skip redrawing settled markers.**
- **Less redundant work in hot paths.**
- **Vehicle is now a coin-run.**
- **Light gamification.**
- **Smoother rendering.**
- **Demo polish & Lidar fix.**
- **Rebranded from LiveCode to OpenXTalk (OXT) / xTalk.**
- **Reorganized the repository** for a public release: source in `src/`, the demo in `examples/`, guides in `docs/`, tests in `tests/`, native libraries bundled in the extension at `src/code/`.
- Renamed `box2d-helper.livecodescript` → `src/box2dxt-kit.livecodescript` and `box2d-demo.livecodescript` → `examples/box2dxt-demo.livecodescript`.
- Renamed the test build option `BOX2DLC_BUILD_TESTS` → `BOX2DXT_BUILD_TESTS`.

### Fixed

- **Platformer: flying movers (bee/fly/fish/ladybug) no longer face backwards.**
- **Platformer: GROUND ladybugs + frogs no longer face backwards either.**
- **Platformer: spike pits now align FLUSH with the pit edges (all levels).**
- **Platformer (OXT round 6): five polish fixes for a solid state.**
- **Platformer: the L5 thorn pit fits its spikes and the final coin is off the flag.**
- **Platformer (OXT round 4): the collapsing-bridge planks now actually DROP.**
- **Platformer: the L1 swim basin has a KILL FLOOR under the water.**
- **Platformer (OXT round 3): the ROOT cause of the drifting coins and flags — cast sprites were born scroll-shifted.**
- **Platformer (OXT round 2): the L3 wall-jump shaft reads as a real beat now.**
- **Platformer: removed the L5 spider + its floating sand overhang.**
- **Platformer: the flag/checkpoint plant was raised 8px → 16px** after an OXT pass showed flags still hovering at 8px.
- **Platformer: the L4 COLLAPSING BRIDGE was crammed into a 128px lava slot between two crushers — rebuilt with room to read.**
- **Platformer: flags/checkpoints that read as "floating" on the user's engine are now PLANTED.**
- **Platformer: scenery no longer spawns on top of enemies or coins.**
- **Platformer: three coins sat *on* a wall — lifted clear (a measured-alpha audit of every coin/flag in all four levels).**
- **Kit: commands called with function syntax never worked in OXT.**
- **Kit: an invalid colour name no longer aborts a spawn.**
- **Docs: `b2AddSegment` / `b2kWall` segments are two-sided.**
- **Platformer: levels now hug their CONTENT, so the hero can no longer walk off into dead ground at either end.**
- **Placed parts now show up immediately, not "only after I press Run".**
- **Popups no longer glitch over a running sim (contraption builder).**
- **Inspector text no longer overlaps the settings rows (contraption builder).**
- **Parts can no longer be parked overlapping the chrome (contraption builder).**
- **Signal wires no longer churn the renderer (contraption builder).**
- **Geometry getters no longer leak the previous shape's values.**
- **An aborted `b2kAddSensor` / `b2kReshape` no longer leaks one-shot shapedef flags.**
- **`b2kPruneDeadRefs` now clears every parallel table** (shape, render, verts, radius, image-angle, static, spawned, sensor) like `b2kRemove` does.
- **`b2kDefineLayer` refuses a 33rd layer** instead of overflowing xTalk's 32-bit `bitOr` into a collide-with-nothing category.
- Stale ABI-`3` references in the demo header, getting-started, kit-reference, and changelog preamble now read `4`.
- **Every inspector setting is reachable again.**
- **Collision settings survive a reshape.**
- **Drawn ground now collides and is clearly visible.**
- **Drawn terrain saves where you last dragged it.**
- **Tidied the smooth-hill outline locals.**
- **Kit collision-layer handlers no longer trip an OpenXTalk reserved word.**
- **Contraption motors no longer stay dead after a pressure plate + rebuild.**
- **`b2kReshape` no longer leaves a body shapeless — and keeps it sensor-aware.**
- **Demo's first FPS reading is no longer bogus.**
- **Bridge & Chain spans ignore Bouncy mode.**
- **Duplicating a rotated part keeps its size.**
- **Kit no longer leaks image-angle cache entries across teardowns.**
- **No more divide-by-zero after editing the demo script.**
- **Playground see-saw now tilts.**
- **`b2kRemove` now deletes kit-spawned controls**, so removing a body never leaves a dead graphic behind.
- **Newton's cradle no longer explodes on launch.**

### Removed

- **The micro-game example (`box2dxt-microgame.livecodescript`) was retired.**

## [0.2.0]

- Box2D Kit (`b2k…`): a batteries-included pure-script helper toolkit.
- Demo rebuilt as a self-building, multi-scene interactive testbed (Playground,
  Pyramid, Newton, Bridge, Vehicle, Lidar) with major rendering optimizations.
- Full low-level `b2…` binding over Box2D v3.1.0: world, bodies, shapes, joints
  (revolute, distance, weld, prismatic, wheel, mouse), ray casts, point picks,
  and contact events.
- Cross-platform CMake build (fetches and pins Box2D v3.1.0), runtime smoke test,
  and CI that builds and releases native libraries for Linux, macOS, and Windows.
