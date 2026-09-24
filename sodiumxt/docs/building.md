# Building SodiumXT

The heavy part (acquiring and building libsodium) and the day-to-day loop (sanitizers,
the static gate, packaging), for contributors. The rules a change must keep are in
`CLAUDE.md`.

## Layout

- `src/sodium_shim.{c,h}` - the C shim: a thin marshaling layer over libsodium, exporting
  the stable `sxt_*` ABI.
- `src/sodium.lcb` - the LiveCode Builder binding that presents the public `sx*` handlers.
- `src/code/<arch>-<platform>/` - the bundled native libraries, plus `MANIFEST.sha256`
  (their recorded SHA256s).
- `src/vendor/` - the vendored trezor-crypto SHA3 sources (`src/vendor/VENDOR.md`).
- `tests/sodium_smoke_test.c` - the C suite: known-answer tests, round trips, and the
  tamper / wrong-key / firewall checks.
- `tools/` - `run-gates.sh` (the member gate list CI runs), `check-livecodescript.py`
  (the script static gate), `check-docs-style.py` (no em/en dashes or curly quotes in any
  `.md` here), `package-extension.py`.
- `examples/` - the demo stack and the xTalk self-test.
- `docs/` - the user documentation.

## What gets built

ONE shared library, statically linking a pinned libsodium, named with the bare token
`sodiumxt` (`PREFIX ""`, `OUTPUT_NAME sodiumxt`, no `lib` prefix):

```
src/sodium_shim.c  +  libsodium (static, pinned)  ->  sodiumxt.{so,dll,dylib}
```

The bare token matters: the packaged extension ships this binary under
`src/code/<arch>-<platform>/sodiumxt.{so,dll,dylib}`, and the engine resolves
`c:sodiumxt>sxt_*` against it via `the revLibraryMapping`. No loose library, no `sudo`,
no `LD_LIBRARY_PATH`, no rename.

## The pinned libsodium

libsodium is pinned in `CMakeLists.txt` and acquired by CMake at build time with an
integrity check:

| | |
|---|---|
| version | `1.0.20` |
| url | `https://github.com/jedisct1/libsodium/releases/download/1.0.20-RELEASE/libsodium-1.0.20.tar.gz` |
| sha256 | `ebb65ef6ca439333c2bb41a0c1990587288da07f6c7fd07cb3a18cc18d30ce19` |

Re-pinning is a two-file change in one commit: the three `SODIUMXT_LIBSODIUM_*` values
(version, URL, SHA256) in `CMakeLists.txt` AND the `SXT_PINNED_SODIUM` string in
`tests/sodium_smoke_test.c`. The smoke test asserts only that the linked libsodium is on
the 1.0.x line and PRINTS the linked version beside the pin; the functional KATs are what
catch a real drift. libsodium's own build is autotools: on Linux and macOS CMake drives
`./configure --enable-static --disable-shared --with-pic` through `ExternalProject`, then
imports the resulting `libsodium.a`.

**Windows is the exception, by decision.** Windows / MSVC links the libsodium **vcpkg**
provides (`libsodium:<triplet>-static`) instead of building the pinned source, so it is
not covered by the SHA256 pin; the committed Windows DLLs carry libsodium 1.0.22.
Decided 2026-08-27 (owner-delegated, decision D-08): this KAT-guarded state is the
recorded choice, not an oversight. The known-answer tests (BLAKE2b, Argon2id, ed25519,
KDF) gate every build, and the release lane drives the published vectors on a real
Windows runner before any DLL is bundled, so a pin would add maintenance without adding
a check. To hold Windows to an exact libsodium, pin a vcpkg baseline (a `vcpkg.json` with
a `builtin-baseline`) or build the pinned source (the mingw recipe in `CLAUDE.md`).

## Where the built library lands

A plain `cmake --build` copies the freshly built library into the bundle location the
packaged extension reads, `src/code/<arch>-<platform>/sodiumxt.{so,dll,dylib}`, so the
engine can resolve `c:sodiumxt>` with no extra step. The platform id is detected
automatically (architecture first; Windows is `-win32` for both bitnesses; macOS files
under `universal-mac`); override it for a cross build with `-DSODIUMXT_PLATFORM_ID=<id>`,
or turn the copy off with `-DSODIUMXT_PLACE_IN_SRC=OFF`.

This also means a plain build makes the committed `x86_64-linux` binary differ, so the
MANIFEST gate fails until you `git checkout` it (nothing changed) or refresh binary and
manifest together (the change was intentional).

## Build and test (Linux, macOS)

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DSODIUMXT_BUILD_TESTS=ON
cmake --build build --config Release
ctest --test-dir build --output-on-failure        # sodium_smoke_test (KATs + round trip)
# -> build also wrote src/code/<arch>-<platform>/sodiumxt.{so,dylib}
```

The first build downloads and compiles libsodium (a couple of minutes); later builds reuse
it.

## Build and test (Windows / MSVC)

From a Developer PowerShell (so `cl.exe` is on PATH), with `VCPKG_INSTALLATION_ROOT` set to
your vcpkg checkout:

```powershell
vcpkg install libsodium:x64-windows-static          # or x86-windows-static for 32-bit

