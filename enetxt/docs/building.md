# Building enetxt

The family's lightest dependency story: ENet is one small C library, fetched and pinned by
CMake (v1.3.18), statically folded into the one shared library. Minutes, not the hours
Boost/libtorrent cost TorrentXT.

## Linux (the everyday lane)

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENETXT_BUILD_TESTS=ON
cmake --build build --parallel
ctest --test-dir build --output-on-failure   # record_handle_test + enet_smoke_test
```

**The sanitizer lane.** `ENETXT_SANITIZE` is a STRING and GLOBAL, injected before
FetchContent so ENet itself is instrumented too. gcc only (clang's sanitizer runtimes are
not installed in the reference environment):

```sh
cmake -S . -B build-asan -DENETXT_BUILD_TESTS=ON -DENETXT_SANITIZE=address
cmake --build build-asan --parallel
./build-asan/record_handle_test && ./build-asan/enet_smoke_test
```

A shim change is only "done" green under ASan/UBSan. There is no TSan lane: ENet is
threadless and the shim spawns nothing (the binding that needs TSan is dataChannelXT).

`CMAKE_POSITION_INDEPENDENT_CODE ON` sits BEFORE FetchContent in the CMakeLists: a non-PIC
static ENet cannot link into the shared library, and ld's entire diagnosis is "bad value".

The committed Linux libraries need glibc 2.14 (`x86_64-linux`) and 2.28 (`x86-linux`),
measured 2026-09-23 with `objdump -T` on the 2026-09-12 binaries.

## Windows

Visual Studio 2022+ (the default generator). No vcpkg: ENet has no external dependencies;
winsock comes with the SDK.

```powershell
cmake -S . -B build -DENETXT_BUILD_TESTS=ON
cmake --build build --config Release --parallel
ctest --test-dir build --build-config Release --output-on-failure
```

For the 32-bit DLL add `-A Win32`.

## macOS

A plain configure (the Linux commands above) is a HOST-ARCH build, right for developing and
running the tests on the machine in front of you. What ships under `universal-mac` must
carry BOTH slices, and ENet has no external dependency, so one pass does it:

```sh
cmake -S . -B build-mac -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build build-mac --parallel
lipo -archs build-mac/enetxt.dylib     # must print: x86_64 arm64
```

The suite's `native-enetxt.yml` (artifact only) and `release-binaries.yml` pass that same
flag, the release lane asserts `lipo -archs` at birth, and the suite's
`tools/install-release-binaries.py` REFUSES a thin Mach-O under `universal-mac` (such a
library loads for whoever built it and fails for users on the other architecture). Mac artifacts ship UNSIGNED in the distribution sense:
arm64 code carries the linker's automatic ad-hoc signature, and no lane codesigns or
notarizes (credentials CI does not hold), so a browser-downloaded zip needs its quarantine
attribute cleared while a git checkout does not.

## Packaging

```sh
python3 tools/package-extension.py --platform-id x86_64-linux --lib build/enetxt.so
```

copies the library into `src/code/<arch>-<platform>/` under the bare-token name (the tree
the packaged extension bundles; `--dry-run` shows what would change, `--assemble` stages the
IDE packaging layout). Update that platform's line in `src/code/MANIFEST.sha256` in the same
change - `tools/run-gates.sh` refuses a blob that does not match it; the suite's
`tools/install-release-binaries.py` does both for a release build. Two things happen to the
artifact, and neither touches your build tree's own copy:

- **Only the `enx_*` ABI is exported** - the 22 entry points the `.lcb` binds plus the
  `enx_selftest_throw` firewall hook. ENet is statically linked, and its symbols would
  otherwise inherit the library's public visibility, which another extension bundling its
  own ENet could interpose with. `src/enetxt.map` is the one source of truth: a version
  script for GNU ld / lld, and on macOS CMakeLists derives an `-exported_symbols_list` from
  it (ld64 has no `--version-script`; added 2026-08-26 after release run 10 measured 70
  leaked upstream names in the dylib). `-fvisibility=hidden` cannot do this: ENet is
  compiled by its own CMake target, out of reach of our flags.
- **The committed copy is stripped** by the packager (`strip --strip-unneeded`, which keeps
  `.dynsym` so the bindings still resolve).

## CI

In the suite, the root workflow `native-enetxt.yml` builds and tests the five-target
matrix and uploads each library as an artifact; it never commits. Binaries are committed
by the hand-dispatched `release-binaries.yml`: all five platforms are committed
(`universal-mac` since 2026-08-27; every platform rebuilt 2026-09-12). This member's own
`.github/workflows/native.yml` and `gates.yml` are GENERATED from the root lanes by the
suite's `tools/sync-member-workflows.py`: inert inside the suite, they are the live CI of
the published enetxt repository.
