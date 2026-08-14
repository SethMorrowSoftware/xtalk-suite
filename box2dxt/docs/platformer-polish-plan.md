# Platformer Polish Plan — bringing the demo to its final form

Forward feature development on the platformer is **frozen**. The demo is a
**7-level** scrolling showcase (asset-expansion Phases A–G shipped; an 8th level
"Clocktown" was attempted and rolled back — it left no trace in the canonical
history, so the as-built record is `plan.md` + `CHANGELOG.md`, not a recoverable
commit). This document is the plan to take it from "feature-complete" to
**polished and final**: the things to refine, not to add.

The discipline that built it still governs: **OXT is the truth for runtime/feel**
(claim "verified statically; needs an OXT pass", never assert what we can't
observe), every `.livecodescript` edit passes `tools/check-livecodescript.py` +
`tools/audit-platformer.py`, and a **Kit** change bumps `kStHarnessV` + re-syncs
the embedded copies. Polish is example-side wherever possible.

---

## 0. What "final form" means

A stranger should be able to open the demo and have it read as a **finished little
game**, not a tech demo: it boots to a title, transitions cleanly between levels
(no visible construction), plays with consistent feel, looks composed (art faces
the right way, scales right, scenes aren't sparse), sounds intentional, and ends
with a satisfying summary. Nothing half-drawn, nothing that "outruns the camera",
no dev seams showing.

Definition-of-done checklist lives in §9.

---

## 1. The as-built demo (what we're polishing)

- **7 levels / biomes:** L1 Green Hills, L2 The Works, L3 Frozen Citadel, L4
  Haunted Hollow, L5 Scorched Dunes, L6 Cavern Depths, L7 Stone Keep (a vertical
  climb). Each ~6,400px / 3 acts / ~24 coins / 3 checkpoints (L1 is longer, L7 is
  vertical).
- **Moves:** run, double-jump, wall-jump, dash, duck, swim, ladders.
- **Mechanics:** moving lifts, conveyors, springs, one-way clouds/bridges,
  key+door + switch-gates, ?-boxes.
- **Bestiary:** slimes (+ block/fire/skins), snail, snake + rising serpents, bat,
  ghost, mimic, frog, spider, barnacle, plant, bee/fly/fish movers, boulders,
  crushers, saws, spinners, piranhas.
- **Collectibles:** coins (bronze/silver/gold tiers → a bonus score), a bonus gem
  and a hidden **star** per level — all banked to the win screen.
- **Health:** a forgiving 5-heart buffer (contact costs a pip; emptying it routes
  to a checkpoint respawn that refills).
- **Identity:** character select (1–5: beige/green/pink/purple/yellow) + a HUD
  portrait.
- **Chrome:** a screen-fixed **art HUD** (coins/gems/keys/hearts/star/portrait), a
  transient splash, an ESC pause overlay, a win dialogue, a dev level-picker.

This is a lot of working machinery — the polish is making it all *present* itself
well, not adding more.

---

## 2. THE HEADLINE: interstitial / transition screens

> **Status: SHIPPED & MERGED (PR #70 + #71), OXT-confirmed.** A card-level
> `pfCardShade`/`pfCardText` overlay (built once in `buildPfUI`, `kPfUIVersion` → 11)
> covers every `pfStartGame` teardown+build (`pfCardCover` before the teardown,
> `pfCardReveal` send-driven `blendLevel` fade after `b2kStart`), the demo boots to a
> title screen with a live hero preview + the 1-5 chooser (moved off the in-level
> binding), and the win screen is recomposed in the card language. The level cards are
> **illustrated**: each shows the level's real biome backdrop (L1-L5, scaled to cover
> the card under a dimming scrim) plus a cast row of real sprites (hero + foe + coin +
> flag) on a ground band, all cloned from the loaded atlases (no new assets), every
> piece degrading to the tint base if a slice fails. Example-side only (no Kit touch).
> (Real per-level screenshots were rejected: the levels are ~6,400px scrolling worlds,
> so a flat grab is unrepresentative and would mean shipping/maintaining PNGs.)
> Remaining card work is cosmetic OXT tuning (cast spacing, scrim strength, crop
> framing); see the CHANGELOG entries for the full landing notes.

**The problem.** `pfStartGame` (the per-level world build) runs its **teardown
before the `lock screen`** (it deletes the previous level's controls at
~`pfStartGame`:`b2kTeardown`/`pfWipeStage`, then locks the screen only at the
backdrop step), and nothing masks the moment of reveal. So the player *sees* the
old level clear and the new one assemble — on every level start, level→level
advance, R-restart, level-picker jump, and hero re-skin (1–5). It reads as a
flicker/construction seam — the single most "demo-not-game" tell.

**The fix: a full-screen transition that COVERS the build.** A card-level opaque
overlay (the proven backdrop/HUD pattern — a control on the card, *not* in the
camera group, raised to the very top) shown **before** the teardown, held through
the build, then faded out to reveal the positioned level.

### 2.1 The level card
A composed "LEVEL n — NAME" card, biome-tinted (it can reuse the per-level
backdrop colour, so each card feels like its world). Show: the level number/name,
maybe a one-line flavour, and a subtle "ready" beat. This **replaces the current
`pfSplash` intro-pan reminder** (or precedes it): the splash currently appears
*after* the build, over the live level — fold its content into the card instead,
so the controls reminder is shown while the world is hidden, not over it.

### 2.2 The flow (per `pfStartGame`)
1. **Cover:** raise + show the opaque level card at the top; force one repaint so
   it's actually on screen (the build that follows is invisible behind it).
2. **Build under cover:** extend the screen lock to wrap the teardown too (or rely
   on the opaque card), so the construction never paints.
3. **Settle the camera** at the spawn (already deferred to scroll-0, keep that).
4. **Reveal:** unlock, hold the card briefly (~0.8–1.2s, the existing
   `gIntroPan` beat), then **fade the card out** (a short `blendLevel` ramp via a
   `send`-driven tick, or a quick cross-fade) to the live level. Control hands to
   the player as the fade completes (reuse the `gIntroPan` gate).

### 2.3 Transitions to cover (one mechanism, several callers)
- **Level start / R-restart / level-picker jump / hero pick (1–5):** all go
  through `pfStartGame` → the card covers them for free.
- **Level → level (`pfLevelClear` → `pfNextLevel`):** today it banners "LEVEL n
  CLEAR!" then `send`s the rebuild 1.2s later; make the card **fade IN** as the
  clear banner ends, so the advance is one continuous wipe (clear → card → next
  level), never a flash.
- **Death / respawn:** `pfHurt` respawns at a checkpoint without a full rebuild
  (just repositioning) — a brief screen flash/vignette is enough here, NOT the
  full card (a full card on every death would grate). Keep it light.

### 2.4 Bookends (the same overlay system buys these)
- **A title / start screen.** The demo currently boots straight into L1. A
  polished demo opens on a title (game name + "press SPACE to start" + the
  character-select moved here, where picking a hero is natural and can't
  accidentally restart a level — see §4). Build it with the same card overlay.
- **The win screen** (`pfWin`) already exists as an overlay — polish its
  composition (final-run stats: time, falls, gems, stars, coin score, hero) and
  give it the same visual language as the level cards.

### 2.5 Gotchas to respect (earned, see CLAUDE.md)
- The card is **screen chrome** — card-level, never `b2kCamAdopt`-ed, raised to
  `the number of controls of this card` like the HUD/pause overlay.
- `pfWipeStage` deletes `pf_*` card controls each build — the card must **not** be
  named `pf_*`, or use a name the build won't wipe, and be rebuilt/persisted
  deliberately.
- Don't `create` the card mid-game per the build-once law — build it once (in
  `buildPfUI`, bump `kPfUIVersion`) and show/hide/fade it.
