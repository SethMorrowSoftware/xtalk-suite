#!/usr/bin/env bash
# build-android.sh - build one native member's library for one Android ABI.
#
#   bash tools/build-android.sh <member> <platform-id>
#   bash tools/build-android.sh --list          # the members and platform ids
#   bash tools/build-android.sh --pins          # the pinned versions, one a line
#   bash tools/build-android.sh --api <member>  # the Android API level it is built for
#
#   <member>       sodiumxt | enetxt | box2dxt | box3dxt | audioxt | render3dxt |
#                  xlsxt | coinxt | curlxt | datachannelxt | torrentxt
#   <platform-id>  arm64-android | armv7-android | x86_64-android | x86-android
#
# It writes <member>/src/code/<platform-id>/<member>.so, the place every
# other platform's library is built into, and nothing else in the tree.
#
# WHY THIS IS A SCRIPT AND NOT TWENTY-EIGHT WORKFLOW ROWS. The desktop lanes
# of release-binaries.yml spell every member's row out because each row's
# setup is a different runner's packages. Android is the opposite case: one
# toolchain (the NDK) builds all four ABIs from one Linux machine, and the
# only thing that differs between members is which pinned dependency they
# take. So the recipe is here once, the workflow's Android job is a matrix
# that calls it, and a person with the NDK runs exactly what CI runs (root
# CLAUDE.md: exercise a gate the way the build will).
#
# WHAT "ANDROID" MEANS HERE. OXT-Beyond's Android builder takes an
# extension's native code from code/<arch>-android/, for the four names
# above (its kAndroidArchitectures), and puts it in the app as lib<name>.so.
# The libraries are built the way OXT-Beyond builds its own Android engine
# (its BUILDING.md, "Building the Android engine"): the NDK's Clang with
# API 21 (Android 5.0) as the lowest Android (torrentxt alone: API 24,
# Android 7.0, for the reason beside its pin below), libc++ linked INTO each
# library (never libc++_shared.so, which an app would have to carry), and
# 16 KB segment alignment on the 64-bit ABIs (Android 15's 16 KB devices
# load nothing aligned to less). tools/install-release-binaries.py
# --android-check asserts all of that on the file this script made, and the
# release workflow's installer asserts it again before anything is committed.
#
# THE NDK. One revision, pinned below, the one OXT-Beyond's
# config/android-ndk-version names. It is found through ANDROID_NDK_HOME,
# ANDROID_NDK_ROOT or ANDROID_NDK, or under ANDROID_SDK_ROOT / ANDROID_HOME
# as ndk/<revision>. Another revision is refused unless
# XTALK_ANDROID_ANY_NDK=1, which is for trying a newer NDK by hand: a
# library built with it must not be committed.
#
# THE TESTS. Each member's own tests are BUILT for Android always. They RUN
# only when XTALK_ANDROID_SERIAL names a device or emulator that `adb` can
# reach and that runs this ABI (tools/android-run.sh pushes each test there
# and runs it). Without one the script says so in its last line: built is
# not run, and the lane that has no device for an ABI must not read as if
# it had tested it.
#
# ENVIRONMENT
#   XTALK_ANDROID_WORK    build folders (default: <root>/build-android)
#   XTALK_ANDROID_DEPS    pinned dependency downloads and their builds
#                         (default: $XTALK_ANDROID_WORK/deps)
#   XTALK_ANDROID_SERIAL  adb serial to run the tests on (default: none)
#   XTALK_ANDROID_JOBS    parallel jobs (default: nproc; torrentxt: 2, since
#                         libtorrent from source at -j4 exhausts a runner)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ------------------------------------------------------------------ the pins
# The NDK revision is OXT-Beyond's (config/android-ndk-version there), so the
# libraries and the engine that loads them come from one compiler.
NDK_REVISION="30.0.16248370"
# The lowest Android: API 21 (Android 5.0), the lowest a current NDK builds
# for and the floor of OXT-Beyond's own Android engine.
ANDROID_API="21"
# torrentxt ALONE is built for API 24 (Android 7.0). The reason is Android 11,
# not Android 7: an app that targets API 30 or later may no longer bind a
# NETLINK_ROUTE socket or ask it for the links (RTM_GETLINK), and that socket
# is how libtorrent learns the machine's addresses on Linux. Built for an
# Android below API 24, libtorrent takes the Linux path (its config.hpp:
# TORRENT_USE_NETLINK), and inside such an app the session's address watcher
# fails to bind, the session pauses itself at birth, and "listen on every
# address" finds no address to listen on (observed in OXT-Beyond's app on an
# Android 13 emulator, 2026-11-21: a torrent of a local file never left
# checking). Built for API 24 or later, libtorrent takes its own Android path
# instead: getifaddrs(), which bionic has from API 24 and keeps working for
# every app, and no netlink at all. So this one library asks for Android 7.0,
# and the others keep Android 5.0. tools/install-release-binaries.py holds
# the same number (ANDROID_API_FOR) and refuses a torrentxt built for less.
TORRENTXT_ANDROID_API="24"
# OpenSSL and Boost are the release workflow's own pins (its "Acquire pinned
# deps" step); tools/test-build-android.py fails when the two disagree, so a
# bump in one place cannot leave Android on the old version.
OPENSSL_VERSION="3.5.9"
OPENSSL_SHA256="603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a"
BOOST_VERSION="1.86.0"
BOOST_SHA256="2128a4c96862b5c0970c1e34d76b1d57e4a1016b80df85ad39667f30b1deba26"

