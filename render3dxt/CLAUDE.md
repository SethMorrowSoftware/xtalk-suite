# CLAUDE.md

Guidance for Claude Code in the render3dxt member of the xtalk-suite monorepo
(`render3dxt/`). Where anything disagrees, the code and this file win.

## What this is

**render3dxt** is a software 3D renderer for OXT: a scene of textured, lit meshes is drawn on
the processor into a pixel buffer a stack sets as an image's `imageData`. The renderer is
this member's own C (`src/render3d_shim.c`, exports `r3x_*`, **ABI 1**: `R3X_ABI_VERSION`
there equals the literal in `checkABI()` of the binding); two single-file readers are compiled
in beside it (`src/render3d_thirdparty.c`: stb_image for pictures, fast_obj for OBJ models,
each FetchContent-pinned to a commit in `CMakeLists.txt`) -> ONE library
`render3dxt.{so,dll,dylib}` (bare token), or `render3dxt.a` for the web -> the LCB binding
`src/render3dxt.lcb` (`org.openxtalk.library.renderthreed`, public `r3*`). box3dxt is its
model and its partner; read that member's CLAUDE.md for the reasons behind the shared shape.

## The rules

1. **Never call script from a foreign thread.** The drawing threads are created for one
   picture and joined: by `r3x_scene_render` before it returns (`flush_queue`), or, for a
   picture begun with `r3x_scene_render_begin`, by the next call that looks a handle up
   (`settle`, called from every table's `_get`). There is no thread pool and no callback:
   the script asks whether a picture is ready, and takes it. While a begun picture draws,
   its threads read the scene's buffers, the queue, textures and materials, and `settle` in
   every lookup is what keeps any call from changing or freeing those under them: a new
   export that reaches an object without its table's `_get` must call `settle` itself.
2. **Nothing crosses the boundary but values.** The shim is C: there is no exception to
   firewall. Every export validates its handles and its numbers before it uses them, and a
   refused call returns 0 or empty and sets `r3x_last_error`. It never aborts and never
   prints.
3. **Several numbers cross as one text** (`"x,y,z"`), in a static buffer returned as a
   `const char *`. The binding declares those returns `Pointer` and copies them with
   `textOf()`. NEVER `ZStringNative`: the engine frees a returned C string, and freeing a
   static buffer killed box3dxt's first engine run. The picture crosses as `Data`
   (`MCDataCreateWithBytes` over the scene's own frame), copied once.
4. **Generation-tagged integer handles**, validated before use. A slot whose generation
   would wrap is retired, never reused, so a stale handle cannot come back to life.
5. **A file is hostile.** Models and pictures come from anywhere, so the readers are fenced:
   stb_image is built with only its PNG, JPEG, BMP and TGA decoders and a size limit, and
   EVERY index of an OBJ is checked against the model's own counts before it is used
   (`build_from_obj`: fast_obj does not do this). fast_obj's number parser overflows a signed
   int on a long digit run, so the readers' translation unit is compiled with `-fwrapv`. A
   new format or reader gets the same treatment and a hostile file in `tests/assets/`.
6. **Every allocation is bounded** by a stated limit (docs/getting-started.md has the
   table): a picture's side, the supersampled buffer, a texture, a mesh's vertices and
   triangles. No argument can ask for more memory than those allow.
7. **The contract with box3dxt is pinned on both sides.** y up, metres, right-handed; a
   transform is `"x,y,z,qx,qy,qz,qw"`; a move line is `"body,x,y,z,qx,qy,qz,qw,fellAsleep"`;
   the camera is `"ex,ey,ez,tx,ty,tz,fov"` (vertical field of view in degrees, up +y, world
   -z standing in when the view is within 0.999 of vertical); the near plane is 0.05 m;
   picture coordinates are continuous from the top left with a pixel's centre at +0.5; depth
   is view-space z in metres; a triangle line is `"x1,y1,z1,x2,y2,z2,x3,y3,z3"`,
   counter-clockwise from outside. `tests/smoke_test.c` pins this member's half and
   `tests/engine-interop.lc` pins the join over a real Box3D simulation. Change none of it
   without changing box3dxt in the same pull request.
8. **Names are mechanical.** `r3x_node_set_position` is bound as `_node_set_position` and
   wrapped by `r3NodeSetPosition`; nothing is renamed by hand, and each wrapper's whole body
   is derived (`tools/check-lcb-signatures.py`, fixture `tools/test-lcb-signatures.py`).
9. **Done means:** a shim change is green in `smoke` AND `fuzz` under
   `-DRENDER3DXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug`, and, if it touches the drawing
   threads, under `-DRENDER3DXT_SANITIZE=thread` too; a binding change passes
   `lc-compile -Werror` and `tests/engine-selftest.lc` on the server engine; a demo change
   passes `tests/engine-demo.lc`; all pass `bash tools/run-gates.sh`. An ABI change bumps
   `R3X_ABI_VERSION` and the two literals in `checkABI()` together. Native-library changes
   refresh the committed binaries through the suite's `release-binaries.yml`;
   `native-render3dxt.yml` never commits.

## Generated text: edit the source, then regenerate

| What | Written by |
|---|---|
| the declaration blocks of both C tests and the fuzz call table | `tools/check-smoke-coverage.py --write` |
| `tests/test_assets.h` (the files of `tests/assets/`, carried inside the C tests) | `tools/build-test-assets.py` |
| `sweepEveryHandler` in `tests/engine-selftest.lc` | `tools/check-lcb-signatures.py --write` |
| `docs/api-reference.md` | `tools/build-api-reference.py` |
| the demo's `kRdScControls` | the suite's `tools/check-demo-control-lists.py --write` |

The demo carries the suite's UI kit and boot self-check blocks verbatim; their masters and
drift gates are the suite's.

## As built

- **The picture is the same for any thread count.** Triangles are set up in order on the
  calling thread into a queue; the picture is cut into bands, several a thread, and each band
  is cleared, drawn (queue order) and resolved by the ONE thread that takes it. A change to
  the fill loop must keep a row's values depending only on the row; the smoke test compares
  the bytes across thread counts.
- **A picture can be begun** (`r3x_scene_render_begin`): the setup, and every pass but the
  last when the queue overflows, run in the call; the last pass is left to threads that are
  all the library's own (`flush_queue_bg`), with their own copy of the frame (`s_bg`).
  `settle` joins them and books the picture and its statistics to the scene. One picture
  at a time, for all scenes: the queue is one. The smoke test holds a begun picture to the
  bytes of the one drawn at once, and destroys what the threads read while they draw.
- **Depth is stored as 1/depth** (0 is "nothing drawn"), and every attribute is interpolated
  divided by depth, stepping by a constant a pixel.
- **Lighting is per vertex** (Gouraud), cached per mesh vertex for each material and side;
  the highlight is added after the texture, so a texture never darkens it.
- **A texture's (0,0) is its top-left corner.** OBJ's v runs upward, so it is flipped at
  load.
- **The texture sampler has three paths** (repeating with power-of-two sides, clamped,
  repeating otherwise), the first two in fixed point. `test_texture_paths` walks all of them.
- **A mesh loaded from an OBJ owns the materials and textures its file made**, and takes
  them with it when destroyed, from whatever slot the script has moved them to or out of:
  both are listed apart from the slots (`ownedMat`, `ownedTex`), and one the script destroys
  first drops out of its list. A material or texture a script made is the script's.
- **Text results share ONE static buffer**: the next text call overwrites it. The binding
  copies at once. Numbers are printed with a `.` in every locale.
- **32-bit x86 is built with SSE2**, so the same scene rounds the same way as on 64-bit.
- **The web build** is single-threaded; `r3SetThreadCount` accepts a number and draws on one.
- **Only `r3x_*` is exported**: `src/render3dxt.map` for GNU ld and the same pattern for ld64.

## Gotchas

1. **A digit in a module's namespace component is a warning, and the Extension Builder runs
   `-Werror`**: the module is `...renderthreed`, not `...render3dxt`.
2. **An all-lowercase LCB handler or foreign name warns**: `_threads` did not compile; the
   exports are `r3x_set_thread_count` and `r3x_thread_count`.
3. **`r3x_text_length` takes `const void *`**, bound as `Pointer`: a text result is a
   Pointer on the script side, and a `ZStringUTF8` parameter refuses one.
4. **The engine compares text without case**: "0 failed" contains "fail". The engine tests
   count log lines by their first word.
5. **The C tests carry their files** (`tests/test_assets.h`) because on the Android emulator
   a test is one pushed binary. Add a file to `tests/assets/`, then run
   `tools/build-test-assets.py`.
6. **`set the imageData` compresses** as `the paintCompression` says, "png" on a desktop
   engine: 36.6 ms of the demo's 49 ms frame before the demo set "rle" around that line
   (OXT-Beyond 0.2.8-dp.2, 2026-11-20). The server engine starts with "rle", so no engine
   test here ever showed it; `tests/engine-demo.lc` now sets "png" first.
7. **`imageData` is not scaled**: the image control must be exactly the picture's size.

## Status

Verified natively (smoke and fuzz; ASan/UBSan and TSan; 64-bit, 32-bit and wasm under node)
and on the headless Linux server engine (`tests/engine-selftest.lc`, `engine-interop.lc`
with box3dxt, `engine-demo.lc`; 2026-11-20, locally built libraries). One desktop IDE has
run it (OXT-Beyond 0.2.8-dp.2 on Linux x86_64, 2026-11-20, locally built libraries
installed as extensions): the demo's window was built, its boot self-check read 11 passed,
the picture was seen and recorded, and a real pointer dragged, kicked and pressed every
button; 57 pictures a second with nine things, 50 to 52 with about fifty. The demo's look was rebuilt on 2026-11-21 (its own painted buttons and toggles, a dark log, a sky, the wheel, pictures a second on the picture's corner) after a Windows pass under a dark theme showed white words on white: that look has run on the server engine (`tests/engine-demo.lc`), been seen offscreen on the Linux desktop engine, and been seen on Windows. One Windows engine has opened the demo (OXT-Beyond 0.2.8-dp.1, 64-bit, dark system appearance, a locally built library (from 3c66637 at the later runs, by their record), 2026-11-21 between 01:19 and 02:00 UTC; an earlier record dated the first screenshot 2026-11-20): a screenshot showed the scene drawn, nine things, 7.8 ms a picture on 6 threads, and the white words that the rebuilt look answers; then the rebuilt look (cd52080, then be477c8) was readable throughout, drew 16 pictures a second with two other 3D stacks running in the same engine, and showed the faults fixed in 5fabc82 and 904bb16 (the badge, the self-check printed twice after a quick reopen, the far floor). 904bb16's fixes, the wheel and the buttons' hover have not run there. Later on 2026-11-21 the demo as merged (fa0a07a) opened on that machine with its boot self-check green (12 passed, 0 failed, 0 skipped). One web engine has run it: a locally built OXT-Beyond web engine with the web archive linked (not a released engine), in Chromium, 2026-11-21, played OXT-Beyond's Render3D Tour at 59 to 60 pictures a second and the demo at 34 to 36 with its boot self-check green (the archive as merged, fa0a07a; the one rebuilt with 457c244's leak fix has run its own tests under node only). No engine on
macOS or Android, and no released web engine, has loaded it: there, and for everything on Windows that those runs do not show, it is verified statically; needs
an OXT pass. Committed: the web archive (`src/code/wasm32-emscripten/render3dxt.a`, built by hand with emsdk 6.0.12, 2026-11-20, and rebuilt with 457c244's fix 2026-11-21) and the six desktop and four Android libraries (the first release dispatch, 2026-11-21, f6c0b1a); of them only the x86_64-linux library has met an engine (OXT-Beyond 0.2.8-dp.1's Linux server engine, 2026-11-21: OXT-Beyond's Android functional test for render3dxt passed with it). Open work is in the suite's `docs/WORK-PLAN.md`.
