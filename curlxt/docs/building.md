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
