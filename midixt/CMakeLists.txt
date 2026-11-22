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
# ShowControl's top-level CMakeLists.txt is this file's ancestor (its midi half).
#
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DMIDIXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --build-config Release --output-on-failure
# ---------------------------------------------------------------------------

option(MIDIXT_BUILD_TESTS "Build the C smoke and mock tests and the mock library" OFF)
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

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(MIDIXT_STATIC_RUNTIME)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# Hidden by default in every object, RtMidi's included: only MIDI_API symbols
# leave the library (RtMidi's own classes are visibility("default") under GCC
# whatever is defined, which is why the version script below exists too).
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

if(MIDIXT_SANITIZE STREQUAL "address")
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
endif()

find_package(Threads REQUIRED)

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