MEMBERS="sodiumxt enetxt box2dxt box3dxt audioxt render3dxt xlsxt coinxt curlxt datachannelxt torrentxt"
PLATFORMS="arm64-android armv7-android x86_64-android x86-android"

# The Android a member is built for: the suite's floor, or the one member
# with a floor of its own (the pins, above).
api_for() {
  if [ "$1" = "torrentxt" ]; then
    echo "$TORRENTXT_ANDROID_API"
  else
    echo "$ANDROID_API"
  fi
}

case "${1:-}" in
  --list)
    echo "members:   $MEMBERS"
    echo "platforms: $PLATFORMS"
    exit 0 ;;
  --pins)
    echo "ndk $NDK_REVISION"
    echo "api $ANDROID_API"
    echo "api-torrentxt $TORRENTXT_ANDROID_API"
    echo "openssl $OPENSSL_VERSION $OPENSSL_SHA256"
    echo "boost $BOOST_VERSION $BOOST_SHA256"
    exit 0 ;;
  --api)
    # Asked by whoever boots the emulator a member's tests run on (the
    # release workflow's android job), so the number is read, never copied.
    case " $MEMBERS " in
      *" ${2:-} "*) api_for "$2"; exit 0 ;;
    esac
    echo "build-android: '${2:-}' is not a native member ($MEMBERS)" >&2
    exit 2 ;;
esac

if [ $# -ne 2 ]; then
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
MEMBER="$1"
PLATFORM="$2"

case " $MEMBERS " in
  *" $MEMBER "*) : ;;
  *) echo "build-android: '$MEMBER' is not a native member ($MEMBERS)" >&2; exit 2 ;;
esac

# One row per ABI: the NDK's name for it, the compiler's target triple, and
# OpenSSL's Configure target. The API level rides on the triple.
# From here ANDROID_API is THIS member's. FLOOR_API stays the suite's: a
# dependency built once and shared between members is built for that.
FLOOR_API="$ANDROID_API"
ANDROID_API="$(api_for "$MEMBER")"

case "$PLATFORM" in
  arm64-android)  ABI="arm64-v8a";   TRIPLE="aarch64-linux-android";    OPENSSL_TARGET="android-arm64" ;;
  armv7-android)  ABI="armeabi-v7a"; TRIPLE="armv7a-linux-androideabi"; OPENSSL_TARGET="android-arm" ;;
  x86_64-android) ABI="x86_64";      TRIPLE="x86_64-linux-android";     OPENSSL_TARGET="android-x86_64" ;;
  x86-android)    ABI="x86";         TRIPLE="i686-linux-android";       OPENSSL_TARGET="android-x86" ;;
  *) echo "build-android: '$PLATFORM' is not an Android platform id ($PLATFORMS)" >&2; exit 2 ;;
esac

# ------------------------------------------------------------------- the NDK
NDK=""
for candidate in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}" "${ANDROID_NDK:-}" \
                 "${ANDROID_SDK_ROOT:+$ANDROID_SDK_ROOT/ndk/$NDK_REVISION}" \
                 "${ANDROID_HOME:+$ANDROID_HOME/ndk/$NDK_REVISION}"; do
  if [ -n "$candidate" ] && [ -f "$candidate/source.properties" ]; then
    NDK="$candidate"
    break
  fi
