# render3dxt

**A textured 3D renderer for OpenXTalk / the xTalk family: a scene goes in, a picture comes out.**

render3dxt draws a 3D scene into an ordinary image control. A stack describes meshes,
materials, lights and a camera; one call returns the finished picture as `imageData`, and the
stack sets it on an image. There is no window of its own and no graphics card: the picture is
made on the processor, inside the library, on several threads, so it works wherever an OXT
stack does and looks the same everywhere.

```
stb_image + fast_obj (pinned, compiled in)              pictures and models from files
   |- C shim   src/render3d_shim.c  ->  render3dxt.{so,dll,dylib}   (ABI: r3x_*, v1)
        |- LCB binding  src/render3dxt.lcb     (org.openxtalk.library.renderthreed; public r3*)
```

It is the drawing half of a pair. [box3dxt](https://github.com/SethMorrowSoftware/box3dxt)
simulates and tells you where things are; render3dxt shows them. Neither needs the other, and
they are made to meet: the same world (y up, metres, a rotation as a quaternion), the same
transform text, the same camera numbers, and one call that carries a whole physics step to
the picture.

## What it can do

- **Models.** Wavefront OBJ files with their material files and the pictures those name
  (`r3MeshLoadObj`), or the same from text with nothing read from disk (`r3MeshParseObj`);
  boxes, planes, spheres, cylinders and capsules made to measure; a mesh built a vertex and a
  triangle at a time; a mesh from a list of triangles as text.
- **Textures.** PNG, JPEG, BMP and TGA from a file or from bytes, an image control's own
  `imageData`, or a checkerboard made on the spot. Smooth or sharp, repeating or clamped,
  with see-through cut-outs.
- **Materials.** Colour, texture, a highlight, glow, flat or smooth shading, one or two
  sides. A node can wear its own material over a shared mesh.
- **Lights and air.** Sun-like and lamp-like lights (eight a scene), ambient light, distance
  fog, a background colour.
- **A camera you can reason about.** An eye, a target and a field of view. `r3SceneProject`
  says where a point of the world lands in the picture and `r3SceneRay` says where a point of
  the picture leads into the world.
- **Clicking on things.** `r3ScenePick` returns the node under a point of the picture and
  `r3HitText` the exact place it was hit; `r3SceneRayCast` does the same along any ray.
- **Smooth edges.** One to four samples each way per pixel (`r3SceneSetSupersample`).
- **Speed.** Everything per pixel is native and spread over the processor's cores. The
  picture is identical whatever the thread count.
- **The family's rules.** No thread ever runs script: every drawing thread is finished
  before `r3SceneRender` returns (rule 1). Every export checks its handles and numbers before
  it uses them, and a refused call returns 0 or empty with a reason in `r3LastError()`: a
  frame loop cannot be stopped by a bad number (rule 2). Results that are several numbers
  cross as one short text (rule 3). Every handle is a generation-tagged integer, and a stale
  one is a harmless no-op (rule 4).

## Quick taste

```livecodescript
local sScene, sCrate

on showCrate
   put r3SceneCreate() into sScene                    -- comes with a camera and a light
   put r3NodeCreate(sScene, r3MeshBox(0.5, 0.5, 0.5)) into sCrate
   r3NodeSetMaterial sCrate, r3MaterialCreate(200, 120, 60)
   r3SceneSetCamera sScene, 2, 2, 4,  0, 0, 0,  50    -- eye, target, field of view
   set the imageData of image "View" to r3SceneRender(sScene, 640, 480)
end showCrate
```

Image "View" must be 640 by 480. With box3dxt, a frame of a simulation is four lines:

```livecodescript
b3WorldStep sWorld, 1/60, 4
get b3WorldUpdateMoves(sWorld)
get r3SceneApplyMoves(sScene, b3MovesText())          -- every moved body's node follows it
set the imageData of image "View" to r3SceneRender(sScene, 640, 480)
```

[docs/getting-started.md](docs/getting-started.md) carries on from there, and
[examples/render3d-physics-demo.livecodescript](examples/render3d-physics-demo.livecodescript)
is that loop as a whole stack: crates, balls and a gem falling, a camera you drag, things
you click to kick.

## Status

Joined the suite on 2026-11-20. What has run, and where:

- **Natively**, on x86_64 Linux: the smoke test calls every export of the shim and checks
  the pictures by reading pixels back; it is clean under ASan/UBSan, and under TSan for the
  drawing threads. A random-call test (`tests/fuzz_test.c`) throws valid, stale and hostile
  arguments at every export. Both also pass as a 32-bit build and as WebAssembly under node.
- **On an engine**, the same day, OXT-Beyond's headless Linux server engine (9.7.1-OXT,
  x86_64) over locally built libraries, three tests: `tests/engine-selftest.lc` (the module
  loads, the ABI check passes, scenes built from script draw the pixels they should, every
  public handler is called); `tests/engine-interop.lc` (box3dxt loaded beside it: a Box3D
  simulation is drawn and the picture agrees with where Box3D says the bodies are); and
  `tests/engine-demo.lc` (the demo stack is opened and driven: its window's controls are
  built, its boot self-check is green, frames run on the timer, the buttons act, closing
  frees everything).
- **Not yet:** no desktop IDE has loaded it, so nobody has SEEN a picture of it on a screen
  through an engine, and no engine on Windows, macOS, Android or the web has run it: on
  those it is verified statically; needs an OXT pass. No library is committed under
  `src/code/` yet; the suite's release-binaries dispatch lands them.

How fast it is depends on the machine. As one measure: a 624 by 468 picture of the demo's
scene with smooth edges took about 8 ms on four threads of a 2.1 GHz virtual machine, and a
640 by 480 picture of a 45,000-triangle model about 15 ms. `r3SceneStats` reports the time
of the last picture on yours.

## Building and testing

```sh
cmake -S . -B build -DRENDER3DXT_BUILD_TESTS=ON && cmake --build build -j && (cd build && ctest)
cmake -S . -B build-asan -DRENDER3DXT_BUILD_TESTS=ON -DRENDER3DXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug && cmake --build build-asan -j && (cd build-asan && ctest)
bash tools/run-gates.sh
```

A C11 compiler and CMake 3.22 are all it needs; the two readers are fetched at configure
time. [docs/building.md](docs/building.md) has the details.

## Documentation

- [docs/getting-started.md](docs/getting-started.md) - the conventions, a first picture, a
  frame loop with box3dxt, models and textures, the limits every call is held to.
- [docs/api-reference.md](docs/api-reference.md) - every `r3*` handler, generated from the
  binding's doc blocks.
- [docs/building.md](docs/building.md) - builds, sanitizers, the tests, the gates.
- [CLAUDE.md](CLAUDE.md) - rules and gotchas for anyone changing this member.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

render3dxt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`render3dxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/render3dxt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `render3dxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port render3dxt --ref pull/<n>/head`, keeping its
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

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `examples/render3d-physics-demo.livecodescript`.
- The boot self-check block (`tools/demo-selfcheck.livecodescript`; gate `tools/check-demo-selfcheck-drift.py`) in `examples/render3d-physics-demo.livecodescript`.
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

MIT (see [LICENSE](LICENSE)). stb_image (Sean Barrett) and fast_obj (thisistherk) are
compiled in, both under the MIT license; their notices are in the same file.
