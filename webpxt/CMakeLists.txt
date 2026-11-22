cmake_minimum_required(VERSION 3.22)
project(webpxt LANGUAGES C)

# ---------------------------------------------------------------------------
# webpxt - libwebp (Google's WebP image codec) for OpenXTalk (OXT) and the
# xTalk family, also compatible with LiveCode 9.6.3+. This builds the C shim
# (src/webp_shim.c) and libwebp into ONE loadable library named "webpxt", or
# for the web into a static archive (below). box3dxt/CMakeLists.txt is this
# file's ancestor.
# ---------------------------------------------------------------------------

option(WEBPXT_BUILD_TESTS "Build the webpxt runtime tests" OFF)
option(WEBPXT_PLACE_IN_SRC
       "Web build only: copy webpxt.a into src/code/wasm32-emscripten/ after building" ON)
set(WEBPXT_SANITIZE "" CACHE STRING "Sanitizer: '' or 'address' (ASan + UBSan, gcc or clang)")
set(WEBPXT_TEST_RPATH "" CACHE PATH
    "Set by the universal macOS build for its slices: the folder the tests load webpxt from")

# The web build (wasm32-emscripten, below) is a release archive: optimised
# unless a build type is given.
if(EMSCRIPTEN AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# libwebp builds as static libraries that are linked into our shared library,
# so every object must be position-independent (box2dxt's lesson: the
# manylinux toolchain does not default to PIE). Not for the web build, whose
# archive is linked into the engine.
if(NOT EMSCRIPTEN)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

# The Windows libraries carry the C runtime (static CRT, as curlxt's do), so a
# PC without the Visual C++ Redistributable loads them.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(WEBPXT_SANITIZE STREQUAL "address")
    # Applies to libwebp too (the options precede its targets): a bad read
    # inside the codec on a damaged file is exactly what the lane is for.
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
endif()

# ---------------------------------------------------------------------------
# Fetch libwebp, pinned to the COMMIT of its v1.6.0 tag (a tag can be moved; a
# commit id cannot). Bump WEBPXT_LIBWEBP_COMMIT to update, then rebuild every
# platform (suite rule 5) and re-run the tests. The licence was read at this
# commit: COPYING (BSD-3-Clause) and PATENTS, both carried in LICENSE.
# -DFETCHCONTENT_SOURCE_DIR_LIBWEBP=<checkout> builds from a local copy with
# no network.
# ---------------------------------------------------------------------------
set(WEBPXT_LIBWEBP_VERSION "1.6.0")
set(WEBPXT_LIBWEBP_COMMIT "4fa21912338357f89e4fd51cf2368325b59e9bd9")
include(FetchContent)
# ---------------------------------------------------------------------------
# A universal macOS library is built one slice at a time, then joined.
#
# libwebp's CMake decides at CONFIGURE time which SIMD files to compile, by
# test-compiling its own dsp.h. With two architectures on one command line
# the SSE2 probe fails for the arm64 half, so libwebp drops its SSE2 files
# and adds -mno-sse2 to every file, and the x86_64 half then cannot return a
# double ("SSE2 register return with SSE2 disabled": the first macos-universal
# run, 2026-11-20). One configure cannot be right for both halves.
#
# So with more than one entry in CMAKE_OSX_ARCHITECTURES this file configures
# ITSELF once per architecture (each a plain single-architecture build, with
# that architecture's SIMD files) and lipo joins the libraries and the test
# programs in this build folder, under the names every other build uses:
# webpxt.dylib, webpxt_smoke, webpxt_fuzz, and the same two ctest names. The
# joined tests load the joined library, so `arch -x86_64 ./webpxt_smoke` runs
# the Intel half of both.
# ---------------------------------------------------------------------------
list(LENGTH CMAKE_OSX_ARCHITECTURES _wpx_arch_count)
if(APPLE AND _wpx_arch_count GREATER 1)
    # Fetch once, for both slices (a SOURCE_SUBDIR that does not exist
    # populates the checkout without adding libwebp's targets here).
    FetchContent_Declare(
        libwebp
        GIT_REPOSITORY https://github.com/webmproject/libwebp.git
        GIT_TAG        ${WEBPXT_LIBWEBP_COMMIT}
        SOURCE_SUBDIR  webpxt-fetch-only
    )
    FetchContent_MakeAvailable(libwebp)

    include(ExternalProject)
    set(_wpx_slice_args
        "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
        "-DWEBPXT_BUILD_TESTS=${WEBPXT_BUILD_TESTS}"
        "-DWEBPXT_SANITIZE=${WEBPXT_SANITIZE}"
        "-DFETCHCONTENT_SOURCE_DIR_LIBWEBP=${libwebp_SOURCE_DIR}"
        "-DWEBPXT_TEST_RPATH=${CMAKE_CURRENT_BINARY_DIR}")
    if(CMAKE_OSX_DEPLOYMENT_TARGET)
        list(APPEND _wpx_slice_args "-DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}")
    endif()
    set(_wpx_joined webpxt.dylib)
    if(WEBPXT_BUILD_TESTS)
        list(APPEND _wpx_joined webpxt_smoke webpxt_fuzz)
    endif()
    set(_wpx_slice_targets)
    foreach(_arch IN LISTS CMAKE_OSX_ARCHITECTURES)
        ExternalProject_Add(webpxt_slice_${_arch}
            SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
            BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/slice-${_arch}"
            CMAKE_ARGS ${_wpx_slice_args} "-DCMAKE_OSX_ARCHITECTURES=${_arch}"
            INSTALL_COMMAND ""
            BUILD_ALWAYS ON)
        list(APPEND _wpx_slice_targets webpxt_slice_${_arch})
    endforeach()
    set(_wpx_lipo_commands)
    foreach(_file IN LISTS _wpx_joined)
        set(_wpx_inputs)
        foreach(_arch IN LISTS CMAKE_OSX_ARCHITECTURES)
            list(APPEND _wpx_inputs "${CMAKE_CURRENT_BINARY_DIR}/slice-${_arch}/${_file}")
        endforeach()
        list(APPEND _wpx_lipo_commands
             COMMAND lipo -create ${_wpx_inputs} -output "${CMAKE_CURRENT_BINARY_DIR}/${_file}")
    endforeach()
    add_custom_target(webpxt_universal ALL
        ${_wpx_lipo_commands}
        COMMENT "Joining the slices: ${_wpx_joined}"
        VERBATIM)
    add_dependencies(webpxt_universal ${_wpx_slice_targets})
    if(WEBPXT_BUILD_TESTS)
        enable_testing()
        add_test(NAME smoke COMMAND "${CMAKE_CURRENT_BINARY_DIR}/webpxt_smoke")
        add_test(NAME fuzz COMMAND "${CMAKE_CURRENT_BINARY_DIR}/webpxt_fuzz")
    endif()
    return()
endif()

FetchContent_Declare(
    libwebp
    GIT_REPOSITORY https://github.com/webmproject/libwebp.git
    GIT_TAG        ${WEBPXT_LIBWEBP_COMMIT}
)

# The libraries alone: no command-line tool, no viewer, nothing that looks
# for libpng, libjpeg, giflib or SDL on the build machine.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WEBP_LINK_STATIC ON CACHE BOOL "" FORCE)
set(WEBP_BUILD_ANIM_UTILS OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_CWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_DWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_GIF2WEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_IMG2WEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_VWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_WEBPINFO OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_WEBPMUX OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_EXTRAS OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_LIBWEBPMUX ON CACHE BOOL "" FORCE)
# No worker threads: nothing in this library leaves the caller's thread
# (suite rule 1), and it needs no thread library on any platform.
set(WEBP_USE_THREAD OFF CACHE BOOL "" FORCE)

# The web archive must be the same bytes wherever it is built: no debug
# info, and the build folder's path (where libwebp is fetched to) mapped
# away. Set before libwebp's targets exist, so it reaches them.
if(EMSCRIPTEN)
    add_compile_options(-g0 "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build")
endif()

FetchContent_MakeAvailable(libwebp)

# libwebp is pinned to a known-good commit, so an upstream warning on a newer
# compiler must never fail this build (box2dxt's lesson with -Werror).
set(_wpx_webp_targets webp webpdemux libwebpmux sharpyuv)
foreach(_target IN LISTS _wpx_webp_targets webpdecode webpdspdecode webputilsdecode
                         webpencode webpdsp webputils)
    if(TARGET ${_target})
        set_target_properties(${_target} PROPERTIES COMPILE_WARNING_AS_ERROR OFF)
    endif()
endforeach()
foreach(_target IN LISTS _wpx_webp_targets)
    if(NOT TARGET ${_target})
        message(FATAL_ERROR "libwebp's build has no target '${_target}': has its CMake changed at the pinned commit?")
    endif()
endforeach()

# ---------------------------------------------------------------------------
# The web build: wasm32-emscripten. A browser loads no library, so for
# OXT-Beyond's web IDE the shim is linked INTO the engine, which keeps a table
# of the libraries compiled into it and finds "c:webpxt>wpx_..." there by
# name. What is built is a static archive, webpxt.a, holding ONE relocatable
# object: the shim and the members of libwebp it uses, linked together
# (emcc -r), plus a table of the symbols the binding names:
#
#     const struct { const char *symbol; void *address; } *
#     webpxt_web_exports(void);       /* ends with { NULL, NULL } */
#
# The table is GENERATED from every `binds to "c:webpxt>NAME"` of
# src/webpxt.lcb, so it cannot drift from the binding, and compiled in ONE
# translation unit with src/webp_shim.c (which it includes), so a bind with
# no shim function is a compile error, never a missing symbol found in a
# browser. This is box2dxt's mechanism, unchanged.
# ---------------------------------------------------------------------------
if(EMSCRIPTEN)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/webpxt.lcb" _wpx_lcb)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${CMAKE_CURRENT_SOURCE_DIR}/src/webpxt.lcb")
    string(REGEX MATCHALL "binds to \"c:webpxt>[A-Za-z_][A-Za-z0-9_]*" _wpx_binds "${_wpx_lcb}")
    set(_wpx_symbols "")
    foreach(_bind IN LISTS _wpx_binds)
        string(REGEX REPLACE ".*>" "" _symbol "${_bind}")
        list(APPEND _wpx_symbols "${_symbol}")
    endforeach()
    list(REMOVE_DUPLICATES _wpx_symbols)
    list(SORT _wpx_symbols)
    list(LENGTH _wpx_symbols _wpx_count)
    if(_wpx_count EQUAL 0)
        message(FATAL_ERROR "src/webpxt.lcb binds no c:webpxt> symbol: is the regular expression stale?")
    endif()
    set(_wpx_rows "")
    foreach(_symbol IN LISTS _wpx_symbols)
        string(APPEND _wpx_rows "\t{ \"${_symbol}\", (void *)${_symbol} },\n")
    endforeach()
    set(_wpx_exports_c "${CMAKE_CURRENT_BINARY_DIR}/webpxt_web_exports.c")
    file(CONFIGURE OUTPUT "${_wpx_exports_c}" @ONLY CONTENT
"/* GENERATED by CMakeLists.txt from src/webpxt.lcb: the shim, and the
 * @_wpx_count@ symbols the binding binds to, for OXT-Beyond's web engine. */
#include \"webp_shim.c\"

struct wpx_web_export { const char *symbol; void *address; };

static const struct wpx_web_export k_wpx_web_exports[] = {
@_wpx_rows@\t{ NULL, NULL },
};

WPX_API const struct wpx_web_export *webpxt_web_exports(void);
WPX_API const struct wpx_web_export *webpxt_web_exports(void)
{
\treturn k_wpx_web_exports;
}
")
    message(STATUS "webpxt web exports: ${_wpx_count} symbols from src/webpxt.lcb")

    # -g0 and the prefix maps keep the build folder's path out of the object,
    # so the same source and Emscripten give the same archive anywhere.
    add_library(webpxt_web_objects OBJECT "${_wpx_exports_c}")
    target_include_directories(webpxt_web_objects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_include_directories(webpxt_web_objects SYSTEM PRIVATE "${libwebp_SOURCE_DIR}/src")
    set_target_properties(webpxt_web_objects PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
    target_compile_options(webpxt_web_objects PRIVATE
        -Os -g0 -Wall -Wextra -Werror=implicit-function-declaration
        "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=webpxt"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")
    set(_wpx_web_object "${CMAKE_CURRENT_BINARY_DIR}/webpxt-web.o")
    set(_wpx_web_archive "${CMAKE_CURRENT_BINARY_DIR}/webpxt.a")
    add_custom_command(
        OUTPUT "${_wpx_web_archive}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${_wpx_web_object}" "${_wpx_web_archive}"
        COMMAND ${CMAKE_C_COMPILER} -r -o "${_wpx_web_object}"
                "$<TARGET_OBJECTS:webpxt_web_objects>"
                "$<TARGET_FILE:libwebpmux>" "$<TARGET_FILE:webpdemux>"
                "$<TARGET_FILE:webp>" "$<TARGET_FILE:sharpyuv>"
        COMMAND ${CMAKE_AR} rcsD "${_wpx_web_archive}" "${_wpx_web_object}"
        DEPENDS webpxt_web_objects ${_wpx_webp_targets} "$<TARGET_OBJECTS:webpxt_web_objects>"
        COMMAND_EXPAND_LISTS
        COMMENT "Linking webpxt.a for the web (shim + libwebp, one object)"
        VERBATIM)
    add_custom_target(webpxt_web ALL DEPENDS "${_wpx_web_archive}")

    # The web tests: the same two programs, linked against the ARCHIVE and
    # run by node (ctest), so what is tested is the file that would ship.
    if(WEBPXT_BUILD_TESTS)
        enable_testing()
        find_program(WEBPXT_NODE node REQUIRED)
        foreach(_test smoke fuzz)
            add_executable(webpxt_${_test} tests/${_test}_test.c)
            add_dependencies(webpxt_${_test} webpxt_web)
            set_target_properties(webpxt_${_test} PROPERTIES SUFFIX ".js"
                                  C_STANDARD 11 C_STANDARD_REQUIRED ON)
            target_link_libraries(webpxt_${_test} PRIVATE "${_wpx_web_archive}")
            target_link_options(webpxt_${_test} PRIVATE -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node
                                -sSTACK_SIZE=1048576)
            add_test(NAME ${_test} COMMAND "${WEBPXT_NODE}" "$<TARGET_FILE:webpxt_${_test}>")
        endforeach()
    endif()

    if(WEBPXT_PLACE_IN_SRC)
        set(_wpx_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/wasm32-emscripten")
        add_custom_command(TARGET webpxt_web POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_wpx_bundle_dir}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_wpx_web_archive}" "${_wpx_bundle_dir}/webpxt.a"
            COMMENT "Bundling webpxt.a -> src/code/wasm32-emscripten/"
            VERBATIM)
    endif()
    return()
endif()

# ---------------------------------------------------------------------------
# The shim + libwebp, linked into a single shared library under its BARE name:
# webpxt.so (Linux, Android), webpxt.dylib (macOS), webpxt.dll (Windows). The
# bare name is the one the tree holds on every platform and, on Linux, the
# soname the engine's dlopen asks for. The LCB bind string "c:webpxt>..."
# resolves to it.
# ---------------------------------------------------------------------------
add_library(webpxt SHARED src/webp_shim.c)
# libwebpmux (the animation writer) and webpdemux (the animation reader) sit
# on webp, which sits on sharpyuv; a static link names them in that order.
target_link_libraries(webpxt PRIVATE libwebpmux webpdemux webp sharpyuv)
# libwebp's headers are a third party's: -isystem keeps -Wall -Wextra about
# our own code (playbook section 9).
target_include_directories(webpxt SYSTEM PRIVATE "${libwebp_SOURCE_DIR}/src")

set_target_properties(webpxt PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_VISIBILITY_PRESET hidden      # export only the WPX_API shim symbols
    PREFIX ""
    OUTPUT_NAME "webpxt"
)

# Keep the shim warning-clean (these flags apply only to webp_shim.c).
if(MSVC)
    target_compile_options(webpxt PRIVATE /W3)
    target_compile_definitions(webpxt PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(webpxt PRIVATE -Wall -Wextra)
    # libwebp's dsp code calls libm (pow, log) and glibc before 2.34 keeps
    # those apart from libc.
    if(NOT APPLE)
        target_link_libraries(webpxt PRIVATE m)
    endif()
endif()

# Export wpx_* and nothing else (src/webpxt.map says why). The map is the one
# source for GNU ld and, by the pattern below, for ld64 (which takes wildcards
# in an exported-symbols list). On Windows only WPX_API functions carry
# dllexport, so the DLL's table is the same list.
set(_wpx_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/webpxt.map")
if(APPLE)
    set(_wpx_exported "${CMAKE_CURRENT_BINARY_DIR}/webpxt.exported_symbols")
    file(WRITE "${_wpx_exported}" "_wpx_*\n")
    target_link_options(webpxt PRIVATE "-Wl,-exported_symbols_list,${_wpx_exported}")
elseif(UNIX)
    include(CheckLinkerFlag)
    check_linker_flag(C "-Wl,--version-script=${_wpx_version_script}" WPX_HAVE_VERSION_SCRIPT)
    if(WPX_HAVE_VERSION_SCRIPT)
        target_link_options(webpxt PRIVATE "-Wl,--version-script=${_wpx_version_script}")
        set_target_properties(webpxt PROPERTIES LINK_DEPENDS "${_wpx_version_script}")
    endif()
endif()

# ---------------------------------------------------------------------------
# The runtime tests. Both link the built library and call it through the same
# C entry points the binding uses.
#   smoke   every export: round trips, sizes, animations, refusals, handles
#   fuzz    damaged files and random calls; must end without a crash or leak
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DWEBPXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --output-on-failure
# ---------------------------------------------------------------------------
if(WEBPXT_BUILD_TESTS)
    enable_testing()
    foreach(_test smoke fuzz)
        add_executable(webpxt_${_test} tests/${_test}_test.c)
        set_target_properties(webpxt_${_test} PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
        target_link_libraries(webpxt_${_test} PRIVATE webpxt)
        if(MSVC)
            target_compile_definitions(webpxt_${_test} PRIVATE _CRT_SECURE_NO_WARNINGS)
        else()
            target_link_libraries(webpxt_${_test} PRIVATE m)
        endif()
        # A slice of a universal macOS build (above): the joined test must
        # load the JOINED library beside it, not this slice's own.
        if(WEBPXT_TEST_RPATH)
            set_target_properties(webpxt_${_test} PROPERTIES SKIP_BUILD_RPATH ON)
            target_link_options(webpxt_${_test} PRIVATE "-Wl,-rpath,${WEBPXT_TEST_RPATH}")
        endif()
        add_test(NAME ${_test} COMMAND webpxt_${_test})
    endforeach()
endif()
