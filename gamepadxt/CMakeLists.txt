cmake_minimum_required(VERSION 3.22)
project(gamepadxt LANGUAGES C)

# ---------------------------------------------------------------------------
# gamepadxt - game controllers for OpenXTalk (OXT) and the xTalk family, also
# compatible with LiveCode 9.6.3+, through SDL3's gamepad subsystem. This
# builds the C shim (src/gamepad_shim.c) and a CUT-DOWN SDL3 into ONE loadable
# library named "gamepadxt", or for the web into a static archive (below).
# box3dxt/CMakeLists.txt is this file's ancestor.
# ---------------------------------------------------------------------------

option(GAMEPADXT_BUILD_TESTS "Build the gamepadxt runtime tests" OFF)
option(GAMEPADXT_PLACE_IN_SRC
       "Web build only: copy gamepadxt.a into src/code/wasm32-emscripten/ after building" ON)
option(GAMEPADXT_ALLOW_NO_UDEV
       "Linux only: build even when libudev's header and library are missing (no HIDAPI drivers, slower hot-plug)" OFF)
set(GAMEPADXT_SANITIZE "" CACHE STRING "Sanitizer: '' or 'address' (ASan + UBSan, gcc or clang)")

# The web build (wasm32-emscripten, below) is a release archive: optimised
# unless a build type is given.
if(EMSCRIPTEN AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# SDL builds as a static library that is linked into our shared library, so
# every SDL object must be position-independent (box2dxt's lesson: the
# manylinux toolchain does not default to PIE). Not for the web build, whose
# archive is linked into the engine.
if(NOT EMSCRIPTEN)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

# The Windows libraries carry the C runtime (static CRT, as curlxt's and
# box3dxt's do), so a PC without the Visual C++ Redistributable loads them.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(GAMEPADXT_SANITIZE STREQUAL "address")
    # Applies to SDL too (the options precede its targets), so a bad read
    # inside SDL that the shim caused is reported, not just the shim's.
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
endif()

# ---------------------------------------------------------------------------
# Linux: libudev, found at BUILD time and loaded at RUN time. SDL uses it for
# two things: hot-plug without scanning /dev/input, and its HIDAPI drivers
# (the ones that know a Switch Pro pad's rumble or a DualSense's light). SDL's
# own CMake quietly builds without either when the header or the library is
# missing, and the library that results still loads and still sees an Xbox
# pad: a difference nobody would notice until a user's PlayStation pad had no
# light. So a Linux build without libudev is an ERROR here, unless asked for.
# The library is dlopen'd by its soname at run time; it is never a link-time
# dependency, and a system without it falls back to scanning.
# ---------------------------------------------------------------------------
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND NOT GAMEPADXT_ALLOW_NO_UDEV)
    include(CheckIncludeFile)
    check_include_file("libudev.h" GAMEPADXT_HAVE_LIBUDEV_H)
    find_library(GAMEPADXT_UDEV_LIBRARY NAMES udev)
    if(NOT GAMEPADXT_HAVE_LIBUDEV_H OR NOT GAMEPADXT_UDEV_LIBRARY)
        message(FATAL_ERROR
            "gamepadxt: libudev's header and library were not found (Debian/Ubuntu: libudev-dev; "
            "RHEL/manylinux: systemd-devel). Without them SDL builds with no HIDAPI drivers. "
            "Install it, or pass -DGAMEPADXT_ALLOW_NO_UDEV=ON to build that lesser library on purpose.")
    endif()
endif()

# ---------------------------------------------------------------------------
# Fetch SDL3, pinned to the COMMIT of a release tag (a commit id names the
# exact tree; a tag can be moved). Bump GAMEPADXT_SDL_COMMIT and
# GAMEPADXT_SDL_VERSION together to update, then rebuild every platform (suite
# rule 5) and re-run the tests: tests/smoke_test.c asserts the version the
# library reports. -DFETCHCONTENT_SOURCE_DIR_SDL3=<checkout> builds from a
# local copy with no network.
# ---------------------------------------------------------------------------
set(GAMEPADXT_SDL_VERSION "3.4.20")
set(GAMEPADXT_SDL_COMMIT "f00dc919ca35b9756316e86c4777392de442f9b2")   # release-3.4.20
include(FetchContent)
FetchContent_Declare(
    SDL3
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG        ${GAMEPADXT_SDL_COMMIT}
)