- Keep it cheap: the fade is one `blendLevel` ramp on one control, throttled — not
  a per-frame field relayout.

---

## 3. Visual polish backlog (the OXT-pass items)

Things flagged "tunable / statically unverifiable" across the phases — confirm or
adjust on an OXT pass, level by level:

- **Coin tier colours.** The height rule makes most coins *silver* (the dominant
  look shifted from all-gold). Confirm it reads well; the thresholds in
  `pfMakeCoin` are a one-line tune if more gold is wanted.
- **Sprite facing.** Art-facing polarity is statically unverifiable (gotcha 26).
  We fixed flyers + ground ladybugs/frogs/snail; do a final sweep that **every**
  mover faces its travel direction across all 7 levels.
- **Scale & alignment.** The hero hitbox vs the visible art (the brick-smash gap
  lesson), enemy bind offsets (spook frames vs foes frames), the HUD sheet scale
  (0.6) and the heart/portrait row — confirm feet-on-ground and no clipping.
- **Scene density.** Some levels are sparser than others (decor placed clear of
  beats, but thin). A pass adding biome scenery (clear of the layout law's ~100px
  beats) makes each world feel inhabited rather than functional. **This is the
  lesson from the Clocktown rollback: composition needs a human eye, not a
  procedural fill — place scenery deliberately, a few strong reads per screen.**
