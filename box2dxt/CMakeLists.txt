cmake_minimum_required(VERSION 3.22)
project(box2dxt LANGUAGES C)

find_package(Threads REQUIRED)

# Box2D builds as a static lib that we link into our shared library, so every
# Box2D object must be position-independent. Ubuntu's gcc defaults to PIE (local
# builds link fine), but toolchains that don't -- e.g. the manylinux2014
# devtoolset used for the portable release binaries -- otherwise fail to link the
# .so on x86-64 with "relocation R_X86_64_32 against `.text` ... recompile with
# -fPIC". Forcing PIC here (before Box2D's targets are created) fixes it on every
# toolchain and is always valid on the architectures we ship.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ---------------------------------------------------------------------------
# Box2Dxt — the native Box2D v3 module for OpenXTalk (OXT) / xTalk, also
# compatible with LiveCode 9.6.3+. This builds the C shim (src/box2d_lc.c)
# and Box2D into one loadable library named "box2dxt".
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Fetch Box2D v3.1.0 (pinned). Bump GIT_TAG to update; the shim is written
# against the 3.1 API (friction/restitution live in b2ShapeDef.material).
# ---------------------------------------------------------------------------
include(FetchContent)
FetchContent_Declare(
    box2d
    GIT_REPOSITORY https://github.com/erincatto/box2d.git
    GIT_TAG        v3.1.0
)

# Build only the library — none of the extras.
set(BOX2D_SAMPLES    OFF CACHE BOOL "" FORCE)
set(BOX2D_BENCHMARKS OFF CACHE BOOL "" FORCE)
set(BOX2D_UNIT_TESTS OFF CACHE BOOL "" FORCE)
set(BOX2D_DOCS       OFF CACHE BOOL "" FORCE)
set(BOX2D_VALIDATE   OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(box2d)

# ---------------------------------------------------------------------------
# Box2D 3.1.0 builds its own sources with -Wall -Wextra -pedantic -Werror
# (MSVC: /Wall + /WX implications). Modern compilers (e.g. GCC 13+) emit
# false-positive warnings such as -Wmaybe-uninitialized in Release, which then
# fail the *whole* build before our shim is ever linked. We pin Box2D to a
# known-good tag, so demote its warnings to non-fatal: keep them visible, but
# never let an upstream warning break our build.
# ---------------------------------------------------------------------------
if(TARGET box2d)
    # Box2D 3.1 turns on warnings-as-errors TWO independent ways:
    #   1. an explicit -Werror in its target COMPILE_OPTIONS, and
    #   2. the CMake COMPILE_WARNING_AS_ERROR target property (3.24+), which
    #      makes CMake append its OWN -Werror / /WX at the very end of the
    #      command line -- after anything we could add ourselves.
    # On newer compilers Box2D emits otherwise-harmless warnings (e.g.
    # -Wmaybe-uninitialized in Release with GCC 13+) that then fail the whole
    # build before our shim ever links. We pin Box2D to a known-good tag, so
    # neutralise both sources rather than depend on flag ordering.
    set_target_properties(box2d PROPERTIES COMPILE_WARNING_AS_ERROR OFF)
    get_target_property(_b2_opts box2d COMPILE_OPTIONS)
    if(_b2_opts)
        list(REMOVE_ITEM _b2_opts "-Werror")
        set_target_properties(box2d PROPERTIES COMPILE_OPTIONS "${_b2_opts}")
    endif()
endif()

# ---------------------------------------------------------------------------
# The shim + Box2D, linked into a single shared library named "box2dxt".
# Produces: libbox2dxt.so (Linux), libbox2dxt.dylib (macOS), box2dxt.dll (Win).
# The xTalk Builder (LCB) FFI binding string "c:box2dxt>..." resolves to these.
# ---------------------------------------------------------------------------
add_library(box2dxt SHARED src/box2d_lc.c)
target_link_libraries(box2dxt PRIVATE box2d Threads::Threads)

set_target_properties(box2dxt PROPERTIES
    C_STANDARD 17
    C_STANDARD_REQUIRED ON
    C_VISIBILITY_PRESET hidden      # export only the LC_API shim symbols
    OUTPUT_NAME "box2dxt"
)

# --- Linux loader assist (spike, opt-in) -----------------------------------
# Build the library under its BARE deploy name (box2dxt.so / box2dxt.dylib)
# instead of libbox2dxt.*. Dropping the prefix makes CMake stamp the ELF/Mach-O
# soname as "box2dxt.so" -- the exact name OXT hands to dlopen at run time.
# That match is what lets a script PRELOAD the file by absolute path (see
# b2LoadNativeLib in src/box2dxt.lcb) and have the engine's later bare-name
# bind resolve to the already-resident copy. glibc matches an already-loaded
# object by soname, NOT by filename, so renaming libbox2dxt.so -> box2dxt.so
# on disk is NOT enough; the soname has to be box2dxt.so too. As a bonus it
# removes the rename-on-deploy step. OFF keeps the historical libbox2dxt.*
# (rename-on-deploy) until the preload path is confirmed in OXT.
option(BOX2DXT_BARE_SONAME "Emit the library under its bare deploy name so its soname matches what OXT dlopens (Linux loader assist)" OFF)
if(BOX2DXT_BARE_SONAME)
    set_target_properties(box2dxt PROPERTIES PREFIX "")
endif()

# Keep our own shim warning-clean (these flags apply only to box2d_lc.c).
if(MSVC)
    target_compile_options(box2dxt PRIVATE /W3)
else()
    target_compile_options(box2dxt PRIVATE -Wall -Wextra)
endif()

# Box2D assumes AVX2 on x64 by default. For binaries that must run on older
# CPUs, configure Box2D with -DBOX2D_DISABLE_SIMD=ON (slower) or an SSE2 build.

# ---------------------------------------------------------------------------
# Optional runtime smoke test. It links the shim and drives the real engine
# (gravity, collisions, joints, queries, contact events, validity guards).
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBOX2DXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --output-on-failure
# ---------------------------------------------------------------------------
option(BOX2DXT_BUILD_TESTS "Build the box2dxt runtime smoke test" OFF)
if(BOX2DXT_BUILD_TESTS)
    enable_testing()
    add_executable(box2dxt_smoke tests/smoke_test.c)
    target_link_libraries(box2dxt_smoke PRIVATE box2dxt)
    if(NOT MSVC)
        target_link_libraries(box2dxt_smoke PRIVATE m)
    endif()
    add_test(NAME smoke COMMAND box2dxt_smoke)
endif()

# Build:
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
#   cmake --build build --config Release