done
if [ -z "$NDK" ]; then
  echo "build-android: no Android NDK found. Set ANDROID_NDK_HOME to NDK $NDK_REVISION" >&2
  echo "  (sdkmanager \"ndk;$NDK_REVISION\" installs it under <sdk>/ndk/)." >&2
  exit 1
fi
have=$(sed -n 's/^Pkg\.Revision *= *//p' "$NDK/source.properties" | tr -d '[:space:]')
if [ "$have" != "$NDK_REVISION" ]; then
  if [ "${XTALK_ANDROID_ANY_NDK:-}" = "1" ]; then
    echo "build-android: WARNING: building with NDK $have, not the pinned $NDK_REVISION." >&2
    echo "  This library must not be committed." >&2
  else
    echo "build-android: $NDK is NDK $have; the pin is $NDK_REVISION." >&2
    echo "  (XTALK_ANDROID_ANY_NDK=1 builds with it anyway, for a trial only.)" >&2
    exit 1
  fi
fi
TOOLCHAIN_BIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
if [ ! -x "$TOOLCHAIN_BIN/clang" ]; then
  echo "build-android: $TOOLCHAIN_BIN/clang is missing; this script builds on Linux x86_64." >&2
  exit 1
fi

WORK="${XTALK_ANDROID_WORK:-$ROOT/build-android}"
DEPS="${XTALK_ANDROID_DEPS:-$WORK/deps}"
BUILD="$WORK/$MEMBER-$PLATFORM"
mkdir -p "$WORK" "$DEPS"
JOBS="${XTALK_ANDROID_JOBS:-$(nproc)}"

OUT_DIR="$ROOT/$MEMBER/src/code/$PLATFORM"
OUT="$OUT_DIR/$MEMBER.so"

SERIAL="${XTALK_ANDROID_SERIAL:-}"
TESTS="built, NOT RUN (no device: set XTALK_ANDROID_SERIAL to run them)"
if [ -n "$SERIAL" ]; then
  # Asked before anything is built: a device that cannot run this ABI would
  # fail every test with "not executable" forty minutes from now, and a
  # device that is not there would fail them the same way. Refused, never
  # skipped: the caller asked for the tests to run.
  abis=$("${ADB:-adb}" -s "$SERIAL" shell getprop ro.product.cpu.abilist 2> /dev/null | tr -d '\r' || true)
  case ",$abis," in
    *",$ABI,"*) : ;;
    *)
      echo "build-android: the device $SERIAL runs '${abis:-nothing adb could ask it}', not $ABI." >&2
      echo "  Unset XTALK_ANDROID_SERIAL to build without running the tests." >&2
      exit 1 ;;
  esac
  # ...and one whose Android is older than the library's own floor would fail
  # them at load ("cannot locate symbol"), which reads as a broken library
  # and is only the wrong emulator (torrentxt's tests need Android 7.0:
  # tools/android-emulator.sh start 24).
  sdk=$("${ADB:-adb}" -s "$SERIAL" shell getprop ro.build.version.sdk 2> /dev/null | tr -d '\r' || true)
  case "$sdk" in
    ''|*[!0-9]*)
      echo "build-android: the device $SERIAL would not say which Android it runs (ro.build.version.sdk: '$sdk')." >&2
      exit 1 ;;
  esac
  if [ "$sdk" -lt "$ANDROID_API" ]; then
    echo "build-android: the device $SERIAL runs Android API $sdk, and $MEMBER is built for API $ANDROID_API or later." >&2
    echo "  Its tests cannot load there. Boot the emulator for it: bash tools/android-emulator.sh start $ANDROID_API" >&2
    exit 1
  fi
fi

# --------------------------------------------------------- pinned downloads
# fetch <url> <sha256> <file>: download once, hash-checked before any use
# (the suite's rule for every dependency: the pin is the integrity gate).
fetch() {
  local url="$1" sha="$2" file="$3"
  if [ -f "$file" ] && echo "$sha  $file" | sha256sum -c --quiet - 2>/dev/null; then
    return 0
  fi
  rm -f "$file"
  curl -fsSL --retry 4 --retry-delay 2 -o "$file.part" "$url"
  echo "$sha  $file.part" | sha256sum -c --quiet -
  mv "$file.part" "$file"
}

