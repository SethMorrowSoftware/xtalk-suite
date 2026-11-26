# box3dxt

**Box3D - 3D rigid-body physics - for OpenXTalk / the xTalk family.**

[Box3D](https://github.com/erincatto/box3d) is Erin Catto's 3D physics engine, the 3D
successor of Box2D: rigid bodies, convex and mesh shapes, eight kinds of joint, ray casts and
contact events, written in C17 and released under the MIT license. box3dxt binds it behind the
family's flat C shim and a thin LCB layer, the way box2dxt binds Box2D:

```
Box3D (pinned to a commit, static)                the physics
   |- C shim   src/box3d_shim.c  ->  box3dxt.{so,dll,dylib}     (ABI: b3x_*, v2)
        |- LCB binding  src/box3dxt.lcb     (org.openxtalk.library.boxthreed; public b3*)
```

It moves bodies and tells you where they are, and it can SHOW them: a small software
renderer inside the library paints a world into the imageData of an image, with no graphics
library and no drawing code in the stack. It is there to see a simulation, not to be a game
renderer (no textures; one light). The suite's render3dxt is the textured one, and the two
count cameras, pictures and rays the same way.

## What it can do

- **Worlds and bodies.** Any number of worlds (128 at once); static, kinematic and dynamic
  bodies; forces, impulses, damping, gravity scale, sleeping, motion locks, bullets.
- **Shapes.** Sphere, capsule, box, cylinder, cone, convex hull (from points), triangle mesh
  and height field (static bodies), with density, friction, restitution, rolling resistance,
  collision filters and sensors.
- **Joints.** Revolute, prismatic, spherical, weld, distance, wheel, motor and parallel, with
  their limits, springs and motors, plus a filter joint that only stops two bodies colliding.
- **Queries.** Ray casts (all hits or the closest), a swept sphere, box and sphere overlaps,
  each through an optional category filter.
- **A picture of the world.** `b3RenderWorld` draws every shape, solid, lit and depth-tested
  (or as a wireframe, or with outlines), into a picture up to 2048 pixels each way;
  `b3RenderPixels` is that picture as imageData. A pixel names the shape drawn there and its
  distance, a world point projects into the picture, and a click becomes a ray for
  `b3CastRayClosest`. `b3ShapeTrianglesText` hands any shape to another renderer as triangles.
- **Events.** Contact begin / end / hit, sensor enter / leave, the bodies that moved in the
  last step, and joints pushed past a force threshold: all read by polling after a step, so no
  callback ever runs script.
- **The family's rules.** Nothing runs on a foreign thread into script (rule 1); every export
  validates before it calls Box3D and none can throw across the boundary (rule 2: the shim is
  C, so there is nothing to throw, and Box3D's asserts are counted, not fatal); results that
  are several numbers cross as one short text (rule 3); every handle is a generation-tagged
  integer, and a stale one is a harmless no-op (rule 4).

## Quick taste

```livecodescript
local sWorld, sBall

on startDrop
   put b3WorldCreate(0, -10, 0, 1) into sWorld                -- gravity x y z, worker threads
   get b3ShapeAddBox(b3BodyCreate(sWorld, 0, 0, -1, 0), 20, 1, 20, 0, 0.6, 0)   -- a static floor
   put b3BodyCreate(sWorld, 2, 0, 5, 0) into sBall            -- 2 = dynamic, at x y z
   get b3ShapeAddSphere(sBall, 0, 0, 0, 0.5, 1, 0.6, 0.4)     -- centre, radius, density, friction, bounce
   send "dropFrame" to me in 16 milliseconds
end startDrop

on dropFrame
   b3WorldStep sWorld, 1/60, 4
   put b3BodyPosition(sBall) into field "where"               -- "x,y,z" in metres
   if b3BodyIsAwake(sBall) then send "dropFrame" to me in 16 milliseconds
end dropFrame
```

[docs/getting-started.md](docs/getting-started.md) carries on from there.

## The game Kit (`b3k...`)

For making games rather than simulations, `src/box3dxt-kit.livecodescript` is a pure-script
toolkit over the binding, the 3D sibling of box2dxt's b2k Kit. You work in metres and degrees
with y up; the Kit runs the world on a fixed step, draws it into one image, moves an orbiting
camera, reads the keyboard, walks a player about, and sends your script `b3kFrame`,
`b3kContact`, `b3kSensorEnter` and `b3kFell`. It draws with the suite's render3dxt when that
extension is loaded (textured, lit, smooth edges) and with box3dxt's own renderer when it is
not; the game code is the same either way.

```livecodescript
on openCard
   b3kQuickStart                          -- world, view, ground, camera, go
   b3kSpawnBox 0, 4, 0, 1, 1, 1, "orange"
   b3kPlayerMake 0, 1, 3                  -- arrows or WASD walk, space jumps
end openCard

on closeCard
   b3kTeardown
end closeCard
```

[docs/kit-guide.md](docs/kit-guide.md) teaches it; [docs/kit-reference.md](docs/kit-reference.md)
lists every handler. `examples/box3dxt-orb-island.livecodescript` is a small game on it, one
file to paste into a stack: walk a floating island, find eight golden orbs, mind the sweeper,
the wrecking ball and the edge.

## Status

Joined the suite on 2026-11-20. What has run, and where:

- **Natively**, on x86_64 Linux: the smoke test calls every export of the shim and checks what
  comes back, clean under ASan/UBSan with Box3D's own asserts switched on; a random-call test
  (`tests/fuzz_test.c`) throws valid, stale and hostile arguments at every export and audits
  the worlds as it goes. Both also pass as a 32-bit build and as WebAssembly under node.
- **On an engine**, the same day: `tests/engine-selftest.lc` ran on OXT-Beyond's headless
  Linux server engine (9.7.1-OXT, x86_64) over a locally built library. It loaded the module,
  passed the ABI check, dropped and stacked bodies, cast rays, read events and joints, and
  called every public handler once.
- **In the desktop IDE**, the same day: OXT-Beyond's IDE on 64-bit Linux (engine
  9.7.1-BeyondEngine build 25923; Ubuntu 24.04) loaded a library built on that machine from
  the suite's commit 144d529, by `load extension` and a `revLibraryMapping` line, not as an
  installed extension. A stack built there dropped twelve boxes and spheres in a `send in`
  frame loop: they fell as gravity says, landed at the right height and slept, a ray cast
  found the ground, contact events arrived, a reset repeated the run exactly, and Box3D
  counted no assert. That is one stack on one machine, not the release library.
- **A real model** (2026-11-20): the Utah teapot, 3644 points and 6320 triangles, is loaded
  as a static mesh and as falling hulls by the smoke test, which checks rays at it against
  a ray-triangle test of its own, and from its `.obj` file by the engine self-test.
- **The sky** (ABI 3, 2026-11-21): `b3RenderSetSky` paints the picture behind the shapes
  from one colour at the top to another at the bottom; `b3RenderSetBackground` is unchanged.
  Held natively by hand-worked rows and on the headless Linux server engine, over a locally
  built library and then over the committed `x86_64-linux` one (below); no IDE has drawn one
  yet: verified statically; needs an OXT pass.
- **The renderer** (ABI 2, 2026-11-20): the smoke test holds a picture to Box3D itself (the
  shape and the distance at a pixel against a ray cast through it, over every shape kind and
  the teapot, from five cameras) and to arithmetic done by hand for one square-on box; the
  random-call test renders thousands of small pictures of whatever the other calls left and
  reads every byte. On the server engine the self-test takes the picture as binary data and
  reads its bytes. In OXT-Beyond's desktop IDE on 64-bit Linux the same day (a library built
  on that machine from 9b7b59a, loaded by hand as above) a stack showed the teapot scene in
  an image, the right way up and in the right colours, in all three modes; a click through
  `b3RenderShapeAt` and `b3RenderRay` named the body under it; about 30 frames a second
  solid at 640 by 400 with the engine's default paintCompression and about 48 with "rle"
  (`docs/getting-started.md`, "Seeing the world");
  four minutes with up to 150 spheres counted no assert. One stack on one machine. On
  Windows the renderer has run in the IDE from script, its picture read as data and never
  shown (below); in a window there, and on macOS, it is verified statically; needs an OXT
  pass.
