# Building enetxt

The dependency story is the family's lightest: ENet is one small C library,
fetched and pinned by CMake, statically folded into the one shared library.
Minutes, not the hours Boost/libtorrent cost TorrentXT.

## Linux (the everyday lane)

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENETXT_BUILD_TESTS=ON
cmake --build build --parallel
ctest --test-dir build --output-on-failure   # record_handle_test + enet_smoke_test
```

**The sanitizer lane** — the `ENETXT_SANITIZE` knob is a STRING and GLOBAL,
injected before FetchContent so ENet itself is instrumented too. gcc only
(clang's sanitizer runtimes are not installed in the reference environment):

```sh
cmake -S . -B build-asan -DENETXT_BUILD_TESTS=ON -DENETXT_SANITIZE=address
cmake --build build-asan --parallel
./build-asan/record_handle_test && ./build-asan/enet_smoke_test
```

A shim change is only "done" green under ASan/UBSan. There is no TSan lane:
ENet is threadless and the shim spawns nothing — there is no concurrency to
sanitize (the one binding that needed TSan is dataChannelXT).

Note `CMAKE_POSITION_INDEPENDENT_CODE ON` sits BEFORE FetchContent in the
CMakeLists — a non-PIC static ENet cannot link into the shared library, and
ld's entire diagnosis is "bad value".

## Windows

Visual Studio 2022+ (the default generator). No vcpkg needed — ENet has no
external dependencies; winsock comes with the SDK.

```powershell
cmake -S . -B build -DENETXT_BUILD_TESTS=ON
cmake --build build --config Release --parallel
ctest --test-dir build --build-config Release --output-on-failure
```

For the 32-bit DLL add `-A Win32`.

## macOS

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENETXT_BUILD_TESTS=ON
cmake --build build --parallel && ctest --test-dir build --output-on-failure
```

That is a HOST-ARCH build — right for developing and running the tests on the
machine in front of you. What ships under `universal-mac` must carry BOTH
slices, and ENet has no external dependency, so one pass does it:

```sh
cmake -S . -B build-mac -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build build-mac --parallel
lipo -archs build-mac/enetxt.dylib     # must print: x86_64 arm64
```

Since 2026-08-23 both root workflows build it exactly that way —
`native-enetxt.yml` (artifact only, never committed) and `release-binaries.yml`
(the lane that can commit) pass the same flag and assert `lipo -archs` carries
both at birth. Do not skip it by hand either: the suite's
`tools/install-release-binaries.py` REFUSES a thin Mach-O under the
`universal-mac` id, because such a library loads for whoever built it and fails
only for users on the other architecture. Every mac artifact here ships
UNSIGNED in the distribution sense (arm64 code always carries the linker's
automatic ad-hoc signature) — codesigning and notarization exist in no lane in
this repository, so a browser-downloaded zip needs its quarantine attribute
cleared while a git checkout does not.

## Packaging

```sh
python3 tools/package-extension.py --platform-id x86_64-linux --lib build/enetxt.so
```

places the bare-token library into `src/code/<arch>-<platform>/` (the tree
the packaged extension bundles); the self-contained gate refuses a library
with unexpected dynamic dependencies. Two things happen to the artifact on
the way in, and neither touches your build tree's own copy:

- **Only the `enx_*` ABI is exported.** ENet is statically linked, and a
  static archive's symbols would otherwise inherit the library's public
  visibility (the shipped `.so` used to export about 65 `enet_*` symbols),
  which another extension bundling its own ENet could interpose with. A
  linker version script (`src/enetxt.map`, applied where the linker supports
  it) filters the export table down to the 22 bound entry points. `-fvisibility=hidden`
  cannot do this: ENet is compiled by its own CMake target, out of reach of
  our flags.
- **The committed copy is stripped** (`strip --strip-unneeded`, which keeps
  `.dynsym` so the bindings still resolve). Debug tables and absolute build
  paths are pure payload in a shipped artifact.

The root CI workflow `.github/workflows/native-enetxt.yml` builds and tests the
5-target matrix (the member's own `.github/workflows/build.yml` is kept for
isolated development but is inert here, since GitHub runs only root workflows).
Each lane uploads its library as an artifact; binaries are committed
deliberately by a maintainer rather than pushed by CI. Four platforms are
committed today (`x86_64-linux`, `x86-linux`, `x86_64-win32`, `x86-win32`,
per `src/code/MANIFEST.sha256`, landed by the 2026-08-08 release run);
macOS: `release-binaries.yml` carries a universal mac lane since 2026-08-23 (both slices in one `CMAKE_OSX_ARCHITECTURES` pass); a manual `lipo` build remains equivalent.