# OpenSSL, static, for this ABI: torrentxt, datachannelxt and curlxt carry
# their TLS inside the library, as their 64-bit Linux and mac builds do. An
# Android app could not rely on a system libssl anyway: Android has none an
# app may link.
OPENSSL_PREFIX="$DEPS/openssl-$OPENSSL_VERSION-$PLATFORM"
need_openssl() {
  if [ -f "$OPENSSL_PREFIX/lib/libssl.a" ] && [ -f "$OPENSSL_PREFIX/lib/libcrypto.a" ]; then
    return 0
  fi
  echo "== build-android: OpenSSL $OPENSSL_VERSION for $PLATFORM =="
  fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" \
        "$OPENSSL_SHA256" "$DEPS/openssl-$OPENSSL_VERSION.tar.gz"
  local src="$DEPS/openssl-src-$PLATFORM"
  rm -rf "$src" "$OPENSSL_PREFIX"
  mkdir -p "$src"
  tar -C "$src" -xzf "$DEPS/openssl-$OPENSSL_VERSION.tar.gz"
  (
    cd "$src/openssl-$OPENSSL_VERSION"
    # OpenSSL's Android targets find the NDK through ANDROID_NDK_ROOT and its
    # clang on PATH; -D__ANDROID_API__ is how they take the API level. That
    # level is the SUITE's floor whichever member asked first: this folder is
    # shared by curlxt, datachannelxt and torrentxt, and an OpenSSL built for
    # torrentxt's higher floor would carry what Android 5.0 lacks into the
    # other two, whose own check (the note of the final link) could not see it.
    export ANDROID_NDK_ROOT="$NDK"
    export PATH="$TOOLCHAIN_BIN:$PATH"
    ./Configure "$OPENSSL_TARGET" "-D__ANDROID_API__=$FLOOR_API" \
      no-shared no-module no-tests -fPIC \
      --prefix="$OPENSSL_PREFIX" --libdir=lib > "$src/configure.log" 2>&1 \
      || { tail -40 "$src/configure.log" >&2; exit 1; }
    make -s -j"$JOBS" > "$src/make.log" 2>&1 || { tail -40 "$src/make.log" >&2; exit 1; }
    make -s install_sw > "$src/install.log" 2>&1 || { tail -40 "$src/install.log" >&2; exit 1; }
  )
  rm -rf "$src"
}

# Boost, headers only (libtorrent links nothing from Boost), one tree for
# every ABI.
BOOST_PREFIX="$DEPS/boost-$BOOST_VERSION"
need_boost() {
  if [ -f "$BOOST_PREFIX/boost/version.hpp" ]; then
    return 0
  fi
  echo "== build-android: Boost $BOOST_VERSION headers =="
  fetch "https://github.com/boostorg/boost/releases/download/boost-$BOOST_VERSION/boost-$BOOST_VERSION-b2-nodocs.tar.gz" \
        "$BOOST_SHA256" "$DEPS/boost-$BOOST_VERSION.tar.gz"
  rm -rf "$BOOST_PREFIX"
  tar -C "$DEPS" -xzf "$DEPS/boost-$BOOST_VERSION.tar.gz" "boost-$BOOST_VERSION/boost"
}