# SDL, cut down to what reads a game controller. Everything named OFF here is
# a subsystem this library never initialises; compiling it out is what keeps
# the library small and keeps X11, Wayland, ALSA, D-Bus and the rest out of
# its dependencies. What stays: joystick (the gamepad API is part of it),
# HIDAPI (the vendor drivers), haptic (rumble on some Linux and Windows
# pads), and SDL's own events, threads and timers.
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL_UNINSTALL OFF CACHE BOOL "" FORCE)
foreach(_gpx_off AUDIO VIDEO GPU RENDER CAMERA SENSOR POWER DIALOG TRAY
                 DBUS IBUS LIBURING HIDAPI_LIBUSB OFFSCREEN)
    set(SDL_${_gpx_off} OFF CACHE BOOL "" FORCE)
endforeach()
foreach(_gpx_on JOYSTICK HAPTIC HIDAPI HIDAPI_JOYSTICK VIRTUAL_JOYSTICK)
    set(SDL_${_gpx_on} ON CACHE BOOL "" FORCE)
endforeach()
# With no video driver SDL's CMake stops a Unix build ("SDL could not find
# X11 or Wayland"); this is its documented switch for a windowless build.
set(SDL_UNIX_CONSOLE_BUILD ON CACHE BOOL "" FORCE)
# SDL's internal assertions: IN under the sanitizer and in a Debug build (the
# shim counts one instead of letting SDL show a dialog, and the tests fail on
# a count), OUT of everything that ships.
if(GAMEPADXT_SANITIZE STREQUAL "address" OR CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(SDL_ASSERTIONS "enabled" CACHE STRING "" FORCE)
else()
    set(SDL_ASSERTIONS "disabled" CACHE STRING "" FORCE)
endif()

FetchContent_MakeAvailable(SDL3)

if(NOT TARGET SDL3-static)
    message(FATAL_ERROR "gamepadxt: SDL's CMake made no SDL3-static target")
endif()

# SDL is pinned to a known-good commit, so an upstream warning on a newer
# compiler must never fail this build.
set_target_properties(SDL3-static PROPERTIES COMPILE_WARNING_AS_ERROR OFF)

# ---------------------------------------------------------------------------
# The web build: wasm32-emscripten. A browser loads no library, so for
# OXT-Beyond's web IDE the shim is linked INTO the engine, which keeps a table
# of the libraries compiled into it and finds "c:gamepadxt>gpx_..." there by
# name. What is built is a static archive, gamepadxt.a, holding ONE
# relocatable object: the shim and the members of SDL it uses, linked together
# (emcc -r), plus a table of the symbols the binding names:
#
#     const struct { const char *symbol; void *address; } *
#     gamepadxt_web_exports(void);       /* ends with { NULL, NULL } */
#
# The table is GENERATED from every `binds to "c:gamepadxt>NAME"` of
# src/gamepadxt.lcb, so it cannot drift from the binding, and compiled in ONE
# translation unit with src/gamepad_shim.c (which it includes), so a bind with
# no shim function is a compile error, never a missing symbol found in a
# browser. This is box2dxt's mechanism, unchanged. On the web SDL reads pads
# through the browser's Gamepad API (its emscripten joystick driver).
# ---------------------------------------------------------------------------
if(EMSCRIPTEN)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/gamepadxt.lcb" _gpx_lcb)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${CMAKE_CURRENT_SOURCE_DIR}/src/gamepadxt.lcb")
    string(REGEX MATCHALL "binds to \"c:gamepadxt>[A-Za-z_][A-Za-z0-9_]*" _gpx_binds "${_gpx_lcb}")
    set(_gpx_symbols "")
    foreach(_bind IN LISTS _gpx_binds)
        string(REGEX REPLACE ".*>" "" _symbol "${_bind}")
        list(APPEND _gpx_symbols "${_symbol}")
    endforeach()
    list(REMOVE_DUPLICATES _gpx_symbols)
    list(SORT _gpx_symbols)
    list(LENGTH _gpx_symbols _gpx_count)
    if(_gpx_count EQUAL 0)
        message(FATAL_ERROR "src/gamepadxt.lcb binds no c:gamepadxt> symbol: is the regular expression stale?")
    endif()
    set(_gpx_rows "")
    foreach(_symbol IN LISTS _gpx_symbols)
        string(APPEND _gpx_rows "\t{ \"${_symbol}\", (void *)${_symbol} },\n")
    endforeach()
    set(_gpx_exports_c "${CMAKE_CURRENT_BINARY_DIR}/gamepadxt_web_exports.c")
    file(CONFIGURE OUTPUT "${_gpx_exports_c}" @ONLY CONTENT
"/* GENERATED by CMakeLists.txt from src/gamepadxt.lcb: the shim, and the
 * @_gpx_count@ symbols the binding binds to, for OXT-Beyond's web engine. */
#include \"gamepad_shim.c\"

struct gpx_web_export { const char *symbol; void *address; };

static const struct gpx_web_export k_gpx_web_exports[] = {
@_gpx_rows@\t{ NULL, NULL },
};

LC_API const struct gpx_web_export *gamepadxt_web_exports(void);
LC_API const struct gpx_web_export *gamepadxt_web_exports(void)
{
\treturn k_gpx_web_exports;
}
")
    message(STATUS "gamepadxt web exports: ${_gpx_count} symbols from src/gamepadxt.lcb")

    # -g0 and the prefix maps keep the build folder's path out of the object,
    # so the same source and Emscripten give the same archive anywhere.
    add_library(gamepadxt_web_objects OBJECT "${_gpx_exports_c}")
    target_include_directories(gamepadxt_web_objects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(gamepadxt_web_objects PRIVATE SDL3::Headers)
    set_target_properties(gamepadxt_web_objects PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
    target_compile_options(gamepadxt_web_objects PRIVATE
        -Os -g0 -Wall -Wextra -Werror=implicit-function-declaration
        "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=gamepadxt"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")
    target_compile_options(SDL3-static PRIVATE -g0
        "-ffile-prefix-map=${sdl3_SOURCE_DIR}=SDL"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")

    set(_gpx_web_object "${CMAKE_CURRENT_BINARY_DIR}/gamepadxt-web.o")
    set(_gpx_web_archive "${CMAKE_CURRENT_BINARY_DIR}/gamepadxt.a")
    add_custom_command(
        OUTPUT "${_gpx_web_archive}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${_gpx_web_object}" "${_gpx_web_archive}"
        COMMAND ${CMAKE_C_COMPILER} -r -o "${_gpx_web_object}"
                "$<TARGET_OBJECTS:gamepadxt_web_objects>" "$<TARGET_FILE:SDL3-static>"
        COMMAND ${CMAKE_AR} rcsD "${_gpx_web_archive}" "${_gpx_web_object}"
        DEPENDS gamepadxt_web_objects SDL3-static "$<TARGET_OBJECTS:gamepadxt_web_objects>"
        COMMAND_EXPAND_LISTS
        COMMENT "Linking gamepadxt.a for the web (shim + SDL, one object)"
        VERBATIM)
    add_custom_target(gamepadxt_web ALL DEPENDS "${_gpx_web_archive}")

    # The web tests: linked against the ARCHIVE and run by node (ctest), so
    # what is tested is the file that would ship. node has no Gamepad API, so
    # what runs there is the shim, SDL's gamepad layer and its virtual pads;
    # SDL's browser driver is compiled and linked, not exercised.
    if(GAMEPADXT_BUILD_TESTS)
        enable_testing()
        find_program(GAMEPADXT_NODE node REQUIRED)
        foreach(_gpx_test smoke fuzz)
            add_executable(gamepadxt_${_gpx_test} tests/${_gpx_test}_test.c)
            add_dependencies(gamepadxt_${_gpx_test} gamepadxt_web)
            set_target_properties(gamepadxt_${_gpx_test} PROPERTIES SUFFIX ".js"
                                  C_STANDARD 11 C_STANDARD_REQUIRED ON)
            target_compile_definitions(gamepadxt_${_gpx_test} PRIVATE
                "GPX_EXPECT_SDL=\"SDL ${GAMEPADXT_SDL_VERSION}\"")
            target_link_libraries(gamepadxt_${_gpx_test} PRIVATE "${_gpx_web_archive}")
            target_link_options(gamepadxt_${_gpx_test} PRIVATE
                -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node -sNODERAWFS=1)
            add_test(NAME ${_gpx_test} COMMAND "${GAMEPADXT_NODE}" "$<TARGET_FILE:gamepadxt_${_gpx_test}>")
        endforeach()
    endif()

    if(GAMEPADXT_PLACE_IN_SRC)
        set(_gpx_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/wasm32-emscripten")
        add_custom_command(TARGET gamepadxt_web POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_gpx_bundle_dir}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_gpx_web_archive}" "${_gpx_bundle_dir}/gamepadxt.a"
            COMMENT "Bundling gamepadxt.a -> src/code/wasm32-emscripten/"
            VERBATIM)
    endif()
    return()
endif()

# ---------------------------------------------------------------------------
# The shim + SDL, linked into a single shared library under its BARE name:
# gamepadxt.so (Linux), gamepadxt.dylib (macOS), gamepadxt.dll (Windows). The
# bare name is the one the tree holds on every platform and, on Linux, the
# soname the engine's dlopen asks for. The LCB bind string "c:gamepadxt>..."
# resolves to it. SDL's static target carries what it needs from the system
# (pthread, dl and m on Linux; IOKit, GameController, CoreHaptics and friends
# on macOS; setupapi, winmm and friends on Windows), so linking it PRIVATE
# brings those along.
# ---------------------------------------------------------------------------
add_library(gamepadxt SHARED src/gamepad_shim.c)
target_link_libraries(gamepadxt PRIVATE SDL3::SDL3-static)

set_target_properties(gamepadxt PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_VISIBILITY_PRESET hidden      # export only the LC_API shim symbols
    PREFIX ""
    OUTPUT_NAME "gamepadxt"
)

# Keep the shim warning-clean (these flags apply only to gamepad_shim.c).
if(MSVC)
    target_compile_options(gamepadxt PRIVATE /W3)
    target_compile_definitions(gamepadxt PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(gamepadxt PRIVATE -Wall -Wextra)
endif()

# Export gpx_* and nothing else. A statically linked dependency inherits the
# library's public visibility unless the link says otherwise (enetxt's release
# run 10 leaked a vendored library's symbols, 2026-08-26), and a leaked SDL_*
# would interpose on any other copy of SDL in the process. src/gamepadxt.map
# is the one source for GNU ld and, by the pattern below, for ld64. On Windows
# only __declspec(dllexport) is exported, and a static SDL declares none.
set(_gpx_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/gamepadxt.map")
if(APPLE)
    set(_gpx_exported "${CMAKE_CURRENT_BINARY_DIR}/gamepadxt.exported_symbols")
    file(WRITE "${_gpx_exported}" "_gpx_*\n")
    target_link_options(gamepadxt PRIVATE "-Wl,-exported_symbols_list,${_gpx_exported}")
elseif(UNIX)
    include(CheckLinkerFlag)
    check_linker_flag(C "-Wl,--version-script=${_gpx_version_script}" GPX_HAVE_VERSION_SCRIPT)
    if(GPX_HAVE_VERSION_SCRIPT)
        target_link_options(gamepadxt PRIVATE "-Wl,--version-script=${_gpx_version_script}")
        set_target_properties(gamepadxt PROPERTIES LINK_DEPENDS "${_gpx_version_script}")
    endif()
endif()

# ---------------------------------------------------------------------------
# The runtime tests. Both are clients of the built library, as the engine's
# FFI is, and both drive it through SDL's VIRTUAL pads, so they run with no
# controller attached, on every platform CI has.
#   smoke: every export, by name, with its results checked;
#   fuzz:  every export, any argument, any order (seeds 1 to 3 by default).
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGAMEPADXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --output-on-failure
# ---------------------------------------------------------------------------
if(GAMEPADXT_BUILD_TESTS)
    enable_testing()
    foreach(_gpx_test smoke fuzz)
        add_executable(gamepadxt_${_gpx_test} tests/${_gpx_test}_test.c)
        set_target_properties(gamepadxt_${_gpx_test} PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
        target_compile_definitions(gamepadxt_${_gpx_test} PRIVATE
            "GPX_EXPECT_SDL=\"SDL ${GAMEPADXT_SDL_VERSION}\"")
        target_link_libraries(gamepadxt_${_gpx_test} PRIVATE gamepadxt)
        if(MSVC)
            target_compile_definitions(gamepadxt_${_gpx_test} PRIVATE _CRT_SECURE_NO_WARNINGS)
        else()
            target_link_libraries(gamepadxt_${_gpx_test} PRIVATE m)
        endif()
        add_test(NAME ${_gpx_test} COMMAND gamepadxt_${_gpx_test})
    endforeach()
endif()