cmake -S . -B build -G "NMake Makefiles" `
  -DCMAKE_BUILD_TYPE=Release `
  -DSODIUMXT_BUILD_TESTS=ON `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded `
  -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_INSTALLATION_ROOT/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build build
ctest --test-dir build --output-on-failure
# -> build also wrote src\code\x86_64-win32\sodiumxt.dll
```

The `NMake Makefiles` generator avoids the Visual Studio generator's VS-instance detection
(which can fail on minimal runners) and gives a native `cl.exe` for the architecture of the
Developer shell you launched. Use the `x86-windows-static` triplet from a 32-bit Developer
shell to produce the `x86-win32` `.dll`. With no MSVC at hand, `CLAUDE.md` has the proven
mingw cross-build recipe and the three checks a cross-built DLL must pass.

## Always iterate under the sanitizers

A crypto binding is exactly where an off-by-one in buffer sizing hides, so ASan and UBSan
are part of the loop, not an afterthought. Use gcc: clang's ASan runtime is not installed
in this environment.

```sh
cmake -S . -B build-asan -DSODIUMXT_BUILD_TESTS=ON -DSODIUMXT_SANITIZE=ON
cmake --build build-asan
ctest --test-dir build-asan --output-on-failure
```

Or the direct one-liner (libsodium headers as system headers with `-isystem`, so their
warnings never pollute our warning-clean `-Wall -Wextra`):

```sh
gcc -std=c11 -Wall -Wextra -fsanitize=address,undefined -fno-sanitize-recover=all \
  -Isrc -isystem <libsodium-include> \
  src/sodium_shim.c tests/sodium_smoke_test.c <path-to>/libsodium.a -o /tmp/sx && /tmp/sx
```

## The static gate for the script layer

OXT is a GUI runtime: there is no headless way to compile or run `.lcb` or
`.livecodescript`. Catch what is statically catchable first:

```sh
python3 tools/check-livecodescript.py
bash tools/run-gates.sh        # the whole member gate list: static gate, docs style, manifest
```

The checker covers smart/curly quotes and dashes, handler / `if` / `repeat` / `unsafe`
balance, constant-declared-before-use, and the prefixed-token-shadow trap. A green run
means "verified statically; still needs an OXT pass" - do not claim runtime behaviour of
the `.lcb` you cannot observe here.

## Packaging and committing the native library

After a build the library is already in place (see "Where the built library lands"). To
copy from a build tree that did not run the post-build step (for example one built with
`-DSODIUMXT_PLACE_IN_SRC=OFF`):

```sh
python3 tools/package-extension.py --build-dir build
# -> src/code/<arch>-<platform>/sodiumxt.{so,dll,dylib}, and a refreshed MANIFEST.sha256
```

`src/code/MANIFEST.sha256` is a plain `sha256sum` list of every committed native blob.
`tools/run-gates.sh` checks it (`cd src/code && sha256sum -c MANIFEST.sha256`), and that
script runs both in the suite's `suite-gates.yml` (via `tools/build-all.sh --gates`) and in
this member's own `.github/workflows/gates.yml`, so a committed `sodiumxt.*` that is
unlisted or does not match fails the build. The manifest is an integrity record, not a
source-provenance proof.

Two routes commit a binary, and both keep committing a deliberate human step:

- **By hand**, in the same change as the native edit: build (or run
  `tools/package-extension.py`) and commit the binary with its manifest entry.
- **The suite's `release-binaries.yml`**, the usual route: a manual `workflow_dispatch`
  that rebuilds every platform, installs each library through
  `tools/install-release-binaries.py` (filename against member, object format and
  architecture against directory), refreshes the manifests, runs the gate set and commits
  (`commit_mode`: `branch` / `pr` / `none`). Pressing "Run workflow" is the human decision.
  All five committed rows came this way (release run 12, 2026-08-27; the Windows DLLs twice
  more, last on 2026-09-12); `CLAUDE.md`'s table records what each row was built from.

The `native sodiumxt` workflow (`native-sodiumxt.yml` in the suite, `native.yml` here)
builds and tests all five platforms and uploads artifacts, but NEVER commits: it fires on
every push, so a commit step would land binaries on somebody else's change. Build from
source yourself when you need end-to-end assurance.

## What "done" means

- A `.lcb` / `.livecodescript` change is done once `tools/check-livecodescript.py` passes
  (and is "verified statically" until it has had an on-engine pass).
- A shim change is done once `sodium_smoke_test` passes under ASan/UBSan, and (for an ABI
  change) `SXT_ABI_VERSION` and the `.lcb` `kSXTABIVersion` are bumped together.
- A native-library change is done once the committed `src/code/<arch>-<platform>/` binary
  AND its `src/code/MANIFEST.sha256` entry are refreshed in the same change.

House style: comment the *why*, matching the density of the surrounding code; ASCII only
in `.lcb` / `.livecodescript`; no em dashes in committed prose.