# ------------------------------------------------------------------ the tests
# The member's registered tests, each run on the device through
# tools/android-run.sh. They are enumerated from ctest's own JSON and
# launched one by one (the release workflow's Rosetta step does the same for
# the mac x86_64 slice) rather than run by ctest through
# CMAKE_CROSSCOMPILING_EMULATOR: that variable also makes CMake RUN its
# configure-time probes on the device, so a build with a device attached
# could configure differently from one without, and the library must be the
# same file either way.
run_tests() {
  if [ -z "$SERIAL" ]; then
    return 0
  fi
  # What goes to the device is STRIPPED, as the library that ships is: the
  # tests then run against the bytes a user gets (the same strip of the same
  # file), and a library whose symbol table alone is over a hundred megabytes
  # (torrentxt, with libtorrent inside) is not pushed once per test to an
  # emulator with a small data partition.
  local device="$BUILD/device"
  rm -rf "$device"
  mkdir -p "$device"
  for lib in "$BUILD"/*.so; do
    [ -f "$lib" ] || continue
    "$TOOLCHAIN_BIN/llvm-strip" --strip-unneeded -o "$device/$(basename "$lib")" "$lib"
  done
  ctest --test-dir "$BUILD" --show-only=json-v1 > "$BUILD/ctest-tests.json"
  XTALK_ANDROID_SERIAL="$SERIAL" python3 - "$BUILD/ctest-tests.json" "$ROOT/tools/android-run.sh" \
      "$device" "$TOOLCHAIN_BIN/llvm-strip" <<'PYEOF'
import json, os, subprocess, sys
listing, runner, device, strip = sys.argv[1:5]
tests = [t for t in json.load(open(listing))["tests"] if t.get("command")]
if not tests:
    # ctest exits 0 on an empty test set, and a lane that ran nothing must
    # not read as one that passed.
    sys.exit("build-android: no tests registered - nothing would run on the device")
for t in tests:
    # A bound on every test: a test that hangs on the device would otherwise
    # hold the lane until the job's own limit, with nothing to say which
    # test it was. Three times the test's own ctest TIMEOUT where it has one
    # (an emulator is slower than the machine that limit was written for),
    # and never under ten minutes.
    limit = 600
    for prop in t.get("properties", []):
        if prop.get("name") == "TIMEOUT":
            limit = max(limit, int(float(prop["value"]) * 3))
    exe = os.path.join(device, os.path.basename(t["command"][0]))
    subprocess.run([strip, "--strip-unneeded", "-o", exe, t["command"][0]], check=True)
    print("android: %s (limit %d s)" % (t["name"], limit), flush=True)
    try:
        subprocess.run(["bash", runner, exe] + t["command"][1:], check=True, timeout=limit)
    except subprocess.TimeoutExpired:
        sys.exit("build-android: %s did not finish on the device in %d s" % (t["name"], limit))
    os.remove(exe)      # android-run.sh pushes every .so beside the test, and only those
print("android: %d test(s) passed on the device" % len(tests))
PYEOF
  TESTS="RUN on $SERIAL, passed"
}

echo "== build-android: $MEMBER for $PLATFORM ($ABI, API $ANDROID_API, NDK $have) =="
rm -rf "$BUILD"
mkdir -p "$BUILD"

if [ "$MEMBER" = "coinxt" ]; then
  # coinxt builds from its own script, as on every other platform: `pack`
  # compiles the shim and both vendored libraries, links them through
  # src/coinxt.map, strips, and writes src/code/<platform-id>/coinxt.so.
  export CC="$TOOLCHAIN_BIN/clang --target=$TRIPLE$ANDROID_API"
  export NM="$TOOLCHAIN_BIN/llvm-nm"
  export STRIP="$TOOLCHAIN_BIN/llvm-strip"
  ( cd "$ROOT/coinxt" && sh native/build.sh pack "$PLATFORM" ) > "$BUILD/pack.log" 2>&1 \
    || { tail -40 "$BUILD/pack.log" >&2; exit 1; }
  grep '^built ' "$BUILD/pack.log"
  # The self-test that `build.sh asan` runs on the host, built for Android
  # against the same sources, and run where there is a device.
  ( cd "$ROOT/coinxt" && sh native/build.sh selftest "$BUILD/cnx_selftest" ) > "$BUILD/selftest.log" 2>&1 \
    || { tail -40 "$BUILD/selftest.log" >&2; exit 1; }
  if [ -n "$SERIAL" ]; then
    XTALK_ANDROID_SERIAL="$SERIAL" timeout 600 bash "$ROOT/tools/android-run.sh" "$BUILD/cnx_selftest"
    TESTS="RUN on $SERIAL, passed"
  fi
else
  flag="$(printf '%s' "$MEMBER" | tr '[:lower:]' '[:upper:]')_BUILD_TESTS"
  args=(
    -S "$ROOT/$MEMBER" -B "$BUILD" -G Ninja
    "-DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake"
    "-DANDROID_ABI=$ABI"
    "-DANDROID_PLATFORM=android-$ANDROID_API"
    # libc++ INSIDE the library. Each one exports a C ABI only, so no C++
    # object crosses a library boundary and each can carry its own runtime;
    # the alternative, libc++_shared.so, is a file every app would have to
    # ship beside ours, and OXT-Beyond's engine does not.
    -DANDROID_STL=c++_static
    -DCMAKE_BUILD_TYPE=Release
    "-D$flag=ON"
  )
  roots=""
  case "$MEMBER" in
    sodiumxt)
      # This script does the placing (stripped, below), as for every member.
      args+=(-DSODIUMXT_PLACE_IN_SRC=OFF) ;;
    box2dxt)
      # The desktop rows' reasons, per ABI: AVX2 off keeps the x86_64 library
      # to what every x86_64 Android device has (SSE4.2 at most), and 32-bit
      # x86 is scalar, as box2dxt's x86 libraries are everywhere. The two
      # ARM ABIs take Box2D's NEON path, which every device of either has.
      case "$PLATFORM" in
        x86_64-android) args+=(-DBOX2D_AVX2=OFF) ;;
        x86-android)    args+=(-DBOX2D_DISABLE_SIMD=ON) ;;
      esac ;;
    box3dxt)
      # Nothing to pass. Box3D picks its AVX2 solver at RUN time (so the
      # x86_64 library needs no flag to stay loadable everywhere), the
      # member's own CMake asks for SSE2 arithmetic on 32-bit x86, and the
      # two ARM ABIs take the NEON path.
      : ;;
    audioxt)
      # Nothing to pass. miniaudio is one header the member's CMake fetches,
      # and it finds Android's audio (AAudio from API 26, OpenSL ES below
      # it) at RUN time, so the library names neither in DT_NEEDED and loads
      # at API 21.
      : ;;
    render3dxt)
      # Nothing to pass. The renderer is plain C with no SIMD of its own and
      # no dependency outside the two single-file readers its CMake fetches;
      # its threads are bionic's pthreads, and its tests carry their model
      # and picture files inside them, so they run from the pushed folder.
      : ;;
    xlsxt)
      # Nothing to pass. libxlsxwriter, zlib and Expat are plain C built from
      # source inside the member's CMake, with no dependency and no
      # per-processor code path, so one recipe serves all four ABIs.
      : ;;
    curlxt|datachannelxt)
      need_openssl
      roots="$OPENSSL_PREFIX"
      args+=("-DOPENSSL_ROOT_DIR=$OPENSSL_PREFIX" -DOPENSSL_USE_STATIC_LIBS=ON) ;;
    torrentxt)
      need_openssl
      need_boost
      roots="$OPENSSL_PREFIX;$BOOST_PREFIX"
      args+=("-DOPENSSL_ROOT_DIR=$OPENSSL_PREFIX" -DOPENSSL_USE_STATIC_LIBS=ON
             "-DBOOST_ROOT=$BOOST_PREFIX")
      JOBS="${XTALK_ANDROID_JOBS:-2}" ;;
  esac
  if [ -n "$roots" ]; then
    # The NDK's toolchain file confines find_package to its sysroot; this is
    # how a dependency built outside it is found, and nothing of the build
    # machine's own is.
    args+=("-DCMAKE_FIND_ROOT_PATH=$roots")
  fi
  cmake "${args[@]}" > "$BUILD/configure.log" 2>&1 || { tail -60 "$BUILD/configure.log" >&2; exit 1; }
  cmake --build "$BUILD" --parallel "$JOBS" > "$BUILD/build.log" 2>&1 \
    || { grep -n -E 'error|FAILED' "$BUILD/build.log" | head -40 >&2; tail -20 "$BUILD/build.log" >&2; exit 1; }

  # CMake names the library for the member's bare token, or with "lib" in
  # front where the member's CMake keeps the prefix (box2dxt); the file the
  # tree holds is always the bare token, as on every other platform.
  built=""
  for name in "$MEMBER.so" "lib$MEMBER.so"; do
    if [ -f "$BUILD/$name" ]; then built="$BUILD/$name"; break; fi
  done
  if [ -z "$built" ]; then
    echo "build-android: the build made no $MEMBER.so in $BUILD" >&2
    exit 1
  fi

  run_tests

  # Strip the COPY (the build folder keeps its symbols), with the NDK's
  # strip: the build machine's binutils does not read an ARM library, and
  # an unstripped torrentxt is over a hundred megabytes.
  mkdir -p "$OUT_DIR"
  cp "$built" "$OUT.tmp"
  "$TOOLCHAIN_BIN/llvm-strip" --strip-unneeded "$OUT.tmp"
  mv "$OUT.tmp" "$OUT"
  echo "built $OUT"
fi

# The contract, asserted where the library is born, by the code the release
# workflow's installer runs again before anything is committed.
python3 "$ROOT/tools/install-release-binaries.py" --android-check "$OUT"

echo "== build-android: $MEMBER/$PLATFORM: $(stat -c %s "$OUT") bytes; tests $TESTS =="
