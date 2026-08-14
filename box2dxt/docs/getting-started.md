# Getting Started with Box2Dxt

This guide takes you from nothing to a running, draggable physics scene in
**OpenXTalk (OXT)** — or any compatible **LiveCode 9.6.3+** IDE. It assumes no
C toolchain: you install a prebuilt extension (the native library is bundled in).

> **Just want to *play*, not code?** If you were handed the prebuilt **platformer
> package** (a zip with the extension — native library bundled in — and a saved
> stack), open its `INSTALL.md` and follow two steps — no scripting. This guide
> is for building your *own* scenes from scratch.

- [1. Install the extension](#1-install-the-extension)
- [2. Load it while developing](#2-load-it-while-developing)
- [3. Sanity check](#3-sanity-check)
- [4. Your first scene (the Kit)](#4-your-first-scene-the-kit)
- [5. Attach controls you designed in the IDE](#5-attach-controls-you-designed-in-the-ide)
- [6. Run the full demo](#6-run-the-full-demo)
- [Troubleshooting](#troubleshooting)
- [Where to go next](#where-to-go-next)

---

## 1. Install the extension

Box2Dxt is a real physics engine compiled to a native library — and that library
ships **inside the extension**, so there's nothing to download, rename, or place
by hand. Installing the extension is the only setup step, and it's identical on
Windows, macOS, and Linux:

1. In OXT, open **Tools → Extension Builder** and open
   [`src/box2dxt.lcb`](../src/box2dxt.lcb).
2. Click **Package** — this rolls the per-platform libraries (committed under
   `src/code/<arch>-<platform>/`) into a `box2dxt.lce` — then install that `.lce`
   via **Tools → Extension Manager**.

The engine then loads the correct library for your platform automatically —
**no `/usr/lib`, no `sudo`, no `LD_LIBRARY_PATH`, no renaming.**

> The per-platform libraries under `src/code/<arch>-<platform>/` are committed
> (built and tested by CI, and attached to each [Release](../../releases)), so
> this is already done in the repo. Prefer building the library yourself? See
> [building.md](building.md).

## 2. Load it while developing

You don't have to repackage on every edit:

- **Extension Builder → Test** compiles and loads `src/box2dxt.lcb` in place — it
  reads the `code/` folder beside the `.lcb`, so the native library loads too.
- **From script:** `load extension from file (the defaultFolder & "/box2dxt.lcb")`
- **No-packaging fallback:** drop `box2dxt.{so,dll,dylib}` (bare name) next to your
  **saved** stack; the Kit points the engine at it on `b2kSetup`, so even Linux
  needs no system path.

Foreign bindings resolve on **first use**, so the library only has to be in place
by the time a `b2…` handler first runs — not when the extension loads.

## 3. Sanity check

Open the Message Box and run:

```
put b2Version()
```

You should see `4` (the shim ABI version). If you get an error instead, the
extension didn't load or the native library can't be found — jump to
[Troubleshooting](#troubleshooting).

## 4. Your first scene (the Kit)

The **Kit** (`box2dxt-kit.livecodescript`) is the friendly layer: you work in
**pixels, screen coordinates and degrees**, and it owns the world, the
fixed-timestep loop, and per-frame control updates.

1. Open your stack's script (*Object → Stack Script*) and paste in the entire
   contents of [`src/box2dxt-kit.livecodescript`](../src/box2dxt-kit.livecodescript).
   (For reuse across stacks, save it as a library stack and `start using` it.)
2. Add these handlers to the **card** script:

```
on openCard
   b2kQuickStart                          -- world + gravity + card-edge walls + go
   b2kSpawnBall 200, 80, 50               -- create & drop a 50px ball
   b2kSpawnBox 260, 80, 60, 40, "orange"  -- (read `the result` for the ref)
end openCard

on mouseDown
   get b2kGrab(the mouseH, the mouseV)    -- grab a body under the pointer
end mouseDown

on mouseUp
   b2kRelease
end mouseUp

on closeCard
   b2kStop                                -- stop the loop, free the world
end closeCard
```

Open the card. A ball and a box fall, settle on the bottom edge of the card, and
you can **drag** them with the mouse. That's it — a live physics scene.

`b2kQuickStart` is the one-call setup: it creates the world, applies gravity,
builds static walls around the card edges, and starts the loop. From there,
`b2kSpawnBall`/`b2kSpawnBox` create controls *and* their bodies in one go.

**Try a few more things** in the Message Box while the card is open:

```
b2kSpawnCapsule 220, 60, 70, 28, "teal"   -- a pill-shaped body
put the result into tPill                  -- every b2kSpawn… reports its ref
b2kImpulse tPill, 0, -12                    -- a sharp upward kick (mass-aware)
b2kSpawnBox 320, 40, 50, 50, "purple"      -- drop another box in
```

Negative `y` is *up* here (screen coordinates). The
[Kit Reference](kit-reference.md) lists the full spawn / force / query surface.

## 5. Attach controls you designed in the IDE

Prefer to draw your objects in the IDE? Attach physics to **any** control —
graphics, images, buttons, fields. Graphics and **dynamic images rotate** with
their body; buttons/fields and other controls follow position only (upright).

```
b2kSetup                                     -- world + gravity, auto origin
b2kAddStatic the long id of graphic "Floor"  -- immovable
b2kAddBox    the long id of graphic "Crate"  -- dynamic box
b2kAddBall   the long id of graphic "Ball"   -- dynamic circle
b2kContactTarget the long id of me           -- receive `on b2kContact pA, pB`
b2kStart                                      -- begin the loop
```

Now `Crate` and `Ball` fall and collide with `Floor`, and your card gets a
`b2kContact` message whenever two attached controls begin touching.

See the [Kit Reference](kit-reference.md) for the full `b2k…` surface
(materials, joints, forces, queries, events).

## 6. Run the full demo

[`examples/box2dxt-demo.livecodescript`](../examples/box2dxt-demo.livecodescript)
is a self-building, multi-scene **testbed** — it creates its own buttons, HUD and
scenes at runtime, so there's nothing to lay out.

The demo is **self-contained**: it bundles a copy of the Kit, so it runs from a
single paste — no separate setup.

1. Make sure the extension is loaded and `put b2Version()` returns `4`.
2. Paste the whole of
   [`examples/box2dxt-demo.livecodescript`](../examples/box2dxt-demo.livecodescript)
   into a stack's script (*Object → Stack Script*). If you previously pasted a
   demo or the Kit into the **card** script, clear that first.
3. Reopen the card, or run `startBox2DDemo` in the Message Box (`stopBox2DDemo`
   stops it).

> The demo embeds a verbatim copy of the Kit purely for one-paste convenience.
> For your own projects, use the standalone Kit
> ([`src/box2dxt-kit.livecodescript`](../src/box2dxt-kit.livecodescript)) as
> shown in steps 4–5 above.

Click the tabs up top to switch scenes:

| Scene | Shows off |
|-------|-----------|
| **Playground** | boxes, a ball, a capsule, polygons, a hinged **pendulum**, a powered **windmill** (hinge motor), and a **see-saw** |
| **Pyramid** | a tall stack; pick the **Bomb** tool and click beside it for a blast |
| **Cradle** | a Newton's cradle — hinge joints + restitution |
| **Bridge** | a plank bridge of hinge joints you can load up |
| **Vehicle** | a car (wheel joints + motor + spring suspension) you **drive with ←/→** over bumps |
| **Lidar** | a live **ray-cast** scanner that follows your mouse and stops each ray at the nearest shape |

Across every scene you can **drag** any dynamic body, **click empty space** to
drop the selected shape (Box/Ball/Capsule/Poly/Bomb), and bodies **flash white**
the instant they begin touching (contact events). A HUD shows live FPS and body
count. The whole demo is written with `b2k…` calls — read it as a worked example
of the [Kit](kit-reference.md).

## Troubleshooting

| Symptom | Likely cause & fix |
|---------|--------------------|
| `b2Version()` throws / "handler not found" | The extension isn't loaded. Re-add and **Load** `box2dxt.lcb` in the Extension Manager. |
| First `b2…` call (or `b2Version()`) errors **"unable to load foreign library"** | The extension loaded without its bundled library. Install the **packaged** extension (Extension Builder → **Package** `src/box2dxt.lcb` → install the `.lce`), or **Test** it with the `code/` folder beside the `.lcb`. Quick fallback: drop `box2dxt.{dll,dylib,so}` (bare name) next to your **saved** stack. (Tip: launch OXT from a terminal — it prints `dlopen failed <name>` showing the filename it wants.) |
| `b2Version()` returns a different number | Your `box2dxt.lcb` and native library are from different versions. Rebuild/redownload both from the same tag. |
| Library won't load on an older PC (Linux/Windows) | The CPU may lack AVX2. Build with `-DBOX2D_DISABLE_SIMD=ON` (see [building.md](building.md#platform--cpu-notes)), or grab a Release binary built for older CPUs. |
| Bodies jitter or behave non-deterministically | You're stepping with a variable timestep. Let the Kit drive the loop, or step in fixed 1/60 s chunks (see [API Reference → Notes](api-reference.md#notes-and-gotchas)). |
| Objects fly off instantly / explode | Sizes are wrong for Box2D's MKS units. Keep moving objects roughly 4–400 px at the default 40 px/m scale. |

## Where to go next

- [**Kit Guide**](kit-guide.md) — the complete, teach-you-everything walkthrough of the `b2k…` toolkit, with runnable examples.
- [Kit Reference](kit-reference.md) — the same `b2k…` API as quick-lookup tables.
- **Example games** — beyond the demo, [`examples/`](../examples/) ships a full **platformer**, an angry-birds-style **slingshot**, and a **contraption builder**, each a single self-contained paste. Hand one to someone else as a zero-setup zip with [`tools/make-release.py`](building.md#packaging-a-distribution-zip).
- [API Reference](api-reference.md) — the low-level `b2…` API and units/gotchas.
- [Architecture](architecture.md) — how it all works under the hood.
- [Building](building.md) — compile the native library yourself.
