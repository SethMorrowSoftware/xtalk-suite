cmake_minimum_required(VERSION 3.22)
project(box2dxt LANGUAGES C)

find_package(Threads REQUIRED)

# The web build (wasm32-emscripten, below) is a release archive: optimised
# unless a build type is given, as sodiumxt's build is on every platform.
if(EMSCRIPTEN AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Box2D builds as a static lib that we link into our shared library, so every
# Box2D object must be position-independent. Ubuntu's gcc defaults to PIE (local
# builds link fine), but toolchains that don't -- e.g. the manylinux2014
# devtoolset used for the portable release binaries -- otherwise fail to link the
# .so on x86-64 with "relocation R_X86_64_32 against `.text` ... recompile with
# -fPIC". Forcing PIC here (before Box2D's targets are created) fixes it on every
# toolchain and is always valid on the architectures we ship.
# (Not for the web build, wasm32-emscripten, which is a static archive linked
# into the engine: position-independent wasm reaches memory through
# __memory_base, which only a dynamically linked module needs.)
if(NOT EMSCRIPTEN)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

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

# Box2D v3.1.0's own Emscripten branch cannot configure: it tests
# `if (BOX2D_DISABLE_SIMD OFF)`, which CMake refuses ("Unknown arguments") with
# either value. So for the web build (below) Box2D is configured as the Unix
# build it otherwise is (a normal variable hides the toolchain's cached
# EMSCRIPTEN for that one call); its sources still see __EMSCRIPTEN__ from
# the compiler, and nothing else in its CMake reads the variable for the
# library.
if(EMSCRIPTEN)
    # Scalar math, as on the 32-bit rows (WebAssembly SIMD could be tried
    # later, and measured)
    set(BOX2D_DISABLE_SIMD ON CACHE BOOL "" FORCE)
    set(EMSCRIPTEN OFF)
    FetchContent_MakeAvailable(box2d)
    unset(EMSCRIPTEN)
else()
    FetchContent_MakeAvailable(box2d)
endif()

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
# The web build: wasm32-emscripten (2026-10-21). A browser loads no library,
# so for OXT-Beyond's web IDE the shim is linked INTO the engine, which keeps a
# table of the libraries compiled into it and finds "c:box2dxt>b2lc_..." there
# by name (OXT-Beyond's engine/src/em-xtalk-web.cpp). What ships is a static
# archive, src/code/wasm32-emscripten/box2dxt.a, holding ONE relocatable
# object: the shim and the members of Box2D it uses, linked together
# (emcc -r), plus a table of the symbols the binding names, which the engine
# registers:
#
#     const struct { const char *symbol; void *address; } *
#     box2dxt_web_exports(void);       /* ends with { NULL, NULL } */
#
# The table is GENERATED from every `binds to "c:box2dxt>NAME"` of
# src/box2dxt.lcb, so it cannot drift from the binding, and compiled in ONE
# translation unit with src/box2d_lc.c (which it includes; the shim has no
# header), so a bind with no shim function is a compile error, never a
# missing symbol found in a browser. Declared with its real prototype, each
# address is the function itself: WebAssembly checks a call's type, and an
# address taken through a declaration of another type would be a stub that
# traps.
#
# The browser build has no threads: without -pthread, pthread_create fails,
# and b2lc_world_create_threaded already falls back to Box2D's
# single-threaded path when its pool cannot start. Box2D's SIMD is off
# (BOX2D_DISABLE_SIMD, forced above for this build).
#
# No folder name of the IDE's code-folder matcher reads "wasm32", so the
# desktop IDE and its HTML5 builder both pass this folder by.
# ---------------------------------------------------------------------------
option(BOX2DXT_PLACE_IN_SRC
       "Web build only: copy box2dxt.a into src/code/wasm32-emscripten/ after building" ON)

if(EMSCRIPTEN)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/box2dxt.lcb" _b2x_lcb)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${CMAKE_CURRENT_SOURCE_DIR}/src/box2dxt.lcb")
    string(REGEX MATCHALL "binds to \"c:box2dxt>[A-Za-z_][A-Za-z0-9_]*" _b2x_binds "${_b2x_lcb}")
    set(_b2x_symbols "")
    foreach(_bind IN LISTS _b2x_binds)
        string(REGEX REPLACE ".*>" "" _symbol "${_bind}")
        list(APPEND _b2x_symbols "${_symbol}")
    endforeach()
    list(REMOVE_DUPLICATES _b2x_symbols)
    list(SORT _b2x_symbols)
    list(LENGTH _b2x_symbols _b2x_count)
    if(_b2x_count EQUAL 0)
        message(FATAL_ERROR "src/box2dxt.lcb binds no c:box2dxt> symbol: is the regular expression stale?")
    endif()
    set(_b2x_rows "")
    foreach(_symbol IN LISTS _b2x_symbols)
        string(APPEND _b2x_rows "\t{ \"${_symbol}\", (void *)${_symbol} },\n")
    endforeach()
    set(_b2x_exports_c "${CMAKE_CURRENT_BINARY_DIR}/box2dxt_web_exports.c")
    file(CONFIGURE OUTPUT "${_b2x_exports_c}" @ONLY CONTENT
"/* GENERATED by CMakeLists.txt from src/box2dxt.lcb: the shim, and the
 * @_b2x_count@ symbols the binding binds to, for OXT-Beyond's web engine. */
#include \"box2d_lc.c\"

struct b2x_web_export { const char *symbol; void *address; };

static const struct b2x_web_export k_b2x_web_exports[] = {
@_b2x_rows@\t{ NULL, NULL },
};

LC_API const struct b2x_web_export *box2dxt_web_exports(void);
LC_API const struct b2x_web_export *box2dxt_web_exports(void)
{
\treturn k_b2x_web_exports;
}
")
    message(STATUS "box2dxt web exports: ${_b2x_count} symbols from src/box2dxt.lcb")

    # -g0 and the prefix maps keep the build folder's path out of the object,
    # so the same source and Emscripten give the same archive anywhere.
    add_library(box2dxt_web_objects OBJECT "${_b2x_exports_c}")
    target_include_directories(box2dxt_web_objects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(box2dxt_web_objects PRIVATE box2d)
    set_target_properties(box2dxt_web_objects PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
    target_compile_options(box2dxt_web_objects PRIVATE
        -Os -g0 -Wall -Wextra -Werror=implicit-function-declaration
        "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=box2dxt"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")
    target_compile_options(box2d PRIVATE -g0
        "-ffile-prefix-map=${box2d_SOURCE_DIR}=box2d"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")

    set(_b2x_web_object "${CMAKE_CURRENT_BINARY_DIR}/box2dxt-web.o")
    set(_b2x_web_archive "${CMAKE_CURRENT_BINARY_DIR}/box2dxt.a")
    add_custom_command(
        OUTPUT "${_b2x_web_archive}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${_b2x_web_object}" "${_b2x_web_archive}"
        COMMAND ${CMAKE_C_COMPILER} -r -o "${_b2x_web_object}"
                "$<TARGET_OBJECTS:box2dxt_web_objects>" "$<TARGET_FILE:box2d>"
        COMMAND ${CMAKE_AR} rcsD "${_b2x_web_archive}" "${_b2x_web_object}"
        DEPENDS box2dxt_web_objects box2d "$<TARGET_OBJECTS:box2dxt_web_objects>"
        COMMAND_EXPAND_LISTS
        COMMENT "Linking box2dxt.a for the web (shim + Box2D, one object)"
        VERBATIM)
    add_custom_target(box2dxt_web ALL DEPENDS "${_b2x_web_archive}")

    # The web smoke test: tests/smoke_test.c, linked against the ARCHIVE
    # that ships and run by node (ctest), so what is tested is the file that
    # is committed.
    option(BOX2DXT_BUILD_TESTS "Build the box2dxt runtime smoke test" OFF)
    if(BOX2DXT_BUILD_TESTS)
        enable_testing()
        add_executable(box2dxt_smoke tests/smoke_test.c)
        add_dependencies(box2dxt_smoke box2dxt_web)
        set_target_properties(box2dxt_smoke PROPERTIES SUFFIX ".js")
        target_include_directories(box2dxt_smoke PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
        target_link_libraries(box2dxt_smoke PRIVATE "${_b2x_web_archive}")
        target_link_options(box2dxt_smoke PRIVATE -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node)
        find_program(BOX2DXT_NODE node REQUIRED)
        add_test(NAME smoke COMMAND "${BOX2DXT_NODE}" "$<TARGET_FILE:box2dxt_smoke>")
    endif()

    if(BOX2DXT_PLACE_IN_SRC)
        set(_b2x_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/wasm32-emscripten")
        add_custom_command(TARGET box2dxt_web POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_b2x_bundle_dir}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_b2x_web_archive}" "${_b2x_bundle_dir}/box2dxt.a"
            COMMENT "Bundling box2dxt.a -> src/code/wasm32-emscripten/"
            VERBATIM)
    endif()
    return()
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
