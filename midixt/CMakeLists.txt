cmake_minimum_required(VERSION 3.22)
project(midixt LANGUAGES C CXX)

# ---------------------------------------------------------------------------
# midixt - realtime MIDI for OpenXTalk (OXT) and the xTalk family, also
# compatible with LiveCode 9.6.3+. The C shim (src/midi_shim.c) over RtMidi
# (MIT, fetched at a pinned commit) is built into ONE loadable library named
# "midixt":
#
#   midixt.so (Linux) / midixt.dylib (macOS) / midixt.dll (Windows)
#
# bundled inside the extension under src/code/<arch>-<platform>/, so the engine
# resolves the binding's "c:midixt>" foreign handlers through the
# revLibraryMapping. RtMidi picks the platform's MIDI service: ALSA on Linux
# (build needs libasound2-dev / alsa-lib-devel; the library loads the system's
# libasound.so.2), CoreMIDI on macOS, Windows MM on Windows. Android is not a
# target: RtMidi's Android backend needs API 29 and a JNI environment, and the
# suite's Android floor is API 21 (docs/building.md).
#
# For the web (emcmake, below) the same shim is built over src/midi_web.c, the
# browser's Web MIDI, into a static archive that OXT-Beyond's web engine links
# in: src/code/wasm32-emscripten/midixt.a.
#
# ShowControl's top-level CMakeLists.txt is this file's ancestor (its midi half).
#
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DMIDIXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --build-config Release --output-on-failure
# ---------------------------------------------------------------------------

option(MIDIXT_BUILD_TESTS "Build the C smoke and mock tests and the mock library" OFF)
option(MIDIXT_PLACE_IN_SRC
       "Web build only: copy midixt.a into src/code/wasm32-emscripten/ after building" ON)
set(MIDIXT_SANITIZE "" CACHE STRING "Sanitizer: '' or 'address' (ASan + UBSan, gcc or clang)")
# The shipped library must load on a machine that has nothing but the OS and the
# engine: the static MSVC CRT (a /MD build needs the VC++ redistributable, and
# for RtMidi's C++ also MSVCP140), and on Linux the static libstdc++/libgcc, so
# the .so does not demand the build host's GLIBCXX version. The version script
# keeps those runtime symbols LOCAL. Nothing the library allocates is freed by
# the engine (every buffer is caller-owned), so a private runtime is safe. A
# sanitizer build uses the shared runtime, whose operator new ASan intercepts.
option(MIDIXT_STATIC_RUNTIME "Link the C/C++ runtime statically into the shipped library" ON)
if(NOT MIDIXT_SANITIZE STREQUAL "")
    set(MIDIXT_STATIC_RUNTIME OFF)
endif()

# The web build (wasm32-emscripten, below) is a release archive: optimised
# unless a build type is given.
if(EMSCRIPTEN AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# The shared library links RtMidi's static objects into itself, so every
# object is position-independent. Not for the web build, whose archive is
# linked into the engine; nor does the web build hide anything (OXT-Beyond
# makes every symbol of the archive local but the table's and EM_JS's own).
if(NOT EMSCRIPTEN)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
    if(MIDIXT_STATIC_RUNTIME)
        set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    endif()

    # Hidden by default in every object, RtMidi's included: only MIDI_API
    # symbols leave the library (RtMidi's own classes are
    # visibility("default") under GCC whatever is defined, which is why the
    # version script below exists too).
    set(CMAKE_C_VISIBILITY_PRESET hidden)
    set(CMAKE_CXX_VISIBILITY_PRESET hidden)
    set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)
endif()

if(MIDIXT_SANITIZE STREQUAL "address")
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
endif()

