# CLAUDE.md

Guidance for Claude Code in the box3dxt member of the xtalk-suite monorepo (`box3dxt/`). Where
anything disagrees, the code and this file win.

## What this is

**box3dxt** binds Box3D (Erin Catto's 3D rigid-body engine, MIT, C17) for OXT: Box3D (static,
FetchContent, pinned to a COMMIT in `CMakeLists.txt` because it has no release tag yet) -> the
C shim `src/box3d_shim.c` (exports `b3x_*`, **ABI 2**: `B3X_ABI_VERSION` there equals the
literal in `checkABI()` of the binding) -> ONE library `box3dxt.{so,dll,dylib}` (bare token),
or `box3dxt.a` for the web -> the LCB binding `src/box3dxt.lcb`
(`org.openxtalk.library.boxthreed`, public `b3*`). box2dxt is its ancestor; read that
member's CLAUDE.md for the reasons behind the shared shape.

## The rules

1. **Never call script from a foreign thread.** Box3D's worker threads live inside
   `b3World_Step` and are joined before it returns; the shim registers no callback that
   reaches script. Events are copied out by the `b3x_world_update_*` calls and read by index.
2. **Nothing crosses the boundary but values.** The shim is C: there is no exception to
   firewall. What stands in its place: every export validates its handles and arguments
   before it calls Box3D, and Box3D's assert and log hooks are replaced (`install_hooks`) so
   an assert is counted (`b3x_assert_count`) and never aborts the host or prints to its
   console.
3. **Several numbers cross as one text** (`"x,y,z"`), in a static buffer returned as a
   `const char *`. The binding declares those returns `Pointer` and copies them with
   `textOf()`. NEVER `ZStringNative`: the engine frees a returned C string, and freeing a
   static buffer killed the first engine run (2026-11-20). The signature gate refuses it.
4. **Generation-tagged integer handles**, validated before use. A slot whose generation
   would wrap is retired, never reused, so a stale handle cannot come back to life.
5. **Box3D trusts its caller; the shim does not.** In a Release build Box3D's asserts are
   compiled out, so an argument it would have asserted on becomes memory corruption. Four
   layers, all in the shim, all found by the tests and dated there:
   - **the envelope**: every number finite and within stated bounds (`fin`, `size_ok`,
     `local_ok`, `hertz_ok`, `ratio_ok`); docs/getting-started.md has the table;
   - **the mass budget**: a dynamic body heavier than a float can carry is refused before
     (`mass_fits`) and checked after (`body_mass_sane`);
   - **the stale move index** (`s_sleepUnsafe`): no forced sleep between an enable or a type
     change and the next step;
   - **the net** (`sweep_unstable`): after every step, a body whose position is not a number
     or whose velocity has run away is destroyed.
   A new export that passes a number to Box3D goes through the envelope. A new way to crash
   Box3D found by the fuzz test gets a guard in the shim AND a named case in the smoke test.
6. **Names are mechanical.** `b3x_body_set_position` is bound as `_body_set_position` and
   wrapped by `b3BodySetPosition`; nothing is renamed by hand
   (`tools/check-lcb-signatures.py`, fixture `tools/test-lcb-signatures.py`).
7. **Done means:** a shim change is green in `smoke` AND `fuzz` under
   `-DBOX3DXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug` (Debug so Box3D's asserts are in);
   a binding change passes `lc-compile -Werror` and `tests/engine-selftest.lc` on the server
   engine; a Kit change passes `tests/engine-kit.lc` with and without render3dxt and
   `tests/engine-demo.lc` with box3dxt, with render3dxt and with `-` (no extension); all pass
   `bash tools/run-gates.sh`. An ABI change bumps `B3X_ABI_VERSION` and
   the two literals in `checkABI()` together. Native-library changes refresh the committed
   binaries through the suite's `release-binaries.yml`; `native-box3dxt.yml` never commits.

## Generated text: edit the source, then regenerate

| What | Written by |
|---|---|
| the declaration blocks of both C tests, the joint family table, the fuzz call table | `tools/check-smoke-coverage.py --write` |
| `sweepEveryHandler` in `tests/engine-selftest.lc` | `tools/check-lcb-signatures.py --write` |
| `docs/api-reference.md` | `tools/build-api-reference.py` |
| `docs/kit-reference.md` | `tools/build-kit-reference.py` (its `--check` also holds the Kit's header cheat sheet) |
| the Kit carried between the markers of `examples/*.livecodescript` | `tools/sync-embedded-kit.py` |
| `tests/teapot_model.h`, from `tests/models/teapot.obj` | `tools/build-test-model.py` |

## As built

- **Text results share ONE static buffer** (the move list has its own): the next text call
  overwrites it. The binding copies at once, so script never sees that; a C caller must copy
  before it asks again. Numbers are printed with a `.` in every locale.
- **Shape events default OFF** in Box3D (contact, hit, sensor); `b3ShapeOptionsSetEvents`
  sets what the next shapes are created with. A sensor needs events on itself and its visitor.
- **A shape's category defaults to every bit**, so a query filter separates nothing until
  shapes have categories of their own.
- **A mesh is one-sided and a hull is simplified** (both found by the first real model,
  the teapot of the smoke test, 2026-11-20). Box3D culls the back of a mesh triangle for
  contacts and for rays. It holds a hull to 128 corners, faces AND edges while its builder
  takes a corner budget only, so `b3x_shape_add_hull` walks the budget down until the hull
  fits: asked for 128 corners of a rounded model, Box3D builds some 250 faces and refuses.
- **A shape's AABB is loose** (Box3D fattens it), so a test that asks where a body rests
  moves the model's points through the body's transform and does not read the AABB.
- **The renderer (ABI 2, 2026-11-20) is in the shim**: a software rasteriser over the
  shim's own shape table (depth as 1/z, near plane 0.05 m, pictures to 2048 a side), one
  picture for the process. It reads a world and never changes it. The picture is the ONE
  result that crosses as bytes: `b3x_render_pixels` is public as Data through `dataOf()`,
  which the signature gate holds to that export alone (its `DATA` set; a second builtin,
  `MCDataCreateWithBytes`). Its oracle in the smoke test is Box3D: the shape and depth at a
  pixel against a ray cast through it, over every shape kind and the teapot, from five
  cameras. The fuzz test reads every byte of the picture after every call. The contract it
  shares with the suite's render3dxt (camera as "ex,ey,ez,tx,ty,tz,fov", picture coordinates
  from the top left with pixel centres at +0.5, a ray as origin and unit direction, y up,
  the fallback up of world -z looking straight down) is in the shim's comments: change
  neither side alone.
- **Box3D re-pairs shapes only when one leaves its fat bounding box**: destroying a filter
  joint does not make two resting bodies collide until one of them moves far enough.
- **32-bit x86 is built with SSE2**, not scalar: Box3D's determinism test fails on x87.
- **The web build** is scalar and single-threaded; the shim forces one worker there.
- **Only `b3x_*` is exported**: `src/box3dxt.map` for GNU ld and the same pattern for ld64.

## The game Kit

`src/box3dxt-kit.livecodescript` is the b3k Kit, a pure-script game layer over the binding,
modelled on box2dxt's b2k Kit (read that member's CLAUDE.md for the shared shape). It is the
ONE source: the example game carries a verbatim copy between `BEGIN EMBEDDED KIT` and
`END EMBEDDED KIT`, so a fix goes into `src/` and is carried by `tools/sync-embedded-kit.py`.

