# Building curlxt

## Dependencies

CMake 3.16+, a C++17 compiler, and network access on the first configure: libcurl 8.22.0
and libssh2 1.11.1 are fetched as pinned release tarballs (SHA256-checked) and built static.

- **Linux:** OpenSSL 3 development files (`libssl-dev`). A plain build links the system
  OpenSSL dynamically; give `-DOPENSSL_ROOT_DIR=<prefix> -DOPENSSL_USE_STATIC_LIBS=ON` to link
  a static one instead, as the release build does.
- **macOS:** `brew install openssl@3`, then `export OPENSSL_ROOT_DIR=$(brew --prefix openssl@3)`.
  Certificates are checked by the OS (curl's Apple SecTrust), not by a CA file.
- **Windows:** nothing extra. TLS is Schannel, libssh2 uses WinCNG, and the C runtime is
  linked statically (`/MT`).
- **Android:** built by the suite's `tools/build-android.sh curlxt <abi>-android` (the pinned
  NDK, API 21, a static OpenSSL 3.5.9 for the ABI). Certificates come from the system store's
  folder, read into memory once; there is no CA file on Android. Built 2026-11-18; the smoke
  test ran that day on an Android 5.0 emulator for the two x86 ABIs (the suite's release
  workflow), the ARM libraries are built and not run.

The committed release libraries come from the suite's `release-binaries.yml` dispatch: a
static pinned OpenSSL 3.5.9 on 64-bit Linux (manylinux_2_28, glibc 2.28) and in both mac
slices, the system's i386 OpenSSL on 32-bit Linux.

## Build and test

```sh
cmake -S . -B build -DCURLXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
(cd build && ctest --output-on-failure)
```

Under the sanitizers (a shim change is done when this is green):

```sh
cmake -S . -B build-asan -DCURLXT_BUILD_TESTS=ON -DCURLXT_SANITIZE=address
cmake --build build-asan -j && (cd build-asan && ctest --output-on-failure)
```

## The gates

```sh
CURLXT_LIB=$PWD/build/curlxt.so bash tools/run-gates.sh
```

`tools/run-gates.sh` is the member's whole compiler-free list. Without `CURLXT_LIB` the two
execution gates SKIP and say so; `CURLXT_REQUIRE_LIB=1` makes that a failure.

## On a real engine

`tests/engine-selftest.lc` runs the binding and both script layers on OXT-Beyond's headless server
engine, against loopback HTTP, `ws://` and `wss://` servers that `tools/run-engine-selftest.py`
starts (the same servers `tools/check-script-vectors.py` runs). It needs a release's
`linux-x86_64-binaries` archive for `lc-compile`, `modules/lci` and `server-community`; the root
`native-curlxt.yml` `engine` job fetches one by its pinned hash and runs this on every change:

```sh
lc-compile -Werror --modulepath <bin>/modules/lci --output /tmp/curl.lcm src/curl.lcb
python3 tools/run-engine-selftest.py <bin>/server-community /tmp/curl.lcm build/curlxt.so
```

Green is the engine's exit 0 and a `SUMMARY` line with no failure and at least the driver's floor
of checks. The driver first holds the test's sweep to the binding: every public handler of
`src/curl.lcb` must be called there. It is not one of `tools/run-gates.sh`'s gates, because it
needs an engine.
