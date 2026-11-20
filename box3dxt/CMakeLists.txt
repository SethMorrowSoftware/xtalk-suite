cmake_minimum_required(VERSION 3.22)
project(box3dxt LANGUAGES C)

# ---------------------------------------------------------------------------
# box3dxt - Box3D (Erin Catto's 3D rigid-body engine) for OpenXTalk (OXT) and
# the xTalk family, also compatible with LiveCode 9.6.3+. This builds the C
# shim (src/box3d_shim.c) and Box3D into ONE loadable library named "box3dxt",
# or for the web into a static archive (below). box2dxt/CMakeLists.txt is this
# file's ancestor.
# ---------------------------------------------------------------------------

option(BOX3DXT_BUILD_TESTS "Build the box3dxt runtime smoke test" OFF)
option(BOX3DXT_PLACE_IN_SRC
       "Web build only: copy box3dxt.a into src/code/wasm32-emscripten/ after building" ON)
set(BOX3DXT_SANITIZE "" CACHE STRING "Sanitizer: '' or 'address' (ASan + UBSan, gcc or clang)")

# The web build (wasm32-emscripten, below) is a release archive: optimised
# unless a build type is given.
if(EMSCRIPTEN AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Box3D builds as a static library that is linked into our shared library, so
# every Box3D object must be position-independent (box2dxt's lesson: the
# manylinux toolchain does not default to PIE). Not for the web build, whose
# archive is linked into the engine: position-independent wasm reaches memory
# through __memory_base, which only a dynamically linked module needs.
if(NOT EMSCRIPTEN)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

# The Windows libraries carry the C runtime (static CRT, as curlxt's do), so a
# PC without the Visual C++ Redistributable loads them and a package needs no
# runtime DLLs beside them.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(BOX3DXT_SANITIZE STREQUAL "address")
    # Applies to Box3D too (the options precede its targets), so a bad read
    # inside the engine that the shim caused is reported, not just the shim's.
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
endif()

# ---------------------------------------------------------------------------
# 32-bit x86 builds with SSE2 arithmetic (measured 2026-11-20, gcc 13 -m32).
# Box3D's own unit tests pass on a 32-bit build with SSE2 and FAIL its
# determinism test on the scalar build (-DBOX3D_DISABLE_SIMD=ON), where gcc
# falls back to the x87 stack and its 80-bit intermediates. So this member's
# x86 libraries are NOT scalar, unlike box2dxt's: SSE2 is the floor (every x86
# CPU since 2003, and required by 64-bit Windows and by Android's x86 ABI).
# gcc and clang need the flags said out loud; MSVC's 32-bit default is SSE2.
# ---------------------------------------------------------------------------
if(NOT EMSCRIPTEN AND NOT MSVC AND CMAKE_SIZEOF_VOID_P EQUAL 4)
    include(CheckCSourceCompiles)
    check_c_source_compiles("
        #if !defined(__i386__)
        #error not 32-bit x86
        #endif
        int main(void) { return 0; }" BOX3DXT_IS_X86_32)
    if(BOX3DXT_IS_X86_32)
        add_compile_options(-msse2 -mfpmath=sse)
    endif()
endif()

# ---------------------------------------------------------------------------
# Fetch Box3D, pinned to a COMMIT: Box3D has no release tags yet
# (2026-11-20), and a commit id names the exact tree where a branch would
# move. Bump BOX3DXT_BOX3D_COMMIT to update, then rebuild every platform
# (suite rule 5) and re-run the smoke test: the shim is written against this
# revision's API. -DFETCHCONTENT_SOURCE_DIR_BOX3D=<checkout> builds from a
# local copy with no network.
# ---------------------------------------------------------------------------
set(BOX3DXT_BOX3D_COMMIT "1767150df433d94ffccd96f550431351403c4e8e")
include(FetchContent)
FetchContent_Declare(
    box3d
    GIT_REPOSITORY https://github.com/erincatto/box3d.git
    GIT_TAG        ${BOX3DXT_BOX3D_COMMIT}
)

# Box3D's samples, unit tests, benchmarks and docs are top-level-only options
# of its own CMake, so a FetchContent consumer builds the library alone.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

# The web build has no SIMD and no threads: scalar math (WebAssembly's floats
# are strict IEEE, so the determinism caveat above does not apply), and the
# shim asks for one worker (src/box3d_shim.c, __EMSCRIPTEN__).
if(EMSCRIPTEN)
    set(BOX3D_DISABLE_SIMD ON CACHE BOOL "" FORCE)
endif()

FetchContent_MakeAvailable(box3d)

# Box3D is pinned to a known-good commit, so an upstream warning on a newer
# compiler must never fail this build (box2dxt's lesson with -Werror).
if(TARGET box3d)
    set_target_properties(box3d PROPERTIES COMPILE_WARNING_AS_ERROR OFF)
endif()

# Under the sanitizers, Box3D alone is excused UBSan's ALIGNMENT check, and
# nothing else. Its SSE2 loader reads three floats with _mm_load_sd through a
# float pointer (simd_sse2.h b3LoadV, met from b3QueryMesh on 2026-11-20): a
# 4-byte-aligned address read as a double. x86 performs that load at any
# alignment, so it is upstream's formal slip and not a fault; but with
# -fno-sanitize-recover it would stop the run at the first mesh contact and
# hide everything the lane exists to find. The shim and the test keep every
# check, alignment included.
if(TARGET box3d AND BOX3DXT_SANITIZE STREQUAL "address")
    target_compile_options(box3d PRIVATE -fno-sanitize=alignment)
endif()

# ---------------------------------------------------------------------------
# The web build: wasm32-emscripten. A browser loads no library, so for
# OXT-Beyond's web IDE the shim is linked INTO the engine, which keeps a table
# of the libraries compiled into it and finds "c:box3dxt>b3x_..." there by
# name. What is built is a static archive, box3dxt.a, holding ONE relocatable
# object: the shim and the members of Box3D it uses, linked together
# (emcc -r), plus a table of the symbols the binding names:
#
#     const struct { const char *symbol; void *address; } *
#     box3dxt_web_exports(void);       /* ends with { NULL, NULL } */
#
# The table is GENERATED from every `binds to "c:box3dxt>NAME"` of
# src/box3dxt.lcb, so it cannot drift from the binding, and compiled in ONE
# translation unit with src/box3d_shim.c (which it includes), so a bind with
# no shim function is a compile error, never a missing symbol found in a
# browser. Declared with its real prototype, each address is the function
# itself: WebAssembly checks a call's type. This is box2dxt's mechanism,
# unchanged.
# ---------------------------------------------------------------------------
if(EMSCRIPTEN)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/box3dxt.lcb" _b3x_lcb)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${CMAKE_CURRENT_SOURCE_DIR}/src/box3dxt.lcb")
    string(REGEX MATCHALL "binds to \"c:box3dxt>[A-Za-z_][A-Za-z0-9_]*" _b3x_binds "${_b3x_lcb}")
    set(_b3x_symbols "")
    foreach(_bind IN LISTS _b3x_binds)
        string(REGEX REPLACE ".*>" "" _symbol "${_bind}")
        list(APPEND _b3x_symbols "${_symbol}")
    endforeach()
    list(REMOVE_DUPLICATES _b3x_symbols)
    list(SORT _b3x_symbols)
    list(LENGTH _b3x_symbols _b3x_count)
    if(_b3x_count EQUAL 0)
        message(FATAL_ERROR "src/box3dxt.lcb binds no c:box3dxt> symbol: is the regular expression stale?")
    endif()
    set(_b3x_rows "")
    foreach(_symbol IN LISTS _b3x_symbols)
        string(APPEND _b3x_rows "\t{ \"${_symbol}\", (void *)${_symbol} },\n")
    endforeach()
    set(_b3x_exports_c "${CMAKE_CURRENT_BINARY_DIR}/box3dxt_web_exports.c")
    file(CONFIGURE OUTPUT "${_b3x_exports_c}" @ONLY CONTENT
"/* GENERATED by CMakeLists.txt from src/box3dxt.lcb: the shim, and the
 * @_b3x_count@ symbols the binding binds to, for OXT-Beyond's web engine. */
#include \"box3d_shim.c\"

struct b3x_web_export { const char *symbol; void *address; };

static const struct b3x_web_export k_b3x_web_exports[] = {
@_b3x_rows@\t{ NULL, NULL },
};

LC_API const struct b3x_web_export *box3dxt_web_exports(void);
LC_API const struct b3x_web_export *box3dxt_web_exports(void)
{
\treturn k_b3x_web_exports;
}
")
    message(STATUS "box3dxt web exports: ${_b3x_count} symbols from src/box3dxt.lcb")

    # -g0 and the prefix maps keep the build folder's path out of the object,
    # so the same source and Emscripten give the same archive anywhere.
    add_library(box3dxt_web_objects OBJECT "${_b3x_exports_c}")
    target_include_directories(box3dxt_web_objects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(box3dxt_web_objects PRIVATE box3d)
    set_target_properties(box3dxt_web_objects PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
    target_compile_options(box3dxt_web_objects PRIVATE
        -Os -g0 -Wall -Wextra -Werror=implicit-function-declaration
        "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=box3dxt"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")
    target_compile_options(box3d PRIVATE -g0
        "-ffile-prefix-map=${box3d_SOURCE_DIR}=box3d"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")

    set(_b3x_web_object "${CMAKE_CURRENT_BINARY_DIR}/box3dxt-web.o")
    set(_b3x_web_archive "${CMAKE_CURRENT_BINARY_DIR}/box3dxt.a")
    add_custom_command(
        OUTPUT "${_b3x_web_archive}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${_b3x_web_object}" "${_b3x_web_archive}"
        COMMAND ${CMAKE_C_COMPILER} -r -o "${_b3x_web_object}"
                "$<TARGET_OBJECTS:box3dxt_web_objects>" "$<TARGET_FILE:box3d>"
        COMMAND ${CMAKE_AR} rcsD "${_b3x_web_archive}" "${_b3x_web_object}"
        DEPENDS box3dxt_web_objects box3d "$<TARGET_OBJECTS:box3dxt_web_objects>"
        COMMAND_EXPAND_LISTS
        COMMENT "Linking box3dxt.a for the web (shim + Box3D, one object)"
        VERBATIM)
    add_custom_target(box3dxt_web ALL DEPENDS "${_b3x_web_archive}")

    # The web smoke test: tests/smoke_test.c, linked against the ARCHIVE and
    # run by node (ctest), so what is tested is the file that would ship.
    if(BOX3DXT_BUILD_TESTS)
        enable_testing()
        add_executable(box3dxt_smoke tests/smoke_test.c)
        add_dependencies(box3dxt_smoke box3dxt_web)
        set_target_properties(box3dxt_smoke PROPERTIES SUFFIX ".js"
                              C_STANDARD 17 C_STANDARD_REQUIRED ON)
        target_link_libraries(box3dxt_smoke PRIVATE "${_b3x_web_archive}")
        target_link_options(box3dxt_smoke PRIVATE -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node)
        find_program(BOX3DXT_NODE node REQUIRED)
        add_test(NAME smoke COMMAND "${BOX3DXT_NODE}" "$<TARGET_FILE:box3dxt_smoke>")
        # The random-call test (tests/fuzz_test.c), over the same archive.
        add_executable(box3dxt_fuzz tests/fuzz_test.c)
        add_dependencies(box3dxt_fuzz box3dxt_web)
        set_target_properties(box3dxt_fuzz PROPERTIES SUFFIX ".js"
                              C_STANDARD 17 C_STANDARD_REQUIRED ON)
        target_link_libraries(box3dxt_fuzz PRIVATE "${_b3x_web_archive}")
        target_link_options(box3dxt_fuzz PRIVATE -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node)
        add_test(NAME fuzz COMMAND "${BOX3DXT_NODE}" "$<TARGET_FILE:box3dxt_fuzz>")
    endif()

    if(BOX3DXT_PLACE_IN_SRC)
        set(_b3x_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/wasm32-emscripten")
        add_custom_command(TARGET box3dxt_web POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_b3x_bundle_dir}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_b3x_web_archive}" "${_b3x_bundle_dir}/box3dxt.a"
            COMMENT "Bundling box3dxt.a -> src/code/wasm32-emscripten/"
            VERBATIM)
    endif()
    return()
endif()

# ---------------------------------------------------------------------------
# The shim + Box3D, linked into a single shared library under its BARE name:
# box3dxt.so (Linux, Android), box3dxt.dylib (macOS), box3dxt.dll (Windows).
# The bare name is the one the tree holds on every platform and, on Linux, the
# soname the engine's dlopen asks for. The LCB bind string "c:box3dxt>..."
# resolves to it.
# ---------------------------------------------------------------------------
add_library(box3dxt SHARED src/box3d_shim.c)
target_link_libraries(box3dxt PRIVATE box3d)

set_target_properties(box3dxt PROPERTIES
    C_STANDARD 17
    C_STANDARD_REQUIRED ON
    C_VISIBILITY_PRESET hidden      # export only the LC_API shim symbols
    PREFIX ""
    OUTPUT_NAME "box3dxt"
)

# Keep the shim warning-clean (these flags apply only to box3d_shim.c).
if(MSVC)
    target_compile_options(box3dxt PRIVATE /W3)
    target_compile_definitions(box3dxt PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(box3dxt PRIVATE -Wall -Wextra)
endif()

# Export b3x_* and nothing else. Box3D is compiled with hidden visibility, so
# this changes little on ELF (it drops the linker's own _init/_fini from the
# dynamic table), but it is the family's rule since enetxt's release run 10
# leaked a vendored library's symbols: the script, not the default, decides.
# src/box3dxt.map is the one source for GNU ld and, by the pattern below, for
# ld64 (which takes wildcards in an exported-symbols list).
set(_b3x_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/box3dxt.map")
if(APPLE)
    set(_b3x_exported "${CMAKE_CURRENT_BINARY_DIR}/box3dxt.exported_symbols")
    file(WRITE "${_b3x_exported}" "_b3x_*\n")
    target_link_options(box3dxt PRIVATE "-Wl,-exported_symbols_list,${_b3x_exported}")
elseif(UNIX)
    include(CheckLinkerFlag)
    check_linker_flag(C "-Wl,--version-script=${_b3x_version_script}" B3X_HAVE_VERSION_SCRIPT)
    if(B3X_HAVE_VERSION_SCRIPT)
        target_link_options(box3dxt PRIVATE "-Wl,--version-script=${_b3x_version_script}")
        set_target_properties(box3dxt PROPERTIES LINK_DEPENDS "${_b3x_version_script}")
    endif()
endif()

# ---------------------------------------------------------------------------
# The runtime smoke test. It links the shim and drives the real engine through
# every export (gravity, stacking, every shape, every joint, queries, events,
# the stale-handle and bad-argument guards).
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBOX3DXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --output-on-failure
# ---------------------------------------------------------------------------
if(BOX3DXT_BUILD_TESTS)
    enable_testing()
    add_executable(box3dxt_smoke tests/smoke_test.c)
    set_target_properties(box3dxt_smoke PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
    target_link_libraries(box3dxt_smoke PRIVATE box3dxt)
    if(MSVC)
        target_compile_definitions(box3dxt_smoke PRIVATE _CRT_SECURE_NO_WARNINGS)
    else()
        target_link_libraries(box3dxt_smoke PRIVATE m)
    endif()
    add_test(NAME smoke COMMAND box3dxt_smoke)

    # The random-call test: every export, any argument, any order
    # (tests/fuzz_test.c says what it holds). Seeds 1 to 3 by default.
    add_executable(box3dxt_fuzz tests/fuzz_test.c)
    set_target_properties(box3dxt_fuzz PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
    target_link_libraries(box3dxt_fuzz PRIVATE box3dxt)
    if(MSVC)
        target_compile_definitions(box3dxt_fuzz PRIVATE _CRT_SECURE_NO_WARNINGS)
    else()
        target_link_libraries(box3dxt_fuzz PRIVATE m)
    endif()
    add_test(NAME fuzz COMMAND box3dxt_fuzz)
endif()
