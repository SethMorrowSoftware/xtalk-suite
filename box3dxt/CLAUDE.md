# CLAUDE.md

Guidance for Claude Code in the box3dxt member of the xtalk-suite monorepo (`box3dxt/`). Where
anything disagrees, the code and this file win.

## What this is

**box3dxt** binds Box3D (Erin Catto's 3D rigid-body engine, MIT, C17) for OXT: Box3D (static,
FetchContent, pinned to a COMMIT in `CMakeLists.txt` because it has no release tag yet) -> the
C shim `src/box3d_shim.c` (exports `b3x_*`, **ABI 1**: `B3X_ABI_VERSION` there equals the
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
   engine; both pass `bash tools/run-gates.sh`. An ABI change bumps `B3X_ABI_VERSION` and
   the two literals in `checkABI()` together. Native-library changes refresh the committed
   binaries through the suite's `release-binaries.yml`; `native-box3dxt.yml` never commits.

## Generated text: edit the source, then regenerate

| What | Written by |
|---|---|
| the declaration blocks of both C tests, the joint family table, the fuzz call table | `tools/check-smoke-coverage.py --write` |
| `sweepEveryHandler` in `tests/engine-selftest.lc` | `tools/check-lcb-signatures.py --write` |
| `docs/api-reference.md` | `tools/build-api-reference.py` |
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
- **Box3D re-pairs shapes only when one leaves its fat bounding box**: destroying a filter
  joint does not make two resting bodies collide until one of them moves far enough.
- **32-bit x86 is built with SSE2**, not scalar: Box3D's determinism test fails on x87.
- **The web build** is scalar and single-threaded; the shim forces one worker there.
- **Only `b3x_*` is exported**: `src/box3dxt.map` for GNU ld and the same pattern for ld64.

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
cast and contact events; README "Status"). No other platform's engine has loaded it and no
IDE has loaded a release library or an installed extension: verified statically; needs an
OXT pass. No binaries are committed yet. Open work is in the suite's
`docs/WORK-PLAN.md`.
