cmake_minimum_required(VERSION 3.22)
project(barcodext LANGUAGES C CXX)

# ---------------------------------------------------------------------------
# barcodext - zxing-cpp (the C++ "zebra crossing" barcode library) for
# OpenXTalk (OXT) and the xTalk family, also compatible with LiveCode 9.6.3+.
# This builds the C++ shim (src/barcode_shim.cpp) and zxing-cpp into ONE
# loadable library named "barcodext", or for the web into a static archive
# (below). webpxt/CMakeLists.txt is this file's sibling; box3dxt's is their
# ancestor.
# ---------------------------------------------------------------------------

option(BARCODEXT_BUILD_TESTS "Build the barcodext runtime tests" OFF)
option(BARCODEXT_PLACE_IN_SRC
       "Web build only: copy barcodext.a into src/code/wasm32-emscripten/ after building" ON)
set(BARCODEXT_SANITIZE "" CACHE STRING "Sanitizer: '' or 'address' (ASan + UBSan, gcc or clang)")

# The web build (wasm32-emscripten, below) is a release archive: optimised
# unless a build type is given.
if(EMSCRIPTEN AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# zxing-cpp builds as a static library that is linked into our shared
# library, so every object must be position-independent. Not for the web
# build, whose archive is linked into the engine.
if(NOT EMSCRIPTEN)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

# zxing-cpp 3 is C++20 (std::span, concepts, <bit>); the shim is held to the
# same standard so one compiler mode builds both.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# The Windows libraries carry the C and C++ runtimes (static CRT, as
# curlxt's do), so a PC without the Visual C++ Redistributable loads them.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(BARCODEXT_SANITIZE STREQUAL "address")
    # Applies to zxing-cpp too (the options precede its targets): a bad read
    # inside the decoder on a damaged picture is exactly what the lane is for.
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
    # The sanitizer lane tests the code that SHIPS, which is a Release build:
    # NDEBUG, so zxing-cpp's assert()s are compiled out. One of them is itself
    # undefined (Pattern.h's ToInt asserts on a sum of "no bar here" markers,
    # each INT_MIN, in the MicroPDF417 reader: observed 2026-11-20 under
    # UBSan on the first picture read), and it is not in any library we ship.
    add_compile_definitions(NDEBUG)
endif()

# ---------------------------------------------------------------------------
# Fetch zxing-cpp, pinned to the COMMIT of its v3.1.1 tag (a tag can be moved;
# a commit id cannot). Bump BARCODEXT_ZXING_COMMIT to update, then rebuild
# every platform (suite rule 5) and re-run the tests. The fetch takes the
# repository's one submodule with it: zint, the encoder zxing-cpp's writer is
# built on, at the commit zxing-cpp itself pins (55541e1). The licences were
# read at these commits: zxing-cpp Apache-2.0, zint's backend and libzueci
# BSD-3-Clause, all carried in LICENSE.
# -DFETCHCONTENT_SOURCE_DIR_ZXING=<checkout> builds from a local copy (with
# its submodule checked out) and no network.
# ---------------------------------------------------------------------------
set(BARCODEXT_ZXING_VERSION "3.1.1")
set(BARCODEXT_ZXING_COMMIT "287c85df6f961c8efbfb5ffd736cd9457b8b890e")
include(FetchContent)
FetchContent_Declare(
    zxing
    GIT_REPOSITORY https://github.com/zxing-cpp/zxing-cpp.git
    GIT_TAG        ${BARCODEXT_ZXING_COMMIT}
    # The library alone: core/ is its own CMake project. The top level would
    # add examples, wrappers and a search for stb and OpenCV.
    SOURCE_SUBDIR  core
)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(ZXING_READERS ON CACHE BOOL "" FORCE)
# NEW is the writer zxing-cpp 3 keeps (over the bundled zint); OLD is the one
# it has deprecated.
set(ZXING_WRITERS "NEW" CACHE STRING "" FORCE)
set(ZXING_USE_BUNDLED_ZINT ON CACHE BOOL "" FORCE)
set(ZXING_C_API OFF CACHE BOOL "" FORCE)
set(ZXING_EXPERIMENTAL_API OFF CACHE BOOL "" FORCE)
# No precompiled header: it buys seconds and costs a different build on every
# compiler (and breaks a two-architecture mac build).
set(ZXING_DISABLE_PCH ON CACHE BOOL "" FORCE)

# The web archive must be the same bytes wherever it is built: no debug
# info, and the build folder's path (where zxing-cpp is fetched to) mapped
# away. Set before zxing-cpp's targets exist, so it reaches them.
if(EMSCRIPTEN)
    add_compile_options(-g0 "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build")
    # zxing-cpp THROWS (an unknown kind, content a kind cannot hold) and the
    # shim's firewall catches. Emscripten compiles `catch` out unless told
    # otherwise, and a throw then aborts the whole engine. -fexceptions is
    # the model OXT-Beyond's web engine is linked for
    # (DISABLE_EXCEPTION_CATCHING=0 in its util/emscripten-javascriptify.py,
    # the way its SQLite driver is compiled); the other model,
    # -fwasm-exceptions, would not link into it.
    add_compile_options(-fexceptions)
    add_link_options(-fexceptions)
endif()

FetchContent_MakeAvailable(zxing)

if(NOT TARGET ZXing)
    message(FATAL_ERROR "zxing-cpp's build has no target 'ZXing': has its CMake changed at the pinned commit?")
endif()
# zxing-cpp is pinned to a known-good commit, so an upstream warning on a
# newer compiler must never fail this build (box2dxt's lesson with -Werror).
set_target_properties(ZXing PROPERTIES COMPILE_WARNING_AS_ERROR OFF)

# Signed overflow is DEFINED (wraps) in zxing-cpp's objects. Its readers mark
# "no bar here" with INT_MIN and then do arithmetic on the marker
# (Pattern.h's NormalizedPattern, reached from the PDF417 readers on a
# damaged picture: found by tests/fuzz_test.cpp under UBSan, 2026-11-20).
# The results are discarded, but the overflow itself is undefined behaviour
# an optimiser may build on; -fwrapv makes it ordinary two's-complement
# arithmetic in what ships, and is the reason the sanitizer lane does not
# stop there. MSVC has no such switch and does not assume the overflow away.
if(NOT MSVC)
    target_compile_options(ZXing PRIVATE -fwrapv)
endif()

# ---------------------------------------------------------------------------
# The web build: wasm32-emscripten. A browser loads no library, so for
# OXT-Beyond's web IDE the shim is linked INTO the engine, which keeps a table
# of the libraries compiled into it and finds "c:barcodext>bcx_..." there by
# name. What is built is a static archive, barcodext.a, holding ONE
# relocatable object: the shim and the members of zxing-cpp it uses, linked
# together (emcc -r), plus a table of the symbols the binding names:
#
#     const struct { const char *symbol; void *address; } *
#     barcodext_web_exports(void);       /* ends with { NULL, NULL } */
#
# The table is GENERATED from every `binds to "c:barcodext>NAME"` of
# src/barcodext.lcb, so it cannot drift from the binding, and compiled in ONE
# translation unit with src/barcode_shim.cpp (which it includes), so a bind
# with no shim function is a compile error, never a missing symbol found in a
# browser. This is box2dxt's mechanism, unchanged.
# ---------------------------------------------------------------------------
if(EMSCRIPTEN)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/barcodext.lcb" _bcx_lcb)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${CMAKE_CURRENT_SOURCE_DIR}/src/barcodext.lcb")
    string(REGEX MATCHALL "binds to \"c:barcodext>[A-Za-z_][A-Za-z0-9_]*" _bcx_binds "${_bcx_lcb}")
    set(_bcx_symbols "")
    foreach(_bind IN LISTS _bcx_binds)
        string(REGEX REPLACE ".*>" "" _symbol "${_bind}")
        list(APPEND _bcx_symbols "${_symbol}")
    endforeach()
    list(REMOVE_DUPLICATES _bcx_symbols)
    list(SORT _bcx_symbols)
    list(LENGTH _bcx_symbols _bcx_count)
    if(_bcx_count EQUAL 0)
        message(FATAL_ERROR "src/barcodext.lcb binds no c:barcodext> symbol: is the regular expression stale?")
    endif()
    set(_bcx_rows "")
    foreach(_symbol IN LISTS _bcx_symbols)
        string(APPEND _bcx_rows "\t{ \"${_symbol}\", (void *)${_symbol} },\n")
    endforeach()
    set(_bcx_exports_cpp "${CMAKE_CURRENT_BINARY_DIR}/barcodext_web_exports.cpp")
    file(CONFIGURE OUTPUT "${_bcx_exports_cpp}" @ONLY CONTENT
"/* GENERATED by CMakeLists.txt from src/barcodext.lcb: the shim, and the
 * @_bcx_count@ symbols the binding binds to, for OXT-Beyond's web engine. */
#include \"barcode_shim.cpp\"

extern \"C\" {

struct bcx_web_export { const char *symbol; void *address; };

static const struct bcx_web_export k_bcx_web_exports[] = {
@_bcx_rows@\t{ nullptr, nullptr },
};

BCX_API const struct bcx_web_export *barcodext_web_exports(void);
BCX_API const struct bcx_web_export *barcodext_web_exports(void)
{
\treturn k_bcx_web_exports;
}

} // extern \"C\"
")
    message(STATUS "barcodext web exports: ${_bcx_count} symbols from src/barcodext.lcb")

    # -g0 and the prefix maps keep the build folder's path out of the object,
    # so the same source and Emscripten give the same archive anywhere.
    add_library(barcodext_web_objects OBJECT "${_bcx_exports_cpp}")
    target_include_directories(barcodext_web_objects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_include_directories(barcodext_web_objects SYSTEM PRIVATE
        "${zxing_SOURCE_DIR}/core/src" "${zxing_BINARY_DIR}")
    target_compile_options(barcodext_web_objects PRIVATE
        -Os -g0 -Wall -Wextra
        "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=barcodext"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")
    add_dependencies(barcodext_web_objects ZXing)
    set(_bcx_web_object "${CMAKE_CURRENT_BINARY_DIR}/barcodext-web.o")
    set(_bcx_web_archive "${CMAKE_CURRENT_BINARY_DIR}/barcodext.a")
    add_custom_command(
        OUTPUT "${_bcx_web_archive}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${_bcx_web_object}" "${_bcx_web_archive}"
        COMMAND ${CMAKE_CXX_COMPILER} -r -o "${_bcx_web_object}"
                "$<TARGET_OBJECTS:barcodext_web_objects>" "$<TARGET_FILE:ZXing>"
        COMMAND ${CMAKE_AR} rcsD "${_bcx_web_archive}" "${_bcx_web_object}"
        DEPENDS barcodext_web_objects ZXing "$<TARGET_OBJECTS:barcodext_web_objects>"
        COMMAND_EXPAND_LISTS
        COMMENT "Linking barcodext.a for the web (shim + zxing-cpp, one object)"
        VERBATIM)
    add_custom_target(barcodext_web ALL DEPENDS "${_bcx_web_archive}")

    # The web tests: the same two programs, linked against the ARCHIVE and
    # run by node (ctest), so what is tested is the file that would ship.
    if(BARCODEXT_BUILD_TESTS)
        enable_testing()
        find_program(BARCODEXT_NODE node REQUIRED)
        foreach(_test smoke fuzz)
            add_executable(barcodext_${_test} tests/${_test}_test.cpp)
            add_dependencies(barcodext_${_test} barcodext_web)
            set_target_properties(barcodext_${_test} PROPERTIES SUFFIX ".js")
            target_link_libraries(barcodext_${_test} PRIVATE "${_bcx_web_archive}")
            target_link_options(barcodext_${_test} PRIVATE -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node
                                -sSTACK_SIZE=1048576)
            add_test(NAME ${_test} COMMAND "${BARCODEXT_NODE}" "$<TARGET_FILE:barcodext_${_test}>")
        endforeach()
    endif()

    if(BARCODEXT_PLACE_IN_SRC)
        set(_bcx_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/wasm32-emscripten")
        add_custom_command(TARGET barcodext_web POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_bcx_bundle_dir}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_bcx_web_archive}" "${_bcx_bundle_dir}/barcodext.a"
            COMMENT "Bundling barcodext.a -> src/code/wasm32-emscripten/"
            VERBATIM)
    endif()
    return()
endif()

# ---------------------------------------------------------------------------
# The shim + zxing-cpp, linked into a single shared library under its BARE
# name: barcodext.so (Linux, Android), barcodext.dylib (macOS), barcodext.dll
# (Windows). The bare name is the one the tree holds on every platform and,
# on Linux, the soname the engine's dlopen asks for. The LCB bind string
# "c:barcodext>..." resolves to it.
# ---------------------------------------------------------------------------
add_library(barcodext SHARED src/barcode_shim.cpp)
target_link_libraries(barcodext PRIVATE ZXing)
# zxing-cpp's headers are a third party's: -isystem keeps -Wall -Wextra about
# our own code (playbook section 9).
target_include_directories(barcodext SYSTEM PRIVATE
    "${zxing_SOURCE_DIR}/core/src" "${zxing_BINARY_DIR}")

set_target_properties(barcodext PROPERTIES
    CXX_VISIBILITY_PRESET hidden    # export only the BCX_API shim symbols
    VISIBILITY_INLINES_HIDDEN ON
    PREFIX ""
    OUTPUT_NAME "barcodext"
)

# Keep the shim warning-clean (these flags apply only to barcode_shim.cpp).
if(MSVC)
    target_compile_options(barcodext PRIVATE /W3 /EHsc /utf-8)
    target_compile_definitions(barcodext PRIVATE _CRT_SECURE_NO_WARNINGS NOMINMAX)
else()
    target_compile_options(barcodext PRIVATE -Wall -Wextra)
endif()

# Linux carries its C++ runtime inside the library (torrentxt's "dominant
# portability win"): the engine that loads it is C, so no other C++ runtime
# is in the process to disagree with, and a distribution's libstdc++ never
# has to be new enough. The version script below keeps that runtime private.
# Android's comes from the toolchain (ANDROID_STL=c++_static,
# tools/build-android.sh); macOS and Windows have their own rules. Not under
# the sanitizer, whose runtime interposes on the C++ one.
if(UNIX AND NOT APPLE AND NOT ANDROID AND NOT BARCODEXT_SANITIZE)
    target_link_options(barcodext PRIVATE -static-libstdc++ -static-libgcc)
endif()

# Export bcx_* and nothing else (src/barcodext.map says why). The map is the
# one source for GNU ld and, by the pattern below, for ld64 (which takes
# wildcards in an exported-symbols list). On Windows only BCX_API functions
# carry dllexport, so the DLL's table is the same list.
set(_bcx_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/barcodext.map")
if(APPLE)
    set(_bcx_exported "${CMAKE_CURRENT_BINARY_DIR}/barcodext.exported_symbols")
    file(WRITE "${_bcx_exported}" "_bcx_*\n")
    target_link_options(barcodext PRIVATE "-Wl,-exported_symbols_list,${_bcx_exported}")
elseif(UNIX)
    include(CheckLinkerFlag)
    check_linker_flag(CXX "-Wl,--version-script=${_bcx_version_script}" BCX_HAVE_VERSION_SCRIPT)
    if(BCX_HAVE_VERSION_SCRIPT)
        target_link_options(barcodext PRIVATE "-Wl,--version-script=${_bcx_version_script}")
        set_target_properties(barcodext PROPERTIES LINK_DEPENDS "${_bcx_version_script}")
    endif()
endif()

# ---------------------------------------------------------------------------
# The runtime tests. Both link the built library and call it through the same
# C entry points the binding uses.
#   smoke   every export: create, draw and read back every kind; refusals
#   fuzz    noise, damaged symbols and random calls; no crash, no leak
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBARCODEXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --output-on-failure
# ---------------------------------------------------------------------------
if(BARCODEXT_BUILD_TESTS)
    enable_testing()
    foreach(_test smoke fuzz)
        add_executable(barcodext_${_test} tests/${_test}_test.cpp)
        target_link_libraries(barcodext_${_test} PRIVATE barcodext)
        if(MSVC)
            target_compile_definitions(barcodext_${_test} PRIVATE _CRT_SECURE_NO_WARNINGS)
        endif()
        add_test(NAME ${_test} COMMAND barcodext_${_test})
    endforeach()
endif()