# ---------------------------------------------------------------------------
# RtMidi 6.0.0, fetched as SOURCE only (SOURCE_SUBDIR names a folder that does
# not exist, CMake's documented way to say "do not add_subdirectory") and
# compiled below from its two files. Its own CMake is not run: it marks every
# class and its C API exported (RTMIDI_EXPORT), adds JACK whenever the build
# machine happens to have JACK's headers (a dependency on libjack.so that the
# release machines do not have), and adds -Werror to Debug builds. Pinned by
# commit, the 6.0.0 tag's.
# ---------------------------------------------------------------------------
set(MIDIXT_RTMIDI_COMMIT "1e5b49925aa60065db52de44c366d446a902547b")  # 6.0.0
include(FetchContent)
FetchContent_Declare(rtmidi
    GIT_REPOSITORY https://github.com/thestk/rtmidi.git
    GIT_TAG        ${MIDIXT_RTMIDI_COMMIT}
    SOURCE_SUBDIR  midixt-builds-the-sources-itself)
FetchContent_MakeAvailable(rtmidi)
set(_rtmidi "${rtmidi_SOURCE_DIR}")

# ---------------------------------------------------------------------------
# The web build: wasm32-emscripten. A browser loads no library, so for
# OXT-Beyond's web engine the shim is linked INTO the engine, which keeps a
# table of the libraries compiled into it and finds "c:midixt>midi_..." there
# by name (its engine/src/em-xtalk-web.cpp). What is built is a static
# archive, midixt.a, holding ONE relocatable object (emcc -r): the shim over
# src/midi_web.c, which is the part of RtMidi's C API the shim calls,
# implemented over the browser's Web MIDI (that file says why RtMidi's own
# Web MIDI backend is not used), and a table of the symbols the binding names:
#
#     const struct { const char *symbol; void *address; } *
#     midixt_web_exports(void);          /* ends with { NULL, NULL } */
#
# The table is GENERATED from every `binds to "c:midixt>NAME"` of src/midi.lcb,
# so it cannot drift from the binding, and compiled in ONE translation unit
# with src/midi_shim.c (which it includes), so a bind with no shim function is
# a compile error, never a missing symbol found in a browser. This is
# box2dxt's mechanism, unchanged. RtMidi is fetched for its header alone: the
# shim and src/midi_web.c compile against rtmidi_c.h, so every backend
# function has RtMidi's own signature, and none of RtMidi's code is in the
# archive.
# ---------------------------------------------------------------------------
if(EMSCRIPTEN)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/midi.lcb" _midi_lcb)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${CMAKE_CURRENT_SOURCE_DIR}/src/midi.lcb")
    string(REGEX MATCHALL "binds to \"c:midixt>[A-Za-z_][A-Za-z0-9_]*" _midi_binds "${_midi_lcb}")
    set(_midi_symbols "")
    foreach(_bind IN LISTS _midi_binds)
        string(REGEX REPLACE ".*>" "" _symbol "${_bind}")
        list(APPEND _midi_symbols "${_symbol}")
    endforeach()
    list(REMOVE_DUPLICATES _midi_symbols)
    list(SORT _midi_symbols)
    list(LENGTH _midi_symbols _midi_count)
    if(_midi_count EQUAL 0)
        message(FATAL_ERROR "src/midi.lcb binds no c:midixt> symbol: is the regular expression stale?")
    endif()
    set(_midi_rows "")
    foreach(_symbol IN LISTS _midi_symbols)
        string(APPEND _midi_rows "\t{ \"${_symbol}\", (void *)${_symbol} },\n")
    endforeach()
    set(_midi_exports_c "${CMAKE_CURRENT_BINARY_DIR}/midixt_web_exports.c")
    file(CONFIGURE OUTPUT "${_midi_exports_c}" @ONLY CONTENT
"/* GENERATED by CMakeLists.txt from src/midi.lcb: the shim, and the
 * @_midi_count@ symbols the binding binds to, for OXT-Beyond's web engine. */
#include \"midi_shim.c\"

struct midixt_web_export { const char *symbol; void *address; };

static const struct midixt_web_export k_midixt_web_exports[] = {
@_midi_rows@\t{ NULL, NULL },
};

MIDI_API const struct midixt_web_export *midixt_web_exports(void);
MIDI_API const struct midixt_web_export *midixt_web_exports(void)
{
\treturn k_midixt_web_exports;
}
")
    message(STATUS "midixt web exports: ${_midi_count} symbols from src/midi.lcb")

    # -g0 and the prefix maps keep the build folder's path out of the object,
    # so the same source and Emscripten give the same archive anywhere.
    add_library(midixt_web_objects OBJECT "${_midi_exports_c}" src/midi_web.c)
    target_include_directories(midixt_web_objects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_include_directories(midixt_web_objects SYSTEM PRIVATE "${_rtmidi}")
    set_target_properties(midixt_web_objects PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
    target_compile_options(midixt_web_objects PRIVATE
        -Os -g0 -Wall -Wextra -Werror=implicit-function-declaration
        "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=midixt"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build"
        "-ffile-prefix-map=${_rtmidi}=rtmidi")

    set(_midi_web_object "${CMAKE_CURRENT_BINARY_DIR}/midixt-web.o")
    set(_midi_web_archive "${CMAKE_CURRENT_BINARY_DIR}/midixt.a")
    add_custom_command(
        OUTPUT "${_midi_web_archive}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${_midi_web_object}" "${_midi_web_archive}"
        COMMAND ${CMAKE_C_COMPILER} -r -o "${_midi_web_object}"
                "$<TARGET_OBJECTS:midixt_web_objects>"
        COMMAND ${CMAKE_AR} rcsD "${_midi_web_archive}" "${_midi_web_object}"
        DEPENDS midixt_web_objects "$<TARGET_OBJECTS:midixt_web_objects>"
        COMMAND_EXPAND_LISTS
        COMMENT "Linking midixt.a for the web (the shim over Web MIDI, one object)"
        VERBATIM)
    add_custom_target(midixt_web ALL DEPENDS "${_midi_web_archive}")

    # The web tests: linked against the ARCHIVE and run by node (ctest), so
    # what is tested is the file that would ship. node has no Web MIDI, so
    # tests/web/fake-web-midi.js (--pre-js) stands in for the browser's: each
    # scene is one run of tests/midi_web_test.c, a fresh page, since a refusal
    # stands for the life of one. Asyncify lets the test wait for the
    # browser's answer (a promise) between two calls, as a script's timer does.
    if(MIDIXT_BUILD_TESTS)
        enable_testing()
        find_program(MIDIXT_NODE node REQUIRED)
        set(_midi_fake "${CMAKE_CURRENT_SOURCE_DIR}/tests/web/fake-web-midi.js")
        add_executable(midi_web_test tests/midi_web_test.c)
        add_dependencies(midi_web_test midixt_web)
        target_include_directories(midi_web_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
        set_target_properties(midi_web_test PROPERTIES SUFFIX ".js" C_STANDARD 17 C_STANDARD_REQUIRED ON
                              LINK_DEPENDS "${_midi_fake}")
        target_compile_options(midi_web_test PRIVATE -Wall -Wextra)
        target_link_libraries(midi_web_test PRIVATE "${_midi_web_archive}")
        # -sEXIT_RUNTIME=1: the test ends with exit(), which reaches node's
        # exit status only so (a slept main's return value never does), and
        # FAIL_REGULAR_EXPRESSION fails a scene on its printed FAIL lines
        # whatever the status says: before both, every failing scene passed.
        target_link_options(midi_web_test PRIVATE
            -sENVIRONMENT=node -sASYNCIFY -sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1
            "--pre-js=${_midi_fake}")
        foreach(_scene none refused framed pending granted)
            add_test(NAME midi_web_${_scene}
                     COMMAND "${MIDIXT_NODE}" "$<TARGET_FILE:midi_web_test>" ${_scene})
            set_tests_properties(midi_web_${_scene} PROPERTIES
                FAIL_REGULAR_EXPRESSION "FAIL  |, [1-9][0-9]* failed")
        endforeach()
    endif()

    if(MIDIXT_PLACE_IN_SRC)
        set(_midi_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/wasm32-emscripten")
        add_custom_command(TARGET midixt_web POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_midi_bundle_dir}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_midi_web_archive}" "${_midi_bundle_dir}/midixt.a"
            COMMENT "Bundling midixt.a -> src/code/wasm32-emscripten/"
            VERBATIM)
    endif()
    return()
endif()

find_package(Threads REQUIRED)

add_library(midixt_rtmidi STATIC "${_rtmidi}/RtMidi.cpp" "${_rtmidi}/rtmidi_c.cpp")
target_include_directories(midixt_rtmidi PUBLIC "${_rtmidi}")
set_target_properties(midixt_rtmidi PROPERTIES CXX_STANDARD 11 CXX_STANDARD_REQUIRED ON)
target_link_libraries(midixt_rtmidi PUBLIC Threads::Threads)
if(APPLE)
    target_compile_definitions(midixt_rtmidi PRIVATE __MACOSX_CORE__)
    target_link_libraries(midixt_rtmidi PUBLIC
        "-framework CoreMIDI" "-framework CoreAudio" "-framework CoreServices" "-framework CoreFoundation")
elseif(WIN32)
    target_compile_definitions(midixt_rtmidi PRIVATE __WINDOWS_MM__)
    target_link_libraries(midixt_rtmidi PUBLIC winmm)
elseif(ANDROID)
    message(FATAL_ERROR "midixt has no Android build: RtMidi's Android backend needs API 29 and JNI")
elseif(UNIX)
    find_package(ALSA REQUIRED)
    target_compile_definitions(midixt_rtmidi PRIVATE __LINUX_ALSA__)
    target_link_libraries(midixt_rtmidi PUBLIC ALSA::ALSA)
else()
    target_compile_definitions(midixt_rtmidi PRIVATE __RTMIDI_DUMMY__)
endif()
# RtMidi's warnings are not ours to fix and must never fail or bury this build.
if(MSVC)
    target_compile_options(midixt_rtmidi PRIVATE /w)
else()
    target_compile_options(midixt_rtmidi PRIVATE -w)
endif()

# ---------------------------------------------------------------------------
# The library: our shim + RtMidi, under its BARE name (no "lib"), which is the
# name the tree holds on every platform and, on Linux, the soname the engine's
# dlopen asks for.
# ---------------------------------------------------------------------------
add_library(midixt SHARED src/midi_shim.c)
target_include_directories(midixt PRIVATE src)
target_link_libraries(midixt PRIVATE midixt_rtmidi)
set_target_properties(midixt PROPERTIES
    C_STANDARD 17
    C_STANDARD_REQUIRED ON
    LINKER_LANGUAGE CXX
    OUTPUT_NAME "midixt"
    PREFIX "")
if(MIDIXT_STATIC_RUNTIME AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND NOT APPLE)
    target_link_options(midixt PRIVATE -static-libstdc++ -static-libgcc)
endif()

if(MSVC)
    target_compile_options(midixt PRIVATE /W3)
    target_compile_definitions(midixt PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(midixt PRIVATE -Wall -Wextra)
endif()

# Export midi_* and nothing else (the family's rule since enetxt's release run
# 10 leaked a vendored library's symbols: the script, not the default,
# decides). src/midixt.map is the one source for GNU ld and, by the pattern
# below, for ld64.
set(_midi_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/midixt.map")
if(APPLE)
    set(_midi_exported "${CMAKE_CURRENT_BINARY_DIR}/midixt.exported_symbols")
    file(WRITE "${_midi_exported}" "_midi_*\n")
    target_link_options(midixt PRIVATE "-Wl,-exported_symbols_list,${_midi_exported}")
elseif(UNIX)
    include(CheckLinkerFlag)
    check_linker_flag(C "-Wl,--version-script=${_midi_version_script}" MIDI_HAVE_VERSION_SCRIPT)
    if(MIDI_HAVE_VERSION_SCRIPT)
        target_link_options(midixt PRIVATE "-Wl,--version-script=${_midi_version_script}")
        set_target_properties(midixt PROPERTIES LINK_DEPENDS "${_midi_version_script}")
    endif()
endif()

# ---------------------------------------------------------------------------
# The tests.
#   midi_smoke       the REAL library (RtMidi over the OS's MIDI service),
#                    written to pass with or without a running service
#   midi_mock_smoke  the shim compiled against tests/mock/rtmidi_c.h, a
#                    controllable RtMidi double: the drain, the stash and every
#                    way RtMidi fails, deterministically, on every platform
#   midixt_mock      the MOCK library: the shim over the same double, built as
#                    "midixt" into <build>/mock/ (a drop-in for the shipped one,
#                    plus the midimock_* controls). The LCB and engine suites
#                    load it to run the whole stack with no MIDI service. NEVER
#                    packaged: tools/package-extension.py refuses a library
#                    that exports midimock_*.
# ---------------------------------------------------------------------------
if(MIDIXT_BUILD_TESTS)
    enable_testing()

    add_executable(midi_smoke tests/midi_smoke_test.c)
    target_include_directories(midi_smoke PRIVATE src)
    set_target_properties(midi_smoke PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
    target_link_libraries(midi_smoke PRIVATE midixt)
    if(MSVC)
        target_compile_definitions(midi_smoke PRIVATE _CRT_SECURE_NO_WARNINGS)
    endif()
    add_test(NAME midi_smoke COMMAND midi_smoke)

    # tests/mock FIRST so the shim's #include "rtmidi_c.h" resolves to the mock.
    add_executable(midi_mock_smoke src/midi_shim.c tests/mock/rtmidi_mock.c tests/midi_mock_smoke_test.c)
    target_include_directories(midi_mock_smoke PRIVATE tests/mock src)
    set_target_properties(midi_mock_smoke PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
    if(MSVC)
        target_compile_options(midi_mock_smoke PRIVATE /W3)
        target_compile_definitions(midi_mock_smoke PRIVATE _CRT_SECURE_NO_WARNINGS)
    else()
        target_compile_options(midi_mock_smoke PRIVATE -Wall -Wextra)
    endif()
    add_test(NAME midi_mock_smoke COMMAND midi_mock_smoke)

    add_library(midixt_mock SHARED src/midi_shim.c tests/mock/rtmidi_mock.c)
    target_include_directories(midixt_mock PRIVATE tests/mock src)
    set_target_properties(midixt_mock PROPERTIES
        C_STANDARD 17
        C_STANDARD_REQUIRED ON
        OUTPUT_NAME "midixt"
        PREFIX ""
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/mock"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/mock"
        ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/mock")
    # Multi-config generators (MSVC, Xcode) append /<Config>; pin every config to
    # the same folder so the runners find it without guessing.
    foreach(cfg Debug Release RelWithDebInfo MinSizeRel)
        string(TOUPPER ${cfg} CFG)
        set_target_properties(midixt_mock PROPERTIES
            LIBRARY_OUTPUT_DIRECTORY_${CFG} "${CMAKE_BINARY_DIR}/mock"
            RUNTIME_OUTPUT_DIRECTORY_${CFG} "${CMAKE_BINARY_DIR}/mock"
            ARCHIVE_OUTPUT_DIRECTORY_${CFG} "${CMAKE_BINARY_DIR}/mock")
    endforeach()
    if(MSVC)
        target_compile_options(midixt_mock PRIVATE /W3)
        target_compile_definitions(midixt_mock PRIVATE _CRT_SECURE_NO_WARNINGS)
    else()
        target_compile_options(midixt_mock PRIVATE -Wall -Wextra)
    endif()
endif()