- **Two renderers, one game.** With render3dxt loaded the Kit draws through a render3dxt
  scene and carries each step's moves across with `b3WorldUpdateMoves` then
  `r3SceneApplyMoves`; without it, box3dxt's own renderer draws the world into the same
  image. A Kit feature that only one renderer can show says so in its doc block ("render3dxt
  only"), and the other renderer ignores it.
- **The sun is the scene's first light.** `r3SceneCreate` makes a default directional light;
  the Kit adopts it as its sun rather than adding another (a second sun washed every surface
  out, 2026-11-21; `tests/engine-kit.lc` counts the scene's lights).
- **The messages' default target is the card current at `b3kSetup`**, chosen again by each
  `b3kSetup` until the game names one. "me" was wrong for a Kit used as a library (OXT-Beyond
  ships script libraries that way): the messages went to the library itself (2026-11-21;
  `testDefaultTarget` fails on that default).
- **`start using` a stack whose script handles a message and passes it runs that handler
  twice** (measured on the server engine), so `tests/engine-demo.lc` puts its probe in a
  button on the game's card instead of using the game as a library.
- **Every public handler has a doc block** (the dictionary reads them, and
  `docs/kit-reference.md` is built from them) except `b3kStep`, the loop's timer message.
  A block holds no line that looks like code to the dictionary's parser (`on ...`, a
  multi-line `if`), so examples are one-line statements; the suite's
  `tools/check-dictionary-docs.py` and `tools/build-kit-reference.py --check` hold them.

## Gotchas

1. **A digit in a module's namespace component is a warning, and the Extension Builder runs
   `-Werror`**: the module is `...boxthreed`, not `...box3dxt`.
2. **An all-lowercase LCB handler or variable name warns** (it could collide with a future
   keyword): the helper is `asInt`, not `bi`.
3. **A step of dt 0 corrupts Box3D's move list** (it is emptied, never refilled, and every
   body keeps its old index): `b3x_world_step` refuses anything below 1e-6.
4. **UBSan's alignment check is off for the Box3D target only** (its SSE2 loader reads three
   floats through a double load). The shim and the tests keep every check.
5. **The fuzz test counts in-step `b3IsValidVec3` asserts apart** from all others: they are
   the unstable scenes the net then removes, and the run fails only on any OTHER assert, on a
   crash, or on a body the audit finds broken after the net ran.

## Status

Verified natively (smoke and fuzz, ASan/UBSan, 64-bit, 32-bit and wasm under node) and on the
headless Linux server engine (`tests/engine-selftest.lc`, 2026-11-20, a locally built
library), and in OXT-Beyond's desktop IDE on 64-bit Linux the same day (a library built on
that machine, loaded by `load extension` and `revLibraryMapping`; one drop scene with a ray
cast and contact events; README "Status"). The renderer has run natively, on the server
engine (the picture as data, its bytes read) and in that Linux IDE (an image showing the
teapot scene, picking by pixel and by ray, 2026-11-20, from 9b7b59a; README "Status"). The game Kit and its example game ran on the server
engine on 2026-11-21 (`tests/engine-kit.lc`, `tests/engine-demo.lc`; a local library, with
box3dxt's renderer and with a render3dxt built from its pull request); no IDE has run them.
Orb Island has played once in a browser, on a web engine built locally from OXT-Beyond's pull
request 606 with the committed web archives of box3dxt and render3dxt linked in (2026-11-21;
its keys not driven). No engine on Windows, macOS or Android has loaded it, and no IDE has
loaded a release library or an installed extension: verified statically; needs an OXT pass.
Release libraries were committed on 2026-11-20 (six desktop platforms, four Android ABIs; the
web archive built separately with emsdk 6.0.12); of them only the web archive has met an
engine (that browser run), and no engine has loaded a desktop or Android one yet. Open work is
in the suite's `docs/WORK-PLAN.md`.