- **Particles / juice.** Defeat poofs, confetti, dust, coin-pops — confirm they're
  consistent and not over-firing; the pools are built-once (don't regress that).
- **Parallax.** Single-layer biome drift is the current ceiling. True multi-layer
  depth is **blocked on transparent overlay art** (a cloud/fog PNG with alpha) the
  project would need to add — if it appears, wire a second drift layer (the
  plumbing is small). Until then, leave as-is.
- **Dark-level splash/card text** already flips light on L6/L7 — carry that rule
  into the level cards.

---

## 4. Feel & gameplay polish (tunables)

- **Jump/movement numbers** (`kMoveSpeed`, `kJumpSpeed`, coyote/buffer/jump-cut,
  `airJumps`, `wallJump*`, `dash*`) are first-pass — do a deliberate feel pass and
  lock them.
- **Spring heights** (the `b2kPlayerJump` apex), **swim feel** (`swimJump`/
  `swimGravity`), **lift speeds**, **conveyor push** — confirm each beat is
  comfortably clearable, never trial-and-error.
- **Hazard timing windows** — serpents, spinners, crushers, the saw/lift — confirm
  the "time it, never a stomp" hazards read fairly (the saw rule).
- **Difficulty curve.** L1 should onboard gently; L7 is the climax. Confirm the
  ramp across the 7 levels feels intentional (enemy density, pit widths, hazard
  mix), not random.
- **Character-select friction.** Today 1–5 rebuilds the *current* level (an
  accidental number press restarts you). **Move hero selection to the title /
  level-card screen** (§2.4) where a rebuild is free, and drop the always-on
  1–5 in-level binding (or gate it to the title only).

---

## 5. Audio polish

- **Coverage:** confirm every action has a cue (jump, land, coin/gem/star, hurt,
  win, checkpoint, spring, door, switch) and nothing is silent or doubled. Sounds
  are synthesized + survive teardown — mind the newest-cue guard when touching
  `*MakeSounds`.
- **Ambience (optional, stretch):** a light per-biome loop or pad would lift the
  "finished game" feel — but it's net-new content; treat as optional and keep the
  mute (M) authoritative.

---

## 6. UX / chrome polish

- **Dev level-picker.** The top-right menu is a dev convenience. For the final
  demo: keep it (it's handy for showing off any level) but consider gating it
  behind the debug toggle (`` ` ``), or style it so it reads as intentional, not
  leftover.
- **Pause / help overlay.** Confirm it lists every control accurately (it gained
  the 1–5 hero line; revisit if hero-select moves to the title).
- **Onboarding.** L1's opening should teach the core moves by level design (it
  mostly does); confirm the first 30 seconds never require an unexplained move.
- **Win screen.** Make the final-run summary the payoff: total time, falls, gems
  `n/m`, stars `n/m`, coin score, the chosen hero, a "flawless run" callout.

---

## 7. Code & repo cleanup

- **Dead/duplicate code.** Sweep for unused handlers and the camera-dead fallback
  paths now that the camera is proven; remove what no level reaches.
- **Self-test harness.** Re-run `examples/box2dxt-selftest.livecodescript`; ensure
  it still passes and covers the shipped feature set. Any Kit touch ⇒ bump
  `kStHarnessV` + re-sync embedded copies (CLAUDE.md law).
- **Embedded-Kit sync.** `python3 tools/sync-embedded-kit.py --check` clean across
  all examples.
- **Audit/gates green** after every edit; keep `tools/audit-platformer.py` clean
  (extend it for any new maker — e.g. the transition overlay needs no geometry, so
  no audit change).
- **Packaging.** Confirm `tools/package-extension.py --check` reports a complete
  `src/code/` tree and the dist stack runs from a fresh machine.

---

## 8. Documentation (this pass — mostly done)

- Stale "five levels" → "seven" fixed across README, `dist/INSTALL.md`, `CLAUDE.md`,
  `asset-expansion-plan.md`.
- `asset-expansion-plan.md` reframed: Phases A–G shipped; forward phases (H
  Clocktown / I alien-swim / J stretch) are **not pursued** (dev frozen) — kept as
  an as-built record + a "if we ever resume" appendix.
- Redundant pre-implementation docs (`game-engine-spec.md` design spec,
  `expansion-prep.md` intake plan) archived under `docs/archive/` (superseded by
  `kit-guide.md` + `kit-reference.md` and `plan.md` + `CHANGELOG.md`).
- This polish plan is the new forward-looking doc; `plan.md` + `CHANGELOG.md`
  remain the as-built record.

---

## 9. Definition of done (the final checklist)

- [x] **No visible build.** Every level start / advance / restart / hero-pick is
  masked by the transition card; the player never sees teardown or construction.
  *(Shipped — `pfCardCover`/`pfCardReveal`, PR #70; OXT-confirmed "working as
  expected".)*
- [x] **Bookends.** A title screen (with hero select) and a composed win screen.
  *(Shipped — boot title with live hero preview + recomposed win card, PR #70; the
  level cards are biome-illustrated, PR #71.)*
- [ ] **Facing & scale clean** on every sprite, all 7 levels (OXT-confirmed).
- [ ] **Feel locked** — jump/dash/swim/spring numbers deliberate, every beat
  fairly clearable, the difficulty ramp intentional.
- [ ] **Each world feels inhabited** — scenery placed by eye, not sparse, clear of
  beats.
- [ ] **Audio complete** — every action cued, nothing silent/doubled.
- [ ] **No dev seams** — the level-picker reads as intentional or is tucked behind
  debug; the debug overlay stays on `` ` ``.
- [ ] **Gates green** — `check-livecodescript.py`, `audit-platformer.py`, the
  self-test harness, embedded-Kit sync, all clean.
- [~] **Docs current** — README/getting-started/CLAUDE describe the 7-level final
  demo; this plan's items all checked. *(README + CLAUDE now describe the boot title +
  transition cards; the stale `fbc93b2` Clocktown recovery ref was corrected — that
  commit never existed. Remaining: tick the rest of this list as those passes land.)*
- [ ] **Packages clean** — a fresh install runs the demo end to end.

---

## 10. Suggested order of attack

1. **Transitions first** (§2) — biggest perceived-quality jump, and the title/win
   bookends fall out of the same overlay system.
2. **A full OXT feel + facing + scale pass** (§3–§4) — level by level, locking
   tunables and fixing any mirrored/misaligned art.
3. **Scene-composition pass** (§3) — deliberately dress each biome.
4. **Audio + UX sweep** (§5–§6).
5. **Code/repo cleanup + final gates + packaging** (§7).
6. **Docs final** (§8) and tick the §9 checklist.

Each step is an OXT pass with the user; nothing here is "claim it works" — it's
"make it, then confirm it on the engine."