- **The game Kit and Orb Island** (2026-11-21): `tests/engine-kit.lc` runs the Kit as a
  library on the headless Linux server engine (9.7.1-OXT, a locally built library) and checks
  it scene by scene, hand-stepped so every number is reproducible, with box3dxt's renderer and
  again with render3dxt (built from its pull request); `tests/engine-demo.lc` builds Orb
  Island's window there and plays the game through, both ways and with no extension loaded.
  Orb Island has also played in a browser once (2026-11-21, Chromium): a web engine built
  locally from OXT-Beyond's pull request 606, with the committed web archives of box3dxt and
  render3dxt linked in (each SHA-256 checked against its pin), opened it and ran its frame
  loop, render3dxt drawing about 12 pictures a second, the orb counter and timer running and
  nothing in the console; its keys were not driven. The same day it played in a published
  player, the web-2026.11.21 pre-release's Stack Player (box3dxt's ABI 2 web archive, no
  render3dxt), in Chromium, built into a stack file for the community gallery: the window
  built at its size, W walked to an orb that was counted, C dropped crates, V said render3dxt
  was not loaded, a click knocked crates over and a drag turned the camera. Neither has run
  in an IDE: a real window, keyboard and mouse there are verified statically; needs an OXT
  pass (the game's header lists what to look at).
- **Orb Island 1.2 and the Kit's glow, lamps and looks** (2026-11-26): the island four
  times the size, sixteen orbs, a pressure plate and vault, crumbling and turning platforms,
  checkpoint flags, Kenney's CC0 models from three of his kits (`examples/models/`), a
  character animated in parts (`b3kAddLookPart`, `b3kPoseLookPart`, `b3kSetLookPose`),
  `b3kSetGlow`, `b3kAddLamp`, `b3kSetLook` and a coloured sun, and the game playing gamepadxt
  and audioxt when they are loaded. On OXT-Beyond 0.2.8-dp.2.1's Linux server engine
  (9.7.1-BeyondEngine) with the committed `x86_64-linux` libraries of all four:
  `tests/engine-kit.lc` passed 243 checks with render3dxt and 215 without, and
  `tests/engine-demo.lc` 201 with render3dxt, gamepadxt (a virtual pad) and audioxt (its
  silent device), 196 with gamepadxt and audioxt but no render3dxt, 186 with render3dxt
  alone beside box3dxt, 181 with box3dxt alone and 6 with no extension. In the gallery's web
  Stack Player (web-2026.11.22, headless Chromium) it built, walked to an orb, found both
  extensions and drew 28 pictures a second where 1.1 drew 36, measured back to back on the
  same machine. A real gamepad, the sound heard and an IDE
  window are verified statically; needs an OXT pass.
- **On Windows, the release library** (2026-11-21): OXT-Beyond 0.2.8-dp.1's IDE on the
  maintainer's Windows PC (engine 9.7.1-BeyondEngine build 25923, x86_64), with box3dxt
  installed as an extension from the ABI 2 files then on the suite's main branch: the file
  the IDE had loaded was the committed `x86_64-win32/box3dxt.dll` of release run 44806507517
  (its SHA-256 read there, 257e576f...). From script in a hidden stack: `b3ABIVersion()` 2
  and `b3LibraryVersion()` "box3dxt ABI 2; Box3D 0.2.0"; a 0.5 m ball dropped on a box floor
  fell 1.26 m in 30 steps of 1/60 s, moving at 5 m/s, and rested at a height of 0.49993
  after 270; a ray straight down hit a box and then the floor; a ball with events on gave one
  begin-touch event naming it; a 200 by 100 picture crossed as 80,000 bytes of data, its
  centre pixel named the box at 9 m, a corner landed where the arithmetic says and the ray
  through a pixel found the shape that pixel showed; Box3D counted no assert. The steps ran
  in a loop, not on a timer, and nothing was drawn in a window.
- **Not yet:** no engine on macOS has run it, nor a released web engine (the one browser run
  is above); on Windows only the script checks above have run (no window, frame loop or
  game) and on Android one call (below): beyond those it is verified statically; needs an
  OXT pass. Of the ABI 2 libraries committed on 2026-11-20 (six desktop platforms, four
  Android ABIs, a web archive) three met an engine: the web archive in that browser, the
  `x86_64-win32` one in that Windows IDE, and the `x86_64-android` one, which answered
  `b3LibraryVersion()` ("box3dxt ABI 2; Box3D 0.2.0") in an app that OXT-Beyond's pull
  request 606 built and ran on x86_64 emulators (Android 13, and Android 16 with 16 KB pages;
  its run 44863595033). The libraries committed now are ABI 3, from release run 44914775780
  on 2026-11-21 (the web archive built separately), tested where they were built; of them
  only the `x86_64-linux` library has met an engine: the same day OXT-Beyond 0.2.8-dp.1's
  Linux server engine loaded it (its SHA-256 as committed, dc3280f7...) and passed with it
  the engine self-test (107 checks, the sky's among them), the Kit's test (204 with
  render3dxt, 193 without) and Orb Island's (102 with render3dxt, 99 without).

Box3D itself is young (no tagged release yet; `b3LibraryVersion()` reports what it calls itself), which is why this member pins
it to a commit and why the shim holds every argument to stated limits before Box3D sees it.

## Building and testing

```sh
cmake -S . -B build -DBOX3DXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release && cmake --build build -j && (cd build && ctest)
cmake -S . -B build-asan -DBOX3DXT_BUILD_TESTS=ON -DBOX3DXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug && cmake --build build-asan -j && (cd build-asan && ctest)
bash tools/run-gates.sh
```

A C17 compiler and CMake 3.22 are all it needs; Box3D is fetched at configure time.
[docs/building.md](docs/building.md) has the details.

## Documentation

- [docs/getting-started.md](docs/getting-started.md) - units, the frame loop, the limits, the
  rules that decide whether a scene works.
- [docs/api-reference.md](docs/api-reference.md) - every `b3*` handler, generated from the
  binding's doc blocks.
- [docs/kit-guide.md](docs/kit-guide.md) - the game Kit, from an empty stack to a game.
- [docs/kit-reference.md](docs/kit-reference.md) - every `b3k*` handler, generated from the
  Kit's doc blocks.
- [docs/building.md](docs/building.md) - builds, sanitizers, the tests, the gates.
- [CLAUDE.md](CLAUDE.md) - rules and gotchas for anyone changing this member.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

box3dxt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`box3dxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/box3dxt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `box3dxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port box3dxt --ref pull/<n>/head`, keeping its
author - but a commit made here directly holds up the next publish until
it has been ported, because publishing never overwrites work it did not
write. The suite's `docs/MEMBER-REPO-SPLIT.md` is the whole workflow.

**Suite-level paths cited from here.** This member's `CLAUDE.md` and
`docs/` cite files that live at the suite root, not in this tree:
`docs/OXT-ENGINE-NOTES.md` (engine behaviour, the authoritative list),
`docs/OXT-PASS-RUNBOOK.md`, `tools/build-all.sh`,
`tests/suite-selftest.livecodescript` and the suite-level `docs/`
index. Read them at `https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/<path>`. A path of the
form `../<member>/...` names a sibling member of the suite; each has its
own repository, listed in `tools/member-registry.py` there.

**Sibling members this member's gates need beside it.** None: `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
needs nothing but this checkout and Python 3.

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `examples/box3dxt-orb-island.livecodescript`.
- `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

**What this repository cannot check on its own.** The suite-wide gates -
cross-library name disjointness (`tools/check-cross-library-names.py`),
the carried-copy drift gates above, embed freshness, the cross-member
handler-call and typed-boundary checks (`tools/check-handler-calls.py`,
`tools/check-lcb-call-types.py`), the timer-pin closure, and the suite
paste's coverage ratchet (`tools/check-suite-coverage.py`) - run only in
the suite. `tools/run-gates.sh` here is this member's own list, and the
suite's `tools/build-all.sh` runs that same script, so the two cannot
disagree about what this member's gates are.

<!-- ==== SUITE RELATIONSHIP END ==== -->

## License

MIT (see [LICENSE](LICENSE)). Box3D is Erin Catto's, also MIT; its notice is in the same file.
