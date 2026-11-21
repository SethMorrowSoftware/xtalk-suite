cmake_minimum_required(VERSION 3.22)
project(audioxt LANGUAGES C)

# ---------------------------------------------------------------------------
# audioxt - miniaudio (David Reid's single-header audio library) for
# OpenXTalk (OXT) and the xTalk family, also compatible with LiveCode 9.6.3+.
# This builds the C shim (src/audio_shim.c), which compiles miniaudio into
# itself, as ONE loadable library named "audioxt", or for the web as a static
# archive (below). box3dxt/CMakeLists.txt is this file's ancestor.
# ---------------------------------------------------------------------------

option(AUDIOXT_BUILD_TESTS "Build the audioxt runtime tests" OFF)
option(AUDIOXT_PLACE_IN_SRC
       "Web build only: copy audioxt.a into src/code/wasm32-emscripten/ after building" ON)
set(AUDIOXT_SANITIZE "" CACHE STRING
    "Sanitizer: '' , 'address' (ASan + UBSan) or 'thread' (TSan); gcc or clang")
set(AUDIOXT_MINIAUDIO_DIR "" CACHE PATH
    "A folder that already holds the pinned miniaudio.h (no download is made)")

# The web build (wasm32-emscripten, below) is a release archive: optimised
# unless a build type is given.
if(EMSCRIPTEN AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Not for the web build, whose archive is linked into the engine:
# position-independent wasm reaches memory through __memory_base, which only
# a dynamically linked module needs.
if(NOT EMSCRIPTEN)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

# The Windows libraries carry the C runtime (static CRT, as curlxt's and
# box3dxt's do), so a PC without the Visual C++ Redistributable loads them
# and a package needs no runtime DLLs beside them.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(AUDIOXT_SANITIZE STREQUAL "address")
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
elseif(AUDIOXT_SANITIZE STREQUAL "thread")
    # miniaudio starts threads (a device thread, a job thread per engine),
    # so the data shared with them is checked for races too.
    add_compile_options(-fsanitize=thread -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=thread)
elseif(AUDIOXT_SANITIZE)
    message(FATAL_ERROR "AUDIOXT_SANITIZE is '${AUDIOXT_SANITIZE}': use '', 'address' or 'thread'")
endif()

# ---------------------------------------------------------------------------
# miniaudio, pinned. It is ONE header, so that one file is fetched, at an
# exact COMMIT of its repository (the tag 0.11.26) and held to a SHA-256: the
# build cannot quietly meet other source than the tests ran against. Bump the
# three values together, then rebuild every platform (suite rule 5) and
# re-run the tests: the shim is written against this revision's API.
# -DAUDIOXT_MINIAUDIO_DIR=<folder> builds from a copy already on disk (it is
# held to the same hash).
# ---------------------------------------------------------------------------
set(AUDIOXT_MINIAUDIO_VERSION "0.11.26")
set(AUDIOXT_MINIAUDIO_COMMIT  "877ea4a7c2601c7b0f2a44e83dfac42e6470fea6")
set(AUDIOXT_MINIAUDIO_SHA256  "6b376c7fbb1352ba1e0e432ab66069b335ea9405e45cb6c30b97ef0f3c9c3e0e")

if(AUDIOXT_MINIAUDIO_DIR)
    set(_aux_ma_dir "${AUDIOXT_MINIAUDIO_DIR}")
    if(NOT EXISTS "${_aux_ma_dir}/miniaudio.h")
        message(FATAL_ERROR "AUDIOXT_MINIAUDIO_DIR (${_aux_ma_dir}) holds no miniaudio.h")
    endif()
    file(SHA256 "${_aux_ma_dir}/miniaudio.h" _aux_ma_have)
    if(NOT _aux_ma_have STREQUAL AUDIOXT_MINIAUDIO_SHA256)
        message(FATAL_ERROR "${_aux_ma_dir}/miniaudio.h is not miniaudio ${AUDIOXT_MINIAUDIO_VERSION} "
                            "(SHA-256 ${_aux_ma_have}, pinned ${AUDIOXT_MINIAUDIO_SHA256})")
    endif()
else()
    set(_aux_ma_dir "${CMAKE_CURRENT_BINARY_DIR}/miniaudio-${AUDIOXT_MINIAUDIO_VERSION}")
    set(_aux_ma_have "")
    if(EXISTS "${_aux_ma_dir}/miniaudio.h")
        file(SHA256 "${_aux_ma_dir}/miniaudio.h" _aux_ma_have)
    endif()
    if(NOT _aux_ma_have STREQUAL AUDIOXT_MINIAUDIO_SHA256)
        file(DOWNLOAD
            "https://raw.githubusercontent.com/mackron/miniaudio/${AUDIOXT_MINIAUDIO_COMMIT}/miniaudio.h"
            "${_aux_ma_dir}/miniaudio.h"
            EXPECTED_HASH "SHA256=${AUDIOXT_MINIAUDIO_SHA256}"
            TLS_VERIFY ON
            STATUS _aux_ma_status)
        list(GET _aux_ma_status 0 _aux_ma_code)
        if(NOT _aux_ma_code EQUAL 0)
            file(REMOVE "${_aux_ma_dir}/miniaudio.h")
            message(FATAL_ERROR "could not fetch miniaudio.h: ${_aux_ma_status} "
                                "(-DAUDIOXT_MINIAUDIO_DIR=<folder> builds from a copy on disk)")
        endif()
    endif()
endif()
message(STATUS "audioxt: miniaudio ${AUDIOXT_MINIAUDIO_VERSION} from ${_aux_ma_dir}")

# ---------------------------------------------------------------------------
# The web build: wasm32-emscripten. A browser loads no library, so for
# OXT-Beyond's web engine the shim is linked INTO the engine, which keeps a
# table of the libraries compiled into it and finds "c:audioxt>aux_..." there
# by name. What is built is a static archive, audioxt.a, holding ONE
# relocatable object: the shim (with miniaudio inside it), plus a table of
# the symbols the binding names:
#
#     const struct { const char *symbol; void *address; } *
#     audioxt_web_exports(void);       /* ends with { NULL, NULL } */
#
# The table is GENERATED from every `binds to "c:audioxt>NAME"` of
# src/audioxt.lcb, so it cannot drift from the binding, and compiled in ONE
# translation unit with src/audio_shim.c (which it includes), so a bind with
# no shim function is a compile error, never a missing symbol found in a
# browser. This is box2dxt's mechanism, unchanged.
#
# miniaudio reaches the browser's Web Audio through JavaScript it carries
# inside itself (EM_ASM), which survives the relocatable link and needs no
# flag of the engine's: it uses a ScriptProcessorNode, on the main thread.
# (Its AudioWorklet path needs -sAUDIO_WORKLET and -sWASM_WORKERS on the
# ENGINE's link line, so it is not asked for here.)
# ---------------------------------------------------------------------------
if(EMSCRIPTEN)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/audioxt.lcb" _aux_lcb)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${CMAKE_CURRENT_SOURCE_DIR}/src/audioxt.lcb")
    string(REGEX MATCHALL "binds to \"c:audioxt>[A-Za-z_][A-Za-z0-9_]*" _aux_binds "${_aux_lcb}")
    set(_aux_symbols "")
    foreach(_bind IN LISTS _aux_binds)
        string(REGEX REPLACE ".*>" "" _symbol "${_bind}")
        list(APPEND _aux_symbols "${_symbol}")
    endforeach()
    list(REMOVE_DUPLICATES _aux_symbols)
    list(SORT _aux_symbols)
    list(LENGTH _aux_symbols _aux_count)
    if(_aux_count EQUAL 0)
        message(FATAL_ERROR "src/audioxt.lcb binds no c:audioxt> symbol: is the regular expression stale?")
    endif()
    set(_aux_rows "")
    foreach(_symbol IN LISTS _aux_symbols)
        string(APPEND _aux_rows "\t{ \"${_symbol}\", (void *)${_symbol} },\n")
    endforeach()
    set(_aux_exports_c "${CMAKE_CURRENT_BINARY_DIR}/audioxt_web_exports.c")
    file(CONFIGURE OUTPUT "${_aux_exports_c}" @ONLY CONTENT
"/* GENERATED by CMakeLists.txt from src/audioxt.lcb: the shim, and the
 * @_aux_count@ symbols the binding binds to, for OXT-Beyond's web engine. */
#include \"audio_shim.c\"

struct aux_web_export { const char *symbol; void *address; };

static const struct aux_web_export k_aux_web_exports[] = {
@_aux_rows@\t{ NULL, NULL },
};

LC_API const struct aux_web_export *audioxt_web_exports(void);
LC_API const struct aux_web_export *audioxt_web_exports(void)
{
\treturn k_aux_web_exports;
}
")
    message(STATUS "audioxt web exports: ${_aux_count} symbols from src/audioxt.lcb")

    # -g0 and the prefix maps keep the build folder's path out of the object,
    # so the same source and Emscripten give the same archive anywhere.
    add_library(audioxt_web_objects OBJECT "${_aux_exports_c}")
    target_include_directories(audioxt_web_objects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_include_directories(audioxt_web_objects SYSTEM PRIVATE "${_aux_ma_dir}")
    set_target_properties(audioxt_web_objects PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
    target_compile_options(audioxt_web_objects PRIVATE
        -Os -g0 -Wall -Wextra -Werror=implicit-function-declaration
        "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=audioxt"
        "-ffile-prefix-map=${_aux_ma_dir}=miniaudio"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")

    set(_aux_web_object "${CMAKE_CURRENT_BINARY_DIR}/audioxt-web.o")
    set(_aux_web_archive "${CMAKE_CURRENT_BINARY_DIR}/audioxt.a")
    add_custom_command(
        OUTPUT "${_aux_web_archive}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${_aux_web_object}" "${_aux_web_archive}"
        COMMAND ${CMAKE_C_COMPILER} -r -o "${_aux_web_object}"
                "$<TARGET_OBJECTS:audioxt_web_objects>"
        COMMAND ${CMAKE_AR} rcsD "${_aux_web_archive}" "${_aux_web_object}"
        DEPENDS audioxt_web_objects "$<TARGET_OBJECTS:audioxt_web_objects>"
        COMMAND_EXPAND_LISTS
        COMMENT "Linking audioxt.a for the web (shim + miniaudio, one object)"
        VERBATIM)
    add_custom_target(audioxt_web ALL DEPENDS "${_aux_web_archive}")

    # The web tests: tests/smoke_test.c and tests/fuzz_test.c, linked against
    # the ARCHIVE and run by node (ctest), so what is tested is the file that
    # would ship. Node has no Web Audio: these prove the mixer, the decoders
    # and every refusal; tests/web/ proves the device in a real browser.
    if(AUDIOXT_BUILD_TESTS)
        enable_testing()
        find_program(AUDIOXT_NODE node REQUIRED)
        foreach(_test smoke fuzz)
            add_executable(audioxt_${_test} tests/${_test}_test.c)
            add_dependencies(audioxt_${_test} audioxt_web)
            set_target_properties(audioxt_${_test} PROPERTIES SUFFIX ".js"
                                  C_STANDARD 17 C_STANDARD_REQUIRED ON)
            target_link_libraries(audioxt_${_test} PRIVATE "${_aux_web_archive}")
            target_link_options(audioxt_${_test} PRIVATE -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node)
            add_test(NAME ${_test} COMMAND "${AUDIOXT_NODE}" "$<TARGET_FILE:audioxt_${_test}>")
        endforeach()

        # The page tests/web/run-web-test.mjs opens in a browser: the archive
        # behind a few exported calls, for a real Web Audio device.
        add_executable(audioxt_page tests/web/page.c)
        add_dependencies(audioxt_page audioxt_web)
        set_target_properties(audioxt_page PROPERTIES SUFFIX ".js"
                              C_STANDARD 17 C_STANDARD_REQUIRED ON)
        target_link_libraries(audioxt_page PRIVATE "${_aux_web_archive}")
        target_link_options(audioxt_page PRIVATE -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=web
                            -sEXPORTED_RUNTIME_METHODS=ccall)
    endif()

    if(AUDIOXT_PLACE_IN_SRC)
        set(_aux_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/wasm32-emscripten")
        add_custom_command(TARGET audioxt_web POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_aux_bundle_dir}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_aux_web_archive}" "${_aux_bundle_dir}/audioxt.a"
            COMMENT "Bundling audioxt.a -> src/code/wasm32-emscripten/"
            VERBATIM)
    endif()
    return()
endif()

# ---------------------------------------------------------------------------
# The shim with miniaudio inside it, as a single shared library under its
# BARE name: audioxt.so (Linux, Android), audioxt.dylib (macOS), audioxt.dll
# (Windows). The bare name is the one the tree holds on every platform and,
# on Linux, the soname the engine's dlopen asks for. The LCB bind string
# "c:audioxt>..." resolves to it.
# ---------------------------------------------------------------------------
add_library(audioxt SHARED src/audio_shim.c)
# SYSTEM: miniaudio is pinned, so a warning of its own on a newer compiler
# must never fail or drown this build; the flags below stay about the shim.
target_include_directories(audioxt SYSTEM PRIVATE "${_aux_ma_dir}")

# What miniaudio needs of the system, and no audio library among it: on
# Linux it finds PulseAudio and ALSA at RUN time (dlopen, hence libdl), on
# macOS Core Audio the same way, on Android AAudio and OpenSL ES, and on
# Windows it loads ole32 for WASAPI. So the library links on a machine with
# no audio headers and loads on one with no sound card. Threads and libm are
# named where they are separate libraries (glibc before 2.34, which the
# release lanes build at; box3dxt's lesson with libpthread).
if(NOT MSVC)
    set(THREADS_PREFER_PTHREAD_FLAG ON)
    find_package(Threads REQUIRED)
    target_link_libraries(audioxt PRIVATE Threads::Threads ${CMAKE_DL_LIBS})
    if(NOT APPLE)
        target_link_libraries(audioxt PRIVATE m)
    endif()
endif()

set_target_properties(audioxt PROPERTIES
    C_STANDARD 17
    C_STANDARD_REQUIRED ON
    C_VISIBILITY_PRESET hidden      # export only the LC_API shim symbols
    PREFIX ""
    OUTPUT_NAME "audioxt"
)

if(MSVC)
    target_compile_options(audioxt PRIVATE /W3)
    target_compile_definitions(audioxt PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(audioxt PRIVATE -Wall -Wextra)
endif()

# Export aux_* and nothing else: the script, not the default, decides (the
# family's rule since enetxt's release run 10). src/audioxt.map is the one
# source for GNU ld and, by the pattern below, for ld64.
set(_aux_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/audioxt.map")
if(APPLE)
    set(_aux_exported "${CMAKE_CURRENT_BINARY_DIR}/audioxt.exported_symbols")
    file(WRITE "${_aux_exported}" "_aux_*\n")
    target_link_options(audioxt PRIVATE "-Wl,-exported_symbols_list,${_aux_exported}")
elseif(UNIX)
    include(CheckLinkerFlag)
    check_linker_flag(C "-Wl,--version-script=${_aux_version_script}" AUX_HAVE_VERSION_SCRIPT)
    if(AUX_HAVE_VERSION_SCRIPT)
        target_link_options(audioxt PRIVATE "-Wl,--version-script=${_aux_version_script}")
        set_target_properties(audioxt PROPERTIES LINK_DEPENDS "${_aux_version_script}")
    endif()
endif()

# ---------------------------------------------------------------------------
# The runtime tests. Both are clients of the built library, as the engine is.
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DAUDIOXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --output-on-failure
# ---------------------------------------------------------------------------
if(AUDIOXT_BUILD_TESTS)
    enable_testing()
    foreach(_test smoke fuzz)
        add_executable(audioxt_${_test} tests/${_test}_test.c)
        set_target_properties(audioxt_${_test} PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
        target_link_libraries(audioxt_${_test} PRIVATE audioxt)
        if(MSVC)
            target_compile_definitions(audioxt_${_test} PRIVATE _CRT_SECURE_NO_WARNINGS)
        else()
            target_link_libraries(audioxt_${_test} PRIVATE m)
        endif()
        add_test(NAME ${_test} COMMAND audioxt_${_test})
    endforeach()
endif()
